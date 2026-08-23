import AppKit
import Foundation
import os.log
import XCTest

@testable import FeishuSpeech

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "ReviewPasteboardLifecycleTests"
)

/// RED contract for the v4 review-only output transaction.
///
/// Review confirmation must never use the general pasteboard or Cmd+V. These
/// tests deliberately do not use the real pasteboard or wall-clock polling:
/// the fake records every prohibited snapshot/read/write/restore/scheduler
/// collaborator and every legacy targeted Cmd+V attempt.
@MainActor
final class ReviewPasteboardLifecycleTests: XCTestCase {
    func test_successfulReviewConfirmationNeverTouchesPasteboardOrCmdV() {
        logger.debug("checking review text-only output")
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

        XCTAssertEqual(result, .submittedUnverified)
        XCTAssertEqual(pasteboard.snapshotCount, 0)
        XCTAssertEqual(pasteboard.changeCountReadCount, 0)
        XCTAssertEqual(pasteboard.writeCount, 0)
        XCTAssertEqual(pasteboard.restoreCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(keyPoster.processIdentifiers, [])
    }

    func test_successfulReviewConfirmationLeavesImageOnlyClipboardUntouched() {
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
            "PRIVATE_SUCCESS_DRAFT",
            destination: Issue38ReviewPasteboardFixtures.destination,
            validateBeforeMutation: { true },
            validateAfterPosting: { true }
        )
        XCTAssertEqual(result, .submittedUnverified)
        XCTAssertEqual(pasteboard.items, priorItems)
        XCTAssertEqual(pasteboard.changeCount, priorChangeCount)
        XCTAssertEqual(pasteboard.snapshotCount, 0)
        XCTAssertEqual(pasteboard.changeCountReadCount, 0)
        XCTAssertEqual(pasteboard.writeCount, 0)
        XCTAssertEqual(pasteboard.restoreCount, 0)
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(keyPoster.processIdentifiers, [])
    }

