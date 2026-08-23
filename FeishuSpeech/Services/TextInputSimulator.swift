import AppKit
import Carbon
import Foundation

import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "TextInputSimulator")

@MainActor
protocol FinalTextOutput: AnyObject {
    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateDestination: () throws -> Bool
    ) -> FinalTextInsertionResult
    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateBeforeMutation: () throws -> Bool,
        validateAfterPosting: () throws -> Bool
    ) -> FinalTextInsertionResult
    func insertReviewAtCurrentFocusOnce(
        _ text: String,
        processIdentifier: pid_t,
        validateBeforeMutation: () -> ReviewCurrentFocusValidation,
        validateAfterPosting: () -> ReviewCurrentFocusValidation
    ) -> FinalTextInsertionResult
    func insertAtCurrentFocusOnce(_ text: String) -> FinalTextInsertionResult

    /// Review delivery may provide one final, synchronously-held critical
    /// section around the complete Unicode pair. The default keeps older
    /// doubles source-compatible while the system implementation uses it to
    /// bind activation and physical-input epochs through both posts.
    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateBeforeMutation: @escaping () throws -> Bool,
        validateAfterPosting: () throws -> Bool,
        postPairIfPreflightRemainsValid pairGate: (@escaping () -> Void) -> Bool
    ) -> FinalTextInsertionResult

    func insertReviewAtCurrentFocusOnce(
        _ text: String,
        processIdentifier: pid_t,
        validateBeforeMutation: @escaping () -> ReviewCurrentFocusValidation,
        validateAfterPosting: () -> ReviewCurrentFocusValidation,
        postPairIfPreflightRemainsValid pairGate: (@escaping () -> Void) -> Bool
    ) -> FinalTextInsertionResult
}

extension FinalTextOutput {
    /// Older output implementations cannot prove the v4 pair/epoch contract.
    /// Keep their source compatibility, but fail closed for explicit review.
    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateBeforeMutation: () throws -> Bool,
        validateAfterPosting: () throws -> Bool
    ) -> FinalTextInsertionResult {
        var validationCallCount = 0
        let result = insertOnce(
            text,
            destination: destination,
            validateDestination: {
                validationCallCount += 1
                if validationCallCount == 1 {
                    return try validateBeforeMutation()
                }
                return try validateAfterPosting()
            }
        )
        if validationCallCount >= 2, result == .destinationInvalid {
            return .deliveryUncertain
        }
        return result
    }

    /// Existing output doubles remain fail-closed until they explicitly adopt the
    /// review-only current-focus transaction.
    func insertReviewAtCurrentFocusOnce(
        _ text: String,
        processIdentifier: pid_t,
        validateBeforeMutation: () -> ReviewCurrentFocusValidation,
        validateAfterPosting: () -> ReviewCurrentFocusValidation
    ) -> FinalTextInsertionResult {
        .destinationInvalid
    }

    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateBeforeMutation: @escaping () throws -> Bool,
        validateAfterPosting: () throws -> Bool,
        postPairIfPreflightRemainsValid pairGate: (@escaping () -> Void) -> Bool
    ) -> FinalTextInsertionResult {
        .deliveryFailed
    }

    func insertReviewAtCurrentFocusOnce(
        _ text: String,
        processIdentifier: pid_t,
        validateBeforeMutation: @escaping () -> ReviewCurrentFocusValidation,
        validateAfterPosting: () -> ReviewCurrentFocusValidation,
        postPairIfPreflightRemainsValid pairGate: (@escaping () -> Void) -> Bool
    ) -> FinalTextInsertionResult {
        .deliveryFailed
    }
}

nonisolated enum ReviewUnicodeOutputFailure: Equatable, Sendable {
    case unsafeText
    case draftTooLong
    case constructionFailed
    case provenanceMismatch
    case secureInput
    case cancelledBeforeSubmission
    case preflightRejected
}

nonisolated enum ReviewUnicodePostflight: Equatable, Sendable {
    case valid
    case uncertain
}

/// A review output attempt is deliberately phase-aware. Once key-down is
/// submitted the result can never be represented as cancellation or a failed
/// preflight, because the process cannot retract that event.
nonisolated enum ReviewUnicodeOutputResult: Equatable, Sendable {
    case failedBeforeSubmission(ReviewUnicodeOutputFailure)
    case cancelledBeforeSubmission
    case submittedUnverified(ReviewUnicodePostflight)
}

@MainActor
final class SystemFinalTextOutput: FinalTextOutput, ReviewCurrentFocusEnvironmentProviding {
    private let currentFocusEventPoster: FinalTextCurrentFocusEventPosting
    private let secureInputStateProvider: SecureInputStateProviding
    private let frontmostProcessProvider: FrontmostProcessProviding

    init(
        pasteboardWriter _: FinalTextPasteboardWriting,
        keyEventPoster _: FinalTextKeyEventPosting,
        secureInputStateProvider: SecureInputStateProviding? = nil,
        frontmostProcessProvider: FrontmostProcessProviding? = nil
    ) {
        currentFocusEventPoster = SystemFinalTextCurrentFocusEventPoster()
        self.secureInputStateProvider = secureInputStateProvider ?? SystemSecureInputStateProvider()
        self.frontmostProcessProvider = frontmostProcessProvider ?? SystemFrontmostProcessProvider()
    }

