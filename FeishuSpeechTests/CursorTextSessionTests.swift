import Foundation
import ApplicationServices
import XCTest
import os.log
@testable import FeishuSpeech

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "CursorTextSessionTests")

@MainActor
final class CursorTextSessionTests: XCTestCase {
    func test_beginSelectsLiveFinalOnlyOrSecureRejectionWithoutWriting() throws {
        let live = makeContext(capability: .live)
        let finalOnly = makeContext(capability: .finalOnly)
        let secure = makeContext(capability: .secureRejected)

        XCTAssertLive(try live.session.begin())
        XCTAssertFinalOnly(try finalOnly.session.begin())
        XCTAssertSecureRejected(try secure.session.begin())
        XCTAssertEqual(live.client.setSelectedTextCalls.count, 0)
        XCTAssertEqual(finalOnly.client.setSelectedTextCalls.count, 0)
        XCTAssertEqual(secure.client.setSelectedTextCalls.count, 0)
    }

    func test_firstDuplicateRevisedAndShorterPartials_replaceOneCompleteOwnedRange() throws {
        let context = makeContext(capability: .live, originalSelection: CursorTextRange(location: 4, length: 3))
        context.client.returnedWriteLengths = [8, 5, 2]
        XCTAssertLive(try context.session.begin())

        try context.session.handle(.partial("complete"), generation: 7)
        XCTAssertEqual(
            context.session.state,
            .provisional(range: CursorTextRange(location: 4, length: 8), text: "complete")
        )

        try context.session.handle(.partial("complete"), generation: 7)
        XCTAssertEqual(context.client.setSelectedTextCalls.count, 1, "duplicate opaque partial is a no-op")

        try context.session.handle(.partial("revise"), generation: 7)
        try context.session.handle(.partial("短"), generation: 7)

        XCTAssertEqual(Array(context.client.selectedRangeWrites.suffix(2)), [
            CursorTextRange(location: 4, length: 8),
            CursorTextRange(location: 4, length: 5)
        ])
        XCTAssertEqual(context.client.setSelectedTextCalls, ["complete", "revise", "短"])
        XCTAssertEqual(
            context.session.state,
            .provisional(range: CursorTextRange(location: 4, length: 2), text: "短")
        )
    }

    func test_unicodeOwnership_usesAccessibilityReturnedRangesNotSwiftCounts() throws {
        let context = makeContext(capability: .live, originalSelection: CursorTextRange(location: 10, length: 0))
        context.client.returnedWriteLengths = [17, 9, 23]
        XCTAssertLive(try context.session.begin())

        try context.session.handle(.partial("👨‍👩‍👧‍👦e\u{301}"), generation: 7)
        XCTAssertEqual(
            context.session.state,
            .provisional(range: CursorTextRange(location: 10, length: 17), text: "👨‍👩‍👧‍👦e\u{301}")
        )

        try context.session.handle(.partial("中文\nسَلَام"), generation: 7)
        XCTAssertEqual(
            context.session.state,
            .provisional(range: CursorTextRange(location: 10, length: 9), text: "中文\nسَلَام")
        )

        try context.session.handle(.final("最終👩🏽‍💻\nשלום"), generation: 7)
        XCTAssertEqual(context.session.state, .committed)
        XCTAssertEqual(context.client.selectedRange.location, 33, "final caret must use the AX-returned end")
        XCTAssertEqual(context.client.selectedRange.length, 0)
    }

    func test_focusCaretOwnedTextAndGenerationMismatch_neverRetargetOrWrite() throws {
        for mismatch in CursorMismatch.allCases {
            let context = makeContext(capability: .live)
            context.client.returnedWriteLengths = [5]
            XCTAssertLive(try context.session.begin())
            try context.session.handle(.partial("first"), generation: 7)
            let writesBeforeMismatch = context.client.setSelectedTextCalls.count

            switch mismatch {
            case .process:
                context.client.currentProcessIdentifier = 99
            case .element:
                context.client.currentFocusedElement = AXUIElementCreateApplication(99)
            case .elementFailure:
                context.client.focusedElementError = .cannotComplete
            case .caret:
                context.client.selectedRange = CursorTextRange(location: 99, length: 0)
            case .ownedText:
                context.client.rangeText = "user edit"
            case .generation:
                break
            }

            try context.session.handle(
                .partial("late revision"),
                generation: mismatch == .generation ? 8 : 7
            )

            XCTAssertEqual(
                context.client.setSelectedTextCalls.count,
                writesBeforeMismatch,
                "\(mismatch) must prevent another target mutation"
            )
            if mismatch == .generation {
                XCTAssertEqual(
                    context.session.state,
                    .provisional(range: CursorTextRange(location: 2, length: 5), text: "first"),
                    "a stale generation callback is discarded rather than invalidating the current session"
                )
            } else {
                XCTAssertEqual(context.session.state, .invalid)
            }
        }
    }

