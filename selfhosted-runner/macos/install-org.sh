#!/usr/bin/env bash
# Install an org-scoped GitHub Actions self-hosted runner on macOS.
#
# Org-scoped means: one runner serves every repo under Wontlost-LTD that
# opts in via repo-level CI_RUNNER_LABELS variable. Compared to repo-scoped:
#   - 1 runner instead of N (one per repo)
#   - 1 launchd service to manage
#   - Single label set centrally controlled
#
# Token mint is done automatically via `gh api` — no copy-paste from the
# browser. You must already be logged in to gh as a Wontlost-LTD admin.
#
# Usage:
#   ./install-org.sh
#
# Then start the service:
#   cd ~/actions-runner-wontlost-org && ./svc.sh install && ./svc.sh start

set -euo pipefail

ORG="Wontlost-LTD"
ORG_URL="https://github.com/${ORG}"
RUNNER_NAME="$(hostname -s)-wontlost-org"
# Same base labels as the prior repo-scoped runner so existing
# CI_RUNNER_LABELS variables that reference [self-hosted,macos,arm64,mbp]
# keep working. Add 'org' so future workflows can target this runner
# specifically when both repo- and org-scoped runners coexist.
RUNNER_LABELS="self-hosted,macos,arm64,mbp,org"
RUNNER_DIR="$HOME/actions-runner-wontlost-org"
RUNNER_VERSION="2.328.0"
RUNNER_ARCH="osx-arm64"
RUNNER_TARBALL="actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"

# Mint a fresh registration token. Token expires in 1 hour but we use it
# immediately, so this is fine. Requires `gh auth login` with admin:org scope.
echo "+ minting registration token for org $ORG"
TOKEN=$(gh api -X POST "orgs/${ORG}/actions/runners/registration-token" --jq '.token')
if [ -z "$TOKEN" ]; then
  echo "failed to mint registration token; check 'gh auth status' for admin:org scope" >&2
  exit 1
fi

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

# Wipe any prior registration state; --replace tells GitHub to overwrite
# any stale server-side registration with the same name.
rm -f .runner .credentials .credentials_rsaparams 2>/dev/null || true

echo "+ registering runner '$RUNNER_NAME' against $ORG_URL"
./config.sh \
  --unattended \
  --url "$ORG_URL" \
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
echo "Org UI:"
echo "  https://github.com/organizations/${ORG}/settings/actions/runners"
echo "  Should show '$RUNNER_NAME' as Idle, available to all repos."
