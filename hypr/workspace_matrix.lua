-- workspace_matrix.lua – Workspace-Matrix pro Monitor (gemeinsam für CachyOS/Arch und Ubuntu)
--
-- Jeder Monitor hat eine eigene Matrix aus 6 Zeilen x 5 Spalten = 30 Workspaces:
--   Monitor 1 (ganz links) = WS  1–30, Monitor 2 = WS 31–60, Monitor 3 = WS 61–90, ...
-- Die Reihenfolge der Monitore ergibt sich aus der Anordnung (x, dann y).
-- SUPER+UP/DOWN, G-Tasten und SUPER+1..5 wirken nur auf den fokussierten Monitor.

local M = {}

M.cols = 5
M.rows = 6
M.block = M.cols * M.rows

local function is_virtual(m)
	return m.is_mirror or (m.name or ""):match("^HEADLESS") ~= nil
end

-- Monitore in Matrix-Reihenfolge: echte Monitore nach Position, virtuelle (HEADLESS/Mirror) dahinter
function M.ordered_monitors()
	local ok, mons = pcall(hl.get_monitors)
	if not ok or not mons then
		return {}
	end
	local list = {}
	for _, m in ipairs(mons) do
		if m.enabled ~= false then
			table.insert(list, m)
		end
	end
	table.sort(list, function(a, b)
		local va, vb = is_virtual(a), is_virtual(b)
		if va ~= vb then
			return vb
		end
		if a.x ~= b.x then
			return a.x < b.x
		end
		if a.y ~= b.y then
			return a.y < b.y
		end
		return a.name < b.name
	end)
	return list
end

-- 0-basierter Index des Monitors in der Matrix-Reihenfolge
function M.index_of(mon)
	if not mon then
		return 0
	end
	for i, m in ipairs(M.ordered_monitors()) do
		if m.name == mon.name then
			return i - 1
		end
	end
	return 0
end

function M.first_workspace(index)
	return index * M.block + 1
end

-- Workspace-ID für (Monitor-Index, Zeile 0-basiert, Spalte 1-basiert)
function M.workspace_id(index, row, col)
	return index * M.block + row * M.cols + col
end

-- Zeile (0-basiert) und Spalte (1-basiert) innerhalb der Matrix aus einer Workspace-ID
function M.row_col(id)
	if not id or id < 1 then
		return 0, 1
	end
	local rel = (id - 1) % M.block
	return math.floor(rel / M.cols), rel % M.cols + 1
end

-- Fokussierter Monitor + aktuelle Position in dessen Matrix
function M.state()
	local mon = hl.get_active_monitor()
	local ws = mon and mon.active_workspace
	local row, col = M.row_col(ws and ws.id)
	return M.index_of(mon), row, col
end

-- Logische Geometrie eines Monitors (Skalierung und Drehung berücksichtigt)
local function geometry(m)
	local w, h = m.width / m.scale, m.height / m.scale
	if (m.transform or 0) % 2 == 1 then
		w, h = h, w
	end
	return m.x, m.y, w, h
end

-- Nächster Monitor in Richtung "left"/"right"/"up"/"down" vom fokussierten Monitor aus.
-- Monitore, die sich auf der Querachse überlappen, werden bevorzugt.
function M.monitor_in_direction(dir)
	local cur = hl.get_active_monitor()
	if not cur then
		return nil
	end
	local cx, cy, cw, ch = geometry(cur)
	local best, best_score
	for _, m in ipairs(M.ordered_monitors()) do
		if m.name ~= cur.name and not is_virtual(m) then
			local x, y, w, h = geometry(m)
			local dist, overlap
			if dir == "left" then
				dist, overlap = cx - (x + w), math.min(cy + ch, y + h) - math.max(cy, y)
			elseif dir == "right" then
				dist, overlap = x - (cx + cw), math.min(cy + ch, y + h) - math.max(cy, y)
			elseif dir == "up" then
				dist, overlap = cy - (y + h), math.min(cx + cw, x + w) - math.max(cx, x)
			elseif dir == "down" then
				dist, overlap = y - (cy + ch), math.min(cx + cw, x + w) - math.max(cx, x)
			end
			if dist and dist > -1 then
				-- ohne Überlappung auf der Querachse nur nachrangig
				local score = dist + (overlap > 0 and 0 or 100000)
				if not best_score or score < best_score then
					best, best_score = m, score
				end
			end
		end
	end
	return best
