#!/usr/bin/env python3
import json
import os
import subprocess

# Matrix pro Monitor (siehe hypr/workspace_matrix.lua): 30 Workspaces je Monitor (6 Zeilen x 5 Spalten)
BLOCK = 30
COLS = 5

try:
    # Monitor dieser Waybar-Instanz (Waybar setzt WAYBAR_OUTPUT_NAME), sonst fokussierter Monitor
    output = os.environ.get("WAYBAR_OUTPUT_NAME")
    monitors = json.loads(subprocess.check_output(["hyprctl", "monitors", "-j"]))
    monitor = next((m for m in monitors if m["name"] == output), None) or next(
        (m for m in monitors if m.get("focused")), monitors[0]
    )
    active_id = monitor["activeWorkspace"]["id"]
    row = ((active_id - 1) % BLOCK) // COLS + 1

    print(json.dumps({"text": str(row), "tooltip": f"Aktive Zeile: {row} ({monitor['name']})"}))
except Exception:
    print(json.dumps({"text": "1"}))
