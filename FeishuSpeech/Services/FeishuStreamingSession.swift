import Foundation
import os.log

private nonisolated let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "StreamingSession"
)

private nonisolated let streamingSpeechURL = URL(
    string: "https://open.feishu.cn/open-apis/speech_to_text/v1/speech/stream_recognize"
)!
private nonisolated let knownInvalidTokenCodes: Set<Int> = [99_991_663]
private nonisolated let abortTimeoutNanoseconds: UInt64 = 1_000_000_000
private nonisolated let maximumErrorBodyByteCount = 64 * 1_024

private nonisolated final class DeadlineSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Bool?
    private var continuation: CheckedContinuation<Bool, Never>?

    func wait() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func resolve(_ result: Bool) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

private nonisolated struct StreamingSpeechRequest: Encodable, Sendable {
    let speech: StreamingSpeechAudio
    let config: StreamingSpeechConfiguration
}

private nonisolated struct StreamingSpeechAudio: Encodable, Sendable {
    let speech: String
}

private nonisolated struct StreamingSpeechConfiguration: Encodable, Sendable {
    let streamID: String
    let sequenceID: Int
    let action: Int
    let format = "pcm"
    let engineType = "16k_auto"

    enum CodingKeys: String, CodingKey {
        case streamID = "stream_id"
        case sequenceID = "sequence_id"
        case action
        case format
        case engineType = "engine_type"
    }
}

private nonisolated struct StreamingSpeechResponse: Decodable, Sendable {
    let code: Int
    let data: StreamingRecognitionData?
}

private nonisolated struct StreamingRecognitionData: Decodable, Sendable {
    let streamID: String?
    let sequenceID: Int?
    let recognitionText: String?

    enum CodingKeys: String, CodingKey {
        case streamID = "stream_id"
        case sequenceID = "sequence_id"
        case recognitionText = "recognition_text"
    }
}

