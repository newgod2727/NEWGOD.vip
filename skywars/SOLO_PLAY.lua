-- SOLO PLAY - the control panel. One place to set everything, and it remembers.
--
-- Why this exists as its own panel: the queue was never firing. Two reasons,
-- both measured 2026-08-21:
--   1. The farm only tried to queue while PlaceId was the lobby (8542259458).
--      After a round you sit on the end screen inside the MATCH place
--      (8542275097), where canQueue() is already true - so the gate blocked
--      every attempt at exactly the moment queueing was possible.
--   2. The matchmaking controller's Flamework id is per place: MMv in the
--      lobby, x1V in the match. Anything holding a hardcoded id resolves to
--      nothing in the other place and fails silently inside a pcall.
-- So: never hardcode the id, and never gate on the place. Ask canQueue().
--
-- Settings are written to disk on every change and read back on load, so a
-- reload, a rejoin or a teleport cannot quietly put FRAME 2 back to VIPER.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Drag needs Active, and the position has to survive a reload.
--
-- Measured 2026-08-21 19:4x on the live client: every one of the four panels had
-- Active=false on both the frame and its title bar. A Frame with Active=false
-- does not receive InputBegan for a mouse button at all - it lets the click fall
-- through to whatever is underneath. That is the whole of "it was fucking siepr
-- hard to dag": the drag only ever started on the frames where a child button
-- happened to be under the pointer.
--
-- And the position was never saved, so every reload threw it back to where the
-- code put it. It is his panel and his position; it gets written on release and
-- read back on load.
local POSFILE = "RobloxComm/solo/panel_pos.json"

local function posLoad(name, frame)
	pcall(function()
		if not isfile(POSFILE) then return end
		local t = game:GetService("HttpService"):JSONDecode(readfile(POSFILE))
		local v = t and t[name]
		-- Store the UDim2, not AbsolutePosition. AbsolutePosition already has the
		-- 36 pixel Roblox top inset baked into it, so writing it back as a pure
		-- offset pushed the panel down by the inset on every single reload -
		-- SoloFarm went 196 -> 250 -> 197 while nobody touched it.
		if v and tonumber(v.xo) and tonumber(v.yo) then
			frame.Position = UDim2.new(tonumber(v.xs) or 0, tonumber(v.xo),
				tonumber(v.ys) or 0, tonumber(v.yo))
		end
	end)
end

local function posSave(name, frame)
	pcall(function()
		if not isfolder("RobloxComm") then makefolder("RobloxComm") end
		if not isfolder("RobloxComm/solo") then makefolder("RobloxComm/solo") end
		local HttpService = game:GetService("HttpService")
		local t = {}
		if isfile(POSFILE) then
			local ok, d = pcall(function() return HttpService:JSONDecode(readfile(POSFILE)) end)
			if ok and type(d) == "table" then t = d end
		end
		local p = frame.Position
		t[name] = { xs = p.X.Scale, xo = p.X.Offset, ys = p.Y.Scale, yo = p.Y.Offset }
		writefile(POSFILE, HttpService:JSONEncode(t))
	end)
end

local function makeDraggable(name, frame, handle)
	frame.Active = true
	handle.Active = true
	posLoad(name, frame)
	local UIS = game:GetService("UserInputService")
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
			posSave(name, frame)
		end
	end)
end
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local env = getgenv and getgenv() or _G
env.__SOLOPLAY_GEN = (env.__SOLOPLAY_GEN or 0) + 1
local MYGEN = env.__SOLOPLAY_GEN
local function alive() return env.__SOLOPLAY_GEN == MYGEN end

local lp = Players.LocalPlayer
while not lp do task.wait(0.2) lp = Players.LocalPlayer end

local CFG_FILE = "RobloxComm/solo/solo_play_cfg.json"
-- 2026-08-21 18:5x - this is why it kept landing in a custom room.
--
-- "why it was telpting to the custom?, it shoudl go to the fuck of solo bro"
--
-- QUEUE_ID was "SkyWarsSolo". That string is real, but it is the game-mode TYPE
-- out of ReplicatedStorage.TS.game.game-mode, not a queue id. The queue ids live
-- in TS.matchmaking.queue-id and they are lowercase:
--
--   Solo = "solo"          Duos = "duos"        Trios = "trios"
--   Quads = "quads"        EggWarsQuads = "eggwars_quads"
--   Private = "private"    TestingSolo = "testing_solo"   ... and so on
--
-- So every joinQueue call this farm has made was handing the matchmaker a value
-- it does not know, and a private/custom room is what came back. The mode module
-- even says AllowedInPrivate = true for Solo, which is why it was a legal place
-- to be dropped rather than an outright error.
local QUEUE_ID = "solo"

