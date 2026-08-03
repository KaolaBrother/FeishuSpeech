import AppKit
import ApplicationServices
import Carbon
import Foundation
import os.log

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "AccessibilityClient"
)

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
}

@MainActor
final class MacAccessibilityClient: AccessibilityClient {
    private let runtime: AccessibilityRuntime

    init(runtime: AccessibilityRuntime) {
        self.runtime = runtime
    }

    convenience init() {
        self.init(runtime: SystemAccessibilityRuntime())
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

    private var supportedEditableRoles: Set<String> {
        [kAXTextFieldRole as String, kAXTextAreaRole as String]
    }

    private var supportedNonSecureSubroles: Set<String> {
        ["AXStandard", kAXSearchFieldSubrole as String]
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
}
