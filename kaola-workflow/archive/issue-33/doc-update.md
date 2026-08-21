# Issue #33 documentation docking receipt

## Verdict

DOCKED. Worktree documentation matches the verified keep-alive-primary / skip-VPN-TUN contract.
No claim is made that this beats corp `includeAllNetworks` or Clash fake-ip DNS.

## Evidence reconciled

- Issue: https://github.com/KaolaBrother/FeishuSpeech/issues/33
- Owner 2026-08-21 reversed Q2-B: skip VPN/TUN; do **not** bind `en0`.
- Production: `DirectFeishuKeepAliveSession.makeParameters()` — SNI `open.feishu.cn`,
  `preferNoProxies = true`, `prohibitedInterfaceTypes = [.other]`, no verify block, no `en0`.
- Production: `TransportAttemptContext.send` — keep-alive primary; URLSession hop once on
  connect-class miss; completed HTTP (incl. 4xx) does not hop; `CancellationError` does not hop;
  sticky-direct after keep-alive success; sticky-URLSession after URLSession fallback success;
  new context starts on keep-alive; abort is URLSession unless already sticky-direct; first-send
  keep-alive miss does **not** invalidate URLSession; mid-attempt sticky-direct drop still
  invalidates.
- `file_recognize` / `recognizeSpeech` unchanged (`executeURLRequest`).
- Slice budgets unchanged (factory 8+7+1 < 18, packet 14+14+1 < 30, finish 15+15+1 < 45).
  Primary uses **direct** slices; fallback uses **urlSession** slices.
- Tests: 352/352. swiftlint 0. Release build succeeded on the worktree.
- Reviews: code approve; security pass. Residual: corp `includeAllNetworks` and Clash fake-ip
  DNS are out of scope / fallback.

## Updated documentation surfaces (worktree)

Paths are under `/Users/ylpromax5/Workspace/feishuspeech/.kw/worktrees/issue-33`.

- `docs/decisions/D-32-01.md` **(new)** — accepts the Q2-B reversal: keep-alive primary +
  prohibit `.other`; URLSession connect-class fallback; no `en0`; no CDN IPs; no toggle; next
  attempt starts on keep-alive again (supersedes D-28-01 “next factory starts on URLSession”).
- `docs/decisions/D-28-01.md` — header pointer that **streaming transport order** is superseded
  by D-32-01 / issue #33. Capture/recognition split, cancel mapping, leftover framing, and slice
  budgets left as the D-28-01 record (no silent rewrite of the URLSession-first Decision body).
- `docs/api.md` — replaced the URLSession-first + hop-to-direct paragraph with keep-alive
  primary, prohibit `.other`, URLSession fallback on no HTTP, sticky modes, leftover framing,
  and `file_recognize` still on `executeURLRequest`. See-also now includes D-28-01 and D-32-01.
- `docs/architecture.md` — same transport-paragraph replacement.
- `docs/README.md` — listed D-32-01; noted D-28-01 transport order superseded; design-index
  pointer that #28–#31 transport order was later superseded by D-32-01.
- `CHANGELOG.md` — `[Unreleased]` Fixed entry for issue #33 (quoted below).
- `README.md` — feature bullet plus FAQ: streaming prefers direct physical-path Feishu and
  skips VPN/TUN; does not promise `includeAllNetworks` or Clash fake-ip.

User-visible CHANGELOG line:

> 修复 VPN 开启时流式识别不稳定：keep-alive 直连改为 primary 并禁止 TUN（`.other`），不绑定 `en0`；同一 watched factory/packet/finish 操作仅在无 HTTP 响应时 hop 一次到 URLSession。已完成 HTTP（含 4xx）与 CancellationError 不 hop；keep-alive 成功后粘性直连，URLSession 回退成功后粘性 URLSession；下一 attempt 重新从 keep-alive 开始（issue #33）

## Skipped (no real change, or instructed historical)

- `scripts/codemaps/` and `docs/CODEMAPS/` — neither exists; no codemap tooling to regenerate.
- `docs/designs/capture-recognition-split-direct-connect.md` — historical confirmed design for
  #28–#31; not rewritten. Index pointer in `docs/README.md` is the supersession notice.
- `docs/streaming-speech-design.md` — issue #27 snapshot/output design; no transport-order
  paragraph to reconcile.
- `docs/conventions.md` — coding/review conventions unchanged.
- `CLAUDE.md` / `AGENTS.md` — project rules and redirect unchanged.
- `.env.example` — not present.
- Production Swift and tests — out of doc-updater custody; not edited.

## Commands

- Read worktree docs, `DirectFeishuKeepAliveSession.makeParameters()`,
  `TransportAttemptContext.send`, `StreamingDrainPolicy` defaults, and
  `kaola-workflow/issue-33/{code-review,security-review,mission-list}.md`.
- Relative Markdown link check on the seven updated files: 20 links, all targets exist.
- `git diff --check -- docs README.md CHANGELOG.md`: clean.
- `git status --short -- docs README.md CHANGELOG.md`: seven documentation paths only
  (`D-32-01.md` untracked; six modified).

This receipt: `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-33/doc-update.md`
