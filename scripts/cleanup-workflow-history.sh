#!/usr/bin/env bash
# Delete failed + cancelled GitHub Actions workflow runs across the
# Wontlost-LTD repos. Successful runs are kept — they're the CI history
# that proves a given commit ever passed.
#
# Why this exists:
#   GitHub gives no UI for bulk-deleting old runs, and the Actions tab
#   accumulates noise quickly when CI is flaky during infra changes
#   (spending-limit blocks, broken yaml expressions, deleted runners,
#   etc.). Cleaning that out makes the recent-success bar in the UI
#   actually meaningful again.
#
# Prerequisites:
#   - `gh` CLI installed and authenticated as a Wontlost-LTD admin
#     (`gh auth status` should show admin scopes for the org).
#   - The repos in REPOS below — edit if scope changes.
#
# Usage:
#   ./cleanup-workflow-history.sh             # interactive: shows counts, prompts
#   ./cleanup-workflow-history.sh --yes       # non-interactive (CI / cron)
#   ./cleanup-workflow-history.sh --dry-run   # report what would be deleted, no actual deletes
#
# Notes:
#   - Idempotent: re-running after success is a no-op.
#   - Runs page-by-page (gh api caps at 100/page). Loops until no more
#     failure/cancelled runs are found. Hard cap at 20 pages per repo
#     to avoid runaway loops on API hiccups.
#   - DELETE is irreversible. Logs/artifacts/step timings cannot be
#     recovered. The Actions UI shows a "deleted" placeholder for the
#     commit's checks, which is fine in practice.

set -euo pipefail

REPOS=(
  Wontlost-LTD/chrono-synth-os
  Wontlost-LTD/chrono-synth-web
  Wontlost-LTD/chrono-synth-desktop
  Wontlost-LTD/chrono-synth-deploy
)

DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help)
      sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//' | head -n -1
      exit 0
      ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found. Install from https://cli.github.com/" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "gh is not authenticated. Run: gh auth login" >&2
  exit 1
fi

# Survey first
echo "Scanning workflow runs across ${#REPOS[@]} repos..."
echo
printf "%-30s %-8s %-10s %-10s\n" "repo" "total" "to-delete" ""
printf "%-30s %-8s %-10s\n" "$(printf '%.0s-' {1..30})" "-----" "---------"
total_to_delete=0
for repo in "${REPOS[@]}"; do
  total=$(gh api "repos/$repo/actions/runs" --jq '.total_count' 2>/dev/null || echo 0)
  to_delete=$(gh api "repos/$repo/actions/runs?per_page=100" \
    --jq '[.workflow_runs[] | select(.conclusion == "failure" or .conclusion == "cancelled")] | length' 2>/dev/null || echo 0)
  printf "%-30s %-8s %-10s\n" "$repo" "$total" "$to_delete"
  total_to_delete=$((total_to_delete + to_delete))
done
echo
echo "Total runs to delete (first page only — actual may be higher across pagination): $total_to_delete"

if [ "$DRY_RUN" = "1" ]; then
  echo
  echo "[dry-run] No changes made."
  exit 0
fi

if [ "$ASSUME_YES" != "1" ]; then
  echo
  read -r -p "Delete failed + cancelled runs across all listed repos? [y/N] " confirm
  case "$confirm" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

# Run cleanup
echo
for repo in "${REPOS[@]}"; do
  before=$(gh api "repos/$repo/actions/runs" --jq '.total_count' 2>/dev/null || echo 0)
  echo "=== $repo (before: $before runs) ==="
  deleted=0
  page=1
  while true; do
    ids=$(gh api "repos/$repo/actions/runs?per_page=100&page=$page" \
      --jq '.workflow_runs[] | select(.conclusion == "failure" or .conclusion == "cancelled") | .id' 2>/dev/null || true)
    page_total=$(gh api "repos/$repo/actions/runs?per_page=100&page=$page" \
      --jq '.workflow_runs | length' 2>/dev/null || echo 0)

    [ "$page_total" = "0" ] && break

    while IFS= read -r id; do
      [ -z "$id" ] && continue
      if gh api -X DELETE "repos/$repo/actions/runs/$id" >/dev/null 2>&1; then
        deleted=$((deleted + 1))
      fi
    done <<< "$ids"

    [ "$page_total" -lt 100 ] && break
    page=$((page + 1))
    if [ "$page" -gt 20 ]; then
      echo "  warning: stopped at page 20 (safety cap). Re-run if more remain."
      break
    fi
  done

  after=$(gh api "repos/$repo/actions/runs" --jq '.total_count' 2>/dev/null || echo 0)
  echo "  deleted: $deleted, after: $after runs"
done

echo
echo "Done. To verify zero residue, re-run with --dry-run."
