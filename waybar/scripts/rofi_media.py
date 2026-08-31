#!/usr/bin/env python3
import os
import subprocess
import sys
import urllib.parse
import urllib.request

ROFI_THEME = "/home/raphaelk/dotfiles/rofi/media.rasi"

def run_cmd(cmd):
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""

def get_cover_art():
    art_url = run_cmd(["playerctl", "metadata", "mpris:artUrl"])
    if not art_url:
        return None
    try:
        if art_url.startswith("file://"):
            path = urllib.parse.unquote(art_url[7:])
            if os.path.exists(path):
                png_path = "/tmp/spotify_cover.png"
                subprocess.run(["magick", path, "-resize", "88x88", png_path], stderr=subprocess.DEVNULL)
                if os.path.exists(png_path):
                    return png_path
        elif art_url.startswith("http"):
            jpg_path = "/tmp/spotify_cover.jpg"
            png_path = "/tmp/spotify_cover.png"
            urllib.request.urlretrieve(art_url, jpg_path)
            subprocess.run(["magick", jpg_path, "-resize", "88x88", png_path], stderr=subprocess.DEVNULL)
            if os.path.exists(png_path):
                return png_path
    except Exception:
        pass
    return None

def main():
    artist = run_cmd(["playerctl", "metadata", "artist"])
    title = run_cmd(["playerctl", "metadata", "title"])
    status = run_cmd(["playerctl", "status"])
    cover = get_cover_art()

    # Formatted Header without prompt icon clutter
    if title and artist:
        header = f"{title}\n{artist}"
    elif title:
        header = title
    elif artist:
        header = artist
    else:
        header = "Media Player"

    play_label = "󰏤" if status == "Playing" else "󰐊"

    # Compact Icon-Only Control Buttons
    options = [
        "󰒮",
        play_label,
        "󰒭",
        "󰓇"
    ]

    input_text = "\n".join(options)

    rofi_cmd = ["rofi", "-dmenu", "-p", header, "-i"]
    if os.path.exists(ROFI_THEME):
        rofi_cmd.extend(["-theme", ROFI_THEME])
        if cover:
            theme_str = f'icon-cover {{ filename: "{cover}"; }}'
            rofi_cmd.extend(["-theme-str", theme_str])

    res = subprocess.run(rofi_cmd, input=input_text, text=True, capture_output=True)
    selected = res.stdout.strip()

    if not selected:
        return

    if selected in ["󰏤", "󰐊"]:
        subprocess.run(["playerctl", "play-pause"])
    elif selected == "󰒮":
        subprocess.run(["playerctl", "previous"])
    elif selected == "󰒭":
        subprocess.run(["playerctl", "next"])
    elif selected == "󰓇":
        subprocess.Popen(["/home/raphaelk/automation/spotify.sh"])

if __name__ == "__main__":
    main()
