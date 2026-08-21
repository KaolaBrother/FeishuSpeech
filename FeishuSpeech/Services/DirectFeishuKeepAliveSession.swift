import Foundation
import Network
import os.log
import Security

private nonisolated let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "DirectKeepAlive"
)

private nonisolated let feishuDirectHost = "open.feishu.cn"

nonisolated protocol DirectKeepAliveTransport: AnyObject, Sendable {
    func send(_ request: URLRequest, deadlineNanoseconds: UInt64) async throws -> DirectHTTPResponse
    func forceCancel()
}

nonisolated final class DirectFeishuKeepAliveSession: DirectKeepAliveTransport, @unchecked Sendable {
    private struct InFlight {
        let continuation: CheckedContinuation<DirectHTTPResponse, Error>
        let request: URLRequest
    }

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.feishuspeech.direct-keepalive")
    private var connection: NWConnection?
    private var didBecomeReady = false
    private var leftover = Data()
    private var receiveBuffer = Data()
    private var inFlight: InFlight?
    private var isDead = false
    private var isReceiving = false

    static func makeParameters() -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(
            tlsOptions.securityProtocolOptions,
            feishuDirectHost
        )
        let parameters = NWParameters(tls: tlsOptions)
        parameters.preferNoProxies = true
        parameters.prohibitedInterfaceTypes = [.other]
        return parameters
    }

    func send(
        _ request: URLRequest,
        deadlineNanoseconds: UInt64
    ) async throws -> DirectHTTPResponse {
        try await withThrowingTaskGroup(of: DirectHTTPResponse.self) { group in
            group.addTask {
                try await self.perform(request)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: deadlineNanoseconds)
                self.forceCancel()
                throw FeishuAPIService.APIError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func forceCancel() {
        lock.lock()
        isDead = true
        let connection = connection
        let pending = inFlight
        inFlight = nil
        lock.unlock()
        connection?.forceCancel()
        pending?.continuation.resume(throwing: CancellationError())
    }

    private func perform(_ request: URLRequest) async throws -> DirectHTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if isDead || inFlight != nil {
                lock.unlock()
                continuation.resume(throwing: FeishuAPIService.APIError.connectionFailed)
                return
            }
            inFlight = InFlight(continuation: continuation, request: request)
            if didBecomeReady, let connection, connection.state == .ready {
                lock.unlock()
                sendHTTP(request, on: connection)
                return
            }
            if connection == nil {
                startConnectionLocked()
            }
            lock.unlock()
        }
    }

    private func startConnectionLocked() {
        let parameters = Self.makeParameters()
        let connection = NWConnection(
            host: NWEndpoint.Host(feishuDirectHost),
            port: 443,
            using: parameters
        )
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleState(state)
        }
        connection.start(queue: queue)
        logger.info("transport=direct connecting")
    }

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            lock.lock()
            let wasReady = didBecomeReady
            didBecomeReady = true
            let pending = inFlight
            let connection = connection
            lock.unlock()
            if !wasReady {
                logger.info("transport=direct")
            }
            if let pending, let connection {
                sendHTTP(pending.request, on: connection)
            }
        case .waiting(let error):
            lock.lock()
            let ready = didBecomeReady
            lock.unlock()
            if !ready {
                failInFlight(mapTransportError(error))
            } else {
                failAttempt(mapTransportError(error))
            }
        case .failed(let error):
            failAttempt(mapTransportError(error))
        case .cancelled:
            failAttempt(CancellationError())
        default:
            break
        }
    }

    private func sendHTTP(_ request: URLRequest, on connection: NWConnection) {
        guard let encoded = Self.encode(request) else {
            failInFlight(FeishuAPIService.APIError.invalidResponse)
            return
        }
        connection.send(content: encoded, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.failAttempt(mapTransportError(error))
                return
            }
            self?.receiveIfNeeded()
        })
    }

    private func receiveIfNeeded() {
        lock.lock()
        if isReceiving {
            lock.unlock()
            return
        }
        isReceiving = true
        let connection = connection
        lock.unlock()
        guard let connection else { return }
        receiveLoop(on: connection)
    }

    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.lock.lock()
                self.receiveBuffer.append(data)
                let snapshot = self.receiveBuffer
                self.lock.unlock()
                do {
                    if let parsed = try Self.parseResponseKeepingRemainder(snapshot) {
                        self.lock.lock()
                        self.receiveBuffer = parsed.remainder
                        self.leftover = parsed.remainder
                        let pending = self.inFlight
                        self.inFlight = nil
                        self.isReceiving = false
                        self.lock.unlock()
                        pending?.continuation.resume(returning: parsed.response)
                        return
                    }
                } catch {
                    self.failAttempt(mapTransportError(error))
                    return
                }
            }
            if let error {
                self.failAttempt(mapTransportError(error))
                return
            }
            if isComplete {
                self.failAttempt(FeishuAPIService.APIError.connectionFailed)
                return
            }
            self.receiveLoop(on: connection)
        }
    }

    private func failInFlight(_ error: Error) {
        lock.lock()
        let pending = inFlight
        inFlight = nil
        isReceiving = false
        lock.unlock()
        pending?.continuation.resume(throwing: error)
    }

    private func failAttempt(_ error: Error) {
        lock.lock()
        isDead = true
        let pending = inFlight
        inFlight = nil
        isReceiving = false
        let connection = connection
        self.connection = nil
        lock.unlock()
        connection?.forceCancel()
        pending?.continuation.resume(throwing: error)
    }

    private static func encode(_ request: URLRequest) -> Data? {
        guard let url = request.url else { return nil }
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query.map { "?\($0)" } ?? ""
        var headerLines = [
            "Host: \(feishuDirectHost)",
            "Accept: application/json",
            "Connection: keep-alive"
        ]
        if let body = request.httpBody {
            headerLines.append("Content-Length: \(body.count)")
        }
        request.allHTTPHeaderFields?.forEach { key, value in
            if key.caseInsensitiveCompare("Host") == .orderedSame ||
                key.caseInsensitiveCompare("Connection") == .orderedSame {
                return
            }
            headerLines.append("\(key): \(value)")
        }
        var data = Data("POST \(path)\(query) HTTP/1.1\r\n\(headerLines.joined(separator: "\r\n"))\r\n\r\n".utf8)
        if let body = request.httpBody {
            data.append(body)
        }
        return data
    }

    private static func parseResponseKeepingRemainder(
        _ responseData: Data
    ) throws -> (response: DirectHTTPResponse, remainder: Data)? {
        try DirectFeishuHTTPClient.parseCompleteResponseKeepingRemainder(responseData)
    }
}
