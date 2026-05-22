#!/usr/bin/env bash
# GA Sprint 3 Step 7 — Kyverno compliance lint.
#
# Verifies:
#   1. compliance/kyverno/policies/ exists and contains at least the
#      load-bearing policies (verify-image-signature, disallow-host-path,
#      disallow-privileged, require-non-root, require-resource-limits).
#   2. verify-image-signature.yaml uses cosign keyless attestor + Rekor.
#   3. compliance/kyverno/policies/kustomization.yaml references every
#      .yaml policy file (no orphans).
#   4. At least one ArgoCD ApplicationSet under argocd/applicationsets/
#      targets `compliance/kyverno/policies` as its source path (so the
#      policies actually get applied to clusters).
#
# Exit 0 = clean. Exit 1 = at least one assertion failed.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
POLICY_DIR="$ROOT/compliance/kyverno/policies"
ARGOCD_DIR="$ROOT/argocd/applicationsets"

REQUIRED_POLICIES=(
  require-image-signature.yaml
  disallow-host-path.yaml
  disallow-privileged.yaml
  require-non-root.yaml
  require-resource-limits.yaml
  require-network-policy.yaml
)

fail=0

# 1) policy directory + required files exist
if [[ ! -d "$POLICY_DIR" ]]; then
  echo "✖ kyverno policies dir missing: $POLICY_DIR"
  exit 1
fi
for required in "${REQUIRED_POLICIES[@]}"; do
  if [[ ! -f "$POLICY_DIR/$required" ]]; then
    echo "✖ missing required policy: $required"
    fail=1
  fi
done

# 2) require-image-signature.yaml uses keyless + Rekor
sig_policy="$POLICY_DIR/require-image-signature.yaml"
if [[ -f "$sig_policy" ]]; then
  if ! grep -q "keyless:" "$sig_policy"; then
    echo "✖ $sig_policy must use cosign keyless attestor (missing 'keyless:' block)"
    fail=1
  fi
  if ! grep -q "rekor:" "$sig_policy"; then
    echo "✖ $sig_policy must reference Rekor transparency log (missing 'rekor:' block)"
    fail=1
  fi
  if ! grep -qE "issuer:\s+https://token\.actions\.githubusercontent\.com" "$sig_policy"; then
    echo "✖ $sig_policy must require GitHub Actions OIDC issuer"
    fail=1
  fi
fi

# 3) kustomization.yaml references every policy file
kustomization="$POLICY_DIR/kustomization.yaml"
if [[ ! -f "$kustomization" ]]; then
  echo "✖ missing $kustomization"
  fail=1
else
  while IFS= read -r -d '' policy_file; do
    base=$(basename "$policy_file")
    [[ "$base" == "kustomization.yaml" ]] && continue
    if ! grep -qE "^[[:space:]]+-\s+$base" "$kustomization"; then
      echo "✖ policy $base not referenced in kustomization.yaml"
      fail=1
    fi
  done < <(find "$POLICY_DIR" -maxdepth 1 -name "*.yaml" -print0)
fi

# 4) ArgoCD ApplicationSet wires the policy path
wired=0
if [[ -d "$ARGOCD_DIR" ]]; then
  while IFS= read -r -d '' appset; do
    if grep -qE "path:[[:space:]]+compliance/kyverno/policies" "$appset"; then
      wired=1
      echo "✓ ArgoCD ApplicationSet wires kyverno policies: $(basename "$appset")"
      break
    fi
  done < <(find "$ARGOCD_DIR" -maxdepth 2 -name "*.yaml" -print0)
fi
if [[ $wired -eq 0 ]]; then
  echo "✖ no ArgoCD ApplicationSet under $ARGOCD_DIR targets compliance/kyverno/policies"
  echo "  Resolution: add an ApplicationSet (see chrono-synth-compliance.yaml) that"
  echo "  fans out the policy bundle to every registered cluster."
  fail=1
fi

if [[ $fail -ne 0 ]]; then
  echo ""
  echo "✖ kyverno compliance lint failed"
  exit 1
fi
echo "✓ kyverno compliance lint clean"
