evidence-binding: n1-explore-api-contract 75add68733b1
files_inspected

- CLAUDE.md and AGENTS.md: mandatory repo rules read; this node is read-only.
- FeishuSpeech/Services/FeishuAPIService.swift: affected API, retry, direct HTTP, token, and cancellation behavior.
- FeishuSpeech/Models/SpeechResult.swift: AuthResponse currently decodes code, msg, tenant_access_token only.
- FeishuSpeechTests/MockURLProtocol.swift and FeishuSpeechTests/*.swift: current test utilities and coverage.
- FeishuSpeech.xcodeproj/project.pbxproj: target/build settings and test target state.
- kaola-workflow roadmap and bundle plan files.

current_behavior

- DirectFeishuHTTPClient.send appends received bytes but only parses response when NWConnection.receive reports isComplete; the timeout path discards fully received responseData.
- The request sends Connection: close, so success currently depends on the peer closing rather than HTTP body completeness.
- parseResponse can parse status, headers, and chunked bodies, but it is not consulted after Content-Length bytes or terminal chunked bytes arrive.
- AuthResponse has no expire field and getAccessToken hardcodes tokenExpiry to Date()+6000.
- withRetry handles APIError separately but generic CancellationError can enter retry logging/sleep behavior.
- DirectFeishuHTTPClient cancellation resumes with CancellationError, but sendDirectRequest catches generic errors per IP and continues through later IPs and URLSession fallback.

test_targets

- Add focused FeishuSpeechTests/FeishuAPIServiceTests.swift.
- Existing MockURLProtocol is not currently useful for direct NWConnection paths or URLSession.shared fallback injection.
- xcodebuild -list currently reports only app target/scheme; test target wiring in FeishuSpeech.xcodeproj/project.pbxproj is likely required for xcodebuild test to execute focused tests.

implementation_constraints

- DirectHTTPResponse, DirectFeishuHTTPClient, parseResponse, decodeChunkedBody, withRetry, getAccessToken, and sendDirectRequest are private implementation surfaces; tests may need narrow test-only hooks or access adjustments.
- FeishuAPIService is an actor singleton with resetState; tests need deterministic seams rather than live network.
- Preserve single-resume guard in finish when adding body-complete parsing.
- Use fallback expiry behavior for missing/invalid expire; issue suggests expire - 300 with fallback to current constant when absent.

risks

- Adding tests without project target wiring may produce a false sense of coverage.
- Cancellation tests must avoid real NWConnection/direct IP flakiness.
- HTTP partial-buffer completion must avoid double-resume and preserve chunked decoding behavior.
