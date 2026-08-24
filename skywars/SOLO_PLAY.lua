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
			local ok, d = pcall(function() return game:GetService("HttpService"):JSONDecode(readfile(POSFILE)) end)
			if ok and type(d) == "table" then t = d end
		end
		local p = frame.Position
		t[name] = { xs = p.X.Scale, xo = p.X.Offset, ys = p.Y.Scale, yo = p.Y.Offset }
		writefile(POSFILE, game:GetService("HttpService"):JSONEncode(t))
	end)
end

local function makeDraggable(name, frame, handle)
	frame.Active = true
	handle.Active = true
	-- Tell HACKFORMAT this panel already has a drag and a saved position.
	--
	-- It checks this same attribute before adding its own, and without it the
	-- panel gets two handlers on one bar: the frame moves twice the mouse delta
	-- and the position is written to two different files that then fight on the
	-- next load. One owner per panel, and the owner is the panel's own file.
	frame:SetAttribute("HFDrag", true)
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
-- 2026-08-22 15:1x - THE ID IS A GAME MODE, NOT A QUEUE ID, AND THIS IS PROVEN
-- BY THE GAME'S OWN SOURCE RATHER THAN BY TRYING BOTH.
--
-- matchmaking-controller, decompiled:
--
--     local GameMode = RuntimeLib.import(..., "TS", "game", "game-mode").GameMode
--     local EggWarsQuads = GameMode.EggWarsQuads
--     ...
--     local v1 = p2 or PlaceUtil.getGameMode()
--     if not v1 then v1 = EggWarsQuads end
--     Events["f77d9402-..."]:fire(true, v1)
--
-- Both the normal value and the fallback are GameMode strings. GameMode holds
-- SkyWarsSolo, SkyWarsDuos, SkyWarsTrios, SkyWarsQuads, SkyWarsOctos,
-- EggWarsQuads, DuelsSolo, DuelsDuos - and note there is no Private in it at
-- all, so a custom room is not even reachable through this call.
--
-- QueueId ("solo", "duos", "eggwars_quads", "private" ...) is a different
-- table used elsewhere. Handing "solo" to this event is the wrong type, the
-- server does not answer it, and the client sits on "Searching for a game"
-- with the timer climbing - measured, ten minutes of it at 14:5x.
--
-- The 2026-08-21 note that blamed "SkyWarsSolo" for the custom room was wrong
-- about the mechanism: the old queueNow never passed QUEUE_ID to anything. It
-- read
--     if BANNED_QUEUE[QUEUE_ID] then error(...) end
--     armGameAutoQueue()
--     mm:joinQueueIn(0)
-- so the constant was checked and then thrown away, and joinQueueIn names no
-- mode at all. Whatever put him in a custom room, it was not that string.
local QUEUE_ID = "SkyWarsSolo"

-- Modes this project must never be put into.
local BANNED_QUEUE = { EggWarsQuads = true, DuelsSolo = true, DuelsDuos = true }

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

-- 2026-08-22 15:0x - THIS IS WHY IT JOINED EGGWARS.
--
-- Decompiled straight out of the game's own matchmaking-controller, line 147:
--
--   function joinQueue(self, p2)
--     if nl6:isOpen() or z0b:isTeleporting() or not self:canQueue() then return end
--     local v1 = p2 or PlaceUtil.getGameMode()
--     if not v1 then v1 = EggWarsQuads end          <-- the default
--     Events["f77d9402-9920-4322-8846-d72e6dd27c51"]:fire(true, v1)
--   end
--
--   function joinQueueIn(self, delay)
--     ... Flamework.resolveDependency("4N"):updateQueue(os.time() + delay, false)
--   end
--
-- joinQueueIn only sets a timer, and when that timer fires it calls joinQueue
-- with NO id. In the match place PlaceUtil.getGameMode() answers Solo, so it
-- works. In the LOBBY it answers nothing, and the fallback on the next line is
-- EggWarsQuads. Measured 14:47:40: queued from the lobby, landed in place
-- 8951451142, which is the EggWars match place.
--
-- So the id is spelled out now, every time. The earlier note that
-- "joinQueue does nothing, use joinQueueIn" was reading the wrong signal:
-- joinQueue returns silently when a menu is open or a teleport is already in
-- flight, and isInQueue only flips once the server has answered, so a check one
-- frame later always says false.
-- THE EVENT ID IS GENERATED PER PLACE. NEVER FIRE IT BY NAME.
--
-- Measured 2026-08-22 15:2x by decompiling the same controller in two places:
--   match place 8542275097   Events["f77d9402-9920-4322-8846-d72e6dd27c51"]
--   lobby       8542259458   Events["e83ed51a-a6d6-4326-bc3f-c7add422229b"]
-- Same function, same line number, different id. So a hardcoded id is not a
-- fallback, it is a loaded gun: in a third place that string is either absent
-- or it belongs to some completely unrelated event. Same trap as the hardcoded
-- Flamework ids that broke the EggWars farm when the game updated.
--
-- So nothing here fires an event by name. Everything goes through the
-- controller, which is resolved from its module by reflection and is therefore
-- right in whatever place we are standing in - and the shadow SOLO_ENTRY puts
-- on joinQueue catches every internal timer inside the game as well, which is
-- the whole reason the EggWars default could reach us in the first place.
local locked = { mm = false }

local function lockQueueToSolo()
	pcall(function()
		local mm = matchmaking()
		if not mm then return end
		if rawget(mm, "__soloLocked") then locked.mm = true return end
		local orig = mm.joinQueue
		if type(orig) ~= "function" then return end
		mm.joinQueue = function(self, id, ...)
			if id ~= QUEUE_ID then
				P.note = "joinQueue mode forced from " .. tostring(id) .. " to " .. QUEUE_ID
			end
			return orig(self, QUEUE_ID, ...)
		end
		rawset(mm, "__soloLocked", true)
		locked.mm = true
	end)
	return locked.mm, "controller=" .. tostring(locked.mm)
