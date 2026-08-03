# Issue #26 terminal stream comparison

## Scope and baseline

Read-only comparison of FeishuSpeech `e743eccdf24ddd11b92ea2a483c4a7302cd44135`
against KaolaTerminal `613047f6351741a51a99e208873a006523aaea3a`.
No application was launched, no permission UI was touched, no credential was read,
and no live Feishu request was made.

## Finding

There is **no material action-2 wire-contract difference** between the two current
implementations. Both send an empty Base64 audio value with `action = 2`, use the
next sequence number, accept `recognition_text` with `text` fallback, treat missing
response data as an empty string, and fail a nonzero business code or malformed
JSON.

The smallest causal difference that explains the user's observation is instead the
surface on which a partial becomes visible:

- FeishuSpeech writes every non-contentless partial into the bound target before
  release/finalization (`FeishuSpeech/ViewModels/MainViewModel.swift:499-508`).
- KaolaTerminal keeps a partial in its review preview (`KaolaTerminal/Features/Terminal/TerminalSessionViewModel.swift:1250-1264`); it does not make that partial the
  terminal authority.

Therefore, in FeishuSpeech, “the recognition succeeded” can mean only that an
`action = 1` or `action = 0` response produced a partial and that partial was
already inserted. It does **not** prove that the subsequent `action = 2` succeeded.
If action 2 then fails, FeishuSpeech intentionally preserves the already verified
partial and publishes `流式识别失败`. This exactly permits “text appeared
successfully, then a stream-failure notification appeared” in one interaction.

The current repository does not contain evidence that explains why action 2 would
fail repeatedly in the installed/live environment. That requires the separate live
diagnostic evidence (safe action/sequence/status/business-code/malformed-response
classification). The KaolaTerminal reference does not justify changing the action-2
payload or suppressing all post-partial finish failures.

## Exact comparison

### 1. Action-2 request payload and audio

Both implementations send the same terminal request shape:

| Field | FeishuSpeech | KaolaTerminal |
|---|---|---|
| Endpoint | `stream_recognize` at `FeishuStreamingSession.swift:9-11` | same endpoint at `FeishuSpeechRecognizer.swift:198-201` |
| HTTP method/auth | POST + bearer token at `FeishuStreamingSession.swift:470-475` | POST + bearer token at `FeishuSpeechRecognizer.swift:789-802` |
| Terminal action | `action: 2` at `FeishuStreamingSession.swift:233-239` | `action: 2` at `FeishuSpeechRecognizer.swift:692-698` |
| Terminal PCM | `Data()` at `FeishuStreamingSession.swift:234-236`; Base64 encoding at `:461-467` | `Data()` at `FeishuSpeechRecognizer.swift:693-695`; Base64 encoding at `:793-800` |
| Encoded `speech` | empty string, because empty `Data` Base64-encodes to `""` | identical |
| Fixed config | `format = pcm`, `engine_type = 16k_auto` at `FeishuStreamingSession.swift:88-101` | identical at `FeishuSpeechRecognizer.swift:65-78` |

FeishuSpeech's focused test pins `[action] = [1, 0, 2]`, sequences `[0, 1, 2]`,
and PCM byte counts `[6400, 6400, 0]`
(`FeishuSpeechTests/FeishuStreamingSessionTests.swift:126-162`). KaolaTerminal's
reference test pins `[1, 0, 2]` and `[0, 1, 2]`
(`KaolaTerminalTests/FeishuStreamingSpeechRecognizerTests.swift:25-56`).

Conclusion: terminal audio/payload is not a causal difference.

### 2. Sequence ownership

The successful path is equivalent:

- FeishuSpeech reads `nextSequenceID`, sends, and increments only after the response
  is accepted (`FeishuStreamingSession.swift:181-194`); finish uses the current value
  and increments after success (`:233-244`).
- KaolaTerminal reads and increments before sending (`FeishuSpeechRecognizer.swift:628-642`,
  `:688-700`).

The timing difference affects only local bookkeeping after a failed request. It does
not change the sequence on the first accepted packet or the normal action-2 request,
so it cannot explain a successful partial followed by the first finish failure.

### 3. Response decoding

The response contract is now materially identical:

- FeishuSpeech decodes `code` plus optional `data`; data accepts optional
  `recognition_text` and optional `text`, preferring the former
  (`FeishuStreamingSession.swift:104-121`).
- KaolaTerminal uses the same tolerant fields and precedence
  (`FeishuSpeechRecognizer.swift:40-58`).
- Both require HTTP 200 and valid JSON, reject nonzero `code`, and return
  `decoded.data?.transcription ?? ""`
  (`FeishuStreamingSession.swift:394-433`;
  `FeishuSpeechRecognizer.swift:804-832`).
- Neither current decoder requires response `stream_id` or `sequence_id` echoes.
  FeishuSpeech explicitly tests missing data, mismatched echoes, and unexpected echo
  types as accepted (`FeishuStreamingSessionTests.swift:71-116`).

Conclusion: the old over-strict response-echo/data validation is no longer present
and cannot explain this new post-partial symptom in current source.

### 4. Empty and nonempty final results

FeishuSpeech:

- A nonempty final is delivered and then completes normally
  (`MainViewModel.swift:511-529`, `:532-547`).
- A contentless final is still a successful terminal result. It preserves the
  existing partial, publishes bounded `emptyFinalPreservedPartial` feedback, then
  completes normally (`:516-529`, `:675-696`).
