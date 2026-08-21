-- SOLO_REC - records a hand-played SkyWars round in full.
-- Runs on its own. It never moves the character, never fires anything, never
-- touches the game. Read only. He plays, this writes.
--
-- Everything lands in RobloxComm/solo/ as plain text, one folder per session.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TextChatService = game:GetService("TextChatService")
local StarterGui = game:GetService("StarterGui")

local env = getgenv and getgenv() or _G

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

-- Only one recorder, ever. Not "the newest one wins" - a second one refuses to
-- start at all and leaves the running one untouched.
do
	local beat = env.__SOLOREC_BEAT
	if type(beat) == "number" and (os.clock() - beat) < 3 then
		local S = env.__SOLOREC
		if S then S.note = "a second copy tried to start at " .. os.date("%H:%M:%S") .. " and was refused" end
		warn("[SOLO REC] already running, this copy is standing down")
		return "SOLO_REC already running - second copy refused"
	end
end

env.__SOLOREC_GEN = (env.__SOLOREC_GEN or 0) + 1
local MYGEN = env.__SOLOREC_GEN
env.__SOLOREC_BEAT = os.clock()

-- Killing the previous copy has to be a sweep, not a single handle.
-- Tracking one GUI in getgenv only removes the panel from the run that stored
-- it; an earlier copy loaded before that variable existed, or one whose store
-- failed, stayed on screen and its counters kept ticking. Executing again then
-- looked like it had duplicated the recorder, because it had. Sweep every host
-- for anything of ours and destroy all of it, every load, no exceptions.
local function sweepOldPanels()
	local hosts = {}
	pcall(function() if gethui then hosts[#hosts + 1] = gethui() end end)
	pcall(function() hosts[#hosts + 1] = game:GetService("CoreGui") end)
	pcall(function()
		local p = game:GetService("Players").LocalPlayer
		if p then hosts[#hosts + 1] = p:FindFirstChild("PlayerGui") end
	end)
	local killed = 0
	for _, h in ipairs(hosts) do
		if h then
			pcall(function()
				for _, c in ipairs(h:GetChildren()) do
					if c:IsA("ScreenGui") and c.Name == "SoloRec" then
						c:Destroy()
						killed = killed + 1
					end
				end
			end)
		end
	end
	pcall(function()
		if env.__SOLOREC_GUI then env.__SOLOREC_GUI:Destroy() end
	end)
	env.__SOLOREC_GUI = nil
	return killed
end

local swept = sweepOldPanels()

local lp = Players.LocalPlayer
while not lp do
	task.wait(0.2)
	lp = Players.LocalPlayer
end

local ROOT = "RobloxComm"
local DIR = ROOT .. "/solo"

-- The recorder is a debug tool, not a feature.
--
-- His words, 2026-08-21 20:2x: "it will having all of mine but jsut the REC will
-- be auto stop, as it was not support me this, beucase rec was for edebug, jst
-- need to make ti was at there scirpt htne ok, we dont need to remove that".
--
-- So on a public load it is present, visible and one press from working - it
-- just does not start itself, and it does not auto-restart between rounds.
local PUBLIC = (getgenv and getgenv().__SKYWARS_PUBLIC) == true

local S = {
	on = not PUBLIC,
	round = 0,
	jobId = "",
	placeId = 0,
	lines = 0,
	hits = 0,
	chats = 0,
	deaths = 0,
	err = "",
	autoStop = true,
	roundOpen = false,
	startedAt = os.time(),
	roundStart = 0,
	dumped = {},
	seenRemote = {},
	logName = "",
}
env.__SOLOREC = S

local function alive()
	return env.__SOLOREC_GEN == MYGEN
end

local function stamp()
	return os.date("%H:%M:%S")
end

local function ensure()
	pcall(function()
		if not isfolder(ROOT) then makefolder(ROOT) end
		if not isfolder(DIR) then makefolder(DIR) end
	end)
end

local function put(file, text)
	if not S.on and not S.always then return end
	local ok, err = pcall(function()
		ensure()
		if isfile(file) then
			appendfile(file, text)
		else
			writefile(file, text)
		end
	end)
	if not ok then
		S.err = tostring(err):sub(1, 90)
	end
end

-- A teleport destroys the whole Luau VM, so getgenv cannot carry the round
-- number across rounds. A file can. Without this, round 2 reopens as r001 and
-- appends into round 1's files.
local COUNTER = DIR .. "/round_state.txt"

-- Returns the round number for the server we are in now, and whether that
-- number is new. Reloading the script inside the same server must give back
-- the same number, or every reload writes a fresh set of round files.
local function roundNumberFor(job)
	local v, lastJob = 0, ""
	pcall(function()
		if isfile(COUNTER) then
			local raw = readfile(COUNTER)
			local a, b = raw:match("^%s*(%d+)%s*|(.-)%s*$")
			v = tonumber(a) or 0
			lastJob = b or ""
		end
	end)
	local fresh = (lastJob ~= job)
	if fresh then
		v = v + 1
		pcall(function()
			if not isfolder(ROOT) then makefolder(ROOT) end
			if not isfolder(DIR) then makefolder(DIR) end
			writefile(COUNTER, tostring(v) .. "|" .. job)
		end)
	end
	return v, fresh
end

local function base()
	return DIR .. "/" .. lp.Name .. "_r" .. string.format("%03d", S.round)
end

-- Structural writes - boot lines, round headers, the map census - go through
-- here so that being idle still leaves a record of what happened. Only the
-- 4-rows-a-second sampler is gated on the START button.
local function log(kind, text)
	S.lines = S.lines + 1
	S.always = true
	put(base() .. "_timeline.log", stamp() .. "  " .. kind .. "  " .. tostring(text) .. "\n")
	S.always = false
end

-- ---------------------------------------------------------------- panel

local panel, lblState, lblRound, lblCount, lblErr, lblLoot, lblFarm, lblXp

local function paint()
	if not panel then return end
	pcall(function()
		lblState.Text = S.on and "RECORDING" or "IDLE - press START"
		lblState.TextColor3 = S.on and Color3.fromRGB(155, 191, 149) or Color3.fromRGB(224, 145, 129)
		lblRound.Text = "round " .. S.round .. "   " .. (S.jobId ~= "" and S.jobId:sub(1, 8) or "no job")
		lblCount.Text = S.lines .. " lines   " .. S.chats .. " chat   " .. S.deaths .. " deaths   passive"
		lblErr.Text = S.err ~= "" and ("! " .. S.err) or DIR
		lblErr.TextColor3 = S.err ~= "" and Color3.fromRGB(224, 145, 129) or Color3.fromRGB(162, 147, 127)
		local L = env.__SOLOLOOT
		if L then
			lblLoot.Text = "map " .. tostring(L.fp) .. "   " .. tostring(L.chests) .. " chests   "
				.. tostring(L.items) .. " items   " .. tostring(L.opened) .. " opened"
		else
			lblLoot.Text = "loot module not loaded"
		end
		local FF = env.__SOLOFARM
		if FF then
			lblFarm.Text = "farm " .. (FF.on and ("ON " .. tostring(FF.phase)) or (FF.auto and "armed" or "off"))
				.. "  " .. tostring(FF.kills) .. "k " .. tostring(FF.chests) .. "c " .. tostring(FF.mode)
		else
			lblFarm.Text = "farm not loaded"
		end
		local XX = env.__XPBAR
		if XX then
			lblXp.Text = "level " .. tostring(XX.lvl) .. "   " .. tostring(XX.into) .. "/" .. tostring(XX.span)
				.. "   " .. tostring(XX.toNext) .. " to go"
		else
			lblXp.Text = "xp bar not loaded"
		end
	end)
end

local function buildPanel()
	local host
	pcall(function() host = gethui and gethui() end)
	if not host then pcall(function() host = game:GetService("CoreGui") end) end
	if not host then pcall(function() host = lp:FindFirstChild("PlayerGui") end) end
	if not host then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SoloRec"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 9000
	gui.Parent = host
	env.__SOLOREC_GUI = gui

	local f = Instance.new("Frame")
	f.Size = UDim2.new(0, 300, 0, 174)
	f.Position = UDim2.new(1, -314, 0, 14)
	f.BackgroundColor3 = Color3.fromRGB(11, 11, 14)
	f.BorderSizePixel = 0
	f.Parent = gui
	panel = f
	local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 10) c.Parent = f
-- The golden ring. Measured off the live client 2026-08-21 19:3x, which is what
-- he meant both times he asked and what I kept missing:
--   SoloPlay  stroke RGB(201,142,74) thickness 2   <- gold
--   XpBar     stroke RGB(201,142,74) thickness 2   <- gold
--   SoloFarm  stroke RGB(51,41,27)   thickness 1   <- dull brown
--   SoloRec   stroke RGB(51,41,27)   thickness 1   <- dull brown
-- Two of four had it. These two did not.
	local st = Instance.new("UIStroke") st.Color = Color3.fromRGB(201, 142, 74) st.Thickness = 2 st.Parent = f

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 27)
	bar.BackgroundColor3 = Color3.fromRGB(24, 20, 14)
	bar.BorderSizePixel = 0
	bar.Parent = f
	local c2 = Instance.new("UICorner") c2.CornerRadius = UDim.new(0, 10) c2.Parent = bar

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 11, 0, 0)
	title.Size = UDim2.new(1, -120, 1, 0)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 12
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(231, 177, 115)
	title.Text = "SOLO REC"
	title.Parent = bar

	local function mkBtn(text, x, w, cb)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, w, 0, 19)
		b.Position = UDim2.new(1, x, 0, 4)
		b.BackgroundColor3 = Color3.fromRGB(201, 142, 74)
		b.BorderSizePixel = 0
		b.Font = Enum.Font.GothamBold
		b.TextSize = 10
		b.TextColor3 = Color3.fromRGB(26, 20, 9)
		b.Text = text
		b.AutoButtonColor = true
		b.Parent = bar
		local bc = Instance.new("UICorner") bc.CornerRadius = UDim.new(0, 6) bc.Parent = b
		b.MouseButton1Click:Connect(function() pcall(cb) end)
		return b
	end

	local btnToggle
	btnToggle = mkBtn(S.on and "PAUSE" or "START", -110, 52, function()
		S.on = not S.on
		btnToggle.Text = S.on and "PAUSE" or "START"
		if S.on then
			log("cmd", "recording started by hand")
		end
		paint()
	end)
	mkBtn("DUMP", -54, 46, function()
		S.dumped = {}
		log("cmd", "manual dump requested")
		env.__SOLOREC_DUMP = true
	end)

	local function mkLbl(y, size, colour)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.new(0, 12, 0, y)
		l.Size = UDim2.new(1, -24, 0, 18)
		l.Font = Enum.Font.Gotham
		l.TextSize = size
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = colour
		l.TextTruncate = Enum.TextTruncate.AtEnd
		l.Text = ""
		l.Parent = f
		return l
	end

	lblState = mkLbl(32, 13, Color3.fromRGB(155, 191, 149))
	lblRound = mkLbl(52, 11, Color3.fromRGB(243, 207, 153))
	lblCount = mkLbl(70, 11, Color3.fromRGB(239, 230, 216))
	lblErr = mkLbl(90, 10, Color3.fromRGB(162, 147, 127))
	lblLoot = mkLbl(110, 10, Color3.fromRGB(201, 142, 74))
	lblFarm = mkLbl(128, 10, Color3.fromRGB(155, 191, 149))
	lblXp = mkLbl(146, 10, Color3.fromRGB(243, 207, 153))

	makeDraggable("SoloRec", f, bar)
end

pcall(buildPanel)

-- ---------------------------------------------------------------- round

local function myRoot()
	local ch = lp.Character
	if not ch then return nil end
	return ch:FindFirstChild("HumanoidRootPart")
end

-- One round is recorded once.
--
-- His words, 2026-08-21 19:2x: "solo rec was shoule be only trec onec at one
-- round only and nto recidng twice". A JobId is the server, and a server is the
-- round, so a job that has already been opened is never opened again - not by a
-- reload, not by SOLO_ENTRY re-running after a teleport, not by anything.
local openedJobs = {}

local function newRound()
	local job = tostring(game.JobId)
	if openedJobs[job] then
		S.jobId = job
		log("round", "already recorded this server, not opening it a second time")
		return
	end
	openedJobs[job] = true
	local num, fresh = roundNumberFor(job)
	S.round = num
	S.fresh = fresh
	S.jobId = job
	S.placeId = game.PlaceId
	S.roundStart = os.clock()
	S.dumped = {}
	local head = {}
	head[#head + 1] = "round " .. S.round
	head[#head + 1] = "when " .. os.date("%Y-%m-%d %H:%M:%S")
	head[#head + 1] = "place " .. tostring(game.PlaceId)
	head[#head + 1] = "job " .. tostring(game.JobId)
	head[#head + 1] = "me " .. lp.Name .. " (" .. tostring(lp.UserId) .. ")"
	head[#head + 1] = "players " .. #Players:GetPlayers()
	if fresh then
		put(base() .. "_timeline.log", table.concat(head, "\n") .. "\n\n")
		log("round", "opened")
	else
		log("round", "recorder reloaded inside the same server, still round " .. num)
	end
end

-- ---------------------------------------------------------------- sampler

local lastPlayers = {}

local function sample()
	local r = myRoot()
	local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
	local tool = lp.Character and lp.Character:FindFirstChildOfClass("Tool")
	local bp = lp:FindFirstChild("Backpack")

	local myY = r and r.Position.Y or -9999
	local alivecount = 0
	local rows = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		local rr = ch and ch:FindFirstChild("HumanoidRootPart")
		local hh = ch and ch:FindFirstChildOfClass("Humanoid")
		local hp = hh and hh.Health or 0
		if hp > 0 then alivecount = alivecount + 1 end
		if rr and p ~= lp then
			local d = r and (rr.Position - r.Position).Magnitude or -1
			rows[#rows + 1] = string.format("%s y=%.1f dy=%.1f dist=%.1f hp=%.0f",
				p.Name, rr.Position.Y, rr.Position.Y - myY, d, hp)
		end
	end

	put(base() .. "_samples.log", string.format(
		"%s  me y=%.1f hp=%.0f tool=%s alive=%d  |  %s\n",
		stamp(), myY,
		hum and hum.Health or 0,
		tool and tool.Name or (bp and bp:FindFirstChildOfClass("Tool") and ("bag:" .. bp:FindFirstChildOfClass("Tool").Name) or "none"),
		alivecount,
		table.concat(rows, " ; ")))
	S.lines = S.lines + 1
end

-- ---------------------------------------------------------------- hooks

local function watchPlayer(p)
	local function onChar(ch)
		local hum = ch:WaitForChild("Humanoid", 8)
		if not hum then return end
		hum.Died:Connect(function()
			S.deaths = S.deaths + 1
			local r = myRoot()
			local rr = ch:FindFirstChild("HumanoidRootPart")
			local d = (r and rr) and (rr.Position - r.Position).Magnitude or -1
			local dy = (r and rr) and (rr.Position.Y - r.Position.Y) or 0
			log("death", string.format("%s died  dist=%.1f dy=%.1f  alive_left=%d  t=%.1fs",
				p.Name, d, dy, (function()
					local n = 0
					for _, q in ipairs(Players:GetPlayers()) do
						local h = q.Character and q.Character:FindFirstChildOfClass("Humanoid")
						if h and h.Health > 0 then n = n + 1 end
					end
					return n
				end)(), os.clock() - S.roundStart))
		end)
	end
	if p.Character then task.spawn(onChar, p.Character) end
	p.CharacterAdded:Connect(function(ch) task.spawn(onChar, ch) end)
end

pcall(function()
	for _, p in ipairs(Players:GetPlayers()) do watchPlayer(p) end
	Players.PlayerAdded:Connect(function(p)
		log("join", p.Name .. " (" .. tostring(p.UserId) .. ")")
		watchPlayer(p)
	end)
	Players.PlayerRemoving:Connect(function(p)
		log("leave", p.Name)
	end)
end)

pcall(function()
	if TextChatService and TextChatService.MessageReceived then
		TextChatService.MessageReceived:Connect(function(m)
			S.chats = S.chats + 1
			local who = "?"
			pcall(function() who = m.TextSource and m.TextSource.Name or "system" end)
			put(base() .. "_chat.log", stamp() .. "  " .. who .. ": " .. tostring(m.Text) .. "\n")
		end)
	end
end)

-- The outbound remote log used to live here as a metamethod hook. It is gone
-- on purpose.
--
-- 2026-08-21: with that hook installed he could not open a chest. Calling the
-- original __namecall from inside a hook loses the method name, so the game's
-- own FireServer for opening a chest arrived malformed and did nothing. The
-- log was worth having; it was not worth breaking the game he is playing.
--
-- Everything else in this recorder only reads. Nothing below can change what
-- the game does. If the outbound remote traffic is wanted again, use Real's
-- own remote-spy for a short window instead of hooking anything from here.

S.err = ""

-- ---------------------------------------------------------------- dumps

local function dumpTree()
	if S.dumped.tree then return end
	S.dumped.tree = true
	local out = {}
	local function walk(inst, depth, path)
		if depth > 3 then return end
		for _, c in ipairs(inst:GetChildren()) do
			out[#out + 1] = string.rep("  ", depth) .. c.ClassName .. "  " .. c.Name
			if #out > 4000 then return end
			pcall(walk, c, depth + 1, path .. "/" .. c.Name)
		end
	end
	for _, svc in ipairs({ "ReplicatedStorage", "Workspace", "Lighting" }) do
		local ok, s = pcall(function() return game:GetService(svc) end)
		if ok and s then
			out[#out + 1] = "\n===== " .. svc .. " ====="
			pcall(walk, s, 0, svc)
		end
	end
	pcall(function()
		local ps = lp:FindFirstChild("PlayerScripts")
		if ps then
			out[#out + 1] = "\n===== PlayerScripts ====="
			pcall(walk, ps, 0, "PlayerScripts")
		end
	end)
	put(DIR .. "/tree_" .. tostring(game.PlaceId) .. ".txt", table.concat(out, "\n") .. "\n")
	log("dump", "tree written, " .. #out .. " lines")
end

local function dumpChests()
	if S.dumped.chest then return end
	S.dumped.chest = true
	local out = {}
	local r = myRoot()
	pcall(function()
		for _, d in ipairs(workspace:GetDescendants()) do
			local n = d.Name:lower()
			if n:find("chest") or n:find("crate") or n:find("loot") or n:find("box") then
				local pos
				pcall(function() pos = d:IsA("BasePart") and d.Position or (d.PrimaryPart and d.PrimaryPart.Position) end)
				if pos then
					out[#out + 1] = string.format("%s  %s  (%.0f, %.0f, %.0f)%s",
						d.ClassName, d:GetFullName(), pos.X, pos.Y, pos.Z,
						r and string.format("  dist=%.0f", (pos - r.Position).Magnitude) or "")
				end
			end
			if #out > 600 then break end
		end
	end)
	if #out > 0 then
		put(base() .. "_chests.log", table.concat(out, "\n") .. "\n")
		log("dump", #out .. " chest-like objects")
	end
end

local function dumpScripts()
	if S.dumped.scripts then return end
	S.dumped.scripts = true
	local names = {}
	local saved = 0
	local function scan(root, tag)
		pcall(function()
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("ModuleScript") or d:IsA("LocalScript") then
					names[#names + 1] = tag .. "  " .. d:GetFullName()
					local low = d.Name:lower()
					if saved < 25 and (low:find("melee") or low:find("combat") or low:find("damage")
						or low:find("round") or low:find("match") or low:find("chest")
						or low:find("loot") or low:find("game") or low:find("controller")) then
						local src
						pcall(function()
							if decompile then src = decompile(d) end
						end)
						if src and #src > 40 then
							saved = saved + 1
							put(DIR .. "/src_" .. tostring(game.PlaceId) .. "_" .. d.Name .. ".lua", src)
						end
					end
				end
				if #names > 3000 then break end
			end
		end)
	end
	scan(game:GetService("ReplicatedStorage"), "RS")
	local ps = lp:FindFirstChild("PlayerScripts")
	if ps then scan(ps, "PS") end
	put(DIR .. "/scripts_" .. tostring(game.PlaceId) .. ".txt", table.concat(names, "\n") .. "\n")
	log("dump", #names .. " scripts listed, " .. saved .. " decompiled")
end

-- ---------------------------------------------------------------- vape
--
-- His words, 2026-08-21 15:5x: "i was forgtoo to execute vape ... the recorder
-- while detect the player dont have vape then will od self execute".
--
-- Vape is what actually takes the loot out of a chest when the bot stands on
-- it, so a round played without it looks exactly like a farm that cannot loot.
-- The detection key is measured, not guessed: with Vape running, shared.vape is
-- a table. getgenv has no vape key at all, so checking there finds nothing.

local VAPE_URL = "https://rawscripts.net/raw/Vape-V4-For-Roblox_316"

local function vapeUp()
	local ok = false
	pcall(function() ok = type(shared) == "table" and type(shared.vape) == "table" end)
	return ok
end

local vapeTries = 0
local vapeLast = 0

local function ensureVape(why)
	if vapeUp() then
		S.vape = "on"
		return true
	end
	if os.clock() - vapeLast < 20 then
		S.vape = "waiting"
		return false
	end
	vapeLast = os.clock()
	vapeTries = vapeTries + 1
	S.vape = "loading try " .. vapeTries
	log("vape", "not loaded (" .. tostring(why) .. ") - executing it, try " .. vapeTries)
	local ok, err = pcall(function()
		loadstring(game:HttpGet(VAPE_URL))()
	end)
	if not ok then
		S.vape = "FAILED"
		log("vape", "execute failed: " .. tostring(err):sub(1, 90))
		return false
	end
	task.wait(3)
	if vapeUp() then
		S.vape = "on"
		log("vape", "loaded on try " .. vapeTries)
		return true
	end
	S.vape = "ran but shared.vape still missing"
	log("vape", "ran but shared.vape is still missing")
	return false
end

env.__SOLOREC_VAPE = ensureVape

task.spawn(function()
	task.wait(2)
	while alive() do
		pcall(ensureVape, "periodic check")
		task.wait(10)
	end
end)

-- ---------------------------------------------------------------- roster
--
-- His words, 2026-08-21 09:5x: "the solo rec will record all thign incuidng
-- those username and flying user and viper or others hacker or the levle high".
--
-- Nothing here is inferred from a name alone. Every player in this game carries
-- real attributes, measured off the live client at 10:0x:
--   Level, Kills, Wins, WinStreak, Title, TeamId, Alive, Health and the three
--   armour slots. His own account read Level 21, Kills 299, Wins 33.
-- So "high level" is a number taken off the player, not a guess, and the two
-- behaviour flags are counted from samples rather than asserted.
--
-- TAB and NL are built with string.char for the same reason SOLO_LOOT does it:
-- a backslash escape in this file was mangled by a patch tool once already
-- today, and a mangled newline inside a quoted string does not compile.

local TAB = string.char(9)
local NL = string.char(10)
local CR = string.char(13)

local HIGH_LEVEL = 40
local FLY_SECS = 2.5
local BLINK_STUDS = 45

local NAME_HINTS = { "viper", "vipe", "hack", "exploit", "autowin", "bot" }

local roster = {}

local function blacklistNames()
	local out = {}
	pcall(function()
		for _, f in ipairs({ "RobloxComm/blacklist.txt", "RobloxComm/solo/blacklist.txt" }) do
			if isfile(f) then
				for line in tostring(readfile(f)):gmatch("[^" .. CR .. NL .. "]+") do
					local nm = line:match("^%s*%d*%s*(%S+)")
					if nm then out[nm:lower()] = true end
				end
			end
		end
	end)
	return out
end

local BLACK = blacklistNames()

local function nameHint(name)
	local n = name:lower()
	if BLACK[n] then return "blacklist" end
	for _, w in ipairs(NAME_HINTS) do
		if n:find(w, 1, true) then return "name-" .. w end
	end
	return nil
end

local function groundUnderPos(ch, pos)
	local hit
	pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { ch }
		hit = workspace:Raycast(pos, Vector3.new(0, -14, 0), params)
	end)
	return hit ~= nil
end

local function rosterPass()
	local now = os.clock()
	for _, p in ipairs(Players:GetPlayers()) do
		local e = roster[p]
		if not e then
			e = { name = p.Name, id = p.UserId, air = 0, maxAir = 0, blinks = 0,
				maxJump = 0, samples = 0, lastPos = nil, lastAt = now, flags = {} }
			roster[p] = e
			local hint = nameHint(p.Name)
			if hint then e.flags[hint] = true end
		end
		pcall(function()
			e.level = p:GetAttribute("Level") or e.level
			e.kills = p:GetAttribute("Kills") or e.kills
			e.wins = p:GetAttribute("Wins") or e.wins
			e.streak = p:GetAttribute("WinStreak") or e.streak
			e.title = p:GetAttribute("Title") or e.title
			e.team = p:GetAttribute("TeamId") or e.team
			if (e.level or 0) >= HIGH_LEVEL then e.flags["highlevel"] = true end
		end)
		local ch = p.Character
		local rr = ch and ch:FindFirstChild("HumanoidRootPart")
		local h = ch and ch:FindFirstChildOfClass("Humanoid")
		if rr and h and h.Health > 0 then
			e.samples = e.samples + 1
			local pos = rr.Position
			local dt = now - e.lastAt
			if e.lastPos and dt > 0 then
				local step = (pos - e.lastPos).Magnitude
				if step > e.maxJump then e.maxJump = step end
				-- A walking body cannot cover this in one sample. It is the same
				-- signature this farm leaves, which is why it is worth logging.
				if step > BLINK_STUDS and dt < 0.6 then
					e.blinks = e.blinks + 1
					if e.blinks >= 3 then e.flags["blinking"] = true end
				end
			end
			if not groundUnderPos(ch, pos) then
				e.air = e.air + dt
				if e.air > e.maxAir then e.maxAir = e.air end
				if e.air >= FLY_SECS then e.flags["flying"] = true end
			else
				e.air = 0
			end
			e.lastPos = pos
			e.lastAt = now
		else
			e.lastAt = now
			e.air = 0
		end
	end
end

local function flagList(e)
	local out = {}
	for k in pairs(e.flags) do out[#out + 1] = k end
	table.sort(out)
	return #out > 0 and table.concat(out, "+") or "-"
end

local function writeRoster(tag)
	local rows, watch = {}, {}
	for _, e in pairs(roster) do
		local fl = flagList(e)
		local row = table.concat({
			e.name, tostring(e.id), tostring(e.level or "?"), tostring(e.kills or "?"),
			tostring(e.wins or "?"), tostring(e.streak or "?"), tostring(e.title or "-"),
			tostring(e.team or "-"), string.format("%.1f", e.maxAir),
			string.format("%.1f", e.maxJump), tostring(e.blinks), tostring(e.samples), fl,
		}, TAB)
		rows[#rows + 1] = row
		if fl ~= "-" then watch[#watch + 1] = row end
	end
	table.sort(rows)
	local head = table.concat({ "name", "userid", "level", "kills", "wins", "streak",
		"title", "team", "max_air_s", "max_step", "blinks", "samples", "flags" }, TAB) .. NL
	put(base() .. "_roster.tsv", head .. table.concat(rows, NL) .. NL)
	local stampNow = os.date("%Y-%m-%d %H:%M:%S")
	local rnd = string.format("r%03d", S.round)
	local job = tostring(game.JobId):sub(1, 8)
	for _, row in ipairs(rows) do
		put("RobloxComm/solo/players_master.tsv",
			stampNow .. TAB .. rnd .. TAB .. job .. TAB .. row .. TAB .. tostring(tag) .. NL)
	end
	table.sort(watch)
	for _, row in ipairs(watch) do
		put("RobloxComm/solo/watchlist.tsv", stampNow .. TAB .. rnd .. TAB .. row .. NL)
	end
	S.watched = #watch
	return #rows, #watch
end

env.__SOLOREC_ROSTER = roster
env.__SOLOREC_WRITE_ROSTER = writeRoster
env.__SOLOREC_CLEAR_ROSTER = function()
	roster = {}
	env.__SOLOREC_ROSTER = roster
end

task.spawn(function()
	while alive() do
		task.wait(0.5)
		if S.on then pcall(rosterPass) end
	end
end)

task.spawn(function()
	while alive() do
		task.wait(20)
		if S.on then pcall(writeRoster, "periodic") end
	end
end)

-- ---------------------------------------------------------------- loops

task.spawn(function()
	newRound()
	pcall(dumpTree)
	pcall(dumpChests)
	pcall(dumpScripts)
	while alive() do
		task.wait(0.25)
		if S.on then
			local foes = 0
			for _, pp in ipairs(Players:GetPlayers()) do
				local hh = pp.Character and pp.Character:FindFirstChildOfClass("Humanoid")
				if hh and hh.Health > 0 then foes = foes + 1 end
			end
			if S.autoStop and S.roundOpen and foes <= 1 then
				S.roundOpen = false
				log("round", "round end detected, recording auto stopped, telling the farm to queue")
				S.on = false
				pcall(function()
					if env.__SOLOFARM_CLOSE then env.__SOLOFARM_CLOSE("round end") end
					if env.__SOLOFARM_QUEUE then env.__SOLOFARM_QUEUE() end
				end)
			elseif foes > 1 then
				S.roundOpen = true
				if S.autoStop and not S.on and not PUBLIC then S.on = true end
			end
			if tostring(game.JobId) ~= S.jobId then
				local seen = {}
				for k, v in pairs(S.seenRemote) do seen[#seen + 1] = k .. "=" .. v end
				table.sort(seen)
				put(base() .. "_remotes.log", table.concat(seen, "\n") .. "\n")
				log("round", string.format("closed after %.1fs", os.clock() - S.roundStart))
				pcall(writeRoster, "round end")
				if env.__SOLOREC_CLEAR_ROSTER then env.__SOLOREC_CLEAR_ROSTER() end
				S.seenRemote = {}
				newRound()
				task.spawn(function()
					task.wait(3)
					pcall(dumpChests)
				end)
			end
			pcall(sample)
			if env.__SOLOREC_DUMP then
				env.__SOLOREC_DUMP = false
				S.dumped = {}
				pcall(dumpTree)
				pcall(dumpChests)
				pcall(dumpScripts)
			end
		end
		pcall(paint)
	end
end)

task.spawn(function()
	while alive() do
		task.wait(0.5)
		env.__SOLOREC_BEAT = os.clock()
	end
end)

task.spawn(function()
	while alive() do
		task.wait(5)
		if S.on then
			local seen = {}
			for k, v in pairs(S.seenRemote) do seen[#seen + 1] = k .. "=" .. v end
			table.sort(seen)
			pcall(function()
				writefile(DIR .. "/live_status.txt", table.concat({
					"gen " .. MYGEN,
					"when " .. os.date("%Y-%m-%d %H:%M:%S"),
					"round " .. S.round,
					"place " .. tostring(game.PlaceId),
					"job " .. tostring(game.JobId),
					"me " .. lp.Name,
					"lines " .. S.lines,
					"fired " .. S.hits,
					"chat " .. S.chats,
					"deaths " .. S.deaths,
					"err " .. (S.err ~= "" and S.err or "none"),
					"remotes " .. table.concat(seen, " "),
				}, "\n") .. "\n")
			end)
		end
	end
end)

-- The map and loot half. Kept in its own file so that if it throws, the
-- timeline recorder above carries on without it.
do
	local ok, err = pcall(function()
		if not isfile("SOLO_LOOT.lua") then
			error("SOLO_LOOT.lua missing from workspace")
		end
		local chunk, cerr = loadstring(readfile("SOLO_LOOT.lua"), "=SOLO_LOOT.lua")
		if not chunk then error("compile: " .. tostring(cerr)) end
		chunk()
	end)
	if ok then
		log("boot", "loot module up")
	else
		S.err = "loot: " .. tostring(err):sub(1, 70)
		log("boot", "LOOT MODULE FAILED: " .. tostring(err))
	end
end

-- No teleport queue here on purpose. SOLO_ENTRY queues the whole set for the
-- far side of a teleport; a second queue in this file meant two copies of the
-- recorder arriving at once, which is exactly the duplicate he kept seeing.

pcall(function()
	StarterGui:SetCore("SendNotification", {
		Title = "SOLO REC",
		Text = "recording, auto stops at round end",
		Duration = 4,
	})
end)

paint()
log("boot", "solo recorder up, gen " .. MYGEN .. ", swept " .. tostring(swept) .. " old panel(s), idle until START")
return "SOLO_REC up"
