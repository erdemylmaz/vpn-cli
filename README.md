# vpn

A small `vpn` command that wraps OpenVPN on macOS, with **multi-profile support**. Start, stop, switch between profiles, check status, and inspect your tunnel from one tidy CLI — no GUI client, no `sudo openvpn --config ...` typed by hand.

```
vpn start              # default profile (set by `vpn use`)
vpn start work         # one-shot to a specific profile
vpn use work           # set default profile
vpn list               # show profiles (* default, ↑ running)
vpn stop               # kill the daemon
vpn status             # pid + uptime + profile
vpn info               # tunnel ip, default route, public ip
vpn logs -f            # follow logs
```

## Requirements

- macOS (tested on Apple Silicon, Tahoe)
- [Homebrew](https://brew.sh)
- One or more OpenVPN client configs (`<name>.ovpn`) with all certs/keys inlined

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

Then drop one or more configs as profiles, pick a default, and start:

```sh
mkdir -p ~/.vpn/profiles
cp /path/to/work.ovpn  ~/.vpn/profiles/work.ovpn  && chmod 600 ~/.vpn/profiles/work.ovpn
cp /path/to/home.ovpn  ~/.vpn/profiles/home.ovpn  && chmod 600 ~/.vpn/profiles/home.ovpn
vpn use home    # set default
vpn start       # connect to default
vpn start work  # one-shot to another profile
```

## Commands

| Command | Description |
|---|---|
| `vpn start [profile]` | daemonize openvpn, write pid + log. Uses default if no profile given. |
| `vpn stop` | SIGTERM the daemon, escalate to SIGKILL if needed |
| `vpn restart [profile]` | stop + start. Restarts the currently running profile if no arg. |
| `vpn list` | list available profiles (`*` default, `↑` running) |
| `vpn use <profile>` | set the default profile |
| `vpn status` | running/stopped, pid, uptime, profile |
| `vpn info` | status + remote + tunnel interface(s) + default route + public IP |
| `vpn logs [N]` | last N log lines (default 50) |
| `vpn logs -f` | follow logs |
| `vpn config path\|edit\|show [profile]` | inspect a profile's .ovpn |
| `vpn help` | usage |

Only one tunnel runs at a time. To switch profiles: `vpn stop && vpn start <other>`.

## Files

| Path | Purpose |
|---|---|
| `~/.vpn/profiles/<name>.ovpn` | one OpenVPN client config per profile (you provide) |
| `~/.vpn/active` | name of the default profile (set by `vpn use`) |
| `~/.vpn/active.run` | name of the profile of the currently running daemon |
| `~/.vpn/client.ovpn` | legacy single-config fallback (still honored if no profiles exist) |
| `~/.vpn/openvpn.pid` | written by openvpn at start |
| `~/.vpn/openvpn.log` | openvpn log output |
| `~/.local/bin/vpn` | symlink to `./vpn` in this repo |
| `/etc/sudoers.d/vpn` | passwordless sudo rule (if installed) |

## Environment overrides

```sh
VPN_PROFILE=work vpn start          # equivalent to `vpn start work`
VPN_DIR=~/.vpn-alt vpn start        # use an alternate vpn home
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

## Server setup & user provisioning

This CLI is the client side. To actually have something to connect to, you (or your teammate) need an OpenVPN server. For a standard Debian/Ubuntu box with a public IPv4 this takes ~3 minutes using the [angristan/openvpn-install](https://github.com/angristan/openvpn-install) script.

### Naming convention

- **Server-side cert name** identifies a *device*, picked when you add a user. Convention: `<person>-<device>` — e.g. `erdem-laptop`, `erdem-desktop`, `ahmet-laptop`. This is what shows up in the server's revoke menu.
- **Local-side profile name** is the `.ovpn` filename on the user's laptop. Convention: name it after the *server you're connecting to* — e.g. `actual-development.ovpn` so `vpn start actual-development` works regardless of whose laptop you're on.

The cert *inside* the file is per-device; the *filename* on disk is per-server.

> **One cert per device — never share `.ovpn` files between people.** If a laptop is lost, you can revoke just that one cert. The default server config doesn't enable `duplicate-cn`, so two devices on the same cert will kick each other off. Audit logs also tell you which device connected when.

### 1) Provisioning a new server (one-time)

Prereqs on the server:
- A public IPv4 (whatever your customer whitelists)
- **UDP 1194** open in the hosting provider's cloud firewall (not just the OS-level iptables)
- root access

```sh
ssh root@<server>
apt update && apt -y install curl
curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh
chmod +x openvpn-install.sh
./openvpn-install.sh
```

Recommended answers when prompted:

| Prompt | Answer |
|---|---|
| IPv4 address | (default) |
| Public IPv4 / hostname | (default — or a DNS name if you have one) |
| IPv6 support | `n` |
| Port | `1194` (or `443` if 1194 is firewalled on customer networks) |
| Protocol | `UDP` (use TCP only if UDP is blocked) |
| DNS resolvers | `Cloudflare` or `1.1.1.1` |
| Compression | `n` (insecure — VORACLE) |
| Customize encryption | `n` |
| First client name | `<person>-<device>` (e.g. `erdem-laptop`) |
| Password-protect client | `n` (for headless laptop use) |

If you run with `sudo` from a non-root user, the `.ovpn` lands in `/root/`. Move it:

```sh
sudo mkdir -p /home/admin/.vpn && sudo mv /root/*.ovpn /home/admin/.vpn/
sudo chown -R admin:admin /home/admin/.vpn && sudo chmod 700 /home/admin/.vpn
sudo chmod 600 /home/admin/.vpn/*.ovpn
```

The script also runs in **non-interactive mode** if it can't get a TTY (e.g. via certain CI/SSH setups) — it picks sensible defaults matching the table above, except client name defaults to `client`. Rename later via the menu (see below).

### 2) Adding a new device or teammate

Re-run the same script — it detects the existing install and shows a menu:

```sh
./openvpn-install.sh
# 1) Add a new user
# 2) Revoke existing user
# 3) Remove OpenVPN
# 4) Exit
```

Pick **1**, give a name like `ahmet-laptop`, choose passwordless. Result: `~/<name>.ovpn` (or `/root/<name>.ovpn` if you used sudo — move it as above).

### 3) Delivering the `.ovpn` securely

`.ovpn` files contain a private key. **Do not** send them via plain email, Slack DM, GitHub, or anything that gets logged. Pick one:

- **1Password / Bitwarden** secure note + attachment (best for teams)
- **Signal** (E2E, ephemeral)
- `scp` direct between machines on a trusted network (LAN/Tailscale)
- Encrypted archive (`age` / `gpg`) sent any way, with the passphrase via a *different* channel

After the file has been received and verified, **wipe the server copy**:

```sh
shred -u /home/admin/.vpn/ahmet-laptop.ovpn
```

The cert is still active server-side (in the CA's issued list); only the bearer file is gone. To regenerate, re-add the user with the same name (revoke the old first when prompted).

### 4) Teammate onboarding (their laptop, one-time)

```sh
# install this CLI
git clone git@github.com:erdemylmaz/vpn-cli.git ~/Documents/personal/vpn
cd ~/Documents/personal/vpn
./install.sh --sudoers

# drop in the config (received securely; rename to the *server* name, not their cert name)
mkdir -p ~/.vpn/profiles
mv ~/Downloads/ahmet-laptop.ovpn ~/.vpn/profiles/actual-development.ovpn
chmod 600 ~/.vpn/profiles/actual-development.ovpn

# set default and connect
vpn use actual-development
vpn start
vpn info   # "public ip:" should now be the dev server's public IP
```

After that, day-to-day usage is just `vpn start` and `vpn stop`.

### 5) Revoking access

Laptop lost, teammate left, cert compromised:

```sh
./openvpn-install.sh
# 2) Revoke existing user  -> pick the cert name to revoke -> confirm
```

The cert is added to the CRL and rejected on the next handshake. Already-established tunnels aren't dropped until they reconnect; force-kick by restarting the server:

```sh
systemctl restart openvpn-server@server
```

### 6) Tracking who has what

The angristan script doesn't keep a friendly registry — certs live in `/etc/openvpn/server/easy-rsa/pki/issued/`. For small teams (≤ 5), just keep a private note: `erdem-laptop = me`, `ahmet-laptop = Ahmet`, etc. Worth automating only past that.

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

**Switching profiles while connected**
Only one tunnel runs at a time. `vpn start <other>` will print a hint if a different profile is already up; run `vpn stop && vpn start <other>`.

**`vpn info` shows your old public IP**
Confirm `vpn status` is RUNNING, then check the default route:

```sh
netstat -rn -f inet | head -5
```

The default route should go through `10.x.x.x` (your tunnel gateway), not your LAN router.
