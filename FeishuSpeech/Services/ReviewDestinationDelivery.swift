import AppKit
import ApplicationServices
import Foundation
import os.log

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "ReviewDestinationDelivery"
)

nonisolated enum ReviewActivationResult: Equatable, Sendable {
    case activated
    case notRunning
    case identityChanged
    case requestRejected
    case timedOut
    case cancelled
}

@MainActor
protocol ReviewApplicationRuntime: AnyObject {
    func identity(for processIdentifier: pid_t) -> ReviewApplicationIdentity?
    func frontmostIdentity() -> ReviewApplicationIdentity?
    func frontmostProcessIdentifier() -> pid_t?
}

extension ReviewApplicationRuntime {
    func frontmostProcessIdentifier() -> pid_t? {
        frontmostIdentity()?.processIdentifier
    }
}

@MainActor
protocol ReviewApplicationActivating: AnyObject {
    func activateAndWait(
        for identity: ReviewApplicationIdentity,
        timeoutNanoseconds: UInt64
    ) async -> ReviewActivationResult
}

nonisolated enum ReviewDeliveryResult: Equatable, Sendable {
    case inserted
    case activationFailed
    case identityChanged
    case destinationInvalid
    case securityRejected
    case unsafeText
    case deliveryFailed
    case deliveryUncertain
    case cancelled
}

@MainActor
protocol ReviewDestinationDelivering: AnyObject {
    func capture(generation: UInt64) -> ReviewDestinationCaptureResult
    func deliver(
        _ frozenText: String,
        to destination: ReviewDestinationToken
    ) async -> ReviewDeliveryResult
}

private func hasCompleteApplicationIdentity(_ identity: ReviewApplicationIdentity) -> Bool {
    identity.processIdentifier > 0
        && !identity.bundleIdentifier.isEmpty
        && !identity.executableURL.path.isEmpty
        && identity.launchDate.timeIntervalSinceReferenceDate.isFinite
}

@MainActor
final class SystemReviewApplicationRuntime: ReviewApplicationRuntime {
    func identity(for processIdentifier: pid_t) -> ReviewApplicationIdentity? {
        guard let application = NSRunningApplication(processIdentifier: processIdentifier) else {
            return nil
        }
        return Self.identity(for: application)
    }

    func frontmostIdentity() -> ReviewApplicationIdentity? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return Self.identity(for: application)
    }

    func frontmostProcessIdentifier() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    private static func identity(
        for application: NSRunningApplication
    ) -> ReviewApplicationIdentity? {
        guard let bundleIdentifier = application.bundleIdentifier,
              !bundleIdentifier.isEmpty,
              let executableURL = application.executableURL,
              !executableURL.path.isEmpty,
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

@MainActor
private final class ReviewRuntimeFrontmostProcessProvider: FrontmostProcessProviding {
    private let applicationRuntime: ReviewApplicationRuntime

    init(applicationRuntime: ReviewApplicationRuntime) {
        self.applicationRuntime = applicationRuntime
    }

    func frontmostProcessIdentifier() -> pid_t? {
        applicationRuntime.frontmostProcessIdentifier()
    }
}

@MainActor
private final class ReviewActivationWaiter {
    private let applicationRuntime: ReviewApplicationRuntime
    private let identity: ReviewApplicationIdentity
    private var observer: NSObjectProtocol?
    private var timeoutTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<ReviewActivationResult, Never>?
    private var didFinish = false

    init(
        applicationRuntime: ReviewApplicationRuntime,
        identity: ReviewApplicationIdentity
    ) {
        self.applicationRuntime = applicationRuntime
        self.identity = identity
    }

    func wait(timeoutNanoseconds: UInt64) async -> ReviewActivationResult {
        guard timeoutNanoseconds > 0 else { return .timedOut }
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                self.installObserver()
                self.beginActivation(timeoutNanoseconds: timeoutNanoseconds)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.cancelled)
            }
        }
        cleanup()
        return result
    }

    private func installObserver() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleActivationNotification()
            }
        }
    }

    private func beginActivation(timeoutNanoseconds: UInt64) {
        guard let application = NSRunningApplication(
            processIdentifier: identity.processIdentifier
        ) else {
            finish(.notRunning)
            return
        }
        guard applicationRuntime.identity(for: identity.processIdentifier) == identity else {
            finish(.identityChanged)
            return
        }
        if applicationRuntime.frontmostIdentity() == identity {
            finish(.activated)
            return
        }

        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }
            self?.finish(.timedOut)
        }

        guard application.activate(options: []) else {
            finish(.requestRejected)
            return
        }
    }

    private func handleActivationNotification() {
        guard applicationRuntime.identity(for: identity.processIdentifier) == identity,
              applicationRuntime.frontmostIdentity() == identity else {
            return
        }
        finish(.activated)
    }

    private func finish(_ result: ReviewActivationResult) {
        guard !didFinish else { return }
        didFinish = true
        observer.map(NSWorkspace.shared.notificationCenter.removeObserver)
        observer = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: result)
        continuation = nil
    }

    private func cleanup() {
        observer.map(NSWorkspace.shared.notificationCenter.removeObserver)
        observer = nil
        timeoutTask?.cancel()
        timeoutTask = nil
    }
}

