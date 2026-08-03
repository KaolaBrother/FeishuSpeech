import Foundation
import XCTest
import os.log
@testable import FeishuSpeech

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "StreamingAudioIngressTests")

final class StreamingAudioIngressTests: XCTestCase {
    private let productionConfiguration = AudioIngressConfiguration(
        packetByteCount: 6_400,
        minimumTailByteCount: 3_200,
        maximumBufferedByteCount: 1_920_000
    )

    func test_productionConfiguration_isByteDefinedAtSixtySecondPCMCapacity() {
        XCTAssertEqual(productionConfiguration.packetByteCount, 6_400)
        XCTAssertEqual(productionConfiguration.minimumTailByteCount, 3_200)
        XCTAssertEqual(productionConfiguration.maximumBufferedByteCount, 1_920_000)
        XCTAssertEqual(productionConfiguration.bufferedElementCapacity, 300)
    }

    func test_arbitraryCallbackSizes_coalesceIntoOrderedExactPackets() async throws {
        let ingress = ByteBoundedAudioIngress(configuration: productionConfiguration)
        let stream = ingress.stream
        let source = Data((0..<15_000).map { UInt8($0 % 251) })

        ingress.append(Data(source[0..<1_001]))
        ingress.append(Data(source[1_001..<6_399]))
        ingress.append(Data(source[6_399..<6_401]))
        ingress.append(Data(source[6_401..<14_000]))
        ingress.append(Data(source[14_000..<15_000]))
        ingress.finish(streamEstablished: true)

        let elements = try await collect(stream)

        XCTAssertEqual(elements.map(\.count), [6_400, 6_400, 3_200])
        XCTAssertEqual(elements[0], Data(source[0..<6_400]))
        XCTAssertEqual(elements[1], Data(source[6_400..<12_800]))
        XCTAssertEqual(Data(elements[2].prefix(2_200)), Data(source[12_800..<15_000]))
        XCTAssertEqual(
            Data(elements[2].suffix(1_000)),
            Data(repeating: 0, count: 1_000),
            "an established short tail must be padded only with PCM silence"
        )
    }

    func test_finishWithEstablishedLongTail_flushesExactlyOneUnpaddedTail() async throws {
        let ingress = ByteBoundedAudioIngress(configuration: productionConfiguration)
        let stream = ingress.stream
        let packet = Data(repeating: 0x11, count: 6_400)
        let tail = Data(repeating: 0x22, count: 4_001)

        ingress.append(packet + tail)
        ingress.finish(streamEstablished: true)
        ingress.finish(streamEstablished: true)

        let elements = try await collect(stream)
        XCTAssertEqual(elements, [packet, tail], "stop must flush at most one non-empty tail")
    }

    func test_finishBeforeFirstPacket_discardsLocalTailAndCompletesWithoutNetworkElement() async throws {
        let ingress = ByteBoundedAudioIngress(configuration: productionConfiguration)
        let stream = ingress.stream

        ingress.append(Data(repeating: 0x33, count: 5_000))
        ingress.finish(streamEstablished: false)

        let elements = try await collect(stream)
        XCTAssertEqual(elements, [])
    }

    func test_capacityIsNotRawCallbackCount_manyTinyCallbacksStillProduceOneOrderedPacket() async throws {
        let ingress = ByteBoundedAudioIngress(configuration: productionConfiguration)
        let stream = ingress.stream
        for index in 0..<6_400 {
            ingress.append(Data([UInt8(index % 251)]))
        }
        ingress.finish(streamEstablished: true)

        let elements = try await collect(stream)

        XCTAssertEqual(elements.count, 1)
        XCTAssertEqual(elements[0].count, 6_400)
        XCTAssertEqual(elements[0], Data((0..<6_400).map { UInt8($0 % 251) }))
    }

    func test_bufferOverflow_failsExplicitlyWithoutDroppingReplayingOrReorderingAcceptedPackets() async {
        let ingress = ByteBoundedAudioIngress(configuration: productionConfiguration)
        let stream = ingress.stream
        for index in 0...300 {
            ingress.append(Data(repeating: UInt8(index % 251), count: 6_400))
        }

        var accepted: [Data] = []
        do {
            for try await packet in stream {
                accepted.append(packet)
            }
            XCTFail("the 301st queued packet must terminate the 300-element ingress")
        } catch let error as AudioIngressError {
            XCTAssertEqual(error, .ingressOverflow)
        } catch {
            XCTFail("expected AudioIngressError.ingressOverflow, got \(error)")
        }

        XCTAssertEqual(accepted.count, 300)
        for (index, packet) in accepted.enumerated() {
            XCTAssertEqual(packet, Data(repeating: UInt8(index % 251), count: 6_400))
        }
    }

    func test_pendingCoalescingBytesCountTowardExactConfiguredByteBound() {
        let ingress = ByteBoundedAudioIngress(configuration: productionConfiguration)
        let packet = Data(repeating: 0x5A, count: productionConfiguration.packetByteCount)

        for _ in 0..<productionConfiguration.bufferedElementCapacity {
            XCTAssertNil(ingress.append(packet), "the exact configured byte bound must remain accepted")
        }

        let overflow = ingress.append(Data([0x01]))

        XCTAssertEqual(
            overflow,
            .ingressOverflow,
            "one pending coalescing byte beyond the byte ceiling must fail synchronously"
        )
        ingress.fail(.cancelled)
    }

    func test_capacityOneDrainReleasesBytesForAppendUntilActualOccupancyExceedsBound() async throws {
        let configuration = AudioIngressConfiguration(
            packetByteCount: 4,
            minimumTailByteCount: 2,
            maximumBufferedByteCount: 4
        )
        let ingress = ByteBoundedAudioIngress(configuration: configuration)
        var iterator = ingress.stream.makeAsyncIterator()
        let firstPacket = Data([0x01, 0x02, 0x03, 0x04])
        XCTAssertNil(ingress.append(firstPacket))
        let drainedPacket = try await iterator.next()
        XCTAssertEqual(drainedPacket, firstPacket)

        let firstRecoveredByte = ingress.append(Data([0x05]))
        XCTAssertNil(
            firstRecoveredByte,
            "draining the capacity-one stream must release the first packet's four bytes"
        )
        guard firstRecoveredByte == nil else { return }

        XCTAssertNil(ingress.append(Data([0x06, 0x07, 0x08])))
        XCTAssertEqual(
            ingress.append(Data([0x09])),
            .ingressOverflow,
            "only actual queued plus coalescing bytes beyond the configured bound may overflow"
        )
    }

    func test_failureAndRepeatedFinish_closeTheContinuationExactlyOnce() async {
        let ingress = ByteBoundedAudioIngress(configuration: productionConfiguration)
        let stream = ingress.stream

        ingress.fail(.captureFailed)
        ingress.finish(streamEstablished: true)
        ingress.fail(.ingressOverflow)

        do {
            _ = try await collect(stream)
            XCTFail("the first terminal failure must remain authoritative")
        } catch let error as AudioIngressError {
            XCTAssertEqual(error, .captureFailed)
        } catch {
            XCTFail("expected AudioIngressError.captureFailed, got \(error)")
        }
    }

    private func collect(
        _ stream: AsyncThrowingStream<Data, Error>
    ) async throws -> [Data] {
        var values: [Data] = []
        for try await value in stream {
            values.append(value)
        }
        return values
    }
}
