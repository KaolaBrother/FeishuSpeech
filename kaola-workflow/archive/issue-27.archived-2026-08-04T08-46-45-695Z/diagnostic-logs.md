# Issue #27 UAT log investigation

## Verdict

- **Release cutoff: CONFIRMED.** Release 1.0 build 7 closes snapshot admission at Fn-up. In the recorded successful interaction, two later partial responses and the action-2 terminal response arrived 103 ms, 237 ms, and 1,033 ms after Fn-up; all three were deliberately suppressed. The app reset to idle immediately after sealing the pre-release snapshot.
- **Intermittent active-with-no-output: STRONGLY CORRELATED, not fully session-bound.** Two nearby failure bursts contain 11 HTTP-200 responses rejected with Feishu business code `10024`, followed by retry ordinals `1...8` and `1...3`. These are backend business rejections, not lost TCP/HTTP connections at the recorded failure points. The app classifies exactly `backend(10024)` as recoverable and stays in its retry loop while Fn remains down, which explains an apparently active interaction with no new response eligible for output. The retained log lacks generation/state receipts for those older info-level intervals, so it cannot prove which exact user gesture produced each burst.

No transcript text, target-app content, audio, credentials, token, response body, or stream identifier is included below.

## Setup and evidence boundary

- Repository/worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-27`
- Commit: `26825b829cd654f46a445b0505d82b165dc27e40`
- Host: macOS 26.6 build 25G72
- Installed app: `/Applications/FeishuSpeech.app`, version 1.0 build 7
- Existing Release process: PID `79949`; the investigation did not launch, stop, or operate the app.
- Unified-log command:

  ```text
  /usr/bin/log show --last 8h --info --debug --style json --predicate 'subsystem == "com.feishuspeech.app" AND processImagePath == "/Applications/FeishuSpeech.app/Contents/MacOS/FeishuSpeech"'
  ```

- Captured Release window: 2026-08-04 15:00:32.501493+0800 through 15:06:29.077154+0800.
- Captured 298 Release events: 182 permission refresh events, 100 ViewModel, 11 StreamingSession, 3 HotKey, and 2 Audio. Exact process-path filtering excludes the many XCTest events present under the same subsystem.

## Observation table

| Measurement | Command | Result | Exit |
|---|---|---|---:|
| Baseline commit/status/version/process | `git rev-parse HEAD`; `git status --short --branch`; `sw_vers`; `defaults read ...`; `pgrep -fl ...` | Commit and environment above; worktree branch `workflow/issue-27`; Release PID 79949 already running | 0 |
| Release-only unified log | `log show ... processImagePath == /Applications/FeishuSpeech.app/...` | 298 events in the captured window | 0 |
| Category and receipt aggregation | `jq` over the Release-only JSON | 87 response receipts: 84 eligible before release, 2 sealed late partials, 1 terminal-not-admitted result | 0 |
| Backend rejection aggregation | `jq`/`awk` over Release-only StreamingSession and ViewModel events | 11 rejects, all HTTP 200, response size 318 bytes, business code 10024; paired retry warnings | 0 |
| Focused existing cutoff test | `xcodebuild ... -only-testing:FeishuSpeechTests/StreamingMainViewModelTests/test_releaseSealsSnapshotAdmissionBeforeLatePartialAndFinalCallbacks test` | No behavioral result: Xcode remained blocked waiting for test workers to materialize; investigator interrupted after 174.526 s. Result bundle: `/tmp/feishuspeech-issue27-diagnostic-dd/Logs/Test/Test-FeishuSpeech-2026.08.04_15-08-25-+0800.xcresult` | 75 |

## A. Fn release cuts off late/final recognition

### Recorded generation 9 timeline

| Timestamp (+0800) | Delta from Fn-up | Category | Privacy-safe observation |
|---|---:|---|---|
| 15:03:44.468758 | -106 ms | ViewModel | Packet 158 was the last admitted pre-release response; 279 characters, duplicate snapshot, no mutation needed. |
| 15:03:44.574533 | 0 ms | HotKey | Fn released. |
| 15:03:44.574539 | +0.006 ms | HotKey | Transition `streaming -> sealing`. |
| 15:03:44.587234 | +12.701 ms | Audio | Streaming recording stop began. |
| 15:03:44.605559 | +31.026 ms | Audio | Streaming audio resources released. |
| 15:03:44.677888 | +103.355 ms | ViewModel | Generation 9, attempt 0, packet 159, live partial, 279 UTF-16/characters: `eligibility=sealed`, `ownership=notOwned`, `transaction=sealedSuppressed`. |
| 15:03:44.811151 | +236.618 ms | ViewModel | Generation 9, attempt 0, packet 160, same sealed/suppressed outcome. |
| 15:03:45.607692 | +1,033.159 ms | ViewModel | Generation 9 action-2 terminal result, 277 UTF-16 units: `eligibility=terminalNotAdmitted`, `ownership=notOwned`, `route=sealOnly`, `transaction=exactCommitted`. No terminal text was offered to the output route. |
| 15:03:45.608135 | +1,033.602 ms | HotKey | Manual reset to idle. |

Receipt totals for this retained generation slice were 84 eligible responses, followed by exactly 3 suppressed post-release responses. Output outcomes before release were 29 `replacedOwnedTail`, 1 `appendedSuffix`, and 54 duplicate no-ops. After release there were 2 `sealedSuppressed` partials and 1 seal-only terminal finalization.

### Source correlation

This is current production policy, not an incidental race:

1. `MainViewModel.beginSealing` sets `sealStarted = true` and immediately calls `responseOutputLedger.closeAdmission()` before starting the recorder stop barrier (`MainViewModel.swift:1466-1486`).
2. Any packet callback after that boundary is classified `sealed` (`MainViewModel.swift:1151-1171`).
3. The transport still drains the ingress and invokes `session.finish()` (`MainViewModel.swift:680-759`; `FeishuStreamingSession.swift:230-248`).
4. The terminal callback is deliberately logged as `terminalNotAdmitted`; `finalizeExistingOutputOwner` is called without applying the terminal text (`MainViewModel.swift:1190-1231`).
5. The existing test `test_releaseSealsSnapshotAdmissionBeforeLatePartialAndFinalCallbacks` explicitly expects both a late partial and a late final to leave only the pre-release text applied (`StreamingMainViewModelTests.swift:1393-1420`). The focused runner did not materialize, so this is source/test-contract evidence rather than a new passing-test claim.

**What this rules in:** the user's observed tail cutoff is explained by a deterministic admission boundary at Fn-up. Recognition does continue and action 2 completes; output mutation does not continue.

**What this rules out for generation 9:** an early network disconnect, missing action-2 call, audio-stop barrier failure, or absence of a terminal response. All occurred successfully; the responses were discarded by local output policy.

## B. Active interaction with no output

### Failure burst 1

- 15:00:32.501493: action 0, sequence 99 rejected: HTTP 200, 318-byte response, business code 10024.
- 15:00:32.680960 through 15:00:48.840254: retry ordinals 1 through 8 recorded over 16.159 s.
- Subsequent rejected attempts were action 1 sequence 0, except 15:00:41.404411 where action 0 sequence 1 was rejected. Action 0 sequence 1 proves that replacement session had first accepted action 1 sequence 0 before its next packet failed.
- Action 0 sequence 99 proves the initial transport had progressed well beyond stream establishment before the business rejection.

### Failure burst 2

- 15:01:49.224607: action 0, sequence 1 rejected with the same HTTP 200 / 318 bytes / business code 10024 tuple.
- 15:01:49.418758 through 15:01:50.423815: retry ordinals 1 through 3; replacement attempts failed at action 1 sequence 0.

### Source correlation

- A decoded nonzero business code becomes `StreamFailure.backend(code:)` despite HTTP 200 (`FeishuStreamingSession.swift:415-441`).
- `MainViewModel` treats only backend code 10024 as recoverable (`MainViewModel.swift:833-844`).
- The retry loop logs the ordinal, sleeps with jittered exponential backoff capped at 4 seconds, and remains admitted while the interaction is active (`MainViewModel.swift:780-812`; `StreamingSpeechModels.swift:13-31`). No maximum retry count exists while Fn is held.
- On release, if no usable recognition was admitted, the recoverable-release path becomes `流式识别失败`; if some earlier usable recognition exists, it preserves/finalizes that prior output (`MainViewModel.swift:847-863`).

**High-confidence inference:** during these bursts the UI can remain normally active because recovery is happening inside the still-active streaming generation, while there is nothing to type because every observed response is a rejected business result rather than a recognition snapshot. This matches the user's intermittent “active but nothing comes out” description.

**What the evidence rules out:** a lost connection as the direct cause of these 11 recorded failures. Every one reached Feishu and received HTTP 200 with a decoded business code. It does not rule out network conditions outside those request/response instants.

**Backend-code boundary:** the current official Feishu `stream_recognize` error table documents 1040101 (`invalid param`) and 1040102 (`network anomaly`) but does not define code 10024. The response body/message was intentionally not retained. Therefore this investigation cannot responsibly name the server-side meaning of 10024.

## Narrowing legs

| Axis changed | Result | Hypothesis eliminated |
|---|---|---|
| All subsystem events -> exact installed Release process path | Reduced 4,163 mixed app/XCTest events to 298 Release events | XCTest diagnostics masquerading as UAT evidence |
| Errors only -> info/debug plus errors | Exposed generation 9 packet receipts and Fn/audio state transitions | “The terminal response never arrived” |
| Pre-release -> post-release receipts in same generation | 84 admitted then 3 suppressed | Random target-app insertion loss as the cause of this specific tail cutoff |
| Transport status -> decoded business outcome | All 11 silent-period failures were HTTP 200 / code 10024 | Connection loss as the direct recorded failure mode |
| Failure action/sequence across retries | Long-lived action0/seq99, then new action1/seq0 attempts, with intermittent action0/seq1 | A single permanently dead session with no reconnection attempts |

## What remains unmeasured

1. The retained unified log has no info-level generation/HotKey receipts for the older 15:00 and 15:01 failure bursts. Unified-log info retention is shorter than error retention, so those errors cannot be bound to an exact generation or Fn-up timestamp after the fact.
2. Diagnostics intentionally omit the 16-character Feishu stream ID. The retry ordinal and action/sequence identify attempt shape but not the server-side stream instance.
3. The response headers do not record Feishu's request/log identifier, so code 10024 cannot be escalated to Feishu support from this trace alone.
4. Retry warnings omit the typed failure class and generation. Pairing them with the adjacent StreamingSession rejection is strong temporal evidence, but not an explicit structured causal link.
5. A `transaction=replacedOwnedTail/appendedSuffix` receipt proves the app's synthetic keyboard transaction completed according to its local poster; it cannot prove the target application visually rendered the event.
6. The focused XCTest invocation was blocked by Xcode test-worker materialization and was interrupted without a test verdict. No test pass/fail is inferred from it.

## Investigator conclusion

The release behavior is a confirmed local contract defect relative to the revised UAT requirement: Fn-up currently means “stop admitting recognition output immediately,” while the required behavior is “stop recording, drain all recorded audio, accept the resulting late partial/final authority, finish the replacement transaction, then close output ownership.”

The intermittent silent-active behavior has a separate concrete field signature: Feishu business code 10024 drives the intended unbounded-while-held retry loop. The resilience loop is operating, including creation of replacement sessions, but observability and user-visible liveness are weak and no successful response exists to type during rejection bursts. The exact server-side cause of 10024 remains unmeasured.
