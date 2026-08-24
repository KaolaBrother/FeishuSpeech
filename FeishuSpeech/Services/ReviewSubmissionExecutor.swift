import AppKit
import ApplicationServices
import Foundation
import os.log

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "ReviewSubmissionExecutor"
)

private let reviewSubmissionDeadlineNanoseconds: UInt64 = 2_000_000_000
private let reviewModifierStabilizationNanoseconds: UInt64 = 500_000_000
private let reviewRelevantModifierFlags: CGEventFlags = [
    .maskCommand,
    .maskShift,
    .maskControl,
    .maskAlternate,
    .maskSecondaryFn,
    .maskAlphaShift
]

final class ReviewSubmissionValueStore: @unchecked Sendable {
    let lock = NSLock()
    var records: [ReviewSubmissionAttemptHandle: ReservedAttemptControlRecord] = [:]
    var activeHandle: ReviewSubmissionAttemptHandle?
    var combinedEpoch: UInt64 = 0
}

struct ReservedAttemptControlRecord: Equatable, Sendable {
    let handle: ReviewSubmissionAttemptHandle
    let request: ReviewSubmissionRequestDescriptor
    let absolutePreBoundaryDeadline: UInt64
    var phase: ReviewSubmissionPhase
    var cancellationRequested: Bool
}

struct ReviewSubmissionClaim: Equatable, Sendable {
    let request: ReviewSubmissionRequestDescriptor
    let deadline: UInt64
    let expectedCombinedEpoch: UInt64
    let expectedGlobalCombinedEpoch: UInt64
}

struct ReviewCommitGateInput: Equatable, Sendable {
    let expectedCombinedEpoch: UInt64
    let expectedGlobalCombinedEpoch: UInt64
    let liveGlobalCombinedEpoch: UInt64
    let deadline: UInt64
    let now: UInt64
}

/// The control plane is deliberately value-only.  Its queue never carries an
/// AXUIElement, CGEvent, event source, prepared pair, or posting closure as
/// part of an attempt record.  The optional start sink carries only an opaque
/// handle to the separate raw executor queue.
final class ReviewSubmissionControlPlane: @unchecked Sendable {
    let instanceNonce: UInt64
    let valueStore: ReviewSubmissionValueStore

    private let queue: DispatchQueue
    private var eventHandler: (@Sendable (ReviewSubmissionControlEvent) -> Void)?
    private var startHandler: (@Sendable (ReviewSubmissionAttemptHandle) -> Void)?

    init(
        instanceNonce: UInt64 = UInt64.random(in: 1 ... UInt64.max),
        eventHandler: (@Sendable (ReviewSubmissionControlEvent) -> Void)? = nil
    ) {
        self.instanceNonce = instanceNonce == 0 ? 1 : instanceNonce
        self.valueStore = ReviewSubmissionValueStore()
        self.valueStore.combinedEpoch = CurrentFocusCombinedInterferenceEpoch.shared.capture()
        self.eventHandler = eventHandler
        self.queue = DispatchQueue(
            label: "com.feishuspeech.review-submission-control",
            qos: .userInitiated
        )
    }

    /// Installs the raw queue bridge after both confinement domains exist.  It
    /// is not stored in any value record and receives only an opaque handle.
    func attachStartHandler(
        _ handler: @escaping @Sendable (ReviewSubmissionAttemptHandle) -> Void
    ) {
        queue.async { [weak self] in
            self?.startHandler = handler
        }
    }

    /// Installs the typed event sink on the control queue.  The asynchronous
    /// installation is FIFO with every later admission/start/cancellation
    /// command, so production construction never captures a partially
    /// initialized facade and no event can overtake the sink installation.
    func attachEventHandler(
        _ handler: @escaping @Sendable (ReviewSubmissionControlEvent) -> Void
    ) {
        queue.async { [weak self] in
            self?.eventHandler = handler
        }
    }

    /// This is the only operation which MainActor invokes for admission.  It
    /// submits FIFO work and returns without waiting for the control queue.
    func enqueueAdmission(_ envelope: ReviewSubmissionAdmissionEnvelope) {
        queue.async { [weak self] in
            self?.processAdmission(envelope)
        }
    }

    func enqueueStart(_ handle: ReviewSubmissionAttemptHandle) {
        queue.async { [weak self] in
            self?.processStart(handle)
        }
    }

    func enqueueCancellation(_ handle: ReviewSubmissionAttemptHandle) {
        queue.async { [weak self] in
            self?.processCancellation(handle)
        }
    }

    func enqueueRawCleanupComplete(
        _ cleanup: TerminalCleanupValue
    ) {
        queue.async { [weak self] in
            self?.processRawCleanup(cleanup)
        }
    }

    private func processAdmission(_ envelope: ReviewSubmissionAdmissionEnvelope) {
        let now = DispatchTime.now().uptimeNanoseconds
        var event: ReviewSubmissionControlEvent?
        valueStore.lock.lock()
        defer {
            valueStore.lock.unlock()
            if let event { eventHandler?(event) }
        }

        let handle = envelope.handle
        guard handle.instanceNonce == instanceNonce,
              handle.issuedAttemptID > 0 else {
            event = .admissionRejected(handle, .invalidHandle)
            return
        }
        guard envelope.request.generation > 0,
              envelope.request.attemptOrdinal > 0,
              !envelope.request.frozenDraft.isEmpty,
              envelope.request.frozenDraft.utf16.count
                <= TextInputSimulator.reviewMaximumUTF16CodeUnits,
              TextInputSimulator.isSafeForReviewConfirmation(envelope.request.frozenDraft) else {
            event = .admissionRejected(handle, .invalidRequest)
            return
        }
        guard now < envelope.absolutePreBoundaryDeadline else {
            event = .terminal(handle, .notStarted(.deadline))
            return
        }
        guard valueStore.activeHandle == nil else {
            event = .admissionRejected(handle, .duplicateActiveAttempt)
            return
        }
        guard valueStore.records[handle] == nil else {
            event = .admissionRejected(handle, .duplicateActiveAttempt)
            return
        }

        valueStore.records[handle] = ReservedAttemptControlRecord(
            handle: handle,
            request: envelope.request,
            absolutePreBoundaryDeadline: envelope.absolutePreBoundaryDeadline,
            phase: .admitted,
            cancellationRequested: false
        )
        valueStore.activeHandle = handle
        event = .admissionAccepted(handle)
    }

