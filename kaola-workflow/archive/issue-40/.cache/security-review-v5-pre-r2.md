# Issue #40 v5 Pre-Implementation Security Re-review R2

- Blueprint: `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/architecture-blueprint-v5.md`
- Re-reviewed length: 944 lines
- Prior review: `/Users/ylpromax5/Workspace/feishuspeech/kaola-workflow/issue-40/.cache/security-review-v5-pre.md`
- Rejected source: `b321ac5d6c04c91ced9afeb2240f9566d9b8d305`
- Scope: fully revised v5 architecture before production or test implementation

## Verdict

FAIL. The revision closes prior Security R1 and R2 to the strongest implementable public-API boundary, but one new high-severity cancellation race remains in the executor contract. A cancellation requested before key-down is queued on the same occupied serial executor, while the concrete commit gate has no cancellation/attempt-state fence. The blueprint therefore cannot yet prove its own `notStarted(.cancellation)` zero-post guarantee.

finding: id=R3 scope=in_scope action=fix status=open severity=high fix_role=security rationale=queued-cancellation-cannot-fence-keydown

### R3 - Same-executor cancellation can arrive before down but execute only after submission

- Failure class: authorization revocation race / stale one-shot capability.
- Trigger: an admitted permit is executing a synchronous but bounded AX message or event-preparation step on the private serial submission context. Before the two-second deadline and before key-down, MainActor revokes/cancels the interaction. The AX call then returns with positive budget and the active submission continues to the commit gate.
- Expected behavior: cancellation observed before key-down terminalizes the permit as `notStarted(.cancellation)`, destroys every prepared pair, posts zero events, preserves the exact draft, and only then returns a receipt (`architecture-blueprint-v5.md:306-318`, `:337-345`, `:545-554`).
- Observed design gap: cancellation requests are descriptors sent to the same executor (`architecture-blueprint-v5.md:284-288`). If `submit` currently occupies that serial context, the cancellation descriptor cannot execute until the submission yields or returns. The documented commit API accepts only `preparedPair`, `expectedCombinedEpoch`, and `absoluteDeadline` (`architecture-blueprint-v5.md:389-400`), and its under-lock decision compares only deadline plus combined epoch (`:402-428`). Cancellation is not a combined-epoch signal (`:435-462`) and no executor-owned cancelled-attempt bit is read under the gate. Thus a cancellation queued during AX work can remain invisible when AX returns; key-down and mandatory up may post before the queued cancellation is processed.
- Concrete reproduction path: inject a synchronous AX dependency that blocks after permit admission but returns before the absolute deadline. While blocked, send the documented cancellation descriptor. Release the dependency. In a conventional single serial-queue `submit` closure, the active closure proceeds through preparation and sees valid deadline/epoch, posts down/up, terminalizes, and only afterward can the queued cancellation closure run. The same race remains if work is staged but cancellation arrives after the last stage begins and before gate comparison.
- Exploitability and blast radius: a user or lifecycle/security path can revoke an explicit submission before the irreversible boundary yet still have the entire frozen transcript posted once. This violates cancellation authority and can expose the draft to a target after the interaction was revoked. Mandatory up and no-resend still limit the blast radius to one fixed-target attempt, but they do not undo the unauthorized down.
- Why existing controls do not prevent it: MainActor's in-flight fence prevents a sibling permit but does not revoke the live executor permit. Task cancellation is explicitly not proof that synchronous work stopped (`architecture-blueprint-v5.md:512-519`). Deadline checks help only after expiry; this trigger returns before expiry. Combined lifecycle/input signals help only if the cancellation coincidentally produces one of those signals.
- Test gap: the concrete security selector covers cancellation after down and mandatory up (`architecture-blueprint-v5.md:721-734`). The coordinator matrix and installed UAT mention pre-boundary cancellation only generically (`:775-802`, `:850-878`); neither requires `block synchronous AX -> request cancellation -> release before deadline -> zero preparation/post -> terminal cancellation acknowledgement` against the production executor.
- Required repair: make cancellation a synchronous thread-safe revocation signal owned by the same attempt/commit primitive, not merely a queued executor request. The final gate must compare raw `cancelledAttemptID` or an attempt-specific cancellation generation under the same tiny nonrecursive commit lock immediately before down, alongside deadline and combined epoch, with no callback/getter/protocol dispatch. Cancellation after down remains an observation only and must not suppress mandatory up. Add separate before-down and after-down concrete executor tests; the before-down test must use the blocked-AX ordering above and assert zero posts plus terminal cleanup before MainActor can re-enable.

## Prior finding closure

### Security R1 closed - executor confinement, AX ownership, and stale deadline worker

The revision defines one nonisolated serial confinement boundary that owns the target registry, every raw AX object, raw event source/CGEvent, prepared pair, permit phase, absolute deadline, combined epoch baseline, and fixed backend until terminal receipt (`architecture-blueprint-v5.md:142-182`, `:245-304`, `:369-433`). MainActor exchanges only Sendable descriptors, opaque IDs, and typed receipts; raw objects never cross an actor, queue, continuation, protocol, or MainActor boundary.

