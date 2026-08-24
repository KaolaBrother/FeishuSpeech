## Residual system effect diagnosis — current installed candidate stopped

The owner reports an image paste can occur after ordinary typing and can persist after FeishuSpeech is turned off. The installed candidate was terminated immediately; merge and UAT remain blocked.

### Measured after termination

- No `FeishuSpeech` / `Siji.FeishuSpeech` process or launchd helper is running.
- Combined-session CGEvent modifier flags are `0`: Command, Shift, Control, Option, and Caps Lock are not stuck.
- The general pasteboard currently contains PNG/TIFF image types (`public.png`, Apple PNG, `public.tiff`, NeXT TIFF). Pasteboard contents were not read or altered.
- The current application-fallback implementation captures all pasteboard item types, replaces the general pasteboard with transcript text, posts a targeted Cmd+V pair, and asynchronously restores the captured pasteboard after one second.

### Admitted race (source-derived inference)

The target process provides no acknowledgement that it consumed the posted Cmd+V before restoration. A delayed target can therefore consume the queued paste only after the prior image snapshot has been restored, causing an image to paste later and making the next physical input appear to trigger it. The target process event queue is not externally observable, so this causal sequence is an inference from the measured state and exact production transaction, not a claimed runtime trace.

### V4 boundary correction

- Remove general-pasteboard snapshot/write/restore and Cmd+V from every accepted production output path.
- Recording, recognition, preview rendering, draft editing, cancellation, readiness, and failures must produce zero AX writes, keyboard events, pasteboard mutation, copy, paste, retry, retarget, or other synthetic output.
- Only explicit Send/Enter on the final frozen draft may authorize one tagged text transaction after live target-security validation; if a safe one-transaction text delivery cannot be proved, fail closed and retain the draft.
- No image or prior clipboard payload may ever be part of the transaction.

The Issue #40 implementation is not accepted. The app remains stopped while v4 architecture, RED/GREEN tests, implementation, independent reviews, full validation, replacement installation, and owner UAT are completed.
