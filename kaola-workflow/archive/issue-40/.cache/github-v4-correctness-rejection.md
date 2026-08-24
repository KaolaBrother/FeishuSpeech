## 2026-08-23 v4 correctness gate: candidate rejected before installation

The v4 direction remains the canonical repair: all capture/recognition routes converge into one durable editable preview; the independent recorder and recognition tasks remain asynchronous; no target output is authorized before a real **Send** click or qualified **Return/Enter**; the old pasteboard snapshot/replace/restore and synthetic `Cmd+V` path is deleted. The detailed transaction, file ownership, dependency order, and acceptance matrix are in `kaola-workflow/issue-40/architecture-blueprint-v4.md`.

The first integrated v4 candidate passed deterministic security review and clean validation (focused tests, full target, Debug/Release builds, strict lint, diff checks), but **independent correctness review rejected it**. It is not an installable candidate and no GUI/UAT success is claimed.

### Blocking evidence

1. **R1 high — modifier/interference race before first post.** In both exact-cursor and application-bound delivery, binding-specific final validation ran while the physical-input epoch lock was held. A Command/Shift/Control/Option/Fn transition during that validation could not advance the epoch until after the Unicode down/up pair posted. The postflight only downgraded the result to uncertain; it was too late to preserve zero output.
2. **R2 medium — active async coverage was hidden by 51 blanket skips.** The skip list included still-live recorder drain, recognition retry/backoff, journal replay, release barrier, cancellation/reset, and terminal-admission guarantees—not merely obsolete direct-output assertions.
3. **R3 medium — mandatory key-up was partly source-string tested.** Post-down cancellation/fault behavior required executable phase/PID assertions.

### Repaired RED oracle

- `FinalTextOutputSecurityTests`: 32 executed / 20 expected failures. All 10 exact/application × Command/Shift/Control/Option/Fn cases observed `deliveryUncertain` plus `[keyDown, keyUp]`; the required result is pre-boundary failure plus `[]` posts.
- The mandatory-up/cancellation cases are now executable hook tests; before-boundary cases require zero events, and every crossed-boundary case requires exactly down then mandatory up with submitted-unverified semantics.
- The 51-name blanket skip was removed. All 103 `StreamingMainViewModelTests` execute again, with obsolete AX/direct-output expectations migrated to preview-only and zero-output assertions while keeping retry/journal/drain/barrier/cancellation oracles live.
- After migration, the streaming class narrowed from 173 legacy failures to one distinct product regression: post-release drain expiry revokes/marks error instead of preserving the available provisional preview.

Receipts:

- `kaola-workflow/issue-40/.cache/code-review-v4.md`
- `kaola-workflow/issue-40/test-red-v4-r1-r3.md`
- `kaola-workflow/issue-40/.cache/security-review-v4.md`
- `kaola-workflow/issue-40/.cache/validation-v4.md`

### Repair boundary now in flight

- Move binding-specific AX/application validation outside the epoch submission lock.
- Enter a short activation-then-input critical section only after validation, recheck epochs and all relevant combined-session modifiers immediately before the first post, and keep only the mandatory Unicode down/up pair inside it.
- Preserve the provisional draft on post-release drain expiry; do not restore any direct-output/copy/retry path.
- Repeat full serialized tests with no 51-test blanket skip, Debug/Release, strict lint, correctness review, and adversarial security review before any replacement installation.

Operational state: FeishuSpeech remains stopped. The rejected installed v3 copy has not been relaunched, and no v4 build has been installed.