actor FeishuStreamingSession: SpeechStreamingSession {
    typealias RefreshToken = @Sendable () async throws -> String
    typealias RequestSender = @Sendable (URLRequest) async throws -> DirectHTTPResponse

    private enum TerminalState {
        case none
        case completed(StreamingRecognitionEvent)
        case failed(StreamFailure)
    }

    private let streamID: String
    private let refreshToken: RefreshToken
    private let requestSender: RequestSender
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var token: String
    private var nextSequenceID = 0
    private var didAcceptFirstPacket = false
    private var didRefreshFirstPacket = false
    private var terminalState = TerminalState.none

    private var requestInFlight = false
    private var requestWaiters: [CheckedContinuation<Bool, Never>] = []
    private var activeRequestTask: Task<DirectHTTPResponse, Error>?
    private var activeRequestAction: Int?
    private var requestGateReleaseSignal: DeadlineSignal?
    private var didEmitFinishRequest = false

    init(
        streamID: String? = nil,
        initialToken: String,
        refreshToken: @escaping RefreshToken,
        requestSender: @escaping RequestSender
    ) {
        let resolvedStreamID = streamID ?? Self.makeStreamID()
        precondition(Self.isValidStreamID(resolvedStreamID), "Invalid streaming session identifier")

        self.streamID = resolvedStreamID
        token = initialToken
        self.refreshToken = refreshToken
        self.requestSender = requestSender
    }

    func sendAudioPacket(_ audio: Data) async throws -> StreamingRecognitionEvent {
        guard !audio.isEmpty else { throw StreamFailure.invalidRequest }
        try ensureActive()

        guard await acquireRequestGate() else {
            try ensureActive()
            throw StreamFailure.cancelled
        }
        defer { releaseRequestGate() }

        try ensureActive()
        let action = didAcceptFirstPacket ? 0 : 1
        let sequenceID = nextSequenceID

        do {
            let text = try await sendWithInitialTokenRefreshIfNeeded(
                audio: audio,
                action: action,
                sequenceID: sequenceID
            )
            try ensureActive()
            didAcceptFirstPacket = true
            nextSequenceID += 1
            return .partial(text)
        } catch let failure as StreamFailure {
            throw recordFailureIfActive(failure)
        } catch {
            let failure = Self.sanitizedFailure(for: error)
            throw recordFailureIfActive(failure)
        }
    }

    func finish() async throws -> StreamingRecognitionEvent {
        switch terminalState {
        case .completed(let event):
            return event
        case .failed(let failure):
            throw failure
        case .none:
            break
        }

        guard await acquireRequestGate() else {
            return try terminalResult()
        }
        defer { releaseRequestGate() }

        switch terminalState {
        case .completed(let event):
            return event
        case .failed(let failure):
            throw failure
        case .none:
            break
        }

        guard didAcceptFirstPacket else {
            let event = StreamingRecognitionEvent.cancelled
            terminalState = .completed(event)
            return event
        }

        do {
            let text = try await send(
                audio: Data(),
                action: 2,
                sequenceID: nextSequenceID,
                bearerToken: token
            )
            try ensureActive()
            nextSequenceID += 1
            let event = StreamingRecognitionEvent.final(text)
            terminalState = .completed(event)
            return event
        } catch let failure as StreamFailure {
            throw recordFailureIfActive(failure)
        } catch {
            let failure = Self.sanitizedFailure(for: error)
            throw recordFailureIfActive(failure)
        }
    }

    func cancel() async {
        guard case .none = terminalState else { return }

        let deadline = DispatchTime.now().uptimeNanoseconds &+ abortTimeoutNanoseconds
        let inFlightAction = activeRequestAction
        terminalState = .completed(.cancelled)
        rejectRequestWaiters()

        let gateReleaseSignal: DeadlineSignal?
        if didAcceptFirstPacket, requestInFlight, inFlightAction == 0, !didEmitFinishRequest {
            let signal = DeadlineSignal()
            requestGateReleaseSignal = signal
            gateReleaseSignal = signal
        } else {
            gateReleaseSignal = nil
        }
        activeRequestTask?.cancel()

        guard didAcceptFirstPacket, !didEmitFinishRequest else { return }

        if let gateReleaseSignal {
            guard await wait(for: gateReleaseSignal, until: deadline) else {
                if requestGateReleaseSignal === gateReleaseSignal {
                    requestGateReleaseSignal = nil
                }
                return
            }
        } else if requestInFlight {
            return
        }

        guard !requestInFlight else { return }
        await attemptBestEffortAbort(until: deadline)
    }

    private func attemptBestEffortAbort(until deadline: UInt64) async {
        guard !didEmitFinishRequest else { return }

        requestInFlight = true
        defer { releaseRequestGate() }

        let sequenceID = nextSequenceID
        guard let request = try? makeRequest(
            audio: Data(),
            action: 3,
            sequenceID: sequenceID,
            bearerToken: token
        ) else { return }

        let signal = DeadlineSignal()
        let requestSender = self.requestSender
        let requestTask = Task<DirectHTTPResponse, Error> {
            do {
                let response = try await requestSender(request)
                signal.resolve(true)
                return response
            } catch {
                signal.resolve(true)
                throw error
            }
        }
        activeRequestTask = requestTask
        activeRequestAction = 3

        let completedBeforeDeadline = await wait(for: signal, until: deadline)

        if completedBeforeDeadline {
            if case .success = await requestTask.result {
                nextSequenceID += 1
            }
        } else {
            requestTask.cancel()
        }
        activeRequestTask = nil
        activeRequestAction = nil
    }

    private func sendWithInitialTokenRefreshIfNeeded(
        audio: Data,
        action: Int,
        sequenceID: Int
    ) async throws -> String {
        do {
            return try await send(
                audio: audio,
                action: action,
                sequenceID: sequenceID,
                bearerToken: token
            )
        } catch StreamFailure.authentication
            where action == 1 && !didAcceptFirstPacket && !didRefreshFirstPacket {
            try ensureActive()
            didRefreshFirstPacket = true
            do {
                token = try await refreshToken()
            } catch {
                throw StreamFailure.authentication
            }
            try ensureActive()
            return try await send(
                audio: audio,
                action: action,
                sequenceID: sequenceID,
                bearerToken: token
            )
        }
    }

    private func send(
        audio: Data,
        action: Int,
        sequenceID: Int,
        bearerToken: String
    ) async throws -> String {
        let request = try makeRequest(
            audio: audio,
            action: action,
            sequenceID: sequenceID,
            bearerToken: bearerToken
        )

        let requestTask = Task<DirectHTTPResponse, Error> {
            try await requestSender(request)
        }
        if action == 2 {
            didEmitFinishRequest = true
        }
        activeRequestTask = requestTask
        activeRequestAction = action
        defer {
            activeRequestTask = nil
            activeRequestAction = nil
        }

        let response: DirectHTTPResponse
        do {
            response = try await requestTask.value
        } catch {
            throw Self.sanitizedFailure(for: error)
        }

        guard response.statusCode == 200 else {
            if response.statusCode == 400 || response.statusCode == 401,
               response.body.count <= maximumErrorBodyByteCount,
               let errorResponse = try? decoder.decode(
                   StreamingSpeechResponse.self,
                   from: response.body
               ),
               knownInvalidTokenCodes.contains(errorResponse.code) {
                throw StreamFailure.authentication
            }
            throw StreamFailure.httpStatus
        }

        let decoded: StreamingSpeechResponse
        do {
            decoded = try decoder.decode(StreamingSpeechResponse.self, from: response.body)
        } catch {
            throw StreamFailure.malformedResponse
        }

        guard decoded.code == 0 else {
            if knownInvalidTokenCodes.contains(decoded.code) {
                throw StreamFailure.authentication
            }
            throw StreamFailure.backend
        }
        guard let data = decoded.data else {
            throw StreamFailure.malformedResponse
        }
        if let responseStreamID = data.streamID, responseStreamID != streamID {
            throw StreamFailure.responseIdentityMismatch
        }
        if let responseSequenceID = data.sequenceID, responseSequenceID != sequenceID {
            throw StreamFailure.responseIdentityMismatch
        }
        return data.recognitionText ?? ""
    }

    private func makeRequest(
        audio: Data,
        action: Int,
        sequenceID: Int,
        bearerToken: String
    ) throws -> URLRequest {
        let body = StreamingSpeechRequest(
            speech: StreamingSpeechAudio(speech: audio.base64EncodedString()),
            config: StreamingSpeechConfiguration(
                streamID: streamID,
                sequenceID: sequenceID,
                action: action
            )
        )

        var request = URLRequest(url: streamingSpeechURL)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw StreamFailure.invalidRequest
        }
        return request
    }

    private func ensureActive() throws {
        switch terminalState {
        case .none:
            return
        case .completed:
            throw StreamFailure.cancelled
        case .failed(let failure):
            throw failure
        }
    }

    private func terminalResult() throws -> StreamingRecognitionEvent {
        switch terminalState {
        case .completed(let event):
            return event
        case .failed(let failure):
            throw failure
        case .none:
            throw StreamFailure.cancelled
        }
    }

    private func recordFailureIfActive(_ failure: StreamFailure) -> StreamFailure {
        switch terminalState {
        case .none:
            terminalState = .failed(failure)
            return failure
        case .failed(let existingFailure):
            return existingFailure
        case .completed:
            return .cancelled
        }
    }

    private func acquireRequestGate() async -> Bool {
        if !requestInFlight {
            requestInFlight = true
            return true
        }
        return await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    private func releaseRequestGate() {
        requestGateReleaseSignal?.resolve(true)
        requestGateReleaseSignal = nil

        guard !requestWaiters.isEmpty else {
            requestInFlight = false
            return
        }
        requestWaiters.removeFirst().resume(returning: true)
    }

    private func rejectRequestWaiters() {
        let waiters = requestWaiters
        requestWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: false)
        }
    }

    private func wait(for signal: DeadlineSignal, until deadline: UInt64) async -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else { return false }

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: deadline - now)
            guard !Task.isCancelled else { return }
            signal.resolve(false)
        }
        let completedBeforeDeadline = await signal.wait()
        timeoutTask.cancel()
        return completedBeforeDeadline
    }

    private nonisolated static func isValidStreamID(_ candidate: String) -> Bool {
        candidate.utf8.count == 16 && candidate.utf8.allSatisfy {
            ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 95
        }
    }

    private nonisolated static func makeStreamID() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789_")
        return String((0..<16).map { _ in alphabet.randomElement()! })
    }

    private nonisolated static func sanitizedFailure(for error: Error) -> StreamFailure {
        if let failure = error as? StreamFailure {
            return failure
        }
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout
            case .cancelled:
                return .cancelled
            default:
                return .network
            }
        }
        return .network
    }
}
