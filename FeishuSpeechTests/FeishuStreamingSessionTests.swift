import Foundation
import XCTest
import os.log
@testable import FeishuSpeech

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "FeishuStreamingSessionTests")

final class FeishuStreamingSessionTests: XCTestCase {
    func test_firstPacketBackendBusinessFailureEmitsOnlySafeStructuredDiagnostic() async throws {
        let response = DirectHTTPResponse(
            statusCode: 200,
            body: try JSONSerialization.data(withJSONObject: [
                "code": 123_456,
                "msg": "PRIVATE_BACKEND_MESSAGE",
                "data": ["recognition_text": "PRIVATE_TRANSCRIPT"]
            ])
        )

        let diagnostic = try await captureFirstPacketFailure(
            response: response,
            expectedFailure: .backend
        )

        XCTAssertEqual(diagnostic.action, 1)
        XCTAssertEqual(diagnostic.sequenceID, 0)
        XCTAssertEqual(diagnostic.httpStatus, 200)
        XCTAssertEqual(diagnostic.responseByteCount, response.body.count)
        XCTAssertEqual(diagnostic.businessCode, 123_456)
        XCTAssertNil(diagnostic.dataPresent)
        XCTAssertNil(diagnostic.streamIDMatches)
        XCTAssertNil(diagnostic.sequenceIDMatches)
        XCTAssertEqual(diagnostic.outcome, .backendBusinessCode)
        assertSafeDiagnosticSurface(
            diagnostic,
            forbiddenValues: [
                "PRIVATE_BACKEND_MESSAGE",
                "PRIVATE_TRANSCRIPT",
                "PRIVATE_TOKEN",
                "fixed_stream_016",
                "PRIVATE_AUDIO"
            ]
        )
    }

    func test_firstPacketMalformedJSONEmitsOnlySafeStructuredDiagnostic() async throws {
        let response = DirectHTTPResponse(
            statusCode: 200,
            body: Data("PRIVATE_RAW_BODY PRIVATE_TRANSCRIPT PRIVATE_TOKEN".utf8)
        )

        let diagnostic = try await captureFirstPacketFailure(
            response: response,
            expectedFailure: .malformedResponse
        )

        XCTAssertEqual(diagnostic.action, 1)
        XCTAssertEqual(diagnostic.sequenceID, 0)
        XCTAssertEqual(diagnostic.httpStatus, 200)
        XCTAssertEqual(diagnostic.responseByteCount, response.body.count)
        XCTAssertNil(diagnostic.businessCode)
        XCTAssertNil(diagnostic.dataPresent)
        XCTAssertNil(diagnostic.streamIDMatches)
        XCTAssertNil(diagnostic.sequenceIDMatches)
        XCTAssertEqual(diagnostic.outcome, .malformedJSON)
        assertSafeDiagnosticSurface(
            diagnostic,
            forbiddenValues: [
                "PRIVATE_RAW_BODY",
                "PRIVATE_TRANSCRIPT",
                "PRIVATE_TOKEN",
                "fixed_stream_016",
                "PRIVATE_AUDIO"
            ]
        )
    }

    func test_firstPacketCodeZeroMissingDataEmitsOnlySafeStructuredDiagnostic() async throws {
        let response = DirectHTTPResponse(
            statusCode: 200,
            body: try JSONSerialization.data(withJSONObject: [
                "code": 0,
                "msg": "PRIVATE_BACKEND_MESSAGE"
            ])
        )

        let diagnostic = try await captureFirstPacketFailure(
            response: response,
            expectedFailure: .malformedResponse
        )

        XCTAssertEqual(diagnostic.action, 1)
        XCTAssertEqual(diagnostic.sequenceID, 0)
        XCTAssertEqual(diagnostic.httpStatus, 200)
        XCTAssertEqual(diagnostic.responseByteCount, response.body.count)
        XCTAssertEqual(diagnostic.businessCode, 0)
        XCTAssertEqual(diagnostic.dataPresent, false)
        XCTAssertNil(diagnostic.streamIDMatches)
        XCTAssertNil(diagnostic.sequenceIDMatches)
        XCTAssertEqual(diagnostic.outcome, .missingData)
        assertSafeDiagnosticSurface(
            diagnostic,
            forbiddenValues: [
                "PRIVATE_BACKEND_MESSAGE",
                "PRIVATE_TOKEN",
                "fixed_stream_016",
                "PRIVATE_AUDIO"
            ]
        )
    }

