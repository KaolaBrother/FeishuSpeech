# Issue #33 skip VPN/TUN — implementer GREEN receipt

Date: 2026-08-21

## Task

Streaming Feishu transport skips VPN/TUN: Network.framework keep-alive is primary (`prohibitedInterfaceTypes` includes `.other`); URLSession is connect-class fallback only. Owner reversed Q2-B on 2026-08-21.

Oracle: `kaola-workflow/issue-33/test-red.md` (not edited). Production only; no test-file, docs, or CHANGELOG edits.

## Verification tier

`tests-green`

## Files changed

Worktree: `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-33`

- `FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift`
- `FeishuSpeech/Services/TransportAttemptContext.swift`

Not touched: `FeishuSpeechTests/`, `file_recognize` / `recognizeSpeech` / `executeURLRequest` / `URLSession.shared`, `DirectFeishuHTTPClient`, `StreamingDrainPolicy` slice budgets, overlay/hotkey/credentials, docs/CHANGELOG.

`git diff --stat -- FeishuSpeech/`:

```
 FeishuSpeech/Services/DirectFeishuKeepAliveSession.swift |  8 ++-
 FeishuSpeech/Services/TransportAttemptContext.swift      | 62 ++++++++++++++++------
 2 files changed, 52 insertions(+), 18 deletions(-)
```

No `en0`, no `sec_protocol_options_set_verify_block`, no CDN IPs.

## Behavior

### Keep-alive parameters

`DirectFeishuKeepAliveSession.makeParameters()` still sets SNI `open.feishu.cn` and `preferNoProxies = true`. Added `parameters.prohibitedInterfaceTypes = [.other]` (Apple VPN/TUN/virtual bucket). No named BSD bind.

### Injectable seam

`nonisolated protocol DirectKeepAliveTransport: AnyObject, Sendable` with `send(_:deadlineNanoseconds:)` and `forceCancel()`. `DirectFeishuKeepAliveSession` conforms.

`TransportAttemptContext.init(policy:session:keepAlive:)` stores `keepAlive: (any DirectKeepAliveTransport)? = nil`. Nil constructs `DirectFeishuKeepAliveSession` on first `sendDirect`.

### `send` order

1. Invalidated → `CancellationError`.
2. `stickyDirect` → keep-alive only.
3. `stickyURLSession` **or** `phase == .abort` → URLSession slice only (abort remains best-effort URLSession unless already sticky-direct).
4. Else primary keep-alive using `directSliceNanoseconds`.
   - Completed HTTP (including 4xx) → `stickyDirect = true`, log `transport=direct`, no hop.
   - `CancellationError` / `Task.isCancelled` → rethrow, no hop.
   - Other connect-class errors → hop **once** to URLSession using `urlSessionSliceNanoseconds`. Success → `stickyURLSession = true`, log `transport=urlsession`. Failure → `invalidate()` the whole context.

### Invalidate on direct miss

A first-send keep-alive miss no longer kills the URLSession:

- Always `forceCancel` the keep-alive, nil it, clear `stickyDirect`.
- Already `stickyDirect` (mid-attempt drop on the live socket) → `invalidate()` the whole context.
- First primary send (not yet sticky) → do **not** invalidate; rethrow so URLSession can run.

URLSession slice miss still `invalidate()`s the context (session + keep-alive). A new `TransportAttemptContext` starts on keep-alive again.

## Commands

### Before (RED compile-fail, unchanged from oracle)

```
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue-33-impl-before -only-testing:FeishuSpeechTests/DirectFeishuKeepAliveSessionTests -only-testing:FeishuSpeechTests/TransportAttemptContextTests test
```

- Exit: **65**
- Result: `/tmp/feishuspeech-issue-33-impl-before/Logs/Test/Test-FeishuSpeech-2026.08.21_15-06-26-+0800.xcresult`
- Diagnostics: `cannot find type 'DirectKeepAliveTransport' in scope`; `extra argument 'keepAlive' in call`

### After — focused classes

```
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue-33-impl-after -only-testing:FeishuSpeechTests/DirectFeishuKeepAliveSessionTests -only-testing:FeishuSpeechTests/TransportAttemptContextTests test
```

- Exit: **0**
- `** TEST SUCCEEDED **`
- Result: `/tmp/feishuspeech-issue-33-impl-after/Logs/Test/Test-FeishuSpeech-2026.08.21_15-08-04-+0800.xcresult`
- Passed: all 3 `DirectFeishuKeepAliveSessionTests` + all 10 `TransportAttemptContextTests` (including hop, 4xx no-hop, cancellation no-hop, sticky-direct, sticky-URLSession, new-context restart, hung URLSession 40 ms slice)

### After — full suite

```
xcodebuild -project FeishuSpeech.xcodeproj -scheme FeishuSpeech -destination 'platform=macOS' -derivedDataPath /tmp/feishuspeech-issue-33-impl-full test
```

- Exit: **0**
- `** TEST SUCCEEDED **`
- Result: `/tmp/feishuspeech-issue-33-impl-full/Logs/Test/Test-FeishuSpeech-2026.08.21_15-08-30-+0800.xcresult`
- xcresult: **352 passed, 0 failed, 0 skipped**

### Lint

```
swiftlint
```

- Exit: **0**
- `Done linting! Found 0 violations, 0 serious in 30 files.`

## Outcome

GREEN. Keep-alive is primary, `.other` is prohibited, first-send keep-alive miss hops once to URLSession without invalidating the session, completed HTTP does not hop, and both sticky modes hold for the rest of one `TransportAttemptContext`.
