import AppKit
import Foundation
import os.log
import XCTest

@testable import FeishuSpeech

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "ReviewPasteboardLifecycleTests"
)

/// RED contract for the review-only paste transaction.
///
/// The production output must expose an injectable snapshot/change-count/
/// restoration scheduler seam. These tests deliberately do not use the real
/// pasteboard or wall-clock polling: the fake models all original items,
/// third-party change-count races, and a deterministic bounded opportunity.
@MainActor
final class ReviewPasteboardLifecycleTests: XCTestCase {
    func test_successfulReviewPasteRestoresAllPriorItemsAfterBoundedOpportunity() {
        logger.debug("checking review pasteboard restoration")
        let pasteboard = Issue38ReviewPasteboardLifecycleWriter()
        let scheduler = Issue38ReviewPasteboardRestoreScheduler()
        let keyPoster = Issue38ReviewPasteboardKeyPoster()
        let output = makeOutput(
            pasteboard: pasteboard,
            scheduler: scheduler,
            keyPoster: keyPoster
        )
        let priorItems = pasteboard.items

        let result = output.insertOnce(
            "PRIVATE_SUCCESS_DRAFT",
            destination: Issue38ReviewPasteboardFixtures.destination,
            validateBeforeMutation: { true },
            validateAfterPosting: { true }
        )

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(pasteboard.items, [Issue38ReviewPasteboardItem.draft("PRIVATE_SUCCESS_DRAFT")])
        XCTAssertEqual(pasteboard.writeCount, 1)
        XCTAssertEqual(keyPoster.processIdentifiers, [42])
        XCTAssertEqual(scheduler.pendingCount, 1)

        scheduler.runNext()

        XCTAssertEqual(pasteboard.items, priorItems)
        XCTAssertEqual(pasteboard.restoreCount, 1)
        XCTAssertEqual(pasteboard.writtenTexts, ["PRIVATE_SUCCESS_DRAFT"])
    }

    func test_successfulReviewPasteNeverOverwritesThirdPartyClipboardChange() {
        let pasteboard = Issue38ReviewPasteboardLifecycleWriter()
        let scheduler = Issue38ReviewPasteboardRestoreScheduler()
        let keyPoster = Issue38ReviewPasteboardKeyPoster()
        let output = makeOutput(
            pasteboard: pasteboard,
            scheduler: scheduler,
            keyPoster: keyPoster
        )

        let result = output.insertOnce(
            "PRIVATE_SUCCESS_DRAFT",
            destination: Issue38ReviewPasteboardFixtures.destination,
            validateBeforeMutation: { true },
            validateAfterPosting: { true }
        )
        XCTAssertEqual(result, .inserted)

        pasteboard.externalWrite(
            [Issue38ReviewPasteboardItem(type: "public.text", data: Data("THIRD_PARTY".utf8))]
        )
        scheduler.runNext()

        XCTAssertEqual(
            pasteboard.items,
            [Issue38ReviewPasteboardItem(type: "public.text", data: Data("THIRD_PARTY".utf8))]
        )
        XCTAssertEqual(pasteboard.restoreCount, 0)
    }

    func test_successfulApplicationBoundReviewPasteUsesSameSnapshotAndRestoresMultilineDraft() {
        let pasteboard = Issue38ReviewPasteboardLifecycleWriter()
        let scheduler = Issue38ReviewPasteboardRestoreScheduler()
        let keyPoster = Issue38ReviewPasteboardKeyPoster()
        let output = makeOutput(
            pasteboard: pasteboard,
            scheduler: scheduler,
            keyPoster: keyPoster
        )
        let priorItems = pasteboard.items
        let draft = "first line\nsecond line"

        let result = output.insertReviewAtCurrentFocusOnce(
            draft,
            processIdentifier: 42,
            validateBeforeMutation: { .valid },
            validateAfterPosting: { .valid }
        )

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(pasteboard.items, [Issue38ReviewPasteboardItem.draft(draft)])
        XCTAssertEqual(pasteboard.writtenTexts, [draft])
        XCTAssertEqual(pasteboard.writeCount, 1)
        XCTAssertEqual(keyPoster.processIdentifiers, [42])
        XCTAssertEqual(scheduler.pendingCount, 1)

        scheduler.runNext()

        XCTAssertEqual(pasteboard.items, priorItems)
        XCTAssertEqual(pasteboard.restoreCount, 1)
    }

