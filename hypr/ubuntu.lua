-- ubuntu.lua – Zusatzlogik für den Ubuntu-Laptop (versioniert, aber nur aktiv,
-- wenn die lokale machine.lua sie per require("ubuntu").setup({...}) lädt).
-- hyprland.lua (CachyOS-Hauptsystem) bleibt davon unberührt.
--
-- Enthält:
--   1. XDG_DATA_DIRS um Snap/Flatpak/Nix ergänzen (sonst fehlen z.B. Firefox & Co. in Rofi)
--   2. Monitor-Profile je Arbeitsplatz (Integration mit nwg-displays)

local M = {}

local home = os.getenv("HOME")
local hypr_dir = home .. "/.config/hypr"

local function read_file(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local content = f:read("a")
	f:close()
	return content
end

--------------------------------------------------
-- 1. XDG_DATA_DIRS
-- Der env-Block in hl.config() wird von Hyprland (Lua) nicht angewendet, daher hl.env().
--------------------------------------------------
local function setup_xdg_data_dirs()
	local dirs, seen = {}, {}
	local function add(d)
		d = d:gsub("/+$", "")
		if d ~= "" and not seen[d] then
			seen[d] = true
			table.insert(dirs, d)
		end
	end
	for d in (os.getenv("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"):gmatch("[^:]+") do
		add(d)
	end
	for _, d in ipairs({
		"/var/lib/snapd/desktop",
		"/var/lib/flatpak/exports/share",
		home .. "/.local/share/flatpak/exports/share",
		home .. "/.nix-profile/share",
		"/nix/var/nix/profiles/default/share",
	}) do
		local f = io.open(d, "r")
		if f then
			f:close()
			add(d)
		end
	end
	hl.env("XDG_DATA_DIRS", table.concat(dirs, ":"))
end

--------------------------------------------------
-- 1b. CURSOR
-- Das per Nix gebaute Hyprland (libXcursor aus dem Nix-Store) sucht Cursor-Themes nur in
-- ~/.local/share/icons, ~/.icons und im Nix-Store – nicht in /usr/share/icons.
-- Ohne XCURSOR_PATH findet es Adwaita nicht und nutzt einen winzigen Fallback-Cursor.
--------------------------------------------------
local function setup_cursor(cursor)
	cursor = cursor or {}
	local theme = cursor.theme or "Adwaita"
	local size = tostring(cursor.size or 24)
	hl.env(
		"XCURSOR_PATH",
		home .. "/.local/share/icons:" .. home .. "/.icons:/usr/share/icons:/usr/share/pixmaps"
	)
	hl.env("XCURSOR_THEME", theme)
	hl.env("XCURSOR_SIZE", size)
	hl.env("HYPRCURSOR_THEME", theme)
	hl.env("HYPRCURSOR_SIZE", size)
	-- Auch bei jedem Reload anwenden (die Autostart-Zeile in hyprland.lua läuft nur beim Start)
	hl.exec_cmd("hyprctl setcursor " .. theme .. " " .. size)
	M.autostart_cursor = {
		"hyprctl setcursor " .. theme .. " " .. size,
		"gsettings set org.gnome.desktop.interface cursor-theme '" .. theme .. "'",
		"gsettings set org.gnome.desktop.interface cursor-size " .. size,
	}
end

--------------------------------------------------
-- 1c. HYPRIDLE-ZEITEN
-- hypridle.conf (Repo, gemeinsam mit CachyOS) hat zwei Listener: 1. sperren, 2. Bildschirm aus.
-- Hier wird eine Kopie mit gerätespezifischen Zeiten nach $XDG_RUNTIME_DIR geschrieben und
-- per HYPRIDLE_CONFIG bekannt gemacht (Autostart & Waybar starten hypridle mit -c, falls gesetzt).
--------------------------------------------------
local function setup_idle(idle)
	if not idle then
		return
	end
	local base = read_file(hypr_dir .. "/hypridle.conf")
	if not base then
		return
	end
	local values = { idle.lock, idle.screen_off }
	local n = 0
	local content = base:gsub("(\n%s*timeout%s*=%s*)(%d+)", function(prefix, old)
		n = n + 1
		return prefix .. tostring(values[n] or old)
	end)
	local path = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypridle-machine.conf"
	local f = io.open(path, "w")
	if f then
		f:write("# AUTOMATISCH ERZEUGT aus ~/.config/hypr/hypridle.conf (Zeiten aus machine.lua)\n" .. content)
		f:close()
		hl.env("HYPRIDLE_CONFIG", path)
	end
end

--------------------------------------------------
-- 2. MONITOR-PROFILE (nwg-displays)
-- nwg-displays schreibt hyprlang-Dateien (monitors.conf / workspaces.conf);
-- die Lua-API kennt kein "source", daher werden sie hier geparst.
-- Profil-Schlüssel = sortierte Beschreibungen aller angeschlossenen Monitore.
-- In nwg-displays anordnen -> "Anwenden" + bestätigen -> Profil für genau diese
-- Kombination wird gespeichert (mit desc:-Namen, da DP-1/DP-2 wechseln können).
-- Beim An-/Abstecken wird das passende Profil automatisch geladen.
--------------------------------------------------
local nwg_files = { hypr_dir .. "/monitors.conf", hypr_dir .. "/workspaces.conf" }
local profile_dir = hypr_dir .. "/monitor-profiles"

local function split_csv(s)
	local parts = {}
	for p in (s .. ","):gmatch("([^,]*),") do
		table.insert(parts, (p:gsub("^%s+", ""):gsub("%s+$", "")))
	end
	return parts
end

local function apply_monitor_lines(content)
	local specs, order = {}, {}
	local function get(name)
		if not specs[name] then
			specs[name] = { output = name }
			table.insert(order, name)
		end
		return specs[name]
	end

	for line in content:gmatch("[^\r\n]+") do
		local value = line:match("^%s*monitor%s*=%s*(.-)%s*$")
		if value then
			local p = split_csv(value)
			-- hyprlang escaped "#" als "##" (relevant für desc:-Namen)
			local spec = get((p[1]:gsub("##", "#")))
			local i
			if p[2] == "disable" then
				spec.disabled = true
				i = 3
			elseif p[2] == "transform" then
				i = 2
			else
				spec.mode, spec.position = p[2], p[3]
				spec.scale = tonumber(p[4]) or p[4]
				i = 5
			end
			-- Optionale Key/Value-Paare: transform, mirror, bitdepth, vrr, cm ...
			while p[i] and p[i + 1] do
				spec[p[i]] = tonumber(p[i + 1]) or p[i + 1]
				i = i + 2
			end
		end
	end

	local applied = {}
	for _, name in ipairs(order) do
		hl.monitor(specs[name])
		table.insert(applied, specs[name])
	end
	return applied
end

-- Default-Workspaces nach Position verteilen: Monitor ganz links = 1, nächster = 31, ...
-- (eigene Workspace-Matrix pro Monitor, siehe workspace_matrix.lua;
-- Hyprland verteilt sonst nach Monitor-ID, unabhängig von der Anordnung)
local function assign_workspaces_by_position(list)
	return require("workspace_matrix").assign_defaults(list)
end

local function apply_workspace_lines(content)
	for line in content:gmatch("[^\r\n]+") do
		local value = line:match("^%s*workspace%s*=%s*(.-)%s*$")
		if value then
			local p = split_csv(value)
			local rule = { workspace = p[1] }
			for i = 2, #p do
				local k, v = p[i]:match("^([%w_]+):(.*)$")
				if k == "monitor" then
					rule.monitor = (v:gsub("##", "#"))
				elseif k == "default" then
					rule.default = (v == "true")
				end
			end
			if rule.monitor then
				hl.workspace_rule(rule)
			end
		end
	end
end

local function current_monitors()
	local ok, mons = pcall(hl.get_monitors, { all = true })
	if not ok or not mons then
		return {}
	end
	return mons
end

local function setup_key()
	local descs = {}
	for _, m in ipairs(current_monitors()) do
		if not m.name:match("^HEADLESS") then
			table.insert(descs, (m.description:gsub("[^%w]+", "_")))
		end
	end
	table.sort(descs)
	return table.concat(descs, "+")
end

-- monitors.conf von nwg-displays (DP-1 ...) in desc:-Form umschreiben und als Profil speichern
local function save_profile(content)
	local key = setup_key()
	if key == "" then
		return
	end
	local name_to_desc = {}
	for _, m in ipairs(current_monitors()) do
		name_to_desc[m.name] = m.description
	end
	local out = { "# Monitor-Profil (automatisch aus nwg-displays gespeichert)" }
	for raw in content:gmatch("[^\r\n]+") do
		local line = raw
		local name, rest = line:match("^%s*monitor%s*=%s*([^,]+)(,.*)$")
		if name and name_to_desc[name] then
			line = "monitor=desc:" .. name_to_desc[name] .. rest
		end
		if not line:match("^%s*#") then
			table.insert(out, line)
		end
	end
	os.execute("mkdir -p '" .. profile_dir .. "'")
	local f = io.open(profile_dir .. "/" .. key .. ".conf", "w")
	if f then
		f:write(table.concat(out, "\n") .. "\n")
		f:close()
		hl.exec_cmd("notify-send 'Monitor-Profil gespeichert' -t 2000")
	end
end

local function setup_monitor_profiles(default_rules, auto_workspaces)
	_G.__monitor_setup_key = setup_key()
	local profile = (_G.__monitor_setup_key ~= "")
		and read_file(profile_dir .. "/" .. _G.__monitor_setup_key .. ".conf")
	local ws_targets = {}
	if profile then
		for _, s in ipairs(apply_monitor_lines(profile)) do
			local x, y = tostring(s.position or ""):match("^(-?%d+)x(-?%d+)$")
			if x and not s.disabled and not s.mirror then
				table.insert(ws_targets, { monitor = s.output, x = tonumber(x), y = tonumber(y) })
			end
		end
	else
		if default_rules then
			-- Unbekannter Arbeitsplatz: Defaults (z.B. Laptop-Skalierung), Rest "auto"
			for _, m in ipairs(default_rules) do
				hl.monitor(m)
			end
		end
		for _, m in ipairs(current_monitors()) do
			if m.enabled and not m.name:match("^HEADLESS") then
				table.insert(ws_targets, { monitor = m.name, x = m.x, y = m.y })
			end
		end
	end
	if auto_workspaces ~= false then
		M.workspace_order = assign_workspaces_by_position(ws_targets)
	else
		-- workspaces.conf aus nwg-displays nummeriert 1, 2, 3 ... und würde die
		-- Workspace-Matrix pro Monitor (1 / 31 / 61 ...) durchkreuzen -> nur ohne auto_workspaces
		local ws_content = read_file(nwg_files[2])
		if ws_content then
			apply_workspace_lines(ws_content)
		end
	end

	-- Auf "Anwenden" in nwg-displays reagieren: Dateien alle 2s vergleichen
	local snapshot = {}
	for idx, path in ipairs(nwg_files) do
		snapshot[idx] = read_file(path) or ""
	end
	if _G.__nwg_watch then
		_G.__nwg_watch:set_enabled(false)
	end
	_G.__nwg_watch = hl.timer(function()
		for idx, path in ipairs(nwg_files) do
			local now = read_file(path) or ""
			if now ~= snapshot[idx] then
				snapshot[idx] = now
				if idx == 1 then
					save_profile(now)
				end
				hl.exec_cmd("hyprctl reload")
				return
			end
		end
	end, { timeout = 2000, type = "repeat" })

	-- Monitor an-/abgesteckt: nach kurzer Wartezeit neu laden, wenn sich die Kombination geändert hat
	local function on_monitor_change()
		if _G.__monitor_debounce then
			_G.__monitor_debounce:set_enabled(false)
		end
		_G.__monitor_debounce = hl.timer(function()
			if setup_key() ~= _G.__monitor_setup_key then
				hl.exec_cmd("hyprctl reload")
			end
		end, { timeout = 1500, type = "oneshot" })
	end
	if not _G.__monitor_hooks then
		_G.__monitor_hooks = true
		hl.on("monitor.added", on_monitor_change)
		hl.on("monitor.removed", on_monitor_change)
	end
end

--------------------------------------------------
-- Einstiegspunkt
--------------------------------------------------
function M.setup(opts)
	opts = opts or {}
	-- Gerätespezifische Permissions (enforce_permissions ist in hyprland.lua aktiv).
	-- Achtung: Änderungen greifen erst nach einem Neustart von Hyprland.
	for _, p in ipairs(opts.permissions or {}) do
		hl.permission(p)
	end
	setup_xdg_data_dirs()
	setup_idle(opts.idle)
	setup_cursor(opts.cursor)
	setup_monitor_profiles(opts.default_monitor_rules, opts.auto_workspaces)

	-- Autostart-Befehle, die machine.lua übernimmt
	M.autostart = {
		-- Variablen auch an D-Bus/systemd weitergeben (Portale, D-Bus-aktivierte Apps)
		"dbus-update-activation-environment --systemd XDG_DATA_DIRS XCURSOR_PATH XCURSOR_THEME XCURSOR_SIZE",
	}
	for _, cmd in ipairs(M.autostart_cursor) do
		table.insert(M.autostart, cmd)
	end
end

M.autostart = {}

return M
