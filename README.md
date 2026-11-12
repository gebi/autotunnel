# autotunnel

Persistent `autossh` SOCKS tunnels as an instanceable systemd **user** unit.

## Install

    ./autotunnel install

Symlinks `autotunnel@.service` into `~/.config/systemd/user/` and `autotunnel` into
`~/.local/bin/`. (`autotunnel add` also does this if the unit isn't installed yet.)

## Usage

    autotunnel [status]                       # show all tunnels (default)
    autotunnel start|stop|restart NAME... | -a
    autotunnel enable|disable     NAME... | -a   # + start on login / don't; also starts/stops now
    autotunnel add [-n] [-f] NAME [PORT [DEST]]
    journalctl --user -u autotunnel@NAME -f

The TUNNEL column in `status` shows whether the tunnel actually works, beyond systemd's ACTIVE:
`up` (our ssh listens on LISTEN and a SOCKS connect through it reaches the remote), `stale`
(listening, but the remote doesn't answer within 3s), `down` (nothing listening, e.g. ssh still
connecting or failing auth), `conflict` (the port is held by another process).

`-a` means all tunnels: every configured one for start/restart/enable, every running one
for stop, every known one for disable.

`add` creates `~/.config/autotunnel/NAME.conf`:

- `PORT`: local SOCKS port or `addr:port` (default: the first free port from 1080 up, bound to 127.0.0.1)
- `DEST`: ssh destination, a host alias or `user@host` (default: NAME)
- `-n`: enable and start the tunnel right away
- `-f`: overwrite an existing conf

Example: `autotunnel add -n jump 1081 user@jumphost.example.com`

To keep tunnels running without being logged in: `loginctl enable-linger $USER`.

## Config

One file per tunnel: `~/.config/autotunnel/NAME.conf` (see `examples/example.conf`)

    LISTEN=127.0.0.1:1081
    DEST=user@jumphost.example.com
    # SSH_OPTS="-p 2222"   # optional extra ssh args

runs (after sourcing the keychain env, see below) `autossh -M 0 -N -o ExitOnForwardFailure=yes -o BatchMode=yes $SSH_OPTS -D $LISTEN $DEST`.
After editing a conf: `autotunnel restart NAME`.

## Notes

- `ControlMaster`, `ControlPath`, `ServerAliveInterval` are **not** overridden; they come
  from `~/.ssh/config`, so a tunnel acts as the mux master for other ssh sessions to the
  same host. `-M 0` only disables autossh's monitor port, not ssh multiplexing.
- When a tunnel restarts, sessions multiplexed over it drop too. If a master for the host
  already exists when the tunnel starts, the tunnel attaches to it as a mux client.
- `BatchMode=yes`: ssh never asks for a password or passphrase. Auth must work through
  the ssh-agent or an unencrypted key.

## ssh-agent

systemd user services don't inherit your login shell's `SSH_AUTH_SOCK`, and the agent that
systemd's environment points to may be a different one (e.g. `gcr-ssh-agent`, which shows
passphrase pop-ups). So the unit sources [keychain](https://www.funtoo.org/Keychain)'s
env file `~/.keychain/<hostname>-sh` before starting autossh, and reuses the same agent as
your shells.

- If the file doesn't exist yet (keychain not run since boot), the service fails and
  systemd retries every 10s until it does.
- The agent is read at service start. If keychain starts a new agent, restart the tunnels.
- Without keychain: set `KEYCHAIN_ENV=` (empty) in the conf and `SSH_AUTH_SOCK=/path/to/agent.sock`
  instead, or point `KEYCHAIN_ENV` at any sh file that exports `SSH_AUTH_SOCK`.

## Future improvements

- **Optional socket activation** (opt-in per tunnel, e.g. `ACTIVATION=socket` in the conf):
  `ssh -D` can't use a socket systemd already opened, so put `systemd-socket-proxyd` in front.
  `autotunnel-proxy@NAME.socket` listens on `LISTEN` and starts the proxy, which `Requires=`
  `autotunnel@NAME` running on an internal port (e.g. port+10000). The tunnel gets
  `StopWhenUnneeded=yes` plus an `ExecStartPost=` wait until its port is listening, and the
  proxy uses `--exit-idle-time=` so idle tunnels stop. Socket units can't read `EnvironmentFile=`,
  so generate them from the confs with a user generator
  (`~/.config/systemd/user-generators/`).
  Caveats: the ControlMaster only exists while the tunnel is active, and ssh sessions sharing
  its connection drop when it stops idle (only SOCKS traffic counts as activity). The first
  connection also waits for the ssh handshake. So it suits only occasionally used tunnels
  that no ssh sessions share.

## License

Copyright 2026 Michael Gebetsroither

Licensed under the Apache License 2.0, see [LICENSE](LICENSE).
