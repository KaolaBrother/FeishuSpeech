import Foundation
import XCTest
import os.log
@testable import FeishuSpeech

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "AudioRecorderStreamingIntegrationTests"
)

@MainActor
final class AudioRecorderStreamingIntegrationTests: XCTestCase {
    func test_convertedBlocksReachIngressInCaptureOrderAndNormalSealFlushesTailAfterPackets() async throws {
        let recorder = AudioRecorder()
        let ingress = makeIngress()
        let stream = ingress.stream
        let source = Data((0..<7_000).map { UInt8($0 % 251) })
        recorder.attachStreamingIngressForTesting(ingress)

        recorder.publishConvertedAudioForTesting(Data(source[0..<1_001]))
        recorder.publishConvertedAudioForTesting(Data(source[1_001..<6_401]))
        recorder.publishConvertedAudioForTesting(Data(source[6_401..<7_000]))
        await recorder.sealStreamingForTesting(streamEstablished: true)

        let elements = try await collect(stream)
        XCTAssertEqual(elements.map(\.count), [6_400, 3_200])
        XCTAssertEqual(elements[0], Data(source[0..<6_400]))
        XCTAssertEqual(Data(elements[1].prefix(600)), Data(source[6_400..<7_000]))
        XCTAssertEqual(Data(elements[1].suffix(2_600)), Data(repeating: 0, count: 2_600))
    }

    func test_normalStopRetainsCurrentOutputGenerationUntilQueuedAudioCallbackCrossesBarrier() async throws {
        let recorder = AudioRecorder()
        let ingress = makeIngress()
        let stream = ingress.stream
        let source = Data((0..<7_000).map { UInt8($0 % 251) })
        let callbackStarted = DispatchSemaphore(value: 0)
        let releaseCallback = DispatchSemaphore(value: 0)
        recorder.attachStreamingIngressForTesting(ingress)

        recorder.enqueueConvertedAudioCallbackForTesting(
            source,
            started: { callbackStarted.signal() },
            release: { releaseCallback.wait() }
        )
        XCTAssertEqual(
            callbackStarted.wait(timeout: .now() + 1),
            .success,
            "the test callback must be queued on AudioRecorder's real audio queue"
        )

        let stop = Task {
            await recorder.sealStreamingForTesting(streamEstablished: true)
        }
        await Task.yield()
        releaseCallback.signal()
        await stop.value

        let elements = try await collect(stream)
        XCTAssertEqual(elements.map(\.count), [6_400, 3_200])
        XCTAssertEqual(elements[0], Data(source[0..<6_400]))
        XCTAssertEqual(Data(elements[1].prefix(600)), Data(source[6_400..<7_000]))
        XCTAssertEqual(Data(elements[1].suffix(2_600)), Data(repeating: 0, count: 2_600))
    }

    func test_stopUsesPostBarrierEmissionStateWhenQueuedCallbackCreatesFirstFullPacket() async throws {
        let recorder = AudioRecorder()
        let ingress = makeIngress()
        let stream = ingress.stream
        let initialAudio = Data(repeating: 0x51, count: 5_000)
        let queuedAudio = Data(repeating: 0x52, count: 2_000)
        let callbackStarted = DispatchSemaphore(value: 0)
        let releaseCallback = DispatchSemaphore(value: 0)
        recorder.attachStreamingIngressForTesting(ingress)
        recorder.publishConvertedAudioForTesting(initialAudio)

        recorder.enqueueConvertedAudioCallbackForTesting(
            queuedAudio,
            started: { callbackStarted.signal() },
            release: { releaseCallback.wait() }
        )
        XCTAssertEqual(callbackStarted.wait(timeout: .now() + 1), .success)
        let preBarrierEmissionSnapshot = ingress.hasEmittedFullPacket
        XCTAssertFalse(preBarrierEmissionSnapshot)

        let stop = Task {
            await recorder.sealStreamingForTesting(
                streamEstablished: preBarrierEmissionSnapshot
            )
        }
        await Task.yield()
        releaseCallback.signal()
        await stop.value

        let elements = try await collect(stream)
        XCTAssertEqual(
            elements.map(\.count),
            [6_400, 3_200],
            "the seal decision must include packets emitted by callbacks drained at the audioQueue barrier"
        )
        guard elements.count == 2 else { return }
        XCTAssertEqual(Data(elements[0].prefix(5_000)), initialAudio)
        XCTAssertEqual(Data(elements[0].suffix(1_400)), Data(queuedAudio.prefix(1_400)))
        XCTAssertEqual(Data(elements[1].prefix(600)), Data(queuedAudio.suffix(600)))
        XCTAssertEqual(Data(elements[1].suffix(2_600)), Data(repeating: 0, count: 2_600))
    }

