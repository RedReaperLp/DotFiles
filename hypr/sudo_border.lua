-- sudo_border.lua – roter Fensterrand, solange in einem Fenster sudo aktiv ist.
-- Gilt für CachyOS und Ubuntu (wird aus hyprland.lua geladen).
-- Gegenstück in fish: fish/conf.d/sudo_border.fish
--
-- Rot ist ein Fenster, wenn
--   1. sein Prozess oder ein Prozess darunter als root läuft (sudo -i, su -, Root-GUI-Programme ...)
--      oder darin sudo/sudo-rs/doas/run0/pkexec läuft (inkl. Passwortabfrage), oder
--   2. sudo in diesem Terminal das Passwort noch gespeichert hat (kein erneutes Passwort nötig).
--
-- Zu 2.: sudo kann den Cache nicht abfragen, ohne ihn zu verlängern. Daher:
--   - Dieser Timer schreibt "seen-<fish-pid>", wenn er sudo unter einer fish-Shell sieht.
--   - fish prüft danach EINMAL mit "sudo -n -v" und schreibt bei Erfolg "cached-<fish-pid>"
--     mit der Uhrzeit. "sudo -k" löscht die Markierung.
--   - Das Fenster bleibt rot, bis cache_seconds seit dieser Uhrzeit vergangen sind.

local M = {}

local TAG = "sudo"
-- Werkzeuge, die auch dann zählen, wenn der Prozess selbst (noch) nicht als root läuft (z.B. run0)
local PRIV_TOOLS = { sudo = true, ["sudo-rs"] = true, doas = true, run0 = true, pkexec = true }
local state_dir = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/sudo-border"
local cache_seconds = 900

local function read_first_line(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local line = f:read("l")
	f:close()
	return line
end

local function proc_info(pid)
	local stat = read_first_line("/proc/" .. pid .. "/stat")
	if not stat then
		return nil
	end
	-- Format: pid (comm) state ppid ... – comm kann Leerzeichen/Klammern enthalten
	local comm, ppid = stat:match("^%d+ %((.*)%) %S+ (%d+)")
	return comm, tonumber(ppid)
end

local function touch(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return
	end
	f = io.open(path, "w")
	if f then
		f:close()
	end
end

-- Elternkette ab pid in die Menge eintragen
local function add_ancestors(set, pid, on_each)
	local cur, depth = pid, 0
	while cur and cur > 1 and depth < 64 do
		local comm, ppid = proc_info(cur)
		if not comm then
			break
		end
		if on_each then
			on_each(cur, comm)
		end
		if set[cur] then
			break
		end
		set[cur] = true
		cur, depth = ppid, depth + 1
	end
end

local function privileged_ancestors()
	local set = {}

	-- 1. Laufende Root-Prozesse (effektive UID 0) und sudo/doas/run0/pkexec.
	--    Erfasst sudo -i, su -, als root gestartete GUI-Programme usw.
	--    System-Dienste hängen an systemd, nicht an einem Fenster -> kein Treffer.
	local p = io.popen("ps -e -o pid=,euid=,comm= 2>/dev/null")
	if p then
		for line in (p:read("a") or ""):gmatch("[^\n]+") do
			local pid, euid, comm = line:match("^%s*(%d+)%s+(%d+)%s+(.-)%s*$")
			pid, euid = tonumber(pid), tonumber(euid)
			local is_priv_tool = comm and PRIV_TOOLS[comm]
			if pid and (euid == 0 or is_priv_tool) then
				add_ancestors(set, pid, (comm == "sudo" or comm == "sudo-rs") and function(cur, c)
					if c == "fish" then
						touch(state_dir .. "/seen-" .. cur)
					end
				end or nil)
			end
		end
		p:close()
	end

	-- 2. Gespeicherte sudo-Passwörter (von fish gemeldet)
	local ls = io.popen("ls -1 '" .. state_dir .. "' 2>/dev/null")
	if ls then
		local now = os.time()
		for name in (ls:read("a") or ""):gmatch("[^\n]+") do
			local kind, pid = name:match("^(%a+)%-(%d+)$")
			pid = tonumber(pid)
			local path = state_dir .. "/" .. name
			local alive = pid and proc_info(pid) ~= nil
			if not alive then
				os.remove(path)
			elseif kind == "cached" then
				local t = tonumber(read_first_line(path) or "")
				if t and now - t < cache_seconds then
					add_ancestors(set, pid)
				else
					os.remove(path)
				end
			end
		end
		ls:close()
	end

	return set
end

local function has_tag(tags)
	if type(tags) == "table" then
		for _, t in ipairs(tags) do
			if t == TAG then
				return true
			end
		end
	elseif type(tags) == "string" then
		return (" " .. tags .. " "):find("[%s,]" .. TAG .. "[%s,]") ~= nil
	end
	return false
end

local function update()
	local ancestors = privileged_ancestors()
	local ok, windows = pcall(hl.get_windows)
	if not ok or not windows then
		return
	end
	for _, w in ipairs(windows) do
		local should = ancestors[w.pid] == true
		if should ~= has_tag(w.tags) then
			hl.dispatch(hl.dsp.window.tag({ tag = (should and "+" or "-") .. TAG, window = "address:" .. w.address }))
		end
	end
end

function M.setup(opts)
	opts = opts or {}
	local color = opts.color or "rgb(e04545)"
	local inactive = opts.inactive_color or color
	cache_seconds = opts.cache_seconds or cache_seconds

	os.execute("mkdir -p '" .. state_dir .. "' && chmod 700 '" .. state_dir .. "'")

	-- Zwei Farben: aktiv und inaktiv (mit nur einer Farbe wäre nur das fokussierte Fenster rot)
	hl.window_rule({
		name = "sudo-border",
		match = { tag = TAG },
		border_color = color .. " " .. inactive,
	})

	if _G.__sudo_border_timer then
		_G.__sudo_border_timer:set_enabled(false)
	end
	_G.__sudo_border_timer = hl.timer(function()
		pcall(update)
	end, { timeout = opts.interval or 1000, type = "repeat" })
end

return M
