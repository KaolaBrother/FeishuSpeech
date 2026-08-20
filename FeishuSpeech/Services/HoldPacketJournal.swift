import Foundation
import os.log

private nonisolated let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "HoldPacketJournal"
)

nonisolated enum JournalWaitResult: Sendable {
    case packet(index: Int, data: Data)
    case captureComplete
    case cancelled
}

/// Generation-scoped lock-backed journal. Capture appends; recognition waits.
/// `waitForPacket(atOrAfter:)` matches ingress `registerNext`: queued packets before complete.
nonisolated final class HoldPacketJournal: @unchecked Sendable {
    private struct Waiter {
        let id: UUID
        let index: Int
        let continuation: CheckedContinuation<JournalWaitResult, Never>
    }

    private let lock = NSLock()
    private var packets: [Data] = []
    private var waiters: [Waiter] = []
    private var isCaptureComplete = false
    private var isCancelled = false

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return packets.count
    }

    func packet(at index: Int) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard packets.indices.contains(index) else { return nil }
        return packets[index]
    }

    func append(_ packet: Data) {
        lock.lock()
        packets.append(packet)
        let snapshot = packets
        let readyWaiters = removeWaitersLocked { $0.index < packets.count }
        lock.unlock()

        for waiter in readyWaiters {
            waiter.continuation.resume(
                returning: .packet(index: waiter.index, data: snapshot[waiter.index])
            )
        }
    }

    func markCaptureComplete() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCaptureComplete = true
        let completeWaiters = removeWaitersLocked { $0.index >= packets.count }
        lock.unlock()

        logger.info("Capture marked complete")
        for waiter in completeWaiters {
            waiter.continuation.resume(returning: .captureComplete)
        }
    }

    func cancelWaiters() {
        lock.lock()
        isCancelled = true
        let cancelledWaiters = waiters
        waiters.removeAll()
        lock.unlock()

        for waiter in cancelledWaiters {
            waiter.continuation.resume(returning: .cancelled)
        }
    }

    func waitForPacket(atOrAfter index: Int) async -> JournalWaitResult {
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.registerWait(
                    index: index,
                    waiterID: waiterID,
                    continuation: continuation
                )
            }
        } onCancel: {
            self.cancelWaiter(waiterID)
        }
    }

    private func registerWait(
        index: Int,
        waiterID: UUID,
        continuation: CheckedContinuation<JournalWaitResult, Never>
    ) {
        lock.lock()

        if Task.isCancelled {
            lock.unlock()
            continuation.resume(returning: .cancelled)
            return
        }

        if packets.count > index {
            let data = packets[index]
            lock.unlock()
            continuation.resume(returning: .packet(index: index, data: data))
            return
        }

        if isCancelled {
            lock.unlock()
            continuation.resume(returning: .cancelled)
            return
        }

        if isCaptureComplete {
            lock.unlock()
            continuation.resume(returning: .captureComplete)
            return
        }

        waiters.append(
            Waiter(id: waiterID, index: index, continuation: continuation)
        )
        lock.unlock()
    }

    private func cancelWaiter(_ waiterID: UUID) {
        lock.lock()
        guard let waiterIndex = waiters.firstIndex(where: { $0.id == waiterID }) else {
            lock.unlock()
            return
        }
        let waiter = waiters.remove(at: waiterIndex)
        lock.unlock()
        waiter.continuation.resume(returning: .cancelled)
    }

    private func removeWaitersLocked(_ matches: (Waiter) -> Bool) -> [Waiter] {
        let matching = waiters.filter(matches)
        if !matching.isEmpty {
            waiters.removeAll(where: matches)
        }
        return matching
    }
}