end

-- Aktives Fenster auf den Workspace verschieben, der auf dem Nachbarmonitor gerade offen ist
function M.move_window_to_monitor(dir)
	local target = M.monitor_in_direction(dir)
	local ws = target and target.active_workspace
	if not ws or not ws.id then
		return
	end
	hl.dispatch(hl.dsp.window.move({ workspace = ws.id }))
	hl.dispatch(hl.dsp.exec_cmd("pkill -RTMIN+1 waybar"))
end

-- Default-Workspace-Regeln: Liste von { monitor = <Output/desc:...>, x = , y = }
-- Monitor ganz links bekommt WS 1, der nächste WS 31, ...
function M.assign_defaults(list)
	table.sort(list, function(a, b)
		if a.x ~= b.x then
			return a.x < b.x
		end
		return a.y < b.y
	end)
	for i, m in ipairs(list) do
		hl.workspace_rule({ workspace = tostring(M.first_workspace(i - 1)), monitor = m.monitor, default = true })
	end
	_G.__matrix_defaults_assigned = true
	return list
end

-- Fallback (z.B. CachyOS ohne ubuntu.lua): Regeln aus den aktuell angeschlossenen Monitoren
function M.assign_defaults_from_current()
	local list = {}
	for _, m in ipairs(M.ordered_monitors()) do
		if not is_virtual(m) then
			table.insert(list, { monitor = m.name, x = m.x, y = m.y })
		end
	end
	if #list > 0 then
		M.assign_defaults(list)
	end
end

-- Zuletzt sichtbarer Workspace pro Monitor (Schlüssel: Monitor-Beschreibung, damit es auch
-- bei wechselnden Port-Namen wie DP-5/DP-7 passt). Der Lua-Zustand wird bei jedem Reload neu
-- aufgebaut (Ubuntu lädt beim An-/Abstecken neu), daher in einer Datei unter $XDG_RUNTIME_DIR.
local state_file = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr-matrix-last-ws"
local last_ws = {}

local function load_last()
	local f = io.open(state_file, "r")
	if not f then
		return
	end
	for line in f:lines() do
		local desc, id = line:match("^(.-)\t(%d+)$")
		if desc then
			last_ws[desc] = tonumber(id)
		end
	end
	f:close()
end

local function save_last()
	local f = io.open(state_file, "w")
	if not f then
		return
	end
	for desc, id in pairs(last_ws) do
		f:write(desc .. "\t" .. id .. "\n")
	end
	f:close()
end

load_last()

-- Fenster, die beim Abstecken in eine Zeile des verbleibenden Monitors geparkt wurden:
-- address -> { origin = <ursprünglicher WS>, target = <Park-WS>, class = <Fensterklasse> }
-- (ebenfalls in einer Datei, weil Ubuntu beim Abstecken neu lädt). Die Klasse dient als Kontrolle,
-- weil Hyprland Adressen geschlossener Fenster wiederverwendet.
local parked_file = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/hypr-matrix-parked"
local parked = {}

local function load_parked()
	local f = io.open(parked_file, "r")
	if not f then
		return
	end
	for line in f:lines() do
		local addr, origin, target, class = line:match("^(%S+)\t(%d+)\t(%d+)\t?(.*)$")
		if addr then
			parked[addr] = { origin = tonumber(origin), target = tonumber(target), class = class }
		end
	end
	f:close()
end

