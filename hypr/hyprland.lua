-- HYPRLAND v0.55+ NATIVE LUA CONFIG
-- #######################################################################################

local mainMod = "SUPER"
local terminal = "kitty"
local fileManager = "nautilus"
local menu = "~/.config/rofi/launchers/type-6/launcher.sh"
local powerMenu = "~/.config/rofi/powermenu/type-5/powermenu.sh"
local screenshotMenu = "~/.config/rofi/applets/bin/screenshot.sh"

--------------------------------------------------
-- HYPRLAND MATRIX NAVIGATION (pro Monitor, siehe workspace_matrix.lua)
--------------------------------------------------

local matrix = require("workspace_matrix")
-- Wird von matrix.assign_defaults() gesetzt (z.B. durch ubuntu.lua mit Monitor-Profilen)
_G.__matrix_defaults_assigned = false

local function signal_waybar(row_changed)
	if row_changed then
		hl.dispatch(hl.dsp.exec_cmd("pkill -RTMIN+2 waybar"))
	end
	hl.dispatch(hl.dsp.exec_cmd("pkill -RTMIN+1 waybar"))
end

-- Funktion: Vertikaler Sprung (Zeilenwechsel) – nur auf dem fokussierten Monitor
-- is_move = true: aktives Fenster mitnehmen (in die gleiche Spalte der Zielzeile)
local function jump_to_row(new_row, is_move)
	local mon_idx, _, col = matrix.state()

	-- Wrap-around: Von Zeile 6 nach unten springt zu Zeile 1 und umgekehrt
	new_row = new_row % matrix.rows

	local target = matrix.workspace_id(mon_idx, new_row, col)

	-- 1. Animation dynamisch auf vertikal stellen
	hl.dispatch(hl.dsp.exec_cmd("hyprctl keyword animation 'workspaces, 1, 4, default, slidevert'"))

	-- 2. Zum Ziel-Workspace springen (immer auf dem aktuellen Monitor), ggf. mit Fenster
	if is_move then
		hl.dispatch(hl.dsp.window.move({ workspace = target, follow = true }))
	else
		hl.dispatch(hl.dsp.focus({ workspace = target, on_current_monitor = true }))
	end

	-- 3. Kurzes Feedback & Signal für Waybar Zeilenanzeige & Workspaces
	hl.dispatch(hl.dsp.exec_cmd("notify-send 'Zeile " .. (new_row + 1) .. " aktiv' -t 400"))
	signal_waybar(true)
end

-- Relativer Zeilensprung ausgehend von der aktuellen Zeile des fokussierten Monitors
local function jump_row_relative(delta, is_move)
	local _, row = matrix.state()
	jump_to_row(row + delta, is_move)
end

-- Funktion: Horizontaler Sprung (Spaltenwechsel innerhalb der Zeile des fokussierten Monitors)
local function jump_to_col(new_col, is_move)
	local mon_idx, row = matrix.state()
	local target = matrix.workspace_id(mon_idx, row, new_col)

	-- Animation dynamisch zurück auf horizontal stellen
	hl.dispatch(hl.dsp.exec_cmd("hyprctl keyword animation 'workspaces, 1, 4, default, slide'"))

	if is_move then
		hl.dispatch(hl.dsp.window.move({ workspace = target }))
	else
		hl.dispatch(hl.dsp.focus({ workspace = target, on_current_monitor = true }))
	end

	-- Signal für Waybar Workspaces
	signal_waybar(false)
end

-- 1. Mapping der Corsair G-Keys (Direkter Zeilensprung)
local g_key_map = {
	["XF86Tools"] = 0, -- G1
	["XF86Launch5"] = 1, -- G2
	["XF86Launch6"] = 2, -- G3
	["XF86Launch7"] = 3, -- G4
	["XF86Launch8"] = 4, -- G5
	["XF86Launch9"] = 5, -- G6
}

for key, row_idx in pairs(g_key_map) do
	hl.bind(key, function()
		jump_to_row(row_idx)
	end)
end

-- 2. Up / Down für relative Zeilensprünge (nur fokussierter Monitor)
hl.bind(mainMod .. " + up", function()
	-- Hyprland ID-Logik: ID wird kleiner = Slide nach oben
	jump_row_relative(-1)
end)

hl.bind(mainMod .. " + down", function()
	-- Hyprland ID-Logik: ID wird größer = Slide nach unten
	jump_row_relative(1)
end)

