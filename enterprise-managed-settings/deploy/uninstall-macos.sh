#!/usr/bin/env bash
#
# Remove the demo managed-settings file, restoring whatever was there before
# install-macos.sh ran.
#
set -euo pipefail

TARGET_DIR="/Library/Application Support/GitHubCopilot"
TARGET="${TARGET_DIR}/managed-settings.json"
BACKUP="${TARGET}.demo-backup"

if [[ -f "${BACKUP}" ]]; then
  echo "Restoring the policy that was in place before the demo"
  sudo mv "${BACKUP}" "${TARGET}"
  sudo chown root:wheel "${TARGET}"
  sudo chmod 644 "${TARGET}"
  cat "${TARGET}"
elif [[ -f "${TARGET}" ]]; then
  echo "Removing ${TARGET}"
  sudo rm "${TARGET}"
else
  echo "Nothing to remove at ${TARGET}"
fi

echo ""
echo "Restart the GitHub Copilot app so it reloads policy at startup."
