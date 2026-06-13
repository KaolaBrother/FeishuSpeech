import Foundation
import XCTest
import os.log
@testable import FeishuSpeech

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "FeishuAPIServiceTests")

final class FeishuAPIServiceTests: XCTestCase {
    private let service = FeishuAPIService.shared

    override func setUp() async throws {
        try await super.setUp()
        logger.debug("Starting FeishuAPIServiceTests")
        await service.resetForTesting()
    }

    override func tearDown() async throws {
        await service.resetForTesting()
        try await super.tearDown()
    }

    func test_authResponse_decodesExpireFromFeishuPayload() throws {
        let payload = Data("""
        {
          "code": 0,
          "msg": "ok",
          "tenant_access_token": "tenant-token",
          "expire": 7200
        }
        """.utf8)

        let response = try JSONDecoder().decode(AuthResponse.self, from: payload)

        XCTAssertEqual(response.tenantAccessToken, "tenant-token")
        XCTAssertEqual(response.expire, 7200)
    }

    func test_tokenLifetimeForValidExpire_usesExpireMinusSafetyMargin() {
        XCTAssertEqual(
            FeishuAPIService.tokenLifetimeForTesting(expire: 7200),
            6900,
            "Valid Feishu expire values must reserve a 300 second safety margin"
        )
    }

    func test_tokenLifetimeForMissingOrInvalidExpire_fallsBackToDefault() {
        XCTAssertEqual(FeishuAPIService.tokenLifetimeForTesting(expire: nil), 6000)
        XCTAssertEqual(FeishuAPIService.tokenLifetimeForTesting(expire: 0), 6000)
        XCTAssertEqual(FeishuAPIService.tokenLifetimeForTesting(expire: -1), 6000)
    }

    func test_tokenLifetimeForShortPositiveExpire_expiresImmediatelyInsteadOfDefaultFallback() {
        let lifetime = FeishuAPIService.tokenLifetimeForTesting(expire: 299)

        XCTAssertLessThanOrEqual(
            lifetime,
            0,
            "Short positive Feishu expire values must not fall back to the long default cache lifetime"
        )
    }

    func test_directHTTPParser_whenContentLengthBodyComplete_returnsResponse() throws {
        let response = try XCTUnwrap(
            FeishuAPIService.parseCompleteDirectHTTPResponseForTesting(
                httpResponse(headers: ["Content-Length": "11"], body: "hello world")
            )
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(data: response.body, encoding: .utf8), "hello world")
    }

    func test_directHTTPParser_whenContentLengthBodyIncomplete_waitsForMoreData() throws {
        let response = try FeishuAPIService.parseCompleteDirectHTTPResponseForTesting(
            httpResponse(headers: ["Content-Length": "12"], body: "hello")
        )

        XCTAssertNil(response)
    }

    func test_directHTTPParser_whenTerminalChunkedBodyComplete_returnsDecodedBody() throws {
        let chunkedBody = "5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n"
        let response = try XCTUnwrap(
            FeishuAPIService.parseCompleteDirectHTTPResponseForTesting(
                httpResponse(headers: ["Transfer-Encoding": "chunked"], body: chunkedBody)
            )
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(data: response.body, encoding: .utf8), "hello world")
    }

    func test_directHTTPParser_whenChunkedBodyLacksTerminalChunk_waitsForMoreData() throws {
        let chunkedBody = "5\r\nhello\r\n"
        let response = try FeishuAPIService.parseCompleteDirectHTTPResponseForTesting(
            httpResponse(headers: ["Transfer-Encoding": "chunked"], body: chunkedBody)
        )

        XCTAssertNil(response)
    }

    func test_directHTTPParser_whenCloseDelimited_waitsUntilConnectionClose() throws {
        let data = httpResponse(headers: ["Content-Type": "text/plain"], body: "close body")

        let earlyResponse = try FeishuAPIService.parseCompleteDirectHTTPResponseForTesting(data)
        XCTAssertNil(earlyResponse)

        let closedResponse = try FeishuAPIService.parseClosedDirectHTTPResponseForTesting(data)
        XCTAssertEqual(String(data: closedResponse.body, encoding: .utf8), "close body")
    }

