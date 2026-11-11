#!/usr/bin/env python3
import json
import os
import subprocess
import sys

# Matrix pro Monitor (siehe hypr/workspace_matrix.lua): 6 Zeilen x 5 Spalten = 30 Workspaces,
# Monitor 1 = WS 1-30, Monitor 2 = WS 31-60, ...
COLS = 5
BLOCK = 30


def matrix_target(active_id, col):
    base = ((active_id - 1) // BLOCK) * BLOCK
    row = ((active_id - 1) % BLOCK) // COLS
    return base + row * COLS + col


def hyprctl_json(*args):
    return json.loads(subprocess.check_output(["hyprctl", *args, "-j"]))


def bar_monitor():
    """Monitor, auf dem diese Waybar-Instanz läuft (Waybar setzt WAYBAR_OUTPUT_NAME)."""
    output = os.environ.get("WAYBAR_OUTPUT_NAME")
    monitors = hyprctl_json("monitors")
    for m in monitors:
        if m["name"] == output:
            return m
    for m in monitors:
        if m.get("focused"):
            return m
    return monitors[0]


def switch(monitor_name, target_id):
    subprocess.run(["hyprctl", "keyword", "animation", "workspaces, 1, 4, default, slide"])
    lua = (
        f'hl.dispatch(hl.dsp.focus({{ monitor = "{monitor_name}" }})) '
        f"hl.dispatch(hl.dsp.focus({{ workspace = {target_id}, on_current_monitor = true }}))"
    )
    subprocess.run(["hyprctl", "eval", lua])
    subprocess.run(["pkill", "-RTMIN+1", "waybar"])


if len(sys.argv) < 2:
    print(json.dumps({"text": "?"}))
    sys.exit(0)

try:
    col = int(sys.argv[1])  # 1 to 5

    monitor = bar_monitor()
    active_id = monitor["activeWorkspace"]["id"]

    # Target workspace for this column (same row, same monitor block)
    target_id = matrix_target(active_id, col)

    if len(sys.argv) > 2 and sys.argv[2] == "switch":
        switch(monitor["name"], target_id)
        sys.exit(0)

    # Get list of all workspaces (to check if occupied)
    occupied_ids = [w["id"] for w in hyprctl_json("workspaces")]

    if target_id == active_id:
        print(json.dumps({"text": "󱓻", "class": "active", "tooltip": f"Workspace {target_id} (Active)"}))
    elif target_id in occupied_ids:
        print(json.dumps({"text": "", "class": "occupied", "tooltip": f"Workspace {target_id} (Occupied)"}))
    else:
        print(json.dumps({"text": "", "class": "empty", "tooltip": f"Workspace {target_id} (Empty)"}))

except Exception:
    print(json.dumps({"text": "", "class": "empty"}))
