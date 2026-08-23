import AppKit
import ApplicationServices
import Foundation
import os.log
import SwiftUI
import XCTest

@testable import FeishuSpeech

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "ReviewFirstApplicationFallbackTests"
)

@MainActor
private func makeIssue40ReviewDelivery(
    applicationRuntime: ReviewApplicationRuntime,
    applicationActivator: ReviewApplicationActivating,
    accessibility: ReviewDestinationAccessing,
    finalTextOutput: FinalTextOutput,
    accessibilityTrustProvider: AccessibilityTrustProviding? = nil,
    secureInputStateProvider: SecureInputStateProviding? = nil,
    frontmostProcessProvider: FrontmostProcessProviding? = nil
) -> SystemReviewDestinationDelivery {
    SystemReviewDestinationDelivery(
        applicationRuntime: applicationRuntime,
        applicationActivator: applicationActivator,
        accessibility: accessibility,
        finalTextOutput: finalTextOutput,
        accessibilityTrustProvider: accessibilityTrustProvider,
        secureInputStateProvider: secureInputStateProvider,
        frontmostProcessProvider: frontmostProcessProvider,
        inputMonitor: Issue40FallbackInputMonitor(),
        activationMonitor: Issue40FallbackActivationMonitor(),
        modifierSampler: { [] },
        modifierSleeper: { _ in true }
    )
}

@MainActor
final class ReviewFirstApplicationFallbackTests: XCTestCase {
    override func tearDown() async throws {
        HotKeyService.shared.resetToIdle()
        PermissionManager.shared.resetStateForTesting()
        try await super.tearDown()
    }

    func test_nonSecureStrictAXMisses_bindCompleteOriginalApplicationIdentity() {
        let misses = [
            "no focused element",
            "incomplete AX role",
            "unavailable selection",
            "unverifiable selection"
        ]

        for name in misses {
            let runtime = Issue40ApplicationRuntime()
            let accessibility = Issue40StrictReviewAccess(
                captureResult: .nonSecureCursorUnavailable
            )
            let delivery = makeIssue40ReviewDelivery(
                applicationRuntime: runtime,
                applicationActivator: Issue40ApplicationActivator(),
                accessibility: accessibility,
                finalTextOutput: Issue40FinalTextOutput(),
                accessibilityTrustProvider: Issue40AccessibilityTrustProvider()
            )

            let capture = delivery.capture(generation: 40)
            guard case .captured(let destination) = capture else {
                XCTFail(
                    name + " must produce an application-bound review destination, got " +
                        String(describing: capture)
                )
                continue
            }
            XCTAssertEqual(
                destination.application,
                runtime.capturedIdentity,
                name + " must bind the complete identity of the original frontmost application"
            )
            if case .applicationCurrentFocus = destination.binding {
                // The fallback must carry no AX element or selection authority.
            } else {
                XCTFail(name + " must use the application-current-focus binding")
            }
            XCTAssertEqual(
                destination.capturedSecurityState,
                .safe,
                name + " must admit the fallback only after a safe capture"
            )
            XCTAssertEqual(
                accessibility.captureCallCount,
                1,
                name + " must ask AX exactly once after binding the application"
            )
        }
    }

    func test_secureTypedCapture_rejectsWithoutApplicationBoundFallback() {
        let runtime = Issue40ApplicationRuntime()
        let accessibility = Issue40StrictReviewAccess(
            captureResult: .rejected(.secureInput)
        )
        let delivery = makeIssue40ReviewDelivery(
            applicationRuntime: runtime,
            applicationActivator: Issue40ApplicationActivator(),
            accessibility: accessibility,
            finalTextOutput: Issue40FinalTextOutput(),
            accessibilityTrustProvider: Issue40AccessibilityTrustProvider()
        )

        let capture = delivery.capture(generation: 40)

        guard case .rejected(let rejection) = capture else {
            XCTFail("secure AX capture must remain a typed startup rejection")
            return
        }
        XCTAssertEqual(rejection, .secureInput)
        XCTAssertEqual(accessibility.captureCallCount, 1)
    }

    func test_nonSecureStrictAXMiss_capturesIdentityBeforeAXAndRevalidatesAfterward() {
        let runtime = Issue40ApplicationRuntime()
        let accessibility = Issue40StrictReviewAccess(
            captureResult: .nonSecureCursorUnavailable,
            trace: runtime.trace
        )
        let delivery = makeIssue40ReviewDelivery(
            applicationRuntime: runtime,
            applicationActivator: Issue40ApplicationActivator(),
            accessibility: accessibility,
            finalTextOutput: Issue40FinalTextOutput(),
            accessibilityTrustProvider: Issue40AccessibilityTrustProvider()
        )

        let capture = delivery.capture(generation: 40)

        guard case .captured = capture else {
            XCTFail("a stable non-secure AX miss must produce a fallback binding")
            return
        }
        XCTAssertEqual(
            runtime.trace.events,
            ["frontmost-before-ax", "identity-before-ax", "ax", "identity-after-ax", "frontmost-after-ax"]
        )
    }

    func test_incompleteOriginalIdentity_rejectsBeforeAXAndCannotFallBack() {
        let runtime = Issue40ApplicationRuntime()
        runtime.runningIdentity = Issue40Fixtures.applicationIdentity(
            pid: 42,
            bundleIdentifier: ""
        )
        let accessibility = Issue40StrictReviewAccess(
            captureResult: .nonSecureCursorUnavailable,
            trace: runtime.trace
        )
        let delivery = makeIssue40ReviewDelivery(
            applicationRuntime: runtime,
            applicationActivator: Issue40ApplicationActivator(),
            accessibility: accessibility,
            finalTextOutput: Issue40FinalTextOutput(),
            accessibilityTrustProvider: Issue40AccessibilityTrustProvider()
        )

        let capture = delivery.capture(generation: 40)

        guard case .rejected(let rejection) = capture else {
            XCTFail("an incomplete running identity must not admit the application fallback")
            return
        }
        XCTAssertEqual(rejection, .destinationUnavailable)
        XCTAssertEqual(accessibility.captureCallCount, 0)
    }

    func test_identityDriftDuringTypedAXCapture_rejectsFallbackAfterAXWithoutBindingNewApp() {
        let runtime = Issue40ApplicationRuntime()
        runtime.onIdentityQuery = { queryNumber in
            if queryNumber == 1 {
                runtime.runningIdentity = Issue40Fixtures.applicationIdentity(
                    pid: 42,
                    launchDate: Date(timeIntervalSince1970: 999)
                )
            }
        }
        let accessibility = Issue40StrictReviewAccess(
            captureResult: .nonSecureCursorUnavailable,
            trace: runtime.trace
        )
        let delivery = makeIssue40ReviewDelivery(
            applicationRuntime: runtime,
            applicationActivator: Issue40ApplicationActivator(),
            accessibility: accessibility,
            finalTextOutput: Issue40FinalTextOutput(),
            accessibilityTrustProvider: Issue40AccessibilityTrustProvider()
        )

        let capture = delivery.capture(generation: 40)

        guard case .rejected(let rejection) = capture else {
            XCTFail("identity drift during AX probing must not produce a fallback token")
            return
        }
        XCTAssertEqual(rejection, .destinationUnavailable)
        XCTAssertEqual(accessibility.captureCallCount, 1)
    }

    func test_applicationBoundReviewDelivery_reactivatesExactIdentityAndInsertsFrozenMultilineDraftOnce() async {
        let runtime = Issue40ApplicationRuntime()
        let activator = Issue40ApplicationActivator()
        let secureInput = Issue40SecureInputProvider(
            states: [false, false, false, false, false, false]
        )
        let frontmostProcess = Issue40FrontmostProcessProvider(processIdentifiers: [42, 42, 42])
        let pasteboard = Issue40PasteboardWriter()
        let keyPoster = Issue40KeyEventPoster()
        let unicodePoster = Issue40FallbackUnicodePoster()
        let accessibility = Issue40StrictReviewAccess(
            captureResult: .nonSecureCursorUnavailable
        )
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: keyPoster,
            currentFocusEventPoster: unicodePoster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess
        )
        let delivery = makeIssue40ReviewDelivery(
            applicationRuntime: runtime,
            applicationActivator: activator,
            accessibility: accessibility,
            finalTextOutput: output,
            accessibilityTrustProvider: Issue40AccessibilityTrustProvider()
        )
        let destination = Issue40Fixtures.applicationBoundDestination(
            identity: runtime.capturedIdentity,
            generation: 41
        )
        let frozenDraft = "first line\nsecond line"

