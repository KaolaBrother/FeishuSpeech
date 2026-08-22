import AppKit
import ApplicationServices
import Foundation
import os.log
import XCTest

@testable import FeishuSpeech

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "ReviewDestinationDeliveryTests"
)

@MainActor
final class ReviewDestinationDeliveryTests: XCTestCase {
    func test_reviewCaptureReadsExactSelectionAndSecurity_withoutSelectedTextQueryOrWrite() throws {
        logger.debug("checking review destination capture contract")
        let runtime = Issue38ReviewAccessibilityRuntime()
        let client = MacAccessibilityClient(runtime: runtime)

        let token = try client.captureReviewCursorDestination(generation: 38)

        XCTAssertEqual(token.originalSelection, CursorTextRange(location: 7, length: 3))
        XCTAssertTrue(runtime.attributeQueries.contains(kAXSelectedTextRangeAttribute as String))
        XCTAssertTrue(runtime.attributeQueries.contains(kAXFocusedAttribute as String))
        XCTAssertFalse(
            runtime.attributeQueries.contains(kAXSelectedTextAttribute as String),
            "review capture must not probe the non-writable selected-text attribute"
        )
        XCTAssertEqual(runtime.selectedTextWriteCallCount, 0)
        XCTAssertEqual(runtime.focusWriteCallCount, 0)
        XCTAssertEqual(runtime.selectionWriteCallCount, 0)
    }

    func test_reviewCapture_failsClosedForTrustSecureInputOrSelectionUncertainty() {
        let cases: [(String, (Issue38ReviewAccessibilityRuntime) -> Void)] = [
            ("untrusted", { $0.isProcessTrusted = false }),
            ("secure input", { $0.isSecureEventInputEnabled = true }),
            ("wrong frontmost PID", { $0.currentProcessIdentifier = 99 }),
            ("selection not settable", { $0.settableAttributes[kAXSelectedTextRangeAttribute as String] = false }),
            ("focus not settable", { $0.settableAttributes[kAXFocusedAttribute as String] = false }),
            ("unsupported role", { $0.role = "AXButton" }),
            ("secure role", { $0.subrole = kAXSecureTextFieldSubrole as String })
        ]

        for (name, configure) in cases {
            let runtime = Issue38ReviewAccessibilityRuntime()
            configure(runtime)
            let client = MacAccessibilityClient(runtime: runtime)

            XCTAssertThrowsError(
                try client.captureReviewCursorDestination(generation: 39),
                "review capture must fail closed for \(name)"
            )
            XCTAssertEqual(runtime.selectedTextWriteCallCount, 0)
        }
    }

    func test_restoreAndValidateBeforeDelivery_writesOnlyFocusAndSelectionInOrder() throws {
        let runtime = Issue38ReviewAccessibilityRuntime()
        let client = MacAccessibilityClient(runtime: runtime)
        let token = try client.captureReviewCursorDestination(generation: 40)
        runtime.resetTrace()

        XCTAssertTrue(try client.restoreAndValidateBeforeDelivery(token))

        XCTAssertEqual(
            runtime.trace,
            ["focused-write", "focused-read", "selection-write", "selection-read", "security-read"]
        )
        XCTAssertEqual(runtime.selectedTextWriteCallCount, 0)
    }

    func test_applicationIdentityEqualityIncludesPIDBundleExecutableAndLaunchDate() {
        let base = Issue38ReviewFixtures.applicationIdentity(pid: 41)

        XCTAssertNotEqual(base, Issue38ReviewFixtures.applicationIdentity(pid: 42))
        XCTAssertNotEqual(
            base,
            ReviewApplicationIdentity(
                processIdentifier: 41,
                bundleIdentifier: "com.example.relaunched",
                executableURL: base.executableURL,
                launchDate: base.launchDate
            )
        )
        XCTAssertNotEqual(
            base,
            ReviewApplicationIdentity(
                processIdentifier: 41,
                bundleIdentifier: base.bundleIdentifier,
                executableURL: URL(fileURLWithPath: "/Applications/Other.app"),
                launchDate: base.launchDate
            )
        )
        XCTAssertNotEqual(
            base,
            ReviewApplicationIdentity(
                processIdentifier: 41,
                bundleIdentifier: base.bundleIdentifier,
                executableURL: base.executableURL,
                launchDate: Date(timeIntervalSince1970: 999)
            )
        )
    }