    func test_firstPacketStreamIDMismatchEmitsOnlySafeStructuredDiagnostic() async throws {
        let response = streamResponseWithIdentity(
            streamID: "PRIVATE_WRONG_ID",
            sequenceID: 0,
            text: "PRIVATE_TRANSCRIPT"
        )

        let diagnostic = try await captureFirstPacketFailure(
            response: response,
            expectedFailure: .responseIdentityMismatch,
            injectsRequestIdentity: false
        )

        XCTAssertEqual(diagnostic.action, 1)
        XCTAssertEqual(diagnostic.sequenceID, 0)
        XCTAssertEqual(diagnostic.httpStatus, 200)
        XCTAssertEqual(diagnostic.responseByteCount, response.body.count)
        XCTAssertEqual(diagnostic.businessCode, 0)
        XCTAssertEqual(diagnostic.dataPresent, true)
        XCTAssertEqual(diagnostic.streamIDMatches, false)
        XCTAssertNil(diagnostic.sequenceIDMatches)
        XCTAssertEqual(diagnostic.outcome, .streamIDMismatch)
        assertSafeDiagnosticSurface(
            diagnostic,
            forbiddenValues: [
                "PRIVATE_WRONG_ID",
                "PRIVATE_TRANSCRIPT",
                "PRIVATE_TOKEN",
                "fixed_stream_016",
                "PRIVATE_AUDIO"
            ]
        )
    }

    func test_firstPacketSequenceIDMismatchEmitsOnlySafeStructuredDiagnostic() async throws {
        let response = streamResponseWithIdentity(
            streamID: "fixed_stream_016",
            sequenceID: 99,
            text: "PRIVATE_TRANSCRIPT"
        )

        let diagnostic = try await captureFirstPacketFailure(
            response: response,
            expectedFailure: .responseIdentityMismatch,
            injectsRequestIdentity: false
        )

        XCTAssertEqual(diagnostic.action, 1)
        XCTAssertEqual(diagnostic.sequenceID, 0)
        XCTAssertEqual(diagnostic.httpStatus, 200)
        XCTAssertEqual(diagnostic.responseByteCount, response.body.count)
        XCTAssertEqual(diagnostic.businessCode, 0)
        XCTAssertEqual(diagnostic.dataPresent, true)
        XCTAssertEqual(diagnostic.streamIDMatches, true)
        XCTAssertEqual(diagnostic.sequenceIDMatches, false)
        XCTAssertEqual(diagnostic.outcome, .sequenceIDMismatch)
        assertSafeDiagnosticSurface(
            diagnostic,
            forbiddenValues: [
                "PRIVATE_TRANSCRIPT",
                "PRIVATE_TOKEN",
                "fixed_stream_016",
                "PRIVATE_AUDIO"
            ]
        )
    }

    func test_typedEvents_preserveOpaqueReplacementValuesAndTypedFailures() {
        XCTAssertEqual(StreamingRecognitionEvent.partial("revised complete value"), .partial("revised complete value"))
        XCTAssertEqual(StreamingRecognitionEvent.final("authoritative final"), .final("authoritative final"))
        XCTAssertEqual(StreamingRecognitionEvent.cancelled, .cancelled)
        XCTAssertEqual(StreamingRecognitionEvent.failed(.timeout), .failed(.timeout))
    }

