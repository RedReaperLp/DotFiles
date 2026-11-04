# CachyOS liefert eine eigene Basis-Config mit, auf anderen Systemen (Ubuntu) der Nachbau
if test -f /usr/share/cachyos-fish-config/cachyos-config.fish
    source /usr/share/cachyos-fish-config/cachyos-config.fish
else
    source (status dirname)/cachyos-compat.fish
end

if status is-interactive
    type -q tirith; and tirith init --shell fish | source
    type -q zoxide; and zoxide init fish | source
end

# Repo-Pfad aus dem Symlink ~/.config/fish -> <repo>/fish ableiten
set -l __dotfiles_dir (path resolve (status dirname)/..)
if grep -qi '^ID=ubuntu' /etc/os-release 2>/dev/null
    alias sync="$__dotfiles_dir/sync_dotfiles-ubuntu.sh --sync"
else
    alias sync="$__dotfiles_dir/sync_dotfiles.sh --sync"
end
alias vpn='tmux new -s vpn "sudo openvpn --config ~/.config/openvpn/uni_3.ovpn --auth-user-pass ~/.config/openvpn/pass.txt"'
alias cmod='chmod +x '
alias DebugTunnel="ssh -i ~/.ssh/5_9_23_72_KEY -L 5005:localhost:5005 root@10.10.10.105"
alias vps="kitten ssh -i ~/.ssh/5_9_23_72_linux root@direct.redreaperlp.de"

alias steam-safe="flatpak run com.valvesoftware.Steam"
alias steam-native="command steam"

function ssh
    command kitty +kitten ssh $argv
end
