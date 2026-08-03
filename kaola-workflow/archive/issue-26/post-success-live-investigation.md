# Issue #26 post-success live investigation

## Claim and success criterion

Claim under investigation: the currently installed Release accepts an initial recognition, then
publishes `流式识别失败` repeatedly. Success means reconstructing the existing runtime sequence at
the narrowest privacy-safe boundary: timestamp, request action, sequence, HTTP status, sanitized
business outcome, application state publication, and repetition count; then tracing that sequence
to source without reading transcript content, credentials, tokens, stream IDs, raw response bodies,
audio, clipboard data, or target-application content.

This investigation did not launch or stop the application, issue an API request, trigger microphone,
Accessibility, or notification permissions, or edit production/tests. The only write is this report.

## Setup

- Main repository: `/Users/ylpromax5/Workspace/feishuspeech`
- Issue worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26`
- Source commit in both roots: `e743eccdf24ddd11b92ea2a483c4a7302cd44135`
- Runtime: macOS 26.6 (25G72)
- Installed bundle: `/Applications/FeishuSpeech.app`, version 1.0, build 3, identifier
  `Siji.FeishuSpeech`
- Installed executable SHA-256:
  `10df444a7ef63ed033cf20bb63db384d6cb45699ea63cd27729b4c3a1698f1ab`
- Installed executable CDHash: `283a4a4f8c57df812fa7d736f9d91407de5ccce5`
- Existing process at baseline: PID 33111, launched 2026-08-03 17:05:36 +08:00 from the installed
  bundle; it remained running throughout the investigation.
- The bundle has no independently inspected embedded commit marker. Build number, executable
  digest, and the presence/shape of the new diagnostic establish the measured artifact, but exact
  cryptographic equivalence to source commit `e743ecc` remains unproven.

Primary commands (all exit 0 unless noted):

```text
git rev-parse HEAD
git -C .kw/worktrees/issue-26 rev-parse HEAD
sw_vers
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' .../Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' .../Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' .../Info.plist
shasum -a 256 /Applications/FeishuSpeech.app/Contents/MacOS/FeishuSpeech
codesign -dv --verbose=4 /Applications/FeishuSpeech.app
ps -p 33111 -o pid=,lstart=,etime=,%cpu=,%mem=,command=
/usr/bin/log show --start '2026-08-03 17:05:30' ...
  --predicate 'process == "FeishuSpeech" && subsystem == "com.feishuspeech.app" && (...)'
/usr/bin/log show --start '2026-08-03 17:05:50' --end '2026-08-03 17:06:15' ...
  --predicate 'process == "FeishuSpeech" && subsystem == "com.apple.CFNetwork" && (...)'
/usr/bin/log show --start '2026-08-03 17:05:30' ...
  --predicate '(process == "usernoted" || process == "NotificationCenter") &&
               eventMessage CONTAINS[c] "FeishuSpeech"'
