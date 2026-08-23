import Foundation

import os.log

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "TranscriptionReviewState"
)

nonisolated enum TranscriptionReviewState: Equatable, Sendable {
    case idle
    case streaming(preview: String)
    case sealing(preview: String)
    case editable(
        draft: String,
        isPossiblyIncomplete: Bool,
        feedback: ReviewDraftFeedback? = nil
    )
    case editablePending(
        draft: String,
        isPossiblyIncomplete: Bool,
        readiness: ReviewEditableReadinessState,
        feedback: ReviewDraftFeedback? = nil
    )
    case confirming(
        draft: String = "",
        isPossiblyIncomplete: Bool = false
    )
}

nonisolated enum ReviewReadOnlyPhase: Equatable, Sendable {
    case streaming
    case sealing
}

nonisolated enum ReviewEditableTransitionResult: Equatable, Sendable {
    case ready
    case pending(ReviewEditableReadinessFailure)
}

nonisolated enum ReviewEditableReadinessPredicate: String, Equatable, Sendable {
    case activationRequest
    case applicationActive
    case panelKey
    case editorMaterialized
    case editorAttachedToPanel
    case editorFirstResponder
}

nonisolated enum ReviewEditableReadinessFailure: Equatable, Sendable {
    case activationRejected
    case timedOut(lastUnmet: ReviewEditableReadinessPredicate)
    case cancelled(lastUnmet: ReviewEditableReadinessPredicate?)
    case surfaceInvalidated
}

extension ReviewEditableReadinessFailure {
    var telemetryResult: String {
        switch self {
        case .activationRejected:
            return "activationRejected"
        case .timedOut:
            return "timedOut"
        case .cancelled:
            return "cancelled"
        case .surfaceInvalidated:
            return "surfaceInvalidated"
        }
    }

    var telemetryPredicate: String? {
        let predicate: ReviewEditableReadinessPredicate?
        switch self {
        case .activationRejected:
            predicate = .activationRequest
        case .timedOut(let lastUnmet):
            predicate = lastUnmet
        case .cancelled(let lastUnmet):
            predicate = lastUnmet
        case .surfaceInvalidated:
            predicate = nil
        }
        return predicate?.rawValue
    }

    var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

nonisolated enum ReviewEditableReadinessState: Equatable, Sendable {
    case preparing(attempt: UInt64)
    case blocked(attempt: UInt64, failure: ReviewEditableReadinessFailure)
}

nonisolated enum ReviewDraftFeedback: Equatable, Sendable {
    case activationFailed
    case destinationChanged
    case securityRejected
    case unsafeText
    case deliveryFailed
    case deliveryUncertain
    case deliveryCancelled
}
