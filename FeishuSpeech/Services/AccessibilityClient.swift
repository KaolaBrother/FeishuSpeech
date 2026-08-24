import AppKit
import ApplicationServices
import Carbon
import Foundation
import os.log

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "AccessibilityClient"
)

/// Raw review-capture state is executor-confined.  This type is intentionally
/// not Sendable and must never be stored in a MainActor descriptor or control
/// record.
final class ReviewSubmissionRawTargetState {
    let descriptor: CapturedReviewTargetDescriptor
    let applicationElement: AXUIElement
    let focusedElement: AXUIElement?
    let originalSelection: CursorTextRange?

    init(
        descriptor: CapturedReviewTargetDescriptor,
        applicationElement: AXUIElement,
        focusedElement: AXUIElement?,
        originalSelection: CursorTextRange? = nil
    ) {
        self.descriptor = descriptor
        self.applicationElement = applicationElement
        self.focusedElement = focusedElement
        self.originalSelection = originalSelection
    }
}

protocol ReviewSubmissionRawAccessibilityRuntime: AnyObject {
    func capture(
        _ request: ReviewTargetCaptureRequestDescriptor
    ) -> Result<ReviewSubmissionRawTargetState, ReviewPreBoundaryFailure>
    func validate(
        _ target: ReviewSubmissionRawTargetState,
        deadline: UInt64
    ) -> ReviewPreBoundaryFailure?

    func validate(
        _ target: ReviewSubmissionRawTargetState,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> ReviewPreBoundaryFailure?
}

/// Value-only identifiers emitted by the concrete System AX runner.  The
/// observer never receives an AX object, value, event, draft, or target
/// descriptor; it is a raw-executor diagnostic seam only.
enum ReviewAXStepID: String, Sendable {
    case messagingTimeout
    case copyAttribute
    case getProcessIdentifier
    case isAttributeSettable
    case setFocused
    case createAXValue
    case setSelectedRange
    case getSelectedRange
    case readAXValue
    case role
    case subrole
    case secureInput
    case accessibilityTrust
    case runningIdentity
    case frontmost
}

enum ReviewAXResultCategory: String, Sendable {
    case success
    case noValue
    case attributeUnsupported
    case failure
    case malformed
    case secureInputEnabled
    case accessibilityUntrusted
    case missingIdentity
    case wrongIdentity
    case wrongFrontmost
    case cancelled
    case deadline
}

extension ReviewAXStepID {
    static var setMessagingTimeout: Self { .messagingTimeout }
    static var copyAttributeValue: Self { .copyAttribute }
    static var getPID: Self { .getProcessIdentifier }
}

typealias ReviewAXStep = ReviewAXStepID
typealias ReviewAXStepResult = ReviewAXResultCategory

typealias ReviewAXStepObserver = @Sendable (
    _ step: ReviewAXStepID,
    _ result: ReviewAXResultCategory
) -> Void

/// Injectable security reads keep the production composite directly backed by
/// AppKit/ApplicationServices while allowing deterministic raw-runtime tests.
/// They contain values and closures only; no AX object crosses this seam.
struct ReviewAXSecuritySamples: @unchecked Sendable {
    let secureInputEnabled: @Sendable () -> Bool
    let accessibilityTrusted: @Sendable () -> Bool
    let runningIdentity: @Sendable (pid_t) -> ReviewApplicationIdentity?
    let frontmostProcessIdentifier: @Sendable () -> pid_t?

    init(
        secureInputEnabled: @escaping @Sendable () -> Bool = { IsSecureEventInputEnabled() },
        accessibilityTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        runningIdentity: @escaping @Sendable (pid_t) -> ReviewApplicationIdentity? = { pid in
            guard let application = NSRunningApplication(processIdentifier: pid),
                  let bundleIdentifier = application.bundleIdentifier,
                  let executableURL = application.executableURL,
                  let launchDate = application.launchDate else {
                return nil
            }
            return ReviewApplicationIdentity(
                processIdentifier: application.processIdentifier,
                bundleIdentifier: bundleIdentifier,
                executableURL: executableURL,
                launchDate: launchDate
            )
        },
        frontmostProcessIdentifier: @escaping @Sendable () -> pid_t? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
    ) {
        self.secureInputEnabled = secureInputEnabled
        self.accessibilityTrusted = accessibilityTrusted
        self.runningIdentity = runningIdentity
        self.frontmostProcessIdentifier = frontmostProcessIdentifier
    }
}

extension ReviewSubmissionRawAccessibilityRuntime {
    func validate(
        _ target: ReviewSubmissionRawTargetState,
        deadline: UInt64,
        cancellationProbe _: @escaping @Sendable () -> Bool
    ) -> ReviewPreBoundaryFailure? {
        validate(target, deadline: deadline)
    }
}

@MainActor
protocol AccessibilityClient: AnyObject {
    func captureDestination(generation: UInt64) throws -> CursorCapabilityResult
    func frontmostProcessIdentifier() -> pid_t?
    func focusedElement() throws -> AXUIElement
    func currentSecurityState(for token: CursorDestinationToken) throws -> DestinationSecurityState
    func selectedTextRange(for token: CursorDestinationToken) throws -> CursorTextRange
    func string(for range: CursorTextRange, in token: CursorDestinationToken) throws -> String
    func setSelectedTextRange(_ range: CursorTextRange, for token: CursorDestinationToken) throws
    func setSelectedText(_ text: String, for token: CursorDestinationToken) throws
}

@MainActor
protocol AccessibilityRuntime: AnyObject {
    var isProcessTrusted: Bool { get }
    var isSecureEventInputEnabled: Bool { get }

    func frontmostProcessIdentifier() -> pid_t?
    func focusedElement() throws -> AXUIElement
    func processIdentifier(for element: AXUIElement) throws -> pid_t
    func role(for element: AXUIElement) throws -> String?
    func subrole(for element: AXUIElement) throws -> String?
    func selectedTextRange(for element: AXUIElement) throws -> CursorTextRange
    func isAttributeSettable(_ attribute: String, on element: AXUIElement) throws -> Bool
    func supportsStringForRange(on element: AXUIElement) throws -> Bool
    func string(for range: CursorTextRange, in element: AXUIElement) throws -> String
    func setSelectedTextRange(_ range: CursorTextRange, on element: AXUIElement) throws
    func setSelectedText(_ text: String, on element: AXUIElement) throws
    func setFocused(_ focused: Bool, on element: AXUIElement) throws
    func readSecurityState(for element: AXUIElement) -> DestinationSecurityState
}

extension AccessibilityRuntime {
    /// Existing compatibility test doubles do not need review-only focus support.
    /// Review capture/delivery treats the default as a hard failure.
    func setFocused(_: Bool, on _: AXUIElement) throws {
        throw AccessibilityClientError.operationFailed
    }