rg / sed / nl over FeishuStreamingSession.swift, MainViewModel.swift,
HotKeyService.swift, TextInputSimulator.swift, RecordingState.swift,
OverlayWindowController.swift, MenuBarView.swift, and FeishuSpeechApp.swift
```

One initial bundle-metadata attempt used nonexistent `/usr/bin/PlistBuddy` and exited 127. It
produced no measurement; the supported `/usr/libexec/PlistBuddy` path was then used successfully.

## Observation table

| Measurement | Command / method | Raw result | Exit |
|---|---|---|---:|
| Source baseline | `git rev-parse HEAD` in both roots | both `e743eccdf24ddd11b92ea2a483c4a7302cd44135` | 0 |
| Installed artifact | `PlistBuddy`, `shasum`, `codesign` | version 1.0/build 3; identifier and digests above | 0 |
| Existing runtime | `ps -p 33111 ...` | installed process launched 17:05:36 and remained alive | 0 |
| First accepted request in measured burst | filtered CFNetwork log | 17:05:56.266–17:05:56.454; HTTP 200; 187 ms; 9,909 request bytes; 859 response bytes | 0 |
| Second accepted request in measured burst | filtered CFNetwork log | 17:05:56.469–17:05:56.589; HTTP 200; 119 ms; 9,749 request bytes; 860 response bytes | 0 |
| First post-success rejection | app diagnostic + CFNetwork | 17:05:56.818; `action=0`, `sequenceID=2`, HTTP 200, decoded business code 10024, outcome `backendBusinessCode`, diagnostic body count 318 bytes | 0 |
| First public error publication | app diagnostic | 17:05:56.818; `Setting error state: 流式识别失败`, same displayed millisecond as rejection | 0 |
| First repeated attempt | app diagnostic + CFNetwork | 17:06:04.030 rejection: `action=1`, `sequenceID=0`, HTTP 200, code 10024, body count 318; error publication 17:06:04.031 | 0 |
| Second repeated attempt | app diagnostic + CFNetwork | 17:06:08.765 rejection: `action=1`, `sequenceID=0`, HTTP 200, code 10024, body count 318; error publication 17:06:08.766 | 0 |
| Third repeated attempt | app diagnostic + CFNetwork | 17:06:11.501 rejection: `action=1`, `sequenceID=0`, HTTP 200, code 10024, body count 318; error publication 17:06:11.502 | 0 |
| Network requests after each rejection | chronological CFNetwork task summaries | no request after 17:05:56.818 until 17:06:03.678; each later attempt has exactly one request and no immediate finish/abort request | 0 |
| Error-publication count | exact app-log predicate | 4 `Setting error state` records paired one-for-one with 4 rejected responses; 0 `Ignoring repeated identical error state` records | 0 |
| App-created system notification evidence | `usernoted`/`NotificationCenter` FeishuSpeech-name predicate and app fallback-log predicate | 0 matching records | 0 |

The four rejected response-to-error publication lags, using displayed log timestamps, are 0 ms,
1 ms, 1 ms, and 1 ms. Inter-publication intervals are 7.213 s, 4.735 s, and 2.736 s.

No response body, response message, recognition text, request body, header, bearer token,
credential, stream ID, audio, clipboard content, or destination content was inspected or recorded.
Only CFNetwork byte counts/status/duration and the purpose-built sanitized app diagnostic were read.

## Reproduction status

**Reproduced from existing runtime evidence.** The measured process first completed two HTTP-200
streaming requests. The third request was then rejected at the decoded application-business layer
with HTTP 200 / business code 10024 at `action=0, sequenceID=2`. The user's report supplies the
observation that recognition had appeared after the earlier accepted requests; transcript content
was neither logged nor inspected.

Three later interactions each failed on their first packet at `action=1, sequenceID=0` with the
same HTTP status, body size, business code, and outcome. Thus the repetition is four terminal error
publications total: the post-success failure plus three fresh-attempt failures. It is not four
publications from one response.

Generation numbers are not persisted at error level in this Release. They cannot be reported
exactly. However, the three later `action=1, sequenceID=0` records necessarily belong to fresh
`FeishuStreamingSession` instances: code 10024 maps to `.backend`, not the one allowed initial-token
retry, and a failed session retains its terminal failure and cannot send another first packet.

## Exact state and notification trace

### Verified from logs

1. Two network requests completed with HTTP 200 at 17:05:56.454 and 17:05:56.589.
2. At 17:05:56.818 the next streaming packet was decoded and rejected as business code 10024 at
   `action=0, sequenceID=2`.
3. At the same displayed millisecond, HotKey published `.error("流式识别失败")` once.
4. New sessions repeated the sequence at 17:06:04.030/031, 17:06:08.765/766, and
   17:06:11.501/502, each at `action=1, sequenceID=0`.
5. There is no immediate network request after any rejection. In particular, the first established
   stream has neither a measured finish request nor a measured abort request after its failure.

### Verified from source

- A new session chooses `action=1`; after first acceptance it chooses `action=0`, and increments
  sequence only after an accepted response (`FeishuStreamingSession.swift:181-194`). Therefore a
  rejected `action=0, sequenceID=2` proves that sequences 0 and 1 were accepted by this client.
- HTTP 200 plus decoded nonzero business code emits the sanitized diagnostic, then maps code 10024
  to `StreamFailure.backend` (`FeishuStreamingSession.swift:394-433`). It is not the recognized
  invalid-token code and is not retried by the token-refresh branch (`:330-358`).
- `recordFailureIfActive` sets terminal state to `.failed` (`:504-513`). Coordinator failure handling
  then invalidates the active identity, hides the overlay, force-cleans audio, and calls
  `session.cancel()` before publishing the fixed error (`MainViewModel.swift:442-463,698-721`).
- `cancel()` immediately returns unless terminal state is `.none`
  (`FeishuStreamingSession.swift:253-285`). Because the response failure has already recorded
  `.failed`, the established stream cannot reach the action-3 best-effort abort path. It also cannot
  reach action 2 because the packet loop threw before normal sealing/finish.
- The public error is a bounded application state, not the clipboard-fallback system notification.
  The menu-bar label and menu content render `viewModel.status`; the recording overlay is hidden
  before `.error` is assigned. The sole `UNUserNotificationCenter` path is the unrelated fixed
  `已复制到剪贴板` fallback (`TextInputSimulator.swift:362-379`).
- Identical `.error` publication inside one state is suppressed (`HotKeyService.swift:484-492`).
  A later Fn press from `.error` explicitly resets to `.idle` and starts a new pending interaction
  (`:307-327`), so a genuinely new failed session may publish the same error again. Status also
  auto-recovers after a 3-second debounce (`MainViewModel.swift:877-887`).

Therefore the user's word “notification” corresponds, on the measured source path, to the repeated
menu-bar/application error state. There is no evidence that these streaming failures invoke a
macOS `UNUserNotificationCenter` notification, and the source path contains no such call.

## Narrowing legs

### Leg 1 — transport versus backend business outcome

All six measured streaming network transactions (two accepted before the failure, the rejected
third packet, and three later first-packet attempts) completed at HTTP 200. The diagnostic
successfully decoded business code 10024. This rules out DNS, connection failure, timeout, HTTP
failure, malformed JSON, and the earlier response-shape compatibility problem for these rejected
responses.

### Leg 2 — finish response versus mid-stream packet

The first rejection is `action=0, sequenceID=2`, not terminal `action=2`. This rules out the claim
that the observed first failure is caused by parsing the normal finish response. The failure occurs
on a continuing audio packet after two accepted packets.

### Leg 3 — one-response re-entry loop versus separate sessions

There is exactly one `Setting error state` record per rejected response and no
`Ignoring repeated identical error state` record. Later failures are each `action=1, sequenceID=0`,
which a terminal session cannot resend for code 10024. This rules out the previously fixed recursive
error-state feedback loop as the source of the four measured publications. The visible repetition
comes from the initial failed session plus three newly started sessions.

### Leg 4 — teardown request behavior

CFNetwork shows no post-rejection request before the next interaction. Source tracing shows why:
the response path records `.failed` before coordinator cleanup calls `cancel()`, and `cancel()` only
attempts action 3 from `.none`. This rules in a concrete client lifecycle gap: an established stream
that receives a mid-stream backend rejection is abandoned locally without finish or abort.

## Inferences

### High confidence

The immediate cause of every displayed error is the Feishu endpoint's decoded **business code
10024**, returned inside HTTP 200. The first occurrence is a mid-stream packet after two accepted
packets; the next three are first-packet rejections in fresh sessions. The client intentionally
sanitizes all non-auth `StreamFailure` values to `流式识别失败`, hiding that actionable distinction
from the public UI.

The repeated UI symptom is not one callback recursively notifying forever. It is one exact error
publication for each separately rejected interaction.

### Medium confidence

The missing action-2/action-3 teardown after the first established-stream rejection is the strongest
local candidate for why subsequent fresh streams remain rejected. The code and CFNetwork trace prove
the missing teardown; they do **not** prove that Feishu business code 10024 specifically means an
unterminated prior stream or that sending an abort would clear it. That causal link would be refuted
if an authoritative provider contract assigns code 10024 to an unrelated condition, or if a
controlled lifecycle test shows the same repeated rejection after a successful abort.

### Low confidence / not adopted as conclusion

Tenant configuration, concurrency limits, rate limits, engine policy, or another provider-side rule
could also produce code 10024. No local authoritative mapping for 10024 was found, and external
provider documentation was not consulted in this bounded machine-local investigation. None of those
specific meanings should be reported as verified.

## What remains unmeasured

- The provider-authoritative semantic meaning of business code 10024.
- Exact generation numbers and Fn press/release timestamps; Release persistence retained errors and
  CFNetwork metrics but not the relevant info-level state logs.
- Whether the two accepted responses contained nonempty partials. The owner observed recognition,
  but content and response bodies were intentionally outside scope.
- Whether a successful action-3 abort after a mid-stream backend rejection would clear later
  action-1 requests.
- Whether code 10024 itself semantically terminates the provider-side stream, making an abort
  unnecessary despite the client lifecycle gap.
- Independent cryptographic proof that the installed executable corresponds byte-for-byte to source
  commit `e743ecc`.

This report does not choose a fix. It establishes the measured boundary and leaves the remedy to the
implementation owner.
