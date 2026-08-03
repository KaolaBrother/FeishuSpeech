import AppKit
import Foundation

import os.log

private let logger = Logger(subsystem: "com.feishuspeech.app", category: "CurrentFocusAppendSession")

nonisolated enum CurrentFocusHypothesisSource: Equatable, Sendable {
    case livePacket
    case replayCatchUp
}

nonisolated enum CurrentFocusAppendOutcome: Equatable, Sendable {
    case insertedFirst
    case appendedSuffix
    case duplicate
    case revisionSuppressed
    case contentless
    case unsafeTextSuppressed
    case destinationChanged
    case securityRejected
    case deliveryUncertain
    case staleGeneration
}

nonisolated enum CurrentFocusAppendFinalOutcome: Equatable, Sendable {
    case exactCommitted
    case suffixCommitted
    case preservedDivergence
    case preservedDestinationLoss
    case preservedSecurityRejection
    case deliveryUncertain
    case noUsableText
    case staleGeneration
}

@MainActor
protocol CurrentFocusProvisionalOutputSession: AnyObject {
    func applyOpaqueHypothesis(
        _ text: String,
        generation: UInt64,
        source: CurrentFocusHypothesisSource
    ) -> CurrentFocusAppendOutcome

    func finalize(
        finalText: String?,
        lastAcceptedText: String?,
        generation: UInt64
    ) -> CurrentFocusAppendFinalOutcome

    func invalidate()
}

@MainActor
// swiftlint:disable:next type_name
protocol CurrentFocusProvisionalOutputSessionFactory: AnyObject {
    func makeSession(generation: UInt64) -> (any CurrentFocusProvisionalOutputSession)?
}

@MainActor
protocol CurrentFocusActivationMonitoring: AnyObject {
    func startMonitoring(_ handler: @escaping @MainActor (pid_t) -> Void)
    func stopMonitoring()
}

@MainActor
final class CurrentFocusAppendSession: CurrentFocusProvisionalOutputSession {
    private enum Suspension {
        case destinationChanged
        case securityRejected
        case deliveryUncertain
    }

    private let generation: UInt64
    private let boundProcessIdentifier: pid_t
    private let eventPoster: FinalTextCurrentFocusEventPosting
    private let secureInputStateProvider: SecureInputStateProviding
    private let frontmostProcessProvider: FrontmostProcessProviding
    private let activationMonitor: CurrentFocusActivationMonitoring

    private var emittedUTF16: [UInt16] = []
    private var suspension: Suspension?
    private var isClosed = false
    private var isMonitoring = false

    init(
        generation: UInt64,
        boundProcessIdentifier: pid_t,
        eventPoster: FinalTextCurrentFocusEventPosting,
        secureInputStateProvider: SecureInputStateProviding,
        frontmostProcessProvider: FrontmostProcessProviding,
        activationMonitor: CurrentFocusActivationMonitoring
    ) {
        self.generation = generation
        self.boundProcessIdentifier = boundProcessIdentifier
        self.eventPoster = eventPoster
        self.secureInputStateProvider = secureInputStateProvider
        self.frontmostProcessProvider = frontmostProcessProvider
        self.activationMonitor = activationMonitor

        isMonitoring = true
        activationMonitor.startMonitoring { [weak self] processIdentifier in
            guard let self, processIdentifier != self.boundProcessIdentifier else { return }
            self.suspend(.destinationChanged)
        }
    }

    func applyOpaqueHypothesis(
        _ text: String,
        generation: UInt64,
        source _: CurrentFocusHypothesisSource
    ) -> CurrentFocusAppendOutcome {
        let hypothesisUTF16 = Array(text.utf16)
        if let rejection = rejectionBeforePosting(
            text,
            hypothesisUTF16: hypothesisUTF16,
            generation: generation
        ) {
            return rejection
        }

        let suffixUTF16 = hypothesisUTF16[emittedUTF16.count...]
        let suffix = String(decoding: suffixUTF16, as: UTF16.self)
        let wasEmpty = emittedUTF16.isEmpty

        guard sampleDestinationAndSecurity() else {
            return applyOutcome(for: suspension ?? .deliveryUncertain)
        }
        guard sampleDestinationAndSecurity() else {
            return applyOutcome(for: suspension ?? .deliveryUncertain)
        }

        switch eventPoster.postUnicodeText(suffix) {
        case .posted:
            break
        case .securityRejected:
            suspend(.securityRejected)
            return .securityRejected
        case .deliveryFailed:
            suspend(.deliveryUncertain)
            return .deliveryUncertain
        }

        guard sampleDestinationAndSecurity() else {
            return applyOutcome(for: suspension ?? .deliveryUncertain)
        }

        emittedUTF16 = hypothesisUTF16
        return wasEmpty ? .insertedFirst : .appendedSuffix
    }

    private func rejectionBeforePosting(
        _ text: String,
        hypothesisUTF16: [UInt16],
        generation: UInt64
    ) -> CurrentFocusAppendOutcome? {
        guard !isClosed, generation == self.generation else { return .staleGeneration }
        if let suspension {
            return applyOutcome(for: suspension)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .contentless
        }
        guard TextInputSimulator.isSafeForAutomaticPaste(text) else {
            return .unsafeTextSuppressed
        }
        guard hypothesisUTF16.starts(with: emittedUTF16) else {
            return .revisionSuppressed
        }
        guard hypothesisUTF16.count > emittedUTF16.count else {
            return .duplicate
        }
        return nil
    }