        let result = await delivery.deliver(frozenDraft, to: destination)

        XCTAssertEqual(result, .submittedUnverified)
        XCTAssertEqual(activator.activationRequests, [runtime.capturedIdentity])
        XCTAssertEqual(unicodePoster.requestedTexts, [frozenDraft])
        XCTAssertEqual(unicodePoster.processIdentifiers, [42])
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(keyPoster.processIdentifiers, [])
        XCTAssertEqual(secureInput.queryCount, 6)
        XCTAssertEqual(frontmostProcess.queryCount, 3)
        XCTAssertEqual(accessibility.restoreCallCount, 0)
        XCTAssertEqual(accessibility.validateAfterCallCount, 0)
    }

    func test_applicationBoundReviewDelivery_trustRevokedAfterCaptureRejectsBeforeAnyOutput() async {
        let runtime = Issue40ApplicationRuntime()
        let activator = Issue40ApplicationActivator()
        let trustProvider = Issue40AccessibilityTrustProvider()
        let secureInput = Issue40SecureInputProvider(states: [false, false, false, false])
        let frontmostProcess = Issue40FrontmostProcessProvider(processIdentifiers: [42, 42])
        let pasteboard = Issue40PasteboardWriter()
        let keyPoster = Issue40KeyEventPoster()
        let unicodePoster = Issue40FallbackUnicodePoster()
        var snapshotReadCount = 0
        var changeCountReadCount = 0
        var restoreCount = 0
        var restoreScheduleCount = 0
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: keyPoster,
            currentFocusEventPoster: unicodePoster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess,
        )
        let accessibility = Issue40StrictReviewAccess(
            captureResult: .nonSecureCursorUnavailable
        )
        let delivery = makeIssue40ReviewDelivery(
            applicationRuntime: runtime,
            applicationActivator: activator,
            accessibility: accessibility,
            finalTextOutput: output,
            accessibilityTrustProvider: trustProvider,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess
        )

        let capture = delivery.capture(generation: 49)
        guard case .captured(let destination) = capture else {
            XCTFail("a trusted application-current-focus capture must produce a destination")
            return
        }
        guard case .applicationCurrentFocus = destination.binding else {
            XCTFail("this regression must exercise the application-current-focus fallback")
            return
        }
        XCTAssertTrue(trustProvider.isAccessibilityTrusted)

        trustProvider.isAccessibilityTrusted = false
        let result = await delivery.deliver(
            "exact draft retained while trust is revoked",
            to: destination
        )

        XCTAssertEqual(result, .securityRejected)
        XCTAssertNotEqual(result, .submittedUnverified)
        XCTAssertEqual(activator.activationRequests, [])
        XCTAssertEqual(accessibility.restoreCallCount, 0)
        XCTAssertEqual(accessibility.validateAfterCallCount, 0)
        XCTAssertEqual(secureInput.queryCount, 0)
        XCTAssertEqual(frontmostProcess.queryCount, 0)
        XCTAssertEqual(snapshotReadCount, 0)
        XCTAssertEqual(changeCountReadCount, 0)
        XCTAssertEqual(restoreCount, 0)
        XCTAssertEqual(restoreScheduleCount, 0)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(keyPoster.processIdentifiers, [])
    }

    func test_reviewFirst_trustRevokedAfterCaptureRetainsExactDraftAndAuthorityWithoutOutput() async {
        let runtime = Issue40ApplicationRuntime()
        let activator = Issue40ApplicationActivator()
        let trustProvider = Issue40AccessibilityTrustProvider()
        let secureInput = Issue40SecureInputProvider(states: [false, false, false, false])
        let frontmostProcess = Issue40FrontmostProcessProvider(processIdentifiers: [42, 42])
        let pasteboard = Issue40PasteboardWriter()
        let keyPoster = Issue40KeyEventPoster()
        var snapshotReadCount = 0
        var changeCountReadCount = 0
        var restoreCount = 0
        var restoreScheduleCount = 0
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: keyPoster,
            currentFocusEventPoster: Issue40FallbackUnicodePoster(),
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess,
        )
        let systemDelivery = makeIssue40ReviewDelivery(
            applicationRuntime: runtime,
            applicationActivator: activator,
            accessibility: Issue40StrictReviewAccess(
                captureResult: .nonSecureCursorUnavailable
            ),
            finalTextOutput: output,
            accessibilityTrustProvider: trustProvider,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess
        )
        let delivery = Issue40TrustRevokingReviewDelivery(
            delivery: systemDelivery,
            trustProvider: trustProvider
        )
        let recorder = Issue40AudioRecorder()
        let session = Issue40StreamingSession(
            packetEvents: [],
            finishEvent: .final("PRIVATE_TRUSTED_CAPTURE")
        )
        let provider = Issue40StreamingProvider(session: session)
        let presenter = Issue40ReviewSurfacePresenter()
        let viewModel = MainViewModel(
            audioRecorder: recorder,
            settings: AppSettings(
                appId: "configured-app",
                appSecret: "configured-secret",
                autoInsert: true,
                playSound: false,
                reviewBeforeInsert: true
            ),
            hotKeyWakeRecovering: Issue40HotKeyWakeRecoverer(),
            streamingProvider: provider,
            accessibilityClient: Issue40AccessibilityClient(),
            finalTextOutput: Issue40FinalTextOutput(),
            overlayPresenter: Issue40OverlayPresenter(),
            reviewDestinationDelivery: delivery,
            reviewSurfacePresenter: presenter
        )
        let identity = StreamingSessionIdentity(generation: 50)

        viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { recorder.startStreamingCallCount == 1 }
        await waitUntilAsync { await provider.makeSessionCallCount == 1 }
        viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil {
            if case .editable = viewModel.transcriptionReviewState { return true }
            return false
        }

        let frozenDraft = "trusted capture\nrevoked before confirmation"
        presenter.invokeDraftChange(frozenDraft)
        presenter.invokeConfirm()
        await waitUntil { delivery.deliverCallCount == 1 }
        await waitUntil {
            if case .editable(_, _, feedback: .securityRejected) = viewModel.transcriptionReviewState {
                return true
            }
            return false
        }

        XCTAssertEqual(delivery.captureCallCount, 1)
        XCTAssertEqual(delivery.deliveredTexts, [frozenDraft])
        XCTAssertEqual(delivery.deliveredDestinations.count, 1)
        guard case .applicationCurrentFocus = delivery.deliveredDestinations[0].binding else {
            XCTFail("coordinator must retain the captured application-current-focus authority")
            return
        }
        XCTAssertEqual(
            viewModel.transcriptionReviewState,
            .editable(draft: frozenDraft, isPossiblyIncomplete: false, feedback: .securityRejected)
        )
        XCTAssertGreaterThanOrEqual(presenter.renderDraftCallCount, 3)
        XCTAssertEqual(activator.activationRequests, [])
        XCTAssertEqual(snapshotReadCount, 0)
        XCTAssertEqual(changeCountReadCount, 0)
        XCTAssertEqual(restoreCount, 0)
        XCTAssertEqual(restoreScheduleCount, 0)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(keyPoster.processIdentifiers, [])
        XCTAssertEqual(secureInput.queryCount, 0)
        XCTAssertEqual(frontmostProcess.queryCount, 0)
    }

    func test_applicationBoundReviewDelivery_trustRevokedBetweenPreflightCompositeStartAndEndFailsClosed() async {
        let runtime = Issue40ApplicationRuntime()
        let activator = Issue40ApplicationActivator()
        let trustProvider = Issue40AccessibilityTrustProvider()
        let secureInput = Issue40SecureInputProvider(states: [false, false, false, false])
        let frontmostProcess = Issue40FrontmostProcessProvider(processIdentifiers: [42, 42])
        let pasteboard = Issue40PasteboardWriter()
        let keyPoster = Issue40KeyEventPoster()
        var snapshotReadCount = 0
        var changeCountReadCount = 0
        var restoreCount = 0
        var restoreScheduleCount = 0
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: keyPoster,
            currentFocusEventPoster: Issue40FallbackUnicodePoster(),
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess,
        )
        let delivery = makeIssue40ReviewDelivery(
            applicationRuntime: runtime,
            applicationActivator: activator,
            accessibility: Issue40StrictReviewAccess(
                captureResult: .nonSecureCursorUnavailable
            ),
            finalTextOutput: output,
            accessibilityTrustProvider: trustProvider,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess
        )
        let capture = delivery.capture(generation: 51)
        guard case .captured(let destination) = capture else {
            XCTFail("trusted capture must produce an application-current-focus destination")
            return
        }
        trustProvider.setQueuedSamples([
            true,  // initial validation
            true, false,  // first composite: trust changes before its ending sample
            false, false   // second composite still fails closed
        ])

        let result = await delivery.deliver("PRIVATE_PREFLIGHT_TRUST_RACE", to: destination)

        XCTAssertEqual(result, .securityRejected)
        XCTAssertNotEqual(result, .submittedUnverified)
        XCTAssertEqual(trustProvider.readCount, 5)
        XCTAssertEqual(activator.activationRequests, [runtime.capturedIdentity])
        XCTAssertEqual(snapshotReadCount, 0)
        XCTAssertEqual(changeCountReadCount, 0)
        XCTAssertEqual(restoreCount, 0)
        XCTAssertEqual(restoreScheduleCount, 0)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(keyPoster.processIdentifiers, [])
        XCTAssertEqual(secureInput.queryCount, 4)
        XCTAssertEqual(frontmostProcess.queryCount, 2)
    }

    func test_applicationBoundReviewDelivery_trustRevokedDuringPostflightReturnsUncertainAfterOneMutation() async {
        let runtime = Issue40ApplicationRuntime()
        let activator = Issue40ApplicationActivator()
        let trustProvider = Issue40AccessibilityTrustProvider()
        let secureInput = Issue40SecureInputProvider(states: [false, false, false, false, false, false])
        let frontmostProcess = Issue40FrontmostProcessProvider(processIdentifiers: [42, 42, 42])
        let pasteboard = Issue40PasteboardWriter()
        let keyPoster = Issue40KeyEventPoster()
        let unicodePoster = Issue40FallbackUnicodePoster()
        var snapshotReadCount = 0
        var changeCountReadCount = 0
        var restoreCount = 0
        var restoreScheduleCount = 0
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: keyPoster,
            currentFocusEventPoster: unicodePoster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess,
        )
        let delivery = makeIssue40ReviewDelivery(
            applicationRuntime: runtime,
            applicationActivator: activator,
            accessibility: Issue40StrictReviewAccess(
                captureResult: .nonSecureCursorUnavailable
            ),
            finalTextOutput: output,
            accessibilityTrustProvider: trustProvider,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess
        )
        let capture = delivery.capture(generation: 52)
        guard case .captured(let destination) = capture else {
            XCTFail("trusted capture must produce an application-current-focus destination")
            return
        }
        trustProvider.setQueuedSamples([
            true,  // initial validation
            true, true, true, true,  // two stable preflight composites
            true, false  // postflight trust transition after one mutation
        ])

        let result = await delivery.deliver("PRIVATE_POSTFLIGHT_TRUST_RACE", to: destination)

        XCTAssertEqual(result, .deliveryUncertain)
        XCTAssertNotEqual(result, .submittedUnverified)
        XCTAssertEqual(trustProvider.readCount, 7)
        XCTAssertEqual(activator.activationRequests, [runtime.capturedIdentity])
        XCTAssertEqual(snapshotReadCount, 0)
        XCTAssertEqual(changeCountReadCount, 0)
        XCTAssertEqual(restoreCount, 0)
        XCTAssertEqual(restoreScheduleCount, 0)
        XCTAssertEqual(unicodePoster.requestedTexts, ["PRIVATE_POSTFLIGHT_TRUST_RACE"])
        XCTAssertEqual(unicodePoster.processIdentifiers, [42])
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(keyPoster.processIdentifiers, [])
        XCTAssertEqual(secureInput.queryCount, 6)
        XCTAssertEqual(frontmostProcess.queryCount, 3)
    }

    func test_applicationBoundReviewDelivery_rejectsSecureInputOrUnstablePIDBeforeCurrentFocusPost() async {
        let cases: [(String, [Bool], [pid_t?], ReviewDeliveryResult)] = [
            ("secure input", [true, false, false, false], [42, 42], .securityRejected),
            ("late secure input", [false, false, false, true], [42, 42], .securityRejected),
            ("unstable PID", [false, false, false, false], [42, 99], .destinationInvalid),
            ("missing PID", [false, false, false, false], [nil, 42], .destinationInvalid)
        ]

        for (name, secureStates, processIdentifiers, expectedResult) in cases {
            let runtime = Issue40ApplicationRuntime()
            let activator = Issue40ApplicationActivator()
            let pasteboard = Issue40PasteboardWriter()
            let keyPoster = Issue40KeyEventPoster()
            let secureInput = Issue40SecureInputProvider(states: secureStates)
            let frontmostProcess = Issue40FrontmostProcessProvider(
                processIdentifiers: processIdentifiers
            )
            let output = SystemFinalTextOutput(
                pasteboardWriter: pasteboard,
                keyEventPoster: keyPoster,
                currentFocusEventPoster: Issue40FallbackUnicodePoster(),
                secureInputStateProvider: secureInput,
                frontmostProcessProvider: frontmostProcess
            )
            let delivery = makeIssue40ReviewDelivery(
                applicationRuntime: runtime,
                applicationActivator: activator,
                accessibility: Issue40StrictReviewAccess(
                    captureResult: .nonSecureCursorUnavailable
                ),
                finalTextOutput: output,
                accessibilityTrustProvider: Issue40AccessibilityTrustProvider()
            )
            let destination = Issue40Fixtures.applicationBoundDestination(
                identity: runtime.capturedIdentity,
                generation: 44
            )

            let result = await delivery.deliver("PRIVATE_STALE_DRAFT", to: destination)

            XCTAssertEqual(result, expectedResult, "application-bound " + name + " must fail closed")
            XCTAssertEqual(pasteboard.writtenTexts, [], "application-bound " + name + " must not mutate pasteboard")
            XCTAssertEqual(keyPoster.processIdentifiers, [], "application-bound " + name + " must not post cross-app text")
            XCTAssertEqual(secureInput.queryCount, 4, "application-bound " + name + " needs two composite security samples")
            XCTAssertEqual(frontmostProcess.queryCount, 2, "application-bound " + name + " needs a stable PID")
        }
    }

    func test_applicationBoundReviewDelivery_rejectsIdentityDriftDuringPreMutationSamples() async {
        let runtime = Issue40ApplicationRuntime()
        runtime.onIdentityQuery = { queryNumber in
            if queryNumber == 3 {
                runtime.runningIdentity = Issue40Fixtures.applicationIdentity(
                    pid: 42,
                    launchDate: Date(timeIntervalSince1970: 999)
                )
            }
        }
        let pasteboard = Issue40PasteboardWriter()
        let keyPoster = Issue40KeyEventPoster()
        let secureInput = Issue40SecureInputProvider(states: [false, false, false, false])
        let frontmostProcess = Issue40FrontmostProcessProvider(processIdentifiers: [42, 42])
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: keyPoster,
            currentFocusEventPoster: Issue40FallbackUnicodePoster(),
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess
        )
        let delivery = makeIssue40ReviewDelivery(
            applicationRuntime: runtime,
            applicationActivator: Issue40ApplicationActivator(),
            accessibility: Issue40StrictReviewAccess(
                captureResult: .nonSecureCursorUnavailable
            ),
            finalTextOutput: output,
            accessibilityTrustProvider: Issue40AccessibilityTrustProvider()
        )
        let destination = Issue40Fixtures.applicationBoundDestination(
            identity: runtime.capturedIdentity,
            generation: 46
        )

        let result = await delivery.deliver("PRIVATE_IDENTITY_DRIFT", to: destination)

        XCTAssertEqual(result, .identityChanged)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(keyPoster.processIdentifiers, [])
        XCTAssertGreaterThanOrEqual(runtime.identityQueryCount, 3)
    }

    func test_applicationBoundFallback_preflightUsesTwoOrderedCompositeSamples_andRejectsSecureTransitionBeforeMutation() async {
        let stableTrace = Issue40CompositeSampleTrace()
        let stableRuntime = Issue40CompositeApplicationRuntime(trace: stableTrace)
        let stableActivator = Issue40CompositeApplicationActivator(trace: stableTrace)
        let stableSecureInput = Issue40CompositeSecureInputProvider(trace: stableTrace)
        let stableFrontmostProcess = Issue40CompositeFrontmostProcessProvider(trace: stableTrace)
        let stablePasteboard = Issue40TracePasteboardWriter(trace: stableTrace)
        let stableKeyPoster = Issue40TraceKeyEventPoster(trace: stableTrace)
        let stableUnicodePoster = Issue40FallbackUnicodePoster(trace: stableTrace)
        var stableSnapshotCount = 0
        let stableOutput = SystemFinalTextOutput(
            pasteboardWriter: stablePasteboard,
            keyEventPoster: stableKeyPoster,
            currentFocusEventPoster: stableUnicodePoster,
            secureInputStateProvider: stableSecureInput,
            frontmostProcessProvider: stableFrontmostProcess,
        )
        let stableDelivery = makeIssue40ReviewDelivery(
            applicationRuntime: stableRuntime,
            applicationActivator: stableActivator,
            accessibility: Issue40StrictReviewAccess(
                captureResult: .nonSecureCursorUnavailable
            ),
            finalTextOutput: stableOutput,
            accessibilityTrustProvider: Issue40AccessibilityTrustProvider(),
            secureInputStateProvider: stableSecureInput,
            frontmostProcessProvider: stableFrontmostProcess
        )
        let stableDestination = Issue40Fixtures.applicationBoundDestination(
            identity: stableRuntime.capturedIdentity,
            generation: 47
        )

        let stableResult = await stableDelivery.deliver(
            "PRIVATE_STABLE_COMPOSITE",
            to: stableDestination
        )

        XCTAssertEqual(stableResult, .submittedUnverified)
        XCTAssertEqual(
            stableTrace.eventsBetween("activated", and: "unicode"),
            [
                "running", "frontmost",
                "secure", "pid", "running", "frontmost", "secure",
                "secure", "pid", "running", "frontmost", "secure"
            ],
            "fallback preflight must take two consecutive Secure/PID/identity/Secure samples"
        )
        XCTAssertEqual(stablePasteboard.writeCount, 0)
        XCTAssertEqual(stableKeyPoster.processIdentifiers, [])
        XCTAssertEqual(stableUnicodePoster.requestedTexts, ["PRIVATE_STABLE_COMPOSITE"])
        XCTAssertEqual(stableUnicodePoster.processIdentifiers, [42])
        XCTAssertEqual(stableSnapshotCount, 0)
        XCTAssertEqual(stableSecureInput.queryCount, 6)
        XCTAssertEqual(stableFrontmostProcess.queryCount, 3)
        XCTAssertEqual(stableActivator.activationRequests, [stableRuntime.capturedIdentity])

        let transitionTrace = Issue40CompositeSampleTrace()
        let transitionRuntime = Issue40CompositeApplicationRuntime(trace: transitionTrace)
        let transitionActivator = Issue40CompositeApplicationActivator(trace: transitionTrace)
        let transitionSecureInput = Issue40CompositeSecureInputProvider(trace: transitionTrace)
        let transitionFrontmostProcess = Issue40CompositeFrontmostProcessProvider(trace: transitionTrace)
        transitionRuntime.onIdentityQuery = { queryNumber in
            if queryNumber == 4 {
                transitionSecureInput.enableSecureInput()
            }
        }
        let transitionPasteboard = Issue40TracePasteboardWriter(trace: transitionTrace)
        let transitionKeyPoster = Issue40TraceKeyEventPoster(trace: transitionTrace)
        let transitionUnicodePoster = Issue40FallbackUnicodePoster(trace: transitionTrace)
        var transitionSnapshotCount = 0
        let transitionOutput = SystemFinalTextOutput(
            pasteboardWriter: transitionPasteboard,
            keyEventPoster: transitionKeyPoster,
            currentFocusEventPoster: transitionUnicodePoster,
            secureInputStateProvider: transitionSecureInput,
            frontmostProcessProvider: transitionFrontmostProcess,
        )
        let transitionDelivery = makeIssue40ReviewDelivery(
            applicationRuntime: transitionRuntime,
            applicationActivator: transitionActivator,
            accessibility: Issue40StrictReviewAccess(
                captureResult: .nonSecureCursorUnavailable
            ),
            finalTextOutput: transitionOutput,
            accessibilityTrustProvider: Issue40AccessibilityTrustProvider(),
            secureInputStateProvider: transitionSecureInput,
            frontmostProcessProvider: transitionFrontmostProcess
        )
        let transitionDestination = Issue40Fixtures.applicationBoundDestination(
            identity: transitionRuntime.capturedIdentity,
            generation: 48
        )

        let transitionResult = await transitionDelivery.deliver(
            "PRIVATE_SECURE_TRANSITION",
            to: transitionDestination
        )

        XCTAssertEqual(transitionResult, .securityRejected)
        XCTAssertEqual(
            transitionTrace.eventsAfter("activated"),
            [
                "running", "frontmost",
                "secure", "pid", "running", "frontmost", "secure",
                "secure", "pid", "running", "frontmost", "secure"
            ],
            "a secure transition during the second identity sample must be rejected by its ending Secure read"
        )
        XCTAssertEqual(transitionPasteboard.writeCount, 0)
        XCTAssertEqual(transitionKeyPoster.processIdentifiers, [])
        XCTAssertEqual(transitionUnicodePoster.requestedTexts, [])
        XCTAssertEqual(transitionUnicodePoster.processIdentifiers, [])
        XCTAssertEqual(transitionSnapshotCount, 0)
        XCTAssertEqual(transitionSecureInput.queryCount, 4)
        XCTAssertEqual(transitionFrontmostProcess.queryCount, 2)
        XCTAssertEqual(transitionActivator.activationRequests, [transitionRuntime.capturedIdentity])
    }

    func test_applicationBoundReviewDelivery_rejectsActivationIdentityUnsafeAndUncertainWithoutCursorOutput() async {
        let cases: [(String, (Issue40ApplicationRuntime, Issue40ApplicationActivator, Issue40FinalTextOutput) -> Void, String, ReviewDeliveryResult)] = [
            ("activation failure", { _, activator, _ in activator.result = .timedOut }, "PRIVATE_ACTIVATION", .activationFailed),
            ("identity change", { runtime, _, _ in
                runtime.runningIdentity = Issue40Fixtures.applicationIdentity(
                    pid: 42,
                    launchDate: Date(timeIntervalSince1970: 999)
                )
            }, "PRIVATE_IDENTITY", .identityChanged),
            ("wrong app", { runtime, _, _ in
                runtime.frontmost = Issue40Fixtures.applicationIdentity(pid: 99)
            }, "PRIVATE_WRONG_APP", .identityChanged),
            ("unsafe text", { _, _, _ in }, "PRIVATE_UNSAFE\u{0000}", .unsafeText),
            ("uncertain output", { _, _, output in output.currentFocusResult = .deliveryUncertain }, "PRIVATE_UNCERTAIN", .deliveryUncertain)
        ]

        for (name, configure, text, expectedResult) in cases {
            let runtime = Issue40ApplicationRuntime()
            let activator = Issue40ApplicationActivator()
            let output = Issue40FinalTextOutput()
            configure(runtime, activator, output)
            let delivery = makeIssue40ReviewDelivery(
                applicationRuntime: runtime,
                applicationActivator: activator,
                accessibility: Issue40StrictReviewAccess(
                    captureResult: .nonSecureCursorUnavailable
                ),
                finalTextOutput: output,
                accessibilityTrustProvider: Issue40AccessibilityTrustProvider()
            )
            let destination = Issue40Fixtures.applicationBoundDestination(
                identity: runtime.capturedIdentity,
                generation: 45
            )

            let result = await delivery.deliver(text, to: destination)

            XCTAssertEqual(result, expectedResult, "application-bound " + name + " must fail closed")
            XCTAssertEqual(output.currentFocusInsertedTexts, [], "application-bound " + name + " must not post text")
            XCTAssertEqual(output.cursorInsertedTexts, [], "application-bound " + name + " must not use exact cursor output")
        }
    }

    func test_reviewFirst_applicationBoundFallback_keepsPreviewAndRecognitionRetryIndependentOfGatedSurface() async {
        let session = Issue40StreamingSession(
            packetEvents: [.failed(.network), .partial("PRIVATE_REPLAYED_PREVIEW")],
            finishEvent: .final("PRIVATE_ACTION_TWO")
        )
        let provider = Issue40StreamingProvider(session: session)
        let recorder = Issue40AudioRecorder()
        let presenter = Issue40ReviewSurfacePresenter()
        presenter.readOnlyRenderGateOpen = false
        let delivery = Issue40ReviewDestinationDelivery(
            destination: Issue40Fixtures.applicationBoundDestination(generation: 42)
        )
        let viewModel = MainViewModel(
            audioRecorder: recorder,
            settings: AppSettings(
                appId: "configured-app",
                appSecret: "configured-secret",
                autoInsert: true,
                playSound: false,
                reviewBeforeInsert: true
            ),
            hotKeyWakeRecovering: Issue40HotKeyWakeRecoverer(),
            streamingProvider: provider,
            accessibilityClient: Issue40AccessibilityClient(),
            finalTextOutput: Issue40FinalTextOutput(),
            overlayPresenter: Issue40OverlayPresenter(),
            reviewDestinationDelivery: delivery,
            reviewSurfacePresenter: presenter,
            streamingRetryDelay: { _ in 0 },
            streamingRetrySleeper: { _ in }
        )
        let identity = StreamingSessionIdentity(generation: 42)

        viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil {
            recorder.startStreamingCallCount == 1
        }

        XCTAssertEqual(recorder.startStreamingCallCount, 1)
        await waitUntilAsync { await provider.makeSessionCallCount == 1 }
        let initialProviderCallCount = await provider.makeSessionCallCount
        XCTAssertEqual(initialProviderCallCount, 1)
        XCTAssertEqual(viewModel.transcriptionReviewState, .streaming(preview: ""))

        recorder.emit(Data(repeating: 0x40, count: 6_400))
        await waitUntilAsync { await session.sendCallCount >= 1 }
        await waitUntilAsync { await provider.makeSessionCallCount >= 2 }
        await waitUntil {
            viewModel.transcriptionReviewState ==
                .streaming(preview: "PRIVATE_REPLAYED_PREVIEW")
        }

        XCTAssertGreaterThanOrEqual(presenter.renderReadOnlyCallCount, 1)
        XCTAssertEqual(presenter.lastPresentedPreview, "")
        XCTAssertEqual(viewModel.transcriptionReviewState, .streaming(preview: "PRIVATE_REPLAYED_PREVIEW"))
        let sendCallCount = await session.sendCallCount
        XCTAssertGreaterThanOrEqual(sendCallCount, 2)

        viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntilAsync { await session.finishCallCount == 1 }
    }

    func test_reviewFirst_applicationBoundConfirmationFailureReturnsExactDraftWithoutCopy() async {
        let delivery = Issue40ReviewDestinationDelivery(
            destination: Issue40Fixtures.applicationBoundDestination(generation: 43),
            result: .deliveryUncertain
        )
        let context = makeReviewContext(delivery: delivery, finishText: "PRIVATE_FINAL")
        let identity = StreamingSessionIdentity(generation: 43)

        context.viewModel.handleHotKeyStateForTesting(.streaming(sessionID: identity))
        await waitUntil { context.recorder.startStreamingCallCount == 1 }
        await waitUntilAsync { await self.contextProviderCallCount(context) == 1 }
        context.viewModel.handleHotKeyStateForTesting(.sealing(sessionID: identity))
        await waitUntil {
            if case .editable = context.viewModel.transcriptionReviewState { return true }
            return false
        }

        let frozenDraft = "edited first line\nedited second line"
        context.presenter.invokeDraftChange(frozenDraft)
        context.presenter.invokeConfirm()
        context.presenter.invokeConfirm()
        await waitUntil { delivery.deliveredTexts.count == 1 }
        await waitUntil {
            if case .editable(_, _, feedback: .deliveryUncertain) = context.viewModel.transcriptionReviewState {
                return true
            }
            return false
        }

        XCTAssertEqual(delivery.deliveredTexts, [frozenDraft])
        XCTAssertEqual(delivery.copiedTexts, [])
        XCTAssertEqual(delivery.copyCalls, 0)
        XCTAssertEqual(context.output.cursorInsertedTexts, [])
        XCTAssertEqual(context.output.currentFocusInsertedTexts, [])
        XCTAssertEqual(
            context.viewModel.transcriptionReviewState,
            .editable(draft: frozenDraft, isPossiblyIncomplete: false, feedback: .deliveryUncertain)
        )
    }

    private func makeReviewContext(
        delivery: Issue40ReviewDestinationDelivery,
        finishText: String
    ) -> Issue40ReviewContext {
        let recorder = Issue40AudioRecorder()
        let session = Issue40StreamingSession(
            packetEvents: [],
            finishEvent: .final(finishText)
        )
        let provider = Issue40StreamingProvider(session: session)
        let output = Issue40FinalTextOutput()
        let presenter = Issue40ReviewSurfacePresenter()
        let viewModel = MainViewModel(
            audioRecorder: recorder,
            settings: AppSettings(
                appId: "configured-app",
                appSecret: "configured-secret",
                autoInsert: true,
                playSound: false,
                reviewBeforeInsert: true
            ),
            hotKeyWakeRecovering: Issue40HotKeyWakeRecoverer(),
            streamingProvider: provider,
            accessibilityClient: Issue40AccessibilityClient(),
            finalTextOutput: output,
            overlayPresenter: Issue40OverlayPresenter(),
            reviewDestinationDelivery: delivery,
            reviewSurfacePresenter: presenter
        )
        return Issue40ReviewContext(
            viewModel: viewModel,
            recorder: recorder,
            provider: provider,
            output: output,
            presenter: presenter
        )
    }

    private func contextProviderCallCount(_ context: Issue40ReviewContext) async -> Int {
        await context.provider.makeSessionCallCount
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0 ..< 300 {
            if predicate() { return }
            await Task.yield()
        }
        logger.debug("review fallback wait timed out")
        XCTFail("timed out waiting for review fallback state")
    }

    private func waitUntilAsync(
        _ predicate: @escaping @MainActor () async -> Bool
    ) async {
        for _ in 0 ..< 300 {
            if await predicate() { return }
            await Task.yield()
        }
        logger.debug("review fallback async wait timed out")
        XCTFail("timed out waiting for review fallback async state")
    }
}