@MainActor
final class WorkspaceReviewApplicationActivator: ReviewApplicationActivating {
    private let applicationRuntime: ReviewApplicationRuntime

    init(applicationRuntime: ReviewApplicationRuntime) {
        self.applicationRuntime = applicationRuntime
    }

    convenience init() {
        self.init(applicationRuntime: SystemReviewApplicationRuntime())
    }

    func activateAndWait(
        for identity: ReviewApplicationIdentity,
        timeoutNanoseconds: UInt64
    ) async -> ReviewActivationResult {
        guard !Task.isCancelled else { return .cancelled }
        guard hasCompleteApplicationIdentity(identity) else { return .identityChanged }
        logger.debug("review activation requested")
        let waiter = ReviewActivationWaiter(
            applicationRuntime: applicationRuntime,
            identity: identity
        )
        return await waiter.wait(timeoutNanoseconds: timeoutNanoseconds)
    }
}

@MainActor
final class SystemReviewDestinationDelivery: ReviewDestinationDelivering {
    static let activationTimeoutNanoseconds: UInt64 = 2_000_000_000

    private let applicationRuntime: ReviewApplicationRuntime
    private let applicationActivator: ReviewApplicationActivating
    private let accessibility: ReviewDestinationAccessing
    private let finalTextOutput: FinalTextOutput
    private let accessibilityTrustProvider: AccessibilityTrustProviding
    private let secureInputStateProvider: SecureInputStateProviding
    private let frontmostProcessProvider: FrontmostProcessProviding

    init(
        applicationRuntime: ReviewApplicationRuntime,
        applicationActivator: ReviewApplicationActivating,
        accessibility: ReviewDestinationAccessing,
        finalTextOutput: FinalTextOutput,
        accessibilityTrustProvider: AccessibilityTrustProviding? = nil,
        secureInputStateProvider: SecureInputStateProviding? = nil,
        frontmostProcessProvider: FrontmostProcessProviding? = nil
    ) {
        self.applicationRuntime = applicationRuntime
        self.applicationActivator = applicationActivator
        self.accessibility = accessibility
        self.finalTextOutput = finalTextOutput
        self.accessibilityTrustProvider = accessibilityTrustProvider
            ?? (accessibility as? AccessibilityTrustProviding)
            ?? SystemAccessibilityTrustProvider()
        let environment = finalTextOutput as? ReviewCurrentFocusEnvironmentProviding
        self.secureInputStateProvider = secureInputStateProvider
            ?? environment?.reviewSecureInputStateProvider
            ?? SystemSecureInputStateProvider()
        self.frontmostProcessProvider = frontmostProcessProvider
            ?? environment?.reviewFrontmostProcessProvider
            ?? ReviewRuntimeFrontmostProcessProvider(applicationRuntime: applicationRuntime)
    }

    convenience init() {
        let applicationRuntime = SystemReviewApplicationRuntime()
        self.init(
            applicationRuntime: applicationRuntime,
            applicationActivator: WorkspaceReviewApplicationActivator(
                applicationRuntime: applicationRuntime
            ),
            accessibility: MacAccessibilityClient(),
            finalTextOutput: SystemFinalTextOutput()
        )
    }

