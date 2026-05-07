# Self-hosted Runner — Current Status (operational)

Last updated: 2026-05-08

## TL;DR

The org-scoped macOS runner is **fully working** and the GitHub spending
limit has been raised, so the hybrid CI is end-to-end green. Measured
speedups summarized below.

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

### Resolved 2026-05-08

- ✅ **GitHub spending limit raised** — ubuntu-latest jobs (docker-build,
  test-postgres, perf, codeql, tauri-build [release], terraform plan)
  now run cleanly.
- ✅ **`tauri-build` ported to MBP M1 native** — desktop ci.yml's
  tauri-build job now uses self-hosted MBP via OS-conditional steps
  (apt-get gated to Linux, `brew install sqlcipher` gated to macOS).
  build.yml matrix's macos-arm64 row also routed; release.yml stays
  on GitHub-hosted because it consumes APPLE_CERTIFICATE / signing
  secrets.
- ✅ **`a11y` ported to MBP** — web/security e2e.yml's a11y job
  (lightweight Playwright a11y suite) routed to self-hosted. The
  full e2e suite stays ubuntu-latest because the self-hosted
  concurrency=1 queue would bottleneck under frequent pushes.

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

- **Migrate `e2e` to MBP**: not done deliberately. Full Playwright
  e2e suite is 5-10 min and would dominate the concurrency=1
  self-hosted queue if pushed frequently. Ubuntu-latest's parallel
  capacity is the better fit. Reconsider if push frequency drops.
- **Add 2nd runner for parallelism**: register another runner instance
  (different RUNNER_DIR + RUNNER_NAME) when queue depth becomes the
  bottleneck. Today's queue rarely exceeds 1.
- **Org-level `CI_RUNNER_LABELS` variable**: set once at the org level
  instead of 4 repos. https://github.com/organizations/Wontlost-LTD/settings/variables/actions

## Measured speedups

Numbers from smoke runs on 2026-05-07/08.

| Job | Repo | GitHub Ubuntu | M1 self-hosted | Speedup |
|---|---|---|---|---|
| build-and-test | os | ~14 min | 44 s | ~18× |
| contract-and-kernel | os | ~5 min | 28 s | ~10× |
| docker-build | os | 2m 6s | (stays GH) | — |
| test-postgres | os | 2m 3s | (stays GH) | — |
| tauri-build | desktop | ~6-7 min | 2m 50s (cold) | ~3× |
| typecheck | desktop | not measured | 17 s | — |
| a11y | web | not measured | 47 s | — |
| SBOM | os, web | ~1 min | 30 s | ~2× |
| license-check | os, web | ~1 min | 22 s | ~2× |
| terraform fmt+tflint | deploy | ~1 min | 22 s | ~2× |

Largest savings come from npm + tsc + cargo cold-start cost being
amortized away (MBP has a warm `~/.npm`, persistent `node_modules`,
and persistent `src-tauri/target/`; GitHub Ubuntu starts empty each
run). Per push: ~20 min of cumulative GitHub-hosted Ubuntu time
shifted to local hardware.

## Files of record

| File | Purpose |
|---|---|
| `selfhosted-runner/macos/install-org.sh` | Idempotent installer; mints token via `gh api` |
| `selfhosted-runner/macos/uninstall-org.sh` | Tears down launchd + deregisters |
| `selfhosted-runner/macos/README.md` | Operator runbook |
| `selfhosted-runner/docker-compose.yml` | (kept for future newer-NAS deploy) |
| `selfhosted-runner/STATUS.md` | This file |