@MainActor
private struct Issue40ReviewContext {
    let viewModel: MainViewModel
    let recorder: Issue40AudioRecorder
    let provider: Issue40StreamingProvider
    let output: Issue40FinalTextOutput
    let presenter: Issue40ReviewSurfacePresenter
}

@MainActor
private final class Issue40ReviewTrace {
    var events: [String] = []
}

private enum Issue40Fixtures {
    static func applicationIdentity(
        pid: pid_t = 42,
        launchDate: Date = Date(timeIntervalSince1970: 40),
        bundleIdentifier: String = "com.example.issue40.target"
    ) -> ReviewApplicationIdentity {
        ReviewApplicationIdentity(
            processIdentifier: pid,
            bundleIdentifier: bundleIdentifier,
            executableURL: URL(fileURLWithPath: "/Applications/Issue40Target.app/Contents/MacOS/Target"),
            launchDate: launchDate
        )
    }

    static func applicationBoundDestination(
        identity: ReviewApplicationIdentity = applicationIdentity(),
        generation: UInt64 = 40
    ) -> ReviewDestinationToken {
        return ReviewDestinationToken(
            generation: generation,
            application: identity,
            binding: .applicationCurrentFocus,
            capturedSecurityState: .safe
        )
    }
}

@MainActor
private final class Issue40ApplicationRuntime: ReviewApplicationRuntime {
    let capturedIdentity: ReviewApplicationIdentity
    var runningIdentity: ReviewApplicationIdentity
    var frontmost: ReviewApplicationIdentity
    let trace: Issue40ReviewTrace
    var onIdentityQuery: ((Int) -> Void)?
    private(set) var identityQueryCount = 0

