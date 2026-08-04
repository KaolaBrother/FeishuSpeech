# Keep recognized text advancing for the entire Fn hold, not only the first word

- item: Reconstruct the latest installed build-5 one-word UAT from privacy-safe diagnostic logs and prove where progress stops across audio, Feishu responses, coordinator routing, and output outcomes.
  status: done
  result: build 5 sustained capture and 66 HTTP 200 response transactions across 13.55 seconds; progress therefore stops after transport, with successful coordinator/output boundaries absent from persisted diagnostics.

- item: Compare the observed multi-partial response shape with FeishuSpeech and KaolaTerminal streaming semantics, then identify the smallest safe continuous-output ownership model.
  status: done
  result: both clients decode opaque response scalars without assembly; FeishuSpeech emits the first scalar and silently suppresses every later non-prefix scalar as `revisionSuppressed`. The repair will use journal-indexed exact-once ownership and a locally growing output frontier without claiming unproved provider semantics.

- item: Add RED-first coverage for multiple held partials that are cumulative, disjoint, revised, duplicated, retried, and sealed, with no release-triggered first output or unsafe retargeting.
  status: done
  result: seven tests now cover disjoint/equal responses, two-stage replay ownership, ineligible and sealed events, no action-2 mutation, live AX growing frontiers, and the production UTF-16 suffix/PID boundary; baseline produced 10 expected failures across six coordinator tests while the append safety control passed.

- item: Repair the held-output path so every usable response advances visible cursor output throughout the Fn hold while preserving exact target, Secure Input, retry, and uncertainty boundaries.
  status: done
  result: MainViewModel now owns each eligible journal index once, grows a local UTF-16 frontier, suppresses historical replay, closes admission at release, ignores action-2 text, and emits transcript-free receipt/outcome diagnostics; the seven new acceptance tests, 44 transport/append tests, lint, and Debug build pass.

- item: Reconcile superseded coordinator test expectations with the held-output contract while retaining all target, Secure Input, retry, cancellation, and uncertainty assertions.
  status: done
  result: all 69 coordinator tests were retained and aligned to held-frontier/seal-only behavior; the lifecycle-free coordinator class is 69/69 and the complete direct XCTest bundle is 270/270, with all target, security, retry, cancellation, and lifecycle boundaries preserved.

- item: Independently review correctness and security for replacement/disjoint partial semantics, target drift, retries, and release races, then close every admitted finding test-first.
  status: done
  result: security review passed with zero findings; code review's sole P2 R1 was reproduced by two RED tests, repaired with a transcript-free held-recognition latch, reconciled across the suite, and independently re-reviewed as resolved with no new findings.

- item: Dock the corrected contract and run lifecycle-free tests, strict lint, Debug, and incremented Release validation without launching the application.
  status: done
  result: documentation is docked; clean build-for-testing and direct XCTest passed 272/272, strict lint passed 27/27, Debug and Release builds succeeded, and Release 1.0 build 6 passed strict signature/metadata verification with executable SHA-256 `b05753367fb31c235879fff7825bfdca7aaa8fce99ea9d8f040f86fe63448870`.

- item: Finalize and sink issue #26 while keeping it open, then replace Applications with the sole build-6 Release for owner UAT without launching it.
  status: done
  result: the keep-open finalize/sink transaction is prepared with a green consumer receipt, docked docs, and zero unresolved findings; `/Applications/FeishuSpeech.app` was atomically replaced with the verified Release 1.0 build 6, is the sole matching app under Applications, and remains unlaunched for owner UAT.
