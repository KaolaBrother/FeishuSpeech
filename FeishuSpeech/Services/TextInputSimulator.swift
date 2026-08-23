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
}

extension FinalTextOutput {
    /// Keeps pre-issue output implementations source-compatible while exposing the
    /// two-phase contract to review-first delivery. Concrete implementations should
    /// override this when they own the pasteboard and key-event boundary.
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
}

@MainActor
final class SystemFinalTextOutput: FinalTextOutput, ReviewCurrentFocusEnvironmentProviding {
    private typealias ReviewPasteboardSnapshot = [[String: Data]]

    private let pasteboardWriter: FinalTextPasteboardWriting
    private let keyEventPoster: FinalTextKeyEventPosting
    private let currentFocusEventPoster: FinalTextCurrentFocusEventPosting
    private let secureInputStateProvider: SecureInputStateProviding
    private let frontmostProcessProvider: FrontmostProcessProviding
    private let reviewPasteboardSnapshot: () -> ReviewPasteboardSnapshot
    private let reviewPasteboardChangeCount: () -> Int
    private let reviewPasteboardRestore: (ReviewPasteboardSnapshot, Int) -> Void
    private let reviewPasteboardRestoreScheduler: (@escaping () -> Void) -> Void

    init(
        pasteboardWriter: FinalTextPasteboardWriting,
        keyEventPoster: FinalTextKeyEventPosting,
        secureInputStateProvider: SecureInputStateProviding? = nil,
        frontmostProcessProvider: FrontmostProcessProviding? = nil,
        reviewPasteboardSnapshot: (() -> [[String: Data]])? = nil,
        reviewPasteboardChangeCount: (() -> Int)? = nil,
        reviewPasteboardRestore: (([[String: Data]], Int) -> Void)? = nil,
        reviewPasteboardRestoreScheduler: ((@escaping () -> Void) -> Void)? = nil
    ) {
        self.pasteboardWriter = pasteboardWriter
        self.keyEventPoster = keyEventPoster
        currentFocusEventPoster = SystemFinalTextCurrentFocusEventPoster()
        self.secureInputStateProvider = secureInputStateProvider ?? SystemSecureInputStateProvider()
        self.frontmostProcessProvider = frontmostProcessProvider ?? SystemFrontmostProcessProvider()
        self.reviewPasteboardSnapshot = reviewPasteboardSnapshot ?? {
            TextInputSimulator.captureReviewPasteboardSnapshot()
        }
        self.reviewPasteboardChangeCount = reviewPasteboardChangeCount ?? {
            NSPasteboard.general.changeCount
        }
        self.reviewPasteboardRestore = reviewPasteboardRestore ?? { snapshot, expectedChangeCount in
            TextInputSimulator.restoreReviewPasteboardSnapshot(
                snapshot,
                ifChangeCount: expectedChangeCount
            )
        }
        self.reviewPasteboardRestoreScheduler = reviewPasteboardRestoreScheduler ?? { operation in
            DispatchQueue.global(qos: .userInteractive).async {
                Thread.sleep(forTimeInterval: 1.0)
                operation()
            }
        }
    }

    init(
        pasteboardWriter: FinalTextPasteboardWriting,
        keyEventPoster: FinalTextKeyEventPosting,
        currentFocusEventPoster: FinalTextCurrentFocusEventPosting,
        secureInputStateProvider: SecureInputStateProviding,
        frontmostProcessProvider: FrontmostProcessProviding,
        reviewPasteboardSnapshot: (() -> [[String: Data]])? = nil,
        reviewPasteboardChangeCount: (() -> Int)? = nil,
        reviewPasteboardRestore: (([[String: Data]], Int) -> Void)? = nil,
        reviewPasteboardRestoreScheduler: ((@escaping () -> Void) -> Void)? = nil
    ) {
        self.pasteboardWriter = pasteboardWriter
        self.keyEventPoster = keyEventPoster
        self.currentFocusEventPoster = currentFocusEventPoster
        self.secureInputStateProvider = secureInputStateProvider
        self.frontmostProcessProvider = frontmostProcessProvider
        self.reviewPasteboardSnapshot = reviewPasteboardSnapshot ?? {
            TextInputSimulator.captureReviewPasteboardSnapshot()
        }
        self.reviewPasteboardChangeCount = reviewPasteboardChangeCount ?? {
            NSPasteboard.general.changeCount
        }
        self.reviewPasteboardRestore = reviewPasteboardRestore ?? { snapshot, expectedChangeCount in
            TextInputSimulator.restoreReviewPasteboardSnapshot(
                snapshot,
                ifChangeCount: expectedChangeCount
            )
        }
        self.reviewPasteboardRestoreScheduler = reviewPasteboardRestoreScheduler ?? { operation in
            DispatchQueue.global(qos: .userInteractive).async {
                Thread.sleep(forTimeInterval: 1.0)
                operation()
            }
        }
    }