    convenience init() {
        self.init(trace: Issue40ReviewTrace())
    }

    init(trace: Issue40ReviewTrace) {
        capturedIdentity = Issue40Fixtures.applicationIdentity()
        runningIdentity = capturedIdentity
        frontmost = capturedIdentity
        self.trace = trace
    }

    func identity(for processIdentifier: pid_t) -> ReviewApplicationIdentity? {
        identityQueryCount += 1
        if trace.events.count < 3 {
            trace.events.append("identity-before-ax")
        } else {
            trace.events.append("identity-after-ax")
        }
        let identity = processIdentifier == capturedIdentity.processIdentifier ? runningIdentity : nil
        onIdentityQuery?(identityQueryCount)
        return identity
    }

    func frontmostIdentity() -> ReviewApplicationIdentity? {
        if trace.events.isEmpty {
            trace.events.append("frontmost-before-ax")
        } else {
            trace.events.append("frontmost-after-ax")
        }
        return frontmost
    }
}

@MainActor
private final class Issue40CompositeSampleTrace {
    private(set) var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func eventsBetween(_ firstMarker: String, and secondMarker: String) -> [String] {
        guard let firstIndex = events.firstIndex(of: firstMarker),
              let secondIndex = events[(firstIndex + 1)...].firstIndex(of: secondMarker),
              firstIndex < secondIndex else {
            return []
        }
        return Array(events[(firstIndex + 1) ..< secondIndex])
    }

