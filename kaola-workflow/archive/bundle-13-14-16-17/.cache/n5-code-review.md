evidence-binding: n5-code-review 2cdc9c0fc0f5

finding: R1
scope: in_scope
action: follow_up
status: open
severity: warning
file: FeishuSpeech/Views/RecordingOverlayView.swift
description: MainViewModel.overlayMessage is set but not observed by any view — visible empty-result feedback wiring is a follow-up. Node acceptance criteria (observable model state) are satisfied.
fix_role: implementer

finding: R2
scope: in_scope
action: none
status: open
severity: info
file: FeishuSpeech/Services/TextInputSimulator.swift
description: NSPasteboard changeCount reads/writes on global queue — not formally thread-safe but serialized by state machine, low risk, no change required.
fix_role: implementer

finding: R3
scope: pre_existing
action: none
status: open
severity: info
file: FeishuSpeech/Services/TextInputSimulator.swift
description: Import ordering deviates from documented order, consistent with existing codebase practice; defer to swiftlint.
fix_role: implementer

verdict: pass
findings_blocking: 0
code-reviewer
All four fixes are logically correct and thread-safe. n1 clipboard changeCount polling sound; n2 handleRecognitionResult extraction preserves non-empty path; n3 .common run-loop mode correct; n4 generation guard correct with MainActor.assumeIsolated. Approved.