    func test_originalSelectionMismatchBeforeFirstPartialCausesZeroMutation() throws {
        let context = makeContext(
            capability: .live,
            originalSelection: CursorTextRange(location: 3, length: 4)
        )
        XCTAssertLive(try context.session.begin())
        context.client.selectedRange = CursorTextRange(location: 7, length: 0)

        try context.session.handle(.partial("must not write"), generation: 7)

        XCTAssertEqual(context.session.state, .invalid)
        XCTAssertEqual(context.client.setSelectedTextCalls.count, 0)
    }

    func test_accessibilityCannotCompleteBeforeFirstWriteCausesZeroMutation() throws {
        let context = makeContext(capability: .live)
        XCTAssertLive(try context.session.begin())
        context.client.failNextSelectedRangeRead = true

        _ = try? context.session.handle(.partial("must not write"), generation: 7)

        XCTAssertEqual(context.session.state, .invalid)
        XCTAssertEqual(context.client.setSelectedTextCalls.count, 0)
    }

    func test_liveWriteFailsClosedWhenDestinationBecomesSecureOrSecurityQueryFails() throws {
        enum SecurityChange {
            case secure
            case unverifiable
            case queryFailure
        }

        for change in [SecurityChange.secure, .unverifiable, .queryFailure] {
            let context = makeContext(capability: .live)
            XCTAssertLive(try context.session.begin())

            switch change {
            case .secure:
                context.client.currentSecurityState = .secure
            case .unverifiable:
                context.client.currentSecurityState = .unverifiable
            case .queryFailure:
                context.client.securityStateError = .cannotComplete
            }

            _ = try? context.session.handle(.partial("must not write"), generation: 7)

            XCTAssertEqual(
                context.session.state,
                .invalid,
                "a dynamic security change must invalidate the captured destination"
            )
            XCTAssertEqual(context.client.setSelectedTextCalls, [])
            XCTAssertEqual(context.client.selectedRangeWrites, [])
        }
    }

    func test_emptyFinalAndStreamFailure_preserveLastVerifiedPartialAndReleaseOwnership() throws {
        for terminalEvent in [
            StreamingRecognitionEvent.final(""),
            StreamingRecognitionEvent.failed(.network)
        ] {
            let context = makeContext(capability: .live)
            context.client.returnedWriteLengths = [7]
            XCTAssertLive(try context.session.begin())
            try context.session.handle(.partial("visible"), generation: 7)

            try context.session.handle(terminalEvent, generation: 7)

            XCTAssertEqual(context.session.state, .preserved)
            XCTAssertEqual(context.client.setSelectedTextCalls, ["visible"])
            XCTAssertEqual(context.client.rangeText, "visible")
        }
    }

    func test_failureBeforeFirstWriteCausesZeroTargetMutation() throws {
        let context = makeContext(capability: .live)
        XCTAssertLive(try context.session.begin())

        try context.session.handle(.failed(.timeout), generation: 7)

        XCTAssertEqual(context.session.state, .preserved)
        XCTAssertEqual(context.client.setSelectedTextCalls.count, 0)
        XCTAssertEqual(context.client.selectedRangeWrites.count, 0)
    }

    func test_nonEmptyFinalReplacesVerifiedRangeCommitsAndLateEventsWriteNothing() throws {
        let context = makeContext(capability: .live)
        context.client.returnedWriteLengths = [4, 6]
        XCTAssertLive(try context.session.begin())
        try context.session.handle(.partial("part"), generation: 7)

        try context.session.handle(.final("final!"), generation: 7)
        try context.session.handle(.partial("late"), generation: 7)
        try context.session.handle(.final("later final"), generation: 7)

        XCTAssertEqual(context.session.state, .committed)
        XCTAssertEqual(context.client.setSelectedTextCalls, ["part", "final!"])
        XCTAssertEqual(context.client.selectedRange, CursorTextRange(location: 8, length: 0))
    }

    func test_postMutationAccessibilityFailureNeverRollsBackUncertainVisibleText() throws {
        let context = makeContext(capability: .live)
        context.client.returnedWriteLengths = [5]
        context.client.failSelectedRangeReadAfterNextWrite = true
        XCTAssertLive(try context.session.begin())

        _ = try? context.session.handle(.partial("maybe"), generation: 7)

        XCTAssertEqual(context.session.state, .invalid)
        XCTAssertEqual(context.client.setSelectedTextCalls, ["maybe"])
    }