    private func processStart(_ handle: ReviewSubmissionAttemptHandle) {
        var shouldStart = false
        var terminalEvent: ReviewSubmissionControlEvent?
        valueStore.lock.lock()
        if var record = valueStore.records[handle],
           record.handle.instanceNonce == instanceNonce,
           record.phase == .admitted,
           !record.cancellationRequested {
            if DispatchTime.now().uptimeNanoseconds < record.absolutePreBoundaryDeadline {
                record.phase = .startQueued
                valueStore.records[handle] = record
                shouldStart = true
            } else {
                record.phase = .terminal
                valueStore.records.removeValue(forKey: handle)
                if valueStore.activeHandle == handle {
                    valueStore.activeHandle = nil
                }
                terminalEvent = .terminal(handle, .notStarted(.deadline))
            }
        }
        valueStore.lock.unlock()
        if let terminalEvent {
            eventHandler?(terminalEvent)
        }
        if shouldStart {
            startHandler?(handle)
        }
    }

    private func processCancellation(_ handle: ReviewSubmissionAttemptHandle) {
        var result: CancellationSignalResult = .notCurrent
        var terminalEvent: ReviewSubmissionControlEvent?

        valueStore.lock.lock()
        if var record = valueStore.records[handle] {
            switch record.phase {
            case .admitted, .startQueued:
                record.cancellationRequested = true
                record.phase = .terminal
                valueStore.records[handle] = record
                valueStore.records.removeValue(forKey: handle)
                if valueStore.activeHandle == handle { valueStore.activeHandle = nil }
                result = .latched
                terminalEvent = .terminal(handle, .notStarted(.cancellation))
            case .claimed, .preparing, .committing:
                record.cancellationRequested = true
                valueStore.records[handle] = record
                result = .latched
            case .boundaryCrossed:
                record.cancellationRequested = true
                valueStore.records[handle] = record
                result = .observedAfterBoundary
            case .terminalizing, .terminal:
                result = .notCurrent
            }
        }
        valueStore.lock.unlock()

        eventHandler?(.cancellationResolved(handle, result))
        if let terminalEvent { eventHandler?(terminalEvent) }
    }

    private func processRawCleanup(_ cleanup: TerminalCleanupValue) {
        var shouldEmit = false
        var receipt = cleanup.receipt
        valueStore.lock.lock()
        if var record = valueStore.records[cleanup.handle],
           record.phase != .terminal {
            if case .submittedUnverified(let observation) = cleanup.receipt,
               record.cancellationRequested {
                receipt = .submittedUnverified(
                    ReviewPostBoundaryObservation(
                        mandatoryKeyUpAttempted: observation.mandatoryKeyUpAttempted,
                        cancellationObservedAfterDown: true,
                        postflightStable: false
                    )
                )
            }
            record.phase = .terminal
            valueStore.records[cleanup.handle] = record
            valueStore.records.removeValue(forKey: cleanup.handle)
            if valueStore.activeHandle == cleanup.handle { valueStore.activeHandle = nil }
            shouldEmit = true
        }
        valueStore.lock.unlock()
        if shouldEmit {
            eventHandler?(.terminal(cleanup.handle, receipt))
        }
    }

    // MARK: Raw-executor value operations

    func registerTargetEpoch(_ epoch: UInt64) {
        valueStore.lock.lock()
        valueStore.combinedEpoch = epoch
        valueStore.lock.unlock()
    }

    func refreshCombinedEpochBaseline(
        _ handle: ReviewSubmissionAttemptHandle,
        epoch: UInt64
    ) -> Bool {
        valueStore.lock.lock()
        defer { valueStore.lock.unlock() }
        guard let record = valueStore.records[handle],
              record.phase == .claimed,
              !record.cancellationRequested else {
            return false
        }
        valueStore.combinedEpoch = epoch
        return true
    }

    func advanceCombinedEpoch() {
        valueStore.lock.lock()
        valueStore.combinedEpoch &+= 1
        valueStore.lock.unlock()
    }

    func claim(
        _ handle: ReviewSubmissionAttemptHandle
    ) -> ReviewSubmissionClaim? {
        let expectedGlobalCombinedEpoch = CurrentFocusCombinedInterferenceEpoch.shared.capture()
        valueStore.lock.lock()
        defer { valueStore.lock.unlock() }
        guard var record = valueStore.records[handle],
              record.phase == .startQueued,
              !record.cancellationRequested else {
            return nil
        }
        record.phase = .claimed
        valueStore.records[handle] = record
        valueStore.combinedEpoch = expectedGlobalCombinedEpoch
        return ReviewSubmissionClaim(
            request: record.request,
            deadline: record.absolutePreBoundaryDeadline,
            expectedCombinedEpoch: valueStore.combinedEpoch,
            expectedGlobalCombinedEpoch: expectedGlobalCombinedEpoch
        )
    }

    func updatePhase(
        _ phase: ReviewSubmissionPhase,
        for handle: ReviewSubmissionAttemptHandle
    ) -> Bool {
        valueStore.lock.lock()
        defer { valueStore.lock.unlock() }
        guard var record = valueStore.records[handle], record.phase != .terminal else {
            return false
        }
        record.phase = phase
        valueStore.records[handle] = record
        return true
    }

    func beginTerminalizing(
        _ handle: ReviewSubmissionAttemptHandle,
        failure: ReviewPreBoundaryFailure
    ) -> ReviewPreBoundaryFailure? {
        valueStore.lock.lock()
        defer { valueStore.lock.unlock() }
        guard var record = valueStore.records[handle],
              record.phase != .boundaryCrossed,
              record.phase != .terminal,
              record.phase != .terminalizing else {
            return nil
        }
        let effectiveFailure = record.cancellationRequested ? .cancellation : failure
        record.phase = .terminalizing
        valueStore.records[handle] = record
        return effectiveFailure
    }

    /// The caller must already own `valueStore.lock`.  Keeping this check as
    /// direct field access is what prevents a nested epoch getter or callback
    /// from re-entering the non-recursive final gate.
    func commitMayBeginLocked(
        _ handle: ReviewSubmissionAttemptHandle,
        input: ReviewCommitGateInput
    ) -> Bool {
        guard let record = valueStore.records[handle],
              record.phase == .preparing,
              !record.cancellationRequested,
              input.now < input.deadline,
              record.absolutePreBoundaryDeadline == input.deadline,
              valueStore.combinedEpoch == input.expectedCombinedEpoch,
              input.liveGlobalCombinedEpoch == input.expectedGlobalCombinedEpoch else {
            return false
        }
        return true
    }

    func markCommittingLocked(_ handle: ReviewSubmissionAttemptHandle) {
        guard var record = valueStore.records[handle] else { return }
        record.phase = .committing
        valueStore.records[handle] = record
    }

