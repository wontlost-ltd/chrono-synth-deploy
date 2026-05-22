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
PROJECTS_DIR="$ROOT/argocd/projects"

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
  if ! grep -qE "issuer:[[:space:]]+https://token\.actions\.githubusercontent\.com" "$sig_policy"; then
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
    if ! grep -qE "^[[:space:]]+-[[:space:]]+$base" "$kustomization"; then
      echo "✖ policy $base not referenced in kustomization.yaml"
      fail=1
    fi
  done < <(find "$POLICY_DIR" -maxdepth 1 -name "*.yaml" -print0)
fi

# 4) ArgoCD ApplicationSet wires the policy path AND uses a project
#    whose AppProject manifest exists and permits ClusterPolicy resources.
wired_appset=""
wired_project=""
if [[ -d "$ARGOCD_DIR" ]]; then
  while IFS= read -r -d '' appset; do
    if grep -qE "path:[[:space:]]+compliance/kyverno/policies" "$appset"; then
      wired_appset="$appset"
      wired_project=$(grep -E "^[[:space:]]+project:[[:space:]]+" "$appset" | head -n1 | sed -E 's/.*project:[[:space:]]+//; s/[[:space:]]*$//')
      echo "✓ ArgoCD ApplicationSet wires kyverno policies: $(basename "$appset") (project=$wired_project)"
      break
    fi
  done < <(find "$ARGOCD_DIR" -maxdepth 2 -name "*.yaml" -print0)
fi
if [[ -z "$wired_appset" ]]; then
  echo "✖ no ArgoCD ApplicationSet under $ARGOCD_DIR targets compliance/kyverno/policies"
  echo "  Resolution: add an ApplicationSet (see chrono-synth-compliance.yaml) that"
  echo "  fans out the policy bundle to every registered cluster."
  fail=1
elif [[ -n "$wired_project" ]]; then
  # 5) The referenced AppProject must exist and whitelist
  #    kyverno.io/ClusterPolicy. The chrono-synth project deliberately
  #    excludes CRDs, so the ApplicationSet must use a dedicated project.
  project_file=""
  if [[ -d "$PROJECTS_DIR" ]]; then
    while IFS= read -r -d '' candidate; do
      if grep -qE "^[[:space:]]+name:[[:space:]]+${wired_project}\$" "$candidate"; then
        project_file="$candidate"
        break
      fi
    done < <(find "$PROJECTS_DIR" -maxdepth 2 -name "*.yaml" -print0)
  fi
  if [[ -z "$project_file" ]]; then
    echo "✖ AppProject manifest missing for project=$wired_project (expected under $PROJECTS_DIR)"
    echo "  Resolution: create argocd/projects/${wired_project}.yaml or use an existing"
    echo "  project whose clusterResourceWhitelist permits kyverno.io/ClusterPolicy."
    fail=1
  else
    if ! grep -qE "[[:space:]]+kind:[[:space:]]+ClusterPolicy" "$project_file" \
       || ! grep -qE "[[:space:]]+group:[[:space:]]+kyverno\\.io" "$project_file"; then
      echo "✖ AppProject $(basename "$project_file") (name=$wired_project) does not whitelist kyverno.io/ClusterPolicy"
      echo "  Resolution: add { group: kyverno.io, kind: ClusterPolicy } to clusterResourceWhitelist."
      fail=1
    else
      echo "✓ AppProject $wired_project whitelists kyverno.io/ClusterPolicy"
    fi

    # 5a) RBAC discipline: the security-operator role must NOT have
    # `applications, override` — that permission lets an operator sync
    # arbitrary local manifests, bypassing the PR/CODEOWNERS audit
    # trail this AppProject was built around. Break-glass policy
    # disablement runs through cluster-admin escalation, not Argo override.
    if grep -qE "applications,[[:space:]]+override," "$project_file"; then
      echo "✖ AppProject $(basename "$project_file") grants 'applications, override' — bypasses Git/PR audit trail"
      echo "  Resolution: remove the override rule; document break-glass via cluster-admin escalation."
      fail=1
    else
      echo "✓ AppProject $wired_project does not grant applications/override"
    fi
  fi
fi

# 6) CODEOWNERS must claim the compliance paths so Git review actually
# gates policy changes (the whole point of refusing override above).
#
# GitHub's CODEOWNERS uses last-matching-rule-wins precedence. Specific
# compliance rules MUST appear AFTER any broader rule that covers their
# parent directory. The check below resolves the effective owner for
# each protected path by reading the file top-to-bottom and asserting
# that `@wontlost-ltd/security-operators` is the final declared owner.
codeowners="$ROOT/.github/CODEOWNERS"
if [[ ! -f "$codeowners" ]]; then
  echo "✖ missing $codeowners — security-operator review can't be enforced via PR without it"
  fail=1
else
  # Each protected path → its expected exact pattern in CODEOWNERS.
  # The pattern is what GitHub matches; we resolve to the last rule
  # whose pattern is a prefix-or-exact match for the protected path.
  required_paths=(
    "/compliance/"
    "/argocd/projects/chrono-synth-compliance.yaml"
    "/argocd/applicationsets/chrono-synth-compliance.yaml"
    "/scripts/lint-compliance.sh"
    "/.github/CODEOWNERS"
  )
  for path in "${required_paths[@]}"; do
    # Read CODEOWNERS, skip comments + blank lines, find the LAST rule
    # whose pattern prefixes `path` (CODEOWNERS uses gitignore-style
    # prefix matching for directories ending in /, exact match for files).
    effective=$(awk -v p="$path" '
      /^[[:space:]]*$/ { next }
      /^[[:space:]]*#/ { next }
      {
        pattern=$1
        # Strip from pattern: leading whitespace; nothing else needed.
        # gitignore-style: pattern ending in / matches directories;
        # otherwise exact match. We also handle the default "*" rule.
        if (pattern == "*") { match_found = 1; owners = ""; for (i=2;i<=NF;i++) owners = owners " " $i }
        else if (pattern ~ /\/$/) {
          if (substr(p, 1, length(pattern)) == pattern) { match_found = 1; owners = ""; for (i=2;i<=NF;i++) owners = owners " " $i }
        }
        else if (pattern == p) { match_found = 1; owners = ""; for (i=2;i<=NF;i++) owners = owners " " $i }
      }
      END { if (match_found) print owners }
    ' "$codeowners")
    if [[ -z "$effective" ]]; then
      echo "✖ CODEOWNERS has no rule covering: $path"
      fail=1
    elif [[ "$effective" != *"@wontlost-ltd/security-operators"* ]]; then
      echo "✖ CODEOWNERS effective owner for $path lacks @wontlost-ltd/security-operators: $effective"
      echo "  Resolution: move the compliance rules below any broader directory rules."
      fail=1
    else
      echo "✓ CODEOWNERS effectively claims $path with security-operators"
    fi
  done
fi

# 7) Break-glass runbook referenced by the compliance AppProject must
# actually exist in the repo, otherwise the controlled-disable path
# documented in the AppProject is vaporware.
runbook="$ROOT/docs/operations/policy-breakglass-runbook.md"
if [[ ! -f "$runbook" ]]; then
  echo "✖ missing $runbook — referenced by argocd/projects/chrono-synth-compliance.yaml"
  fail=1
else
  echo "✓ break-glass runbook present"
fi

if [[ $fail -ne 0 ]]; then
  echo ""
  echo "✖ kyverno compliance lint failed"
  exit 1
fi
echo "✓ kyverno compliance lint clean"
