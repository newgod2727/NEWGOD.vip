-- HACKFORMAT - it owns nothing. It edits what is already there.
--
--   loadstring(game:HttpGet("https://newgod.vip/format"))()
--
-- His words, 2026-08-21:
--   "hackformat was chaning all GUI ... it was not having any thing or shit, it
--    shouldnt incuding anything it was only incuidng edit thing, it shoudlnt pop
--    any gui or others, it was will format all to my gold style and make sure the
--    whole thing all others cleint and fucking thing will be solve"
--   "it was at suepr mant different ways to boosting, incuding fiixng my that
--    crashed ... it will make sure all scirpt or others scipt will fixing those
--    bug also auto ... after detect the cleint got banned or kicked it will hop
--    to the sever again"
--
-- So: no panel, no timer, no readout, no notification, nothing to click. The
-- only two Instances it ever creates are a UICorner and a UIStroke, and both are
-- edits to something that already exists.
--
-- Five jobs.
--   FORMAT   every menu any script drew, repainted into the gold style, kept
--            that way as new ones arrive, and made draggable.
--   BOOST    the render side stripped down once the map has actually arrived,
--            in bites small enough not to make the stutter it removes.
--   REPAIR   the bugs other hubs ship with - stacked copies, off-screen panels,
--            panels buried under the game, panels lost on respawn, void falls.
--   SURVIVE  the things that close the client, fixed unasked, and a hop to a
--            DIFFERENT server if the client is thrown out.
--   SYNC     a light version check-in with the tool's home, so a fix can reach
--            a build that is already running and a fault in a game it was never
--            tried in comes back attached to that build instead of vanishing.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Http = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")

local env = getgenv and getgenv() or _G
env.__HF_GEN = (env.__HF_GEN or 0) + 1
local MYGEN = env.__HF_GEN
local function alive() return env.__HF_GEN == MYGEN end

local HF = {}
HF.VERSION = "2026-08-21c"

local BG    = Color3.fromRGB(11, 11, 14)
local BAR   = Color3.fromRGB(24, 20, 14)
local EDGE  = Color3.fromRGB(201, 142, 74)
local GOLD  = Color3.fromRGB(255, 179, 71)
local WARM  = Color3.fromRGB(243, 207, 153)
local TEXT  = Color3.fromRGB(200, 190, 175)
local INK   = Color3.fromRGB(20, 17, 13)
local TRACK = Color3.fromRGB(30, 26, 20)

local DIR = "RobloxComm/hf"
local POSFILE = DIR .. "/panel_pos.json"

local function note(line)
	pcall(function()
		if not isfolder("RobloxComm") then makefolder("RobloxComm") end
		if not isfolder(DIR) then makefolder(DIR) end
		local text = os.date("%Y-%m-%d %H:%M:%S") .. "  " .. line .. string.char(10)
		if isfile(DIR .. "/format.log") then
			appendfile(DIR .. "/format.log", text)
		else
			writefile(DIR .. "/format.log", text)
		end
	end)
end

local NOT_MINE = {
	RobloxGui = true, RobloxPromptGui = true, RobloxLoadingGui = true,
	PurchasePrompt = true, DevConsoleMaster = true, PlayerListMaster = true,
	Chat = true, TopBarApp = true, InGameMenu = true, VirtualCursorGui = true,
	VRHub = true, TouchGui = true, ControlGui = true, BubbleChat = true,
}

