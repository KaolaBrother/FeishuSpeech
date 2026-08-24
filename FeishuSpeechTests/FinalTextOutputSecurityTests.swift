import ApplicationServices
import AppKit
import Carbon
@testable import FeishuSpeech
import Foundation
import os.log
import XCTest

private let logger = Logger(
    subsystem: "com.feishuspeech.app",
    category: "FinalTextOutputSecurityTests"
)

@MainActor
final class FinalTextOutputSecurityTests: XCTestCase {
    func test_v9NonNativeFocusedRolesUseOrdinaryApplicationFallback() {
        XCTAssertEqual(
            ReviewAXEditableRolePolicy.classify("AXWebArea"),
            .ordinaryCapabilityMiss
        )
        XCTAssertEqual(
            ReviewAXEditableRolePolicy.classify(kAXButtonRole as String),
            .ordinaryCapabilityMiss
        )
        XCTAssertEqual(
            ReviewAXEditableRolePolicy.classify(kAXTextFieldRole as String),
            .nativeTextInput
        )
        XCTAssertEqual(
            ReviewAXEditableRolePolicy.classify(kAXTextAreaRole as String),
            .nativeTextInput
        )
    }

    func test_v8CaptureTraceIdentifiesSecureInputBeforeAnyAXMessage() {
        let identity = V5SystemAXFixtures.identity(processIdentifier: 42)
        let trace = V5SystemAXStepTrace()
        let runtime = SystemReviewSubmissionAXRuntime(
            stepObserver: trace.observe,
            securitySamples: ReviewAXSecuritySamples(
                secureInputEnabled: { true },
                accessibilityTrusted: { true },
                runningIdentity: { processIdentifier in
                    processIdentifier == identity.processIdentifier ? identity : nil
                },
                frontmostProcessIdentifier: { identity.processIdentifier }
            )
        )

        let result = runtime.capture(
            ReviewTargetCaptureRequestDescriptor(
                generation: 7,
                application: identity
            )
        )

        guard case .failure(let failure) = result else {
            return XCTFail("Secure Input capture must fail before AX messaging")
        }
        XCTAssertEqual(failure, .securityRejected)
        XCTAssertEqual(
            trace.snapshot().map { $0.0.rawValue + ":" + $0.1.rawValue },
            [
                "runningIdentity:success",
                "frontmost:success",
                "secureInput:secureInputEnabled"
            ]
        )
    }

    func test_v8CaptureTraceIdentifiesLostAccessibilityTrustBeforeAnyAXMessage() {
        let identity = V5SystemAXFixtures.identity(processIdentifier: 42)
        let trace = V5SystemAXStepTrace()
        let runtime = SystemReviewSubmissionAXRuntime(
            stepObserver: trace.observe,
            securitySamples: ReviewAXSecuritySamples(
                secureInputEnabled: { false },
                accessibilityTrusted: { false },
                runningIdentity: { processIdentifier in
                    processIdentifier == identity.processIdentifier ? identity : nil
                },
                frontmostProcessIdentifier: { identity.processIdentifier }
            )
        )

        let result = runtime.capture(
            ReviewTargetCaptureRequestDescriptor(
                generation: 7,
                application: identity
            )
        )

        guard case .failure(let failure) = result else {
            return XCTFail("lost Accessibility trust must fail before AX messaging")
        }
        XCTAssertEqual(failure, .securityRejected)
        XCTAssertEqual(
            trace.snapshot().map { $0.0.rawValue + ":" + $0.1.rawValue },
            [
                "runningIdentity:success",
                "frontmost:success",
                "secureInput:success",
                "accessibilityTrust:accessibilityUntrusted"
            ]
        )
    }

    func test_v5ExactCursorCaptureOwnsOriginalFocusAndSelectionThroughSubmission() throws {
        let accessibilitySource = try productionSource(
            relativePath: "FeishuSpeech/Services/AccessibilityClient.swift"
        )
        let executorSource = try productionSource(
            relativePath: "FeishuSpeech/Services/ReviewSubmissionExecutor.swift"
        )

        XCTAssertTrue(
            executorSource.contains("originalSelection"),
            "the accepted v5 raw target must retain the exact selection captured with the focused element"
        )
        XCTAssertTrue(
            executorSource.contains("focusedElement"),
            "the accepted v5 raw target must retain the exact focused AX element"
        )
        XCTAssertTrue(
            accessibilitySource.contains("setSelectedTextRange") &&
                accessibilitySource.contains("selectedTextRange"),
            "exact-cursor confirmation must restore and reread the captured selection before pair preparation"
        )
    }

    func test_v5SubmissionValidationUsesCapturedCursorOrApplicationElementWithoutAmbientFocusLookup() throws {
        let source = try productionSource(
            relativePath: "FeishuSpeech/Services/AccessibilityClient.swift"
        )

        guard let exactStart = source.range(
            of: "private func validateExactState("
        ),
        let exactEnd = source.range(
            of: "private func applicationBoundState(",
            range: exactStart.upperBound ..< source.endIndex
        ),
        let applicationBoundStart = source.range(
            of: "private func validateApplicationBoundState("
        ),
        let applicationBoundEnd = source.range(
            of: "private func validateExactState(",
            range: applicationBoundStart.upperBound ..< source.endIndex
        ) else {
            return XCTFail(
                "submission validation must keep distinct exact-cursor and application-bound routines"
            )
        }

        let exactValidation = String(source[exactStart.lowerBound ..< exactEnd.lowerBound])
        XCTAssertTrue(
            exactValidation.contains("target.focusedElement") &&
                exactValidation.contains("target.originalSelection") &&
                exactValidation.contains("setSelectedRange"),
            "exact-cursor validation must restore the captured element and original selection directly"
        )
        XCTAssertFalse(
            exactValidation.contains("AXUIElementCreateSystemWide"),
            "exact-cursor validation must not reacquire an ambient system-wide focus target"
        )

        let applicationBoundValidation = String(
            source[applicationBoundStart.lowerBound ..< applicationBoundEnd.lowerBound]
        )
        XCTAssertTrue(
            applicationBoundValidation.contains("target.applicationElement") &&
                applicationBoundValidation.contains("kAXFocusedUIElementAttribute"),
            "application-bound validation must read the focused element from the captured application element"
        )
        XCTAssertFalse(
            applicationBoundValidation.contains("AXUIElementCreateSystemWide"),
            "application-bound validation must not retarget through ambient system-wide focus"
        )
    }

    func test_v5ExecutorStabilizesRelevantModifiersAndRechecksAtFinalGate() throws {
        let source = try productionSource(
            relativePath: "FeishuSpeech/Services/ReviewSubmissionExecutor.swift"
        )

        XCTAssertTrue(
            source.contains("flagsState"),
            "v5 submission must sample the combined relevant modifier state before admission"
        )
        XCTAssertTrue(
            source.contains("modifier") && source.contains("modifierInstability"),
            "held Command/Shift/Option/Control/Fn/Caps modifiers must fail closed before down"
        )
        XCTAssertTrue(
            source.contains("final") && source.contains("flagsState"),
            "the final gate must recheck modifier emptiness immediately before key-down"
        )
    }

    func test_v5FacadeComposesLifecycleObserversAndFinalCapturedTargetSample() throws {
        let source = try productionSource(
            relativePath: "FeishuSpeech/Services/ReviewSubmissionExecutor.swift"
        )

        XCTAssertTrue(
            source.contains("NSWorkspace") &&
                source.contains("termination") &&
                source.contains("observer"),
            "the accepted facade must arm activation, termination, process-generation, and observer-loss coverage"
        )
        XCTAssertTrue(
            source.contains("frontmost") && source.contains("postflight"),
            "the submission path must sample the captured target again at the final pre-down boundary"
        )
    }

    func test_v5RawCaptureDistinguishesOrdinaryAXMissFromSecureOrUnverifiableFailure() throws {
        let source = try productionSource(
            relativePath: "FeishuSpeech/Services/AccessibilityClient.swift"
        )

        XCTAssertTrue(
            source.contains("applicationBoundCurrentFocus"),
            "an ordinary nonsecure cursor-detail miss must retain the captured application-bound fallback"
        )
        XCTAssertTrue(
            source.contains("accessibilityTimeout") &&
                source.contains("securityRejected"),
            "secure/unverifiable AX failures must remain typed fail-closed outcomes distinct from ordinary misses"
        )
        guard let focusedStart = source.range(
            of: "switch copyAttribute(\n            kAXFocusedUIElementAttribute"
        ),
        let focusedEnd = source.range(
            of: "return captureFocusedState(",
            range: focusedStart.upperBound ..< source.endIndex
        ) else {
            return XCTFail(
                "capture must expose an explicit focused-element result classifier"
            )
        }
        let focusedClassifier = String(source[focusedStart.lowerBound ..< focusedEnd.lowerBound])
        XCTAssertTrue(
            focusedClassifier.contains("case .unavailable") &&
                focusedClassifier.contains("success(applicationBoundState"),
            "ordinary noValue/unsupported focused-element reads must retain the application-bound fallback"
        )
        XCTAssertTrue(
            focusedClassifier.contains("case .failed") &&
                focusedClassifier.contains("failure(.accessibilityTimeout)"),
            "timed-out/unverifiable focused-element reads must remain typed fail-closed failures"
        )
    }

    func test_v5ApplicationBoundPersistentOrdinaryMissRemainsAllowedWhileSecurityFailuresFailClosed() async throws {
        let scenarios: [(String, ReviewPreBoundaryFailure?, ReviewCommitReceipt)] = [
            (
                "ordinary capability miss",
                nil,
                .submittedUnverified(
                    ReviewPostBoundaryObservation(
                        mandatoryKeyUpAttempted: true,
                        cancellationObservedAfterDown: false,
                        postflightStable: true
                    )
                )
            ),
            ("AX timeout", .accessibilityTimeout, .notStarted(.accessibilityTimeout)),
            ("secure or unverifiable", .securityRejected, .notStarted(.securityRejected))
        ]

        for (label, validationFailure, expectedReceipt) in scenarios {
            let recorder = V5ReviewSubmissionEventRecorder()
            let backend = V5ReviewSubmissionEventBackend()
            let runtime = V5ApplicationBoundOrdinaryMissRawRuntime(
                validationFailure: validationFailure
            )
            let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
            let executor = ReviewSubmissionExecutor(
                controlPlane: controlPlane,
                committer: ReviewUnicodeCommitter(backend: backend),
                rawAccessibility: runtime
            )
            let target = try await captureTarget(
                using: executor,
                request: ReviewTargetCaptureRequestDescriptor(
                    generation: 5,
                    application: V5ReviewSubmissionFixtures.identity
                )
            )
            let issuer = ReviewAttemptTicketIssuer(
                controlPlaneInstanceNonce: controlPlane.instanceNonce
            )
            let handle = try XCTUnwrap(issuer.issue())
            let request = makeSubmissionRequest(
                targetID: target.targetID,
                draft: "ordinary-miss-\(label)"
            )
            controlPlane.enqueueAdmission(
                ReviewSubmissionAdmissionEnvelope(
                    handle: handle,
                    request: request,
                    absolutePreBoundaryDeadline: DispatchTime.now().uptimeNanoseconds
                        + 1_000_000_000
                )
            )
            let admissionAccepted = await recorder.waitFor {
                if case .admissionAccepted(handle) = $0 { return true }
                return false
            }
            XCTAssertTrue(admissionAccepted, "the \(label) scenario must reach admission")
            controlPlane.enqueueStart(handle)
            let terminalReceipt = await recorder.waitForTerminal(for: handle)
            let receipt = try XCTUnwrap(
                terminalReceipt,
                "the \(label) scenario must produce one typed terminal receipt"
            )
            XCTAssertEqual(receipt, expectedReceipt, label)
            if validationFailure == nil {
                XCTAssertEqual(backend.operations, [.prepare, .down, .up], label)
            } else {
                XCTAssertEqual(backend.operations, [], label)
            }
        }
    }

    func test_v5ApplicationBoundValidationDoesNotCollapseOrdinaryMissIntoTimeout() throws {
        let source = try productionSource(
            relativePath: "FeishuSpeech/Services/AccessibilityClient.swift"
        )
        guard let start = source.range(
            of: "private func validateApplicationBoundState("
        ),
        let end = source.range(
            of: "private func validateExactState(",
            range: start.upperBound ..< source.endIndex
        ) else {
            return XCTFail("application-bound validation routine must remain explicit")
        }
        let validation = String(source[start.lowerBound ..< end.lowerBound])
        XCTAssertFalse(
            validation.contains("case .unavailable, .failed"),
            "ordinary noValue/unsupported focus must remain allowed; only timeout or secure/unverifiable failures may reject"
        )
        XCTAssertTrue(
            validation.contains("ordinaryCapabilityMiss") ||
                validation.contains("case .unavailable") && validation.contains("return nil"),
            "submission must preserve an explicit ordinary capability-miss path"
        )
    }

    func test_v5LifecycleLeaseOverlapKeepsCaptureBArmedAndRejectsOnItsObserverEvent() async throws {
        let runtime = V5LifecycleOverlapRawRuntime()
        let lifecycle = V5LifecycleMonitoringFake()
        let backend = V5ReviewSubmissionEventBackend()
        let facade = SystemReviewSubmissionFacade(
            rawAccessibility: runtime,
            committer: ReviewUnicodeCommitter(backend: backend),
            lifecycleObserver: lifecycle
        )
        let recorder = V5ReviewSubmissionEventRecorder()
        facade.setEventHandler(recorder.append)

        let identityA = V5ReviewSubmissionFixtures.identity
        let identityB = V5ReviewSubmissionFixtures.identity(
            processIdentifier: identityA.processIdentifier + 1
        )
        let captureAEntered = DispatchSemaphore(value: 0)
        let captureARelease = DispatchSemaphore(value: 0)
        runtime.captureGates[5] = (captureAEntered, captureARelease)
        runtime.captureFailures = [5]

        let resultA = beginFacadeCapture(
            facade,
            request: ReviewTargetCaptureRequestDescriptor(
                generation: 5,
                application: identityA
            )
        )
        XCTAssertEqual(captureAEntered.wait(timeout: .now() + 1), .success)

        let resultB = beginFacadeCapture(
            facade,
            request: ReviewTargetCaptureRequestDescriptor(
                generation: 6,
                application: identityB
            )
        )
        XCTAssertEqual(lifecycle.armRequests, [identityA, identityB])
        captureARelease.signal()

        let resultAValue = await resultA.wait()
        let resultBValue = await resultB.wait()
        let capturedA = try XCTUnwrap(resultAValue)
        let capturedB = try XCTUnwrap(resultBValue)
        guard case .failure(.accessibilityFailure) = capturedA else {
            return XCTFail("stale capture A must fail through the typed raw-capture path")
        }
        guard case .success(let targetB) = capturedB else {
            return XCTFail("capture B must remain successful while capture A completes")
        }

        XCTAssertEqual(
            lifecycle.activeTarget,
            identityB,
            "completion of stale A must not clear B's observer lease"
        )

        let validationEntered = DispatchSemaphore(value: 0)
        let validationRelease = DispatchSemaphore(value: 0)
        runtime.validationGate = (2, validationEntered, validationRelease)
        let handle = try XCTUnwrap(facade.issueAttemptHandle())
        facade.enqueueAdmission(
            facade.makeAdmissionEnvelope(
                handle: handle,
                request: makeSubmissionRequest(
                    targetID: targetB.targetID,
                    generation: targetB.generation,
                    draft: "lease-overlap"
                )
            )
        )
        let admissionAccepted = await recorder.waitFor {
            if case .admissionAccepted(handle) = $0 { return true }
            return false
        }
        XCTAssertTrue(admissionAccepted)
        facade.enqueueStart(handle)
        XCTAssertEqual(validationEntered.wait(timeout: .now() + 1), .success)

        lifecycle.emitActivation(for: identityB)
        lifecycle.emitTermination(for: identityB)
        validationRelease.signal()

        let terminalReceipt = await recorder.waitForTerminal(for: handle)
        let receipt = try XCTUnwrap(terminalReceipt)
        XCTAssertEqual(
            receipt,
            .notStarted(.inputDrift),
            "activation/termination of the still-armed B target must advance the epoch and fail closed"
        )
        XCTAssertEqual(
            backend.operations,
            [],
            "B observer drift must reject before pair construction and posting"
        )
        XCTAssertEqual(lifecycle.observerEpochAdvanceCount, 2)
    }

    func test_v5LifecycleReleaseOfStaleTargetDoesNotDisarmNewerLease() async throws {
        let runtime = V5LifecycleOverlapRawRuntime()
        let lifecycle = V5LifecycleMonitoringFake()
        let facade = SystemReviewSubmissionFacade(
            rawAccessibility: runtime,
            committer: ReviewUnicodeCommitter(
                backend: V5ReviewSubmissionEventBackend()
            ),
            lifecycleObserver: lifecycle
        )
        let identityA = V5ReviewSubmissionFixtures.identity
        let identityB = V5ReviewSubmissionFixtures.identity(
            processIdentifier: identityA.processIdentifier + 1
        )
        let targetA = try await captureTarget(
            using: facade,
            request: ReviewTargetCaptureRequestDescriptor(
                generation: 7,
                application: identityA
            )
        )
        let targetB = try await captureTarget(
            using: facade,
            request: ReviewTargetCaptureRequestDescriptor(
                generation: 8,
                application: identityB
            )
        )
        XCTAssertEqual(lifecycle.activeTarget, identityB)

        facade.releaseCapturedTarget(targetA.targetID)
        XCTAssertEqual(
            lifecycle.activeTarget,
            identityB,
            "releasing stale A must leave B's lease armed"
        )
        XCTAssertEqual(lifecycle.disarmCount, 0)

        facade.releaseCapturedTarget(targetB.targetID)
        XCTAssertNil(lifecycle.activeTarget)
        XCTAssertEqual(lifecycle.disarmCount, 1)
    }

