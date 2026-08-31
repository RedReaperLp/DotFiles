#!/usr/bin/env python3
import glob
import html
import json
import os
import subprocess
import sys

COLOR_GREEN = "#549e6a"
COLOR_TEAL = "#2DD5B7"
COLOR_YELLOW = "#E5C736"
COLOR_RED = "#FF5345"

HEADSET_KEYWORDS = [
    "headset", "headphone", "headphones", "earbud", "earbuds", "jbl",
    "g935", "sony", "bose", "airpods", "audio", "sound", "reflect",
    "sennheiser", "jabra", "anker", "soundcore", "galaxy buds"
]

MOUSE_KEYWORDS = [
    "mouse", "g903", "hero", "rat", "pointer", "logitech g", "razer", "corsair", "steelseries"
]

def get_color(pct, state):
    if state == "charging":
        return COLOR_TEAL
    if pct <= 10:
        return COLOR_RED
    if pct <= 20:
        return COLOR_YELLOW
    return COLOR_GREEN

def classify_device(name, model, dev_type="", icon_name=""):
    text = f"{name} {model} {dev_type} {icon_name}".lower()

    if "audio-headset" in icon_name or "audio-headphones" in icon_name:
        return "headset"
    if "input-mouse" in icon_name:
        return "mouse"

    for kw in HEADSET_KEYWORDS:
        if kw in text:
            return "headset"
    for kw in MOUSE_KEYWORDS:
        if kw in text:
            return "mouse"

    if "headset" in dev_type or "headphone" in dev_type:
        return "headset"
    if "mouse" in dev_type:
        return "mouse"

    return None

def read_sysfs_device(path):
    try:
        online_file = os.path.join(path, "online")
        status_file = os.path.join(path, "status")
        capacity_file = os.path.join(path, "capacity")
        model_file = os.path.join(path, "model_name")
        type_file = os.path.join(path, "type")
        
        online = int(open(online_file).read().strip()) if os.path.exists(online_file) else 1
        status = open(status_file).read().strip().lower() if os.path.exists(status_file) else "discharging"
        capacity = int(open(capacity_file).read().strip()) if os.path.exists(capacity_file) else None
        model = open(model_file).read().strip() if os.path.exists(model_file) else os.path.basename(path)
        dev_type = open(type_file).read().strip().lower() if os.path.exists(type_file) else ""

        if online == 0 or status == "unknown" or capacity is None or capacity == 0:
            return None

        return {
            "model": model,
            "percentage": capacity,
            "state": status,
            "path": path,
            "dev_type": dev_type
        }
    except Exception:
        return None

def scan_sysfs():
    headset_info = None
    mouse_info = None

    # Scan all power supply nodes, skipping system laptop batteries (BAT0, BAT1, AC)
    for path in sorted(glob.glob("/sys/class/power_supply/*")):
        base = os.path.basename(path)
        if base.startswith(("BAT", "AC", "ADP", "dock")):
            continue

        data = read_sysfs_device(path)
        if not data:
            continue

        category = classify_device(data["path"], data["model"], data["dev_type"])
        if category == "headset" and not headset_info:
            headset_info = data
        elif category == "mouse" and not mouse_info:
            mouse_info = data

    return headset_info, mouse_info

def scan_upower_fallback():
    headset_info = None
    mouse_info = None

    try:
        devices_out = subprocess.check_output(["upower", "-e"], text=True, stderr=subprocess.DEVNULL, timeout=1.5)
        for dev in devices_out.strip().splitlines():
            if "DisplayDevice" in dev or "line_power" in dev:
                continue
            try:
                info_out = subprocess.check_output(["upower", "-i", dev], text=True, stderr=subprocess.DEVNULL, timeout=1.5)
            except Exception:
                continue

            if "native-path:          (null)" in info_out:
                continue

            present = True
            percentage = None
            state = "discharging"
            model = ""
            icon_name = ""
            dev_type = ""

            for line in info_out.splitlines():
                line_str = line.strip()
                if line_str.startswith("present:"):
                    present = (line_str.split(":", 1)[1].strip() == "yes")
                elif line_str.startswith("percentage:"):
                    val = line_str.split(":", 1)[1].strip()
                    if "should be ignored" in val:
                        percentage = None
                    else:
                        try:
                            percentage = int(val.rstrip("%"))
                        except ValueError:
                            percentage = None
                elif line_str.startswith("state:"):
                    state = line_str.split(":", 1)[1].strip()
                elif line_str.startswith("icon-name:"):
                    icon_name = line_str.split(":", 1)[1].strip().strip("'\"")
                    if "charging" in icon_name and "discharging" not in icon_name:
                        state = "charging"
                elif line_str.startswith("model:"):
                    model = line_str.split(":", 1)[1].strip()
                elif line_str in ("headset", "mouse", "keyboard", "headphones"):
                    dev_type = line_str

            if not present or percentage is None or state in ("unknown", ""):
                continue

            category = classify_device(dev, model, dev_type, icon_name)
            data = {
                "dev": dev,
                "model": model or ("Headset" if category == "headset" else "Mouse"),
                "percentage": percentage,
                "state": state
            }

            if category == "headset" and not headset_info:
                headset_info = data
            elif category == "mouse" and not mouse_info:
                mouse_info = data
    except Exception:
        pass

    return headset_info, mouse_info

def main():
    try:
        headset, mouse = scan_sysfs()

        u_headset, u_mouse = scan_upower_fallback()
        if not headset and u_headset:
            headset = u_headset
        if not mouse and u_mouse:
            mouse = u_mouse

        parts = []
        tooltips = []
        classes = []

        if headset:
            hpct = headset["percentage"]
            hstate = headset["state"]
            hcolor = get_color(hpct, hstate)
            hicon = " " if hstate == "charging" else ""
            hmodel_safe = html.escape(headset['model'])
            parts.append(f"<span foreground='{hcolor}'>󰋋 {hpct}%{hicon}</span>")
            tooltips.append(f"Headset ({hmodel_safe}): {hpct}% ({hstate})")
            if hpct <= 10 and hstate != "charging":
                classes.append("critical")
            elif hpct <= 20 and hstate != "charging":
                classes.append("warning")

        if mouse:
            mpct = mouse["percentage"]
            mstate = mouse["state"]
            mcolor = get_color(mpct, mstate)
            micon = " " if mstate == "charging" else ""
            mmodel_safe = html.escape(mouse['model'])
            parts.append(f"<span foreground='{mcolor}'>󰍽 {mpct}%{micon}</span>")
            tooltips.append(f"Maus ({mmodel_safe}): {mpct}% ({mstate})")
            if mpct <= 10 and mstate != "charging":
                classes.append("critical")
            elif mpct <= 20 and mstate != "charging":
                classes.append("warning")

        if not parts:
            print(json.dumps({}))
            sys.stdout.flush()
            return

        text = "   ".join(parts)
        tooltip = "\n".join(tooltips)

        output = {
            "text": text,
            "tooltip": tooltip,
            "class": " ".join(set(classes))
        }

        print(json.dumps(output))
        sys.stdout.flush()
    except Exception:
        print(json.dumps({}))
        sys.stdout.flush()

if __name__ == "__main__":
    main()
