# macOS self-hosted runner — Apple Silicon MBP

This is the working alternative after Synology DS916+ (kernel 3.10.108)
turned out to be too old for the modern runner image (missing `getrandom(2)`
syscall).

Native macOS runner avoids the syscall issue entirely, runs at full
Apple Silicon speed, and doesn't need Docker.

## What you get

- Runner registered against `Wontlost-LTD/chrono-synth-os`
- Labels: `self-hosted, macos, arm64, mbp`
- Auto-starts at login via launchd
- Lives in `~/actions-runner-chrono-os/` (isolated from any other tooling)

## Trade-offs vs. Synology

| Dimension | Synology (didn't work) | MBP M1 native |
|---|---|---|
| Always-on | ✅ | ❌ Only when MBP is awake + logged in |
| CPU during dev | ✅ Doesn't compete | ⚠️ Will compete during a CI run |
| Speed | n/a | ⚡️ M1 ≈ 3-5× a GitHub-hosted Ubuntu runner |
| Setup complexity | High (compose + docker.sock) | Low (single binary + launchd) |
| Power cost | Always-on but tiny | Negligible (sleeps when MBP sleeps) |

If a CI run starts while you're using the MBP, you'll feel a fan ramp.
launchd doesn't support nice/ionice configs for runner workloads in the
GitHub-published plist, but the runner's own .NET process plays well
with macOS's QoS system: foreground apps stay responsive.

## Install

### 1. Get a registration token

Open https://github.com/Wontlost-LTD/chrono-synth-os/settings/actions/runners/new
in your browser. The "Configure" section shows a command like:

```
./config.sh --url https://github.com/Wontlost-LTD/chrono-synth-os --token AAAAAAAAA...
```

Copy the part after `--token`. Token expires in 1 hour; do this right
before running the install script.

### 2. Run the installer

```bash
cd /Users/rpang/IdeaProjects/chrono-synth-deploy/selfhosted-runner/macos
./install.sh <PASTE_TOKEN_HERE>
```

It downloads actions/runner v2.328.0, extracts to
`~/actions-runner-chrono-os`, and registers.

### 3. Install + start the launchd service

```bash
cd ~/actions-runner-chrono-os
./svc.sh install
./svc.sh start
./svc.sh status
```

### 4. Verify

GitHub UI:
https://github.com/Wontlost-LTD/chrono-synth-os/settings/actions/runners

Should show `Pang-chrono-os` (or whatever your hostname is) with status
**Idle** and labels `self-hosted, macos, arm64, mbp`.

### 5. Switch the workflow to use it

Repository variable (Settings → Variables → Actions):

- Name:  `CI_RUNNER_LABELS`
- Value: `["self-hosted","macos","arm64","mbp"]`

Effective on the next push.

## Day-2 ops

### Watch logs

```bash
# Live tail of the runner's stdout
tail -f ~/Library/Logs/actions.runner.*.log

# Or via the svc helper
~/actions-runner-chrono-os/svc.sh status
```

### Stop temporarily (e.g., heavy battery usage during travel)

```bash
~/actions-runner-chrono-os/svc.sh stop
```

The runner shows up as **Offline** in GitHub UI; jobs queue until you
restart it (or delete the `CI_RUNNER_LABELS` variable to fall back to
GitHub-hosted).

```bash
~/actions-runner-chrono-os/svc.sh start
```

### Remove cleanly

1. Get a *removal* token (different from registration token):
   GitHub UI → the runner's row → ⋯ → Remove → copy the token from the
   shown command.
2. Run:
   ```bash
   cd /Users/rpang/IdeaProjects/chrono-synth-deploy/selfhosted-runner/macos
   ./uninstall.sh <REMOVAL_TOKEN>
   ```

### Adding more repos

Either:
- (a) Repeat install with a different `RUNNER_DIR` (edit script's
      `RUNNER_DIR` and `RUNNER_NAME`), or
- (b) Use an org-scoped runner (one runner serves all 4 chrono repos);
      requires an admin to register at the org level. Recommended once
      the pilot is stable.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Job stuck "queued", no runner picks it up | `CI_RUNNER_LABELS` mismatch | Verify variable value matches what install registered |
| Runner shows Offline in GitHub UI but `svc.sh status` says running | Network blip or GitHub side | Restart: `svc.sh stop && svc.sh start` |
| Permission errors on first run | macOS Gatekeeper quarantined the binary | `xattr -dr com.apple.quarantine ~/actions-runner-chrono-os` |
| Job fails on `actions/setup-node@v6` | First run downloads Node into runner cache | Re-run; second time hits the cache |
| MBP sleeps during long-running job | macOS sleep | System Settings → Battery → "Prevent automatic sleeping when display off" + plug in |