    func test_twoPhasePaste_runsOriginalSelectionPreflightBeforePasteboardMutation() {
        let trace = Issue38ReviewTrace()
        let pasteboard = Issue38ReviewPasteboardWriter(trace: trace)
        let keyPoster = Issue38ReviewKeyEventPoster(trace: trace)
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: keyPoster
        )
        var beforeCalls = 0
        var afterCalls = 0

        let result = output.insertOnce(
            "PRIVATE_FROZEN_DRAFT",
            destination: Issue38ReviewFixtures.cursorToken(),
            validateBeforeMutation: {
                beforeCalls += 1
                trace.events.append("preflight")
                return true
            },
            validateAfterPosting: {
                afterCalls += 1
                trace.events.append("postflight")
                return true
            }
        )

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(beforeCalls, 1)
        XCTAssertEqual(afterCalls, 1)
        XCTAssertEqual(trace.events, ["preflight", "pasteboard", "post-command-v", "postflight"])
        XCTAssertEqual(pasteboard.writtenTexts, ["PRIVATE_FROZEN_DRAFT"])
        XCTAssertEqual(keyPoster.processIdentifiers, [42])
    }

    func test_twoPhasePaste_preflightFailureLeavesPasteboardAndSyntheticEventsUntouched() {
        let trace = Issue38ReviewTrace()
        let pasteboard = Issue38ReviewPasteboardWriter(trace: trace)
        let keyPoster = Issue38ReviewKeyEventPoster(trace: trace)
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: keyPoster
        )

        let result = output.insertOnce(
            "PRIVATE_FROZEN_DRAFT",
            destination: Issue38ReviewFixtures.cursorToken(),
            validateBeforeMutation: { false },
            validateAfterPosting: { XCTFail("postflight must not run after preflight rejection"); return false }
        )

        XCTAssertEqual(result, .destinationInvalid)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(keyPoster.processIdentifiers, [])
        XCTAssertEqual(trace.events, [])
    }

    func test_twoPhasePaste_postflightFailureIsUncertainAndNeverRetries() {
        let trace = Issue38ReviewTrace()
        let pasteboard = Issue38ReviewPasteboardWriter(trace: trace)
        let keyPoster = Issue38ReviewKeyEventPoster(trace: trace)
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: keyPoster
        )

        let result = output.insertOnce(
            "PRIVATE_FROZEN_DRAFT",
            destination: Issue38ReviewFixtures.cursorToken(),
            validateBeforeMutation: { true },
            validateAfterPosting: { false }
        )

        XCTAssertEqual(result, .deliveryUncertain)
        XCTAssertEqual(pasteboard.writtenTexts, ["PRIVATE_FROZEN_DRAFT"])
        XCTAssertEqual(keyPoster.processIdentifiers, [42])
    }

    func test_twoPhasePaste_rejectsUnsafeTextBeforeAnyMutation() {
        let trace = Issue38ReviewTrace()
        let pasteboard = Issue38ReviewPasteboardWriter(trace: trace)
        let keyPoster = Issue38ReviewKeyEventPoster(trace: trace)
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: keyPoster
        )

        let result = output.insertOnce(
            "PRIVATE_UNSAFE\u{0000}",
            destination: Issue38ReviewFixtures.cursorToken(),
            validateBeforeMutation: { XCTFail("unsafe text must be rejected before preflight"); return true },
            validateAfterPosting: { XCTFail("unsafe text must not reach postflight"); return true }
        )

        XCTAssertEqual(result, .deliveryFailed)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(keyPoster.processIdentifiers, [])
    }

    func test_twoPhasePaste_acceptsExactMultilineReviewDraft_withoutNormalization() {
        let draft = "first line\nsecond line"
        let trace = Issue38ReviewTrace()
        let pasteboard = Issue38ReviewPasteboardWriter(trace: trace)
        let keyPoster = Issue38ReviewKeyEventPoster(trace: trace)
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: keyPoster
        )

        let result = output.insertOnce(
            draft,
            destination: Issue38ReviewFixtures.cursorToken(),
            validateBeforeMutation: { true },
            validateAfterPosting: { true }
        )

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(pasteboard.writtenTexts, [draft])
        XCTAssertEqual(keyPoster.processIdentifiers, [42])
    }

    func test_twoPhasePaste_rejectsTabAndCarriageReturn_withoutNormalization() {
        for draft in ["first\tline", "first\rline"] {
            let trace = Issue38ReviewTrace()
            let pasteboard = Issue38ReviewPasteboardWriter(trace: trace)
            let keyPoster = Issue38ReviewKeyEventPoster(trace: trace)
            let output = SystemFinalTextOutput(
                pasteboardWriter: pasteboard,
                keyEventPoster: keyPoster
            )

            let result = output.insertOnce(
                draft,
                destination: Issue38ReviewFixtures.cursorToken(),
                validateBeforeMutation: { XCTFail("control text must be rejected before preflight"); return true },
                validateAfterPosting: { XCTFail("control text must not reach postflight"); return true }
            )

            XCTAssertEqual(result, .deliveryFailed, "draft: \(draft.debugDescription)")
            XCTAssertEqual(pasteboard.writtenTexts, [], "draft: \(draft.debugDescription)")
            XCTAssertEqual(keyPoster.processIdentifiers, [], "draft: \(draft.debugDescription)")
        }
    }

    func test_systemReviewDelivery_rejectsIdentityReuseAndWrongAppWithoutOutput() async throws {
        let runtime = Issue38ReviewApplicationRuntime()
        let activator = Issue38ReviewApplicationActivator()
        let accessibility = Issue38ReviewDestinationAccess()
        let output = Issue38ReviewOutput()
        let delivery = SystemReviewDestinationDelivery(
            applicationRuntime: runtime,
            applicationActivator: activator,
            accessibility: accessibility,
            finalTextOutput: output
        )
        let destination = try delivery.capture(generation: 41)

        runtime.frontmost = Issue38ReviewFixtures.applicationIdentity(pid: 43)
        let wrongApp = await delivery.deliver("PRIVATE_WRONG_APP", to: destination)
        XCTAssertEqual(wrongApp, .identityChanged)
        XCTAssertEqual(output.mutationCount, 0)

        runtime.frontmost = destination.application
        runtime.running = Issue38ReviewFixtures.applicationIdentity(
            pid: destination.application.processIdentifier,
            launchDate: Date(timeIntervalSince1970: 100)
        )
        let reusedPID = await delivery.deliver("PRIVATE_PID_REUSE", to: destination)
        XCTAssertEqual(reusedPID, .identityChanged)
        XCTAssertEqual(output.mutationCount, 0)
    }

    func test_systemReviewDelivery_activationTimeoutIsBoundedAndDoesNotRetarget() async throws {
        let runtime = Issue38ReviewApplicationRuntime()
        let activator = Issue38ReviewApplicationActivator(result: .timedOut)
        let accessibility = Issue38ReviewDestinationAccess()
        let output = Issue38ReviewOutput()
        let delivery = SystemReviewDestinationDelivery(
            applicationRuntime: runtime,
            applicationActivator: activator,
            accessibility: accessibility,
            finalTextOutput: output
        )
        let destination = try delivery.capture(generation: 42)

        let result = await delivery.deliver("PRIVATE_TIMEOUT", to: destination)

        XCTAssertEqual(result, .activationFailed)
        XCTAssertEqual(activator.requestedTimeouts, [2_000_000_000])
        XCTAssertEqual(activator.activationRequests, [destination.application])
        XCTAssertEqual(output.mutationCount, 0)
    }

    func test_systemReviewDelivery_restoresSelectionBeforePasteAndPostflightFailureIsUncertain() async throws {
        let runtime = Issue38ReviewApplicationRuntime()
        let activator = Issue38ReviewApplicationActivator()
        let accessibility = Issue38ReviewDestinationAccess()
        accessibility.beforeDeliveryResult = true
        accessibility.afterDeliveryResult = false
        let output = Issue38ReviewOutput()
        let delivery = SystemReviewDestinationDelivery(
            applicationRuntime: runtime,
            applicationActivator: activator,
            accessibility: accessibility,
            finalTextOutput: output
        )
        let destination = try delivery.capture(generation: 43)

        let result = await delivery.deliver("PRIVATE_UNCERTAIN", to: destination)

        XCTAssertEqual(result, .deliveryUncertain)
        XCTAssertEqual(accessibility.trace, ["restore-before", "postflight"])
        XCTAssertEqual(output.trace, ["preflight", "mutation", "postflight"])
        XCTAssertEqual(output.mutationCount, 1)
        XCTAssertEqual(output.insertedTexts, ["PRIVATE_UNCERTAIN"])
    }
}

