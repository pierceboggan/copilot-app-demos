#!/usr/bin/env bash
#
# Install a managed-settings file into the Linux file-based policy location.
#
#   ./install-linux.sh ../scenarios/01-lock-down-bypass.json
#
# Linux has no native MDM delivery for Copilot, so file-based is the only
# device-channel option there.
#
set -euo pipefail

TARGET_DIR="/etc/github-copilot"
TARGET="${TARGET_DIR}/managed-settings.json"
BACKUP="${TARGET}.demo-backup"

SOURCE="${1:-}"
if [[ -z "${SOURCE}" ]]; then
  echo "usage: $0 <path-to-managed-settings.json>" >&2
  exit 64
fi

if [[ ! -f "${SOURCE}" ]]; then
  echo "error: ${SOURCE} does not exist" >&2
  exit 66
fi

if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "${SOURCE}"; then
  echo "error: ${SOURCE} is not valid JSON" >&2
  exit 65
fi

sudo mkdir -p "${TARGET_DIR}"

if [[ -f "${TARGET}" && ! -f "${BACKUP}" ]]; then
  echo "Backing up the existing policy to ${BACKUP}"
  sudo cp "${TARGET}" "${BACKUP}"
fi

sudo cp "${SOURCE}" "${TARGET}"
sudo chown root:root "${TARGET}"
sudo chmod 644 "${TARGET}"

ls -l "${TARGET}"
echo ""
cat "${TARGET}"
echo ""
echo "Restart the client so it reloads policy at startup, then run:"
echo "  cd ../../validate && npm install && node validate-managed-settings.mjs"
