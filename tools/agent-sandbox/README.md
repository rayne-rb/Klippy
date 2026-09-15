# Agent sandboxes

Isolated graphical sandboxes for autonomous agents. Each sandbox is a Docker
container with its own virtual X display (Xvfb), the openbox window manager, a
browser, and ffmpeg — so an agent can drive GUI apps, be recorded doing it, and
never touch the host desktop.

## One-command lifecycle

```sh
tools/agent-sandbox/sandbox create demo --record --vnc   # up (builds image on first run)
tools/agent-sandbox/sandbox exec demo xterm              # run anything in the session
tools/agent-sandbox/sandbox shot demo                    # screenshot -> out/
tools/agent-sandbox/sandbox record demo stop             # finalize out/session.mp4
tools/agent-sandbox/sandbox vnc demo info                # where to watch it live
tools/agent-sandbox/sandbox destroy demo --purge         # gone (files kept without --purge)
```

Options for `create`: `--screen WxHxD`, `--cpus N`, `--mem SIZE`, `--pids N`,
`--net none` (offline agent), `--record`, `--vnc`.

## Where things live

`$SANDBOX_HOME` (default `~/agent-sandboxes`), one directory per sandbox:

| Directory | Mount | Holds |
| --- | --- | --- |
| `out/` | `/output` | session recordings, screenshots, agent artifacts |
| `logs/` | `/logs` | ffmpeg logs, anything the agent logs |
| `home/` | `/home/agent` | the agent's home directory (browser profiles, etc.) |

## Isolation

- Docker container, non-root `agent` user, `no-new-privileges`, private PID
  namespace, tmpfs `/tmp`.
- CPU / memory / process limits via `--cpus` / `--memory` / `--pids-limit`
  (defaults 2 CPUs, 4 GB, 512 processes).
- Network defaults to the docker bridge (online); `--net none` gives a fully
  offline agent.
- Each sandbox has its own X display with its own Xauthority cookie, so
  sandboxes cannot draw into — or read — each other's screens.
- The only host-visible surface is the sandbox directory plus, if `--vnc` was
  given, a loopback-only VNC port for live human inspection
  (`vnc://127.0.0.1:<port>`, no password — reachable from this machine only).

## Notes

- The image is Debian trixie (not Ubuntu) because Ubuntu ships firefox as a
  snap, and snaps do not work inside containers. firefox-esr installs as a
  normal deb.
- Recording uses ffmpeg's x11grab on the virtual display, so it captures the
  true framebuffer (including the cursor) at up to the screen resolution.
- Two sandboxes can run at the same time; VNC ports are picked per name.