-- SUPER + SHIFT + Up / Down: aktives Fenster eine Zeile nach oben/unten verschieben
hl.bind(mainMod .. " + SHIFT + up", function()
	jump_row_relative(-1, true)
end)

hl.bind(mainMod .. " + SHIFT + down", function()
	jump_row_relative(1, true)
end)

-- 3. Workspace-Navigation (SUPER + Ziffer)
for i = 1, matrix.cols do
	local key = tostring(i)

	-- Springen (Horizontal)
	hl.bind(mainMod .. " + " .. key, function()
		jump_to_col(i, false)
	end)

	-- Fenster Verschieben (Horizontal)
	hl.bind(mainMod .. " + SHIFT + " .. key, function()
		jump_to_col(i, true)
	end)
end

--------------------------------------------------
-- HYPRLAND MATRIX NAVIGATION --- END
--------------------------------------------------

-- 1. Lokale machine.lua laden
local has_machine, machine = pcall(require, "machine")
if not has_machine then
	machine = {}
end
--

-- Default-Workspaces pro Monitor (WS 1 / 31 / 61 ...), falls machine.lua das nicht schon
-- erledigt hat (ubuntu.lua macht es anhand der Monitor-Profile)
if not _G.__matrix_defaults_assigned then
	matrix.assign_defaults_from_current()
end

-- Nach Start, Reload und Hotplug Workspaces zu ihrem Monitor zurückschieben und den zuletzt
-- sichtbaren Workspace pro Monitor wiederherstellen (z.B. nach Ab-/Anstecken der Monitore)
matrix.schedule_restore(1000)
hl.on("hyprland.start", function()
	matrix.schedule_restore(1000)
end)
hl.on("monitor.added", function()
	-- etwas länger warten: Ubuntu lädt nach dem Anstecken erst noch das Monitor-Profil neu
	matrix.schedule_restore(2500)
end)
hl.on("monitor.removed", function()
	matrix.schedule_restore(1000)
end)
hl.on("workspace.active", function()
	matrix.remember()
end)

if machine.binds then
	for _, b in ipairs(machine.binds) do
		local key_combo = b[1]

		-- Falls KEIN " + " im String existiert (z.B. reine Medientasten wie XF86...),
		-- hängen wir ein leeres Präfix an, damit die v0.55+ API die Taste sauber parst.
		if not key_combo:find("%+") then
			key_combo = " + " .. key_combo
		end

		hl.bind(key_combo, hl.dsp.exec_cmd(b[2]), { repeating = b.repeating })
	end
end

