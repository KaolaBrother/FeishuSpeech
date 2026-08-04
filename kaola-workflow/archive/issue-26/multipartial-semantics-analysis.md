# Issue #26 multi-partial semantics analysis

Date: 2026-08-04  
FeishuSpeech worktree inspected read-only: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-26`  
KaolaTerminal reference inspected read-only: `/Users/ylpromax5/Workspace/kaolaterminal`

## Verdict

The installed build-5 symptom “exactly one word appears, later responses do not advance the cursor”
has a direct source-level failure mechanism:

1. `FeishuStreamingSession` decodes one optional scalar `data.recognition_text` (falling back to
   `data.text`) from every successful request and emits that scalar unchanged as `.partial(text)` or
   `.final(text)` (`FeishuSpeech/Services/FeishuStreamingSession.swift:104-121,173-198,206-247,415-442`).
2. `MainViewModel` forwards each non-contentless scalar immediately, but does not assemble response
   values locally (`FeishuSpeech/ViewModels/MainViewModel.swift:883-953`).
3. `CurrentFocusAppendSession` posts the whole first scalar, then accepts a later scalar only if its
   UTF-16 units start with **all units already emitted**. A shorter, revised, or disjoint next scalar
   returns `.revisionSuppressed`; an exact repeat returns `.duplicate` (`FeishuSpeech/Services/CurrentFocusAppendSession.swift:141-183,185-207`).
4. `MainViewModel` treats `.revisionSuppressed` and `.duplicate` as nonterminal no-ops, with no
   visible or diagnostic outcome (`FeishuSpeech/ViewModels/MainViewModel.swift:1113-1135`).
5. Release finalization applies the same prefix rule. A final value that is not an exact extension of
   the first emitted scalar returns `.preservedDivergence` and posts nothing
   (`FeishuSpeech/Services/CurrentFocusAppendSession.swift:209-244`; tests at
   `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift:443-457`).

Therefore, for observed response values such as `R1 = "word1"`, `R2 = "word2"`, `R3 = "word3"`,
the exact production result is: post `word1`; suppress `word2`; suppress `word3`; preserve only
`word1` at release. The same stall occurs for revisions or shortenings. This explanation does not
require a transport failure, focus loss, Secure Input, or release race.

What is **not** established is the vendor semantic category of `R1`, `R2`, and `R3`. Neither the
current source/tests, KaolaTerminal, nor the retained public-contract research proves that Feishu
intermediate strings are cumulative whole hypotheses, disjoint segments, revisions, or per-packet
results. The safe conclusion is:

> Feishu returns one opaque scalar response value per successful request. Its relationship to prior
> values is unverified. KaolaTerminal performs no speech-text assembly; it replaces its preview with
> each opaque value. To satisfy FeishuSpeech's newly stated product contract that every usable
> response advances cursor output, FeishuSpeech must add an explicit **local response-ordered output
> assembly policy**. That is an application policy, not a discovered Feishu guarantee.

## 1. Exact FeishuSpeech response decoding and event production

### Facts

- The response model contains only `code` and optional `data`; `data` contains optional
  `recognition_text` and optional `text`. `transcription` chooses `recognition_text ?? text`
  (`FeishuSpeech/Services/FeishuStreamingSession.swift:104-121`).
- The model decodes no response action, final flag, stability flag, segment list, word timestamp, or
  response identity (`FeishuSpeech/Services/FeishuStreamingSession.swift:104-121`).
- Every nonempty audio request is action 1 for the first accepted packet and action 0 thereafter.
  After a successful response, the returned scalar is emitted unchanged as `.partial(text)`
  (`FeishuSpeech/Services/FeishuStreamingSession.swift:173-198`).
- `finish()` sends action 2 with empty audio and emits the returned scalar unchanged as `.final(text)`
  (`FeishuSpeech/Services/FeishuStreamingSession.swift:206-247`).
- Missing `data` or missing both text fields becomes the empty string rather than a typed absence
  (`FeishuSpeech/Services/FeishuStreamingSession.swift:441`).
- Typed events themselves carry only a `String`; there is no packet ordinal, request action,
  sequence ID, attempt ID, cumulative/delta marker, or response-shape metadata
  (`FeishuSpeech/Models/StreamingSpeechModels.swift:99-104`).
- Tests prove direct pass-through, not semantic assembly. Two packet fixtures `"opaque one"` and
  `"opaque revision"` become two corresponding partial events, then `"final authority"` becomes a
  final event (`FeishuSpeechTests/FeishuStreamingSessionTests.swift:119-150`). Tests also prove
  `recognition_text` precedence over `text` (`:643-675`) and missing data becoming `.partial("")`
  (`:71-83`).

### Consequence

The transport cannot currently tell an output owner whether two response values are extensions,
revisions, segments, or duplicates. Any such interpretation occurs downstream or is assumed by a
test fixture.

## 2. MainViewModel routing, retry, replay, and release

### Live packets

- The coordinator appends each audio packet to `packetJournal` **before** sending it. On success it
  marks `acceptedPacket`, then routes the returned event (`FeishuSpeech/ViewModels/MainViewModel.swift:553-570`).
- A non-contentless partial overwrites `latestFinalOnlyValue`, is suppressed after `sealStarted`, and
  otherwise goes to exactly one of two continuous owners: `CursorTextSession` or
  `CurrentFocusAppendSession` (`FeishuSpeech/ViewModels/MainViewModel.swift:921-941`).
- A nonterminal `.final` is also routed as a provisional value. A terminal final calls append-session
  finalization (`FeishuSpeech/ViewModels/MainViewModel.swift:944-1020`).
- `latestFinalOnlyValue` is only the latest opaque scalar, not a transcript assembly
  (`FeishuSpeech/ViewModels/MainViewModel.swift:82,926-928,950-953`).

### Target selection

- Startup first attempts a captured AX `CursorTextSession`. A `.live` capability owns the range; a
  `.finalOnly` capability may arm a PID- and element-validated append session; unavailable AX uses a
  current-focus fallback (`FeishuSpeech/ViewModels/MainViewModel.swift:345-414`).
- On the first partial, an unbound fallback retries AX once. A rebound live target uses
  `CursorTextSession`; rebound final-only can arm the captured append owner; otherwise it arms the
  PID-bound current-focus append owner (`FeishuSpeech/ViewModels/MainViewModel.swift:1023-1110`).

### Retry and replay

- Recoverable failure retains the same `packetJournal`, backs off, creates a new stream, and replays
  every retained packet (`FeishuSpeech/ViewModels/MainViewModel.swift:447-550,648-689`).
- Replay suppresses every intermediate replay event and retains only the latest usable replay event
  as `catchUpEvent`; that one value is then routed with source `.replayCatchUp`
  (`FeishuSpeech/ViewModels/MainViewModel.swift:574-606`).
- The output session ignores the `source` value entirely
  (`FeishuSpeech/Services/CurrentFocusAppendSession.swift:141-145`). Thus replay safety currently
  depends entirely on the same text-prefix test, not on packet/response identity.

### Release

- Fn release sets the monotonic `sealStarted` latch, closes retry admission, stops the timer and
  recorder, and moves UI status to sealing (`FeishuSpeech/ViewModels/MainViewModel.swift:1276-1319`).
- Once sealed, later partials can update `latestFinalOnlyValue` but cannot enter continuous output
  (`FeishuSpeech/ViewModels/MainViewModel.swift:926-929`).
- Normal action-2 final can still mutate output through `finalize`; recoverable release failure can
  finalize from the latest retained scalar (`FeishuSpeech/ViewModels/MainViewModel.swift:627-645,724-790,979-1020`).
- After any provisional post attempt or uncertainty, the existing design intentionally forbids a
  whole-value one-shot resend/copy fallback. This is enforced by append outcomes and recovery
  eligibility (`FeishuSpeech/ViewModels/MainViewModel.swift:803-830,1113-1151`).

## 3. CurrentFocusAppendSession prefix ownership and instrumentation

### Existing ownership and safety facts

One session binds an immutable generation and PID, optionally an exact captured-destination validator
(`FeishuSpeech/Services/CurrentFocusAppendSession.swift:104-139`). Before each post it:

1. rejects stale/closed, contentless, unsafe-control-character, duplicate, and non-prefix values
   (`:185-207`);
2. samples Secure Input, frontmost PID, and optional captured destination twice before posting
   (`:159-166,267-289`);
3. posts directly to the bound PID;
4. samples destination/security again after posting (`:166-181`).

Destination drift, Secure Input, or uncertain delivery permanently suspends the session
(`:267-310`). Once suspended, there is no retry/resend. Repeated finalize, invalidation, and late
values are no-ops (`:209-249`). These are the exact boundaries to preserve.

### Meaning of `emittedUTF16`

`emittedUTF16` is currently overloaded:

- it is good evidence of what payload units this session has already **attempted/accepted locally**
  for no-resend and final-suffix decisions;
- it also acts as an unproven recognition-semantic assertion that every future response must be a
  cumulative whole hypothesis beginning with all previous units.

The first purpose is required for safety. The second purpose causes the one-word stall. Separating
“ordered response ownership” from “bytes already offered to this target” is the central correction.

### Current observability gap

Successful responses and apply/final outcomes have no privacy-safe diagnostic record. The transport
only logs rejected backend/malformed responses with action, sequence, HTTP status, byte count,
business code, and typed outcome (`FeishuSpeech/Services/FeishuStreamingSession.swift:16-45,415-459`).
`CurrentFocusAppendSession` logs only permanent suspension reasons (`:299-310`). `MainViewModel`
does not log whether a response was routed as first/duplicate/prefix extension/revision suppression,
or whether it used AX, captured append, unbound append, replay, or final-only fallback.

Consequently, build-5 logs can prove successful request counts only if another network receipt exists;
they cannot by themselves prove how many nonempty response values reached the coordinator or which
prefix outcome suppressed them. Transcript contents must remain unlogged, but typed shape and route
metadata can be recorded safely.

## 4. Comparison with KaolaTerminal

### What KaolaTerminal actually proves

- It decodes the same scalar shape: `recognition_text ?? text`
  (`KaolaTerminal/Services/Speech/FeishuSpeechRecognizer.swift:40-58`).
- Each action-1/action-0 response is emitted unchanged as `.partial(text)`; action 2 is emitted
  unchanged as `.final(text)` (`KaolaTerminal/Services/Speech/FeishuSpeechRecognizer.swift:652-708,797-862`).
- The controller stores each nonempty response as `bestStreamingPreview = text`; it does not append or
  assemble response text (`KaolaTerminal/Services/Speech/SpeechClient.swift:1078-1091`).
- The view model replaces the whole preview with every partial. A final received while physical hold
  remains active also replaces the opaque preview; only release/sealing grants final draft authority
  (`KaolaTerminal/Features/Terminal/TerminalSessionViewModel.swift:1296-1333`).
- The acceptance test deliberately sends `"first opaque state"` then `"revised opaque state"` and
  requires full replacement with no terminal output
  (`KaolaTerminalTests/VoiceReviewViewModelTests.swift:13-35`).

### What KaolaTerminal explicitly does not prove

KaolaTerminal's locked decision says Feishu does not define whether intermediate text is delta,
cumulative replacement, stable segments, or revisable hypotheses; therefore it is handled as opaque
response state and never blindly appended (`docs/DECISIONS.md:141`). Its API documentation repeats
that live credential-bearing observation remains required and action-2 is the only local final
authority (`docs/api.md:14-25`). Its current plan still marks intermediate semantics as an explicit
live-UAT gap (`PLAN.md:117-119`).

Thus “KaolaTerminal's proven semantics” means **proven local output behavior**—opaque whole-preview
replacement and zero automatic terminal write—not a proven Feishu response relationship. It offers
no assembly algorithm that FeishuSpeech can copy.

## 5. Response-shape conclusion

| Candidate semantic | Proven by source/tests/docs? | Effect in build 5 |
|---|---|---|
| Cumulative whole hypothesis | No | Exact extensions work; revisions/shortenings stall after first post. |
| Disjoint segment text | No | First segment posts; every later segment normally fails the prefix gate. This exactly matches the one-word symptom. |
| Revisable hypothesis | No | First hypothesis posts; every non-prefix revision is suppressed, leaving stale first text. |
| Per-packet independent result | Only the transport/request association is proven; text relation is not | Same failure as disjoint segments unless later values happen to be cumulative extensions. |
| Local server-response assembly already exists | Refuted | Both projects pass one scalar through; KaolaTerminal replaces preview and FeishuSpeech assumes prefix compatibility. |

The provider semantic category remains **UNKNOWN**. The local implementation requirement for the
user's contract is nevertheless clear: cursor output needs its own ordered assembly/ownership model,
rather than using provider text-prefix similarity as response identity.

## 6. Smallest safe continuous-output ownership model

### Product contract translated into invariants

- While the matching Fn generation is unsealed, every newly accepted, non-contentless, automatic-
  output-safe response that has not already been owned by replay advances exactly one fixed output
  owner.
- Release closes response/output admission and seals what was already offered. It does not become a
  second full-value insertion path and does not repair earlier uncertainty by resending.
- Exact target, Secure Input, generation, lifecycle, and delivery-uncertainty checks remain stronger
  than “every response”: an unsafe or uncertain response is not eligible for further mutation.
- Recognition-response identity is packet/attempt/journal ownership, not string equality or prefix
  similarity.

### Minimal state boundary

Keep one coordinator-owned, generation-scoped **response output ledger** beside `packetJournal`:

- ordered journal packet index;
- whether that packet's usable response has already been offered to output;
- an assembled UTF-16 frontier made by concatenating each newly owned response scalar exactly once;
- the existing single selected output owner (AX owned range, captured append, or PID-bound append);
- closed/suspended/uncertain state remains in the selected sink.

For each successful live packet response:

1. classify only eligibility (matching generation, unsealed, non-contentless, safe text);
2. claim its journal packet index exactly once;
3. append the scalar's UTF-16 units to the coordinator frontier without inferring any relationship
   to earlier response text;
4. feed the assembled whole frontier to `CursorTextSession` (which can replace its verified owned
   range), or feed the same frontier to `CurrentFocusAppendSession` (whose existing `emittedUTF16`
   prefix logic now sees a prefix guaranteed by **local assembly**, so it posts only the new scalar);
5. record the typed outcome, never the text.

This is smaller and safer than teaching the unverified current-focus route to delete/backspace,
select arbitrary text, or resend complete values. It reuses both existing writers and leaves every
destination/security/postflight gate intact.

For retry replay, journal index is authoritative:

- suppress responses for packet indices already output-owned;
- the previously failed/unacknowledged frontier packet may claim one new response when replay first
  succeeds;
- historical replay response values never re-own an already claimed index, even if their strings
  differ;
- after catch-up, new live packets continue with new indices.

This replaces the current “keep only the last replay text and hope it extends emitted text” behavior
with exact packet ownership while retaining one serial session and no parallel/redundant output.

On release, close ledger admission before recorder/session draining. Action-2 text may remain useful
as recognition diagnostics or a non-output final result, but under the stated “release only seals”
contract it must not create a first output, append a new suffix, replace assembled output, trigger
Cmd+V, or copy for recovery. Finalize the selected output owner against the already assembled frontier
only. A product decision to append action-2 text would be a different contract and needs explicit
acceptance because it makes release mutate cursor content.

### Privacy-safe instrumentation needed for the next installed UAT

Record fixed enums/integers only:

- generation-local response ordinal, request action/sequence, attempt ordinal, and journal index;
- source: `live`, `replayHistoricalSuppressed`, `replayFrontierOwned`, `terminal`;
- response shape relative to prior raw response: `contentless`, `first`, `exactDuplicate`,
  `prefixExtension`, `shorter`, `divergent` (classification is diagnostic only);
- raw-response UTF-16 count and newly assembled UTF-16 count, with no payload;
- selected route: `axRange`, `capturedAppend`, `unboundPIDAppend`, `finalOnly`, `disabled`;
- apply result: existing typed `CurrentFocusAppendOutcome` / `CurrentFocusAppendFinalOutcome`, plus
  `ownedResponse`, `historicalReplaySuppressed`, and `sealedSuppressed` at coordinator level;
- poster call count and attempted UTF-16 count, never text, app name, element value, stream ID, audio,
  credentials, clipboard, or response body.

That receipt can distinguish “provider returned only one usable value”, “later values were
contentless”, “later values were non-prefix and suppressed”, “target/security suspended”, and
“poster accepted locally but target visibly ignored it” without exposing speech content.

## 7. Test blueprint

Test custody should remain separate from production implementation per repository rules.

### Transport/event tests — `FeishuSpeechTests/FeishuStreamingSessionTests.swift`

1. Two successful packet responses with independent values still produce two ordered partial events;
   transport performs no assembly.
2. Response action/sequence or a new internal envelope, if added, preserves exact journal identity
   without transcript logging.
3. `recognition_text`/`text`, empty data, final, and failure behavior remain unchanged.

### Output-ledger unit tests — new focused test file or a narrow extracted policy test

1. Disjoint values `one`, `two`, `three` build the local frontier `onetwothree`, with each packet index
   claimed once.
2. Exact repeated text from two distinct live packet indices advances twice; string equality is not
   identity.
3. One journal index replayed through multiple attempts advances at most once.
4. Historical acknowledged replay indices advance zero times; the previously unresolved frontier
   index advances once when accepted.
5. Contentless/unsafe/stale/sealed values do not advance.
6. Release atomically closes admission; action-2/late packet values do not mutate the frontier.

### Production current-focus tests — `FeishuSpeechTests/CurrentFocusAppendSessionTests.swift`

Retain all existing Secure Input, PID, captured-element, uncertainty, stale-generation, exact-once,
and no-resend cases (`:134-207,241-365,367-490`). Add an integration-facing case that locally
assembled frontiers `one`, `onetwo`, `onetwothree` post payloads `one`, `two`, `three`. Do not weaken
the sink's rule that an externally supplied divergent whole frontier is suppressed; the coordinator
must be what guarantees monotonic assembly.

### Coordinator tests — `FeishuSpeechTests/StreamingMainViewModelTests.swift`

1. Use the production append session, not only `CoordinatorCurrentFocusAppendSession`, with three
   disjoint response values. Assert three Unicode payloads before release and zero release-time
   payloads.
2. Live AX range receives the growing local frontier after each independent response, so visible
   cursor output advances rather than replacing the prior response with one word.
3. Initial captured final-only, rebound final-only, and AX-unavailable routes all select one owner and
   exhibit the same ordered response behavior.
4. Retry: first attempt outputs response for packet 0 then fails packet 1; replay suppresses packet 0,
   owns packet 1 once, and later live packet 2 advances once.
5. Release during backoff/replay/in-flight packet closes admission and posts no late/final text.
6. PID/focused-element drift, activation away, Secure Input, poster uncertainty, reset, sleep/wake,
   and stale generation continue to stop all later output with no resend/copy/fallback.
7. Assert privacy-safe diagnostic enums/ordinals and assert transcript markers are absent from their
   descriptions/log payloads.

The current tests do not catch build 5's failure because they split incompatible assumptions across
layers: the transport test explicitly permits opaque revisions
(`FeishuSpeechTests/FeishuStreamingSessionTests.swift:119-150`), the production append tests only
expect exact cumulative extensions (`FeishuSpeechTests/CurrentFocusAppendSessionTests.swift:37-101`),
and the coordinator continuous-output test uses monotonic strings plus a recording double that does
not enforce production prefix semantics (`FeishuSpeechTests/StreamingMainViewModelTests.swift:1125-1155,2416-2472`).

### Suggested validation commands

```text
xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/FeishuStreamingSessionTests test

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/CurrentFocusAppendSessionTests test

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' \
  -only-testing:FeishuSpeechTests/StreamingMainViewModelTests test

xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test
swiftlint
xcodebuild -scheme FeishuSpeech -configuration Debug build
```

Installed Release UAT remains required to establish visible target acceptance and to observe the
provider's response-shape distribution. It must use the typed/redacted receipt above; no transcript,
raw response body, credentials, audio, clipboard, focused-element contents, or target-application
contents need to be retained.

## 8. Facts, inference, and remaining unknowns

### Confirmed facts

- One scalar is decoded and emitted per successful Feishu request; neither project assembles it.
- KaolaTerminal replaces opaque preview state and explicitly disclaims knowledge of intermediate
  response semantics.
- FeishuSpeech's unbound/captured append route posts once, then only exact UTF-16 extensions.
- Non-prefix later values are silently suppressed; divergent final preserves the first post.
- Existing exact-target, Secure Input, generation, lifecycle, and uncertainty/no-resend boundaries
  are explicit and covered by tests.

### Strong inference

- If build 5 received multiple usable non-prefix response values, current source necessarily explains
  the exact one-word output. A typed build-5 response/apply receipt can confirm that antecedent without
  revealing text.

### Unknowns that block a vendor-semantic claim, but not the local repair plan

- Whether real Feishu intermediate values are cumulative, disjoint, per-packet, stable, revisable, or
  tenant/engine dependent.
- Whether identical values on distinct packets mean repetition or unchanged recognition state.
- Whether action-2 text is complete, a delta, a revision, or sometimes empty.
- Whether build 5's target accepted the first CGEvent and rejected later events, versus later events
  never being posted. `CGEventPostToPid` supplies no target acknowledgement; typed route/outcome logs
  plus owner-visible UAT are needed.

These unknowns are why the proposed behavior must be documented as a **user-selected local ordered
response assembly policy**, not as a factual decoding of Feishu transcript semantics.
