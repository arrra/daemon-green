# Containerized E2E for daemon-green's SystemdUser backend.
#
# Boots real systemd (PID 1), runs a lingering user manager for user `dg`, and
# executes the gated `systemd_lifecycle` integration test AS that user against
# the real `systemctl --user`. Build from the crate root:
#
#   docker build -f tests/e2e/Dockerfile -t daemon-green-e2e .
#
# Run (needs privileged + host cgroup ns for systemd in Docker Desktop):
#
#   docker run -d --privileged --cgroupns=host daemon-green-e2e
#
# The container's job is just to come up with a working user manager; the
# actual test is executed from the host via `docker exec` (see run.sh) so its
# exit code propagates cleanly.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        systemd systemd-sysv dbus-user-session cargo rustc ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    # strip units that hang / are useless in a container
    && find /etc/systemd/system /lib/systemd/system -name '*getty*' -exec rm -f {} + 2>/dev/null || true

# Test user with a FREE uid (uid 1000 is already taken by the default `ubuntu`
# user in ubuntu:24.04) + lingering enabled, so its `systemd --user` manager
# starts at boot without an interactive login.
RUN useradd -m -u 1001 -s /bin/bash dg \
    && mkdir -p /var/lib/systemd/linger && touch /var/lib/systemd/linger/dg

# Copy the crate source in and prebuild the test binary as dg (cache the
# compile in the image — the actual test run reuses this).
COPY . /home/dg/src
# Drop any host-side Cargo.lock — ubuntu:24.04 ships cargo 1.75 which only
# understands lockfile v3, but a recent host cargo may have written v4.
# As a library crate we don't need a pinned lockfile here.
RUN rm -f /home/dg/src/Cargo.lock && chown -R dg:dg /home/dg/src
USER dg
RUN cd /home/dg/src && cargo test --test systemd_lifecycle --no-run 2>&1 | tail -5
USER root

# systemd as PID 1.
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
