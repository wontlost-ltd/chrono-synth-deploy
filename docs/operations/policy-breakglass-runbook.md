# Kyverno policy break-glass runbook

> Owner: `@wontlost-ltd/security-operators`
> Audience: SRE on-call + incident commander
> Last reviewed: 2026-05

## When to use

A Kyverno ClusterPolicy is admission-blocking a legitimate workload, and:

- the workload cannot be reshaped to satisfy the policy quickly enough
  to meet the incident SLA (e.g. customer-impacting outage), **and**
- the relevant ApplicationSet's `applications, override` permission has
  been deliberately removed (see
  `argocd/projects/chrono-synth-compliance.yaml`) so we cannot patch
  the policy from inside ArgoCD without going through Git review.

If neither applies, open a PR to relax / amend the policy via the
normal CODEOWNERS-gated flow instead.

## Authorisation

Break-glass requires **two** of:

1. The on-call incident commander (SEV1/SEV2 only).
2. A member of `@wontlost-ltd/security-operators`.
3. CTO or VP Eng (recorded escalation only).

A break-glass action MUST be paired with an incident ticket
(`INC-####`) and a JIRA `SEC-` ticket for the post-incident PR that
restores the policy to its enforced state.

## Procedure

1. **Capture evidence.** Before disabling anything, `kubectl get
   clusterpolicy <name> -o yaml > /tmp/cp.<name>.before.yaml` and
   attach it to the incident ticket.

2. **Disable the rule** via the cluster admin path (NOT ArgoCD):

   ```bash
   # Option A — set the policy to Audit mode (preferred; still emits PolicyReport).
   kubectl patch clusterpolicy <name> --type merge \
     -p '{"spec":{"validationFailureAction":"Audit"}}' \
     --as=cluster-admin-breakglass

   # Option B — delete the specific rule entry (use only if Audit is
   # not enough). Pipe the captured YAML through yq and re-apply.
   ```

3. **Suspend ArgoCD reconciliation** for the compliance Application on
   that cluster only:

   ```bash
   argocd app set chrono-synth-compliance-<cluster> \
     --sync-policy none \
     --self-heal false
   ```

   Without this, selfHeal will revert the live patch within seconds.

4. **Notify** in `#sec-incidents` with `INC-####` + the policy + the
   cluster + estimated duration.

5. **Open the restoration PR** within 24 hours. The PR MUST:
   - Re-enable Argo selfHeal: `argocd app set ... --sync-policy
     automated --self-heal true`.
   - Either restore the original policy unchanged, OR include the
     amended policy with CODEOWNERS approval from
     `@wontlost-ltd/security-operators`.

## What this runbook is NOT

- It is NOT a way to relax a policy long-term. Use the standard PR
  flow for that.
- It is NOT executable by a single operator. The two-person rule
  exists because admission policy disablement is a P0 audit event.
- It is NOT a workaround for image-signature failures
  (`require-image-signature` ClusterPolicy). Those go through
  `chrono-synth-os` release pipeline, not break-glass.