    func capture(generation: UInt64) -> ReviewDestinationCaptureResult {
        guard generation > 0,
              let application = applicationRuntime.frontmostIdentity(),
              hasCompleteApplicationIdentity(application),
              let runningApplication = applicationRuntime.identity(
                  for: application.processIdentifier
              ),
              runningApplication == application else {
            return .rejected(.destinationUnavailable)
        }

        let captureResult = accessibility.captureReviewCursorDestination(generation: generation)
        let binding: ReviewDestinationBinding
        switch captureResult {
        case .exact(let cursor):
            guard isValidCursorDestination(
                cursor,
                generation: generation,
                processIdentifier: application.processIdentifier
            ) else {
                return .rejected(.destinationUnavailable)
            }
            binding = .exactCursor(cursor)
        case .nonSecureCursorUnavailable:
            binding = .applicationCurrentFocus
        case .rejected(.secureInput):
            return .rejected(.secureInput)
        case .rejected(.accessibilityUnavailable):
            return .rejected(.destinationUnavailable)
        }

        guard applicationRuntime.identity(for: application.processIdentifier) == application,
              applicationRuntime.frontmostIdentity() == application else {
            return .rejected(.destinationUnavailable)
        }

        return .captured(
            ReviewDestinationToken(
                generation: generation,
                application: application,
                binding: binding,
                capturedSecurityState: .safe
            )
        )
    }

    func deliver(
        _ frozenText: String,
        to destination: ReviewDestinationToken
    ) async -> ReviewDeliveryResult {
        guard !Task.isCancelled else { return .cancelled }
        if let validationFailure = initialValidationFailure(
            frozenText,
            destination: destination
        ) {
            return validationFailure
        }

        let activation = await applicationActivator.activateAndWait(
            for: destination.application,
            timeoutNanoseconds: Self.activationTimeoutNanoseconds
        )
        guard !Task.isCancelled else { return .cancelled }
        guard activation == .activated else { return activationFailure(for: activation) }

        guard destinationIsCurrent(destination) else {
            return .identityChanged
        }

        let insertionResult: FinalTextInsertionResult
        switch destination.binding {
        case .exactCursor(let cursor):
            insertionResult = finalTextOutput.insertOnce(
                frozenText,
                destination: cursor,
                validateBeforeMutation: { [weak self] in
                    self?.validateExactBeforeMutation(destination) == .valid
                },
                validateAfterPosting: { [weak self] in
                    self?.validateExactAfterPosting(destination) == .valid
                }
            )
        case .applicationCurrentFocus:
            insertionResult = finalTextOutput.insertReviewAtCurrentFocusOnce(
                frozenText,
                processIdentifier: destination.application.processIdentifier,
                validateBeforeMutation: { [weak self] in
                    self?.validateApplicationCurrentFocusBeforeMutation(destination)
                        ?? .destinationInvalid
                },
                validateAfterPosting: { [weak self] in
                    self?.validateApplicationCurrentFocusAfterPosting(destination)
                        ?? .destinationInvalid
                }
            )
        }

        guard !Task.isCancelled else { return .cancelled }

        return reviewDeliveryResult(for: insertionResult)
    }

    private func destinationIsCurrent(_ destination: ReviewDestinationToken) -> Bool {
        guard destinationIsRunning(destination) else {
            return false
        }
        return applicationRuntime.frontmostIdentity() == destination.application
    }

    private func destinationIsRunning(_ destination: ReviewDestinationToken) -> Bool {
        guard applicationRuntime.identity(
            for: destination.application.processIdentifier
        ) == destination.application,
        hasCompleteApplicationIdentity(destination.application) else {
            return false
        }
        return true
    }

    private func initialValidationFailure(
        _ frozenText: String,
        destination: ReviewDestinationToken
    ) -> ReviewDeliveryResult? {
        guard !frozenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              TextInputSimulator.isSafeForReviewConfirmation(frozenText) else {
            return .unsafeText
        }
        guard destination.capturedSecurityState == .safe else {
            return .securityRejected
        }
        if case .applicationCurrentFocus = destination.binding,
           !accessibilityTrustProvider.isAccessibilityTrusted {
            return .securityRejected
        }
        guard reviewDestinationTokenIsValid(destination) else {
            return .destinationInvalid
        }
        guard destinationIsRunning(destination) else {
            return .identityChanged
        }
        return nil
    }

    private func activationFailure(for result: ReviewActivationResult) -> ReviewDeliveryResult {
        switch result {
        case .activated:
            return .activationFailed
        case .identityChanged:
            return .identityChanged
        case .cancelled:
            return .cancelled
        case .notRunning, .requestRejected, .timedOut:
            return .activationFailed
        }
    }

    private func validateExactBeforeMutation(
        _ destination: ReviewDestinationToken
    ) -> ReviewCurrentFocusValidation {
        guard !Task.isCancelled else { return .destinationInvalid }
        guard destinationIsCurrent(destination) else { return .identityChanged }
        guard case .exactCursor(let cursor) = destination.binding else {
            return .destinationInvalid
        }
        do {
            guard try accessibility.restoreAndValidateBeforeDelivery(cursor) else {
                return .destinationInvalid
            }
            return destinationIsCurrent(destination) ? .valid : .identityChanged
        } catch {
            return .destinationInvalid
        }
    }

