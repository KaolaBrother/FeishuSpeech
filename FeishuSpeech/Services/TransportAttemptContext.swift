import Foundation
import os.log

private nonisolated let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "TransportAttempt"
)

private nonisolated final class SliceWinnerGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isSettled = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isSettled else { return false }
        isSettled = true
        return true
    }
}

nonisolated final class TransportAttemptContext: @unchecked Sendable {
    private let policy: StreamingDrainPolicy
    private let lock = NSLock()
    private var session: URLSession
    private var isInvalidated = false

    init(policy: StreamingDrainPolicy, session: URLSession? = nil) {
        self.policy = policy
        if let session {
            self.session = session
        } else {
            let resourceTimeout = Self.resourceTimeout(for: policy)
            self.session = URLSession(
                configuration: Self.makeStreamingSessionConfiguration(
                    resourceTimeout: resourceTimeout
                )
            )
        }
    }

    var capturedSession: URLSession {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    var isInvalidatedForTesting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isInvalidated
    }

    static func makeStreamingSessionConfiguration(
        resourceTimeout: TimeInterval
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.timeoutIntervalForRequest = resourceTimeout
        return configuration
    }

    static func resourceTimeout(for policy: StreamingDrainPolicy) -> TimeInterval {
        let maxSlice = max(
            policy.urlSessionFactorySliceNanoseconds,
            max(
                policy.urlSessionPacketSliceNanoseconds,
                policy.urlSessionFinishSliceNanoseconds
            )
        )
        return TimeInterval(maxSlice) / 1_000_000_000
    }

    func invalidate() {
        lock.lock()
        guard !isInvalidated else {
            lock.unlock()
            return
        }
        isInvalidated = true
        let session = session
        lock.unlock()
        session.invalidateAndCancel()
        logger.info("transport=urlsession invalidated")
    }

    func send(_ attempt: AttemptHTTPRequest) async throws -> DirectHTTPResponse {
        lock.lock()
        if isInvalidated {
            lock.unlock()
            throw CancellationError()
        }
        let session = session
        lock.unlock()

        var request = attempt.request
        let slice = policy.urlSessionSliceNanoseconds(for: attempt.phase)
        request.timeoutInterval = TimeInterval(slice) / 1_000_000_000
        return try await sendURLSessionSlice(
            request,
            session: session,
            sliceNanoseconds: slice
        )
    }

    private func sendURLSessionSlice(
        _ request: URLRequest,
        session: URLSession,
        sliceNanoseconds: UInt64
    ) async throws -> DirectHTTPResponse {
        let gate = SliceWinnerGate()
        let (stream, continuation) = AsyncStream<Result<DirectHTTPResponse, Error>>.makeStream()
        let requestTask = Task {
            do {
                let response = try await Self.performURLSession(session, request: request)
                if gate.claim() {
                    continuation.yield(.success(response))
                    continuation.finish()
                }
            } catch {
                if gate.claim() {
                    continuation.yield(.failure(error))
                    continuation.finish()
                }
            }
        }
        let timerTask = Task {
            do {
                try await Task.sleep(nanoseconds: sliceNanoseconds)
            } catch {
                return
            }
            if gate.claim() {
                continuation.yield(.failure(FeishuAPIService.APIError.timeout))
                continuation.finish()
            }
        }

        var iterator = stream.makeAsyncIterator()
        let winner = await withTaskCancellationHandler {
            await iterator.next()
        } onCancel: {
            requestTask.cancel()
            timerTask.cancel()
        }
        requestTask.cancel()
        timerTask.cancel()

        switch winner {
        case .success(let response):
            return response
        case .failure(let error):
            invalidate()
            throw mapTransportError(error)
        case nil:
            invalidate()
            throw FeishuAPIService.APIError.timeout
        }
    }

    private static func performURLSession(
        _ session: URLSession,
        request: URLRequest
    ) async throws -> DirectHTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw FeishuAPIService.APIError.invalidResponse
            }
            return DirectHTTPResponse(statusCode: httpResponse.statusCode, body: data)
        } catch let error as CancellationError {
            throw error
        } catch {
            throw error
        }
    }
}

nonisolated func mapTransportError(_ error: Error) -> Error {
    if let apiError = error as? FeishuAPIService.APIError {
        return apiError
    }
    if error is CancellationError {
        return error
    }
    if let urlError = error as? URLError {
        switch urlError.code {
        case .timedOut:
            return FeishuAPIService.APIError.timeout
        case .cancelled:
            return CancellationError()
        default:
            return FeishuAPIService.APIError.connectionFailed
        }
    }
    return FeishuAPIService.APIError.networkError("")
}
