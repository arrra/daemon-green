#!/usr/bin/env bash
# Containerized end-to-end test harness for daemon-green's SystemdUser backend.
#
# Builds the systemd-in-Docker image, boots it with --privileged --cgroupns=host
# (the only combo verified to give a working PID-1 systemd on Docker Desktop),
# waits for the test user's `systemd --user` manager to come up, then runs the
# gated `systemd_lifecycle` integration test inside the container as user `dg`
# via `docker exec`. Exits 0 only if the test exits 0 AND prints "DG_E2E_PASS".
#
# Usage: bash tests/e2e/run.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
IMAGE="daemon-green-e2e"

log() { printf '[e2e] %s\n' "$*" >&2; }
fail() { log "FAIL: $*"; exit 1; }

cleanup() {
    if [ -n "${CID:-}" ]; then
        docker kill "$CID" >/dev/null 2>&1 || true
        docker rm -f "$CID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

command -v docker >/dev/null 2>&1 || fail "docker not found in PATH"

log "building image: $IMAGE"
if ! docker build -f "$HERE/Dockerfile" -t "$IMAGE" "$ROOT" >&2; then
    fail "docker build failed"
fi

log "starting container (privileged + cgroupns=host)"
CID="$(docker run -d --privileged --cgroupns=host "$IMAGE")" \
    || fail "docker run failed"
log "container id: $CID"

# Wait up to ~45s for systemd to be running/degraded AND the user bus socket to
# appear at /run/user/1001/bus (created when dg's user manager starts).
log "waiting for systemd + user manager (uid 1001)"
ready=0
for i in $(seq 1 90); do
    state="$(docker exec "$CID" systemctl is-system-running 2>/dev/null || true)"
    if [ "$state" = "running" ] || [ "$state" = "degraded" ]; then
        if docker exec "$CID" test -S /run/user/1001/bus 2>/dev/null; then
            ready=1
            log "ready (system=$state, /run/user/1001/bus present) after ${i}x0.5s"
            break
        fi
    fi
    sleep 0.5
done
if [ "$ready" -ne 1 ]; then
    log "container failed to become ready; dumping journal tail:"
    docker exec "$CID" journalctl -n 80 --no-pager >&2 2>&1 || true
    fail "systemd / user manager not ready"
fi

# Run the gated lifecycle test as dg. Capture both stdout and exit code.
log "running systemd_lifecycle test as dg (DG_E2E=1)"
OUT_FILE="$(mktemp)"
trap 'rm -f "$OUT_FILE"; cleanup' EXIT
set +e
docker exec -u dg \
    -e DG_E2E=1 \
    -e XDG_RUNTIME_DIR=/run/user/1001 \
    "$CID" \
    bash -lc 'cd /home/dg/src && cargo test --test systemd_lifecycle -- --nocapture' \
    >"$OUT_FILE" 2>&1
RC=$?
set -e

cat "$OUT_FILE" >&2

if [ "$RC" -ne 0 ]; then
    fail "test exited with code $RC"
fi

if ! grep -q 'DG_E2E_PASS' "$OUT_FILE"; then
    fail "test output missing DG_E2E_PASS sentinel"
fi

log "PASS: containerized systemd --user lifecycle E2E green"
exit 0