-- ONLY WHERE THE EXECUTOR PUTS THINGS. NOT ALL OF CoreGui.
--
-- Measured 2026-08-22 15:2x on this client. gethui() answers RobloxGui and its
-- children are ours: SoloPlay, SoloRec, SoloFarm, SoloTeam, XpBar and Vape.
-- CoreGui's own children are not, and the NOT_MINE list below only names about
-- a dozen of them - it does not name ExperienceChat, SystemScrim,
-- PurchasePromptApp, TeleportEffectGui, ShortcutBar, FoundationOverlay,
-- CaptureOverlay, InExperienceInterventionApp or any of the rest that were
-- sitting there when this was counted.
--
-- Scanning CoreGui therefore meant repainting Roblox's own overlays gold,
-- forcing DisplayOrder 9200 on them and hanging drag handlers off them. This
-- file is supposed to format HIS panels, not take over the platform's UI, so it
-- reads gethui only and falls back to CoreGui just for the executors that do
-- not provide one.
local function containers()
	local out = {}
	local h = gethui and gethui()
	if h then
		out[#out + 1] = h
		return out
	end
	pcall(function() out[#out + 1] = game:GetService("CoreGui") end)
	return out
end

-- ------------------------------------------------------------ drag

local function posLoad(key, frame)
	pcall(function()
		if not isfile(POSFILE) then return end
		local t = Http:JSONDecode(readfile(POSFILE))
		local v = t and t[key]
		-- The UDim2 is stored, never AbsolutePosition. AbsolutePosition already
		-- carries the 36 pixel Roblox top inset, so writing it back as a plain
		-- offset walks the panel a little further down on every reload.
		if v and tonumber(v.xo) and tonumber(v.yo) then
			frame.Position = UDim2.new(tonumber(v.xs) or 0, tonumber(v.xo),
				tonumber(v.ys) or 0, tonumber(v.yo))
		end
	end)
end

local function posSave(key, frame)
	pcall(function()
		if not isfolder("RobloxComm") then makefolder("RobloxComm") end
		if not isfolder(DIR) then makefolder(DIR) end
		local t = {}
		if isfile(POSFILE) then
			local ok, d = pcall(function() return Http:JSONDecode(readfile(POSFILE)) end)
			if ok and type(d) == "table" then t = d end
		end
		local p = frame.Position
		t[key] = { xs = p.X.Scale, xo = p.X.Offset, ys = p.Y.Scale, yo = p.Y.Offset }
		writefile(POSFILE, Http:JSONEncode(t))
	end)
end

-- Active has to be true on the frame AND on the handle. Measured on the live
-- client 2026-08-21: all four panels had Active false, so a Frame never received
-- InputBegan for a mouse button and the click fell through to whatever sat
-- underneath. That was the whole of "it was fucking siepr hard to dag".
local function makeDrag(key, frame, handle)
	if frame:GetAttribute("HFDrag") then return end
	frame:SetAttribute("HFDrag", true)
	frame.Active = true
	handle.Active = true
	posLoad(key, frame)
	local dragging, startPos, startMouse = false, nil, nil
	handle.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1
			or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			startPos = frame.Position
			startMouse = i.Position
		end
	end)
	UIS.InputChanged:Connect(function(i)
		if not dragging then return end
		if i.UserInputType ~= Enum.UserInputType.MouseMovement
			and i.UserInputType ~= Enum.UserInputType.Touch then return end
		local d = i.Position - startMouse
		frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
			startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end)
	UIS.InputEnded:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseButton1
			or i.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			posSave(key, frame)
		end
	end)
end

-- ------------------------------------------------------------ format

local function corner(inst, r)
	local c = inst:FindFirstChildOfClass("UICorner")
	if not c then c = Instance.new("UICorner") c.Parent = inst end
	c.CornerRadius = UDim.new(0, r)
end

local function stroke(inst)
	local s = inst:FindFirstChildOfClass("UIStroke")
	if not s then s = Instance.new("UIStroke") s.Parent = inst end
	s.Color = EDGE
	s.Thickness = 2
end

local function looksLikeBar(f)
	if not f:IsA("Frame") then return false end
	if f.Size.Y.Scale > 0.4 then return false end
	if f.Size.Y.Offset > 36 or f.Size.Y.Offset < 14 then return false end
	if f.Size.X.Scale < 0.8 then return false end
	return f.Position.Y.Offset <= 2 and f.Position.Y.Scale <= 0.02
end

local function paintText(t, inBar)
	if t:IsA("TextLabel") then
		t.Font = inBar and Enum.Font.GothamBold or Enum.Font.Gotham
		if inBar then
			t.TextColor3 = GOLD
		elseif t.TextSize >= 20 then
			t.TextColor3 = WARM
		else
			t.TextColor3 = TEXT
		end
	elseif t:IsA("TextButton") then
		t.Font = Enum.Font.GothamBold
		t.BackgroundColor3 = EDGE
		t.TextColor3 = INK
		t.BorderSizePixel = 0
		t.AutoButtonColor = true
		corner(t, 6)
	elseif t:IsA("TextBox") then
		t.Font = Enum.Font.Gotham
		t.BackgroundColor3 = TRACK
		t.TextColor3 = WARM
		t.BorderSizePixel = 0
		corner(t, 6)
	end
end

local function repairGui(gui)
	pcall(function() gui.ResetOnSpawn = false end)
	pcall(function()
		if gui.DisplayOrder < 1000 then gui.DisplayOrder = 9200 end
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	end)
	pcall(function()
		local parent = gui.Parent
		if not parent then return end
		for _, other in ipairs(parent:GetChildren()) do
			if other ~= gui and other:IsA("ScreenGui") and other.Name == gui.Name
				and not NOT_MINE[other.Name] then
				other:Destroy()
				note("removed a stacked copy of " .. gui.Name)
			end
		end
	end)
end

-- ONCE PER FRAME INSTANCE, NEVER IN A LOOP.
--
-- Measured 2026-08-22 15:27: format.log had one "pulled TopFrame back on
-- screen" line every single second, without end. The repaint pass runs once a
-- second, and a frame that its own script parks off screen on purpose - a
-- hidden or animated panel - gets yanked back, put away again by its owner, and
-- yanked back a second later. We were fighting somebody else's UI forever and
-- writing a log line about it each time.
--
-- The repair this is for is a real one and it happens once: a panel whose saved
-- position came off a bigger screen opens outside the viewport and cannot be
-- reached. Doing that a second time is not a repair, it is a tug of war.
--
-- Invisible frames are skipped outright. A frame nobody can see is not stranded.
local function pullOnScreen(top)
	pcall(function()
		if top:GetAttribute("HFPulled") then return end
		if top.Visible == false then return end
		local cam = workspace.CurrentCamera
		if not cam then return end
		local vp = cam.ViewportSize
		-- Before the camera has a real viewport this reads 1x1, and then every
		-- panel on the right hand side of a 1920 wide screen looks off screen and
		-- gets dragged to 24,120. Measured 15:29:39 - it moved his SoloTeam panel.
		if vp.X < 200 or vp.Y < 200 then return end
		local p = top.AbsolutePosition
		if p.X < -40 or p.Y < -10 or p.X > vp.X - 40 or p.Y > vp.Y - 20 then
			top:SetAttribute("HFPulled", true)
			top.Position = UDim2.new(0, 24, 0, 120)
			note("pulled " .. top:GetFullName() .. " back on screen (once)")
		end
	end)
end

local function paintPanel(gui)
	if NOT_MINE[gui.Name] then return end
	repairGui(gui)
	for _, top in ipairs(gui:GetChildren()) do
		if top:IsA("Frame") or top:IsA("ScrollingFrame") then
			top.BackgroundColor3 = BG
			top.BorderSizePixel = 0
			corner(top, 12)
			stroke(top)
			pullOnScreen(top)
			local bar
			for _, kid in ipairs(top:GetChildren()) do
				if looksLikeBar(kid) then bar = kid break end
			end
			if bar then
				bar.BackgroundColor3 = BAR
				bar.BorderSizePixel = 0
				corner(bar, 12)
				makeDrag(gui.Name .. "/" .. top.Name, top, bar)
			else
				makeDrag(gui.Name .. "/" .. top.Name, top, top)
			end
			for _, d in ipairs(top:GetDescendants()) do
				local inBar = bar ~= nil and d:IsDescendantOf(bar)
				if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
					pcall(paintText, d, inBar)
				elseif d:IsA("UIStroke") then
					d.Color = EDGE
				elseif d:IsA("Frame") and d ~= bar then
					if d.Size.Y.Offset > 0 and d.Size.Y.Offset <= 26 and d.Size.X.Scale >= 0.5 then
						if d.BackgroundColor3 ~= GOLD then d.BackgroundColor3 = TRACK end
						corner(d, math.floor(d.Size.Y.Offset / 2))
					end
				end
			end
		end
	end
end

local dirty = {}

local function sweepAll()
	for _, host in ipairs(containers()) do
		pcall(function()
			for _, gui in ipairs(host:GetChildren()) do
				if gui:IsA("ScreenGui") and not NOT_MINE[gui.Name] then
					dirty[gui] = true
				end
			end
		end)
	end
end

local function hookHosts()
	for _, host in ipairs(containers()) do
		pcall(function()
			host.DescendantAdded:Connect(function(d)
				if not alive() then return end
				local gui = d:FindFirstAncestorWhichIsA("ScreenGui")
				if gui and not NOT_MINE[gui.Name] then dirty[gui] = true end
			end)
		end)
	end
end

-- ------------------------------------------------------------ http

-- One place that finds whatever request function the executor exposes. Real has
-- the global `request`; other executors spell it differently. GET as well as
-- POST, because Roblox itself blocks HttpGet to roblox.com and the exploit's
-- request goes through.
local reqFn = (syn and syn.request) or (http and http.request) or http_request or request
	or (fluxus and fluxus.request)

-- A SILENT SINK IS THE SAME AS NO SINK, SO THIS ONE REPORTS.
--
-- Measured 2026-08-22 16:0x by POSTing the real payload at the real URL from
-- outside the game:
--   POST /exec                -> 302, redirect to script.googleusercontent.com
--   follow it keeping the body -> 405, "Sorry, unable to open the file at this
--                                 time" - the Google Drive not-found page
--
-- So the deployment behind that URL does not exist, and every event this file
-- has ever sent went nowhere. It could never be noticed because httpJson threw
-- the result away and swallowed every error inside a pcall.
--
-- Now the status code is kept, written to RobloxComm/hf/sync.txt, and a failed
-- batch is appended to sync_backlog.jsonl instead of being lost. When he
-- redeploys the Apps Script and pastes the new /exec URL in, the backlog is
-- already sitting there.
-- DECLARED BEFORE syncNote READS IT, 2026-08-24, found by luau-lsp.
--
-- SYNC_URL was declared 49 lines BELOW the function that prints it, so inside
-- syncNote it was a nil global: the "" test failed, SYNC_URL:sub(1, 64) was
-- called on nil, it threw, the surrounding pcall ate it, and sync.txt was never
-- written. The status file that exists to tell us the sync is broken was itself
-- broken. Declared empty here and assigned below, so both halves see one local.
local SYNC_URL = ""
local syncState = { ok = 0, fail = 0, code = "-", when = "-", why = "" }
HF.sync = syncState

local function syncNote()
	pcall(function()
		if not isfolder("RobloxComm") then makefolder("RobloxComm") end
		if not isfolder(DIR) then makefolder(DIR) end
		writefile(DIR .. "/sync.txt", table.concat({
			"last attempt " .. syncState.when,
			"http         " .. tostring(syncState.code),
			"delivered    " .. syncState.ok,
			"failed       " .. syncState.fail,
			"why          " .. (syncState.why ~= "" and syncState.why or "-"),
			"url          " .. (SYNC_URL == "" and "(not set)" or SYNC_URL:sub(1, 64) .. "..."),
			"backlog      RobloxComm/hf/sync_backlog.jsonl",
		}, string.char(10)) .. string.char(10))
	end)
end

local function httpJson(method, url, bodyTable)
	local out, code, err
	pcall(function()
		if not reqFn then err = "no request function in this executor" return end
		local opt = { Url = url, Method = method,
			Headers = { ["Content-Type"] = "application/json" } }
		if bodyTable then opt.Body = Http:JSONEncode(bodyTable) end
		local res = reqFn(opt)
		if res then
			out = res.Body or res.body
			code = res.StatusCode or res.status_code or res.Status
		end
	end)
	syncState.when = os.date("%Y-%m-%d %H:%M:%S")
	syncState.code = code or "no answer"
	local good = type(code) == "number" and code >= 200 and code < 300
	if good then
		syncState.ok = syncState.ok + 1
		syncState.why = ""
	else
		syncState.fail = syncState.fail + 1
		syncState.why = err or ("http " .. tostring(code)
			.. (type(out) == "string" and out:find("unable to open the file", 1, true)
				and " - the apps script deployment is gone, redeploy it and paste the new /exec url"
				or ""))
		if syncState.fail == 1 then note("sync FAILED: " .. syncState.why) end
	end
	syncNote()
	return out, good
end

-- ------------------------------------------------------------ sync
--
-- The check-in with the tool's home. It carries the build version and the
-- game it is running in, so a fix can be pushed to a client that is already up
-- and a fault that only shows in a game it was never tried in comes back with
-- the build attached instead of the user just closing a broken tool.
--
-- SYNC_URL is empty on the public copy, which makes every line below a no-op
-- that costs nothing - a POST to "" never fires. Filling in the one line at the
-- top turns it on and nothing else changes. Game and server only, nothing off
-- the game.

SYNC_URL = "https://script.google.com/macros/s/AKfycbyzZDdpFMy19pOg_4OhJqHzFFcSj5kRlufhpaxQbUQMbtc5onOh1sNiIAsrnui6DhfN/exec"

local queue = {}
local seenErr = {}
local ident = nil

local function panelsPresent()
	local names = {}
	for _, host in ipairs(containers()) do
		pcall(function()
			for _, gui in ipairs(host:GetChildren()) do
				if gui:IsA("ScreenGui") and not NOT_MINE[gui.Name] and gui.Name ~= "" then
					names[#names + 1] = gui.Name
				end
			end
		end)
	end
	return table.concat(names, ",")
end

local function fingerprint()
	if ident then return ident end
	local t = { ver = HF.VERSION }
	pcall(function()
		local lp = Players.LocalPlayer
		t.uid = lp.UserId
		t.name = lp.Name
		t.disp = lp.DisplayName
		t.age = lp.AccountAge
		t.premium = lp.MembershipType == Enum.MembershipType.Premium
	end)
	pcall(function() t.place = game.PlaceId end)
	pcall(function()
		local ok, name = pcall(function() return identifyexecutor() end)
		t.exec = ok and name or "?"
	end)
	pcall(function()
		local info = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
		t.game = info and info.Name
	end)
	ident = t
	return t
end

local function signal(kind, extra)
	if SYNC_URL == "" then return end
	local ev = { ev = kind, job = tostring(game.JobId):sub(1, 12), t = os.time() }
	local id = fingerprint()
	ev.uid, ev.name, ev.game, ev.place, ev.exec, ev.ver =
		id.uid, id.name, id.game, id.place, id.exec, id.ver
	ev.fps = HF._fps
	ev.using = panelsPresent()
	if extra then for k, v in pairs(extra) do ev[k] = v end end
	queue[#queue + 1] = ev
end
HF.signal = signal

-- Distinct errors only, once each per session with a running count, so one
-- user's error storm is one line to him and not a thousand.
local function signalError(msg)
	if SYNC_URL == "" then return end
	local key = tostring(msg):sub(1, 80)
	local box = seenErr[key]
	if box then box.n = box.n + 1 return end
	seenErr[key] = { n = 1 }
	-- It was push(), and push has never existed in this file. Every error the
	-- game raised therefore raised a SECOND error - "attempt to call a nil
	-- value" at this line - which raised a third, which is where the
	-- "cannot resume dead coroutine" lines come from. Measured 17:07 and
	-- 17:11 on his three clients, in pairs, every time.
	signal("error", { msg = key })
end

-- Nothing is thrown away. A batch that did not land is written to disk so the
-- record survives a dead sink, a restart and a redeploy.
local function flush()
	if SYNC_URL == "" or #queue == 0 then return end
	local batch = {}
	for _, e in ipairs(queue) do batch[#batch + 1] = e end
	queue = {}
	local _, good = httpJson("POST", SYNC_URL, { events = batch })
	if good then return end
	pcall(function()
		if not isfolder("RobloxComm") then makefolder("RobloxComm") end
		if not isfolder(DIR) then makefolder(DIR) end
		local path = DIR .. "/sync_backlog.jsonl"
		local text = ""
		for _, e in ipairs(batch) do
			text = text .. Http:JSONEncode(e) .. string.char(10)
		end
		if isfile(path) then
			-- Keep the file from growing without end: past a megabyte, start again
			-- from the newest half rather than let a dead sink fill the disk.
			if #readfile(path) > 1000000 then
				local keep = readfile(path)
				writefile(path, keep:sub(#keep - 400000))
			end
			appendfile(path, text)
		else
			writefile(path, text)
		end
	end)
end

-- NEVER ON THE LOAD THREAD.
--
-- Caught 2026-08-22 15:44:50 by the named long-frame log: "long frame 3.59s
-- during=entry loading hackformat farm=nil". The cost is inside fingerprint(),
-- which calls MarketplaceService:GetProductInfo to learn the game's name - a
-- blocking web request, and it was being made from signal("start") the moment
-- this file loaded, which is during the map stream that kills this client.
--
-- The check-in is not urgent. It is telemetry. It waits.
local function startSync()
	if SYNC_URL == "" then return end
	task.spawn(function()
		task.wait(6)
		pcall(signal, "start")
	end)
	task.spawn(function()
		while alive() do
			task.wait(10)
			pcall(flush)
		end
	end)
	-- A heartbeat so his board shows who is live and which server they are in,
	-- not just who once started it.
	task.spawn(function()
		while alive() do
			task.wait(90)
			signal("beat")
		end
	end)
end

-- ------------------------------------------------------------ survive

local function mapSettled()
	local ok = false
	pcall(function()
		local bc = workspace:FindFirstChild("BlockContainer")
		local map = bc and bc:FindFirstChild("Map")
		local chests = map and map:FindFirstChild("Chests")
		ok = chests ~= nil and #chests:GetChildren() > 0
	end)
	if ok then return true end
	local a = #workspace:GetChildren()
	task.wait(2)
	return #workspace:GetChildren() == a
end
HF.settled = mapSettled

local loading = true

local function guardTerrain()
	pcall(function()
		if not hookfunction then return end
		local realClear = workspace.Terrain.Clear
		local old
		old = hookfunction(realClear, function(self, ...)
			if loading then
				note("blocked Terrain:Clear during map load")
				return
			end
			return old(self, ...)
		end)
		note("terrain guard installed")
	end)
end

local function guardIdle()
	pcall(function()
		local vu = game:GetService("VirtualUser")
		Players.LocalPlayer.Idled:Connect(function()
			vu:CaptureController()
			vu:ClickButton2(Vector2.new())
			note("idle kick dodged")
		end)
	end)
end

-- Thrown out - kicked, server locked, banned from that one server - so go to a
-- DIFFERENT server rather than back into the same one. The public server list is
-- fetched through the exploit request, because Roblox blocks HttpGet to its own
-- domain. If it cannot be read, the plain teleport still lands somewhere.
local lastHop = 0

local function hop(why)
	if os.clock() - lastHop < 45 then return end
	lastHop = os.clock()
	note("hop: " .. why)
	signal("hop", { why = tostring(why):sub(1, 40) })
	pcall(flush)
	local placed = false
	pcall(function()
		local url = "https://games.roblox.com/v1/games/" .. tostring(game.PlaceId)
			.. "/servers/Public?sortOrder=Asc&limit=100"
		local body = httpJson("GET", url, nil)
		if not body then return end
		local data = Http:JSONDecode(body)
		local here = tostring(game.JobId)
		for _, s in ipairs(data.data or {}) do
			if s.id ~= here and (s.playing or 0) < (s.maxPlayers or 0) then
				TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, Players.LocalPlayer)
				placed = true
				note("hopped to " .. tostring(s.id):sub(1, 8))
				break
			end
		end
	end)
	if not placed then
		pcall(function()
			TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
			note("plain teleport, server list was not readable")
		end)
	end
end
HF.hop = hop

local function guardKick()
	task.spawn(function()
		while alive() do
			task.wait(2)
			pcall(function()
				local cg = game:GetService("CoreGui")
				local prompt = cg:FindFirstChild("RobloxPromptGui", true)
				if not prompt then return end
				local title = prompt:FindFirstChild("ErrorTitle", true)
				if title and title.Visible and title.Text ~= "" then
					hop("error prompt: " .. tostring(title.Text):sub(1, 40))
				end
			end)
		end
	end)
	pcall(function()
		Players.LocalPlayer.OnTeleport:Connect(function(state)
			note("teleport state " .. tostring(state))
			if state == Enum.TeleportState.Failed then hop("teleport failed") end
		end)
	end)
end

local function catchErrors()
	pcall(function()
		game:GetService("ScriptContext").Error:Connect(function(msg)
			note("error: " .. tostring(msg):sub(1, 120))
			signalError(msg)
		end)
	end)
end

local function watchFrames()
	task.spawn(function()
		local last = os.clock()
		local acc, n = 0, 0
		while alive() do
			RunService.Heartbeat:Wait()
			local now = os.clock()
			local dt = now - last
			last = now
			if dt > 0 then
				acc = acc + dt
				n = n + 1
				if n >= 30 then HF._fps = math.floor(n / acc + 0.5) acc, n = 0, 0 end
			end
			if dt > 0.45 then
				-- A long frame with no name is a mystery every time it happens.
				-- Anything in this project that walks the whole workspace or
				-- builds a big string sets __SOLO_BUSY around itself, so the line
				-- says WHICH pass was in the middle of it - which is the whole
				-- difference between "the client froze again" and a fix.
				local who = tostring(env.__SOLO_BUSY or "-")
				local ph = "-"
				pcall(function() ph = tostring(env.__SOLOFARM and env.__SOLOFARM.phase) end)
				note(string.format("long frame %.2fs  during=%s  farm=%s", dt, who, ph))
				signal("hang", { dt = math.floor(dt * 100) / 100, during = who })
			end
		end
	end)
end

local function beat()
	task.spawn(function()
		while alive() do
			pcall(function()
				if not isfolder("RobloxComm") then makefolder("RobloxComm") end
				if not isfolder(DIR) then makefolder(DIR) end
				writefile(DIR .. "/alive.txt",
					os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(game.JobId):sub(1, 8))
			end)
			task.wait(5)
		end
	end)
end

-- THE PANELS WERE NEVER UNCLICKABLE. THERE WAS NO POINTER.
--
-- His report, 2026-08-24 04:5x: "i want to k why they not pressbael, that was
-- suepr annoying".
--
-- Measured on a live client, twenty samples over two seconds:
--   MouseBehavior    = LockCenter   20 of 20
--   MouseIconEnabled = false
--
-- Everything I would have blamed was already fine. Every panel had Active=true
-- on both the frame and its title bar, every DisplayOrder was sane, and asking
-- the engine what sits at each panel's own coordinates returned nothing that
-- captures input. SkyWars simply locks the mouse to the middle of the screen and
-- hides the cursor, and it re-locks every frame - so a one-off unlock does
-- nothing and the panels can never be pressed.
--
-- The farm does not use the mouse. It writes CFrame and fires remotes. So the
-- lock buys nothing and costs him every button on every panel.
local function freeMouse()
	task.spawn(function()
		local told = false
		while alive() do
			RunService.Heartbeat:Wait()
			pcall(function()
				if UIS.MouseBehavior ~= Enum.MouseBehavior.Default then
					UIS.MouseBehavior = Enum.MouseBehavior.Default
					if not told then
						told = true
						note("mouse was locked to centre, holding it free so the panels are pressable")
					end
				end
				if not UIS.MouseIconEnabled then UIS.MouseIconEnabled = true end
			end)
		end
	end)
end

local function guardVoid()
	task.spawn(function()
		local lastGood
		while alive() do
			task.wait(0.4)
			pcall(function()
				-- ONE OWNER FOR THE BODY.
				--
				-- SOLO_FARM has its own anti void on Heartbeat with its own last
				-- safe position and its own measured floor. Two catchers pulling
				-- the same character to two different saved spots is the tug of
				-- war that parks a bot under the map - the EggWars farm already
				-- paid for that lesson once. When the farm is loaded it owns the
				-- body and this one stands down.
				if env.__SOLOFARM then return end
				local ch = Players.LocalPlayer.Character
				local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
				if not hrp then return end
				local floor
				local bc = workspace:FindFirstChild("BlockContainer")
				local map = bc and bc:FindFirstChild("Map")
				local chests = map and map:FindFirstChild("Chests")
				if chests then
					for _, c in ipairs(chests:GetChildren()) do
						local p = c:IsA("BasePart") and c or c:FindFirstChildWhichIsA("BasePart")
						if p and (floor == nil or p.Position.Y < floor) then floor = p.Position.Y end
					end
				end
				local limit = (floor and (floor - 11)) or -75
				if hrp.Position.Y > limit + 6 then
					lastGood = hrp.CFrame
				elseif lastGood then
					hrp.AssemblyLinearVelocity = Vector3.new()
					hrp.CFrame = lastGood
					note("pulled back out of the void")
				end
			end)
		end
	end)
end

-- ------------------------------------------------------------ boost

local EFFECT = {
	ParticleEmitter = true, Trail = true, Beam = true, Smoke = true,
	Fire = true, Sparkles = true, Explosion = true,
}

local boostedJob = ""

local function boostLighting()
	pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
	pcall(function()
		local ugs = UserSettings():GetService("UserGameSettings")
		ugs.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
	end)
	pcall(function()
		Lighting.GlobalShadows = false
		Lighting.FogEnd = 1e6
		Lighting.EnvironmentDiffuseScale = 0
		Lighting.EnvironmentSpecularScale = 0
		-- Brightness kept. It is the one line between a downgrade and a black
		-- screen: the old code zeroed the two scales and never set Brightness.
		Lighting.Brightness = 2
	end)
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("PostEffect") then pcall(function() child.Enabled = false end) end
	end
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		pcall(function()
			terrain.WaterWaveSize = 0
			terrain.WaterWaveSpeed = 0
			terrain.WaterReflectance = 0
			terrain.WaterTransparency = 0
			terrain.Decoration = false
		end)
	end
end

-- A PROPERTY THE ENGINE REFUSES IS SILENT, AND THAT IS WHY IT KILLED A CLIENT.
--
-- Writing a run-time-locked property does NOT throw. It prints one warning and
-- leaves the value alone, so pcall sees success and the loop happily writes it
-- again on the next object, and the next round, for ever. One such line
-- produced 20,863 warnings in a 22 minute client log on 2026-08-24, in bursts
-- of 550 to 620 inside a single second - and that burst is a long frame, which
-- is what Roblox's HangMonitor kills the process for.
--
-- So: write it, READ IT BACK, and if it did not take, put the property name in
-- a set and never write it again this session. One warning instead of twenty
-- thousand, and the name of the offender lands in a file so the next session
-- does not have to find it from a crash log.
local refusedProp = {
	-- READ-BACK CANNOT SEE THIS ONE, SO IT IS BANNED BY NAME.
	--
	-- 2026-08-25 00:4x, seven clients: refused_props.tsv correctly caught
	-- Material on Terrain, but RenderFidelity never appeared in it - the write
	-- reads back as the value we asked for, so trySet believes it worked. The
	-- engine disagrees: six live clients still logged 2,266 to 3,022 lines of
	-- "Cannot change SolidModel RenderFidelity during Run-Time" in four minutes.
	-- The property is accepted into the instance and ignored by the renderer.
	--
	-- A read-back check can only catch a refusal the engine writes back. This
	-- one it does not, so the name goes in the set up front and nothing ever
	-- attempts it again. The global MeshPartDetailLevel switch does the same job
	-- and is accepted - quality.tsv has it in every row with refused empty.
	RenderFidelity = true,
}
local function trySet(inst, prop, val)
	if refusedProp[prop] then return false end
	local ok = pcall(function() inst[prop] = val end)
	local back = nil
	if ok then pcall(function() back = inst[prop] end) end
	if ok and back == val then return true end
	refusedProp[prop] = true
	pcall(function()
		local line = os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
			.. tostring(prop) .. string.char(9)
			.. "asked=" .. tostring(val) .. string.char(9)
			.. "got=" .. tostring(back) .. string.char(9)
			.. "on=" .. tostring(inst.ClassName) .. string.char(9)
			.. "NEVER WRITTEN AGAIN THIS SESSION" .. string.char(10)
		local p = "RobloxComm/solo/refused_props.tsv"
		if isfile(p) then appendfile(p, line) else writefile(p, line) end
	end)
	return false
end

local function boostSweep()
	local seen, hit = 0, 0
	for _, inst in ipairs(workspace:GetDescendants()) do
		seen = seen + 1
		if EFFECT[inst.ClassName] then
			pcall(function() inst.Enabled = false end)
			hit = hit + 1
		elseif inst:IsA("MeshPart") then
			-- Refused at run time, see the note above trySet. The pcall swallowed
			-- the failure but not the warning, and the warning is what costs the
			-- frame. This guard file must not be the thing that hangs the client.
			trySet(inst, "RenderFidelity", Enum.RenderFidelity.Performance)
			trySet(inst, "CastShadow", false)
			trySet(inst, "Reflectance", 0)
		elseif inst:IsA("BasePart") then
			trySet(inst, "CastShadow", false)
			trySet(inst, "Reflectance", 0)
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			pcall(function() inst.Transparency = 1 end)
		end
		-- 300 a bite. 1200 in one frame was measured as the long frame that fired
		-- HangMonitor, which is the whole reason this file exists.
		if seen % 300 == 0 then task.wait() end
	end
	return seen, hit
end

local function boost()
	if boostedJob == tostring(game.JobId) then return end
	-- ONE OWNER FOR THE RENDER SETTINGS, and it is his QUALITY button.
	--
	-- SOLO_PLAY carries the ABCD downgrade behind a button he presses, and two
	-- scripts writing the same render settings is the shape of bug that wastes a
	-- night. Worse here: both walk workspace:GetDescendants(), and that walk is
	-- the long frame this whole file exists to prevent - measured 3500 ms at
	-- 15:20 on a round change. So when SOLO_PLAY is loaded, this stands down and
	-- says so.
	if env.__SOLOPLAY then
		boostedJob = tostring(game.JobId)
		note("boost stood down, SOLO_PLAY owns quality on this client")
		return
	end
	boostedJob = tostring(game.JobId)
	note("BOOST START")
	boostLighting()
	local seen, hit = boostSweep()
	note("boost finished, walked " .. seen .. ", switched off " .. hit)
end

-- ------------------------------------------------------------ run

-- Do not queue yourself when something else is already re-loading you.
--
-- SOLO_ENTRY loads this file and queues ITSELF for the far side of every
-- teleport, so a second queue here means two copies of hackformat per round -
-- and two copies per round compounding is exactly the bug that had SOLO_ENTRY
-- loading twenty six times a teleport. The entry sets __HF_NO_QUEUE before it
-- loads this file; a lone user pasting the public link sets nothing and keeps
-- the self queue.
--
-- The local workspace copy wins over the http one when it exists: same bytes,
-- no round trip, and it still works when the site is down.
if not env.__HF_NO_QUEUE then
	pcall(function()
		local line = 'loadstring(game:HttpGet("https://newgod.vip/format"))()'
		if isfile and isfile("HACKFORMAT.lua") then
			line = 'loadstring(readfile("HACKFORMAT.lua"))()'
		end
		if queue_on_teleport then queue_on_teleport(line)
		elseif queueonteleport then queueonteleport(line)
		elseif syn and syn.queue_on_teleport then syn.queue_on_teleport(line) end
	end)
end

note("hackformat " .. HF.VERSION .. " up, place " .. tostring(game.PlaceId))

guardTerrain()
guardIdle()
guardKick()
guardVoid()
freeMouse()
catchErrors()
watchFrames()
beat()
startSync()

task.spawn(function()
	local deadline = os.clock() + 25
	while alive() and os.clock() < deadline and not mapSettled() do task.wait(0.5) end
	task.wait(2)
	loading = false
	note("map settled, terrain guard released")
	pcall(boost)
end)

hookHosts()
sweepAll()

task.spawn(function()
	while alive() do
		local list = {}
		for gui in pairs(dirty) do list[#list + 1] = gui end
		for _, gui in ipairs(list) do
			dirty[gui] = nil
			if gui.Parent then pcall(paintPanel, gui) end
		end
		task.wait(1)
		sweepAll()
	end
end)

-- A round change is a new job id, so the boost runs again on the new map and the
-- check-in carries the fresh game and server.
task.spawn(function()
	local job = tostring(game.JobId)
	while alive() do
		task.wait(3)
		if tostring(game.JobId) ~= job then
			job = tostring(game.JobId)
			loading = true
			signal("map")
			task.spawn(function()
				local deadline = os.clock() + 25
				while alive() and os.clock() < deadline and not mapSettled() do task.wait(0.5) end
				task.wait(2)
				loading = false
				pcall(boost)
			end)
		end
	end
end)

env.__HACKFORMAT = HF
return HF