    init(
        pasteboardWriter _: FinalTextPasteboardWriting,
        keyEventPoster _: FinalTextKeyEventPosting,
        currentFocusEventPoster: FinalTextCurrentFocusEventPosting,
        secureInputStateProvider: SecureInputStateProviding,
        frontmostProcessProvider: FrontmostProcessProviding
    ) {
        self.currentFocusEventPoster = currentFocusEventPoster
        self.secureInputStateProvider = secureInputStateProvider
        self.frontmostProcessProvider = frontmostProcessProvider
    }

    convenience init() {
        self.init(
            pasteboardWriter: ReviewOutputCompatibilityWriter(),
            keyEventPoster: ReviewOutputCompatibilityPoster(),
            secureInputStateProvider: SystemSecureInputStateProvider(),
            frontmostProcessProvider: SystemFrontmostProcessProvider()
        )
    }

    var reviewSecureInputStateProvider: SecureInputStateProviding {
        secureInputStateProvider
    }

    var reviewFrontmostProcessProvider: FrontmostProcessProviding {
        frontmostProcessProvider
    }

    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateDestination: () throws -> Bool
    ) -> FinalTextInsertionResult {
        guard TextInputSimulator.isSafeForReviewConfirmation(text) else {
            return .deliveryFailed
        }
        do {
            guard try validateDestination() else { return .destinationInvalid }
        } catch {
            return .destinationInvalid
        }
        return insertReviewPair(
            text,
            processIdentifier: destination.processIdentifier,
            validateAfterPosting: {
                do {
                    return try validateDestination()
                        ? .valid
                        : .destinationInvalid
                } catch {
                    return .destinationInvalid
                }
            },
            pairGate: { postPair in
                postPair()
                return true
            }
        )
    }

    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateBeforeMutation: () throws -> Bool,
        validateAfterPosting: () throws -> Bool
    ) -> FinalTextInsertionResult {
        withoutActuallyEscaping(validateBeforeMutation) { validation in
            insertOnce(
                text,
                destination: destination,
                validateBeforeMutation: validation,
                validateAfterPosting: validateAfterPosting,
                postPairIfPreflightRemainsValid: { postPair in
                    postPair()
                    return true
                }
            )
        }
    }

    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateBeforeMutation: @escaping () throws -> Bool,
        validateAfterPosting: () throws -> Bool,
        postPairIfPreflightRemainsValid pairGate: (@escaping () -> Void) -> Bool
    ) -> FinalTextInsertionResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              TextInputSimulator.isSafeForReviewConfirmation(text) else {
            return .deliveryFailed
        }
        do {
            guard try validateBeforeMutation() else {
                return .destinationInvalid
            }
        } catch {
            return .destinationInvalid
        }
        let result = insertReviewPair(
            text,
            processIdentifier: destination.processIdentifier,
            validateAfterPosting: {
                do {
                    return try validateAfterPosting() ? .valid : .destinationInvalid
                } catch {
                    return .destinationInvalid
                }
            },
            pairGate: { postPair in pairGate(postPair) }
        )
        return result
    }

    func insertReviewAtCurrentFocusOnce(
        _ text: String,
        processIdentifier: pid_t,
        validateBeforeMutation: () -> ReviewCurrentFocusValidation,
        validateAfterPosting: () -> ReviewCurrentFocusValidation
    ) -> FinalTextInsertionResult {
        withoutActuallyEscaping(validateBeforeMutation) { validation in
            insertReviewAtCurrentFocusOnce(
                text,
                processIdentifier: processIdentifier,
                validateBeforeMutation: validation,
                validateAfterPosting: validateAfterPosting,
                postPairIfPreflightRemainsValid: { postPair in
                    postPair()
                    return true
                }
            )
        }
    }

    func insertReviewAtCurrentFocusOnce(
        _ text: String,
        processIdentifier: pid_t,
        validateBeforeMutation: @escaping () -> ReviewCurrentFocusValidation,
        validateAfterPosting: () -> ReviewCurrentFocusValidation,
        postPairIfPreflightRemainsValid pairGate: (@escaping () -> Void) -> Bool
    ) -> FinalTextInsertionResult {
        guard processIdentifier > 0,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              TextInputSimulator.isSafeForReviewConfirmation(text) else {
            return .deliveryFailed
        }

        let preflightResult = validateBeforeMutation()
        guard preflightResult == .valid else {
            return finalTextInsertionResult(for: preflightResult)
        }
        let result = insertReviewPair(
            text,
            processIdentifier: processIdentifier,
            validateAfterPosting: validateAfterPosting,
            pairGate: { postPair in pairGate(postPair) }
        )
        return result
    }

    private func insertReviewPair(
        _ text: String,
        processIdentifier: pid_t,
        validateAfterPosting: () -> ReviewCurrentFocusValidation,
        pairGate: (@escaping () -> Void) -> Bool
    ) -> FinalTextInsertionResult {
        let result = currentFocusEventPoster.postReviewUnicodePair(
            text,
            to: processIdentifier,
            postPairIfPreflightRemainsValid: pairGate,
            validateAfterPosting: validateAfterPosting
        )
        return finalTextInsertionResult(for: result)
    }

    private func finalTextInsertionResult(
        for validation: ReviewCurrentFocusValidation
    ) -> FinalTextInsertionResult {
        switch validation {
        case .valid:
            return .submittedUnverified
        case .securityRejected:
            return .securityRejected
        case .identityChanged:
            return .identityChanged
        case .destinationInvalid:
            return .destinationInvalid
        }
    }

    private func finalTextInsertionResult(
        for result: ReviewUnicodeOutputResult
    ) -> FinalTextInsertionResult {
        switch result {
        case .failedBeforeSubmission(let failure):
            switch failure {
            case .secureInput:
                return .securityRejected
            default:
                return .deliveryFailed
            }
        case .cancelledBeforeSubmission:
            return .deliveryFailed
        case .submittedUnverified(.valid):
            return .submittedUnverified
        case .submittedUnverified(.uncertain):
            return .deliveryUncertain
        }
    }

    func insertAtCurrentFocusOnce(_ text: String) -> FinalTextInsertionResult {
        guard TextInputSimulator.isSafeForAutomaticPaste(text) else {
            return .deliveryFailed
        }

        let firstSecureInputSample = secureInputStateProvider.isSecureInputEnabled()
        let firstProcessIdentifier = frontmostProcessProvider.frontmostProcessIdentifier()
        let secondSecureInputSample = secureInputStateProvider.isSecureInputEnabled()
        let secondProcessIdentifier = frontmostProcessProvider.frontmostProcessIdentifier()

        guard !firstSecureInputSample, !secondSecureInputSample else {
            return .securityRejected
        }
        guard let firstProcessIdentifier,
              firstProcessIdentifier == secondProcessIdentifier else {
            return .destinationInvalid
        }
        switch currentFocusEventPoster.postUnicodeText(text, to: firstProcessIdentifier) {
        case .posted:
            return .inserted
        case .securityRejected:
            return .securityRejected
        case .deliveryFailed:
            return .deliveryFailed
        }
    }

}

