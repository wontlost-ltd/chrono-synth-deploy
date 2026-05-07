#!/usr/bin/env bash
# Tear down the macOS self-hosted runner cleanly.
#
# Steps:
#   1. Stop + uninstall the launchd service (so it doesn't restart)
#   2. Deregister from GitHub (frees the runner slot in the org)
#   3. Delete the install directory
#
# Usage:
#   ./uninstall.sh <removal-token>
#
# Removal token comes from the same GitHub page as the registration token,
# but using the "Remove" button on the existing runner row, not "New runner".

set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "usage: $0 <removal-token>" >&2
  echo "  Get the removal token from the runner's row at:" >&2
  echo "  https://github.com/Wontlost-LTD/chrono-synth-os/settings/actions/runners" >&2
  exit 1
fi
TOKEN="$1"

RUNNER_DIR="$HOME/actions-runner-chrono-os"

if [ ! -d "$RUNNER_DIR" ]; then
  echo "+ no runner directory at $RUNNER_DIR — nothing to do"
  exit 0
fi

cd "$RUNNER_DIR"

if [ -f ./svc.sh ]; then
  echo "+ stopping launchd service"
  ./svc.sh stop || true
  ./svc.sh uninstall || true
fi

if [ -f ./config.sh ] && [ -f .runner ]; then
  echo "+ deregistering from GitHub"
  ./config.sh remove --token "$TOKEN" || true
fi

cd "$HOME"
echo "+ removing $RUNNER_DIR"
rm -rf "$RUNNER_DIR"

echo ""
echo "Runner uninstalled. Verify on GitHub UI that the runner row is gone:"
echo "  https://github.com/Wontlost-LTD/chrono-synth-os/settings/actions/runners"
