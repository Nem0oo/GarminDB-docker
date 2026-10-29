# garmindb-docker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Docker image + CI/CD that runs upstream GarminDB unmodified with a daily scheduled sync, as a data backup.

**Architecture:** Three small bash scripts (`sync.sh`, `healthcheck.sh`, `entrypoint.sh`) on top of a GarminDB wheel built from the upstream submodule; supercronic schedules `sync.sh`. Scripts read their paths from env vars with production defaults so they are testable on the host with a stub `garmindb_cli.py`.

**Tech Stack:** bash, flock (util-linux), supercronic v0.2.51, python:3.12-slim, GarminDB v3.9.0 (upstream submodule), GitHub Actions, Dependabot.

**Spec:** `docs/superpowers/specs/2026-10-30-garmindb-docker-design.md`

## Global Constraints

- Submodule URL: `https://github.com/tcgoetz/GarminDB.git`, pinned to tag `v3.9.0`. No local patches.
- No `libfaketime`, FastAPI, matplotlib or `garminconnect` in the image.
- Sync command, verbatim: `garmindb_cli.py --all --download --import --analyze --latest`
- `SYNC_SCHEDULE` default `0 4 * * *`; `MAX_AGE_HOURS` default `36`; timezone from `TZ`.
- Container paths: config `/root/.GarminDb`, data `/root/HealthData`, success marker `/root/HealthData/last_success` (ISO 8601), lock `/tmp/sync.lock`, start marker `/tmp/started_at`.
- No sync on container start.
- Image name `garmindb-docker`; tags `latest` and `previous`. Secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, `N8N_WEBHOOK_ID`.
- Script env overrides (for tests): `HEALTHDATA_DIR`, `LOCK_FILE`, `STARTED_AT_FILE`, `GARMINDB_CLI`, `CRONTAB_FILE`.

## Review Focus

1. Sync fails (Garmin auth expired, network down) → `last_success` must keep its old value and the exit code must be non-zero so supercronic logs the failure. (Task 1 test `failure_keeps_last_success`.)
2. A manual `sync-now` while the 04:00 run is in progress → second run exits 0 immediately with a message, no second GarminDB process. (Task 1 test `concurrent_run_skipped`.)
3. Container restarted daily by watchtower/n8n redeploys → healthcheck must still go unhealthy if syncs keep failing; the grace period applies only when `last_success` is missing, never resets an existing stale one. (Task 2 test `stale_success_unhealthy_even_after_restart`.)
4. Garbage in `last_success` (empty / truncated file) → treated as unhealthy, not a script crash that reports healthy. (Task 2 test `corrupt_last_success_unhealthy`.)
5. `SYNC_SCHEDULE` containing spaces passed through compose → crontab line is exactly `<schedule> /usr/local/bin/sync.sh`. (Task 3 test `crontab_from_schedule`.)

---

### Task 1: Repo skeleton + `sync.sh`

**Files:**
- Create: `.gitmodules`, `GarminDB/` (submodule), `scripts/sync.sh`, `tests/lib.sh`, `tests/test_sync.sh`, `tests/run.sh`, `.gitignore`

**Interfaces:**
- Produces: `scripts/sync.sh` (no args). Exit 0 on success or when skipped by the lock; exit = GarminDB's code on failure. Writes `$HEALTHDATA_DIR/last_success` with `date -Iseconds` on success.
- Produces: `tests/lib.sh` with `assert_eq <expected> <actual> <msg>`, `assert_file <path>`, `assert_no_file <path>`, `make_stub_cli <dir> <exit_code> [sleep_seconds]` (writes an executable stub that records its args to `<dir>/cli_args` then sleeps/exits), and `tests/run.sh` that runs every `tests/test_*.sh` and exits non-zero if any fails.

- [ ] **Step 1: Init submodule**

```bash
git submodule add https://github.com/tcgoetz/GarminDB.git GarminDB
git -C GarminDB checkout v3.9.0
git submodule update --init --recursive
```
Expected: `git submodule status` shows `v3.9.0`.

- [ ] **Step 2: Write `tests/lib.sh`, `tests/run.sh`, and failing tests in `tests/test_sync.sh`**