    func test_packetsFinishAndIdentity_useOneStrictSerialActionSequence() async throws {
        let transport = StreamingRequestStub(responses: [
            streamResponse(text: "opaque one"),
            streamResponse(text: "opaque revision"),
            streamResponse(text: "final authority")
        ])
        let session = FeishuStreamingSession(
            initialToken: "warm-token",
            refreshToken: { "unused-refresh" },
            requestSender: { request in try await transport.send(request) }
        )

        let first = try await session.sendAudioPacket(Data(repeating: 0x11, count: 6_400))
        let second = try await session.sendAudioPacket(Data(repeating: 0x22, count: 6_400))
        let final = try await session.finish()
        let duplicateFinish = try await session.finish()

        XCTAssertEqual(first, .partial("opaque one"))
        XCTAssertEqual(second, .partial("opaque revision"))
        XCTAssertEqual(final, .final("final authority"))
        XCTAssertEqual(duplicateFinish, final)

        let requests = try await transport.parsedRequests()
        XCTAssertEqual(requests.map(\.action), [1, 0, 2])
        XCTAssertEqual(requests.map(\.sequenceID), [0, 1, 2])
        XCTAssertEqual(requests.map(\.pcmByteCount), [6_400, 6_400, 0])
        XCTAssertTrue(requests.allSatisfy {
            $0.method == "POST"
                && $0.path == "/open-apis/speech_to_text/v1/speech/stream_recognize"
                && $0.contentType.lowercased() == "application/json; charset=utf-8"
        })
        XCTAssertEqual(Set(requests.map(\.streamID)).count, 1)
        let streamID = try XCTUnwrap(requests.first?.streamID)
        XCTAssertEqual(streamID.count, 16)
        XCTAssertNotNil(streamID.range(of: #"^[a-z0-9_]{16}$"#, options: .regularExpression))
        XCTAssertTrue(requests.allSatisfy { $0.authorization == "Bearer warm-token" })
        XCTAssertTrue(requests.allSatisfy { $0.format == "pcm" && $0.engineType == "16k_auto" })
    }

    func test_overlappingPacketCalls_neverCreateParallelRequests() async throws {
        let transport = StreamingRequestStub(
            responses: [streamResponse(text: "first"), streamResponse(text: "second")],
            gateFirstRequest: true
        )
        let session = FeishuStreamingSession(
            streamID: "fixed_stream_001",
            initialToken: "token",
            refreshToken: { "unused" },
            requestSender: { request in try await transport.send(request) }
        )

        let first = Task { try await session.sendAudioPacket(Data(repeating: 1, count: 6_400)) }
        await transport.waitForRequestCount(1)
        let second = Task { try await session.sendAudioPacket(Data(repeating: 2, count: 6_400)) }
        try await Task.sleep(nanoseconds: 50_000_000)

        let requestCountWhileFirstIsPending = await transport.requestCount
        let maximumWhileFirstIsPending = await transport.maximumActiveRequestCount
        XCTAssertEqual(requestCountWhileFirstIsPending, 1)
        XCTAssertEqual(maximumWhileFirstIsPending, 1)

        await transport.releaseFirstRequest()
        _ = try await first.value
        _ = try await second.value
        let maximumActiveRequestCount = await transport.maximumActiveRequestCount
        let sequenceIDs = try await transport.parsedRequests().map(\.sequenceID)
        XCTAssertEqual(maximumActiveRequestCount, 1)
        XCTAssertEqual(sequenceIDs, [0, 1])
    }

    func test_cancelClaimsTerminalIntentAndReturnsWhileFirstPacketSenderIgnoresCancellation() async throws {
        let transport = StreamingRequestStub(
            responses: [
                streamResponse(text: "late first response"),
                streamResponse(text: "abort response")
            ],
            gatedRequestOrdinals: [1]
        )
        let session = FeishuStreamingSession(
            streamID: "fixed_stream_007",
            initialToken: "token",
            refreshToken: { "unused" },
            requestSender: { request in try await transport.send(request) }
        )

        let firstPacket = Task {
            try await session.sendAudioPacket(Data(repeating: 0x31, count: 6_400))
        }
        await transport.waitForRequestCount(1)

        let cancelOutcome = OperationOutcomeProbe()
        let cancelTask = Task {
            await session.cancel()
            await cancelOutcome.record(.completed)
        }
        await Task.yield()

        let latePacketOutcome = OperationOutcomeProbe()
        let latePacket = Task {
            do {
                _ = try await session.sendAudioPacket(Data(repeating: 0x32, count: 6_400))
                await latePacketOutcome.record(.completed)
            } catch let failure as StreamFailure {
                await latePacketOutcome.record(.failure(failure))
            } catch {
                await latePacketOutcome.record(.unexpectedFailure)
            }
        }

        try await Task.sleep(nanoseconds: 1_200_000_000)

        let observedCancelOutcome = await cancelOutcome.outcome
        let observedLatePacketOutcome = await latePacketOutcome.outcome
        let maximumActiveRequestCount = await transport.maximumActiveRequestCount
        XCTAssertEqual(
            observedCancelOutcome,
            .completed,
            "cancel must not wait forever for the in-flight packet sender"
        )
        XCTAssertEqual(
            observedLatePacketOutcome,
            .failure(.cancelled),
            "terminal intent must reject later packets before the stuck sender returns"
        )
        XCTAssertEqual(maximumActiveRequestCount, 1)

        await transport.releaseRequest(1)
        _ = await firstPacket.result
        await cancelTask.value
        await latePacket.value
    }

    func test_cancelAndFinishReturnByDeadlineWhenAbortSenderIgnoresCancellation() async throws {
        let transport = StreamingRequestStub(
            responses: [
                streamResponse(text: "accepted"),
                streamResponse(text: "late abort response")
            ],
            gatedRequestOrdinals: [2]
        )
        let session = FeishuStreamingSession(
            streamID: "fixed_stream_008",
            initialToken: "token",
            refreshToken: { "unused" },
            requestSender: { request in try await transport.send(request) }
        )
        _ = try await session.sendAudioPacket(Data(repeating: 0x33, count: 6_400))

        let cancelOutcome = OperationOutcomeProbe()
        let cancelTask = Task {
            await session.cancel()
            await cancelOutcome.record(.completed)
        }
        await transport.waitForRequestCount(2)

        let finishOutcome = OperationOutcomeProbe()
        let finishTask = Task {
            do {
                let event = try await session.finish()
                await finishOutcome.record(.event(event))
            } catch let failure as StreamFailure {
                await finishOutcome.record(.failure(failure))
            } catch {
                await finishOutcome.record(.unexpectedFailure)
            }
        }

        try await Task.sleep(nanoseconds: 1_200_000_000)

        let observedCancelOutcome = await cancelOutcome.outcome
        let observedFinishOutcome = await finishOutcome.outcome
        let maximumActiveRequestCount = await transport.maximumActiveRequestCount
        XCTAssertEqual(
            observedCancelOutcome,
            .completed,
            "best-effort action 3 must return when its local deadline expires"
        )
        XCTAssertEqual(
            observedFinishOutcome,
            .event(.cancelled),
            "the first cancel intent must be visible without waiting for action 3"
        )
        XCTAssertEqual(maximumActiveRequestCount, 1, "terminal requests must never overlap")

        await transport.releaseRequest(2)
        await cancelTask.value
        _ = await finishTask.result
    }

    func test_cancelDuringEstablishedContinuationDefersOneSerialAbortUntilPacketReleases() async throws {
        let transport = StreamingRequestStub(
            responses: [
                streamResponse(text: "accepted"),
                streamResponse(text: "cancelled continuation"),
                streamResponse(text: "abort acknowledged")
            ],
            gatedRequestOrdinals: [2]
        )
        let session = FeishuStreamingSession(
            streamID: "fixed_stream_014",
            initialToken: "token",
            refreshToken: { "unused" },
            requestSender: { request in try await transport.send(request) }
        )
        _ = try await session.sendAudioPacket(Data(repeating: 0x34, count: 6_400))

        let continuationOutcome = OperationOutcomeProbe()
        let continuation = Task {
            do {
                _ = try await session.sendAudioPacket(Data(repeating: 0x35, count: 6_400))
                await continuationOutcome.record(.completed)
            } catch let failure as StreamFailure {
                await continuationOutcome.record(.failure(failure))
            } catch {
                await continuationOutcome.record(.unexpectedFailure)
            }
        }
        await transport.waitForRequestCount(2)

        let cancelOutcome = OperationOutcomeProbe()
        let cancel = Task {
            await session.cancel()
            await cancelOutcome.record(.completed)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        await transport.releaseRequest(2)
        await transport.waitForRequestCount(3)
        try await Task.sleep(nanoseconds: 1_100_000_000)

        let requests = try await transport.parsedRequests()
        let maximumActiveRequestCount = await transport.maximumActiveRequestCount
        let observedCancelOutcome = await cancelOutcome.outcome
        let observedContinuationOutcome = await continuationOutcome.outcome
        XCTAssertEqual(
            observedCancelOutcome,
            .completed,
            "cancel must finish within its bounded abort deadline"
        )
        XCTAssertEqual(observedContinuationOutcome, .failure(.cancelled))
        XCTAssertEqual(requests.map(\.action), [1, 0, 3])
        XCTAssertEqual(requests.map(\.sequenceID), [0, 1, 1])
        XCTAssertEqual(requests.filter { $0.action == 3 }.count, 1)
        XCTAssertEqual(maximumActiveRequestCount, 1, "action 3 must wait for action 0 to release the gate")

        await session.cancel()
        let finalAbortCount = try await transport.parsedRequests().filter { $0.action == 3 }.count
        XCTAssertEqual(finalAbortCount, 1, "repeated cancel must not emit another abort")
        await cancel.value
        await continuation.value
    }

    func test_cancelAfterAction2NeverEmitsAbort() async throws {
        let transport = StreamingRequestStub(responses: [
            streamResponse(text: "accepted"),
            streamResponse(text: "final")
        ])
        let session = FeishuStreamingSession(
            streamID: "fixed_stream_015",
            initialToken: "token",
            refreshToken: { "unused" },
            requestSender: { request in try await transport.send(request) }
        )

        _ = try await session.sendAudioPacket(Data(repeating: 0x36, count: 6_400))
        _ = try await session.finish()
        await session.cancel()
        await session.cancel()

        let actions = try await transport.parsedRequests().map(\.action)
        XCTAssertEqual(actions, [1, 2])
        XCTAssertFalse(actions.contains(3), "action 3 is forbidden after action 2 was emitted")
    }

    func test_knownInvalidTokenBeforeAcceptance_refreshesOnceAndRetriesSameFirstPacketAndSequence() async throws {
        let transport = StreamingRequestStub(responses: [
            streamResponse(code: 9_999_1663, message: "raw invalid token detail", text: ""),
            streamResponse(text: "accepted"),
            streamResponse(text: "final")
        ])
        let refreshes = RefreshTokenStub(tokens: ["fresh-token"])
        let session = FeishuStreamingSession(
            streamID: "fixed_stream_002",
            initialToken: "stale-token",
            refreshToken: { try await refreshes.next() },
            requestSender: { request in try await transport.send(request) }
        )

        let accepted = try await session.sendAudioPacket(Data(repeating: 0x41, count: 6_400))
        XCTAssertEqual(accepted, .partial("accepted"))
        _ = try await session.finish()

        let requests = try await transport.parsedRequests()
        XCTAssertEqual(requests.map(\.action), [1, 1, 2])
        XCTAssertEqual(requests.map(\.sequenceID), [0, 0, 1])
        XCTAssertEqual(
            requests.map(\.authorization),
            ["Bearer stale-token", "Bearer fresh-token", "Bearer fresh-token"]
        )
        let refreshCallCount = await refreshes.callCount
        XCTAssertEqual(refreshCallCount, 1)
    }

    func test_knownInvalidTokenInHTTP400Or401RefreshesSameFirstRequestButGeneric400IsTerminal() async {
        for statusCode in [400, 401] {
            let transport = StreamingRequestStub(responses: [
                httpBusinessResponse(statusCode: statusCode, code: 99_991_663),
                streamResponse(text: "accepted after refresh")
            ])
            let refreshes = RefreshTokenStub(tokens: ["fresh-token"])
            let session = FeishuStreamingSession(
                streamID: "fixed_stream_009",
                initialToken: "stale-token",
                refreshToken: { try await refreshes.next() },
                requestSender: { request in try await transport.send(request) }
            )

            do {
                let event = try await session.sendAudioPacket(Data(repeating: 0x42, count: 6_400))
                XCTAssertEqual(event, .partial("accepted after refresh"))
            } catch {
                XCTFail("known token code in HTTP \(statusCode) must refresh once, got \(error)")
            }

            let requests = (try? await transport.parsedRequests()) ?? []
            let refreshCallCount = await refreshes.callCount
            XCTAssertEqual(requests.map(\.action), [1, 1])
            XCTAssertEqual(requests.map(\.sequenceID), [0, 0])
            XCTAssertEqual(
                requests.map(\.authorization),
                ["Bearer stale-token", "Bearer fresh-token"]
            )
            XCTAssertEqual(refreshCallCount, 1)
        }

        let genericTransport = StreamingRequestStub(responses: [
            httpBusinessResponse(statusCode: 400, code: 123_400)
        ])
        let genericRefreshes = RefreshTokenStub(tokens: ["must-not-refresh"])
        let genericSession = FeishuStreamingSession(
            streamID: "fixed_stream_010",
            initialToken: "token",
            refreshToken: { try await genericRefreshes.next() },
            requestSender: { request in try await genericTransport.send(request) }
        )

        do {
            _ = try await genericSession.sendAudioPacket(Data(repeating: 0x43, count: 6_400))
            XCTFail("generic HTTP 400 must remain terminal")
        } catch let failure as StreamFailure {
            XCTAssertEqual(failure, .httpStatus)
        } catch {
            XCTFail("expected sanitized StreamFailure.httpStatus, got \(error)")
        }
        let genericRefreshCallCount = await genericRefreshes.callCount
        let genericRequestCount = await genericTransport.requestCount
        XCTAssertEqual(genericRefreshCallCount, 0)
        XCTAssertEqual(genericRequestCount, 1)
    }

    func test_successAcceptsOmittedIdentityEchoesOnPacket() async {
        let omittedTransport = StreamingRequestStub(
            responses: [streamResponseOmittingIdentity(text: "partial without echo")],
            injectsRequestIdentity: false
        )
        let omittedSession = FeishuStreamingSession(
            streamID: "fixed_stream_011",
            initialToken: "token",
            refreshToken: { "unused" },
            requestSender: { request in try await omittedTransport.send(request) }
        )

        do {
            let partial = try await omittedSession.sendAudioPacket(Data(repeating: 0x44, count: 6_400))
            XCTAssertEqual(partial, .partial("partial without echo"))
        } catch {
            XCTFail("successful packet response may omit identity echoes, got \(error)")
        }
    }

    func test_successAcceptsOmittedIdentityEchoesOnFinish() async {
        let omittedTransport = StreamingRequestStub(
            responses: [
                streamResponseWithIdentity(
                    streamID: "fixed_stream_013",
                    sequenceID: 0,
                    text: "accepted"
                ),
                streamResponseOmittingIdentity(text: "final without echo")
            ],
            injectsRequestIdentity: false
        )
        let omittedSession = FeishuStreamingSession(
            streamID: "fixed_stream_013",
            initialToken: "token",
            refreshToken: { "unused" },
            requestSender: { request in try await omittedTransport.send(request) }
        )

        do {
            _ = try await omittedSession.sendAudioPacket(Data(repeating: 0x46, count: 6_400))
            let final = try await omittedSession.finish()
            XCTAssertEqual(final, .final("final without echo"))
        } catch {
            XCTFail("successful terminal response may omit identity echoes, got \(error)")
        }
    }

    func test_successRejectsProvidedIdentityMismatches() async {
        for mismatch in [
            streamResponseWithIdentity(streamID: "wrong_stream_000", sequenceID: 0, text: "wrong stream"),
            streamResponseWithIdentity(streamID: "fixed_stream_012", sequenceID: 99, text: "wrong sequence")
        ] {
            let mismatchTransport = StreamingRequestStub(
                responses: [mismatch],
                injectsRequestIdentity: false
            )
            let mismatchSession = FeishuStreamingSession(
                streamID: "fixed_stream_012",
                initialToken: "token",
                refreshToken: { "unused" },
                requestSender: { request in try await mismatchTransport.send(request) }
            )
            do {
                _ = try await mismatchSession.sendAudioPacket(Data(repeating: 0x45, count: 6_400))
                XCTFail("a provided response identity mismatch must be rejected")
            } catch let failure as StreamFailure {
                XCTAssertEqual(failure, .responseIdentityMismatch)
            } catch {
                XCTFail("expected responseIdentityMismatch, got \(error)")
            }
        }
    }

    func test_failureAfterFirstAcceptance_doesNotReplayRefreshOrFallbackAndSanitizesPublicError() async throws {
        let privateText = "PRIVATE_TRANSCRIPT"
        let privateMessage = "RAW_BACKEND_MESSAGE token=PRIVATE_TOKEN"
        let transport = StreamingRequestStub(responses: [
            streamResponse(text: "accepted"),
            streamResponse(code: 123_456, message: privateMessage, text: privateText)
        ])
        let refreshes = RefreshTokenStub(tokens: ["must-not-refresh"])
        let session = FeishuStreamingSession(
            streamID: "fixed_stream_003",
            initialToken: "PRIVATE_TOKEN",
            refreshToken: { try await refreshes.next() },
            requestSender: { request in try await transport.send(request) }
        )

        _ = try await session.sendAudioPacket(Data(repeating: 0x51, count: 6_400))
        do {
            _ = try await session.sendAudioPacket(Data(repeating: 0x52, count: 6_400))
            XCTFail("an established stream must fail without replay")
        } catch {
            let publicSurface = error.localizedDescription + String(reflecting: error)
            for secret in [privateText, privateMessage, "PRIVATE_TOKEN", "fixed_stream_003"] {
                XCTAssertFalse(publicSurface.contains(secret), "public failure leaked \(secret)")
            }
        }

        let requestCount = await transport.requestCount
        let refreshCallCount = await refreshes.callCount
        let actions = try await transport.parsedRequests().map(\.action)
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(refreshCallCount, 0)
        XCTAssertEqual(actions, [1, 0])
    }

    func test_cancelBeforeAcceptanceIsLocal_andActiveCancelEmitsOneAbortOnly() async throws {
        let inactiveTransport = StreamingRequestStub(responses: [])
        let inactive = FeishuStreamingSession(
            streamID: "fixed_stream_004",
            initialToken: "token",
            refreshToken: { "unused" },
            requestSender: { request in try await inactiveTransport.send(request) }
        )

        let localFinish = try await inactive.finish()
        XCTAssertEqual(localFinish, .cancelled)
        await inactive.cancel()
        await inactive.cancel()
        let inactiveRequestCount = await inactiveTransport.requestCount
        XCTAssertEqual(inactiveRequestCount, 0)

        let activeTransport = StreamingRequestStub(responses: [
            streamResponse(text: "partial"),
            streamResponse(text: "abort acknowledged")
        ])
        let active = FeishuStreamingSession(
            streamID: "fixed_stream_005",
            initialToken: "token",
            refreshToken: { "unused" },
            requestSender: { request in try await activeTransport.send(request) }
        )
        _ = try await active.sendAudioPacket(Data(repeating: 0x61, count: 6_400))

        await active.cancel()
        await active.cancel()

        let requests = try await activeTransport.parsedRequests()
        XCTAssertEqual(requests.map(\.action), [1, 3])
        XCTAssertEqual(requests.map(\.sequenceID), [0, 1])
        XCTAssertEqual(requests.filter { $0.action == 3 }.count, 1)
    }

    func test_non200RawBody_isSanitizedAndNeverRetried() async {
        let rawBody = Data("RAW_BODY PRIVATE_TRANSCRIPT PRIVATE_TOKEN".utf8)
        let transport = StreamingRequestStub(responses: [DirectHTTPResponse(statusCode: 500, body: rawBody)])
        let session = FeishuStreamingSession(
            streamID: "fixed_stream_006",
            initialToken: "PRIVATE_TOKEN",
            refreshToken: { "unused" },
            requestSender: { request in try await transport.send(request) }
        )

        do {
            _ = try await session.sendAudioPacket(Data(repeating: 0x71, count: 6_400))
            XCTFail("HTTP failure must terminate the current stream")
        } catch {
            let publicSurface = error.localizedDescription + String(reflecting: error)
            for secret in ["RAW_BODY", "PRIVATE_TRANSCRIPT", "PRIVATE_TOKEN", "fixed_stream_006"] {
                XCTAssertFalse(publicSurface.contains(secret), "public failure leaked \(secret)")
            }
        }

        let requestCount = await transport.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    private func captureFirstPacketFailure(
        response: DirectHTTPResponse,
        expectedFailure: StreamFailure,
        injectsRequestIdentity: Bool = false
    ) async throws -> StreamingResponseDiagnostic {
        let diagnostics = LockedDiagnosticRecorder<StreamingResponseDiagnostic>()
        let transport = StreamingRequestStub(
            responses: [response],
            injectsRequestIdentity: injectsRequestIdentity
        )
        let session = FeishuStreamingSession(
            streamID: "fixed_stream_016",
            initialToken: "PRIVATE_TOKEN",
            refreshToken: { "unused" },
            requestSender: { request in try await transport.send(request) },
            diagnosticSink: { diagnostics.record($0) }
        )

        do {
            _ = try await session.sendAudioPacket(Data("PRIVATE_AUDIO".utf8))
            XCTFail("the first packet response must fail for this diagnostic branch")
        } catch let failure as StreamFailure {
            XCTAssertEqual(failure, expectedFailure)
        } catch {
            XCTFail("expected sanitized StreamFailure, got \(error)")
        }

        let requestCount = await transport.requestCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(diagnostics.values.count, 1, "one failed response must emit exactly one diagnostic")
        return try XCTUnwrap(diagnostics.values.first)
    }

    private func assertSafeDiagnosticSurface(
        _ diagnostic: StreamingResponseDiagnostic,
        forbiddenValues: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let allowedFields: Set<String> = [
            "action",
            "sequenceID",
            "httpStatus",
            "responseByteCount",
            "businessCode",
            "dataPresent",
            "streamIDMatches",
            "sequenceIDMatches",
            "outcome"
        ]
        let reflectedFields = Set(Mirror(reflecting: diagnostic).children.compactMap(\.label))
        XCTAssertEqual(reflectedFields, allowedFields, file: file, line: line)

        let publicSurface = String(describing: diagnostic) + String(reflecting: diagnostic)
        for forbiddenValue in forbiddenValues {
            XCTAssertFalse(
                publicSurface.contains(forbiddenValue),
                "diagnostic leaked forbidden value \(forbiddenValue)",
                file: file,
                line: line
            )
        }
    }
}

private final class LockedDiagnosticRecorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [Value] = []

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return recordedValues
    }

    func record(_ value: Value) {
        lock.lock()
        recordedValues.append(value)
        lock.unlock()
    }
}

private struct ParsedStreamingRequest: Sendable {
    let method: String
    let path: String
    let contentType: String
    let action: Int
    let sequenceID: Int
    let streamID: String
    let authorization: String
    let format: String
    let engineType: String
    let pcmByteCount: Int
}

private actor StreamingRequestStub {
    private var responses: [DirectHTTPResponse]
    private var requests: [URLRequest] = []
    private var activeRequestCount = 0
    private(set) var maximumActiveRequestCount = 0
    private var gatedRequestOrdinals: Set<Int>
    private var requestContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private let injectsRequestIdentity: Bool

    init(
        responses: [DirectHTTPResponse],
        gateFirstRequest: Bool = false,
        gatedRequestOrdinals: Set<Int> = [],
        injectsRequestIdentity: Bool = true
    ) {
        self.responses = responses
        self.gatedRequestOrdinals = gatedRequestOrdinals
        if gateFirstRequest {
            self.gatedRequestOrdinals.insert(1)
        }
        self.injectsRequestIdentity = injectsRequestIdentity
    }

    var requestCount: Int { requests.count }

    func send(_ request: URLRequest) async throws -> DirectHTTPResponse {
        requests.append(request)
        let requestOrdinal = requests.count
        activeRequestCount += 1
        maximumActiveRequestCount = max(maximumActiveRequestCount, activeRequestCount)
        if gatedRequestOrdinals.contains(requestOrdinal) {
            await withCheckedContinuation { continuation in
                requestContinuations[requestOrdinal] = continuation
            }
        }
        defer { activeRequestCount -= 1 }
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return try responseMatchingRequest(responses.removeFirst(), request: request)
    }

    func releaseFirstRequest() {
        releaseRequest(1)
    }

    func releaseRequest(_ ordinal: Int) {
        gatedRequestOrdinals.remove(ordinal)
        requestContinuations.removeValue(forKey: ordinal)?.resume()
    }

    func waitForRequestCount(_ expected: Int) async {
        for _ in 0..<100 where requests.count < expected {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func parsedRequests() throws -> [ParsedStreamingRequest] {
        try requests.map { request in
            let body = try XCTUnwrap(request.httpBody)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let config = try XCTUnwrap(object["config"] as? [String: Any])
            let speech = try XCTUnwrap(object["speech"] as? [String: Any])
            let encodedPCM = speech["speech"] as? String ?? ""
            return ParsedStreamingRequest(
                method: request.httpMethod ?? "",
                path: request.url?.path ?? "",
                contentType: request.value(forHTTPHeaderField: "Content-Type") ?? "",
                action: try XCTUnwrap(config["action"] as? Int),
                sequenceID: try XCTUnwrap(config["sequence_id"] as? Int),
                streamID: try XCTUnwrap(config["stream_id"] as? String),
                authorization: request.value(forHTTPHeaderField: "Authorization") ?? "",
                format: try XCTUnwrap(config["format"] as? String),
                engineType: try XCTUnwrap(config["engine_type"] as? String),
                pcmByteCount: Data(base64Encoded: encodedPCM)?.count ?? -1
            )
        }
    }

    private func responseMatchingRequest(
        _ response: DirectHTTPResponse,
        request: URLRequest
    ) throws -> DirectHTTPResponse {
        guard injectsRequestIdentity,
              response.statusCode == 200,
              var object = try JSONSerialization.jsonObject(with: response.body) as? [String: Any],
              var data = object["data"] as? [String: Any],
              let requestBody = request.httpBody,
              let requestObject = try JSONSerialization.jsonObject(with: requestBody) as? [String: Any],
              let config = requestObject["config"] as? [String: Any],
              let streamID = config["stream_id"] as? String,
              let sequenceID = config["sequence_id"] as? Int else {
            return response
        }
        data["stream_id"] = streamID
        data["sequence_id"] = sequenceID
        object["data"] = data
        return DirectHTTPResponse(
            statusCode: response.statusCode,
            body: try JSONSerialization.data(withJSONObject: object)
        )
    }
}

private enum OperationOutcome: Equatable, Sendable {
    case pending
    case completed
    case event(StreamingRecognitionEvent)
    case failure(StreamFailure)
    case unexpectedFailure
}

private actor OperationOutcomeProbe {
    private(set) var outcome: OperationOutcome = .pending

    func record(_ outcome: OperationOutcome) {
        self.outcome = outcome
    }
}

private actor RefreshTokenStub {
    private var tokens: [String]
    private(set) var callCount = 0

    init(tokens: [String]) {
        self.tokens = tokens
    }

    func next() throws -> String {
        callCount += 1
        guard !tokens.isEmpty else { throw URLError(.userAuthenticationRequired) }
        return tokens.removeFirst()
    }
}

private func streamResponse(
    code: Int = 0,
    message: String = "ok",
    text: String
) -> DirectHTTPResponse {
    let body = try! JSONSerialization.data(withJSONObject: [
        "code": code,
        "msg": message,
        "data": [
            "stream_id": "response-id",
            "sequence_id": 0,
            "recognition_text": text
        ]
    ])
    return DirectHTTPResponse(statusCode: 200, body: body)
}

private func streamResponseOmittingIdentity(text: String) -> DirectHTTPResponse {
    let body = try! JSONSerialization.data(withJSONObject: [
        "code": 0,
        "msg": "ok",
        "data": ["recognition_text": text]
    ])
    return DirectHTTPResponse(statusCode: 200, body: body)
}

private func streamResponseWithIdentity(
    streamID: String,
    sequenceID: Int,
    text: String
) -> DirectHTTPResponse {
    let body = try! JSONSerialization.data(withJSONObject: [
        "code": 0,
        "msg": "ok",
        "data": [
            "stream_id": streamID,
            "sequence_id": sequenceID,
            "recognition_text": text
        ]
    ])
    return DirectHTTPResponse(statusCode: 200, body: body)
}

private func httpBusinessResponse(statusCode: Int, code: Int) -> DirectHTTPResponse {
    let body = try! JSONSerialization.data(withJSONObject: [
        "code": code,
        "msg": "PRIVATE_BACKEND_DETAIL",
        "data": ["recognition_text": "PRIVATE_TRANSCRIPT"]
    ])
    return DirectHTTPResponse(statusCode: statusCode, body: body)
}