    func test_repeatedNormalSeal_forceCleanupAndFailureCloseIngressExactlyOnce() async throws {
        let recorder = AudioRecorder()
        let ingress = makeIngress()
        let stream = ingress.stream
        recorder.attachStreamingIngressForTesting(ingress)
        recorder.publishConvertedAudioForTesting(Data(repeating: 0x11, count: 7_000))

        await recorder.sealStreamingForTesting(streamEstablished: true)
        await recorder.sealStreamingForTesting(streamEstablished: true)
        recorder.forceCleanup()
        recorder.simulateRuntimeErrorForTesting()

        let elements = try await collect(stream)
        XCTAssertEqual(elements.map(\.count), [6_400, 3_200])
    }

    func test_forceCleanupCancelsActiveIngressAndDiscardsUnsealedTail() async {
        let recorder = AudioRecorder()
        let ingress = makeIngress()
        let stream = ingress.stream
        recorder.attachStreamingIngressForTesting(ingress)
        recorder.publishConvertedAudioForTesting(Data(repeating: 0x22, count: 5_000))

        recorder.forceCleanup()

        await assertStreamFails(stream, expected: .cancelled, acceptedElementCount: 0)
    }

    func test_captureFailureWinsBeforeCleanupAndTerminatesIngressAsCaptureFailed() async {
        let recorder = AudioRecorder()
        let ingress = makeIngress()
        let stream = ingress.stream
        recorder.attachStreamingIngressForTesting(ingress)
        recorder.publishConvertedAudioForTesting(Data(repeating: 0x33, count: 6_400))

        recorder.simulateRuntimeErrorForTesting()
        recorder.forceCleanup()

        await assertStreamFails(stream, expected: .captureFailed, acceptedElementCount: 1)
        XCTAssertEqual(recorder.failure, .runtime)
        XCTAssertFalse(recorder.isRecording)
    }

    func test_ingressOverflowStopsRecorderAndPublishesDedicatedFailureWithoutReorderingAcceptedAudio() async {
        let configuration = AudioIngressConfiguration(
            packetByteCount: 6_400,
            minimumTailByteCount: 3_200,
            maximumBufferedByteCount: 6_400
        )
        let recorder = AudioRecorder()
        let ingress = ByteBoundedAudioIngress(configuration: configuration)
        let stream = ingress.stream
        recorder.attachStreamingIngressForTesting(ingress)

        recorder.publishConvertedAudioForTesting(Data(repeating: 0x41, count: 6_400))
        recorder.publishConvertedAudioForTesting(Data(repeating: 0x42, count: 6_400))
        recorder.publishConvertedAudioForTesting(Data(repeating: 0x43, count: 6_400))

        await assertStreamFails(stream, expected: .ingressOverflow, acceptedElementCount: 1)
        XCTAssertEqual(recorder.failure, .ingressOverflow)
        XCTAssertFalse(recorder.isRecording, "overflow must request immediate capture stop")
    }

    private func makeIngress() -> ByteBoundedAudioIngress {
        ByteBoundedAudioIngress(
            configuration: AudioIngressConfiguration(
                packetByteCount: 6_400,
                minimumTailByteCount: 3_200,
                maximumBufferedByteCount: 1_920_000
            )
        )
    }

    private func collect(_ stream: AsyncThrowingStream<Data, Error>) async throws -> [Data] {
        var elements: [Data] = []
        for try await element in stream {
            elements.append(element)
        }
        return elements
    }

    private func assertStreamFails(
        _ stream: AsyncThrowingStream<Data, Error>,
        expected: AudioIngressError,
        acceptedElementCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        var elements: [Data] = []
        do {
            for try await element in stream {
                elements.append(element)
            }
            XCTFail("expected ingress failure \(expected)", file: file, line: line)
        } catch let error as AudioIngressError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected AudioIngressError, got \(error)", file: file, line: line)
        }
        XCTAssertEqual(elements.count, acceptedElementCount, file: file, line: line)
    }
}