    func test_applicationBoundReviewPastePostflightUncertaintyDoesNotRestoreOrRetry() {
        let pasteboard = Issue38ReviewPasteboardLifecycleWriter()
        let scheduler = Issue38ReviewPasteboardRestoreScheduler()
        let keyPoster = Issue38ReviewPasteboardKeyPoster()
        let output = makeOutput(
            pasteboard: pasteboard,
            scheduler: scheduler,
            keyPoster: keyPoster
        )

        let result = output.insertReviewAtCurrentFocusOnce(
            "PRIVATE_FALLBACK_UNCERTAIN",
            processIdentifier: 42,
            validateBeforeMutation: { .valid },
            validateAfterPosting: { .destinationInvalid }
        )

        XCTAssertEqual(result, .deliveryUncertain)
        XCTAssertEqual(pasteboard.writtenTexts, ["PRIVATE_FALLBACK_UNCERTAIN"])
        XCTAssertEqual(keyPoster.processIdentifiers, [42])
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(pasteboard.restoreCount, 0)
    }

    func test_preflightFailureDoesNotSnapshotMutateScheduleOrRestore() {
        let pasteboard = Issue38ReviewPasteboardLifecycleWriter()
        let scheduler = Issue38ReviewPasteboardRestoreScheduler()
        let keyPoster = Issue38ReviewPasteboardKeyPoster()
        let output = makeOutput(
            pasteboard: pasteboard,
            scheduler: scheduler,
            keyPoster: keyPoster
        )
        let priorItems = pasteboard.items
        let priorChangeCount = pasteboard.changeCount

        let result = output.insertOnce(
            "PRIVATE_PREFLIGHT_DRAFT",
            destination: Issue38ReviewPasteboardFixtures.destination,
            validateBeforeMutation: { false },
            validateAfterPosting: { XCTFail("postflight must not run"); return false }
        )

        XCTAssertEqual(result, .destinationInvalid)
        XCTAssertEqual(pasteboard.items, priorItems)
        XCTAssertEqual(pasteboard.changeCount, priorChangeCount)
        XCTAssertEqual(pasteboard.writeCount, 0)
        XCTAssertEqual(keyPoster.processIdentifiers, [])
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(pasteboard.restoreCount, 0)
    }

    func test_keyPostUncertaintyIsTerminalAndLeavesFrozenDraftForManualRecovery() {
        let pasteboard = Issue38ReviewPasteboardLifecycleWriter()
        let scheduler = Issue38ReviewPasteboardRestoreScheduler()
        let keyPoster = Issue38ReviewPasteboardKeyPoster(shouldPost: false)
        let output = makeOutput(
            pasteboard: pasteboard,
            scheduler: scheduler,
            keyPoster: keyPoster
        )

        let result = output.insertOnce(
            "PRIVATE_KEY_POST_UNCERTAIN",
            destination: Issue38ReviewPasteboardFixtures.destination,
            validateBeforeMutation: { true },
            validateAfterPosting: { XCTFail("postflight must not run after key-post uncertainty"); return true }
        )

        XCTAssertEqual(result, .deliveryUncertain)
        XCTAssertEqual(pasteboard.writtenTexts, ["PRIVATE_KEY_POST_UNCERTAIN"])
        XCTAssertEqual(keyPoster.processIdentifiers, [42])
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(
            pasteboard.items,
            [Issue38ReviewPasteboardItem.draft("PRIVATE_KEY_POST_UNCERTAIN")],
            "uncertain delivery leaves the frozen draft available for the one manual-recovery copy"
        )
    }