    func markBoundaryCrossedLocked(_ handle: ReviewSubmissionAttemptHandle) {
        guard var record = valueStore.records[handle] else { return }
        record.phase = .boundaryCrossed
        valueStore.records[handle] = record
    }

    func cancellationRequestedLocked(_ handle: ReviewSubmissionAttemptHandle) -> Bool {
        valueStore.records[handle]?.cancellationRequested ?? true
    }

    func cancellationRequested(_ handle: ReviewSubmissionAttemptHandle) -> Bool {
        valueStore.lock.lock()
        defer { valueStore.lock.unlock() }
        return valueStore.records[handle]?.cancellationRequested ?? true
    }
}

final class ReviewSubmissionPreparedUnicodePair {
    let utf16: [UInt16]
    let targetProcessIdentifier: pid_t
    let sourceProcessIdentifier: pid_t
    let userData: Int64
    let flags: CGEventFlags

    fileprivate let keyDown: CGEvent?
    fileprivate let keyUp: CGEvent?

    init(
        utf16: [UInt16],
        targetProcessIdentifier: pid_t,
        sourceProcessIdentifier: pid_t,
        userData: Int64,
        flags: CGEventFlags,
        keyDown: CGEvent?,
        keyUp: CGEvent?
    ) {
        self.utf16 = utf16
        self.targetProcessIdentifier = targetProcessIdentifier
        self.sourceProcessIdentifier = sourceProcessIdentifier
        self.userData = userData
        self.flags = flags
        self.keyDown = keyDown
        self.keyUp = keyUp
    }
}

protocol ReviewSubmissionEventBackend: AnyObject {
    func preparePair(
        utf16: [UInt16],
        targetProcessIdentifier: pid_t
    ) -> ReviewSubmissionPreparedUnicodePair?
    func postDown(_ pair: ReviewSubmissionPreparedUnicodePair)
    func postUp(_ pair: ReviewSubmissionPreparedUnicodePair)
    func discardPair(_ pair: ReviewSubmissionPreparedUnicodePair)
}

extension ReviewSubmissionEventBackend {
    /// A prepared pair is executor-confined.  Backends may observe explicit
    /// pre-boundary discard for deterministic tests; production has no
    /// external resource to release beyond dropping this value.
    func discardPair(_: ReviewSubmissionPreparedUnicodePair) {}
}

final class SystemReviewSubmissionEventBackend: ReviewSubmissionEventBackend {
    func preparePair(
        utf16: [UInt16],
        targetProcessIdentifier: pid_t
    ) -> ReviewSubmissionPreparedUnicodePair? {
        guard targetProcessIdentifier > 0,
              utf16.count <= TextInputSimulator.reviewMaximumUTF16CodeUnits,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 0,
                  keyDown: true
              ),
              let up = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: 0,
                  keyDown: false
              ) else {
            return nil
        }

        let tag = FeishuSpeechSyntheticEventTag.value
        let sourcePID = getpid()
        for event in [down, up] {
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: tag)
            event.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(sourcePID))
            event.keyboardSetUnicodeString(
                stringLength: utf16.count,
                unicodeString: utf16
            )
        }

        // Read back every field that is available from CoreGraphics before a
        // permit can reach the post gate.  The target PID is kept as an exact
        // immutable pair field and is supplied to both post calls below.
        guard down.flags.isEmpty,
              up.flags.isEmpty,
              unicodeString(from: down) == utf16,
              unicodeString(from: up) == utf16,
              down.getIntegerValueField(.eventSourceUserData) == tag,
              up.getIntegerValueField(.eventSourceUserData) == tag,
              down.getIntegerValueField(.eventSourceUnixProcessID) == Int64(sourcePID),
              up.getIntegerValueField(.eventSourceUnixProcessID) == Int64(sourcePID) else {
            return nil
        }
        return ReviewSubmissionPreparedUnicodePair(
            utf16: utf16,
            targetProcessIdentifier: targetProcessIdentifier,
            sourceProcessIdentifier: sourcePID,
            userData: tag,
            flags: [],
            keyDown: down,
            keyUp: up
        )
    }

    func postDown(_ pair: ReviewSubmissionPreparedUnicodePair) {
        pair.keyDown?.postToPid(pair.targetProcessIdentifier)
    }

    func postUp(_ pair: ReviewSubmissionPreparedUnicodePair) {
        pair.keyUp?.postToPid(pair.targetProcessIdentifier)
    }

    private func unicodeString(from event: CGEvent) -> [UInt16] {
        var actualLength = 0
        var buffer = [UniChar](
            repeating: 0,
            count: max(1, TextInputSimulator.reviewMaximumUTF16CodeUnits)
        )
        buffer.withUnsafeMutableBufferPointer { buffer in
            event.keyboardGetUnicodeString(
                maxStringLength: buffer.count,
                actualStringLength: &actualLength,
                unicodeString: buffer.baseAddress
            )
        }
        guard actualLength >= 0,
              actualLength <= buffer.count else {
            return []
        }
        return Array(buffer.prefix(actualLength))
    }
}

final class ReviewUnicodeCommitter: @unchecked Sendable {
    // A backend is retained only for deterministic test seams. Production
    // construction uses the concrete CoreGraphics path below, so the final
    // gate does not perform protocol dispatch for its two direct posts.
    private let injectedBackend: ReviewSubmissionEventBackend?

    init(backend: ReviewSubmissionEventBackend? = nil) {
        self.injectedBackend = backend
    }

    func prepare(
        _ frozenDraft: String,
        fixedProcessIdentifier: pid_t
    ) -> Result<ReviewSubmissionPreparedUnicodePair, ReviewPreBoundaryFailure> {
        prepare(
            frozenDraft,
            fixedProcessIdentifier: fixedProcessIdentifier,
            absoluteDeadline: UInt64.max
        )
    }

    func prepare(
        _ frozenDraft: String,
        fixedProcessIdentifier: pid_t,
        absoluteDeadline: UInt64
    ) -> Result<ReviewSubmissionPreparedUnicodePair, ReviewPreBoundaryFailure> {
        guard DispatchTime.now().uptimeNanoseconds < absoluteDeadline else {
            return .failure(.deadline)
        }
        guard fixedProcessIdentifier > 0,
              !frozenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              TextInputSimulator.isSafeForReviewConfirmation(frozenDraft) else {
            return .failure(.constructionFailure)
        }
        let utf16 = Array(frozenDraft.utf16)
        guard utf16.count <= TextInputSimulator.reviewMaximumUTF16CodeUnits else {
            return .failure(.constructionFailure)
        }
        let pair = injectedBackend?.preparePair(
            utf16: utf16,
            targetProcessIdentifier: fixedProcessIdentifier
        ) ?? SystemReviewSubmissionEventBackend().preparePair(
            utf16: utf16,
            targetProcessIdentifier: fixedProcessIdentifier
        )
        guard let pair else {
            return .failure(.constructionFailure)
        }
        guard DispatchTime.now().uptimeNanoseconds < absoluteDeadline else {
            return .failure(.deadline)
        }
        guard pair.utf16 == utf16,
              pair.targetProcessIdentifier == fixedProcessIdentifier,
              pair.flags.isEmpty,
              pair.userData == FeishuSpeechSyntheticEventTag.value,
              pair.sourceProcessIdentifier == getpid() else {
            return .failure(.readbackFailure)
        }
        return .success(pair)
    }