@MainActor
protocol FinalTextPasteboardWriting: AnyObject {
}

@MainActor
protocol FinalTextKeyEventPosting: AnyObject {
}

@MainActor
protocol FinalTextCurrentFocusEventPosting: AnyObject {
    func postUnicodeText(
        _ text: String,
        to processIdentifier: pid_t
    ) -> FinalTextCurrentFocusPostResult
    func postReplacement(
        deleteCharacterCount: Int,
        insertText: String,
        to processIdentifier: pid_t
    ) -> FinalTextCurrentFocusPostResult
    func postReplacement(
        deleteCharacterCount: Int,
        insertText: String,
        to processIdentifier: pid_t,
        whileInterferenceEpochIsUnchanged: () -> Bool
    ) -> FinalTextCurrentFocusPostResult
    func postReplacement(
        deleteCharacterCount: Int,
        insertText: String,
        to processIdentifier: pid_t,
        postCompleteSyntheticPairIfInterferenceEpochIsUnchanged pairGate: (
            (_ postPair: () -> Void) -> Bool
        )
    ) -> FinalTextCurrentFocusPostResult
    func postReviewUnicodePair(
        _ text: String,
        to processIdentifier: pid_t,
        postPairIfPreflightRemainsValid pairGate: (
            (_ postPair: @escaping () -> Void
            ) -> Bool
        ),
        validateAfterPosting: () -> ReviewCurrentFocusValidation
    ) -> ReviewUnicodeOutputResult
}

extension FinalTextCurrentFocusEventPosting {
    func postReplacement(
        deleteCharacterCount: Int,
        insertText: String,
        to processIdentifier: pid_t
    ) -> FinalTextCurrentFocusPostResult {
        guard deleteCharacterCount == 0 else { return .deliveryFailed }
        return postUnicodeText(insertText, to: processIdentifier)
    }

    func postReplacement(
        deleteCharacterCount: Int,
        insertText: String,
        to processIdentifier: pid_t,
        whileInterferenceEpochIsUnchanged: () -> Bool
    ) -> FinalTextCurrentFocusPostResult {
        guard whileInterferenceEpochIsUnchanged() else { return .deliveryFailed }
        return postReplacement(
            deleteCharacterCount: deleteCharacterCount,
            insertText: insertText,
            to: processIdentifier
        )
    }

    func postReplacement(
        deleteCharacterCount: Int,
        insertText: String,
        to processIdentifier: pid_t,
        postCompleteSyntheticPairIfInterferenceEpochIsUnchanged pairGate: (
            (_ postPair: () -> Void) -> Bool
        )
    ) -> FinalTextCurrentFocusPostResult {
        guard pairGate({}) else {
            return .deliveryFailed
        }
        return postReplacement(
            deleteCharacterCount: deleteCharacterCount,
            insertText: insertText,
            to: processIdentifier
        )
    }

