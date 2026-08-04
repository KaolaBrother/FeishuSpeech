import Foundation
import os.log

private nonisolated let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "StreamingSpeechModels"
)

nonisolated struct StreamingSessionIdentity: Equatable, Hashable, Sendable {
    let generation: UInt64
}

nonisolated struct StreamingRetryPolicy: Sendable {
    private let jitterFactor: @Sendable () -> Double

    init(jitterFactor: @escaping @Sendable () -> Double = {
        Double.random(in: 0.8...1.2)
    }) {
        self.jitterFactor = jitterFactor
    }

    func delayNanoseconds(forRetryOrdinal ordinal: Int) -> UInt64 {
        let boundedOrdinal = min(max(ordinal, 1), 5)
        let baseDelay = min(
            UInt64(250_000_000) << UInt64(boundedOrdinal - 1),
            4_000_000_000
        )
        let boundedJitter = min(max(jitterFactor(), 0.8), 1.2)
        return min(UInt64(Double(baseDelay) * boundedJitter), 4_000_000_000)
    }
}

nonisolated struct StreamingDrainPolicy: Equatable, Sendable {
    let operationTimeoutNanoseconds: UInt64
    let postReleaseDrainTimeoutNanoseconds: UInt64

    init(
        operationTimeoutNanoseconds: UInt64 = 30_000_000_000,
        postReleaseDrainTimeoutNanoseconds: UInt64 = 60_000_000_000
    ) {
        precondition(operationTimeoutNanoseconds > 0)
        precondition(postReleaseDrainTimeoutNanoseconds > 0)
        self.operationTimeoutNanoseconds = operationTimeoutNanoseconds
        self.postReleaseDrainTimeoutNanoseconds = postReleaseDrainTimeoutNanoseconds
    }

    func operationTimeout(remainingDrainNanoseconds: UInt64?) -> UInt64 {
        guard let remainingDrainNanoseconds else {
            return operationTimeoutNanoseconds
        }
        return min(operationTimeoutNanoseconds, remainingDrainNanoseconds)
    }

    func retryDelay(
        _ requestedNanoseconds: UInt64,
        remainingDrainNanoseconds: UInt64?
    ) -> UInt64 {
        guard let remainingDrainNanoseconds else {
            return requestedNanoseconds
        }
        return min(requestedNanoseconds, remainingDrainNanoseconds)
    }
}

nonisolated struct AudioIngressConfiguration: Equatable, Sendable {
    let packetByteCount: Int
    let minimumTailByteCount: Int
    let maximumBufferedByteCount: Int

    var bufferedElementCapacity: Int {
        maximumBufferedByteCount / packetByteCount
    }

    init(
        packetByteCount: Int,
        minimumTailByteCount: Int,
        maximumBufferedByteCount: Int
    ) {
        precondition(packetByteCount > 0)
        precondition(minimumTailByteCount > 0 && minimumTailByteCount <= packetByteCount)
        precondition(maximumBufferedByteCount >= packetByteCount)
        precondition(maximumBufferedByteCount.isMultiple(of: packetByteCount))

        self.packetByteCount = packetByteCount
        self.minimumTailByteCount = minimumTailByteCount
        self.maximumBufferedByteCount = maximumBufferedByteCount
    }
}

nonisolated enum AudioIngressError: Error, Equatable, Sendable {
    case ingressOverflow
    case captureFailed
    case cancelled
}

nonisolated enum StreamFailure: LocalizedError, Equatable, Sendable {
    case invalidRequest
    case authentication
    case network
    case timeout
    case httpStatus(Int)
    case backend(code: Int)
    case malformedResponse
    case responseIdentityMismatch
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid streaming request"
        case .authentication:
            return "Streaming authentication failed"
        case .network:
            return "Streaming network request failed"
        case .timeout:
            return "Streaming request timed out"
        case .httpStatus:
            return "Streaming server request failed"
        case .backend:
            return "Streaming recognition failed"
        case .malformedResponse:
            return "Invalid streaming response"
        case .responseIdentityMismatch:
            return "Streaming response identity mismatch"
        case .cancelled:
            return "Streaming request was cancelled"
        }
    }
}

nonisolated enum StreamingRecognitionEvent: Equatable, Sendable {
    case partial(String)
    case final(String)
    case cancelled
    case failed(StreamFailure)
}
