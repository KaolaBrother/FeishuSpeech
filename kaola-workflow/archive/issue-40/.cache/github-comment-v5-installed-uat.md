## v5 Release candidate installed — owner UAT required

The third rejected installed candidate is superseded by commit [`bf1d81d`](https://github.com/KaolaBrother/FeishuSpeech/commit/bf1d81d3ff2fa8ee0bc260ee8ed87fc6d7938c8c). Issue #40 remains open and the branch is not merged pending owner UAT.

### Final external-output contract

1. Holding Fn starts the existing asynchronous recording and recognition lines and renders their streaming text only inside the preview.
2. Releasing Fn does not output anything. Final recognition action 2 plus the independent recorder barrier freezes one durable editable draft.
3. Editing, ordinary typing, focus work, and preview presentation do not emit a character, clipboard change, Cmd+V, application activation, retarget, or other external signal.
4. Only the visible preview-local Send button or a qualified Return in the key preview can create a confirmation intent. Blank, IME-marked, repeated, modified, wrong-window, or non-key-panel Return is rejected.
5. After confirmation, the fixed captured target passes the opaque lifecycle lease, exact/application-bound AX proof, leading/binding/trailing security composite, cancellation/deadline matrix, modifier and epoch gates.
6. The executor constructs one immutable Unicode pair, attempts one down and the mandatory up, never retries, and terminalizes without resend authority. Post-boundary status is only `submitted-unverified`; it never claims target consumption.

The canonical design and structure are docked in [`D-40-01`](https://github.com/KaolaBrother/FeishuSpeech/blob/bf1d81d3ff2fa8ee0bc260ee8ed87fc6d7938c8c/docs/decisions/D-40-01.md), [`docs/architecture.md`](https://github.com/KaolaBrother/FeishuSpeech/blob/bf1d81d3ff2fa8ee0bc260ee8ed87fc6d7938c8c/docs/architecture.md), and [`docs/streaming-speech-design.md`](https://github.com/KaolaBrother/FeishuSpeech/blob/bf1d81d3ff2fa8ee0bc260ee8ed87fc6d7938c8c/docs/streaming-speech-design.md). The detailed v5 and v5-r3 blueprints are preserved in the workflow evidence folder with SHA-256 `15f6dacc27306c9df978a5f73d5c36453fc7358354d137ff004704049781ef24` and `21780570e5816147dbc61734f5fa141b27dd3e700bf8d524b74fd689a01dc10c`.

### Validation and independent review

- focused nine-suite matrix: **324 passed, 0 failed, 0 skipped**
- full project target: **537 passed, 0 failed, 1 expected issue-#34 live-TCP skip**
- Debug and Release builds: **PASS**
- strict SwiftLint: **0 violations**
- correctness review R6: **PASS, 0 blockers**
- security review R6: **PASS, 0 blockers**
- accepted-route scan: no clipboard, Cmd+V, app activation, ambient retarget, or legacy direct output
- protected topology: recording drain and recognition consumer remain independent asynchronous roots
- validated candidate tree hash: `6ff2b26b781ede9683f8fee49a1e7c0d5e1dc8b7752f455a9c3e9a67fca90d5d`

### Installed artifact receipt

- installed path: `/Applications/FeishuSpeech.app`
- sole-copy audit: removed 291 DerivedData/temporary `FeishuSpeech.app` bundles; Spotlight, Applications, DerivedData, and bounded `/private/tmp` audits leave only `/Applications/FeishuSpeech.app`
- bundle ID/build: `Siji.FeishuSpeech` / `8`
- executable SHA-256: `1ddd9bd08a0a45866233ddd510c2e0013f19ad2b08d46ff0682ec0eabe1838b0`
- code directory hash: `b33203991a38cedfa991c7f0903a5cdade74c669`
- signature verification: `codesign --verify --deep --strict` passed
- launched PID was verified to execute `/Applications/FeishuSpeech.app/Contents/MacOS/FeishuSpeech`

### Owner UAT gate

Please test in a real third-party input target:

1. Hold Fn and confirm streaming text appears only in the preview.
2. Release Fn and wait for the preview to become a durable editable draft.
3. Edit the draft; confirm no character/image/clipboard/activation side effect occurs before confirmation.
4. Press preview-local Return (and separately Send if desired).
5. Confirm exactly one output attempt appears at the original target and the preview cannot resend after the terminal result.

Any failure rejects this candidate. Merge, Issue #40 closure, workflow archival, and final sink remain blocked until owner UAT passes.