    func readSecurityState(for element: AXUIElement) -> DestinationSecurityState {
        do {
            guard let role = try role(for: element),
                  [kAXTextFieldRole as String, kAXTextAreaRole as String].contains(role),
                  let subrole = try subrole(for: element) else {
                return .unverifiable
            }
            if subrole == (kAXSecureTextFieldSubrole as String) {
                return .secure
            }
            return ["AXStandard", kAXSearchFieldSubrole as String].contains(subrole)
                ? .safe
                : .unverifiable
        } catch {
            return .unverifiable
        }
    }
}

@MainActor
protocol ReviewDestinationAccessing: AnyObject {
    func captureReviewCursorDestination(generation: UInt64) -> ReviewCursorCaptureResult
    func restoreAndValidateBeforeDelivery(_ token: CursorDestinationToken) throws -> Bool
    func validateAfterDelivery(_ token: CursorDestinationToken) throws -> Bool
}

@MainActor
protocol AccessibilityTrustProviding: AnyObject {
    var isAccessibilityTrusted: Bool { get }
}

@MainActor
final class MacAccessibilityClient: AccessibilityClient, ReviewDestinationAccessing,
    AccessibilityTrustProviding {
    private let runtime: AccessibilityRuntime

    init(runtime: AccessibilityRuntime) {
        self.runtime = runtime
    }

    convenience init() {
        self.init(runtime: SystemAccessibilityRuntime())
    }

    var isAccessibilityTrusted: Bool {
        runtime.isProcessTrusted
    }

    func captureDestination(generation: UInt64) throws -> CursorCapabilityResult {
        guard runtime.isProcessTrusted else {
            return .rejected(.accessibilityUnavailable)
        }
        guard !runtime.isSecureEventInputEnabled else {
            return .rejected(.secureTarget)
        }

        let element = try focusedElement()
        let processIdentifier = try runtime.processIdentifier(for: element)
        guard processIdentifier != 0,
              processIdentifier == frontmostProcessIdentifier() else {
            throw AccessibilityClientError.cannotComplete
        }

        let securityState = try securityState(for: element)
        if securityState == .secure {
            return .rejected(.secureTarget)
        }
        guard securityState == .safe,
              try runtime.isAttributeSettable(kAXSelectedTextAttribute as String, on: element) else {
            return .rejected(.accessibilityUnavailable)
        }

        let placeholder = CursorDestinationToken(
            generation: generation,
            processIdentifier: processIdentifier,
            element: element,
            originalSelection: CursorTextRange(location: 0, length: 0)
        )
        let selection: CursorTextRange
        do {
            selection = try selectedTextRange(for: placeholder)
        } catch AccessibilityClientError.operationFailed,
                AccessibilityClientError.noFocusedElement,
                AccessibilityClientError.invalidValue {
            let token = CursorDestinationToken(
                generation: generation,
                processIdentifier: processIdentifier,
                element: element,
                originalSelection: CursorTextRange(location: 0, length: 0)
            )
            return .finalOnly(token)
        }
        let token = CursorDestinationToken(
            generation: generation,
            processIdentifier: processIdentifier,
            element: element,
            originalSelection: selection
        )

        let supportsLiveReplacement = try runtime.isAttributeSettable(
            kAXSelectedTextRangeAttribute as String,
            on: element
        ) && runtime.supportsStringForRange(on: element)

        return supportsLiveReplacement ? .live(token) : .finalOnly(token)
    }

    func frontmostProcessIdentifier() -> pid_t? {
        runtime.frontmostProcessIdentifier()
    }

    func focusedElement() throws -> AXUIElement {
        try runtime.focusedElement()
    }

    func currentSecurityState(for token: CursorDestinationToken) throws -> DestinationSecurityState {
        guard runtime.isProcessTrusted else {
            return .unverifiable
        }
        guard !runtime.isSecureEventInputEnabled else {
            return .secure
        }
        guard try runtime.processIdentifier(for: token.element) == token.processIdentifier else {
            return .unverifiable
        }
        return try securityState(for: token.element)
    }

    func selectedTextRange(for token: CursorDestinationToken) throws -> CursorTextRange {
        try runtime.selectedTextRange(for: token.element)
    }

    func string(for range: CursorTextRange, in token: CursorDestinationToken) throws -> String {
        try runtime.string(for: range, in: token.element)
    }

    func setSelectedTextRange(_ range: CursorTextRange, for token: CursorDestinationToken) throws {
        try runtime.setSelectedTextRange(range, on: token.element)
    }

    func setSelectedText(_ text: String, for token: CursorDestinationToken) throws {
        try runtime.setSelectedText(text, on: token.element)
    }

    func captureReviewCursorDestination(generation: UInt64) -> ReviewCursorCaptureResult {
        if let admissionResult = reviewCaptureAdmissionResult() {
            return admissionResult
        }

        let element: AXUIElement
        do {
            element = try runtime.focusedElement()
        } catch {
            return reviewCaptureResultForCapabilityMiss()
        }

        let processIdentifier: pid_t
        do {
            processIdentifier = try runtime.processIdentifier(for: element)
        } catch {
            return reviewCaptureResultForCapabilityMiss()
        }
        guard processIdentifier > 0,
              processIdentifier == runtime.frontmostProcessIdentifier() else {
            return reviewCaptureResultForCapabilityMiss()
        }

        if let securityResult = reviewSecurityValidation(for: element) {
            return securityResult
        }

        guard let selection = reviewSelection(for: element),
              selection.location >= 0,
              selection.length >= 0,
              selection.endLocation != nil else {
            return reviewCaptureResultForCapabilityMiss()
        }

        guard reviewCaptureAttributesAreSettable(for: element) else {
            return reviewCaptureResultForCapabilityMiss()
        }

        if let admissionResult = reviewCaptureAdmissionResult() {
            return admissionResult
        }

        return .exact(CursorDestinationToken(
            generation: generation,
            processIdentifier: processIdentifier,
            element: element,
            originalSelection: selection
        ))
    }

    func restoreAndValidateBeforeDelivery(_ token: CursorDestinationToken) throws -> Bool {
        guard runtime.isProcessTrusted,
              !runtime.isSecureEventInputEnabled,
              token.processIdentifier > 0,
              try runtime.processIdentifier(for: token.element) == token.processIdentifier,
              try securityState(for: token.element) == .safe else {
            return false
        }

        guard try runtime.isAttributeSettable(kAXFocusedAttribute as String, on: token.element),
              try runtime.isAttributeSettable(
                  kAXSelectedTextRangeAttribute as String,
                  on: token.element
              ) else {
            return false
        }

        try runtime.setFocused(true, on: token.element)
        let focusedElement = try runtime.focusedElement()
        guard CFEqual(focusedElement, token.element) else {
            return false
        }

        try runtime.setSelectedTextRange(token.originalSelection, on: token.element)
        guard try runtime.selectedTextRange(for: token.element) == token.originalSelection else {
            return false
        }
        guard !runtime.isSecureEventInputEnabled,
              runtime.readSecurityState(for: token.element) == .safe else {
            return false
        }
        return true
    }

    func validateAfterDelivery(_ token: CursorDestinationToken) throws -> Bool {
        guard runtime.isProcessTrusted,
              !runtime.isSecureEventInputEnabled,
              token.processIdentifier > 0,
              try runtime.processIdentifier(for: token.element) == token.processIdentifier,
              runtime.readSecurityState(for: token.element) == .safe else {
            return false
        }
        let focusedElement = try runtime.focusedElement()
        return CFEqual(focusedElement, token.element)
    }

    private func securityState(for element: AXUIElement) throws -> DestinationSecurityState {
        guard let role = try runtime.role(for: element), supportedEditableRoles.contains(role),
              let subrole = try runtime.subrole(for: element) else {
            return .unverifiable
        }
        if subrole == (kAXSecureTextFieldSubrole as String) {
            return .secure
        }
        return supportedNonSecureSubroles.contains(subrole) ? .safe : .unverifiable
    }

    private func reviewCaptureAdmissionResult() -> ReviewCursorCaptureResult? {
        guard runtime.isProcessTrusted else {
            return .rejected(.accessibilityUnavailable)
        }
        guard !runtime.isSecureEventInputEnabled else {
            return .rejected(.secureInput)
        }
        return nil
    }

    private func reviewSecurityValidation(
        for element: AXUIElement
    ) -> ReviewCursorCaptureResult? {
        let state: DestinationSecurityState
        do {
            state = try reviewSecurityState(for: element)
        } catch {
            return reviewCaptureResultForCapabilityMiss()
        }
        switch state {
        case .secure:
            return .rejected(.secureInput)
        case .unverifiable:
            return reviewCaptureResultForCapabilityMiss()
        case .safe:
            return nil
        }
    }

    private func reviewSecurityState(
        for element: AXUIElement
    ) throws -> DestinationSecurityState {
        guard let subrole = try runtime.subrole(for: element) else {
            return .unverifiable
        }
        if subrole == (kAXSecureTextFieldSubrole as String) {
            return .secure
        }
        return try securityState(for: element)
    }

    private func reviewSelection(for element: AXUIElement) -> CursorTextRange? {
        try? runtime.selectedTextRange(for: element)
    }

    private func reviewCaptureAttributesAreSettable(for element: AXUIElement) -> Bool {
        do {
            guard try runtime.isAttributeSettable(
                kAXSelectedTextRangeAttribute as String,
                on: element
            ) else {
                return false
            }
            return try runtime.isAttributeSettable(
                kAXFocusedAttribute as String,
                on: element
            )
        } catch {
            return false
        }
    }

    private func reviewCaptureResultForCapabilityMiss() -> ReviewCursorCaptureResult {
        guard runtime.isProcessTrusted else {
            return .rejected(.accessibilityUnavailable)
        }
        guard !runtime.isSecureEventInputEnabled else {
            return .rejected(.secureInput)
        }
        return .nonSecureCursorUnavailable
    }

    private var supportedEditableRoles: Set<String> {
        [kAXTextFieldRole as String, kAXTextAreaRole as String]
    }

    private var supportedNonSecureSubroles: Set<String> {
        ["AXStandard", kAXSearchFieldSubrole as String]
    }
}

@MainActor
final class SystemAccessibilityTrustProvider: AccessibilityTrustProviding {
    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }
}

