import Foundation
import XCTest
import os.log
@testable import FeishuSpeech

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "FeishuAPIServiceTests")

final class FeishuAPIServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        logger.debug("Starting FeishuAPIServiceTests")
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
        let service = FeishuAPIService.shared
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

    func test_resetStateForWake_clearsTokenNetworkErrorAndRefreshesAvailability() async {
        let service = FeishuAPIService.shared
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
