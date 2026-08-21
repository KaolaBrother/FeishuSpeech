import Foundation
import XCTest
import os.log

@testable import FeishuSpeech

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "TransportAttemptContextTests"
)

final class TransportAttemptContextTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLSessionTestProbe.shared.reset()
    }

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
        let keepAlive = MockKeepAliveTransport(results: [
            .success(DirectHTTPResponse(statusCode: 200, body: Data()))
        ])
        let policy = StreamingDrainPolicy()
        // 500 decoy: URLSession-first or an incorrect hop would surface this status.
        let context = makeProbedContext(
            keepAlive: keepAlive,
            policy: policy,
            urlStatusCode: 500
        )

        let response = try await context.send(tokenRequest())

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertFalse(context.isInvalidatedForTesting)
        XCTAssertEqual(keepAlive.recordedSendCount, 1)
        XCTAssertEqual(
            keepAlive.recordedDeadlineNanoseconds,
            policy.directSliceNanoseconds(for: .factoryToken)
        )
        XCTAssertEqual(URLSessionTestProbe.shared.recordedStartCount, 0)
        XCTAssertEqual(keepAlive.callLog.snapshot(), ["keepAlive"])
    }

    func test_keepAliveConnectClassErrorDoesNotHopToURLSessionForFactoryPacketOrFinish() async {
        let connectClassErrors: [FeishuAPIService.APIError] = [
            .connectionFailed,
            .timeout,
            .networkError("probe")
        ]
        let phases: [AttemptHTTPPhase] = [.factoryToken, .packet, .finish]
        let policy = StreamingDrainPolicy()

        for expectedError in connectClassErrors {
            for phase in phases {
                let keepAlive = MockKeepAliveTransport(results: [.failure(expectedError)])
                let context = makeProbedContext(
                    keepAlive: keepAlive,
                    policy: policy,
                    urlStatusCode: 200
                )

                do {
                    _ = try await context.send(attemptRequest(phase: phase))
                    XCTFail("connect-class \(expectedError) for \(phase) must rethrow, not hop")
                } catch let thrown as FeishuAPIService.APIError {
                    assertSameConnectClass(thrown, expectedError, phase: phase)
                } catch {
                    XCTFail("expected \(expectedError) for \(phase), got \(error)")
                }

                XCTAssertEqual(
                    keepAlive.recordedSendCount,
                    1,
                    "keep-alive must be primary for \(expectedError) \(phase)"
                )
                XCTAssertEqual(
                    keepAlive.recordedDeadlineNanoseconds,
                    policy.directSliceNanoseconds(for: phase)
                )
                XCTAssertEqual(
                    URLSessionTestProbe.shared.recordedStartCount,
                    0,
                    "factory/packet/finish must not hop to URLSession for \(expectedError) \(phase)"
                )
                XCTAssertEqual(keepAlive.callLog.snapshot(), ["keepAlive"])
            }
        }
    }

    func test_keepAliveCompletedHTTP4xxDoesNotHopToURLSession() async throws {
        for statusCode in [400, 401, 403, 407] {
            let keepAlive = MockKeepAliveTransport(results: [
                .success(DirectHTTPResponse(statusCode: statusCode, body: Data()))
            ])
            let context = makeProbedContext(
                keepAlive: keepAlive,
                urlStatusCode: 200
            )

            let response = try await context.send(tokenRequest())

            XCTAssertEqual(response.statusCode, statusCode)
            XCTAssertFalse(context.isInvalidatedForTesting)
            XCTAssertEqual(keepAlive.recordedSendCount, 1)
            XCTAssertEqual(URLSessionTestProbe.shared.recordedStartCount, 0)
            XCTAssertEqual(keepAlive.callLog.snapshot(), ["keepAlive"])
        }
    }

    func test_keepAliveCancellationErrorDoesNotHopToURLSession() async {
        let keepAlive = MockKeepAliveTransport(results: [
            .failure(CancellationError())
        ])
        let context = makeProbedContext(
            keepAlive: keepAlive,
            urlStatusCode: 200
        )

        do {
            _ = try await context.send(tokenRequest())
            XCTFail("CancellationError from keep-alive must be rethrown")
        } catch is CancellationError {
            XCTAssertEqual(keepAlive.recordedSendCount, 1)
            XCTAssertEqual(URLSessionTestProbe.shared.recordedStartCount, 0)
            XCTAssertEqual(keepAlive.callLog.snapshot(), ["keepAlive"])
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    func test_stickyDirectLeavesURLSessionUnusedAcrossTwoSends() async throws {
        let keepAlive = MockKeepAliveTransport(results: [
            .success(DirectHTTPResponse(statusCode: 200, body: Data())),
            .success(DirectHTTPResponse(statusCode: 200, body: Data()))
        ])
        let context = makeProbedContext(
            keepAlive: keepAlive,
            urlStatusCode: 500
        )

        let first = try await context.send(tokenRequest())
        let second = try await context.send(tokenRequest())

        XCTAssertEqual(first.statusCode, 200)
        XCTAssertEqual(second.statusCode, 200)
        XCTAssertEqual(keepAlive.recordedSendCount, 2)
        XCTAssertEqual(URLSessionTestProbe.shared.recordedStartCount, 0)
        XCTAssertEqual(keepAlive.callLog.snapshot(), ["keepAlive", "keepAlive"])
        XCTAssertFalse(context.isInvalidatedForTesting)
    }

    func test_keepAliveConnectClassMissRetriesKeepAliveOnNextSend() async throws {
        let keepAlive = MockKeepAliveTransport(results: [
            .failure(FeishuAPIService.APIError.connectionFailed),
            .success(DirectHTTPResponse(statusCode: 200, body: Data()))
        ])
        let context = makeProbedContext(
            keepAlive: keepAlive,
            urlStatusCode: 200
        )

        do {
            _ = try await context.send(tokenRequest())
            XCTFail("first connect-class miss must rethrow, not hop to URLSession")
        } catch let error as FeishuAPIService.APIError {
            switch error {
            case .connectionFailed:
                break
            default:
                XCTFail("expected connectionFailed, got \(error)")
            }
        } catch {
            XCTFail("expected connectionFailed, got \(error)")
        }

        XCTAssertEqual(keepAlive.recordedSendCount, 1)
        XCTAssertEqual(URLSessionTestProbe.shared.recordedStartCount, 0)
        XCTAssertEqual(keepAlive.callLog.snapshot(), ["keepAlive"])

        let second = try await context.send(tokenRequest())

        XCTAssertEqual(second.statusCode, 200)
        XCTAssertEqual(keepAlive.recordedSendCount, 2)
        XCTAssertEqual(URLSessionTestProbe.shared.recordedStartCount, 0)
        XCTAssertEqual(keepAlive.callLog.snapshot(), ["keepAlive", "keepAlive"])
        XCTAssertFalse(context.isInvalidatedForTesting)
    }

    func test_newTransportAttemptContextStartsOnKeepAliveAgain() async throws {
        let firstKeepAlive = MockKeepAliveTransport(results: [
            .failure(FeishuAPIService.APIError.connectionFailed)
        ])
        let firstContext = makeProbedContext(
            keepAlive: firstKeepAlive,
            urlStatusCode: 200
        )
        do {
            _ = try await firstContext.send(tokenRequest())
            XCTFail("first context connect-class miss must rethrow, not hop")
        } catch let error as FeishuAPIService.APIError {
            switch error {
            case .connectionFailed:
                break
            default:
                XCTFail("expected connectionFailed, got \(error)")
            }
        } catch {
            XCTFail("expected connectionFailed, got \(error)")
        }
        XCTAssertEqual(firstKeepAlive.recordedSendCount, 1)
        XCTAssertEqual(URLSessionTestProbe.shared.recordedStartCount, 0)
        XCTAssertEqual(firstKeepAlive.callLog.snapshot(), ["keepAlive"])

        let nextKeepAlive = MockKeepAliveTransport(results: [
            .success(DirectHTTPResponse(statusCode: 200, body: Data()))
        ])
        let nextContext = makeProbedContext(
            keepAlive: nextKeepAlive,
            urlStatusCode: 500
        )
        let second = try await nextContext.send(tokenRequest())

        XCTAssertEqual(second.statusCode, 200)
        XCTAssertEqual(nextKeepAlive.recordedSendCount, 1)
        XCTAssertEqual(URLSessionTestProbe.shared.recordedStartCount, 0)
        XCTAssertEqual(nextKeepAlive.callLog.snapshot(), ["keepAlive"])
    }

    func test_keepAliveConnectClassMissDoesNotStartHungURLSession() async {
        let policy = StreamingDrainPolicy(
            factoryTimeoutNanoseconds: 5_000_000_000,
            packetTimeoutNanoseconds: 5_000_000_000,
            finishTimeoutNanoseconds: 5_000_000_000,
            postReleaseDrainTimeoutNanoseconds: 60_000_000_000,
            urlSessionFactorySliceNanoseconds: 40_000_000,
            directFactorySliceNanoseconds: 2_000_000_000,
            urlSessionPacketSliceNanoseconds: 40_000_000,
            directPacketSliceNanoseconds: 2_000_000_000,
            urlSessionFinishSliceNanoseconds: 40_000_000,
            directFinishSliceNanoseconds: 2_000_000_000,
            sliceSlackNanoseconds: 500_000_000
        )
        let keepAlive = MockKeepAliveTransport(results: [
            .failure(FeishuAPIService.APIError.connectionFailed)
        ])
        let context = makeProbedContext(
            keepAlive: keepAlive,
            policy: policy,
            hangURLSession: true
        )
        let started = ContinuousClock.now

        do {
            _ = try await context.send(tokenRequest())
            XCTFail("connect-class miss must rethrow, not hop to a hung URLSession")
        } catch let error as FeishuAPIService.APIError {
            switch error {
            case .timeout, .connectionFailed, .networkError:
                break
            default:
                XCTFail("keep-alive miss must stay connect-class, got \(error)")
            }
        } catch {
            XCTFail("expected connect-class error, got \(error)")
        }

        let elapsed = ContinuousClock.now - started
        XCTAssertLessThan(
            elapsed,
            Duration.seconds(1),
            "connect-class miss must not wait for a URLSession slice"
        )
        XCTAssertEqual(keepAlive.recordedSendCount, 1)
        XCTAssertEqual(
            keepAlive.recordedDeadlineNanoseconds,
            policy.directSliceNanoseconds(for: .factoryToken)
        )
        XCTAssertEqual(URLSessionTestProbe.shared.recordedStartCount, 0)
        XCTAssertEqual(keepAlive.callLog.snapshot(), ["keepAlive"])
        XCTAssertFalse(keepAlive.callLog.snapshot().contains("urlSession"))
    }

    func test_abortDoesNotHopToURLSessionWhenKeepAliveIsPresent() async throws {
        let keepAlive = MockKeepAliveTransport(results: [
            .success(DirectHTTPResponse(statusCode: 200, body: Data()))
        ])
        let context = makeProbedContext(
            keepAlive: keepAlive,
            urlStatusCode: 500
        )

        let response = try await context.send(attemptRequest(phase: .abort))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(keepAlive.recordedSendCount, 1)
        XCTAssertEqual(
            keepAlive.recordedDeadlineNanoseconds,
            StreamingDrainPolicy().directSliceNanoseconds(for: .abort)
        )
        XCTAssertEqual(URLSessionTestProbe.shared.recordedStartCount, 0)
        XCTAssertEqual(keepAlive.callLog.snapshot(), ["keepAlive"])
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

    private func makeProbedContext(
        keepAlive: MockKeepAliveTransport,
        policy: StreamingDrainPolicy = StreamingDrainPolicy(),
        urlStatusCode: Int = 200,
        hangURLSession: Bool = false
    ) -> TransportAttemptContext {
        URLSessionTestProbe.shared.reset(
            statusCode: urlStatusCode,
            hang: hangURLSession,
            callLog: keepAlive.callLog
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProbedURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return TransportAttemptContext(
            policy: policy,
            session: session,
            keepAlive: keepAlive
        )
    }

    private func tokenRequest() -> AttemptHTTPRequest {
        attemptRequest(phase: .factoryToken)
    }

    private func attemptRequest(phase: AttemptHTTPPhase) -> AttemptHTTPRequest {
        AttemptHTTPRequest(
            request: URLRequest(url: URL(string: "https://open.feishu.cn/stream")!),
            phase: phase
        )
    }

    private func assertSameConnectClass(
        _ thrown: FeishuAPIService.APIError,
        _ expected: FeishuAPIService.APIError,
        phase: AttemptHTTPPhase
    ) {
        switch (thrown, expected) {
        case (.timeout, .timeout), (.connectionFailed, .connectionFailed):
            return
        case (.networkError(let got), .networkError(let want)):
            XCTAssertEqual(got, want, "networkError payload mismatch for \(phase)")
        default:
            XCTFail("expected \(expected) for \(phase), got \(thrown)")
        }
    }
}

private nonisolated final class TransportCallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func record(_ event: String) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

private nonisolated final class MockKeepAliveTransport: DirectKeepAliveTransport, @unchecked Sendable {
    let callLog = TransportCallLog()
    private let lock = NSLock()
    private var results: [Result<DirectHTTPResponse, Error>]
    private var sendCount = 0
    private var lastDeadlineNanoseconds: UInt64?

    init(results: [Result<DirectHTTPResponse, Error>]) {
        self.results = results
    }

    var recordedSendCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sendCount
    }

    var recordedDeadlineNanoseconds: UInt64? {
        lock.lock()
        defer { lock.unlock() }
        return lastDeadlineNanoseconds
    }

    func send(
        _ request: URLRequest,
        deadlineNanoseconds: UInt64
    ) async throws -> DirectHTTPResponse {
        _ = request
        let result = dequeueResult(deadlineNanoseconds: deadlineNanoseconds)
        callLog.record("keepAlive")
        return try result.get()
    }

    private func dequeueResult(deadlineNanoseconds: UInt64) -> Result<DirectHTTPResponse, Error> {
        lock.lock()
        defer { lock.unlock() }
        sendCount += 1
        lastDeadlineNanoseconds = deadlineNanoseconds
        if results.isEmpty {
            return .failure(FeishuAPIService.APIError.connectionFailed)
        }
        return results.removeFirst()
    }

    func forceCancel() {}
}

private nonisolated final class URLSessionTestProbe: @unchecked Sendable {
    static let shared = URLSessionTestProbe()

    private let lock = NSLock()
    private var startCount = 0
    private var statusCode = 200
    private var hang = false
    private var callLog: TransportCallLog?

    func reset(
        statusCode: Int = 200,
        hang: Bool = false,
        callLog: TransportCallLog? = nil
    ) {
        lock.lock()
        startCount = 0
        self.statusCode = statusCode
        self.hang = hang
        self.callLog = callLog
        lock.unlock()
    }

    func recordStart() -> (hang: Bool, statusCode: Int) {
        lock.lock()
        startCount += 1
        let shouldHang = hang
        let code = statusCode
        let log = callLog
        lock.unlock()
        log?.record("urlSession")
        return (shouldHang, code)
    }

    var recordedStartCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return startCount
    }
}

private final class ProbedURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let probe = URLSessionTestProbe.shared.recordStart()
        if probe.hang {
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: probe.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"code":0}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
