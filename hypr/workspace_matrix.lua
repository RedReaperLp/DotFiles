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

-- Monitore, deren (leerer) aktiver Workspace nicht in ihrem eigenen Block liegt, auf ihren
-- ersten Workspace setzen (z.B. nach Hotplug, wenn Hyprland die nächste freie ID vergeben hat).
-- Workspaces mit Fenstern werden nicht angefasst.
function M.normalize()
	local active = hl.get_active_monitor()
	local changed = false
	for i, m in ipairs(M.ordered_monitors()) do
		local ws = m.active_workspace
		local base = (i - 1) * M.block
		if ws and ws.id and (ws.id <= base or ws.id > base + M.block) and (ws.windows or 0) == 0 then
			hl.dispatch(hl.dsp.focus({ monitor = m.name }))
			hl.dispatch(hl.dsp.focus({ workspace = base + 1, on_current_monitor = true }))
			changed = true
		end
	end
	if changed and active then
		hl.dispatch(hl.dsp.focus({ monitor = active.name }))
	end
end

return M