    private func validateExactAfterPosting(
        _ destination: ReviewDestinationToken
    ) -> ReviewCurrentFocusValidation {
        guard !Task.isCancelled else { return .destinationInvalid }
        guard destinationIsCurrent(destination) else { return .identityChanged }
        guard case .exactCursor(let cursor) = destination.binding else {
            return .destinationInvalid
        }
        do {
            guard try accessibility.validateAfterDelivery(cursor) else {
                return .destinationInvalid
            }
            return destinationIsCurrent(destination) ? .valid : .identityChanged
        } catch {
            return .destinationInvalid
        }
    }

    private func validateApplicationCurrentFocusBeforeMutation(
        _ destination: ReviewDestinationToken
    ) -> ReviewCurrentFocusValidation {
        var result: ReviewCurrentFocusValidation = .valid
        for _ in 0 ..< 2 {
            let sample = applicationCurrentFocusSample(destination)
            if sample != .valid, result == .valid {
                result = sample
            }
        }
        return result
    }

    private func validateApplicationCurrentFocusAfterPosting(
        _ destination: ReviewDestinationToken
    ) -> ReviewCurrentFocusValidation {
        applicationCurrentFocusSample(destination)
    }

    private func applicationCurrentFocusSample(
        _ destination: ReviewDestinationToken
    ) -> ReviewCurrentFocusValidation {
        guard !Task.isCancelled,
              destination.application.processIdentifier > 0 else {
            return .destinationInvalid
        }

        // Keep this as one composite sample. The initial trust and Secure Input
        // reads must precede every destination read, and the final reads close
        // races where either permission changes while identities are loaded.
        let accessibilityTrustedAtStart = accessibilityTrustProvider.isAccessibilityTrusted
        let secureInputAtStart = secureInputStateProvider.isSecureInputEnabled()
        let rawFrontmostProcessIdentifier = frontmostProcessProvider.frontmostProcessIdentifier()
        let running = applicationRuntime.identity(
            for: destination.application.processIdentifier
        )
        let frontmost = applicationRuntime.frontmostIdentity()
        let secureInputAtEnd = secureInputStateProvider.isSecureInputEnabled()
        let accessibilityTrustedAtEnd = accessibilityTrustProvider.isAccessibilityTrusted

        guard accessibilityTrustedAtStart,
              accessibilityTrustedAtEnd,
              !secureInputAtStart,
              !secureInputAtEnd else {
            return .securityRejected
        }
        guard rawFrontmostProcessIdentifier == destination.application.processIdentifier else {
            return .destinationInvalid
        }
        guard let running,
              hasCompleteApplicationIdentity(running),
              running == destination.application else {
            return .identityChanged
        }
        guard let frontmost,
              hasCompleteApplicationIdentity(frontmost),
              frontmost == destination.application else {
            return .identityChanged
        }
        return .valid
    }

    private func reviewDestinationTokenIsValid(
        _ destination: ReviewDestinationToken
    ) -> Bool {
        guard destination.generation > 0,
              destination.capturedSecurityState == .safe,
              hasCompleteApplicationIdentity(destination.application) else {
            return false
        }
        switch destination.binding {
        case .exactCursor(let cursor):
            return isValidCursorDestination(
                cursor,
                generation: destination.generation,
                processIdentifier: destination.application.processIdentifier
            )
        case .applicationCurrentFocus:
            return true
        }
    }

    private func isValidCursorDestination(
        _ cursor: CursorDestinationToken,
        generation: UInt64,
        processIdentifier: pid_t
    ) -> Bool {
        cursor.generation == generation &&
            cursor.processIdentifier == processIdentifier &&
            cursor.processIdentifier > 0 &&
            cursor.originalSelection.location >= 0 &&
            cursor.originalSelection.length >= 0 &&
            cursor.originalSelection.endLocation != nil
    }

    private func reviewDeliveryResult(
        for insertionResult: FinalTextInsertionResult
    ) -> ReviewDeliveryResult {
        switch insertionResult {
        case .inserted:
            return .inserted
        case .securityRejected:
            return .securityRejected
        case .identityChanged:
            return .identityChanged
        case .destinationInvalid:
            return .destinationInvalid
        case .deliveryUncertain:
            return .deliveryUncertain
        case .deliveryFailed:
            return .deliveryFailed
        }
    }
}