    func test_v5RawValidationCancellationCheckpointStopsTheUninterruptedAXSequence() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let runtime = V5CancellationCheckpointRawRuntime()
        let backend = V5ReviewSubmissionEventBackend()
        let executor = ReviewSubmissionExecutor(
            controlPlane: controlPlane,
            committer: ReviewUnicodeCommitter(backend: backend),
            rawAccessibility: runtime
        )
        let target = try await captureTarget(
            using: executor,
            request: ReviewTargetCaptureRequestDescriptor(
                generation: 5,
                application: V5ReviewSubmissionFixtures.identity
            )
        )
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        let handle = try XCTUnwrap(issuer.issue())
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: handle,
                request: makeSubmissionRequest(targetID: target.targetID),
                absolutePreBoundaryDeadline: DispatchTime.now().uptimeNanoseconds
                    + 1_000_000_000
            )
        )
        let admissionAccepted = await recorder.waitFor {
            if case .admissionAccepted(handle) = $0 { return true }
            return false
        }
        XCTAssertTrue(admissionAccepted)
        controlPlane.enqueueStart(handle)
        XCTAssertEqual(runtime.setFocusedReturned.wait(timeout: .now() + 1), .success)

        controlPlane.enqueueCancellation(handle)
        let cancellation = await recorder.waitForCancellation(for: handle)
        XCTAssertEqual(cancellation, .latched)
        runtime.resumeAfterSetFocused.signal()

        let terminalReceipt = await recorder.waitForTerminal(for: handle)
        let receipt = try XCTUnwrap(terminalReceipt)
        XCTAssertEqual(receipt, .notStarted(.cancellation))
        XCTAssertTrue(runtime.cancellationObservedAtCheckpoint)
        XCTAssertEqual(
            runtime.operations,
            [.setFocused],
            "cancellation after setFocused must prevent selected-range/readback work"
        )
        XCTAssertEqual(backend.operations, [])
    }

    func test_v5SystemAXCancellationAfterMessagingTimeoutStopsBeforeAnyFocusOrReadbackStep() throws {
        let processIdentifier = pid_t(ProcessInfo.processInfo.processIdentifier)
        let identity = V5SystemAXFixtures.identity(processIdentifier: processIdentifier)
        let probe = V5SystemAXCancellationProbe()
        let trace = V5SystemAXStepTrace(onStep: { step, _ in
            if step == .messagingTimeout {
                // The value-only observer represents the independent control
                // plane latching cancellation after the messaging-timeout
                // return and before the next AX operation is admitted.
                probe.cancel()
            }
        })
        let runtime = SystemReviewSubmissionAXRuntime(
            stepObserver: trace.observe,
            securitySamples: V5SystemAXFixtures.securitySamples(identity: identity)
        )
        let target = V5SystemAXFixtures.rawTarget(
            identity: identity,
            binding: .exactCursor
        )

        let result = runtime.validate(
            target,
            deadline: DispatchTime.now().uptimeNanoseconds + 1_000_000_000,
            cancellationProbe: probe.isCancelled
        )

        XCTAssertEqual(
            result,
            .cancellation,
            "cancellation latched after a real messaging-timeout return must stop the raw sequence"
        )
        let steps = trace.snapshot()
        XCTAssertTrue(
            steps.contains { $0.0 == .messagingTimeout },
            "the concrete System AX runtime must report the timeout-setting step"
        )
        XCTAssertFalse(
            steps.contains { step, _ in
                [.setFocused, .setSelectedRange, .getSelectedRange, .readAXValue].contains(step)
            },
            "cancellation after messaging-timeout must prevent focus setter, selection setter, and readback"
        )
    }

    func test_v5SystemAXAbsoluteDeadlineAfterMessagingTimeoutStopsBeforeAnyFocusOrReadbackStep() throws {
        let processIdentifier = pid_t(ProcessInfo.processInfo.processIdentifier)
        let identity = V5SystemAXFixtures.identity(processIdentifier: processIdentifier)
        let trace = V5SystemAXStepTrace(onStep: { step, _ in
            guard step == .messagingTimeout else { return }
            // Force the immutable absolute deadline to expire in the seam
            // between the timeout-setting return and the next AX setter.
            Thread.sleep(forTimeInterval: 0.02)
        })
        let runtime = SystemReviewSubmissionAXRuntime(
            stepObserver: trace.observe,
            securitySamples: V5SystemAXFixtures.securitySamples(identity: identity)
        )
        let target = V5SystemAXFixtures.rawTarget(
            identity: identity,
            binding: .exactCursor
        )
        let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000

        let result = runtime.validate(
            target,
            deadline: deadline,
            cancellationProbe: { false }
        )

        XCTAssertEqual(
            result,
            .accessibilityTimeout,
            "expiry after a real messaging-timeout return must fail closed before focus mutation"
        )
        let steps = trace.snapshot()
        XCTAssertTrue(steps.contains { $0.0 == .messagingTimeout })
        XCTAssertFalse(
            steps.contains { step, _ in
                [.setFocused, .setSelectedRange, .getSelectedRange, .readAXValue].contains(step)
            },
            "absolute deadline expiry must prevent focus setter, selection setter, and readback"
        )
    }

    func test_v5SystemAXExactFocusReadbackCancellationAfterRestorationStopsBeforeCopy() throws {
        let processIdentifier = pid_t(ProcessInfo.processInfo.processIdentifier)
        let identity = V5SystemAXFixtures.identity(processIdentifier: processIdentifier)
        let latch = V5SystemAXReadbackCancellationLatch()
        let trace = V5SystemAXStepTrace(onStep: latch.observe)
        let runtime = SystemReviewSubmissionAXRuntime(
            stepObserver: trace.observe,
            securitySamples: V5SystemAXFixtures.securitySamples(identity: identity)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        editor.isEditable = true
        editor.string = "PRIVATE_R4_FOCUS_READBACK"
        window.contentView = editor
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(editor)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        defer {
            window.orderOut(nil)
            window.close()
        }

        let applicationElement = AXUIElementCreateApplication(identity.processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return XCTFail("the real editor must expose a focused AX element for exact readback")
        }
        let target = ReviewSubmissionRawTargetState(
            descriptor: CapturedReviewTargetDescriptor(
                generation: 5,
                application: identity,
                binding: .exactCursor,
                securityAtCapture: .safe
            ),
            applicationElement: applicationElement,
            focusedElement: unsafeBitCast(focusedValue, to: AXUIElement.self),
            originalSelection: CursorTextRange(location: 0, length: 0)
        )

        let result = runtime.validate(
            target,
            deadline: DispatchTime.now().uptimeNanoseconds + 1_000_000_000,
            cancellationProbe: latch.probe.isCancelled
        )

        XCTAssertEqual(
            result,
            .cancellation,
            "exact focus readback cancellation must fail closed before the focused-element copy"
        )
        let steps = trace.snapshot()
        XCTAssertTrue(
            latch.didLatch,
            "the latch must occur after restoration and before readback; trace=\(v5SystemAXTraceDescription(steps))"
        )
        guard let timeoutIndex = steps.lastIndex(where: { $0.0 == .messagingTimeout }) else {
            return XCTFail("exact restoration must reach the focused-element readback timeout")
        }
        XCTAssertTrue(
            steps[..<timeoutIndex].contains { $0.0 == .setSelectedRange },
            "the cancellation must be injected only after exact selection restoration"
        )
        XCTAssertEqual(
            steps.count,
            timeoutIndex + 1,
            "after cancellation at the readback timeout, no copy, later AX step, pair, down, or up may occur"
        )
        XCTAssertFalse(
            steps.dropFirst(timeoutIndex + 1).contains { $0.0 == .copyAttribute },
            "the focused-element copy must not execute after the live cancellation probe is latched"
        )
    }

    func test_v5SystemAXExactFocusReadbackCancellationStopsExecutorBeforePairOrPosts() async throws {
        let processIdentifier = pid_t(ProcessInfo.processInfo.processIdentifier)
        let identity = V5SystemAXFixtures.identity(processIdentifier: processIdentifier)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        editor.isEditable = true
        editor.string = "PRIVATE_R4_EXECUTOR_FOCUS_READBACK"
        window.contentView = editor
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(editor)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        defer {
            window.orderOut(nil)
            window.close()
        }

        let applicationElement = AXUIElementCreateApplication(identity.processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return XCTFail("the real editor must expose a focused AX element for executor validation")
        }
        let rawTarget = ReviewSubmissionRawTargetState(
            descriptor: CapturedReviewTargetDescriptor(
                generation: 5,
                application: identity,
                binding: .exactCursor,
                securityAtCapture: .safe
            ),
            applicationElement: applicationElement,
            focusedElement: unsafeBitCast(focusedValue, to: AXUIElement.self),
            originalSelection: CursorTextRange(location: 0, length: 0)
        )

        let recorder = V5ReviewSubmissionEventRecorder()
        let cancellationResolved = DispatchSemaphore(value: 0)
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: { event in
            recorder.append(event)
            if case .cancellationResolved = event {
                cancellationResolved.signal()
            }
        })
        let latch = V5SystemAXExecutorCancellationLatch(
            controlPlane: controlPlane,
            cancellationResolved: cancellationResolved
        )
        let systemRuntime = SystemReviewSubmissionAXRuntime(
            stepObserver: { [latch] step, result in
                latch.observe(step, result)
            },
            securitySamples: V5SystemAXFixtures.securitySamples(identity: identity)
        )
        let backend = V5ReviewSubmissionEventBackend()
        let executor = ReviewSubmissionExecutor(
            controlPlane: controlPlane,
            committer: ReviewUnicodeCommitter(backend: backend),
            rawAccessibility: V5SystemAXDelegatingRuntime(
                runtime: systemRuntime,
                rawTarget: rawTarget
            )
        )
        let target = try await captureTarget(
            using: executor,
            request: ReviewTargetCaptureRequestDescriptor(
                generation: 5,
                application: identity
            )
        )
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        let handle = try XCTUnwrap(issuer.issue())
        latch.arm(handle)
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: handle,
                request: makeSubmissionRequest(targetID: target.targetID),
                absolutePreBoundaryDeadline: DispatchTime.now().uptimeNanoseconds
                    + 1_000_000_000
            )
        )
        let admissionAccepted = await recorder.waitFor {
            if case .admissionAccepted(handle) = $0 { return true }
            return false
        }
        XCTAssertTrue(admissionAccepted)
        controlPlane.enqueueStart(handle)

        let terminalReceipt = await recorder.waitForTerminal(for: handle)
        let terminal = try XCTUnwrap(terminalReceipt)
        XCTAssertEqual(terminal, .notStarted(.cancellation))
        XCTAssertTrue(latch.didLatch)
        XCTAssertEqual(
            backend.operations,
            [],
            "readback cancellation must prevent pair construction, Unicode down, and mandatory up"
        )
        let steps = latch.trace.snapshot()
        guard let timeoutIndex = steps.lastIndex(where: { $0.0 == .messagingTimeout }) else {
            return XCTFail("executor validation must reach the exact focused-element readback timeout")
        }
        XCTAssertEqual(
            steps.count,
            timeoutIndex + 1,
            "executor cancellation must leave no later copy, AX step, pair, down, or up"
        )
    }

    func test_v5SystemAXCancellationAndDeadlineCoverEveryReachableExactAndApplicationBoundStep() throws {
        let exactExpected = V5SystemAXExpectedInventory.exactValidation
        let applicationBoundExpected = V5SystemAXExpectedInventory.applicationBoundValidation
        let allValidationSteps = exactExpected + applicationBoundExpected

        XCTAssertEqual(
            V5SystemAXExpectedInventory.allProductionSteps.count,
            15,
            "the fixed inventory must enumerate every production ReviewAXStepID exactly once"
        )
        XCTAssertEqual(
            Set(V5SystemAXExpectedInventory.allProductionSteps.map(\.rawValue)).count,
            15,
            "the fixed production step inventory must not contain aliases or duplicates"
        )
        for step in V5SystemAXExpectedInventory.allProductionSteps {
            XCTAssertTrue(
                allValidationSteps.contains(step)
                    || V5SystemAXExpectedInventory.captureOnlySteps.contains(step),
                "production step \(step.rawValue) must be classified before scenarios are generated"
            )
        }
        XCTAssertEqual(
            V5SystemAXExpectedInventory.captureOnlySteps,
            [.isAttributeSettable],
            "isAttributeSettable is capture-only; all validation steps must be exercised below"
        )
        let lateSteps: [ReviewAXStepID] = [
            .copyAttribute,
            .getSelectedRange,
            .readAXValue,
            .role,
            .subrole
        ]
        for lateStep in lateSteps {
            XCTAssertTrue(
                exactExpected.contains(lateStep),
                "exact validation inventory must retain late readback/editability step \(lateStep.rawValue)"
            )
        }
        XCTAssertGreaterThanOrEqual(
            exactExpected.filter { $0 == .secureInput }.count,
            2,
            "exact validation must include both leading and trailing security composites"
        )
        XCTAssertGreaterThanOrEqual(
            applicationBoundExpected.filter { $0 == .secureInput }.count,
            2,
            "application-bound validation must include both leading and trailing security composites"
        )

        let identity = V5SystemAXFixtures.identity(
            processIdentifier: pid_t(ProcessInfo.processInfo.processIdentifier)
        )
        let exactFixture = try V5SystemAXValidationFixture.exact(identity: identity)
        let exactTrace = V5SystemAXStepTrace()
        let exactRuntime = SystemReviewSubmissionAXRuntime(
            stepObserver: exactTrace.observe,
            securitySamples: V5SystemAXFixtures.securitySamples(identity: identity)
        )
        XCTAssertNil(
            exactRuntime.validate(
                exactFixture.target,
                deadline: DispatchTime.now().uptimeNanoseconds + 1_000_000_000,
                cancellationProbe: { false }
            ),
            "the real editable window must complete exact validation before the matrix is generated"
        )
        let exactObserved = exactTrace.snapshot().map { $0.0 }
        XCTAssertEqual(
            exactObserved,
            exactExpected,
            "exact scenarios must use the fixed complete successful validation trace, not a self-shrinking prefix"
        )
        exactFixture.close()

        let applicationBoundFixture = try V5SystemAXValidationFixture.applicationBoundOrdinaryMiss(
            identity: identity
        )
        let applicationBoundTrace = V5SystemAXStepTrace()
        let applicationBoundRuntime = SystemReviewSubmissionAXRuntime(
            stepObserver: applicationBoundTrace.observe,
            securitySamples: V5SystemAXFixtures.securitySamples(identity: identity)
        )
        XCTAssertNil(
            applicationBoundRuntime.validate(
                applicationBoundFixture.target,
                deadline: DispatchTime.now().uptimeNanoseconds + 1_000_000_000,
                cancellationProbe: { false }
            ),
            "the concrete application-bound target must remain an ordinary focused-element miss"
        )
        let applicationBoundObserved = applicationBoundTrace.snapshot().map { $0.0 }
        XCTAssertEqual(
            applicationBoundObserved,
            applicationBoundExpected,
            "application-bound scenarios must use the fixed ordinary-miss trace"
        )
        applicationBoundFixture.close()

        try runV5SystemAXFixedStepMatrix(
            binding: .exactCursor,
            expected: exactExpected,
            identity: identity,
            makeFixture: { try V5SystemAXValidationFixture.exact(identity: identity) }
        )
        try runV5SystemAXFixedStepMatrix(
            binding: .applicationBoundCurrentFocus,
            expected: applicationBoundExpected,
            identity: identity,
            makeFixture: {
                try V5SystemAXValidationFixture.applicationBoundOrdinaryMiss(identity: identity)
            }
        )
    }

    func test_v5ExactFocusOrSelectionDriftAfterPairWithoutEpochDestroysPairAndPostsNothing() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let runtime = V5ReviewSubmissionRawRuntime(binding: .exactCursor)
        let backend = V5ReviewSubmissionEventBackend()
        backend.onPrepare = {
            // The pair is already constructed while the captured focus or
            // original selection changes without an epoch callback. A final
            // exact binding validation must destroy that prepared capability.
            runtime.setValidationFailure(.targetIdentityChanged)
        }
        let executor = ReviewSubmissionExecutor(
            controlPlane: controlPlane,
            committer: ReviewUnicodeCommitter(backend: backend),
            rawAccessibility: runtime
        )
        let target = try await captureTarget(
            using: executor,
            request: ReviewTargetCaptureRequestDescriptor(
                generation: 5,
                application: V5ReviewSubmissionFixtures.identity
            )
        )

        let receipt = try await submitRawAttempt(
            using: executor,
            controlPlane: controlPlane,
            target: target,
            recorder: recorder,
            draft: "exact-focus-drift-after-pair"
        )
        XCTAssertEqual(
            receipt,
            .notStarted(.targetIdentityChanged),
            "exact focus/selection drift after pair readback must fail before output"
        )
        XCTAssertEqual(backend.operations, [.prepare])
        XCTAssertFalse(backend.operations.contains(.down))
        XCTAssertFalse(backend.operations.contains(.up))
    }

    func test_v5ApplicationBoundResponderSecurityDriftAfterPairWithoutEpochDestroysPairAndPostsNothing() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let runtime = V5ReviewSubmissionRawRuntime(binding: .applicationBoundCurrentFocus)
        let backend = V5ReviewSubmissionEventBackend()
        backend.onPrepare = {
            // A same-application responder/security change is deliberately not
            // allowed to hide behind an unchanged combined epoch.
            runtime.setValidationFailure(.securityRejected)
        }
        let executor = ReviewSubmissionExecutor(
            controlPlane: controlPlane,
            committer: ReviewUnicodeCommitter(backend: backend),
            rawAccessibility: runtime
        )
        let target = try await captureTarget(
            using: executor,
            request: ReviewTargetCaptureRequestDescriptor(
                generation: 5,
                application: V5ReviewSubmissionFixtures.identity
            )
        )

        let receipt = try await submitRawAttempt(
            using: executor,
            controlPlane: controlPlane,
            target: target,
            recorder: recorder,
            draft: "application-bound-security-drift-after-pair"
        )
        XCTAssertEqual(
            receipt,
            .notStarted(.securityRejected),
            "application-bound responder/security drift after pair must fail closed"
        )
        XCTAssertEqual(backend.operations, [.prepare])
        XCTAssertFalse(backend.operations.contains(.down))
        XCTAssertFalse(backend.operations.contains(.up))
    }

    func test_v5FinalCompositeTransitionsRejectSecureTrustIdentityAndFrontmostDriftButAllowSafeOrdinaryMiss() async throws {
        let scenarios: [(String, ReviewPreBoundaryFailure)] = [
            ("Secure Input", .securityRejected),
            ("Accessibility trust", .securityRejected),
            ("running identity", .targetIdentityChanged),
            ("frontmost application", .frontmostChanged)
        ]

        for (label, failure) in scenarios {
            let recorder = V5ReviewSubmissionEventRecorder()
            let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
            let runtime = V5ReviewSubmissionRawRuntime(binding: .applicationBoundCurrentFocus)
            let backend = V5ReviewSubmissionEventBackend()
            backend.onPrepare = {
                // These are the trailing-composite transitions. The current
                // candidate has no post-pair composite, so each row is RED.
                runtime.setValidationFailure(failure)
            }
            let executor = ReviewSubmissionExecutor(
                controlPlane: controlPlane,
                committer: ReviewUnicodeCommitter(backend: backend),
                rawAccessibility: runtime
            )
            let target = try await captureTarget(
                using: executor,
                request: ReviewTargetCaptureRequestDescriptor(
                    generation: 5,
                    application: V5ReviewSubmissionFixtures.identity
                )
            )

            let receipt = try await submitRawAttempt(
                using: executor,
                controlPlane: controlPlane,
                target: target,
                recorder: recorder,
                draft: "composite-\(label)"
            )
            XCTAssertEqual(receipt, .notStarted(failure), label)
            XCTAssertEqual(backend.operations, [.prepare], label)
            XCTAssertFalse(backend.operations.contains(.down), label)
            XCTAssertFalse(backend.operations.contains(.up), label)
        }

        // An ordinary noValue/unsupported application-bound miss remains
        // admissible only when the trailing composite is still safe.
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let runtime = V5ReviewSubmissionRawRuntime(binding: .applicationBoundCurrentFocus)
        let backend = V5ReviewSubmissionEventBackend()
        let executor = ReviewSubmissionExecutor(
            controlPlane: controlPlane,
            committer: ReviewUnicodeCommitter(backend: backend),
            rawAccessibility: runtime
        )
        let target = try await captureTarget(
            using: executor,
            request: ReviewTargetCaptureRequestDescriptor(
                generation: 5,
                application: V5ReviewSubmissionFixtures.identity
            )
        )
        let receipt = try await submitRawAttempt(
            using: executor,
            controlPlane: controlPlane,
            target: target,
            recorder: recorder,
            draft: "ordinary-miss-safe-trailing-composite"
        )
        guard case .submittedUnverified = receipt else {
            return XCTFail("a safe ordinary application-bound miss must remain allowed")
        }
        XCTAssertEqual(backend.operations, [.prepare, .down, .up])
    }

    func test_v5AdmittedBeforeDeadlineStartAfterDeadlineEmitsOneTerminalAndNoRawWork() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let startRecorder = V5ReviewSubmissionStartRecorder()
        controlPlane.attachStartHandler(startRecorder.append)
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        let handle = try XCTUnwrap(issuer.issue())
        let deadline = DispatchTime.now().uptimeNanoseconds + 50_000_000
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: handle,
                request: makeSubmissionRequest(
                    targetID: CapturedReviewTargetID(),
                    draft: "PRIVATE_EXPIRED_START_DRAFT"
                ),
                absolutePreBoundaryDeadline: deadline
            )
        )
        let admissionAccepted = await recorder.waitFor {
            if case .admissionAccepted(handle) = $0 { return true }
            return false
        }
        XCTAssertTrue(admissionAccepted)

        try await Task.sleep(for: .milliseconds(80))
        controlPlane.enqueueStart(handle)
        let terminal = await recorder.waitForTerminal(for: handle)

        XCTAssertEqual(
            terminal,
            .notStarted(.deadline),
            "an admitted handle that starts after its immutable deadline must terminalize exactly once"
        )
        XCTAssertEqual(startRecorder.handles, [], "expired start must not invoke raw work")
        XCTAssertNil(controlPlane.valueStore.activeHandle)
        XCTAssertTrue(controlPlane.valueStore.records.isEmpty)
    }

    func test_baselineProductionFinalPairDetectsReentrantEpochAccessWithoutHanging() {
        let inputMonitor = ReentrancyDetectingInputMonitor()
        let activationMonitor = R1ReviewActivationMonitor()
        let session = ReviewDeliveryMonitoringSession(
            inputMonitor: inputMonitor,
            activationMonitor: activationMonitor,
            modifierSampler: { [] }
        )

        XCTAssertTrue(session.arm())
        XCTAssertTrue(session.captureBaselines())

        var postPairCount = 0
        XCTAssertTrue(
            session.performFinalPair {
                postPairCount += 1
            },
            "the injected monitor must complete immediately without using the real non-recursive lock"
        )
        XCTAssertEqual(postPairCount, 1)
        XCTAssertEqual(
            inputMonitor.reentrantAccessCount,
            0,
            "the production commit gate must not read interferenceEpoch again from inside its epoch gate"
        )
        session.stop()
    }

    func test_productionCommitGateNeverReentersNonrecursiveEpochLock() {
        let inputMonitor = ReentrancyDetectingInputMonitor()
        let activationMonitor = R1ReviewActivationMonitor()
        let session = ReviewDeliveryMonitoringSession(
            inputMonitor: inputMonitor,
            activationMonitor: activationMonitor,
            modifierSampler: { [] }
        )

        XCTAssertTrue(session.arm())
        XCTAssertTrue(session.captureBaselines())
        _ = session.performFinalPair {}

        XCTAssertEqual(
            inputMonitor.reentrantAccessCount,
            0,
            "the concrete production commit gate must have one owner and no callback-under-lock epoch read"
        )
        session.stop()
    }

    func test_combinedEpochDriftBeforeCommitPostsNothing() {
        let inputMonitor = ReentrancyDetectingInputMonitor()
        inputMonitor.advanceEpochBeforeNextPair = true
        let activationMonitor = R1ReviewActivationMonitor()
        let session = ReviewDeliveryMonitoringSession(
            inputMonitor: inputMonitor,
            activationMonitor: activationMonitor,
            modifierSampler: { [] }
        )

        XCTAssertTrue(session.arm())
        XCTAssertTrue(session.captureBaselines())

        var postPairCount = 0
        XCTAssertFalse(
            session.performFinalPair {
                postPairCount += 1
            },
            "a combined input epoch drift before commit must reject the pair"
        )
        XCTAssertEqual(postPairCount, 0)
        session.stop()
    }

    func test_productionCommitGateCompletesBeforeDeadlineWithRealEpochAndBackend() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let backend = V5ReviewSubmissionEventBackend()
        let runtime = V5ReviewSubmissionRawRuntime()
        let executor = ReviewSubmissionExecutor(
            controlPlane: controlPlane,
            committer: ReviewUnicodeCommitter(backend: backend),
            rawAccessibility: runtime
        )
        let requestDescriptor = ReviewTargetCaptureRequestDescriptor(
            generation: 5,
            application: V5ReviewSubmissionFixtures.identity
        )
        let target = try await captureTarget(
            using: executor,
            request: requestDescriptor
        )
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        let handle = try XCTUnwrap(issuer.issue())
        let request = makeSubmissionRequest(
            targetID: target.targetID,
            generation: target.generation,
            draft: "exact\nUTF16"
        )
        let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000

        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: handle,
                request: request,
                absolutePreBoundaryDeadline: deadline
            )
        )
        let admissionAccepted = await recorder.waitFor {
                if case .admissionAccepted(handle) = $0 { return true }
                return false
            }
        XCTAssertTrue(admissionAccepted)
        controlPlane.enqueueStart(handle)

        let terminalReceipt = await recorder.waitForTerminal(for: handle)
        let terminal = try XCTUnwrap(terminalReceipt)
        guard case .submittedUnverified(let observation) = terminal else {
            return XCTFail("real executor composition must reach a typed submitted receipt")
        }
        XCTAssertTrue(observation.mandatoryKeyUpAttempted)
        XCTAssertTrue(observation.postflightStable)
        XCTAssertEqual(backend.operations, [.prepare, .down, .up])
        XCTAssertEqual(backend.preparedUTF16, [Array(request.frozenDraft.utf16)])
        XCTAssertEqual(backend.postedTargetProcessIdentifiers, [
            V5ReviewSubmissionFixtures.identity.processIdentifier,
            V5ReviewSubmissionFixtures.identity.processIdentifier
        ])
    }

    func test_admissionPreservesExactDescriptorAndAbsoluteDeadlineThroughRawClaim() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let startRecorder = V5ReviewSubmissionStartRecorder()
        controlPlane.attachStartHandler(startRecorder.append)
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        let handle = try XCTUnwrap(issuer.issue())
        let targetID = CapturedReviewTargetID()
        let request = makeSubmissionRequest(
            targetID: targetID,
            generation: 77,
            revision: 14,
            attemptOrdinal: 3,
            draft: "preserve\nall fields",
            confirmationUptime: 123
        )
        let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
        let envelope = ReviewSubmissionAdmissionEnvelope(
            handle: handle,
            request: request,
            absolutePreBoundaryDeadline: deadline
        )

        controlPlane.enqueueAdmission(envelope)
        let admissionAccepted = await recorder.waitFor {
                if case .admissionAccepted(handle) = $0 { return true }
                return false
            }
        XCTAssertTrue(admissionAccepted)
        controlPlane.enqueueStart(handle)
        let startObserved = await startRecorder.waitFor(handle)
        XCTAssertTrue(startObserved)

        let claim = try XCTUnwrap(controlPlane.claim(handle))
        XCTAssertEqual(claim.request, request)
        XCTAssertEqual(claim.deadline, deadline)
        XCTAssertEqual(claim.request.capturedTargetID, targetID)
        XCTAssertEqual(claim.request.frozenDraft, "preserve\nall fields")
    }

    func test_cancelAfterAdmissionEnqueueBeforeRawStartPerformsZeroRawWork() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let startRecorder = V5ReviewSubmissionStartRecorder()
        controlPlane.attachStartHandler(startRecorder.append)
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        let handle = try XCTUnwrap(issuer.issue())
        let request = makeSubmissionRequest(targetID: CapturedReviewTargetID())
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: handle,
                request: request,
                absolutePreBoundaryDeadline: DispatchTime.now().uptimeNanoseconds + 1_000_000_000
            )
        )
        let admissionAccepted = await recorder.waitFor {
                if case .admissionAccepted(handle) = $0 { return true }
                return false
            }
        XCTAssertTrue(admissionAccepted)
        controlPlane.enqueueCancellation(handle)
        let terminalReceipt = await recorder.waitForTerminal(for: handle)
        let terminal = try XCTUnwrap(terminalReceipt)
        XCTAssertEqual(terminal, .notStarted(.cancellation))
        XCTAssertEqual(startRecorder.handles, [])
        XCTAssertNil(controlPlane.valueStore.activeHandle)
        XCTAssertTrue(controlPlane.valueStore.records.isEmpty)
    }

    func test_occupiedRawExecutorKeepsControlPlaneResponsive() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let runtime = V5ReviewSubmissionRawRuntime()
        let executor = ReviewSubmissionExecutor(
            controlPlane: controlPlane,
            committer: ReviewUnicodeCommitter(backend: V5ReviewSubmissionEventBackend()),
            rawAccessibility: runtime
        )
        let target = try await captureTarget(
            using: executor,
            request: ReviewTargetCaptureRequestDescriptor(
                generation: 5,
                application: V5ReviewSubmissionFixtures.identity
            )
        )
        let captureEntered = DispatchSemaphore(value: 0)
        let captureRelease = DispatchSemaphore(value: 0)
        runtime.captureBlock = captureEntered
        runtime.captureRelease = captureRelease
        executor.capture(
            ReviewTargetCaptureRequestDescriptor(
                generation: 6,
                application: V5ReviewSubmissionFixtures.identity
            )
        ) { _ in }
        XCTAssertEqual(captureEntered.wait(timeout: .now() + 1), .success)

        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        let handle = try XCTUnwrap(issuer.issue())
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: handle,
                request: makeSubmissionRequest(targetID: target.targetID),
                absolutePreBoundaryDeadline: DispatchTime.now().uptimeNanoseconds + 1_000_000_000
            )
        )
        let admissionAccepted = await recorder.waitFor {
            if case .admissionAccepted(handle) = $0 { return true }
            return false
        }
        XCTAssertTrue(admissionAccepted)
        controlPlane.enqueueStart(handle)
        controlPlane.enqueueCancellation(handle)
        let cancellation = await recorder.waitForCancellation(for: handle)
        XCTAssertEqual(cancellation, .latched)
        XCTAssertEqual(runtime.captureCallCount, 2)
        XCTAssertEqual(runtime.validateCallCount, 0)
        captureRelease.signal()
        let terminal = await recorder.waitForTerminal(for: handle)
        XCTAssertEqual(terminal, .notStarted(.cancellation))
    }

    func test_cancelWhilePrebaselineAXBlockedThenReleaseBeforeDeadlinePostsNothing() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let runtime = V5ReviewSubmissionRawRuntime()
        let executor = ReviewSubmissionExecutor(
            controlPlane: controlPlane,
            committer: ReviewUnicodeCommitter(backend: V5ReviewSubmissionEventBackend()),
            rawAccessibility: runtime
        )
        let target = try await captureTarget(
            using: executor,
            request: ReviewTargetCaptureRequestDescriptor(
                generation: 5,
                application: V5ReviewSubmissionFixtures.identity
            )
        )
        let validationEntered = DispatchSemaphore(value: 0)
        let validationRelease = DispatchSemaphore(value: 0)
        runtime.validationBlock = validationEntered
        runtime.validationRelease = validationRelease
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        let handle = try XCTUnwrap(issuer.issue())
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: handle,
                request: makeSubmissionRequest(targetID: target.targetID),
                absolutePreBoundaryDeadline: DispatchTime.now().uptimeNanoseconds + 1_000_000_000
            )
        )
        let admissionAccepted = await recorder.waitFor {
            if case .admissionAccepted(handle) = $0 { return true }
            return false
        }
        XCTAssertTrue(admissionAccepted)
        controlPlane.enqueueStart(handle)
        XCTAssertEqual(validationEntered.wait(timeout: .now() + 1), .success)
        controlPlane.enqueueCancellation(handle)
        let cancellation = await recorder.waitForCancellation(for: handle)
        XCTAssertEqual(cancellation, .latched)
        validationRelease.signal()
        let terminal = await recorder.waitForTerminal(for: handle)
        XCTAssertEqual(terminal, .notStarted(.cancellation))
        XCTAssertEqual(runtime.validateCallCount, 1)
    }

    func test_cancelAfterBaselineBeforeGatePostsNothing() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let backend = V5ReviewSubmissionEventBackend()
        let prepareEntered = DispatchSemaphore(value: 0)
        let prepareRelease = DispatchSemaphore(value: 0)
        backend.prepareEntered = prepareEntered
        backend.prepareRelease = prepareRelease
        let executor = ReviewSubmissionExecutor(
            controlPlane: controlPlane,
            committer: ReviewUnicodeCommitter(backend: backend),
            rawAccessibility: V5ReviewSubmissionRawRuntime()
        )
        let target = try await captureTarget(
            using: executor,
            request: ReviewTargetCaptureRequestDescriptor(
                generation: 5,
                application: V5ReviewSubmissionFixtures.identity
            )
        )
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        let handle = try XCTUnwrap(issuer.issue())
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: handle,
                request: makeSubmissionRequest(targetID: target.targetID),
                absolutePreBoundaryDeadline: DispatchTime.now().uptimeNanoseconds + 1_000_000_000
            )
        )
        let admissionAccepted = await recorder.waitFor {
            if case .admissionAccepted(handle) = $0 { return true }
            return false
        }
        XCTAssertTrue(admissionAccepted)
        controlPlane.enqueueStart(handle)
        XCTAssertEqual(prepareEntered.wait(timeout: .now() + 1), .success)
        controlPlane.enqueueCancellation(handle)
        let cancellation = await recorder.waitForCancellation(for: handle)
        XCTAssertEqual(cancellation, .latched)
        prepareRelease.signal()
        let terminal = await recorder.waitForTerminal(for: handle)
        XCTAssertEqual(terminal, .notStarted(.cancellation))
        XCTAssertEqual(backend.postedTargetProcessIdentifiers, [])
    }

    func test_releasedCapturedTargetFailsBeforeRawEventConstruction() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let backend = V5ReviewSubmissionEventBackend()
        let executor = ReviewSubmissionExecutor(
            controlPlane: controlPlane,
            committer: ReviewUnicodeCommitter(backend: backend),
            rawAccessibility: V5ReviewSubmissionRawRuntime()
        )
        let target = try await captureTarget(
            using: executor,
            request: ReviewTargetCaptureRequestDescriptor(
                generation: 5,
                application: V5ReviewSubmissionFixtures.identity
            )
        )
        let replacement = try await captureTarget(
            using: executor,
            request: ReviewTargetCaptureRequestDescriptor(
                generation: 6,
                application: V5ReviewSubmissionFixtures.identity
            )
        )
        executor.release(target.targetID)
        _ = replacement
        try await Task.sleep(for: .milliseconds(10))
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        let handle = try XCTUnwrap(issuer.issue())
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: handle,
                request: makeSubmissionRequest(targetID: target.targetID),
                absolutePreBoundaryDeadline: DispatchTime.now().uptimeNanoseconds + 1_000_000_000
            )
        )
        let admissionAccepted = await recorder.waitFor {
            if case .admissionAccepted(handle) = $0 { return true }
            return false
        }
        XCTAssertTrue(admissionAccepted)
        controlPlane.enqueueStart(handle)
        let terminal = await recorder.waitForTerminal(for: handle)
        XCTAssertEqual(terminal, .notStarted(.targetIdentityChanged))
        XCTAssertEqual(backend.operations, [])
    }

    func test_foreignOrStaleStartIsRejectedBeforeRawWork() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let startRecorder = V5ReviewSubmissionStartRecorder()
        controlPlane.attachStartHandler(startRecorder.append)
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        let foreignPlane = ReviewSubmissionControlPlane()
        let foreignIssuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: foreignPlane.instanceNonce
        )
        let foreign = try XCTUnwrap(foreignIssuer.issue())
        let neverAdmitted = try XCTUnwrap(issuer.issue())
        controlPlane.enqueueStart(foreign)
        controlPlane.enqueueStart(neverAdmitted)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(startRecorder.handles, [])

        let admitted = try XCTUnwrap(issuer.issue())
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: admitted,
                request: makeSubmissionRequest(targetID: CapturedReviewTargetID()),
                absolutePreBoundaryDeadline: DispatchTime.now().uptimeNanoseconds + 1_000_000_000
            )
        )
        let admissionAccepted = await recorder.waitFor {
                if case .admissionAccepted(admitted) = $0 { return true }
                return false
            }
        XCTAssertTrue(admissionAccepted)
        controlPlane.enqueueCancellation(admitted)
        let admittedTerminal = await recorder.waitForTerminal(for: admitted)
        XCTAssertNotNil(admittedTerminal)
        controlPlane.enqueueStart(admitted)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(startRecorder.handles, [])
    }

    func test_deadlineWhileWaitingForGatePostsNothing() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        controlPlane.attachStartHandler { _ in }
        let handle = try XCTUnwrap(issuer.issue())
        let request = makeSubmissionRequest(targetID: CapturedReviewTargetID())
        let deadline = DispatchTime.now().uptimeNanoseconds + 50_000_000
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: handle,
                request: request,
                absolutePreBoundaryDeadline: deadline
            )
        )
        let admissionAccepted = await recorder.waitFor {
                if case .admissionAccepted(handle) = $0 { return true }
                return false
            }
        XCTAssertTrue(admissionAccepted)
        controlPlane.enqueueStart(handle)
        try await Task.sleep(for: .milliseconds(10))
        let claim = try XCTUnwrap(controlPlane.claim(handle))
        XCTAssertTrue(controlPlane.updatePhase(.preparing, for: handle))
        controlPlane.valueStore.lock.lock()
        let allowed = controlPlane.commitMayBeginLocked(
            handle,
            input: ReviewCommitGateInput(
                expectedCombinedEpoch: claim.expectedCombinedEpoch,
                expectedGlobalCombinedEpoch: claim.expectedGlobalCombinedEpoch,
                liveGlobalCombinedEpoch: claim.expectedGlobalCombinedEpoch,
                deadline: claim.deadline,
                now: claim.deadline
            )
        )
        controlPlane.valueStore.lock.unlock()
        XCTAssertFalse(allowed, "a gate deadline is final and must reject before any raw post")
        controlPlane.enqueueCancellation(handle)
        _ = await recorder.waitForTerminal(for: handle)
    }

    func test_deadlineRecheckedUnderGateImmediatelyBeforeDown() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        controlPlane.attachStartHandler { _ in }
        let handle = try XCTUnwrap(issuer.issue())
        let request = makeSubmissionRequest(targetID: CapturedReviewTargetID())
        let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: handle,
                request: request,
                absolutePreBoundaryDeadline: deadline
            )
        )
        let admissionAccepted = await recorder.waitFor {
            if case .admissionAccepted(handle) = $0 { return true }
            return false
        }
        XCTAssertTrue(admissionAccepted)
        controlPlane.enqueueStart(handle)
        try await Task.sleep(for: .milliseconds(10))
        let claim = try XCTUnwrap(controlPlane.claim(handle))
        XCTAssertTrue(controlPlane.updatePhase(.preparing, for: handle))
        controlPlane.valueStore.lock.lock()
        let beforeDeadline = controlPlane.commitMayBeginLocked(
            handle,
            input: ReviewCommitGateInput(
                expectedCombinedEpoch: claim.expectedCombinedEpoch,
                expectedGlobalCombinedEpoch: claim.expectedGlobalCombinedEpoch,
                liveGlobalCombinedEpoch: claim.expectedGlobalCombinedEpoch,
                deadline: claim.deadline,
                now: claim.deadline - 1
            )
        )
        let atDeadline = controlPlane.commitMayBeginLocked(
            handle,
            input: ReviewCommitGateInput(
                expectedCombinedEpoch: claim.expectedCombinedEpoch,
                expectedGlobalCombinedEpoch: claim.expectedGlobalCombinedEpoch,
                liveGlobalCombinedEpoch: claim.expectedGlobalCombinedEpoch,
                deadline: claim.deadline,
                now: claim.deadline
            )
        )
        controlPlane.valueStore.lock.unlock()
        XCTAssertTrue(beforeDeadline)
        XCTAssertFalse(atDeadline)
        controlPlane.enqueueCancellation(handle)
        _ = await recorder.waitForTerminal(for: handle)
    }

    func test_physicalInputAtGateOrdersAfterCompleteMandatoryPair() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let backend = V5ReviewSubmissionEventBackend()
        backend.advanceCombinedEpochOnDown = true
        let executor = ReviewSubmissionExecutor(
            controlPlane: controlPlane,
            committer: ReviewUnicodeCommitter(backend: backend),
            rawAccessibility: V5ReviewSubmissionRawRuntime()
        )
        let target = try await captureTarget(
            using: executor,
            request: ReviewTargetCaptureRequestDescriptor(
                generation: 5,
                application: V5ReviewSubmissionFixtures.identity
            )
        )
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        let handle = try XCTUnwrap(issuer.issue())
        let request = makeSubmissionRequest(targetID: target.targetID)
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: handle,
                request: request,
                absolutePreBoundaryDeadline: DispatchTime.now().uptimeNanoseconds + 1_000_000_000
            )
        )
        let admissionAccepted = await recorder.waitFor {
                if case .admissionAccepted(handle) = $0 { return true }
                return false
            }
        XCTAssertTrue(admissionAccepted)
        controlPlane.enqueueStart(handle)
        let terminalReceipt = await recorder.waitForTerminal(for: handle)
        let terminal = try XCTUnwrap(terminalReceipt)
        guard case .submittedUnverified(let observation) = terminal else {
            return XCTFail("physical input after down must not suppress the mandatory up")
        }
        XCTAssertTrue(observation.mandatoryKeyUpAttempted)
        XCTAssertTrue(
            backend.physicalEpochCallbackWasAttempted,
            "the physical observer callback must be initiated from a separate queue during down"
        )
        XCTAssertFalse(
            backend.physicalEpochAdvancedBeforeUp,
            "a physical observer may contend during down but cannot linearize before mandatory up"
        )
        XCTAssertTrue(
            backend.waitForPhysicalEpochAdvance(),
            "the physical observer must complete after the reservation releases"
        )
        XCTAssertFalse(observation.postflightStable)
        XCTAssertEqual(backend.operations, [.prepare, .down, .up])
    }

    func test_cancelDuringGateAdmissionPostsNothing() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let startRecorder = V5ReviewSubmissionStartRecorder()
        controlPlane.attachStartHandler(startRecorder.append)
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        let handle = try XCTUnwrap(issuer.issue())
        let request = makeSubmissionRequest(targetID: CapturedReviewTargetID())
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: handle,
                request: request,
                absolutePreBoundaryDeadline: DispatchTime.now().uptimeNanoseconds + 1_000_000_000
            )
        )
        let admissionAccepted = await recorder.waitFor {
                if case .admissionAccepted(handle) = $0 { return true }
                return false
            }
        XCTAssertTrue(admissionAccepted)
        controlPlane.enqueueStart(handle)
        let startObserved = await startRecorder.waitFor(handle)
        XCTAssertTrue(startObserved)
        let claim = try XCTUnwrap(controlPlane.claim(handle))
        XCTAssertTrue(controlPlane.updatePhase(.preparing, for: handle))
        controlPlane.valueStore.lock.lock()
        controlPlane.enqueueCancellation(handle)
        try await Task.sleep(for: .milliseconds(20))
        let cancelledWhileLocked = controlPlane.cancellationRequestedLocked(handle)
        controlPlane.valueStore.lock.unlock()
        XCTAssertFalse(
            cancelledWhileLocked,
            "cancellation must not be observed until the gate owner releases its lock"
        )
        _ = claim
        let cancellation = await recorder.waitForCancellation(for: handle)
        XCTAssertNotNil(cancellation)
        _ = await recorder.waitForTerminal(for: handle)
    }

    func test_staleAttemptCancellationCannotCancelLaterAttempt() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        let first = try XCTUnwrap(issuer.issue())
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: first,
                request: makeSubmissionRequest(targetID: CapturedReviewTargetID()),
                absolutePreBoundaryDeadline: DispatchTime.now().uptimeNanoseconds + 1_000_000_000
            )
        )
        let admissionAccepted = await recorder.waitFor {
                if case .admissionAccepted(first) = $0 { return true }
                return false
            }
        XCTAssertTrue(admissionAccepted)
        controlPlane.enqueueCancellation(first)
        let firstTerminal = await recorder.waitForTerminal(for: first)
        XCTAssertNotNil(firstTerminal)

        let second = try XCTUnwrap(issuer.issue())
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: second,
                request: makeSubmissionRequest(targetID: CapturedReviewTargetID()),
                absolutePreBoundaryDeadline: DispatchTime.now().uptimeNanoseconds + 1_000_000_000
            )
        )
        let secondAdmissionAccepted = await recorder.waitFor {
                if case .admissionAccepted(second) = $0 { return true }
                return false
            }
        XCTAssertTrue(secondAdmissionAccepted)
        controlPlane.enqueueCancellation(first)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(controlPlane.valueStore.activeHandle, second)
        XCTAssertNotNil(controlPlane.valueStore.records[second])
        controlPlane.enqueueCancellation(second)
        let secondTerminal = await recorder.waitForTerminal(for: second)
        XCTAssertNotNil(secondTerminal)
    }

    func test_cancelAfterDownStillAttemptsExactlyOneUpAndReturnsSubmittedUnverified() async throws {
        let recorder = V5ReviewSubmissionEventRecorder()
        let controlPlane = ReviewSubmissionControlPlane(eventHandler: recorder.append)
        let backend = V5ReviewSubmissionEventBackend(holdDown: true)
        let executor = ReviewSubmissionExecutor(
            controlPlane: controlPlane,
            committer: ReviewUnicodeCommitter(backend: backend),
            rawAccessibility: V5ReviewSubmissionRawRuntime()
        )
        let target = try await captureTarget(
            using: executor,
            request: ReviewTargetCaptureRequestDescriptor(
                generation: 5,
                application: V5ReviewSubmissionFixtures.identity
            )
        )
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        let handle = try XCTUnwrap(issuer.issue())
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: handle,
                request: makeSubmissionRequest(targetID: target.targetID),
                absolutePreBoundaryDeadline: DispatchTime.now().uptimeNanoseconds + 1_000_000_000
            )
        )
        let admissionAccepted = await recorder.waitFor {
                if case .admissionAccepted(handle) = $0 { return true }
                return false
            }
        XCTAssertTrue(admissionAccepted)
        controlPlane.enqueueStart(handle)
        let downObserved = backend.waitForDown()
        XCTAssertTrue(downObserved)
        var heartbeat = 0
        let heartbeatTask = Task { @MainActor in
            while !Task.isCancelled {
                heartbeat += 1
                try? await Task.sleep(for: .milliseconds(2))
            }
        }
        controlPlane.enqueueCancellation(handle)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertGreaterThan(heartbeat, 0, "MainActor must remain live while raw commit is blocked")
        backend.releaseDown()
        let terminalReceipt = await recorder.waitForTerminal(for: handle)
        let terminal = try XCTUnwrap(terminalReceipt)
        heartbeatTask.cancel()
        guard case .submittedUnverified(let observation) = terminal else {
            return XCTFail("post-boundary cancellation must remain a submitted uncertainty")
        }
        XCTAssertTrue(observation.mandatoryKeyUpAttempted)
        XCTAssertTrue(observation.cancellationObservedAfterDown)
        XCTAssertFalse(observation.postflightStable)
        XCTAssertEqual(backend.operations, [.prepare, .down, .up])
    }

    func test_safePlainTextTargetsCapturedPIDAndChecksSameDestinationBeforeAndAfterPosting() throws {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let eventPoster = FakeFinalTextKeyEventPoster()
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster()
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: eventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false]),
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [42])
        )
        let destination = makeDestination(processIdentifier: 42)
        var validationResults = [true, false]
        var validationCallCount = 0

        let result = output.insertOnce(
            "safe plain text",
            destination: destination,
            validateBeforeMutation: {
                validationCallCount += 1
                return validationResults.removeFirst()
            },
            validateAfterPosting: {
                validationCallCount += 1
                return validationResults.removeFirst()
            },
            postPairIfPreflightRemainsValid: { postPair in
                postPair()
                return true
            }
        )

        XCTAssertEqual(result, .deliveryUncertain)
        XCTAssertEqual(validationCallCount, 2)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(eventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, ["safe plain text"])
        XCTAssertEqual(currentFocusEventPoster.destinationProcessIdentifiers, [42])
    }

    func test_failedPreflightValidationDoesNotTouchPasteboardOrPostSyntheticInput() throws {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let eventPoster = FakeFinalTextKeyEventPoster()
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: eventPoster
        )

        let result = output.insertOnce(
            "safe plain text",
            destination: makeDestination(processIdentifier: 77),
            validateDestination: { false }
        )

        XCTAssertEqual(result, .destinationInvalid)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(eventPoster.destinationProcessIdentifiers, [])
    }

    func test_safePlainTextRetainsAutomaticFallbackWhenDeliveryIsStable() throws {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let eventPoster = FakeFinalTextKeyEventPoster()
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster()
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: eventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false]),
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [88])
        )
        var validationCallCount = 0

        let result = output.insertOnce(
            "safe plain text",
            destination: makeDestination(processIdentifier: 88),
            validateBeforeMutation: {
                validationCallCount += 1
                return true
            },
            validateAfterPosting: {
                validationCallCount += 1
                return true
            },
            postPairIfPreflightRemainsValid: { postPair in
                postPair()
                return true
            }
        )

        XCTAssertEqual(result, .submittedUnverified)
        XCTAssertEqual(validationCallCount, 2)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(eventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, ["safe plain text"])
        XCTAssertEqual(currentFocusEventPoster.destinationProcessIdentifiers, [88])
    }

    func test_keyEventPostingFailureIsReportedForManualRecovery() throws {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let eventPoster = FakeFinalTextKeyEventPoster()
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster(result: .deliveryFailed)
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: eventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false]),
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [99])
        )

        let result = output.insertOnce(
            "safe plain text",
            destination: makeDestination(processIdentifier: 99),
            validateBeforeMutation: { true },
            validateAfterPosting: { true },
            postPairIfPreflightRemainsValid: { postPair in
                postPair()
                return true
            }
        )

        XCTAssertEqual(result, .deliveryFailed)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(eventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, ["safe plain text"])
        XCTAssertEqual(currentFocusEventPoster.destinationProcessIdentifiers, [99])
    }

    func test_currentFocusStableSafePIDPostsUnicodeOnceWithoutTouchingPasteboard() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let boundEventPoster = FakeFinalTextKeyEventPoster()
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster()
        let secureInput = FakeSecureInputStateProvider(states: [false, false])
        let frontmostProcess = FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: boundEventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess
        )

        let result = output.insertAtCurrentFocusOnce("直接输入中文")

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(boundEventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, ["直接输入中文"])
        XCTAssertEqual(currentFocusEventPoster.destinationProcessIdentifiers, [42])
        XCTAssertEqual(secureInput.queryCount, 2)
        XCTAssertEqual(frontmostProcess.queryCount, 2)
    }

    func test_reviewApplicationBoundDraftUsesOneModifierFreeUnicodePairWithoutPasteboardOrCmdV() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let legacyEventPoster = FakeFinalTextKeyEventPoster()
        let backend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let unicodeEventPoster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: legacyEventPoster,
            currentFocusEventPoster: unicodeEventPoster,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false, false]),
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
        )
        var beforeCalls = 0
        var afterCalls = 0
        let draft = "first line\nsecond line"

        let result = output.insertReviewAtCurrentFocusOnce(
            draft,
            processIdentifier: 42,
            validateBeforeMutation: {
                beforeCalls += 1
                return .valid
            },
            validateAfterPosting: {
                afterCalls += 1
                return .valid
            }
        )

        XCTAssertEqual(result, .submittedUnverified)
        XCTAssertEqual(beforeCalls, 1)
        XCTAssertEqual(afterCalls, 1)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(legacyEventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(backend.constructedEvents.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(backend.constructedEvents.map(\.virtualKey), [nil, nil])
        XCTAssertEqual(backend.constructedEvents.map(\.utf16), [Array(draft.utf16), Array(draft.utf16)])
        XCTAssertEqual(backend.constructedEvents.map(\.flags), [[], []])
        XCTAssertEqual(backend.postedEvents.map(\.processIdentifier), [42, 42])
        XCTAssertEqual(backend.taggedUserData, [FeishuSpeechSyntheticEventTag.value, FeishuSpeechSyntheticEventTag.value])
    }

    func test_reviewExactBindingUsesOneModifierFreeUnicodePairWithoutPasteboardOrCmdV() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let legacyEventPoster = FakeFinalTextKeyEventPoster()
        let backend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let unicodeEventPoster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: legacyEventPoster,
            currentFocusEventPoster: unicodeEventPoster,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false, false]),
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
        )
        let draft = "first line\nsecond line"

        let result = output.insertOnce(
            draft,
            destination: makeDestination(processIdentifier: 42),
            validateBeforeMutation: { true },
            validateAfterPosting: { true }
        )

        XCTAssertEqual(result, .submittedUnverified)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(legacyEventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(backend.constructedEvents.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(backend.constructedEvents.map(\.virtualKey), [nil, nil])
        XCTAssertEqual(backend.constructedEvents.map(\.utf16), [Array(draft.utf16), Array(draft.utf16)])
        XCTAssertEqual(backend.constructedEvents.map(\.flags), [[], []])
        XCTAssertEqual(backend.postedEvents.map(\.processIdentifier), [42, 42])
        XCTAssertEqual(backend.taggedUserData, [FeishuSpeechSyntheticEventTag.value, FeishuSpeechSyntheticEventTag.value])
    }

    func test_reviewExactBindingPostflightUncertaintyPostsOneUnicodePairWithoutRetryOrPasteboard() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let legacyEventPoster = FakeFinalTextKeyEventPoster()
        let backend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let unicodeEventPoster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: legacyEventPoster,
            currentFocusEventPoster: unicodeEventPoster,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false, false]),
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
        )
        let draft = "first line\nsecond line"

        let result = output.insertOnce(
            draft,
            destination: makeDestination(processIdentifier: 42),
            validateBeforeMutation: { true },
            validateAfterPosting: { false }
        )

        XCTAssertEqual(result, .deliveryUncertain)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(legacyEventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(backend.constructedEvents.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(backend.constructedEvents.map(\.virtualKey), [nil, nil])
        XCTAssertEqual(backend.constructedEvents.map(\.utf16), [Array(draft.utf16), Array(draft.utf16)])
        XCTAssertEqual(backend.constructedEvents.map(\.flags), [[], []])
        XCTAssertEqual(backend.postedEvents.map(\.processIdentifier), [42, 42])
        XCTAssertEqual(backend.taggedUserData, [FeishuSpeechSyntheticEventTag.value, FeishuSpeechSyntheticEventTag.value])
    }

    func test_reviewApplicationBoundPostflightUncertaintyPostsOneUnicodePairWithoutRetryOrPasteboard() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let legacyEventPoster = FakeFinalTextKeyEventPoster()
        let backend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let unicodeEventPoster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: legacyEventPoster,
            currentFocusEventPoster: unicodeEventPoster,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false, false]),
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
        )
        let draft = "first line\nsecond line"

        let result = output.insertReviewAtCurrentFocusOnce(
            draft,
            processIdentifier: 42,
            validateBeforeMutation: { .valid },
            validateAfterPosting: { .identityChanged }
        )

        XCTAssertEqual(result, .deliveryUncertain)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(legacyEventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(backend.constructedEvents.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(backend.constructedEvents.map(\.virtualKey), [nil, nil])
        XCTAssertEqual(backend.constructedEvents.map(\.utf16), [Array(draft.utf16), Array(draft.utf16)])
        XCTAssertEqual(backend.constructedEvents.map(\.flags), [[], []])
        XCTAssertEqual(backend.postedEvents.map(\.processIdentifier), [42, 42])
        XCTAssertEqual(backend.taggedUserData, [FeishuSpeechSyntheticEventTag.value, FeishuSpeechSyntheticEventTag.value])
    }

    func test_reviewExactAndApplicationBoundPreflightFailurePostsNoUnicodePair() {
        let draft = "first line\nsecond line"
        for route in ["exact", "application"] {
            let pasteboard = FakeFinalTextPasteboardWriter()
            let legacyEventPoster = FakeFinalTextKeyEventPoster()
            let unicodeEventPoster = FakeCurrentFocusUnicodeEventPoster()
            let output = SystemFinalTextOutput(
                pasteboardWriter: pasteboard,
                keyEventPoster: legacyEventPoster,
                currentFocusEventPoster: unicodeEventPoster,
                secureInputStateProvider: FakeSecureInputStateProvider(states: [false, false]),
                frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
            )
            let result: FinalTextInsertionResult
            if route == "exact" {
                result = output.insertOnce(
                    draft,
                    destination: makeDestination(processIdentifier: 42),
                    validateBeforeMutation: { false },
                    validateAfterPosting: {
                        XCTFail("preflight rejection must not run postflight")
                        return false
                    }
                )
            } else {
                result = output.insertReviewAtCurrentFocusOnce(
                    draft,
                    processIdentifier: 42,
                    validateBeforeMutation: { .destinationInvalid },
                    validateAfterPosting: {
                        XCTFail("preflight rejection must not run postflight")
                        return .destinationInvalid
                    }
                )
            }
            XCTAssertEqual(result, .destinationInvalid, "route: \(route)")
            XCTAssertEqual(pasteboard.writtenTexts, [], "route: \(route)")
            XCTAssertEqual(legacyEventPoster.destinationProcessIdentifiers, [], "route: \(route)")
            XCTAssertEqual(unicodeEventPoster.requestedTexts, [], "route: \(route)")
        }
    }

    func test_reviewCurrentFocusUnsafeMultilineControlsRejectBeforeValidationOrMutation() {
        for draft in [
            "first\tline",
            "first\rline",
            "first\u{0000}line",
            "first\u{007F}line",
            "first\u{0085}line",
            "\n\n"
        ] {
            let pasteboard = FakeFinalTextPasteboardWriter()
            let eventPoster = FakeFinalTextKeyEventPoster()
            let output = SystemFinalTextOutput(
                pasteboardWriter: pasteboard,
                keyEventPoster: eventPoster
            )

            let result = output.insertReviewAtCurrentFocusOnce(
                draft,
                processIdentifier: 42,
                validateBeforeMutation: {
                    XCTFail("unsafe review text must be rejected before destination validation")
                    return .valid
                },
                validateAfterPosting: {
                    XCTFail("unsafe review text must not reach postflight")
                    return .valid
                }
            )

            XCTAssertEqual(result, .deliveryFailed, "draft: \(draft.debugDescription)")
            XCTAssertEqual(pasteboard.writtenTexts, [], "draft: \(draft.debugDescription)")
            XCTAssertEqual(eventPoster.destinationProcessIdentifiers, [], "draft: \(draft.debugDescription)")
        }
    }

    func test_reviewCurrentFocusTypedValidationRejectsSecurityIdentityOrDestinationBeforeMutation() {
        let failures: [(ReviewCurrentFocusValidation, FinalTextInsertionResult)] = [
            (.securityRejected, .securityRejected),
            (.identityChanged, .identityChanged),
            (.destinationInvalid, .destinationInvalid)
        ]

        for (validation, expectedResult) in failures {
            let pasteboard = FakeFinalTextPasteboardWriter()
            let eventPoster = FakeFinalTextKeyEventPoster()
            let output = SystemFinalTextOutput(
                pasteboardWriter: pasteboard,
                keyEventPoster: eventPoster
            )

            let result = output.insertReviewAtCurrentFocusOnce(
                "PRIVATE_REVIEW_DRAFT",
                processIdentifier: 42,
                validateBeforeMutation: { validation },
                validateAfterPosting: {
                    XCTFail("a rejected preflight must not reach postflight")
                    return .valid
                }
            )

            XCTAssertEqual(result, expectedResult)
            XCTAssertEqual(pasteboard.writtenTexts, [])
            XCTAssertEqual(eventPoster.destinationProcessIdentifiers, [])
        }
    }

    func test_reviewCurrentFocusPostflightIdentityChangeIsUncertainAndDoesNotRetry() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let eventPoster = FakeFinalTextKeyEventPoster()
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster()
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: eventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false]),
            frontmostProcessProvider: FakeFrontmostProcessProvider(processIdentifiers: [42])
        )

        let result = output.insertReviewAtCurrentFocusOnce(
            "PRIVATE_POSTFLIGHT_IDENTITY_CHANGE",
            processIdentifier: 42,
            validateBeforeMutation: { .valid },
            validateAfterPosting: { .identityChanged },
            postPairIfPreflightRemainsValid: { postPair in
                postPair()
                return true
            }
        )

        XCTAssertEqual(result, .deliveryUncertain)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(eventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, ["PRIVATE_POSTFLIGHT_IDENTITY_CHANGE"])
        XCTAssertEqual(currentFocusEventPoster.destinationProcessIdentifiers, [42])
    }

    func test_systemUnicodePosterConstructsCompletePrivatePairBeforePostingDownThenUpOnce() {
        let trace = FakePosterOperationTrace()
        let backend = FakeSystemUnicodeEventBackend(failure: nil, trace: trace)
        let secureInput = FakeTracingSecureInputStateProvider(isEnabled: false, trace: trace)
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: secureInput
        )
        let text = "first line\nFn held 中文"

        let result = poster.postUnicodeText(text, to: 4242)

        XCTAssertEqual(result, .posted)
        XCTAssertEqual(
            backend.operations,
            [
                "source",
                "construct-down",
                "construct-up",
                "tag-down",
                "target-down",
                "tag-up",
                "target-up",
                "readback-down",
                "readback-up",
                "secure",
                "post-down-4242",
                "post-up-4242"
            ]
        )
        XCTAssertEqual(backend.sourceStateIDs, [.privateState])
        XCTAssertEqual(backend.constructedEvents.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(
            backend.constructedEvents.map(\.sourceIdentity),
            [backend.sourceIdentity, backend.sourceIdentity]
        )
        XCTAssertEqual(backend.constructedEvents.map(\.utf16), [Array(text.utf16), Array(text.utf16)])
        XCTAssertEqual(backend.constructedEvents.map(\.flags), [[], []])
        XCTAssertEqual(backend.postedEvents.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(backend.postedEvents.map(\.processIdentifier), [4242, 4242])
        XCTAssertEqual(
            backend.taggedUserData,
            Array(repeating: FeishuSpeechSyntheticEventTag.value, count: 2)
        )
        XCTAssertEqual(secureInput.queryCount, 1)
    }

    func test_v4ReviewUnicodePairAcceptsExactUTF16CapAndRejectsSurrogateOverflowBeforeConstruction() {
        let acceptedText = String(repeating: "a", count: 16_382) + "😀"
        XCTAssertEqual(
            acceptedText.utf16.count,
            16_384,
            "the boundary fixture must count the non-BMP character as its intact surrogate pair"
        )
        let acceptedBackend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let acceptedPoster = SystemFinalTextCurrentFocusEventPoster(
            backend: acceptedBackend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )

        XCTAssertEqual(acceptedPoster.postUnicodeText(acceptedText, to: 42), .posted)
        XCTAssertEqual(
            acceptedBackend.constructedEvents.map(\.utf16),
            [Array(acceptedText.utf16), Array(acceptedText.utf16)]
        )
        XCTAssertEqual(
            acceptedBackend.postedEvents.map(\.phase),
            [.keyDown, .keyUp],
            "exactly one complete pair is allowed at the 16,384 UTF-16-unit boundary"
        )
        XCTAssertEqual(
            acceptedBackend.constructedEvents.map(\.sourceProcessIdentifier),
            [getpid(), getpid()],
            "both prepared events must carry the producing process provenance"
        )
        XCTAssertEqual(
            acceptedBackend.constructedEvents.map(\.sourceIdentity),
            [acceptedBackend.sourceIdentity, acceptedBackend.sourceIdentity]
        )
        XCTAssertEqual(acceptedBackend.constructedEvents.map(\.flags), [[], []])
        XCTAssertEqual(
            acceptedBackend.constructedEvents.map(\.userData),
            [FeishuSpeechSyntheticEventTag.value, FeishuSpeechSyntheticEventTag.value]
        )
        XCTAssertEqual(acceptedBackend.postedEvents.map(\.processIdentifier), [42, 42])

        let rejectedText = String(repeating: "a", count: 16_383) + "😀"
        XCTAssertEqual(rejectedText.utf16.count, 16_385)
        let rejectedBackend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let rejectedPoster = SystemFinalTextCurrentFocusEventPoster(
            backend: rejectedBackend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )

        XCTAssertEqual(
            rejectedPoster.postUnicodeText(rejectedText, to: 42),
            .deliveryFailed,
            "one unit over the product cap must fail before event construction"
        )
        XCTAssertEqual(rejectedBackend.constructedEvents.count, 0)
        XCTAssertEqual(rejectedBackend.postedEvents, [])
    }

    func test_v4PreparedPairReadbackFaultsFailBeforeAnyPost() {
        for fault in FakeSystemUnicodeEventBackend.ReadbackFault.allCases {
            let backend = FakeSystemUnicodeEventBackend(
                failure: nil,
                trace: FakePosterOperationTrace()
            )
            backend.readbackFault = fault
            let poster = SystemFinalTextCurrentFocusEventPoster(
                backend: backend,
                secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
            )

            XCTAssertEqual(
                poster.postUnicodeText("PRIVATE_READBACK_FAULT", to: 4242),
                .deliveryFailed,
                "readback fault \(fault) must remain in the notStarted phase"
            )
            XCTAssertEqual(
                backend.postedEvents,
                [],
                "readback fault \(fault) must not submit even a down event"
            )
        }
    }

    func test_v4ReviewUnicodePairHooksAreExecutablePhaseAndPIDOracles() {
        let scenarios: [(
            name: String,
            hooks: ReviewUnicodePosterHooks,
            expected: ReviewUnicodeOutputResult,
            expectedPhases: [FinalTextUnicodeEventPhase]
        )] = [
            (
                "beforeDown",
                ReviewUnicodePosterHooks(beforeDown: { false }),
                .failedBeforeSubmission(.preflightRejected),
                []
            ),
            (
                "afterDown",
                ReviewUnicodePosterHooks(afterDown: { false }),
                .submittedUnverified(.uncertain),
                [.keyDown, .keyUp]
            ),
            (
                "beforeUp",
                ReviewUnicodePosterHooks(beforeUp: { false }),
                .submittedUnverified(.uncertain),
                [.keyDown, .keyUp]
            ),
            (
                "afterUp",
                ReviewUnicodePosterHooks(afterUp: { false }),
                .submittedUnverified(.uncertain),
                [.keyDown, .keyUp]
            ),
            (
                "postflight",
                ReviewUnicodePosterHooks(postflight: { false }),
                .submittedUnverified(.uncertain),
                [.keyDown, .keyUp]
            )
        ]

        for scenario in scenarios {
            let backend = FakeSystemUnicodeEventBackend(
                failure: nil,
                trace: FakePosterOperationTrace()
            )
            let poster = SystemFinalTextCurrentFocusEventPoster(
                backend: backend,
                secureInputStateProvider: FakeSecureInputStateProvider(states: [false]),
                hooks: scenario.hooks
            )
            var pairGateCalls = 0

            let result = poster.postReviewUnicodePair(
                "PRIVATE_\(scenario.name)",
                to: 4242,
                postPairIfPreflightRemainsValid: { postPair in
                    pairGateCalls += 1
                    postPair()
                    return true
                },
                validateAfterPosting: { .valid }
            )

            XCTAssertEqual(result, scenario.expected, scenario.name)
            XCTAssertEqual(pairGateCalls, 1, scenario.name)
            XCTAssertEqual(
                backend.postedEvents.map(\.phase),
                scenario.expectedPhases,
                "phase sequence for \(scenario.name)"
            )
            XCTAssertEqual(
                backend.postedEvents.map(\.processIdentifier),
                Array(repeating: 4242, count: scenario.expectedPhases.count),
                "captured PID for \(scenario.name)"
            )
        }
    }

    func test_v4ReviewUnicodePairCancellationBeforeAndAfterBoundaryIsPhaseAware() {
        let beforeBackend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let beforePoster = SystemFinalTextCurrentFocusEventPoster(
            backend: beforeBackend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false]),
            hooks: ReviewUnicodePosterHooks(cancellation: { true })
        )
        XCTAssertEqual(
            beforePoster.postReviewUnicodePair(
                "PRIVATE_CANCEL_BEFORE_DOWN",
                to: 4242,
                postPairIfPreflightRemainsValid: { postPair in
                    postPair()
                    return true
                },
                validateAfterPosting: { .valid }
            ),
            .cancelledBeforeSubmission
        )
        XCTAssertEqual(beforeBackend.postedEvents, [])

        var cancellationCalls = 0
        let afterBackend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let afterPoster = SystemFinalTextCurrentFocusEventPoster(
            backend: afterBackend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false]),
            hooks: ReviewUnicodePosterHooks(cancellation: {
                cancellationCalls += 1
                return cancellationCalls >= 3
            })
        )
        XCTAssertEqual(
            afterPoster.postReviewUnicodePair(
                "PRIVATE_CANCEL_AFTER_DOWN",
                to: 4242,
                postPairIfPreflightRemainsValid: { postPair in
                    postPair()
                    return true
                },
                validateAfterPosting: { .valid }
            ),
            .submittedUnverified(.uncertain)
        )
        XCTAssertEqual(
            afterBackend.postedEvents.map(\.phase),
            [.keyDown, .keyUp],
            "cancellation after the boundary must still attempt the complete pair"
        )
        XCTAssertEqual(afterBackend.postedEvents.map(\.processIdentifier), [4242, 4242])
    }

    func test_v4BindingSpecificFinalValidationModifierTransitionIsPreBoundaryForExactAndApplicationRoutes() async {
        for modifier in [
            CGEventFlags.maskCommand,
            .maskShift,
            .maskControl,
            .maskAlternate,
            .maskSecondaryFn
        ] {
            for route in ["exact", "application"] {
                let runtime = R1ReviewApplicationRuntime()
                let activation = R1ReviewApplicationActivator()
                let flags = R1MutableReviewModifierFlags()
                let access = R1ReviewDestinationAccess(
                    captureResult: route == "exact"
                        ? .exact(R1ReviewFixtures.cursorToken())
                        : .nonSecureCursorUnavailable
                )
                let secureInput = R1MutableReviewSecureInputProvider()
                let backend = FakeSystemUnicodeEventBackend(
                    failure: nil,
                    trace: FakePosterOperationTrace()
                )
                let poster = SystemFinalTextCurrentFocusEventPoster(
                    backend: backend,
                    secureInputStateProvider: secureInput
                )
                let output = SystemFinalTextOutput(
                    pasteboardWriter: FakeFinalTextPasteboardWriter(),
                    keyEventPoster: FakeFinalTextKeyEventPoster(),
                    currentFocusEventPoster: poster,
                    secureInputStateProvider: secureInput,
                    frontmostProcessProvider: R1ReviewFrontmostProcessProvider(
                        runtime: runtime
                    )
                )

                if route == "exact" {
                    access.onRestore = { flags.value = modifier }
                } else {
                    // The fourth secure-input read is the second composite
                    // sample inside application-bound final validation. It
                    // occurs after the monitor's empty modifier check and
                    // before the pair can be submitted.
                    secureInput.onQuery = { queryCount in
                        if queryCount == 4 {
                            flags.value = modifier
                        }
                    }
                }

                let delivery = SystemReviewDestinationDelivery(
                    applicationRuntime: runtime,
                    applicationActivator: activation,
                    accessibility: access,
                    finalTextOutput: output,
                    accessibilityTrustProvider: R1ReviewTrustProvider(),
                    secureInputStateProvider: secureInput,
                    frontmostProcessProvider: R1ReviewFrontmostProcessProvider(
                        runtime: runtime
                    ),
                    inputMonitor: R1ReviewInputMonitor(),
                    activationMonitor: R1ReviewActivationMonitor(),
                    modifierSampler: { flags.value },
                    modifierSleeper: { _ in true }
                )
                let destination = R1ReviewFixtures.destination(
                    binding: route == "exact"
                        ? .exactCursor(R1ReviewFixtures.cursorToken())
                        : .applicationCurrentFocus
                )

                let result = await delivery.deliver(
                    "PRIVATE_MODIFIER_\(route)_\(modifier.rawValue)",
                    to: destination
                )

                XCTAssertEqual(
                    result,
                    .deliveryFailed,
                    "\(route) route must fail before the Unicode submission boundary for \(modifier)"
                )
                XCTAssertEqual(
                    backend.postedEvents,
                    [],
                    "\(route) route must not post after \(modifier) changes in final validation"
                )
                XCTAssertEqual(
                    backend.constructedEvents.count,
                    2,
                    "\(route) route may prepare/read back, but must not post, for \(modifier)"
                )
            }
        }
    }

    func test_systemReplacementPosterConstructsAndTagsEveryEventBeforeOrderedPosting() {
        let trace = FakePosterOperationTrace()
        let backend = FakeSystemUnicodeEventBackend(failure: nil, trace: trace)
        let secureInput = FakeTracingSecureInputStateProvider(isEnabled: false, trace: trace)
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: secureInput
        )

        let result = poster.postReplacement(
            deleteCharacterCount: 2,
            insertText: "r",
            to: 4242
        )

        XCTAssertEqual(result, .posted)
        XCTAssertEqual(backend.sourceStateIDs, [.privateState])
        XCTAssertEqual(
            backend.constructedEvents.map(\.phase),
            [.keyDown, .keyUp, .keyDown, .keyUp, .keyDown, .keyUp]
        )
        XCTAssertEqual(
            backend.constructedEvents.map(\.virtualKey),
            [
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                nil,
                nil
            ]
        )
        XCTAssertEqual(
            backend.constructedEvents.map(\.utf16),
            [[], [], [], [], Array("r".utf16), Array("r".utf16)]
        )
        XCTAssertEqual(
            backend.constructedEvents.map(\.sourceIdentity),
            Array(repeating: backend.sourceIdentity, count: 6)
        )
        XCTAssertEqual(backend.constructedEvents.map(\.flags), Array(repeating: [], count: 6))
        XCTAssertEqual(
            backend.taggedUserData,
            Array(repeating: FeishuSpeechSyntheticEventTag.value, count: 6)
        )
        XCTAssertEqual(
            backend.postedEvents.map(\.virtualKey),
            [
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                nil,
                nil
            ]
        )
        XCTAssertEqual(backend.postedEvents.map(\.processIdentifier), Array(repeating: 4242, count: 6))
        let lastConstruction = backend.operations.lastIndex { $0.hasPrefix("construct-") }
        let lastTag = backend.operations.lastIndex { $0.hasPrefix("tag-") }
        let firstPost = backend.operations.firstIndex { $0.hasPrefix("post-") }
        XCTAssertNotNil(lastConstruction)
        XCTAssertNotNil(lastTag)
        XCTAssertNotNil(firstPost)
        if let lastConstruction, let lastTag, let firstPost {
            XCTAssertLessThan(lastConstruction, firstPost)
            XCTAssertLessThan(lastTag, firstPost)
        }
        XCTAssertEqual(secureInput.queryCount, 1)
    }

    func test_productionGuardedReplacementEpochDriftBeforeFirstPairPostsNothing() {
        let gate = CurrentFocusInputInterferenceEpoch()
        let expectedEpoch = gate.value
        let backend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )
        gate.observePreDispatch(type: .keyDown, event: makePhysicalKeyEvent())

        let result = poster.postReplacement(
            deleteCharacterCount: 2,
            insertText: "replacement",
            to: 4242,
            postCompleteSyntheticPairIfInterferenceEpochIsUnchanged: { postPair in
                gate.performIfUnchanged(expectedEpoch: expectedEpoch, postPair)
            }
        )

        XCTAssertEqual(result, .deliveryFailed)
        XCTAssertEqual(backend.postedEvents, [])
    }

    func test_productionGuardedReplacementUnchangedEpochPostsEveryCompletePair() {
        let gate = CurrentFocusInputInterferenceEpoch()
        let expectedEpoch = gate.value
        let backend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )

        let result = poster.postReplacement(
            deleteCharacterCount: 2,
            insertText: "r",
            to: 4242,
            postCompleteSyntheticPairIfInterferenceEpochIsUnchanged: { postPair in
                gate.performIfUnchanged(expectedEpoch: expectedEpoch, postPair)
            }
        )

        XCTAssertEqual(result, .posted)
        XCTAssertEqual(
            backend.postedEvents.map(\.phase),
            [.keyDown, .keyUp, .keyDown, .keyUp, .keyDown, .keyUp]
        )
        XCTAssertEqual(
            backend.postedEvents.map(\.virtualKey),
            [
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                CGKeyCode(kVK_Delete),
                nil,
                nil
            ]
        )
    }

    func test_productionSharedGateFinishesFirstPairThenBlocksLaterPairsAndInsertion() {
        let gate = CurrentFocusInputInterferenceEpoch()
        let expectedEpoch = gate.value
        let backend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )
        let trace = ThreadSafeProductionGateTrace()
        let physicalEvent = makePhysicalKeyEvent()
        let attemptedAdvance = DispatchSemaphore(value: 0)
        let completedAdvance = DispatchSemaphore(value: 0)
        var advanceStarted = false

        backend.onPostedEvent = { event in
            let isDelete = event.virtualKey == CGKeyCode(kVK_Delete)
            trace.append(isDelete ? "delete-\(event.phase)" : "insert-\(event.phase)")
            guard isDelete, event.phase == .keyDown, !advanceStarted else { return }
            advanceStarted = true
            DispatchQueue.global(qos: .userInitiated).async {
                attemptedAdvance.signal()
                gate.observePreDispatch(type: .keyDown, event: physicalEvent)
                trace.append("physical-epoch-advance")
                completedAdvance.signal()
            }
            attemptedAdvance.wait()
        }

        let result = poster.postReplacement(
            deleteCharacterCount: 3,
            insertText: "r",
            to: 4242,
            postCompleteSyntheticPairIfInterferenceEpochIsUnchanged: { postPair in
                let posted = gate.performIfUnchanged(
                    expectedEpoch: expectedEpoch,
                    postPair
                )
                if advanceStarted {
                    completedAdvance.wait()
                    advanceStarted = false
                }
                return posted
            }
        )

        XCTAssertEqual(result, .deliveryFailed)
        XCTAssertEqual(
            trace.values,
            ["delete-keyDown", "delete-keyUp", "physical-epoch-advance"]
        )
        XCTAssertEqual(backend.postedEvents.count, 2)
        XCTAssertEqual(backend.postedEvents.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(
            backend.postedEvents.map(\.virtualKey),
            [CGKeyCode(kVK_Delete), CGKeyCode(kVK_Delete)]
        )
    }

    func test_productionGuardedInsertionOnlyRejectsEpochDriftWithoutPosting() {
        let gate = CurrentFocusInputInterferenceEpoch()
        let expectedEpoch = gate.value
        let backend = FakeSystemUnicodeEventBackend(
            failure: nil,
            trace: FakePosterOperationTrace()
        )
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )
        gate.observePreDispatch(type: .leftMouseDown, event: makePhysicalMouseEvent())

        let result = poster.postReplacement(
            deleteCharacterCount: 0,
            insertText: "insertion",
            to: 4242,
            postCompleteSyntheticPairIfInterferenceEpochIsUnchanged: { postPair in
                gate.performIfUnchanged(expectedEpoch: expectedEpoch, postPair)
            }
        )

        XCTAssertEqual(result, .deliveryFailed)
        XCTAssertEqual(backend.postedEvents, [])
    }

    func test_systemReplacementPosterDeleteOnlyPostsExactBackspacePairs() {
        let backend = FakeSystemUnicodeEventBackend(failure: nil, trace: FakePosterOperationTrace())
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )

        let result = poster.postReplacement(
            deleteCharacterCount: 2,
            insertText: "",
            to: 5150
        )

        XCTAssertEqual(result, .posted)
        XCTAssertEqual(
            backend.postedEvents.map(\.phase),
            [.keyDown, .keyUp, .keyDown, .keyUp]
        )
        XCTAssertEqual(
            backend.postedEvents.map(\.virtualKey),
            Array(repeating: CGKeyCode(kVK_Delete), count: 4)
        )
        XCTAssertEqual(backend.postedEvents.map(\.processIdentifier), Array(repeating: 5150, count: 4))
    }

    func test_systemReplacementPosterAnyConstructionFailurePostsNothing() {
        for phase in [FinalTextUnicodeEventPhase.keyDown, .keyUp] {
            let backend = FakeSystemUnicodeEventBackend(
                failure: nil,
                trace: FakePosterOperationTrace(),
                keyboardFailurePhase: phase
            )
            let poster = SystemFinalTextCurrentFocusEventPoster(
                backend: backend,
                secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
            )

            let result = poster.postReplacement(
                deleteCharacterCount: 1,
                insertText: "r",
                to: 5150
            )

            XCTAssertEqual(result, .deliveryFailed, "phase: \(phase)")
            XCTAssertEqual(backend.postedEvents, [], "phase: \(phase)")
        }

        let unicodeFailure = FakeSystemUnicodeEventBackend(
            failure: .keyDown,
            trace: FakePosterOperationTrace()
        )
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: unicodeFailure,
            secureInputStateProvider: FakeSecureInputStateProvider(states: [false])
        )

        XCTAssertEqual(
            poster.postReplacement(deleteCharacterCount: 1, insertText: "r", to: 5150),
            .deliveryFailed
        )
        XCTAssertEqual(unicodeFailure.postedEvents, [])
    }

    func test_systemUnicodePosterConstructionFailuresPostNothing() {
        for failure in FakeSystemUnicodeEventBackend.Failure.allCases {
            let backend = FakeSystemUnicodeEventBackend(
                failure: failure,
                trace: FakePosterOperationTrace()
            )
            let secureInput = FakeSecureInputStateProvider(states: [false])
            let poster = SystemFinalTextCurrentFocusEventPoster(
                backend: backend,
                secureInputStateProvider: secureInput
            )

            let result = poster.postUnicodeText("all or nothing", to: 5150)

            XCTAssertEqual(result, .deliveryFailed, "failure: \(failure)")
            XCTAssertEqual(backend.postedEvents, [], "failure: \(failure)")
            let expectedOperations: [String]
            switch failure {
            case .source:
                expectedOperations = ["source"]
            case .keyDown:
                expectedOperations = ["source", "construct-down"]
            case .keyUp:
                expectedOperations = ["source", "construct-down", "construct-up"]
            }
            XCTAssertEqual(backend.operations, expectedOperations, "failure: \(failure)")
            XCTAssertFalse(
                backend.operations.contains(where: { $0.hasPrefix("post-") }),
                "failure: \(failure)"
            )
        }
    }

    func test_systemUnicodePosterConstructionHookCanEnableSecureInputBeforeFinalSampleAndZeroPosts() {
        let trace = FakePosterOperationTrace()
        let secureInput = FakeTracingSecureInputStateProvider(isEnabled: false, trace: trace)
        let backend = FakeSystemUnicodeEventBackend(failure: nil, trace: trace)
        backend.onConstructedEvent = { phase in
            if phase == .keyUp {
                secureInput.enable()
            }
        }
        let poster = SystemFinalTextCurrentFocusEventPoster(
            backend: backend,
            secureInputStateProvider: secureInput
        )

        let result = poster.postUnicodeText("PRIVATE_SECURE_TEXT", to: 4242)

        XCTAssertEqual(result, .securityRejected)
        XCTAssertEqual(secureInput.queryCount, 1)
        XCTAssertEqual(
            backend.operations,
            [
                "source",
                "construct-down",
                "construct-up",
                "tag-down",
                "target-down",
                "tag-up",
                "target-up",
                "readback-down",
                "readback-up",
                "secure"
            ]
        )
        XCTAssertEqual(backend.constructedEvents.map(\.phase), [.keyDown, .keyUp])
        XCTAssertEqual(backend.postedEvents, [])
    }

    func test_currentFocusLiveSecureInputTransitionRejectsBeforeUnicodePost() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let boundEventPoster = FakeFinalTextKeyEventPoster()
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster()
        let secureInput = FakeSecureInputStateProvider(states: [false, true])
        let frontmostProcess = FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: boundEventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess
        )

        let result = output.insertAtCurrentFocusOnce("PRIVATE_SECURE_TEXT")

        XCTAssertEqual(result, .securityRejected)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(boundEventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, [])
        XCTAssertEqual(secureInput.queryCount, 2)
    }

    func test_currentFocusFrontmostPIDChangeFailsClosedBeforeUnicodePost() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let boundEventPoster = FakeFinalTextKeyEventPoster()
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster()
        let secureInput = FakeSecureInputStateProvider(states: [false, false])
        let frontmostProcess = FakeFrontmostProcessProvider(processIdentifiers: [42, 99])
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: boundEventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess
        )

        let result = output.insertAtCurrentFocusOnce("PRIVATE_STALE_TEXT")

        XCTAssertEqual(result, .destinationInvalid)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(boundEventPoster.destinationProcessIdentifiers, [])
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, [])
        XCTAssertEqual(frontmostProcess.queryCount, 2)
    }

    func test_currentFocusPosterSecurityRejectionIsPreservedWithoutAmbientResample() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let boundEventPoster = FakeFinalTextKeyEventPoster()
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster(
            result: .securityRejected
        )
        let secureInput = FakeSecureInputStateProvider(states: [false, false])
        let frontmostProcess = FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: boundEventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess
        )

        let result = output.insertAtCurrentFocusOnce("PRIVATE_POSTER_SECURE_TEXT")

        XCTAssertEqual(result, .securityRejected)
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, ["PRIVATE_POSTER_SECURE_TEXT"])
        XCTAssertEqual(
            secureInput.queryCount,
            2,
            "the typed poster result must be preserved without an ambiguous third security sample"
        )
        XCTAssertEqual(frontmostProcess.queryCount, 2)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(boundEventPoster.destinationProcessIdentifiers, [])
    }

    func test_currentFocusPosterOrdinaryFailureMapsToDeliveryFailedWithoutResample() {
        let pasteboard = FakeFinalTextPasteboardWriter()
        let boundEventPoster = FakeFinalTextKeyEventPoster()
        let currentFocusEventPoster = FakeCurrentFocusUnicodeEventPoster(
            result: .deliveryFailed
        )
        let secureInput = FakeSecureInputStateProvider(states: [false, false])
        let frontmostProcess = FakeFrontmostProcessProvider(processIdentifiers: [42, 42])
        let output = SystemFinalTextOutput(
            pasteboardWriter: pasteboard,
            keyEventPoster: boundEventPoster,
            currentFocusEventPoster: currentFocusEventPoster,
            secureInputStateProvider: secureInput,
            frontmostProcessProvider: frontmostProcess
        )

        let result = output.insertAtCurrentFocusOnce("PRIVATE_POSTER_FAILURE_TEXT")

        XCTAssertEqual(result, .deliveryFailed)
        XCTAssertEqual(currentFocusEventPoster.requestedTexts, ["PRIVATE_POSTER_FAILURE_TEXT"])
        XCTAssertEqual(secureInput.queryCount, 2)
        XCTAssertEqual(frontmostProcess.queryCount, 2)
        XCTAssertEqual(pasteboard.writtenTexts, [])
        XCTAssertEqual(boundEventPoster.destinationProcessIdentifiers, [])
    }

    private func captureTarget(
        using executor: ReviewSubmissionExecutor,
        request: ReviewTargetCaptureRequestDescriptor
    ) async throws -> CapturedReviewTargetDescriptor {
        try await withCheckedThrowingContinuation { continuation in
            executor.capture(request) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func submitRawAttempt(
        using executor: ReviewSubmissionExecutor,
        controlPlane: ReviewSubmissionControlPlane,
        target: CapturedReviewTargetDescriptor,
        recorder: V5ReviewSubmissionEventRecorder,
        draft: String
    ) async throws -> ReviewCommitReceipt {
        let issuer = ReviewAttemptTicketIssuer(
            controlPlaneInstanceNonce: controlPlane.instanceNonce
        )
        let handle = try XCTUnwrap(issuer.issue())
        controlPlane.enqueueAdmission(
            ReviewSubmissionAdmissionEnvelope(
                handle: handle,
                request: makeSubmissionRequest(
                    targetID: target.targetID,
                    draft: draft
                ),
                absolutePreBoundaryDeadline: DispatchTime.now().uptimeNanoseconds
                    + 1_000_000_000
            )
        )
        let admissionAccepted = await recorder.waitFor {
            if case .admissionAccepted(handle) = $0 { return true }
            return false
        }
        XCTAssertTrue(admissionAccepted, "the raw pair scenario must reach admission")
        controlPlane.enqueueStart(handle)
        let terminalReceipt = await recorder.waitForTerminal(for: handle)
        return try XCTUnwrap(
            terminalReceipt,
            "the raw pair scenario must emit one typed terminal receipt"
        )
    }

    private func captureTarget(
        using facade: SystemReviewSubmissionFacade,
        request: ReviewTargetCaptureRequestDescriptor
    ) async throws -> CapturedReviewTargetDescriptor {
        try await withCheckedThrowingContinuation { continuation in
            facade.captureTarget(request) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func beginFacadeCapture(
        _ facade: SystemReviewSubmissionFacade,
        request: ReviewTargetCaptureRequestDescriptor
    ) -> V5CaptureResultBox {
        let box = V5CaptureResultBox()
        facade.captureTarget(request) { result in
            box.resolve(result)
        }
        return box
    }

    private func makeSubmissionRequest(
        targetID: CapturedReviewTargetID,
        generation: UInt64 = 5,
        revision: UInt64 = 1,
        attemptOrdinal: UInt64 = 1,
        draft: String = "PRIVATE_V5_DRAFT",
        confirmationUptime: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> ReviewSubmissionRequestDescriptor {
        ReviewSubmissionRequestDescriptor(
            reviewID: UUID(uuidString: "A0000000-0000-4000-8000-000000000005")!,
            generation: generation,
            revision: revision,
            attemptOrdinal: attemptOrdinal,
            frozenDraft: draft,
            capturedTargetID: targetID,
            confirmationUptime: confirmationUptime
        )
    }

    private func runV5SystemAXFixedStepMatrix(
        binding: CapturedReviewTargetBinding,
        expected: [ReviewAXStepID],
        identity: ReviewApplicationIdentity,
        makeFixture: () throws -> V5SystemAXValidationFixture
    ) throws {
        var occurrenceByStep: [String: Int] = [:]
        let scenarios: [(ReviewAXStepID, Int)] = expected.map { step in
            let nextOccurrence = (occurrenceByStep[step.rawValue] ?? 0) + 1
            occurrenceByStep[step.rawValue] = nextOccurrence
            return (step, nextOccurrence)
        }
        XCTAssertEqual(
            scenarios.count,
            expected.count,
            "scenario generation must preserve every fixed \(binding) inventory entry"
        )

        for (step, occurrence) in scenarios {
            let fixture = try makeFixture()
            defer { fixture.close() }
            let latch = V5SystemAXCancellationAtOccurrence(
                step: step,
                occurrence: occurrence
            )
            let trace = V5SystemAXStepTrace(onStep: latch.observe)
            let runtime = SystemReviewSubmissionAXRuntime(
                stepObserver: trace.observe,
                securitySamples: V5SystemAXFixtures.securitySamples(identity: identity)
            )
            let result = runtime.validate(
                fixture.target,
                deadline: DispatchTime.now().uptimeNanoseconds + 1_000_000_000,
                cancellationProbe: latch.probe.isCancelled
            )
            XCTAssertEqual(
                result,
                .cancellation,
                "cancellation at fixed \(binding)/\(step)#\(occurrence) must be typed and fail closed"
            )
            let observed = trace.snapshot()
            guard let boundary = v5SystemAXOccurrenceIndex(
                step: step,
                occurrence: occurrence,
                in: observed
            ) else {
                XCTFail(
                    "fixed cancellation scenario did not observe \(binding)/\(step)#\(occurrence); trace=\(v5SystemAXTraceDescription(observed))"
                )
                continue
            }
            XCTAssertEqual(
                observed.count,
                boundary + 1,
                "no AX step may follow cancellation at fixed \(binding)/\(step)#\(occurrence)"
            )
        }

        for (step, occurrence) in scenarios {
            let fixture = try makeFixture()
            defer { fixture.close() }
            let latch = V5SystemAXDeadlineAtOccurrence(
                step: step,
                occurrence: occurrence
            )
            let trace = V5SystemAXStepTrace(onStep: latch.observe)
            let runtime = SystemReviewSubmissionAXRuntime(
                stepObserver: trace.observe,
                securitySamples: V5SystemAXFixtures.securitySamples(identity: identity)
            )
            let result = runtime.validate(
                fixture.target,
                deadline: DispatchTime.now().uptimeNanoseconds + 150_000_000,
                cancellationProbe: { false }
            )
            XCTAssertEqual(
                result,
                .accessibilityTimeout,
                "deadline at fixed \(binding)/\(step)#\(occurrence) must fail closed"
            )
            let observed = trace.snapshot()
            guard let boundary = v5SystemAXOccurrenceIndex(
                step: step,
                occurrence: occurrence,
                in: observed
            ) else {
                XCTFail(
                    "fixed deadline scenario did not observe \(binding)/\(step)#\(occurrence); trace=\(v5SystemAXTraceDescription(observed))"
                )
                continue
            }
            XCTAssertEqual(
                observed.count,
                boundary + 1,
                "no AX step may follow deadline at fixed \(binding)/\(step)#\(occurrence)"
            )
        }
    }

    private func productionSource(relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeDestination(processIdentifier: pid_t) -> CursorDestinationToken {
        CursorDestinationToken(
            generation: 7,
            processIdentifier: processIdentifier,
            element: AXUIElementCreateApplication(processIdentifier),
            originalSelection: CursorTextRange(location: 2, length: 0)
        )
    }

    private func makePhysicalKeyEvent() -> CGEvent {
        CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        )!
    }

    private func makePhysicalMouseEvent() -> CGEvent {
        CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: .zero,
            mouseButton: .left
        )!
    }
}

private enum V5ReviewSubmissionFixtures {
    static let identity = ReviewApplicationIdentity(
        processIdentifier: 42,
        bundleIdentifier: "com.example.issue40.v5.target",
        executableURL: URL(fileURLWithPath: "/Applications/Issue40V5Target.app/Contents/MacOS/Target"),
        launchDate: Date(timeIntervalSince1970: 5)
    )

    static func identity(processIdentifier: pid_t) -> ReviewApplicationIdentity {
        ReviewApplicationIdentity(
            processIdentifier: processIdentifier,
            bundleIdentifier: "com.example.issue40.v5.target.\(processIdentifier)",
            executableURL: URL(
                fileURLWithPath: "/Applications/Issue40V5Target\(processIdentifier).app/Contents/MacOS/Target"
            ),
            launchDate: Date(timeIntervalSince1970: TimeInterval(processIdentifier))
        )
    }
}

private enum V5SystemAXFixtures {
    static func identity(processIdentifier: pid_t) -> ReviewApplicationIdentity {
        ReviewApplicationIdentity(
            processIdentifier: processIdentifier,
            bundleIdentifier: "com.example.issue40.system-ax",
            executableURL: URL(fileURLWithPath: "/Applications/Issue40SystemAX.app/Contents/MacOS/Target"),
            launchDate: Date(timeIntervalSince1970: 5)
        )
    }

    static func securitySamples(
        identity: ReviewApplicationIdentity
    ) -> ReviewAXSecuritySamples {
        ReviewAXSecuritySamples(
            secureInputEnabled: { false },
            accessibilityTrusted: { true },
            runningIdentity: { processIdentifier in
                processIdentifier == identity.processIdentifier ? identity : nil
            },
            frontmostProcessIdentifier: { identity.processIdentifier }
        )
    }

    static func rawTarget(
        identity: ReviewApplicationIdentity,
        binding: CapturedReviewTargetBinding
    ) -> ReviewSubmissionRawTargetState {
        let element = AXUIElementCreateApplication(identity.processIdentifier)
        let descriptor = CapturedReviewTargetDescriptor(
            generation: 5,
            application: identity,
            binding: binding,
            securityAtCapture: .safe
        )
        return ReviewSubmissionRawTargetState(
            descriptor: descriptor,
            applicationElement: element,
            focusedElement: binding == .exactCursor ? element : nil,
            originalSelection: binding == .exactCursor
                ? CursorTextRange(location: 0, length: 0)
                : nil
        )
    }
}

private enum V5SystemAXExpectedInventory {
    // This is intentionally hand-authored from the production ReviewAXStepID
    // enum.  Scenario generation below is allowed to consume only these fixed
    // binding-specific traces, never a trace that can terminate early.
    static let allProductionSteps: [ReviewAXStepID] = [
        .messagingTimeout,
        .copyAttribute,
        .getProcessIdentifier,
        .isAttributeSettable,
        .setFocused,
        .createAXValue,
        .setSelectedRange,
        .getSelectedRange,
        .readAXValue,
        .role,
        .subrole,
        .secureInput,
        .accessibilityTrust,
        .runningIdentity,
        .frontmost
    ]

    static let captureOnlySteps: [ReviewAXStepID] = [
        .isAttributeSettable
    ]

    static let exactValidation: [ReviewAXStepID] = [
        // Leading security composite.
        .secureInput,
        .accessibilityTrust,
        .runningIdentity,
        .frontmost,
        // Application identity, captured element identity, and restoration.
        .messagingTimeout,
        .getProcessIdentifier,
        .messagingTimeout,
        .getProcessIdentifier,
        .messagingTimeout,
        .setFocused,
        .messagingTimeout,
        .createAXValue,
        .setSelectedRange,
        // Exact focus readback.
        .messagingTimeout,
        .copyAttribute,
        // Exact selection readback, including the AXValue decode.
        .messagingTimeout,
        .getSelectedRange,
        .readAXValue,
        // Exact editable role/subrole assessment and captured PID readback.
        .messagingTimeout,
        .role,
        .messagingTimeout,
        .subrole,
        .messagingTimeout,
        .getProcessIdentifier,
        // Trailing security composite.
        .secureInput,
        .accessibilityTrust,
        .runningIdentity,
        .frontmost
    ]

    static let applicationBoundValidation: [ReviewAXStepID] = [
        // Leading security composite.
        .secureInput,
        .accessibilityTrust,
        .runningIdentity,
        .frontmost,
        // Concrete ordinary focused-element miss on the application root.
        .messagingTimeout,
        .getProcessIdentifier,
        .messagingTimeout,
        .copyAttribute,
        // Trailing security composite.
        .secureInput,
        .accessibilityTrust,
        .runningIdentity,
        .frontmost
    ]
}

@MainActor
private final class V5SystemAXAccessibleTextView: NSTextView {
    override func accessibilityAttributeValue(
        _ attribute: NSAccessibility.Attribute
    ) -> Any? {
        if attribute == .subrole {
            return "AXStandard"
        }
        return super.accessibilityAttributeValue(attribute)
    }
}

@MainActor
private final class V5SystemAXValidationFixture {
    let target: ReviewSubmissionRawTargetState
    private let window: NSWindow

    private init(target: ReviewSubmissionRawTargetState, window: NSWindow) {
        self.target = target
        self.window = window
    }

    static func exact(identity: ReviewApplicationIdentity) throws -> Self {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let editor = V5SystemAXAccessibleTextView(
            frame: NSRect(x: 0, y: 0, width: 360, height: 120)
        )
        editor.isEditable = true
        editor.string = "PRIVATE_V5_EXHAUSTIVE_EXACT"
        window.contentView = editor
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        guard window.makeFirstResponder(editor) else {
            window.orderOut(nil)
            window.close()
            throw V5SystemAXValidationFixtureError.editorDidNotBecomeFirstResponder
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        let applicationElement = AXUIElementCreateApplication(identity.processIdentifier)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            window.orderOut(nil)
            window.close()
            throw V5SystemAXValidationFixtureError.focusedEditorUnavailable
        }
        let target = ReviewSubmissionRawTargetState(
            descriptor: CapturedReviewTargetDescriptor(
                generation: 5,
                application: identity,
                binding: .exactCursor,
                securityAtCapture: .safe
            ),
            applicationElement: applicationElement,
            focusedElement: unsafeBitCast(focusedValue, to: AXUIElement.self),
            originalSelection: CursorTextRange(location: 0, length: 0)
        )
        return Self(target: target, window: window)
    }

    static func applicationBoundOrdinaryMiss(identity: ReviewApplicationIdentity) throws -> Self {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        // A concrete non-editor surface is retained only long enough to make
        // the current application root real.  It has no focused text element,
        // so the app-bound copy is an ordinary noValue/unsupported miss.
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        window.isReleasedWhenClosed = false
        window.orderOut(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))

        let target = ReviewSubmissionRawTargetState(
            descriptor: CapturedReviewTargetDescriptor(
                generation: 5,
                application: identity,
                binding: .applicationBoundCurrentFocus,
                securityAtCapture: .safe
            ),
            applicationElement: AXUIElementCreateApplication(identity.processIdentifier),
            focusedElement: nil,
            originalSelection: nil
        )
        return Self(target: target, window: window)
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }
}

private enum V5SystemAXValidationFixtureError: Error {
    case editorDidNotBecomeFirstResponder
    case focusedEditorUnavailable
}

private final class V5SystemAXCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: @Sendable () -> Bool {
        { [weak self] in
            guard let self else { return false }
            self.lock.lock()
            let result = self.cancelled
            self.lock.unlock()
            return result
        }
    }
}

private final class V5SystemAXStepTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [(ReviewAXStepID, ReviewAXResultCategory)] = []
    private let onStep: (@Sendable (ReviewAXStepID, ReviewAXResultCategory) -> Void)?

    init(
        onStep: (@Sendable (ReviewAXStepID, ReviewAXResultCategory) -> Void)? = nil
    ) {
        self.onStep = onStep
    }

    func observe(_ step: ReviewAXStepID, _ result: ReviewAXResultCategory) {
        lock.lock()
        steps.append((step, result))
        lock.unlock()
        onStep?(step, result)
    }

    func snapshot() -> [(ReviewAXStepID, ReviewAXResultCategory)] {
        lock.lock()
        let result = steps
        lock.unlock()
        return result
    }
}

