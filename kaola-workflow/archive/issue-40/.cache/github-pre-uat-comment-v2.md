## Issue #40 v2 implementation and pre-UAT evidence — 2026-08-23

Candidate: `aec7aad8ca29eab8cbde90b23be5dbe66ce454e2` on `workflow/issue-40`.

### Delivered contract

- Every accepted Fn interaction and every legacy `reviewBeforeInsert` / `autoInsert` value now converges into one streaming preview.
- Capture/recording and recognition/provider remain independent asynchronous roots.
- Fn release seals; action 2 plus the recorder barrier freezes the same panel as a durable editable draft.
- External output exists only after explicit Send, Return, Enter, or Command+Return; Shift+Return inserts a newline.
- Readiness, delivery, permission, Secure Input, monitoring, and uncertainty failures retain the exact draft for edit/retry/discard with no automatic direct output, copy, retry, or retarget.
- Exact AX authority remains preferred. Application fallback remains bound to the captured application identity/PID and now rechecks live Accessibility trust before activation, at both boundaries of both consecutive preflight composites, and at postflight.

### Evidence

- Final serialized target: 459 executed; 407 passed, 52 intentional skips, 0 failures. The skips are 51 retired direct-output MainViewModel oracles plus one protected live-network test.
- Blueprint-focused final gate: 181 passed, 51 intentional skips, 0 failures.
- Debug and Release builds: passed.
- `swiftlint --strict`: 0 violations.
- `git diff --check`, protected capture/recognition topology, forbidden direct/copy route searches, and documentation link/reference checks: passed.
- Independent correctness review: PASS, 0 blocking findings.
- Independent security review: PASS, 0 blocking findings.
- Documentation docking: 12 README/changelog/architecture/design/decision surfaces updated; D-40 is the current authority and historical direct/recovery routes are marked superseded.

### Installed Release

- Installed path: `/Applications/FeishuSpeech.app`
- Bundle: `Siji.FeishuSpeech`, version `1.0` (`8`)
- Executable SHA-256: `561db2e8bc3abce8bec0a211211c8da4a13cc542d98c05858d8d4e865644bb07`
- Code signature verification: valid and satisfies its designated requirement.
- Installed-location audit: exactly one installed app bundle in `/Applications` / `~/Applications`; exactly one process is running from `/Applications/FeishuSpeech.app`.

### Remaining close gate

The issue intentionally remains open until owner UAT on the installed Release confirms: hold Fn and speak; release Fn; the same preview remains as an editable draft; editing works; Shift+Return inserts a newline; Return sends once to the captured destination. No transcript content should be posted here.
