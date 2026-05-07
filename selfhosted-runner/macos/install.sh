#!/usr/bin/env bash
# Install GitHub Actions self-hosted runner natively on macOS.
#
# Why native (not Docker): macOS containers go through a Linux VM (Lima/Docker
# Desktop), which adds CPU+IO overhead and runs into Apple Silicon networking
# quirks. The native binary is what GitHub publishes for macOS arm64 and runs
# directly on the host kernel.
#
# Why this script (not just paste from the GitHub UI): the GitHub-provided
# snippet hardcodes a token (single-use, 1h validity) and a temp install path.
# This script:
#   - lets you re-run idempotently
#   - separates the long-lived install from the short-lived token
#   - uses a stable RUNNER_DIR so launchd can re-find it
#
# Usage:
#   1. Get a registration token from
#      https://github.com/Wontlost-LTD/chrono-synth-os/settings/actions/runners/new
#   2. Run:
#        ./install.sh <REGISTRATION_TOKEN>
#   3. Start as a launchd service:
#        cd ~/actions-runner-chrono-os && ./svc.sh install && ./svc.sh start

set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "usage: $0 <registration-token>" >&2
  exit 1
fi
TOKEN="$1"

REPO_URL="https://github.com/Wontlost-LTD/chrono-synth-os"
RUNNER_NAME="$(hostname -s)-chrono-os"
RUNNER_LABELS="self-hosted,macos,arm64,mbp"
RUNNER_DIR="$HOME/actions-runner-chrono-os"
# Pin the version to keep installs reproducible. Bump intentionally; auto-update
# is on by default, so the runner self-updates from this baseline anyway.
RUNNER_VERSION="2.328.0"
RUNNER_ARCH="osx-arm64"
RUNNER_TARBALL="actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"

mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

if [ ! -f ./config.sh ]; then
  echo "+ downloading actions/runner ${RUNNER_VERSION} (${RUNNER_ARCH})"
  curl -fsSL -o "$RUNNER_TARBALL" \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_TARBALL}"
  tar xzf "$RUNNER_TARBALL"
  rm "$RUNNER_TARBALL"
else
  echo "+ runner already extracted in $RUNNER_DIR"
fi

# Wipe any prior registration state. We do NOT call `./config.sh remove`
# here — that endpoint requires a separate *removal* token, not the
# registration token, and calling it with the wrong token can cause GitHub
# to invalidate the registration token before we get to use it. Instead,
# delete the local state files directly and let `--replace` below tell
# GitHub to overwrite any stale registration server-side.
rm -f .runner .credentials .credentials_rsaparams 2>/dev/null || true

echo "+ registering runner '$RUNNER_NAME' against $REPO_URL"
./config.sh \
  --unattended \
  --url "$REPO_URL" \
  --token "$TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$RUNNER_LABELS" \
  --work _work \
  --replace

echo ""
echo "Runner installed at: $RUNNER_DIR"
echo ""
echo "Next: install + start the launchd service so it auto-starts on login."
echo ""
echo "  cd $RUNNER_DIR"
echo "  ./svc.sh install"
echo "  ./svc.sh start"
echo ""
echo "Verify:"
echo "  ./svc.sh status"
echo ""
echo "GitHub UI:"
echo "  $REPO_URL/settings/actions/runners"
echo "  Should show '$RUNNER_NAME' as Idle."
