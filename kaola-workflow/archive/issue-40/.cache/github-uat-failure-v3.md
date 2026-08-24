## Installed Release UAT failed — UI/readiness follow-up, 2026-08-23

Installed candidate: `aec7aad8ca29eab8cbde90b23be5dbe66ce454e2`.

Owner-observed evidence:

- After speech stops, the same preview is typeable but remains in the `重试编辑` presentation instead of exposing direct Send/Return.
- The panel dimensions are acceptable; only transcript text in preview/editing is too small.
- During streaming, the `输入前预览`/content placement overlaps the upper-left traffic-light controls; after editing begins, placement becomes correct.

Acceptance correction:

- Remove the `重试编辑` control and repair the readiness transition so a genuinely ready/typeable frozen draft becomes directly sendable without weakening fail-closed security or the explicit-confirm-only gate.
- Increase transcript font size without enlarging the panel.
- Keep read-only streaming content/title below and clear of the titlebar controls.

Issue #40 remains open. Merge, closure, archive, and final installation are paused until focused RED/GREEN evidence, full validation, independent re-review, replacement Release installation, and owner UAT all pass. No transcript content is recorded.
