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
- Goal-driven execution: Define verifiable success criteria before starting. Keep the tests in separate custody from the code they judge — whoever implements a behavior does not author its tests. Loop until criteria pass; do not declare done on weak signals.
- Verify facts, do not fabricate: confirm API and library behavior against documentation, source, or a run before relying on it. Name what is unknown and find out.
- Reuse before adding: search for an existing equivalent before introducing a new interface or abstraction.
- Escalate irreversible changes: present the decision and evidence before altering a user-owned contract, public API, schema, dependency, build tool, or working capability.
- Thread safety: UI updates must be on `@MainActor`; audio callbacks run on `audioQueue`; use `actor` for shared mutable state.
- Logger everywhere: every new file must declare `private let logger = Logger(subsystem: "com.feishuspeech.app", category: "X")`.

## First Principles

These are the workflow's tie-breaking axioms, applied in priority order whenever a situation is not already settled.

1. **Correct first.** Never trade correctness for speed or cost; rework is the most expensive outcome.
2. **Then save human time.** Remove manual steps and shorten the wait, without weakening axiom 1.
3. **Then spend as little as possible.** Use the cheapest sufficient mechanism — parallelism, extra agents, and higher model tiers are means, not goals.
4. **Machines decide facts; humans decide values.** Take irreversible and value-laden calls to the user and ask, in conversation; leave everything checkable to run automatically.
5. **Own your own verdicts.** Never let a system the workflow does not own, such as CI or an external service, be the judge of done.

**Tie-breaker protocol:** when nothing else covers a situation, walk these axioms in order and record a one-line derivation alongside the work when useful.

**Dispatch production; keep decisions:** the main session owns orchestration, review, validation, integration, and final decisions. Delegate discretionary production when the handoff saves more context than it costs.

**Parallel by default:** run genuinely independent work concurrently and dependent work in order. Size concurrency to the actual shape of the task.

## Validation Policy

- Treat background hook output as advisory; do not re-run checks already passed.
- Run `xcodebuild … build` to confirm no compilation errors after non-trivial edits.
- Run `xcodebuild … test` before marking any bug fix complete.
- Run `swiftlint` and fix all warnings before committing.

## Kaola-Workflow

- Start and resume all workflow work through the installed workflow router.
- A run owns one issue, or one explicitly selected same-scope set, and records its issue, branch, and worktree in `kaola-workflow/{project}/workflow-state.md`.
- `kaola-workflow/{project}/mission-list.md` is the run's coordination record and the one file a successor needs. Its H1 states the goal; each ordered item is a one-line mission with `todo`, `in-flight`, or `done` status.
- Observe the three write moments: create an item before work, record `dispatched` and its output locator before sending work out, then record `result` when closing it.
- The frontier is the mission list minus `done` and `in-flight`. Decide whether to work inline or dispatch, and at what width, when an item reaches the frontier.
- Delegate production to installed role agents by default when delegation is useful; the main session retains orchestration, review, integration, and decisions. Keep role names runtime-neutral.
- Use `code-explorer` for repository research and `knowledge-lookup` for external behavior that cannot be verified locally.
- Keep test and implementation custody separate: `tdd-guide` owns test artifacts; `implementer` owns production code and may read and run, but not author, those tests.
- Route build, type, lint, dependency, and tooling failures to `build-error-resolver`; route behavior and coverage failures to `tdd-guide`.
- Route documentation work to `doc-updater`, which must transcribe verified ground truth or state what evidence is missing.
- At router startup, fetch remote-tracking refs, classify local/upstream state, and ask before risky synchronization.
- Use a persistent objective that ends with the selected issue. Never imply automatic continuation into another issue.
- Treat generated names, collision suffixes, cache paths, and harmless ordering as autonomous bookkeeping; take irreversible and value-laden decisions to the user.
- GitHub issues are the roadmap source of truth when available; `kaola-workflow/ROADMAP.md` is the generated local mirror.
- `kaola-workflow/ROADMAP.md` is generated from `kaola-workflow/.roadmap/issue-*.md`; do not hand-edit the mirror.
- Active issue work runs in a repo-local worktree at `<repo-root>/.kw/worktrees/<project>/` by default.
- After resume or compaction, read `workflow-state.md` and `mission-list.md`; for an `in-flight` item, look for the promised work product before deciding whether to re-dispatch.
- End each cycle by docking docs, resolving closure decisions, updating issues, refreshing the roadmap, archiving the workflow folder, and only then committing and pushing.

## Project Conventions

- Swift: PascalCase types, camelCase methods/properties, no underscore prefix for private.
- Imports ordered: Foundation → AppKit → AVFoundation → Combine → SwiftUI → os.log; blank line between groups.
- Services: singleton + `ObservableObject`, or `actor` for concurrency-sensitive services.
- `@AppStorage` for non-secret UserDefaults; Keychain-backed storage for credentials; `Codable + Sendable` for data models.
- `[weak self]` in all Combine closures; subscriptions stored in `Set<AnyCancellable>`.

## Known Gotchas

- `TextInputSimulator` clipboard restore is confirmed via changeCount polling and full snapshot; race fixed — issue #13 resolved.
- `AVCaptureSession.startRunning()` blocks the run loop; event tap must not share the main run loop — issue #9.
- Feishu token lifetime follows the response `expire` value with a 300-second safety margin; missing or non-positive values use the legacy fallback — issue #12 resolved.
- App ID and App Secret persist through `KeychainCredentialStore`; legacy UserDefaults values are migration inputs only — issue #18 resolved.
- Always run `swiftlint` before committing; `.swiftlint.yml` is present and enforced in CI.

## Documentation Map

- `README.md` — project overview and quick-start.
- `AGENTS.md` — mandatory redirect to this canonical file; historical guidance remains below its migration divider.
- `CHANGELOG.md` — user-visible changes.
- `docs/README.md` — documentation index.
- `docs/architecture.md` — system structure and data flow.
- `docs/api.md` — Feishu API integration details.
- `docs/conventions.md` — coding, testing, Git, and review rules.
- `docs/decisions/` — architecture decision records.
- `kaola-workflow/ROADMAP.md` — active implementation roadmap.

## Documentation Update Checklist

- Update `README.md` and `CHANGELOG.md` for user-visible behavior changes.
- Update `docs/api.md` when integration contracts or error outcomes change.
- Update `docs/architecture.md` and the relevant decision record when data flow or trust boundaries change.
- Update `docs/README.md` when documentation navigation changes.
- Record an explicit no-impact reason when none of these surfaces is affected.

## Maintenance

- Keep this file under 200 lines; move detail to docs or skills.
- Add rules only after repeated mistakes, review feedback, or stable project conventions.
- Do not use `@path` imports for optional reference material.