-- Never let a bad id put us in a custom or a testing queue again.
local BANNED_QUEUE = { private = true, testing_private = true }

-- 2026-08-21 19:2x - measured, and joinQueue was never going to work.
--
--   mm:joinQueue("solo")   -> returns ok, isInQueue stays FALSE. Does nothing.
--   mm:joinQueueIn(0)      -> isInQueue becomes TRUE. This is the one.
--
-- And the game has its own self queue that was switched off the whole time:
-- the settings controller (Flamework id 32y) holds a setting called AutoQueue,
-- it read FALSE, and the matchmaking controller only calls joinQueueIn(6) after
-- an elimination when that setting is true and the party is one man. Turning it
-- on is what "self queue" actually means in this game - the rest of this file
-- just needs to not fight it.
local function queueEngine()
	local mod, mm, st
	pcall(function()
		mod = require(ReplicatedStorage.rbxts_include.node_modules["@flamework"].core.out)
		mm = mod.Flamework.resolveDependency("x1V")
		st = mod.Flamework.resolveDependency("32y")
	end)
	return mm, st
end

local autoQueueArmed = false
local function armGameAutoQueue()
	if autoQueueArmed then return end
	local _, st = queueEngine()
	if not st then return end
	local cur
	pcall(function() cur = st:getSetting("AutoQueue") end)
	if cur ~= true then
		pcall(function() st:setSetting("AutoQueue", true) end)
	end
	pcall(function() cur = st:getSetting("AutoQueue") end)
	autoQueueArmed = (cur == true)
end



-- This panel owns two things only: queueing, and the quality downgrade.
-- What the farm does and which kill mode it uses is the farm's own panel.
local DEFAULTS = { autoQueue = true, quality = true }

local C = {}
for k, v in pairs(DEFAULTS) do C[k] = v end
env.__SOLOPLAY = C

local P = { queued = false, canQueue = false, place = 0, note = "", saved = "",
	roundOver = true, sawLive = 0, overSince = 0, job = "",
	sessionStart = os.clock(), roundStart = 0, rounds = 0, lastRound = 0 }
env.__SOLOPLAY_STATE = P

local function ensure()
	pcall(function()
		if not isfolder("RobloxComm") then makefolder("RobloxComm") end
		if not isfolder("RobloxComm/solo") then makefolder("RobloxComm/solo") end
	end)
end

local function save()
	ensure()
	local ok = pcall(function()
		writefile(CFG_FILE, HttpService:JSONEncode(C))
	end)
	P.saved = ok and os.date("%H:%M:%S") or "SAVE FAILED"
end

local function load()
	pcall(function()
		if not isfile(CFG_FILE) then return end
		local t = HttpService:JSONDecode(readfile(CFG_FILE))
		if type(t) ~= "table" then return end
		for k, v in pairs(DEFAULTS) do
			if t[k] ~= nil and type(t[k]) == type(v) then C[k] = t[k] end
		end
		P.note = "settings restored"
	end)
end
load()

-- ---------------------------------------------------------------- queue

local mmCache, mmPlace
local function matchmaking()
	if mmCache and mmPlace == game.PlaceId then return mmCache end
	mmCache, mmPlace = nil, game.PlaceId
	pcall(function()
		local core = ReplicatedStorage.rbxts_include.node_modules["@flamework"].core.out
		local mod = require(core)
		local ps = lp:WaitForChild("PlayerScripts", 10)
		local cls = require(ps.TS.controllers["matchmaking-controller"])
		local target = cls
		if type(cls) == "table" then
			for _, v in pairs(cls) do
				if type(v) == "table" and mod.Reflect.getMetadata(v, "identifier") then target = v break end
			end
		end
		mmCache = mod.Flamework.resolveDependency(mod.Reflect.getMetadata(target, "identifier"))
	end)
	return mmCache
end