    func test_successfulApplicationBoundReviewConfirmationNeverTouchesPasteboardOrCmdV() {
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
        let draft = "first line\nsecond line"

        let result = output.insertReviewAtCurrentFocusOnce(
            draft,
            processIdentifier: 42,
            validateBeforeMutation: { .valid },
            validateAfterPosting: { .valid }
        )

        XCTAssertEqual(result, .submittedUnverified)
        XCTAssertEqual(pasteboard.items, priorItems)
        XCTAssertEqual(pasteboard.changeCount, priorChangeCount)
        XCTAssertEqual(pasteboard.snapshotCount, 0)
        XCTAssertEqual(pasteboard.changeCountReadCount, 0)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(pasteboard.writeCount, 0)
        XCTAssertEqual(pasteboard.restoreCount, 0)
        XCTAssertEqual(keyPoster.processIdentifiers, [])
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func test_applicationBoundReviewConfirmationPostflightUncertaintyDoesNotTouchPasteboardOrRetry() {
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
        XCTAssertEqual(pasteboard.snapshotCount, 0)
        XCTAssertEqual(pasteboard.changeCountReadCount, 0)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(keyPoster.processIdentifiers, [])
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
        XCTAssertEqual(pasteboard.snapshotCount, 0)
        XCTAssertEqual(pasteboard.changeCountReadCount, 0)
        XCTAssertEqual(pasteboard.writeCount, 0)
        XCTAssertEqual(keyPoster.processIdentifiers, [])
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(pasteboard.restoreCount, 0)
    }

    func test_keyPostUncertaintyIsTerminalAndLeavesFrozenDraftForManualRecovery() {
        let pasteboard = Issue38ReviewPasteboardLifecycleWriter()
        let scheduler = Issue38ReviewPasteboardRestoreScheduler()
        let keyPoster = Issue38ReviewPasteboardKeyPoster(shouldPost: false)
        let unicodePoster = Issue40ReviewPasteboardUnicodePoster(
            result: .submittedUnverified(.uncertain)
        )
        let output = makeOutput(
            pasteboard: pasteboard,
            scheduler: scheduler,
            keyPoster: keyPoster,
            unicodePoster: unicodePoster
        )
        let priorItems = pasteboard.items
        let priorChangeCount = pasteboard.changeCount

        let result = output.insertOnce(
            "PRIVATE_KEY_POST_UNCERTAIN",
            destination: Issue38ReviewPasteboardFixtures.destination,
            validateBeforeMutation: { true },
            validateAfterPosting: { XCTFail("postflight must not run after key-post uncertainty"); return true }
        )

        XCTAssertEqual(result, .deliveryUncertain)
        XCTAssertEqual(pasteboard.snapshotCount, 0)
        XCTAssertEqual(pasteboard.changeCountReadCount, 0)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(keyPoster.processIdentifiers, [])
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(
            pasteboard.items,
            priorItems,
            "uncertain delivery must not replace or read the user clipboard"
        )
        XCTAssertEqual(pasteboard.changeCount, priorChangeCount)
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
        let priorItems = pasteboard.items
        let priorChangeCount = pasteboard.changeCount

        let result = output.insertOnce(
            "PRIVATE_POSTFLIGHT_UNCERTAIN",
            destination: Issue38ReviewPasteboardFixtures.destination,
            validateBeforeMutation: { true },
            validateAfterPosting: { false }
        )

        XCTAssertEqual(result, .deliveryUncertain)
        XCTAssertEqual(pasteboard.snapshotCount, 0)
        XCTAssertEqual(pasteboard.changeCountReadCount, 0)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(keyPoster.processIdentifiers, [])
        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(pasteboard.restoreCount, 0)
        XCTAssertEqual(pasteboard.items, priorItems)
        XCTAssertEqual(pasteboard.changeCount, priorChangeCount)
    }

    private func makeOutput(
        pasteboard: Issue38ReviewPasteboardLifecycleWriter,
        scheduler: Issue38ReviewPasteboardRestoreScheduler,
        keyPoster: Issue38ReviewPasteboardKeyPoster,
        unicodePoster: Issue40ReviewPasteboardUnicodePoster? = nil
    ) -> SystemFinalTextOutput {
        let unicodePoster = unicodePoster ?? Issue40ReviewPasteboardUnicodePoster()
        return SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: keyPoster,
            currentFocusEventPoster: unicodePoster,
            secureInputStateProvider: Issue40ReviewPasteboardSecureInputProvider(),
            frontmostProcessProvider: Issue40ReviewPasteboardFrontmostProcessProvider()
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
    private(set) var snapshotCount = 0
    private(set) var changeCountReadCount = 0

    func replaceContents(with text: String) -> Bool {
        writtenTexts.append(text)
        writeCount += 1
        items = [.draft(text)]
        changeCount += 1
        return true
    }

    func snapshot() -> [[String: Data]] {
        snapshotCount += 1
        return items.map { [$0.type: $0.data] }
    }

    func readChangeCount() -> Int {
        changeCountReadCount += 1
        return changeCount
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

@MainActor
private final class Issue40ReviewPasteboardUnicodePoster: FinalTextCurrentFocusEventPosting {
    let result: ReviewUnicodeOutputResult
    private(set) var requestedTexts: [String] = []
    private(set) var processIdentifiers: [pid_t] = []

    init(result: ReviewUnicodeOutputResult = .submittedUnverified(.valid)) {
        self.result = result
    }

    func postUnicodeText(
        _ text: String,
        to processIdentifier: pid_t
    ) -> FinalTextCurrentFocusPostResult {
        requestedTexts.append(text)
        processIdentifiers.append(processIdentifier)
        switch result {
        case .failedBeforeSubmission(.secureInput):
            return .securityRejected
        case .failedBeforeSubmission, .cancelledBeforeSubmission:
            return .deliveryFailed
        case .submittedUnverified:
            return .posted
        }
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
        guard pairGate({
            _ = self.postUnicodeText(text, to: processIdentifier)
        }) else {
            return .failedBeforeSubmission(.preflightRejected)
        }
        switch result {
        case .submittedUnverified(.valid):
            return validateAfterPosting() == .valid
                ? .submittedUnverified(.valid)
                : .submittedUnverified(.uncertain)
        default:
            return result
        }
    }
}

@MainActor
private final class Issue40ReviewPasteboardSecureInputProvider: SecureInputStateProviding {
    func isSecureInputEnabled() -> Bool { false }
}

@MainActor
private final class Issue40ReviewPasteboardFrontmostProcessProvider: FrontmostProcessProviding {
    func frontmostProcessIdentifier() -> pid_t? { 42 }
}
