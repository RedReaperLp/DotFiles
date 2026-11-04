# Roter Fensterrand in Hyprland, solange sudo in diesem Terminal das Passwort gespeichert hat.
# Gegenstück: ~/.config/hypr/sudo_border.lua (dort auch die Erklärung).
#
# Nach einem Befehl mit sudo (direkt oder z.B. über einen Alias – dann meldet Hyprland "seen-<pid>")
# wird EINMAL mit "sudo -n -v" geprüft, ob das Passwort jetzt gespeichert ist. "-n" fragt nie nach
# einem Passwort; die Prüfung verlängert den Cache nur um die Sekunden seit dem sudo-Aufruf.

status is-interactive; or return

if set -q XDG_RUNTIME_DIR
    set -g __sudo_border_dir $XDG_RUNTIME_DIR/sudo-border
else
    set -g __sudo_border_dir /tmp/sudo-border
end

function __sudo_border_check --on-event fish_postexec
    set -l seen $__sudo_border_dir/seen-$fish_pid
    set -l cached $__sudo_border_dir/cached-$fish_pid

    # sudo -k / sudo -K: gespeichertes Passwort verworfen
    if string match -qr -- '(^|[\s;&|(])sudo\s+-[kK](\s|$)' $argv[1]
        rm -f $seen $cached
        return
    end

    if test -e $seen; or string match -qr -- '(^|[\s;&|(])sudo(\s|$)' $argv[1]
        rm -f $seen
        command -q sudo; or return
        mkdir -p $__sudo_border_dir
        if command sudo -n -v 2>/dev/null
            date +%s >$cached
        else
            rm -f $cached
        end
    end
end

function __sudo_border_cleanup --on-event fish_exit
    rm -f $__sudo_border_dir/seen-$fish_pid $__sudo_border_dir/cached-$fish_pid
end