Each test runs in a fresh `mktemp -d` with `HEALTHDATA_DIR`, `LOCK_FILE`, `GARMINDB_CLI` pointing inside it.
- `success_writes_last_success`: stub exit 0 → script exit 0, `last_success` exists and parses with `date -d`; `cli_args` equals `--all --download --import --analyze --latest`.
- `failure_keeps_last_success`: pre-write `last_success` = `2026-01-01T00:00:00+00:00`, stub exit 3 → script exit 3, file content unchanged.
- `failure_without_previous`: stub exit 1 → exit 1, no `last_success`.
- `concurrent_run_skipped`: stub sleeps 3s; start script in background, start second one 0.5s later → second exits 0 within 1s and its output contains `already running`; stub invoked once.

- [ ] **Step 3: Run tests, verify they fail**

Run: `bash tests/run.sh`
Expected: FAIL (`scripts/sync.sh` missing).

- [ ] **Step 4: Implement `scripts/sync.sh`**

`set -euo pipefail`; defaults `HEALTHDATA_DIR=/root/HealthData`, `LOCK_FILE=/tmp/sync.lock`, `GARMINDB_CLI=garmindb_cli.py`. Use `exec 9>"$LOCK_FILE"; flock -n 9 || { echo "sync already running, skipping"; exit 0; }`. Log start/end with timestamps. Capture the CLI exit code without `set -e` aborting; write `last_success` via temp file + `mv` (atomic) only on 0.

- [ ] **Step 5: Run tests, verify they pass**

Run: `bash tests/run.sh` → all PASS.

- [ ] **Step 6: Commit**

```bash
git add .gitmodules GarminDB scripts/sync.sh tests .gitignore
git commit -m "feat: GarminDB submodule and sync script with lock"
```

### Task 2: `healthcheck.sh`

**Files:**
- Create: `scripts/healthcheck.sh`, `tests/test_healthcheck.sh`

**Interfaces:**
- Consumes: `last_success` format from Task 1; `tests/lib.sh`.
- Produces: `scripts/healthcheck.sh` → exit 0 healthy, 1 unhealthy, one-line reason on stdout. Env: `HEALTHDATA_DIR`, `STARTED_AT_FILE` (default `/tmp/started_at`, holds epoch seconds), `MAX_AGE_HOURS` (36).

- [ ] **Step 1: Write failing tests**

- `recent_success_healthy`: `last_success` = now − 1h → exit 0.
- `stale_success_unhealthy_even_after_restart`: `last_success` = now − 40h, `started_at` = now − 1min → exit 1.
- `missing_success_grace_period`: no `last_success`, `started_at` = now − 1h → exit 0.
- `missing_success_after_grace`: no `last_success`, `started_at` = now − 37h → exit 1.
- `corrupt_last_success_unhealthy`: `last_success` empty, then `not-a-date` → exit 1 both.
- `max_age_override`: `MAX_AGE_HOURS=2`, `last_success` = now − 3h → exit 1.

- [ ] **Step 2: Run, verify fail** — `bash tests/run.sh` → healthcheck tests FAIL.

- [ ] **Step 3: Implement `scripts/healthcheck.sh`** with `date -d "$(cat file)" +%s`; any parse failure → unhealthy. Missing `started_at` with missing `last_success` → unhealthy.

- [ ] **Step 4: Run, verify pass** — `bash tests/run.sh` → all PASS.

- [ ] **Step 5: Commit** — `git commit -m "feat: healthcheck based on last successful sync"`

### Task 3: `entrypoint.sh` + Dockerfile

**Files:**
- Create: `scripts/entrypoint.sh`, `tests/test_entrypoint.sh`, `Dockerfile`, `.dockerignore`

**Interfaces:**
- Consumes: `/usr/local/bin/sync.sh`, `/usr/local/bin/healthcheck.sh` (copied by Dockerfile).
- Produces: `entrypoint.sh` writes `date +%s` to `$STARTED_AT_FILE`, writes `$CRONTAB_FILE` (default `/tmp/crontab`) containing `${SYNC_SCHEDULE:-0 4 * * *} /usr/local/bin/sync.sh`, then `exec "${SUPERCRONIC:-supercronic}" "$CRONTAB_FILE"`. `sync-now` = symlink `/usr/local/bin/sync-now → sync.sh`.

- [ ] **Step 1: Write failing tests** (stub `SUPERCRONIC` that echoes its args and exits 0)
- `crontab_default`: no `SYNC_SCHEDULE` → crontab is exactly `0 4 * * * /usr/local/bin/sync.sh`.
- `crontab_from_schedule`: `SYNC_SCHEDULE="30 2 * * 1-5"` → exactly `30 2 * * 1-5 /usr/local/bin/sync.sh`.
- `started_at_written`: file contains an integer within 5s of now.
- `execs_supercronic_with_crontab`: stub output equals the crontab path.

- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement `scripts/entrypoint.sh`.**
- [ ] **Step 4: Run, verify pass.**

- [ ] **Step 5: Write `Dockerfile`**

Stage 1 `python:3.12-slim AS wheel-builder`: copy `GarminDB/`, `pip install build && python -m build --wheel --outdir /dist`.
Stage 2 `python:3.12-slim`: install the wheel; download supercronic `v0.2.51` linux-amd64 from GitHub releases and verify with `sha1sum -c` against the SHA1 published on the release page (look it up at implementation time and hardcode it as `ARG SUPERCRONIC_SHA1SUM`); `util-linux` is already in slim (flock) — verify. Copy `scripts/*.sh` to `/usr/local/bin/`, symlink `sync-now`. `ENV SYNC_SCHEDULE="0 4 * * *" MAX_AGE_HOURS=36`. `HEALTHCHECK --interval=1h --timeout=10s CMD healthcheck.sh`. `ENTRYPOINT ["entrypoint.sh"]`. `.dockerignore`: `.git`, `docs`, `tests`.

- [ ] **Step 6: Verify image**

```bash
docker build -t garmindb-docker:test .
docker run --rm garmindb-docker:test which garmindb_cli.py sync-now flock supercronic
docker run --rm -e TZ=Europe/Paris -d --name gdb-test garmindb-docker:test
sleep 3; docker logs gdb-test        # supercronic shows schedule "0 4 * * *"
docker exec gdb-test healthcheck.sh  # exit 0 (grace period)
docker exec gdb-test sync-now; echo $?   # non-zero (no config), no last_success
docker exec gdb-test test ! -f /root/HealthData/last_success
docker rm -f gdb-test
```
Expected: as commented; no `faketime` in `docker run --rm garmindb-docker:test ls /usr/lib | grep -i faketime` (empty).

- [ ] **Step 7: Commit** — `git commit -m "feat: entrypoint with supercronic and Dockerfile"`

### Task 4: CI/CD, Dependabot, docs

**Files:**
- Create: `.github/workflows/build.yml`, `.github/workflows/test.yml`, `.github/dependabot.yml`, `docker-compose.example.yml`, `README.md`

**Interfaces:**
- Consumes: `tests/run.sh`, `Dockerfile`.

- [ ] **Step 1: `build.yml`** — copy `~/Projects/garmin-bridge/.github/workflows/build.yml`, rename to `Build garmindb-docker Image`, replace image `garmin-bridge` → `garmindb-docker` (3 places: pull, tag previous, build tags). Add a step `bash tests/run.sh` before login.
- [ ] **Step 2: `test.yml`** — on `pull_request`: checkout recursive, `bash tests/run.sh`, `docker build .` (no push). This is what validates Dependabot PRs before merge.
- [ ] **Step 3: `dependabot.yml`**

```yaml
version: 2
updates:
  - package-ecosystem: gitsubmodule
    directory: /
    schedule:
      interval: weekly
```

- [ ] **Step 4: `docker-compose.example.yml`** — exactly the compose block from the spec ("Exemple compose"), with `restart: unless-stopped`.
- [ ] **Step 5: `README.md`** (French) — purpose (CI/CD packaging of upstream GarminDB, no code changes), env vars table (`TZ`, `SYNC_SCHEDULE`, `MAX_AGE_HOURS`), volumes, `sync-now`, healthcheck meaning, the server setup section copied from the spec ("Mise en place sur le serveur"), required GitHub secrets.
- [ ] **Step 6: Verify** — `python3 -c "import yaml,sys;[yaml.safe_load(open(f)) for f in sys.argv[1:]]" .github/workflows/*.yml .github/dependabot.yml docker-compose.example.yml` → no error; `docker compose -f docker-compose.example.yml config` → valid.
- [ ] **Step 7: Commit** — `git commit -m "ci: build/push workflow, PR tests, dependabot; docs"`

### Task 5 (user, not agent): publish and deploy

Not automated — requires the user's accounts and server.
1. Create GitHub repo `Nem0oo/garmindb-docker`, add secrets, push `main`.
2. Check the Actions run pushes `garmindb-docker:latest`.
3. Server setup steps 1–4 from the spec.
