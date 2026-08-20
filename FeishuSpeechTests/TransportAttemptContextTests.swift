import Foundation
import XCTest
import os.log

@testable import FeishuSpeech

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "TransportAttemptContextTests"
)

final class TransportAttemptContextTests: XCTestCase {
    func test_makeStreamingSessionConfigurationPinsWaitsForConnectivityFalseAndResourceTimeout() {
        logger.info("TransportAttemptContextTests starting")
        let policy = StreamingDrainPolicy()
        let resourceTimeout = TransportAttemptContext.resourceTimeout(for: policy)
        let configuration = FeishuAPIService.makeStreamingSessionConfiguration(
            resourceTimeout: resourceTimeout
        )

        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertEqual(resourceTimeout, 15, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(
            configuration.timeoutIntervalForResource,
            TimeInterval(policy.urlSessionFinishSliceNanoseconds) / 1_000_000_000
        )
        XCTAssertGreaterThan(
            configuration.timeoutIntervalForResource,
            TimeInterval(policy.urlSessionFactorySliceNanoseconds) / 1_000_000_000
        )
    }

    func test_completedHTTPDoesNotInvalidateSession() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CompletedHTTPURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let context = TransportAttemptContext(
            policy: StreamingDrainPolicy(
                operationTimeoutNanoseconds: 2_000_000_000,
                postReleaseDrainTimeoutNanoseconds: 60_000_000_000
            ),
            session: session
        )
        let request = URLRequest(url: URL(string: "https://open.feishu.cn/token")!)

        let response = try await context.send(
            AttemptHTTPRequest(request: request, phase: .factoryToken)
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertFalse(context.isInvalidatedForTesting)
    }

    func test_sliceTimerCancelsHungDataForAndInvalidates() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HangingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let context = TransportAttemptContext(
            policy: StreamingDrainPolicy(
                factoryTimeoutNanoseconds: 2_000_000_000,
                packetTimeoutNanoseconds: 2_000_000_000,
                finishTimeoutNanoseconds: 2_000_000_000,
                postReleaseDrainTimeoutNanoseconds: 60_000_000_000,
                urlSessionFactorySliceNanoseconds: 40_000_000,
                directFactorySliceNanoseconds: 40_000_000,
                urlSessionPacketSliceNanoseconds: 40_000_000,
                directPacketSliceNanoseconds: 40_000_000,
                urlSessionFinishSliceNanoseconds: 40_000_000,
                directFinishSliceNanoseconds: 40_000_000,
                sliceSlackNanoseconds: 500_000_000
            ),
            session: session
        )
        let request = URLRequest(url: URL(string: "https://open.feishu.cn/hang")!)

        do {
            _ = try await context.send(
                AttemptHTTPRequest(request: request, phase: .factoryToken)
            )
            XCTFail("hung data(for:) must lose the URLSession slice")
        } catch let error as FeishuAPIService.APIError {
            guard case .timeout = error else {
                XCTFail("expected timeout, got \(error)")
                return
            }
        } catch {
            XCTFail("expected timeout, got \(error)")
        }
        XCTAssertTrue(context.isInvalidatedForTesting)
    }

    func test_sessionCancelInvalidatesCapturedContext() async {
        let context = TransportAttemptContext(policy: StreamingDrainPolicy())
        let session = FeishuStreamingSession(
            streamID: "fixed_stream_030",
            initialToken: "token",
            refreshToken: { "token" },
            requestSender: { _ in
                DirectHTTPResponse(statusCode: 200, body: Data())
            },
            invalidateTransport: {
                context.invalidate()
            }
        )

        await session.cancel()
        XCTAssertTrue(context.isInvalidatedForTesting)
    }
}

private final class CompletedHTTPURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"code":0}"#.utf8))
        client?.urlProtocol(self, didFinishLoading: self)
    }

    override func stopLoading() {}
}

private final class HangingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {}

    override func stopLoading() {}
}
