# Design cursor-bound streaming Feishu transcription for the macOS Fn workflow

- item: Verify the newest KaolaTerminal streaming implementation and the official Feishu transport contract.
  status: done
  dispatched: self; evidence remains in KaolaTerminal commits 96b9422 and 397ad67 plus the official stream_recognize documentation.
  result: D-148/D-149 establish strict serial action/sequence requests, 6,400-byte PCM packets, byte-bounded ingress, opaque-replacement partials, and fail-current-stream behavior.

- item: Derive the macOS cursor-writing safety contract from the current FeishuSpeech state, audio, API, and pasteboard paths.
  status: done
  dispatched: self; outcome will land in docs/decisions/D-25-01.md and docs/streaming-speech-design.md in the issue worktree.
  result: docs/decisions/D-25-01.md and docs/streaming-speech-design.md define captured AX destination ownership, opaque full-range replacement, safe invalidation, final-only fallback, and failure preservation.

- item: Dock the design into architecture and API documentation without changing production or test code.
  status: done
  dispatched: self; documentation changes land in docs/README.md, docs/architecture.md, and docs/api.md in the issue worktree.
  result: architecture and API surfaces now distinguish the accepted future contract from the unchanged whole-file Swift implementation.

- item: Validate completeness, source-only scope, documentation consistency, and issue acceptance criteria.
  status: done
  dispatched: self; validation receipts will be recorded in the issue worktree diff and final issue update.
  result: staged diff is exactly five docs files with 760 insertions; git diff --cached --check and scope/retired-placeholder checks passed; no Swift or test source changed. swiftlint was unavailable on PATH and no Swift lint surface changed.