    func eventsAfter(_ marker: String) -> [String] {
        guard let markerIndex = events.firstIndex(of: marker) else {
            return []
        }
        return Array(events[(markerIndex + 1)...])
    }
}

@MainActor
private final class Issue40CompositeApplicationRuntime: ReviewApplicationRuntime {
    let capturedIdentity: ReviewApplicationIdentity
    var runningIdentity: ReviewApplicationIdentity
    var frontmost: ReviewApplicationIdentity
    let trace: Issue40CompositeSampleTrace
    var onIdentityQuery: ((Int) -> Void)?
    private(set) var identityQueryCount = 0

    init(trace: Issue40CompositeSampleTrace) {
        capturedIdentity = Issue40Fixtures.applicationIdentity()
        runningIdentity = capturedIdentity
        frontmost = capturedIdentity
        self.trace = trace
    }

    func identity(for processIdentifier: pid_t) -> ReviewApplicationIdentity? {
        trace.append("running")
        identityQueryCount += 1
        let identity = processIdentifier == capturedIdentity.processIdentifier ? runningIdentity : nil
        onIdentityQuery?(identityQueryCount)
        return identity
    }

    func frontmostIdentity() -> ReviewApplicationIdentity? {
        trace.append("frontmost")
        return frontmost
    }

    func frontmostProcessIdentifier() -> pid_t? {
        trace.append("pid")
        return frontmost.processIdentifier
    }
}