end
env.__SOLOPLAY_LOCK_QUEUE = lockQueueToSolo
env.__SOLOPLAY_LOCKED = locked

-- The load lock. A map load measures 5 to 12 seconds in solo_boot.log, so 20
-- seconds is a load that is never coming back, and 25 is longer than any
-- honest wait for one.
local LOCK_FILE = "RobloxComm/solo/loadlock.txt"
local LOCK_STALE = 20
local LOCK_WAIT = 25

local function queueNow(reason)
	if BANNED_QUEUE[QUEUE_ID] then P.note = "refusing to queue into " .. QUEUE_ID return false end
	local mm = matchmaking()
	if not mm then
		P.note = "no matchmaking controller in this place - not queueing blind"
		return false
	end
	local q, can = false, false
	pcall(function() q = mm:isInQueue() end)
	pcall(function() can = mm:canQueue() end)
	P.queued, P.canQueue = q, can
	if q then P.note = "already in queue" return true end
	if not can then P.note = "canQueue is false right now" return false end

	-- THREE BOTS QUEUEING IN THE SAME INSTANT LAND IN THE SAME MATCH.
	--
	-- Measured 2026-08-22 17:17:54, and both surviving clients logged the same
	-- line in the same second:
	--
	--   Error [DFLog::NetworkClient] Failed to connect to server at
	--   128.116.5.33|53142, no response.
	--
	-- That is error 279, failed to connect to the game. One server did not
	-- answer and it took out every bot at once, because the matchmaker had put
	-- all of them into that one server - they had queued together.
	--
	-- Landing together is a loss anyway: one of them takes the round and the
	-- other two spent it for nothing. So the join is spread by bot number. It
	-- costs the last bot about two and a half seconds and it buys three separate
	-- matches, which is the whole reason there are three clients.
	--
	-- The button he presses is never delayed - only the automatic path.
	if reason ~= "button" then
		local n = 0
		pcall(function()
			local T = env.__SOLOTEAM
			if T and tonumber(T.num) then n = tonumber(T.num) end
		end)
		-- 1.2s was too small to matter. The thing being separated is a map load
		-- that measures 3 to 5 seconds, so the spacing has to be bigger than the
		-- load or the three still overlap inside it. 5 seconds apart means bot1
		-- has finished building its map before bot2 starts, and bot3 after that.
		--
		-- It costs the third bot ten seconds a round and it buys three loads that
		-- do not fight, which is the difference between a heavy frame and a hang.
		-- ONE MAP LOAD AT A TIME, ACROSS ALL CLIENTS.
		--
		-- 2026-08-24 03:3x. Two clients died tonight, 03:33:02 and 03:38:34, and
		-- both died the same way: Roblox's own ESGamePerfMonitor opened a second
		-- D3D9 graphics device during the map load, the frame never came back, and
		-- the hang monitor ended the process four seconds later.
		--
		-- Nineteen client logs from today. Exactly two contain "ESGamePerfMonitor
		-- GPU", and they are exactly the two that died. Every flag that would turn
		-- that monitor off is already in the Fishstrap settings file and Roblox
		-- denies every one of them by name, so it cannot be switched off.
		--
		-- What CAN be removed is the thing that turns its probe into a hang. Both
		-- deaths happened while another client was loading a map in the same
		-- second - the first during the launch of all four, the second with
		-- format.log showing another client's "map settled" at 03:38:30. Creating a
		-- D3D9 device while other clients are building maps on the same 3060 is
		-- what stalls; there is one GPU in this machine and no second card.
		--
		-- So loads are now serialised. A client may not join a queue while another
		-- client is loading a map. The old fixed 0/4/8/12 stagger only hoped they
		-- would not collide; this makes it impossible.
		--
		-- Two escapes so a dead client can never freeze the farm: a lock older
		-- than LOCK_STALE is taken from whoever left it, and no client waits more
		-- than LOCK_WAIT before going anyway.
		do
			local t0 = os.clock()
			local waited, why = 0, "free"
			while os.clock() - t0 < LOCK_WAIT do
				local holder, at = 0, 0
				pcall(function()
					if isfile(LOCK_FILE) then
						local a, b = readfile(LOCK_FILE):match("^(%d+)|(%d+)")
						holder, at = tonumber(a) or 0, tonumber(b) or 0
					end
				end)
				if holder == 0 or holder == lp.UserId then why = "free" break end
				if (os.time() - at) > LOCK_STALE then why = "took a stale lock" break end
				why = "another client is loading a map"
				task.wait(0.4)
				waited = os.clock() - t0
			end
			pcall(function()
				writefile(LOCK_FILE, tostring(lp.UserId) .. "|" .. tostring(os.time()))
			end)
			P.note = string.format("load lock after %.1fs (%s)", waited, why)
		end
	end

	armGameAutoQueue()
	local ok = pcall(function() mm:joinQueue(QUEUE_ID) end)

	-- Verify rather than assume. joinQueue can return having done nothing at
	-- all - a menu open is enough - and the old code called that a success.
	local landed = false
	for _ = 1, 20 do
		local v = false
		pcall(function() v = mm:isInQueue() end)
		if v then landed = true break end
		task.wait(0.1)
	end

	P.queued = landed
	P.note = landed
		and ("queued into " .. QUEUE_ID .. " (" .. tostring(reason) .. ") at " .. os.date("%H:%M:%S"))
		or ("join sent but isInQueue never turned true (" .. tostring(reason) .. ")")
	return landed or ok
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

-- Smaller bites. 1200 descendants in one frame is a long frame, and a long
-- frame during a map load is exactly when the hang monitor fires.
local STRIP_CHUNK = 60
local qStripped = 0
local qBusy = false

