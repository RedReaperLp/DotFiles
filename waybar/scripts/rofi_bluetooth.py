#!/usr/bin/env python3
import glob
import os
import re
import subprocess
import sys
import time

ROFI_THEME = "/home/raphaelk/dotfiles/rofi/bluetooth.rasi"

def run_cmd(cmd):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return ""

def notify(title, msg):
    try:
        subprocess.run(["notify-send", title, msg, "-t", "2000"])
    except Exception:
        pass

def get_power_status():
    out = run_cmd(["bluetoothctl", "show"])
    return "Powered: yes" in out

def get_device_icon(name, icon_name="", dev_class=""):
    text = f"{name} {icon_name} {dev_class}".lower()
    if "speaker" in text or "audio-card" in text:
        return "󰓃"
    if "phone" in text or "mobile" in text or "iphone" in text or "android" in text:
        return "󰏲"
    if "headset" in text or "headphone" in text or "earbud" in text or "jbl" in text or "g935" in text or "airpods" in text or "reflect" in text:
        return "󰎤"
    if "mouse" in text or "g903" in text or "hero" in text:
        return "󰍽"
    if "keyboard" in text:
        return "󰌌"
    if "gamepad" in text or "controller" in text or "joystick" in text:
        return "󰊴"
    return "󰂯"

def get_sysfs_battery_for_mac(mac):
    mac_clean = mac.replace(":", "_").lower()
    for path in glob.glob("/sys/class/power_supply/*"):
        if mac_clean in path.lower():
            cap_file = os.path.join(path, "capacity")
            if os.path.exists(cap_file):
                try:
                    return int(open(cap_file).read().strip())
                except Exception:
                    pass
    return None

def get_devices():
    out = run_cmd(["bluetoothctl", "devices"])
    devices = []
    for line in out.strip().splitlines():
        match = re.match(r"^Device\s+([0-9A-Fa-f:]+)\s+(.+)$", line.strip())
        if match:
            mac = match.group(1)
            name = match.group(2)
            info = run_cmd(["bluetoothctl", "info", mac])
            connected = "Connected: yes" in info
            paired = "Paired: yes" in info
            
            battery = None
            for info_line in info.splitlines():
                if "Battery Percentage:" in info_line:
                    try:
                        battery = int(info_line.split(":", 1)[1].strip().strip("() %"))
                    except Exception:
                        pass
            
            if battery is None:
                battery = get_sysfs_battery_for_mac(mac)

            icon = get_device_icon(name)

            devices.append({
                "mac": mac,
                "name": name,
                "connected": connected,
                "paired": paired,
                "battery": battery,
                "icon": icon
            })
    return devices

def main():
    powered = get_power_status()

    options = []
    dev_map = {}

    if powered:
        devices = get_devices()
        connected_count = sum(1 for d in devices if d["connected"])
        
        header_status = f"󰂯 Bluetooth ({connected_count} Verbunden)" if connected_count > 0 else "󰂯 Bluetooth (Aktiv)"
        
        options.append("󰤨  Geräte suchen (Scan 5s)")
        options.append("󰂲  Bluetooth ausschalten")

        if devices:
            for d in devices:
                icon = d["icon"]
                name = d["name"]
                batt_str = f"  {d['battery']}% 󰁹" if d["battery"] is not None else ""

                if d["connected"]:
                    label = f"{icon}  {name}  (Verbunden){batt_str}"
                else:
                    label = f"{icon}  {name}  (Getrennt)"
                
                options.append(label)
                dev_map[label] = d
        else:
            options.append("󰂲  Keine gekoppelten Geräte")

        options.append("󰒓  Einstellungen (Terminal)")
    else:
        header_status = "󰂲 Bluetooth (Deaktiviert)"
        options.append("󰂱  Bluetooth einschalten")

    input_text = "\n".join(options)

    rofi_cmd = ["rofi", "-dmenu", "-p", header_status, "-i"]
    if os.path.exists(ROFI_THEME):
        rofi_cmd.extend(["-theme", ROFI_THEME])

    res = subprocess.run(rofi_cmd, input=input_text, text=True, capture_output=True)
    selected = res.stdout.strip()

    if not selected:
        return

    if selected == "󰂱  Bluetooth einschalten":
        run_cmd(["bluetoothctl", "power", "on"])
        notify("Bluetooth", "Bluetooth eingeschaltet")
        time.sleep(0.5)
        main()
    elif selected == "󰂲  Bluetooth ausschalten":
        run_cmd(["bluetoothctl", "power", "off"])
        notify("Bluetooth", "Bluetooth ausgeschaltet")
    elif selected == "󰤨  Geräte suchen (Scan 5s)":
        notify("Bluetooth", "Suche läuft (5s)...")
        run_cmd(["bluetoothctl", "--timeout", "5", "scan", "on"])
        main()
    elif selected == "󰒓  Einstellungen (Terminal)":
        subprocess.Popen(["kitty", "-e", "bluetoothctl"])
    elif selected in dev_map:
        d = dev_map[selected]
        mac = d["mac"]
        name = d["name"]

        if d["connected"]:
            notify("Bluetooth", f"Trenne {name}...")
            run_cmd(["bluetoothctl", "disconnect", mac])
        else:
            notify("Bluetooth", f"Verbinde {name}...")
            out = run_cmd(["bluetoothctl", "connect", mac])
            if "Successful" in out or "connected" in out.lower():
                notify("Bluetooth", f"Erfolgreich mit {name} verbunden")
            else:
                notify("Bluetooth", f"Verbindung mit {name} fehlgeschlagen")

if __name__ == "__main__":
    main()