local function save_parked()
	-- erst komplett zusammenbauen, dann schreiben (eine leere Datei durch einen Fehler mittendrin
	-- würde sonst alle geparkten Fenster vergessen)
	local lines = {}
	for addr, p in pairs(parked) do
		if p.origin and p.target then
			table.insert(lines, addr .. "\t" .. p.origin .. "\t" .. p.target .. "\t" .. (p.class or "") .. "\n")
		end
	end
	local f = io.open(parked_file, "w")
	if not f then
		return
	end
	f:write(table.concat(lines))
	f:close()
end

load_parked()

local function in_block(id, index)
	local base = index * M.block
	return id and id > base and id <= base + M.block
end

-- Während ein Restore aussteht (Hotplug/Reload), nichts merken – sonst würden die von Hyprland
-- beim Anstecken vergebenen Workspaces die gemerkten überschreiben.
M.restoring = false

-- Merkt sich für jeden Monitor den sichtbaren Workspace, sofern er im eigenen Block liegt
function M.remember()
	if M.restoring then
		return
	end
	local changed = false
	for i, m in ipairs(M.ordered_monitors()) do
		local ws = m.active_workspace
		if ws and in_block(ws.id, i - 1) and m.description and last_ws[m.description] ~= ws.id then
			last_ws[m.description] = ws.id
			changed = true
		end
	end
	if changed then
		save_last()
	end
end

-- Nach Start, Reload und Hotplug:
-- 0. Geparkte Fenster, deren Monitor wieder da ist, zurück auf ihren ursprünglichen Workspace
--    (auch wenn sie zwischendurch verschoben wurden; nur geschlossene Fenster werden vergessen).
-- 1. Jeder Workspace wandert zu dem Monitor, dem sein Block gehört (WS 31–60 -> Monitor 2, ...).
--    Fehlt der Monitor (abgesteckt), werden seine Fenster auf dem ersten Monitor in einer eigenen
--    Zeile geparkt: Monitor 2 -> Zeile 2 (WS 6–10), Monitor 3 -> Zeile 3 (WS 11–15), ...
--    Die Spalte bleibt erhalten (WS 33 -> WS 8). Beim Wiederanstecken greift Schritt 0.
-- 2. Jeder Monitor zeigt wieder den Workspace, der dort zuletzt sichtbar war.
--    Liegt der sichtbare Workspace außerhalb des eigenen Blocks und ist leer (z.B. von Hyprland
--    beim Hotplug vergeben), wird stattdessen der erste Workspace des Blocks gezeigt.
-- Hinweis: HL-Objekte (Workspace, Fenster, Monitor) werden bei jedem Feldzugriff live gelesen.
-- Verschiebt man das letzte Fenster aus einem Workspace, löscht Hyprland ihn sofort und ws.id
-- liefert nil. Deshalb wird hier zuerst alles in einfache Tabellen kopiert und erst dann verschoben.
local function snapshot()
	local mons = {}
	for _, m in ipairs(M.ordered_monitors()) do
		local ws = m.active_workspace
		table.insert(mons, {
			name = m.name,
			description = m.description or "",
			active_id = ws and ws.id,
			active_windows = ws and ws.windows or 0,
		})
	end
	local windows = {}
	local okw, wins = pcall(hl.get_windows)
	for _, w in ipairs(okw and wins or {}) do
		local ws = w.workspace
		table.insert(windows, { address = w.address, ws_id = ws and ws.id, class = w.class or "" })
	end
	local workspaces = {}
	local okws, wss = pcall(hl.get_workspaces)
	for _, ws in ipairs(okws and wss or {}) do
		local mon = ws.monitor
		if not ws.special and ws.id and ws.id > 0 then
			table.insert(workspaces, { id = ws.id, monitor = mon and mon.name })
		end
	end
	local active = hl.get_active_monitor()
	return mons, windows, workspaces, active and active.name
end