local function queueNow(reason)
	local mm = matchmaking()
	if not mm then P.note = "no matchmaking controller here" return false end
	local q, can = false, false
	pcall(function() q = mm:isInQueue() end)
	pcall(function() can = mm:canQueue() end)
	P.queued, P.canQueue = q, can
	if q then P.note = "already in queue" return true end
	if not can then P.note = "canQueue is false right now" return false end
	local ok, err = pcall(function() if BANNED_QUEUE[QUEUE_ID] then error("refusing to queue into " .. QUEUE_ID) end
		armGameAutoQueue()
		mm:joinQueueIn(0) end)
	if ok then
		P.note = "queued (" .. tostring(reason) .. ") at " .. os.date("%H:%M:%S")
		P.queued = true
	else
		P.note = "joinQueue failed: " .. tostring(err):sub(1, 40)
	end
	return ok
end
env.__SOLOPLAY_QUEUE = queueNow

-- ---------------------------------------------------------------- quality
--
-- This is the ABCD RAM DOWNGRADE, copied out of FARM_SKYWARS_ABCD.lua rather
-- than reinvented, because he told me to go and read it:
--
--   "is the farm ABCD that scirpt have a thing called dwongrade?, as that i need
--    u put the downgrade at the solo play ... but of cosue i didnt mean blank
--    screen i was onyl downgrade the whole queiaty, beucase u frogot what is
--    downgrae quaity, as u mistkae that bro, have a chekc at the ABCD that code
--    frist"
--
-- He is right that the version that was here was not his downgrade. Two lines in
-- it were what made the screen go dark rather than merely cheap:
--   EnvironmentDiffuseScale = 0 and EnvironmentSpecularScale = 0 kill the ambient
--   light without putting anything back, and nothing here ever set Brightness.
-- His ABCD version deliberately sets Lighting.Brightness = 2 while it turns the
-- expensive things off, which is exactly the difference between "downgraded" and
-- "blank". It also does not touch the fps cap and does not mute the game.
--
-- Everything below is client side only. Nothing is sent to the server and no
-- other player sees any of it. Destroying an instance is what actually frees
-- memory - hiding it does not - so ON is one way: what is stripped comes back on
-- the next round, not when the button is pressed again.

local STRIP_CLASSES = {
	Decal = true,
	Texture = true,
	ParticleEmitter = true,
	Trail = true,
	Beam = true,
	Smoke = true,
	Fire = true,
	Sparkles = true,
	SurfaceAppearance = true,
	Sound = true,
	Explosion = true,
}

local STRIP_CHUNK = 1200
local qStripped = 0
local qBusy = false

local function memMb()
	local ok, v = pcall(function()
		return game:GetService("Stats"):GetTotalMemoryUsageMb()
	end)
	return ok and v or 0
end

local function applyQuality()
	if not C.quality or qBusy then return end
	qBusy = true
	local before = memMb()
	local n = 0

	pcall(function()
		settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
	end)

	-- Brightness 2 is the line that keeps this a downgrade instead of a blackout.
	pcall(function()
		Lighting.GlobalShadows = false
		Lighting.FogEnd = 1000000
		Lighting.Brightness = 2
		for _, v in ipairs(Lighting:GetChildren()) do
			if v:IsA("PostEffect") or v:IsA("Atmosphere") or v:IsA("Sky") then
				v:Destroy()
				n = n + 1
			end
		end
	end)

	pcall(function()
		workspace.Terrain:Clear()
	end)

	-- Every pickup on the map is shadowed by a visual-only twin whose name ends
	-- in "Render". They are pure decoration and deleting them costs nothing.
	pcall(function()
		for _, m in ipairs(workspace:GetChildren()) do
			if string.find(m.Name, "Render", 1, true) then
				m:Destroy()
				n = n + 1
			end
		end
		local fx = workspace:FindFirstChild("KillEffects")
		if fx then
			fx:ClearAllChildren()
			n = n + 1
		end
	end)

	-- Yield every so often. Done in one go this is a single frame hundreds of
	-- milliseconds long, and during that frame nothing else runs - including the
	-- farm's anti-void catch, which is how a bot gets from the catch line to
	-- below -500 and is deleted. Spread over frames it costs the same and blocks
	-- nothing.
	pcall(function()
		local seen = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			seen = seen + 1
			if seen % STRIP_CHUNK == 0 then
				RunService.Heartbeat:Wait()
			end
			if STRIP_CLASSES[d.ClassName] then
				d:Destroy()
				n = n + 1
			elseif d:IsA("Accessory") then
				d:Destroy()
				n = n + 1
			elseif d:IsA("MeshPart") then
				d.RenderFidelity = Enum.RenderFidelity.Performance
				d.CastShadow = false
				d.Reflectance = 0
			elseif d:IsA("BasePart") then
				d.CastShadow = false
				d.Reflectance = 0
				if d.Material ~= Enum.Material.SmoothPlastic then
					d.Material = Enum.Material.SmoothPlastic
				end
			end
		end
	end)

	task.wait(1)
	local after = memMb()
	qStripped = qStripped + n
	P.note = string.format("downgrade: %d stripped, %.0f -> %.0f MB", n, before, after)
	qBusy = false