    func postReviewUnicodePair(
        _ text: String,
        to processIdentifier: pid_t,
        postPairIfPreflightRemainsValid pairGate: (
            (_ postPair: @escaping () -> Void
            ) -> Bool
        ),
        validateAfterPosting: () -> ReviewCurrentFocusValidation
        ) -> ReviewUnicodeOutputResult {
        guard processIdentifier > 0,
              TextInputSimulator.isSafeForReviewConfirmation(text) else {
            return .failedBeforeSubmission(.unsafeText)
        }
        var postResult: FinalTextCurrentFocusPostResult = .deliveryFailed
        guard pairGate({
            postResult = self.postUnicodeText(text, to: processIdentifier)
        }) else {
            return .failedBeforeSubmission(.preflightRejected)
        }
        switch postResult {
        case .posted:
            return validateAfterPosting() == .valid
                ? .submittedUnverified(.valid)
                : .submittedUnverified(.uncertain)
        case .securityRejected:
            return .failedBeforeSubmission(.secureInput)
        case .deliveryFailed:
            return .failedBeforeSubmission(.constructionFailed)
        }
    }
}

nonisolated enum FinalTextCurrentFocusPostResult: Equatable, Sendable {
    case posted
    case securityRejected
    case deliveryFailed
}

nonisolated enum FinalTextUnicodeEventPhase: Equatable, Sendable {
    case keyDown
    case keyUp
}

@MainActor
protocol FinalTextUnicodeEventSourceHandle: AnyObject {}

@MainActor
protocol FinalTextUnicodeEventHandle: AnyObject {}

@MainActor
struct FinalTextUnicodeReadback {
    let event: any FinalTextUnicodeEventHandle
    let source: any FinalTextUnicodeEventSourceHandle
    let expectedPhase: FinalTextUnicodeEventPhase
    let expectedUTF16: [UInt16]
    let expectedFlags: CGEventFlags
    let expectedUserData: Int64
    let expectedSourceProcessIdentifier: pid_t
    let expectedTargetProcessIdentifier: pid_t
}

@MainActor
protocol FinalTextUnicodeEventBackend: AnyObject {
    func makeEventSource(
        stateID: CGEventSourceStateID
    ) -> (any FinalTextUnicodeEventSourceHandle)?
    func makeUnicodeEvent(
        source: any FinalTextUnicodeEventSourceHandle,
        phase: FinalTextUnicodeEventPhase,
        utf16: [UInt16],
        flags: CGEventFlags
    ) -> (any FinalTextUnicodeEventHandle)?
    func makeKeyboardEvent(
        source: any FinalTextUnicodeEventSourceHandle,
        phase: FinalTextUnicodeEventPhase,
        virtualKey: CGKeyCode,
        flags: CGEventFlags
    ) -> (any FinalTextUnicodeEventHandle)?
    func setUserData(
        _ userData: Int64,
        for event: any FinalTextUnicodeEventHandle
    )
    func setTargetProcessIdentifier(
        _ processIdentifier: pid_t,
        for event: any FinalTextUnicodeEventHandle
    )
    func readbackEvent(_ expectation: FinalTextUnicodeReadback) -> Bool
    func postUnicodeEvent(
        _ event: any FinalTextUnicodeEventHandle,
        to processIdentifier: pid_t
    )
}

extension FinalTextUnicodeEventBackend {
    func makeKeyboardEvent(
        source _: any FinalTextUnicodeEventSourceHandle,
        phase _: FinalTextUnicodeEventPhase,
        virtualKey _: CGKeyCode,
        flags _: CGEventFlags
    ) -> (any FinalTextUnicodeEventHandle)? {
        nil
    }

    func setUserData(
        _: Int64,
        for _: any FinalTextUnicodeEventHandle
    ) {}

    /// Compatibility default for pre-v4 fakes. The production backend below
    /// overrides this with a complete CoreGraphics readback; new fakes should
    /// override it as well so missing provenance capability fails closed.
    func setTargetProcessIdentifier(
        _: pid_t,
        for _: any FinalTextUnicodeEventHandle
    ) {}

    func readbackEvent(_: FinalTextUnicodeReadback) -> Bool {
        false
    }
}

nonisolated enum FeishuSpeechSyntheticEventTag {
    static let value: Int64 = 0x4653_5350_4545_4348

    /// Synthetic identity is deliberately conjunctive. A fixed public tag is
    /// not sufficient to suppress physical-input interference from a foreign
    /// or malformed event source.
    static func isSelfIdentified(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == value
            && event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid())
    }
}

nonisolated enum ReviewUnicodeSubmissionPhase: Equatable, Sendable {
    case notStarted
    case submissionBoundaryCrossed
}

/// Dependency-free fault and cancellation seams for the review pair. The
/// production value performs no mutation and reports the live task state;
/// tests may replace individual hooks without changing the transaction order.
@MainActor
struct ReviewUnicodePosterHooks {
    let beforeBuild: () -> Bool
    let afterBuild: () -> Bool
    let beforeDown: () -> Bool
    let afterDown: () -> Bool
    let beforeUp: () -> Bool
    let afterUp: () -> Bool
    let postflight: () -> Bool
    let cancellation: () -> Bool

