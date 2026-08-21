verdict: PASS

Updated from verified source (current tree ce8e3d2):

- CHANGELOG.md: icon-only extra, chunked keep-alive remainder, Release coverage off
- docs/api.md: leftover is raw framed message end
- docs/architecture.md: repaired spliced journal-index paragraph; watchdog 18/30/min(drain,45); remainder framing
- docs/README.md: single Conventions/Decisions list including D-28-01
- docs/decisions/D-28-01.md: remainder + icon-only extra consequences
- README.md: already said 菜单栏图标; no-impact

Evidence:
- DirectFeishuHTTPClient.parseCompleteResponseKeepingRemainder in FeishuAPIService.swift
- DirectFeishuKeepAliveSession.parseResponseKeepingRemainder delegates to that parser
- FeishuSpeechApp.swift MenuBarExtra label is Image-only
- project.pbxproj Release ENABLE_CODE_COVERAGE = NO
