#!/usr/bin/env python3
import os
import subprocess
import sys

ROFI_THEME = "/home/raphaelk/dotfiles/rofi/bluetooth.rasi"

def main():
    options = [
        "󰌾  Bildschirm sperren",
        "󰤄  Energiesparmodus",
        "󰜉  Neustart",
        "  Herunterfahren",
        "󰈆  Abmelden"
    ]

    input_text = "\n".join(options)

    rofi_cmd = ["rofi", "-dmenu", "-p", "  Power Menu", "-i"]
    if os.path.exists(ROFI_THEME):
        rofi_cmd.extend(["-theme", ROFI_THEME])

    res = subprocess.run(rofi_cmd, input=input_text, text=True, capture_output=True)
    selected = res.stdout.strip()

    if not selected:
        return

    if selected == "󰌾  Bildschirm sperren":
        subprocess.run(["hyprlock"])
    elif selected == "󰤄  Energiesparmodus":
        subprocess.run(["systemctl", "suspend"])
    elif selected == "󰜉  Neustart":
        subprocess.run(["systemctl", "reboot"])
    elif selected == "  Herunterfahren":
        subprocess.run(["systemctl", "poweroff"])
    elif selected == "󰈆  Abmelden":
        subprocess.run(["hyprctl", "dispatch", "exit"])

if __name__ == "__main__":
    main()