The same absolute deadline starts at gesture consumption, includes queue wait, and is enforced by the executor through every AX message, preparation/readback, bounded `try()` lock admission, and the under-lock pre-down check (`architecture-blueprint-v5.md:490-519`). Every freshly created AX object receives `min(500 ms, remaining positive budget)` before each message (`:184-207`, `:502-511`). MainActor has no independent timeout and cannot re-enable until terminal cleanup proves no old prepared pair can post (`:279-288`, `:418-423`, `:512-543`). The stale-worker, queue-delay, fresh-object timeout, gate-deadline, and heartbeat oracles are explicit (`:775-802`). R3 is a cancellation-specific gap, not a reopening of deadline authority.

### Security R2 closed - strongest-observable activation/frontmost/process fence

The input-only epoch is replaced by one combined epoch covering physical input, relevant modifiers, programmatic activation/frontmost change, target termination, process-generation/identity change, observer loss, and both event-tap disablement modes (`architecture-blueprint-v5.md:435-462`). Observers advance the shared primitive synchronously on their callback thread instead of queueing behind AX work. The gate compares the raw combined epoch immediately before down, with exact tag plus own source PID as the only synthetic-event exemption (`:448-480`).

The revision no longer claims an impossible atomic WindowServer/process transaction. Notification lag, last-sample-to-post drift, and PID reuse are explicit fixed-target residuals; any subsequently observed drift is terminal uncertain with no retry, retarget, or ordinary Send (`architecture-blueprint-v5.md:464-488`, `:910-923`). This is an acceptable bounded platform limit for the fixed captured PID policy; disabling synthetic output remains the stated alternative if product policy rejects it.

## Other claims that survived re-review

- Zero pre-confirmation output remains categorical: no CGEvent post, target AX setter/focus restoration, activation, pasteboard operation, synthetic signal, delivery, retry, retarget, or automatic confirmation before a real current-preview intent (`architecture-blueprint-v5.md:40-63`). Capture is executor-owned and read-only; exact-cursor restore is post-confirmation (`:142-211`).
- Authority requires same-generation action 2 plus recorder barrier, current review/revision, editable state, safe nonempty draft capped at 16,384 UTF-16 units, one in-flight fence, and executor admission of one opaque target ID (`architecture-blueprint-v5.md:218-288`).
- Prepared down/up events are executor-confined, use one private source, exact frozen UTF-16 payload, empty flags, exact tag, own source PID, fixed target PID, and complete readback before gate admission (`architecture-blueprint-v5.md:290-304`, `:389-428`). No callback, getter, validation, logging, protocol dispatch, async hop, continuation, or allocation occurs under the commit lock.
- The first down remains the irreversible boundary, key-up is mandatory and synchronous, and every crossed-boundary outcome is submitted-unverified terminal with no resend or ordinary Send/Return capability (`architecture-blueprint-v5.md:306-354`, `:402-423`, `:545-554`).
- The preview is a true nonactivating panel. Presentation never calls FeishuSpeech or target activation; WindowServer failure keeps only visible mouse Send and never installs global Return capture (`architecture-blueprint-v5.md:65-140`). Installed WindowServer proof remains a mandatory UAT gate.
- One native preview-local arbiter owns all keyboard authority. The Send button has no default action or Return key equivalent; only exact unmodified nonrepeating Return/keypad Enter in the exact key preview can confirm. Shift, IME, Option, Control, Command, Caps, repeats, non-key-preview Return, and target Return cannot create intent (`architecture-blueprint-v5.md:556-597`). Native `NSApplication.sendEvent` tests cover Control+Return and Control+keypad Enter with zero intent/delivery/output (`:745-773`).
- No clipboard, pasteboard, copy/paste, Cmd+V, target activation, ambient PID selection, global Return authorization, automatic retry, or retarget fallback is permitted. Static rejection searches and final independent security review are mandatory (`architecture-blueprint-v5.md:814-848`, `:886-906`).
- Physical and lifecycle signals synchronously advance the combined epoch; tap-disabled signals always advance, and only dual exact tag plus own PID provenance is exempt. Foreign, missing, zero-PID, wrong-tag, activation, and lifecycle signals cannot be exempt (`architecture-blueprint-v5.md:435-480`).
- Application-bound fallback keeps the captured stable positive PID/identity/current responder and never selects the ambient frontmost PID. Exact cursor uses only executor-owned captured raw AX state (`architecture-blueprint-v5.md:142-211`).
- Focus failure can affect only a local hint/telemetry. It cannot mutate the draft, call delivery, dismiss, activate, mint a permit, or capture target Return (`architecture-blueprint-v5.md:110-140`).
- The diagnostic-seam RED ordering is custody-safe and executable: output ownership first exposes only a behavior-preserving seam; TDD then records an immediate reentrant-access RED without hanging; behavioral repair is prohibited until that receipt; GREEN must use the concrete repaired epoch/executor/committer composition (`architecture-blueprint-v5.md:599-734`, `:814-833`).

## Review receipt

- Read the complete revised 944-line blueprint and the complete prior security review before judgment.
- Re-falsified executor/raw-handle confinement, exact-object AX timeout, absolute deadline and stale-worker ordering, combined input/activation/lifecycle epoch coverage, tag-plus-own-PID provenance, fixed-target platform residual, zero pre-confirmation side effects, one-shot phase boundary, mandatory up, terminal no-resend, nonactivation, local Return, clipboard/Cmd+V absence, and diagnostic RED custody/order.
- No blueprint, production, test, documentation, or installed application file was edited. This review wrote only the authorized workflow evidence file.

verdict: fail
findings_blocking: 1
review_conclusion: The revised blueprint closes both prior security findings, but pre-key-down cancellation still lacks an atomic executor-owned revocation fence and remains unsafe to implement.
