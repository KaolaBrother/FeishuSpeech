## Installed v5 UAT failure diagnosed and repaired inline as v6

Owner report: an accepted Fn hold immediately showed `无法确认输入位置`, so the streaming preview never
became useful.

### Measured root cause

- Installed v5 launched at **19:04:19**; macOS wrote the Accessibility TCC authorization at
  **19:04:24**.
- The production lifecycle observer installed its workspace/local/global monitors once during
  initialization. If the global monitor was unavailable before Accessibility authorization completed,
  it removed the partial set and never retried.
- Every later fixed-target lease therefore returned typed `accessibilityFailure`.
- `MainViewModel.completeReviewTargetCapture` mapped that capture failure to the exact reported message
  before audio/provider startup. Recording and recognition were not the failing components.

### v6 design and implementation

Production commit: [`39848ee4`](https://github.com/KaolaBrother/FeishuSpeech/commit/39848ee4aa16f807b7ac81fb6a186891e71ba6ab)

- Before acquiring the original-target lease, production now verifies the complete observer set.
- If initialization preceded permission, it removes partial state and reinstalls all observers in place.
- If reinstallation still fails, capture remains pre-boundary fail-closed: zero character/image/clipboard/
  activation/AX-insertion/Unicode-event output is possible.
- Capture-failure logs contain only the typed enum, never transcript or target text.
- Recording/capture and recognition/provider remain independent asynchronous roots; Fn release still only
  seals capture. No confirmation/output state or ordering was weakened.

Documentation/install-state commit: [`ae53360`](https://github.com/KaolaBrother/FeishuSpeech/commit/ae533602f2642d87354ed1e40090c11a7a246f89)

### Bound validation evidence

- Focused nine-suite matrix: **324/324**, 0 failed, 0 skipped.
- Full serialized macOS target: **537 tests**, 0 failed, 1 expected Issue #34 live-TCP skip.
- Debug and Release builds: `BUILD SUCCEEDED`.
- SwiftLint strict: 0 violations in 36 files.
- `git diff --check`: pass.

### Installed candidate and remaining owner gate

- `/Applications/FeishuSpeech.app` is the sole audited application copy.
- Executable SHA-256: `2adb263bb8bc1b4b6ecc0bac1a1718da007c5432a1b65473af9954ff58c17208`
- CDHash: `77d8046dc8a48d3e209070f164bd57e76ca8ec64`
- Stable signature: `Apple Development: Yanlei Chen (C2D65N458L)`;
  TeamIdentifier `D5KY7PZC5N`.
- The previous TCC row is pinned to rejected v5's ad-hoc CDHash. The new installed binary therefore
  correctly reports Accessibility false until the owner authorizes the current signed app. System Settings
  is open at Privacy & Security > Accessibility.

Issue #40 remains **OPEN / P1 / workflow:in-progress**. After Accessibility is reauthorized, owner UAT must
still prove: Fn shows the streaming preview; Fn release + final recognition yields the durable editable draft;
editing has zero external side effects; and preview-local Send or qualified Return causes exactly one output
attempt at the original application.
