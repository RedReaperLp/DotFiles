#!/bin/bash
# ~/.config/hypr/scripts/row_manager.sh

STATE_FILE="/tmp/hypr_active_row"
# Default Zeile 0 (Workspaces 1-5)
[[ ! -f "$STATE_FILE" ]] && echo 0 >"$STATE_FILE"

case $1 in
set)
  echo "$2" >"$STATE_FILE"
  notify-send "Zeile $(($2 + 1)) aktiv" -t 800
  ;;
jump)
  ROW=$(cat "$STATE_FILE")
  # Berechne Workspace: (Row * 5) + Zahl
  TARGET=$(((ROW * 5) + $2))
  hyprctl dispatch workspace "$TARGET"
  ;;
esac