    func finalize(
        finalText: String?,
        lastAcceptedText: String?,
        generation: UInt64
    ) -> CurrentFocusAppendFinalOutcome {
        guard !isClosed, generation == self.generation else { return .staleGeneration }
        close()

        if let suspension {
            return finalOutcome(for: suspension)
        }

        let candidate = usableFinalValue(finalText) ?? usableFinalValue(lastAcceptedText)
        guard let candidate else {
            return emittedUTF16.isEmpty ? .noUsableText : .exactCommitted
        }

        guard TextInputSimulator.isSafeForAutomaticPaste(candidate) else {
            return emittedUTF16.isEmpty ? .noUsableText : .preservedDivergence
        }

        let candidateUTF16 = Array(candidate.utf16)
        guard candidateUTF16.starts(with: emittedUTF16) else {
            return .preservedDivergence
        }
        guard candidateUTF16.count > emittedUTF16.count else {
            return .exactCommitted
        }

        let suffix = String(decoding: candidateUTF16[emittedUTF16.count...], as: UTF16.self)
        guard postFinalSuffix(suffix) else {
            return finalOutcome(for: suspension ?? .deliveryUncertain)
        }
        emittedUTF16 = candidateUTF16
        return .suffixCommitted
    }

    func invalidate() {
        guard !isClosed else { return }
        close()
    }

    private func postFinalSuffix(_ suffix: String) -> Bool {
        guard sampleDestinationAndSecurity(), sampleDestinationAndSecurity() else { return false }

        switch eventPoster.postUnicodeText(suffix) {
        case .posted:
            break
        case .securityRejected:
            suspend(.securityRejected)
            return false
        case .deliveryFailed:
            suspend(.deliveryUncertain)
            return false
        }
        return sampleDestinationAndSecurity()
    }

    private func sampleDestinationAndSecurity() -> Bool {
        guard !secureInputStateProvider.isSecureInputEnabled() else {
            suspend(.securityRejected)
            return false
        }
        guard frontmostProcessProvider.frontmostProcessIdentifier() == boundProcessIdentifier else {
            suspend(.destinationChanged)
            return false
        }
        return true
    }

    private func usableFinalValue(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    private func suspend(_ reason: Suspension) {
        guard suspension == nil else { return }
        suspension = reason
        stopMonitoring()
        switch reason {
        case .destinationChanged:
            logger.info("Current-focus append suspended because the destination changed")
        case .securityRejected:
            logger.info("Current-focus append suspended because secure input was observed")
        case .deliveryUncertain:
            logger.info("Current-focus append suspended because delivery became uncertain")
        }
    }

    private func close() {
        isClosed = true
        stopMonitoring()
    }

    private func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        activationMonitor.stopMonitoring()
    }

    private func applyOutcome(for suspension: Suspension) -> CurrentFocusAppendOutcome {
        switch suspension {
        case .destinationChanged:
            return .destinationChanged
        case .securityRejected:
            return .securityRejected
        case .deliveryUncertain:
            return .deliveryUncertain
        }
    }

    private func finalOutcome(for suspension: Suspension) -> CurrentFocusAppendFinalOutcome {
        switch suspension {
        case .destinationChanged:
            return .preservedDestinationLoss
        case .securityRejected:
            return .preservedSecurityRejection
        case .deliveryUncertain:
            return .deliveryUncertain
        }
    }
}

@MainActor
// swiftlint:disable:next type_name
final class SystemCurrentFocusProvisionalOutputSessionFactory: CurrentFocusProvisionalOutputSessionFactory {
    private let eventPoster: FinalTextCurrentFocusEventPosting
    private let secureInputStateProvider: SecureInputStateProviding
    private let frontmostProcessProvider: FrontmostProcessProviding
    private let activationMonitorFactory: @MainActor () -> CurrentFocusActivationMonitoring

    convenience init() {
        self.init(
            eventPoster: SystemFinalTextCurrentFocusEventPoster(),
            secureInputStateProvider: SystemSecureInputStateProvider(),
            frontmostProcessProvider: SystemFrontmostProcessProvider(),
            activationMonitorFactory: { WorkspaceCurrentFocusActivationMonitor() }
        )
    }

    init(
        eventPoster: FinalTextCurrentFocusEventPosting,
        secureInputStateProvider: SecureInputStateProviding,
        frontmostProcessProvider: FrontmostProcessProviding,
        activationMonitorFactory: @escaping @MainActor () -> CurrentFocusActivationMonitoring
    ) {
        self.eventPoster = eventPoster
        self.secureInputStateProvider = secureInputStateProvider
        self.frontmostProcessProvider = frontmostProcessProvider
        self.activationMonitorFactory = activationMonitorFactory
    }

    func makeSession(generation: UInt64) -> (any CurrentFocusProvisionalOutputSession)? {
        guard let processIdentifier = frontmostProcessProvider.frontmostProcessIdentifier() else {
            logger.info("Current-focus append session was not created because no frontmost process was available")
            return nil
        }
        return CurrentFocusAppendSession(
            generation: generation,
            boundProcessIdentifier: processIdentifier,
            eventPoster: eventPoster,
            secureInputStateProvider: secureInputStateProvider,
            frontmostProcessProvider: frontmostProcessProvider,
            activationMonitor: activationMonitorFactory()
        )
    }
}

@MainActor
final class WorkspaceCurrentFocusActivationMonitor: NSObject, CurrentFocusActivationMonitoring {
    private var handler: (@MainActor (pid_t) -> Void)?
    private var isMonitoring = false

    func startMonitoring(_ handler: @escaping @MainActor (pid_t) -> Void) {
        self.handler = handler
        guard !isMonitoring else { return }
        isMonitoring = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        handler = nil
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else {
            return
        }
        handler?(application.processIdentifier)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