local function do_restore()
	local mons, windows, workspaces, active_name = snapshot()
	if #mons == 0 then
		return
	end
	local function owner_of(id)
		return mons[math.floor((id - 1) / M.block) + 1]
	end
	local by_addr = {}
	for _, w in ipairs(windows) do
		by_addr[w.address] = w
	end

	-- 0. Geparkte Fenster zurück auf ihren ursprünglichen Workspace, sobald ihr Monitor wieder da
	--    ist – auch wenn sie inzwischen von Hand verschoben wurden
	local unpark = {}
	for addr, p in pairs(parked) do
		local w = by_addr[addr]
		if not w or ((p.class or "") ~= "" and w.class ~= p.class) then
			-- Fenster geschlossen (Adresse ggf. von einem neuen Fenster wiederverwendet) -> vergessen
			parked[addr] = nil
		elseif owner_of(p.origin) then
			table.insert(unpark, { address = addr, ws = p.origin })
			parked[addr] = nil
		end
	end

	-- 1a. Fenster von Workspaces fehlender Monitore parken (Monitor k -> Zeile k auf Monitor 1)
	local park = {}
	for _, w in ipairs(windows) do
		if w.ws_id and w.ws_id > 0 and not owner_of(w.ws_id) then
			local k = math.floor((w.ws_id - 1) / M.block)
			local _, col = M.row_col(w.ws_id)
			local target = M.workspace_id(0, k % M.rows, col)
			table.insert(park, { address = w.address, ws = target })
			parked[w.address] = { origin = w.ws_id, target = target, class = w.class }
		end
	end

	-- Zuordnung sichern, bevor irgendetwas verschoben wird
	save_parked()

	for _, mv in ipairs(unpark) do
		hl.dispatch(hl.dsp.window.move({ window = "address:" .. mv.address, workspace = mv.ws, follow = false }))
	end
	for _, mv in ipairs(park) do
		hl.dispatch(hl.dsp.window.move({ window = "address:" .. mv.address, workspace = mv.ws, follow = false }))
	end

	-- 1b. Workspaces zu ihrem Monitor zurückschieben (Liste neu lesen: Schritt 0 legt evtl. neue an)
	local _, _, workspaces_now = snapshot()
	for _, ws in ipairs(workspaces_now) do
		local owner = owner_of(ws.id)
		if owner and ws.monitor and ws.monitor ~= owner.name then
			hl.dispatch(hl.dsp.workspace.move({ workspace = ws.id, monitor = owner.name }))
		end
	end

	-- 2. Sichtbaren Workspace pro Monitor wiederherstellen
	local mons_now = snapshot()
	local changed = false
	for i, m in ipairs(mons_now) do
		local idx = i - 1
		local want = last_ws[m.description]
		if not in_block(want, idx) then
			want = nil
		end
		if not want and not in_block(m.active_id, idx) and m.active_windows == 0 then
			want = M.first_workspace(idx)
		end
		if want and want ~= m.active_id then
			hl.dispatch(hl.dsp.focus({ monitor = m.name }))
			hl.dispatch(hl.dsp.focus({ workspace = want, on_current_monitor = true }))
			changed = true
		end
	end
	if changed and active_name and hl.get_monitor(active_name) then
		hl.dispatch(hl.dsp.focus({ monitor = active_name }))
	end
end

function M.restore()
	local ok, err = pcall(do_restore)
	M.restoring = false
	if not ok then
		local msg = tostring(err):gsub("'", "")
		hl.exec_cmd("notify-send -u critical 'Workspace-Matrix: Restore fehlgeschlagen' '" .. msg .. "'")
	end
	M.remember()
end

-- Restore verzögert ausführen (mehrere Hotplug-Events kurz hintereinander zusammenfassen)
local restore_timer
function M.schedule_restore(delay_ms)
	M.restoring = true
	if restore_timer then
		restore_timer:set_enabled(false)
	end
	restore_timer = hl.timer(function()
		M.restore()
	end, { timeout = delay_ms or 1000, type = "oneshot" })
end

return M
