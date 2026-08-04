# Issue 26 one-word runtime diagnosis

## Result

**PARTIAL runtime proof; strong downstream diagnosis.** The newest observable installed-build UAT contains two held-audio interactions. In the most recent leg, macOS recorded a continuous run of **66 HTTP 200 transaction summaries from 09:19:17.261568 through 09:19:30.806583 CST**, while microphone/capture activity spans 09:19:16-09:19:29. Therefore the app did not stop capturing or exchanging successful HTTP responses after the first visible word. The failure boundary is downstream of transport: response interpretation, MainViewModel routing, or output classification.

The strongest source-consistent explanation is that `CurrentFocusAppendSession` accepts only cumulative hypotheses whose UTF-16 content starts with everything already emitted. A later disjoint or revised Feishu hypothesis is silently classified `revisionSuppressed`; an identical one is silently `duplicate`; an empty one is silently `contentless`. This exactly permits “first word appears, later responses continue, no later visible advance.” Runtime logs do **not** record which of those outcomes occurred, so this is a high-confidence inference, not a directly observed outcome.

No recognized text, audio, credential/token, stream identifier, clipboard/AX content, window title, or document content was read or recorded in this investigation.

## Setup and installed process

- Repository root: `/Users/ylpromax5/Workspace/feishuspeech`
- Issue worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26`
- Both inspected checkouts: commit `7396a7cbdaf37058ca2a9b2df89923525d2ce7c8`; root `main`, worktree `workflow/issue-26`. Repository/product files were not modified; this report is the investigation's only write.
- Host: macOS 26.6 (25G72), timezone CST (UTC+08:00).
- Installed application: `/Applications/FeishuSpeech.app`, version 1.0, build 5, bundle identifier `Siji.FeishuSpeech`.
- Installed bundle and executable timestamps: 2026-08-03 21:20:13 CST; executable SHA-256 `1f0e496200c8a066062c2112793fcbf13a83d77697c56cfd0ba2bd75aef47e6e`.
- Process at baseline sample: PID 81054, PPID 1, started 2026-08-04 09:18:51 CST from the installed application; it remained running when sampled. The investigation did not launch, stop, or interact with it.
- The installed binary contains the expected generation-start, continuous-append, append-suspension, and rejected-response diagnostic format strings. This establishes that the installed build has those diagnostic sites, but not that success-path events were persisted.

## Observation table

| Measurement | Read-only command/surface | Result | Exit |
|---|---|---:|---:|
| Repository baseline | `git status --short --branch`; `git rev-parse HEAD` in root and issue worktree | Same commit; root had pre-existing untracked `.kw/` and `kaola-workflow/issue-26/`; issue worktree clean | 0 |
| Installed metadata | `plutil`, `stat`, `codesign`, `shasum` on installed bundle | Release 1.0 (5), installed before process launch; metadata above | 0 |
| Process context | `pgrep -x FeishuSpeech`; `ps -p 81054 -o ...` | PID 81054, PPID 1, start 09:18:51 CST | 0 |
| Privacy-safe log inventory | `/usr/bin/log show ... --style json`, grouped only by PID/subsystem/category/timestamp/count | UAT activity concentrated in two capture/network legs; no transcript-bearing fields selected | 0 |
| Successful response cadence | CFNetwork `Summary`, extracting only timestamp, `response_status`, and duration | Leg 1: 56 HTTP 200 summaries; leg 2: 66 HTTP 200 summaries; no non-200 summary in either leg | 0 |
| Product diagnostic categories during UAT | Unified log predicate for PID 81054 and categories `ViewModel`, `Audio`, `HotKey`, `StreamingSession`, `CurrentFocusAppendSession` | Zero persisted entries during 09:19:00-09:19:31 | 0 |
| Logger persistence control | Unified-log category inventory for same PID | `Permission` entries persisted later, proving the subsystem itself was present; this does not recover the missing UAT success boundary | 0 |
| Source trace boundary | `nl`/`sed` on streaming, coordinator, ingress, and append-session source | Success-path packet, event, and append outcomes are not logged | 0 |

## Interaction-by-interaction evidence

The unified log does not contain the app's generation number, so “leg 1/2” below means the two temporally separated capture interactions, not a guessed `generation` value.

| Observed leg | Capture-system activity | HTTP 200 response summaries | Observed cadence | Exact app generation/action/sequence | Output outcome |
|---|---|---:|---|---|---|
| 1 | starts 09:19:02; teardown activity at 09:19:13 | 56, from 09:19:03.020075 to 09:19:14.555926 | responses recur throughout the hold, generally multiple per second; terminal-like final gap ends at 14.555926 | Not persisted. Source would use action 1 for first audio packet, action 0 for later packets, action 2 for finish, with monotonically increasing sequence IDs, but the logs cannot assign counts to those actions safely. | Not persisted |
| 2 (most recent, reported one-word symptom) | starts 09:19:16; teardown activity at 09:19:29 | 66, from 09:19:17.261568 to 09:19:30.806583 | uninterrupted successful transactions across about 13.55 s; maximum whole-second gap between adjacent summaries was 1 s | Not persisted for the same reason | Not persisted |

The 6,400-byte ingress packet size at 16 kHz, 16-bit mono represents 0.2 seconds of audio. The observed roughly five-response-per-second cadence matches the serial one-request-per-audio-packet loop. This is corroborating evidence, not a substitute for the absent packet counter.

## What the evidence proves

### Audio packets continued

**Proved at the transport boundary, but not by an app-owned packet counter.** In the second leg, capture-system activity lasts until 09:19:29 and HTTP 200 responses recur from 09:19:17.261568 through 09:19:30.806583. Source sends one request only after `ByteBoundedAudioIngress` yields a packet. The cadence matches 0.2-second packets. A recorder that stopped after one word cannot explain 66 serialized successful transactions across the full hold.

What remains unmeasured is the exact packet ordinal, captured byte total, full-packet count, and tail size for this generation.

### Feishu responses continued

**Proved at HTTP status/timing level.** The second leg has 66 status-200 CFNetwork summaries continuously distributed over the hold. No status other than 200 was extracted. The app's `StreamingSession` rejection logger emitted no persisted malformed-JSON or backend-business-code diagnostic.

What remains unmeasured is the privacy-safe semantic shape of each accepted body: nonempty versus contentless, partial versus final, action, sequence ID, and response byte count. Successes are not logged by `FeishuStreamingSession`.

### MainViewModel continued receiving events

**Strong source-backed inference, not direct runtime instrumentation.** `consumePackets` serially awaits `sendAudioPacket`, then calls `handleStreamingEvent`, before asking ingress for and sending the next packet (`MainViewModel.swift:553-570`). `sendAudioPacket` returns `.partial` only after HTTP 200, JSON decode, business code 0, and sequence advancement (`FeishuStreamingSession.swift:173-203`, `390-441`). Therefore the continuing request chain strongly implies MainViewModel accepted and handled preceding partial events. The last response after capture teardown is consistent with `finish()` producing the terminal final event (`FeishuStreamingSession.swift:206-248`).

Direct proof is unavailable because `handleStreamingEvent`, `handlePartial`, and `handleFinal` record no privacy-safe event receipt diagnostic (`MainViewModel.swift:883-1019`).

### CurrentFocusAppendSession outcome

**Not observable in current logs.** Runtime cannot discriminate among:

- `insertedFirst` followed by `revisionSuppressed` (strongest match if Feishu partials are disjoint or revise earlier content);
- `insertedFirst` followed by `duplicate`;
- `insertedFirst` followed by `contentless`;
- `destinationChanged`, `securityRejected`, or `deliveryUncertain` suspension;
- a different output path (`CursorTextSession` or final-only fallback) rather than `CurrentFocusAppendSession`.

The source makes the first three normal apply outcomes silent. Only suspension reasons log a generic message (`CurrentFocusAppendSession.swift:299-310`), and none persisted for this UAT. Because all other expected app-owned UAT categories are also absent, that absence is insufficient to rule out suspension.

## Narrowing legs

| Axis changed | Observation | Hypothesis eliminated or weakened |
|---|---|---|
| Recorder/capture versus output | Capture-system activity spans the entire interaction | “Microphone stopped after first word” eliminated |
| Network transport versus downstream | 66 consecutive HTTP 200 summaries through the newest hold | Connection/HTTP failure after first word eliminated; early security-triggered termination strongly weakened |
| Accepted-response loop versus rendering | Serial source path cannot send the next packet until the previous event returns through coordinator handling | MainViewModel completely stopped receiving after the first response strongly weakened |
| Output semantics | Append session rejects non-prefix revisions and duplicates without emitting text; those outcomes are unlogged | Revision/disjoint/duplicate/contentless suppression remains live and best matches the symptom |
| Destination/security/delivery | Only generic suspension logs exist, but the entire relevant app-log boundary is missing | These alternatives remain unmeasured, not eliminated |

## Labeled inferences

1. **High confidence:** the defect is not an audio-stop or Feishu HTTP-stop defect. Refutation would require showing that the 66 successful transactions belonged to another concurrent network feature; the source and their 0.2-second cadence make that unlikely.
2. **High confidence:** most pre-terminal response events traversed MainViewModel. Refutation would require an installed-binary path that pipelines those requests without the serial `consumePackets` loop; no such path appears in the inspected source.
3. **Medium-high confidence:** later Feishu hypotheses were disjoint/revised and therefore classified `revisionSuppressed` by cumulative-prefix append logic. This best explains one visible word plus sustained successful traffic. It would be refuted by a privacy-safe trace showing later hypotheses were cumulative and strictly longer.
4. **Medium confidence alternative:** later accepted results were `duplicate` or `contentless`. A per-event content class and UTF-16 length would distinguish them without exposing text.
5. **Lower confidence alternatives:** destination change or delivery uncertainty could suspend output while requests continue. Secure-input rejection is less consistent because MainViewModel schedules termination for that outcome, while the request cadence continued across the hold.

## Exact missing instrumentation

The next UAT needs an app-owned, privacy-safe trace with no transcript content:

- **Audio ingress:** generation, monotonic packet ordinal, captured byte count, full/tail flag, cumulative captured bytes, enqueue timestamp, and finish/fail timestamp/outcome.
- **Streaming session accepted response:** generation, action, sequence ID, HTTP status, response byte count, decode/business outcome, event kind (`partial`/`final`), contentless boolean, and UTF-16 length. Existing diagnostics cover only rejected bodies and do not carry generation.
- **MainViewModel receipt/routing:** generation, event ordinal, source (`livePacket`/`replayCatchUp`), event kind, contentless boolean, UTF-16 length, `sealStarted`, `isTerminal`, selected output path, and handler continuation/termination result.
- **CurrentFocusAppendSession apply/finalize:** generation, hypothesis ordinal, source, prior and candidate UTF-16 lengths, prefix relation boolean, exact `CurrentFocusAppendOutcome` or `CurrentFocusAppendFinalOutcome`, emitted length after, and suspension state. Do not log text or a reversible text hash.

Without these fields, exact action/sequence-to-generation assignment and duplicate/revision/contentless/destination/security/delivery classification cannot be reconstructed from current logs without guessing.

## UAT constraints

- Keep the current app untouched until the owner chooses a newly instrumented build; this investigation did not start/stop it or trigger any permission/UI path.
- A conclusive rerun should use one clearly bounded hold per generation and collect only the privacy-safe fields above.
- Success evidence must show multiple increasing output commits during the hold, not merely continuous HTTP 200 responses or a correct final after release.
- The rerun must separately exercise disjoint, cumulative, revised, duplicate, contentless, destination-change, secure-input, and delivery-uncertain outcomes without logging transcript or destination content.
