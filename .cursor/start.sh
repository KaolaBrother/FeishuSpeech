#!/usr/bin/env bash
#
# Cloud Agent start — FeishuSpeech
#
# Per-boot reconciliation. The Kaola-Workflow cursor edition lives under the Cursor
# home (~/.cursor), which can be re-provisioned between boots, so we redeploy it
# here from the local clone created by install.sh. Idempotent and offline.
set -euo pipefail

KAOLA_DIR="/opt/kaola-workflow"
CURSOR_HOME_DIR="${CURSOR_HOME:-$HOME/.cursor}"

if [ -x "${KAOLA_DIR}/install-cursor.sh" ]; then
  echo "==> Reconciling Kaola-Workflow cursor edition into ${CURSOR_HOME_DIR}"
  "${KAOLA_DIR}/install-cursor.sh" --global --yes
elif [ -f "${CURSOR_HOME_DIR}/commands/workflow-next.md" ]; then
  echo "==> Kaola-Workflow commands already present"
else
  echo "error: Kaola-Workflow is not provisioned; run .cursor/install.sh" >&2
  exit 1
fi

echo "==> start complete"