private func v5SystemAXOccurrenceIndex(
    step: ReviewAXStepID,
    occurrence: Int,
    in steps: [(ReviewAXStepID, ReviewAXResultCategory)]
) -> Int? {
    var seen = 0
    for index in steps.indices where steps[index].0 == step {
        seen += 1
        if seen == occurrence {
            return index
        }
    }
    return nil
}

private func v5SystemAXTraceDescription(
    _ steps: [(ReviewAXStepID, ReviewAXResultCategory)]
) -> String {
    steps.map { "\($0.0.rawValue):\($0.1.rawValue)" }.joined(separator: ",")
}

private final class V5SystemAXReadbackCancellationLatch: @unchecked Sendable {
    let probe = V5SystemAXCancellationProbe()
    private let lock = NSLock()
    private var restorationComplete = false
    private var latched = false

    var didLatch: Bool {
        lock.lock()
        let value = latched
        lock.unlock()
        return value
    }

    func observe(_ step: ReviewAXStepID, _: ReviewAXResultCategory) {
        lock.lock()
        if step == .setSelectedRange {
            restorationComplete = true
        }
        let shouldLatch = restorationComplete && step == .messagingTimeout && !latched
        if shouldLatch {
            latched = true
        }
        lock.unlock()
        if shouldLatch {
            probe.cancel()
        }
    }
}