@MainActor
private final class SystemAccessibilityRuntime: AccessibilityRuntime {
    var isProcessTrusted: Bool { AXIsProcessTrusted() }
    var isSecureEventInputEnabled: Bool { IsSecureEventInputEnabled() }

    func frontmostProcessIdentifier() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func focusedElement() throws -> AXUIElement {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let value else { throw map(result) }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    func processIdentifier(for element: AXUIElement) throws -> pid_t {
        var processIdentifier: pid_t = 0
        let result = AXUIElementGetPid(element, &processIdentifier)
        guard result == .success else { throw map(result) }
        return processIdentifier
    }

    func role(for element: AXUIElement) throws -> String? {
        try stringAttribute(kAXRoleAttribute as CFString, on: element)
    }

    func subrole(for element: AXUIElement) throws -> String? {
        try stringAttribute(kAXSubroleAttribute as CFString, on: element)
    }

    func selectedTextRange(for element: AXUIElement) throws -> CursorTextRange {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            throw map(result)
        }
        var range = CFRange()
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cfRange, &range),
              range.location >= 0, range.length >= 0 else {
            throw AccessibilityClientError.invalidValue
        }
        return CursorTextRange(location: range.location, length: range.length)
    }

    func isAttributeSettable(_ attribute: String, on element: AXUIElement) throws -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        if result == .attributeUnsupported { return false }
        guard result == .success else { throw map(result) }
        return settable.boolValue
    }

    func supportsStringForRange(on element: AXUIElement) throws -> Bool {
        var names: CFArray?
        let result = AXUIElementCopyParameterizedAttributeNames(element, &names)
        if result == .attributeUnsupported { return false }
        guard result == .success, let names = names as? [String] else { throw map(result) }
        return names.contains(kAXStringForRangeParameterizedAttribute as String)
    }

    func string(for range: CursorTextRange, in element: AXUIElement) throws -> String {
        var cfRange = try validatedCFRange(range)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            throw AccessibilityClientError.invalidValue
        }
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &value
        )
        guard result == .success, let text = value as? String else { throw map(result) }
        return text
    }

    func setSelectedTextRange(_ range: CursorTextRange, on element: AXUIElement) throws {
        var cfRange = try validatedCFRange(range)
        guard let value = AXValueCreate(.cfRange, &cfRange) else {
            throw AccessibilityClientError.invalidValue
        }
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
        guard result == .success else { throw map(result) }
    }

    func setSelectedText(_ text: String, on element: AXUIElement) throws {
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        guard result == .success else { throw map(result) }
    }

    func setFocused(_ focused: Bool, on element: AXUIElement) throws {
        let value: CFBoolean = focused ? kCFBooleanTrue : kCFBooleanFalse
        let result = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, value)
        guard result == .success else { throw map(result) }
    }

    func readSecurityState(for element: AXUIElement) -> DestinationSecurityState {
        do {
            guard let role = try role(for: element), supportedEditableRoles.contains(role),
                  let subrole = try subrole(for: element) else {
                return .unverifiable
            }
            if subrole == (kAXSecureTextFieldSubrole as String) {
                return .secure
            }
            return supportedNonSecureSubroles.contains(subrole) ? .safe : .unverifiable
        } catch {
            return .unverifiable
        }
    }

    private func stringAttribute(_ attribute: CFString, on element: AXUIElement) throws -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        if result == .noValue || result == .attributeUnsupported { return nil }
        guard result == .success else { throw map(result) }
        return value as? String
    }

    private func validatedCFRange(_ range: CursorTextRange) throws -> CFRange {
        guard range.location >= 0, range.length >= 0 else {
            throw AccessibilityClientError.invalidValue
        }
        return CFRange(location: range.location, length: range.length)
    }

    private func map(_ error: AXError) -> AccessibilityClientError {
        switch error {
        case .cannotComplete:
            return .cannotComplete
        case .noValue:
            return .noFocusedElement
        case .success:
            return .invalidValue
        default:
            return .operationFailed
        }
    }

    private var supportedEditableRoles: Set<String> {
        [kAXTextFieldRole as String, kAXTextAreaRole as String]
    }

    private var supportedNonSecureSubroles: Set<String> {
        ["AXStandard", kAXSearchFieldSubrole as String]
    }
}