@MainActor
private enum Issue38ReviewFixtures {
    static func applicationIdentity(
        pid: pid_t,
        launchDate: Date = Date(timeIntervalSince1970: 1)
    ) -> ReviewApplicationIdentity {
        ReviewApplicationIdentity(
            processIdentifier: pid,
            bundleIdentifier: "com.example.target",
            executableURL: URL(fileURLWithPath: "/Applications/Target.app"),
            launchDate: launchDate
        )
    }

    static func cursorToken(generation: UInt64 = 1) -> CursorDestinationToken {
        CursorDestinationToken(
            generation: generation,
            processIdentifier: 42,
            element: AXUIElementCreateApplication(42),
            originalSelection: CursorTextRange(location: 7, length: 3)
        )
    }
}

@MainActor
private final class Issue38ReviewTrace {
    var events: [String] = []
}

@MainActor
private final class Issue38ReviewPasteboardWriter: FinalTextPasteboardWriting {
    let trace: Issue38ReviewTrace
    private(set) var writtenTexts: [String] = []

    init(trace: Issue38ReviewTrace) {
        self.trace = trace
    }

    func replaceContents(with text: String) -> Bool {
        trace.events.append("pasteboard")
        writtenTexts.append(text)
        return true
    }
}

@MainActor
private final class Issue38ReviewKeyEventPoster: FinalTextKeyEventPosting {
    let trace: Issue38ReviewTrace
    private(set) var processIdentifiers: [pid_t] = []

