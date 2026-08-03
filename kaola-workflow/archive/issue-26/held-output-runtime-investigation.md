# Issue 26 held-output runtime investigation

## Verdict

**PARTIAL** — the retained unified logs prove that the installed Release 1.0 (build 4) received usable streaming hypotheses and selected the unbound current-focus append path. They also prove that first-hypothesis timing was mixed: generations 6, 7, and 9 selected that path while Fn was still held, whereas generations 5, 8, and the latest generation 10 did not select it until sealing had begun. No fixed typed failure or warning/error entry was retained for the installed process. The current logging surface does not confirm that the target control accepted a posted Unicode event, so visible insertion cannot be proved or disproved from these logs.

## Privacy and mutation boundary

- Read only process metadata, installed bundle identity/signature/hash, repository source that defines fixed log markers and output routing, and unified-log entries restricted to subsystem `com.feishuspeech.app` plus pre-audited fixed stage/capability/error markers.
- Did not launch or restart the application, simulate Fn, trigger permissions, make an API call, read credentials, transcription text, audio, response bodies, pasteboard contents, app/window titles, or focused-control contents.
- Did not edit source or tests. This report is the only file written.

## Setup

| Item | Observed value |
|---|---|
| Repository working directory | `/Users/ylpromax5/Workspace/feishuspeech` |
| Repository commit | `43fbfe203cffbac4bc8df1ec45fd6addf82ea880` |
| Host | macOS 26.6 (25G72), arm64 |
| Measurement time | 2026-08-03T12:02:19Z (20:02:19 Asia/Shanghai) |
| Installed process | PID 20339, started 2026-08-03 19:56:15 +0800 |
| Executable | `/Applications/FeishuSpeech.app/Contents/MacOS/FeishuSpeech` |
| Installed version | 1.0 (build 4) |
| Executable SHA-256 | `f1f65f6b829386d26db57c048ad76cdd0ed5f22893ad4cee68f62d185a1dbf7d` |
| Signature verification | `valid on disk`; satisfies Designated Requirement |
| Log interval used for installed PID | 2026-08-03 19:56:15 +0800 through query time |

The installed executable hash matches the build-4 hash recorded by the prior validated install receipt. This identifies the running process as the intended installed Release surface; it does not by itself validate runtime output.

## Observation table

| Measurement | Command (verbatim or predicate-preserving form) | Result | Exit code |
|---|---|---|---:|
| Repository/environment baseline | `git rev-parse HEAD`; `git status --short`; `sw_vers`; `uname -m`; `date -u '+%Y-%m-%dT%H:%M:%SZ'` | Commit and host values shown in Setup. Existing `.kw/` and `kaola-workflow/issue-26/` were untracked; no tracked files were changed. | 0 |
| Installed process and bundle | `pgrep -x -l FeishuSpeech`; `ps -p 20339 -o pid=,lstart=,etime=,command=`; PlistBuddy reads of `CFBundleShortVersionString` and `CFBundleVersion` | PID 20339 was live from the installed app; version 1.0 build 4. | 0 |
| Installed executable identity | `shasum -a 256 /Applications/FeishuSpeech.app/Contents/MacOS/FeishuSpeech`; `codesign --verify --deep --strict --verbose=2 /Applications/FeishuSpeech.app` | SHA-256 and valid signature shown in Setup. | 0 |
| Safe runtime chronology | `/usr/bin/log show --info --debug --start '2026-08-03 19:40:00' --style compact --predicate 'subsystem == "com.feishuspeech.app" AND (<pre-audited fixed stage/capability/failure markers>)'` | Six installed-process generations (5 through 10) were retained. The earlier xctest PID 70744 and prior app PID 33111 were separated by process identity and excluded from the UAT conclusion. | 0 |
| Installed-process warning/error scan | `/usr/bin/log show --info --debug --start '2026-08-03 19:56:15' --style compact --predicate 'processIdentifier == 20339 AND subsystem == "com.feishuspeech.app"' \| rg ' E  \| W  '` | No matching retained warning/error entry for PID 20339. `rg` returned no-match. | 1 (no match) |
| Routing implementation read | `nl -ba FeishuSpeech/ViewModels/MainViewModel.swift | sed -n '868,1117p'`; `nl -ba FeishuSpeech/Services/CurrentFocusAppendSession.swift`; `nl -ba FeishuSpeech/Services/TextInputSimulator.swift | sed -n '1,230p'` | Established what the fixed capability markers mean without reading runtime content. No code was executed or changed. | 0 |

## Reproduction status

**Reproduced from retained runtime evidence, without re-triggering the interaction.**

The latest retained interaction, generation 10, had this sequence:

| Timestamp (+0800) | Fixed event |
|---|---|
| 20:01:30.531 | Transition to streaming generation 10 |
| 20:01:30.531 | Initial AX destination unavailable; current-focus final fallback selected |
| 20:01:30.597 | Streaming capture started |
| 20:01:32.108 | Fn release transitioned streaming to sealing |
| 20:01:32.112 | Streaming recording began stopping |
| 20:01:32.129 | Streaming audio resources released |
| 20:01:32.304 | Continuous current-focus append output armed |
| 20:01:32.857 | State returned to a private-valued normal state marker |

The append-path marker occurred **196 ms after release/sealing began**, and 175 ms after audio resources were released. In this implementation that marker is reachable only while handling a non-contentless first streaming hypothesis. Therefore generation 10 did receive a usable hypothesis, but not early enough to select continuous output while Fn was held.

## Per-generation timing

`Armed continuous current-focus append output` is used as the privacy-safe proxy for the first usable hypothesis: the source emits it only from `handlePartial` after the initial AX-unavailable fallback is re-evaluated on a non-contentless hypothesis.

