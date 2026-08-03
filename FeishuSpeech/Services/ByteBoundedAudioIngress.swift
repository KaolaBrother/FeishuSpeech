import Foundation
import os.log

private nonisolated let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "AudioIngress"
)

nonisolated final class ByteBoundedAudioIngress: @unchecked Sendable {
    let stream: AsyncThrowingStream<Data, Error>

    private let storage: Storage

    var hasEmittedFullPacket: Bool {
        storage.hasEmittedFullPacket
    }

    init(
        configuration: AudioIngressConfiguration,
        retainsDeliveredPacketsForReplay: Bool = false
    ) {
        let storage = Storage(
            configuration: configuration,
            retainsDeliveredPacketsForReplay: retainsDeliveredPacketsForReplay
        )
        self.storage = storage
        stream = AsyncThrowingStream(
            unfolding: {
                try await storage.next()
            }
        )
    }

    @discardableResult
    func append(_ audio: Data) -> AudioIngressError? {
        storage.append(audio)
    }

    func finish(streamEstablished: Bool) {
        storage.finish(streamEstablished: streamEstablished)
    }

    func fail(_ error: AudioIngressError) {
        storage.fail(error)
    }
}

private extension ByteBoundedAudioIngress {
    nonisolated final class Storage: @unchecked Sendable {
        private enum TerminalState {
            case open
            case finished
            case failed(AudioIngressError)
        }

        private struct Waiter {
            let id: UUID
            let continuation: CheckedContinuation<Data?, Error>
        }

        private struct BufferedPacket {
            let data: Data
            let capturedByteCount: Int
            let chargedByteCount: Int
        }

        private let configuration: AudioIngressConfiguration
        private let retainsDeliveredPacketsForReplay: Bool
        private let lock = NSLock()
        private var queuedPackets: [BufferedPacket] = []
        private var waiters: [Waiter] = []
        private var pendingAudio = Data()
        private var bufferedByteCount = 0
        private var retainedDeliveredByteCount = 0
        private var hasEmittedFullPacketStorage = false
        private var terminalState = TerminalState.open

        init(
            configuration: AudioIngressConfiguration,
            retainsDeliveredPacketsForReplay: Bool
        ) {
            self.configuration = configuration
            self.retainsDeliveredPacketsForReplay = retainsDeliveredPacketsForReplay
        }

        var hasEmittedFullPacket: Bool {
            lock.lock()
            defer { lock.unlock() }
            return hasEmittedFullPacketStorage
        }

        func append(_ audio: Data) -> AudioIngressError? {
            guard !audio.isEmpty else { return nil }

            lock.lock()
            defer { lock.unlock() }
            guard case .open = terminalState else { return nil }

            var nextIndex = audio.startIndex
            while nextIndex < audio.endIndex {
                let availablePacketBytes = configuration.packetByteCount - pendingAudio.count
                let remainingAudioBytes = audio.distance(from: nextIndex, to: audio.endIndex)
                let appendedByteCount = min(availablePacketBytes, remainingAudioBytes)

                guard currentBufferedByteCount + appendedByteCount
                        <= configuration.maximumBufferedByteCount else {
                    terminateLocked(with: .ingressOverflow)
                    return .ingressOverflow
                }

                let chunkEnd = audio.index(nextIndex, offsetBy: appendedByteCount)
                pendingAudio.append(contentsOf: audio[nextIndex..<chunkEnd])
                nextIndex = chunkEnd

                if pendingAudio.count == configuration.packetByteCount {
                    let packet = pendingAudio
                    pendingAudio.removeAll(keepingCapacity: true)
                    if let error = enqueueLocked(
                        packet,
                        capturedByteCount: packet.count,
                        isFullPacket: true
                    ) {
                        return error
                    }
                }
            }
            return nil
        }

        func finish(streamEstablished: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard case .open = terminalState else { return }

            if streamEstablished, !pendingAudio.isEmpty {
                let capturedByteCount = pendingAudio.count
                var tail = pendingAudio
                pendingAudio.removeAll(keepingCapacity: false)
                if tail.count < configuration.minimumTailByteCount {
                    tail.append(
                        Data(
                            repeating: 0,
                            count: configuration.minimumTailByteCount - tail.count
                        )
                    )
                }
                guard enqueueLocked(
                    tail,
                    capturedByteCount: capturedByteCount,
                    isFullPacket: false
                ) == nil else { return }
            }

            pendingAudio.removeAll(keepingCapacity: false)
            terminalState = .finished
            resumeTerminalWaitersLocked()
        }

        func fail(_ error: AudioIngressError) {
            lock.lock()
            defer { lock.unlock() }
            terminateLocked(with: error)
        }

        func next() async throws -> Data? {
            let waiterID = UUID()
            return try await withTaskCancellationHandler(
                operation: {
                    try await withCheckedThrowingContinuation { continuation in
                        self.registerNext(waiterID: waiterID, continuation: continuation)
                    }
                },
                onCancel: {
                    self.cancelWaiter(waiterID)
                }
            )
        }

        private var currentBufferedByteCount: Int {
            retainedDeliveredByteCount + bufferedByteCount + pendingAudio.count
        }

        private func enqueueLocked(
            _ packet: Data,
            capturedByteCount: Int,
            isFullPacket: Bool
        ) -> AudioIngressError? {
            let chargedByteCount = retainsDeliveredPacketsForReplay
                ? capturedByteCount
                : packet.count
            guard currentBufferedByteCount + chargedByteCount
                    <= configuration.maximumBufferedByteCount else {
                terminateLocked(with: .ingressOverflow)
                return .ingressOverflow
            }

            if isFullPacket {
                hasEmittedFullPacketStorage = true
            }

            if waiters.isEmpty {
                queuedPackets.append(
                    BufferedPacket(
                        data: packet,
                        capturedByteCount: capturedByteCount,
                        chargedByteCount: chargedByteCount
                    )
                )
                bufferedByteCount += chargedByteCount
            } else {
                let waiter = waiters.removeFirst()
                if retainsDeliveredPacketsForReplay {
                    retainedDeliveredByteCount += capturedByteCount
                }
                waiter.continuation.resume(returning: packet)
            }
            return nil
        }

        private func registerNext(
            waiterID: UUID,
            continuation: CheckedContinuation<Data?, Error>
        ) {
            lock.lock()

            if Task.isCancelled {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }

            if !queuedPackets.isEmpty {
                let packet = queuedPackets.removeFirst()
                bufferedByteCount -= packet.chargedByteCount
                if retainsDeliveredPacketsForReplay {
                    retainedDeliveredByteCount += packet.capturedByteCount
                }
                lock.unlock()
                continuation.resume(returning: packet.data)
                return
            }

            switch terminalState {
            case .open:
                waiters.append(Waiter(id: waiterID, continuation: continuation))
                lock.unlock()
            case .finished:
                lock.unlock()
                continuation.resume(returning: nil)
            case .failed(let error):
                lock.unlock()
                continuation.resume(throwing: error)
            }
        }

        private func cancelWaiter(_ waiterID: UUID) {
            lock.lock()
            guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else {
                lock.unlock()
                return
            }
            let waiter = waiters.remove(at: index)
            lock.unlock()
            waiter.continuation.resume(throwing: CancellationError())
        }

        private func terminateLocked(with error: AudioIngressError) {
            guard case .open = terminalState else { return }
            terminalState = .failed(error)
            pendingAudio.removeAll(keepingCapacity: false)
            resumeTerminalWaitersLocked()
        }

        private func resumeTerminalWaitersLocked() {
            guard queuedPackets.isEmpty else { return }
            let terminalWaiters = waiters
            waiters.removeAll()

            for waiter in terminalWaiters {
                switch terminalState {
                case .open:
                    preconditionFailure("Cannot resume terminal waiters while ingress is open")
                case .finished:
                    waiter.continuation.resume(returning: nil)
                case .failed(let error):
                    waiter.continuation.resume(throwing: error)
                }
            }
        }
    }
}
