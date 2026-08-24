## Second installed UAT failed — confirmation authority correction required

Installed candidate: `4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a`.

Owner screenshot and interaction evidence, with transcript content intentionally omitted:

- The titlebar/traffic-light layout is now correct.
- The enlarged transcript typography is present.
- After freeze, the real editor is visible and usable, but the footer contains only Cancel.
- Send is absent and Return performs no confirmation.

Diagnosis boundary: the draft remains in non-confirmable `editablePending`. Best-effort AppKit activation/key/first-responder readiness is still acting as confirmation authority even after the durable draft surface exists. This is the wrong authority boundary.

V4 correction:

- Action 2 plus the recorder barrier must make the coordinator-owned frozen draft immediately editable and confirmable.
- AppKit activation/key/editor focus remains a best-effort presentation aid and typed telemetry surface; it must not hide Send or disable Return.
- External output remains possible only after the user's explicit Send/Return callback.
- Exact/application target identity, PID, live Accessibility trust, Secure Input, unsafe-text, stale-generation, and exact-once checks remain mandatory in the delivery layer after confirmation.
- No automatic delivery, retry, retarget, copy, or focus-based output is authorized.

Issue #40 remains open. Merge/closure/archive are paused for v4 architecture, RED/GREEN tests, implementation, reviews, final validation, replacement installation, and owner UAT.
