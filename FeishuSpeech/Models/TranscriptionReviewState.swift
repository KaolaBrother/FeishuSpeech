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
    case editable(draft: String, isPossiblyIncomplete: Bool)
    case confirming
}

nonisolated enum InteractionOutputMode: Equatable, Sendable {
    case reviewFirst
    case compatibility(autoInsert: Bool)
}

nonisolated enum ReviewReadOnlyPhase: Equatable, Sendable {
    case streaming
    case sealing
}

nonisolated enum ReviewEditableTransitionResult: Equatable, Sendable {
    case ready
    case failed
}