    init(
        beforeBuild: @escaping () -> Bool = { true },
        afterBuild: @escaping () -> Bool = { true },
        beforeDown: @escaping () -> Bool = { true },
        afterDown: @escaping () -> Bool = { true },
        beforeUp: @escaping () -> Bool = { true },
        afterUp: @escaping () -> Bool = { true },
        postflight: @escaping () -> Bool = { true },
        cancellation: @escaping () -> Bool = { Task.isCancelled }
    ) {
        self.beforeBuild = beforeBuild
        self.afterBuild = afterBuild
        self.beforeDown = beforeDown
        self.afterDown = afterDown
        self.beforeUp = beforeUp
        self.afterUp = afterUp
        self.postflight = postflight
        self.cancellation = cancellation
    }

}

@MainActor
protocol SecureInputStateProviding: AnyObject {
    func isSecureInputEnabled() -> Bool
}

@MainActor
protocol FrontmostProcessProviding: AnyObject {
    func frontmostProcessIdentifier() -> pid_t?
}

@MainActor
protocol ReviewCurrentFocusEnvironmentProviding: AnyObject {
    var reviewSecureInputStateProvider: SecureInputStateProviding { get }
    var reviewFrontmostProcessProvider: FrontmostProcessProviding { get }
}

/// Marker implementations retained only so older dependency-injection call
/// sites can compile. Review output never reads or writes a pasteboard and
/// never emits a virtual-key command event.
@MainActor
private final class ReviewOutputCompatibilityWriter: FinalTextPasteboardWriting {}

@MainActor
private final class ReviewOutputCompatibilityPoster: FinalTextKeyEventPosting {}

@MainActor
final class SystemFinalTextCurrentFocusEventPoster: FinalTextCurrentFocusEventPosting {
    private let backend: FinalTextUnicodeEventBackend
    private let secureInputStateProvider: SecureInputStateProviding
    private let hooks: ReviewUnicodePosterHooks

    convenience init() {
        self.init(
            backend: SystemFinalTextUnicodeEventBackend(),
            secureInputStateProvider: SystemSecureInputStateProvider(),
            hooks: ReviewUnicodePosterHooks()
        )
    }

    init(
        backend: FinalTextUnicodeEventBackend,
        secureInputStateProvider: SecureInputStateProviding,
        hooks: ReviewUnicodePosterHooks? = nil
    ) {
        self.backend = backend
        self.secureInputStateProvider = secureInputStateProvider
        self.hooks = hooks ?? ReviewUnicodePosterHooks()
    }

    private struct PreparedReviewUnicodePair {
        let keyDown: any FinalTextUnicodeEventHandle
        let keyUp: any FinalTextUnicodeEventHandle
    }

    private enum ReviewUnicodePreparation {
        case ready(PreparedReviewUnicodePair)
        case failed(ReviewUnicodeOutputResult)
    }

    private struct ReviewUnicodeSubmissionState {
        var phase = ReviewUnicodeSubmissionPhase.notStarted
        var postAttemptHadFault = false
        var postPairWasEntered = false
        var preBoundaryFailure = false
    }

    func postUnicodeText(
        _ text: String,
        to processIdentifier: pid_t
    ) -> FinalTextCurrentFocusPostResult {
        switch postReviewUnicodePair(
            text,
            to: processIdentifier,
            postPairIfPreflightRemainsValid: { postPair in
                postPair()
                return true
            },
            validateAfterPosting: { .valid }
        ) {
        case .failedBeforeSubmission(let failure):
            switch failure {
            case .secureInput:
                return .securityRejected
            default:
                return .deliveryFailed
            }
        case .cancelledBeforeSubmission:
            return .deliveryFailed
        case .submittedUnverified(.valid):
            return .posted
        case .submittedUnverified(.uncertain):
            return .deliveryFailed
        }
    }

    /// Posts exactly one fully prepared Unicode key-down/key-up pair. The
    /// complete pair is constructed, tagged, targeted, and read back before
    /// the first post. `submissionBoundaryCrossed` is set at the down call;
    /// every path after that boundary attempts the up event and returns
    /// `submittedUnverified`, never cancellation.
    func postReviewUnicodePair(
        _ text: String,
        to processIdentifier: pid_t,
        postPairIfPreflightRemainsValid pairGate: (
            (_ postPair: @escaping () -> Void
            ) -> Bool
        ),
        validateAfterPosting: () -> ReviewCurrentFocusValidation
    ) -> ReviewUnicodeOutputResult {
        switch prepareReviewUnicodePair(text, processIdentifier: processIdentifier) {
        case .failed(let result):
            return result
        case .ready(let preparedPair):
            guard !secureInputStateProvider.isSecureInputEnabled() else {
                return .failedBeforeSubmission(.secureInput)
            }
            return submitReviewUnicodePair(
                preparedPair,
                to: processIdentifier,
                pairGate: pairGate,
                validateAfterPosting: validateAfterPosting
            )
        }
    }