--2. Declarative Config (Settings, Rules, Looks)
hl.config({
	autogenerated = false,
	ecosystem = {
		enforce_permissions = true,
	},
	-- Monitore aus der machine.lua laden
	monitor = machine.monitors or { { ",", "preferred", "auto", 1 } },

	env = {
		{ "XCURSOR_SIZE", "24" },
		{ "HYPRCURSOR_SIZE", "24" },
		{ "QT_QPA_PLATFORMTHEME", "qt6ct" },
		{ "GDK_BACKEND", "wayland,x11,*" },
		{ "QT_QPA_PLATFORM", "wayland;xcb" },
		{ "SDL_VIDEODRIVER", "wayland" },
		{ "CLUTTER_BACKEND", "wayland" },
		{ "XDG_CURRENT_DESKTOP", "Hyprland" },
		{ "XDG_SESSION_TYPE", "wayland" },
		{ "XDG_SESSION_DESKTOP", "Hyprland" },
	},

	general = {
		gaps_in = 5,
		gaps_out = 15,
		border_size = 2,
		["col.active_border"] = "rgba(509475ff)",
		["col.inactive_border"] = "rgba(111c18ff)",
		resize_on_border = true,
		allow_tearing = false,
		layout = "dwindle",
	},

	decoration = {
		rounding = 10,
		rounding_power = 2,
		active_opacity = 1.0,
		inactive_opacity = 1.0,
		shadow = { enabled = true, range = 4, render_power = 3, color = "rgba(1a1a1aff)" },
		blur = { enabled = true, size = 3, passes = 1, vibrancy = 0.1696 },
	},

	animations = {
		enabled = true,
		bezier = {
			{ "easeOutQuint", 0.23, 1, 0.32, 1 },
			{ "easeInOutCubic", 0.65, 0.05, 0.36, 1 },
			{ "linear", 0, 0, 1, 1 },
			{ "almostLinear", 0.5, 0.5, 0.75, 1 },
			{ "quick", 0.15, 0, 0.1, 1 },
		},
		animation = {
			{ "global", 1, 10, "default" },
			{ "border", 1, 5.39, "easeOutQuint" },
			{ "windows", 1, 4.79, "easeOutQuint" },
			{ "windowsIn", 1, 4.1, "easeOutQuint", "popin 87%" },
			{ "windowsOut", 1, 1.49, "linear", "popin 87%" },
			{ "fadeIn", 1, 1.73, "almostLinear" },
			{ "fadeOut", 1, 1.46, "almostLinear" },
			{ "fade", 1, 3.03, "quick" },
			{ "layers", 1, 3.81, "easeOutQuint" },
			{ "layersIn", 1, 4, "easeOutQuint", "fade" },
			{ "layersOut", 1, 1.5, "linear", "fade" },
			{ "fadeLayersIn", 1, 1.79, "almostLinear" },
			{ "fadeLayersOut", 1, 1.39, "almostLinear" },
			{ "workspaces", 1, 1.94, "almostLinear", "fade" },
			{ "workspacesIn", 1, 1.21, "almostLinear", "fade" },
			{ "workspacesOut", 1, 1.94, "almostLinear", "fade" },
			{ "zoomFactor", 1, 7, "quick" },
		},
	},

	dwindle = { preserve_split = true },
	master = { new_status = "master" },
	misc = { force_default_wallpaper = -1, disable_hyprland_logo = false, vrr = 1 },

	input = {
		kb_layout = "de",
		follow_mouse = 1,
		sensitivity = 0,
		touchpad = { natural_scroll = true },
	},

	xwayland = {
		force_zero_scaling = true,
	},
}) -- HIER ENDET hl.config()

hl.permission({
	binary = "/usr/bin/deskflow",
	type = "input-capture",
	mode = "allow",
})
-- #######################################################################################
-- 2.1 Gestures, Devices & Window Rules (Eigenständige Funktionen)
-- #######################################################################################

-- 3-Finger-Geste aktivieren
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- Spezifische Geräteeinstellungen
hl.device({ name = "epic-mouse-v1", sensitivity = -0.5 })

-- Fensterregeln (windowrules)
hl.window_rule({
	name = "suppress-maximize-events",
	match = { class = ".*" },
	suppress_event = "maximize",
})

hl.window_rule({
	name = "fix-xwayland-drags",
	match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
	no_focus = true,
})

hl.window_rule({
	name = "move-hyprland-run",
	match = { class = "hyprland-run" },
	move = "20 monitor_h-120",
	float = true,
})

hl.window_rule({
	name = "render-unfocused-steam-games",
	match = { class = "^(steam_app_.*)$" },
	render_unfocused = true,
})

hl.window_rule({
	name = "render-unfocused-gamescope",
	match = { class = "^(gamescope)$" },
	render_unfocused = true,
})

-- Roter Rand, solange im Fenster sudo läuft (siehe sudo_border.lua)
local has_sudo_border, sudo_border = pcall(require, "sudo_border")
if has_sudo_border then
	-- pcall: ein Fehler hier (z.B. andere Hyprland-Version) soll nicht die ganze Config abbrechen
	pcall(sudo_border.setup, {
		color = "rgb(e04545)",
		-- Wie lange sudo das Passwort speichert (sudoers: timestamp_timeout), pro Gerät in machine.lua
		cache_seconds = (machine.sudo_cache_minutes or 15) * 60,
	})
end

-- Umgebungsvariablen aus machine.lua mergen
if machine.env then
	for _, e in ipairs(machine.env) do
		hl.exec_cmd("hyprctl keyword env " .. e[1] .. "," .. e[2])
	end
end