@MainActor
private final class Issue40CompositeApplicationActivator: ReviewApplicationActivating {
    let trace: Issue40CompositeSampleTrace
    private(set) var activationRequests: [ReviewApplicationIdentity] = []

    init(trace: Issue40CompositeSampleTrace) {
        self.trace = trace
    }

    func activateAndWait(
        for identity: ReviewApplicationIdentity,
        timeoutNanoseconds: UInt64
    ) async -> ReviewActivationResult {
        trace.append("activated")
        activationRequests.append(identity)
        return .activated
    }
}

@MainActor
private final class Issue40CompositeSecureInputProvider: SecureInputStateProviding {
    let trace: Issue40CompositeSampleTrace
    private(set) var queryCount = 0
    private var secureInputEnabled = false

    init(trace: Issue40CompositeSampleTrace) {
        self.trace = trace
    }

    func enableSecureInput() {
        secureInputEnabled = true
    }

    func isSecureInputEnabled() -> Bool {
        trace.append("secure")
        queryCount += 1
        return secureInputEnabled
    }
}

@MainActor
private final class Issue40CompositeFrontmostProcessProvider: FrontmostProcessProviding {
    let trace: Issue40CompositeSampleTrace
    private(set) var queryCount = 0

    init(trace: Issue40CompositeSampleTrace) {
        self.trace = trace
    }

    func frontmostProcessIdentifier() -> pid_t? {
        trace.append("pid")
        queryCount += 1
        return 42
    }
}

@MainActor
private final class Issue40FallbackInputMonitor: CurrentFocusInputMonitoring {
    let supportsReviewDeliveryEpoch = true
    var interferenceEpoch: UInt64 = 0

    func startMonitoring(_ handler: @escaping @MainActor () -> Void) {}

    func armMonitoringFailClosed(_ handler: @escaping @MainActor () -> Void) -> Bool {
        true
    }

    func armMonitoringFailClosedWithEpoch(
        _ handler: @escaping @MainActor () -> Void
    ) -> UInt64? {
        0
    }

    func postCompleteSyntheticPairIfInterferenceEpochIsUnchanged(
        expectedEpoch: UInt64,
        _ postPair: () -> Void
    ) -> Bool {
        guard expectedEpoch == interferenceEpoch else { return false }
        postPair()
        return true
    }

    func stopMonitoring() {}
}

@MainActor
private final class Issue40FallbackActivationMonitor: CurrentFocusActivationMonitoring {
    let supportsReviewDeliveryEpoch = true
    var activationEpoch: UInt64 = 0

    func startMonitoring(_ handler: @escaping @MainActor (pid_t) -> Void) {}

    func armMonitoringFailClosedWithEpoch(
        _ handler: @escaping @MainActor (pid_t) -> Void
    ) -> UInt64? {
        0
    }

    func stopMonitoring() {}
}

@MainActor
private final class Issue40FallbackUnicodePoster: FinalTextCurrentFocusEventPosting {
    let trace: Issue40CompositeSampleTrace?
    var result: FinalTextCurrentFocusPostResult = .posted
    private(set) var requestedTexts: [String] = []
    private(set) var processIdentifiers: [pid_t] = []

    init(trace: Issue40CompositeSampleTrace? = nil) {
        self.trace = trace
    }

    func postUnicodeText(
        _ text: String,
        to processIdentifier: pid_t
    ) -> FinalTextCurrentFocusPostResult {
        trace?.append("unicode")
        requestedTexts.append(text)
        processIdentifiers.append(processIdentifier)
        return result
    }

    func postReviewUnicodePair(
        _ text: String,
        to processIdentifier: pid_t,
        postPairIfPreflightRemainsValid pairGate: (
            (_ postPair: @escaping () -> Void
            ) -> Bool
        ),
        validateAfterPosting: () -> ReviewCurrentFocusValidation
    ) -> ReviewUnicodeOutputResult {
        var posted = false
        guard pairGate({
            posted = true
            _ = self.postUnicodeText(text, to: processIdentifier)
        }), posted else {
            return .failedBeforeSubmission(.preflightRejected)
        }
        switch result {
        case .posted:
            return validateAfterPosting() == .valid
                ? .submittedUnverified(.valid)
                : .submittedUnverified(.uncertain)
        case .securityRejected:
            return .failedBeforeSubmission(.secureInput)
        case .deliveryFailed:
            return .failedBeforeSubmission(.constructionFailed)
        }
    }
}

@MainActor
private final class Issue40TracePasteboardWriter: FinalTextPasteboardWriting {
    let trace: Issue40CompositeSampleTrace
    private(set) var writeCount = 0

    init(trace: Issue40CompositeSampleTrace) {
        self.trace = trace
    }

    func replaceContents(with _: String) -> Bool {
        trace.append("pasteboard")
        writeCount += 1
        return true
    }
}

@MainActor
private final class Issue40TraceKeyEventPoster: FinalTextKeyEventPosting {
    let trace: Issue40CompositeSampleTrace
    private(set) var processIdentifiers: [pid_t] = []

    init(trace: Issue40CompositeSampleTrace) {
        self.trace = trace
    }

    func postCommandV(to processIdentifier: pid_t) -> Bool {
        trace.append("cmdv")
        processIdentifiers.append(processIdentifier)
        return true
    }
}