    private func prepareReviewUnicodePair(
        _ text: String,
        processIdentifier: pid_t
    ) -> ReviewUnicodePreparation {
        guard processIdentifier > 0,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failed(.failedBeforeSubmission(.unsafeText))
        }
        guard TextInputSimulator.isSafeForReviewConfirmation(text) else {
            return .failed(.failedBeforeSubmission(.unsafeText))
        }
        guard text.utf16.count <= TextInputSimulator.reviewMaximumUTF16CodeUnits else {
            return .failed(.failedBeforeSubmission(.draftTooLong))
        }
        guard !hooks.cancellation() else {
            return .failed(.cancelledBeforeSubmission)
        }
        guard hooks.beforeBuild() else {
            return .failed(.failedBeforeSubmission(.constructionFailed))
        }

        let utf16 = Array(text.utf16)
        guard let source = backend.makeEventSource(stateID: .privateState),
              let keyDown = backend.makeUnicodeEvent(
                  source: source,
                  phase: .keyDown,
                  utf16: utf16,
                  flags: []
              ),
              let keyUp = backend.makeUnicodeEvent(
                  source: source,
                  phase: .keyUp,
                  utf16: utf16,
                  flags: []
              ) else {
            return .failed(.failedBeforeSubmission(.constructionFailed))
        }

        let events: [(any FinalTextUnicodeEventHandle, FinalTextUnicodeEventPhase)] = [
            (keyDown, .keyDown),
            (keyUp, .keyUp)
        ]
        for (event, _) in events {
            backend.setUserData(FeishuSpeechSyntheticEventTag.value, for: event)
            backend.setTargetProcessIdentifier(processIdentifier, for: event)
        }
        guard events.allSatisfy({ event, expectedPhase in
            backend.readbackEvent(FinalTextUnicodeReadback(
                event: event,
                source: source,
                expectedPhase: expectedPhase,
                expectedUTF16: utf16,
                expectedFlags: [],
                expectedUserData: FeishuSpeechSyntheticEventTag.value,
                expectedSourceProcessIdentifier: getpid(),
                expectedTargetProcessIdentifier: processIdentifier
            ))
        }) else {
            return .failed(.failedBeforeSubmission(.provenanceMismatch))
        }
        guard hooks.afterBuild() else {
            return .failed(.failedBeforeSubmission(.constructionFailed))
        }
        return .ready(PreparedReviewUnicodePair(keyDown: keyDown, keyUp: keyUp))
    }

    private func submitReviewUnicodePair(
        _ preparedPair: PreparedReviewUnicodePair,
        to processIdentifier: pid_t,
        pairGate: (
            (_ postPair: @escaping () -> Void
            ) -> Bool
        ),
        validateAfterPosting: () -> ReviewCurrentFocusValidation
    ) -> ReviewUnicodeOutputResult {
        var state = ReviewUnicodeSubmissionState()
        let entered = pairGate { [self] in
            guard !self.hooks.cancellation(), self.hooks.beforeDown() else {
                state.preBoundaryFailure = true
                return
            }
            self.backend.postUnicodeEvent(preparedPair.keyDown, to: processIdentifier)
            state.phase = .submissionBoundaryCrossed
            state.postPairWasEntered = true

            // The boundary is irreversible. These hooks may report a fault,
            // but they must never suppress the mandatory key-up attempt.
            if !self.hooks.afterDown() { state.postAttemptHadFault = true }
            if !self.hooks.beforeUp() { state.postAttemptHadFault = true }
            self.backend.postUnicodeEvent(preparedPair.keyUp, to: processIdentifier)
            if !self.hooks.afterUp() { state.postAttemptHadFault = true }
        }

        guard state.postPairWasEntered,
              state.phase == .submissionBoundaryCrossed else {
            return preBoundaryResult(entered: entered, state: state)
        }

        let postflight = validateAfterPosting()
        guard !state.postAttemptHadFault,
              !hooks.cancellation(),
              hooks.postflight(),
              postflight == .valid else {
            return .submittedUnverified(.uncertain)
        }
        return .submittedUnverified(.valid)
    }

    private func preBoundaryResult(
        entered: Bool,
        state: ReviewUnicodeSubmissionState
    ) -> ReviewUnicodeOutputResult {
        guard !hooks.cancellation() else {
            return .cancelledBeforeSubmission
        }
        let rejected = state.preBoundaryFailure || !entered
        return .failedBeforeSubmission(rejected ? .preflightRejected : .constructionFailed)
    }

    func postReplacement(
        deleteCharacterCount: Int,
        insertText: String,
        to processIdentifier: pid_t
    ) -> FinalTextCurrentFocusPostResult {
        postReplacement(
            deleteCharacterCount: deleteCharacterCount,
            insertText: insertText,
            to: processIdentifier,
            postCompleteSyntheticPairIfInterferenceEpochIsUnchanged: { postPair in
                postPair()
                return true
            }
        )
    }

    func postReplacement(
        deleteCharacterCount: Int,
        insertText: String,
        to processIdentifier: pid_t,
        whileInterferenceEpochIsUnchanged: () -> Bool
    ) -> FinalTextCurrentFocusPostResult {
        postReplacement(
            deleteCharacterCount: deleteCharacterCount,
            insertText: insertText,
            to: processIdentifier,
            postCompleteSyntheticPairIfInterferenceEpochIsUnchanged: { postPair in
                guard whileInterferenceEpochIsUnchanged() else { return false }
                postPair()
                return true
            }
        )
    }

    func postReplacement(
        deleteCharacterCount: Int,
        insertText: String,
        to processIdentifier: pid_t,
        postCompleteSyntheticPairIfInterferenceEpochIsUnchanged pairGate: (
            (_ postPair: () -> Void) -> Bool
        )
    ) -> FinalTextCurrentFocusPostResult {
        guard processIdentifier > 0,
              deleteCharacterCount >= 0,
              deleteCharacterCount > 0 || !insertText.isEmpty,
              TextInputSimulator.isSafeForAutomaticKeyboardEventText(insertText) else {
            return .deliveryFailed
        }
        guard let source = backend.makeEventSource(stateID: .privateState) else {
            return .deliveryFailed
        }

        var backspacePairs: [[any FinalTextUnicodeEventHandle]] = []
        backspacePairs.reserveCapacity(deleteCharacterCount)
        for _ in 0 ..< deleteCharacterCount {
            guard let keyDown = backend.makeKeyboardEvent(
                source: source,
                phase: .keyDown,
                virtualKey: CGKeyCode(kVK_Delete),
                flags: []
            ), let keyUp = backend.makeKeyboardEvent(
                source: source,
                phase: .keyUp,
                virtualKey: CGKeyCode(kVK_Delete),
                flags: []
            ) else {
                return .deliveryFailed
            }
            backspacePairs.append([keyDown, keyUp])
        }

        var insertionPair: [any FinalTextUnicodeEventHandle] = []
        if !insertText.isEmpty {
            let utf16 = Array(insertText.utf16)
            guard let keyDown = backend.makeUnicodeEvent(
                source: source,
                phase: .keyDown,
                utf16: utf16,
                flags: []
            ), let keyUp = backend.makeUnicodeEvent(
                source: source,
                phase: .keyUp,
                utf16: utf16,
                flags: []
            ) else {
                return .deliveryFailed
            }
            insertionPair = [keyDown, keyUp]
        }

        let events = backspacePairs.flatMap { $0 } + insertionPair
        events.forEach { backend.setUserData(FeishuSpeechSyntheticEventTag.value, for: $0) }
        guard !secureInputStateProvider.isSecureInputEnabled() else {
            return .securityRejected
        }
        return postPreparedPairs(
            backspacePairs,
            insertionPair: insertionPair,
            to: processIdentifier,
            pairGate: pairGate
        ) ? .posted : .deliveryFailed
    }

    private func postPreparedPairs(
        _ backspacePairs: [[any FinalTextUnicodeEventHandle]],
        insertionPair: [any FinalTextUnicodeEventHandle],
        to processIdentifier: pid_t,
        pairGate: ((_ postPair: () -> Void) -> Bool)
    ) -> Bool {
        for pair in backspacePairs {
            let posted = pairGate {
                pair.forEach { backend.postUnicodeEvent($0, to: processIdentifier) }
            }
            guard posted else { return false }
        }
        guard !insertionPair.isEmpty else { return true }
        return pairGate {
            insertionPair.forEach { backend.postUnicodeEvent($0, to: processIdentifier) }
        }
    }
}