    func prepare(
        _ frozenDraft: String,
        fixedProcessIdentifier: pid_t,
        deadline: UInt64
    ) -> Result<ReviewSubmissionPreparedUnicodePair, ReviewPreBoundaryFailure> {
        prepare(
            frozenDraft,
            fixedProcessIdentifier: fixedProcessIdentifier,
            absoluteDeadline: deadline
        )
    }

    func postDown(_ pair: ReviewSubmissionPreparedUnicodePair) {
        if let injectedBackend {
            injectedBackend.postDown(pair)
        } else {
            pair.keyDown?.postToPid(pair.targetProcessIdentifier)
        }
    }

    func postUp(_ pair: ReviewSubmissionPreparedUnicodePair) {
        if let injectedBackend {
            injectedBackend.postUp(pair)
        } else {
            pair.keyUp?.postToPid(pair.targetProcessIdentifier)
        }
    }

    func discard(_ pair: ReviewSubmissionPreparedUnicodePair) {
        injectedBackend?.discardPair(pair)
    }
}

/// Raw submission state is confined to this serial queue.  Only a value
/// handle and a value receipt cross the boundary.  The executor deliberately
/// does not activate or retarget an application; the target registry is fixed
/// by the capture descriptor supplied by the caller.
final class ReviewSubmissionExecutor: @unchecked Sendable {
    private struct RawAttemptPreparation {
        let pair: ReviewSubmissionPreparedUnicodePair
        let expectedEpoch: UInt64
        let expectedGlobalEpoch: UInt64
    }

    private struct CommitContext {
        let handle: ReviewSubmissionAttemptHandle
        let targetID: CapturedReviewTargetID
        let expectedEpoch: UInt64
        let expectedGlobalEpoch: UInt64
        let deadline: UInt64
    }

    /// Ephemeral evidence for one reservation iteration.  It is never stored
    /// in the value control plane or carried across a retry.
    private struct FinalBindingProof {}

    private let queue: DispatchQueue
    private let controlPlane: ReviewSubmissionControlPlane
    private let committer: ReviewUnicodeCommitter
    private let rawAccessibility: ReviewSubmissionRawAccessibilityRuntime?
    private var targetRegistry: [CapturedReviewTargetID: CapturedReviewTargetDescriptor] = [:]
    private var rawTargetRegistry: [CapturedReviewTargetID: ReviewSubmissionRawTargetState] = [:]

    init(
        controlPlane: ReviewSubmissionControlPlane,
        committer: ReviewUnicodeCommitter = ReviewUnicodeCommitter(),
        rawAccessibility: ReviewSubmissionRawAccessibilityRuntime? = nil
    ) {
        self.controlPlane = controlPlane
        self.committer = committer
        self.rawAccessibility = rawAccessibility
        self.queue = DispatchQueue(
            label: "com.feishuspeech.review-submission-executor",
            qos: .userInitiated
        )
        controlPlane.attachStartHandler { [weak self] handle in
            self?.enqueueRawAttempt(handle)
        }
    }

    func registerCapturedTarget(_ descriptor: CapturedReviewTargetDescriptor) {
        queue.async { [weak self] in
            self?.targetRegistry[descriptor.targetID] = descriptor
        }
    }

    /// Capture runs on the raw executor and returns only a Sendable
    /// descriptor.  The AX objects are retained in the executor's private
    /// registry and are never exposed to the caller.
    func capture(
        _ request: ReviewTargetCaptureRequestDescriptor,
        completion: @escaping @Sendable (Result<CapturedReviewTargetDescriptor, ReviewPreBoundaryFailure>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self, let rawAccessibility = self.rawAccessibility else {
                completion(.failure(.accessibilityFailure))
                return
            }
            switch rawAccessibility.capture(request) {
            case .failure(let failure):
                completion(.failure(failure))
            case .success(let state):
                self.targetRegistry[state.descriptor.targetID] = state.descriptor
                self.rawTargetRegistry[state.descriptor.targetID] = state
                completion(.success(state.descriptor))
            }
        }
    }

    func release(_ targetID: CapturedReviewTargetID) {
        queue.async { [weak self] in
            self?.targetRegistry.removeValue(forKey: targetID)
            self?.rawTargetRegistry.removeValue(forKey: targetID)
        }
    }

    func advanceCombinedEpoch() {
        CurrentFocusCombinedInterferenceEpoch.shared.advance()
        controlPlane.advanceCombinedEpoch()
    }

    private func stabilizeRelevantModifiers(
        for handle: ReviewSubmissionAttemptHandle,
        deadline: UInt64
    ) -> ReviewPreBoundaryFailure? {
        let now = DispatchTime.now().uptimeNanoseconds
        let stabilizationDeadline = min(
            deadline,
            now.addingReportingOverflow(reviewModifierStabilizationNanoseconds).overflow
                ? UInt64.max
                : now + reviewModifierStabilizationNanoseconds
        )
        var consecutiveEmptySamples = 0
        while DispatchTime.now().uptimeNanoseconds < stabilizationDeadline {
            if controlPlane.cancellationRequested(handle) {
                return .cancellation
            }
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.isDisjoint(with: reviewRelevantModifierFlags) {
                consecutiveEmptySamples += 1
                if consecutiveEmptySamples >= 2 {
                    return nil
                }
            } else {
                consecutiveEmptySamples = 0
            }
            if controlPlane.cancellationRequested(handle) {
                return .cancellation
            }
            Thread.sleep(forTimeInterval: 0.002)
            if controlPlane.cancellationRequested(handle) {
                return .cancellation
            }
        }
        return controlPlane.cancellationRequested(handle) ? .cancellation : .modifierInstability
    }

    private func finalModifierGate(
        for handle: ReviewSubmissionAttemptHandle
    ) -> ReviewPreBoundaryFailure? {
        if controlPlane.cancellationRequested(handle) {
            return .cancellation
        }
        let finalFlags = CGEventSource.flagsState(.combinedSessionState)
        guard finalFlags.isDisjoint(with: reviewRelevantModifierFlags) else {
            return .modifierInstability
        }
        return controlPlane.cancellationRequested(handle) ? .cancellation : nil
    }

