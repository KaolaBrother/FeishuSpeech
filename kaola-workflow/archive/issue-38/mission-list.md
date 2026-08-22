# 输入前审阅、编辑并显式确认识别文本后再安全写入原目标

- item: 对照 KaolaTerminal 当前 review-first 状态与 FeishuSpeech 输出链路，形成设计并创建 issue #38
  status: done
  dispatched: code-explorer read-only agents; evidence returned in conversation and /tmp/kaolaterminal-voice-review-exploration.md
  result: GitHub issue #38 records the interaction, destination-authority, privacy, compatibility, and acceptance contracts

- item: 为 macOS review-first 状态、窗口、原目标恢复与 fail-closed 交付形成依赖安全的实现蓝图
  status: done
  dispatched: code-architect revises kaola-workflow/issue-38/architecture-blueprint.md for the owner-required live streaming/sealing preview while preserving the independent capture and recognition axes
  result: architecture-blueprint.md now defines the live read-only streaming/sealing review axis, same-panel editable transition, and zero-wait boundary against capture/journal and recognition/retry/replay

- item: 先建立 review-first 行为、安全边界与设置迁移的失败测试
  status: done
  dispatched: tdd-guide owns issue-38 changes under .kw/worktrees/issue-38/FeishuSpeechTests only; RED evidence goes to kaola-workflow/issue-38/test-red.md
  result: four issue-38 test surfaces are RED on ec3e4bd; evidence is recorded in test-red.md and includes the owner-confirmed live preview plus two-line async invariant

- item: 实现 review 状态、可编辑窗口、显式确认/取消、原目标恢复交付与兼容模式
  status: done
  dispatched: model/settings, destination delivery, live review surface, and MainViewModel convergence landed in .kw/worktrees/issue-38; build-error-resolver removed the pre-XCTest Keychain host hang in FeishuSpeechApp.swift; tdd-guide repaired the generation-echo fixture and proved 11/11 delivery tests; implement_review_coordinator is hardening the same-panel editable activation/focus as a bounded review-only async transition
  result: same-panel live streaming/sealing preview, bounded editable readiness, explicit confirm/discard, fail-closed captured-destination delivery, default-on setting migration, compatibility sampling, and a nonblocking XCTest host are implemented; four focused suites pass 52/52

- item: 运行聚焦与完整验证并完成独立正确性和安全隐私审查，修复所有阻塞发现
  status: done
  dispatched: root ran focused and full serial XCTest plus Debug/Release/lint/static gates; tdd-guide pinned 103 legacy streaming tests to explicit compatibility mode and added RED coverage for exact LF drafts plus conditional clipboard restoration; implement_review_coordinator repaired both medium findings; code-reviewer and security-reviewer independently re-reviewed the final delta
  result: focused 59/59 and full 408 executed with 1 skipped and 0 failures; Debug and Release builds, strict SwiftLint, diff checks, and untouched legacy-overlay boundaries pass; correctness and security/privacy rereviews both pass with zero blocking findings

- item: 对接 README、CHANGELOG、架构、流式设计与 superseding ADR，然后完成工作流归档和 sink
  status: done
  dispatched: doc-updater docked the verified final behavior into README, CHANGELOG, architecture, streaming design, documentation index, and decision records; root proceeds with kaola-workflow-finalize for closure, archive, and sink
  result: D-38-01 records default-on review-first and three-axis independence; D-25-01 and D-27-01 are superseded only conditionally while review-first is enabled; documentation links and diff checks pass, with real WindowServer, microphone, credential, Accessibility, and targeted paste UAT retained as explicit residual validation
