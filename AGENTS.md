# FeishuSpeech Project Instructions

## Project Snapshot

- Purpose: macOS menu bar app that records a held Fn key, sends 16 kHz PCM audio to Feishu speech-to-text, and types recognized text at the cursor.
- Stack: Swift 5.9+, SwiftUI, macOS 13.0+, AVCaptureSession, CGEventTap, AVAudioConverter, and NWPathMonitor.
- Architecture:
  - `HotKeyService` owns the idle -> pending -> recording -> transcribing state machine.
  - `AudioRecorder` converts captured audio to 16 kHz, 16-bit, mono PCM with a bounded 2 MB buffer.
  - `FeishuAPIService` is an actor that owns token caching, network state, timeouts, and retries.
  - `MainViewModel` is the `@MainActor` coordinator; `TextInputSimulator` owns cursor insertion.

## Commands

- Open project: `open FeishuSpeech.xcodeproj`
- Test: `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test`
- Build: `xcodebuild -scheme FeishuSpeech -configuration Debug build`
- Lint: `swiftlint`
- Dev server: N/A; this is a native macOS application.

## Non-Negotiable Rules

- Think before coding: state assumptions, surface ambiguity, and ask when unclear.
- Read before writing: inspect the target and its surrounding conventions immediately before editing.
- Keep changes simple and surgical; solve the requested problem without speculative abstractions.
- Define verifiable success criteria before starting and loop until they pass.
- Keep acceptance meaning independent from the production code it judges.
- Verify APIs, interfaces, and behavior against documentation, source, or a real run; do not fabricate.
- Reuse an existing equivalent before adding a new interface.
- Escalate irreversible changes and user-owned public-contract decisions to the user.
- Keep UI updates on `@MainActor`, audio callbacks on `audioQueue`, and shared mutable service state actor-isolated.
- Every new Swift file must declare a private `Logger` with subsystem `com.feishuspeech.app`.

## First Principles

1. Correct first; never trade correctness for speed or cost.
2. Then save human time without weakening correctness.
3. Then use the cheapest sufficient mechanism.
4. Machines decide facts; humans decide values.
5. Own local completion evidence instead of outsourcing the verdict.

## Validation Policy

- Treat background hooks as advisory and avoid repeating validation they already completed.
- Record the exact commands and outcomes that establish completion.
- Run the smallest focused proof first, then `xcodebuild -scheme FeishuSpeech -destination 'platform=macOS' test` before completing a bug fix.
- Run a Debug build after non-trivial edits and run `swiftlint` before committing.

## Kaola-Workflow

<!-- KW-AGENTS-MANAGED-START -->
Everything between these markers is owned by `workflow-init`; owner content outside them is preserved.

<!-- PIN: forge-is-the-backlog -->
- Start or resume workflow work through the router entrypoint installed by the active runtime.
- The forge is the backlog authority; freshly verify issue state before it shapes implementation.
- `kaola-workflow/.roadmap/_rules.md` is the one optional local file that survives for standing project rules.
- nothing else is generated or tracked under `kaola-workflow/.roadmap/`; there is no local mirror to refresh.
- Top-priority labels: declare in `kaola-workflow/config.json` (`priority_top_tier_labels`).
- A run records its claim in `kaola-workflow/{project}/workflow-state.md` and its missions in
  `kaola-workflow/{project}/mission-list.md`.
- Keep each mission as `item`, `status`, `dispatched`, and `result`.
- Each entry is a mission, not a specification.
- The frontier is the list minus done minus in-flight; re-evaluate dispatch or inline for every item.
- One item never establishes a run-wide posture, and one unavailable exact role does not prove all native child dispatch is unavailable.
- **Three write moments.** Create the mission, record `dispatched` **before the work goes out**, then record `result` when it closes.
- `dispatched` records what went out, to whom, and where the output was to land.
- Once closed, the completed item and its result are immutable.
- The invariant is one dispatch has one result; if later work appears, append a new mission.
- A mission names a recoverable outcome or a newly discovered independent causal class; one selector, assertion, command, or review round is not by itself a mission.
- Keep working through same-custody failures; `BLOCKED` means the current owner cannot safely continue.
- Custody (who decides meaning) is independent of carrier (inline vs a native child).
- Converge the observed failure frontier before freezing a candidate and reviewing it.
- Name roles by function and reasoning tier, never by a vendor model name; write `planner (heavy-reasoning tier)`.
- Prefer the installed named role and follow this runtime's workflow-next / finalize capability guide for
  lookup, dispatch carrier, default tier binding, and available native routes.
- A built-in or generic child may take an item only as its real mechanism when it can satisfy the task, custody,
  evidence, and stop boundaries; never present it as a missing named role. Inline only that item when no adequate route exists.
- After resume or compaction, read the workflow state and mission list before continuing.
- Finalize only after focused and integration evidence pass, documentation is docked, and every finding closes.
- Archive completed run state through the installed workflow lifecycle rather than deleting it by hand.
<!-- KW-AGENTS-MANAGED-END -->

## Documentation Map

- `README.md` — project overview and quick start.
- `CHANGELOG.md` — user-visible changes.
- `docs/README.md` — documentation index.
- `docs/architecture.md` — component boundaries and data flow.
- `docs/api.md` — Feishu API contracts and error outcomes.
- `docs/conventions.md` — coding, testing, Git, and review conventions.
- `docs/decisions/` — architecture decision records.

## Project Conventions

- Use PascalCase for types and camelCase for methods and properties; private members have no underscore prefix.
- Order imports Foundation -> AppKit -> AVFoundation -> Combine -> SwiftUI -> os.log, with blank lines between groups.
- Services are singleton `ObservableObject`s or actors when concurrency-sensitive.
- Use `@AppStorage` for non-secret defaults and Keychain-backed storage for credentials.
- Use `Codable + Sendable` for data models and `[weak self]` in Combine closures.

## Known Gotchas

- `TextInputSimulator` clipboard restore uses change-count polling and a full snapshot; issue #13 fixed the race.
- `AVCaptureSession.startRunning()` blocks; never run the event tap on the same run loop as capture startup.
- Feishu token lifetime follows response `expire` with a 300-second safety margin; missing or non-positive values use the legacy fallback.
- App ID and App Secret belong in `KeychainCredentialStore`; legacy UserDefaults values are migration inputs only.

## Documentation Update Checklist

- Update `README.md` and `CHANGELOG.md` for user-visible behavior changes.
- Update `docs/api.md` when integration contracts or error outcomes change.
- Update `docs/architecture.md` and the relevant decision record when data flow or trust boundaries change.
- Update `docs/README.md` when documentation navigation changes.
- Record an explicit no-impact reason when none of these surfaces is affected.

## Maintenance

- Keep this universal contract concise; move long procedures and runtime-only detail elsewhere.
- Add rules only after repeated mistakes, review feedback, or stable project conventions.
- Runtime-native first-read files may bridge to this file and carry only genuine runtime overlays.
