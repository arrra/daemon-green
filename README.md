# daemon-green

Cross-platform per-user background **service** management for Rust. One
trait, two native backends, zero external dependencies.

- **macOS** → per-user **gui-domain LaunchAgent** (`launchctl bootstrap
  gui/<uid>`), so your service runs inside the user's login session and can
  reach the **login keychain**. We deliberately **do not** set `SessionCreate`
  — it detaches the service from the login session and blocks keychain access.
- **Linux** → **`systemd --user`** unit, with `XDG_RUNTIME_DIR` /
  `DBUS_SESSION_BUS_ADDRESS` plumbed and lingering supported.

Both backends are **sudo-free** and work **over SSH** (as long as a login
session is active, which a desktop Mac always has). The macOS path is
hardened against the real footguns: it waits out the async `bootout` before
re-`bootstrap`ing, retries, and falls back to `launchctl asuser`. Logs come
from `~/Library/Logs/<label>.log` on macOS and from `journalctl --user` on
Linux.

## Usage

```rust
use daemon_green::{native, ServiceSpec};

let spec = ServiceSpec::new("com.example.myd", "/usr/local/bin/myd")
    .arg("serve")
    .env("MY_VAR", "1")
    .keep_alive(true)
    .run_at_load(true);

let mgr = native();
mgr.install(&spec)?;           // render unit + register (idempotent)
mgr.start(spec.label())?;      // bootstrap / enable
// ... later ...
mgr.restart(spec.label())?;
mgr.stop(spec.label())?;
# Ok::<(), daemon_green::Error>(())
```

The `ServiceManager` trait exposes `install` / `start` / `stop` / `restart` /
`status` / `logs`. `install` and `start` are idempotent — safe to call on
every app launch.

## What you get vs. just shelling out

- **No `SessionCreate` on macOS.** Many guides paste this in; it silently
  breaks keychain access. The plist renderer is unit-tested to keep it out.
- **XML-escaped plist rendering.** Labels and args with `<`/`>`/`&`/`"` /
  `'` don't blow up the plist.
- **R8-style robustness.** macOS `bootstrap` is retried after waiting for an
  in-flight `bootout` to actually drain, with an `asuser` fallback for the
  edge cases where the gui domain isn't reachable.
- **SSH-safe.** Both backends discover the right user / domain without
  needing an interactive shell.
- **Loud, actionable errors.** When `launchctl` / `systemctl` fail, you get
  the exact command, exit code, and stderr tail back — never a silent swallow.

## Testing

`cargo test` runs the pure renderer unit tests (no system side effects).

The systemd backend has a full lifecycle E2E gated behind `DG_E2E=1` — see
[`tests/e2e/README.md`](tests/e2e/README.md) for the containerized harness
(`bash tests/e2e/run.sh`). The harness boots real `systemd` in Docker and
drives `install → start → Running → restart → logs → stop` end-to-end through
`systemctl --user`.

## License

MIT.