@MainActor
private final class SystemFinalTextUnicodeEventBackend: FinalTextUnicodeEventBackend {
    func makeEventSource(
        stateID: CGEventSourceStateID
    ) -> (any FinalTextUnicodeEventSourceHandle)? {
        guard let source = CGEventSource(stateID: stateID) else { return nil }
        return SystemFinalTextUnicodeEventSourceHandle(source: source)
    }

    func makeUnicodeEvent(
        source: any FinalTextUnicodeEventSourceHandle,
        phase: FinalTextUnicodeEventPhase,
        utf16: [UInt16],
        flags: CGEventFlags
    ) -> (any FinalTextUnicodeEventHandle)? {
        guard let source = source as? SystemFinalTextUnicodeEventSourceHandle,
              let event = CGEvent(
                keyboardEventSource: source.source,
                virtualKey: 0,
                keyDown: phase == .keyDown
        ) else {
            return nil
        }
        event.flags = flags
        event.setIntegerValueField(
            .eventSourceUnixProcessID,
            value: Int64(getpid())
        )
        event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        return SystemFinalTextUnicodeEventHandle(
            event: event,
            phase: phase,
            utf16: utf16,
            source: source
        )
    }

    func makeKeyboardEvent(
        source: any FinalTextUnicodeEventSourceHandle,
        phase: FinalTextUnicodeEventPhase,
        virtualKey: CGKeyCode,
        flags: CGEventFlags
    ) -> (any FinalTextUnicodeEventHandle)? {
        guard let source = source as? SystemFinalTextUnicodeEventSourceHandle,
              let event = CGEvent(
                keyboardEventSource: source.source,
                virtualKey: virtualKey,
                keyDown: phase == .keyDown
        ) else {
            return nil
        }
        event.flags = flags
        event.setIntegerValueField(
            .eventSourceUnixProcessID,
            value: Int64(getpid())
        )
        return SystemFinalTextUnicodeEventHandle(
            event: event,
            phase: phase,
            utf16: [],
            source: source,
            virtualKey: virtualKey
        )
    }

