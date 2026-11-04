# Nachbau von /usr/share/cachyos-fish-config/cachyos-config.fish für Systeme ohne CachyOS (Ubuntu).
# Wird von config.fish nur geladen, wenn die echte CachyOS-Config fehlt.
# pure-Prompt und done-Plugin installiert fish/post-sync.sh nach ~/.local/share/fish.

## Begrüßung: fastfetch
function fish_greeting
    if type -q fastfetch
        fastfetch
    end
end

## Manpages formatieren (bat heißt unter Ubuntu "batcat")
set -l __bat_cmd
if type -q bat
    set __bat_cmd bat
else if type -q batcat
    set __bat_cmd batcat
    alias bat=batcat
end
set -x MANROFFOPT -c
if test -n "$__bat_cmd"
    set -x MANPAGER "sh -c 'col -bx | $__bat_cmd -l man -p'"
end

## done-Plugin: Benachrichtigung bei langen Befehlen
set -U __done_min_cmd_duration 10000
set -U __done_notification_urgency_level low

## Umgebung
if test -f ~/.fish_profile
    source ~/.fish_profile
end

if test -d ~/.local/bin
    if not contains -- ~/.local/bin $PATH
        set -p PATH ~/.local/bin
    end
end

## !! und !$ (wie bash)
function __history_previous_command
    switch (commandline -t)
        case "!"
            commandline -t $history[1]
            commandline -f repaint
        case "*"
            commandline -i !
    end
end

function __history_previous_command_arguments
    switch (commandline -t)
        case "!"
            commandline -t ""
            commandline -f history-token-search-backward
        case "*"
            commandline -i '$'
    end
end

if [ "$fish_key_bindings" = fish_vi_key_bindings ]
    bind -M insert ! __history_previous_command
    bind -M insert '$' __history_previous_command_arguments
else
    bind ! __history_previous_command
    bind '$' __history_previous_command_arguments
end

## Funktionen
function history
    builtin history --show-time='%F %T '
end

function backup --argument filename
    cp $filename $filename.bak
end

function copy
    if test (count $argv) -eq 2; and test -d "$argv[1]"
        command cp -r (string trim -r -c / -- $argv[1]) $argv[2]
    else
        command cp $argv
    end
end

## Aliase
if type -q eza
    alias ls='eza -al --color=always --group-directories-first --icons'
    alias la='eza -a --color=always --group-directories-first --icons'
    alias ll='eza -l --color=always --group-directories-first --icons'
    alias lt='eza -aT --color=always --group-directories-first --icons'
    alias l.="eza -a | grep -e '^\.'"
end

alias tarnow='tar -acf '
alias untar='tar -zxvf '
alias wget='wget -c '
alias psmem='ps auxf | sort -nr -k 4'
alias psmem10='ps auxf | sort -nr -k 4 | head -10'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ......='cd ../../../../..'
alias dir='dir --color=auto'
alias vdir='vdir --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias jctl='journalctl -p 3 -xb'
type -q hwinfo; and alias hw='hwinfo --short'

# Ubuntu-Pendants zu den pacman-Aliasen
alias update='sudo apt update && sudo apt upgrade'
alias cleanup='sudo apt autoremove --purge'
alias grubup='sudo update-grub'
alias big="dpkg-query -Wf '\${Installed-Size}\t\${Package}\n' | sort -n | awk '{printf \"%.1f MB\t%s\n\", \$1/1024, \$2}' | nl"
alias rip="grep -h ' install ' /var/log/dpkg.log* | sort | tail -200 | nl"
