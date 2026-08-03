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

    func test_replayRetention_acceptsExactlyTheHoldWideByteBudgetAfterDrain() async throws {
        let configuration = AudioIngressConfiguration(
            packetByteCount: 4,
            minimumTailByteCount: 2,
            maximumBufferedByteCount: 8
        )
        let ingress = ByteBoundedAudioIngress(
            configuration: configuration,
            retainsDeliveredPacketsForReplay: true
        )
        var iterator = ingress.stream.makeAsyncIterator()
        let firstPacket = Data([0x01, 0x02, 0x03, 0x04])
        let secondPacket = Data([0x05, 0x06, 0x07, 0x08])

        XCTAssertNil(ingress.append(firstPacket))
        let drainedFirstPacket = try await iterator.next()
        XCTAssertEqual(drainedFirstPacket, firstPacket)

        XCTAssertNil(
            ingress.append(secondPacket),
            "delivered plus undrained bytes exactly equal to the hold-wide limit must be accepted"
        )
        ingress.finish(streamEstablished: true)

        let drainedSecondPacket = try await iterator.next()
        XCTAssertEqual(drainedSecondPacket, secondPacket)
        let terminalElement = try await iterator.next()
        XCTAssertNil(terminalElement)
    }

    func test_replayRetention_oneBytePastBudgetFailsSynchronouslyAfterDeliveredPacket() async throws {
        let configuration = AudioIngressConfiguration(
            packetByteCount: 4,
            minimumTailByteCount: 2,
            maximumBufferedByteCount: 4
        )
        let ingress = ByteBoundedAudioIngress(
            configuration: configuration,
            retainsDeliveredPacketsForReplay: true
        )
        var iterator = ingress.stream.makeAsyncIterator()
        let retainedPacket = Data([0x11, 0x12, 0x13, 0x14])

        XCTAssertNil(ingress.append(retainedPacket))
        let deliveredPacket = try await iterator.next()
        XCTAssertEqual(deliveredPacket, retainedPacket)

        XCTAssertEqual(
            ingress.append(Data([0x15])),
            AudioIngressError.ingressOverflow,
            "a delivered replay packet must remain charged against the same byte limit"
        )

        do {
            _ = try await iterator.next()
            XCTFail("the synchronous overflow must terminate the ingress")
        } catch let error as AudioIngressError {
            XCTAssertEqual(error, .ingressOverflow)
        } catch {
            XCTFail("expected AudioIngressError.ingressOverflow, got \(error)")
        }
    }

    func test_replayRetention_directWaiterDeliveryRemainsChargedAgainstBudget() async throws {
        let configuration = AudioIngressConfiguration(
            packetByteCount: 4,
            minimumTailByteCount: 2,
            maximumBufferedByteCount: 4
        )
        let ingress = ByteBoundedAudioIngress(
            configuration: configuration,
            retainsDeliveredPacketsForReplay: true
        )
        var iterator = ingress.stream.makeAsyncIterator()
        let waiterEnteredNext = expectation(description: "consumer entered next")
        let packet = Data([0x16, 0x17, 0x18, 0x19])
        let deliveryTask = Task { @MainActor in
            waiterEnteredNext.fulfill()
            return try await iterator.next()
        }

        await fulfillment(of: [waiterEnteredNext], timeout: 1)
        XCTAssertNil(ingress.append(packet))
        let directlyDeliveredPacket = try await deliveryTask.value
        XCTAssertEqual(directlyDeliveredPacket, packet)
        XCTAssertEqual(
            ingress.append(Data([0x1A])),
            AudioIngressError.ingressOverflow,
            "delivery through a suspended waiter must not bypass replay-byte accounting"
        )
    }

    func test_explicitNonReplayIngress_releasesDeliveredBytesForReuse() async throws {
        let configuration = AudioIngressConfiguration(
            packetByteCount: 4,
            minimumTailByteCount: 2,
            maximumBufferedByteCount: 4
        )
        let ingress = ByteBoundedAudioIngress(
            configuration: configuration,
            retainsDeliveredPacketsForReplay: false
        )
        var iterator = ingress.stream.makeAsyncIterator()
        let firstPacket = Data([0x21, 0x22, 0x23, 0x24])
        let replacementPacket = Data([0x25, 0x26, 0x27, 0x28])

        XCTAssertNil(ingress.append(firstPacket))
        let deliveredFirstPacket = try await iterator.next()
        XCTAssertEqual(deliveredFirstPacket, firstPacket)
        XCTAssertNil(
            ingress.append(replacementPacket),
            "explicit non-replay mode must preserve occupancy-released buffering"
        )

        ingress.finish(streamEstablished: true)
        let deliveredReplacementPacket = try await iterator.next()
        XCTAssertEqual(deliveredReplacementPacket, replacementPacket)
        let terminalElement = try await iterator.next()
        XCTAssertNil(terminalElement)
    }

    func test_replayRetention_shortPaddedTailDoesNotDoubleChargeCapturedBytes() async throws {
        let configuration = AudioIngressConfiguration(
            packetByteCount: 4,
            minimumTailByteCount: 4,
            maximumBufferedByteCount: 4
        )
        let ingress = ByteBoundedAudioIngress(
            configuration: configuration,
            retainsDeliveredPacketsForReplay: true
        )
        var iterator = ingress.stream.makeAsyncIterator()

        XCTAssertNil(ingress.append(Data([0x31])))
        ingress.finish(streamEstablished: true)

        let paddedTail = try await iterator.next()
        XCTAssertEqual(paddedTail, Data([0x31, 0x00, 0x00, 0x00]))
        let terminalElement = try await iterator.next()
        XCTAssertNil(
            terminalElement,
            "padding the retained raw tail must not make the exact byte budget overflow"
        )
    }

    func test_replayRetention_firstTerminalFailureRemainsAuthoritative() async {
        let ingress = ByteBoundedAudioIngress(
            configuration: productionConfiguration,
            retainsDeliveredPacketsForReplay: true
        )
        let stream = ingress.stream

        ingress.fail(AudioIngressError.captureFailed)
        ingress.finish(streamEstablished: true)
        ingress.fail(AudioIngressError.ingressOverflow)

        do {
            _ = try await collect(stream)
            XCTFail("the first terminal failure must remain authoritative in replay mode")
        } catch let error as AudioIngressError {
            XCTAssertEqual(error, .captureFailed)
        } catch {
            XCTFail("expected AudioIngressError.captureFailed, got \(error)")
        }
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