    convenience init() {
        self.init(
            pasteboardWriter: SystemFinalTextPasteboardWriter(),
            keyEventPoster: SystemFinalTextKeyEventPoster(),
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
        guard TextInputSimulator.isSafeForAutomaticPaste(text) else {
            return .deliveryFailed
        }
        do {
            guard try validateDestination() else { return .destinationInvalid }
        } catch {
            return .destinationInvalid
        }
        guard pasteboardWriter.replaceContents(with: text),
              keyEventPoster.postCommandV(to: destination.processIdentifier) else {
            return .deliveryFailed
        }
        do {
            return try validateDestination() ? .inserted : .destinationInvalid
        } catch {
            return .destinationInvalid
        }
    }

    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateBeforeMutation: () throws -> Bool,
        validateAfterPosting: () throws -> Bool
    ) -> FinalTextInsertionResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              TextInputSimulator.isSafeForReviewConfirmation(text) else {
            return .deliveryFailed
        }
        return performReviewPaste(
            text,
            processIdentifier: destination.processIdentifier,
            validateBeforeMutation: {
                do {
                    return try validateBeforeMutation() ? .valid : .destinationInvalid
                } catch {
                    return .destinationInvalid
                }
            },
            validateAfterPosting: {
                do {
                    return try validateAfterPosting() ? .valid : .destinationInvalid
                } catch {
                    return .destinationInvalid
                }
            }
        )
    }

    func insertReviewAtCurrentFocusOnce(
        _ text: String,
        processIdentifier: pid_t,
        validateBeforeMutation: () -> ReviewCurrentFocusValidation,
        validateAfterPosting: () -> ReviewCurrentFocusValidation
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

        return performReviewPaste(
            text,
            processIdentifier: processIdentifier,
            validateBeforeMutation: { preflightResult },
            validateAfterPosting: validateAfterPosting
        )
    }

    private func performReviewPaste(
        _ text: String,
        processIdentifier: pid_t,
        validateBeforeMutation: () -> ReviewCurrentFocusValidation,
        validateAfterPosting: () -> ReviewCurrentFocusValidation
    ) -> FinalTextInsertionResult {
        let preflightResult = validateBeforeMutation()
        guard preflightResult == .valid else {
            return finalTextInsertionResult(for: preflightResult)
        }

        let reviewPasteboardSnapshot = reviewPasteboardSnapshot()
        guard pasteboardWriter.replaceContents(with: text) else {
            return .deliveryFailed
        }
        let postWriteChangeCount = reviewPasteboardChangeCount()
        guard keyEventPoster.postCommandV(to: processIdentifier) else {
            return .deliveryUncertain
        }

        guard validateAfterPosting() == .valid else {
            return .deliveryUncertain
        }
        scheduleReviewPasteboardRestore(
            reviewPasteboardSnapshot,
            expectedChangeCount: postWriteChangeCount
        )
        return .inserted
    }

    private func finalTextInsertionResult(
        for validation: ReviewCurrentFocusValidation
    ) -> FinalTextInsertionResult {
        switch validation {
        case .valid:
            return .inserted
        case .securityRejected:
            return .securityRejected
        case .identityChanged:
            return .identityChanged
        case .destinationInvalid:
            return .destinationInvalid
        }
    }

    private func scheduleReviewPasteboardRestore(
        _ snapshot: ReviewPasteboardSnapshot,
        expectedChangeCount: Int
    ) {
        let changeCount = reviewPasteboardChangeCount
        let restore = reviewPasteboardRestore
        reviewPasteboardRestoreScheduler {
            guard changeCount() == expectedChangeCount else {
                logger.debug("Review pasteboard changed after insertion; skipping restoration")
                return
            }
            restore(snapshot, expectedChangeCount)
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
    func replaceContents(with text: String) -> Bool
}

@MainActor
protocol FinalTextKeyEventPosting: AnyObject {
    func postCommandV(to processIdentifier: pid_t) -> Bool
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
}

nonisolated enum FeishuSpeechSyntheticEventTag {
    static let value: Int64 = 0x4653_5350_4545_4348
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

@MainActor
private final class SystemFinalTextPasteboardWriter: FinalTextPasteboardWriting {
    func replaceContents(with text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

@MainActor
private final class SystemFinalTextKeyEventPoster: FinalTextKeyEventPosting {
    func postCommandV(to processIdentifier: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
        return true
    }
}

@MainActor
final class SystemFinalTextCurrentFocusEventPoster: FinalTextCurrentFocusEventPosting {
    private let backend: FinalTextUnicodeEventBackend
    private let secureInputStateProvider: SecureInputStateProviding

    convenience init() {
        self.init(
            backend: SystemFinalTextUnicodeEventBackend(),
            secureInputStateProvider: SystemSecureInputStateProvider()
        )
    }

    init(
        backend: FinalTextUnicodeEventBackend,
        secureInputStateProvider: SecureInputStateProviding
    ) {
        self.backend = backend
        self.secureInputStateProvider = secureInputStateProvider
    }

    func postUnicodeText(
        _ text: String,
        to processIdentifier: pid_t
    ) -> FinalTextCurrentFocusPostResult {
        postReplacement(
            deleteCharacterCount: 0,
            insertText: text,
            to: processIdentifier
        )
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
        event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        return SystemFinalTextUnicodeEventHandle(event: event)
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
        return SystemFinalTextUnicodeEventHandle(event: event)
    }

    func setUserData(
        _ userData: Int64,
        for event: any FinalTextUnicodeEventHandle
    ) {
        guard let event = event as? SystemFinalTextUnicodeEventHandle else { return }
        event.event.setIntegerValueField(.eventSourceUserData, value: userData)
    }

    func postUnicodeEvent(
        _ event: any FinalTextUnicodeEventHandle,
        to processIdentifier: pid_t
    ) {
        guard let event = event as? SystemFinalTextUnicodeEventHandle else { return }
        event.event.postToPid(processIdentifier)
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

    init(event: CGEvent) {
        self.event = event
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
    static func isSafeForAutomaticPaste(_ text: String) -> Bool {
        !text.unicodeScalars.contains { scalar in
            scalar.value < 0x20 || scalar.value == 0x7F || (0x80 ... 0x9F).contains(scalar.value)
        }
    }

    /// Review confirmation preserves the exact multiline draft. LF is the only
    /// control scalar admitted here; tabs, CR, NUL, DEL, and C1 controls remain
    /// rejected before any destination or pasteboard mutation.
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

    /// Captures all data-bearing types from every existing pasteboard item for
    /// the review-confirmation transaction.
    fileprivate static func captureReviewPasteboardSnapshot() -> [[String: Data]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var dataByType: [String: Data] = [:]
            for pasteboardType in item.types {
                if let data = item.data(forType: pasteboardType) {
                    dataByType[pasteboardType.rawValue] = data
                }
            }
            return dataByType
        }
    }

    /// Restores the full review snapshot only while the paste written by this
    /// process is still the current pasteboard contents.
    fileprivate static func restoreReviewPasteboardSnapshot(
        _ snapshot: [[String: Data]],
        ifChangeCount expectedChangeCount: Int
    ) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount == expectedChangeCount else {
            logger.debug("Review pasteboard changed before restoration; leaving it untouched")
            return
        }

        let restoredItems = snapshot.map { dataByType -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (rawType, data) in dataByType {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawValue: rawType))
            }
            return item
        }
        pasteboard.clearContents()
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
        logger.debug("Restored \(restoredItems.count) review pasteboard item(s)")
    }

}
