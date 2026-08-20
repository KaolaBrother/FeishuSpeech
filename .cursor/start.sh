#!/usr/bin/env bash
#
# Cloud Agent start — FeishuSpeech
#
# Per-boot reconciliation. The Kaola-Workflow cursor edition lives under the Cursor home
# (~/.cursor), which can be re-provisioned between boots, so we redeploy it here from the
# local clone created by install.sh. This is idempotent, local, and needs no network.
set -euo pipefail

KAOLA_DIR="/opt/kaola-workflow"

if [ -x "${KAOLA_DIR}/install-cursor.sh" ]; then
  echo "==> Reconciling Kaola-Workflow cursor edition into ${CURSOR_HOME:-$HOME/.cursor}"
  "${KAOLA_DIR}/install-cursor.sh" --global --yes || \
    echo "warning: Kaola-Workflow cursor redeploy failed; workflow commands may be unavailable this boot" >&2
else
  echo "warning: ${KAOLA_DIR} not found; run .cursor/install.sh to provision the environment" >&2
fi

echo "==> start complete"