    func test_directHTTPParser_whenStatusLineMalformed_throwsInvalidResponse() {
        XCTAssertThrowsError(
            try FeishuAPIService.parseCompleteDirectHTTPResponseForTesting(
                Data("HTTP/1.1 OK\r\nContent-Length: 0\r\n\r\n".utf8)
            )
        ) { error in
            assertInvalidResponse(error)
        }
    }

    func test_directHTTPParser_whenContentLengthInvalidOrNegative_throwsInvalidResponse() {
        for contentLength in ["abc", "-1"] {
            XCTAssertThrowsError(
                try FeishuAPIService.parseCompleteDirectHTTPResponseForTesting(
                    httpResponse(headers: ["Content-Length": contentLength], body: "")
                )
            ) { error in
                assertInvalidResponse(error)
            }
        }
    }

    func test_directHTTPParser_whenHeaderDelimiterMissing_waitsForMoreData() throws {
        let response = try FeishuAPIService.parseCompleteDirectHTTPResponseForTesting(
            Data("HTTP/1.1 200 OK\r\nContent-Length: 5\r\nhello".utf8)
        )

        XCTAssertNil(response)
    }

    func test_directHTTPParser_whenChunkSizeMalformed_throwsInvalidResponse() {
        XCTAssertThrowsError(
            try FeishuAPIService.parseCompleteDirectHTTPResponseForTesting(
                httpResponse(headers: ["Transfer-Encoding": "chunked"], body: "zz\r\nhello\r\n0\r\n\r\n")
            )
        ) { error in
            assertInvalidResponse(error)
        }
    }

    func test_directHTTPParser_whenChunkDataMissingTerminatingCRLF_throwsInvalidResponse() {
        XCTAssertThrowsError(
            try FeishuAPIService.parseCompleteDirectHTTPResponseForTesting(
                httpResponse(headers: ["Transfer-Encoding": "chunked"], body: "5\r\nhello0\r\n\r\n")
            )
        ) { error in
            assertInvalidResponse(error)
        }
    }

    func test_directHTTPParser_whenChunkExtensionsAndTrailersPresent_decodesBody() throws {
        let response = try XCTUnwrap(
            FeishuAPIService.parseCompleteDirectHTTPResponseForTesting(
                httpResponse(
                    headers: ["Transfer-Encoding": "chunked"],
                    body: "5;foo=bar\r\nhello\r\n0\r\nX-Trailer: yes\r\n\r\n"
                )
            )
        )

        XCTAssertEqual(String(data: response.body, encoding: .utf8), "hello")
    }

    func test_directHTTPParser_whenContentLengthHasExtraBytes_ignoresExtraBytes() throws {
        let response = try XCTUnwrap(
            FeishuAPIService.parseCompleteDirectHTTPResponseForTesting(
                httpResponse(headers: ["Content-Length": "5"], body: "hello ignored")
            )
        )

        XCTAssertEqual(String(data: response.body, encoding: .utf8), "hello")
    }

    func test_timeoutFallback_parsesCompleteBufferedContentLengthResponse() throws {
        let response = try FeishuAPIService.parseTimeoutBufferedDirectHTTPResponseForTesting(
            httpResponse(headers: ["Content-Length": "11"], body: "hello world")
        )

        XCTAssertEqual(String(data: response.body, encoding: .utf8), "hello world")
    }

    func test_timeoutFallback_rejectsIncompleteBufferedContentLengthBody() {
        XCTAssertThrowsError(
            try FeishuAPIService.parseTimeoutBufferedDirectHTTPResponseForTesting(
                httpResponse(headers: ["Content-Length": "12"], body: "hello")
            )
        ) { error in
            assertTimeout(error)
        }
    }

