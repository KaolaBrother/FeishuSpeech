# Skip VPN/TUN on streaming Feishu transport (issue #33)

- item: Pin failing tests for prohibited `.other`, keep-alive-primary send, URLSession connect-class fallback, completed-HTTP no hop, sticky-direct and sticky-URLSession, no `en0`/CDN; prove red on the current worktree baseline
  status: done
  dispatched: tdd-guide on worktree `.kw/worktrees/issue-33`; write tests under `FeishuSpeechTests/` and red evidence at `kaola-workflow/issue-33/test-red.md`
  result: RED compile-fail on baseline `89b9395`; tests in worktree `FeishuSpeechTests/{DirectFeishuKeepAliveSession,TransportAttemptContext}Tests.swift`; evidence `kaola-workflow/issue-33/test-red.md`

- item: Implement keep-alive as primary with `prohibitedInterfaceTypes` including `.other`, URLSession connect-class fallback, both sticky modes; make the new tests pass without editing test files
  status: done
  dispatched: implementer on worktree `.kw/worktrees/issue-33`; production only under `FeishuSpeech/`; green evidence at `kaola-workflow/issue-33/implement-green.md`
  result: keep-alive primary + `prohibitedInterfaceTypes = [.other]`; first-send miss hops without killing URLSession; focused 13/13 and full 352/352; `implement-green.md`

- item: Run the macOS test suite, Debug build, and swiftlint on the worktree; route failures to the owning role
  status: done
  dispatched: self — confirm worktree diff, Release build, and implementer's xcresult; extra evidence at `kaola-workflow/issue-33/validation.md`
  result: full 352/352, swiftlint 0, worktree Release BUILD SUCCEEDED; `validation.md`

- item: Code and security review of the VPN-skip transport invert
  status: done
  dispatched: code-reviewer → `kaola-workflow/issue-33/code-review.md`; security-reviewer → `kaola-workflow/issue-33/security-review.md`
  result: code-review approve; security-review pass (no P0–P3); Q2-B policy residual only

- item: Dock D-32-01 (Q2-B reversal), api.md, architecture.md, CHANGELOG, and a D-28-01 pointer from verified behavior
  status: done
  dispatched: doc-updater on worktree `.kw/worktrees/issue-33`; evidence `kaola-workflow/issue-33/doc-update.md`
  result: DOCKED — D-32-01, D-28-01 pointer, api.md, architecture.md, docs/README.md, CHANGELOG, README; `doc-update.md`
