# Self-hosted Runner — Current Status (paused, awaiting spending limit)

Last updated: 2026-05-07 (deferred to next month)

## TL;DR

The org-scoped macOS runner is **fully working**. CI minutes are saving as
expected — measured ~18× speedup on the heaviest job (build-and-test:
14 min on GitHub Ubuntu → 45 s on M1 self-hosted). Resume from here next
month after the GitHub spending limit is raised.

## Whose status is what

### Working

- **Runner**: `Pang-wontlost-org` (org-scoped, MBP M1)
  - Install dir: `~/actions-runner-wontlost-org`
  - launchd: `actions.runner.Wontlost-LTD.Pang-wontlost-org`
  - Labels: `self-hosted, macos, arm64, mbp, org`
  - Concurrency: 1 (default; can scale by registering a 2nd instance)
- **`CI_RUNNER_LABELS` repo variable** set on all 4 repos:
  `["self-hosted","macos","arm64","mbp"]`
- **12 jobs** routed to MBP (build-and-test, contract-and-kernel,
  typecheck, terraform fmt+tflint, terraform security-scan, license-check x2,
  sbom x2)
- **NPM cache removed** from setup-node everywhere (was uploading 3.66 GB
  per job to GitHub cache server, causing 10+ minute post-steps on
  self-hosted)

### Pinned to ubuntu-latest (intentional)

| Job | Repo | Why |
|---|---|---|
| docker-build | os, web | buildx requires buildkit; macOS uses podman, no buildkit |
| test-postgres | os | `services:` is Linux-only |
| perf | os | uses `services: redis` (Linux-only) |
| codeql | os, web | CodeQL Linux-only |
| secrets-scan (trufflehog) | os, web | trufflehog action runs `docker run`; no docker CLI on macOS |
| e2e, a11y | web | Playwright works on macOS but adds setup cost; defer |
| tauri-build | desktop | apt-get installs Linux system libs (webkit2gtk, sqlcipher); Linux build path |
| build matrix | desktop | release.yml matrix targets multi-OS already |
| release.yml build-and-push | os, web | docker push to ghcr.io |
| terraform plan | deploy | uses AWS OIDC role; don't want cloud creds on dev machine |
| ci validate | deploy | installs kustomize via sudo to /usr/local/bin |

### Blocked (you, next month)

**Raise GitHub spending limit** to $5/mo at
https://github.com/settings/billing/spending_limit

Currently every run hits at least one ubuntu-latest job, and those fail
instantly with: `The job was not started because recent account payments
have failed or your spending limit needs to be increased.`

This affects: any push to any repo. Once raised, the hybrid CI is fully
operational.

## How to verify everything still works after a month

1. **Runner alive?**

   ```bash
   ~/actions-runner-wontlost-org/svc.sh status
   gh api orgs/Wontlost-LTD/actions/runners --jq '.runners[].status'
   # Both should report online/Started.
   ```

2. **Push something trivial:**

   ```bash
   cd /Users/rpang/IdeaProjects/chrono-synth-os
   git commit --allow-empty -m "ci: smoke after self-hosted resume"
   git push origin main
   gh run watch
   ```

   Expected: build-and-test + contract-and-kernel run on MBP (~1 min total),
   docker-build + test-postgres run on ubuntu-latest (~2 min total).

3. **If runner is offline:**

   ```bash
   ~/actions-runner-wontlost-org/svc.sh start
   ```

   If service is gone (rare; macOS update can wipe LaunchAgent dirs):

   ```bash
   /Users/rpang/IdeaProjects/chrono-synth-deploy/selfhosted-runner/macos/uninstall-org.sh
   /Users/rpang/IdeaProjects/chrono-synth-deploy/selfhosted-runner/macos/install-org.sh
   cd ~/actions-runner-wontlost-org && ./svc.sh install && ./svc.sh start
   ```

## Still on the runway (deferred, not blocking)

- **`tauri-build` to macOS native**: replace apt-get install with brew
  install (webkit comes for free on macOS), build the macOS .app
  directly. M1 native compile would be much faster. ~1h work.
- **Migrate `e2e` + `a11y` to MBP**: install Playwright Chromium binary
  cache on host, then unpinning is one variable flip. ~30min.
- **Add 2nd runner for parallelism**: register another runner instance
  (different RUNNER_DIR + RUNNER_NAME) when queue depth becomes the
  bottleneck.
- **Org-level `CI_RUNNER_LABELS` variable**: set once at the org level
  instead of 4 repos. https://github.com/organizations/Wontlost-LTD/settings/variables/actions

## Measured speedups (smoke run 2026-05-07)

| Job | GitHub Ubuntu | M1 self-hosted | Speedup |
|---|---|---|---|
| build-and-test (os) | ~14 min | 45 s | 18× |
| contract-and-kernel (os) | ~5 min | 29 s | 10× |
| typecheck (desktop) | not measured | 18 s | n/a |
| SBOM (os, web) | ~1 min | 30 s | 2× |
| license-check (os, web) | ~1 min | 22 s | 2× |
| terraform fmt+tflint | ~1 min | 22 s | 2× |

Largest savings come from npm + tsc cold-start cost being amortized away
(MBP `~/.npm` is 14 GB warm cache, GitHub Ubuntu starts empty each run).

## Files of record

| File | Purpose |
|---|---|
| `selfhosted-runner/macos/install-org.sh` | Idempotent installer; mints token via `gh api` |
| `selfhosted-runner/macos/uninstall-org.sh` | Tears down launchd + deregisters |
| `selfhosted-runner/macos/README.md` | Operator runbook |
| `selfhosted-runner/docker-compose.yml` | (kept for future newer-NAS deploy) |
| `selfhosted-runner/STATUS.md` | This file |