    func test_withRetry_whenOperationThrowsCancellation_attemptsOnceAndRethrows() async {
        await service.setNetworkAvailableForTesting(true)
        var attempts = 0

        do {
            try await service.withRetryForTesting(maxAttempts: 3) {
                attempts += 1
                throw CancellationError()
            }
            XCTFail("withRetryForTesting must rethrow CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertEqual(attempts, 1)
    }

    func test_sendDirectRequest_whenDirectSenderCancels_doesNotTryLaterIPsOrFallback() async {
        let service = FeishuAPIService.shared
        await service.setNetworkAvailableForTesting(true)
        var attemptedIPs: [String] = []
        var fallbackAttempts = 0

        do {
            _ = try await service.sendDirectRequestForTesting(
                ipAddresses: ["first", "second"],
                directSend: { ipAddress in
                    attemptedIPs.append(ipAddress)
                    throw CancellationError()
                },
                fallbackSend: {
                    fallbackAttempts += 1
                    return DirectHTTPResponse(statusCode: 200, body: Data())
                }
            )
            XCTFail("sendDirectRequestForTesting must rethrow CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertEqual(attemptedIPs, ["first"])
        XCTAssertEqual(fallbackAttempts, 0)
    }

    func test_withRetry_whenRetriableError_recordsRetryDelaysWithoutSleeping() async throws {
        var attempts = 0
        var delays: [TimeInterval] = []
        await service.setRetrySleeperForTesting { delay in
            delays.append(delay)
        }

        try await service.withRetryForTesting(maxAttempts: 3) {
            attempts += 1
            if attempts < 3 {
                throw FeishuAPIService.APIError.timeout
            }
        }

        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(delays, [1.0, 2.0])
    }

    func test_withRetry_whenAuthFailed_doesNotRetryOrSleep() async {
        var attempts = 0
        var delays: [TimeInterval] = []
        await service.setRetrySleeperForTesting { delay in
            delays.append(delay)
        }

        do {
            try await service.withRetryForTesting(maxAttempts: 3) {
                attempts += 1
                throw FeishuAPIService.APIError.authFailed("bad secret")
            }
            XCTFail("withRetryForTesting must throw authFailed")
        } catch FeishuAPIService.APIError.authFailed {
            // Expected.
        } catch {
            XCTFail("Expected authFailed, got \(error)")
        }

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(delays, [])
    }

    func test_withRetry_whenGenericErrorsExhaust_rethrowsLastError() async {
        struct RetryProbeError: Error, Equatable {
            let id: Int
        }

        var attempts = 0
        var delays: [TimeInterval] = []
        await service.setRetrySleeperForTesting { delay in
            delays.append(delay)
        }

        do {
            try await service.withRetryForTesting(maxAttempts: 3) {
                attempts += 1
                throw RetryProbeError(id: attempts)
            }
            XCTFail("withRetryForTesting must throw the last generic error")
        } catch let error as RetryProbeError {
            XCTAssertEqual(error, RetryProbeError(id: 3))
        } catch {
            XCTFail("Expected RetryProbeError, got \(error)")
        }

        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(delays, [1.0, 2.0])
    }

    func test_withRetry_whenNetworkUnavailable_preflightAvoidsOperation() async {
        await service.setNetworkAvailableForTesting(false)
        var attempts = 0

        do {
            try await service.withRetryForTesting(maxAttempts: 3) {
                attempts += 1
            }
            XCTFail("withRetryForTesting must throw networkUnavailable")
        } catch FeishuAPIService.APIError.networkUnavailable {
            // Expected.
        } catch {
            XCTFail("Expected networkUnavailable, got \(error)")
        }

        XCTAssertEqual(attempts, 0)
    }

    func test_recognizeSpeech_whenAuthSucceeds_cachesTokenForSecondRequest() async throws {
        let transport = MockFeishuRequestSequence([
            .success(jsonResponse(authJSON(token: "cached-token"))),
            .success(jsonResponse(speechJSON(text: "first"))),
            .success(jsonResponse(speechJSON(text: "second")))
        ])
        await service.setDirectRequestSenderForTesting(transport.send)

        let first = try await service.recognizeSpeech(audioData: Data([1, 2]), appId: "app", appSecret: "secret")
        let second = try await service.recognizeSpeech(audioData: Data([3, 4]), appId: "app", appSecret: "secret")

        XCTAssertEqual(first, "first")
        XCTAssertEqual(second, "second")
        XCTAssertEqual(transport.requestPaths(), [
            FeishuAPIService.authPathForTesting,
            FeishuAPIService.speechPathForTesting,
            FeishuAPIService.speechPathForTesting
        ])
        XCTAssertEqual(transport.authorizationHeaders(), [
            "Bearer cached-token",
            "Bearer cached-token"
        ])
    }

    func test_recognizeSpeech_whenSpeechReturns400_clearsTokenAndRetriesWithFreshAuth() async throws {
        try await assertSpeechHTTPErrorRefreshesToken(statusCode: 400)
    }

    func test_recognizeSpeech_whenSpeechReturns401_clearsTokenAndRetriesWithFreshAuth() async throws {
        try await assertSpeechHTTPErrorRefreshesToken(statusCode: 401)
    }

    func test_resetStateForWake_clearsTokenNetworkErrorAndRefreshesAvailability() async {
        await service.seedStateForWakeTesting(
            cachedToken: "stale-token",
            tokenExpiresIn: 600,
            lastNetworkError: FeishuAPIService.APIError.connectionFailed,
            isNetworkAvailable: false
        )

        await service.resetStateForWake()

        let snapshot = await service.stateSnapshotForTesting()
        XCTAssertFalse(snapshot.hasCachedToken, "wake reset must clear stale cached token")
        XCTAssertFalse(snapshot.hasTokenExpiry, "wake reset must clear stale token expiry")
        XCTAssertNil(snapshot.lastNetworkErrorDescription, "wake reset must clear stale network error")
        XCTAssertTrue(snapshot.isNetworkAvailable, "wake reset must allow fresh network checks after wake")
    }

    private func assertSpeechHTTPErrorRefreshesToken(statusCode: Int) async throws {
        let transport = MockFeishuRequestSequence([
            .success(jsonResponse(authJSON(token: "stale-token"))),
            .success(jsonResponse(["code": 999, "msg": "expired"], statusCode: statusCode)),
            .success(jsonResponse(authJSON(token: "fresh-token"))),
            .success(jsonResponse(speechJSON(text: "fresh result")))
        ])
        await service.setDirectRequestSenderForTesting(transport.send)

        let result = try await service.recognizeSpeech(audioData: Data([1, 2]), appId: "app", appSecret: "secret")

        XCTAssertEqual(result, "fresh result")
        XCTAssertEqual(transport.requestPaths(), [
            FeishuAPIService.authPathForTesting,
            FeishuAPIService.speechPathForTesting,
            FeishuAPIService.authPathForTesting,
            FeishuAPIService.speechPathForTesting
        ])
        XCTAssertEqual(transport.authorizationHeaders(), [
            "Bearer stale-token",
            "Bearer fresh-token"
        ])
    }
}

private func httpResponse(headers: [String: String], body: String) -> Data {
    let headerLines = headers
        .map { "\($0.key): \($0.value)" }
        .joined(separator: "\r\n")
    return Data("HTTP/1.1 200 OK\r\n\(headerLines)\r\n\r\n\(body)".utf8)
}

private func assertTimeout(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
    guard case FeishuAPIService.APIError.timeout = error else {
        XCTFail("Expected APIError.timeout, got \(error)", file: file, line: line)
        return
    }
}

private func assertInvalidResponse(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
    guard case FeishuAPIService.APIError.invalidResponse = error else {
        XCTFail("Expected APIError.invalidResponse, got \(error)", file: file, line: line)
        return
    }
}

private func authJSON(token: String) -> [String: Any] {
    [
        "code": 0,
        "msg": "ok",
        "tenant_access_token": token,
        "expire": 7200
    ]
}

private func speechJSON(text: String) -> [String: Any] {
    [
        "code": 0,
        "msg": "ok",
        "data": [
            "recognition_text": text
        ]
    ]
}

private func jsonResponse(_ json: [String: Any], statusCode: Int = 200) -> DirectHTTPResponse {
    let data = try! JSONSerialization.data(withJSONObject: json)
    return DirectHTTPResponse(statusCode: statusCode, body: data)
}