| Generation | Streaming start | Append armed | Release/seal | Append minus release | First usable hypothesis before release? |
|---:|---:|---:|---:|---:|---|
| 5 | 20:00:19.534 | 20:00:21.533 | 20:00:21.480 | +53 ms | No; after sealing began |
| 6 | 20:00:27.566 | 20:00:30.973 | 20:00:36.505 | -5.532 s | Yes |
| 7 | 20:01:03.127 | 20:01:05.814 | 20:01:08.317 | -2.503 s | Yes |
| 8 | 20:01:10.843 | 20:01:13.534 | 20:01:13.364 | +170 ms | No; after sealing began |
| 9 | 20:01:19.135 | 20:01:23.526 | 20:01:24.505 | -979 ms | Yes |
| 10 | 20:01:30.531 | 20:01:32.304 | 20:01:32.108 | +196 ms | No; after sealing began |

Raw result: 3/6 generations selected the append path before release and 3/6 after release. The latest generation was in the after-release group.

## Narrowing legs

### Leg 1 — installed identity versus unrelated logs

Axis: process identity.

- PID 20339 is the installed build-4 process.
- xctest PID 70744 emitted many synthetic error fixtures around 19:42; those are test logs, not installed-runtime failures.
- prior app PID 33111 emitted an event-tap warning at 19:51; it predates PID 20339 and is not attributed to these generations.

This eliminates the hypothesis that the visible xctest business codes or typed errors were failures from the installed UAT process.

### Leg 2 — recognition availability versus no partials

Axis: first usable hypothesis timing.

Every observed generation reached `Armed continuous current-focus append output`. By source control flow, that marker requires a non-contentless partial to have reached `handlePartial`. This rules out “the installed run never received any usable partial” for generations 5–10.

It does not show the hypothesis content or whether a later final differed; neither was inspected.

### Leg 3 — capability selection

Axis: output capability/path.

Every generation first logged `Accessibility destination unavailable; using current-focus final output`. On the first usable hypothesis, every generation then logged `Armed continuous current-focus append output`.

The selected path was therefore:

1. initial AX cursor capture unavailable;
2. temporary current-focus final-only fallback;
3. first-partial AX rebind still unavailable;
4. same-frontmost-process current-focus append session;
5. incremental Unicode CGEvent posting through the HID event tap, not the AX replacement path and not the pasteboard/Cmd-V final-only path.

### Leg 4 — sealing timing

Axis: append-path selection relative to release.

Generations 6, 7, and 9 prove that selection was not universally deferred until sealing. Generations 5, 8, and 10 prove that some hypotheses arrived too late for held-key output; their output path was selected only after release began sealing. This rules out a single deterministic local gate that always waits for release, but confirms the reported timing for the latest generation.

### Leg 5 — fixed failure surface

Axis: retained warning/error messages for PID 20339.

The process-specific warning/error scan had zero matches. There was no installed-process `Streaming response rejected`, retry warning, secure-input suspension, destination-change suspension, delivery-uncertain suspension, manual-recovery marker, or fixed HotKey error in the retained interval.

This rules out a logged typed failure as the explanation. It does not rule out an unlogged target-control rejection of a posted CGEvent.

## Labeled inferences

1. **High confidence:** generations 5–10 each received at least one usable non-contentless streaming hypothesis. Refutation: demonstrate another reachable source path that emits `Armed continuous current-focus append output` without `handlePartial`; the inspected source has none.
2. **High confidence:** generation 10 could not have attempted incremental append before release because its append session was not armed until 196 ms after sealing began. Refutation: a separate unlogged output route active before the marker; the inspected routing state shows none for this AX-unavailable case.
3. **High confidence:** generations 6, 7, and 9 selected the continuous append path while held. Refutation: timestamp ordering error in unified logging across these same-process, same-thread fixed markers; all relevant markers were emitted by PID 20339/TID 4cce567.
4. **Medium confidence:** for the pre-release generations, the app locally proceeded as though it posted incremental Unicode events. There were no suspension/failure markers, and `handlePartial` applies the same hypothesis immediately after arming. Confidence is not high because `CGEvent.post` has no target-control acknowledgement and the successful apply outcome is not logged.
5. **High confidence:** there is no retained fixed typed failure for the installed process. This is an absence claim limited to the retained unified-log interval, not proof that no unlogged failure occurred.

## What remains unmeasured

- Whether the HID-posted Unicode event was accepted, ignored, transformed, or rejected by the target control. The current event poster returns `.posted` immediately after `CGEvent.post` and has no delivery acknowledgement.
- Which exact target application/control was involved. Deliberately not read under the privacy boundary.
- Whether `autoInsert` or another preference changed between generations. Credentials and user content were not read; the capability markers do establish that automatic-output routing was active when the partial arrived.
- Partial/final text, audio, response bodies, and clipboard state. Deliberately not read.
- Provider-side latency breakdown before the first hypothesis. The logs expose local stage timestamps but no safe request/response timing marker for each accepted partial.
- A live re-run. Deliberately not performed.

## Conclusion

The latest installed build-4 run did receive a usable hypothesis, but its continuous-output path was selected only after Fn release had already initiated sealing. Across the six retained runs, the behavior was timing-dependent rather than universally release-gated: half selected current-focus append while held, half only after release. All runs used the AX-unavailable fallback that ultimately posts Unicode CGEvents to the current focus. No fixed typed failure was logged. For runs that armed before release, the remaining gap is downstream of capability selection: the app has no log or acknowledgement proving that the focused control accepted the posted Unicode event.
