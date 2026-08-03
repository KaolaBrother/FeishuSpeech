@testable import FeishuSpeech
import Foundation
import os.log
import XCTest

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "CurrentFocusAppendSessionTests"
)

@MainActor
final class CurrentFocusAppendSessionTests: XCTestCase {
    private let generation: UInt64 = 41
    private let boundProcessIdentifier: pid_t = 4242

    func test_firstValuePostsWholePayloadAndExactDuplicateIsNoOp() {
        let context = makeContext()

        let first = context.session.applyOpaqueHypothesis(
            "first visible value",
            generation: generation,
            source: .livePacket
        )
        let duplicate = context.session.applyOpaqueHypothesis(
            "first visible value",
            generation: generation,
            source: .replayCatchUp
        )

        XCTAssertEqual(first, .insertedFirst)
        XCTAssertEqual(duplicate, .duplicate)
        assertPosted(["first visible value"], by: context.poster)
        XCTAssertEqual(context.poster.destinationProcessIdentifiers, [boundProcessIdentifier])
        XCTAssertEqual(context.poster.callCount, 1)
    }

    func test_exactUTF16ExtensionsPostOnlyUnseenSuffixesAcrossEmojiZWJCJKAndRTL() {
        let context = makeContext()
        let first = "A"
        let family = "👨‍👩‍👧‍👦"
        let cjk = "中文"
        let rtl = "שלום"

        XCTAssertEqual(
            context.session.applyOpaqueHypothesis(first, generation: generation, source: .livePacket),
            .insertedFirst
        )
        XCTAssertEqual(
            context.session.applyOpaqueHypothesis(
                first + family,
                generation: generation,
                source: .livePacket
            ),
            .appendedSuffix
        )
        XCTAssertEqual(
            context.session.applyOpaqueHypothesis(
                first + family + cjk + rtl,
                generation: generation,
                source: .livePacket
            ),
            .appendedSuffix
        )

        assertPosted([first, family, cjk + rtl], by: context.poster)
        XCTAssertTrue(
            context.poster.requestedTexts.joined().utf16.elementsEqual((first + family + cjk + rtl).utf16),
            "posted UTF-16 payloads must concatenate to the latest accepted hypothesis"
        )
    }

    func test_shorterRevisedAndCanonicallyEquivalentValuesAreSuppressedButLaterExactExtensionAppends() {
        let context = makeContext()
        let decomposed = "cafe\u{301}"

        XCTAssertEqual(
            context.session.applyOpaqueHypothesis(decomposed, generation: generation, source: .livePacket),
            .insertedFirst
        )
        XCTAssertEqual(
            context.session.applyOpaqueHypothesis("caf", generation: generation, source: .livePacket),
            .revisionSuppressed
        )
        XCTAssertEqual(
            context.session.applyOpaqueHypothesis("café", generation: generation, source: .livePacket),
            .revisionSuppressed
        )
        XCTAssertEqual(
            context.session.applyOpaqueHypothesis("revised", generation: generation, source: .livePacket),
            .revisionSuppressed
        )
        XCTAssertEqual(
            context.session.applyOpaqueHypothesis(
                decomposed + "!",
                generation: generation,
                source: .replayCatchUp
            ),
            .appendedSuffix
        )

        assertPosted([decomposed, "!"], by: context.poster)
    }

    func test_contentlessAndUnsafeC0C1DELValuesNeverPostAndSafeExtensionCanRecover() {
        for unsafe in ["safe\u{0000}", "safe\u{001F}", "safe\u{007F}", "safe\u{0085}", "safe\u{009F}"] {
            let context = makeContext()
            XCTAssertEqual(
                context.session.applyOpaqueHypothesis(unsafe, generation: generation, source: .livePacket),
                .unsafeTextSuppressed
            )
            XCTAssertEqual(context.poster.callCount, 0)
        }

        let context = makeContext()
        XCTAssertEqual(
            context.session.applyOpaqueHypothesis("   ", generation: generation, source: .livePacket),
            .contentless
        )
        XCTAssertEqual(
            context.session.applyOpaqueHypothesis("safe", generation: generation, source: .livePacket),
            .insertedFirst
        )
        XCTAssertEqual(
            context.session.applyOpaqueHypothesis("safe\u{007F}", generation: generation, source: .livePacket),
            .unsafeTextSuppressed
        )
        XCTAssertEqual(
            context.session.applyOpaqueHypothesis("safe suffix", generation: generation, source: .livePacket),
            .appendedSuffix
        )
        assertPosted(["safe", " suffix"], by: context.poster)
    }

