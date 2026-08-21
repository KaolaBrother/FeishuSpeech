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
    private var socket: BoundTLSSocket?
    private var didBecomeReady = false
    private var leftover = Data()
    private var receiveBuffer = Data()
    private var inFlight: InFlight?
    private var isDead = false
    private var isReceiving = false

    static func physicalInterface(from path: NWPath) -> NWInterface? {
        path.availableInterfaces.first { interface in
            interface.type == .wifi || interface.type == .wiredEthernet
        }
    }

    static func makeParameters(requiredInterface: NWInterface? = nil) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(
            tlsOptions.securityProtocolOptions,
            feishuDirectHost
        )
        let parameters = NWParameters(tls: tlsOptions)
        parameters.preferNoProxies = true
        parameters.prohibitedInterfaceTypes = [.other]
        if let requiredInterface {
            parameters.requiredInterface = requiredInterface
        }
        return parameters
    }

    static func snapshotPhysicalInterface(
        timeoutNanoseconds: UInt64 = 300_000_000
    ) -> NWInterface? {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.feishuspeech.direct-path")
        let lock = NSLock()
        var interface: NWInterface?
        let semaphore = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { path in
            lock.lock()
            interface = physicalInterface(from: path)
            lock.unlock()
            semaphore.signal()
        }
        monitor.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + .nanoseconds(Int(timeoutNanoseconds)))
        monitor.cancel()
        lock.lock()
        defer { lock.unlock() }
        return interface
    }

    private static func pathKindName(for type: NWInterface.InterfaceType?) -> String {
        switch type {
        case .wifi:
            return "wifi"
        case .wiredEthernet:
            return "wired"
        case .other:
            return "other"
        case .none:
            return "none"
        default:
            return "unknown"
        }
    }

    private static func pathKindName(for path: NWPath?) -> String {
        guard let path else { return "none" }
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.wiredEthernet) { return "wired" }
        if path.usesInterfaceType(.other) { return "other" }
        return "unknown"
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
        let socket = socket
        let pending = inFlight
        inFlight = nil
        lock.unlock()
        socket?.close()
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
            if didBecomeReady, socket != nil {
                lock.unlock()
                sendHTTP(request)
                return
            }
            let needsConnect = socket == nil
            lock.unlock()
            let physical = needsConnect ? Self.snapshotPhysicalInterface() : nil
            lock.lock()
            if isDead {
                let pending = inFlight
                inFlight = nil
                lock.unlock()
                pending?.continuation.resume(throwing: CancellationError())
                return
            }
            if socket == nil {
                let interface = physical
                lock.unlock()
                guard let interface else {
                    failInFlight(FeishuAPIService.APIError.connectionFailed)
                    return
                }
                startConnection(requiredInterface: interface)
                return
            }
            lock.unlock()
        }
    }

    private func startConnection(requiredInterface: NWInterface) {
        let kind = Self.pathKindName(for: requiredInterface.type)
        logger.notice("transport=direct connecting path=\(kind, privacy: .public)")
        let interfaceName = requiredInterface.name
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let socket = try BoundTLSSocket.connect(
                    host: feishuDirectHost,
                    interfaceName: interfaceName
                )
                self.lock.lock()
                if self.isDead {
                    self.lock.unlock()
                    socket.close()
                    return
                }
                let onTunnel = socket.localIPv4?.hasPrefix("198.18.") == true
                if onTunnel {
                    self.lock.unlock()
                    socket.close()
                    logger.notice("transport=direct rejected tunnel local")
                    self.failAttempt(FeishuAPIService.APIError.connectionFailed)
                    return
                }
                self.socket = socket
                self.didBecomeReady = true
                let pending = self.inFlight
                self.lock.unlock()
                logger.notice("transport=direct path=\(kind, privacy: .public) tunnel=false")
                if let pending {
                    self.sendHTTP(pending.request)
                }
            } catch {
                self.failAttempt(mapTransportError(error))
            }
        }
    }

    private func sendHTTP(_ request: URLRequest) {
        guard let encoded = Self.encode(request) else {
            failInFlight(FeishuAPIService.APIError.invalidResponse)
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let socket = self.socket
            self.lock.unlock()
            guard let socket else {
                self.failAttempt(FeishuAPIService.APIError.connectionFailed)
                return
            }
            do {
                try socket.write(encoded)
                self.receiveIfNeeded()
            } catch {
                self.failAttempt(mapTransportError(error))
            }
        }
    }

    private func receiveIfNeeded() {
        lock.lock()
        if isReceiving {
            lock.unlock()
            return
        }
        isReceiving = true
        lock.unlock()
        receiveLoop()
    }

    private func receiveLoop() {
        lock.lock()
        let socket = socket
        lock.unlock()
        guard let socket else { return }
        do {
            let data = try socket.read(maxLength: 64 * 1_024)
            if data.isEmpty {
                failAttempt(FeishuAPIService.APIError.connectionFailed)
                return
            }
            lock.lock()
            receiveBuffer.append(data)
            let snapshot = receiveBuffer
            lock.unlock()
            if let parsed = try Self.parseResponseKeepingRemainder(snapshot) {
                lock.lock()
                receiveBuffer = parsed.remainder
                leftover = parsed.remainder
                let pending = inFlight
                inFlight = nil
                isReceiving = false
                lock.unlock()
                pending?.continuation.resume(returning: parsed.response)
                return
            }
            receiveLoop()
        } catch {
            failAttempt(mapTransportError(error))
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
        let socket = socket
        self.socket = nil
        lock.unlock()
        socket?.close()
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