private final class V5SystemAXCancellationAtOccurrence: @unchecked Sendable {
    let probe = V5SystemAXCancellationProbe()
    private let target: ReviewAXStepID
    private let occurrence: Int
    private let lock = NSLock()
    private var seen = 0
    private var latched = false

    init(step: ReviewAXStepID, occurrence: Int) {
        target = step
        self.occurrence = occurrence
    }

    func observe(_ step: ReviewAXStepID, _: ReviewAXResultCategory) {
        guard step == target else { return }
        lock.lock()
        seen += 1
        let shouldLatch = seen == occurrence && !latched
        if shouldLatch {
            latched = true
        }
        lock.unlock()
        if shouldLatch {
            probe.cancel()
        }
    }
}

private final class V5SystemAXDeadlineAtOccurrence: @unchecked Sendable {
    private let target: ReviewAXStepID
    private let occurrence: Int
    private let lock = NSLock()
    private var seen = 0
    private var expired = false

    init(step: ReviewAXStepID, occurrence: Int) {
        target = step
        self.occurrence = occurrence
    }

    func observe(_ step: ReviewAXStepID, _: ReviewAXResultCategory) {
        guard step == target else { return }
        lock.lock()
        seen += 1
        let shouldExpire = seen == occurrence && !expired
        if shouldExpire {
            expired = true
        }
        lock.unlock()
        if shouldExpire {
            Thread.sleep(forTimeInterval: 0.3)
        }
    }
}

