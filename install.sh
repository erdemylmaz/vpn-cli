#!/usr/bin/env bash
# install.sh — set up the `vpn` command on a new macOS machine
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$REPO_DIR/vpn"
BIN_DIR="$HOME/.local/bin"
VPN_DIR="$HOME/.vpn"
OPENVPN_BIN="/opt/homebrew/sbin/openvpn"

say() { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33mwarn:\033[0m %s\n" "$*" >&2; }

# 1. macOS + brew + openvpn
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: this installer is macOS-only" >&2
  exit 1
fi
if ! command -v brew >/dev/null 2>&1; then
  echo "error: Homebrew not found — install from https://brew.sh first" >&2
  exit 1
fi
if [[ ! -x "$OPENVPN_BIN" ]]; then
  say "installing openvpn via brew…"
  brew install openvpn
fi

# 2. ~/.vpn/ and ~/.vpn/profiles/
say "creating $VPN_DIR and $VPN_DIR/profiles"
mkdir -p "$VPN_DIR/profiles"
chmod 700 "$VPN_DIR" "$VPN_DIR/profiles"

# 3. symlink ~/.local/bin/vpn -> repo
mkdir -p "$BIN_DIR"
if [[ -e "$BIN_DIR/vpn" || -L "$BIN_DIR/vpn" ]]; then
  current_target=$(readlink "$BIN_DIR/vpn" 2>/dev/null || echo "")
  if [[ "$current_target" != "$SCRIPT" ]]; then
    say "replacing existing $BIN_DIR/vpn"
    rm -f "$BIN_DIR/vpn"
  fi
fi
ln -sf "$SCRIPT" "$BIN_DIR/vpn"
chmod +x "$SCRIPT"
say "linked $BIN_DIR/vpn -> $SCRIPT"

# 4. PATH check
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "$BIN_DIR is not on your PATH — add this to ~/.zshrc:"
     printf '    export PATH="$HOME/.local/bin:$PATH"\n' ;;
esac

# 5. sudoers (opt-in via flag or VPN_INSTALL_SUDOERS=1)
install_sudoers=0
case "${1:-}" in
  --sudoers|-s) install_sudoers=1 ;;
esac
[[ "${VPN_INSTALL_SUDOERS:-}" == "1" ]] && install_sudoers=1

if (( install_sudoers )); then
  say "installing /etc/sudoers.d/vpn (you'll be asked for your password)…"
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT
  cat > "$tmp" <<EOF
# passwordless vpn wrapper for $USER
# whitelists only the binaries the vpn script invokes as root
Cmnd_Alias VPN_CMDS = $OPENVPN_BIN, /bin/kill, /usr/bin/tail
$USER ALL=(root) NOPASSWD: VPN_CMDS
EOF
  sudo visudo -cf "$tmp"
  sudo install -m 0440 -o root -g wheel "$tmp" /etc/sudoers.d/vpn
  say "passwordless sudo configured for: openvpn, kill, tail"
else
  echo
  echo "to enable passwordless sudo (recommended), re-run with --sudoers:"
  echo "    ./install.sh --sudoers"
fi

# 6. profile check
echo
shopt -s nullglob
profiles=( "$VPN_DIR"/profiles/*.ovpn )
shopt -u nullglob
if (( ${#profiles[@]} == 0 )) && [[ ! -f "$VPN_DIR/client.ovpn" ]]; then
  warn "no profiles found in $VPN_DIR/profiles/"
  echo "    drop your OpenVPN client config(s) there, named <profile>.ovpn:"
  echo "      cp /path/to/foo.ovpn $VPN_DIR/profiles/foo.ovpn && chmod 600 $VPN_DIR/profiles/foo.ovpn"
  echo "      vpn use foo"
elif (( ${#profiles[@]} > 0 )); then
  say "found ${#profiles[@]} profile(s) in $VPN_DIR/profiles/"
else
  say "legacy config detected at $VPN_DIR/client.ovpn (will be used as fallback)"
fi

echo
say "done. try: vpn help"
