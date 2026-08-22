# Return 确认审阅草稿，Shift+Return 保留多行编辑，并保持 Issue #38 的安全与异步边界

- item: 核对当前 SwiftUI/AppKit 按键路由并建立 Return、Shift+Return、Command+Return、Escape 与只读阶段的失败测试
  status: done
  dispatched: code-explorer returns a read-only key-routing analysis in its agent result; tdd-guide owns only Issue #39 test artifacts in the linked worktree and records deterministic RED evidence at kaola-workflow/issue-39/test-red.md
  result: AppKit evidence is recorded at kaola-workflow/issue-39/.cache/key-routing-analysis.md; real NSHostingView/NSTextView tests execute 30 focused cases with one attributable RED, bare Return does not confirm, while Shift+Return, Command+Return, Escape, exact-once, and read-only authority remain green

- item: 实现编辑器键盘契约且不改变原目标交付、剪贴板生命周期或三条异步轴
  status: done
  dispatched: implementer owns the minimum production key-event seam in TranscriptionReviewView/adjacent review UI only, may read and run but must not modify tests; production result lands in the linked worktree and implementation evidence in its agent result
  result: TranscriptionReviewView now uses a native NSTextView representable with event-level Return/keypad routing, Shift newline pass-through, Command compatibility, unsupported-modifier and marked-text pass-through; no controller, MainViewModel, delivery, clipboard, recorder, or recognition production changed

- item: 运行聚焦与完整验证并完成独立正确性审查，修复所有阻塞发现
  status: done
  dispatched: root owns focused/full XCTest, Debug/Release, strict lint, and static boundary gates; code-reviewer and security-reviewer independently inspect the final candidate and write bound evidence under kaola-workflow/issue-39/.cache/
  result: 40/40 final focused tests and 423 executed with 1 skipped and 0 failures in the full serial suite; Debug/Release, strict lint, diff/static boundaries pass; the initial medium coverage finding was repaired by tdd-guide and both final correctness and security/privacy reviews pass with zero blocking findings

- item: 对接用户文档和 ADR 后执行工作流归档、合并、关闭 Issue #39 与 sink
  status: done
  dispatched: doc-updater owns documentation-only docking for the Return/Shift+Return contract and conditional supersession of Issue #38 prose; root then runs kaola-workflow-finalize, merge sink, closure audit, and remote verification
  result: README, CHANGELOG, architecture, streaming design, docs index, D-38-01, and new D-39-01 now document Return/Enter confirmation, Shift newline, Command compatibility, IME pass-through, and unchanged Issue #38 safety/async boundaries; Markdown links and diff checks pass, ready for finalization and sink