-- 3. Autostart Hook
hl.on("hyprland.start", function()
	local cmds = {
		"dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE",
		"systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE",
		"killall xdg-desktop-portal-hyprland; /usr/lib/xdg-desktop-portal-hyprland &",
		"killall xdg-desktop-portal; /usr/lib/xdg-desktop-portal &",
		"wl-paste --type text --watch cliphist store &",
		"wl-paste --type image --watch cliphist store &",
		"sleep 1 && waybar",
		"mako &",
		"hyprctl setcursor Adwaita 24",
		"gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'",
		"~/.local/bin/trcc gui",
		"sleep 6 && pipeweaver-daemon --background",
		"/home/raphaelk/automation/spotify.sh",
		"linux-wallpaperengine --screen-root DP-2 --silent 3120881329",
		"lan-mouse daemon",
		"kdeconnectd",
		-- Config: hypridle.conf (machine.lua kann per HYPRIDLE_CONFIG eine eigene setzen)
		'pgrep -x hypridle || hypridle ${HYPRIDLE_CONFIG:+-c "$HYPRIDLE_CONFIG"}',
	}

	-- Globale Autostarts ausführen
	for _, cmd in ipairs(cmds) do
		hl.exec_cmd(cmd)
	end

	-- Gerätespezifische Autostarts aus der machine.lua ausführen
	if machine.autostart then
		for _, cmd in ipairs(machine.autostart) do
			hl.exec_cmd(cmd)
		end
	end
end)

-- 4. Keybinds (Echt Nativ)
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen(1))
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(
	mainMod .. " + M",
	hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch exit")
)
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind("ALT + Space", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + X", hl.dsp.exec_cmd("python3 /home/raphaelk/dotfiles/waybar/scripts/rofi_powermenu.py"))
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd(screenshotMenu))
hl.bind(mainMod .. " + P", function()
	hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
	hl.dispatch(hl.dsp.window.pin())
end)
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("python3 /home/raphaelk/dotfiles/waybar/scripts/rofi_bluetooth.py"))
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("python3 /home/raphaelk/dotfiles/waybar/scripts/rofi_media.py"))

hl.bind(mainMod .. " + U", hl.dsp.window.move({ workspace = "special:magic" }))
hl.bind(mainMod .. " + I", hl.dsp.workspace.toggle_special("magic"))

-- Headless Script
hl.bind(
	mainMod .. " + R",
	hl.dsp.exec_cmd(
		'bash -c "killall wayvnc; hyprctl keyword monitor HEADLESS-2,disable; hyprctl output create headless && sleep 1 && hyprctl keyword monitor HEADLESS-2,1920x1080@60,1920x0,1 && wayvnc --output HEADLESS-2 0.0.0.0 5900"'
	)
)
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("killall wayvnc && hyprctl keyword monitor HEADLESS-1,disable"))

-- Fokus verschieben
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
-- SUPER + up/down ist durch die Matrix-Navigation (Zeilenwechsel) belegt, siehe oben

-- Fenster auf den Nachbarmonitor links/rechts verschieben (landet auf dessen gerade offenem Workspace)
-- (SUPER + SHIFT + up/down verschiebt in die Zeile darüber/darunter, siehe Matrix-Navigation)
for _, dir in ipairs({ "left", "right" }) do
	hl.bind(mainMod .. " + SHIFT + " .. dir, function()
		matrix.move_window_to_monitor(dir)
	end)
end

-- Workspaces
-- for i = 1, 10 do
-- local key = i % 10 -- 10 maps to key 0
-- hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
-- hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
-- end

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- 5. Lautstärke & Helligkeit (Echt Nativ)
hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),
	{ repeating = true, locked = true }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
	{ repeating = true, locked = true }
)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind(
	"XF86MonBrightnessUp",
	hl.dsp.exec_cmd("/home/raphaelk/.config/hypr/scripts/change_brightness.sh up 5"),
	{ repeating = true, locked = true }
)
hl.bind(
	"XF86MonBrightnessDown",
	hl.dsp.exec_cmd("/home/raphaelk/.config/hypr/scripts/change_brightness.sh down 5"),
	{ repeating = true, locked = true }
)

-- 6. Playerctl & Screenshot (Echt Nativ)
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- Philips Monitor (Links, Hauptbildschirm)
hl.monitor({
	output = "desc:Philips Consumer Electronics Company PHL 322E1 0x00001FAE",
	mode = "1920x1080@75",
	position = "0x0",
	scale = 1,
})

-- Lenovo Laptop (Rechts)
hl.monitor({
	output = "desc:Lenovo Group Limited 0x403A",
	mode = "1920x1200@60",
	position = "1920x538",
	scale = 1.5,
})

-- Fallback-Regel (für alle anderen Monitore, die du evtl. mal ansteckst)
hl.monitor({
	output = "",
	mode = "preferred",
	position = "auto",
	scale = 1,
})