/// The v5 raw AX runtime is deliberately separate from the MainActor-facing
/// compatibility client above.  It is created and used only by the submission
/// executor.  Every newly-created object is assigned a timeout immediately
/// before each message; AX timeouts are never inherited from another object.
final class SystemReviewSubmissionAXRuntime: ReviewSubmissionRawAccessibilityRuntime {
    private let captureBudgetNanoseconds: UInt64 = 500_000_000
    private let stepObserver: ReviewAXStepObserver?
    private let securitySamples: ReviewAXSecuritySamples

    init(
        stepObserver: ReviewAXStepObserver? = nil,
        securitySamples: ReviewAXSecuritySamples = ReviewAXSecuritySamples()
    ) {
        self.stepObserver = stepObserver
        self.securitySamples = securitySamples
    }

    convenience init(
        stepObserver: @escaping @Sendable (ReviewAXStepID) -> Void
    ) {
        self.init(stepObserver: { step, _ in stepObserver(step) })
    }

    private enum AXElementRead {
        case value(AXUIElement)
        case unavailable
        case failed
        case cancelled
        case deadline
    }

    private enum AXStringRead {
        case value(String)
        case unavailable
        case failed
        case cancelled
        case deadline
    }

    private enum AXSettableRead {
        case settable
        case unavailable
        case failed
        case cancelled
        case deadline
    }

    private enum AXRangeRead {
        case value(CursorTextRange)
        case unavailable
        case failed
        case cancelled
        case deadline
    }

    private enum AXOperationResult {
        case success
        case failed
        case cancelled
        case deadline

        func mapOperationResult(success: Bool) -> AXOperationResult {
            switch self {
            case .cancelled: return .cancelled
            case .deadline: return .deadline
            case .success: return success ? .success : .failed
            case .failed: return .failed
            }
        }
    }

    private enum AXCheckpointResult {
        case success
        case cancelled
        case deadline

        func mapOperationResult(success: Bool) -> AXOperationResult {
            switch self {
            case .cancelled: return .cancelled
            case .deadline: return .deadline
            case .success: return success ? .success : .failed
            }
        }
    }

    private enum AXPIDRead {
        case value(pid_t)
        case failed
        case cancelled
        case deadline
    }

    private enum EditableAssessment {
        case safe
        case ordinaryCapabilityMiss
        case secure
        case unverifiable
        case cancelled
        case deadline
    }

    func capture(
        _ request: ReviewTargetCaptureRequestDescriptor
    ) -> Result<ReviewSubmissionRawTargetState, ReviewPreBoundaryFailure> {
        let captureDeadline = request.captureUptime.addingReportingOverflow(
            captureBudgetNanoseconds
        )
        let deadline = captureDeadline.overflow ? UInt64.max : captureDeadline.partialValue
        guard isWithin(deadline) else { return .failure(.accessibilityTimeout) }
        guard let running = NSRunningApplication(
            processIdentifier: request.application.processIdentifier
        ),
        applicationIdentity(for: running) == request.application,
        NSWorkspace.shared.frontmostApplication?.processIdentifier
            == request.application.processIdentifier else {
            return .failure(.targetIdentityChanged)
        }
        guard !IsSecureEventInputEnabled(), AXIsProcessTrusted() else {
            return .failure(.securityRejected)
        }

        let applicationElement = AXUIElementCreateApplication(
            request.application.processIdentifier
        )
        guard case .success = sendTimeout(
            to: applicationElement,
            deadline: deadline,
            cancellationProbe: { false }
        ) else {
            return .failure(.accessibilityTimeout)
        }

        let focused: AXUIElement
        switch copyAttribute(
            kAXFocusedUIElementAttribute as CFString,
            from: applicationElement,
            deadline: deadline,
            cancellationProbe: { false }
        ) {
        case .value(let value):
            focused = value
        case .unavailable:
            return .success(applicationBoundState(
                request: request,
                applicationElement: applicationElement
            ))
        case .failed:
            return .failure(.accessibilityTimeout)
        case .cancelled:
            return .failure(.cancellation)
        case .deadline:
            return .failure(.accessibilityTimeout)
        }
        return captureFocusedState(
            focused,
            request: request,
            applicationElement: applicationElement,
            deadline: deadline
        )
    }

    func validate(
        _ target: ReviewSubmissionRawTargetState,
        deadline: UInt64
    ) -> ReviewPreBoundaryFailure? {
        validate(target, deadline: deadline, cancellationProbe: { false })
    }

