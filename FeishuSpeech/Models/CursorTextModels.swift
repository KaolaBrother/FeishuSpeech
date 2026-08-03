import ApplicationServices
import Foundation
import os.log

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "CursorTextModels"
)

nonisolated struct CursorTextRange: Equatable, Sendable {
    let location: Int
    let length: Int

    var endLocation: Int? {
        let (end, overflow) = location.addingReportingOverflow(length)
        return overflow ? nil : end
    }

    init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

struct CursorDestinationToken {
    let generation: UInt64
    let processIdentifier: pid_t
    let element: AXUIElement
    let originalSelection: CursorTextRange
}

nonisolated enum CursorCapabilityRejection: Equatable, Sendable {
    case secureTarget
    case accessibilityUnavailable
}

enum CursorCapabilityResult {
    case live(CursorDestinationToken)
    case finalOnly(CursorDestinationToken)
    case rejected(CursorCapabilityRejection)
}

nonisolated enum AccessibilityClientError: Error, Equatable, Sendable {
    case accessibilityUnavailable
    case noFocusedElement
    case cannotComplete
    case invalidValue
    case operationFailed
}

nonisolated enum DestinationSecurityState: Equatable, Sendable {
    case safe
    case secure
    case unverifiable
}

nonisolated enum CursorTextSessionState: Equatable, Sendable {
    case unavailable
    case armed
    case finalOnly
    case provisional(range: CursorTextRange, text: String)
    case invalid
    case committed
    case preserved
}

nonisolated enum FinalOnlyFallbackDecision: Equatable, Sendable {
    case insertOnce
    case copyForManualRecovery
    case noInsertion
    case rejectSecureTarget

    static func evaluate(
        autoInsert: Bool,
        secureTarget: Bool,
        finalTextIsEmpty: Bool,
        destinationStillCurrent: Bool
    ) -> FinalOnlyFallbackDecision {
        if secureTarget {
            return .rejectSecureTarget
        }
        guard autoInsert, !finalTextIsEmpty else {
            return .noInsertion
        }
        return destinationStillCurrent ? .insertOnce : .copyForManualRecovery
    }
}

nonisolated enum FinalTextInsertionResult: Equatable, Sendable {
    case inserted
    case securityRejected
    case destinationInvalid
    case deliveryFailed
}
