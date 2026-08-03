import Foundation
import os.log

private nonisolated let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "StreamingSpeechModels"
)

nonisolated struct StreamingSessionIdentity: Equatable, Hashable, Sendable {
    let generation: UInt64
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
    case httpStatus
    case backend
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