    init(trace: Issue38ReviewTrace) {
        self.trace = trace
    }

    func postCommandV(to processIdentifier: pid_t) -> Bool {
        trace.events.append("post-command-v")
        processIdentifiers.append(processIdentifier)
        return true
    }
}

@MainActor
private final class Issue38ReviewAccessibilityRuntime: AccessibilityRuntime {
    let element = AXUIElementCreateApplication(42)
    var isProcessTrusted = true
    var isSecureEventInputEnabled = false
    var currentProcessIdentifier: pid_t = 42
    var role: String? = kAXTextAreaRole as String
    var subrole: String? = "AXStandard"
    var selectedRange = CursorTextRange(location: 7, length: 3)
    var settableAttributes: [String: Bool] = [
        kAXSelectedTextRangeAttribute as String: true,
        kAXFocusedAttribute as String: true,
        kAXSelectedTextAttribute as String: false
    ]
    private(set) var attributeQueries: [String] = []
    private(set) var trace: [String] = []
    private(set) var selectedTextWriteCallCount = 0
    private(set) var focusWriteCallCount = 0
    private(set) var selectionWriteCallCount = 0

    func frontmostProcessIdentifier() -> pid_t? { currentProcessIdentifier }
    func focusedElement() throws -> AXUIElement {
        trace.append("focused-read")
        return element
    }
    func processIdentifier(for element: AXUIElement) throws -> pid_t { 42 }
    func role(for element: AXUIElement) throws -> String? { role }
    func subrole(for element: AXUIElement) throws -> String? { subrole }
    func selectedTextRange(for element: AXUIElement) throws -> CursorTextRange {
        trace.append("selection-read")
        return selectedRange
    }
    func isAttributeSettable(_ attribute: String, on element: AXUIElement) throws -> Bool {
        attributeQueries.append(attribute)
        return settableAttributes[attribute] ?? false
    }
    func supportsStringForRange(on element: AXUIElement) throws -> Bool { true }
    func string(for range: CursorTextRange, in element: AXUIElement) throws -> String { "" }
    func setSelectedTextRange(_ range: CursorTextRange, on element: AXUIElement) throws {
        trace.append("selection-write")
        selectionWriteCallCount += 1
        selectedRange = range
    }
    func setSelectedText(_ text: String, on element: AXUIElement) throws {
        selectedTextWriteCallCount += 1
    }
    func setFocused(_ focused: Bool, on element: AXUIElement) throws {
        trace.append("focused-write")
        focusWriteCallCount += 1
    }
    func readSecurityState(for element: AXUIElement) -> DestinationSecurityState {
        trace.append("security-read")
        return .safe
    }

