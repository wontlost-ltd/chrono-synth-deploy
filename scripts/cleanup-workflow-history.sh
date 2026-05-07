#!/usr/bin/env bash
# Bulk-clean GitHub Actions workflow history across the Wontlost-LTD
# repos, keeping ONLY the most recent successful run per distinct
# workflow.
#
# Why this exists:
#   GitHub gives no UI for bulk-deleting old runs. The Actions tab
#   accumulates noise quickly during infra changes (spending-limit
#   blocks, broken yaml, deleted runners, dependabot churn). Even the
#   "passed" history holds little value past the latest run for each
#   workflow — older success runs' logs are rarely consulted, and the
#   "latest run" badge on the repo page is what signals current health.
#
# Retention policy:
#   For each distinct workflow_id in a repo, keep the single most
#   recent run with `conclusion=success`. Delete everything else
#   (failures, cancellations, AND superseded successes).
#
# Prerequisites:
#   - `gh` CLI installed and authenticated as a Wontlost-LTD admin
#     (`gh auth status` should show admin scopes for the org).
#   - The repos in REPOS below — edit if scope changes.
#
# Usage:
#   ./cleanup-workflow-history.sh             # interactive: shows plan, prompts
#   ./cleanup-workflow-history.sh --yes       # non-interactive (CI / cron)
#   ./cleanup-workflow-history.sh --dry-run   # report only, no deletes
#
# Notes:
#   - Idempotent: re-running after success is a no-op.
#   - Pages through all runs (gh api caps at 100/page). Hard cap at
#     30 pages per repo to bound runtime on noisy repos.
#   - DELETE is irreversible. Logs/artifacts/step timings cannot be
#     recovered; the Actions UI shows a "deleted" placeholder. The
#     latest-success run for each workflow IS preserved precisely
#     because the recent-success badge depends on it.

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

# Pull every workflow run id+conclusion+workflow_id+created_at for a repo
# across all pages, emit one TSV line per run on stdout.
list_all_runs() {
  local repo="$1"
  local page=1
  while true; do
    local data
    data=$(gh api "repos/$repo/actions/runs?per_page=100&page=$page" 2>/dev/null || echo '{"workflow_runs":[]}')
    local count
    count=$(echo "$data" | jq -r '.workflow_runs | length')
    [ "$count" = "0" ] && break

    echo "$data" | jq -r '.workflow_runs[] | [.id, .workflow_id, .conclusion // "running", .created_at] | @tsv'

    [ "$count" -lt 100 ] && break
    page=$((page + 1))
    [ "$page" -gt 30 ] && break
  done
}

# Given the TSV stream from list_all_runs, output "keep" or "delete"
# per id according to the retention policy. Keep = id of the latest
# success per workflow_id. Delete = everything else.
plan_for_repo() {
  awk -F'\t' '
    {
      id=$1; wf=$2; concl=$3; ts=$4;
      runs[NR]=id"\t"wf"\t"concl"\t"ts;
      if (concl == "success") {
        if (!(wf in latest_ts) || ts > latest_ts[wf]) {
          latest_ts[wf] = ts;
          latest_id[wf] = id;
        }
      }
    }
    END {
      for (i=1; i<=NR; i++) {
        n = split(runs[i], r, "\t");
        id = r[1]; wf = r[2]; concl = r[3];
        if (concl == "success" && latest_id[wf] == id) {
          print "keep\t" id "\t" wf "\t" concl;
        } else {
          print "delete\t" id "\t" wf "\t" concl;
        }
      }
    }
  '
}

echo "Scanning workflow runs across ${#REPOS[@]} repos..."
echo
echo "Retention: keep the most recent SUCCESS run per distinct workflow."
echo "Delete: failures, cancellations, AND older successes."
echo
printf "%-32s %-7s %-7s %-7s\n" "repo" "total" "keep" "delete"
printf "%-32s %-7s %-7s %-7s\n" "$(printf '%.0s-' {1..32})" "-----" "----" "------"

# First pass: build per-repo plans into temp files for execution + display
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

total_delete=0
total_keep=0
for repo in "${REPOS[@]}"; do
  plan_file="$TMP_DIR/$(echo "$repo" | tr '/' '_').plan"
  list_all_runs "$repo" | plan_for_repo > "$plan_file"

  total=$(wc -l < "$plan_file" | tr -d ' \n')
  keep=$( { grep -c '^keep' "$plan_file" 2>/dev/null || true; } | head -1 | tr -d ' \n')
  delete=$( { grep -c '^delete' "$plan_file" 2>/dev/null || true; } | head -1 | tr -d ' \n')
  [ -z "$total" ] && total=0
  [ -z "$keep" ] && keep=0
  [ -z "$delete" ] && delete=0

  printf "%-32s %-7s %-7s %-7s\n" "$repo" "$total" "$keep" "$delete"
  total_delete=$((total_delete + delete))
  total_keep=$((total_keep + keep))
done

echo
echo "Total to keep:   $total_keep"
echo "Total to delete: $total_delete"

if [ "$DRY_RUN" = "1" ]; then
  echo
  echo "[dry-run] Detailed keep list:"
  for repo in "${REPOS[@]}"; do
    plan_file="$TMP_DIR/$(echo "$repo" | tr '/' '_').plan"
    if grep -q '^keep' "$plan_file" 2>/dev/null; then
      echo
      echo "  $repo:"
      grep '^keep' "$plan_file" | while IFS=$'\t' read -r action id wf concl; do
        printf "    keep run=%s workflow=%s\n" "$id" "$wf"
      done
    fi
  done
  echo
  echo "[dry-run] No changes made."
  exit 0
fi

if [ "$total_delete" = "0" ]; then
  echo "Nothing to delete."
  exit 0
fi

if [ "$ASSUME_YES" != "1" ]; then
  echo
  read -r -p "Delete $total_delete runs (keep $total_keep)? [y/N] " confirm
  case "$confirm" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

echo
for repo in "${REPOS[@]}"; do
  plan_file="$TMP_DIR/$(echo "$repo" | tr '/' '_').plan"
  delete_count=$( { grep -c '^delete' "$plan_file" 2>/dev/null || true; } | head -1 | tr -d ' \n')
  [ -z "$delete_count" ] && delete_count=0
  [ "$delete_count" = "0" ] && continue

  echo "=== $repo (deleting $delete_count) ==="
  deleted=0
  failed=0
  while IFS=$'\t' read -r action id wf concl; do
    if gh api -X DELETE "repos/$repo/actions/runs/$id" >/dev/null 2>&1; then
      deleted=$((deleted + 1))
    else
      failed=$((failed + 1))
    fi
  done < <(grep '^delete' "$plan_file")

  if [ "$failed" -gt 0 ]; then
    echo "  deleted: $deleted, failed: $failed"
  else
    echo "  deleted: $deleted"
  fi
done

echo
echo "Done. Verify with: $0 --dry-run"
