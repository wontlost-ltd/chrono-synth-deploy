#!/usr/bin/env bash
# Tear down the org-scoped macOS self-hosted runner.
#
# Steps:
#   1. Stop + uninstall launchd service
#   2. Mint removal token from GitHub API (no copy-paste needed)
#   3. Deregister from the org
#   4. Delete install directory
#
# Usage: ./uninstall-org.sh

set -euo pipefail

ORG="Wontlost-LTD"
RUNNER_DIR="$HOME/actions-runner-wontlost-org"

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
  echo "+ minting removal token for org $ORG"
  TOKEN=$(gh api -X POST "orgs/${ORG}/actions/runners/remove-token" --jq '.token')
  if [ -z "$TOKEN" ]; then
    echo "failed to mint removal token; you can still rm -rf $RUNNER_DIR but the org runner list will keep a stale entry until you Force-remove it via UI" >&2
  else
    echo "+ deregistering from $ORG"
    ./config.sh remove --token "$TOKEN" || true
  fi
fi

cd "$HOME"
echo "+ removing $RUNNER_DIR"
rm -rf "$RUNNER_DIR"

echo ""
echo "Runner uninstalled. Verify:"
echo "  https://github.com/organizations/${ORG}/settings/actions/runners"