end

local function restoreQuality()
	pcall(function()
		settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
	end)
	pcall(function()
		Lighting.GlobalShadows = true
		Lighting.Brightness = 3
	end)
	P.note = "quality restored - deleted parts come back next round"
end

-- Re-assert after a round change, because a teleport builds a new DataModel and
-- the quality level comes back with it.
task.spawn(function()
	local lastJob = ""
	while alive() do
		task.wait(3)
		local job = tostring(game.JobId)
		if job ~= lastJob then
			lastJob = job
			if C.quality then
				task.wait(4)
				pcall(applyQuality)
			end
		end
	end
end)

-- Deliberately does not touch the farm's auto flag or its kill mode. Those
-- are set on the SOLO FARM panel and this one must not overwrite them.
local function pushToFarm() end

-- ---------------------------------------------------------------- self debug
--
-- His two loops, 2026-08-21 19:0x:
--
--   "add to the solo play that mkae sure it was each 10 sec detecting is that i
--    was killing or at others sever or what? it shuld auto detect then back to
--    solo that was the backup for the line"
--
--   "the solo play was auto each 2 sec detecting was that i was in the round or
--    at wehre, and detecting am i killing player? if it was killing player adn
--    at the solo then just ready for the self quee ... it wil self debug that
--    was am i fucking not quuee or afking too long at the round did i win yet or
--    wahat"
--
-- Two loops, two jobs. The two second one only WATCHES and writes down where it
-- is and whether the farm is achieving anything. The ten second one is the
-- backup line: it is the only thing here allowed to act, and it acts on one
-- condition only - we are not where we should be and nothing is queued.

local MATCH_PLACE = 8542275097
local LOBBY_PLACE = 8542259458

local D = {
	where = "?", inRound = false, killing = false, lastKillT = 0,
	stuckFor = 0, note = "", acted = 0, lastAct = 0,
}
env.__SOLOPLAY_DEBUG = D

local function farm()
	return env.__SOLOFARM
end

local function whereAmI()
	if game.PlaceId == MATCH_PLACE then return "match" end
	if game.PlaceId == LOBBY_PLACE then return "lobby" end
	return "somewhere else (" .. tostring(game.PlaceId) .. ")"
end