    func test_invalidateBeforeAsyncCleanupMakesEveryLateEventANoOp() throws {
        let context = makeContext(capability: .live)
        XCTAssertLive(try context.session.begin())

        context.session.invalidate()
        try context.session.handle(.partial("late"), generation: 7)
        try context.session.handle(.final("late final"), generation: 7)

        XCTAssertEqual(context.session.state, .invalid)
        XCTAssertEqual(context.client.setSelectedTextCalls.count, 0)
    }

    func test_finalOnlyDecisionHonorsSecureAutoInsertEmptyFinalAndDestinationStaleness() {
        XCTAssertEqual(
            FinalOnlyFallbackDecision.evaluate(
                autoInsert: true,
                secureTarget: false,
                finalTextIsEmpty: false,
                destinationStillCurrent: true
            ),
            .insertOnce
        )
        XCTAssertEqual(
            FinalOnlyFallbackDecision.evaluate(
                autoInsert: true,
                secureTarget: false,
                finalTextIsEmpty: false,
                destinationStillCurrent: false
            ),
            .copyForManualRecovery
        )
        XCTAssertEqual(
            FinalOnlyFallbackDecision.evaluate(
                autoInsert: false,
                secureTarget: false,
                finalTextIsEmpty: false,
                destinationStillCurrent: true
            ),
            .noInsertion
        )
        XCTAssertEqual(
            FinalOnlyFallbackDecision.evaluate(
                autoInsert: true,
                secureTarget: false,
                finalTextIsEmpty: true,
                destinationStillCurrent: true
            ),
            .noInsertion
        )
        XCTAssertEqual(
            FinalOnlyFallbackDecision.evaluate(
                autoInsert: true,
                secureTarget: true,
                finalTextIsEmpty: false,
                destinationStillCurrent: true
            ),
            .rejectSecureTarget
        )
    }

    func test_macAccessibilityClientFailsClosedForMissingSubroleAndNoneditableRole() throws {
        let missingSubrole = FakeAccessibilityRuntime()
        missingSubrole.role = kAXTextFieldRole as String
        missingSubrole.subrole = nil

        let noneditable = FakeAccessibilityRuntime()
        noneditable.role = kAXButtonRole as String
        noneditable.subrole = "AXStandard"

        for runtime in [missingSubrole, noneditable] {
            let result = try MacAccessibilityClient(runtime: runtime).captureDestination(generation: 7)
            guard case .rejected = result else {
                return XCTFail("unverifiable or noneditable AX targets must be rejected, got \(result)")
            }
            XCTAssertEqual(runtime.writeCallCount, 0)
        }
    }

    func test_macAccessibilityClientFailsClosedWhenRoleOrSubroleQueryThrows() {
        for failedQuery in [FakeAccessibilityRuntime.FailedQuery.role, .subrole] {
            let runtime = FakeAccessibilityRuntime()
            runtime.failedQuery = failedQuery
            let client = MacAccessibilityClient(runtime: runtime)

            XCTAssertThrowsError(try client.captureDestination(generation: 7))
            XCTAssertEqual(runtime.writeCallCount, 0)
        }
    }

    private func makeContext(
        capability: FakeAccessibilityClient.Capability,
        originalSelection: CursorTextRange = CursorTextRange(location: 2, length: 0)
    ) -> CursorTestContext {
        let token = CursorDestinationToken(
            generation: 7,
            processIdentifier: 42,
            element: AXUIElementCreateApplication(42),
            originalSelection: originalSelection
        )
        let client = FakeAccessibilityClient(
            token: token,
            capability: capability,
            selectedRange: originalSelection
        )
        return CursorTestContext(
            session: CursorTextSession(generation: 7, accessibilityClient: client),
            client: client
        )
    }

    private func XCTAssertLive(
        _ result: CursorCapabilityResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .live = result else {
            return XCTFail("expected live capability, got \(result)", file: file, line: line)
        }
    }

    private func XCTAssertFinalOnly(
        _ result: CursorCapabilityResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .finalOnly = result else {
            return XCTFail("expected final-only capability, got \(result)", file: file, line: line)
        }
    }

    private func XCTAssertSecureRejected(
        _ result: CursorCapabilityResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .rejected(.secureTarget) = result else {
            return XCTFail("expected secure-target rejection, got \(result)", file: file, line: line)
        }
    }
}

private struct CursorTestContext {
    let session: CursorTextSession
    let client: FakeAccessibilityClient
}

private enum CursorMismatch: CaseIterable {
    case process
    case element
    case elementFailure
    case caret
    case ownedText
    case generation
}

@MainActor
private final class FakeAccessibilityClient: AccessibilityClient {
    enum Capability {
        case live
        case finalOnly
        case secureRejected
    }

