#!/usr/bin/env bash
# Render the chrono-synth helm chart and validate it can be consumed by
# podman play kube. Useful for sanity-checking that the K8s manifests
# remain transportable to non-K8s runtimes (catches things like missing
# Secret YAML, unsupported NetworkPolicy syntax, etc.).
#
# Prereqs:
#   - helm 3.x
#   - podman 5.x
#   - awk (filters out resource kinds podman doesn't support)
#
# Usage:
#   scripts/podman-render.sh             # parse only, don't start pods
#   scripts/podman-render.sh --start     # actually run the pods locally

set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="${TMPDIR:-/tmp}"
RENDERED="$OUT_DIR/chrono-rendered.yaml"
FILTERED="$OUT_DIR/chrono-rendered-podman.yaml"
SECRETS="$OUT_DIR/chrono-secrets.yaml"

helm template chrono-synth helm/chrono-synth \
  --set backend.image.tag=e2e \
  --set frontend.image.tag=e2e \
  > "$RENDERED"

# Strip Pod (helm test) + NetworkPolicy (podman partial support).
awk '
BEGIN { skip=0; doc="" }
/^---$/ {
  if (!skip && doc != "") print doc "---"
  doc=""; skip=0; next
}
/^kind: (Pod|NetworkPolicy)$/ { skip=1 }
{ doc = doc $0 "\n" }
END { if (!skip && doc != "") print doc }
' "$RENDERED" > "$FILTERED"

# Provide stub secrets the manifest references (real K8s deployments use
# external-secrets-operator or similar; podman E2E uses these dummies).
cat > "$SECRETS" <<'YAML'
apiVersion: v1
kind: Secret
metadata:
  name: chrono-synth-postgres
  namespace: chrono-synth
type: Opaque
stringData:
  connection-string: "postgres://chrono:chrono@chrono-postgres:5432/chrono"
---
apiVersion: v1
kind: Secret
metadata:
  name: chrono-synth-redis
  namespace: chrono-synth
type: Opaque
stringData:
  url: "redis://chrono-redis:6379"
YAML

echo "+ helm rendered → $RENDERED ($(wc -l < "$RENDERED") lines)"
echo "+ filtered      → $FILTERED ($(grep -c '^kind:' "$FILTERED") resources)"

# Always (re)create stub secrets first, then the workload.
podman play kube "$SECRETS" >/dev/null
echo "+ stub secrets installed"

START_FLAG="--start=false"
if [[ "${1:-}" == "--start" ]]; then START_FLAG=""; fi

podman play kube $START_FLAG "$FILTERED"
echo "+ manifests parsed by podman play kube"

if [[ "$START_FLAG" == "--start=false" ]]; then
  podman play kube --down "$FILTERED" >/dev/null
  echo "+ pods torn down (parse-only mode)"
fi