-- Every two seconds: where am I, am I in a round, am I killing anybody. This
-- one never touches the queue.
task.spawn(function()
	local lastFin, lastDmg = 0, 0
	while alive() do
		task.wait(2)
		pcall(function()
			local F = farm()
			D.where = whereAmI()
			D.inRound = (D.where == "match") and (P.roundOver == false)

			local fin = F and (F.finishes or 0) or 0
			local dmg = F and (F.dmgSeen or 0) or 0
			if fin > lastFin or dmg > lastDmg then
				D.killing = true
				D.lastKillT = os.clock()
			elseif os.clock() - D.lastKillT > 6 then
				D.killing = false
			end
			lastFin, lastDmg = fin, dmg

			-- The self debug line: the four questions he listed, answered.
			local bits = {}
			if not P.queued and not D.inRound then bits[#bits + 1] = "NOT QUEUED and not in a round" end
			if D.inRound and not D.killing then bits[#bits + 1] = "in a round but killing nothing" end
			if F and F.dryFor and F.dryFor > 8 then
				bits[#bits + 1] = string.format("nothing has bled for %.0fs", F.dryFor)
			end
			if D.where ~= "match" and D.where ~= "lobby" then
				bits[#bits + 1] = "WRONG PLACE - " .. D.where
			end
			D.note = #bits > 0 and table.concat(bits, "; ") or "ok"

			if #bits > 0 then D.stuckFor = D.stuckFor + 2 else D.stuckFor = 0 end

			pcall(function()
				if not isfolder("RobloxComm") then makefolder("RobloxComm") end
				if not isfolder("RobloxComm/solo") then makefolder("RobloxComm/solo") end
				local line = os.date("%H:%M:%S") .. string.char(9)
					.. D.where .. string.char(9)
					.. "round=" .. tostring(D.inRound) .. string.char(9)
					.. "killing=" .. tostring(D.killing) .. string.char(9)
					.. "queued=" .. tostring(P.queued) .. string.char(9)
					.. "canQueue=" .. tostring(P.canQueue) .. string.char(9)
					.. "finishes=" .. tostring(F and F.finishes) .. string.char(9)
					.. "stuck=" .. tostring(D.stuckFor) .. "s" .. string.char(9)
					.. D.note .. string.char(10)
				if isfile("RobloxComm/solo/selfdebug.log") then
					appendfile("RobloxComm/solo/selfdebug.log", line)
				else
					writefile("RobloxComm/solo/selfdebug.log", line)
				end
			end)
		end)
	end
end)

-- Every ten seconds: the backup line. Only fires when we are genuinely adrift -
-- not in a round, not queued, and it has been that way for a while. Rate limited
-- so it can never become the relaunch loop he banned.
task.spawn(function()
	while alive() do
		task.wait(10)
		pcall(function()
			if not C.autoQueue then return end
			if D.inRound then return end
			if P.queued then return end
			if D.stuckFor < 10 then return end
			if os.clock() - D.lastAct < 20 then return end
			D.lastAct = os.clock()
			D.acted = D.acted + 1
			local ok = queueNow("backup line: " .. D.note)
			P.note = "backup line fired (" .. D.acted .. "): " .. tostring(ok)
		end)
	end
end)

-- ---------------------------------------------------------------- panel

local panel, lbl, btn = nil, {}, {}

local function modeText()
	local F = env.__SOLOFARM
	if not F then return "farm not loaded" end
	return F.mode == "FRAME" and ("FRAME " .. tostring(F.frames)) or "VIPER"
end

local function paint()
	if not panel then return end
	pcall(function()
		btn.q.Text = C.autoQueue and "SELF QUEUE ON" or "SELF QUEUE OFF"
		btn.q.BackgroundColor3 = C.autoQueue and Color3.fromRGB(201, 142, 74) or Color3.fromRGB(70, 62, 50)
		btn.qual.Text = C.quality and "QUALITY LOW" or "QUALITY NORMAL"
		btn.qual.BackgroundColor3 = C.quality and Color3.fromRGB(201, 142, 74) or Color3.fromRGB(70, 62, 50)

		local F = env.__SOLOFARM
		lbl.farm.Text = F and ("farm " .. (F.on and ("ON  " .. tostring(F.phase)) or "off")
			.. "   " .. tostring(F.kills) .. " kills  " .. tostring(F.chests) .. " chests") or "farm not loaded"
		lbl.q.Text = "queue " .. (P.queued and "IN" or "out")
			.. "   canQueue " .. tostring(P.canQueue)
			.. "   round " .. (P.roundOver and "OVER" or "LIVE")
			.. "   peak " .. tostring(P.sawLive)
		local function clock(v)
			if v <= 0 then return "00:00" end
			return string.format("%02d:%02d", math.floor(v / 60), math.floor(v % 60))
		end
		local roundT = P.roundStart > 0 and (os.clock() - P.roundStart) or 0
		lbl.timer.Text = "round " .. clock(roundT)
			.. "   session " .. clock(os.clock() - P.sessionStart)
			.. "   rounds " .. tostring(P.rounds)
			.. (P.lastRound > 0 and ("   last " .. clock(P.lastRound)) or "")
		lbl.note.Text = P.note ~= "" and P.note or "ready"
		lbl.saved.Text = "saved " .. (P.saved ~= "" and P.saved or "not yet")
			.. "   |   queue and quality only, farm mode is on the farm panel"
	end)
end

local function build()
	for _, h in ipairs({ (gethui and gethui()) or nil, game:GetService("CoreGui"), lp:FindFirstChild("PlayerGui") }) do
		if h then
			pcall(function()
				for _, c in ipairs(h:GetChildren()) do
					if c:IsA("ScreenGui") and c.Name == "SoloPlay" then c:Destroy() end
				end
			end)
		end
	end
	local host = (gethui and gethui()) or game:GetService("CoreGui") or lp:FindFirstChild("PlayerGui")
	if not host then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SoloPlay" gui.ResetOnSpawn = false gui.DisplayOrder = 9150 gui.Parent = host
	env.__SOLOPLAY_GUI = gui

	local f = Instance.new("Frame")
	f.Size = UDim2.new(0, 352, 0, 206)
	f.Position = UDim2.new(1, -366, 0, 424)
	f.BackgroundColor3 = Color3.fromRGB(11, 11, 14)
	f.BorderSizePixel = 0 f.Parent = gui
	panel = f
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
	local st = Instance.new("UIStroke", f) st.Color = Color3.fromRGB(201, 142, 74) st.Thickness = 2

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 27)
	bar.BackgroundColor3 = Color3.fromRGB(24, 20, 14)
	bar.BorderSizePixel = 0 bar.Parent = f
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 10)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1 title.Position = UDim2.new(0, 12, 0, 0)
	title.Size = UDim2.new(1, -24, 1, 0) title.Font = Enum.Font.GothamBold
	title.TextSize = 13 title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 179, 71) title.Text = "SOLO PLAY" title.Parent = bar

	local function mkToggle(text, x, y, w, cb)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, w, 0, 26) b.Position = UDim2.new(0, x, 0, y)
		b.BackgroundColor3 = Color3.fromRGB(201, 142, 74) b.BorderSizePixel = 0
		b.Font = Enum.Font.GothamBold b.TextSize = 11
		b.TextColor3 = Color3.fromRGB(26, 20, 9) b.Text = text b.Parent = f
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
		b.MouseButton1Click:Connect(function() pcall(cb) end)
		return b
	end

	btn.q = mkToggle("SELF QUEUE", 12, 36, 164, function()
		C.autoQueue = not C.autoQueue
		save() paint()
	end)
	btn.qual = mkToggle("QUALITY", 184, 36, 156, function()
		C.quality = not C.quality
		if C.quality then applyQuality() else restoreQuality() end
		save() paint()
	end)

	local big = Instance.new("TextButton")
	big.Size = UDim2.new(1, -24, 0, 32) big.Position = UDim2.new(0, 12, 0, 72)
	big.BackgroundColor3 = Color3.fromRGB(243, 207, 153) big.BorderSizePixel = 0
	big.Font = Enum.Font.GothamBold big.TextSize = 14
	big.TextColor3 = Color3.fromRGB(26, 20, 9) big.Text = "QUEUE NOW" big.Parent = f
	Instance.new("UICorner", big).CornerRadius = UDim.new(0, 8)
	big.MouseButton1Click:Connect(function()
		pcall(function() queueNow("button") end)
		paint()
	end)
	btn.big = big

	-- ORA. His word, 2026-08-21 20:1x: "at the solo play add a thng that was ORA,
	-- that was using the format of the gui psositon, to make sure if the user was
	-- lazy then that".
	--
	-- Read as: one press puts every panel back to the saved layout, so a lazy
	-- user never has to drag four panels into place again. It uses the same
	-- panel_pos.json the drag writes, so whatever he arranges by hand IS the
	-- format ORA restores - there is no second copy of the layout to go stale.
	--
	-- If ORA was meant to be something else, this is the wrong half of the guess
	-- and the button is one line to repoint.
	local ora = Instance.new("TextButton")
	ora.Size = UDim2.new(0, 60, 0, 19) ora.Position = UDim2.new(1, -72, 0, 4)
	ora.BackgroundColor3 = Color3.fromRGB(201, 142, 74) ora.BorderSizePixel = 0
	ora.Font = Enum.Font.GothamBold ora.TextSize = 11
	ora.TextColor3 = Color3.fromRGB(26, 20, 9) ora.Text = "ORA" ora.Parent = bar
	Instance.new("UICorner", ora).CornerRadius = UDim.new(0, 6)
	ora.MouseButton1Click:Connect(function()
		pcall(function()
			if not isfile(POSFILE) then P.note = "ORA: no saved layout yet" return end
			local t = game:GetService("HttpService"):JSONDecode(readfile(POSFILE))
			local hosts = {}
			pcall(function() if gethui then hosts[#hosts+1] = gethui() end end)
			pcall(function() hosts[#hosts+1] = game:GetService("CoreGui") end)
			pcall(function() hosts[#hosts+1] = Players.LocalPlayer:FindFirstChild("PlayerGui") end)
			local n = 0
			for _, h in ipairs(hosts) do
				for _, sg in ipairs(h:GetChildren()) do
					if sg:IsA("ScreenGui") and t[sg.Name] then
						local v = t[sg.Name]
						for _, fr in ipairs(sg:GetChildren()) do
							if fr:IsA("Frame") and tonumber(v.xo) then
								fr.Position = UDim2.new(tonumber(v.xs) or 0, tonumber(v.xo),
									tonumber(v.ys) or 0, tonumber(v.yo))
								n = n + 1
							end
						end
					end
				end
			end
			P.note = "ORA: put " .. n .. " panel(s) back to the saved layout"
		end)
		paint()
	end)
	btn.ora = ora

	local function mkLbl(y, size, col)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1 l.Position = UDim2.new(0, 12, 0, y)
		l.Size = UDim2.new(1, -24, 0, 18) l.Font = Enum.Font.Gotham
		l.TextSize = size l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = col l.TextTruncate = Enum.TextTruncate.AtEnd l.Text = "" l.Parent = f
		return l
	end
	lbl.farm = mkLbl(110, 11, Color3.fromRGB(155, 191, 149))
	lbl.q = mkLbl(128, 11, Color3.fromRGB(239, 230, 216))
	lbl.timer = mkLbl(146, 12, Color3.fromRGB(243, 207, 153))
	lbl.note = mkLbl(166, 10, Color3.fromRGB(243, 207, 153))
	lbl.saved = mkLbl(182, 10, Color3.fromRGB(162, 147, 127))

	makeDraggable("SoloPlay", f, bar)
end

pcall(build)
pushToFarm()
if C.quality then applyQuality() end

-- The queue keeper.
--
-- canQueue() is true during a live match as well, so acting on it alone pulled
-- him out of games he was still playing. And at the first second of a round
-- nobody has spawned yet, so "one player left" looks exactly like "you won".
--
-- So a round only counts as over once it was genuinely running - at least two
-- living players seen in THIS server - and then either everyone else is gone
-- or we are dead. Plus two seconds of that staying true, so a brief gap while
-- characters respawn cannot trigger it.
local MATCH_PLACE = 8542275097

local function livingCount()
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		local h = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 then n = n + 1 end
	end
	return n
end

local function iAmAlive()
	local c = lp.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end

task.spawn(function()
	while alive() do
		task.wait(1)
		pcall(function()
			P.place = game.PlaceId
			local job = tostring(game.JobId)
			if job ~= P.job then
				if P.roundStart > 0 then P.lastRound = os.clock() - P.roundStart end
				P.job = job
				P.sawLive = 0
				P.overSince = 0
				P.roundStart = 0
			end

			local inMatch = (game.PlaceId == MATCH_PLACE)
			local live = livingCount()
			if live > P.sawLive then P.sawLive = live end
			if inMatch and P.sawLive >= 2 and P.roundStart == 0 then
				P.roundStart = os.clock()
				P.rounds = P.rounds + 1
			end

			local over
			if not inMatch then
				over = true
			elseif P.sawLive >= 2 and (live <= 1 or not iAmAlive()) then
				over = true
			else
				over = false
			end

			if over then
				if P.overSince == 0 then P.overSince = os.clock() end
			else
				P.overSince = 0
			end
			P.roundOver = over

			local mm = matchmaking()
			if mm then
				pcall(function() P.queued = mm:isInQueue() end)
				pcall(function() P.canQueue = mm:canQueue() end)
			else
				P.canQueue = false
			end

			local settled = P.overSince > 0 and (os.clock() - P.overSince) >= 2
			if C.autoQueue and P.canQueue and not P.queued and over and settled then
				queueNow("round over")
			elseif not over then
				P.note = "in a live round, holding the queue (" .. live .. " alive, peak " .. P.sawLive .. ")"
			end

			pushToFarm()
			if C.quality then applyQuality() end
		end)
	end
end)

task.spawn(function()
	while alive() do task.wait(0.3) pcall(paint) end
end)

save()
paint()
return "SOLO_PLAY up, mode " .. modeText() .. ", autoFarm " .. tostring(C.autoFarm)
	.. ", autoQueue " .. tostring(C.autoQueue) .. ", quality " .. tostring(C.quality)