private final class V5SystemAXExecutorCancellationLatch: @unchecked Sendable {
    let trace = V5SystemAXStepTrace()
    private let controlPlane: ReviewSubmissionControlPlane
    private let cancellationResolved: DispatchSemaphore
    private let lock = NSLock()
    private var handle: ReviewSubmissionAttemptHandle?
    private var restorationComplete = false
    private var latched = false

    init(
        controlPlane: ReviewSubmissionControlPlane,
        cancellationResolved: DispatchSemaphore
    ) {
        self.controlPlane = controlPlane
        self.cancellationResolved = cancellationResolved
    }

    var didLatch: Bool {
        lock.lock()
        let value = latched
        lock.unlock()
        return value
    }

    func arm(_ handle: ReviewSubmissionAttemptHandle) {
        lock.lock()
        self.handle = handle
        lock.unlock()
    }

    func observe(_ step: ReviewAXStepID, _ result: ReviewAXResultCategory) {
        trace.observe(step, result)
        lock.lock()
        if step == .setSelectedRange {
            restorationComplete = true
        }
        let shouldLatch = restorationComplete && step == .messagingTimeout && !latched
        let handle = self.handle
        if shouldLatch {
            latched = true
        }
        lock.unlock()
        guard shouldLatch, let handle else { return }
        controlPlane.enqueueCancellation(handle)
        _ = cancellationResolved.wait(timeout: .now() + 2)
    }
}

