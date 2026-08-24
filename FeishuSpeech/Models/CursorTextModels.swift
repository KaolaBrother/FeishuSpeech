import ApplicationServices
import Foundation
import os.log

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "CursorTextModels"
)

nonisolated struct CursorTextRange: Equatable, Sendable {
    let location: Int
    let length: Int

    var endLocation: Int? {
        let (end, overflow) = location.addingReportingOverflow(length)
        return overflow ? nil : end
    }

    init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

struct CursorDestinationToken {
    let generation: UInt64
    let processIdentifier: pid_t
    let element: AXUIElement
    let originalSelection: CursorTextRange
}

nonisolated struct ReviewApplicationIdentity: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String
    let executableURL: URL
    let launchDate: Date
}

/// The stable application identity is deliberately a value descriptor.  It is
/// safe to carry between the UI, control plane, and raw submission executor;
/// it is never a PID alias and never contains an AX object.
typealias StableApplicationIdentity = ReviewApplicationIdentity

nonisolated struct CapturedReviewTargetID: Equatable, Hashable, Sendable {
    fileprivate let rawValue: UUID

    init() {
        rawValue = UUID()
    }

    fileprivate init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

/// Opaque MainActor-owned lifetime authority for one raw capture request.  A
/// lease is never interpreted by the coordinator; only the lifecycle observer
/// which issued it can prove ownership or retire it.
nonisolated struct ReviewSubmissionLifecycleLease: Equatable, Hashable, Sendable {
    private let rawValue: UUID

    init() {
        rawValue = UUID()
    }
}

nonisolated enum CapturedReviewTargetBinding: Equatable, Sendable {
    case exactCursor
    case applicationBoundCurrentFocus
}

nonisolated struct ReviewTargetCaptureRequestDescriptor: Equatable, Sendable {
    let generation: UInt64
    let application: StableApplicationIdentity
    let captureUptime: UInt64

    init(
        generation: UInt64,
        application: StableApplicationIdentity,
        captureUptime: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        self.generation = generation
        self.application = application
        self.captureUptime = captureUptime
    }
}

nonisolated struct CapturedReviewTargetDescriptor: Equatable, Sendable {
    let targetID: CapturedReviewTargetID
    let generation: UInt64
    let application: StableApplicationIdentity
    let binding: CapturedReviewTargetBinding
    let securityAtCapture: DestinationSecurityState

    init(
        targetID: CapturedReviewTargetID = CapturedReviewTargetID(),
        generation: UInt64,
        application: StableApplicationIdentity,
        binding: CapturedReviewTargetBinding,
        securityAtCapture: DestinationSecurityState = .safe
    ) {
        self.targetID = targetID
        self.generation = generation
        self.application = application
        self.binding = binding
        self.securityAtCapture = securityAtCapture
    }
}

nonisolated struct ReviewSubmissionRequestDescriptor: Equatable, Sendable {
    let reviewID: UUID
    let generation: UInt64
    let revision: UInt64
    let attemptOrdinal: UInt64
    let frozenDraft: String
    let capturedTargetID: CapturedReviewTargetID
    let confirmationUptime: UInt64

    init(
        reviewID: UUID,
        generation: UInt64,
        revision: UInt64,
        attemptOrdinal: UInt64,
        frozenDraft: String,
        capturedTargetID: CapturedReviewTargetID,
        confirmationUptime: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        self.reviewID = reviewID
        self.generation = generation
        self.revision = revision
        self.attemptOrdinal = attemptOrdinal
        self.frozenDraft = frozenDraft
        self.capturedTargetID = capturedTargetID
        self.confirmationUptime = confirmationUptime
    }
}

/// An attempt handle is intentionally opaque outside the issuing authority.
/// The nonce prevents a handle from one control-plane instance fencing a later
/// attempt, while the monotonically issued ID prevents reuse within a nonce.
nonisolated struct ReviewSubmissionAttemptHandle: Equatable, Hashable, Sendable {
    private let controlPlaneInstanceNonce: UInt64
    private let attemptID: UInt64

    fileprivate init(controlPlaneInstanceNonce: UInt64, attemptID: UInt64) {
        self.controlPlaneInstanceNonce = controlPlaneInstanceNonce
        self.attemptID = attemptID
    }

    /// Read-only identity checks are available to the control plane, while
    /// construction remains confined to the MainActor ticket issuer below.
    var instanceNonce: UInt64 {
        controlPlaneInstanceNonce
    }

    var issuedAttemptID: UInt64 {
        attemptID
    }
}

/// MainActor value authority for opaque attempt IDs.  It has no queue, lock,
/// raw target, or output capability and therefore can synchronously reserve a
/// handle before the first nonblocking enqueue.
@MainActor
final class ReviewAttemptTicketIssuer {
    let controlPlaneInstanceNonce: UInt64
    private var nextAttemptID: UInt64 = 0

    init(controlPlaneInstanceNonce: UInt64) {
        self.controlPlaneInstanceNonce = controlPlaneInstanceNonce
    }

    func issue() -> ReviewSubmissionAttemptHandle? {
        guard nextAttemptID < UInt64.max else { return nil }
        nextAttemptID += 1
        return ReviewSubmissionAttemptHandle(
            controlPlaneInstanceNonce: controlPlaneInstanceNonce,
            attemptID: nextAttemptID
        )
    }
}

nonisolated struct ReviewSubmissionAdmissionEnvelope: Equatable, Sendable {
    let handle: ReviewSubmissionAttemptHandle
    let request: ReviewSubmissionRequestDescriptor
    let absolutePreBoundaryDeadline: UInt64

    init(
        handle: ReviewSubmissionAttemptHandle,
        request: ReviewSubmissionRequestDescriptor,
        absolutePreBoundaryDeadline: UInt64
    ) {
        self.handle = handle
        self.request = request
        self.absolutePreBoundaryDeadline = absolutePreBoundaryDeadline
    }

    init(
        handle: ReviewSubmissionAttemptHandle,
        request: ReviewSubmissionRequestDescriptor,
        timeoutNanoseconds: UInt64 = 2_000_000_000
    ) {
        let (deadline, overflow) = request.confirmationUptime.addingReportingOverflow(
            timeoutNanoseconds
        )
        self.init(
            handle: handle,
            request: request,
            absolutePreBoundaryDeadline: overflow ? UInt64.max : deadline
        )
    }
}

nonisolated enum ReviewSubmissionAdmissionRejection: Equatable, Sendable {
    case duplicateActiveAttempt
    case deadline
    case invalidHandle
    case unsafeDraft
    case invalidRequest
}

nonisolated enum CancellationSignalResult: Equatable, Sendable {
    case latched
    case observedAfterBoundary
    case notCurrent
}

nonisolated enum AdmissionResult: Equatable, Sendable {
    case accepted
    case rejected(ReviewSubmissionAdmissionRejection)
}

nonisolated enum ReviewSubmissionControlEvent: Equatable, Sendable {
    case admissionAccepted(ReviewSubmissionAttemptHandle)
    case admissionRejected(
        ReviewSubmissionAttemptHandle,
        ReviewSubmissionAdmissionRejection
    )
    case cancellationResolved(ReviewSubmissionAttemptHandle, CancellationSignalResult)
    case terminal(ReviewSubmissionAttemptHandle, ReviewCommitReceipt)
}

nonisolated enum ReviewSubmissionPhase: Equatable, Sendable {
    case admitted
    case startQueued
    case claimed
    case preparing
    case committing
    case boundaryCrossed
    case terminalizing
    case terminal
}

nonisolated enum ReviewPreBoundaryFailure: Error, Equatable, Sendable {
    case cancellation
    case deadline
    case targetIdentityChanged
    case frontmostChanged
    case securityRejected
    case modifierInstability
    case inputDrift
    case activationDrift
    case accessibilityTimeout
    case accessibilityFailure
    case constructionFailure
    case readbackFailure
    case gateRejected
}

nonisolated struct ReviewPostBoundaryObservation: Equatable, Sendable {
    let mandatoryKeyUpAttempted: Bool
    let cancellationObservedAfterDown: Bool
    let postflightStable: Bool
}

nonisolated enum ReviewCommitReceipt: Equatable, Sendable {
    case notStarted(ReviewPreBoundaryFailure)
    case submittedUnverified(ReviewPostBoundaryObservation)
}

nonisolated struct TerminalCleanupValue: Equatable, Sendable {
    let handle: ReviewSubmissionAttemptHandle
    let receipt: ReviewCommitReceipt
}

enum ReviewDestinationBinding {
    case exactCursor(CursorDestinationToken)
    case applicationCurrentFocus
}

struct ReviewDestinationToken {
    let generation: UInt64
    let application: ReviewApplicationIdentity
    let binding: ReviewDestinationBinding
    let capturedSecurityState: DestinationSecurityState
}

enum ReviewCursorCaptureResult {
    case exact(CursorDestinationToken)
    case nonSecureCursorUnavailable
    case rejected(ReviewCursorCaptureRejection)
}

nonisolated enum ReviewCursorCaptureRejection: Equatable, Sendable {
    case secureInput
    case accessibilityUnavailable
}

enum ReviewDestinationCaptureResult {
    case captured(ReviewDestinationToken)
    case rejected(ReviewDestinationCaptureRejection)
}

nonisolated enum ReviewDestinationCaptureRejection: Equatable, Sendable {
    case secureInput
    case destinationUnavailable
}

nonisolated enum CursorCapabilityRejection: Equatable, Sendable {
    case secureTarget
    case accessibilityUnavailable
}

enum CursorCapabilityResult {
    case live(CursorDestinationToken)
    case finalOnly(CursorDestinationToken)
    case rejected(CursorCapabilityRejection)
}

nonisolated enum AccessibilityClientError: Error, Equatable, Sendable {
    case accessibilityUnavailable
    case noFocusedElement
    case cannotComplete
    case invalidValue
    case operationFailed
}

nonisolated enum DestinationSecurityState: Equatable, Sendable {
    case safe
    case secure
    case unverifiable
}

nonisolated enum ReviewCurrentFocusValidation: Equatable, Sendable {
    case valid
    case securityRejected
    case identityChanged
    case destinationInvalid
}

nonisolated enum CursorTextSessionState: Equatable, Sendable {
    case unavailable
    case armed
    case finalOnly
    case provisional(range: CursorTextRange, text: String)
    case invalid
    case committed
    case preserved
}

nonisolated enum FinalOnlyFallbackDecision: Equatable, Sendable {
    case insertOnce
    case copyForManualRecovery
    case noInsertion
    case rejectSecureTarget

    static func evaluate(
        autoInsert: Bool,
        secureTarget: Bool,
        finalTextIsEmpty: Bool,
        destinationStillCurrent: Bool
    ) -> FinalOnlyFallbackDecision {
        if secureTarget {
            return .rejectSecureTarget
        }
        guard autoInsert, !finalTextIsEmpty else {
            return .noInsertion
        }
        return destinationStillCurrent ? .insertOnce : .copyForManualRecovery
    }
}

nonisolated enum FinalTextInsertionResult: Equatable, Sendable {
    case inserted
    /// CoreGraphics accepts the local event submission, but the target gives
    /// no consumption/display receipt. Review output must expose that fact
    /// instead of claiming the text was consumed.
    case submittedUnverified
    case securityRejected
    case identityChanged
    case destinationInvalid
    case deliveryFailed
    case deliveryUncertain
}
