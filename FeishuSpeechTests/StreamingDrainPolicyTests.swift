import Foundation
import XCTest
import os.log

@testable import FeishuSpeech

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "StreamingDrainPolicyTests"
)

final class StreamingDrainPolicyTests: XCTestCase {
    func test_productionDefaultsSatisfySliceSlackInvariant() {
        logger.info("StreamingDrainPolicyTests starting")
        let policy = StreamingDrainPolicy()

        XCTAssertEqual(policy.factoryTimeoutNanoseconds, 18_000_000_000)
        XCTAssertEqual(policy.packetTimeoutNanoseconds, 30_000_000_000)
        XCTAssertEqual(policy.finishTimeoutNanoseconds, 45_000_000_000)
        XCTAssertEqual(policy.postReleaseDrainTimeoutNanoseconds, 60_000_000_000)
        XCTAssertLessThan(
            policy.urlSessionFactorySliceNanoseconds
                + policy.directFactorySliceNanoseconds
                + policy.sliceSlackNanoseconds,
            policy.factoryTimeoutNanoseconds
        )
        XCTAssertLessThan(
            policy.urlSessionPacketSliceNanoseconds
                + policy.directPacketSliceNanoseconds
                + policy.sliceSlackNanoseconds,
            policy.packetTimeoutNanoseconds
        )
        XCTAssertLessThan(
            policy.urlSessionFinishSliceNanoseconds
                + policy.directFinishSliceNanoseconds
                + policy.sliceSlackNanoseconds,
            policy.finishTimeoutNanoseconds
        )
        XCTAssertGreaterThanOrEqual(policy.sliceSlackNanoseconds, 500_000_000)
    }

    func test_testOverrideInitKeepsASingleOuterForAllOperations() {
        let policy = StreamingDrainPolicy(
            operationTimeoutNanoseconds: 1_000_000,
            postReleaseDrainTimeoutNanoseconds: 50_000_000
        )
        XCTAssertEqual(policy.operationTimeout(for: "factory", remainingDrainNanoseconds: nil), 1_000_000)
        XCTAssertEqual(policy.operationTimeout(for: "packet", remainingDrainNanoseconds: nil), 1_000_000)
        XCTAssertEqual(policy.operationTimeout(for: "finish", remainingDrainNanoseconds: nil), 1_000_000)
        XCTAssertEqual(policy.postReleaseDrainTimeoutNanoseconds, 50_000_000)
    }

    func test_finishOuterIsClampedToRemainingDrain() {
        let policy = StreamingDrainPolicy()
        XCTAssertEqual(
            policy.operationTimeout(for: "finish", remainingDrainNanoseconds: 8_000_000_000),
            8_000_000_000
        )
        XCTAssertEqual(
            policy.operationTimeout(for: "finish", remainingDrainNanoseconds: nil),
            45_000_000_000
        )
    }
}
