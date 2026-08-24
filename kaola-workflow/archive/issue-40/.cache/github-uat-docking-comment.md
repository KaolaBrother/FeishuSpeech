<!-- kw:uat-diagnosis-v2 issue=40 candidate=60090c9 -->
## UAT diagnosis and contract docking receipt — 2026-08-23

The Issue #40 body has been rewritten as the canonical authority after installed-Release UAT.

Docked into the issue itself:

- original strict-AX startup failure evidence on `98e1eb5`;
- candidate `60090c9` implementation scope and automated validation totals;
- installed PID 3567 Fn/streaming/release/barrier/reset/recovery-copy timeline and the second failed
  interaction;
- source-backed release -> sealing -> action-2/barrier -> editable-readiness failure ->
  copy/revoke/dismiss root-cause chain;
- the telemetry boundary: the exact AppKit readiness predicate is still unmeasured;
- explanation of why fake/static/window-independent tests passed;
- the single-output architecture, state machine, component ownership, destination-security model,
  expected file surfaces, dependency-safe implementation order, and complete acceptance checklist.

The updated authority explicitly supersedes two obsolete rules from the prior body/design:

1. compatibility/direct insertion is no longer an allowed user-visible route; and
2. automatic transcript copy on presenter or delivery failure is no longer allowed.

Capture and recognition remain separate asynchronous roots. They converge only into the durable
preview/draft. External delivery can begin only after the user clicks Send or presses bare Return.

Candidate `60090c9` remains rejected for release, Issue #40 remains open, and no implementation
change was made as part of this diagnosis/docking step.