    func resetTrace() {
        trace.removeAll()
    }
}

@MainActor
private final class Issue38ReviewApplicationRuntime: ReviewApplicationRuntime {
    let captured = Issue38ReviewFixtures.applicationIdentity(pid: 42)
    var running: ReviewApplicationIdentity
    var frontmost: ReviewApplicationIdentity

    init() {
        running = captured
        frontmost = captured
    }

    func identity(for processIdentifier: pid_t) -> ReviewApplicationIdentity? {
        processIdentifier == captured.processIdentifier ? running : nil
    }

    func frontmostIdentity() -> ReviewApplicationIdentity? { frontmost }
}

@MainActor
private final class Issue38ReviewApplicationActivator: ReviewApplicationActivating {
    var result: ReviewActivationResult = .activated
    private(set) var requestedTimeouts: [UInt64] = []
    private(set) var activationRequests: [ReviewApplicationIdentity] = []

    init(result: ReviewActivationResult = .activated) {
        self.result = result
    }

    func activateAndWait(
        for identity: ReviewApplicationIdentity,
        timeoutNanoseconds: UInt64
    ) async -> ReviewActivationResult {
        activationRequests.append(identity)
        requestedTimeouts.append(timeoutNanoseconds)
        return result
    }
}

@MainActor
private final class Issue38ReviewDestinationAccess: ReviewDestinationAccessing {
    var beforeDeliveryResult = true
    var afterDeliveryResult = true
    private(set) var trace: [String] = []

    func captureReviewCursorDestination(generation: UInt64) throws -> CursorDestinationToken {
        Issue38ReviewFixtures.cursorToken(generation: generation)
    }

    func restoreAndValidateBeforeDelivery(_ token: CursorDestinationToken) throws -> Bool {
        trace.append("restore-before")
        return beforeDeliveryResult
    }

    func validateAfterDelivery(_ token: CursorDestinationToken) throws -> Bool {
        trace.append("postflight")
        return afterDeliveryResult
    }
}

@MainActor
private final class Issue38ReviewOutput: FinalTextOutput {
    private(set) var mutationCount = 0
    private(set) var insertedTexts: [String] = []
    private(set) var trace: [String] = []

    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateDestination: () throws -> Bool
    ) -> FinalTextInsertionResult { .inserted }

    func insertOnce(
        _ text: String,
        destination: CursorDestinationToken,
        validateBeforeMutation: () throws -> Bool,
        validateAfterPosting: () throws -> Bool
    ) -> FinalTextInsertionResult {
        do {
            trace.append("preflight")
            guard try validateBeforeMutation() else { return .destinationInvalid }
            mutationCount += 1
            insertedTexts.append(text)
            trace.append("mutation")
            let postflightPassed = try validateAfterPosting()
            trace.append("postflight")
            return postflightPassed ? .inserted : .deliveryUncertain
        } catch {
            return .deliveryUncertain
        }
    }

    func insertAtCurrentFocusOnce(_ text: String) -> FinalTextInsertionResult { .inserted }
    func copyForManualRecovery(_ text: String) {}
}