    func test_PIDMismatchAtEitherPreflightOrPostflightPermanentlySuspendsOutput() {
        let samples: [[pid_t?]] = [
            [9999],
            [boundProcessIdentifier, 9999],
            [boundProcessIdentifier, boundProcessIdentifier, 9999]
        ]

        for processIdentifiers in samples {
            let context = makeContext(processIdentifiers: processIdentifiers)
            let first = context.session.applyOpaqueHypothesis(
                "candidate",
                generation: generation,
                source: .livePacket
            )
            let late = context.session.applyOpaqueHypothesis(
                "candidate extension",
                generation: generation,
                source: .livePacket
            )

            XCTAssertEqual(first, .destinationChanged)
            XCTAssertEqual(late, .destinationChanged)
            XCTAssertLessThanOrEqual(context.poster.callCount, 1)
        }
    }

    func test_secureInputAtEitherPreflightPosterOrPostflightPermanentlySuspendsOutput() {
        let firstSample = makeContext(secureInputStates: [true])
        assertSecuritySuspension(firstSample)

        let secondSample = makeContext(secureInputStates: [false, true])
        assertSecuritySuspension(secondSample)

        let posterSample = makeContext(
            secureInputStates: [false, false],
            posterResults: [.securityRejected]
        )
        assertSecuritySuspension(posterSample)

        let postflightSample = makeContext(secureInputStates: [false, false, true])
        assertSecuritySuspension(postflightSample)
    }

    func test_activationAwayPermanentlySuspendsEvenAfterActivationReturns() {
        let context = makeContext()

        context.activationMonitor.activate(processIdentifier: 9999)
        context.activationMonitor.activate(processIdentifier: boundProcessIdentifier)

        XCTAssertEqual(
            context.session.applyOpaqueHypothesis("late", generation: generation, source: .livePacket),
            .destinationChanged
        )
        XCTAssertEqual(context.poster.callCount, 0)
        XCTAssertEqual(context.activationMonitor.startCallCount, 1)
    }

    func test_stableSamePIDAllowsOutputAndDocumentsUnobservableSameProcessCaretRisk() {
        let context = makeContext()

        XCTAssertEqual(
            context.session.applyOpaqueHypothesis("same process", generation: generation, source: .livePacket),
            .insertedFirst
        )

        XCTAssertEqual(context.poster.callCount, 1)
        XCTAssertEqual(context.processProvider.queryCount, 3)
        XCTAssertEqual(context.secureInputProvider.queryCount, 3)
    }

    func test_systemFactoryCapturedSessionUsesSuppliedPIDAndValidatesTwiceBeforeOnceAfterPost() {
        let poster = FakeUnicodeEventPoster(results: [])
        let secureInput = FakeAppendSecureInputStateProvider(states: [false, false, false])
        let processProvider = FakeAppendFrontmostProcessProvider(
            processIdentifiers: [boundProcessIdentifier, boundProcessIdentifier, boundProcessIdentifier]
        )
        let activationMonitor = FakeActivationMonitor()
        let factory = SystemCurrentFocusProvisionalOutputSessionFactory(
            eventPoster: poster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: processProvider,
            activationMonitorFactory: { activationMonitor }
        )
        var validationCallCount = 0

        let session = factory.makeSession(
            generation: generation,
            boundProcessIdentifier: boundProcessIdentifier,
            validateBoundDestination: {
                validationCallCount += 1
                return .valid
            }
        )
        let outcome = session?.applyOpaqueHypothesis(
            "captured target",
            generation: generation,
            source: .livePacket
        )

        XCTAssertEqual(outcome, .insertedFirst)
        XCTAssertEqual(validationCallCount, 3, "captured validation must run twice before and once after posting")
        XCTAssertEqual(poster.requestedTexts, ["captured target"])
        XCTAssertEqual(poster.destinationProcessIdentifiers, [boundProcessIdentifier])
        XCTAssertEqual(processProvider.queryCount, 3)
        XCTAssertEqual(secureInput.queryCount, 3)
    }