- The preservation behavior is covered for empty/whitespace finals at
  `StreamingMainViewModelTests.swift:471-535`.

KaolaTerminal:

- Any `.final(text)` becomes an editable review draft
  (`TerminalSessionViewModel.swift:1265-1275`).
- Sanitized empty final gets warning feedback `No speech text detected`; nonempty
  final gets success feedback (`:1271-1275`).

Conclusion: neither implementation treats an empty code-zero action-2 result as a
stream failure.

### 5. Finish failure after an accepted partial

Both implementations treat a real terminal failure as a failure even when a partial
was already accepted:

- FeishuSpeech catches `session.finish()` failure and routes it to the generic
  streaming failure path (`MainViewModel.swift:416-453`). The cursor session receives
  `.failed(.network)` before abnormal termination (`:442-453`), and the test confirms
  that the previously verified partial remains in the target for a failed terminal
  event (`StreamingMainViewModelTests.swift:471-496`).
- KaolaTerminal catches finish failure and calls recovery
  (`TerminalSessionViewModel.swift:1162-1237`). Recovery extracts the current preview,
  retains it as an editable draft, publishes error feedback, and cancels the controller
  session (`:1308-1357`).

Thus the reference behavior does not say “an accepted partial converts all finish
failures into success.” It says the user's recognized partial/draft must be preserved
while the terminal failure remains visible.

### 6. Teardown and repeated feedback

FeishuSpeech abnormal teardown:

1. invalidates the active generation/cursor;
2. fails ingress and clears task references;
3. hides the overlay;
4. cancels the task, cleans the recorder, and cancels the session;
5. publishes one error state

(`MainViewModel.swift:698-721`). Late events lose authority because `isActive` checks
the identity (`:744-746`), and the stale-event test confirms no late partial/final/
failure changes idle state (`StreamingMainViewModelTests.swift:650-674`). One terminal
event is tested to cause exactly one cleanup (`StreamingMainViewModelTests.swift:80-121`).

`HotKeyService.setError` ignores an already-published identical error
(`HotKeyService.swift:484-492`), with explicit repeated-publication coverage
(`HotKeyServiceTests.swift:82-99`). `MainViewModel` resets an error to idle after a
three-second debounce (`MainViewModel.swift:877-887`). A release while the hot-key
state is already `.error` does not start another finish (`HotKeyService.swift:337-343`).

KaolaTerminal similarly uses generation/session authority checks before applying a
finish result (`TerminalSessionViewModel.swift:1182-1190`, `:1240-1248`), tears down
ownership while preserving the draft (`:1321-1357`), and consumes the next release
after an early failure with `suppressNextVoiceReleaseAfterFailure`
(`:1084-1087`, `:1349-1351`).

No current production path was found that repeatedly republishes the same terminal
failure from one accepted FeishuSpeech generation. If the user sees recurring alerts,
the remaining distinctions are:

1. one alert per new interaction because each interaction reaches and fails its own
   terminal request; or
2. a live/installed binary or runtime path differing from this source; or
3. an external recorder/provider failure independently starting a new error path.

The safe live logs are needed to distinguish these. Source comparison alone cannot.

## Facts versus inference

### Confirmed facts

- Current action-2 request/audio/config and successful sequence are equivalent.
- Current response decoding is equivalent for the relevant fields.
- Empty code-zero final is normal completion in both implementations.
- A true finish failure remains a failure in both implementations, while prior text
  is preserved.
- FeishuSpeech can expose a partial in the target before action 2 begins.
- Current FeishuSpeech has generation invalidation and identical-error suppression.

### Inference

The most economical explanation for “first successful recognition followed by
stream-failure feedback” is: the visible “success” was a partial, followed by a real
action-2 failure. This inference is structurally supported but cannot identify the
live failure class without the privacy-safe runtime diagnostic.

### Unknowns blocking a reliable fix plan

- Whether the recurring live failure is action 2 or a later/new interaction's action
  1/0; source alone does not show runtime action/sequence.
- HTTP status, response byte count, business code, or malformed-JSON classification
  for the post-success failure.
- Whether “keeps notify” means one alert per hold or repeated alerts without another
  hold.
- Whether the installed executable exactly matches the current repository candidate.

## Likely validation surfaces

- Transport: `FeishuSpeechTests/FeishuStreamingSessionTests.swift`
- Coordinator/final/teardown: `FeishuSpeechTests/StreamingMainViewModelTests.swift`
- Duplicate hot-key error publication: `FeishuSpeechTests/HotKeyServiceTests.swift`
- Kaola reference transport: `KaolaTerminalTests/FeishuStreamingSpeechRecognizerTests.swift`
- Kaola lifecycle/review recovery: `KaolaTerminalTests/SpeechStreamingLifecycleTests.swift`
  and `KaolaTerminalTests/TerminalSessionViewModelTests.swift`

Read-only validation commands for a later test-owning/validation role:

```sh
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test \
  -only-testing:FeishuSpeechTests/FeishuStreamingSessionTests \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests \
  -only-testing:FeishuSpeechTests/HotKeyServiceTests

xcodebuild -scheme KaolaTerminal \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  test -parallel-testing-enabled NO \
  -only-testing:KaolaTerminalTests/FeishuStreamingSpeechRecognizerTests \
  -only-testing:KaolaTerminalTests/SpeechStreamingLifecycleTests \
  -only-testing:KaolaTerminalTests/TerminalSessionViewModelTests
```

These commands were not run in this read-only comparison because no source changed
and the requested deliverable was a code-path analysis.
