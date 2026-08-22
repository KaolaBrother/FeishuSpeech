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
    func capture(generation: UInt64) throws -> ReviewDestinationToken
    func deliver(
        _ frozenText: String,
        to destination: ReviewDestinationToken
    ) async -> ReviewDeliveryResult
    func copyForManualRecovery(_ frozenText: String)
}

private enum ReviewDestinationDeliveryError: Error {
    case destinationUnavailable
    case identityChanged
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

    init(
        applicationRuntime: ReviewApplicationRuntime,
        applicationActivator: ReviewApplicationActivating,
        accessibility: ReviewDestinationAccessing,
        finalTextOutput: FinalTextOutput
    ) {
        self.applicationRuntime = applicationRuntime
        self.applicationActivator = applicationActivator
        self.accessibility = accessibility
        self.finalTextOutput = finalTextOutput
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

    func capture(generation: UInt64) throws -> ReviewDestinationToken {
        let cursor = try accessibility.captureReviewCursorDestination(generation: generation)
        guard cursor.generation == generation,
              let application = applicationRuntime.identity(for: cursor.processIdentifier),
              application.processIdentifier == cursor.processIdentifier,
              hasCompleteApplicationIdentity(application) else {
            throw ReviewDestinationDeliveryError.destinationUnavailable
        }
        guard applicationRuntime.frontmostIdentity() == application else {
            throw ReviewDestinationDeliveryError.identityChanged
        }
        return ReviewDestinationToken(
            cursor: cursor,
            application: application,
            capturedSecurityState: .safe
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

        let insertionResult = finalTextOutput.insertOnce(
            frozenText,
            destination: destination.cursor,
            validateBeforeMutation: { [weak self] in
                self?.validateBeforeMutation(destination) ?? false
            },
            validateAfterPosting: { [weak self] in
                self?.validateAfterPosting(destination) ?? false
            }
        )

        return reviewDeliveryResult(for: insertionResult)
    }

    func copyForManualRecovery(_ frozenText: String) {
        finalTextOutput.copyForManualRecovery(frozenText)
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
        guard destination.application.processIdentifier == destination.cursor.processIdentifier,
              destinationIsRunning(destination) else {
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

    private func validateBeforeMutation(_ destination: ReviewDestinationToken) -> Bool {
        guard !Task.isCancelled, destinationIsCurrent(destination) else { return false }
        do {
            guard try accessibility.restoreAndValidateBeforeDelivery(destination.cursor) else {
                return false
            }
            return destinationIsCurrent(destination)
        } catch {
            return false
        }
    }

    private func validateAfterPosting(_ destination: ReviewDestinationToken) -> Bool {
        guard !Task.isCancelled, destinationIsCurrent(destination) else { return false }
        do {
            guard try accessibility.validateAfterDelivery(destination.cursor) else {
                return false
            }
            return destinationIsCurrent(destination)
        } catch {
            return false
        }
    }

    private func reviewDeliveryResult(
        for insertionResult: FinalTextInsertionResult
    ) -> ReviewDeliveryResult {
        switch insertionResult {
        case .inserted:
            return .inserted
        case .securityRejected:
            return .securityRejected
        case .destinationInvalid:
            return .destinationInvalid
        case .deliveryUncertain:
            return .deliveryUncertain
        case .deliveryFailed:
            return .deliveryFailed
        }
    }
}
