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
    case confirming(
        draft: String = "",
        isPossiblyIncomplete: Bool = false
    )
    /// The exact draft is frozen while the one-shot submission admission is
    /// being resolved.  This state deliberately carries no confirmation
    /// capability.
    case preparingSubmission(
        draft: String,
        isPossiblyIncomplete: Bool,
        feedback: ReviewDraftFeedback? = nil
    )
    /// A complete output attempt crossed the irreversible key-down boundary.
    /// The preview is terminal and must never expose Send or Return again.
    case submittedUnverifiedTerminal(
        draft: String,
        isPossiblyIncomplete: Bool,
        feedback: ReviewDraftFeedback? = .deliveryUncertain
    )
}

nonisolated enum ReviewReadOnlyPhase: Equatable, Sendable {
    case streaming
    case sealing
    case recovery
}

nonisolated enum ReviewPresentationFocusResult: Equatable, Sendable {
    case focused
    case notFocused(ReviewPresentationFocusFailure)
}

nonisolated enum ReviewPresentationFocusPredicate: String, Equatable, Sendable {
    case activationRequest
    case applicationActive
    case panelKey
    case editorMaterialized
    case editorAttachedToPanel
    case editorFirstResponder
}

nonisolated enum ReviewPresentationFocusFailure: Equatable, Sendable {
    case timedOut(lastUnmet: ReviewPresentationFocusPredicate)
    case cancelled(lastUnmet: ReviewPresentationFocusPredicate?)
    case surfaceInvalidated
}

nonisolated struct ReviewPresentationFocusRequest: Equatable, Sendable {
    let reviewID: UUID
    let generation: UInt64
    let focusAttemptID: UInt64
    let capturedApplication: StableApplicationIdentity?

    init(
        reviewID: UUID,
        generation: UInt64,
        focusAttemptID: UInt64,
        capturedApplication: StableApplicationIdentity? = nil
    ) {
        self.reviewID = reviewID
        self.generation = generation
        self.focusAttemptID = focusAttemptID
        self.capturedApplication = capturedApplication
    }
}

nonisolated struct ReviewPresentationFocusOutcome: Equatable, Sendable {
    let request: ReviewPresentationFocusRequest
    let result: ReviewPresentationFocusResult
}

extension ReviewPresentationFocusFailure {
    var telemetryResult: String {
        switch self {
        case .timedOut:
            return "timedOut"
        case .cancelled:
            return "cancelled"
        case .surfaceInvalidated:
            return "surfaceInvalidated"
        }
    }

    var telemetryPredicate: String? {
        let predicate: ReviewPresentationFocusPredicate?
        switch self {
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

nonisolated enum ReviewDraftFeedback: Equatable, Sendable {
    case activationFailed
    case destinationChanged
    case securityRejected
    case unsafeText
    case deliveryFailed
    case deliveryUncertain
    case deliveryCancelled
    case draftTooLong
}
