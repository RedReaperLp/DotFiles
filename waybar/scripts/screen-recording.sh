#!/usr/bin/env python3
import json
import subprocess
import sys

def get_app_details(node_name):
    node_name_lower = node_name.lower()
    
    # Mapping of node name substrings to (icon, display_name, brand_color)
    mappings = {
        "vesktop": ("󰙯", "Discord (Vesktop)", "#5865F2"),
        "discord": ("󰙯", "Discord", "#5865F2"),
        "firefox": ("󰈹", "Firefox", "#FF9400"),
        "chromium": ("󰊯", "Chromium", "#4285F4"),
        "chrome": ("󰊯", "Google Chrome", "#4285F4"),
        "obs": ("󰕧", "OBS Studio", "#FFFFFF"),
        "zoom": ("󰕧", "Zoom", "#2D8CFF"),
        "teams": ("󰊻", "Microsoft Teams", "#464EB8"),
        "slack": ("󰒓", "Slack", "#4A154B"),
    }
    
    for key, (icon, name, color) in mappings.items():
        if key in node_name_lower:
            return icon, name, color
            
    return "󰻂", f"Screen Sharing ({node_name})", "#FF5345"

try:
    # 1. Check if gpu-screen-recorder is running (local recording)
    res = subprocess.run(["pgrep", "-f", "^gpu-screen-recorder"], stdout=subprocess.DEVNULL)
    if res.returncode == 0:
        markup_text = "<span color='#FF5345'>󰻂</span>"
        print(json.dumps({"text": markup_text, "tooltip": "Recording screen (local)", "class": "active"}))
        sys.exit(0)

    # 2. Check Pipewire for active video sharing/screencast streams
    dump_data = json.loads(subprocess.check_output(["pw-dump"]))
    active_sharing = False
    app_icon = "󰻂"
    app_name = "Screen Sharing"
    app_color = "#FF5345"
    
    running_nodes = []
    for item in dump_data:
        if item.get("type") == "PipeWire:Interface:Node":
            props = item.get("info", {}).get("props", {})
            media_class = props.get("media.class")
            state = item.get("info", {}).get("state")
            node_name = props.get("node.name", "")
            
            if state == "running":
                running_nodes.append((media_class, node_name))

    # Prioritize Stream/Input/Video (the capturing client app, e.g. vesktop)
    client_node = next((name for cls, name in running_nodes if cls == "Stream/Input/Video"), None)
    
    if client_node:
        app_icon, app_name, app_color = get_app_details(client_node)
        active_sharing = True
    else:
        # Fallback to Video/Source portal
        portal_node = next((name for cls, name in running_nodes if cls == "Video/Source" and "portal" in name.lower()), None)
        if portal_node:
            app_icon, app_name, app_color = get_app_details(portal_node)
            active_sharing = True

    if active_sharing:
        markup_text = f"<span color='{app_color}'>{app_icon}</span>"
        print(json.dumps({"text": markup_text, "tooltip": f"Sharing via {app_name}", "class": "active"}))
    else:
        print(json.dumps({"text": ""}))

except Exception as e:
    # Fallback to empty JSON
    print(json.dumps({"text": ""}))
