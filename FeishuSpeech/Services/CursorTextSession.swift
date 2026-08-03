import ApplicationServices
import Foundation
import os.log

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "CursorTextSession"
)

@MainActor
final class CursorTextSession {
    private let generation: UInt64
    private let accessibilityClient: AccessibilityClient
    private var destination: CursorDestinationToken?

    private(set) var state: CursorTextSessionState = .unavailable

    init(generation: UInt64, accessibilityClient: AccessibilityClient) {
        self.generation = generation
        self.accessibilityClient = accessibilityClient
    }

    func begin() throws -> CursorCapabilityResult {
        guard state == .unavailable else {
            return currentCapabilityResult()
        }

        let result = try accessibilityClient.captureDestination(generation: generation)
        switch result {
        case .live(let token):
            destination = token
            state = .armed
        case .finalOnly(let token):
            destination = token
            state = .finalOnly
        case .rejected:
            state = .invalid
        }
        return result
    }

    func handle(_ event: StreamingRecognitionEvent, generation callbackGeneration: UInt64) throws {
        guard callbackGeneration == generation else {
            return
        }
        guard state == .armed || isProvisional else {
            return
        }

        switch event {
        case .partial(let text):
            guard !text.isEmpty else {
                return
            }
            replaceOwnedText(with: text, commits: false)
        case .final(let text):
            guard !text.isEmpty else {
                state = .preserved
                return
            }
            replaceOwnedText(with: text, commits: true)
        case .failed, .cancelled:
            state = .preserved
        }
    }

    func invalidate() {
        destination = nil
        state = .invalid
    }

    private var isProvisional: Bool {
        if case .provisional = state {
            return true
        }
        return false
    }

    private func replaceOwnedText(with text: String, commits: Bool) {
        guard let destination else {
            state = .invalid
            return
        }

        let replacementRange: CursorTextRange
        switch state {
        case .armed:
            replacementRange = destination.originalSelection
        case .provisional(let range, let previousText):
            guard commits || text != previousText else {
                return
            }
            replacementRange = range
        default:
            return
        }

        do {
            guard try prepareOwnedReplacement(
                with: text,
                commits: commits,
                in: replacementRange,
                at: destination
            ) else {
                return
            }
            guard try performReplacement(text, in: replacementRange, at: destination),
                  let ownedRange = try verifiedOwnedRange(
                      for: text,
                      replacing: replacementRange,
                      at: destination
                  ) else {
                invalidate()
                return
            }

            state = commits ? .committed : .provisional(range: ownedRange, text: text)
            if commits {
                self.destination = nil
            }
        } catch {
            // A write may already be visible. Invalidate ownership and never attempt rollback.
            invalidate()
        }
    }

    private func prepareOwnedReplacement(
        with text: String,
        commits: Bool,
        in replacementRange: CursorTextRange,
        at destination: CursorDestinationToken
    ) throws -> Bool {
        guard try destinationIsCurrent(destination),
              try accessibilityClient.currentSecurityState(for: destination) == .safe,
              try accessibilityClient.selectedTextRange(for: destination) == expectedCaretOrSelection(
                  for: replacementRange
              ) else {
            invalidate()
            return false
        }

        guard case .provisional(_, let previousText) = state else {
            return true
        }
        guard try accessibilityClient.string(for: replacementRange, in: destination) == previousText else {
            invalidate()
            return false
        }
        if commits, text == previousText {
            state = .committed
            self.destination = nil
            return false
        }
        return true
    }

    private func performReplacement(
        _ text: String,
        in replacementRange: CursorTextRange,
        at destination: CursorDestinationToken
    ) throws -> Bool {
        guard try accessibilityClient.currentSecurityState(for: destination) == .safe else {
            return false
        }
        try accessibilityClient.setSelectedTextRange(replacementRange, for: destination)
        guard try accessibilityClient.currentSecurityState(for: destination) == .safe else {
            return false
        }
        try accessibilityClient.setSelectedText(text, for: destination)
        return true
    }

    private func verifiedOwnedRange(
        for text: String,
        replacing replacementRange: CursorTextRange,
        at destination: CursorDestinationToken
    ) throws -> CursorTextRange? {
        guard try destinationIsCurrent(destination) else {
            return nil
        }
        let returnedCaret = try accessibilityClient.selectedTextRange(for: destination)
        guard returnedCaret.length == 0,
              returnedCaret.location >= replacementRange.location else {
            return nil
        }
        let ownedRange = CursorTextRange(
            location: replacementRange.location,
            length: returnedCaret.location - replacementRange.location
        )
        guard try accessibilityClient.string(for: ownedRange, in: destination) == text else {
            return nil
        }
        return ownedRange
    }

    private func expectedCaretOrSelection(for replacementRange: CursorTextRange) -> CursorTextRange? {
        switch state {
        case .armed:
            return replacementRange
        case .provisional:
            guard let end = replacementRange.endLocation else {
                return nil
            }
            return CursorTextRange(location: end, length: 0)
        default:
            return nil
        }
    }

    private func destinationIsCurrent(_ destination: CursorDestinationToken) throws -> Bool {
        guard accessibilityClient.frontmostProcessIdentifier() == destination.processIdentifier else {
            return false
        }
        let focusedElement = try accessibilityClient.focusedElement()
        return CFEqual(focusedElement, destination.element)
    }

    private func currentCapabilityResult() -> CursorCapabilityResult {
        if let destination {
            return state == .finalOnly ? .finalOnly(destination) : .live(destination)
        }
        return .rejected(.accessibilityUnavailable)
    }
}
