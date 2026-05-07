# Self-hosted GitHub Actions Runner — Synology Container Manager

Pilot scope: chrono-synth-os only (most active repo, pure Linux jobs).
Other repos can join later by changing `REPO_URL` in `.env` and restarting,
or by deploying a parallel container with `RUNNER_SUFFIX=2`.

> ⚠️ **Synology DSM kernel requirement**: this compose file targets DSM 7.2+
> machines whose kernel is **4.4 or newer** (DS923+, DS1522+, DS1621+, etc.).
> Older boxes like the **DS916+ (kernel 3.10.108)** lack the `getrandom(2)`
> syscall that modern git in the runner container relies on; jobs will fail
> with `error: unable to get random bytes for temporary file: Function not
> implemented`. Run `uname -r` on the NAS first; if you see 3.10.x or 3.x,
> use the native macOS runner under `macos/` instead.

## What this gives us

- ✅ CI minutes from chrono-synth-os no longer count against the GitHub free tier
- ⚠️ Storage (artifacts, cache, logs) and Packages traffic still bill normally
- ⚠️ Runner has Docker socket access — only safe because all 4 repos are PRIVATE
- ⚠️ Synology box electricity + network are now part of the dev infra footprint

## One-time setup on the Synology

### 1. Install Container Manager (DSM 7.x)

DSM Package Center -> search "Container Manager" -> Install.
Older DSM 6 / Docker package don't support compose v2 properly.

### 2. Upload this folder

Via File Station, upload the entire `selfhosted-runner/` directory to:

```
/volume1/docker/chrono-gha-runner/
```

The contents you should see there:

```
docker-compose.yml
.env.example
.gitignore
README.md   (this file)
```

### 3. Get a registration token from GitHub

This is the only secret you need. It's one-time and short-lived (1 hour).

1. Open https://github.com/Wontlost-LTD/chrono-synth-os
2. Settings -> Actions -> Runners -> **New self-hosted runner**
3. OS: Linux. Architecture: **x64**.
4. Scroll to the "Configure" section. The line that looks like:
   ```
   ./config.sh --url https://github.com/Wontlost-LTD/chrono-synth-os --token AAAA...
   ```
   The `AAAA...` part is the registration token. Copy it.

### 4. Create `.env`

SSH to the NAS or use File Station to copy `.env.example` -> `.env`,
edit, paste the token in `RUNNER_TOKEN=`. Save.

If you have SSH:

```bash
cd /volume1/docker/chrono-gha-runner
cp .env.example .env
nano .env   # paste RUNNER_TOKEN, save
```

### 5. Bring up the stack via Container Manager

DSM -> Container Manager -> **Project** -> **Create**:

- Project name: `chrono-gha-runner`
- Path: `/volume1/docker/chrono-gha-runner`
- Source: "Use existing docker-compose.yml" -> auto-detects the file
- Click Next, Next, Done.

Container Manager will pull the image (~200 MB), then start it.

### 6. Verify

Two checks:

**On the Synology**, Container Manager -> Container -> `chrono-gha-runner`
should show **Running** and the log should include lines like:

```
√ Connected to GitHub
√ Runner registered successfully!
√ Runner connection is good
√ Listening for Jobs
```

**On GitHub**, https://github.com/Wontlost-LTD/chrono-synth-os/settings/actions/runners
should show one runner named `synology-ds916-1` with status **Idle** and
the labels: `self-hosted`, `linux`, `x64`, `synology`.

If both show green, registration worked. From here on, no further token
swaps needed — the runner reauthenticates itself.

## Operating notes

### Triggering a job on the runner

Workflows already targeting `runs-on: ubuntu-latest` will *not* automatically
move to the self-hosted runner. We patch one workflow at a time, switching
to:

```yaml
runs-on: [self-hosted, linux, x64, synology]
```

The pilot patch lands as a separate commit, so you can roll back fast if
the runner misbehaves.

### Watching it work

- Live job logs: GitHub UI -> Actions tab on the repo
- Runner-side logs: DSM Container Manager -> Container -> Logs
- Resource use: DSM Resource Monitor (or `docker stats` over SSH)

### Stopping

Container Manager -> Container -> Stop. The runner sends a deregister
request on SIGTERM, so GitHub UI will mark it Offline within a minute.

### Adding more repos

Two ways:

(a) **Switch the existing runner** (simpler, one repo at a time):
edit `.env`, change `REPO_URL`, restart the container. The old
registration is automatically replaced when the runner re-registers
under the new URL.

(b) **Run multiple runners in parallel** (better for parallelism): copy
the folder to `/volume1/docker/chrono-gha-runner-web/`, set
`RUNNER_SUFFIX=2` and a different `REPO_URL`, deploy as a second
project.

Org-scoped runners (one runner serves all 4 repos) are an option but
require an org-level admin token; we'll evaluate after the pilot.

### Updating the runner version

Edit `docker-compose.yml`, bump the image tag (e.g. `2.328.0` -> the
latest from https://github.com/myoung34/docker-github-actions-runner/pkgs/container/github-runner),
restart. The cache volume persists across version bumps.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Container restart loop, log says "token expired" | Token is older than 1 hour | Get a fresh token from step 3, paste, restart |
| Container Manager shows runner Online but GitHub UI shows Offline | Outbound HTTPS blocked | Check Synology firewall + DNS to github.com |
| Job stuck in queued state for >2 min | Workflow's labels don't match runner's | Verify `runs-on:` includes all the labels we register with |
| `docker build` step fails with permission denied on /var/run/docker.sock | Synology user not in docker group | SSH in, run `sudo synogroup --member docker $USER` (DSM-version-dependent) |
| `npm ci` very slow on first run | Cache volume empty | Expected — second run will hit the cache |
| Job runs to completion but GitHub UI never marks the runner Online again | Ephemeral mode worked; Container Manager should restart shortly | Wait 30 sec; if not, check the container's restart policy |