    private func enqueueRawAttempt(_ handle: ReviewSubmissionAttemptHandle) {
        queue.async { [weak self] in
            self?.performRawAttempt(handle)
        }
    }

    private func performRawAttempt(_ handle: ReviewSubmissionAttemptHandle) {
        guard let claim = controlPlane.claim(handle) else { return }
        guard let target = targetRegistry[claim.request.capturedTargetID],
              let rawTarget = rawTargetRegistry[claim.request.capturedTargetID] else {
            terminalize(handle, failure: .targetIdentityChanged)
            return
        }
        guard let preparation = prepareRawAttempt(
            handle,
            claim: claim,
            target: target,
            rawTarget: rawTarget
        ) else {
            return
        }
        let receipt = commit(
            preparation.pair,
            context: CommitContext(
                handle: handle,
                targetID: claim.request.capturedTargetID,
                expectedEpoch: preparation.expectedEpoch,
                expectedGlobalEpoch: preparation.expectedGlobalEpoch,
                deadline: claim.deadline
            )
        )
        if case .notStarted(let failure) = receipt {
            terminalize(handle, failure: failure)
            return
        }
        controlPlane.enqueueRawCleanupComplete(
            TerminalCleanupValue(handle: handle, receipt: receipt)
        )
    }

    private func prepareRawAttempt(
        _ handle: ReviewSubmissionAttemptHandle,
        claim: ReviewSubmissionClaim,
        target: CapturedReviewTargetDescriptor,
        rawTarget: ReviewSubmissionRawTargetState
    ) -> RawAttemptPreparation? {
        let request = claim.request
        let deadline = claim.deadline
        if let failure = targetPreflightFailure(
            rawTarget,
            request: request,
            deadline: deadline
        ) {
            terminalize(handle, failure: failure)
            return nil
        }
        if let failure = stabilizeRelevantModifiers(for: handle, deadline: deadline) {
            terminalize(handle, failure: failure)
            return nil
        }
        if let failure = validateRawTarget(
            request.capturedTargetID,
            handle: handle,
            deadline: deadline
        ) {
            terminalize(handle, failure: failure)
            return nil
        }
        guard let baseline = establishBaseline(
            handle,
            expectedEpoch: claim.expectedGlobalCombinedEpoch
        ) else {
            terminalize(handle, failure: .inputDrift)
            return nil
        }
        guard controlPlane.updatePhase(.preparing, for: handle) else { return nil }
        if let failure = validateRawTarget(
            request.capturedTargetID,
            handle: handle,
            deadline: deadline
        ) {
            terminalize(handle, failure: failure)
            return nil
        }
        if let failure = prePairGate(
            handle,
            expectedEpoch: baseline
        ) {
            terminalize(handle, failure: failure)
            return nil
        }
        guard let pair = preparedPair(
            request: request,
            target: target,
            deadline: deadline
        ) else {
            terminalize(handle, failure: pairFailure(for: handle, deadline: deadline))
            return nil
        }
        return RawAttemptPreparation(
            pair: pair,
            expectedEpoch: baseline,
            expectedGlobalEpoch: baseline
        )
    }

    private func prePairGate(
        _ handle: ReviewSubmissionAttemptHandle,
        expectedEpoch: UInt64
    ) -> ReviewPreBoundaryFailure? {
        if controlPlane.cancellationRequested(handle) {
            return .cancellation
        }
        let snapshot = CurrentFocusCombinedInterferenceEpoch.shared.captureSnapshot()
        guard snapshot.isStable(expectedValue: expectedEpoch) else {
            return controlPlane.cancellationRequested(handle) ? .cancellation : .inputDrift
        }
        let storeStable = controlPlane.valueStore.lockedValue {
            controlPlane.valueStore.combinedEpoch == expectedEpoch
        }
        guard storeStable else {
            return controlPlane.cancellationRequested(handle) ? .cancellation : .inputDrift
        }
        return controlPlane.cancellationRequested(handle) ? .cancellation : nil
    }

    private func targetPreflightFailure(
        _ target: ReviewSubmissionRawTargetState,
        request: ReviewSubmissionRequestDescriptor,
        deadline: UInt64
    ) -> ReviewPreBoundaryFailure? {
        guard target.descriptor.generation == request.generation,
              target.descriptor.securityAtCapture == .safe,
              DispatchTime.now().uptimeNanoseconds < deadline else {
            return target.descriptor.generation == request.generation
                ? .deadline
                : .targetIdentityChanged
        }
        guard target.descriptor.binding != .exactCursor
            || (target.focusedElement != nil && target.originalSelection != nil) else {
            return .securityRejected
        }
        return nil
    }

    private func validateRawTarget(
        _ targetID: CapturedReviewTargetID,
        handle: ReviewSubmissionAttemptHandle,
        deadline: UInt64
    ) -> ReviewPreBoundaryFailure? {
        guard let rawAccessibility,
              let rawTarget = rawTargetRegistry[targetID] else {
            return nil
        }
        let controlPlane = self.controlPlane
        return rawAccessibility.validate(
            rawTarget,
            deadline: deadline,
            cancellationProbe: { [controlPlane, handle] in
                controlPlane.cancellationRequested(handle)
            }
        )
    }

    private func establishBaseline(
        _ handle: ReviewSubmissionAttemptHandle,
        expectedEpoch: UInt64
    ) -> UInt64? {
        let snapshot = CurrentFocusCombinedInterferenceEpoch.shared.captureSnapshot()
        guard snapshot.isStable(expectedValue: expectedEpoch),
              controlPlane.refreshCombinedEpochBaseline(
                  handle,
                  epoch: snapshot.rawValue
              ) else {
            return nil
        }
        return snapshot.rawValue
    }

    private func pairFailure(
        for handle: ReviewSubmissionAttemptHandle,
        deadline: UInt64
    ) -> ReviewPreBoundaryFailure {
        if DispatchTime.now().uptimeNanoseconds >= deadline {
            return .deadline
        }
        return controlPlane.cancellationRequested(handle)
            ? .cancellation
            : .constructionFailure
    }

    private func preparedPair(
        request: ReviewSubmissionRequestDescriptor,
        target: CapturedReviewTargetDescriptor,
        deadline: UInt64
    ) -> ReviewSubmissionPreparedUnicodePair? {
        guard DispatchTime.now().uptimeNanoseconds < deadline else { return nil }
        // Application-bound fallback still uses the one captured PID.  This
        // executor has no ambient frontmost lookup and cannot retarget.
        let result = committer.prepare(
            request.frozenDraft,
            fixedProcessIdentifier: target.application.processIdentifier,
            absoluteDeadline: deadline
        )
        guard case .success(let pair) = result else { return nil }
        guard DispatchTime.now().uptimeNanoseconds < deadline else {
            committer.discard(pair)
            return nil
        }
        return pair
    }