    func validate(
        _ target: ReviewSubmissionRawTargetState,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> ReviewPreBoundaryFailure? {
        if let failure = securityComposite(
            target.descriptor.application,
            deadline: deadline,
            cancellationProbe: cancellationProbe,
            leading: true
        ) {
            return failure
        }
        switch processIdentifier(
            for: target.applicationElement,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) {
        case .value(let applicationProcessIdentifier):
            guard applicationProcessIdentifier
                == target.descriptor.application.processIdentifier else {
                return .targetIdentityChanged
            }
        case .cancelled:
            return .cancellation
        case .deadline:
            return .accessibilityTimeout
        case .failed:
            return cancellationProbe() ? .cancellation : .targetIdentityChanged
        }
        let bindingFailure: ReviewPreBoundaryFailure?
        switch target.descriptor.binding {
        case .exactCursor:
            bindingFailure = validateExactState(
                target,
                deadline: deadline,
                cancellationProbe: cancellationProbe
            )
        case .applicationBoundCurrentFocus:
            bindingFailure = validateApplicationBoundState(
                target,
                deadline: deadline,
                cancellationProbe: cancellationProbe
            )
        }
        if let bindingFailure {
            return bindingFailure
        }
        return securityComposite(
            target.descriptor.application,
            deadline: deadline,
            cancellationProbe: cancellationProbe,
            leading: false
        )
    }

    private func captureFocusedState(
        _ focused: AXUIElement,
        request: ReviewTargetCaptureRequestDescriptor,
        applicationElement: AXUIElement,
        deadline: UInt64
    ) -> Result<ReviewSubmissionRawTargetState, ReviewPreBoundaryFailure> {
        guard let processIdentifier = captureProcessIdentifier(for: focused, deadline: deadline),
              processIdentifier == request.application.processIdentifier else {
            return .failure(.targetIdentityChanged)
        }
        switch captureEditableAssessment(focused, deadline: deadline) {
        case .safe:
            break
        case .ordinaryCapabilityMiss:
            return .success(applicationBoundState(
                request: request,
                applicationElement: applicationElement
            ))
        case .secure, .unverifiable:
            return .failure(.securityRejected)
        case .cancelled:
            return .failure(.cancellation)
        case .deadline:
            return .failure(.accessibilityTimeout)
        }
        switch exactSelection(on: focused, deadline: deadline) {
        case .success(let selection):
            guard let selection else {
                return .success(applicationBoundState(
                    request: request,
                    applicationElement: applicationElement
                ))
            }
            let descriptor = CapturedReviewTargetDescriptor(
                generation: request.generation,
                application: request.application,
                binding: .exactCursor,
                securityAtCapture: .safe
            )
            return .success(ReviewSubmissionRawTargetState(
                descriptor: descriptor,
                applicationElement: applicationElement,
                focusedElement: focused,
                originalSelection: selection
            ))
        case .failure(let failure):
            return .failure(failure)
        }
    }

    private func exactSelection(
        on focused: AXUIElement,
        deadline: UInt64
    ) -> Result<CursorTextRange?, ReviewPreBoundaryFailure> {
        switch exactAttributeSettable(
            kAXSelectedTextRangeAttribute as CFString,
            on: focused,
            deadline: deadline
        ) {
        case .success(true): break
        case .success(false): return .success(nil)
        case .failure(let failure): return .failure(failure)
        }
        switch exactAttributeSettable(
            kAXFocusedAttribute as CFString,
            on: focused,
            deadline: deadline
        ) {
        case .success(true): break
        case .success(false): return .success(nil)
        case .failure(let failure): return .failure(failure)
        }
        return selectedRangeResult(on: focused, deadline: deadline)
    }

    private func exactAttributeSettable(
        _ attribute: CFString,
        on focused: AXUIElement,
        deadline: UInt64
    ) -> Result<Bool, ReviewPreBoundaryFailure> {
        switch attributeSettable(
            attribute,
            on: focused,
            deadline: deadline,
            cancellationProbe: { false }
        ) {
        case .settable: return .success(true)
        case .unavailable: return .success(false)
        case .cancelled: return .failure(.cancellation)
        case .deadline: return .failure(.accessibilityTimeout)
        case .failed: return .failure(.securityRejected)
        }
    }

    private func selectedRangeResult(
        on focused: AXUIElement,
        deadline: UInt64
    ) -> Result<CursorTextRange?, ReviewPreBoundaryFailure> {
        switch selectedRange(
            on: focused,
            deadline: deadline,
            cancellationProbe: { false }
        ) {
        case .value(let range):
            guard range.location >= 0,
                  range.length >= 0,
                  range.endLocation != nil else {
                return .failure(.securityRejected)
            }
            return .success(range)
        case .unavailable:
            return .success(nil)
        case .failed:
            return .failure(.securityRejected)
        case .cancelled:
            return .failure(.cancellation)
        case .deadline:
            return .failure(.accessibilityTimeout)
        }
    }

    private func validateFocusedState(
        _ focused: AXUIElement,
        target: ReviewSubmissionRawTargetState,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> ReviewPreBoundaryFailure? {
        switch processIdentifier(
            for: focused,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) {
        case .cancelled:
            return .cancellation
        case .deadline:
            return .accessibilityTimeout
        case .failed:
            return cancellationProbe() ? .cancellation : .targetIdentityChanged
        case .value(let processIdentifier):
            guard processIdentifier == target.descriptor.application.processIdentifier else {
                return .targetIdentityChanged
            }
        }
        switch editableAssessment(
            focused,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) {
        case .safe:
            break
        case .ordinaryCapabilityMiss:
            return nil
        case .secure, .unverifiable:
            return .securityRejected
        case .cancelled:
            return .cancellation
        case .deadline:
            return .accessibilityTimeout
        }
        return nil
    }

    private func validateApplicationBoundState(
        _ target: ReviewSubmissionRawTargetState,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> ReviewPreBoundaryFailure? {
        let focused: AXUIElement
        switch copyAttribute(
            kAXFocusedUIElementAttribute as CFString,
            from: target.applicationElement,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) {
        case .value(let value):
            focused = value
            guard !cancellationProbe() else { return .cancellation }
        case .unavailable:
            guard !cancellationProbe() else { return .cancellation }
            return nil
        case .failed:
            return cancellationOr(
                cancellationProbe,
                deadline: deadline,
                fallback: .accessibilityTimeout
            )
        case .cancelled:
            return .cancellation
        case .deadline:
            return .accessibilityTimeout
        }
        return validateFocusedState(
            focused,
            target: target,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        )
    }

    private func validateExactState(
        _ target: ReviewSubmissionRawTargetState,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> ReviewPreBoundaryFailure? {
        guard let capturedElement = target.focusedElement,
              let originalSelection = target.originalSelection else {
            return .securityRejected
        }
        if let failure = restoreExactCursor(
            capturedElement,
            originalSelection: originalSelection,
            target: target,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) {
            return failure
        }
        return validateExactReadback(
            capturedElement,
            originalSelection: originalSelection,
            target: target,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        )
    }

    private func restoreExactCursor(
        _ capturedElement: AXUIElement,
        originalSelection: CursorTextRange,
        target: ReviewSubmissionRawTargetState,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> ReviewPreBoundaryFailure? {
        if let failure = validateCapturedElementPID(
            capturedElement,
            target: target,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        if let failure = restoreFocusedElement(
            capturedElement,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        if let failure = restoreSelectedRange(
            originalSelection,
            on: capturedElement,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        return cancellationProbe() ? .cancellation : nil
    }

    private func validateCapturedElementPID(
        _ element: AXUIElement,
        target: ReviewSubmissionRawTargetState,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> ReviewPreBoundaryFailure? {
        switch processIdentifier(
            for: element,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) {
        case .cancelled: return .cancellation
        case .deadline: return .accessibilityTimeout
        case .failed:
            return cancellationProbe() ? .cancellation : .securityRejected
        case .value(let processIdentifier):
            return processIdentifier == target.descriptor.application.processIdentifier
                ? nil
                : .targetIdentityChanged
        }
    }

    private func restoreFocusedElement(
        _ element: AXUIElement,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> ReviewPreBoundaryFailure? {
        switch setFocused(element, deadline: deadline, cancellationProbe: cancellationProbe) {
        case .success: return nil
        case .cancelled: return .cancellation
        case .deadline: return .accessibilityTimeout
        case .failed:
            return cancellationOr(
                cancellationProbe,
                deadline: deadline,
                fallback: .securityRejected
            )
        }
    }

    private func restoreSelectedRange(
        _ range: CursorTextRange,
        on element: AXUIElement,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> ReviewPreBoundaryFailure? {
        switch setSelectedRange(
            range,
            on: element,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) {
        case .success: return nil
        case .cancelled: return .cancellation
        case .deadline: return .accessibilityTimeout
        case .failed:
            return cancellationOr(
                cancellationProbe,
                deadline: deadline,
                fallback: .securityRejected
            )
        }
    }

    private func validateExactReadback(
        _ capturedElement: AXUIElement,
        originalSelection: CursorTextRange,
        target: ReviewSubmissionRawTargetState,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> ReviewPreBoundaryFailure? {
        if let failure = validateExactFocusReadback(
            capturedElement,
            target: target,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) {
            return failure
        }
        if let failure = validateExactSelectionReadback(
            capturedElement,
            originalSelection: originalSelection,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) {
            return failure
        }
        return validateExactEditableState(
            capturedElement,
            target: target,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        )
    }

    private func validateExactFocusReadback(
        _ capturedElement: AXUIElement,
        target: ReviewSubmissionRawTargetState,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> ReviewPreBoundaryFailure? {
        let restoredFocused: AXUIElement
        switch copyAttribute(
            kAXFocusedUIElementAttribute as CFString,
            from: target.applicationElement,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) {
        case .value(let value):
            restoredFocused = value
        case .cancelled:
            return .cancellation
        case .deadline:
            return .accessibilityTimeout
        case .unavailable, .failed:
            return cancellationOr(
                cancellationProbe,
                deadline: deadline,
                fallback: .securityRejected
            )
        }
        guard !cancellationProbe() else { return .cancellation }
        return CFEqual(restoredFocused, capturedElement) ? nil : .securityRejected
    }

    private func validateExactSelectionReadback(
        _ capturedElement: AXUIElement,
        originalSelection: CursorTextRange,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> ReviewPreBoundaryFailure? {
        let restoredSelection: CursorTextRange
        switch selectedRange(
            on: capturedElement,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) {
        case .value(let value):
            restoredSelection = value
        case .cancelled:
            return .cancellation
        case .deadline:
            return .accessibilityTimeout
        case .unavailable, .failed:
            return cancellationOr(
                cancellationProbe,
                deadline: deadline,
                fallback: .securityRejected
            )
        }
        guard !cancellationProbe() else { return .cancellation }
        return restoredSelection == originalSelection ? nil : .securityRejected
    }

    private func validateExactEditableState(
        _ capturedElement: AXUIElement,
        target: ReviewSubmissionRawTargetState,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> ReviewPreBoundaryFailure? {
        switch editableAssessment(
            capturedElement,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) {
        case .safe:
            break
        case .cancelled:
            return .cancellation
        case .deadline:
            return .accessibilityTimeout
        case .ordinaryCapabilityMiss, .secure, .unverifiable:
            return cancellationOr(
                cancellationProbe,
                deadline: deadline,
                fallback: .securityRejected
            )
        }
        switch processIdentifier(
            for: capturedElement,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) {
        case .cancelled:
            return .cancellation
        case .deadline:
            return .accessibilityTimeout
        case .failed:
            return cancellationProbe() ? .cancellation : .securityRejected
        case .value(let processIdentifier):
            guard processIdentifier == target.descriptor.application.processIdentifier else {
                return .securityRejected
            }
        }
        guard !cancellationProbe() else { return .cancellation }
        return nil
    }

    private func applicationBoundState(
        request: ReviewTargetCaptureRequestDescriptor,
        applicationElement: AXUIElement
    ) -> ReviewSubmissionRawTargetState {
        ReviewSubmissionRawTargetState(
            descriptor: CapturedReviewTargetDescriptor(
                generation: request.generation,
                application: request.application,
                binding: .applicationBoundCurrentFocus,
                securityAtCapture: .safe
            ),
            applicationElement: applicationElement,
            focusedElement: nil,
            originalSelection: nil
        )
    }

    private func securityComposite(
        _ expected: ReviewApplicationIdentity,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool,
        leading: Bool
    ) -> ReviewPreBoundaryFailure? {
        if let failure = checkpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        let secureInputEnabled = securitySamples.secureInputEnabled()
        observe(
            leading ? .secureInput : .secureInput,
            result: secureInputEnabled ? .secureInputEnabled : .success
        )
        if let failure = checkpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        guard !secureInputEnabled else { return .securityRejected }

        let trusted = securitySamples.accessibilityTrusted()
        observe(
            .accessibilityTrust,
            result: trusted ? .success : .accessibilityUntrusted
        )
        if let failure = checkpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        guard trusted else { return .securityRejected }

        guard let identity = securitySamples.runningIdentity(expected.processIdentifier) else {
            observe(.runningIdentity, result: .missingIdentity)
            return cancellationOr(
                cancellationProbe,
                deadline: deadline,
                fallback: .targetIdentityChanged
            )
        }
        observe(
            .runningIdentity,
            result: identity == expected ? .success : .wrongIdentity
        )
        if let failure = checkpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        guard identity == expected else { return .targetIdentityChanged }

        let frontmost = securitySamples.frontmostProcessIdentifier()
        observe(
            .frontmost,
            result: frontmost == expected.processIdentifier ? .success : .wrongFrontmost
        )
        if let failure = checkpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        guard frontmost == expected.processIdentifier else { return .frontmostChanged }
        return nil
    }

    private func cancellationOr(
        _ cancellationProbe: @escaping @Sendable () -> Bool,
        deadline: UInt64,
        fallback: ReviewPreBoundaryFailure
    ) -> ReviewPreBoundaryFailure {
        if cancellationProbe() { return .cancellation }
        return isWithin(deadline) ? fallback : .accessibilityTimeout
    }

    private func checkpointFailure(
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> ReviewPreBoundaryFailure? {
        switch checkpoint(deadline: deadline, cancellationProbe: cancellationProbe) {
        case .success:
            return nil
        case .cancelled:
            return .cancellation
        case .deadline:
            return .accessibilityTimeout
        }
    }

    private func elementTimeoutFailure(
        _ result: AXOperationResult
    ) -> AXElementRead? {
        switch result {
        case .success: return nil
        case .cancelled: return .cancelled
        case .failed: return .failed
        case .deadline: return .deadline
        }
    }

    private func elementCheckpointFailure(
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> AXElementRead? {
        switch checkpoint(deadline: deadline, cancellationProbe: cancellationProbe) {
        case .success: return nil
        case .cancelled: return .cancelled
        case .deadline: return .deadline
        }
    }

    private func pidTimeoutFailure(
        _ result: AXOperationResult
    ) -> AXPIDRead? {
        switch result {
        case .success: return nil
        case .cancelled: return .cancelled
        case .failed: return .failed
        case .deadline: return .deadline
        }
    }

    private func pidCheckpointFailure(
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> AXPIDRead? {
        switch checkpoint(deadline: deadline, cancellationProbe: cancellationProbe) {
        case .success: return nil
        case .cancelled: return .cancelled
        case .deadline: return .deadline
        }
    }

    private func rangeTimeoutFailure(
        _ result: AXOperationResult
    ) -> AXRangeRead? {
        switch result {
        case .success: return nil
        case .cancelled: return .cancelled
        case .failed: return .failed
        case .deadline: return .deadline
        }
    }

    private func rangeCheckpointFailure(
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> AXRangeRead? {
        switch checkpoint(deadline: deadline, cancellationProbe: cancellationProbe) {
        case .success: return nil
        case .cancelled: return .cancelled
        case .deadline: return .deadline
        }
    }

    private func settableTimeoutFailure(
        _ result: AXOperationResult
    ) -> AXSettableRead? {
        switch result {
        case .success: return nil
        case .cancelled: return .cancelled
        case .failed: return .failed
        case .deadline: return .deadline
        }
    }

    private func settableCheckpointFailure(
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> AXSettableRead? {
        switch checkpoint(deadline: deadline, cancellationProbe: cancellationProbe) {
        case .success: return nil
        case .cancelled: return .cancelled
        case .deadline: return .deadline
        }
    }

    private func stringTimeoutFailure(
        _ result: AXOperationResult
    ) -> AXStringRead? {
        switch result {
        case .success: return nil
        case .cancelled: return .cancelled
        case .failed: return .failed
        case .deadline: return .deadline
        }
    }

    private func stringCheckpointFailure(
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> AXStringRead? {
        switch checkpoint(deadline: deadline, cancellationProbe: cancellationProbe) {
        case .success: return nil
        case .cancelled: return .cancelled
        case .deadline: return .deadline
        }
    }

    private func operationCheckpointFailure(
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> AXOperationResult? {
        switch checkpoint(deadline: deadline, cancellationProbe: cancellationProbe) {
        case .success: return nil
        case .cancelled: return .cancelled
        case .deadline: return .deadline
        }
    }

    private func operationTimeoutFailure(
        _ result: AXOperationResult
    ) -> AXOperationResult? {
        switch result {
        case .success: return nil
        case .cancelled: return .cancelled
        case .failed: return .failed
        case .deadline: return .deadline
        }
    }

    private func checkpoint(
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> AXCheckpointResult {
        if cancellationProbe() { return .cancelled }
        return isWithin(deadline) ? .success : .deadline
    }

    private func observe(
        _ step: ReviewAXStepID,
        result: ReviewAXResultCategory
    ) {
        stepObserver?(step, result)
    }

    private func isWithin(_ deadline: UInt64) -> Bool {
        DispatchTime.now().uptimeNanoseconds < deadline
    }

    private func sendTimeout(
        to element: AXUIElement,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> AXOperationResult {
        switch checkpoint(deadline: deadline, cancellationProbe: cancellationProbe) {
        case .cancelled: return .cancelled
        case .deadline: return .deadline
        case .success: break
        }
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else { return .deadline }
        let remaining = deadline - now
        let seconds = min(0.5, Double(remaining) / 1_000_000_000)
        guard seconds > 0 else { return .deadline }
        let status = AXUIElementSetMessagingTimeout(element, Float(seconds))
        observe(
            .messagingTimeout,
            result: status == .success ? .success : .failure
        )
        return checkpoint(deadline: deadline, cancellationProbe: cancellationProbe)
            .mapOperationResult(success: status == .success)
    }

    private func copyAttribute(
        _ attribute: CFString,
        from element: AXUIElement,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> AXElementRead {
        if let failure = elementTimeoutFailure(
            sendTimeout(to: element, deadline: deadline, cancellationProbe: cancellationProbe)
        ) { return failure }
        if let failure = elementCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        let category: ReviewAXResultCategory
        switch result {
        case .success: category = .success
        case .noValue: category = .noValue
        case .attributeUnsupported: category = .attributeUnsupported
        default: category = .failure
        }
        observe(.copyAttribute, result: category)
        if let failure = elementCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        if result == .noValue || result == .attributeUnsupported {
            return .unavailable
        }
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            observe(.copyAttribute, result: .malformed)
            return .failed
        }
        return .value(unsafeBitCast(value, to: AXUIElement.self))
    }

    private func captureProcessIdentifier(
        for element: AXUIElement,
        deadline: UInt64
    ) -> pid_t? {
        switch processIdentifier(
            for: element,
            deadline: deadline,
            cancellationProbe: { false }
        ) {
        case .value(let processIdentifier): return processIdentifier
        case .failed, .cancelled, .deadline: return nil
        }
    }

    private func processIdentifier(
        for element: AXUIElement,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> AXPIDRead {
        if let failure = pidTimeoutFailure(
            sendTimeout(to: element, deadline: deadline, cancellationProbe: cancellationProbe)
        ) { return failure }
        if let failure = pidCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        var processIdentifier: pid_t = 0
        let result = AXUIElementGetPid(element, &processIdentifier)
        observe(
            .getProcessIdentifier,
            result: result == .success ? .success : .failure
        )
        if let failure = pidCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        guard result == .success, processIdentifier > 0 else { return .failed }
        return .value(processIdentifier)
    }

    private func attributeSettable(
        _ attribute: CFString,
        on element: AXUIElement,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> AXSettableRead {
        if let failure = settableTimeoutFailure(
            sendTimeout(
                to: element,
                deadline: deadline,
                cancellationProbe: cancellationProbe
            )
        ) { return failure }
        if let failure = settableCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, attribute, &settable)
        observe(
            .isAttributeSettable,
            result: result == .success ? .success : (
                result == .attributeUnsupported ? .attributeUnsupported : .failure
            )
        )
        if let failure = settableCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        if result == .attributeUnsupported || (result == .success && !settable.boolValue) {
            return .unavailable
        }
        return result == .success ? .settable : .failed
    }

    private func selectedRange(
        on element: AXUIElement,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> AXRangeRead {
        if let failure = rangeTimeoutFailure(
            sendTimeout(to: element, deadline: deadline, cancellationProbe: cancellationProbe)
        ) { return failure }
        if let failure = rangeCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )
        observe(
            .getSelectedRange,
            result: result == .success ? .success : (
                result == .noValue ? .noValue : (
                    result == .attributeUnsupported ? .attributeUnsupported : .failure
                )
            )
        )
        if let failure = rangeCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        if result == .noValue || result == .attributeUnsupported {
            return .unavailable
        }
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            observe(.getSelectedRange, result: .malformed)
            return .failed
        }
        var range = CFRange()
        if let failure = rangeCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        let valueRead = AXValueGetValue(
            unsafeBitCast(value, to: AXValue.self),
            .cfRange,
            &range
        )
        observe(.readAXValue, result: valueRead ? .success : .malformed)
        if let failure = rangeCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        guard valueRead else {
            return .failed
        }
        return .value(CursorTextRange(location: range.location, length: range.length))
    }

    private func setFocused(
        _ element: AXUIElement,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> AXOperationResult {
        if let failure = operationTimeoutFailure(
            sendTimeout(to: element, deadline: deadline, cancellationProbe: cancellationProbe)
        ) { return failure }
        if let failure = operationCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        let result = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        observe(.setFocused, result: result == .success ? .success : .failure)
        return operationCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        )?.mapOperationResult(success: result == .success)
            ?? (result == .success ? .success : .failed)
    }

    private func setSelectedRange(
        _ range: CursorTextRange,
        on element: AXUIElement,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> AXOperationResult {
        guard range.location >= 0,
              range.length >= 0,
              range.endLocation != nil else {
            return .failed
        }
        if let failure = operationTimeoutFailure(
            sendTimeout(to: element, deadline: deadline, cancellationProbe: cancellationProbe)
        ) { return failure }
        if let failure = operationCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else {
            observe(.createAXValue, result: .malformed)
            return .failed
        }
        observe(.createAXValue, result: .success)
        if let failure = operationCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        )
        observe(.setSelectedRange, result: result == .success ? .success : .failure)
        return operationCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        )?.mapOperationResult(success: result == .success)
            ?? (result == .success ? .success : .failed)
    }

    private func captureEditableAssessment(
        _ element: AXUIElement,
        deadline: UInt64
    ) -> EditableAssessment {
        editableAssessment(
            element,
            deadline: deadline,
            cancellationProbe: { false }
        )
    }

    private func editableAssessment(
        _ element: AXUIElement,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> EditableAssessment {
        let role: String
        switch editableStringValue(
            kAXRoleAttribute as CFString,
            on: element,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) {
        case .value(let value):
            role = value
        case .failure(let failure):
            return failure
        }
        guard [kAXTextFieldRole as String, kAXTextAreaRole as String].contains(role) else {
            return .unverifiable
        }
        let subrole: String
        switch editableStringValue(
            kAXSubroleAttribute as CFString,
            on: element,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) {
        case .value(let value):
            subrole = value
        case .failure(let failure):
            return failure
        }
        if subrole == (kAXSecureTextFieldSubrole as String) {
            return .secure
        }
        return ["AXStandard", kAXSearchFieldSubrole as String].contains(subrole)
            ? .safe
            : .unverifiable
    }

    private enum EditableStringResult {
        case value(String)
        case failure(EditableAssessment)
    }

    private func editableStringValue(
        _ attribute: CFString,
        on element: AXUIElement,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> EditableStringResult {
        switch stringAttributeAfterCancellation(
            attribute,
            on: element,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) {
        case .value(let value): return .value(value)
        case .unavailable: return .failure(.ordinaryCapabilityMiss)
        case .failed: return .failure(.unverifiable)
        case .cancelled: return .failure(.cancelled)
        case .deadline: return .failure(.deadline)
        }
    }

    private func stringAttributeAfterCancellation(
        _ attribute: CFString,
        on element: AXUIElement,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> AXStringRead {
        stringAttribute(
            attribute,
            on: element,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        )
    }

    private func stringAttribute(
        _ attribute: CFString,
        on element: AXUIElement,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> AXStringRead {
        if let failure = stringTimeoutFailure(
            sendTimeout(to: element, deadline: deadline, cancellationProbe: cancellationProbe)
        ) { return failure }
        if let failure = stringCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        observe(
            attribute == (kAXRoleAttribute as CFString) ? .role : .subrole,
            result: result == .success ? .success : (
                result == .noValue ? .noValue : (
                    result == .attributeUnsupported ? .attributeUnsupported : .failure
                )
            )
        )
        if let failure = stringCheckpointFailure(
            deadline: deadline,
            cancellationProbe: cancellationProbe
        ) { return failure }
        if result == .noValue || result == .attributeUnsupported {
            return .unavailable
        }
        guard result == .success, let value = value as? String else {
            observe(
                attribute == (kAXRoleAttribute as CFString) ? .role : .subrole,
                result: .malformed
            )
            return .failed
        }
        return .value(value)
    }

    private func applicationIdentity(
        for application: NSRunningApplication
    ) -> ReviewApplicationIdentity? {
        guard let bundleIdentifier = application.bundleIdentifier,
              let executableURL = application.executableURL,
              let launchDate = application.launchDate else {
            return nil
        }
        return ReviewApplicationIdentity(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: bundleIdentifier,
            executableURL: executableURL,
            launchDate: launchDate
        )
    }
}

/// Naming retained from the v5 architecture so tests and diagnostics can
/// refer to the single concrete step runner without introducing a second AX
/// abstraction.
typealias SystemReviewAXStepRunner = SystemReviewSubmissionAXRuntime
