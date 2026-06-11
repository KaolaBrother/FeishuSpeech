# Claude Project Instructions

## Project Snapshot

- Purpose: macOS menu bar app that records voice (Fn key held), sends audio to Feishu speech-to-text API, and types recognized text at the cursor position.
- Stack: Swift 5.9+, SwiftUI, macOS 13.0+, AVCaptureSession, CGEventTap, AVAudioConverter, NWPathMonitor
- Architecture:
  - `HotKeyService` — CGEventTap state machine: idle → pending (0.3s) → recording → transcribing → idle
  - `AudioRecorder` — AVCaptureSession → AVAudioConverter → 16 kHz 16-bit PCM mono, 2 MB buffer
  - `FeishuAPIService` (actor) — token cache, retry with exponential backoff, NWPathMonitor
  - `TextInputSimulator` — CGEvent keyboard simulation (Cmd+V) to type at cursor
  - `MainViewModel` (@MainActor) — coordinator binding all services via Combine

## Commands

- Install: `open FeishuSpeech.xcodeproj`
- Test: `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test`
- Build: `xcodebuild -scheme FeishuSpeech -configuration Debug build`
- Lint: `swiftlint`
- Dev server: N/A (macOS app — build and run from Xcode or `xcodebuild`)

## Non-Negotiable Rules

- Think before coding: state assumptions, surface ambiguity, and ask when unclear.
- Read before writing: inspect the target file and relevant surrounding conventions immediately before editing or creating files.
- Keep it simple: solve the requested problem without speculative abstractions.
- Make surgical changes: touch only what the task requires; do not "improve" adjacent code.
- Goal-driven execution: define verifiable success criteria before starting; prefer write-the-failing-test-first for bugs; loop until criteria pass.
- Thread safety: UI updates must be on `@MainActor`; audio callbacks run on `audioQueue`; use `actor` for shared mutable state.
- Logger everywhere: every new file must declare `private let logger = Logger(subsystem: "com.feishuspeech.app", category: "X")`.

## Validation Policy

- Treat background hook output as advisory; do not re-run checks already passed.
- Run `xcodebuild … build` to confirm no compilation errors after non-trivial edits.
- Run `xcodebuild … test` before marking any bug fix complete.
- Run `swiftlint` and fix all warnings before committing.

## Kaola-Workflow

- Use `/workflow-next` as the workflow entrypoint and router.
- Keep phase work scoped, resumable, and recorded under `kaola-workflow/`.
- Maintain `workflow-state.md` for active work; it records current phase, step, pending gates, and next command.
- Delegate phase-specific work to vendored Claude Code agents; main session owns orchestration, review, and final decisions.
- Phase 1 discovers facts, Phase 2 chooses strategy, Phase 3 creates the executable blueprint.
- In Phase 1, spawn `code-explorer` for codebase research; spawn `knowledge-lookup` for external API/library behavior.
- In Phase 4, spawn `tdd-guide` per task as executor (RED → GREEN → REFACTOR).
- Route build/type/lint failures to `build-error-resolver`; route behavior/coverage failures back to `tdd-guide`.
- Active issue work runs in a repo-local worktree at `<repo-root>/.kw/worktrees/<project>/`.
- GitHub issues are the roadmap source of truth; `kaola-workflow/ROADMAP.md` is the local active-work mirror.
- `kaola-workflow/ROADMAP.md` is generated from `kaola-workflow/.roadmap/issue-*.md`; do not hand-edit the mirror.
- Each `/workflow-next` run targets one issue; finishing it is the terminal event.
- End each cycle: dock docs, update issues, refresh roadmap, archive completed folders, then commit and push.

## Project Conventions

- Swift: PascalCase types, camelCase methods/properties, no underscore prefix for private.
- Imports ordered: Foundation → AppKit → AVFoundation → Combine → SwiftUI → os.log; blank line between groups.
- Services: singleton + `ObservableObject`, or `actor` for concurrency-sensitive services.
- `@AppStorage` for UserDefaults; `Codable + Sendable` for data models.
- `[weak self]` in all Combine closures; subscriptions stored in `Set<AnyCancellable>`.

## Known Gotchas

- `TextInputSimulator` uses Cmd+V via CGEvent; clipboard restore can race the paste — issue #13.
- `AVCaptureSession.startRunning()` blocks the run loop; event tap must not share the main run loop — issue #9.
- Token expiry from Feishu API is currently ignored (hardcoded 6000 s) — issue #12.
- `appSecret` stored in plaintext UserDefaults; Keychain migration tracked in issue #18.
- Always run `swiftlint` before committing; `.swiftlint.yml` is present and enforced in CI.

## Documentation Map

- `README.md` — project overview and quick-start.
- `AGENTS.md` — full coding conventions, architecture details, and task recipes.
- `CHANGELOG.md` — user-visible changes.
- `docs/README.md` — documentation index.
- `docs/architecture.md` — system structure and data flow.
- `docs/api.md` — Feishu API integration details.
- `docs/conventions.md` — coding, testing, Git, and review rules.
- `docs/decisions/` — architecture decision records.
- `kaola-workflow/ROADMAP.md` — active implementation roadmap.

## Maintenance

- Keep this file under 200 lines; move detail to `AGENTS.md`, docs, or skills.
- Add rules only after repeated mistakes, review feedback, or stable project conventions.
- Do not use `@path` imports for optional reference material.
