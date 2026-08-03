import AppKit
import Carbon
import Foundation
import UserNotifications

import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "TextInputSimulator")

@MainActor
protocol FinalTextOutput: AnyObject {
    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateDestination: () throws -> Bool
    ) -> FinalTextInsertionResult
    func insertAtCurrentFocusOnce(_ text: String) -> FinalTextInsertionResult
    func copyForManualRecovery(_ text: String)
}

@MainActor
final class SystemFinalTextOutput: FinalTextOutput {
    private let pasteboardWriter: FinalTextPasteboardWriting
    private let keyEventPoster: FinalTextKeyEventPosting
    private let currentFocusEventPoster: FinalTextCurrentFocusEventPosting
    private let secureInputStateProvider: SecureInputStateProviding
    private let frontmostProcessProvider: FrontmostProcessProviding

    init(
        pasteboardWriter: FinalTextPasteboardWriting,
        keyEventPoster: FinalTextKeyEventPosting
    ) {
        self.pasteboardWriter = pasteboardWriter
        self.keyEventPoster = keyEventPoster
        currentFocusEventPoster = SystemFinalTextCurrentFocusEventPoster()
        secureInputStateProvider = SystemSecureInputStateProvider()
        frontmostProcessProvider = SystemFrontmostProcessProvider()
    }

    init(
        pasteboardWriter: FinalTextPasteboardWriting,
        keyEventPoster: FinalTextKeyEventPosting,
        currentFocusEventPoster: FinalTextCurrentFocusEventPosting,
        secureInputStateProvider: SecureInputStateProviding,
        frontmostProcessProvider: FrontmostProcessProviding
    ) {
        self.pasteboardWriter = pasteboardWriter
        self.keyEventPoster = keyEventPoster
        self.currentFocusEventPoster = currentFocusEventPoster
        self.secureInputStateProvider = secureInputStateProvider
        self.frontmostProcessProvider = frontmostProcessProvider
    }

    convenience init() {
        self.init(
            pasteboardWriter: SystemFinalTextPasteboardWriter(),
            keyEventPoster: SystemFinalTextKeyEventPoster()
        )
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
        switch currentFocusEventPoster.postUnicodeText(text) {
        case .posted:
            return .inserted
        case .securityRejected:
            return .securityRejected
        case .deliveryFailed:
            return .deliveryFailed
        }
    }

    func copyForManualRecovery(_ text: String) {
        TextInputSimulator.copyForManualRecovery(text)
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
    func postUnicodeText(_ text: String) -> FinalTextCurrentFocusPostResult
}

nonisolated enum FinalTextCurrentFocusPostResult: Equatable, Sendable {
    case posted
    case securityRejected
    case deliveryFailed
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
private final class SystemFinalTextCurrentFocusEventPoster: FinalTextCurrentFocusEventPosting {
    func postUnicodeText(_ text: String) -> FinalTextCurrentFocusPostResult {
        let utf16 = Array(text.utf16)
        guard !utf16.isEmpty,
              let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
            return .deliveryFailed
        }
        event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        guard !IsSecureEventInputEnabled() else { return .securityRejected }
        event.post(tap: .cghidEventTap)
        return .posted
    }
}

@MainActor
private final class SystemSecureInputStateProvider: SecureInputStateProviding {
    func isSecureInputEnabled() -> Bool {
        IsSecureEventInputEnabled()
    }
}

@MainActor
private final class SystemFrontmostProcessProvider: FrontmostProcessProviding {
    func frontmostProcessIdentifier() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}

/// Snapshot of ALL pasteboard items before we overwrite the board.
private struct PasteboardSnapshot {
    struct Item {
        let dataByType: [NSPasteboard.PasteboardType: Data]
    }
    let items: [Item]
    let changeCountBeforeWrite: Int
}

enum TextInputSimulator {
    /// Maximum poll iterations waiting for the paste consumer.
    private static let maxPollIterations = 20
    /// Polling interval between changeCount checks.
    private static let pollIntervalSeconds: Double = 0.05

    static func isSafeForAutomaticPaste(_ text: String) -> Bool {
        !text.unicodeScalars.contains { scalar in
            scalar.value < 0x20 || scalar.value == 0x7F || (0x80 ... 0x9F).contains(scalar.value)
        }
    }

    static func insertText(_ text: String) {
        insertTextViaPasteboard(text)
    }