@MainActor
private final class Issue40ApplicationActivator: ReviewApplicationActivating {
    var result: ReviewActivationResult = .activated
    private(set) var activationRequests: [ReviewApplicationIdentity] = []

    func activateAndWait(
        for identity: ReviewApplicationIdentity,
        timeoutNanoseconds: UInt64
    ) async -> ReviewActivationResult {
        activationRequests.append(identity)
        return result
    }
}

@MainActor
private final class Issue40AccessibilityTrustProvider: AccessibilityTrustProviding {
    private var trustedValue: Bool
    private var queuedSamples: [Bool] = []
    private(set) var readCount = 0

    init(isAccessibilityTrusted: Bool = true) {
        trustedValue = isAccessibilityTrusted
    }

    var isAccessibilityTrusted: Bool {
        get {
            readCount += 1
            if !queuedSamples.isEmpty {
                return queuedSamples.removeFirst()
            }
            return trustedValue
        }
        set {
            trustedValue = newValue
            queuedSamples = []
        }
    }

    func setQueuedSamples(_ samples: [Bool]) {
        queuedSamples = samples
    }

}

@MainActor
private final class Issue40StrictReviewAccess: ReviewDestinationAccessing {
    private let captureResult: ReviewCursorCaptureResult
    private let trace: Issue40ReviewTrace?
    private(set) var captureCallCount = 0
    private(set) var restoreCallCount = 0
    private(set) var validateAfterCallCount = 0

    init(
        captureResult: ReviewCursorCaptureResult,
        trace: Issue40ReviewTrace? = nil
    ) {
        self.captureResult = captureResult
        self.trace = trace
    }

    func captureReviewCursorDestination(generation: UInt64) -> ReviewCursorCaptureResult {
        captureCallCount += 1
        trace?.events.append("ax")
        switch captureResult {
        case .exact:
            return .exact(
                CursorDestinationToken(
                    generation: generation,
                    processIdentifier: 42,
                    element: AXUIElementCreateApplication(42),
                    originalSelection: CursorTextRange(location: 0, length: 0)
                )
            )
        case .nonSecureCursorUnavailable, .rejected:
            return captureResult
        }
    }

    func restoreAndValidateBeforeDelivery(_ token: CursorDestinationToken) throws -> Bool {
        restoreCallCount += 1
        return true
    }

    func validateAfterDelivery(_ token: CursorDestinationToken) throws -> Bool {
        validateAfterCallCount += 1
        return true
    }
}

@MainActor
private final class Issue40FinalTextOutput: FinalTextOutput {
    private(set) var cursorInsertedTexts: [String] = []
    private(set) var currentFocusInsertedTexts: [String] = []
    private(set) var copiedTexts: [String] = []
    var currentFocusResult: FinalTextInsertionResult = .inserted

    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateDestination: () throws -> Bool
    ) -> FinalTextInsertionResult {
        do {
            guard try validateDestination() else { return .destinationInvalid }
        } catch {
            return .destinationInvalid
        }
        cursorInsertedTexts.append(text)
        return .inserted
    }

    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateBeforeMutation: () throws -> Bool,
        validateAfterPosting: () throws -> Bool
    ) -> FinalTextInsertionResult {
        do {
            guard try validateBeforeMutation() else { return .destinationInvalid }
            cursorInsertedTexts.append(text)
            return try validateAfterPosting() ? .inserted : .deliveryUncertain
        } catch {
            return .deliveryUncertain
        }
    }

    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateBeforeMutation: @escaping () throws -> Bool,
        validateAfterPosting: () throws -> Bool,
        postPairIfPreflightRemainsValid pairGate: (@escaping () -> Void) -> Bool
    ) -> FinalTextInsertionResult {
        do {
            guard try validateBeforeMutation() else { return .destinationInvalid }
            var didInsert = false
            guard pairGate({ [self] in
                self.cursorInsertedTexts.append(text)
                didInsert = true
            }), didInsert else {
                return .deliveryFailed
            }
            return try validateAfterPosting() ? .inserted : .deliveryUncertain
        } catch {
            return .deliveryUncertain
        }
    }

    func insertReviewAtCurrentFocusOnce(
        _ text: String,
        processIdentifier _: pid_t,
        validateBeforeMutation: () -> ReviewCurrentFocusValidation,
        validateAfterPosting: () -> ReviewCurrentFocusValidation
    ) -> FinalTextInsertionResult {
        switch validateBeforeMutation() {
        case .valid:
            break
        case .securityRejected:
            return .securityRejected
        case .identityChanged:
            return .identityChanged
        case .destinationInvalid:
            return .destinationInvalid
        }
        switch currentFocusResult {
        case .inserted:
            currentFocusInsertedTexts.append(text)
        default:
            return currentFocusResult
        }
        switch validateAfterPosting() {
        case .valid:
            return .inserted
        case .securityRejected:
            return .securityRejected
        case .identityChanged:
            return .identityChanged
        case .destinationInvalid:
            return .deliveryUncertain
        }
    }

    func insertReviewAtCurrentFocusOnce(
        _ text: String,
        processIdentifier _: pid_t,
        validateBeforeMutation: @escaping () -> ReviewCurrentFocusValidation,
        validateAfterPosting: () -> ReviewCurrentFocusValidation,
        postPairIfPreflightRemainsValid pairGate: (@escaping () -> Void) -> Bool
    ) -> FinalTextInsertionResult {
        switch validateBeforeMutation() {
        case .valid:
            break
        case .securityRejected:
            return .securityRejected
        case .identityChanged:
            return .identityChanged
        case .destinationInvalid:
            return .destinationInvalid
        }
        guard currentFocusResult == .inserted else { return currentFocusResult }
        var didInsert = false
        guard pairGate({ [self] in
            self.currentFocusInsertedTexts.append(text)
            didInsert = true
        }), didInsert else {
            return .deliveryFailed
        }
        switch validateAfterPosting() {
        case .valid:
            return .inserted
        case .securityRejected:
            return .securityRejected
        case .identityChanged, .destinationInvalid:
            return .deliveryUncertain
        }
    }

    func insertAtCurrentFocusOnce(_ text: String) -> FinalTextInsertionResult {
        currentFocusInsertedTexts.append(text)
        return currentFocusResult
    }

    func copyForManualRecovery(_ text: String) {
        copiedTexts.append(text)
    }
}

@MainActor
private final class Issue40PasteboardWriter: FinalTextPasteboardWriting {
    private(set) var writtenTexts: [String] = []

    func replaceContents(with text: String) -> Bool {
        writtenTexts.append(text)
        return true
    }
}

@MainActor
private final class Issue40KeyEventPoster: FinalTextKeyEventPosting {
    private(set) var processIdentifiers: [pid_t] = []

    func postCommandV(to processIdentifier: pid_t) -> Bool {
        processIdentifiers.append(processIdentifier)
        return true
    }
}

@MainActor
private final class Issue40CurrentFocusEventPoster: FinalTextCurrentFocusEventPosting {
    private(set) var requestedTexts: [String] = []
    private(set) var requestedProcessIdentifiers: [pid_t] = []

    func postUnicodeText(
        _ text: String,
        to processIdentifier: pid_t
    ) -> FinalTextCurrentFocusPostResult {
        requestedTexts.append(text)
        requestedProcessIdentifiers.append(processIdentifier)
        return .posted
    }
}

@MainActor
private final class Issue40SecureInputProvider: SecureInputStateProviding {
    private var states: [Bool]
    private(set) var queryCount = 0

    init(states: [Bool]) {
        self.states = states
    }

    func isSecureInputEnabled() -> Bool {
        queryCount += 1
        return states.isEmpty ? true : states.removeFirst()
    }
}

@MainActor
private final class Issue40FrontmostProcessProvider: FrontmostProcessProviding {
    private var processIdentifiers: [pid_t?]
    private(set) var queryCount = 0

    init(processIdentifiers: [pid_t?]) {
        self.processIdentifiers = processIdentifiers
    }

    func frontmostProcessIdentifier() -> pid_t? {
        queryCount += 1
        return processIdentifiers.isEmpty ? nil : processIdentifiers.removeFirst()
    }
}

