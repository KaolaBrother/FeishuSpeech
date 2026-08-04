# Issue #27 documentation docking receipt

## Verdict

DOCKED. Documentation now matches the verified Release 1.0 build 8 release-drain and resilience
contract. No real-credential or cross-application UAT success is claimed.

## Evidence reconciled

- `diagnostic-logs.md` and `lifecycle-trace.md`: build 7 suppressed valid tail packets and action-2
  final after Fn-up; repeated HTTP-200 business code `10024` correlated with active-but-silent
  recovery, without an asserted provider meaning.
- `release-drain-blueprint.md`: Fn-up is a capture boundary; the current generation drains queued
  and tail audio, retries/replays, accepts terminal authority, and closes output only afterward.
- `coordinator-green.md`, `keyboard-final-green.md`, and `review-green-r1-r4.md`: packet ACK resets
  consecutive backoff; factory/send/finish use 30-second watchdogs; the post-recorder-barrier drain
  budget is 60 seconds; safe action-2 final reconciliation reuses the original AX/fixed-PID owner;
  expiry preserves typed output state and suppresses late work.
- `review-correctness.md` and `review-security.md`: R1-R4 are resolved; fixed target, Secure Input,
  physical-interference epoch, unsafe-control rejection, stale generation/attempt suppression, and
  transcript-free diagnostics remain fail closed.
- Production/test diff `26825b8..b10a40c` and project metadata: Release 1.0 build 8; final authored
  suite evidence is 316/316.

## Updated documentation surfaces

- `README.md`: user-facing Fn-up drain behavior, authoritative final replacement, watchdog/drain
  limits, retry reset, expiry outcomes, build 8 verification, and pending owner UAT.
- `CHANGELOG.md`: release-tail cutoff and silent-active resilience fixes, supersession of the old
  release-immediate-seal policy, build 8 verification, and explicit pending UAT.
- `docs/architecture.md`: capture versus response authority, post-barrier drain lifecycle,
  operation deadlines, terminal reconciliation, output-preservation state, and stale-result gates.
- `docs/api.md`: generation-wide retry/ACK reset, backend `10024` recovery boundary, 30-second
  factory/send/finish watchdogs, 60-second drain budget, action-2 authority, and expiry semantics.
- `docs/decisions/D-27-01.md`: decision extended from snapshot replacement to release drain,
  authoritative terminal output, resilience deadlines, and conservative expiry.
- `docs/streaming-speech-design.md`: detailed state, recovery, writer, diagnostics, test, and
  completion contracts updated to the final behavior.
- `docs/README.md`: navigation descriptions updated; no new document was added.

No change was needed in `docs/conventions.md` or older decision records: coding/review conventions
did not change, and D-27-01 is the explicit superseding current contract. `CLAUDE.md` and
`AGENTS.md` were deliberately not edited because project rules and the canonical redirect did not
change.

## Validation

- `git diff --check`: passed before commit.
- Local Markdown link existence check across all changed documentation: passed.
- Contradiction sweep for build 7/300-of-300, immediate release admission closure, action-2
  non-authority, and non-resetting retry ordinal: only the changelog's historical build 7 defect
  reference remains.
- Staged scope check: exactly seven documentation files; no code, tests, project configuration,
  workflow records, or installed application entered the commit.

Documentation commit: `b78e68a docs: document release drain and resilience`.

## Remaining documentation risk

The local test/build evidence cannot prove Feishu credential-bearing behavior or target-control
acceptance of PID-targeted events. Those remain owner-UAT gates and are stated as pending throughout
the user, architecture, API, decision, and design surfaces. Diagnostics remain specified as counts,
typed phases/failures, timing, and preservation state only; transcript, audio, credentials, token,
response body, stream ID, target content, and content-derived hashes remain forbidden.
