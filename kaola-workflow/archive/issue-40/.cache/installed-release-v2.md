# Issue #40 installed Release receipt

date: 2026-08-23 Asia/Shanghai
candidate_commit: 4f9908fb1d5c8ed6eb6cc80da6e9d40c3ffdea5a
installed_path: /Applications/FeishuSpeech.app
bundle_identifier: Siji.FeishuSpeech
short_version: 1.0
bundle_version: 8
binary_sha256: 91731ffe1b2e0fac6943b96ae1ff34bc7335d72757a9af4f1bd59de7d48d9690
codesign_verdict: valid on disk; satisfies designated requirement
running_pid: 84412
running_executable: /Applications/FeishuSpeech.app/Contents/MacOS/FeishuSpeech

The Release product and installed executable hashes are identical. The installed-location audit of
/Applications and ~/Applications found exactly one app bundle: /Applications/FeishuSpeech.app.
Spotlight also reports Debug and Release Xcode DerivedData build products; these are build artifacts,
not installed application copies. Exactly one FeishuSpeech process is running, from /Applications.

owner_uat: failed_v3_retest

Observed by the owner on the installed Release: after speech stops, the same preview is editable but
remains on a persistent `重试编辑` state instead of exposing direct Send; transcript text is too
small; during streaming, content/title placement overlaps the upper-left window controls. The panel
size itself is acceptable and must not be enlarged. Issue #40 remains open pending repair and a new
installed-Release UAT.

The replacement Release at commit 4f9908f repairs those three observations, passed final v3 local
validation and independent correctness/security review, and is now installed for the second owner
UAT. The original failure above remains as historical evidence.

Second owner UAT evidence: the titlebar layout and enlarged typography are correct, but the frozen
draft shows only Cancel; Send is absent and Return does nothing. The visible editor remains trapped
in `editablePending`, proving that best-effort AppKit focus readiness is incorrectly acting as
confirmation authority. Transcript content from the supplied screenshot is intentionally not
recorded. Issue #40 remains open.