@MainActor
private final class Issue40ReviewDestinationDelivery: ReviewDestinationDelivering {
    let destination: ReviewDestinationToken
    var result: ReviewDeliveryResult
    private(set) var captureCallCount = 0
    private(set) var deliveredTexts: [String] = []
    private(set) var deliveredDestinations: [ReviewDestinationToken] = []
    private(set) var copyCalls = 0
    private(set) var copiedTexts: [String] = []

    init(
        destination: ReviewDestinationToken,
        result: ReviewDeliveryResult = .submittedUnverified
    ) {
        self.destination = destination
        self.result = result
    }

    func capture(generation: UInt64) -> ReviewDestinationCaptureResult {
        captureCallCount += 1
        return .captured(destination)
    }

    func deliver(
        _ frozenText: String,
        to destination: ReviewDestinationToken
    ) async -> ReviewDeliveryResult {
        deliveredTexts.append(frozenText)
        deliveredDestinations.append(destination)
        return result
    }

    func copyForManualRecovery(_ frozenText: String) {
        copyCalls += 1
        copiedTexts.append(frozenText)
    }
}

@MainActor
private final class Issue40TrustRevokingReviewDelivery: ReviewDestinationDelivering {
    private let delivery: SystemReviewDestinationDelivery
    private let trustProvider: Issue40AccessibilityTrustProvider
    private(set) var captureCallCount = 0
    private(set) var deliverCallCount = 0
    private(set) var deliveredTexts: [String] = []
    private(set) var deliveredDestinations: [ReviewDestinationToken] = []

    init(
        delivery: SystemReviewDestinationDelivery,
        trustProvider: Issue40AccessibilityTrustProvider
    ) {
        self.delivery = delivery
        self.trustProvider = trustProvider
    }

    func capture(generation: UInt64) -> ReviewDestinationCaptureResult {
        captureCallCount += 1
        return delivery.capture(generation: generation)
    }

    func deliver(
        _ frozenText: String,
        to destination: ReviewDestinationToken
    ) async -> ReviewDeliveryResult {
        deliverCallCount += 1
        deliveredTexts.append(frozenText)
        deliveredDestinations.append(destination)
        trustProvider.isAccessibilityTrusted = false
        return await delivery.deliver(frozenText, to: destination)
    }
}

private actor Issue40StreamingSession: SpeechStreamingSession {
    private var packetEvents: [StreamingRecognitionEvent]
    private let finishEvent: StreamingRecognitionEvent
    private(set) var sendCallCount = 0
    private(set) var finishCallCount = 0

    init(
        packetEvents: [StreamingRecognitionEvent],
        finishEvent: StreamingRecognitionEvent
    ) {
        self.packetEvents = packetEvents
        self.finishEvent = finishEvent
    }

    func sendAudioPacket(_ pcm16: Data) async throws -> StreamingRecognitionEvent {
        sendCallCount += 1
        return packetEvents.isEmpty ? .partial("") : packetEvents.removeFirst()
    }

    func finish() async throws -> StreamingRecognitionEvent {
        finishCallCount += 1
        return finishEvent
    }

    func cancel() async {}
}

private actor Issue40StreamingProvider: SpeechStreamingSessionProviding {
    let session: Issue40StreamingSession
    private(set) var makeSessionCallCount = 0

    init(session: Issue40StreamingSession) {
        self.session = session
    }

    func makeStreamingSession(
        appId: String,
        appSecret: String
    ) async throws -> any SpeechStreamingSession {
        makeSessionCallCount += 1
        return session
    }
}

@MainActor
private final class Issue40AudioRecorder: AudioRecorder {
    private var ingress: ByteBoundedAudioIngress?
    private(set) var startStreamingCallCount = 0

    override func startStreamingRecording(
        ingress: ByteBoundedAudioIngress,
        completion: @escaping (_ started: Bool) -> Void
    ) -> Bool {
        startStreamingCallCount += 1
        self.ingress = ingress
        isRecording = true
        completion(true)
        return true
    }

    override func stopStreamingRecording(streamEstablished: Bool) async {
        isRecording = false
        ingress?.finish(streamEstablished: streamEstablished)
    }

    override func forceCleanup() {
        ingress?.fail(.cancelled)
        ingress = nil
        isRecording = false
    }

    func emit(_ data: Data) {
        _ = ingress?.append(data)
    }
}

@MainActor
private final class Issue40ReviewSurfacePresenter: ReviewSurfacePresenting {
    var readOnlyRenderGateOpen = true
    private(set) var renderReadOnlyCallCount = 0
    private(set) var lastPresentedPreview = ""
    private(set) var renderDraftCallCount = 0
    private var draftState: TranscriptionReviewState?
    private var onDraftChange: (@MainActor (String) -> Void)?
    private var onConfirm: (@MainActor (ReviewConfirmationIntent) -> Void)?

    func renderReadOnly(phase: ReviewReadOnlyPhase, preview: String) {
        renderReadOnlyCallCount += 1
        guard readOnlyRenderGateOpen else { return }
        lastPresentedPreview = preview
    }

    func renderDraft(
        state: TranscriptionReviewState,
        onDraftChange: @escaping @MainActor (String) -> Void,
        onConfirm: @escaping @MainActor (ReviewConfirmationIntent) -> Void,
        onDiscard: @escaping @MainActor () -> Void
    ) {
        renderDraftCallCount += 1
        draftState = state
        self.onDraftChange = onDraftChange
        self.onConfirm = onConfirm
    }

    func requestPresentationFocus(
        _ request: ReviewPresentationFocusRequest
    ) async -> ReviewPresentationFocusOutcome {
        ReviewPresentationFocusOutcome(request: request, result: .focused)
    }

    func dismiss() {}

    func invokeDraftChange(_ draft: String) {
        onDraftChange?(draft)
        if case .editable(_, let isPossiblyIncomplete, _) = draftState {
            draftState = .editable(
                draft: draft,
                isPossiblyIncomplete: isPossiblyIncomplete,
                feedback: nil
            )
        }
    }

    func invokeConfirm() {
        guard let draftState,
              case .editable = draftState,
              let onConfirm else { return }
        let hostingView = NSHostingView(
            rootView: TranscriptionReviewView(
                state: draftState,
                onConfirm: onConfirm
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        guard let editor = editableTextView(in: hostingView) else {
            XCTFail("the opaque confirmation path must materialize the real editable editor")
            window.orderOut(nil)
            window.close()
            return
        }
        XCTAssertTrue(window.makeFirstResponder(editor))
        guard let returnEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ) else {
            XCTFail("the qualified native Return event must be constructible")
            window.orderOut(nil)
            window.close()
            return
        }
        editor.keyDown(with: returnEvent)
        window.orderOut(nil)
        window.close()
    }

    private func editableTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView, textView.isEditable {
            return textView
        }
        for subview in view.subviews.reversed() {
            if let textView = editableTextView(in: subview) {
                return textView
            }
        }
        return nil
    }
}

@MainActor
private final class Issue40AccessibilityClient: AccessibilityClient {
    private let element = AXUIElementCreateApplication(42)

    func captureDestination(generation: UInt64) throws -> CursorCapabilityResult {
        .rejected(.accessibilityUnavailable)
    }

    func frontmostProcessIdentifier() -> pid_t? { 42 }

    func focusedElement() throws -> AXUIElement { element }

    func currentSecurityState(for token: CursorDestinationToken) throws -> DestinationSecurityState { .safe }

    func selectedTextRange(for token: CursorDestinationToken) throws -> CursorTextRange {
        CursorTextRange(location: 0, length: 0)
    }

    func string(for range: CursorTextRange, in token: CursorDestinationToken) throws -> String { "" }

    func setSelectedTextRange(_ range: CursorTextRange, for token: CursorDestinationToken) throws {}

    func setSelectedText(_ text: String, for token: CursorDestinationToken) throws {}
}

@MainActor
private final class Issue40OverlayPresenter: RecordingOverlayPresenting {
    func show(status: RecordingState) {}
    func update(status: RecordingState) {}
    func hide() {}
    func presentCompletionFeedback(
        _ feedback: RecordingState,
        minimumVisibleDuration: TimeInterval
    ) {}
}

@MainActor
private final class Issue40HotKeyWakeRecoverer: HotKeyWakeRecovering {
    func recoverAfterWake() {}
}
