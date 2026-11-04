#!/bin/bash
# Post-Sync-Hook für fish (wird von sync_dotfiles*.sh ausgeführt).
# Auf CachyOS kommt alles aus cachyos-fish-config -> hier nichts tun.
# Auf anderen Systemen (Ubuntu): pure-Prompt und done-Plugin nachinstallieren,
# damit sich fish wie der CachyOS-Default verhält. Installation nach
# ~/.local/share/fish/vendor_*.d (wird von fish automatisch geladen, nicht im Repo).

[ -f /usr/share/cachyos-fish-config/cachyos-config.fish ] && exit 0

PURE_VERSION="v4.19.2"
DONE_VERSION="1.21.1"

DATA_DIR="$HOME/.local/share/fish"
FUNC_DIR="$DATA_DIR/vendor_functions.d"
CONF_DIR="$DATA_DIR/vendor_conf.d"
mkdir -p "$FUNC_DIR" "$CONF_DIR"

install_repo() { # <name> <github-repo> <tag>
  local name="$1" repo="$2" tag="$3"
  local stamp="$DATA_DIR/.${name}-version"
  if [ "$(cat "$stamp" 2>/dev/null)" = "$tag" ]; then
    echo "[SKIP] $name $tag already installed"
    return
  fi
  local tmp
  tmp=$(mktemp -d)
  if curl -fsSL "https://github.com/$repo/archive/refs/tags/$tag.tar.gz" | tar -xz -C "$tmp" --strip-components=1; then
    [ -d "$tmp/functions" ] && cp "$tmp"/functions/*.fish "$FUNC_DIR/"
    [ -d "$tmp/conf.d" ] && cp "$tmp"/conf.d/*.fish "$CONF_DIR/"
    echo "$tag" >"$stamp"
    echo "[OK] $name $tag installed"
  else
    echo "[ERR] Download of $name $tag failed"
  fi
  rm -rf "$tmp"
}

install_repo pure pure-fish/pure "$PURE_VERSION"
install_repo done franciscolourenco/done "$DONE_VERSION"

# Tools aus der CachyOS-Config, die per apt verfügbar sind
if command -v apt >/dev/null; then
  MISSING=""
  for pkg in fastfetch eza bat fzf hwinfo; do
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed" || MISSING="$MISSING $pkg"
  done
  if [ -n "$MISSING" ]; then
    echo "[PKG] Installing:$MISSING"
    sudo apt install -y $MISSING || echo "[ERR] apt install failed"
  fi
fi