    private func commit(
        _ pair: ReviewSubmissionPreparedUnicodePair,
        context: CommitContext
    ) -> ReviewCommitReceipt {
        let handle = context.handle
        let targetID = context.targetID
        let expectedEpoch = context.expectedEpoch
        let expectedGlobalEpoch = context.expectedGlobalEpoch
        let deadline = context.deadline
        while DispatchTime.now().uptimeNanoseconds < deadline {
            switch validateForImmediateCommit(
                targetID,
                handle: handle,
                deadline: deadline
            ) {
            case .success:
                break
            case .failure(let failure):
                committer.discard(pair)
                return .notStarted(failure)
            }
            if let failure = finalModifierGate(for: handle) {
                committer.discard(pair)
                return .notStarted(failure)
            }
            switch CurrentFocusCombinedInterferenceEpoch.shared.beginCommitReservation(
                expectedValue: expectedGlobalEpoch
            ) {
            case .drifted:
                committer.discard(pair)
                return .notStarted(.inputDrift)
            case .unavailable:
                Thread.sleep(forTimeInterval: 0.0005)
                continue
            case .acquired:
                guard controlPlane.valueStore.lock.try() else {
                    CurrentFocusCombinedInterferenceEpoch.shared.endCommitReservation()
                    Thread.sleep(forTimeInterval: 0.0005)
                    continue
                }

                let now = DispatchTime.now().uptimeNanoseconds
                let allowed = controlPlane.commitMayBeginLocked(
                    handle,
                    input: ReviewCommitGateInput(
                        expectedCombinedEpoch: expectedEpoch,
                        expectedGlobalCombinedEpoch: expectedGlobalEpoch,
                        // The epoch reservation proves this value is still
                        // current without a getter under the value lock.
                        liveGlobalCombinedEpoch: expectedGlobalEpoch,
                        deadline: deadline,
                        now: now
                    )
                )
                if allowed {
                    controlPlane.markCommittingLocked(handle)
                    // This is the only post-capable critical section. The
                    // pair is already immutable and read-back validated; no
                    // getter, callback, allocation, or validation is called
                    // between the two direct backend posts.
                    committer.postDown(pair)
                    controlPlane.markBoundaryCrossedLocked(handle)
                    committer.postUp(pair)
                    controlPlane.valueStore.lock.unlock()
                    CurrentFocusCombinedInterferenceEpoch.shared.endCommitReservation()
                    let storeStable = controlPlane.valueStore.lockedValue {
                        controlPlane.valueStore.combinedEpoch == expectedEpoch
                    }
                    let cancellationObserved = controlPlane.valueStore.lockedValue {
                        controlPlane.valueStore.records[handle]?.cancellationRequested ?? false
                    }
                    let postflightSnapshot =
                        CurrentFocusCombinedInterferenceEpoch.shared.captureSnapshot()
                    let postflightStable = storeStable
                        && postflightSnapshot.isStable(expectedValue: expectedGlobalEpoch)
                    return .submittedUnverified(
                        ReviewPostBoundaryObservation(
                            mandatoryKeyUpAttempted: true,
                            cancellationObservedAfterDown: cancellationObserved || !postflightStable,
                            postflightStable: postflightStable
                        )
                    )
                }
                let cancelled = controlPlane.cancellationRequestedLocked(handle)
                let expired = now >= deadline
                controlPlane.valueStore.lock.unlock()
                CurrentFocusCombinedInterferenceEpoch.shared.endCommitReservation()
                committer.discard(pair)
                return .notStarted(
                    cancelled ? .cancellation : (expired ? .deadline : .gateRejected)
                )
            }
        }
        committer.discard(pair)
        return .notStarted(.deadline)
    }

    private func validateForImmediateCommit(
        _ targetID: CapturedReviewTargetID,
        handle: ReviewSubmissionAttemptHandle,
        deadline: UInt64
    ) -> Result<FinalBindingProof, ReviewPreBoundaryFailure> {
        if let failure = validateRawTarget(
            targetID,
            handle: handle,
            deadline: deadline
        ) {
            return .failure(failure)
        }
        return .success(FinalBindingProof())
    }

    private func terminalize(
        _ handle: ReviewSubmissionAttemptHandle,
        failure: ReviewPreBoundaryFailure
    ) {
        guard let effectiveFailure = controlPlane.beginTerminalizing(handle, failure: failure) else {
            return
        }
        controlPlane.enqueueRawCleanupComplete(
            TerminalCleanupValue(handle: handle, receipt: .notStarted(effectiveFailure))
        )
    }
}

private extension ReviewSubmissionValueStore {
    func lockedValue<T>(_ read: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return read()
    }
}

@MainActor
private enum ReviewLifecycleLeaseRegistry {
    private final class Entry {
        weak var owner: AnyObject?
        let lease: ReviewSubmissionLifecycleLease

        init(owner: AnyObject, lease: ReviewSubmissionLifecycleLease) {
            self.owner = owner
            self.lease = lease
        }
    }

    private static var entries: [ObjectIdentifier: Entry] = [:]

    static func install(
        _ observer: any ReviewSubmissionLifecycleMonitoring,
        lease: ReviewSubmissionLifecycleLease
    ) {
        entries[ObjectIdentifier(observer)] = Entry(owner: observer, lease: lease)
    }

    static func owns(
        _ observer: any ReviewSubmissionLifecycleMonitoring,
        lease: ReviewSubmissionLifecycleLease
    ) -> Bool {
        let key = ObjectIdentifier(observer)
        guard let entry = entries[key], entry.owner === observer else {
            entries.removeValue(forKey: key)
            return false
        }
        return entry.lease == lease
    }

    static func retire(
        _ observer: any ReviewSubmissionLifecycleMonitoring,
        lease: ReviewSubmissionLifecycleLease
    ) -> Bool {
        let key = ObjectIdentifier(observer)
        guard let entry = entries[key], entry.owner === observer,
              entry.lease == lease else {
            return false
        }
        entries.removeValue(forKey: key)
        return true
    }
}

@MainActor
protocol ReviewSubmissionLifecycleMonitoring: AnyObject {
    var isArmed: Bool { get }
    func arm(for target: StableApplicationIdentity) -> Bool
    func disarm()
    func acquireLease(for target: StableApplicationIdentity) -> ReviewSubmissionLifecycleLease?
    func owns(_ lease: ReviewSubmissionLifecycleLease) -> Bool
    func retire(_ lease: ReviewSubmissionLifecycleLease)
}