    func test_capturedPostflightElementDriftPermanentlySuspendsWithoutLaterFinalPost() {
        let poster = FakeUnicodeEventPoster(results: [])
        let secureInput = FakeAppendSecureInputStateProvider(
            states: Array(repeating: false, count: 10)
        )
        let processProvider = FakeAppendFrontmostProcessProvider(
            processIdentifiers: Array(repeating: boundProcessIdentifier, count: 10)
        )
        let activationMonitor = FakeActivationMonitor()
        let factory = SystemCurrentFocusProvisionalOutputSessionFactory(
            eventPoster: poster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: processProvider,
            activationMonitorFactory: { activationMonitor }
        )
        var validations: [CurrentFocusBoundDestinationValidation] = [
            .valid,
            .valid,
            .destinationChanged
        ]
        let session = factory.makeSession(
            generation: generation,
            boundProcessIdentifier: boundProcessIdentifier,
            validateBoundDestination: {
                guard !validations.isEmpty else { return .valid }
                return validations.removeFirst()
            }
        )

        let first = session?.applyOpaqueHypothesis(
            "visible",
            generation: generation,
            source: .livePacket
        )
        let late = session?.applyOpaqueHypothesis(
            "visible extension",
            generation: generation,
            source: .livePacket
        )
        let final = session?.finalize(
            finalText: "visible final",
            lastAcceptedText: "visible extension",
            generation: generation
        )

        XCTAssertEqual(first, .destinationChanged)
        XCTAssertEqual(late, .destinationChanged)
        XCTAssertEqual(final, .preservedDestinationLoss)
        XCTAssertEqual(poster.requestedTexts, ["visible"])
        XCTAssertEqual(poster.destinationProcessIdentifiers, [boundProcessIdentifier])
    }

    func test_capturedPostflightSecureInputPermanentlySuspendsWithoutLaterFinalPost() {
        let poster = FakeUnicodeEventPoster(results: [])
        let secureInput = FakeAppendSecureInputStateProvider(states: [false, false, true])
        let processProvider = FakeAppendFrontmostProcessProvider(
            processIdentifiers: Array(repeating: boundProcessIdentifier, count: 10)
        )
        let activationMonitor = FakeActivationMonitor()
        let factory = SystemCurrentFocusProvisionalOutputSessionFactory(
            eventPoster: poster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: processProvider,
            activationMonitorFactory: { activationMonitor }
        )
        var validationCallCount = 0
        let session = factory.makeSession(
            generation: generation,
            boundProcessIdentifier: boundProcessIdentifier,
            validateBoundDestination: {
                validationCallCount += 1
                return .valid
            }
        )

        let first = session?.applyOpaqueHypothesis(
            "visible",
            generation: generation,
            source: .livePacket
        )
        let late = session?.applyOpaqueHypothesis(
            "visible extension",
            generation: generation,
            source: .livePacket
        )
        let final = session?.finalize(
            finalText: "visible final",
            lastAcceptedText: "visible extension",
            generation: generation
        )

        XCTAssertEqual(first, .securityRejected)
        XCTAssertEqual(late, .securityRejected)
        XCTAssertEqual(final, .preservedSecurityRejection)
        XCTAssertEqual(validationCallCount, 2)
        XCTAssertEqual(poster.requestedTexts, ["visible"])
        XCTAssertEqual(poster.destinationProcessIdentifiers, [boundProcessIdentifier])
    }

    func test_posterFailureOrSecurityUncertaintyNeverResendsPayload() {
        for posterResult in [FinalTextCurrentFocusPostResult.deliveryFailed, .securityRejected] {
            let context = makeContext(posterResults: [posterResult, .posted])

            let first = context.session.applyOpaqueHypothesis(
                "uncertain",
                generation: generation,
                source: .livePacket
            )
            let retry = context.session.applyOpaqueHypothesis(
                "uncertain",
                generation: generation,
                source: .replayCatchUp
            )

            XCTAssertEqual(
                first,
                posterResult == .securityRejected ? .securityRejected : .deliveryUncertain
            )
            XCTAssertEqual(
                retry,
                posterResult == .securityRejected ? .securityRejected : .deliveryUncertain
            )
            XCTAssertEqual(context.poster.callCount, 1)
        }
    }

    func test_staleGenerationInvalidateAndLateValuesAreNoOps() {
        let stale = makeContext()
        XCTAssertEqual(
            stale.session.applyOpaqueHypothesis("stale", generation: generation + 1, source: .livePacket),
            .staleGeneration
        )
        XCTAssertEqual(
            stale.session.finalize(
                finalText: "stale final",
                lastAcceptedText: nil,
                generation: generation + 1
            ),
            .staleGeneration
        )
        XCTAssertEqual(stale.poster.callCount, 0)

        let invalidated = makeContext()
        invalidated.session.invalidate()
        XCTAssertEqual(
            invalidated.session.applyOpaqueHypothesis("late", generation: generation, source: .livePacket),
            .staleGeneration
        )
        XCTAssertEqual(
            invalidated.session.finalize(
                finalText: "late final",
                lastAcceptedText: "late accepted",
                generation: generation
            ),
            .staleGeneration
        )
        XCTAssertEqual(invalidated.poster.callCount, 0)
        XCTAssertEqual(invalidated.activationMonitor.stopCallCount, 1)
    }

