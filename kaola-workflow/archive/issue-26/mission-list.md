# Diagnose the real-credential streaming failure and deliver a verified installed Release

goal: Diagnose the real-credential streaming failure and deliver a verified installed Release

- item: Trace the current installed-Release failure to the exact token, session-start, packet, response, or terminal boundary without launching the app or reading credentials.
  status: done
  dispatched: investigator performs read-only inspection of current unified logs and process state, with evidence at `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-26/live-failure-investigation.md`; code-explorer independently maps every production path that becomes generic `流式识别失败` and returns its code map to the main session. Neither may launch the app, access credential values, make credential-bearing requests, or trigger macOS permissions.
  result: Five real-credential attempts reached cached-token success, recording startup, and the first action=1/sequence=0 request; every request returned HTTP 200 and failed 1–6 ms later before Fn release. The remaining boundary is exactly backend business code, response decoding/data absence, or stream/sequence identity mismatch. Current production discards that safe classification and logs none of it; full evidence is in live-failure-investigation.md.

- item: Add baseline-RED regression coverage for the proven live failure with test custody separate from production implementation.
  status: done
  dispatched: tdd-guide owns only FeishuStreamingSession test changes and defines a safe structured diagnostic contract for HTTP-200 backend, malformed-response/data-absence, and identity-mismatch branches; tests must prove the diagnostic contains action, sequence, HTTP status, response byte count, numeric business code and match booleans but never raw body, msg, token, stream ID, audio, or transcript. It records lifecycle-free baseline RED evidence and does not edit production.
  result: Five RED-first tests in FeishuStreamingSessionTests cover backend business code, malformed JSON, missing data, stream-ID mismatch, and sequence-ID mismatch for the first action=1/sequence=0 response. Baseline build-for-testing fails because the safe diagnostic type and sink do not yet exist; evidence is `/tmp/issue26-safe-diagnostic-red.qYYCKH/baseline-red.log`.

- item: Add privacy-safe response-boundary instrumentation that distinguishes the five remaining first-packet failure branches.
  status: done
  dispatched: implementer owns FeishuStreamingSession production changes only, must satisfy the TDD-owned diagnostic contract with a source-compatible optional sink and default Logger output, and may never log raw body/msg/token/stream ID/audio/transcript or edit tests; it must run the focused lifecycle-free tests without launching the app or requesting permissions.
  result: FeishuStreamingSession now emits exactly one structured diagnostic for backend business code, malformed JSON, missing data, stream-ID mismatch, or sequence-ID mismatch. The object and default public Logger line contain only nine allow-listed safe fields. Focused lifecycle-free tests pass 20/20, strict SwiftLint is clean, and build-for-testing succeeds.

- item: Capture the exact classified failure from one instrumented owner interaction and repair the proven protocol or service-outcome handling defect.
  status: done
  dispatched: code-reviewer and security-reviewer independently audit the two-file diagnostic diff; the main session runs the full lifecycle-free suite, builds a Release diagnostic candidate, stops the currently running old process only for replacement, installs the sole verified copy without launching it, and then reads one owner-triggered Fn attempt from safe unified logs. Review receipts land in `code-review-diagnostic.md` and `security-review-diagnostic.md` under the active run folder.
  result: Privacy/correctness reviews PASS, the full suite passes 189/189, and diagnostic Release 1.0 build 2 is the sole installed copy and remains stopped. The requested kaolaterminal comparison superseded another owner interaction and provided direct source proof of the over-strict client response contract.

- item: Review correctness/security, dock the behavior, and validate lifecycle-free tests, strict lint, Debug, and Release builds.
  status: done
  dispatched: code-reviewer and security-reviewer audit the kaolaterminal response-contract port and its interaction with safe diagnostics; doc-updater owns only the affected README/changelog/API/architecture/design/decision docking. The main session runs the full lifecycle-free suite, strict lint, Debug and Release validation. Receipts land under the active issue-26 run folder.
  result: Correctness and security reviews both PASS with zero blocking findings after obsolete unreachable diagnostic fields were removed. README, changelog, API, architecture, streaming design, and D-25-01 are docked. The final candidate passes 190/190 lifecycle-free tests, strict SwiftLint reports zero violations across 26 files, Debug build-for-testing succeeds, and Release 1.0 build 3 builds and passes strict code-sign verification.

- item: Finalize and sink the repair while keeping issue #26 open for owner UAT, then replace Applications with the sole verified Release without launching it.
  status: done
  result: The implementation is committed at 50cc9f6, issue #26 is configured to remain open for owner UAT, and the verified Release 1.0 build 3 is the sole Applications copy at /Applications/FeishuSpeech.app. Candidate and installed bytes match, the executable SHA-256 is 10df444a7ef63ed033cf20bb63db384d6cb45699ea63cd27729b4c3a1698f1ab, the app remains stopped, and no permission request was triggered.

- item: Verify the action=1 request and response models against the current official Feishu markdown contract and identify any proven wire mismatch.
  status: done
  dispatched: knowledge-lookup compares only the official Feishu stream_recognize markdown specification with the current request/response model and returns a source-linked contract report to the main session; it must not use credentials or make API requests.
  result: Official Feishu markdown confirms the first action=1/sequence=0 request and response model match the contract, including 16-character stream ID, nested speech/config, PCM Base64, and 16k_auto. A later cancel sequence reuse gap exists but cannot explain the immediate first-packet failure. Valid credentials remain independent from speech scope, publication, tenant edition (free edition unsupported), and service admission.

- item: Compare the proven kaolaterminal Feishu Stream implementation against FeishuSpeech and identify the smallest behaviorally relevant difference at the first-packet boundary.
  status: done
  dispatched: code-explorer reads both repositories' canonical instructions, then performs a read-only field-by-field comparison of token/session/request/audio/response/error behavior and returns exact file/line evidence to the main session; it must not read credentials, run either app, make API calls, edit files, or trigger permissions.
  result: Request, token, PCM, packet size, stream ID generation, action, and sequence behavior match. The decisive response difference is that kaolaterminal ignores response identity echoes, tolerates missing data, and reads recognition_text or text; FeishuSpeech typed and synchronously rejected identity mismatch/type variance and missing data immediately after HTTP 200.

- item: Port kaolaterminal's proven tolerant stream-response contract while preserving nonzero-code rejection and first-token refresh.
  status: done
  dispatched: tdd-guide owns FeishuStreamingSessionTests and replaces the over-strict identity/missing-data expectations with RED coverage for mismatched or wrong-typed echo tolerance, missing-data empty partial, and recognition_text/text fallback; after RED evidence, implementer will own the production response-model port and may not edit tests.
  result: FeishuStreamingSession now ignores response identity echo fields and their types, treats code-zero missing data as an empty partial, and reads recognition_text with text fallback exactly like kaolaterminal. Focused lifecycle-free tests pass 21/21 after four behavior-specific RED failures on the prior implementation.