-- ONCE A ROUND, NOT ONCE A SECOND.
--
-- Caught 2026-08-22 15:35 with the named long-frame log HACKFORMAT now writes.
-- Every single entry said the same thing:
--
--   15:32:49  long frame 0.65s  during=solo play quality sweep
--   15:35:14  long frame 0.50s  during=solo play quality sweep
--   15:35:26  long frame 0.46s  during=solo play quality sweep
--   15:35:29  long frame 0.63s  during=solo play quality sweep
--   15:35:32  long frame 2.47s  during=solo play quality sweep
--   15:35:39  long frame 3.14s  during=solo play quality sweep
--
-- The keeper loop ends with "if C.quality then applyQuality() end" and that
-- loop ticks every second, so this walked workspace:GetDescendants() once a
-- second for the whole round - during combat, during the map load, forever.
-- qBusy only stopped it re-entering itself; it never stopped it starting again
-- a second later.
--
-- A 3.14 second frame during a map load is the shape that kills this client:
-- three deaths on 2026-08-21 all landed eight seconds into loading a new map
-- with a HangMonitor timeout as the last line. So this is not a tidiness fix.
--
-- One sweep per server, keyed on JobId, the same way HACKFORMAT's boost is.
-- His QUALITY button passes force and always runs.
local qJob = ""
local qWalked = 0

local function memMb()
	local ok, v = pcall(function()
		return game:GetService("Stats"):GetTotalMemoryUsageMb()
	end)
	return ok and v or 0
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