    func test_postflightUncertaintyIsTerminalAndNeverRetriesOrRestoresAutomatically() {
        let pasteboard = Issue38ReviewPasteboardLifecycleWriter()
        let scheduler = Issue38ReviewPasteboardRestoreScheduler()
        let keyPoster = Issue38ReviewPasteboardKeyPoster()
        let output = makeOutput(
            pasteboard: pasteboard,
            scheduler: scheduler,
            keyPoster: keyPoster
        )

        let result = output.insertOnce(
            "PRIVATE_POSTFLIGHT_UNCERTAIN",
            destination: Issue38ReviewPasteboardFixtures.destination,
            validateBeforeMutation: { true },
            validateAfterPosting: { false }
        )

        XCTAssertEqual(result, .deliveryUncertain)
        XCTAssertEqual(pasteboard.writtenTexts, ["PRIVATE_POSTFLIGHT_UNCERTAIN"])
        XCTAssertEqual(keyPoster.processIdentifiers, [42])
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(pasteboard.restoreCount, 0)
        XCTAssertEqual(
            pasteboard.items,
            [Issue38ReviewPasteboardItem.draft("PRIVATE_POSTFLIGHT_UNCERTAIN")]
        )
    }

    private func makeOutput(
        pasteboard: Issue38ReviewPasteboardLifecycleWriter,
        scheduler: Issue38ReviewPasteboardRestoreScheduler,
        keyPoster: Issue38ReviewPasteboardKeyPoster
    ) -> SystemFinalTextOutput {
        SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: keyPoster,
            reviewPasteboardSnapshot: { pasteboard.snapshot() },
            reviewPasteboardChangeCount: { pasteboard.changeCount },
            reviewPasteboardRestore: { snapshot, expectedChangeCount in
                pasteboard.restore(snapshot, ifChangeCount: expectedChangeCount)
            },
            reviewPasteboardRestoreScheduler: { operation in
                scheduler.schedule(operation)
            }
        )
    }
}

@MainActor
private enum Issue38ReviewPasteboardFixtures {
    static let destination = CursorDestinationToken(
        generation: 38,
        processIdentifier: 42,
        element: AXUIElementCreateApplication(42),
        originalSelection: CursorTextRange(location: 3, length: 0)
    )
}

@MainActor
private struct Issue38ReviewPasteboardItem: Equatable {
    let type: String
    let data: Data

    static func draft(_ text: String) -> Self {
        Self(type: "public.utf8-plain-text", data: Data(text.utf8))
    }
}

@MainActor
private final class Issue38ReviewPasteboardLifecycleWriter: FinalTextPasteboardWriting {
    private(set) var items = [
        Issue38ReviewPasteboardItem(type: "public.utf8-plain-text", data: Data("OLD_TEXT".utf8)),
        Issue38ReviewPasteboardItem(type: "com.example.rich", data: Data([0xCA, 0xFE]))
    ]
    private(set) var changeCount = 17
    private(set) var writtenTexts: [String] = []
    private(set) var writeCount = 0
    private(set) var restoreCount = 0

    func replaceContents(with text: String) -> Bool {
        writtenTexts.append(text)
        writeCount += 1
        items = [.draft(text)]
        changeCount += 1
        return true
    }

    func snapshot() -> [[String: Data]] {
        items.map { [$0.type: $0.data] }
    }

    func restore(_ snapshot: [[String: Data]], ifChangeCount expectedChangeCount: Int) {
        guard changeCount == expectedChangeCount else { return }
        items = snapshot.flatMap { item in
            item.map { Issue38ReviewPasteboardItem(type: $0.key, data: $0.value) }
        }
        restoreCount += 1
        changeCount += 1
    }

    func externalWrite(_ newItems: [Issue38ReviewPasteboardItem]) {
        items = newItems
        changeCount += 1
    }
}

@MainActor
private final class Issue38ReviewPasteboardRestoreScheduler {
    private var operations: [() -> Void] = []

    var pendingCount: Int { operations.count }

    func schedule(_ operation: @escaping () -> Void) {
        operations.append(operation)
    }

    func runNext() {
        precondition(!operations.isEmpty)
        operations.removeFirst()()
    }
}

@MainActor
private final class Issue38ReviewPasteboardKeyPoster: FinalTextKeyEventPosting {
    let shouldPost: Bool
    private(set) var processIdentifiers: [pid_t] = []

    init(shouldPost: Bool = true) {
        self.shouldPost = shouldPost
    }

    func postCommandV(to processIdentifier: pid_t) -> Bool {
        processIdentifiers.append(processIdentifier)
        return shouldPost
    }
}
