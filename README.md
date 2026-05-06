# vpn

A small `vpn` command that wraps OpenVPN on macOS. Start, stop, check status, and inspect your tunnel from one tidy CLI — no GUI client, no `sudo openvpn --config ...` typed by hand.

```
vpn start    # daemonize openvpn
vpn stop     # kill the daemon
vpn status   # pid + uptime
vpn info     # tunnel ip, default route, public ip
vpn logs -f  # follow logs
```

## Requirements

- macOS (tested on Apple Silicon, Tahoe)
- [Homebrew](https://brew.sh)
- An OpenVPN client config (`client.ovpn`) with all certs/keys inlined

## Install

```sh
git clone git@github.com:erdemylmaz/vpn-cli.git ~/Documents/personal/vpn
cd ~/Documents/personal/vpn
./install.sh --sudoers
```

`install.sh` does:

1. `brew install openvpn` if missing
2. creates `~/.vpn/` with mode 700
3. symlinks `./vpn` into `~/.local/bin/vpn` (must be on `PATH`)
4. with `--sudoers`: installs `/etc/sudoers.d/vpn` so `vpn start` / `stop` never prompt for a password

If `~/.local/bin` isn't on your `PATH`, the installer warns you. Add to `~/.zshrc`:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Then drop your config:

```sh
cp /path/to/client.ovpn ~/.vpn/client.ovpn
chmod 600 ~/.vpn/client.ovpn
vpn start
```

## Commands

| Command | Description |
|---|---|
| `vpn start` | daemonize openvpn, write pid + log |
| `vpn stop` | SIGTERM the daemon, escalate to SIGKILL if needed |
| `vpn restart` | stop + start |
| `vpn status` | running/stopped, pid, uptime |
| `vpn info` | status + remote + tunnel interface(s) + default route + public IP |
| `vpn logs [N]` | last N log lines (default 50) |
| `vpn logs -f` | follow logs |
| `vpn config path\|edit\|show` | inspect the .ovpn file |
| `vpn help` | usage |

## Files

| Path | Purpose |
|---|---|
| `~/.vpn/client.ovpn` | your OpenVPN config (you provide) |
| `~/.vpn/openvpn.pid` | written by openvpn at start |
| `~/.vpn/openvpn.log` | openvpn log output |
| `~/.local/bin/vpn` | symlink to `./vpn` in this repo |
| `/etc/sudoers.d/vpn` | passwordless sudo rule (if installed) |

## Environment overrides

Useful if you want to keep the config elsewhere or run multiple profiles:

```sh
VPN_DIR=~/.vpn-work vpn start
VPN_CONFIG=~/.vpn/work.ovpn vpn start
OPENVPN_BIN=/opt/homebrew/sbin/openvpn vpn start
```

## Passwordless sudo

The `vpn` script needs root for three things:
- starting `openvpn` (it creates a `tun` device and rewrites the routing table)
- `kill`ing the daemon (the daemon runs as root)
- `tail`ing the log if it's not world-readable

The sudoers drop-in installed by `./install.sh --sudoers` whitelists exactly:

```
Cmnd_Alias VPN_CMDS = /opt/homebrew/sbin/openvpn, /bin/kill, /usr/bin/tail
<your-user> ALL=(root) NOPASSWD: VPN_CMDS
```

This is narrow — it does not give passwordless sudo for anything else.

To revert: `sudo rm /etc/sudoers.d/vpn`.

## Use on another device

```sh
git clone git@github.com:erdemylmaz/vpn-cli.git ~/Documents/personal/vpn
cd ~/Documents/personal/vpn
./install.sh --sudoers
# then copy your client.ovpn into ~/.vpn/
```

The repo never contains your `client.ovpn` — keys live only in `~/.vpn/`. `.gitignore` blocks `*.ovpn` / `*.pem` / `*.key` / `*.crt` defensively.

## Uninstall

```sh
vpn stop || true
sudo rm -f /etc/sudoers.d/vpn
rm -f ~/.local/bin/vpn
rm -rf ~/.vpn
brew uninstall openvpn   # optional
```

## Troubleshooting

**`vpn start` says "failed to start" but `vpn status` later shows running**
The pid file appears slightly after openvpn forks. Usually harmless; `vpn status` reflects truth.

**`Unrecognized option ... block-outside-dns`**
Windows-only directive in your `.ovpn`. OpenVPN 2.7 rejects the legacy `setenv opt block-outside-dns` form. Comment it out — `ignore-unknown-option block-outside-dns` (also typically present) is the modern equivalent.

**`vpn info` shows your old public IP**
Confirm `vpn status` is RUNNING, then check the default route:

```sh
netstat -rn -f inet | head -5
```

The default route should go through `10.x.x.x` (your tunnel gateway), not your LAN router.
