#!/usr/bin/env python3
import json
import subprocess

try:
    active_ws_data = json.loads(subprocess.check_output(["hyprctl", "activeworkspace", "-j"]))
    active_id = active_ws_data["id"]
    row = (active_id - 1) // 5 + 1
    
    print(json.dumps({"text": str(row), "tooltip": f"Aktive Zeile: {row}"}))
except Exception:
    print(json.dumps({"text": "1"}))