-- THE WHOLE POINT IS LOW QUALITY, AND THERE IS A ONE LINE WAY TO GET IT.
--
-- His words, 2026-08-24 22:0x: "did u evne thinnnign about waht is the best
-- queatiy? that was matching the goal in simple ways". He is right and the
-- sweep below was never the simple way. Walking every descendant to set
-- CastShadow and Material one object at a time is a whole-workspace job that
-- has to be scheduled around a load window; the engine already exposes the same
-- outcome as four global switches that cost nothing and cannot produce a long
-- frame.
--
-- Every name here was checked against E:\tools\luau\globalTypes.d.luau before
-- it was written, not remembered: RenderSettings.QualityLevel line 16434,
-- RenderSettings.MeshPartDetailLevel line 16433 (this is the global form of the
-- per-MeshPart RenderFidelity that the engine refuses at run time),
-- Lighting.GlobalShadows line 14084, UserGameSettings.SavedQualityLevel 18821.
--
-- Result goes in quality.tsv so "did the simple way work" is a number and not
-- an opinion.
local qGlobalDone = ""
local qFpsWant = 0
-- SEVEN CLIENTS MUST NOT FIGHT OVER ONE FILE.
--
-- Every high frequency log was a single shared path. put() and putRoll() both
-- append, and appendfile opens, writes and closes the file each time, so seven
-- processes hitting the same path several times a second is lock contention on
-- the main thread - and a stalled main thread is exactly the long frame that
-- Roblox's HangMonitor kills a client for. live_status.txt was worse than the
-- rest: it uses writefile, so seven clients were each rewriting the whole file
-- and the last writer won.
--
-- The measurement tables (ab_test, kills, chest_contents) stay shared on
-- purpose - a few lines per round each, and they are only useful read together.
local function quickQuality(job)
	local ok, fail = {}, {}
	local function try(name, fn)
		if pcall(fn) then ok[#ok + 1] = name else fail[#fail + 1] = name end
	end
	try("QualityLevel", function()
		settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
	end)
	try("MeshPartDetailLevel", function()
		settings().Rendering.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level04
	end)
	try("EnableFRM", function()
		settings().Rendering.EnableFRM = false
	end)
	try("GlobalShadows", function()
		game:GetService("Lighting").GlobalShadows = false
	end)
	try("SavedQualityLevel", function()
		UserSettings():GetService("UserGameSettings").SavedQualityLevel =
			Enum.SavedQualitySetting.QualityLevel1
	end)
	-- THE FRAME CAP IS THE ONE THAT DECIDES WHETHER SEVEN CLIENTS FIT.
	--
	-- Measured 2026-08-25 00:0x on RAMST: i7-8700, 6 physical / 12 logical, so
	-- the whole box is 1200% of one core. The 2026-08-20 measurement says an
	-- IDLE client costs about 166%, and seven of those is 1162% - 97% of the
	-- machine before the farm layer is even loaded.
	--
	-- BOOST.lua already holds this lever and RobloxComm/boost_fps.txt already
	-- says 20, but nothing in the solo stack has ever loaded BOOST - fps.tsv
	-- measured 59 to 61 all evening, so the cap has never once been applied.
	--
	-- Only the one line is taken from it. BOOST also walks the whole workspace
	-- to kill particle emitters, and a full descendant walk during a map load is
	-- exactly what killed a client at 21:32 tonight. The cap needs no walk.
	try("fpscap", function()
		local want = 20
		pcall(function()
			if isfile("RobloxComm/boost_fps.txt") then
				local n = tonumber((readfile("RobloxComm/boost_fps.txt"):gsub("%s", "")))
				if n and n >= 5 and n <= 240 then want = n end
			end
		end)
		if setfpscap then setfpscap(want) end
		qFpsWant = want
	end)
	pcall(function()
		local line = os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
			.. tostring(job):sub(1, 8) .. string.char(9)
			.. "fps=" .. tostring(qFpsWant) .. string.char(9)
			.. "took=" .. table.concat(ok, ",") .. string.char(9)
			.. "refused=" .. (#fail > 0 and table.concat(fail, ",") or "-") .. string.char(10)
		local p = "RobloxComm/solo/quality.tsv"
		if isfile(p) then appendfile(p, line) else writefile(p, line) end
	end)
	return #ok, #fail
end

-- FPS, SAMPLED, SO THE TWO ROADS CAN BE COMPARED INSTEAD OF ARGUED ABOUT.
--
-- One row every two seconds with the seconds since the drop, so the file shows
-- what the four global switches bought on their own and whether the heavy sweep
-- at second twelve moves the number at all. If it does not, the sweep goes.
local fpsFrames = 0
task.spawn(function()
	while alive() do
		RunService.Heartbeat:Wait()
		fpsFrames = fpsFrames + 1
	end
end)
task.spawn(function()
	local last, lastT = 0, os.clock()
	while alive() do
		task.wait(2)
		local now, nowT = fpsFrames, os.clock()
		local fps = (now - last) / math.max(0.01, nowT - lastT)
		last, lastT = now, nowT
		pcall(function()
			if game.PlaceId ~= 8542275097 then return end
			local FF = getgenv and getgenv().__SOLOFARM
			local drop = FF and tonumber(FF.dropAt) or 0
			if drop <= 0 then return end
			local line = os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
				.. tostring(game.JobId):sub(1, 8) .. string.char(9)
				.. string.format("t=%.1f", os.clock() - drop) .. string.char(9)
				.. string.format("fps=%.0f", fps) .. string.char(9)
				.. "global=" .. tostring(qGlobalDone ~= "") .. string.char(9)
				.. "sweep=" .. tostring(qJob == tostring(game.JobId)) .. string.char(10)
			local p = "RobloxComm/solo/fps_" .. lp.Name .. ".tsv"
			if isfile(p) then appendfile(p, line) else writefile(p, line) end
		end)
	end
end)

local function applyQuality(force)
	if not C.quality or qBusy then return end
	local job = tostring(game.JobId)
	if not force and qJob == job then return end
	-- And not while the map is still arriving. The whole reason a long frame is
	-- dangerous is that it lands during the load, so the one sweep a round waits
	-- for the chests to exist before it walks anything. The job is not claimed
	-- until the sweep actually starts, so this simply tries again next second.
	-- Both the place id and the settled test are spelled out here rather than
	-- borrowed from further down the file. MATCH_PLACE and mapSettled are both
	-- declared BELOW this function, so the names read nil at this point - the
	-- place comparison would silently never match, and calling mapSettled threw
	-- "attempt to call a nil value" at 15:38:25 and took the whole panel down
	-- with it.
	if not force and game.PlaceId == 8542275097 then
		local ready = false
		pcall(function()
			local bc = workspace:FindFirstChild("BlockContainer")
			local map = bc and bc:FindFirstChild("Map")
			local chests = map and map:FindFirstChild("Chests")
			ready = chests ~= nil and #chests:GetChildren() > 0
		end)
		if not ready then return end
	end
	qJob = job
	qBusy = true
	-- Named, so a long frame caught by HACKFORMAT says it was this and not a
	-- mystery. Cleared on every exit path below.
	env.__SOLO_BUSY = "solo play quality sweep"
	local before = memMb()
	local n = 0
	local qT0 = os.clock()
	local qTa, qTb, qTc = 0, 0, 0

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

	qTa = os.clock() - qT0

	-- Terrain:Clear() is GONE on purpose.
	--
	-- 2026-08-21 21:45 the client died eight seconds into loading a new map,
	-- right after the log shows Terrain TextureArray and the D3D9 device being
	-- rebuilt, and the last line is a HangMonitor timeout. Windows recorded no
	-- crash, memory was flat at 3.5 GB all six hours, and it was not kicked. The
	-- one thing that reaches into terrain and textures during a load is this
	-- function. Clearing terrain while the engine is still building it is not
	-- worth whatever it saved - this map is block built and has almost no
	-- terrain anyway.

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

	qTb = os.clock() - qT0

	-- Yield every so often. Done in one go this is a single frame hundreds of
	-- milliseconds long, and during that frame nothing else runs - including the
	-- farm's anti-void catch, which is how a bot gets from the catch line to
	-- below -500 and is deleted. Spread over frames it costs the same and blocks
	-- nothing.
	pcall(function()
		local seen = 0
		local all = workspace:GetDescendants()
		qWalked = #all
		for _, d in ipairs(all) do
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
				-- Routed through trySet so a refusal is learned once, not repeated
				-- on every mesh of every round.
				trySet(d, "RenderFidelity", Enum.RenderFidelity.Performance)
				-- RenderFidelity IS REFUSED AT RUN TIME AND IT KILLED THE CLIENT.
				--
				-- Every write printed "Warning: Cannot change SolidModel
				-- RenderFidelity during Run-Time" and changed nothing. Client
				-- log 20260824T131013Z, 22 minutes of one client: 20,863 of
				-- those lines, in bursts of 550 to 620 inside a single second,
				-- once per sweep per round. That burst IS a long frame.
				--
				-- 21:32:31.7 six hundred of them -> 21:32:32.3 Roblox's own
				-- ESGamePerfMonitor opens a SECOND D3D9 device on the 3060 ->
				-- 21:32:36.0 HangMonitor timeout, process gone. Same three-step
				-- death as 03:33 and 03:38 this morning. Zero successes against
				-- twenty thousand refusals, so there is nothing to lose here.
				d.CastShadow = false
				d.Reflectance = 0
			elseif d:IsA("BasePart") then
				trySet(d, "CastShadow", false)
				trySet(d, "Reflectance", 0)
				if d.Material ~= Enum.Material.SmoothPlastic then
					trySet(d, "Material", Enum.Material.SmoothPlastic)
				end
			end
		end
	end)

	qTc = os.clock() - qT0

	-- Cleared BEFORE the settle wait. It used to stay set through task.wait(1),
	-- so any long frame the engine produced in that second was written down as
	-- "solo play quality sweep" when the sweep was already finished.
	env.__SOLO_BUSY = nil

	-- Which phase actually costs the seconds, written down instead of guessed.
	-- 18:00:37 this sweep carried a 5.39s frame and the three phases were
	-- indistinguishable from the outside.
	pcall(function()
		appendfile("RobloxComm/hf/qphase.log", string.format(
			"%s  lighting %.2fs  render-strip %.2fs  descendants %.2fs  walked %d  stripped %d\n",
			os.date("%Y-%m-%d %H:%M:%S"), qTa, qTb - qTa, qTc - qTb, qWalked, n))
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
-- Wait for the map to finish arriving before touching anything.
--
-- The old version slept a flat four seconds after the JobId changed and then
-- started destroying instances. Measured on this game, the map streams in over
-- about nine seconds, so four seconds lands in the middle of the load - the
-- worst possible moment to walk the tree and delete things out of it.
--
-- The settled test is the same one the farm uses: the tier four chests exist.
-- When they do, the map is really there. There is a hard cap so a map that
-- never settles does not mean the downgrade never runs.
local function mapSettled()
	local ok = false
	pcall(function()
		local bc = workspace:FindFirstChild("BlockContainer")
		local map = bc and bc:FindFirstChild("Map")
		local chests = map and map:FindFirstChild("Chests")
		ok = chests ~= nil and #chests:GetChildren() > 0
	end)
	return ok
end

local sweptJob = ""

task.spawn(function()
	while alive() do
		task.wait(2)
		local job = tostring(game.JobId)
		-- THE CHEAP HALF RUNS THE INSTANT WE ARE IN, EVERY ROUND.
		--
		-- No walk, no descendants, no frame to lose - so there is no reason to
		-- schedule it around the load window the way the sweep below has to be.
		if C.quality and job ~= qGlobalDone and game.PlaceId == 8542275097 then
			qGlobalDone = job
			quickQuality(job)
		end
		if C.quality and job ~= sweptJob and game.PlaceId == 8542275097 then
			local deadline = os.clock() + 25
			while os.clock() < deadline and not mapSettled() do task.wait(0.5) end
			-- TWO SECONDS PUT THE SWEEP INSIDE THE WINDOW THAT KILLS THE CLIENT.
			--
			-- 2026-08-24 21:32, measured from three files that agree: farm_live.log
			-- opens the round at 21:32:29, sweep.log writes SWEEP START at
			-- 21:32:32, and the client log's last line is a HangMonitor timeout at
			-- 21:32:36. Drop, sweep three seconds later, dead at second seven.
			--
			-- StreamingEnabled is false in this game, so the tier 4 chests exist
			-- the instant we land and mapSettled() is already true - the wait it
			-- was supposed to provide never happened at all. Only the flat
			-- task.wait(2) stood between the drop and a full workspace walk.
			--
			-- 12 seconds clears the 7-to-8 second death window with room. The
			-- round is 20 to 30 seconds so the sweep now lands mid-round, which
			-- costs a little fps early and buys a client that is still alive.
			local FF = getgenv and getgenv().__SOLOFARM
			local drop = FF and tonumber(FF.dropAt) or 0
			if drop > 0 then
				while os.clock() - drop < 12 do task.wait(0.5) end
			else
				task.wait(12)
			end
			sweptJob = job
			-- A marker either side, so if the client dies mid sweep the file
			-- shows a start with no finish and this stops being a suspicion.
			local function mark(t)
				pcall(function()
					if not isfolder("RobloxComm") then makefolder("RobloxComm") end
					if not isfolder("RobloxComm/solo") then makefolder("RobloxComm/solo") end
					local line = os.date("%Y-%m-%d %H:%M:%S") .. "  " .. t .. "  job "
						.. job:sub(1, 8) .. string.char(10)
					-- Per client, same reason as the other high frequency logs:
					-- seven processes appending one path is lock contention on the
					-- main thread, and the main thread stalling is the long frame.
					local sp = "RobloxComm/solo/sweep_" .. lp.Name .. ".log"
					if isfile(sp) then
						appendfile(sp, line)
					else
						writefile(sp, line)
					end
				end)
			end
			mark("SWEEP START  settled=" .. tostring(mapSettled()))
			pcall(applyQuality)
			mark("sweep finished")
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

-- 35s sits inside the 30 to 40 he named. A healthy queue delivers in 2 to 4.
local QUEUE_STUCK_SECS = 35

-- A WINDOW TO TOUCH THE THING BEFORE IT FLIES OFF.
--
-- His report, 2026-08-24 04:5x: "the quee that fukcing so annoying while at the
-- start wile inject and execute hat atuo, that wa susper suck, and a big prblme
-- for me".
--
-- Four clients inject one after another and every one of them queued on its
-- first tick, so all four teleported into matches while he was still looking at
-- them. Nothing was reachable in that window - which was worse than it sounds,
-- because the mouse was locked to the centre at the time, so he could not press
-- SELF QUEUE OFF either.
--
-- This holds the AUTOMATIC queue for the first stretch after an injection only.
-- It is keyed on a getgenv flag, so a round change - which reloads this whole
-- file - does not pay it again. Twenty seconds is his window; the button still
-- works the whole time, and pressing it queues immediately.
local FIRST_GRACE = 20
if env.__SOLOPLAY_INJECTED_AT == nil then
	env.__SOLOPLAY_INJECTED_AT = os.clock()
end
local function inFirstGrace()
	local at = env.__SOLOPLAY_INJECTED_AT
	return at ~= nil and (os.clock() - at) < FIRST_GRACE
end

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

			-- How long have we been sitting in the queue without a game arriving.
			if P.queued and not D.inRound then
				if not D.queuedSince then D.queuedSince = os.clock() end
			else
				D.queuedSince = nil
			end

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
			-- WRONG GAME is not the same as idle, and it is the one thing that
			-- gets acted on whether or not self queue is switched on.
			--
			-- 2026-08-22 14:47: a queue call from the lobby landed the client in
			-- place 8951451142, the EggWars match place, because the game's own
			-- joinQueue defaults to EggWarsQuads when nobody names a queue. The
			-- id is spelled out now so it cannot happen again, but if anything
			-- else ever puts this client somewhere that is not SkyWars solo, it
			-- would otherwise sit there forever with the farm switched off,
			-- which is the five hours of 2026-08-21 all over again.
			--
			-- This is NOT the automatic back-to-lobby he banned on the EggWars
			-- side. That one fired at the end of a healthy round and cost 108 to
			-- 781 seconds between games. This one only fires when the client is
			-- in a place this project does not play.
			local here = game.PlaceId
			if here ~= MATCH_PLACE and here ~= LOBBY_PLACE then
				-- HE IS ALLOWED TO GO SOMEWHERE ON PURPOSE.
				--
				-- 2026-08-24, his words: "why i was want to go to custoem, but it
				-- just auto telpted back to lobby?, it was off those alreayd".
				--
				-- He is right and the comment above is why it bit him: this branch
				-- deliberately fires whether or not self queue is on, because a
				-- client stranded in the wrong game with the farm off would sit
				-- there for hours. That reasoning holds for an ACCIDENT. A custom
				-- room he walked into himself is not an accident, and dragging him
				-- out of it is the farm overruling its owner.
				--
				-- byHand is the signal and it already exists: SOLO_FARM sets it
				-- when he presses STOP on the panel and clears it when he presses
				-- START. Hand on the button means he is driving, so this watchdog
				-- stands down and lets him sit wherever he likes. With the farm
				-- running it behaves exactly as before.
				local drivenByHim = false
				pcall(function()
					local FF = getgenv().__SOLOFARM
					drivenByHim = FF ~= nil and FF.byHand == true
				end)
				if drivenByHim then
					P.note = "in place " .. tostring(here) .. " and you stopped the farm by hand - leaving you alone"
					return
				end
				if os.clock() - (D.lastRescue or 0) < 60 then return end
				D.lastRescue = os.clock()
				D.acted = D.acted + 1
				P.note = "WRONG PLACE " .. tostring(here) .. " - going back to the skywars lobby"
				pcall(function()
					if not isfolder("RobloxComm/solo") then makefolder("RobloxComm/solo") end
					local line = os.date("%Y-%m-%d %H:%M:%S") .. "\twrong place\t" .. tostring(here)
						.. "\tsent back to lobby\n"
					if isfile("RobloxComm/solo/selfdebug.log") then
						appendfile("RobloxComm/solo/selfdebug.log", line)
					else writefile("RobloxComm/solo/selfdebug.log", line) end
				end)
				pcall(function()
					game:GetService("TeleportService"):Teleport(LOBBY_PLACE, lp)
				end)
				return
			end
			if not C.autoQueue then return end
			if inFirstGrace() then return end
			if D.inRound then return end

			-- STUCK ON "SEARCHING FOR A GAME".
			--
			-- His words, 2026-08-24 03:2x: "it should eahc bot while detect the
			-- searching for a game was more hten 30-40sec+ then will auto canel and
			-- start a new game instead, beucase now the bot f23 that now was facing
			-- the prbme".
			--
			-- The line below used to read "if P.queued then return end", so being in
			-- the queue was treated as proof that everything was fine. It is not:
			-- isInQueue turns true the moment the join is accepted and stays true
			-- whether or not a server ever arrives, and queueNow itself returns
			-- early on "already in queue" - so once a queue went dead, nothing in
			-- this file could ever fix it and the client sat there for good.
			--
			-- Leaving and re-joining is the only thing that gets a new ticket.
			if P.queued then
				local waited = os.clock() - (D.queuedSince or os.clock())
				if waited < QUEUE_STUCK_SECS then return end
				if os.clock() - (D.lastRequeue or 0) < QUEUE_STUCK_SECS then return end
				D.lastRequeue = os.clock()
				D.queuedSince = nil
				local mm = matchmaking()
				if not mm then return end
				pcall(function() mm:leaveQueue() end)
				P.queued = false
				task.wait(1)
				local again = queueNow("stuck searching for " .. string.format("%.0f", waited) .. "s")
				P.note = "queue was dead after " .. string.format("%.0f", waited)
					.. "s, left it and re-joined: " .. tostring(again)
				pcall(function()
					if not isfolder("RobloxComm") then makefolder("RobloxComm") end
					if not isfolder("RobloxComm/solo") then makefolder("RobloxComm/solo") end
					local line = os.date("%Y-%m-%d %H:%M:%S") .. "\tqueue stuck\t"
						.. string.format("%.0f", waited) .. "s searching\trejoined=" .. tostring(again) .. "\n"
					if isfile("RobloxComm/solo/selfdebug.log") then
						appendfile("RobloxComm/solo/selfdebug.log", line)
					else writefile("RobloxComm/solo/selfdebug.log", line) end
				end)
				return
			end
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

-- ONE PANEL, NOT A STACK.
--
-- Measured 2026-08-22 15:0x: gethui() answers RobloxGui and held one of each
-- panel, while PlayerGui held two more of each and three XpBars. The old sweep
-- ran once at build time against a host list that can still be incomplete that
-- early - PlayerGui in particular is not always there yet - so a copy created
-- under one host was never seen by the next build.
--
-- So the sweep knows the four places a panel can be, it never removes the live
-- one, and it runs again a few seconds later when everything has appeared.
local function soloSweep(name, keep)
	local hosts = {}
	pcall(function() if gethui then hosts[#hosts + 1] = gethui() end end)
	pcall(function() hosts[#hosts + 1] = game:GetService("CoreGui") end)
	pcall(function() hosts[#hosts + 1] = game:GetService("CoreGui"):FindFirstChild("RobloxGui") end)
	pcall(function() hosts[#hosts + 1] = lp:FindFirstChild("PlayerGui") end)
	local n = 0
	for _, h in ipairs(hosts) do
		if h then
			pcall(function()
				for _, c in ipairs(h:GetChildren()) do
					if c:IsA("ScreenGui") and c.Name == name and c ~= keep then
						c:Destroy()
						n = n + 1
					end
				end
			end)
		end
	end
	return n
end

local function build()
	-- gethui() does not always hand back the same container, so a sweep by name
	-- alone can miss the copy the last generation made and the panels stack.
	-- The handle this file stored last time is the one certain way to find it.
	soloSweep("SoloPlay", nil)
	env.__SOLOPLAY_GUI = nil
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
		if C.quality then applyQuality(true) else restoreQuality() qJob = "" end
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
	-- BACK TO LOBBY, 2026-08-22: "at the solo play add a back lobby button
	-- beucase that was needded".
	--
	-- It goes in the title bar beside ORA rather than as a new row, because the
	-- layout under the bar is his and a button that moves his labels down is a
	-- change he did not ask for.
	--
	-- Manual only. Nothing in this file may call it: on the EggWars side an
	-- automatic back-to-lobby cost 108 to 781 seconds between rounds against 48
	-- to 62 when the server was left to start the next one itself, and he banned
	-- it outright. This is the button he presses, and that is all it is.
	local lobbyBtn = Instance.new("TextButton")
	lobbyBtn.Size = UDim2.new(0, 70, 0, 19) lobbyBtn.Position = UDim2.new(1, -146, 0, 4)
	lobbyBtn.BackgroundColor3 = Color3.fromRGB(201, 142, 74) lobbyBtn.BorderSizePixel = 0
	lobbyBtn.Font = Enum.Font.GothamBold lobbyBtn.TextSize = 10
	lobbyBtn.TextColor3 = Color3.fromRGB(26, 20, 9) lobbyBtn.Text = "LOBBY" lobbyBtn.Parent = bar
	Instance.new("UICorner", lobbyBtn).CornerRadius = UDim.new(0, 6)
	lobbyBtn.MouseButton1Click:Connect(function()
		pcall(function()
			if game.PlaceId == LOBBY_PLACE then P.note = "already in the lobby" paint() return end
			P.note = "going back to the lobby..."
			paint()
			local F = env.__SOLOFARM
			if F then F.on = false if env.__SOLOFARM_SAVE then pcall(env.__SOLOFARM_SAVE) end end
			local ok, err = pcall(function()
				game:GetService("TeleportService"):Teleport(LOBBY_PLACE, lp)
			end)
			P.note = ok and "lobby teleport sent" or ("lobby teleport failed: " .. tostring(err):sub(1, 40))
			paint()
		end)
	end)
	btn.lobby = lobbyBtn

	-- HIDE. Same job as the alt key below, for the times the key is eaten by
	-- something else - and because every other thing in this project is driven
	-- from a button on the panel.
	local hideBtn = Instance.new("TextButton")
	hideBtn.Size = UDim2.new(0, 70, 0, 19) hideBtn.Position = UDim2.new(1, -224, 0, 4)
	hideBtn.BackgroundColor3 = Color3.fromRGB(201, 142, 74) hideBtn.BorderSizePixel = 0
	hideBtn.Font = Enum.Font.GothamBold hideBtn.TextSize = 10
	hideBtn.TextColor3 = Color3.fromRGB(26, 20, 9) hideBtn.Text = "HIDE" hideBtn.Parent = bar
	Instance.new("UICorner", hideBtn).CornerRadius = UDim.new(0, 6)
	hideBtn.MouseButton1Click:Connect(function()
		if env.__SOLO_HIDE_TOGGLE then pcall(env.__SOLO_HIDE_TOGGLE) end
	end)
	btn.hide = hideBtn

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

task.spawn(function()
	for _ = 1, 4 do
		task.wait(2)
		if not alive() then return end
		pcall(soloSweep, "SoloPlay", env.__SOLOPLAY_GUI)
	end
end)
pushToFarm()
if C.quality then applyQuality() end

-- Before anything can queue, including the game's own timers.
do
	local ok, why = lockQueueToSolo()
	P.note = ok and ("queue locked to solo (" .. tostring(why) .. ")")
		or ("no matchmaking controller here yet (" .. tostring(why) .. ")")
end
task.spawn(function()
	while alive() do
		task.wait(3)
		pcall(lockQueueToSolo)
	end
end)

-- ---------------------------------------------------------------- hide all
--
-- His words, 2026-08-22: "using alt was able to hide all gui, add that and make
-- sure while mkaing sciript was able to doing that beucase imrpaont".
--
-- What gets hidden is every GUI that is OURS - the five panels and Vape - and
-- nothing that belongs to the game. Executor GUIs live under gethui(), the
-- game's own live under PlayerGui, so the split is a real boundary and not a
-- list of names to keep up to date. The game's scoreboard stays where it is,
-- which matters: the farm reads the round clock out of it.
--
-- Enabled=false, never Destroy. A hidden panel is still running, still saving,
-- still writing its logs; it is only not drawn.
local hidden = false
local hiddenSet = {}

local function ourGuis()
	local out = {}
	local seen = {}
	local function add(h)
		if not h then return end
		pcall(function()
			for _, c in ipairs(h:GetChildren()) do
				if c:IsA("ScreenGui") and not seen[c] then seen[c] = true out[#out + 1] = c end
			end
		end)
	end
	pcall(function() if gethui then add(gethui()) end end)
	-- CoreGui may also hold our panels when gethui is not available, but it holds
	-- Roblox's own as well, so only the names this project creates are taken.
	local mine = { SoloFarm = true, SoloPlay = true, SoloRec = true, SoloTeam = true, XpBar = true }
	pcall(function()
		for _, c in ipairs(game:GetService("CoreGui"):GetChildren()) do
			if c:IsA("ScreenGui") and mine[c.Name] and not seen[c] then
				seen[c] = true out[#out + 1] = c
			end
		end
	end)
	return out
end

local function hideAll(want)
	hidden = want
	if want then
		hiddenSet = {}
		for _, g in ipairs(ourGuis()) do
			if g.Enabled then
				hiddenSet[#hiddenSet + 1] = g
				pcall(function() g.Enabled = false end)
			end
		end
		P.note = "hidden " .. #hiddenSet .. " gui - alt or HIDE to bring them back"
	else
		local n = 0
		for _, g in ipairs(hiddenSet) do
			if g and g.Parent then pcall(function() g.Enabled = true end) n = n + 1 end
		end
		hiddenSet = {}
		P.note = "shown " .. n .. " gui"
	end
	pcall(paint)
end

env.__SOLO_HIDE_TOGGLE = function() hideAll(not hidden) end
env.__SOLO_HIDDEN = function() return hidden end

pcall(function()
	local UIS = game:GetService("UserInputService")
	UIS.InputBegan:Connect(function(i, processed)
		if processed then return end
		if i.KeyCode == Enum.KeyCode.LeftAlt or i.KeyCode == Enum.KeyCode.RightAlt then
			if not alive() then return end
			hideAll(not hidden)
		end
	end)
end)

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

-- ALIVE IS AN ATTRIBUTE. Humanoid.Health IS NOT.
--
-- His report, 2026-08-22: "at eh solo play should be auto detect am i die?, if
-- i was die then just instead self queue then beucase it now was dead by
-- unknown". These two functions are the whole of that fault.
--
-- Measured 2026-08-21 10:0x, and written into the farm long before this file
-- caught up: Humanoid.Health reads 100 for every player in this game, always -
-- three players whose real health was 68, 42 and 17 all reported 100. The
-- number the game plays with is the Health ATTRIBUTE on the Player, and life or
-- death is the Alive ATTRIBUTE.
--
-- So livingCount counted everybody with a body and never fell to one, and
-- iAmAlive could never return false. He dies, nothing notices, nothing queues.
-- That is "dead by unknown".
local function isUp(p)
	if p:GetAttribute("Alive") == false then return false end
	local hp = p:GetAttribute("Health")
	if type(hp) == "number" and hp <= 0 then return false end
	local ch = p.Character
	if not ch or not ch:FindFirstChild("HumanoidRootPart") then return false end
	return true
end

local function livingCount()
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if isUp(p) then n = n + 1 end
	end
	return n
end

local function iAmAlive()
	return isUp(lp)
end

-- DIED, SO QUEUE, and immediately rather than folded into the two second
-- "round settled" wait further down. Once this body is dead the round is over
-- for us whatever the scoreboard says, and the two to three seconds a queue
-- costs are better spent now than after the win screen.
--
-- Fires once per server. The farm is switched off in the same breath so it
-- stops swinging at people it can no longer reach; AUTO is armed, so it turns
-- itself back on at the next round change.
task.spawn(function()
	local wasUp, firedFor = false, ""
	while alive() do
		task.wait(0.2)
		pcall(function()
			if game.PlaceId ~= MATCH_PLACE then wasUp = false return end
			local job = tostring(game.JobId)
			if iAmAlive() then wasUp = true return end
			if not wasUp or firedFor == job then return end
			firedFor = job
			wasUp = false
			P.note = "I DIED at " .. os.date("%H:%M:%S") .. " - queueing straight away"
			pcall(function()
				local F = env.__SOLOFARM
				if F then F.on = false end
			end)
			pcall(function()
				if not isfolder("RobloxComm") then makefolder("RobloxComm") end
				if not isfolder("RobloxComm/solo") then makefolder("RobloxComm/solo") end
				local TAB, NL = string.char(9), string.char(10)
				local row = os.date("%Y-%m-%d %H:%M:%S") .. TAB .. "died" .. TAB
					.. job:sub(1, 8) .. TAB .. "queued straight away" .. NL
				if isfile("RobloxComm/solo/selfdebug.log") then
					appendfile("RobloxComm/solo/selfdebug.log", row)
				else
					writefile("RobloxComm/solo/selfdebug.log", row)
				end
			end)
			queueNow("i died")
			pcall(paint)
		end)
	end
end)

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
			-- THE ROUND STARTS WHEN THE BODIES HIT THE MAP, NOT WHEN THIS LOOP
			-- NOTICES.
			--
			-- His line, 2026-08-24 21:2x: "the round timer ... it have over 2 sec
			-- delay it was wonrg ... it shouldbe like while the countdown done
			-- count all any player go drop to the ground, that was will be the
			-- round started".
			--
			-- Both seconds were real and neither was the clock being slow. This
			-- loop runs on task.wait(1), so noticing costs up to a second, and it
			-- then waited for sawLive to reach 2, which is another sample. Both
			-- disappear by taking a TIMESTAMP instead of starting a stopwatch:
			-- SOLO_FARM already stamps F.dropAt the first 0.1s tick the body is
			-- below the holding pen, which is exactly the drop he is describing,
			-- and both files share one Luau VM so os.clock() is the same clock.
			-- Noticing late no longer matters when the start time is read, not set.
			if inMatch and P.roundStart == 0 then
				local FF = getgenv and getgenv().__SOLOFARM
				local drop = FF and tonumber(FF.dropAt) or 0
				if drop > 0 then
					P.roundStart = drop
					P.rounds = P.rounds + 1
					P.startedBy = "drop"
				elseif P.sawLive >= 2 then
					-- Fallback only: the farm is not up, so there is no drop stamp
					-- to read and this is the best this file can do alone.
					P.roundStart = os.clock()
					P.rounds = P.rounds + 1
					P.startedBy = "sawLive"
				end
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
			if inFirstGrace() then
				P.note = string.format("just injected, holding the queue %.0fs so you can touch it",
					FIRST_GRACE - (os.clock() - env.__SOLOPLAY_INJECTED_AT))
			elseif C.autoQueue and P.canQueue and not P.queued and over and settled then
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