    static func insertTextViaPasteboard(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.warning("insertTextViaPasteboard called with empty/whitespace-only text — skipping")
            return
        }
        guard isSafeForAutomaticPaste(text) else {
            logger.warning("Automatic paste rejected action-capable control characters")
            copyForManualRecovery(text)
            showFallbackNotification()
            return
        }

        let pasteboard = NSPasteboard.general

        // 1. Deep-copy ALL current pasteboard items before overwriting.
        let snapshot = captureSnapshot(pasteboard)

        // 2. Write the recognised text and record the post-write changeCount.
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let postWriteChangeCount = pasteboard.changeCount
        logger.debug("Pasteboard written; changeCount after write = \(postWriteChangeCount)")

        // 3. Post Cmd+V, then wait for consumption before restoring.
        let pasted = simulateCommandV()
        guard pasted else {
            // CGEvent creation failed; leave text on clipboard and notify.
            logger.error("simulateCommandV failed — leaving text on clipboard and notifying user")
            showFallbackNotification()
            return
        }

        DispatchQueue.global(qos: .userInteractive).async {
            var consumed = false
            for _ in 0 ..< maxPollIterations {
                Thread.sleep(forTimeInterval: pollIntervalSeconds)
                if pasteboard.changeCount != postWriteChangeCount {
                    consumed = true
                    break
                }
            }

            if !consumed {
                logger.warning("Pasteboard changeCount unchanged after polling; restoring clipboard anyway")
            } else {
                logger.debug("Paste consumed (changeCount advanced); restoring saved clipboard")
            }

            restoreSnapshot(snapshot, to: pasteboard)
        }
    }

    /// Keeps the exact recognized value available for a manual paste without
    /// posting keyboard events or restoring the previous clipboard contents.
    static func copyForManualRecovery(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.warning("copyForManualRecovery called with empty/whitespace-only text — skipping")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        logger.info("Recovery text copied to pasteboard")
    }

    // MARK: - Private helpers

    /// Captures every item and every type currently on the pasteboard.
    private static func captureSnapshot(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let changeCountBefore = pasteboard.changeCount
        var items: [PasteboardSnapshot.Item] = []

        for pbItem in pasteboard.pasteboardItems ?? [] {
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
            for pasteboardType in pbItem.types {
                if let data = pbItem.data(forType: pasteboardType) {
                    dataByType[pasteboardType] = data
                }
            }
            if !dataByType.isEmpty {
                items.append(PasteboardSnapshot.Item(dataByType: dataByType))
            }
        }
        logger.debug("Captured \(items.count) pasteboard item(s) (changeCount = \(changeCountBefore))")
        return PasteboardSnapshot(items: items, changeCountBeforeWrite: changeCountBefore)
    }

    /// Restores a previously captured snapshot back to the pasteboard.
    private static func restoreSnapshot(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        guard !snapshot.items.isEmpty else {
            logger.debug("Snapshot was empty — nothing to restore")
            return
        }

        let newItems = snapshot.items.map { snapshotItem -> NSPasteboardItem in
            let pbItem = NSPasteboardItem()
            for (pasteboardType, data) in snapshotItem.dataByType {
                pbItem.setData(data, forType: pasteboardType)
            }
            return pbItem
        }

        pasteboard.clearContents()
        pasteboard.writeObjects(newItems)
        logger.debug("Restored \(newItems.count) pasteboard item(s)")
    }

    /// Posts a synthetic Cmd+V key-down/up pair via CGEvent. Returns false if event creation fails.
    @discardableResult
    private static func simulateCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            logger.error("Failed to create CGEventSource")
            return false
        }
        let vKeyCode: CGKeyCode = 9

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else {
            logger.error("Failed to create CGEvent for Cmd+V")
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        logger.debug("Cmd+V events posted")
        return true
    }

    /// Shows a brief notification informing the user that text was copied to the clipboard.
    private static func showFallbackNotification() {
        let content = UNMutableNotificationContent()
        content.title = "FeishuSpeech"
        content.body = "已复制到剪贴板"

        let request = UNNotificationRequest(
            identifier: "com.feishuspeech.clipboard-fallback",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.warning("Fallback notification could not be delivered: \(error.localizedDescription)")
            } else {
                logger.info("Fallback notification delivered")
            }
        }
    }
}
