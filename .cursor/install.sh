#!/usr/bin/env bash
#
# Cloud Agent install — FeishuSpeech
#
# FeishuSpeech is a macOS menu-bar app (AppKit / AVFoundation / SwiftUI / CGEventTap).
# It can only be *built and run* on macOS + Xcode, so `xcodebuild build`/`test` are NOT
# possible on this Linux Cloud Agent VM. What IS portable is the CI `swiftlint --strict`
# lint gate — this script provisions the Swift toolchain (for SourceKit) and SwiftLint so
# that gate runs here, and installs the Kaola-Workflow "cursor edition" agents/commands.
#
# The script is idempotent: it may run repeatedly and skips work that is already done.
set -euo pipefail

SWIFT_URL="https://download.swift.org/swift-6.1.2-release/ubuntu2404/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-ubuntu24.04.tar.gz"
SWIFT_DIR="/opt/swift"

SWIFTLINT_VERSION="0.65.0"
SWIFTLINT_URL="https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/swiftlint_linux_amd64.zip"
SWIFTLINT_DIR="/opt/swiftlint"

KAOLA_REPO="https://github.com/KaolaBrother/Kaola-Workflow.git"
KAOLA_SHA="b96d0d565147f90fd1450fe846f7a99ece50b08b"
KAOLA_DIR="/opt/kaola-workflow"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# Run a command as root when we are not already root.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

# ---------------------------------------------------------------------------
# 1. System packages required by the Swift runtime (best-effort).
# ---------------------------------------------------------------------------
log "Installing system packages for the Swift toolchain"
export DEBIAN_FRONTEND=noninteractive
as_root apt-get update -qq || true
as_root apt-get install -y -qq --no-install-recommends \
  binutils \
  git \
  curl \
  libc6-dev \
  libcurl4-openssl-dev \
  libedit2 \
  libncurses-dev \
  libpython3-dev \
  libsqlite3-0 \
  libxml2-dev \
  libz3-dev \
  pkg-config \
  tzdata \
  unzip \
  zlib1g-dev || true

# ---------------------------------------------------------------------------
# 2. Swift toolchain (provides SourceKit for SwiftLint; also gives `swift`/`swiftc`).
# ---------------------------------------------------------------------------
if [ -x "${SWIFT_DIR}/usr/bin/swift" ]; then
  log "Swift toolchain already present at ${SWIFT_DIR} — skipping download"
else
  log "Installing Swift toolchain into ${SWIFT_DIR}"
  as_root mkdir -p "${SWIFT_DIR}"
  as_root chown "$(id -u):$(id -g)" "${SWIFT_DIR}"
  curl -fsSL -o /tmp/swift.tar.gz "${SWIFT_URL}"
  tar -xzf /tmp/swift.tar.gz -C "${SWIFT_DIR}" --strip-components=1
  rm -f /tmp/swift.tar.gz
fi
"${SWIFT_DIR}/usr/bin/swift" --version

# Expose swift/swiftc on PATH via stable symlinks (avoids relying on profile sourcing).
as_root ln -sf "${SWIFT_DIR}/usr/bin/swift" /usr/local/bin/swift
as_root ln -sf "${SWIFT_DIR}/usr/bin/swiftc" /usr/local/bin/swiftc

# ---------------------------------------------------------------------------
# 3. SwiftLint (portable Linux binary) + wrapper that points it at SourceKit.
# ---------------------------------------------------------------------------
if swiftlint version 2>/dev/null | grep -qx "${SWIFTLINT_VERSION}"; then
  log "SwiftLint ${SWIFTLINT_VERSION} already installed — skipping"
else
  log "Installing SwiftLint ${SWIFTLINT_VERSION}"
  as_root mkdir -p "${SWIFTLINT_DIR}"
  curl -fsSL -o /tmp/swiftlint.zip "${SWIFTLINT_URL}"
  as_root unzip -o -q /tmp/swiftlint.zip -d "${SWIFTLINT_DIR}"
  rm -f /tmp/swiftlint.zip
  as_root chmod +x "${SWIFTLINT_DIR}/swiftlint"
  # Wrapper so `swiftlint` finds libsourcekitdInProc.so from the Swift toolchain.
  as_root tee /usr/local/bin/swiftlint >/dev/null <<EOF
#!/usr/bin/env bash
export LINUX_SOURCEKIT_LIB_PATH="\${LINUX_SOURCEKIT_LIB_PATH:-${SWIFT_DIR}/usr/lib}"
exec "${SWIFTLINT_DIR}/swiftlint" "\$@"
EOF
  as_root chmod +x /usr/local/bin/swiftlint
fi
swiftlint version

# Persist env for interactive shells (SourceKit path + Swift on PATH).
as_root tee /etc/profile.d/swift.sh >/dev/null <<EOF
export PATH="${SWIFT_DIR}/usr/bin:\$PATH"
export LINUX_SOURCEKIT_LIB_PATH="${SWIFT_DIR}/usr/lib"
EOF

# ---------------------------------------------------------------------------
# 4. Kaola-Workflow cursor edition (agents + commands + support scripts + hooks).
#    Cloned to a stable location so `start` can redeploy it per-boot without network.
# ---------------------------------------------------------------------------
log "Fetching Kaola-Workflow (pinned ${KAOLA_SHA})"
if [ -d "${KAOLA_DIR}/.git" ]; then
  git -C "${KAOLA_DIR}" fetch --depth 1 origin "${KAOLA_SHA}" || git -C "${KAOLA_DIR}" fetch origin
  git -C "${KAOLA_DIR}" checkout -q "${KAOLA_SHA}"
else
  as_root mkdir -p "${KAOLA_DIR}"
  as_root chown "$(id -u):$(id -g)" "${KAOLA_DIR}"
  git clone "${KAOLA_REPO}" "${KAOLA_DIR}"
  git -C "${KAOLA_DIR}" checkout -q "${KAOLA_SHA}"
fi

log "Deploying Kaola-Workflow cursor edition into ${CURSOR_HOME:-$HOME/.cursor}"
"${KAOLA_DIR}/install-cursor.sh" --global --yes

log "Install complete."
