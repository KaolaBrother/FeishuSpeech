## Owner UAT passed — v9 ready to finalize

Date: 2026-08-24

Published evidence: https://github.com/KaolaBrother/FeishuSpeech/issues/40#issuecomment-5395158661

The owner exercised the installed v9 flow and reported that it now looks good
with no remaining observed problem, authorizing Issue #40 finalization.

Exercised acceptance path:

1. Fn starts the one review-first interaction.
2. Streaming recognition appears in the preview.
3. Fn release retains the preview and settles it into a durable editable draft.
4. The user can edit and explicitly confirm through the preview.
5. No output is authorized before panel-local Send or qualified Return/Enter.

Bound candidate and receipts:

- commit `584e09d` (`fix: admit non-native AX roles to review preview`), pushed to
  `workflow/issue-40`;
- focused security/delivery matrix: 100 passed, 0 failed;
- full macOS target: 539 passed, 1 expected live-TCP skip, 0 failed;
- strict SwiftLint: 0 violations;
- Apple Development-signed `/Applications/FeishuSpeech.app`, sole-copy audit
  passed;
- CDHash `5bbecdf0c1f33a1cb2e477021c98a75ee32392bd`;
- executable SHA-256
  `c2e9f2797c86789e69394e68dbd8c308767f5bd5cbb971d839e2213cd681d0ea`.

The accepted scope remains precise: recording/capture and recognition/provider
stay independent asynchronous roots; Secure Input, Accessibility trust,
identity/frontmost drift, cancellation, deadline, modifier/interference, and
lifecycle checks remain fail closed; explicit confirmation authorizes at most
one bounded Unicode submission attempt with no clipboard, Cmd+V, activation,
retarget, or retry after the boundary.

This UAT closes the exercised Issue #40 acceptance path. It does not claim broad
compatibility with every third-party control or an OS-level acknowledgement that
the target consumed a posted Unicode pair.