    private let token: CursorDestinationToken
    private let capability: Capability
    var currentProcessIdentifier: pid_t = 42
    var currentFocusedElement: AXUIElement
    var focusedElementError: AccessibilityClientError?
    var selectedRange: CursorTextRange
    var rangeText = ""
    var returnedWriteLengths: [Int] = []
    var failNextSelectedRangeRead = false
    var failSelectedRangeReadAfterNextWrite = false
    var currentSecurityState: DestinationSecurityState = .safe
    var securityStateError: AccessibilityClientError?
    private var shouldFailSelectedRangeRead = false
    private(set) var selectedRangeWrites: [CursorTextRange] = []
    private(set) var setSelectedTextCalls: [String] = []

    init(token: CursorDestinationToken, capability: Capability, selectedRange: CursorTextRange) {
        self.token = token
        self.capability = capability
        self.selectedRange = selectedRange
        currentFocusedElement = token.element
    }

    func captureDestination(generation: UInt64) throws -> CursorCapabilityResult {
        XCTAssertEqual(generation, token.generation)
        switch capability {
        case .live:
            return .live(token)
        case .finalOnly:
            return .finalOnly(token)
        case .secureRejected:
            return .rejected(.secureTarget)
        }
    }

    func frontmostProcessIdentifier() -> pid_t? {
        currentProcessIdentifier
    }

    func focusedElement() throws -> AXUIElement {
        if let focusedElementError {
            throw focusedElementError
        }
        return currentFocusedElement
    }

    func currentSecurityState(for token: CursorDestinationToken) throws -> DestinationSecurityState {
        if let securityStateError {
            throw securityStateError
        }
        return currentSecurityState
    }

    func selectedTextRange(for token: CursorDestinationToken) throws -> CursorTextRange {
        if failNextSelectedRangeRead {
            failNextSelectedRangeRead = false
            throw AccessibilityClientError.cannotComplete
        }
        if shouldFailSelectedRangeRead {
            shouldFailSelectedRangeRead = false
            throw AccessibilityClientError.cannotComplete
        }
        return selectedRange
    }

    func string(for range: CursorTextRange, in token: CursorDestinationToken) throws -> String {
        rangeText
    }

    func setSelectedTextRange(_ range: CursorTextRange, for token: CursorDestinationToken) throws {
        selectedRangeWrites.append(range)
        selectedRange = range
    }

    func setSelectedText(_ text: String, for token: CursorDestinationToken) throws {
        setSelectedTextCalls.append(text)
        let replacementStart = selectedRange.location
        let returnedLength = returnedWriteLengths.isEmpty ? text.utf16.count : returnedWriteLengths.removeFirst()
        rangeText = text
        selectedRange = CursorTextRange(location: replacementStart + returnedLength, length: 0)
        if failSelectedRangeReadAfterNextWrite {
            failSelectedRangeReadAfterNextWrite = false
            shouldFailSelectedRangeRead = true
        }
    }
}

@MainActor
private final class FakeAccessibilityRuntime: AccessibilityRuntime {
    enum FailedQuery {
        case role
        case subrole
    }

    let element = AXUIElementCreateApplication(42)
    var isProcessTrusted = true
    var isSecureEventInputEnabled = false
    var currentProcessIdentifier: pid_t = 42
    var role: String? = kAXTextFieldRole as String
    var subrole: String? = "AXStandard"
    var selectedRange = CursorTextRange(location: 2, length: 0)
    var failedQuery: FailedQuery?
    private(set) var selectedTextRangeQueryCount = 0
    private(set) var writeCallCount = 0

    func frontmostProcessIdentifier() -> pid_t? {
        currentProcessIdentifier
    }

    func focusedElement() throws -> AXUIElement {
        element
    }

    func processIdentifier(for element: AXUIElement) throws -> pid_t {
        currentProcessIdentifier
    }

    func role(for element: AXUIElement) throws -> String? {
        if failedQuery == .role {
            throw AccessibilityClientError.cannotComplete
        }
        return role
    }

    func subrole(for element: AXUIElement) throws -> String? {
        if failedQuery == .subrole {
            throw AccessibilityClientError.cannotComplete
        }
        return subrole
    }

    func selectedTextRange(for element: AXUIElement) throws -> CursorTextRange {
        selectedTextRangeQueryCount += 1
        return selectedRange
    }

    func isAttributeSettable(_ attribute: String, on element: AXUIElement) throws -> Bool {
        true
    }

    func supportsStringForRange(on element: AXUIElement) throws -> Bool {
        true
    }

    func string(for range: CursorTextRange, in element: AXUIElement) throws -> String {
        ""
    }

    func setSelectedTextRange(_ range: CursorTextRange, on element: AXUIElement) throws {
        writeCallCount += 1
    }

    func setSelectedText(_ text: String, on element: AXUIElement) throws {
        writeCallCount += 1
    }
}