@MainActor
extension ReviewSubmissionLifecycleMonitoring {
    func acquireLease(
        for target: StableApplicationIdentity
    ) -> ReviewSubmissionLifecycleLease? {
        guard arm(for: target) else { return nil }
        let lease = ReviewSubmissionLifecycleLease()
        ReviewLifecycleLeaseRegistry.install(self, lease: lease)
        return lease
    }

    func owns(_ lease: ReviewSubmissionLifecycleLease) -> Bool {
        isArmed && ReviewLifecycleLeaseRegistry.owns(self, lease: lease)
    }

    func retire(_ lease: ReviewSubmissionLifecycleLease) {
        guard ReviewLifecycleLeaseRegistry.retire(self, lease: lease) else {
            return
        }
        disarm()
    }
}

/// The accepted facade owns this monitor for the full captured-target lifetime.
/// Every observer callback only classifies the signal and advances the shared
/// epoch; no callback reaches the raw executor or waits on its queue.
@MainActor
final class SystemReviewSubmissionLifecycleObserver: ReviewSubmissionLifecycleMonitoring {
    private let workspaceCenter: NotificationCenter
    private var workspaceTokens: [NSObjectProtocol] = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var activeLeases: [ReviewSubmissionLifecycleLease: StableApplicationIdentity] = [:]

    private(set) var isArmed = false

    init(workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.workspaceCenter = workspaceCenter
        installObservers()
    }

    func arm(for target: StableApplicationIdentity) -> Bool {
        acquireLease(for: target) != nil
    }

    func acquireLease(
        for target: StableApplicationIdentity
    ) -> ReviewSubmissionLifecycleLease? {
        if !observersInstalled {
            logger.info("Retrying review lifecycle observer installation before target capture")
            installObservers()
        }
        guard observersInstalled else {
            isArmed = false
            logger.error("Review lifecycle observers remain unavailable after retry")
            return nil
        }
        isArmed = true
        let lease = ReviewSubmissionLifecycleLease()
        activeLeases[lease] = target
        return lease
    }

    func disarm() {
        activeLeases.removeAll()
    }

    func owns(_ lease: ReviewSubmissionLifecycleLease) -> Bool {
        isArmed && activeLeases[lease] != nil
    }

    func retire(_ lease: ReviewSubmissionLifecycleLease) {
        activeLeases.removeValue(forKey: lease)
    }

    private func installObservers() {
        removeObservers()

        let activationToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.observeActivation()
            }
        }
        let terminationToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.observeTermination(notification)
            }
        }
        let launchToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.observeProcessGeneration(notification)
            }
        }
        workspaceTokens = [activationToken, terminationToken, launchToken]

        let mask: NSEvent.EventTypeMask = [
            .keyDown,
            .flagsChanged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged
        ]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.observeAppKitEvent(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.observeAppKitEvent(event)
        }

        isArmed = workspaceTokens.count == 3
            && localMonitor != nil
            && globalMonitor != nil
        if !isArmed {
            removeObservers()
        }
    }

    private var observersInstalled: Bool {
        workspaceTokens.count == 3
            && localMonitor != nil
            && globalMonitor != nil
    }

    private func observeActivation() {
        guard !activeLeases.isEmpty else { return }
        CurrentFocusCombinedInterferenceEpoch.shared.advance()
    }

    private func observeTermination(_ notification: Notification) {
        guard !activeLeases.isEmpty else { return }
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else {
            CurrentFocusCombinedInterferenceEpoch.shared.advance()
            return
        }
        if activeLeases.values.contains(where: {
            $0.processIdentifier == application.processIdentifier
        }) {
            CurrentFocusCombinedInterferenceEpoch.shared.advance()
        }
    }

    private func observeProcessGeneration(_ notification: Notification) {
        guard !activeLeases.isEmpty else { return }
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else {
            CurrentFocusCombinedInterferenceEpoch.shared.advance()
            return
        }
        if activeLeases.values.contains(where: {
            $0.processIdentifier == application.processIdentifier
        }) {
            CurrentFocusCombinedInterferenceEpoch.shared.advance()
        }
    }

    private func observeAppKitEvent(_ event: NSEvent) {
        guard !activeLeases.isEmpty else { return }
        guard let cgEvent = event.cgEvent else {
            CurrentFocusCombinedInterferenceEpoch.shared.advance()
            return
        }
        guard !FeishuSpeechSyntheticEventTag.isSelfIdentified(cgEvent) else { return }
        CurrentFocusCombinedInterferenceEpoch.shared.advance()
    }

    private func removeObservers() {
        isArmed = false
        workspaceTokens.forEach { workspaceCenter.removeObserver($0) }
        workspaceTokens.removeAll()
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    deinit {
        workspaceTokens.forEach { workspaceCenter.removeObserver($0) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }
}

/// MainActor-facing production seam for v5 review submission.  It carries
/// only stable value descriptors, opaque handles, immutable envelopes, and
/// typed receipts/events.  A fake can implement this protocol without
/// constructing an AX object or an event source.
@MainActor
protocol ReviewSubmissionFacade: AnyObject {
    func setEventHandler(
        _ handler: (@MainActor @Sendable (ReviewSubmissionControlEvent) -> Void)?
    )
    func snapshotFrontmostApplication() -> StableApplicationIdentity?
    func captureTarget(
        _ request: ReviewTargetCaptureRequestDescriptor,
        completion: @escaping @MainActor @Sendable (
            Result<CapturedReviewTargetDescriptor, ReviewPreBoundaryFailure>
        ) -> Void
    )
    func issueAttemptHandle() -> ReviewSubmissionAttemptHandle?
    func makeAdmissionEnvelope(
        handle: ReviewSubmissionAttemptHandle,
        request: ReviewSubmissionRequestDescriptor
    ) -> ReviewSubmissionAdmissionEnvelope
    func enqueueAdmission(_ envelope: ReviewSubmissionAdmissionEnvelope)
    func enqueueStart(_ handle: ReviewSubmissionAttemptHandle)
    func enqueueCancellation(_ handle: ReviewSubmissionAttemptHandle)
    func releaseCapturedTarget(_ targetID: CapturedReviewTargetID)
}

extension ReviewSubmissionFacade {
    /// Convenience for a coordinator that wants the facade to take exactly
    /// one MainActor identity snapshot for this capture request.
    func captureTarget(
        generation: UInt64,
        completion: @escaping @MainActor @Sendable (
            Result<CapturedReviewTargetDescriptor, ReviewPreBoundaryFailure>
        ) -> Void
    ) {
        guard generation > 0,
              let application = snapshotFrontmostApplication() else {
            Task { @MainActor in
                completion(.failure(.targetIdentityChanged))
            }
            return
        }
        captureTarget(
            ReviewTargetCaptureRequestDescriptor(
                generation: generation,
                application: application
            ),
            completion: completion
        )
    }
}

/// A small value-event relay keeps control-plane callback installation
/// independent from facade initialization.  The relay never stores raw AX or
/// CGEvent state and delivers events asynchronously on MainActor.
final class ReviewSubmissionEventRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@MainActor @Sendable (ReviewSubmissionControlEvent) -> Void)?

    func install(
        _ handler: (@MainActor @Sendable (ReviewSubmissionControlEvent) -> Void)?
    ) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func receive(_ event: ReviewSubmissionControlEvent) {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        guard let handler else { return }
        Task { @MainActor in
            handler(event)
        }
    }
}

