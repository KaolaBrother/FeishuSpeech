import Foundation
import XCTest
import os.log

@testable import FeishuSpeech

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "HoldPacketJournalTests"
)

/// Issue #28: generation-scoped lock-backed journal. Capture appends; recognition waits.
/// Packet-before-complete matches ingress `registerNext`.
final class HoldPacketJournalTests: XCTestCase {
    override func setUp() {
        super.setUp()
        logger.info("HoldPacketJournalTests starting")
    }

    func test_append_preservesCaptureOrderAndCount() {
        let journal = HoldPacketJournal()
        let first = Data(repeating: 0x11, count: 6_400)
        let second = Data(repeating: 0x22, count: 6_400)

        journal.append(first)
        journal.append(second)

        XCTAssertEqual(journal.count, 2)
        XCTAssertEqual(journal.packet(at: 0), first)
        XCTAssertEqual(journal.packet(at: 1), second)
        XCTAssertNil(journal.packet(at: 2))
        XCTAssertEqual(journal.packet(at: 0), first, "repeated reads must not consume or rewrite storage")
    }

    func test_waitForPacket_returnsQueuedIndexBeforeCompleteEvenWhenAlreadyMarked() async {
        let journal = HoldPacketJournal()
        let first = Data(repeating: 0x31, count: 6_400)
        let tail = Data(repeating: 0x32, count: 3_200)
        journal.append(first)
        journal.append(tail)
        journal.markCaptureComplete()

        let indexZero = await journal.waitForPacket(atOrAfter: 0)
        let indexOne = await journal.waitForPacket(atOrAfter: 1)
        let pastEnd = await journal.waitForPacket(atOrAfter: 2)

        assertWait(indexZero, equals: .packet(index: 0, data: first))
        assertWait(indexOne, equals: .packet(index: 1, data: tail))
        assertWait(
            pastEnd,
            equals: .captureComplete,
            "complete is visible only after every stored index has been offered"
        )
    }

    func test_waitForPacket_deliversLastTailWhenCompleteArrivesInSameWakeup() async {
        let journal = HoldPacketJournal()
        journal.append(Data(repeating: 0x41, count: 6_400))
        let tail = Data(repeating: 0x42, count: 3_200)

        let waiter = Task {
            await journal.waitForPacket(atOrAfter: 1)
        }
        await yieldForParkedWaiter()

        journal.append(tail)
        journal.markCaptureComplete()

        let result = await waiter.value
        assertWait(
            result,
            equals: .packet(index: 1, data: tail),
            "packet-before-complete must send the last tail even if complete is observed in the same wakeup"
        )
        assertWait(await journal.waitForPacket(atOrAfter: 2), equals: .captureComplete)
    }

    func test_cancelWaiters_doesNotMarkCaptureComplete() async {
        let journal = HoldPacketJournal()
        journal.append(Data(repeating: 0x51, count: 6_400))

        let parked = Task {
            await journal.waitForPacket(atOrAfter: 1)
        }
        await yieldForParkedWaiter()
        journal.cancelWaiters()

        assertWait(
            await parked.value,
            equals: .cancelled,
            "iterator throw / ingress.fail must wake waiters as cancelled"
        )
        assertWait(
            await journal.waitForPacket(atOrAfter: 1),
            equals: .cancelled,
            "cancelWaiters is sticky and must not become captureComplete"
        )
        assertWait(
            await journal.waitForPacket(atOrAfter: 0),
            equals: .packet(index: 0, data: Data(repeating: 0x51, count: 6_400)),
            "already-stored indices remain readable after cancel"
        )
    }

    func test_markCaptureComplete_doesNotFireWhileUnreadPacketsRemain() async {
        let journal = HoldPacketJournal()
        let packet = Data(repeating: 0x61, count: 6_400)
        journal.append(packet)

        let parkedAtZero = Task {
            await journal.waitForPacket(atOrAfter: 0)
        }
        journal.markCaptureComplete()

        assertWait(await parkedAtZero.value, equals: .packet(index: 0, data: packet))
        assertWait(await journal.waitForPacket(atOrAfter: 1), equals: .captureComplete)
    }

    private func yieldForParkedWaiter() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    private func assertWait(
        _ result: JournalWaitResult,
        equals expected: JournalWaitResult,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            journalWait(result, matches: expected),
            message.isEmpty
                ? "unexpected journal wait: \(String(describing: result))"
                : message,
            file: file,
            line: line
        )
    }

    private func journalWait(_ lhs: JournalWaitResult, matches rhs: JournalWaitResult) -> Bool {
        switch (lhs, rhs) {
        case let (.packet(leftIndex, leftData), .packet(rightIndex, rightData)):
            return leftIndex == rightIndex && leftData == rightData
        case (.captureComplete, .captureComplete), (.cancelled, .cancelled):
            return true
        default:
            return false
        }
    }
}
