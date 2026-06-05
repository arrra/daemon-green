# Containerized E2E for daemon-green's SystemdUser backend.
# Boots real systemd (PID 1), runs a lingering user manager for user `dg`, and
# executes the gated `systemd_lifecycle` integration test AS that user against the
# real `systemctl --user`. Build from the crate root:
#   docker build -f tests/e2e/Dockerfile -t daemon-green-e2e .
# Run (needs privileged for systemd):
#   docker run --rm --privileged daemon-green-e2e
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        systemd systemd-sysv dbus-user-session cargo rustc ca-certificates sudo \
    && rm -rf /var/lib/apt/lists/* \
    # strip units that hang/are useless in a container
    && find /etc/systemd/system /lib/systemd/system -name '*getty*' -exec rm -f {} + 2>/dev/null || true

# Test user with a FIXED uid + lingering enabled (so its systemd --user manager
# starts at boot without an interactive login).
RUN useradd -m -u 1000 -s /bin/bash dg \
    && mkdir -p /var/lib/systemd/linger && touch /var/lib/systemd/linger/dg

# Build the test binary as dg (cache the compile in the image).
COPY . /home/dg/src
RUN chown -R dg:dg /home/dg/src
USER dg
RUN cd /home/dg/src && cargo test --test systemd_lifecycle --no-run 2>&1 | tail -5
USER root

# The oneshot that runs the e2e once the user manager is up, then powers off.
COPY tests/e2e/in-container.sh /usr/local/bin/in-container.sh
COPY tests/e2e/dg-e2e.service /etc/systemd/system/dg-e2e.service
RUN chmod +x /usr/local/bin/in-container.sh \
    && ln -sf /etc/systemd/system/dg-e2e.service /etc/systemd/system/multi-user.target.wants/dg-e2e.service \
    # dg needs passwordless sudo? No — in-container runs as root and drops to dg via sudo.
    && echo "dg ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/dg

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
