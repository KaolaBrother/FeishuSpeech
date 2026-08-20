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
    let factoryTimeoutNanoseconds: UInt64
    let packetTimeoutNanoseconds: UInt64
    let finishTimeoutNanoseconds: UInt64
    let postReleaseDrainTimeoutNanoseconds: UInt64
    let urlSessionFactorySliceNanoseconds: UInt64
    let directFactorySliceNanoseconds: UInt64
    let urlSessionPacketSliceNanoseconds: UInt64
    let directPacketSliceNanoseconds: UInt64
    let urlSessionFinishSliceNanoseconds: UInt64
    let directFinishSliceNanoseconds: UInt64
    let sliceSlackNanoseconds: UInt64

    var operationTimeoutNanoseconds: UInt64 {
        packetTimeoutNanoseconds
    }

    init(
        factoryTimeoutNanoseconds: UInt64 = 18_000_000_000,
        packetTimeoutNanoseconds: UInt64 = 30_000_000_000,
        finishTimeoutNanoseconds: UInt64 = 45_000_000_000,
        postReleaseDrainTimeoutNanoseconds: UInt64 = 60_000_000_000,
        urlSessionFactorySliceNanoseconds: UInt64 = 8_000_000_000,
        directFactorySliceNanoseconds: UInt64 = 7_000_000_000,
        urlSessionPacketSliceNanoseconds: UInt64 = 14_000_000_000,
        directPacketSliceNanoseconds: UInt64 = 14_000_000_000,
        urlSessionFinishSliceNanoseconds: UInt64 = 15_000_000_000,
        directFinishSliceNanoseconds: UInt64 = 15_000_000_000,
        sliceSlackNanoseconds: UInt64 = 1_000_000_000
    ) {
        precondition(factoryTimeoutNanoseconds > 0)
        precondition(packetTimeoutNanoseconds > 0)
        precondition(finishTimeoutNanoseconds > 0)
        precondition(postReleaseDrainTimeoutNanoseconds > 0)
        precondition(sliceSlackNanoseconds >= 500_000_000 || sliceSlackNanoseconds == 1)
        precondition(
            urlSessionFactorySliceNanoseconds &+ directFactorySliceNanoseconds &+ sliceSlackNanoseconds
                < factoryTimeoutNanoseconds
        )
        precondition(
            urlSessionPacketSliceNanoseconds &+ directPacketSliceNanoseconds &+ sliceSlackNanoseconds
                < packetTimeoutNanoseconds
        )
        precondition(
            urlSessionFinishSliceNanoseconds &+ directFinishSliceNanoseconds &+ sliceSlackNanoseconds
                < finishTimeoutNanoseconds
        )
        self.factoryTimeoutNanoseconds = factoryTimeoutNanoseconds
        self.packetTimeoutNanoseconds = packetTimeoutNanoseconds
        self.finishTimeoutNanoseconds = finishTimeoutNanoseconds
        self.postReleaseDrainTimeoutNanoseconds = postReleaseDrainTimeoutNanoseconds
        self.urlSessionFactorySliceNanoseconds = urlSessionFactorySliceNanoseconds
        self.directFactorySliceNanoseconds = directFactorySliceNanoseconds
        self.urlSessionPacketSliceNanoseconds = urlSessionPacketSliceNanoseconds
        self.directPacketSliceNanoseconds = directPacketSliceNanoseconds
        self.urlSessionFinishSliceNanoseconds = urlSessionFinishSliceNanoseconds
        self.directFinishSliceNanoseconds = directFinishSliceNanoseconds
        self.sliceSlackNanoseconds = sliceSlackNanoseconds
    }

    init(
        operationTimeoutNanoseconds: UInt64,
        postReleaseDrainTimeoutNanoseconds: UInt64 = 60_000_000_000
    ) {
        let outer = operationTimeoutNanoseconds
        self.init(
            factoryTimeoutNanoseconds: outer,
            packetTimeoutNanoseconds: outer,
            finishTimeoutNanoseconds: outer,
            postReleaseDrainTimeoutNanoseconds: postReleaseDrainTimeoutNanoseconds,
            urlSessionFactorySliceNanoseconds: 1,
            directFactorySliceNanoseconds: 1,
            urlSessionPacketSliceNanoseconds: 1,
            directPacketSliceNanoseconds: 1,
            urlSessionFinishSliceNanoseconds: 1,
            directFinishSliceNanoseconds: 1,
            sliceSlackNanoseconds: 1
        )
    }

    func operationTimeout(remainingDrainNanoseconds: UInt64?) -> UInt64 {
        operationTimeout(for: "packet", remainingDrainNanoseconds: remainingDrainNanoseconds)
    }

    func operationTimeout(
        for operation: String,
        remainingDrainNanoseconds: UInt64?
    ) -> UInt64 {
        let outer: UInt64
        switch operation {
        case "factory":
            outer = factoryTimeoutNanoseconds
        case "finish":
            outer = finishTimeoutNanoseconds
        default:
            outer = packetTimeoutNanoseconds
        }
        guard let remainingDrainNanoseconds else {
            return outer
        }
        return min(outer, remainingDrainNanoseconds)
    }

    func urlSessionSliceNanoseconds(for phase: AttemptHTTPPhase) -> UInt64 {
        switch phase {
        case .factoryToken:
            return urlSessionFactorySliceNanoseconds
        case .packet:
            return urlSessionPacketSliceNanoseconds
        case .finish:
            return urlSessionFinishSliceNanoseconds
        case .abort:
            return 1_000_000_000
        }
    }

    func directSliceNanoseconds(for phase: AttemptHTTPPhase) -> UInt64 {
        switch phase {
        case .factoryToken:
            return directFactorySliceNanoseconds
        case .packet:
            return directPacketSliceNanoseconds
        case .finish:
            return directFinishSliceNanoseconds
        case .abort:
            return 1_000_000_000
        }
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

nonisolated enum AttemptHTTPPhase: Equatable, Sendable {
    case factoryToken
    case packet
    case finish
    case abort
}

nonisolated struct AttemptHTTPRequest: Sendable {
    let request: URLRequest
    let phase: AttemptHTTPPhase
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
