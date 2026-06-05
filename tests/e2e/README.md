# Containerized E2E for the SystemdUser backend

`tests/systemd_lifecycle.rs` is a real integration test against `systemctl
--user` (install → start → Running → marker → restart → logs → stop). It is
gated behind `DG_E2E=1` so it never runs during a normal `cargo test` on a dev
machine that lacks a user systemd instance.

This directory boots a containerized environment that *does* have one, then
runs that test inside it.

## Run it

From the crate root:

```sh
bash tests/e2e/run.sh
```

It exits `0` on success (the test prints `DG_E2E_PASS`) and non-zero on
failure, dumping the captured test output so you can see why.

## How it works

- `Dockerfile` builds an `ubuntu:24.04` image with `systemd`, `systemd-sysv`,
  `dbus-user-session`, and `cargo`/`rustc`. It creates a test user `dg` with
  uid **1001** (uid 1000 is already taken by ubuntu:24.04's default `ubuntu`
  user) and enables lingering so `dg`'s `systemd --user` manager starts at
  boot — no interactive login required. It also prebuilds the test binary into
  the image so the actual run is fast.
- `run.sh` builds the image, runs it as a daemon with **`--privileged
  --cgroupns=host`** (the only combo verified to give a working PID-1 systemd
  inside Docker Desktop), waits for `systemctl is-system-running` to be
  `running`/`degraded` **and** for `/run/user/1001/bus` to exist, then runs the
  gated test via `docker exec -u dg -e DG_E2E=1`. The container is killed and
  removed on exit.

## Requirements

- Docker (Desktop or engine) with privileged containers permitted.
- The host kernel must support cgroups v2 (Docker Desktop on macOS and most
  modern Linux distros already do).

## Why not run the test directly on the host?

Because macOS dev machines don't have `systemctl --user`, and most CI Linux
runners don't have a logged-in user with lingering enabled. The container
gives the test a deterministic, real `systemd --user` to talk to.
