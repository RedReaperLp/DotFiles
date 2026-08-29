#!/bin/bash
# ~/.config/hypr/scripts/change_brightness.sh
# Rate-limited brightness adjustment to prevent I2C bus flooding and system crashes

LOCKFILE="/tmp/hypr_ddcutil_brightness.lock"

exec 9>"$LOCKFILE"
if ! flock -n 9; then
    # Ignore rapid duplicate key presses while an I2C transaction is in progress
    exit 0
fi

ACTION="$1"
STEP="${2:-10}"

case "$ACTION" in
    up)
        ddcutil setvcp 10 + "$STEP" --noverify &>/dev/null &
        ;;
    down)
        ddcutil setvcp 10 - "$STEP" --noverify &>/dev/null &
        ;;
esac

# Brief sleep to throttle rapid key presses and protect the I2C bus
sleep 0.15
