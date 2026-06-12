evidence-binding: n4-overlay-generation-guard c4cd5c2a7f3d
non_tdd_reason: Glue / animation-lifecycle wiring — OverlayWindowController is a @MainActor singleton driving a live NSPanel and NSAnimationContext completion callback. The race is a window/animation-lifecycle side-effect with no injectable seam for unit testing.
build-green: yes
regression-green: yes
Added private var generation: Int = 0; show() increments generation before showing; hide() captures generation, guards orderOut in completion handler with generation == capturedGeneration to prevent stale-completion race. Also added logger per project convention.
