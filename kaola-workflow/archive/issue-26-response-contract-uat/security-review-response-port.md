# Security Review Receipt: issue-26 response-contract port

Status: PASS

Scope:

- Candidate production file: `.kw/worktrees/issue-26/FeishuSpeech/Services/FeishuStreamingSession.swift`
- Candidate test file: `.kw/worktrees/issue-26/FeishuSpeechTests/FeishuStreamingSessionTests.swift`
- Context traced through `MainViewModel.swift`, `CursorTextSession.swift`, and `TextInputSimulator.swift`.
- Reference contract checked against `/Users/ylpromax5/Workspace/kaolaterminal/KaolaTerminal/Services/Speech/FeishuSpeechRecognizer.swift`.

Security result:

- Untrusted `stream_id` and `sequence_id` response echoes are no longer decoded. Missing, mismatched, object-shaped, or string-shaped echoes therefore cannot influence request identity, sequencing, terminal state, or output routing.
- A code-zero response with missing `data` or missing transcript becomes `.partial("")` or `.final("")`. Existing handlers discard empty partials, treat empty finals as contentless, preserve any already-owned provisional text, and do not paste or copy an empty value.
- Accepted transcript values still pass through the existing active-generation check, auto-insert setting, cursor-destination ownership checks, current security-state checks, final-only destination validation, current-focus Secure Input checks, and one-shot output controls. The response-contract change introduces no direct output path.
- Malformed JSON, a missing/non-integer required `code`, or a malformed decoded transcript field fails closed as `StreamFailure.malformedResponse`. Any nonzero business code fails closed as authentication or backend failure before response text is returned.
- Diagnostic construction and logging expose only locally generated action/sequence counters, HTTP status, byte count, business code, optional booleans, and an outcome enum. They do not retain or log the raw response body, backend `msg`, bearer token, stream identifier or response identity echoes, audio bytes/base64, or transcript text. Candidate changes remove identity-mismatch diagnostics and add no new log surface.
- The tests explicitly exercise nonzero-code rejection, malformed JSON rejection, missing-data empty output, mismatched identity echoes, unexpected identity echo types, `data.text` fallback, primary-field precedence, and secret-free structured diagnostics.

Validation note:

- Static review completed over the exact candidate diff and the full downstream output/logging path.
- A targeted `xcodebuild -only-testing:FeishuSpeechTests/FeishuStreamingSessionTests test` build completed but the test runner did not return during the review window. No runtime pass is claimed here, and no live API, credential, permission, microphone, or product interaction was used.

verdict: pass
findings_blocking: 0
review_conclusion: The response-contract port preserves fail-closed error handling, existing output authorization controls, and secret-free diagnostic logging without introducing a candidate-caused security defect.