    func setUserData(
        _ userData: Int64,
        for event: any FinalTextUnicodeEventHandle
    ) {
        guard let event = event as? SystemFinalTextUnicodeEventHandle else { return }
        event.event.setIntegerValueField(.eventSourceUserData, value: userData)
    }

    func setTargetProcessIdentifier(
        _ processIdentifier: pid_t,
        for event: any FinalTextUnicodeEventHandle
    ) {
        guard let event = event as? SystemFinalTextUnicodeEventHandle else { return }
        event.targetProcessIdentifier = processIdentifier
    }

    func readbackEvent(_ expectation: FinalTextUnicodeReadback) -> Bool {
        guard let event = expectation.event as? SystemFinalTextUnicodeEventHandle,
              let expectedSource = expectation.source as? SystemFinalTextUnicodeEventSourceHandle,
              event.source === expectedSource,
              event.phase == expectation.expectedPhase,
              event.targetProcessIdentifier == expectation.expectedTargetProcessIdentifier,
              event.event.flags == expectation.expectedFlags,
              event.event.getIntegerValueField(.eventSourceUserData)
                == expectation.expectedUserData,
              event.event.getIntegerValueField(.eventSourceUnixProcessID)
                == Int64(expectation.expectedSourceProcessIdentifier) else {
            return false
        }

        guard expectation.expectedPhase == event.phase else { return false }
        guard expectation.expectedUTF16 == event.utf16 else { return false }
        guard expectation.expectedUTF16.isEmpty
                || readbackUnicodeString(from: event.event) == expectation.expectedUTF16 else {
            return false
        }
        return true
    }

    func postUnicodeEvent(
        _ event: any FinalTextUnicodeEventHandle,
        to processIdentifier: pid_t
    ) {
        guard let event = event as? SystemFinalTextUnicodeEventHandle else { return }
        event.event.postToPid(processIdentifier)
    }

    private func readbackUnicodeString(from event: CGEvent) -> [UInt16] {
        var actualLength = 0
        let capacity = max(1, TextInputSimulator.reviewMaximumUTF16CodeUnits)
        var buffer = [UniChar](repeating: 0, count: capacity)
        buffer.withUnsafeMutableBufferPointer { buffer in
            event.keyboardGetUnicodeString(
                maxStringLength: buffer.count,
                actualStringLength: &actualLength,
                unicodeString: buffer.baseAddress
            )
        }
        guard actualLength >= 0, actualLength <= buffer.count else { return [] }
        return Array(buffer.prefix(actualLength))
    }
}

@MainActor
private final class SystemFinalTextUnicodeEventSourceHandle: FinalTextUnicodeEventSourceHandle {
    let source: CGEventSource

    init(source: CGEventSource) {
        self.source = source
    }
}

@MainActor
private final class SystemFinalTextUnicodeEventHandle: FinalTextUnicodeEventHandle {
    let event: CGEvent
    let phase: FinalTextUnicodeEventPhase
    let utf16: [UInt16]
    let source: SystemFinalTextUnicodeEventSourceHandle
    let virtualKey: CGKeyCode?
    var targetProcessIdentifier: pid_t?

    init(
        event: CGEvent,
        phase: FinalTextUnicodeEventPhase,
        utf16: [UInt16],
        source: SystemFinalTextUnicodeEventSourceHandle,
        virtualKey: CGKeyCode? = nil
    ) {
        self.event = event
        self.phase = phase
        self.utf16 = utf16
        self.source = source
        self.virtualKey = virtualKey
    }
}

@MainActor
final class SystemSecureInputStateProvider: SecureInputStateProviding {
    func isSecureInputEnabled() -> Bool {
        IsSecureEventInputEnabled()
    }
}

@MainActor
final class SystemFrontmostProcessProvider: FrontmostProcessProviding {
    func frontmostProcessIdentifier() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}

enum TextInputSimulator {
    static let reviewMaximumUTF16CodeUnits = 16_384

    static func isSafeForAutomaticPaste(_ text: String) -> Bool {
        !text.unicodeScalars.contains { scalar in
            scalar.value < 0x20 || scalar.value == 0x7F || (0x80 ... 0x9F).contains(scalar.value)
        }
    }

    /// Review confirmation preserves the exact multiline draft. LF is the only
    /// control scalar admitted here; tabs, CR, NUL, DEL, and C1 controls remain
    /// rejected before destination validation or event construction.
    static func isSafeForReviewConfirmation(_ text: String) -> Bool {
        !text.unicodeScalars.contains { scalar in
            let value = scalar.value
            if value == 0x0A { return false }
            return value < 0x20 || value == 0x7F || (0x80 ... 0x9F).contains(value)
        }
    }

    static func isSafeForAutomaticKeyboardText(_ text: String) -> Bool {
        !text.unicodeScalars.contains { scalar in
            let value = scalar.value
            if value == 0x0A { return false }
            return value < 0x20 || value == 0x7F || (0x80 ... 0x9F).contains(value)
        }
    }

    static func isSafeForAutomaticKeyboardEventText(_ text: String) -> Bool {
        isSafeForAutomaticPaste(text)
    }
}