private final class V5SystemAXDelegatingRuntime: ReviewSubmissionRawAccessibilityRuntime, @unchecked Sendable {
    private let runtime: SystemReviewSubmissionAXRuntime
    private let rawTarget: ReviewSubmissionRawTargetState

    init(
        runtime: SystemReviewSubmissionAXRuntime,
        rawTarget: ReviewSubmissionRawTargetState
    ) {
        self.runtime = runtime
        self.rawTarget = rawTarget
    }

    func capture(
        _ request: ReviewTargetCaptureRequestDescriptor
    ) -> Result<ReviewSubmissionRawTargetState, ReviewPreBoundaryFailure> {
        let descriptor = CapturedReviewTargetDescriptor(
            targetID: rawTarget.descriptor.targetID,
            generation: request.generation,
            application: request.application,
            binding: rawTarget.descriptor.binding,
            securityAtCapture: rawTarget.descriptor.securityAtCapture
        )
        return .success(
            ReviewSubmissionRawTargetState(
                descriptor: descriptor,
                applicationElement: rawTarget.applicationElement,
                focusedElement: rawTarget.focusedElement,
                originalSelection: rawTarget.originalSelection
            )
        )
    }

    func validate(
        _ target: ReviewSubmissionRawTargetState,
        deadline: UInt64
    ) -> ReviewPreBoundaryFailure? {
        runtime.validate(target, deadline: deadline)
    }