    func test_finalizeExactIsNoOpAndRepeatedFinalizeAndLateHypothesisCannotWrite() {
        let context = makeContext()
        _ = context.session.applyOpaqueHypothesis("visible", generation: generation, source: .livePacket)

        let first = context.session.finalize(
            finalText: "visible",
            lastAcceptedText: "visible",
            generation: generation
        )
        let repeated = context.session.finalize(
            finalText: "visible extension",
            lastAcceptedText: "visible extension",
            generation: generation
        )
        let late = context.session.applyOpaqueHypothesis(
            "visible extension",
            generation: generation,
            source: .livePacket
        )

        XCTAssertEqual(first, .exactCommitted)
        XCTAssertEqual(repeated, .staleGeneration)
        XCTAssertEqual(late, .staleGeneration)
        assertPosted(["visible"], by: context.poster)
        XCTAssertEqual(context.activationMonitor.stopCallCount, 1)
    }

    func test_finalizeExactExtensionPostsSuffixOnce() {
        let context = makeContext()
        _ = context.session.applyOpaqueHypothesis("base", generation: generation, source: .livePacket)

        XCTAssertEqual(
            context.session.finalize(
                finalText: "base final",
                lastAcceptedText: "base final",
                generation: generation
            ),
            .suffixCommitted
        )
        assertPosted(["base", " final"], by: context.poster)
    }

    func test_finalizeRevisionOrShorteningPreservesEmittedTextWithoutRecoveryOutput() {
        for finalText in ["revise", "vis"] {
            let context = makeContext()
            _ = context.session.applyOpaqueHypothesis("visible", generation: generation, source: .livePacket)

            XCTAssertEqual(
                context.session.finalize(
                    finalText: finalText,
                    lastAcceptedText: "visible",
                    generation: generation
                ),
                .preservedDivergence
            )
            assertPosted(["visible"], by: context.poster)
        }
    }

    func test_finalizeEmptyPreservesEmittedOrUsesLastAcceptedThroughNormalGates() {
        let emitted = makeContext()
        _ = emitted.session.applyOpaqueHypothesis("visible", generation: generation, source: .livePacket)
        XCTAssertEqual(
            emitted.session.finalize(
                finalText: nil,
                lastAcceptedText: "visible",
                generation: generation
            ),
            .exactCommitted
        )
        assertPosted(["visible"], by: emitted.poster)

        let fallback = makeContext()
        XCTAssertEqual(
            fallback.session.finalize(
                finalText: "",
                lastAcceptedText: "accepted",
                generation: generation
            ),
            .suffixCommitted
        )
        assertPosted(["accepted"], by: fallback.poster)

        let empty = makeContext()
        XCTAssertEqual(
            empty.session.finalize(finalText: nil, lastAcceptedText: nil, generation: generation),
            .noUsableText
        )
        XCTAssertEqual(empty.poster.callCount, 0)
    }

    func test_finalizePreservesTypedDestinationSecurityAndDeliveryUncertainty() {
        let destination = makeContext(processIdentifiers: [9999])
        _ = destination.session.applyOpaqueHypothesis("candidate", generation: generation, source: .livePacket)
        XCTAssertEqual(
            destination.session.finalize(
                finalText: "candidate",
                lastAcceptedText: "candidate",
                generation: generation
            ),
            .preservedDestinationLoss
        )

        let security = makeContext(secureInputStates: [true])
        _ = security.session.applyOpaqueHypothesis("candidate", generation: generation, source: .livePacket)
        XCTAssertEqual(
            security.session.finalize(
                finalText: "candidate",
                lastAcceptedText: "candidate",
                generation: generation
            ),
            .preservedSecurityRejection
        )

        let delivery = makeContext(posterResults: [.deliveryFailed])
        _ = delivery.session.applyOpaqueHypothesis("candidate", generation: generation, source: .livePacket)
        XCTAssertEqual(
            delivery.session.finalize(
                finalText: "candidate",
                lastAcceptedText: "candidate",
                generation: generation
            ),
            .deliveryUncertain
        )
    }

    func test_outcomeDescriptionsAreTypedAndTranscriptFree() {
        let marker = "PRIVATE_TRANSCRIPT_MARKER"
        let context = makeContext()
        let apply = context.session.applyOpaqueHypothesis(marker, generation: generation, source: .livePacket)
        let final = context.session.finalize(
            finalText: marker,
            lastAcceptedText: marker,
            generation: generation
        )

        XCTAssertFalse(String(describing: apply).contains(marker))
        XCTAssertFalse(String(describing: final).contains(marker))
    }

