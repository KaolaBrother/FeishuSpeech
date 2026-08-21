# Capture/recognition split and preferNoProxies fallback for issues #28–#31

- item: Implement capture-line HoldPacketJournal so PCM is journaled without waiting on Feishu factory
  status: done
  dispatched: Cursor PR #32 plus local remainder/UAT follow-up
  result: HoldPacketJournal + MainViewModel capture drain landed on cursor/bundle-28-29-30-31-ef04; overlay copy stays 正在聆听… / 正在完成识别…

- item: Map in-attempt transport cancel to recoverable timeout; keep generation cancel terminal
  status: done
  dispatched: PR #32
  result: CancellationError / URLError.cancelled / StreamFailure.cancelled remapped while retry admission is open

- item: Per-attempt URLSession with transport-owned slice timers; drop streaming NWPathMonitor hard gate
  status: done
  dispatched: PR #32
  result: factory 18 s (8+7+1), packet 30 s (14+14+1), finish min(drain, 45 s)

- item: Hop once from a no-HTTP URLSession slice to preferNoProxies keep-alive; remainder must be raw-framed
  status: done
  dispatched: PR #32 plus local parser fix
  result: DirectFeishuKeepAliveSession uses parseCompleteResponseKeepingRemainder; chunked leftover tests green

- item: Local macOS suite, icon-only extra, uninstrumented Release install
  status: done
  dispatched: self
  result: 345 xctest / 0 fail; Release without LLVM coverage; unique /Applications/FeishuSpeech.app