    func validate(
        _ target: ReviewSubmissionRawTargetState,
        deadline: UInt64,
        cancellationProbe: @escaping @Sendable () -> Bool
    ) -> ReviewPreBoundaryFailure? {
        runtime.validate(
            target,
            deadline: deadline,
            cancellationProbe: cancellationProbe
        )
    }
}

private final class V5CaptureResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<CapturedReviewTargetDescriptor, ReviewPreBoundaryFailure>?

    func resolve(
        _ result: Result<CapturedReviewTargetDescriptor, ReviewPreBoundaryFailure>
    ) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func wait() async -> Result<CapturedReviewTargetDescriptor, ReviewPreBoundaryFailure>? {
        for _ in 0 ..< 500 {
            lock.lock()
            let result = self.result
            lock.unlock()
            if let result { return result }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return nil
    }
}

private final class V5ReviewSubmissionEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ReviewSubmissionControlEvent] = []

    func append(_ event: ReviewSubmissionControlEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    func waitFor(
        _ predicate: @escaping (ReviewSubmissionControlEvent) -> Bool
    ) async -> Bool {
        for _ in 0 ..< 500 {
            lock.lock()
            let found = storage.contains(where: predicate)
            lock.unlock()
            if found { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return false
    }

    func waitForTerminal(
        for handle: ReviewSubmissionAttemptHandle
    ) async -> ReviewCommitReceipt? {
        for _ in 0 ..< 500 {
            lock.lock()
            let receipt = storage.compactMap { event -> ReviewCommitReceipt? in
                guard case .terminal(let eventHandle, let receipt) = event,
                      eventHandle == handle else {
                    return nil
                }
                return receipt
            }.last
            lock.unlock()
            if let receipt { return receipt }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return nil
    }

    func waitForCancellation(
        for handle: ReviewSubmissionAttemptHandle
    ) async -> CancellationSignalResult? {
        for _ in 0 ..< 500 {
            lock.lock()
            let result = storage.compactMap { event -> CancellationSignalResult? in
                guard case .cancellationResolved(let eventHandle, let result) = event,
                      eventHandle == handle else {
                    return nil
                }
                return result
            }.last
            lock.unlock()
            if let result { return result }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return nil
    }
}

private final class V5ReviewSubmissionStartRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ReviewSubmissionAttemptHandle] = []

    var handles: [ReviewSubmissionAttemptHandle] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ handle: ReviewSubmissionAttemptHandle) {
        lock.lock()
        storage.append(handle)
        lock.unlock()
    }

    func waitFor(_ handle: ReviewSubmissionAttemptHandle) async -> Bool {
        for _ in 0 ..< 500 {
            if handles.contains(handle) { return true }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return false
    }
}

private final class V5ReviewSubmissionEventBackend: ReviewSubmissionEventBackend, @unchecked Sendable {
    enum Operation: Equatable {
        case prepare
        case down
        case up
    }

    private let lock = NSLock()
    private let downEntered = DispatchSemaphore(value: 0)
    private let downRelease = DispatchSemaphore(value: 0)
    private let physicalEpochQueue = DispatchQueue(
        label: "com.feishuspeech.tests.physical-epoch",
        qos: .userInteractive
    )
    private let physicalEpochCallbackAttempted = DispatchSemaphore(value: 0)
    private let physicalEpochCallbackCompleted = DispatchSemaphore(value: 0)
    private let holdDown: Bool
    private(set) var operations: [Operation] = []
    private(set) var preparedUTF16: [[UInt16]] = []
    private(set) var postedTargetProcessIdentifiers: [pid_t] = []
    private(set) var physicalEpochCallbackWasAttempted = false
    private(set) var physicalEpochAdvancedBeforeUp = false
    private var physicalEpochAdvanced = false
    var advanceCombinedEpochOnDown = false
    var prepareEntered: DispatchSemaphore?
    var prepareRelease: DispatchSemaphore?
    var onPrepare: (() -> Void)?

    init(holdDown: Bool = false) {
        self.holdDown = holdDown
    }

    func preparePair(
        utf16: [UInt16],
        targetProcessIdentifier: pid_t
    ) -> ReviewSubmissionPreparedUnicodePair? {
        lock.lock()
        operations.append(.prepare)
        preparedUTF16.append(utf16)
        lock.unlock()
        onPrepare?()
        prepareEntered?.signal()
        prepareRelease?.wait()
        return ReviewSubmissionPreparedUnicodePair(
            utf16: utf16,
            targetProcessIdentifier: targetProcessIdentifier,
            sourceProcessIdentifier: getpid(),
            userData: FeishuSpeechSyntheticEventTag.value,
            flags: [],
            keyDown: nil,
            keyUp: nil
        )
    }

    func postDown(_ pair: ReviewSubmissionPreparedUnicodePair) {
        lock.lock()
        operations.append(.down)
        postedTargetProcessIdentifiers.append(pair.targetProcessIdentifier)
        lock.unlock()
        if advanceCombinedEpochOnDown {
            physicalEpochQueue.async { [self] in
                self.lock.lock()
                self.physicalEpochCallbackWasAttempted = true
                self.lock.unlock()
                self.physicalEpochCallbackAttempted.signal()

                // This models the physical observer's callback thread. It
                // contends with the production commit reservation rather than
                // re-entering the epoch primitive from postDown's thread.
                CurrentFocusCombinedInterferenceEpoch.shared.advance()

                self.lock.lock()
                self.physicalEpochAdvanced = true
                self.lock.unlock()
                self.physicalEpochCallbackCompleted.signal()
            }
            _ = physicalEpochCallbackAttempted.wait(timeout: .now() + 2)
        }
        downEntered.signal()
        if holdDown {
            downRelease.wait()
        }
    }

    func postUp(_ pair: ReviewSubmissionPreparedUnicodePair) {
        lock.lock()
        physicalEpochAdvancedBeforeUp = physicalEpochAdvanced
        operations.append(.up)
        postedTargetProcessIdentifiers.append(pair.targetProcessIdentifier)
        lock.unlock()
    }

    func waitForDown() -> Bool {
        downEntered.wait(timeout: .now() + 2) == .success
    }

    func releaseDown() {
        downRelease.signal()
    }

    func waitForPhysicalEpochAdvance() -> Bool {
        physicalEpochCallbackCompleted.wait(timeout: .now() + 2) == .success
    }
}

private final class V5ReviewSubmissionRawRuntime: ReviewSubmissionRawAccessibilityRuntime, @unchecked Sendable {
    private let captureLock = NSLock()
    private let binding: CapturedReviewTargetBinding
    private(set) var captureCallCount = 0
    private(set) var validateCallCount = 0
    var captureBlock: DispatchSemaphore?
    var captureRelease: DispatchSemaphore?
    var validationBlock: DispatchSemaphore?
    var validationRelease: DispatchSemaphore?
    private var validationFailure: ReviewPreBoundaryFailure?

    init(binding: CapturedReviewTargetBinding = .applicationBoundCurrentFocus) {
        self.binding = binding
    }

    func setValidationFailure(_ failure: ReviewPreBoundaryFailure?) {
        captureLock.lock()
        validationFailure = failure
        captureLock.unlock()
    }

    func capture(
        _ request: ReviewTargetCaptureRequestDescriptor
    ) -> Result<ReviewSubmissionRawTargetState, ReviewPreBoundaryFailure> {
        captureLock.lock()
        captureCallCount += 1
        let captureBlock = self.captureBlock
        let captureRelease = self.captureRelease
        captureLock.unlock()
        captureBlock?.signal()
        captureRelease?.wait()
        let descriptor = CapturedReviewTargetDescriptor(
            generation: request.generation,
            application: request.application,
            binding: binding,
            securityAtCapture: .safe
        )
        return .success(
            ReviewSubmissionRawTargetState(
                descriptor: descriptor,
                applicationElement: AXUIElementCreateApplication(
                    request.application.processIdentifier
                ),
                focusedElement: binding == .exactCursor
                    ? AXUIElementCreateSystemWide()
                    : nil,
                originalSelection: binding == .exactCursor
                    ? CursorTextRange(location: 0, length: 0)
                    : nil
            )
        )
    }

    func validate(
        _ target: ReviewSubmissionRawTargetState,
        deadline: UInt64
    ) -> ReviewPreBoundaryFailure? {
        _ = target
        _ = deadline
        captureLock.lock()
        validateCallCount += 1
        let block = validationBlock
        let release = validationRelease
        let failure = validationFailure
        captureLock.unlock()
        block?.signal()
        release?.wait()
        return failure
    }
}

private final class V5ApplicationBoundOrdinaryMissRawRuntime: ReviewSubmissionRawAccessibilityRuntime,
    @unchecked Sendable {
    private let lock = NSLock()
    private let validationFailure: ReviewPreBoundaryFailure?

    init(validationFailure: ReviewPreBoundaryFailure?) {
        self.validationFailure = validationFailure
    }

    func capture(
        _ request: ReviewTargetCaptureRequestDescriptor
    ) -> Result<ReviewSubmissionRawTargetState, ReviewPreBoundaryFailure> {
        let descriptor = CapturedReviewTargetDescriptor(
            generation: request.generation,
            application: request.application,
            binding: .applicationBoundCurrentFocus,
            securityAtCapture: .safe
        )
        return .success(
            ReviewSubmissionRawTargetState(
                descriptor: descriptor,
                applicationElement: AXUIElementCreateApplication(
                    request.application.processIdentifier
                ),
                focusedElement: nil,
                originalSelection: nil
            )
        )
    }

    func validate(
        _ target: ReviewSubmissionRawTargetState,
        deadline: UInt64
    ) -> ReviewPreBoundaryFailure? {
        _ = target
        _ = deadline
        lock.lock()
        let result = validationFailure
        lock.unlock()
        // nil is the injected executable representation of an ordinary
        // noValue/unsupported application-bound capability miss. Typed
        // timeout/security failures remain explicit and fail closed below.
        return result
    }
}

private final class V5LifecycleOverlapRawRuntime: ReviewSubmissionRawAccessibilityRuntime,
    @unchecked Sendable {
    private let lock = NSLock()
    var captureGates: [UInt64: (DispatchSemaphore, DispatchSemaphore)] = [:]
    var captureFailures: Set<UInt64> = []
    var validationGate: (Int, DispatchSemaphore, DispatchSemaphore)?
    private var validationCallCount = 0

    func capture(
        _ request: ReviewTargetCaptureRequestDescriptor
    ) -> Result<ReviewSubmissionRawTargetState, ReviewPreBoundaryFailure> {
        lock.lock()
        let gate = captureGates[request.generation]
        let shouldFail = captureFailures.contains(request.generation)
        lock.unlock()

        gate?.0.signal()
        gate?.1.wait()
        if shouldFail {
            return .failure(.accessibilityFailure)
        }

        let descriptor = CapturedReviewTargetDescriptor(
            generation: request.generation,
            application: request.application,
            binding: .applicationBoundCurrentFocus,
            securityAtCapture: .safe
        )
        return .success(
            ReviewSubmissionRawTargetState(
                descriptor: descriptor,
                applicationElement: AXUIElementCreateApplication(
                    request.application.processIdentifier
                ),
                focusedElement: nil,
                originalSelection: nil
            )
        )
    }

    func validate(
        _ target: ReviewSubmissionRawTargetState,
        deadline: UInt64
    ) -> ReviewPreBoundaryFailure? {
        _ = target
        _ = deadline
        lock.lock()
        validationCallCount += 1
        let gate = validationGate
        let call = validationCallCount
        lock.unlock()
        guard let gate, gate.0 == call else { return nil }
        gate.1.signal()
        gate.2.wait()
        return nil
    }
}

@MainActor
private final class V5LifecycleMonitoringFake: ReviewSubmissionLifecycleMonitoring {
    private(set) var isArmed = true
    private(set) var activeTarget: StableApplicationIdentity?
    private(set) var armRequests: [StableApplicationIdentity] = []
    private(set) var disarmCount = 0
    private(set) var observerEpochAdvanceCount = 0

    func arm(for target: StableApplicationIdentity) -> Bool {
        guard isArmed else { return false }
        armRequests.append(target)
        activeTarget = target
        return true
    }

    func disarm() {
        disarmCount += 1
        activeTarget = nil
    }

    func emitActivation(for target: StableApplicationIdentity) {
        guard activeTarget == target else { return }
        observerEpochAdvanceCount += 1
        CurrentFocusCombinedInterferenceEpoch.shared.advance()
    }

    func emitTermination(for target: StableApplicationIdentity) {
        guard activeTarget == target else { return }
        observerEpochAdvanceCount += 1
        CurrentFocusCombinedInterferenceEpoch.shared.advance()
    }
}

private final class V5CancellationCheckpointRawRuntime: ReviewSubmissionRawAccessibilityRuntime,
    @unchecked Sendable {
    enum Operation: Equatable {
        case setFocused
        case setSelectedRange
        case readback
    }

    let setFocusedReturned = DispatchSemaphore(value: 0)
    let resumeAfterSetFocused = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private(set) var operations: [Operation] = []
    private(set) var cancellationObservedAtCheckpoint = false

    func capture(
        _ request: ReviewTargetCaptureRequestDescriptor
    ) -> Result<ReviewSubmissionRawTargetState, ReviewPreBoundaryFailure> {
        let descriptor = CapturedReviewTargetDescriptor(
            generation: request.generation,
            application: request.application,
            binding: .applicationBoundCurrentFocus,
            securityAtCapture: .safe
        )
        return .success(
            ReviewSubmissionRawTargetState(
                descriptor: descriptor,
                applicationElement: AXUIElementCreateApplication(
                    request.application.processIdentifier
                ),
                focusedElement: nil,
                originalSelection: nil
            )
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
        _ = target
        _ = deadline
        append(.setFocused)
        setFocusedReturned.signal()
        resumeAfterSetFocused.wait()
        cancellationObservedAtCheckpoint = cancellationProbe()
        guard !cancellationObservedAtCheckpoint else { return .cancellation }
        append(.setSelectedRange)
        append(.readback)
        return nil
    }

    private func append(_ operation: Operation) {
        lock.lock()
        operations.append(operation)
        lock.unlock()
    }
}

@MainActor
private enum R1ReviewFixtures {
    static let identity = ReviewApplicationIdentity(
        processIdentifier: 42,
        bundleIdentifier: "com.example.issue40.r1",
        executableURL: URL(fileURLWithPath: "/Applications/Issue40R1.app/Contents/MacOS/R1"),
        launchDate: Date(timeIntervalSince1970: 40)
    )

    static func cursorToken() -> CursorDestinationToken {
        CursorDestinationToken(
            generation: 40,
            processIdentifier: identity.processIdentifier,
            element: AXUIElementCreateApplication(identity.processIdentifier),
            originalSelection: CursorTextRange(location: 0, length: 0)
        )
    }

    static func destination(binding: ReviewDestinationBinding) -> ReviewDestinationToken {
        ReviewDestinationToken(
            generation: 40,
            application: identity,
            binding: binding,
            capturedSecurityState: .safe
        )
    }
}

@MainActor
private final class R1ReviewApplicationRuntime: ReviewApplicationRuntime {
    func identity(for processIdentifier: pid_t) -> ReviewApplicationIdentity? {
        processIdentifier == R1ReviewFixtures.identity.processIdentifier
            ? R1ReviewFixtures.identity
            : nil
    }

    func frontmostIdentity() -> ReviewApplicationIdentity? {
        R1ReviewFixtures.identity
    }

    func frontmostProcessIdentifier() -> pid_t? {
        R1ReviewFixtures.identity.processIdentifier
    }
}

@MainActor
private final class R1ReviewApplicationActivator: ReviewApplicationActivating {
    func activateAndWait(
        for _: ReviewApplicationIdentity,
        timeoutNanoseconds _: UInt64
    ) async -> ReviewActivationResult {
        .activated
    }
}

@MainActor
private final class R1ReviewDestinationAccess: ReviewDestinationAccessing {
    let captureResult: ReviewCursorCaptureResult
    var onRestore: (() -> Void)?

    init(captureResult: ReviewCursorCaptureResult) {
        self.captureResult = captureResult
    }

    func captureReviewCursorDestination(generation: UInt64) -> ReviewCursorCaptureResult {
        captureResult
    }

    func restoreAndValidateBeforeDelivery(_: CursorDestinationToken) throws -> Bool {
        onRestore?()
        return true
    }

    func validateAfterDelivery(_: CursorDestinationToken) throws -> Bool {
        true
    }
}

@MainActor
private final class R1ReviewTrustProvider: AccessibilityTrustProviding {
    var isAccessibilityTrusted = true
}

@MainActor
private final class R1MutableReviewModifierFlags {
    var value: CGEventFlags = []
}

@MainActor
private final class R1MutableReviewSecureInputProvider: SecureInputStateProviding {
    var onQuery: ((Int) -> Void)?
    private(set) var queryCount = 0

    func isSecureInputEnabled() -> Bool {
        queryCount += 1
        onQuery?(queryCount)
        return false
    }
}

@MainActor
private final class R1ReviewFrontmostProcessProvider: FrontmostProcessProviding {
    private let runtime: R1ReviewApplicationRuntime

    init(runtime: R1ReviewApplicationRuntime) {
        self.runtime = runtime
    }

    func frontmostProcessIdentifier() -> pid_t? {
        runtime.frontmostProcessIdentifier()
    }
}

@MainActor
private final class R1ReviewInputMonitor: CurrentFocusInputMonitoring {
    let supportsReviewDeliveryEpoch = true
    var interferenceEpoch: UInt64 = 0

    func startMonitoring(_: @escaping @MainActor () -> Void) {}

    func armMonitoringFailClosed(_: @escaping @MainActor () -> Void) -> Bool {
        true
    }

    func armMonitoringFailClosedWithEpoch(
        _: @escaping @MainActor () -> Void
    ) -> UInt64? {
        interferenceEpoch
    }

    func postCompleteSyntheticPairIfInterferenceEpochIsUnchanged(
        expectedEpoch: UInt64,
        _ postPair: () -> Void
    ) -> Bool {
        guard expectedEpoch == interferenceEpoch else { return false }
        postPair()
        return true
    }

    func stopMonitoring() {}
}

/// A deterministic, non-blocking stand-in for the production monitor's
/// non-recursive epoch gate. The real monitor must never deadlock this test;
/// while the gate is owned, an epoch read records the nested access and
/// returns immediately so the rejected production composition is observable.
@MainActor
private final class ReentrancyDetectingInputMonitor: CurrentFocusInputMonitoring {
    let supportsReviewDeliveryEpoch = true
    var interferenceEpoch: UInt64 {
        if gateDepth > 0 {
            reentrantAccessCount += 1
        }
        return epoch
    }

    private var epoch: UInt64 = 0
    private var gateDepth = 0
    private(set) var reentrantAccessCount = 0
    var advanceEpochBeforeNextPair = false

    func startMonitoring(_: @escaping @MainActor () -> Void) {}

    func armMonitoringFailClosed(_: @escaping @MainActor () -> Void) -> Bool {
        true
    }

    func armMonitoringFailClosedWithEpoch(
        _: @escaping @MainActor () -> Void
    ) -> UInt64? {
        epoch
    }

    func postCompleteSyntheticPairIfInterferenceEpochIsUnchanged(
        expectedEpoch: UInt64,
        _ postPair: () -> Void
    ) -> Bool {
        if advanceEpochBeforeNextPair {
            advanceEpochBeforeNextPair = false
            epoch &+= 1
        }
        guard expectedEpoch == epoch else { return false }
        gateDepth += 1
        defer { gateDepth -= 1 }
        postPair()
        return true
    }

    func stopMonitoring() {}
}

@MainActor
private final class R1ReviewActivationMonitor: CurrentFocusActivationMonitoring {
    let supportsReviewDeliveryEpoch = true
    var activationEpoch: UInt64 = 0

    func startMonitoring(_: @escaping @MainActor (pid_t) -> Void) {}

    func armMonitoringFailClosedWithEpoch(
        _: @escaping @MainActor (pid_t) -> Void
    ) -> UInt64? {
        activationEpoch
    }

    func stopMonitoring() {}
}

@MainActor
private final class FakeFinalTextPasteboardWriter: FinalTextPasteboardWriting {
    private(set) var writtenTexts: [String] = []

    func replaceContents(with text: String) -> Bool {
        writtenTexts.append(text)
        return true
    }
}

@MainActor
private final class FakeFinalTextKeyEventPoster: FinalTextKeyEventPosting {
    var shouldSucceed = true
    private(set) var destinationProcessIdentifiers: [pid_t] = []

    func postCommandV(to processIdentifier: pid_t) -> Bool {
        destinationProcessIdentifiers.append(processIdentifier)
        return shouldSucceed
    }
}

@MainActor
private final class FakeCurrentFocusUnicodeEventPoster: FinalTextCurrentFocusEventPosting {
    private let result: FinalTextCurrentFocusPostResult
    private(set) var requestedTexts: [String] = []
    private(set) var destinationProcessIdentifiers: [pid_t] = []

    init(result: FinalTextCurrentFocusPostResult = .posted) {
        self.result = result
    }

    func postUnicodeText(
        _ text: String,
        to processIdentifier: pid_t
    ) -> FinalTextCurrentFocusPostResult {
        requestedTexts.append(text)
        destinationProcessIdentifiers.append(processIdentifier)
        return result
    }
}

@MainActor
private final class FakeSystemUnicodeEventBackend: FinalTextUnicodeEventBackend {
    enum Failure: String, CaseIterable {
        case source
        case keyDown
        case keyUp
    }

    enum ReadbackFault: String, CaseIterable {
        case tag
        case sourcePID
        case sourceIdentity
        case flags
        case phase
        case payload
        case targetPID
    }

    private let failure: Failure?
    private let keyboardFailurePhase: FinalTextUnicodeEventPhase?
    private let source = FakeUnicodeEventSourceHandle()
    private let trace: FakePosterOperationTrace
    private(set) var sourceStateIDs: [CGEventSourceStateID] = []
    private(set) var constructedEvents: [FakeUnicodeEventHandle] = []
    private(set) var postedEvents: [FakePostedUnicodeEvent] = []
    private(set) var taggedUserData: [Int64] = []
    var readbackFault: ReadbackFault?
    var onConstructedEvent: ((FinalTextUnicodeEventPhase) -> Void)?
    var onPostedEvent: ((FakePostedUnicodeEvent) -> Void)?

    var sourceIdentity: ObjectIdentifier { ObjectIdentifier(source) }
    var operations: [String] { trace.operations }

    init(
        failure: Failure?,
        trace: FakePosterOperationTrace,
        keyboardFailurePhase: FinalTextUnicodeEventPhase? = nil
    ) {
        self.failure = failure
        self.trace = trace
        self.keyboardFailurePhase = keyboardFailurePhase
    }

    func makeEventSource(
        stateID: CGEventSourceStateID
    ) -> (any FinalTextUnicodeEventSourceHandle)? {
        trace.record("source")
        sourceStateIDs.append(stateID)
        return failure == .source ? nil : source
    }

    func makeUnicodeEvent(
        source: any FinalTextUnicodeEventSourceHandle,
        phase: FinalTextUnicodeEventPhase,
        utf16: [UInt16],
        flags: CGEventFlags
    ) -> (any FinalTextUnicodeEventHandle)? {
        trace.record(phase == .keyDown ? "construct-down" : "construct-up")
        if failure == .keyDown, phase == .keyDown { return nil }
        if failure == .keyUp, phase == .keyUp { return nil }
        let event = FakeUnicodeEventHandle(
            phase: readbackFault == .phase
                ? (phase == .keyDown ? .keyUp : .keyDown)
                : phase,
            sourceIdentity: readbackFault == .sourceIdentity
                ? ObjectIdentifier(FakeUnicodeEventSourceHandle())
                : ObjectIdentifier(source),
            sourceProcessIdentifier: readbackFault == .sourcePID ? nil : getpid(),
            utf16: readbackFault == .payload ? Array(utf16.dropLast()) : utf16,
            flags: readbackFault == .flags ? .maskCommand : flags,
            virtualKey: nil
        )
        constructedEvents.append(event)
        onConstructedEvent?(phase)
        return event
    }

    func makeKeyboardEvent(
        source: any FinalTextUnicodeEventSourceHandle,
        phase: FinalTextUnicodeEventPhase,
        virtualKey: CGKeyCode,
        flags: CGEventFlags
    ) -> (any FinalTextUnicodeEventHandle)? {
        trace.record(phase == .keyDown ? "construct-delete-down" : "construct-delete-up")
        if keyboardFailurePhase == phase { return nil }
        let event = FakeUnicodeEventHandle(
            phase: phase,
            sourceIdentity: ObjectIdentifier(source),
            sourceProcessIdentifier: getpid(),
            utf16: [],
            flags: flags,
            virtualKey: virtualKey
        )
        constructedEvents.append(event)
        return event
    }

    func setUserData(
        _ userData: Int64,
        for event: any FinalTextUnicodeEventHandle
    ) {
        guard let event = event as? FakeUnicodeEventHandle else {
            XCTFail("poster tagged an event outside the injected backend")
            return
        }
        trace.record(event.phase == .keyDown ? "tag-down" : "tag-up")
        let actualUserData = readbackFault == .tag ? 0 : userData
        event.userData = actualUserData
        taggedUserData.append(actualUserData)
    }

    func setTargetProcessIdentifier(
        _ processIdentifier: pid_t,
        for event: any FinalTextUnicodeEventHandle
    ) {
        guard let event = event as? FakeUnicodeEventHandle else {
            XCTFail("poster targeted an event outside the injected backend")
            return
        }
        trace.record(event.phase == .keyDown ? "target-down" : "target-up")
        event.targetProcessIdentifier = readbackFault == .targetPID
            ? processIdentifier + 1
            : processIdentifier
    }

    func readbackEvent(_ expectation: FinalTextUnicodeReadback) -> Bool {
        guard let event = expectation.event as? FakeUnicodeEventHandle,
              let source = expectation.source as? FakeUnicodeEventSourceHandle else {
            return false
        }
        trace.record(event.phase == .keyDown ? "readback-down" : "readback-up")
        return event.phase == expectation.expectedPhase
            && event.sourceIdentity == ObjectIdentifier(source)
            && event.sourceProcessIdentifier == expectation.expectedSourceProcessIdentifier
            && event.targetProcessIdentifier == expectation.expectedTargetProcessIdentifier
            && event.utf16 == expectation.expectedUTF16
            && event.flags == expectation.expectedFlags
            && event.userData == expectation.expectedUserData
    }

    func postUnicodeEvent(
        _ event: any FinalTextUnicodeEventHandle,
        to processIdentifier: pid_t
    ) {
        guard let event = event as? FakeUnicodeEventHandle else {
            XCTFail("poster returned an event outside the injected backend")
            return
        }
        let phaseName = event.phase == .keyDown ? "down" : "up"
        let eventName = event.virtualKey == CGKeyCode(kVK_Delete) ? "delete-\(phaseName)" : phaseName
        trace.record("post-\(eventName)-\(processIdentifier)")
        let postedEvent = FakePostedUnicodeEvent(
            phase: event.phase,
            processIdentifier: readbackFault == .targetPID ? processIdentifier + 1 : processIdentifier,
            virtualKey: event.virtualKey,
            utf16: event.utf16
        )
        postedEvents.append(postedEvent)
        onPostedEvent?(postedEvent)
    }
}

@MainActor
private final class FakeUnicodeEventSourceHandle: FinalTextUnicodeEventSourceHandle {}

@MainActor
private final class FakeUnicodeEventHandle: FinalTextUnicodeEventHandle {
    let phase: FinalTextUnicodeEventPhase
    let sourceIdentity: ObjectIdentifier
    let sourceProcessIdentifier: pid_t?
    let utf16: [UInt16]
    let flags: CGEventFlags
    let virtualKey: CGKeyCode?
    var userData: Int64 = 0
    var targetProcessIdentifier: pid_t?

    init(
        phase: FinalTextUnicodeEventPhase,
        sourceIdentity: ObjectIdentifier,
        sourceProcessIdentifier: pid_t?,
        utf16: [UInt16],
        flags: CGEventFlags,
        virtualKey: CGKeyCode?
    ) {
        self.phase = phase
        self.sourceIdentity = sourceIdentity
        self.sourceProcessIdentifier = sourceProcessIdentifier
        self.utf16 = utf16
        self.flags = flags
        self.virtualKey = virtualKey
    }
}

private struct FakePostedUnicodeEvent: Equatable {
    let phase: FinalTextUnicodeEventPhase
    let processIdentifier: pid_t
    let virtualKey: CGKeyCode?
    let utf16: [UInt16]
}

private final class ThreadSafeProductionGateTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

@MainActor
private final class FakePosterOperationTrace {
    private(set) var operations: [String] = []

    func record(_ operation: String) {
        operations.append(operation)
    }
}

@MainActor
private final class FakeTracingSecureInputStateProvider: SecureInputStateProviding {
    private var isEnabled: Bool
    private let trace: FakePosterOperationTrace
    private(set) var queryCount = 0

    init(isEnabled: Bool, trace: FakePosterOperationTrace) {
        self.isEnabled = isEnabled
        self.trace = trace
    }

    func enable() {
        isEnabled = true
    }

    func isSecureInputEnabled() -> Bool {
        queryCount += 1
        trace.record("secure")
        return isEnabled
    }
}

@MainActor
private final class FakeSecureInputStateProvider: SecureInputStateProviding {
    private var states: [Bool]
    private(set) var queryCount = 0

    init(states: [Bool]) {
        self.states = states
    }

    func isSecureInputEnabled() -> Bool {
        queryCount += 1
        guard !states.isEmpty else { return true }
        return states.removeFirst()
    }
}

@MainActor
private final class FakeFrontmostProcessProvider: FrontmostProcessProviding {
    private var processIdentifiers: [pid_t?]
    private(set) var queryCount = 0

    init(processIdentifiers: [pid_t?]) {
        self.processIdentifiers = processIdentifiers
    }

    func frontmostProcessIdentifier() -> pid_t? {
        queryCount += 1
        guard !processIdentifiers.isEmpty else { return nil }
        return processIdentifiers.removeFirst()
    }
}
