# autotunnel

Persistent `autossh` SOCKS tunnels as an instanceable systemd **user** unit.

## Install / add a tunnel

    ./install.sh                          # install unit + status script only
    ./install.sh [-n] [-f] NAME [PORT [DEST]]

Installing symlinks `autotunnel@.service` into `~/.config/systemd/user/` and
`autotunnel-status` into `~/.local/bin/`. Pass a NAME to also create
`~/.config/autotunnel/NAME.conf`:

- `PORT`: local SOCKS port or `addr:port` (default: the first free port from 1080 up, bound to 127.0.0.1)
- `DEST`: ssh destination, a host alias or `user@host` (default: NAME)
- `-n`: enable and start the tunnel right away
- `-f`: overwrite an existing conf

Example: `./install.sh -n jump 1081 user@jumphost.example.com`

## Config

One file per tunnel: `~/.config/autotunnel/NAME.conf` (see `examples/example.conf`)

    LISTEN=127.0.0.1:1081
    DEST=user@jumphost.example.com
    # SSH_OPTS="-p 2222"   # optional extra ssh args

runs `autossh -M 0 -N -o ExitOnForwardFailure=yes -o BatchMode=yes $SSH_OPTS -D $LISTEN $DEST`.
After editing a conf: `systemctl --user restart autotunnel@NAME`.

## Usage

    systemctl --user enable --now autotunnel@NAME    # start now + on login
    systemctl --user disable --now autotunnel@NAME
    journalctl --user -u autotunnel@NAME -f
    autotunnel-status

To keep tunnels running without being logged in: `loginctl enable-linger $USER`.

## Notes

- `ControlMaster`, `ControlPath`, `ServerAliveInterval` are **not** overridden; they come
  from `~/.ssh/config`, so a tunnel acts as the mux master for other ssh sessions to the
  same host. `-M 0` only disables autossh's monitor port, not ssh multiplexing.
- When a tunnel restarts, sessions multiplexed over it drop too. If a master for the host
  already exists when the tunnel starts, the tunnel attaches to it as a mux client.
- `BatchMode=yes`: auth must work non-interactively. With a passphrase-protected key the
  service needs the agent socket, e.g. `systemctl --user import-environment SSH_AUTH_SOCK`
  (or `SSH_AUTH_SOCK=...` in the conf).

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
