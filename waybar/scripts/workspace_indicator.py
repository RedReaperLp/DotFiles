#!/usr/bin/env python3
import json
import subprocess
import sys

if len(sys.argv) < 2:
    print(json.dumps({"text": "?"}))
    sys.exit(0)

try:
    col = int(sys.argv[1]) # 1 to 5
    
    # Check if we should switch workspace
    if len(sys.argv) > 2 and sys.argv[2] == "switch":
        active_ws_data = json.loads(subprocess.check_output(["hyprctl", "activeworkspace", "-j"]))
        active_id = active_ws_data["id"]
        row = (active_id - 1) // 5
        target_id = row * 5 + col
        # Set animation direction back to horizontal
        subprocess.run(["hyprctl", "keyword", "animation", "workspaces, 1, 4, default, slide"])
        subprocess.run(["hyprctl", "dispatch", "workspace", str(target_id)])
        sys.exit(0)
        
    # Get active workspace ID
    active_ws_data = json.loads(subprocess.check_output(["hyprctl", "activeworkspace", "-j"]))
    active_id = active_ws_data["id"]
    
    # Calculate current row (0-indexed)
    row = (active_id - 1) // 5
    
    # Target workspace for this column
    target_id = row * 5 + col
    
    # Get list of all workspaces (to check if occupied)
    workspaces_list = json.loads(subprocess.check_output(["hyprctl", "workspaces", "-j"]))
    occupied_ids = [w["id"] for w in workspaces_list]
    
    if target_id == active_id:
        print(json.dumps({"text": "󱓻", "class": "active", "tooltip": f"Workspace {target_id} (Active)"}))
    elif target_id in occupied_ids:
        print(json.dumps({"text": "", "class": "occupied", "tooltip": f"Workspace {target_id} (Occupied)"}))
    else:
        print(json.dumps({"text": "", "class": "empty", "tooltip": f"Workspace {target_id} (Empty)"}))

except Exception as e:
    print(json.dumps({"text": "", "class": "empty"}))
