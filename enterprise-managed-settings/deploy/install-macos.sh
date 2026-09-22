#!/usr/bin/env bash
#
# Install a managed-settings file into the macOS file-based policy location and
# verify the Copilot runtime picked it up.
#
# File-based delivery is the fastest way to demo enterprise managed settings:
# it needs no enterprise, no `.github-private` repository, and no MDM server.
# The trade-off is that it applies to whoever is signed in on this machine.
#
#   ./install-macos.sh ../scenarios/01-lock-down-bypass.json
#   ./install-macos.sh ../copilot/managed-settings.json
#
set -euo pipefail

TARGET_DIR="/Library/Application Support/GitHubCopilot"
TARGET="${TARGET_DIR}/managed-settings.json"
BACKUP="${TARGET}.demo-backup"

SOURCE="${1:-}"
if [[ -z "${SOURCE}" ]]; then
  echo "usage: $0 <path-to-managed-settings.json>" >&2
  echo "" >&2
  echo "available scenarios:" >&2
  ls -1 "$(dirname "$0")/../scenarios" 2>/dev/null | sed 's/^/  /' >&2
  exit 64
fi

if [[ ! -f "${SOURCE}" ]]; then
  echo "error: ${SOURCE} does not exist" >&2
  exit 66
fi

# The CLI rejects a malformed policy outright, which is a confusing way to
# discover a typo mid-demo.
if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "${SOURCE}"; then
  echo "error: ${SOURCE} is not valid JSON" >&2
  exit 65
fi

echo "Installing ${SOURCE}"
echo "         -> ${TARGET}"
echo ""
echo "This needs sudo: the CLI requires the file to be owned by root and not"
echo "group- or world-writable, and it refuses to follow a symlink."
echo ""

sudo mkdir -p "${TARGET_DIR}"

if [[ -f "${TARGET}" && ! -f "${BACKUP}" ]]; then
  echo "Backing up the existing policy to ${BACKUP}"
  sudo cp "${TARGET}" "${BACKUP}"
fi

sudo cp "${SOURCE}" "${TARGET}"
sudo chown root:wheel "${TARGET}"
sudo chmod 644 "${TARGET}"

echo ""
echo "Installed:"
ls -l "${TARGET}"
echo ""
cat "${TARGET}"
echo ""
echo "Restart the GitHub Copilot app (or the CLI) so it reloads policy at startup."
echo "Then confirm what the runtime actually enforced:"
echo ""
echo "  cd ../../validate && npm install && node validate-managed-settings.mjs"
