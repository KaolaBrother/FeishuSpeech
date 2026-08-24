## 2026-08-24 v4 repaired candidate installed for owner UAT

The correctness R1-R4 repairs are complete and the exact candidate commit is now installed:

- commit/remote branch: `b321ac5d6c04c91ced9afeb2240f9566d9b8d305` (`origin/workflow/issue-40` matched);
- install: `/Applications/FeishuSpeech.app`, bundle `Siji.FeishuSpeech`, version `1.0`;
- executable SHA-256: `4a5bc6b1d76d3b56c52e133db8e6b26b9f9a9ac3c8d15ccf898c92a231618fdb`;
- content-manifest SHA-256: `84fcd7885430e17e0c3e4c2b82d0e2dbe4a2caa32974d0369048d2adfc1ad5a3`;
- codesign verification passed;
- sole-copy audit found only `/Applications/FeishuSpeech.app` after deleting the rejected Applications bundle, two stale DerivedData copies, and the temporary build copy;
- exactly one process is running from `/Applications/FeishuSpeech.app/Contents/MacOS/FeishuSpeech`.

### Final gates

- R4 selectors: 3/3;
- Streaming: 105/105, zero skips;
- focused v4: 265/265, zero skips;
- full target: 483 passed, zero failed, one unrelated live-TCP skip;
- Debug/Release, strict lint, diff, docs links, async-topology and forbidden-output scans: PASS;
- independent correctness re-review: PASS, zero blocker/high/medium;
- adversarial security re-review: PASS, zero blocker/high.

### Installed interaction contract to verify

1. Fn press, recording, streaming recognition, Fn release/sealing, preview rendering, and every draft edit character create **zero external output signal**: no target text, image paste, clipboard change, copy/paste, AX write, synthetic keyboard event, retry, or retarget.
2. Only authoritative recognition action 2 plus the recorder barrier creates the editable draft and visible Send/qualified Return authority.
3. A real Send click or qualified Return/Enter authorizes exactly one modifier-free Unicode text submission attempt to the captured PID. The app never claims target consumption; uncertain state keeps the exact draft and does not auto-retry.
4. If recognition never reaches action 2, drain expiry may retain the exact partial (including LF) only as read-only “recognition incomplete” recovery; Send and Return must remain unavailable.
5. Multiline and emoji/non-BMP text remain exact data. Holding Command/Shift/Control/Option/Fn at final confirmation must fail closed with zero post.

Evidence receipts:

- `kaola-workflow/issue-40/test-green-v4-r4-final.md`
- `kaola-workflow/issue-40/.cache/code-review-v4-r4-final.md`
- `kaola-workflow/issue-40/.cache/security-review-v4-r4-final.md`
- `kaola-workflow/issue-40/.cache/validation-v4-r4-final.md`
- `kaola-workflow/issue-40/.cache/installed-release-v4.md`

Owner UAT is **pending**. The issue remains open and no merge/closure/success claim is made yet.