/// The accepted v5 production path.  MainActor snapshots only the stable
/// frontmost identity; the raw executor then captures, validates, posts, and
/// releases every AXUIElement/CGEvent within its private serial context.  It
/// never invokes the legacy output delivery path, changes target focus, or
/// exposes a raw destination token property or API.
@MainActor
final class SystemReviewSubmissionFacade: ReviewSubmissionFacade {
    private let controlPlane: ReviewSubmissionControlPlane
    private let executor: ReviewSubmissionExecutor
    private let ticketIssuer: ReviewAttemptTicketIssuer
    private let eventRelay: ReviewSubmissionEventRelay
    private let lifecycleObserver: ReviewSubmissionLifecycleMonitoring
    private var lifecycleLeasesByTarget: [CapturedReviewTargetID: ReviewSubmissionLifecycleLease] = [:]
    private var targetByAttempt: [ReviewSubmissionAttemptHandle: CapturedReviewTargetID] = [:]

    init(
        rawAccessibility: ReviewSubmissionRawAccessibilityRuntime? = nil,
        committer: ReviewUnicodeCommitter? = nil,
        lifecycleObserver: ReviewSubmissionLifecycleMonitoring? = nil
    ) {
        let rawAccessibility = rawAccessibility ?? SystemReviewSubmissionAXRuntime()
        let committer = committer ?? ReviewUnicodeCommitter()
        let eventRelay = ReviewSubmissionEventRelay()
        let controlPlane = ReviewSubmissionControlPlane()
        let executor = ReviewSubmissionExecutor(
            controlPlane: controlPlane,
            committer: committer,
            rawAccessibility: rawAccessibility
        )
        self.controlPlane = controlPlane
        self.executor = executor
        self.ticketIssuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        self.eventRelay = eventRelay
        self.lifecycleObserver = lifecycleObserver ?? SystemReviewSubmissionLifecycleObserver()

        // Both queue bridges capture independent, fully initialized helpers;
        // neither closure captures `self` during initialization.
        controlPlane.attachEventHandler { [weak eventRelay] event in
            eventRelay?.receive(event)
        }
    }

    func setEventHandler(
        _ handler: (@MainActor @Sendable (ReviewSubmissionControlEvent) -> Void)?
    ) {
        eventRelay.install(handler)
    }

    func snapshotFrontmostApplication() -> StableApplicationIdentity? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier > 0,
              let bundleIdentifier = application.bundleIdentifier,
              let executableURL = application.executableURL,
              let launchDate = application.launchDate else {
            return nil
        }
        return StableApplicationIdentity(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: bundleIdentifier,
            executableURL: executableURL,
            launchDate: launchDate
        )
    }

    func captureTarget(
        _ request: ReviewTargetCaptureRequestDescriptor,
        completion: @escaping @MainActor @Sendable (
            Result<CapturedReviewTargetDescriptor, ReviewPreBoundaryFailure>
        ) -> Void
    ) {
        guard let lease = lifecycleObserver.acquireLease(for: request.application) else {
            Task { @MainActor in
                completion(.failure(.accessibilityFailure))
            }
            return
        }
        executor.capture(request) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else {
                    completion(result)
                    return
                }
                switch result {
                case .failure(let failure):
                    self.lifecycleObserver.retire(lease)
                    completion(.failure(failure))
                case .success(let descriptor):
                    guard self.lifecycleObserver.owns(lease) else {
                        self.executor.release(descriptor.targetID)
                        self.lifecycleObserver.retire(lease)
                        completion(.failure(.accessibilityFailure))
                        return
                    }
                    self.lifecycleLeasesByTarget[descriptor.targetID] = lease
                    completion(.success(descriptor))
                }
            }
        }
    }

    func issueAttemptHandle() -> ReviewSubmissionAttemptHandle? {
        ticketIssuer.issue()
    }

    func makeAdmissionEnvelope(
        handle: ReviewSubmissionAttemptHandle,
        request: ReviewSubmissionRequestDescriptor
    ) -> ReviewSubmissionAdmissionEnvelope {
        if let lease = lifecycleLeasesByTarget[request.capturedTargetID],
           lifecycleObserver.owns(lease) {
            targetByAttempt[handle] = request.capturedTargetID
        } else {
            targetByAttempt.removeValue(forKey: handle)
        }
        return ReviewSubmissionAdmissionEnvelope(handle: handle, request: request)
    }

    func enqueueAdmission(_ envelope: ReviewSubmissionAdmissionEnvelope) {
        guard let targetID = targetByAttempt[envelope.handle],
              let lease = lifecycleLeasesByTarget[targetID],
              lifecycleObserver.owns(lease) else {
            eventRelay.receive(.admissionRejected(envelope.handle, .invalidRequest))
            return
        }
        controlPlane.enqueueAdmission(envelope)
    }

    func enqueueStart(_ handle: ReviewSubmissionAttemptHandle) {
        guard let targetID = targetByAttempt[handle],
              let lease = lifecycleLeasesByTarget[targetID],
              lifecycleObserver.owns(lease) else {
            controlPlane.enqueueCancellation(handle)
            return
        }
        controlPlane.enqueueStart(handle)
    }

    func enqueueCancellation(_ handle: ReviewSubmissionAttemptHandle) {
        controlPlane.enqueueCancellation(handle)
    }

    func releaseCapturedTarget(_ targetID: CapturedReviewTargetID) {
        executor.release(targetID)
        if let lease = lifecycleLeasesByTarget.removeValue(forKey: targetID) {
            lifecycleObserver.retire(lease)
        }
        targetByAttempt = targetByAttempt.filter { $0.value != targetID }
    }
}
