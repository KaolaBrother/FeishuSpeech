import AppKit
import Foundation
import UserNotifications

import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "TextInputSimulator")

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

    static func insertText(_ text: String) {
        insertTextViaPasteboard(text)
    }

    static func insertTextViaPasteboard(_ text: String) {
        let sanitized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else {
            logger.warning("insertTextViaPasteboard called with empty/whitespace-only text — skipping")
            return
        }

        let pasteboard = NSPasteboard.general

        // 1. Deep-copy ALL current pasteboard items before overwriting.
        let snapshot = captureSnapshot(pasteboard)

        // 2. Write the recognised text and record the post-write changeCount.
        pasteboard.clearContents()
        pasteboard.setString(sanitized, forType: .string)
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

    // MARK: - Private helpers

    /// Captures every item and every type currently on the pasteboard.
    private static func captureSnapshot(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let changeCountBefore = pasteboard.changeCount
        var items: [PasteboardSnapshot.Item] = []

        for pbItem in pasteboard.pasteboardItems ?? [] {
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
            for type_ in pbItem.types {
                if let data = pbItem.data(forType: type_) {
                    dataByType[type_] = data
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
            for (type_, data) in snapshotItem.dataByType {
                pbItem.setData(data, forType: type_)
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