    private func assertSecuritySuspension(_ context: TestContext) {
        let first = context.session.applyOpaqueHypothesis(
            "candidate",
            generation: generation,
            source: .livePacket
        )
        let late = context.session.applyOpaqueHypothesis(
            "candidate extension",
            generation: generation,
            source: .livePacket
        )

        XCTAssertEqual(first, .securityRejected)
        XCTAssertEqual(late, .securityRejected)
        XCTAssertLessThanOrEqual(context.poster.callCount, 1)
    }

    private func assertPosted(
        _ expected: [String],
        by poster: FakeUnicodeEventPoster,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            poster.requestedTexts == expected,
            "direct Unicode payload sequence differed from the opaque contract",
            file: file,
            line: line
        )
    }

    private func makeContext(
        processIdentifiers: [pid_t?]? = nil,
        secureInputStates: [Bool]? = nil,
        posterResults: [FinalTextCurrentFocusPostResult] = []
    ) -> TestContext {
        let processProvider = FakeAppendFrontmostProcessProvider(
            processIdentifiers: processIdentifiers ?? Array(repeating: boundProcessIdentifier, count: 30)
        )
        let secureInputProvider = FakeAppendSecureInputStateProvider(
            states: secureInputStates ?? Array(repeating: false, count: 30)
        )
        let poster = FakeUnicodeEventPoster(results: posterResults)
        let activationMonitor = FakeActivationMonitor()
        let session = CurrentFocusAppendSession(
            generation: generation,
            boundProcessIdentifier: boundProcessIdentifier,
            eventPoster: poster,
            secureInputStateProvider: secureInputProvider,
            frontmostProcessProvider: processProvider,
            activationMonitor: activationMonitor
        )
        return TestContext(
            session: session,
            poster: poster,
            secureInputProvider: secureInputProvider,
            processProvider: processProvider,
            activationMonitor: activationMonitor
        )
    }
}

@MainActor
private struct TestContext {
    let session: CurrentFocusAppendSession
    let poster: FakeUnicodeEventPoster
    let secureInputProvider: FakeAppendSecureInputStateProvider
    let processProvider: FakeAppendFrontmostProcessProvider
    let activationMonitor: FakeActivationMonitor
}

@MainActor
private final class FakeUnicodeEventPoster: FinalTextCurrentFocusEventPosting {
    private var results: [FinalTextCurrentFocusPostResult]
    private(set) var requestedTexts: [String] = []
    private(set) var destinationProcessIdentifiers: [pid_t] = []

    var callCount: Int { requestedTexts.count }

    init(results: [FinalTextCurrentFocusPostResult]) {
        self.results = results
    }

    func postUnicodeText(
        _ text: String,
        to processIdentifier: pid_t
    ) -> FinalTextCurrentFocusPostResult {
        requestedTexts.append(text)
        destinationProcessIdentifiers.append(processIdentifier)
        guard !results.isEmpty else { return .posted }
        return results.removeFirst()
    }
}

@MainActor
private final class FakeAppendSecureInputStateProvider: SecureInputStateProviding {
    private var states: [Bool]
    private(set) var queryCount = 0

    init(states: [Bool]) {
        self.states = states
    }

    func isSecureInputEnabled() -> Bool {
        queryCount += 1
        guard !states.isEmpty else { return true }
        return states.removeFirst()
    }
}

@MainActor
private final class FakeAppendFrontmostProcessProvider: FrontmostProcessProviding {
    private var processIdentifiers: [pid_t?]
    private(set) var queryCount = 0

    init(processIdentifiers: [pid_t?]) {
        self.processIdentifiers = processIdentifiers
    }

    func frontmostProcessIdentifier() -> pid_t? {
        queryCount += 1
        guard !processIdentifiers.isEmpty else { return nil }
        return processIdentifiers.removeFirst()
    }
}

@MainActor
private final class FakeActivationMonitor: CurrentFocusActivationMonitoring {
    private var handler: (@MainActor (pid_t) -> Void)?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func startMonitoring(_ handler: @escaping @MainActor (pid_t) -> Void) {
        startCallCount += 1
        self.handler = handler
    }

    func stopMonitoring() {
        stopCallCount += 1
        handler = nil
    }

    func activate(processIdentifier: pid_t) {
        handler?(processIdentifier)
    }
}
