-- EggWars panels: coin collector, auto buy, player tracker with void detection.
-- Standalone, paste-and-run. Safe to run again: it kills the previous copy first.
--
-- Collecting works by moving the PLAYER onto each pickup. Pickups are server-owned,
-- so writing their CFrame would only move them on your screen.
-- Buying goes through the game's own GameShopController, confirmed by watching the
-- currency actually drop, so the log never claims a purchase the server refused.
-- Void detection is pure raycasting off other players' positions - no hooks, no remotes.

-- DUPLICATE LOAD GUARD, and it has to be the very first thing in the file.
--
-- Two copies loading seconds apart inside the same server is never a deliberate re-run: it is
-- the autoexec and the queued teleport stub both winning the race. The old guard lived inside
-- the stub only, so whichever copy the stub did not start walked straight past it - seven
-- rounds logged DOUBLE LOAD on 2026-08-03, one of them four copies at once.
--
-- It cannot be moved further down. Three lines below this the kill hook fires and the
-- generation token is overwritten, and either one of those has already killed the healthy
-- copy by the time a later check could notice. Standing down has to happen before both.
--
-- Keyed on JobId as well as time so it can never misfire after a teleport: a new round is a
-- new server, so the stored id no longer matches and the new copy is free to load. A real
-- re-run more than 20 seconds later is still allowed, which is how edits get picked up
-- between rounds.
do (function()
	local job = tostring(game.JobId)
	local at = getgenv().__EWCOIN_LOAD_AT
	if at and getgenv().__EWCOIN_LOAD_JOB == job and os.clock() - at < 20 then
		getgenv().__EWCOIN_LOADS = (getgenv().__EWCOIN_LOADS or 0) + 1
		warn(string.format(
			"[panels] duplicate load ignored - another copy loaded %.1fs ago in this same server (%d so far)",
			os.clock() - at,
			getgenv().__EWCOIN_LOADS
		))
		return
	end
	getgenv().__EWCOIN_LOAD_AT = os.clock()
	getgenv().__EWCOIN_LOAD_JOB = job
end)() end

if getgenv().__EWCOIN_KILL then
	pcall(getgenv().__EWCOIN_KILL)
end

-- A generation token on top of the kill function. If an older copy is still running and
-- its kill function got overwritten in getgenv - which happens when the teleport bootstrap
-- reloads on top of a manual load - calling kill is not enough and its loops keep driving
-- the character. Every loop checks this token, so the newest copy always wins outright.
local MY_GEN = tick()
getgenv().__EWCOIN_GEN = MY_GEN

-- One boot per DataModel, and this is the flag that enforces it.
--
-- Every running copy arms queue_on_teleport, and the autoexec adds one more whenever Roblox
-- swaps process on a teleport. Nothing ever removed one, so the number of copies loading each
-- round grew by exactly one per round: 1 a minute at 07:48, 60 by 08:20, and 600 a minute
-- after four hours - six hundred compiles of a 106 KB script per minute, each building eleven
-- panels. Two of the three clients died of it. The generation token below still decides which
-- copy DRIVES, but by then the damage is the loading itself, so it has to be stopped earlier.
-- getgenv is wiped whenever the DataModel changes, so this resets itself every round.
getgenv().__EWCOIN_BOOT_CLAIMED = true

-- Self check. getgenv is wiped on every DataModel change, so this counts how many copies of
-- this file loaded in THIS round. The answer must always be 1. Two means the boot claim
-- failed and the copies are breeding again - the exact failure that grew to 600 loads a
-- minute and killed two clients while every panel still looked perfectly healthy. It cost
-- four hours to find once; it should announce itself in four seconds next time.
getgenv().__EWCOIN_LOADS = (getgenv().__EWCOIN_LOADS or 0) + 1

-- The on/off switch has to live on disk, not in getgenv: a round-end teleport restarts
-- the Luau VM and wipes getgenv, but the queued copy still has to know you unloaded.
--
-- One flag per account, not one for the machine. All four clients share Real's single
-- workspace folder, so this used to resolve to the identical string on every one of them:
-- pressing OFF on one bot wrote "0" into the file the other three read, and the farm came
-- off all four on their next reload. The UserId is resolved here, at load time, so the
-- queued stub below never has to find a LocalPlayer of its own to know whose flag it is -
-- the finished path is already baked into the string it is handed.
local FLAG = "RobloxComm/ew_panels_" .. (function()
	local ok, uid = pcall(function()
		return game:GetService("Players").LocalPlayer.UserId
	end)
	if ok and type(uid) == "number" and uid > 0 then
		return tostring(uid)
	end
	-- The fallback used to be the literal word "shared", and that word undid the whole line
	-- above it: with no LocalPlayer all four clients resolve to the same string again, one OFF
	-- press writes 0 into the file the other three read, and the farm comes off all four. That
	-- is the exact bug the UserId is here to kill, sitting in the one path nobody ever tests.
	-- MY_GEN is this VM's own tick() from thirty lines up, so no other client can produce this
	-- name. It does not survive a teleport, and that is correct: a client that could not name
	-- its own account has no switch worth keeping. The STOP FARM panel prints this whole path,
	-- so the broken client is the one saying it is broken.
	return "noplayer-" .. tostring(MY_GEN)
end)() .. ".txt"
local SELF = "FARM_SKYWARS_ABCD.lua"

-- pcall's verdict is kept now instead of thrown away. A switch whose write failed reads as ON
-- to everything else on the machine while this client's own OFF press can never take, and
-- until now that failed in complete silence. The STOP FARM panel prints it.
getgenv().__EWCOIN_FLAG_WRITE = pcall(function()
	if not isfolder("RobloxComm") then
		makefolder("RobloxComm")
	end
	writefile(FLAG, "1")
end)

-- Re-arm for the next teleport HERE, at the top, before a single line of the rest of this
-- file has run. It used to be the very last statement in the script, and that is why a bot
-- could lose the panels for the whole session while Vape carried on: anything that stopped
-- this file reaching its final line - one error in three thousand lines, or simply the
-- lobby sending you into the next match before a 90 KB script had finished building sixty
-- odd buttons on a window running at four frames a second - meant queue_on_teleport was
-- never called, and nothing was queued, and it never came back on its own. Armed first, the
-- chain survives every one of those. The stub re-reads the file from disk, so edits made
-- between rounds are picked up for free, and the copy it loads arms the round after that.
-- The pcall's verdict is kept, exactly like __EWCOIN_FLAG_WRITE twenty lines up. string.format
-- throws on a bad specifier and this arm sat inside a bare pcall, so a stub that was never queued
-- looked identical to one that was: no line on disk, no line on the panel, nothing. The STOP FARM
-- panel prints this now.
getgenv().__EWCOIN_ARMED = pcall(function()
	queue_on_teleport(string.format(
		[[
task.spawn(function()
    local flag, self, stopall = %q, %q, %q
    local t0 = os.clock()
    repeat task.wait(0.5) until game:IsLoaded() or os.clock() - t0 > 40
    local w = os.clock()
    while not getgenv().__EWCOIN_BOOT_CLAIMED and os.clock() - w < 6 do task.wait(0.1) end
    if getgenv().__EWCOIN_BOOT_CLAIMED then return end
    local function note(msg)
        pcall(function()
            if not isfolder("RobloxComm") then makefolder("RobloxComm") end
            appendfile("RobloxComm/autoexec_status.txt", os.date("%%Y-%%m-%%d %%H:%%M:%%S")
                .. "  [panels] queued reload " .. msg .. string.char(10))
        end)
        warn("[panels] queued reload " .. msg)
    end
    if not game:GetService("Players").LocalPlayer then
        local t1 = os.clock()
        repeat task.wait(0.2) until game:GetService("Players").LocalPlayer or os.clock() - t1 > 20
    end
    if not game:GetService("Players").LocalPlayer then
        note("FAILED: still no LocalPlayer 20s in - the farm is not loaded blind, it needs the account to name its own switch")
        return
    end
    local okS, rawS = pcall(function() if isfile(stopall) then return readfile(stopall) end end)
    if okS and type(rawS) == "string" and rawS:match("^%%s*STOP%%s*$") then
        note("STOP ALL is set - " .. stopall .. " says STOP, nothing loaded on this account")
        return
    end
    local okF, rawF = pcall(function() if isfile(flag) then return readfile(flag) end end)
    if not okF or type(rawF) ~= "string" or not rawF:match("^%%s*1%%s*$") then return end
    if not isfile(self) then note("FAILED: " .. self .. " is not in the workspace folder") return end
    local chunk, cerr = loadstring(readfile(self))
    if not chunk then note("FAILED to compile: " .. tostring(cerr)) return end
    if getgenv().__EWCOIN_BOOT_CLAIMED then return end
    getgenv().__EWCOIN_BOOT_CLAIMED = true
    local ok, err = pcall(chunk)
    if not ok then
        getgenv().__EWCOIN_BOOT_CLAIMED = nil
        note("ERROR while running: " .. tostring(err))
    end
end)
]],
		FLAG,
		SELF,
		"RobloxComm/ew_stop_all.txt"
	))
end)

-- Luau allows a function at most 200 local registers, and the main chunk of this file IS a
-- function. At 205 top level locals it stopped compiling outright - loadstring returned nil
-- and the only symptom was the autoexec saying "attempt to call a nil value". Constants that
-- are read in only a few places live on this one table instead of taking a register each,
-- which buys the headroom back. Anything added later should go here too, not become a new
-- top level local.
local K = {}

-- Published deliberately so that inspecting this script from outside is a table lookup and
-- never a heap scan. Reading the timeline with filtergc worked while the client was fresh
-- and then hung one that had been running seven hours - Roblox terminated it with
-- "Terminated due it was hanging past timeout". A debug probe must never be able to do that.
getgenv().__EWCOIN_K = K

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lp = Players.LocalPlayer

local alive = true
local conns = {}
local function bind(signal, fn)
	local c = signal:Connect(fn)
	table.insert(conns, c)
	return c
end

-- Every loop below catches its own errors and writes them onto a panel label. That alone is
-- not enough and has already cost this project two sessions: several loops write to the same
-- label many times a second, so a real error flashes for one frame and is gone, and a loop
-- that is failing every single frame looks exactly like a loop that is idle. This puts a copy
-- in the console, where nothing overwrites it, and rate limits per message so a failure that
-- repeats sixty times a second does not bury everything else.
K.loudSeen = {}
K.loudLog = {}
-- Flamework must be left alone until the game has finished its own preloading. Resolving a
-- dependency early makes Flamework warn "Attempting to load dependency during preloading -
-- prone to race conditions", and it is not an idle warning: it instantiates controllers out
-- of order and can leave the game half built. Doing it across every id in Reflect.idToObj -
-- which an earlier version of the FREE MOUSE code did - force-created every controller in the
-- game during startup and left the screen controller with zero screens, so the lobby had no
-- UI at all: no menus, no party invites, nothing. Nothing here may resolve before this is true.
K.fwReady = false
task.spawn(function()
	pcall(setthreadidentity, 8)
	local t0 = os.clock()
	repeat
		task.wait(0.5)
	until game:IsLoaded() or os.clock() - t0 > 30
	task.wait(8)
	K.fwReady = true
end)

local function loud(key, msg)
	local now = os.clock()
	if K.loudSeen[key] and now - K.loudSeen[key] < 10 then
		return
	end
	K.loudSeen[key] = now
	warn("[panels] " .. key .. ": " .. tostring(msg))
	-- Keep the last few for the round log. Reading a round file should tell you whether that
	-- round went wrong without also having to still have the console open.
	table.insert(K.loudLog, os.date("%H:%M:%S") .. "  " .. key .. ": " .. tostring(msg))
	if #K.loudLog > 12 then
		table.remove(K.loudLog, 1)
	end
end

if getgenv().__EWCOIN_LOADS > 1 then
	loud("DOUBLE LOAD", getgenv().__EWCOIN_LOADS .. " copies loaded this round - the boot claim is not holding")
end

local TYPES = {
	{ key = "BronzeCoin", label = "BRONZE", color = Color3.fromRGB(205, 127, 50) },
	{ key = "IronCoin", label = "IRON", color = Color3.fromRGB(198, 202, 212) },
	{ key = "GoldCoin", label = "GOLD", color = Color3.fromRGB(255, 205, 60) },
	{ key = "Shard", label = "SHARD", color = Color3.fromRGB(190, 110, 255) },
}

K.TEAM_SHORT = { Red = "Rd", Yellow = "Yl", Lime = "Lm", Cyan = "Cy" }
K.TEAM_COLOR = {
	Red = Color3.fromRGB(255, 100, 100),
	Yellow = Color3.fromRGB(255, 225, 110),
	Lime = Color3.fromRGB(130, 235, 130),
	Cyan = Color3.fromRGB(120, 210, 255),
}

K.DWELLS = { 0, 0.02, 0.04, 0.06, 0.08, 0.12, 0.2 }
K.TEAM_TIER_PRICE = { 5, 10, 15 }
K.ADRENALINE_INDEX = 10
K.ADRENALINE_PRICE = 8
K.VAMPYRISM_INDEX = 1
K.TRIUMPH_INDEX = 0
K.VAMPYRISM_STATE_KEY = "Lifesteal"

-- Void thresholds. K.GROUND_MISS is how far down we look before calling it empty air.
K.GROUND_MISS = 25
K.EDGE_PROBE = 5
K.FALL_SPEED = 30

local cfg = {
	enabled = true,
	-- Iron is the one that matters, bronze comes along, gold is not worth the trip.
	--
	-- His call, 2026-08-16: "make sure it was not get gold coin, as normally having 16 gold
	-- then ok, it need to main was get iron coin to upgrade the sword, but make sure it will
	-- get those bronze coin also". Gold is already sitting at 16 without trying, so every
	-- gold trip is a detour that buys nothing.
	types = { BronzeCoin = true, IronCoin = true, GoldCoin = false, Shard = true },
	dwellIndex = 1,
	radius = 400,
	perPass = 25,
	returnHome = true,

	autoBuy = true,
	buySword = true,
	buyArmour = false,
	buyVamp = true,
	buyTriumph = true,
	-- Which team upgrade is worth more depends on how many people are still alive, and the
	-- crossover is the owner's call, not a guess: with a full server every kill is followed
	-- by another one, so Triumph (heal on kill) pays constantly. Down to the last few, kills
	-- stop coming and only damage dealt keeps flowing, so Vampyrism (lifesteal) pays instead.
	vampWhenAliveAtMost = 4,
	buyAdrenaline = true,
	adrenAutoUse = true,
	adrenHold = 0.9,
	adrenAtHealth = 50,
	adrenKeep = 2,

	trackEnemiesOnly = true,

	avFloor = true,
	avCatch = true,
	avFollow = false,
	avY = -70,
	avSize = 4000,

	tpOn = false,
	-- 0 means standing INSIDE the target, which is what this was until 2026-08-03 and what
	-- the panel label calls "range 0 (inside him)". The code below has always aimed for the
	-- back arc, but at range 0 the back arc is his own hitbox: the bot stood in the middle of
	-- everyone swinging. 46 of 264 deaths came in the first three seconds and 38 of those took
	-- a full 100 damage. 3.5 keeps it inside the killaura's 14 stud reach with the target's
	-- own body between the bot and whoever else is hitting him.
	-- Closer, because 3.5 was costing him 2-4 seconds a kill.
	--
	-- His report, 2026-08-14 21:5x: they was at the game that it was slow 2-4 sec ... need to
	-- fix the distance to make it more shorter.
	--
	-- The destination is "tpRange studs directly behind the target", written every frame for
	-- tpFrames frames. Behind is deliberate - it is the arc he cannot swing into - but 3.5
	-- studs plus a lead term on a moving target puts some of those frames at the edge of the
	-- sword's own reach, and a frame that lands out of reach is a swing that does nothing.
	-- Half the distance, same arc, and every frame is inside reach.
	--
	-- Not taken to 0: at range 0 the bot stands inside the model, which throws away the
	-- back-arc protection that is the whole reason it stands behind rather than orbiting.
	-- Five, not two. His call, 2026-08-16: "it should behind the player more studs because
	-- it was still too close to the player, the player hitbox will kill the bot".
	--
	-- At 2.0 the bot stands inside the swing of whatever it is hitting, so a player who
	-- turns round kills it for free. Five keeps it behind the shoulder and still inside its
	-- own reach. Raise it further from the panel if a weapon still lands.
	-- Back to 2. He worked out what the kick actually keys on, 2026-08-16: it is not how
	-- close the bot stands, it is how LONG it stays behind the same player. Six seconds of
	-- sitting in someone's back arc is the pattern, so distance stopped mattering and the
	-- fix moved to tpMaxSecs below. Two studs is inside its own reach, which is what makes
	-- three seconds enough to finish.
	tpRange = 5.0,
	-- Hard ceiling on one target. Under his measured kick line of 6s with room to spare.
	tpMaxSecs = 3.0,
	-- Stand in front of the target instead of behind it.
	tpFront = true,
	-- How close to a flagged flyer. One stud, his number.
	tpFlyRange = 1.0,
	-- Seconds a target is left alone after we break off, so the pass does not walk straight
	-- back onto him and rebuild the same six seconds in two-second slices.
	tpCoolSecs = 8.0,
	-- No fighting before this sword. His rule: "dont kill any player until u get gold sword".
	-- Below it the bot cannot finish inside three seconds, and a fight it cannot finish is
	-- exactly the one that runs long enough to be seen.
	-- OFF for normal farming. This gate is a war rule, not a farm rule.
	--
	-- 2026-08-16 05:3x he asked why the three bots were not attacking. They were at sword
	-- tier 2, 1 and 1 against a gate that demanded 3, so the target loop broke on its first
	-- line every pass and nobody ever swung - with ten enemies on the server.
	--
	-- The rule he actually gave me was about the two hackers: do not walk into THEM without
	-- a proper sword. Ordinary players are not that fight, and holding fire against them is
	-- how the farm stops earning. So the flag is off by default and the war ladder turns it
	-- on when a blacklisted account is in the server.
	tpNeedGoldSword = false,
	-- Set by the leader's KILL ALL, cleared by STOP KILL ALL. Never saved to disk.
	killOverride = false,
	-- Never alone. At least this many bots on the same man before anyone swings.
	tpMinTogether = 2,
	-- Two frames a target, his number. "the speed must be super fast teleport, dont be slow,
	-- we must super fast teleport to 2 frame then, that was the perfect i think."
	--
	-- Four was already about 0.07s a visit; two halves it, so the sweep gets round the whole
	-- target list twice as often and no single man is stood behind for as long. That second
	-- part matters as much as the speed - the kick he measured keys on total time behind one
	-- player, and this spreads the same work thinner.
	tpFrames = 2,
	tpGrabCoins = true,
	tpGrabRadius = 45,

	eggOn = true,
	-- Studs ABOVE the top of the shell. Was eggDown, which went below the shell and
	-- put the character inside the platform - see the note at the teleport itself.
	-- Minus ten, measured by him on 2026-08-16, not chosen by me.
	--
	-- He tested -7 first and it landed, then went further and settled on -10 as the spot
	-- that actually breaks the egg: ten studs BELOW the bottom face of the shell, hitting
	-- upwards into it. Positive numbers still mean above the shell; this default is negative
	-- on purpose and the panel reads "under 10 studs" for it.
	eggUp = -8,
	eggFrames = 1,
	eggThenTp = true,

	-- Backstop only. The settle below releases the moment the character reports a floor, so
	-- this is what happens when the floor never arrives, and it is counted from the first
	-- frame of the live round rather than from the spawn.
	settleSecs = 2,

	-- Grabbing coins in the middle of the egg sweep pulls the character off the egg. Across
	-- the 184 recorded rounds that ended in 13s or less the median coins collected was 1 and
	-- the median purchases was 0, with 117 of those 184 buying nothing at all, so the egg
	-- phase was paying for a detour that bought nothing. EGG-PHASE COINS on the STOP panel
	-- turns it back on.
	eggGrabCoins = false,

	esp = false,

	ramOn = true,
	ram3d = false,
	vapeCycle = true,
	farmPaused = false,
	teamOn = true,
	teamFocusThreat = true,
}

-- SETTINGS THAT SURVIVE A RELAUNCH. Nothing in this file ever wrote cfg down, so every
-- relaunch put back the defaults in the source and threw away whatever he had set. His
-- words, 2026-08-14: if not save then next time i doing the farming it will not same as
-- what i edit.
--
-- Two guards, and each exists because of a specific way this could go wrong.
--
-- One: never write while the farm is paused. setFarmPaused zeroes enabled, autoBuy, tpOn
-- and eggOn and keeps the originals in a plain local that dies on reload. Saving during a
-- pause would write those four zeroes as if they were his settings, and after the next
-- relaunch the panel would read FARM RUNNING with all four switches off and nothing left
-- that could put them back.
--
-- Two: only write a value that has held still for two samples. A switch flipped by an
-- error handler and flipped back never reaches disk; only a state actually sitting there
-- does.
local CFG_FILE = nil
-- tpOn is never written to disk, and that is the fix for the worst bug of the night.
--
-- 2026-08-16 00:1x he found bots attacking players and eggs with his own hands nowhere near
-- KILL ALL. The chain: pressing KILL ALL sets cfg.tpOn = true, the config saver wrote that
-- true into cfg_<name>.json, and from then on every relaunch came back already in battle
-- mode. STOP KILL ALL cleared the live flag but the file kept the true, so the next reload
-- undid it - a press from twenty minutes ago kept firing.
--
-- tpOn is not a preference of his, it is the leader's battle switch. The leader owns it, so
-- it does not belong in a saved profile at all. Skipping it here means a fresh load always
-- starts with players unhunted, and only killall.txt saying ON can turn it on.
-- eggOn joins the never-saved list, for the same reason tpOn did.
--
-- Measured 2026-08-16 03:23: all three cfg_*.json held "eggOn":false, written two to four
-- seconds after killall.txt flipped to OFF. The kill switch turns the egg pass off while
-- hunting, the saver saw that false sit still for two samples, and wrote it - so a battle
-- state became a permanent setting and no bot would ever break an egg again. A farm that
-- cannot break an egg cannot win a round, and it looks completely healthy while doing it.
local CFG_SKIP = { farmPaused = true, tpOn = true, killOverride = true, eggOn = true }

local function cfgPath()
	if not CFG_FILE then
		local ok, name = pcall(function()
			return game:GetService("Players").LocalPlayer.Name
		end)
		CFG_FILE = "RobloxComm/cfg_" .. ((ok and name) or "unknown") .. ".json"
	end
	return CFG_FILE
end

local function cfgSnapshot()
	local out = {}
	for k, v in pairs(cfg) do
		if not CFG_SKIP[k] then
			local t = type(v)
			if t == "boolean" or t == "number" or t == "string" then
				out[k] = v
			elseif t == "table" then
				local sub = {}
				for k2, v2 in pairs(v) do
					local t2 = type(v2)
					if t2 == "boolean" or t2 == "number" or t2 == "string" then
						sub[k2] = v2
					end
				end
				out[k] = sub
			end
		end
	end
	return out
end

local function cfgEncode()
	return pcall(function()
		return game:GetService("HttpService"):JSONEncode(cfgSnapshot())
	end)
end

local function loadCfg()
	local ok, raw = pcall(readfile, cfgPath())
	if not ok or type(raw) ~= "string" or raw == "" then
		return false
	end
	local okD, data = pcall(function()
		return game:GetService("HttpService"):JSONDecode(raw)
	end)
	if not okD or type(data) ~= "table" then
		return false
	end
	for k, v in pairs(data) do
		if not CFG_SKIP[k] and cfg[k] ~= nil then
			if type(v) == "table" and type(cfg[k]) == "table" then
				for k2, v2 in pairs(v) do
					if cfg[k][k2] ~= nil and type(v2) == type(cfg[k][k2]) then
						cfg[k][k2] = v2
					end
				end
			elseif type(v) == type(cfg[k]) then
				cfg[k] = v
			end
		end
	end
	cfg.farmPaused = false
	return true
end

-- The saver was the one loop in this file with no way out: no alive check, no generation
-- token, so a reload left the old copy running and a kill left it writing. Its own comment
-- says the two guards exist to stop "farm off" reaching the disk - but the kill zeroes
-- cfg.enabled and cfg.autoBuy WITHOUT setting cfg.farmPaused, which is the only flag this
-- loop reads, so the orphan happily saved the off state and the next load restored it.
-- Found by the audit, 2026-08-14.
getgenv().__CFG_GEN = (getgenv().__CFG_GEN or 0) + 1
local MY_CFG_GEN = getgenv().__CFG_GEN

task.spawn(function()
	pcall(loadCfg)
	local written, seen = nil, nil
	while alive and getgenv().__CFG_GEN == MY_CFG_GEN do
		task.wait(2)
		if not cfg.farmPaused then
			local okE, enc = cfgEncode()
			if okE and type(enc) == "string" then
				if enc == seen and enc ~= written then
					if pcall(writefile, cfgPath(), enc) then
						written = enc
					end
				end
				seen = enc
			end
		end
	end
end)

-- A player below this Y has already lost the round to the void. He is not a target, not
-- a threat and not worth a teleport - the tracker calls him a VOID player and everything
-- else skips him. Below -100 he is simply gone. The same line is what pulls you back.
K.VOID_Y = -69
K.VOID_GONE = -100

-- The lowest Y this file is allowed to put the character at, ever. Six studs of daylight
-- above K.VOID_Y so a hop that lands here is still recoverable, and low enough that going
-- under an egg (they sit around -50) is untouched.
K.SAFE_Y = -63

-- Roughly a killaura's reach: anyone inside this of a target gets hit by the same swings.
K.CLUSTER_R = 14

-- ...but the reach works both ways. A pile of four hits back four times as fast as one does,
-- and 100 health against four starting swords is gone inside a second - that is the whole of
-- "died at 0.8s with full health" in the round logs. Piles up to this size are still worth
-- picking; anything bigger is a place to die, and gets sorted to the back instead of to the
-- front. This is the single change that stops the round-start deaths.
K.CLUSTER_MAX = 3

-- How far ahead of a moving target to aim, in seconds, and the hard cap in studs. 0.06 is
-- about one frame at 60 fps plus a little for the round trip; more than that and the bot
-- stands in front of someone walking normally instead of behind him.
K.TP_LEAD = 0.06
K.TP_LEAD_MAX = 6
-- Where the ground check for a teleport destination starts, and the spots it is
-- allowed to fall back to. Probing from slightly above the spot keeps the ray from
-- starting inside the very block we are asking about.
K.TP_PROBE_UP = Vector3.new(0, 3, 0)
K.TP_TURNS = { 0, 45, -45, 90, -90, 135, -135, 180 }
K.TP_SHRINK = { 1, 0.6, 0.3 }
K.tpBlocked = 0
K.tpBlockedPass = 0

-- Flight detection thresholds. Deliberately about BEHAVIOUR and not about any one script:
-- there are dozens of fly scripts on Roblox and the next one will not look like the last.
-- Reading a BodyVelocity off his torso is the fastest check but it is also the narrowest,
-- true only for the scripts that happen to use BodyMovers, so it is one signal of four and
-- never the only one.
--
-- A real jump settles every argument about the numbers here. Roblox's default jump leaves
-- the ground for well under a second and its vertical speed is negative from the apex on,
-- about a third of a second in. Nobody rises for six tenths of a second under their own
-- legs, and nobody crosses ground at 32 studs a second - sprint in this game is nowhere
-- near it. Someone bridging on placed blocks always has a block under his feet, so his
-- airborne timer never starts at all.
K.FLY_AIR_T = 2.5
K.FLY_RISE_Y = 8
K.FLY_SPEED = 32
K.FLY_MIN_AIR = 0.6

-- Which threat gets rushed first. A HACKER teleports, breaks eggs and swings - he ends the
-- round for us if nobody stops him. A FLYING USER is the opposite: 9999 speed and hiding, no
-- damage to anybody, and chasing him is how dfa5321d took 131 seconds and 71886fc8 took 68,
-- the only two rounds all day over a minute. Deal with the one that can hurt the round first.
K.THREAT_RANK = {
	["HACKER"] = 1,
	["HACKER FAKE DEAD"] = 2,
	["FLYING USER"] = 3,
}

-- Short names for the panel. The team status label is 232 pixels wide with wrapping off, which
-- at TextSize 12 in the Code font is about 32 characters - so "RUSH 1 threat (FLYING USER)
-- 6 fair 1 parked" is cut off in the middle and the part that gets cut is the part worth
-- reading.
K.THREAT_TAG = {
	["HACKER"] = "HAK",
	["HACKER FAKE DEAD"] = "HFD",
	["FLYING USER"] = "FLY",
}

-- How long the team may stay on one flagged player before he goes to the BACK of the sweep for
-- the rest of the round.
--
-- Not a guess: across the 683 recorded rounds a teleport frame aimed at a flagged player strips
-- 9.0 health per second and shows any health loss at all in 20 percent of its samples, while an
-- unflagged one strips 23.1 per second and lands in 46. The rank above has only ever been
-- ordering flyers against flyers - all 904 flags in the log were FLYING USER (784) or HACKER
-- FAKE DEAD (120) and HACKER fired zero times - which is the exact fight the comment above it
-- says not to take.
--
-- Rank 1 is exempt. HACKER is the one that ends the round if nobody stops him, and a budget
-- that quietly stops the team fighting him would be removing the only fight worth having. Three
-- days of zero HACKER sightings is not a guarantee that there will not be one tonight.
K.THREAT_BUDGET = 4

-- HITTING THINGS, measured rather than hoped for. 2026-08-20.
--
-- Vape's Breaker was enabled with a break range of 40 and it fired NOTHING. Eight seconds
-- parked under an egg with remote-spy running caught one spectate call and two tool
-- equips and not one hit, and the egg sat at 82 hp while six minutes of a round went by.
--
-- The game's own path, read out of PlayerScripts.TS.controllers.melee-controller in
-- strikeMobile: it collects models in a box in front of the character, throws away
-- anything further than MeleeConstants.MAXIMUM_HIT_RANGE_BLOCKS * 2.3 - 4.5 * 2.3, so
-- 10.35 studs - checks line of sight, and then fires one of two events. A player hit
-- goes out with the Player; anything else goes out with the MODEL. Those two ids are
-- what actually takes health off anything in this game.
--
-- Fired straight at the egg on the live client, 18 fires over five seconds took it from
-- 82 hp to 53. That is the difference between winning a round and standing next to an
-- egg until the round ends.
K.HIT_ENTITY = "f32c9bc1-cb4b-4616-96ac-bddaefd35e92"
K.HIT_PLAYER = "93b2718b-2b2a-4859-b36e-fd4614c7f0c9"

-- How close the bot has to be to the thing it is hitting. The game refuses at 10.35, so
-- this sits under it with room for the half height of whatever is being hit.
K.EGG_REACH = 8
K.hits = 0

K.hitRemote = function(id)
	K.__remotes = K.__remotes or {}
	local r = K.__remotes[id]
	if r and r.Parent then
		return r
	end
	r = nil
	pcall(function()
		local RSx = game:GetService("ReplicatedStorage")
		-- The folder was Kw8 on place version 296. Named lookup first because it is
		-- cheap, then a recursive one, because that name is generated and will move.
		local folder = RSx:FindFirstChild("Kw8")
		r = folder and folder:FindFirstChild(id) or RSx:FindFirstChild(id, true)
	end)
	K.__remotes[id] = r
	return r
end

-- One hit per target per K.HIT_GAP seconds. The measured rate that took an egg from 82 to
-- 53 was 18 fires in five seconds, so 0.12 leaves room above what is known to work while
-- stopping the frame loop from turning into a flood - the game's own client fires this
-- once per swing, and a stream forty times faster is the shape a rate limiter is for.
K.HIT_GAP = 0.12

K.hitThing = function(id, target)
	if not target or not target.Parent then
		return false
	end
	K.__hitAt = K.__hitAt or {}
	local now = os.clock()
	local last = K.__hitAt[target]
	if last and now - last < K.HIT_GAP then
		return false
	end
	local r = K.hitRemote(id)
	if not r then
		return false
	end
	K.__hitAt[target] = now
	K.hits = K.hits + 1
	return (pcall(function()
		r:FireServer(target)
	end))
end

K.hitEgg = function(model)
	return K.hitThing(K.HIT_ENTITY, model)
end

-- THE EGG HAMMER. eggPass walks the eggs one frame each, so one egg gets one hit per
-- pass, and at the 30 fps four clients actually run at that is a slow way to spend a
-- round: three enemy eggs took about half a minute. This is the same hit on its own
-- beat, aimed at every live enemy egg rather than only the one being stood under.
-- K.HIT_GAP still bounds it, so this is three calls per gap and not a flood.
--
-- It costs nothing if the server turns out to want the body next to the shell: those
-- calls are simply refused and the ones eggPass fires from underneath still land.
K.eggHammer = function(eggsFolder, myTeam)
	if not eggsFolder or not myTeam then
		return 0
	end
	local n = 0
	for _, e in ipairs(eggsFolder:GetChildren()) do
		if tostring(e:GetAttribute("TeamId")) ~= tostring(myTeam)
			and (e:GetAttribute("Health") or 0) > 0 then
			if K.hitEgg(e) then
				n = n + 1
			end
		end
	end
	return n
end

K.hitPlayer = function(p)
	return K.hitThing(K.HIT_PLAYER, p)
end

-- Who is running the leader on this client. The three bots put every frame into the
-- shells until the shells are gone; D fights from the first second. Both halves are his
-- order of 2026-08-20: "just make sure it was done kill all egg frist, dotn telepting to
-- any player" and "the fucking leard bot will go killing others player as the same time".
K.iAmLeaderClient = function()
	if getgenv().__IS_LEADER == true then
		return true
	end
	local id = K.leaderAccountId()
	return id ~= nil and lp.UserId == id
end

-- Keep the body upright. CFrame.new(dest, target) with the target straight overhead
-- points the look vector at the sky and Roblox lays the whole character flat to obey it -
-- which is exactly what he saw: "it was fucking the human obdy turn into flat that
-- middle". Flattening the look to the horizontal plane keeps it standing while it still
-- stands underneath.
K.faceFlat = function(r, dest, lookAt)
	local flat = Vector3.new(lookAt.X - dest.X, 0, lookAt.Z - dest.Z)
	if flat.Magnitude < 0.05 then
		return CFrame.new(dest) * (r.CFrame - r.CFrame.Position)
	end
	return CFrame.new(dest, dest + flat)
end

-- Teleporting that costs no damage is the shape that draws the kick. His words,
-- 2026-08-20: "the main was telprting not costing any damage bro ... it was not cositng
-- any dmaage then telepting that was not allow". A visit that takes nothing off a man
-- puts him down for this long and the bot goes somewhere useful instead of bouncing.
K.NODMG_SECS = 6
K.noDmg = {}

-- THE BOARD. Every client writes one line about itself and reads the other three, so a bot
-- can answer "where is the leader, where are the others, has anyone been thrown out" by
-- itself instead of waiting to be told. His order, 2026-08-20: "those bot have to read log
-- also, it need to chekcing now the bto and the leard or others bot was at where ... make
-- sure it was while detect kciked and bakc lobby the all bot at the frist time can able to
-- see that frist".
--
-- One file per writer, never one shared file. Four clients writing the same path is how a
-- half written line gets read as the truth.
K.WHERE_DIR = "RobloxComm/where"

K.whereWrite = function(kickedAt)
	pcall(function()
		if not isfolder(K.WHERE_DIR) then
			makefolder(K.WHERE_DIR)
		end
		if kickedAt then
			K.__kickedAt = kickedAt
		end
		local ch = lp.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		writefile(K.WHERE_DIR .. "/" .. lp.Name .. ".txt", string.format(
			"%d|%s|%d|%s|%s|%s|%d\n",
			os.time(), lp.Name, game.PlaceId, tostring(game.JobId),
			tostring(hum ~= nil and hum.Health > 0), tostring(K.iAmLeaderClient()),
			K.__kickedAt or 0))
	end)
end

-- Four known names, not a directory scan, and cached for two seconds.
--
-- The first version called listfiles() on the folder every read, on four clients at once,
-- while all four were also writing into it twice a second. Measured 2026-08-20 05:3x with
-- that running: three of the four clients sat at 0 to 1 fps with worst frames of 5.5
-- SECONDS, and the executor's file bridge is the only thing in this file that can stall a
-- frame that long. The board is worth keeping; scanning a directory to find four filenames
-- I already know is not.
K.whereAll = function()
	local now = os.clock()
	if K.__boardAt and (now - K.__boardAt) < 2 and K.__board then
		return K.__board
	end
	K.__boardAt = now
	local out = {}
	local names = {}
	for _, n in pairs(K.BOTS) do
		names[#names + 1] = n
	end
	names[#names + 1] = K.leaderName()
	pcall(function()
		for _, nm in ipairs(names) do
			local path = K.WHERE_DIR .. "/" .. nm .. ".txt"
			local ok, raw = false, nil
			if isfile(path) then
				ok, raw = pcall(readfile, path)
			end
			if ok and type(raw) == "string" then
				local at, name, place, job, up, boss, kicked =
					raw:gsub("^\239\187\191", ""):match("^(%d+)|([^|]*)|(%d+)|([^|]*)|([^|]*)|([^|]*)|(%d+)")
				if name then
					out[name] = {
						at = tonumber(at) or 0,
						place = tonumber(place) or 0,
						job = job,
						alive = up == "true",
						leader = boss == "true",
						kicked = tonumber(kicked) or 0,
						age = os.time() - (tonumber(at) or 0),
					}
				end
			end
		end
	end)
	K.__board = out
	return out
end

-- Anyone of ours thrown out in the last twelve seconds, by name. Twelve because a kicked
-- client stops writing the moment it goes, so the stamp is the last thing it left behind.
K.someoneKicked = function()
	for name, w in pairs(K.whereAll()) do
		if name ~= lp.Name and w.kicked > 0 and os.time() - w.kicked <= 12 then
			return name, w
		end
	end
	return nil
end

-- Where the leader is standing right now, straight off the board rather than out of a file
-- somebody wrote a minute ago.
K.leaderWhere = function()
	for name, w in pairs(K.whereAll()) do
		if w.leader and w.age <= 10 then
			return name, w
		end
	end
	return nil
end

task.spawn(function()
	while getgenv().__EWCOIN_K == K do
		K.whereWrite()
		-- Two seconds, not half. Four writers at 2 Hz into one folder is what the file
		-- bridge was choking on; the sync it feeds only has to notice a bot leaving a
		-- server, and that is not a half second question.
		task.wait(2)
	end
end)
K.threatGaveUp = 0
K.threatNote = ""

-- Accounts this farm must never treat as an enemy, by UserId. NEWGOD is the human who
-- owns all of this and he plays his own account in the same servers - matchmaking puts him
-- on whichever team it likes, and every target test in this file works off TeamId alone, so
-- without this list the bots pile onto him the moment he lands on the other side. Checked in
-- validTarget, in the threat scan and by the tracker. Add a UserId here, never a name: names
-- can be changed and a farm that trusts a name can be walked straight into.
K.OWNERS = {
	[8522417802] = "NEWGOD",
}

-- The leader stopped being a fixed account on 2026-08-20. It moved onto the leader and it now runs
-- this farm as well, as BOT D, so four clients kill at the same time instead of three - and it
-- means this file can no longer be told who the leader is at edit time.
-- LEADER.lua writes its own name and UserId into this file the moment it loads and every client
-- reads it back. The UserId is what the target tests use, for the same reason K.OWNERS is keyed
-- by id: a name can be changed and a farm that trusts a name can be walked straight into.
-- Hung on K, not a new top level local - the main chunk is at the 200 register ceiling.
-- Which build this client is actually running. Twice tonight I patched the file, told him
-- it was fixed, and the clients were still carrying the copy they loaded twenty minutes
-- earlier. Read this before believing anything about behaviour.
K.BUILD = "2026-08-20 12:2x qk-verify"
K.LEADER_FILE = "RobloxComm/leader_name.txt"

K.leaderRead = function()
	local now = os.clock()
	if K.__leaderAt and (now - K.__leaderAt) < 5 then
		return
	end
	K.__leaderAt = now
	pcall(function()
		local raw = readfile(K.LEADER_FILE)
		local nm, id = raw:gsub("^\239\187\191", ""):match("^%s*(%S+)%s+(%d+)")
		if nm then
			K.__leaderName = nm
			K.__leaderId = tonumber(id)
		end
	end)
end

-- One value each, on purpose. Handing back the name and the id from the same call would put a
-- number into the second argument of FindFirstChild, which is what turns it into a recursive
-- search of the whole DataModel.
K.leaderName = function()
	K.leaderRead()
	return K.__leaderName or ""
end

K.leaderId = function()
	K.leaderRead()
	return K.__leaderId or K.leaderAccountId()
end

-- leader_name.txt is published by LEADER.lua, which loads AFTER the farm - autoexec runs the
-- folder in name order and eggwars_autostart comes before leader_autostart. So anything the
-- farm needs at build time, the panel letter above all, has to come from leader_account.txt
-- instead: that one is a plain file on disk and it is there before any client starts.
K.leaderAccountId = function()
	local now = os.clock()
	if K.__accAt and (now - K.__accAt) < 5 then
		return K.__accId
	end
	K.__accAt = now
	pcall(function()
		if isfile("RobloxComm/leader_account.txt") then
			K.__accId = tonumber((readfile("RobloxComm/leader_account.txt"):gsub("^\239\187\191", ""):match("%d+")))
		end
	end)
	return K.__accId
end

-- Tolerates a bare userId as well as a player object. The party invite event is
-- the reason: nothing on this machine proves which shape it hands over, and
-- `p.UserId` on a number is a hard error. Thrown inside an event callback that
-- is not wrapped, that error vanishes without trace and looks exactly like the
-- event never firing - which is the wrong conclusion I drew from the logs.
local function isOwner(p)
	-- The account running LEADER.lua counts as an owner too, whoever it is this week.
	local lid = K.leaderId()
	if type(p) == "number" then
		return K.OWNERS[p] ~= nil or (lid ~= nil and p == lid)
	end
	local ok, uid = pcall(function()
		return p and p.UserId
	end)
	if not ok or uid == nil then
		return false
	end
	return K.OWNERS[uid] ~= nil or (lid ~= nil and uid == lid)
end

-- The three farm accounts themselves, by UserId, for the same reason as K.OWNERS. They
-- teleport onto people, they hover over an egg and they die on purpose, so they trip every
-- detector in the threat scan. The 2026-08-03 round logs carry 138 threat lines and 118 of
-- them are these three flagging each other, mostly as HACKER FAKE DEAD. That is not just
-- noise in the report: a player carrying a role is a player the rush logic will go and hunt,
-- so the farm was spending rounds chasing its own team. Hung on K, not a new top level local:
-- the main chunk is at 187 of the 200 Luau registers.
K.BOTS = {
	-- Put your own accounts here: [UserId] = "Username". Three bots plus a leader
	-- is what this was built and measured on. One account works but only the
	-- leader half of it runs; the shell splitting needs the other three.
	-- [123456789] = "YourBotA",
	-- [123456790] = "YourBotB",
	-- [123456791] = "YourBotC",
}

K.isBot = function(p)
	return p ~= nil and K.BOTS[p.UserId] ~= nil
end

-- The match itself. The lobby is 8542259458 and shares this universe, so anything that only
-- makes sense in a round has to ask which place it is standing in rather than assume.
K.MATCH_PLACE = 8951451142

-- Everything that moves the character is gated on this. The script now loads in the lobby as
-- well, and the lobby is where gating stops being cosmetic: there are no Eggs there, so
-- eggPass reports "no egg left", eggThenTp switches AUTO TP on, and then validTarget finds
-- that nobody in a lobby has a TeamId - which makes the team test fall through and marks
-- every single person standing there as a legal target. An ungated farm would spend the whole
-- lobby teleporting onto strangers, in full view of them.
local function inMatch()
	return game.PlaceId == K.MATCH_PLACE
end

-- Being in the match place is not the same as the round having started, and the difference
-- cost most of a round. During Pregame and Countdown everyone is packed into the spawn area,
-- and AUTO TP happily teleported the bot to stand ON a player - the timeline shows dist 0
-- with nine others inside the cluster radius. The moment InGame began it was in the middle
-- of nine enemies holding the starting sword, and it was dead 0.8 seconds later. Respawn is
-- six seconds, so a seventeen second round lost its first seven seconds to that, every time.
-- Fighting starts when the round starts.
-- 2026-08-16, his order, said more than once and finally in full: "while enter the game
-- detect it was at which team then jsut open atk systme go to start farming alreayd and not
-- fucking stadning, it should ingore the whole gaem skywars sytem and go fight". He has
-- watched the bot hang in the air through Pregame and Countdown doing nothing, and he is
-- right that it is dead time - he measured it at twenty seconds and more.
--
-- So the gate is the place and the body now, not the game's own word for whether the round
-- has begun. Nothing waits to be given permission.
--
-- The paragraph above this used to justify the old gate and the thing it warns about is real
-- and was measured, so it is kept here rather than deleted: during Pregame everyone is packed
-- into the spawn area, AUTO TP put the bot at dist 0 on top of a player with nine others
-- inside the cluster radius, InGame began, and it died 0.8 seconds later to nine starting
-- swords. Respawn is six seconds. That is the bill if this turns out badly, and it shows up
-- as deaths in the first seconds of a round, not as anything subtler.
-- His detector, 2026-08-16, and it is better than mine: "we need to do was detect the brozen
-- at each base was alreayd have atelast 1.8 brozne coin alreyad ... it was each sec 1 brozne
-- ... the fastest to detect was detect self base is that alreayd have atleast 1 coin".
--
-- A body says the client loaded. A bronze coin lying at a base says the SERVER has started
-- running the round's economy, which is the thing we actually want to know, and it says it
-- one second in rather than whenever GameState gets around to flipping.
--
-- Bronze only ever spawns at the four team bases, so the nearest cluster to us is ours. With
-- no body yet there is nothing to measure from, so any bronze anywhere counts - the generator
-- is running either way and that is the question being asked.
K.BASE_R = 120

function K.roundOpen()
	if not inMatch() then
		K.roundOpenAt = nil
		return false
	end
	-- Latched for the round once it has answered yes. The question is "has this round
	-- started", which is answered once - asking it again from the middle of the map,
	-- where there is no base and no bronze inside 120 studs, would answer no and switch
	-- the whole farm off in the middle of the round it just turned on.
	if K.roundOpenAt == game.JobId then
		return true
	end
	local c = lp.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	for _, m in ipairs(workspace:GetChildren()) do
		if m.Name == "BronzeCoin" then
			local hb = m:FindFirstChild("Hitbox")
			if hb and hb.Position.Y > -400 then
				if not r then
					K.roundOpenAt = game.JobId
					return true
				end
				local d = (Vector3.new(hb.Position.X, 0, hb.Position.Z)
					- Vector3.new(r.Position.X, 0, r.Position.Z)).Magnitude
				if d <= K.BASE_R then
					K.roundOpenAt = game.JobId
					return true
				end
			end
		end
	end
	return false
end

function K.roundLive()
	return K.roundOpen()
end

local TEAM = {
	dir = "RobloxComm/team",
	roles = { "A", "B", "C", "D" },
	roster = {},
	here = {},
	index = 1,
	count = 1,
	role = "A",
	-- Distinct from role on purpose: role is a stable identity kept across rounds, prime is
	-- "the one doing the single-owner jobs in THIS round". See refreshRoster.
	prime = true,
	note = "solo",
}

local stats = {
	found = 0,
	visited = 0,
	collected = 0,
	byType = {},
	rate = 0,
	lastPassMs = 0,
	startClock = 0,
	elapsed = 0,
	adrenBought = 0,
	buys = 0,
	voidEvents = 0,
}

local splits = {}
local csvPath = nil
local coinPaused = false
local coinAutoOffDone = {}
local store, shopMod, ctrl

local function getStore()
	if store then
		return store
	end
	local ok, res = pcall(function()
		return require(lp.PlayerScripts.TS.ui.rodux["global-store"]).GlobalStore
	end)
	if ok then
		store = res
	end
	return store
end

local function getShop()
	if shopMod then
		return shopMod
	end
	local ok, m = pcall(function()
		return require(ReplicatedStorage.TS.game.shop["game-shop"])
	end)
	if ok then
		shopMod = m
	end
	return shopMod
end

local function getCtrl()
	if ctrl then
		return ctrl
	end
	local ok, fw = pcall(function()
		return require(ReplicatedStorage.rbxts_include.node_modules["@flamework"].core.out).Flamework
	end)
	if not ok then
		return nil, "flamework " .. tostring(fw)
	end
	local ok2, c = pcall(fw.resolveDependency, "M6K")
	if not ok2 or not c then
		return nil, "resolve M6K " .. tostring(c)
	end
	ctrl = c
	return ctrl
end

local function state()
	local s = getStore()
	if not s then
		return nil
	end
	local ok, st = pcall(function()
		return s:getState()
	end)
	if ok then
		return st
	end
	return nil
end

local function quantities()
	local st = state()
	if not st or not st.GameCurrency then
		return nil
	end
	return st.GameCurrency.Quantities
end

local function have(tier)
	local q = quantities()
	if not q then
		return 0
	end
	return q[tier] or 0
end

local function currencyTotals()
	local q = quantities()
	if not q then
		return 0, 0, 0, 0
	end
	return q.TierOne or 0, q.TierTwo or 0, q.TierThree or 0, q.TierFour or 0
end

local function upgradeGroup(idName)
	local s = getShop()
	if not s then
		return nil
	end
	for _, grp in ipairs(s.Shops.Blacksmith.ItemUpgrades) do
		if grp.Id == idName then
			return grp
		end
	end
	return nil
end

local function ownedTierIndex(grp)
	local items = grp.Items
	if grp.Id == "Armour" then
		local worn = lp:GetAttribute("Chestplate")
		if worn then
			for i, it in ipairs(items) do
				if it.ItemType == worn then
					return i
				end
			end
		end
	end
	local inv = ctrl and ctrl.inventoryController
	if not inv then
		return 0
	end
	local best = 0
	for i, it in ipairs(items) do
		local ok, has = pcall(function()
			return inv:hasItem(it.ItemType)
		end)
		if ok and has then
			best = i
		end
	end
	return best
end

-- Own ladder walk instead of the game's getNextUpgradeableItem, which returns nil both
-- when you are maxed and when you own nothing in that ladder - opposite answers.
-- THE THREE RULES HE WORKED OUT, 2026-08-16.
--
-- The kick is not about hitboxes or teleport distance. It fires when a bot sits behind the
-- same player for more than about six seconds; he watched it happen and named it. So the
-- whole fix is about time, and everything here exists to keep one engagement under three
-- seconds:
--
--   gold sword or better, or do not start - a bronze sword cannot finish in three seconds
--   two bots minimum on the same man - one bot alone takes too long by definition
--   three seconds and out, then leave him alone for eight
--
-- The focus is shared through RobloxComm/focus_<name>.txt. Each bot writes who it is on and
-- when; a bot only swings once it can see another bot's fresh claim on the same name. No
-- leader is involved, so it keeps working when the leader is dead or in the lobby.
-- Which tier of sword we own, and where a named tier sits in the list.
--
-- The war plan needs "do we have a diamond yet", not just "do we have a gold yet", so this
-- answers for any word. Names come from the shop group, so a game update that renames a
-- tier still works as long as the word is in the name.
K.swordAt = function(word)
	local grp = upgradeGroup("Sword")
	if not grp or not grp.Items then
		return 0, 0
	end
	local at = 0
	for i, it in ipairs(grp.Items) do
		if at == 0 and tostring(it.ItemType):lower():find(word) then
			at = i
		end
	end
	if at == 0 then
		at = #grp.Items
	end
	return ownedTierIndex(grp), at
end

-- The only honest answer to "did the burst actually pick that coin up". The hitbox does not
-- vanish when a coin is taken, so TICK counting parents was counting the wrong thing; this is
-- the same number the shop spends and the same one coin_test writes.
K.iron = function()
	return have("TierTwo")
end

K.swordIndex = function()
	local grp = upgradeGroup("Sword")
	if not grp or not grp.Items then
		return 0, 0
	end
	local goldAt = 0
	for i, it in ipairs(grp.Items) do
		if goldAt == 0 and tostring(it.ItemType):lower():find("gold") then
			goldAt = i
		end
	end
	if goldAt == 0 then
		goldAt = math.min(3, #grp.Items)
	end
	return ownedTierIndex(grp), goldAt
end

K.swordReady = function()
	if not cfg.tpNeedGoldSword then
		return true, "gate off"
	end
	local owned, need = K.swordIndex()
	if owned >= need then
		return true, string.format("sword %d of %d", owned, need)
	end
	return false, string.format("sword %d, waiting for %d", owned, need)
end

K.focusClaim = function(name)
	pcall(writefile, "RobloxComm/focus_" .. lp.Name .. ".txt",
		string.format("%s %d", tostring(name), os.time()))
end

K.focusCount = function(name)
	local n = 0
	local now = os.time()
	for _, other in pairs(K.BOTS or {}) do
		local ok, raw = pcall(function()
			local f = "RobloxComm/focus_" .. other .. ".txt"
			if isfile(f) then
				return readfile(f)
			end
		end)
		if ok and type(raw) == "string" then
			local who, when = raw:match("^(.-)%s+(%d+)$")
			if who == name and (now - (tonumber(when) or 0)) <= 4 then
				n = n + 1
			end
		end
	end
	return n
end

local function nextUpgrade(idName)
	local grp = upgradeGroup(idName)
	if not grp then
		return nil, nil
	end
	local owned = ownedTierIndex(grp)
	if owned >= #grp.Items then
		return nil, grp
	end
	return grp.Items[owned + 1], grp
end

-- Server truth, not a guess: GameTeams carries an AliveCount per team.
local function aliveCount()
	local st = state()
	local teams = st and st.GameTeams
	if not teams then
		return nil
	end
	local n = 0
	for _, t in pairs(teams) do
		n = n + (tonumber(t.AliveCount) or 0)
	end
	return n
end

-- True when the server has thinned out enough that lifesteal beats heal-on-kill.
local function preferVamp()
	local n = aliveCount()
	return n ~= nil and n <= cfg.vampWhenAliveAtMost
end

local function vampTier()
	local st = state()
	if not st or not st.TeamUpgrades then
		return 0
	end
	return st.TeamUpgrades[K.VAMPYRISM_STATE_KEY] or 0
end

-- Resolve everything now, on the loading thread. A spawned loop that requires a game
-- module later throws "cannot access 'Instance' (lacking capability Plugin)".
getStore()
getShop()
getCtrl()

local gui = Instance.new("ScreenGui")
gui.Name = "EggWarsCoinTest"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
do (function()
	local parented = pcall(function()
		gui.Parent = gethui()
	end)
	if not parented then
		gui.Parent = game:GetService("CoreGui")
	end
end)() end

-- y=90 keeps the bar clear of Roblox's own top bar, which sits over anything at y<60
-- once IgnoreGuiInset is on. The grip on the left drags the whole bar anywhere.
local uiRoot = gui.Parent

local iconBar = Instance.new("Frame")
iconBar.Name = "IconBar"
iconBar.Size = UDim2.fromOffset(560, 42)
iconBar.Position = UDim2.fromOffset(24, 90)
iconBar.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
iconBar.BackgroundTransparency = 0.15
iconBar.BorderSizePixel = 0
iconBar.Active = true
iconBar.Parent = gui
Instance.new("UICorner", iconBar).CornerRadius = UDim.new(0, 6)
do (function()
	local st = Instance.new("UIStroke", iconBar)
	st.Color = Color3.fromRGB(60, 60, 72)
end)() end

-- Icons live in their own list frame so the unload button can sit pinned at the far
-- right of the bar instead of being packed in with them.
local iconList = Instance.new("Frame")
iconList.Name = "List"
iconList.Size = UDim2.new(1, -104, 1, 0)
iconList.BackgroundTransparency = 1
iconList.Parent = iconBar
do (function()
	local layout = Instance.new("UIListLayout", iconList)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	local pad = Instance.new("UIPadding", iconList)
	pad.PaddingLeft = UDim.new(0, 6)
end)() end

local iconGrip = Instance.new("TextLabel")
iconGrip.Name = "Grip"
iconGrip.Size = UDim2.fromOffset(18, 34)
iconGrip.LayoutOrder = 0
iconGrip.BackgroundColor3 = Color3.fromRGB(52, 52, 64)
iconGrip.BorderSizePixel = 0
iconGrip.Text = ":"
iconGrip.TextColor3 = Color3.fromRGB(180, 180, 195)
iconGrip.Font = Enum.Font.GothamBold
iconGrip.TextSize = 16
iconGrip.Parent = iconList
Instance.new("UICorner", iconGrip).CornerRadius = UDim.new(0, 4)

local function label(parent, text, y, h, color, size)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -16, 0, h)
	l.Position = UDim2.new(0, 8, 0, y)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color or Color3.fromRGB(190, 190, 200)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.Font = Enum.Font.Code
	l.TextSize = size or 12
	l.Parent = parent
	return l
end

local function button(parent, text, x, y, w, h)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(w, h)
	b.Position = UDim2.fromOffset(x, y)
	b.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = Color3.fromRGB(225, 225, 235)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 12
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
	return b
end

local function makeDraggable(bar, target)
	local dragging, dragStart, startPos = false, nil, nil
	bind(bar.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			-- The # button on every panel. His ask, 2026-08-15: locked means it cannot be
			-- dragged at all, unlocked means he can move it and it stays where he put it.
			-- Nothing repositions a panel after the round has opened.
			if getgenv().__GUI_LOCKED then
				return
			end
			dragging = true
			dragStart = input.Position
			startPos = target.Position
		end
	end)
	bind(UserInputService.InputChanged, function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			local d = input.Position - dragStart
			target.Position =
				UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
	bind(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

makeDraggable(iconGrip, iconBar)

-- The auto-arranger is gone. He owns where the panels sit.
--
-- It used to walk every panel and pack them into columns, first every 15 seconds and
-- then once per round. Both versions fought him for the same thing: he drags a panel
-- somewhere and something else decides that is not where it goes. His call once the #
-- lock existed, 2026-08-15: "remove the auto putting to position, remove all, i hate
-- it as i was using the # already". Panels now open where makePanel puts them and stay
-- exactly where he leaves them, for the whole session. Nothing writes a position again.
--
-- The size pass below is a different thing and stays - it scales, it never moves.

-- HIS SAVED FORMAT. Placed once, then never touched again.
--
-- This is not the arranger coming back. The arranger invented a layout out of column maths
-- and re-asserted it forever. This reads one file that holds the exact layout he built by
-- hand and called perfect on 2026-08-15, writes each panel there one time at load, locks
-- everything, and stops. After that nothing in the file ever writes a position again.
--
-- Panels are matched by their title with the account name and the (A)/(B)/(C) letter taken
-- out, so one saved format fits all three bots; the few frames with no title fall back to
-- their ScreenGui name plus their size, which is unique for those.
--
-- To re-save after moving things: press # to unlock, drag, then write the new file the same
-- way it was made - RobloxComm/panel_format.txt, one "key|x|y" per line.
do (function()
	getgenv().__FORMAT_GEN = (getgenv().__FORMAT_GEN or 0) + 1
	local MY_FORMAT_GEN = getgenv().__FORMAT_GEN

	getgenv().__FORMAT_KEY = function(g, f, myName)
		for _, c in ipairs(f:GetChildren()) do
			if c:IsA("TextLabel") and c.Text ~= "" and c.Size.Y.Offset > 0 and c.Size.Y.Offset <= 30 then
				local t = c.Text:gsub(myName, ""):gsub("%b()", ""):gsub("%s+", " ")
				t = t:gsub("^[%s%-]+", ""):gsub("[%s%-]+$", "")
				if t ~= "" then
					return t
				end
			end
		end
		return string.format("%s@%dx%d", g.Name, f.Size.X.Offset, f.Size.Y.Offset)
	end

	getgenv().__APPLY_FORMAT = function()
		local raw
		pcall(function()
			if isfile("RobloxComm/panel_format.txt") then
				raw = readfile("RobloxComm/panel_format.txt")
			end
		end)
		if type(raw) ~= "string" or raw == "" then
			return 0, "no saved format on disk"
		end
		local want = {}
		for line in raw:gmatch("[^\r\n]+") do
			local k, x, y = line:match("^(.-)|(-?%d+)|(-?%d+)$")
			if k then
				want[k] = { tonumber(x), tonumber(y) }
			end
		end
		local hui = (pcall(gethui) and gethui() or nil)
		if not hui then
			return 0, "no hidden ui"
		end
		local myName = game:GetService("Players").LocalPlayer.Name
		local placed, missed = 0, {}
		for _, g in ipairs(hui:GetChildren()) do
			if g:IsA("ScreenGui") then
				for _, f in ipairs(g:GetChildren()) do
					if f:IsA("Frame") and f.Size.X.Offset > 40 then
						local key = getgenv().__FORMAT_KEY(g, f, myName)
						local p = want[key]
						if p then
							f.Position = UDim2.fromOffset(p[1], p[2])
							placed = placed + 1
						else
							missed[#missed + 1] = key
						end
					end
				end
			end
		end
		return placed, table.concat(missed, ", ")
	end

	task.spawn(function()
		task.wait(8)
		if getgenv().__FORMAT_GEN ~= MY_FORMAT_GEN then
			return
		end
		local placed, note = getgenv().__APPLY_FORMAT()
		getgenv().__GUI_LOCKED = true
		pcall(getgenv().__LOCK_PAINT)
		pcall(function()
			appendfile("RobloxComm/autoexec_status.txt", os.date("%Y-%m-%d %H:%M:%S")
				.. "  [panels] saved format placed " .. tostring(placed)
				.. " panels and locked them. not matched: " .. tostring(note) .. "\n")
		end)
	end)
end)() end

-- ONE SCALE FOR EVERY PANEL, TAKEN FROM THE SCREEN.
--
-- His report, 2026-08-14 22:4x, with a screenshot: it little some so big some so small some
-- too large some too fit and sometime those word just scuk out for no reason ... it should
-- using how big the client and decive to deicde, beucase i might want to at the futre making
-- a connecting at the phone.
--
-- He is right and the cause is plain in his picture. Every panel is built with hard-typed
-- pixel offsets - makePanel(x, y, w, h) - so on a 1920 wide window they land where somebody
-- once measured them, and nowhere else. Nothing in the file ever reads the viewport, so a
-- smaller window does not shrink them, it just runs them into each other, and a label longer
-- than its hand-typed width has nowhere to go and spills out the side.
--
-- A UIScale on the ScreenGui is the whole fix for the size half. It multiplies every child's
-- position AND size by one number, so the layout he already approved is preserved exactly -
-- nothing moves relative to anything else - and the entire thing shrinks or grows with the
-- window. 1920x1080 is the reference because that is the screen those offsets were measured
-- on. On a phone the same panels arrive proportionally smaller instead of off the edge.
--
-- ClipsDescendants on each panel is the other half: a label that is too long is cut at its
-- own frame instead of being drawn across the panel beside it.
if not getgenv().__FIT_GUI then
	getgenv().__GUI_FIT_NAMES = {
		PerfFloor = true,
		LeaderPanel = true,
		ServerPicker = true,
		InviteBack = true,
		BotFollow = true,
		ServerTimeAlways = true,
	}

	getgenv().__FIT_GUI = function()
		local cam = workspace.CurrentCamera
		if not cam then
			return 0, 0
		end
		local vp = cam.ViewportSize
		if vp.X < 1 or vp.Y < 1 then
			return 0, 0
		end
		-- The smaller of the two ratios, so nothing is ever scaled past the edge it is
		-- anchored to. Floored at 0.45 because below that the text stops being readable and
		-- an unreadable panel is worth no more than a missing one.
		local s = math.min(vp.X / 1920, vp.Y / 1080)
		s = math.clamp(s, 0.45, 1.25)

		local hui = (pcall(gethui) and gethui() or nil)
		local me = game:GetService("Players").LocalPlayer
		local seen, n = {}, 0
		for _, root in ipairs({ hui, game:GetService("CoreGui"),
			me and me:FindFirstChildOfClass("PlayerGui") }) do
			if root then
				for _, d in ipairs(root:GetDescendants()) do
					if d:IsA("ScreenGui") and not seen[d] then
						local mine = getgenv().__GUI_FIT_NAMES[d.Name] or false
						if not mine and hui and d:IsDescendantOf(hui) then
							mine = true
						end
						if mine then
							seen[d] = true
							n = n + 1
							local sc = d:FindFirstChildOfClass("UIScale")
							if not sc then
								sc = Instance.new("UIScale")
								sc.Parent = d
							end
							sc.Scale = s
							-- Only the panels, never the ScreenGui itself, and never a frame
							-- that is only there to hold a row of buttons.
							for _, f in ipairs(d:GetChildren()) do
								if f:IsA("Frame") and f.Size.X.Offset > 80 and f.Size.Y.Offset > 40 then
									f.ClipsDescendants = true
								end
							end
						end
					end
				end
			end
		end
		return n, s
	end

	task.spawn(function()
		getgenv().__FIT_GEN = (getgenv().__FIT_GEN or 0) + 1
		local MY_FIT_GEN = getgenv().__FIT_GEN
		while getgenv().__FIT_GEN == MY_FIT_GEN do
			pcall(getgenv().__FIT_GUI)
			task.wait(3)
		end
	end)
end

-- ALT HIDES EVERY SCRIPT GUI, NOT JUST ONE PANEL.
--
-- His words, 2026-08-14: it should hide all gui [ALL GUI] ... as it only hide a few part it
-- dind thide all scirpt gui.
--
-- The old handler flipped one ScreenGui - the farm's own - so PERF FLOOR, SERVER PICKER and
-- the leader panel all stayed on screen. Measured on the live leader: the ScreenGuis our
-- scripts own are ScreenGui, PerfFloor, LeaderPanel and ServerPicker, and every one of them
-- sits under gethui(). Everything the game itself draws is in PlayerGui or elsewhere in
-- CoreGui, so anchoring on gethui() catches all of ours and none of theirs, and the name
-- list underneath catches anything that ends up parented somewhere else.
--
-- The switch lives in getgenv so the leader and the bots share one state: one press, one
-- result, whichever file installed the key.
-- A version stamp, because the guard below is a trap.
--
-- The whole block is skipped when __TOGGLE_ALL_GUI already exists, which is what makes the
-- switch shared. The cost showed up on 2026-08-15: I added the keep list to this function,
-- reloaded the farm on all three bots, and nothing changed - the old function was still
-- sitting in getgenv and the new definition never ran. He found it the way anyone would,
-- by pressing ALT and watching the egg test panel vanish anyway.
--
-- Bumping this number forces the rebuild. Any future edit in here has to bump it too.
if getgenv().__TOGGLE_VER ~= 2 then
	getgenv().__TOGGLE_VER = 2
	getgenv().__TOGGLE_ALL_GUI = nil
end

if not getgenv().__TOGGLE_ALL_GUI then
	getgenv().__GUI_NAMES = {
		PerfFloor = true,
		LeaderPanel = true,
		ServerPicker = true,
		InviteBack = true,
		BotFollow = true,
	}
	getgenv().__GUI_HIDDEN = false

	-- SERVER TIME NEVER HIDES.
	--
	-- His rule, 2026-08-14: the severtime at all client even pressing the thing it shoudlt be
	-- hide, as timer was super irmapont.
	--
	-- It cannot simply be skipped by the toggle, because it is a Frame inside the leader
	-- panel's ScreenGui - disabling that ScreenGui takes the clock down with it whatever the
	-- Frame says. So it is moved into a ScreenGui of its own that the toggle never touches.
	-- Its Position is screen-relative, so it lands in exactly the same pixels and nothing on
	-- screen moves.
	getgenv().__SERVERTIME_KEEP = function()
		local hui = (pcall(gethui) and gethui() or nil)
		local parent = hui or game:GetService("CoreGui")
		local host = parent:FindFirstChild("ServerTimeAlways")
		if not host then
			host = Instance.new("ScreenGui")
			host.Name = "ServerTimeAlways"
			host.ResetOnSpawn = false
			host.DisplayOrder = 10000
			host.Parent = parent
		end
		-- The clock has to ignore the top bar like every other panel here does.
		--
		-- This host ScreenGui was the one place that never set it, and every other ScreenGui in
		-- the file sets it true. So the moment SERVER TIME was reparented in here it started
		-- rendering 58 px lower than the slot it was written for - the gap between the leader
		-- panel that ends at 592 and START that begins at 700. That is his "little position bug".
		-- Set every time, not only on creation, so a host made by an older load is repaired too.
		host.IgnoreGuiInset = true
		host.Enabled = true
		local me = game:GetService("Players").LocalPlayer
		local moved = 0
		for _, root in ipairs({ hui, game:GetService("CoreGui"),
			me and me:FindFirstChildOfClass("PlayerGui") }) do
			if root then
				for _, d in ipairs(root:GetDescendants()) do
					if d:IsA("Frame") and d.Name == "ServerTime" and d.Parent ~= host then
						pcall(function()
							d.Parent = host
						end)
						moved = moved + 1
					end
				end
			end
		end
		return host, moved
	end

	getgenv().__TOGGLE_ALL_GUI = function()
		local hide = not getgenv().__GUI_HIDDEN
		getgenv().__GUI_HIDDEN = hide
		pcall(getgenv().__SERVERTIME_KEEP)
		local hui = (pcall(gethui) and gethui() or nil)
		local me = game:GetService("Players").LocalPlayer
		local seen, n = {}, 0
		for _, root in ipairs({ hui, game:GetService("CoreGui"),
			me and me:FindFirstChildOfClass("PlayerGui") }) do
			if root then
				for _, d in ipairs(root:GetDescendants()) do
					-- A keep list, so ALT does not swallow panels that are not the farm's.
				--
				-- His correction, 2026-08-15: the egg range test is a temporary panel he is
				-- driving by hand, not part of the farm's GUI, so hiding everything should
				-- leave it alone. Anything that registers its name in __GUI_KEEP survives
				-- the toggle; ServerTimeAlways was the first one and was hardcoded here.
				getgenv().__GUI_KEEP = getgenv().__GUI_KEEP or {}
				getgenv().__GUI_KEEP.ServerTimeAlways = true
				getgenv().__GUI_KEEP.EggRangeTest = true
				if d:IsA("ScreenGui") and not seen[d] and not getgenv().__GUI_KEEP[d.Name] then
						local mine = getgenv().__GUI_NAMES[d.Name] or false
						if not mine and hui then
							local a = d.Parent
							while a do
								if a == hui then
									mine = true
									break
								end
								a = a.Parent
							end
						end
						if mine then
							seen[d] = true
							n = n + 1
							pcall(function()
								d.Enabled = not hide
							end)
						end
					end
				end
			end
		end
		return n, hide
	end
end

gui.Enabled = true

-- AUTO HIDE THE BOT PANELS ON ENTERING A MATCH.
--
-- His ask, 2026-08-16: "i jstu while enter game auto hide all bot gui then ok, only left the
-- leader gui dont hide then ok".
--
-- Safe by construction: this file only ever runs on the three bots. The leader runs
-- LEADER.lua and never loads this one, so nothing here can reach his leader panel.
--
-- Two details that would break it if left out. __TOGGLE_ALL_GUI is a toggle, not a setter,
-- and getgenv survives a place change on the same client - so the flag is forced false first
-- or the second round of the night toggles every panel back ON. And it waits a second,
-- because the panels the toggle walks are still being parented while this line runs.
--
-- ALT still works. This sets the starting state, it does not take the control away.
do (function()
	if game.PlaceId ~= K.MATCH_PLACE then
		return
	end
	if getgenv().__BOT_GUI_AUTOHIDE == game.JobId then
		return
	end
	getgenv().__BOT_GUI_AUTOHIDE = game.JobId
	task.spawn(function()
		task.wait(1)
		getgenv().__GUI_NAMES = getgenv().__GUI_NAMES or {}
		getgenv().__GUI_NAMES[gui.Name] = true
		getgenv().__GUI_HIDDEN = false
		local ok, n = pcall(getgenv().__TOGGLE_ALL_GUI)
		pcall(appendfile, "RobloxComm/gui_autohide.log", string.format(
			"%s  %s  hid %s panel(s) on entering %s\n", os.date("%Y-%m-%d %H:%M:%S"),
			lp.Name, ok and tostring(n) or ("FAILED " .. tostring(n)), tostring(game.JobId)))
	end)
end)() end

bind(UserInputService.InputBegan, function(input, typing)
	if typing then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
		getgenv().__GUI_NAMES[gui.Name] = true
		getgenv().__TOGGLE_ALL_GUI()
	end
end)

-- Every panel gets a [-] that shrinks it to an icon in the top-left bar, and the icon
-- brings it back. Nothing is destroyed, so state and running loops are untouched.
local iconOrder = 0
local function makePanel(x, y, w, h, titleText, iconText, startCollapsed)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(w, h)
	f.Position = UDim2.fromOffset(x, y)
	f.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
	f.BorderSizePixel = 0
	f.Active = true
	f.Parent = gui
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)
	local st = Instance.new("UIStroke", f)
	st.Color = Color3.fromRGB(60, 60, 72)
	st.Thickness = 1

	local bar = Instance.new("TextLabel")
	bar.Size = UDim2.new(1, 0, 0, 28)
	bar.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
	bar.BorderSizePixel = 0
	bar.Text = titleText
	bar.TextColor3 = Color3.fromRGB(235, 235, 245)
	bar.Font = Enum.Font.GothamBold
	bar.TextSize = 13
	bar.Parent = f
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 6)

	local minus = button(f, "-", w - 30, 4, 22, 20)
	minus.Font = Enum.Font.GothamBold
	minus.TextSize = 16
	minus.BackgroundColor3 = Color3.fromRGB(52, 52, 64)


	iconOrder = iconOrder + 1
	local icon = Instance.new("TextButton")
	icon.Size = UDim2.fromOffset(52, 34)
	icon.LayoutOrder = iconOrder
	icon.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
	icon.BorderSizePixel = 0
	icon.Text = iconText
	icon.TextColor3 = Color3.fromRGB(225, 225, 235)
	icon.Font = Enum.Font.GothamBold
	icon.TextSize = 13
	icon.Parent = iconList
	Instance.new("UICorner", icon).CornerRadius = UDim.new(0, 5)
	local istroke = Instance.new("UIStroke", icon)
	istroke.Color = Color3.fromRGB(60, 60, 72)

	local function setCollapsed(v)
		f.Visible = not v
		icon.Visible = v
	end
	bind(minus.MouseButton1Click, function()
		setCollapsed(true)
	end)
	bind(icon.MouseButton1Click, function()
		setCollapsed(false)
	end)
	setCollapsed(startCollapsed and true or false)

	makeDraggable(bar, f)
	return f, bar, icon
end

-- Default layout, laid out by hand on a 1920x1009 screen and kept as-is. Every panel is
-- still draggable; these are only where they start.
local frame = makePanel(945, 276, 248, 470, "COIN TEST", "COIN", false)
local buyFrame = makePanel(1214, 277, 236, 470, "AUTO BUY", "BUY", false)
local trackFrame = makePanel(301, 271, 356, 490, "PLAYER TRACKER", "PLYR", false)
local avFrame = makePanel(681, 282, 236, 366, "ANTI VOID", "VOID", false)
local tpFrame = makePanel(24, 264, 250, 250, "AUTO TP", "TP", false)
local eggFrame = makePanel(24, 524, 250, 250, "AUTO EGG", "EGG", false)
local timerFrame = makePanel(39, 147, 200, 108, "SERVER TIME", "TIME", false)
local ramFrame = makePanel(681, 656, 236, 250, "RAM DOWNGRADE", "RAM", false)
-- 142 to 176. The two settle buttons go on the row at y=102 that the note used to hold, and
-- the note moves down to 132. y=72 is not free - FREE MOUSE has been sitting there.
-- WHOSE SCREEN IS THIS.
--
-- His ask 2026-08-15: "i need was must be write the bot was what at the gui also add that so
-- i can ez to say this was what bot". Four windows all showing the same panels and nothing on
-- any of them said which account he was looking at, so every instruction had to start with
-- him working that out first.
--
-- The letter is the one the leader uses in its roll calls - A, B and C keyed by UserId in
-- LEADER.lua - so the name on screen and the name in the log are the same word.
-- Inlined, not held in a local, because this file is at Luau's ceiling.
--
-- Measured 2026-08-15 17:4x, straight off the client: the whole script stopped compiling with
-- ":7611: Out of local registers when trying to allocate MY_FORGOT_GEN: exceeded limit 200".
-- A Luau function may hold 200 locals and the main chunk of this file was sitting on the line,
-- so the single `local WHO_LETTER` added an hour earlier for the panel title was enough to push
-- it over - and a file that will not compile means every bot silently has no farm at all, which
-- is exactly what was found: armed=nil on all three.
local stopFrame = makePanel(301, 780, 356, 176,
	string.format("STOP FARM  -  %s  (%s)", lp.Name,
		({ ["YourBotA"] = "A", ["YourBotB"] = "B", ["YourBotC"] = "C" })[lp.Name]
		or ((getgenv().__IS_LEADER or lp.UserId == K.leaderAccountId()) and "D") or "?"),
	"STOP", false)

local master = button(frame, "START", 8, 34, 232, 30)
master.Font = Enum.Font.GothamBold
master.TextSize = 14

local typeButtons = {}
for i, t in ipairs(TYPES) do
	local y = 72 + (i - 1) * 26
	local b = button(frame, t.label, 8, y, 150, 22)
	b.TextXAlignment = Enum.TextXAlignment.Left
	Instance.new("UIPadding", b).PaddingLeft = UDim.new(0, 8)
	local count = label(frame, "0", y + 3, 18, t.color)
	count.Size = UDim2.fromOffset(78, 18)
	count.Position = UDim2.fromOffset(162, y + 3)
	count.TextXAlignment = Enum.TextXAlignment.Right
	typeButtons[t.key] = { button = b, count = count, def = t }
	bind(b.MouseButton1Click, function()
		cfg.types[t.key] = not cfg.types[t.key]
		if cfg.types[t.key] then
			-- Turning it on by hand means you want it on: auto buy may not take it away.
			coinAutoOffDone[t.key] = true
		else
			-- and turning it off by hand hands control back to auto buy.
			coinAutoOffDone[t.key] = nil
		end
	end)
end

local function stepper(parent, y, w, onMinus, onPlus)
	local l = label(parent, "", y + 4, 18)
	l.Size = UDim2.fromOffset(w - 80, 18)
	local minus = button(parent, "-", w - 70, y, 34, 22)
	local plus = button(parent, "+", w - 32, y, 34, 22)
	bind(minus.MouseButton1Click, onMinus)
	bind(plus.MouseButton1Click, onPlus)
	return l
end

local dwellLabel = stepper(frame, 182, 240, function()
	cfg.dwellIndex = math.max(1, cfg.dwellIndex - 1)
end, function()
	cfg.dwellIndex = math.min(#K.DWELLS, cfg.dwellIndex + 1)
end)

local radiusLabel = stepper(frame, 208, 240, function()
	cfg.radius = math.max(50, cfg.radius - 50)
end, function()
	cfg.radius = math.min(2000, cfg.radius + 50)
end)

local perPassLabel = stepper(frame, 234, 240, function()
	cfg.perPass = math.max(1, cfg.perPass - 5)
end, function()
	cfg.perPass = math.min(200, cfg.perPass + 5)
end)

local homeButton = button(frame, "RETURN HOME: ON", 8, 260, 232, 22)
local statsLabel = label(frame, "", 290, 78)
local splitLabel = label(frame, "", 372, 62, Color3.fromRGB(150, 200, 150))
local errorLabel = label(frame, "", 436, 28, Color3.fromRGB(255, 92, 92))

local autoMaster = button(buyFrame, "AUTO BUY: OFF", 8, 34, 220, 30)
autoMaster.Font = Enum.Font.GothamBold
autoMaster.TextSize = 14

local buyToggles = {}
local BUY_ROWS = {
	{ key = "buySword", label = "SWORD" },
	{ key = "buyArmour", label = "ARMOUR" },
	{ key = "buyVamp", label = "T1 VAMPYRISM" },
	{ key = "buyTriumph", label = "T0 TRIUMPH" },
	{ key = "buyAdrenaline", label = "ADRENALINE" },
	{ key = "adrenAutoUse", label = "  AUTO USE IT" },
}
for i, row in ipairs(BUY_ROWS) do
	local y = 72 + (i - 1) * 26
	local b = button(buyFrame, row.label, 8, y, 220, 22)
	b.TextXAlignment = Enum.TextXAlignment.Left
	Instance.new("UIPadding", b).PaddingLeft = UDim.new(0, 8)
	buyToggles[row.key] = { button = b, label = row.label }
	bind(b.MouseButton1Click, function()
		cfg[row.key] = not cfg[row.key]
	end)
end

local buyStatus = label(buyFrame, "", 240, 96)
local buyLog = label(buyFrame, "", 340, 90, Color3.fromRGB(150, 200, 150))
local buyError = label(buyFrame, "", 436, 28, Color3.fromRGB(255, 92, 92))

local trackHeader = label(trackFrame, "", 36, 16, Color3.fromRGB(225, 225, 235))
local enemyButton = button(trackFrame, "SHOW: EVERYONE", 8, 56, 166, 22)
local espButton = button(trackFrame, "ESP: ON", 182, 56, 166, 22)
local voidLog = label(trackFrame, "", 84, 62, Color3.fromRGB(255, 150, 90))

bind(espButton.MouseButton1Click, function()
	cfg.esp = not cfg.esp
end)

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.fromOffset(340, 330)
scroll.Position = UDim2.fromOffset(8, 150)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = trackFrame
do (function()
	local layout = Instance.new("UIListLayout", scroll)
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
end)() end

bind(enemyButton.MouseButton1Click, function()
	cfg.trackEnemiesOnly = not cfg.trackEnemiesOnly
end)

local avFloorButton = button(avFrame, "FLOOR: OFF", 8, 34, 220, 26)
avFloorButton.Font = Enum.Font.GothamBold
local avCatchButton = button(avFrame, "CATCH BACK: ON", 8, 64, 220, 26)
local avFollowButton = button(avFrame, "FOLLOW ME: OFF", 8, 94, 220, 26)

local avYLabel = stepper(avFrame, 156, 228, function()
	cfg.avY = cfg.avY - 5
end, function()
	cfg.avY = cfg.avY + 5
end)
local avSizeLabel = stepper(avFrame, 182, 228, function()
	cfg.avSize = math.max(200, cfg.avSize - 200)
end, function()
	cfg.avSize = math.min(4000, cfg.avSize + 200)
end)

local avSnapButton = button(avFrame, "SNAP FLOOR TO MAP", 8, 210, 220, 22)
local avStatus = label(avFrame, "", 240, 86)
local avError = label(avFrame, "", 330, 26, Color3.fromRGB(255, 92, 92))

local tpButton = button(tpFrame, "AUTO TP: OFF", 8, 34, 234, 30)
tpButton.Font = Enum.Font.GothamBold
tpButton.TextSize = 14

local tpRangeLabel = stepper(tpFrame, 72, 242, function()
	cfg.tpRange = math.max(0, cfg.tpRange - 0.5)
end, function()
	cfg.tpRange = math.min(30, cfg.tpRange + 0.5)
end)
local tpFramesLabel = stepper(tpFrame, 98, 242, function()
	cfg.tpFrames = math.max(1, cfg.tpFrames - 1)
end, function()
	cfg.tpFrames = math.min(10, cfg.tpFrames + 1)
end)

local tpStatus = label(tpFrame, "", 128, 88)
local tpError = label(tpFrame, "", 218, 26, Color3.fromRGB(255, 92, 92))

local eggButton = button(eggFrame, "AUTO EGG: OFF", 8, 34, 234, 30)
eggButton.Font = Enum.Font.GothamBold
eggButton.TextSize = 14
local eggThenButton = button(eggFrame, "THEN AUTO TP: ON", 8, 68, 234, 22)

local eggDownLabel = stepper(eggFrame, 96, 242, function()
	cfg.eggUp = math.max(-40, cfg.eggUp - 1)
end, function()
	cfg.eggUp = cfg.eggUp + 1
end)
local eggFramesLabel = stepper(eggFrame, 122, 242, function()
	cfg.eggFrames = math.max(1, cfg.eggFrames - 1)
end, function()
	cfg.eggFrames = math.min(10, cfg.eggFrames + 1)
end)

local eggStatus = label(eggFrame, "", 152, 88)
local eggError = label(eggFrame, "", 242, 26, Color3.fromRGB(255, 92, 92))

-- One scrolling module list instead of Vape's eight floating windows. A row is only
-- clickable when it is actually wired to something; anything not implemented yet stays
-- grey and says so, rather than pretending to be a working switch.

local ramButton = button(ramFrame, "RAM DOWNGRADE: ON", 8, 34, 220, 30)
ramButton.Font = Enum.Font.GothamBold
ramButton.TextSize = 14
local ram3dButton = button(ramFrame, "3D RENDER: ON", 8, 68, 220, 24)
-- On K and not a top level local, which is not a style choice. Adding this as local number
-- 181 pushed the main chunk past Luau's 200 register limit and the farm stopped compiling
-- outright: at 20:07:19 on 2026-08-05 a bot teleported into a match, the autoexec logged
-- "Out of local registers", and the round ran with no farm at all and nothing on screen to
-- say why. The comment at the top of this file says exactly this. I ignored it.
K.vapeCycleButton = button(ramFrame, "VAPE ON DEMAND: ON", 8, 96, 220, 24)
local ramStatus = label(ramFrame, "", 126, 84)
local ramError = label(ramFrame, "", 214, 28, Color3.fromRGB(255, 92, 92))

local stopButton = button(stopFrame, "FARM RUNNING - CLICK TO STOP", 8, 34, 340, 34)
stopButton.Font = Enum.Font.GothamBold
stopButton.TextSize = 16
-- On K and not on top level locals, for the reason written above VAPE ON DEMAND: this chunk
-- has already been pushed past Luau's 200 register limit once, and when that happens the farm
-- does not compile at all and the round runs with nothing on screen to say why.
K.settleButton = button(stopFrame, "SETTLE 2.0s", 8, 102, 166, 24)
K.eggCoinButton = button(stopFrame, "EGG-PHASE COINS: OFF", 182, 102, 166, 24)

bind(K.settleButton.MouseButton1Click, function()
	local steps = { 0, 1, 2, 4, 6 }
	local at = 1
	for i, v in ipairs(steps) do
		if v == cfg.settleSecs then
			at = i
		end
	end
	cfg.settleSecs = steps[(at % #steps) + 1]
end)

bind(K.eggCoinButton.MouseButton1Click, function()
	cfg.eggGrabCoins = not cfg.eggGrabCoins
end)

local stopNote = label(stopFrame, "stops coins, buying, AUTO TP and AUTO EGG only.\nanti void, catch back, ESP and Vape keep running.", 132, 32, Color3.fromRGB(140, 140, 155), 11)

local timerLabel = label(timerFrame, "00:00.000", 36, 34, Color3.fromRGB(235, 235, 245), 26)
timerLabel.TextXAlignment = Enum.TextXAlignment.Center
local timerSub = label(timerFrame, "", 72, 18, Color3.fromRGB(140, 140, 155), 11)
timerSub.TextXAlignment = Enum.TextXAlignment.Center

bind(eggThenButton.MouseButton1Click, function()
	cfg.eggThenTp = not cfg.eggThenTp
end)

bind(avFloorButton.MouseButton1Click, function()
	cfg.avFloor = not cfg.avFloor
end)
bind(avCatchButton.MouseButton1Click, function()
	cfg.avCatch = not cfg.avCatch
end)
bind(avFollowButton.MouseButton1Click, function()
	cfg.avFollow = not cfg.avFollow
end)

local logLines = {}
local function pushLog(text)
	table.insert(logLines, 1, text)
	if #logLines > 7 then
		table.remove(logLines)
	end
end

local voidLines = {}
local function pushVoid(text)
	table.insert(voidLines, 1, text)
	if #voidLines > 4 then
		table.remove(voidLines)
	end
	stats.voidEvents = stats.voidEvents + 1
end

local function setError(msg)
	errorLabel.Text = msg and ("! " .. msg) or ""
end

local function setBuyError(msg)
	buyError.Text = msg and ("! " .. msg) or ""
end

bind(homeButton.MouseButton1Click, function()
	cfg.returnHome = not cfg.returnHome
end)

bind(autoMaster.MouseButton1Click, function()
	cfg.autoBuy = not cfg.autoBuy
	if cfg.autoBuy then
		setBuyError(nil)
	end
end)

local function appendCsv(line)
	if not csvPath then
		return
	end
	local ok, err = pcall(appendfile, csvPath, line .. "\n")
	if not ok then
		setError("csv " .. tostring(err))
	end
end

local function startCollect()
	stats.visited = 0
	stats.collected = 0
	stats.byType = {}
	stats.startClock = os.clock()
	splits = {}
	setError(nil)

	-- One file per load of this script, not one per press of START. Every restart of the
	-- collector used to mint another csv and nothing ever deleted them, so the folder had
	-- collected over two hundred of these. Left running unattended that is the file count
	-- growing all night for no reader.
	if csvPath then
		return
	end

	local ok, err = pcall(function()
		if not isfolder("RobloxComm") then
			makefolder("RobloxComm")
		end
		-- Keep the six newest and drop the rest. The names are timestamps, so sorting the
		-- names is sorting by age.
		local old = {}
		for _, f in ipairs(listfiles("RobloxComm")) do
			-- This account's own files only. The name used to be a bare timestamp with no
			-- account in it, so with four clients sharing one workspace folder the fourth one
			-- to load deleted a csv the first one was still appending to, and the first one
			-- then silently rebuilt it from half a file.
			if string.find(f, "coin_test_" .. lp.Name .. "_", 1, true) then
				old[#old + 1] = f
			end
		end
		table.sort(old)
		for i = 1, #old - 6 do
			pcall(delfile, old[i])
		end

		csvPath = "RobloxComm/coin_test_" .. lp.Name .. "_" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".csv"
		writefile(csvPath, "elapsed_s,visited,collected,rate_per_s,bronze,iron,gold,shard\n")
	end)
	if not ok then
		csvPath = nil
		setError("csv init " .. tostring(err))
	end
end

bind(master.MouseButton1Click, function()
	cfg.enabled = not cfg.enabled
	if cfg.enabled then
		startCollect()
	end
end)

if cfg.enabled then
	startCollect()
end

local function root()
	local char = lp.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

-- Only one thing may drive the character at a time. The coin collector, AUTO TP, AUTO EGG
-- and the anti-void catch all write HumanoidRootPart.CFrame, and before this they simply
-- fought: the collector would dive after a pickup, the catch would haul you back up, and
-- the next frame the collector dove again. That tug of war is what parked the bot under
-- the map. Anti-void wins outright - nothing else moves while you are under the line.
local function belowVoid()
	local r = root()
	return r ~= nil and r.Position.Y < K.VOID_Y
end

local function collectPass()
	local r = root()
	if not r then
		setError("no HumanoidRootPart - waiting for spawn")
		return
	end
	if lp:GetAttribute("Alive") == false then
		setError("dead - waiting for respawn")
		return
	end
	if belowVoid() then
		setError("under the void line - anti void has priority")
		return
	end

	local home = r.CFrame
	local list = {}
	for _, m in ipairs(workspace:GetChildren()) do
		if cfg.types[m.Name] then
			local hb = m:FindFirstChild("Hitbox")
			if hb and hb:IsA("BasePart") then
				local d = (hb.Position - home.Position).Magnitude
				-- a coin that fell off the map is not worth following it down
				if d <= cfg.radius and hb.Position.Y >= K.VOID_Y then
					table.insert(list, { m = m, hb = hb, d = d, name = m.Name })
				end
			end
		end
	end
	stats.found = #list
	if #list == 0 then
		setError(nil)
		return
	end

	table.sort(list, function(a, b)
		return a.d < b.d
	end)

	local dwell = K.DWELLS[cfg.dwellIndex] or 0
	local n = math.min(cfg.perPass, #list)
	local t0 = os.clock()

	for i = 1, n do
		if not cfg.enabled or not alive or getgenv().__EWCOIN_GEN ~= MY_GEN then
			break
		end
		local e = list[i]
		-- Re-read the height now, not when the list was sorted: these hitboxes fall.
		-- Above the void line is not the same as standing on something: a coin knocked
		-- out over a gap stays above the line the whole way down, and fetching it put
		-- the bot in open air with it.
		local spot = e.hb.Parent and r.Parent and e.hb.Position.Y >= K.VOID_Y
			and K.safeDest(e.hb.Position, e.hb.Position, e.m) or nil
		if spot then
			K.hop(r, CFrame.new(spot))
			if dwell > 0 then
				task.wait(dwell)
			else
				RunService.Heartbeat:Wait()
			end
			stats.visited = stats.visited + 1
			if not e.m.Parent then
				stats.collected = stats.collected + 1
				stats.byType[e.name] = (stats.byType[e.name] or 0) + 1
			end
		end
	end

	if cfg.returnHome and r.Parent and home.Position.Y >= K.VOID_Y then
		K.hop(r, home)
	end
	stats.lastPassMs = (os.clock() - t0) * 1000
	setError(nil)
end

local function fireAndConfirm(tier, price, what, fn)
	local before = have(tier)
	local ok, err = pcall(fn)
	if not ok then
		setBuyError(tostring(err))
		return false
	end
	local t0 = os.clock()
	while os.clock() - t0 < 0.6 do
		if have(tier) <= before - price then
			stats.buys = stats.buys + 1
			pushLog(string.format("%.0fs %s -%d", stats.elapsed, what, price))
			return true
		end
		RunService.Heartbeat:Wait()
	end
	pushLog(string.format("%.0fs %s REFUSED", stats.elapsed, what))
	return false
end

local flameworkCache
local function resolve(id)
	if not K.fwReady then
		return nil
	end
	if not flameworkCache then
		local ok, fw = pcall(function()
			return require(ReplicatedStorage.rbxts_include.node_modules["@flamework"].core.out).Flamework
		end)
		if not ok then
			return nil
		end
		flameworkCache = fw
	end
	local ok, dep = pcall(flameworkCache.resolveDependency, id)
	return ok and dep or nil
end

-- Untested path, kept honest: pick the Adrenaline slot with the hotbar controller ("845"
-- is its Flamework id) and then click the way a hand would. Success is judged only by the
-- Shield attribute actually going up, never by the call not erroring.
local adrenLastTry = 0
local function useAdrenaline()
	if os.clock() - adrenLastTry < 2.5 then
		return
	end
	adrenLastTry = os.clock()

	local shield = lp:GetAttribute("Shield") or 0
	if shield >= 25 then
		return
	end

	local st = state()
	local contents = st and st.Inventory and st.Inventory.Contents
	if not contents then
		setBuyError("auto use: no Inventory.Contents")
		return
	end

	local slot
	for k, v in pairs(contents) do
		if type(v) == "table" then
			local it = v.ItemType or v.Type or (v.Item and v.Item.ItemType)
			if it == "Adrenaline" then
				slot = v.SlotId or v.Slot or v.slotId or (type(k) == "number" and k or nil)
				break
			end
		end
	end
	if not slot then
		setBuyError("auto use: no Adrenaline in hotbar")
		return
	end

	local hotbar = resolve("845")
	if not hotbar then
		setBuyError("auto use: hotbar controller missing")
		return
	end
	-- Remember what was held. Leaving the Adrenaline slot selected is not a small thing:
	-- MeleeController:strike bails out unless getHeldItemInfo().Melee is true, so an
	-- unrestored slot silently kills every aura and leaves you swinging by hand.
	local previousSlot
	pcall(function()
		previousSlot = state().ActiveSlot
	end)
	local function restoreSlot()
		if previousSlot and previousSlot ~= slot then
			pcall(function()
				hotbar:setActiveSlot(previousSlot)
			end)
		end
	end

	local ok, err = pcall(function()
		hotbar:setActiveSlot(slot)
	end)
	if not ok then
		setBuyError("auto use: setActiveSlot " .. tostring(err))
		restoreSlot()
		return
	end
	task.wait(0.2)

	-- Adrenaline is a HOLD, not a click - a tap does nothing at all.
	--
	-- mouse1press is Real's NATIVE, OS level input, and native input is a silent no-op
	-- whenever the Roblox window is not focused. Three clients farming while you do something
	-- else are unfocused by definition, so on this setup that path can never work - and it
	-- never says so either, because a no-op does not raise an error, so the pcall reports
	-- success and the only trace left is "shield never rose" two seconds later.
	-- VirtualInputManager goes through the engine and does not care about focus, so it is the
	-- one that has to be used when the window is in the background.
	local focused = true
	pcall(function()
		focused = isrbxactive()
	end)

	local vim = game:GetService("VirtualInputManager")
	local held, release, path = false, nil, nil

	if focused then
		held = pcall(function()
			mouse1press()
		end)
		if held then
			path = "native"
			release = function()
				pcall(function()
					mouse1release()
				end)
			end
		end
	end
	if not held then
		held = pcall(function()
			vim:SendMouseButtonEvent(0, 0, 0, true, game, 0)
		end)
		if held then
			path = "virtual"
			release = function()
				pcall(function()
					vim:SendMouseButtonEvent(0, 0, 0, false, game, 0)
				end)
			end
		end
	end
	if not held or not release then
		setBuyError("auto use: no mouse hold available (focused=" .. tostring(focused) .. ")")
		return
	end

	local shieldRose = false
	local hold0 = os.clock()
	while os.clock() - hold0 < cfg.adrenHold do
		if (lp:GetAttribute("Shield") or 0) > shield then
			shieldRose = true
			break
		end
		RunService.Heartbeat:Wait()
	end
	release()
	if shieldRose then
		restoreSlot()
		pushLog(string.format("%.0fs Adrenaline USED +shield", stats.elapsed))
		setBuyError(nil)
		return
	end

	local t0 = os.clock()
	while os.clock() - t0 < 1.2 do
		if (lp:GetAttribute("Shield") or 0) > shield then
			restoreSlot()
			pushLog(string.format("%.0fs Adrenaline USED +shield", stats.elapsed))
			setBuyError(nil)
			return
		end
		RunService.Heartbeat:Wait()
	end
	restoreSlot()
	-- Naming the path matters: "shield never rose via native" means the window was focused and
	-- the game refused, "via virtual" means the engine took the click and the game still
	-- refused. Those are two different investigations.
	setBuyError(string.format("auto use: held %.1fs via %s, shield never rose", cfg.adrenHold, tostring(path)))
end


-- Vape's Killaura, and the game's own MeleeController:strike, both bail out unless
-- getHeldItemInfo().Melee is true. Anything that changes the active slot - the adrenaline
-- auto-use above all - therefore silently switches off every attack you have. This puts
-- the sword back and is the difference between a farm that fights and one that jogs.
-- Count what is in the bag so gold stops being farmed once you are stocked.
local function countItem(itemType)
	local st = state()
	local contents = st and st.Inventory and st.Inventory.Contents
	if not contents then
		return 0
	end
	local n = 0
	for _, v in pairs(contents) do
		if type(v) == "table" then
			local it = v.ItemType or v.Type or (v.Item and v.Item.ItemType)
			if it == itemType then
				n = n + (tonumber(v.Quantity) or tonumber(v.Amount) or 1)
			end
		end
	end
	return n
end

local function ensureMeleeHeld()
	local hot = resolve("845")
	if not hot then
		return
	end
	local ok, info = pcall(function()
		return hot:getHeldItemInfo()
	end)
	if ok and info and info.Melee then
		return
	end
	local st = state()
	local contents = st and st.Inventory and st.Inventory.Contents
	if not contents then
		return
	end
	for k, v in pairs(contents) do
		if type(v) == "table" then
			local it = v.ItemType or v.Type or (v.Item and v.Item.ItemType)
			if type(it) == "string" and string.find(it, "Sword") then
				local slot = v.SlotId or v.Slot or v.slotId or (type(k) == "number" and k or nil)
				if slot then
					-- This said "hat", a one letter typo for the controller resolved above.
					-- hat is a nil global, the pcall ate the error, and so the sword was never
					-- actually put back: one adrenaline drink switched off every attack for the
					-- rest of the round and the bot just jogged around holding a potion.
					local okSet, setErr = pcall(function()
						hot:setActiveSlot(slot)
					end)
					if not okSet then
						setBuyError("melee guard: " .. tostring(setErr))
					end
				end
				return
			end
		end
	end
end

-- Farm the currency the next thing you actually want is priced in. Collecting iron while
-- the sword still needs bronze is the exact failure this replaces.
K.ensureMelee = ensureMeleeHeld

local function retuneCoinTypes()
	if not cfg.autoBuy then
		return
	end
	local want = { TierOne = false, TierTwo = false, TierThree = false, TierFour = false }

	local swordNext = nextUpgrade("Sword")
	if cfg.buySword and swordNext then
		want[swordNext.CurrencyType] = true
	end
	if cfg.buyArmour then
		local armourNext = nextUpgrade("Armour")
		if armourNext then
			want[armourNext.CurrencyType] = true
		end
	end
	if cfg.buyAdrenaline and countItem("Adrenaline") < cfg.adrenKeep then
		want.TierThree = true
	end
	local st = state()
	local ups = st and st.TeamUpgrades or {}
	-- Triumph stops at one or two em. His rule: "while detect only have 1-2 em, it will
	-- stop buying turm buff, as that it need to start buying only vam buff only".
	-- Vampyrism keeps the bot alive through the last fight; Triumph does not decide it.
	local lateGame = K.emEndgame()
	local wantShard = (cfg.buyTriumph and not lateGame and (ups.Triumph or 0) < 3)
		or (cfg.buyVamp and (ups.Lifesteal or 0) < 3)
	-- Shards are one bot's job and nobody else's - but "one bot" means one of the bots in this
	-- round, not whoever holds the letter A. See refreshRoster for why that distinction cost a
	-- whole match of team upgrades.
	if cfg.teamOn and not TEAM.prime then
		wantShard = false
	end
	want.TierFour = wantShard and true or false

	-- coinAutoOffDone was being written by the coin buttons and then never read by anyone,
	-- so the comment there ("never auto-off it again") was not true of the code: this ran
	-- every Heartbeat and overwrote the choice within a frame. With AUTO BUY on, all four
	-- coin buttons on the COIN TEST panel were effectively dead - press one, nothing sticks.
	-- A hand pressed ON now wins until it is pressed OFF again.
	cfg.types.BronzeCoin = true
	-- Iron is the sword line, so it is always on, not only when the shop happens to want a
	-- TierTwo item this frame. That gate is what switched it off between purchases.
	cfg.types.IronCoin = true
	-- Gold stays off unless he turns it on by hand. AUTO BUY used to switch it back on
	-- every frame the shop wanted a TierThree item, which is why setting it off never stuck.
	cfg.types.GoldCoin = false
	cfg.types.Shard = want.TierFour or coinAutoOffDone.Shard or false
end

local function buyPass()
	local c, cerr = getCtrl()
	if not c then
		setBuyError(cerr or "no shop controller")
		return
	end
	local s = getShop()
	if not s then
		setBuyError("no game-shop module")
		return
	end
	setBuyError(nil)

	local swordNext, swordGrp = nextUpgrade("Sword")

	if cfg.buySword and swordNext and swordGrp then
		if have(swordNext.CurrencyType) >= swordNext.Price then
			fireAndConfirm(swordNext.CurrencyType, swordNext.Price, swordNext.ItemType, function()
				c:purchaseItemUpgrade(s.ShopType.Blacksmith, swordGrp.ItemIndex)
			end)
			return
		end
	end

	-- Surplus rule: gold buys nothing except consumables and the top chestplate. Once the
	-- next armour tier is the gold one and you are sitting on the gold anyway, take it -
	-- that is 30 gold turned into the best armour in the game instead of dead currency.
	do
		local armourNext, armourGrp = nextUpgrade("Armour")
		if armourNext and armourGrp and armourNext.CurrencyType == "TierThree" then
			if have("TierThree") >= armourNext.Price then
				fireAndConfirm("TierThree", armourNext.Price, armourNext.ItemType .. " (surplus gold)", function()
					c:purchaseItemUpgrade(s.ShopType.Blacksmith, armourGrp.ItemIndex)
				end)
				return
			end
		end
	end

	-- Armour is deliberately gated: nothing is spent on it until the sword is maxed.
	if cfg.buyArmour and not swordNext then
		local armourNext, armourGrp = nextUpgrade("Armour")
		if armourNext and armourGrp and have(armourNext.CurrencyType) >= armourNext.Price then
			fireAndConfirm(armourNext.CurrencyType, armourNext.Price, armourNext.ItemType, function()
				c:purchaseItemUpgrade(s.ShopType.Blacksmith, armourGrp.ItemIndex)
			end)
			return
		end
	end

	-- Order the two team upgrades by what the current headcount is worth, rather than always
	-- buying Triumph first. Both still get bought; this only decides which one the next shards
	-- go on, and that is the difference between healing on a kill you are about to get and
	-- healing off damage you are already dealing.
	local vampFirst = preferVamp()
	if cfg.buyVamp and vampFirst then
		local tier = vampTier()
		if tier < 3 then
			local price = K.TEAM_TIER_PRICE[tier + 1]
			if have("TierFour") >= price then
				fireAndConfirm("TierFour", price, "Vampyrism " .. (tier + 1), function()
					c:purchaseTeamUpgrade(s.ShopType.Merchant, K.VAMPYRISM_INDEX)
				end)
				return
			end
		end
	end

	if cfg.buyTriumph and not vampFirst and not K.emEndgame() then
		local st = state()
		local tier = (st and st.TeamUpgrades and st.TeamUpgrades.Triumph) or 0
		if tier < 3 then
			local price = K.TEAM_TIER_PRICE[tier + 1]
			if have("TierFour") >= price then
				fireAndConfirm("TierFour", price, "Triumph " .. (tier + 1), function()
					c:purchaseTeamUpgrade(s.ShopType.Merchant, K.TRIUMPH_INDEX)
				end)
				return
			end
		end
	end

	-- Whichever line was not preferred still gets bought once the preferred one is maxed, so
	-- shards are never left unspent just because of the crossover rule.
	do
		local id = vampFirst and K.TRIUMPH_INDEX or K.VAMPYRISM_INDEX
		local key = vampFirst and "Triumph" or K.VAMPYRISM_STATE_KEY
		local wanted = vampFirst and cfg.buyTriumph or cfg.buyVamp
		local st2 = state()
		local tier2 = (st2 and st2.TeamUpgrades and st2.TeamUpgrades[key]) or 0
		if wanted and tier2 < 3 then
			local price2 = K.TEAM_TIER_PRICE[tier2 + 1]
			if have("TierFour") >= price2 then
				fireAndConfirm("TierFour", price2, key .. " " .. (tier2 + 1), function()
					c:purchaseTeamUpgrade(s.ShopType.Merchant, id)
				end)
				return
			end
		end
	end

	if cfg.buyAdrenaline and countItem("Adrenaline") < cfg.adrenKeep then
		if have("TierThree") >= K.ADRENALINE_PRICE then
			local got = fireAndConfirm("TierThree", K.ADRENALINE_PRICE, "Adrenaline", function()
				c:purchaseItem(s.ShopType.Blacksmith, K.ADRENALINE_INDEX)
			end)
			if got then
				stats.adrenBought = stats.adrenBought + 1
			end
			return
		end
	end

	-- One trigger only: health under 50. Adrenaline is 30 shield, a 10% speed boost and
	-- 30 seconds, so it is worth drinking exactly when you are already hurt - and never
	-- while you are at full health, where it would just burn the 15 second cooldown.
	if cfg.adrenAutoUse then
		local hp = lp:GetAttribute("Health")
		if hp and hp < cfg.adrenAtHealth then
			useAdrenaline()
		end
	end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshRayFilter()
	local chars = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(chars, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = chars
end

-- Cheap enough to call every frame: the Eggs folder never holds more than four models.
local function eggsLeft()
	local folder = workspace:FindFirstChild("Eggs")
	if not folder then
		return 0
	end
	local myTeam = lp:GetAttribute("TeamId")
	-- If TeamId has not replicated yet, "not myTeam" used to make every egg on the map count
	-- as an enemy egg - including our own. eggPass then reported work to do forever, tpPass
	-- returned early every time, and the bot sat under its own egg while enemies walked past
	-- untouched. That is the "it goes AFK after the eggs and never attacks anyone" report.
	-- Unknown team means wait, not attack everything.
	if not myTeam then
		return 0
	end
	local n = 0
	for _, m in ipairs(folder:GetChildren()) do
		local hp = m:GetAttribute("Health")
		if hp and hp > 0 and m:GetAttribute("TeamId") ~= myTeam then
			n = n + 1
		end
	end
	return n
end

-- `ignore` is the pickup we are on our way to. Without it this probe answers
-- "there is ground here" for EVERY coin on the map, including the ones hanging
-- over the void: the probe starts three studs above the coin, casts down, and the
-- first thing it meets is that coin's own Hitbox. rayParams excludes player
-- characters and nothing else, so the coin is very much visible to the ray. The
-- ground check on the three coin paths was therefore doing nothing at all, which
-- is the half of the void fix that mattered most - the round dumps show the bot
-- driving COIN at the moment it died.
--
-- Every OTHER pickup is the same hazard, and they are identifiable by name rather
-- than by guessing: the handoff has it verified that a pickup Model holds exactly
-- one Part called Hitbox, and its purely visual twin holds a MeshPart called
-- Handle. Neither is something a character can stand on.
local function groundBelow(pos, ignore)
	local from = pos
	for _ = 1, 5 do
		local hit = workspace:Raycast(from, Vector3.new(0, -400, 0), rayParams)
		if not hit then
			return 999
		end
		local n = hit.Instance.Name
		if not (n == "Hitbox" or n == "Handle"
			or (ignore and hit.Instance:IsDescendantOf(ignore))) then
			-- Measured from the ORIGINAL probe point, not from where this
			-- iteration happened to restart.
			return pos.Y - hit.Position.Y
		end
		from = Vector3.new(from.X, hit.Position.Y - 0.5, from.Z)
	end
	-- Five pickups stacked and still no floor: treat it as empty air. Refusing
	-- the teleport is the safe direction when the answer is unclear.
	return 999
end

-- Nothing in AUTO TP ever asked whether the spot it was about to stand on had any
-- ground under it. The destination is "tpRange studs behind him", and behind a man
-- standing at the lip of a spawn platform or a bridge is open air, so the bot put
-- itself over the void and fell. That is the death that kept getting read as a kill:
-- the corpse icon says void, health was full, and nothing ever touched us.
--
-- The target is not automatically safe either. Someone who stepped off an edge half
-- a second ago is still above K.VOID_Y and still passes every existing filter, so
-- following him was diving in after him.
--
-- Order matters: keep the ideal spot if it is solid, otherwise swing around him at
-- the same distance, then pull in closer, then settle for his own feet. Returns nil
-- when even he has nothing underneath, which is the signal to leave him alone.
function K.safeDest(around, want, ignore)
	if groundBelow(want + K.TP_PROBE_UP, ignore) < K.GROUND_MISS then
		return want
	end
	local off = want - around
	local flat = Vector3.new(off.X, 0, off.Z)
	local dist = flat.Magnitude
	if dist > 0.01 then
		flat = flat.Unit
		for _, turn in ipairs(K.TP_TURNS) do
			local dir = CFrame.Angles(0, math.rad(turn), 0) * flat
			for _, scale in ipairs(K.TP_SHRINK) do
				local try = around + dir * (dist * scale)
				if groundBelow(try + K.TP_PROBE_UP, ignore) < K.GROUND_MISS then
					return try
				end
			end
		end
	end
	if groundBelow(around + K.TP_PROBE_UP, ignore) < K.GROUND_MISS then
		return around
	end
	return nil
end

-- Every teleport in this file goes through here, and nothing writes HumanoidRootPart.CFrame
-- directly any more.
--
-- Why: on 2026-08-11 at 02:27 two bots were kicked with the server's own message
-- "Unexpected behaviour, code 10449" - read out of the Roblox client log, not guessed. The
-- string is nowhere in the 987 client scripts, so the check is server side and its threshold
-- cannot be read. What it was being handed is not in doubt: the sweep wrote a brand new
-- CFrame up to 335 studs away on every Heartbeat, zeroed the velocity in the same frame, and
-- did it thousands of times a round. A body that moves 335 studs while reporting no velocity
-- is the single most obvious thing a movement check can look for.
--
-- So the jump is broken into hops no longer than HOP_MAX, one per Heartbeat, and the velocity
-- is left alone on the way and only zeroed on arrival. The path is the same, the destination
-- is the same, and no single replicated step is one a fast player could not have made.
-- 24 studs a step and never more than MAX_HOPS steps for one move.
--
-- The first version had only the studs cap and it strangled the farm. Measured on
-- BOT A at 04:12 on 2026-08-11: the auto backoff had walked HOP_MAX down to its floor
-- of 6, hopSteps was 57299, moved-in-4-seconds was 0.00, and the farm's own watchdog was
-- printing "SWEEP FROZEN - AUTO TP on with targets but no cycle completed in 20s" and
-- "NOT MOVING for 25s while COIN, targets 5, eggs 0". At 6 studs a Heartbeat a 335 stud trip
-- costs 56 frames, and a sweep that visits several targets and their coins can no longer
-- finish a single cycle. The bots were not idle - they were crawling, and from outside that
-- is exactly what AFK looks like.
--
-- So the cap is now on TIME as well as distance: at most MAX_HOPS frames per move, and if the
-- distance needs more than that the step grows to cover it. A 335 stud trip is 8 frames of
-- about 42 studs instead of one instant 335 stud jump - still nothing like the original, and
-- fast enough that a cycle completes.
-- Faster, on his call. 2026-08-14: the auto tp all thigns ti was shoudl be very fast adn
-- fast to can abel to kill player in fast as we alreayd fixed about been kciked this shit.
--
-- What this number does: a move longer than HOP_MAX is split into steps of HOP_MAX each,
-- one per frame, up to MAX_HOPS of them. At 24 a 100 stud move took 5 frames; at 40 it takes
-- 3. That is the whole of the delay he is asking about - the bot is not thinking, it is
-- walking there in instalments.
--
-- Why it was 24: a single jump of the full distance produced "Unexpected behaviour, code
-- 10449" from the server on 2026-08-11, and the instalments are what stopped that. Raising
-- the instalment size moves back toward the shape the server complained about, so the
-- adaptive step-down underneath is left exactly as it was - if a run is cut off mid match
-- the cap drops by 4 on the next load and keeps dropping to HOP_FLOOR. It gets faster by
-- default and slows itself down only if the server actually objects.
K.HOP_MAX = 40
K.HOP_FLOOR = 16
K.MAX_HOPS = 8
K.hopSteps = 0
K.hopNote = "hop cap 40 studs, max 8 frames"

-- freeze is for the anti-void rescue and nothing else. A normal hop leaves velocity alone on
-- the way, which is what makes it look like running; a rescue hop is climbing out of a fall,
-- so gravity has to be cancelled at every step or the lerp spends the whole climb fighting a
-- body that is still accelerating downwards.
-- One mover at a time.
--
-- Measured on BOT A at 04:20 on 2026-08-11: hopSteps rose by 2649 in eight seconds -
-- about 330 a second, five times the Heartbeat rate - while the body moved 0.0 studs. That is
-- not one glide, it is four or five of them at once. The coin pass, the TP sweep, the egg
-- phase and the anti-void catch all move the same HumanoidRootPart, and before hopping existed
-- each of them won its frame outright with a single CFrame write. Now that a move spans several
-- frames they interleave, every frame yanks the character somewhere different, and the net
-- travel is nothing. From outside that is a bot standing still doing nothing.
--
-- So the character has an owner for the duration of a move. A second caller waits briefly for
-- the first to finish; if it is still busy after that it takes the jump in one step rather than
-- starting a glide that would fight the one already running.
K.hopBusy = false

function K.hop(root, goal, freeze)
	if not root or not root.Parent then
		return false
	end
	-- NOTHING MAY BE PLACED UNDER THE VOID LINE. One clamp, at the one door every mover
	-- in this file goes through.
	--
	-- His rule, 2026-08-20: "all bot was making something so it wont allow to jump inot
	-- void". Measured the same night: a bot went -31.5 -> -57 -> -85.8 -> -135.3 at up to
	-- 112 studs a second and died, while EWAntiVoidFloor was sitting right there - a 240
	-- thick part whose top face is at -67. It did not stop anything, and it cannot: this
	-- file writes HumanoidRootPart.CFrame every frame, and a character being CFramed does
	-- not collide with a part. The floor and the catch both act after the fall has
	-- started. This acts before it, and it covers every mover at once - eggs, players,
	-- coins, the sticky chase, the anti-void catch itself.
	if goal and goal.Position.Y < K.SAFE_Y then
		goal = goal + Vector3.new(0, K.SAFE_Y - goal.Position.Y, 0)
		K.hopClamped = (K.hopClamped or 0) + 1
	end
	if K.hopBusy then
		-- Real seconds, not frames times a guess. This counted 0.016 per Heartbeat, which
		-- is only true at 60 fps, and these three clients do not run at 60: measured
		-- 2026-08-14 they were at 9.6, 15.9 and 19.4 fps against the leader's 106.9. At 20
		-- fps the half second above was really a second and a half; at 7 fps, which
		-- PERF-FLOOR.lua:6-7 measured as the median for the first two seconds of InGame,
		-- it was four and a half.
		--
		-- That mattered for more than the delay. When this wait runs out the fallback three
		-- lines down writes the whole distance in one step, and a one-shot jump of that size
		-- is exactly what the comment at 1984 records as producing "Unexpected behaviour,
		-- code 10449" on 2026-08-11. A wait that expired three times too early was firing
		-- the one move in this file that gets him kicked.
		local until_t = os.clock() + 0.5
		while K.hopBusy and os.clock() < until_t do
			RunService.Heartbeat:Wait()
		end
		if K.hopBusy then
			root.CFrame = goal
			root.AssemblyLinearVelocity = Vector3.zero
			K.hopSteps = (K.hopSteps or 0) + 1
			return true
		end
	end
	K.hopBusy = true
	local from = root.CFrame.Position
	local to = goal.Position
	local gap = (to - from).Magnitude
	local rot = goal - to
	if gap <= K.HOP_MAX then
		root.CFrame = goal
		root.AssemblyLinearVelocity = Vector3.zero
		K.hopBusy = false
		return true
	end
	local steps = math.min(K.MAX_HOPS, math.ceil(gap / K.HOP_MAX))
	for i = 1, steps - 1 do
		if not root.Parent or not alive or getgenv().__EWCOIN_GEN ~= MY_GEN then
			K.hopBusy = false
			return false
		end
		root.CFrame = CFrame.new(from:Lerp(to, i / steps)) * rot
		if freeze then
			root.AssemblyLinearVelocity = Vector3.zero
		end
		K.hopSteps = K.hopSteps + 1
		RunService.Heartbeat:Wait()
	end
	if not root.Parent then
		K.hopBusy = false
		return false
	end
	root.CFrame = goal
	root.AssemblyLinearVelocity = Vector3.zero
	K.hopSteps = K.hopSteps + 1
	K.hopBusy = false
	return true
end

-- The self-healing half. A kicked client cannot write anything down - it is gone - so the
-- evidence has to be left BEFORE the kick and read on the way back in. This writes the hop
-- cap and the match state every few seconds; on the next load, a file that says "InGame"
-- from less than a minute ago means the last run did not end, it was ended, and the cap
-- comes down four studs. A round that finishes normally writes Ended and costs nothing.
do (function()
	-- WAS THIS CLIENT KICKED. His question, 2026-08-14: is that able to detect is the bot was
-- bee kicked.
--
-- Yes, but only while it is happening. GuiService:GetErrorCode() returns an
-- Enum.ConnectionError and it reads OK (0) the whole time nothing is wrong. The codes were
-- read off his own live client rather than looked up: DisconnectLuaKick = 267 is the server
-- or its anticheat throwing you out, which is the "Unexpected behaviour, code 10449"
-- family. DisconnectEvicted = 273, DisconnectConnectionLost = 277, DisconnectIdle = 278,
-- DisconnectRaknetErrors = 279, ServerShutdown = 288.
--
-- After the kick lands there is nothing to detect with - the Luau VM is gone. This file
-- already says so twice, at 1983 and 2033. So the evidence is written the moment the code
-- changes and read on the way back in, the same pattern tp_guard uses.
--
-- Why it matters for the relaunch: the watchdog does not watch for kicks at all, it watches
-- the leader's roll call, so a kicked bot only ever showed up as sixty seconds of silence.
local GuiSvc = game:GetService("GuiService")
K.KICK_FILE = "RobloxComm/kicked_" .. lp.Name .. ".txt"
K.KICK_NEED = "RobloxComm/need_relaunch.txt"

-- Only the two that mean this client is not coming back on its own. Connection lost and
-- raknet errors are what Roblox's own reconnect handles, and asking for a relaunch on those
-- would rebuild all four clients for a blip.
local KICK_HARD = {
	[267] = "kicked by the server (LuaKick)",
	[273] = "evicted",
}

local kickReported = false

-- Hop back to skywars instead of ending the client.
--
-- His rule, 2026-08-14: "i told u to mkae it hop sever u mkae ti jsut clsoe clinet?"
-- Until now a hard kick wrote need_relaunch.txt and the watchdog killed all four clients
-- and started them again. That throws away three healthy clients to recover one, and it
-- takes fifteen seconds plus a full reload. A teleport back to the lobby costs neither.
--
-- Teleport(K.LOBBY_HOP, lp) is the same call the panel's own lobby route uses, measured six
-- fires and six arrivals on 2026-08-05. queue_on_teleport is already armed at the top of
-- this file, so the script comes back by itself on the other side.
--
-- The relaunch ask stays as the fallback underneath: if the VM is already gone the hop
-- never fires, and something still has to notice.
K.LOBBY_HOP = 8542259458
local hopFired = false

-- THE LAST GATE. Nothing leaves a live round while the team is standing in it.
--
-- This sits on the action instead of on the reason, and that is the point. Every way out of
-- a server goes through this one function, so a guard here cannot be bypassed by the next
-- detector I get wrong - and I got one wrong today: the left-behind watcher read a stale
-- leader_where.txt line at 21:1x and pulled the whole team out of a healthy round.
--
-- The rule in one line: if the leader is standing in this server with me, I am not lost.
-- A kick is the exception - it is not a decision, it has already happened, and the hop is
-- the recovery.
-- The leader's name is not written down here any more. It is K.leaderName(), which reads
-- RobloxComm/leader_name.txt, because the account changed on 2026-08-20 and will change
-- again. An empty answer means nobody has published one yet, and empty blocks nothing.

local function hopBlocked(why)
	-- A kick, an eviction or a failed teleport is never blocked.
	local w = tostring(why):lower()
	if w:find("kick") or w:find("evict") or w:find("teleportinitfailed") then
		return nil
	end
	local Players = game:GetService("Players")
	local me = Players.LocalPlayer
	-- On the leader this file is a passenger. LEADER.lua owns every server move that client
	-- makes - the party, the queue, the ride back to the lobby - and two systems teleporting
	-- one client is how the party host wanders out of a live round. A kick is still a hop:
	-- that case returned above, before this one.
	if me and me.Name == K.leaderName() then
		return "LEADER.lua owns the hop on this client"
	end
	if Players:FindFirstChild(K.leaderName()) then
		return "the leader is in this server with me"
	end
	-- Do not walk out of a round that is still ours to win. His order, 2026-08-20: "it
	-- was msut stahyin to done killing all while the bots or the last bot was still
	-- alive at the game". A kick already returned at the top of this function, so this
	-- only holds the voluntary exits - the watchers, the timers, the left behind
	-- detector. The round ends because the last enemy fell, not because a clock said so.
	if K.roundLive and K.roundLive() then
		-- mineOthers, not mine. mine counts ME, so a bot standing alone in a finished
		-- server always satisfied mine > 0 and could never be released while any enemy
		-- was alive - it was pinned there until it died while the rest of the team was
		-- somewhere else entirely.
		local mine, mineOthers, enemy = 0, 0, 0
		for _, p in ipairs(Players:GetPlayers()) do
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			local up = hum ~= nil and hum.Health > 0 and p:GetAttribute("Alive") ~= false
			if p == me or isOwner(p) or K.isBot(p) then
				if up then
					mine = mine + 1
					if p ~= me then
						mineOthers = mineOthers + 1
					end
				end
			elseif up then
				enemy = enemy + 1
			end
		end
		if mineOthers > 0 and enemy > 0 then
			return string.format("round not finished - %d of ours up, %d enemies alive", mine, enemy)
		end
	end
	return nil
end

local function hopToLobby(why)
	if hopFired then
		return false
	end
	local blocked = hopBlocked(why)
	if blocked then
		pcall(appendfile, "RobloxComm/hop_log.txt", string.format(
			"%d %s REFUSED hop (%s) - %s\n", os.time(),
			tostring(game:GetService("Players").LocalPlayer
				and game:GetService("Players").LocalPlayer.Name),
			tostring(why), blocked))
		return false
	end
	hopFired = true
	local me = game:GetService("Players").LocalPlayer
	local ok, err = pcall(function()
		game:GetService("TeleportService"):Teleport(K.LOBBY_HOP, me)
	end)
	pcall(appendfile, "RobloxComm/hop_log.txt", string.format(
		"%d %s %s hop to lobby %s%s\n", os.time(), tostring(me and me.Name), tostring(why),
		ok and "fired" or "FAILED ", ok and "" or tostring(err)))
	return ok
end

-- FOLLOW THE BOARD. Every client writes where it is standing; this reads the other three
-- and acts on the one case that matters.
--
-- Measured 2026-08-20 04:08 while he was shouting about exactly this. The board said:
--
--   BOT A  place 8951451142  job c077e16f  alive=false
--   BOT B    place 8951451142  job c077e16f  alive=false
--   BOT C      place 8542259458  job 4132ac4d  alive=true
--   the leader          place 8542259458  job 4132ac4d  alive=true   LEADER
--
-- Two bots stranded in a finished server while the leader stood in the lobby asking for a
-- roll call and writing "only 1 of 3, missing A,B" every forty seconds. All four were
-- writing the board correctly and not one of them was reading it: I built the sensor and
-- never wired the action. His words - "why the 2 bot was dindt have a look at the sync? it
-- should be knowing the others bot was at the lobby thne back lobby bro".
--
-- This is NOT the round cycle going through the lobby, which he banned an hour earlier. A
-- bot sitting in a server the leader has left is the stranded case, and the stranded case
-- is the one job the lobby has. hopBlocked still has the last word: while any of ours is
-- standing and an enemy is alive it refuses, so a live round is never abandoned.
K.FOLLOW_HOLD = 10
task.spawn(function()
	pcall(setthreadidentity, 8)
	while getgenv().__EWCOIN_K == K do
		task.wait(5)
		local ok = pcall(function()
			if K.iAmLeaderClient() then
				K.strandedFor = 0
				return
			end
			local boss
			for _, w in pairs(K.whereAll()) do
				if w.leader and w.age <= 12 then
					boss = w
				end
			end
			-- Only a bot left behind in a MATCH is stranded. In the lobby the four of us
			-- are almost never in the same instance and that is normal - what brings us
			-- together there is the party invite, not the jobId. Without this gate the
			-- test fired in the lobby, hopped the bot into another RANDOM lobby instance,
			-- cured nothing, and re-armed itself - a loop that fed on its own output and
			-- kept every bot bouncing between lobbies instead of queueing.
			if boss and boss.job ~= tostring(game.JobId)
				and game.PlaceId == K.MATCH_PLACE then
				K.strandedFor = (K.strandedFor or 0) + 5
				K.followNote = string.format("leader is in %s, I am in %s - %ds", tostring(boss.job):sub(1, 8), tostring(game.JobId):sub(1, 8), K.strandedFor)
				if K.strandedFor >= K.FOLLOW_HOLD then
					K.strandedFor = 0
					loud("board", "the leader is in another server - going to the lobby to rejoin")
					hopToLobby("the leader is in another server - following the board")
				end
			else
				K.strandedFor = 0
				K.followNote = nil
			end
		end)
		if not ok then
			task.wait(3)
		end
	end
end)

-- Published so the far end of this file can reach it.
--
-- Measured on the live bot 2026-08-14 21:36: the left-behind watcher threw
-- ":7832: attempt to call a nil value" on the line that calls hopToLobby. This file is
-- 7000+ lines and the watcher sits at the bottom, far past the point where that local is
-- still in register - Luau keeps only 200 locals live per function and this chunk is well
-- over it, so a name defined at 2291 is simply not there at 7259. A getgenv handle does not
-- care how far away it is called from.
getgenv().__HOP_TO_LOBBY = hopToLobby

-- A teleport that never lands leaves the client on a loading screen with nothing running.
-- Same answer: go to the lobby rather than sit there.
-- IsTeleporting is not a failure. It means a teleport is ALREADY running, which is what
-- the farm does at the end of every round, and answering it with a second teleport is how
-- BOT B fired six hops into one round change at 18:26:26 on 2026-08-14.
pcall(function()
	game:GetService("TeleportService").TeleportInitFailed:Connect(function(_, result, msg)
		if result == Enum.TeleportResult.IsTeleporting then
			return
		end
		hopFired = false
		hopToLobby("TeleportInitFailed " .. tostring(result) .. " " .. tostring(msg))
	end)
end)

local function onKickCode(code)
	if kickReported or not code or code == Enum.ConnectionError.OK then
		return
	end
	kickReported = true
	local v = code.Value
	-- The board first, then the file. When one of them is thrown out the other three
	-- have to see it at the first opportunity, not at the next roll call.
	K.whereWrite(os.time())
	pcall(writefile, K.KICK_FILE, string.format("%d %s %s value=%d job=%s",
		os.time(), lp.Name, tostring(code.Name), v, tostring(game.JobId)))

	-- Only a real kick, never a normal round change.
	--
	-- Measured 2026-08-14 18:26: code 285 DisconnectClientRequest is the CLIENT asking to
	-- leave, which is exactly what the farm's own end-of-round teleport looks like. Hopping
	-- on it sent all three accounts to the lobby in the middle of a working round. KICK_HARD
	-- already holds the only two codes that mean somebody threw us out - 267 LuaKick and
	-- 273 Evicted - so the hop uses that same list.
	if KICK_HARD[v] then
		-- Leave the note before the teleport, because the teleport ends this VM.
		pcall(writefile, "RobloxComm/invite_back_" .. lp.Name .. ".txt",
			string.format("%d %s [LEADER INVITE ME BACK] %s", os.time(), lp.Name, tostring(code.Name)))
		-- The relaunch ask is the FALLBACK, so it only fires when the hop did not.
		--
		-- It used to fire alongside a working hop, which is the opposite of the point: the bot
		-- put itself back in the lobby within seconds, and the watchdog still killed all four
		-- clients when the round ended because the note was under 180s old. Found by the audit,
		-- 2026-08-14.
		local hopped = hopToLobby(tostring(code.Name))
		if not hopped then
			pcall(writefile, K.KICK_NEED,
				string.format("%d %s %s", os.time(), lp.Name, KICK_HARD[v]))
		end
	end
end

pcall(function()
	GuiSvc.ErrorMessageChanged:Connect(function()
		local ok, code = pcall(function()
			return GuiSvc:GetErrorCode()
		end)
		if ok then
			onKickCode(code)
		end
	end)
end)

-- The signal does not fire on every path out, so the code is sampled as well. Four times a
-- second is cheap and it is the difference between leaving a note and leaving nothing.
task.spawn(function()
	while not kickReported do
		task.wait(0.25)
		local ok, code = pcall(function()
			return GuiSvc:GetErrorCode()
		end)
		if ok then
			onKickCode(code)
		end
	end
end)

local FILE = "RobloxComm/tp_guard_" .. lp.Name .. ".txt"
	pcall(function()
		if not isfolder("RobloxComm") then
			makefolder("RobloxComm")
		end
		if isfile(FILE) then
			local prev = readfile(FILE)
			local when, cap, state = prev:match("^(%d+)%s+(%d+)%s+(%S+)")
			if when and cap and state then
				cap = tonumber(cap)
				if state == "InGame" and os.time() - tonumber(when) < 60 then
					K.HOP_MAX = math.max(K.HOP_FLOOR, cap - 4)
					K.hopNote = string.format("hop cap %d - LAST RUN WAS CUT OFF MID MATCH, stepped down from %d",
						K.HOP_MAX, cap)
					loud("tp", K.hopNote)
				else
					K.HOP_MAX = math.clamp(cap, K.HOP_FLOOR, 40)
					K.hopNote = string.format("hop cap %d - carried over, last run ended clean", K.HOP_MAX)
				end
			end
		end
	end)
	-- setthreadidentity, not claimIdentity: claimIdentity is a local declared 1500 lines below
	-- this point, so up here the name is a nil global and calling it would kill this thread
	-- inside a task.spawn where nothing would ever print. Silent is exactly what this file
	-- must not be.
	task.spawn(function()
		pcall(setthreadidentity, 8)
		while alive and getgenv().__EWCOIN_GEN == MY_GEN do
			pcall(function()
				writefile(FILE, string.format("%d %d %s", os.time(), K.HOP_MAX, tostring(K.gameState)))
			end)
			task.wait(5)
		end
	end)

	-- A rolling breadcrumb trail, and the reason it exists is his reading of the kick rather
	-- than mine: that the bot is being teleported onto a spot the developer watches, and that
	-- the position is what costs the round, not the speed of getting there. The evidence that
	-- makes it worth testing is in the round log - "DIED at y=-999706 vy=-0, 100 hp 0.0s
	-- before". Nothing fell there: velocity zero, full health a moment earlier. The server put
	-- it there. So -999706 is the punishment, and the position the bot was standing on when it
	-- earned it is the thing nobody has written down yet.
	--
	-- One line a second, last 45 kept, rewritten in place. A kicked client cannot flush
	-- anything on the way out, so this has to already be on disk when the kick lands. If the
	-- last coordinates from several kicks turn out to sit on top of each other, that is the
	-- trap and safeDest can be told to refuse it.
	local TRAIL = "RobloxComm/tp_trail_" .. lp.Name .. ".txt"
	task.spawn(function()
		pcall(setthreadidentity, 8)
		local rows = {}
		while alive and getgenv().__EWCOIN_GEN == MY_GEN do
			pcall(function()
				local c = lp.Character
				local r = c and c:FindFirstChild("HumanoidRootPart")
				if r then
					local p = r.Position
					rows[#rows + 1] = string.format("%d %.1f %.1f %.1f %s %s",
						os.time(), p.X, p.Y, p.Z, tostring(K.gameState), tostring(K.tpCurrent or "-"))
					while #rows > 45 do
						table.remove(rows, 1)
					end
					writefile(TRAIL, table.concat(rows, "\n"))
				end
			end)
			task.wait(1)
		end
	end)
end)() end

local function targetRoot(p)
	local c = p.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function isVoidPlayer(p)
	local r = targetRoot(p)
	return r ~= nil and r.Position.Y < K.VOID_Y
end

-- Filled by the tracker: players the game reports as dead or spectating while their
-- character is still standing there and still moving. That is a spoofed state, and it is
-- exactly why an aura skips someone a manual click can still hit - every target filter
-- trusts those attributes. We stop trusting them.
local spoofed = {}
-- declared up here because tpPass reads it for threat priority, long before the
-- tracker section that fills it in.
local track = {}
K.__track = track

-- Charges time-on-target against a flagged player and clears it the moment he actually loses
-- health, so a threat that is being killed is never parked and a threat that cannot be touched
-- stops owning the sweep. It lives here rather than beside K.THREAT_BUDGET at the top of the
-- file because it needs `track`, which is declared on the line above and would be a nil upvalue
-- up there. Keyed on JobId so every new server starts clean.
--
-- `blocked` is charged half a budget on its own because a target the destination solver cannot
-- solve for costs almost no wall clock: safeDest returns nil on the first frame and the sweep
-- breaks out immediately. A man hanging in open air is the case this budget exists for, and on
-- time alone he would never run it out. Two blocked visits park him.
function K.chargeThreat(p, hpBefore, secs, blocked)
	local t = track[p]
	if not t then
		return
	end
	-- The round reset runs before the role check, not after. A flyer who lands loses his role
	-- for a moment and gets it back the next time he takes off - the flag flickers by design,
	-- FLY_AIR_T is 2.5 seconds - and if the reset sat behind the role check his spend would
	-- survive that gap and park him on the strength of a fight that ended a minute ago.
	if t.threatRound ~= tostring(game.JobId) then
		t.threatRound = tostring(game.JobId)
		t.threatSpent = 0
		t.threatDropped = false
		K.threatNote = ""
	end
	if not t.role then
		t.threatSpent = 0
		t.threatDropped = false
		return
	end
	if K.THREAT_RANK[t.role] == 1 then
		return
	end
	local hpAfter = p:GetAttribute("Health")
	if type(hpBefore) == "number" and type(hpAfter) == "number" and hpAfter < hpBefore then
		t.threatSpent = 0
		t.threatDropped = false
		return
	end
	t.threatSpent = (t.threatSpent or 0) + (secs or 0)
	if blocked then
		t.threatSpent = t.threatSpent + K.THREAT_BUDGET * 0.5
	end
	if t.threatSpent >= K.THREAT_BUDGET and not t.threatDropped then
		t.threatDropped = true
		K.threatGaveUp = (K.threatGaveUp or 0) + 1
		K.threatNote = string.format("! park %s %.0fs no dmg",
			tostring(p.Name):sub(1, 12), t.threatSpent)
		K.event(string.format("THREAT BUDGET SPENT - parked %s (%s) after %.1fs and no damage",
			p.Name, tostring(t.role), t.threatSpent))
	end
end

-- One definition of "worth teleporting to", used by AUTO TP and by the anti-void catch.
local function validTarget(p)
	if p == lp or not p.Parent then
		return false
	end
	-- Before anything else, and deliberately not folded into the team test below: the owner
	-- is off limits whatever colour the game happens to have put him on this round.
	-- K.isBot sits here for the same reason and it is NOT already covered by the team test
	-- underneath. That test is skipped whole whenever this client's own TeamId has not
	-- replicated - `myTeam and ...` is false, so every branch falls through - and inside that
	-- window the other three farm accounts are legal targets. Membership of the farm must never
	-- depend on replication, so it is asked here, off the UserId, which is known at load.
	if isOwner(p) or K.isBot(p) then
		return false
	end
	-- A target the threat budget has already given up on this round is not a target any more.
	-- Without this, the last man standing being an unreachable flyer parks the entire farm:
	-- AUTO TP keeps picking him because he is the only name left, every teleport is refused,
	-- and the bot stands still until the round ends. Measured on 2026-08-11 at 02:22 on
	-- BOT A - tpBlocked 31091, "NOT MOVING for 25s while TP, targets 1, eggs 0", and
	-- the timeline showing the same "TP kingof1917 d335" line every two seconds forever.
	-- chargeThreat already decided he was not worth it; this is what makes that decision count.
	local parked = track[p]
	if parked and parked.threatDropped and parked.threatRound == tostring(game.JobId) then
		return false
	end
	-- A man the last visit took nothing off is not a target, he is a kick waiting to
	-- happen. See K.NODMG_SECS.
	local dry = K.noDmg and K.noDmg[p]
	if dry and os.clock() - dry < K.NODMG_SECS then
		return false
	end
	local myTeam = lp:GetAttribute("TeamId")
	if myTeam and p:GetAttribute("TeamId") == myTeam then
		return false
	end
	local r = targetRoot(p)
	if not r or r.Position.Y < K.VOID_Y then
		return false
	end
	if p:GetAttribute("Alive") == false or p:GetAttribute("Spectating") then
		if not spoofed[p] then
			return false
		end
	end
	return true, r
end

local function nearestTarget(from)
	local best, bestRoot, bestDist
	for _, p in ipairs(Players:GetPlayers()) do
		local ok, r = validTarget(p)
		if ok then
			local d = (r.Position - from).Magnitude
			if not bestDist or d < bestDist then
				best, bestRoot, bestDist = p, r, d
			end
		end
	end
	return best, bestRoot, bestDist
end

-- Who is safe to be thrown at when you are already under the line. This is NOT the same
-- question as who is worth attacking, and using nearestTarget for it was a real bug: the
-- nearest valid target while you are falling is very often the corpse you were chasing,
-- still ragdolling downwards a few studs above the line. You land on it, you fall again,
-- it catches you again, and the anti-void spends the rest of the round feeding you back
-- into the void it was supposed to pull you out of. A rescue target has to be standing on
-- something real and be clear of the line, or it is not a rescue.
local function rescueTarget(from)
	local best, bestRoot, bestDist
	for _, p in ipairs(Players:GetPlayers()) do
		local ok, r = validTarget(p)
		if ok and r.Position.Y > K.VOID_Y + 20 and groundBelow(r.Position) < K.GROUND_MISS then
			local d = (r.Position - from).Magnitude
			if not bestDist or d < bestDist then
				best, bestRoot, bestDist = p, r, d
			end
		end
	end
	return best, bestRoot, bestDist
end

local avPart, lastSafe
local avCatches = 0
local avState = "idle"

-- Nothing here is replicated. This part is created on this client only, so no other
-- player and no server script ever sees it - it is yours alone.
K.FLOOR_PHYS = PhysicalProperties.new(1, 0.9, 0, 100, 1)

-- The floor used to be 6 studs thick and that is what let bots fall through it. This client
-- runs in a background window at 130-290 ms a frame, and terminal velocity here is about
-- -311 studs/s, so one frame moves the character up to 90 studs. A 6 stud slab is simply not
-- there any more by the time the next physics step looks. 240 studs cannot be tunnelled at
-- any frame time this machine produces. The TOP of the slab stays exactly where it was, so
-- nothing about where you stand changes - it only grows downwards.
K.FLOOR_THICK = 240
K.FLOOR_TOP_OVER_AVY = 3

-- Same problem from the other side: the catch below only gets one look per frame, so at
-- -311 studs/s it can be handed a character that has already passed -500 and been deleted by
-- FallenPartsDestroyHeight. Capping the fall speed while there is nothing underneath keeps
-- every frame short enough for the catch to stay ahead of it.
K.FALL_CAP = 140

local function destroyFloor()
	if avPart then
		pcall(function()
			avPart:Destroy()
		end)
		avPart = nil
	end
end

-- CanQuery=false is the important bit: the floor still catches you and you can stand and
-- walk on it, but no raycast can see it. Without that every void check on this panel
-- would find "ground" everywhere the moment the floor turned on.
local function ensureFloor()
	if avPart and avPart.Parent then
		return avPart
	end
	local p = Instance.new("Part")
	p.Name = "EWAntiVoidFloor"
	p.Anchored = true
	p.CanCollide = true
	p.CanQuery = false
	p.CanTouch = false
	p.Size = Vector3.new(cfg.avSize, K.FLOOR_THICK, cfg.avSize)
	p.Transparency = 0
	p.Color = Color3.fromRGB(120, 120, 120)
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = 0
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CustomPhysicalProperties = K.FLOOR_PHYS
	p.Parent = workspace
	avPart = p
	return p
end

local function avPass()
	local r = root()
	if not r then
		avState = "no character"
		return
	end
	local pos = r.Position
	if string.find(avError.Text, "no character") then
		avError.Text = ""
	end

	-- The slab is centred this far under avY so that its top face stays at avY + 3, which is
	-- where it has always been. Only the underside moves.
	local centreY = cfg.avY + K.FLOOR_TOP_OVER_AVY - K.FLOOR_THICK / 2

	-- Only in a match. The lobby has its own ground at its own height and a 2048 wide slab
	-- dropped into it does nothing useful, so the script now loads in both places but only
	-- builds the floor where there is a void to fall into.
	if cfg.avFloor and game.PlaceId == K.MATCH_PLACE then
		local p = ensureFloor()
		if p.Size.X ~= cfg.avSize or p.Size.Y ~= K.FLOOR_THICK then
			p.Size = Vector3.new(cfg.avSize, K.FLOOR_THICK, cfg.avSize)
		end
		-- Static by default and centred on the map origin. A floor that teleports under
		-- you every frame is what makes the usual anti-void something you can only land
		-- on; leave it still and you can actually walk around on it.
		local centre = Vector3.new(0, centreY, 0)
		if cfg.avFollow then
			local standing = pos.Y < cfg.avY + 12
			local far = math.abs(pos.X - p.Position.X) > cfg.avSize / 2 - 80
				or math.abs(pos.Z - p.Position.Z) > cfg.avSize / 2 - 80
			if standing and not far then
				centre = Vector3.new(p.Position.X, centreY, p.Position.Z)
			else
				centre = Vector3.new(pos.X, centreY, pos.Z)
			end
		end
		if (p.Position - centre).Magnitude > 0.05 then
			p.CFrame = CFrame.new(centre)
		end
	else
		destroyFloor()
	end

	-- The last spot with genuine map ground under it. The anti-void floor is CanQuery=false
	-- so it never counts as ground here, which is what keeps this an honest "safe" record.
	local below = groundBelow(pos)
	if below < 20 and pos.Y > cfg.avY + 12 then
		lastSafe = pos
		avState = "safe"
	end

	-- Brake before the line, not only at it. Free fall over the void reaches about -311
	-- studs/s; at the 130-290 ms frames this window actually runs at that is 40 to 90 studs
	-- of travel between two looks, and a couple of long frames in a row is enough to pass
	-- -500 and be deleted outright. Capped, the worst case per frame is about 40 studs.
	local vel = r.AssemblyLinearVelocity
	if below >= K.GROUND_MISS and vel.Y < -K.FALL_CAP then
		r.AssemblyLinearVelocity = Vector3.new(vel.X, -K.FALL_CAP, vel.Z)
	end

	-- K.VOID_Y is the line, full stop. The floor used to move this down to below itself,
	-- which is why you could sink past -69 and stay there. You never go under it now.
	local catchY = K.VOID_Y
	if cfg.avCatch and inMatch() and pos.Y < catchY then
		-- Straight up, not across the map.
		--
		-- 2026-08-05: this used to rescue onto the nearest live enemy first, because
		-- that put the bot back into the fight instead of on an empty platform. In one
		-- 56 second round it fired 59 times on one bot and 18 on another - so that is
		-- 59 cross-map jumps landing on top of other players, inside a minute, and the
		-- server sent code 10449 five to eleven seconds into the round. The egg
		-- teleport never ran at all that round (eggsMine stayed 0), so this is the
		-- frequent teleport, not that one.
		--
		-- The order is now reversed. A catch is a short vertical move onto the floor
		-- this script already maintains directly underneath, or onto the last piece of
		-- real ground it stood on. Landing on a player is the last resort, only when
		-- there is no floor and no remembered ground - which should be never, because
		-- the floor always exists.
		local target, how
		target = lastSafe and (lastSafe + Vector3.new(0, 4, 0))
			or Vector3.new(pos.X, cfg.avY + 10, pos.Z)
		how = lastSafe and "last ground" or "floor top"
		if not target then
			local _, tr = rescueTarget(pos)
			if tr then
				target = tr.Position + Vector3.new(0, 4, 0)
				how = "player"
			end
		end
		-- This was the last raw teleport left in the file and it is not a rare one: the panel
		-- read "caught 15" in a single round on 2026-08-11, fifteen instant jumps from under
		-- the map back up to a player. Hopping it too, with freeze on so the climb is not
		-- fought by the fall it is rescuing from.
		K.hop(r, CFrame.new(target), true)
		avCatches = avCatches + 1
		avState = string.format("caught y=%.0f -> %s", pos.Y, how)
		avError.Text = ""
	elseif below >= K.GROUND_MISS and pos.Y > catchY then
		avState = "over void"
	end
end

local tpVisited, tpCycles, tpLastTargets = 0, 0, 0
local tpCurrent = "-"
local tpState = "idle"
local tpCycleMs = 0
local tpStartT, tpKillsBase = 0, 0

local eggVisited, eggCycles, eggAliveCount = 0, 0, 0
local eggCurrent = "-"
local eggState = "idle"
local eggStartT = 0
local eggsBroken = 0
local eggSeen = {}

local function myKills()
	local st = state()
	if st and st.GameStats then
		return st.GameStats.Kills or 0
	end
	return 0
end

local function setTp(on)
	cfg.tpOn = on
	if on then
		tpStartT = os.clock()
		tpKillsBase = myKills()
	end
end

-- Latch, or the "eggs done -> turn AUTO TP on" rule fires every single frame and you can
-- never switch AUTO TP back off by hand: it just comes straight back.
local eggAutoArmed = true

-- When the character actually appeared, recorded at the spawn instead of guessed at later.
--
-- This is kept for the round files and for the panel; it is deliberately NOT what the settle
-- below counts against. Measured across 568 round files, the gap between the character
-- appearing and the round going live has a median of 15.7 seconds - the character has almost
-- always been standing on its island through the whole of Countdown - so counting a two
-- second settle from here would release instantly in 94 percent of rounds and the floor check
-- would never get a vote. K.liveAt, stamped when the server says InGame, is what the settle
-- actually measures.
K.spawnAt = os.clock()
bind(lp.CharacterAdded, function()
	K.spawnAt = os.clock()
	K.lastChar = nil
end)

bind(tpButton.MouseButton1Click, function()
	setTp(not cfg.tpOn)
	if not cfg.tpOn then
		eggAutoArmed = false
	end
end)

bind(eggButton.MouseButton1Click, function()
	cfg.eggOn = not cfg.eggOn
	if cfg.eggOn then
		eggStartT = os.clock()
		eggsBroken = 0
		eggSeen = {}
		eggAutoArmed = true
	end
end)

-- Eggs live in Workspace.Eggs and are never removed when they break, so Health is the
-- only honest test. Never use GetPivot on one: its PrimaryPart sits at the very bottom
-- of the model, about 2.5 studs under the shell you can actually see.
local function aliveEggs()
	local out = {}
	local folder = workspace:FindFirstChild("Eggs")
	if not folder then
		return out
	end
	local myTeam = lp:GetAttribute("TeamId")
	-- Same gate as eggsLeft, and for the same reason: an unknown team must never be read as
	-- "they are all enemies". Returning nothing here lets eggPass report no work, which lets
	-- AUTO TP take over and fight people instead of standing still.
	if not myTeam then
		if not K.warnedNoTeam then
			K.warnedNoTeam = true
			K.event("TeamId not replicated yet - egg phase held")
		end
		return out
	end
	K.warnedNoTeam = false
	for _, m in ipairs(folder:GetChildren()) do
		local hp = m:GetAttribute("Health")
		local team = m:GetAttribute("TeamId")
		local id = m:GetAttribute("EggId")
		if id then
			if hp and hp <= 0 and eggSeen[id] then
				eggsBroken = eggsBroken + 1
				eggSeen[id] = nil
			elseif hp and hp > 0 then
				eggSeen[id] = true
			end
		end
		if hp and hp > 0 and team ~= myTeam then
			local ok, cf, size = pcall(function()
				return m:GetBoundingBox()
			end)
			if ok and cf then
				table.insert(out, { m = m, pos = cf.Position, size = size, hp = hp, id = id, team = team })
			end
		end
	end
	return out
end

-- Team coordination. Both clients run on the same PC and share Real's workspace folder,
-- so a file is a better channel than in-game chat: instant, private, no rate limit and
-- nothing the other team can read. Nobody negotiates either - each bot writes a heartbeat
-- and then sorts the live roster by UserId, so every bot independently reaches the same
-- order and therefore the same split, with no messages and no race to be A.
do (function()
	local function writeHeartbeat()
		pcall(function()
			if not isfolder(TEAM.dir) then
				makefolder(TEAM.dir)
			end
			-- the alive flag matters: a dead bot must stop owning a share of the work
			local amAlive = lp:GetAttribute("Alive") ~= false and lp.Character ~= nil
			writefile(TEAM.dir .. "/" .. lp.Name .. ".txt", string.format("%d|%d|%s|%s", os.time(), lp.UserId, tostring(game.JobId), amAlive and "1" or "0"))
		end)
	end

	local function refreshRoster()
		local known, here = {}, {}
		local okScan, scanErr = pcall(function()
			for _, f in ipairs(listfiles(TEAM.dir)) do
				-- Roblox usernames are alphanumeric plus underscore, so match those directly.
				local nm = string.match(f, "([%w_]+)%.txt$")
				if nm then
					local okR, data = pcall(readfile, f)
					if okR and data then
						local ts, uid, job, liveFlag = string.match(data, "^(%d+)|(%d+)|([^|]*)|?(%d*)$")
						-- Never let an owner account into the roster. He does not run this
						-- script, so he can never do a share of the work, and his UserId is
						-- lower than every bot's - so he would sort to the front and take a
						-- job nobody would then do.
						if ts and uid and not K.OWNERS[tonumber(uid)] then
							local age = os.time() - (tonumber(ts) or 0)
							-- Housekeeping: this folder is never cleaned otherwise and a file
							-- from hours ago still counts towards the identity window.
							if age > 1800 then
								pcall(delfile, f)
							end
							-- Identity is decided across rounds so A is always A. Ten minutes of
							-- slack covers a lobby trip; the split below is what needs same-round.
							if age <= 600 then
								known[#known + 1] = { name = nm, userId = tonumber(uid) }
								-- A corpse must not keep owning eggs or targets, or its share is
								-- simply never done. Roles stay fixed; only the split reacts.
								if job == tostring(game.JobId) and age <= 20 and Players:FindFirstChild(nm) and liveFlag ~= "0" then
									here[#here + 1] = { name = nm, userId = tonumber(uid) }
								end
							end
						end
					end
				end
			end
		end)
		-- A throw halfway down that scan used to leave known and here half filled and be committed
		-- anyway, so the role fell back to A, prime to true and count to 1 - on every client at
		-- once, because listfiles fails for all of them for the same reason. Keeping the roster
		-- from the last good pass is always closer to the truth than collapsing to solo, and the
		-- reason goes on the TEAMMATE panel rather than only into warn.
		if not okScan then
			warn("[panels] team roster scan: " .. tostring(scanErr))
			pcall(function()
				TEAM.err.Text = "! roster scan: " .. tostring(scanErr)
			end)
			return
		end
		local byId = function(a, b)
			return a.userId < b.userId
		end
		table.sort(known, byId)
		table.sort(here, byId)

		TEAM.roster = known
		TEAM.here = here
		TEAM.count = math.max(1, #here)
		TEAM.index = 1
		for i, e in ipairs(here) do
			if e.name == lp.Name then
				TEAM.index = i
				break
			end
		end
		-- Counted, not searched. The old loop started at 1 and only moved if this bot found its
		-- own heartbeat in the list it had just read, so a single tick where that file could not be
		-- read - a write that failed inside its pcall, or a read that landed while another client
		-- was truncating its own - handed this bot the letter the real A was holding at that same
		-- moment, and two clients answering to one letter is one letter. known is sorted by UserId
		-- above, so counting the bots below me gives the same letter whether or not my own entry
		-- made it into this pass.
		local rank = 1
		for _, e in ipairs(known) do
			if e.userId and e.userId < lp.UserId then
				rank = rank + 1
			end
		end
		TEAM.role = TEAM.roles[rank] or tostring(rank)

		-- The single-owner jobs - shards above all - used to be given to "role A". That was
		-- wrong in two ways at once. The role letter is decided over a ten minute window that
		-- deliberately spans rounds, but the job has to be done in THIS round: a bot that is A
		-- and did not make it into this match left nobody collecting shards for the whole game,
		-- and no error anywhere, just no team upgrades. Roles stay stable for identity. The job
		-- goes to whoever is first among the bots actually standing here, right now.
		TEAM.prime = (#here == 0) or (here[1] ~= nil and here[1].name == lp.Name)
	end

	task.spawn(function()
		pcall(setthreadidentity, 8)
		while alive and getgenv().__EWCOIN_GEN == MY_GEN do
			writeHeartbeat()
			local ok, err = pcall(refreshRoster)
			if not ok then
				-- TEAM.err is created further down the file, when the TEAMMATE panel is built,
				-- so for the first moments of a load this label does not exist yet and writing
				-- to it throws inside a pcall that discards the result. That is how a roster
				-- failure becomes completely invisible. The warn is the part that survives.
				warn("[panels] team roster: " .. tostring(err))
				pcall(function()
					TEAM.err.Text = "! " .. tostring(err)
				end)
			end
			task.wait(3)
		end
	end)
end)() end

-- Contiguous split: two bots and four eggs means A takes the first two, B the last two.
-- A bot whose chunk comes out empty falls back to the whole list rather than standing idle.
function TEAM.share(list)
	if not cfg.teamOn or TEAM.count <= 1 then
		return list
	end
	local n = #list
	if n == 0 then
		return list
	end
	local per = math.ceil(n / TEAM.count)
	local first = (TEAM.index - 1) * per + 1
	local out = {}
	for i = first, math.min(n, first + per - 1) do
		out[#out + 1] = list[i]
	end
	if #out == 0 then
		return list
	end
	return out
end

-- ONE COLOUR PER BOT. His order, 2026-08-20: "rmemebr each bot was killing each own colour
-- frist then after odne hit or kill then kill the owned based, then it will will fucking able
-- to no distnace".
--
-- The point is the travel. A bot that breaks the Yellow egg is standing in the Yellow base,
-- and the Yellow players are the ones standing around it - so finishing that colour costs no
-- distance at all. Sending it across the map for whoever happens to be nearest afterwards is
-- the gap he keeps watching.
--
-- Keyed the same way as everything else that has to agree across four clients with no talking:
-- the colours sorted by name, the bots sorted by name, take your own index.
-- Which of the bots this is, 1 2 3, off K.BOTS - the roster that is written into this file
-- and therefore identical on every client from the first frame.
--
-- The first version asked TEAM.here, and TEAM.here is empty during Pregame: every bot read
-- a roster of one, called itself slot 1, and all three took the same colour. Measured at
-- 04:2x - the leader said Cyan and BOT A said Cyan in the same second.
K.mySlot = function()
	local names = {}
	for _, n in pairs(K.BOTS) do
		names[#names + 1] = n
	end
	table.sort(names)
	for i, n in ipairs(names) do
		if n == lp.Name then
			return i, #names
		end
	end
	return 1, math.max(#names, 1)
end

K.myColour = function()
	local now = os.clock()
	if K.__colAt and (now - K.__colAt) < 3 then
		return K.__col
	end
	K.__colAt = now
	local mine = tostring(lp:GetAttribute("TeamId"))
	local seen, cols = {}, {}
	pcall(function()
		local eggsF = workspace:FindFirstChild("Eggs")
		for _, e in ipairs(eggsF and eggsF:GetChildren() or {}) do
			local t = tostring(e:GetAttribute("TeamId"))
			if t ~= mine and t ~= "nil" and not seen[t] then
				seen[t] = true
				cols[#cols + 1] = t
			end
		end
	end)
	if #cols == 0 then
		pcall(function()
			for _, p in ipairs(Players:GetPlayers()) do
				local t = tostring(p:GetAttribute("TeamId"))
				if t ~= mine and t ~= "nil" and not seen[t] then
					seen[t] = true
					cols[#cols + 1] = t
				end
			end
		end)
	end
	if #cols == 0 then
		K.__col = nil
		return nil
	end
	table.sort(cols)
	local slot = K.mySlot()
	K.__col = cols[((slot - 1) % #cols) + 1]
	return K.__col
end

-- EM. His word, coined 2026-08-20: "i need to create a word, it was called {em} as that it
-- was others player mean". An em is an enemy player - not our bots, not the owner, not a
-- teammate. Everything below counts em, never "players".
K.emAlive = function()
	local now = os.clock()
	if K.__emAt and (now - K.__emAt) < 0.5 then
		return K.__emN or 0, K.__emList or {}
	end
	K.__emAt = now
	local n, list = 0, {}
	local myTeam = tostring(lp:GetAttribute("TeamId"))
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= lp and not isOwner(p) and not K.isBot(p) then
			local same = myTeam ~= "nil" and tostring(p:GetAttribute("TeamId")) == myTeam
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			local up = hum ~= nil and hum.Health > 0 and p:GetAttribute("Alive") ~= false
			if not same and up then
				n = n + 1
				list[#list + 1] = p
			end
		end
	end
	K.__emN, K.__emList = n, list
	return n, list
end

-- ENDGAME. His rule, same message: "while detect only 1-2 em, it need to frist was stop all
-- action all bot following that em to kill him frist beucae that was the fastest way to win
-- the game". At one or two em left nothing else is worth a frame - no coins, no Triumph, no
-- splitting by colour. Every bot goes to whoever is left.
K.EM_ENDGAME = 2
K.emEndgame = function()
	local n = K.emAlive()
	return n > 0 and n <= K.EM_ENDGAME
end

-- How many em this round started with, so "most of them are dead" is a measurement and
-- not a feeling. Stamped once per round, the first time this client sees any em at all.
K.emNoteStart = function()
	if K.armRound and K.emStartRound ~= K.armRound then
		local n = K.emAlive()
		if n > 0 then
			K.emStartRound = K.armRound
			K.emAtStart = n
		end
	end
end

K.emMostDead = function()
	if not K.emAtStart or K.emAtStart <= 0 then
		return false
	end
	return K.emAlive() <= K.emAtStart / 2
end


-- Resolve a Flamework controller by its MODULE NAME, not by its hashed id.
--
-- Measured 2026-08-20 07:0x on a live client, the morning the game updated: of the six
-- hashed ids this farm had memorised, only MMv and PrB still resolved. r8A, EPe, z0b and
-- apv were all dead - "Could not find constructor". Those ids are rebuilt by the compiler
-- on every game build, so a hardcoded one is a fuse waiting to blow, and it blows quietly:
-- resolveDependency throws inside a pcall and the feature behind it just stops existing.
--
-- Module names do not change. PlayerScripts.TS.controllers.matchmaking-controller has been
-- called that all along. So find the class by module, read the identifier Flamework itself
-- stamped on it, and resolve that. Read off a live client the same morning:
--   matchmaking-controller MMv   tele-controller mPW   screen-controller lB5
--   camera-controller      VJk   party-controller PrB  lobby-controller  pY0
-- The old hardcoded id stays only as a last resort.
K.ctrl = function(moduleName, fallbackId)
	K.__ctrlCache = K.__ctrlCache or {}
	if K.__ctrlCache[moduleName] ~= nil then
		return K.__ctrlCache[moduleName] or nil
	end
	local got
	pcall(function()
		local core = require(ReplicatedStorage.rbxts_include.node_modules["@flamework"].core.out)
		local folder = lp:FindFirstChild("PlayerScripts")
		folder = folder and folder:FindFirstChild("TS")
		folder = folder and folder:FindFirstChild("controllers")
		local mod = folder and folder:FindFirstChild(moduleName)
		if mod then
			for _, v in pairs(require(mod)) do
				if type(v) == "table" then
					local id = core.Reflect.getMetadata(v, "identifier")
					if id then
						local ok, inst = pcall(function()
							return core.Flamework.resolveDependency(id)
						end)
						if ok and type(inst) == "table" then
							got = inst
							return
						end
					end
				end
			end
		end
		if not got and fallbackId then
			local ok, inst = pcall(function()
				return core.Flamework.resolveDependency(fallbackId)
			end)
			if ok and type(inst) == "table" then
				got = inst
			end
		end
	end)
	K.__ctrlCache[moduleName] = got or false
	return got
end

-- QUEUE KEEPER.
--
-- His line, 2026-08-20: "i just want to fix the farming making sure the farming all 4 bot
-- was killing and winning 24/7".
--
-- What was actually wrong, measured at 07:05 on the live leader the leader: isInQueue() was
-- false, canQueue() was TRUE, and it had sat in the lobby for 585 seconds writing nothing
-- but the party-invite heartbeat. Nothing in the game was refusing us - the farm simply
-- never called joinQueue. Calling it by hand flipped isInQueue to true on the first try.
--
-- So this is the floor under everything else in this file: while we are in the lobby, and
-- the game says we may queue, and we are not queued, queue. Nothing else here is worth a
-- frame if the bots never reach a match.
K.QUEUE_MODE = "EggWarsQuads"
K.queueKeeper = function()
	task.spawn(function()
		getgenv().__QK_GEN = (getgenv().__QK_GEN or 0) + 1
		local mine = getgenv().__QK_GEN
		local said = 0
		while getgenv().__QK_GEN == mine do
			task.wait(5)
			pcall(function()
				if game.PlaceId ~= K.LOBBY_HOP then
					return
				end
				local mm = K.ctrl("matchmaking-controller", "MMv")
				if not mm then
					return
				end
				local inQ = select(2, pcall(function() return mm:isInQueue() end))
				if inQ == true then
					K.qkSince = nil
					return
				end
				local can = select(2, pcall(function() return mm:canQueue() end))
				if can ~= true then
					return
				end
				-- One fire per twenty seconds, no matter what isInQueue says.
				--
				-- Measured 2026-08-20 09:50 on the leader: three joinQueue calls in ten
				-- seconds, 09:50:36, 09:50:41 and 09:50:46, all with waited=0s, and 31 in
				-- half an hour. isInQueue() does not flip the instant joinQueue returns, so
				-- the five second loop kept re-firing into a queue it had already joined.
				-- Asking to queue again while queueing is at best noise and at worst the
				-- thing that keeps resetting the wait.
				if K.qkLast and (os.clock() - K.qkLast) < 20 then
					return
				end
				-- The leader queues at once: it is the party host and the party rides with
				-- it. A bot waits 45 seconds first, so in the normal case the host has
				-- already pulled it in and it never queues alone. That wait is the whole
				-- difference between one match together and four separate matches.
				K.qkSince = K.qkSince or os.clock()
				local waited = os.clock() - K.qkSince
				if not K.iAmLeaderClient() and waited < 45 then
					return
				end
				local ok, err = pcall(function()
					mm:joinQueue(K.QUEUE_MODE)
				end)
				K.qkLast = os.clock()
				K.qkSince = nil
				-- Did it actually take? fired=true only means the call did not throw.
				--
				-- Measured 2026-08-20 12:22 on BOT C: joinQueue returned cleanly, no error,
				-- and isInQueue was still false eight seconds later. The keeper had been
				-- writing fired=true every sixty-five seconds for two hours while the client
				-- was never in a queue at all, so the log read like success and the farm had
				-- not started a round since 10:16:05. A call that cannot fail out loud cannot
				-- be debugged, so this one now checks and says so.
				task.wait(3)
				local took = select(2, pcall(function() return mm:isInQueue() end))
				if took ~= true then
					pcall(appendfile, "RobloxComm/round_log.txt",
						string.format("%s  %-14s queue-keeper: joinQueue(%s) HAD NO EFFECT - isInQueue still %s after 3s\n",
							os.date("%Y-%m-%d %H:%M:%S"), lp.Name, K.QUEUE_MODE, tostring(took)))
				end
				local now = os.clock()
				if ok or (now - said) > 30 then
					said = now
					pcall(appendfile, "RobloxComm/round_log.txt",
						string.format("%s  %-14s queue-keeper: joinQueue(%s) fired=%s waited=%.0fs err=%s\n",
							os.date("%Y-%m-%d %H:%M:%S"), lp.Name, K.QUEUE_MODE,
							tostring(ok), waited, tostring(err)))
				end
			end)
		end
	end)
end

-- Eggs and players share one mover. Two loops both writing HumanoidRootPart.CFrame every
-- frame would fight each other and neither sweep would land where it meant to.
local function eggPass(r)
	local eggs = aliveEggs()
	eggAliveCount = #eggs
	if #eggs == 0 then
		eggState = "no egg left"
		eggCurrent = "-"
		return false
	end

	-- Split on EggId first so both bots carve up the same stable list, then walk your
	-- own share nearest first. A takes the low ids, B the high ones.
	table.sort(eggs, function(a, b)
		return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
	end)
	eggAliveCount = #eggs
	-- ONE BOT, ONE EGG. His correction, 2026-08-20: "it was each bot go to each egg,
	-- there is 3 egg was kill able bro, and nto all 3 bot go to kill one egg that will
	-- cost too much of time". Three shells and three bots is three dying at once; three
	-- bots stacked on one shell is the same total damage stretched over three times the
	-- wall clock, and the wall clock is his first rule.
	--
	-- Worked out here rather than through TEAM.share, because share cuts on TEAM.count
	-- and that count includes the leader - and the leader does not do eggs any more, so
	-- its slot would eat one of the three and leave a real bot with share's fallback,
	-- which is the whole list.
	--
	-- Both keys are stable and read the same on every client in the same instant: the
	-- eggs by EggId (sorted above), the bots by name. So the three of them arrive at
	-- three different shells without needing to agree about anything first.
	-- My colour's shell, so the players I fight next are already standing around me.
	local col = K.myColour()
	local pick
	if col then
		for _, e in ipairs(eggs) do
			if tostring(e.team) == col then
				pick = e
			end
		end
	end
	if not pick then
		-- My colour is already broken, or the board has not settled yet. Fall in behind
		-- whatever is left, by index, so three bots still land on three shells.
		pick = eggs[((K.mySlot() - 1) % #eggs) + 1]
	end
	eggs = { pick }

	for _, e in ipairs(eggs) do
		if not cfg.eggOn or not alive or getgenv().__EWCOIN_GEN ~= MY_GEN then
			break
		end
		if r.Parent and e.m.Parent and (e.m:GetAttribute("Health") or 0) > 0 then
			eggCurrent = string.format("#%s %s %.0fhp", tostring(e.id), tostring(e.team), e.m:GetAttribute("Health") or 0)

			-- Bronze drops from the generator right next to a base, and the egg is at that
			-- base, so the coins worth having in the egg phase are already underfoot. Taking
			-- them here is what pays for the first two sword tiers, which are bronze priced -
			-- waiting until the eggs are done would mean fighting with the starting sword.
			--
			-- The round files do not support that argument. Across the 184 rounds that ended
			-- in 13s or less the median coins collected was 1 and the median purchases was 0,
			-- with 117 of those 184 buying nothing at all - and meanwhile this block walks
			-- every child of workspace once per egg per frame and teleports the character off
			-- the egg for each coin it finds. It is the egg phase that decides the round.
			-- Off by default; EGG-PHASE COINS on the STOP panel turns it back on.
			if cfg.eggGrabCoins and cfg.tpGrabCoins then
				for _, m in ipairs(workspace:GetChildren()) do
					if cfg.types[m.Name] then
						local hb = m:FindFirstChild("Hitbox")
						local spot = hb and hb.Position.Y >= K.VOID_Y
							and (hb.Position - e.pos).Magnitude <= cfg.tpGrabRadius
							and K.safeDest(hb.Position, hb.Position, m) or nil
						if spot then
							K.hop(r, CFrame.new(spot))
							RunService.Heartbeat:Wait()
							stats.visited = stats.visited + 1
							if not m.Parent then
								stats.collected = stats.collected + 1
								stats.byType[m.Name] = (stats.byType[m.Name] or 0) + 1
							end
						end
					end
				end
			end
			-- ABOVE the egg, never under it.
			--
			-- This used to read `e.pos.Y - e.size.Y / 2 - cfg.eggDown`, which put the
			-- character three studs below the bottom of the shell - inside the platform
			-- the egg stands on. The comment that was here said so outright: the point
			-- was to sit somewhere other players could not reach.
			--
			-- That is the destination format Benedict watched get him kicked, twice. It
			-- is also exactly what the old `teleport to egg test` script did: it solved
			-- for a spot with the head UNDER the surface and called it covered. A player
			-- standing inside solid geometry is one of the oldest things a server checks
			-- for, and it does not care how you got there - so the fix is the destination,
			-- not the speed of the move.
			--
			-- On top of the shell instead. It is a place a real player can stand and walk
			-- to, the egg is still adjacent, and nothing is inside anything. The cost is
			-- that the bot is now hittable up there, which is a fair trade against a kick.
					-- Negative means under the egg, not above it.
		--
		-- His test, 2026-08-15: stand below the egg and hit it upwards, five studs down or
		-- more. Until now this only ever computed a spot on top - egg centre, plus half its
		-- height, plus eggUp - so there was no way to ask for underneath at all.
		--
		-- Same number, both directions, so his stepper still drives it: 3 means three studs
		-- above the top face, -5 means five studs below the bottom face. Zero is touching the
		-- top, which is where it has always been.
		-- UNDER, always. 2026-08-20: "make sure ti was tlepeott to down bro, and not top
		-- beucase top was 80% got killed". Standing on the shell is a man on a pedestal in
		-- the middle of somebody else's base.
		--
		-- The distance is not free to pick. The game refuses a hit past 10.35 studs from the
		-- model, and eggUp was -8 with 2.8 studs of shell half height on top of it - 10.8,
		-- just outside. That is why sixteen seconds of camping moved an egg from 64 hp to
		-- 64 hp. Clamped into K.EGG_REACH so the offset he sets can never leave the range.
		local eggHalf = e.size.Y / 2
		local under = math.min(math.abs(cfg.eggUp), math.max(1, K.EGG_REACH - eggHalf))
		local dest = Vector3.new(e.pos.X, e.pos.Y - eggHalf - under, e.pos.Z)
			-- Two frames each, his number. The hammer that used to swing at the other
			-- shells from here is gone: he wants the three of them on ONE egg until it
			-- dies, not damage spread across the field.
			for _ = 1, math.max(2, cfg.eggFrames) do
				K.hop(r, K.faceFlat(r, dest, e.pos))
				K.hitEgg(e.m)
				RunService.Heartbeat:Wait()
			end
			eggVisited = eggVisited + 1
		end
	end
	eggCycles = eggCycles + 1
	-- Eggs first and eggs finished, in that order. 2026-08-20, after the stall watchdog
	-- put both phases on at once: "make sure the meesage done kill egg then go to start
	-- kill the player, and nto fucking telpeot tto egg then kill player that was wrong".
	-- So this stays true while one enemy egg is standing, and the only way out is the egg
	-- actually dying.
	eggState = "sweeping"
	return true
end

-- One pass = one full sweep of every valid enemy on the map, a frame each. Sitting on a
-- single target is wasted time: hitting everyone in rotation spreads damage across the
-- whole lobby at a rate no amount of pressing R by hand can reach.
local function tpPass()
	local r = root()
	if not r then
		tpState = "no character"
		eggState = "no character"
		return
	end
	if lp:GetAttribute("Alive") == false then
		tpState = "dead - waiting"
		eggState = "dead - waiting"
		return
	end
	if belowVoid() then
		tpState = "under the void line - waiting for catch"
		eggState = tpState
		return
	end

	-- One gate for both halves of the pass, because an unknown TeamId poisons both of them.
	--
	-- aliveEggs already refuses to answer without a TeamId and hands back an empty list. eggPass
	-- reads that as "no egg left", eggThenTp latches AUTO TP on, eggAutoArmed goes false and only
	-- a button press puts it back - so a few frames of replication delay skipped the egg phase for
	-- a whole round. The same unknown TeamId makes validTarget skip its team test, so the sweep
	-- that took over was aimed at the entire server, the other three farm accounts included.
	--
	-- The line aliveEggs used to write is kept here, latched the same way, because this gate
	-- returns before aliveEggs is ever reached. A hold with no reason in the round file is a bot
	-- that stood still all night for a cause nobody can reconstruct in the morning.
	if not lp:GetAttribute("TeamId") then
		if K.event and not K.warnedNoTeam then
			K.warnedNoTeam = true
			K.event("TeamId not replicated yet - egg phase held")
		end
		tpState = "TeamId not replicated yet - holding"
		eggState = tpState
		return
	end
	K.warnedNoTeam = false

	-- Wait for a floor, not for a clock.
	--
	-- What the old guard was written to stop is real: a character moved off its island before
	-- the spawn platform under it has loaded falls to the void with health never leaving 100.
	-- But it asked the wrong question. It waited six seconds and then assumed a floor, and the
	-- stamp it counted from landed in the wrong place - this function only runs once
	-- K.roundLive() is true, so the six seconds were counted from the first frame of InGame
	-- every round, no matter how long the character had already been standing still.
	--
	-- Measured across the 471 recorded rounds: of the 318 from before the guard existed, 248
	-- broke an egg inside six seconds and the fastest managed 0.5s. Of the 137 recorded after
	-- it went in, not one broke an egg or picked a target before 6.0s and the fastest was 6.8s.
	-- The floor in the data sits exactly on the guard's own threshold. What it cost is the fast
	-- tail, not the median: in the controlled window either side of the change the median first
	-- egg only moved from 9.9s to 10.5s.
	--
	-- A humanoid already knows whether it is standing on something, so ask it. The backstop is
	-- counted from K.liveAt - the first frame of the live round - because counting it from the
	-- spawn would make it expire before this function ever runs.
	-- A respawn is a new body on a platform that may not have loaded yet - the same hazard
	-- the round start has. The character swap was already detected here and then thrown
	-- away: K.settleDone stayed true from the first life, so the fresh body was moved on
	-- its first frame. Measured over the round files, the median gap from "alive = true"
	-- to the first egg or target was 0.5s on 08-03 and 08-05 with no spawn guard, and
	-- 7.5s on 08-06 when the guard was anchored on the character instead of the round.
	-- The settle now counts from whichever came later: the round going live, or this body.
	if lp.Character ~= K.lastChar then
		K.lastChar = lp.Character
		K.charAt = os.clock()
		K.settleDone = false
	end
	if K.liveAt and not K.settleDone then
		local from = K.liveAt
		if K.charAt and K.charAt > from then
			from = K.charAt
		end
		local waited = os.clock() - from
		local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
		local hs = hum and hum:GetState()
		local footed = hs == Enum.HumanoidStateType.Running
			or hs == Enum.HumanoidStateType.RunningNoPhysics
			or hs == Enum.HumanoidStateType.Landed
			or groundBelow(r.Position + K.TP_PROBE_UP) < K.GROUND_MISS
		-- THE 2 TO 4 SECONDS HE KEEPS SEEING AFTER THE LAST EGG.
		--
		-- The settle releases early only when the character is FOOTED - Running, Landed, or
		-- ground within GROUND_MISS. A bot that has spent the egg phase hanging under a
		-- shell, and a bot that just respawned in mid air, are both not footed, so both pay
		-- the full cfg.settleSecs backstop - two seconds, every time the body changed. And
		-- because this gate sits ABOVE the egg gate, it is charged again on every respawn,
		-- including the ones that happen the moment the shells are gone.
		--
		-- The settle is for a body that has just appeared at the start of a round, not for
		-- the tenth respawn of a bot that has been teleporting for a minute. So once this
		-- client is already in the killing phase the backstop drops to his own ceiling:
		-- "i only can allow lower thne 0.2 sec distance".
		local cap = cfg.settleSecs
		if cfg.tpOn then
			cap = 0.2
		end
		if footed or waited >= cap then
			K.settleDone = true
			K.settleLast = waited
			K.event(string.format("settle released after %.2fs (%s, cap %.2fs)", waited,
				footed and "floor found" or "backstop, no floor", cap))
		else
			tpState = string.format("round live, no floor yet - %.2fs left", cap - waited)
			eggState = tpState
			return
		end
	end

	-- RE-ARM PER ROUND. This is the answer to the question he asked four times: why is
	-- there still a gap after the eggs die.
	--
	-- eggAutoArmed is a one-shot latch so the egg-to-kill handover fires once. Nothing was
	-- resetting it between rounds inside one client generation, so the FIRST round handed
	-- over and every round after it did not: the shells died, setTp was never called,
	-- cfg.tpOn stayed false, and the bot stood in the ruins doing nothing at all.
	--
	-- Measured 2026-08-20 04:30:12 with a probe on BOT A: the last enemy egg died
	-- and the bot fired ZERO player hits for the full twelve seconds the probe watched,
	-- with tpCurrent stuck on "-" the whole time. It was never 2 to 4 seconds. It was the
	-- rest of the round.
	if K.armRound ~= tostring(game.JobId) then
		K.armRound = tostring(game.JobId)
		eggAutoArmed = true
	end
	K.emNoteStart()
	
	-- The leader does not queue behind the eggs. It is BOT D and its job is the players,
	-- from the first second, while A, B and C put every frame into the shells.
	if K.iAmLeaderClient() and eggAutoArmed and not cfg.tpOn then
		eggAutoArmed = false
		setTp(true)
		loud("bot D", "leader fights from the first second - the eggs are the other three")
	end
	
	-- Eggs first, always. A round is decided by eggs, not by kills.
	if cfg.eggOn and not K.iAmLeaderClient() then
		if eggPass(r) then
			return
		end
		if cfg.eggThenTp and eggAutoArmed and not cfg.tpOn then
			eggAutoArmed = false
			setTp(true)
			
			-- CLEAR EVERYTHING, THEN KILL - no gap. His order, 2026-08-20: "after done kill
			-- the egg after 2 sec it have a distatecne cant doing killing ... it should done
			-- kill the egg then clearing all again then start to killing again, beucae eahc
			-- sec was imrapont".
			--
			-- Those two seconds are cfg.settleSecs, and they are exactly two because of how
			-- the settle releases: early if the character is FOOTED, otherwise on the
			-- backstop. A bot that has just spent the egg phase hanging eight studs under a
			-- shell is not footed, so it never takes the early exit - it pays the full
			-- backstop every time its body changed during the egg phase. The settle exists to
			-- stop a brand new body being thrown around before it has loaded, and a bot that
			-- was teleporting onto an egg a second ago is not a brand new body.
			K.settleDone = true
			
			-- And start the fight on a clean sheet, which is the other half of what he asked
			-- for. Everything below remembers people: the dry list from the anti-kick rule,
			-- the break-off cooldowns, the rolling time-spent-on-one-man tally, and the
			-- threat budget's parked flag. All of that was earned during the egg phase, when
			-- this bot was not fighting anybody, so none of it should be holding a target
			-- back the moment the shells are gone.
			K.noDmg = {}
			K.tpCool = {}
			K.tpSpent = {}
			for _, t in pairs(track) do
				t.threatDropped = nil
			end
			eggState = "eggs done - auto tp on"
			loud("egg", "ALL ENEMY EGGS DEAD - killing starts now, everything cleared")
		end
	end

	if not cfg.tpOn then
		tpState = "off"
		tpCurrent = "-"
		K.tpCurrent = tpCurrent
		return
	end

	-- No search radius: teleporting has no range limit, so anything less than the whole
	-- server is just leaving targets on the table.
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local ok, pr = validTarget(p)
		if ok then
			table.insert(list, { p = p, r = pr, d = (pr.Position - r.Position).Magnitude })
		end
	end
	tpLastTargets = #list
	if #list == 0 then
		-- Never stand still because of my own gates. If the only reason there is nothing
		-- to hit is that everyone is on the dry list or parked by the threat budget, wipe
		-- both and look again in this same frame. His words, 2026-08-20: "i just k one bto
		-- afk over 4 sec near, then that was imrpaont" - an idle bot is worth less than a
		-- wasted teleport, and both of those lists were only ever meant to steer, not stop.
		K.noDmg = {}
		for _, t in pairs(track) do
			t.threatDropped = nil
		end
		for _, p in ipairs(Players:GetPlayers()) do
			local ok2, pr2 = validTarget(p)
			if ok2 then
				table.insert(list, { p = p, r = pr2, d = (pr2.Position - r.Position).Magnitude })
			end
		end
		tpLastTargets = #list
	end
	if #list == 0 then
		tpState = "no target"
		tpCurrent = "-"
		K.tpCurrent = tpCurrent
		return
	end

	-- Where the crowd is, first. Standing in a group of four means every swing of the
	-- aura lands on four people, so a pile is worth more than whoever happens to be near.
	for _, e in ipairs(list) do
		local n = 0
		for _, o in ipairs(list) do
			if o ~= e and (o.r.Position - e.r.Position).Magnitude <= K.CLUSTER_R then
				n = n + 1
			end
		end
		e.cluster = n
		e.deathPile = n > K.CLUSTER_MAX
	end
	-- A flyer first, but LATE ONLY. He corrected me on this within the minute: "this was
	-- needed at all egg was killed, and also the round was most die alreayd at the round".
	--
	-- Early in a round a flyer is the worst thing to chase - he is out of reach, he is
	-- moving away every frame, and the shells are what decide the round. Late, when the
	-- shells are gone and most of the round is dead, he is often the only thing standing
	-- between us and the win, and then he goes first.
	--
	-- Both halves are measured, not guessed: eggsLeft() for the shells, and half of the
	-- em this round actually started with for "most die alreayd".
	local myCol = K.myColour()
	local endgame = K.emEndgame()
	local huntFly = eggsLeft() == 0 and K.emMostDead()
	table.sort(list, function(a, b)
		if huntFly then
			local ar = track[a.p] and track[a.p].role
			local br = track[b.p] and track[b.p].role
			local aFly = ar == "FLYING USER"
			local bFly = br == "FLYING USER"
			if aFly ~= bFly then
				return aFly
			end
		end
		if myCol and not endgame then
			local am = tostring(a.p:GetAttribute("TeamId")) == myCol
			local bm = tostring(b.p:GetAttribute("TeamId")) == myCol
			if am ~= bm then
				return am
			end
		end
		-- A pile over the cap is worth less than a lone enemy, not more, however many swings
		-- would land in it. Ordering it last rather than dropping it keeps it as a target of
		-- last resort, so a round where everyone is bunched together still gets played.
		if a.deathPile ~= b.deathPile then
			return b.deathPile
		end
		if a.cluster ~= b.cluster then
			return a.cluster > b.cluster
		end
		return a.d < b.d
	end)

	-- A hacker or a flyer goes to the FRONT of the sweep. He does not become the sweep.
	--
	-- This block used to end in `list = threats`, which deleted every ordinary enemy from the
	-- pass for as long as one flag was up, and a flag is up in 225 of the 352 recorded rounds.
	-- Measured across those rounds: a teleport frame aimed at a flagged player strips 9.0 health
	-- per second and lands in 20 percent of its samples; an unflagged one strips 23.1 and lands
	-- in 46. Ranking keeps the intent - every bot hits the dangerous one first - without handing
	-- him the round when he turns out to be unreachable.
	local threats, spent = {}, {}
	for _, e in ipairs(list) do
		local t = track[e.p]
		if t and t.role then
			if t.threatDropped and t.threatRound == tostring(game.JobId) then
				spent[#spent + 1] = e
			else
				threats[#threats + 1] = e
			end
		end
	end
	if cfg.teamFocusThreat and (#threats > 0 or #spent > 0) then
		-- The fair split still runs over the WHOLE list, not over what is left after the
		-- flagged ones are pulled out.
		--
		-- TEAM.share cuts on `per = ceil(n / TEAM.count)`, so two bots only land on the same
		-- boundary when they are handed the same n. Membership of `list` comes from
		-- validTarget, which reads server attributes, so every client sees the same n. Whether
		-- a player is FLAGGED does not: role is worked out locally from airborne timers and
		-- this client's own frame rate, which ran between 6 and 166 fps. Sharing a list with
		-- the flagged ones already removed would hand bot A n=5 and bot B n=6, move the
		-- boundary, and drop an ordinary enemy into the gap where no bot owns him - silently,
		-- with all three panels reading normal. Filtering AFTER the split only removes
		-- entries; it never moves the cut.
		table.sort(list, function(a, b)
			return a.p.UserId < b.p.UserId
		end)
		local plain = {}
		for _, e in ipairs(TEAM.share(list)) do
			local t = track[e.p]
			if not (t and t.role) then
				plain[#plain + 1] = e
			end
		end
		table.sort(plain, function(a, b)
			return a.d < b.d
		end)
		-- Dangerous first, hiding last. Before this the rush list was in scan order, so a flyer
		-- who was doing nothing but running away could be picked ahead of a teleport killer who
		-- was actively taking the round off us.
		table.sort(threats, function(a, b)
			local ra = K.THREAT_RANK[track[a.p] and track[a.p].role] or 9
			local rb = K.THREAT_RANK[track[b.p] and track[b.p].role] or 9
			if ra ~= rb then
				return ra < rb
			end
			return a.d < b.d
		end)
		table.sort(spent, function(a, b)
			return a.d < b.d
		end)
		list = {}
		for _, e in ipairs(threats) do
			list[#list + 1] = e
		end
		for _, e in ipairs(plain) do
			list[#list + 1] = e
		end
		-- Parked, but still swung at last of all rather than dropped, and taken from the whole
		-- list rather than from this bot's share - otherwise a round whose last living enemy is
		-- a parked flyer leaves every bot that does not own him standing still.
		for _, e in ipairs(spent) do
			list[#list + 1] = e
		end
		local tag = threats[1] and (K.THREAT_TAG[track[threats[1].p] and track[threats[1].p].role] or "???")
			or "-"
		TEAM.note = string.format("RUSH %d (%s) %d fair %d park", #threats, tag, #plain, #spent)
		if K.threatNote ~= "" then
			TEAM.note = TEAM.note .. "\n" .. K.threatNote
		end
	else
		-- Stable split on UserId so both bots agree who owns whom, then nearest first.
		table.sort(list, function(a, b)
			return a.p.UserId < b.p.UserId
		end)
		list = TEAM.share(list)
		TEAM.note = string.format("%s: %d of the enemies", TEAM.role, #list)
		table.sort(list, function(a, b)
			return a.d < b.d
		end)
	end
	tpLastTargets = #list

	local sweepPickups = {}
	-- No coin is worth a frame with one or two em left.
	if cfg.tpGrabCoins and not K.emEndgame() then
		for _, m in ipairs(workspace:GetChildren()) do
			if cfg.types[m.Name] then
				local hb = m:FindFirstChild("Hitbox")
				if hb and hb.Position.Y >= K.VOID_Y then
					sweepPickups[#sweepPickups + 1] = { m = m, hb = hb }
				end
			end
		end
	end

	local t0 = os.clock()
	-- Per pass, so the panel shows what is happening now rather than a
	-- lifetime total that only ever grows.
	K.tpBlockedPass = 0
	for _, e in ipairs(list) do
		if not cfg.tpOn or not alive or getgenv().__EWCOIN_GEN ~= MY_GEN then
			break
		end
		local tr = targetRoot(e.p)
		local swordOk, swordWhy = K.swordReady()
		if cfg.tpNeedGoldSword and not swordOk and not cfg.killOverride then
			tpState = swordWhy
			break
		end
		-- Two-together is also a war rule. Against ordinary players it just made every
		-- bot wait for a partner who was waiting too, so nobody moved.
		--
		-- Declared HERE, one level out from where it was. It used to be a local inside the
		-- first if, and the SECOND if read it at a scope where it does not exist - so every
		-- frame that actually had a target threw comparing a number with nil and took the
		-- whole sweep down with it. tpLastTargets was already set by then, which also holds
		-- the coin collector, so the bot stood still doing nothing at all. That is the gap
		-- after the eggs he kept reporting, and it was never a timing problem.
		local needTogether = (cfg.killOverride or cfg.tpNeedGoldSword)
			and (cfg.killOverride and 1 or cfg.tpMinTogether) or 1
		if tr and validTarget(e.p) and r.Parent then
			-- Say who we are on, then wait to be joined. A bot that finds itself alone on a
			-- man leaves him for someone else rather than starting a fight it has to hold
			-- open. One second of waiting costs far less than a kick.
			K.focusClaim(e.p.Name)
			if K.focusCount(e.p.Name) < needTogether then
				tpState = "waiting for a second bot on " .. e.p.Name
				RunService.Heartbeat:Wait()
			end
		end
		if tr and validTarget(e.p) and r.Parent
			and K.focusCount(e.p.Name) >= needTogether
			and (K.tpCool == nil or (K.tpCool[e.p.Name] or 0) < os.clock()) then
			tpCurrent = e.cluster and e.cluster > 0 and string.format("%s +%d", e.p.Name, e.cluster) or e.p.Name
			K.tpCurrent = tpCurrent
			-- Coins and kills at the same time. Anything lying within grabRadius of the man
			-- you are already standing on costs one extra frame to take, so the sweep picks
			-- it up on the way instead of making a separate trip for it later.
			-- No coin is worth a frame with one or two em left.
	if cfg.tpGrabCoins and not K.emEndgame() then
				for _, entry in ipairs(sweepPickups) do
					local m, hb = entry.m, entry.hb
					-- The Y test has to be done HERE and not only when the list was built.
					-- Hitboxes are unanchored, this list is built once per sweep, and a sweep
					-- is seconds long at these frame times - a coin that was on the map when
					-- the list was made is somewhere under it by the time we reach it, and
					-- teleporting to its old entry means diving after it.
					if m.Parent and hb.Parent and hb.Position.Y >= K.VOID_Y then
						local spot = (hb.Position - tr.Position).Magnitude <= cfg.tpGrabRadius
							and K.safeDest(hb.Position, hb.Position, m) or nil
						if spot then
							K.hop(r, CFrame.new(spot))
							RunService.Heartbeat:Wait()
							stats.visited = stats.visited + 1
							if not m.Parent then
								stats.collected = stats.collected + 1
								stats.byType[m.Name] = (stats.byType[m.Name] or 0) + 1
							end
						end
					end
				end
			end

			-- Budget clock for this target. Started here and not at the top of the pass so the
			-- coin grab above is never charged to him.
			local spend0 = os.clock()
			local hpBefore = e.p:GetAttribute("Health")
			local noFloor = false
			for _ = 1, cfg.tpFrames do
				-- Three seconds and out. This is the line the kick is drawn on.
				if os.clock() - spend0 > cfg.tpMaxSecs then
					K.tpCool = K.tpCool or {}
					K.tpCool[e.p.Name] = os.clock() + cfg.tpCoolSecs
					tpState = "broke off " .. e.p.Name .. " at " .. tostring(cfg.tpMaxSecs) .. "s"
					break
				end
				-- IN FRONT, not behind. This is the whole anti-kick change.
				--
				-- His read, 2026-08-16: "the kick system was only kick behind... at the front
				-- I don't believe it will kick us, because the black sword only needs very
				-- few seconds to kill the player already". Standing in the back arc is the
				-- safe place to fight from and that is exactly why it is the pattern the
				-- server watches for - a player who never once gets swung at is not a player
				-- having a fight. Standing in front looks like a normal duel, and with the
				-- black sword the duel is over before the difference costs anything.
				--
				-- One line, one sign. LookVector is the way he is facing; -1 put us at his
				-- back, +1 puts us in his face.
				local face = tr.CFrame.LookVector * (cfg.tpFront and 1 or -1)
				local flat = Vector3.new(face.X, 0, face.Z)
				flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
				-- A flyer gets closed right down. He asked for one stud: a flying target is
				-- already moving away every frame, so anything further is a swing at air.
				local useRange = cfg.tpRange
				local tt = K.__track and K.__track[e.p]
				if tt and tt.role then
					useRange = cfg.tpFlyRange
				end
				-- Lead a fast mover. Standing where he WAS is how a flyer stays out of reach:
				-- the fly script pushes a BodyVelocity at up to 50 studs a second and climbing,
				-- so by the time this frame's CFrame lands he has already moved most of a stud
				-- past it, every frame, forever. Aiming at where he will be closes that gap and
				-- costs nothing against someone standing still, whose velocity is zero. Capped
				-- so a body flung by an explosion does not throw the bot across the map.
				local lead = tr.AssemblyLinearVelocity * K.TP_LEAD
				if lead.Magnitude > K.TP_LEAD_MAX then
					lead = lead.Unit * K.TP_LEAD_MAX
				end
				-- Never lead downwards. A target who just walked off an edge is doing
				-- 50 studs a second straight down, and leading him meant aiming the
				-- teleport into the void ahead of him.
				if lead.Y < 0 then
					lead = Vector3.new(lead.X, 0, lead.Z)
				end
				-- UNDERNEATH him, not in front and not behind. 2026-08-20: "dont ever teleprot
				-- to the player frotn of behind, teleprot to the upside down ... i think msot
				-- time was down". In his face was the old anti-kick answer and it still parks the
				-- bot inside the man's swing; under him is outside both arcs. It costs no damage
				-- now that the hit is fired at the event instead of swung through the melee box.
				-- Falls back to the old flat spot if underneath would be over the void line.
				-- Under him, and if under is not available, over him. Never in front and never
				-- behind - 2026-08-20: "i must it was at the upside down or top to kill the
				-- player and not at the behind or front, that was too useless". Front was the
				-- old anti-kick answer and it still parks the bot inside the man's swing; the
				-- kick itself keys on time spent behind one player, so both of the old spots
				-- are the wrong ones. Down first because that is where he wants it most of the
				-- time; up only when down would put the bot under the void line.
				local off = math.clamp(useRange, 3, K.EGG_REACH)
				local dest = tr.Position + lead - Vector3.new(0, off, 0)
				if dest.Y <= K.VOID_Y + 5 then
					dest = tr.Position + lead + Vector3.new(0, off, 0)
				end
				if not dest then
					K.tpBlocked = K.tpBlocked + 1
					K.tpBlockedPass = K.tpBlockedPass + 1
					tpState = "skipped: nothing solid under him"
					noFloor = true
					break
				end
				K.hop(r, K.faceFlat(r, dest, tr.Position))
				K.hitPlayer(e.p)
				RunService.Heartbeat:Wait()
			end
			tpVisited = tpVisited + 1
			-- Did that visit actually take anything off him. If not, he goes on the dry
			-- list and the bot stops teleporting onto a man it cannot hurt.
			local hpAfter = e.p:GetAttribute("Health")
			if type(hpBefore) == "number" and type(hpAfter) == "number" and hpAfter >= hpBefore then
				K.noDmg[e.p] = os.clock()
				tpState = "no damage on " .. e.p.Name .. " - leaving him alone"
			end
			K.chargeThreat(e.p, hpBefore, os.clock() - spend0, noFloor)

			-- Add up the visits, because one visit is nothing.
			--
			-- He caught my first attempt at this, 2026-08-16: "we now those was using fast
			-- moving to kill right, it was not using teleport to behind to kill right". He is
			-- correct - tpFrames is 4, so one visit is about 0.07s, and a three second cap
			-- inside that loop could never once have fired.
			--
			-- The six seconds he measured is built out of hundreds of those 0.07s visits: the
			-- pass finishes the list and comes straight back, so with one live target the bot
			-- is behind the same man continuously while never staying more than four frames.
			-- The only number that matters is therefore the TOTAL, so this keeps a rolling
			-- tally per player and forces a real break when it passes tpMaxSecs. The window
			-- resets after six quiet seconds, so a man fought twice a minute apart never
			-- accumulates.
			K.tpSpent = K.tpSpent or {}
			local spent = K.tpSpent[e.p.Name]
			local nowc = os.clock()
			if not spent or nowc - (spent.last or 0) > 6 then
				spent = { secs = 0, last = nowc }
				K.tpSpent[e.p.Name] = spent
			end
			spent.secs = spent.secs + (nowc - spend0)
			spent.last = nowc
			if spent.secs > cfg.tpMaxSecs then
				K.tpCool = K.tpCool or {}
				K.tpCool[e.p.Name] = nowc + cfg.tpCoolSecs
				spent.secs = 0
				tpState = string.format("%s had %.1fs total - breaking off for %ds",
					e.p.Name, cfg.tpMaxSecs, cfg.tpCoolSecs)
				K.event(string.format("anti-kick: left %s after %.1fs behind him",
					e.p.Name, cfg.tpMaxSecs))
			end
		end
	end
	tpCycles = tpCycles + 1
	tpCycleMs = (os.clock() - t0) * 1000
	tpState = "sweeping"
end

getgenv().EWAntiVoid = {
	floorY = function()
		return cfg.avY
	end,
	-- For a teleport or aim routine: anyone at or under the floor is already lost,
	-- teleporting to them just drops you in after them.
	isSafeTarget = function(p)
		local c = p and p.Character
		local rr = c and c:FindFirstChild("HumanoidRootPart")
		if not rr then
			return false
		end
		return rr.Position.Y > cfg.avY + 4
	end,
}

local rows = {}

local function rowFor(p)
	local r = rows[p]
	if r and r.Parent then
		return r
	end
	r = Instance.new("TextLabel")
	r.Size = UDim2.new(1, -6, 0, 15)
	r.BackgroundTransparency = 1
	r.Font = Enum.Font.Code
	r.TextSize = 12
	r.TextXAlignment = Enum.TextXAlignment.Left
	r.Text = ""
	r.Parent = scroll
	rows[p] = r
	return r
end

local espGuis = {}

-- Vape draws its ESP with Drawing objects, which sit above every Roblox GUI, so we cannot
-- win a z-fight with it. We sit higher above the head instead, and if its name tag is
-- already on we drop the name and show only what it does not: level, state, health.
local function vapeShowsNames()
	local v = rawget(shared, "vape")
	if not v or type(v) ~= "table" then
		return false
	end
	local mods = rawget(v, "Modules")
	if type(mods) ~= "table" then
		return false
	end
	for _, name in ipairs({ "Nametags", "ESP" }) do
		local m = mods[name]
		if type(m) == "table" and m.Enabled then
			return true
		end
	end
	return false
end

local function destroyEsp(p)
	local b = espGuis[p]
	if b then
		pcall(function()
			b:Destroy()
		end)
		espGuis[p] = nil
	end
end

local function destroyAllEsp()
	for p in pairs(espGuis) do
		destroyEsp(p)
	end
end

-- A tag over each head: name and level on top, what he is doing right now underneath,
-- and a health bar along the bottom. The outline is his team colour, the state line is
-- the void-risk colour, so one glance gives you side and danger without reading words.
local function updateEsp(p, adornee, name, level, stateWord, dist, hp, teamColour, stateColour)
	if not cfg.esp or not adornee then
		destroyEsp(p)
		return
	end
	local b = espGuis[p]
	if not b or not b.Parent then
		b = Instance.new("BillboardGui")
		b.Name = "EWESP"
		b.Size = UDim2.fromOffset(190, 44)
		b.StudsOffset = Vector3.new(0, 5.2, 0)
		b.AlwaysOnTop = true
		b.MaxDistance = 2000
		b.LightInfluence = 0

		local body = Instance.new("Frame")
		body.Name = "Body"
		body.Size = UDim2.fromScale(1, 1)
		body.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
		body.BackgroundTransparency = 0.25
		body.BorderSizePixel = 0
		body.Parent = b
		Instance.new("UICorner", body).CornerRadius = UDim.new(0, 5)
		local st = Instance.new("UIStroke", body)
		st.Name = "Edge"
		st.Thickness = 1.5

		local n = Instance.new("TextLabel")
		n.Name = "N"
		n.Size = UDim2.new(1, -10, 0, 17)
		n.Position = UDim2.fromOffset(5, 3)
		n.BackgroundTransparency = 1
		n.Font = Enum.Font.GothamBold
		n.TextSize = 14
		n.TextStrokeTransparency = 0.4
		n.TextXAlignment = Enum.TextXAlignment.Center
		n.Parent = body

		local s = Instance.new("TextLabel")
		s.Name = "S"
		s.Size = UDim2.new(1, -10, 0, 14)
		s.Position = UDim2.fromOffset(5, 20)
		s.BackgroundTransparency = 1
		s.Font = Enum.Font.GothamMedium
		s.TextSize = 12
		s.TextStrokeTransparency = 0.5
		s.TextXAlignment = Enum.TextXAlignment.Center
		s.Parent = body

		local barBg = Instance.new("Frame")
		barBg.Name = "BarBg"
		barBg.Size = UDim2.new(1, -10, 0, 4)
		barBg.Position = UDim2.new(0, 5, 1, -7)
		barBg.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
		barBg.BorderSizePixel = 0
		barBg.Parent = body
		Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)

		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.Size = UDim2.fromScale(1, 1)
		bar.BackgroundColor3 = Color3.fromRGB(90, 220, 110)
		bar.BorderSizePixel = 0
		bar.Parent = barBg
		Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

		b.Parent = uiRoot
		espGuis[p] = b
	end

	b.Adornee = adornee
	local body = b:FindFirstChild("Body")
	if not body then
		return
	end
	local edge = body:FindFirstChild("Edge")
	if edge then
		edge.Color = teamColour
	end
	local n = body:FindFirstChild("N")
	if n then
		n.Text = vapeShowsNames() and string.format("Lv%s", tostring(level or "?"))
			or string.format("%s  Lv%s", name, tostring(level or "?"))
		n.TextColor3 = teamColour
	end
	local s = body:FindFirstChild("S")
	if s then
		s.Text = dist and string.format("%s   %dm", stateWord, math.floor(dist)) or stateWord
		s.TextColor3 = stateColour
	end
	local barBg = body:FindFirstChild("BarBg")
	local bar = barBg and barBg:FindFirstChild("Bar")
	if bar then
		local frac = math.clamp((hp or 0) / 100, 0, 1)
		bar.Size = UDim2.fromScale(frac, 1)
		bar.BackgroundColor3 = frac > 0.6 and Color3.fromRGB(90, 220, 110)
			or frac > 0.3 and Color3.fromRGB(240, 200, 80)
			or Color3.fromRGB(240, 90, 90)
	end
end

-- Three escalating levels, in the order the user asked for them:
--   1 EDGE  standing on solid ground but the next step forward is empty air
--   2 JUMP  left the ground over empty air and still rising
--   3 FALL  over empty air and dropping fast - already committed to the void
local function voidLevel(pos, vel, onGround)
	local below = groundBelow(pos)
	if onGround then
		local flat = Vector3.new(vel.X, 0, vel.Z)
		local dir = flat.Magnitude > 1 and flat.Unit or Vector3.new(0, 0, 0)
		if dir.Magnitude < 0.5 then
			return 0, below
		end
		local aheadBelow = groundBelow(pos + dir * K.EDGE_PROBE + Vector3.new(0, 2, 0))
		if aheadBelow >= K.GROUND_MISS then
			return 1, below
		end
		return 0, below
	end
	if below < K.GROUND_MISS then
		return 0, below
	end
	if vel.Y < -K.FALL_SPEED then
		return 3, below
	end
	return 2, below
end

local function trackPass()
	refreshRayFilter()
	local now = os.clock()
	local myTeam = lp:GetAttribute("TeamId")
	local shown, atRisk = 0, 0

	for _, p in ipairs(Players:GetPlayers()) do
		local t = track[p]
		if not t then
			t = { lastPos = nil, lastKills = p:GetAttribute("Kills"), lastAlive = true, action = "", actionT = 0, level = 0 }
			track[p] = t
		end

		local char = p.Character
		local r = char and char:FindFirstChild("HumanoidRootPart")
		local pAlive = p:GetAttribute("Alive")

		if r then
			local pos = r.Position
			local vel = r.AssemblyLinearVelocity
			local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
			local below = 999
			local onGround = false
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				local st = hum:GetState()
				onGround = st == Enum.HumanoidStateType.Running
					or st == Enum.HumanoidStateType.RunningNoPhysics
					or st == Enum.HumanoidStateType.Landed
			end

			local lvl
			lvl, below = voidLevel(pos, vel, onGround)

			if lvl > t.level and lvl >= 2 then
				local word = lvl == 3 and "FALLING INTO VOID" or "JUMPED OVER VOID"
				t.action = word
				t.actionT = now
				pushVoid(string.format("%s %s", p.Name, word))
			elseif lvl == 1 and t.level == 0 then
				t.action = "at edge"
				t.actionT = now
			end
			t.level = lvl
			if lvl > 0 then
				atRisk = atRisk + 1
			end

			local kills = p:GetAttribute("Kills")
			if t.lastKills and kills and kills > t.lastKills then
				t.action = "KILLED SOMEONE"
				t.actionT = now
				t.killEvents = (t.killEvents or 0) + 1
			end
			t.lastKills = kills

			-- Dead or spectating on paper, but the body is still here and still moving.
			-- Only sideways movement over solid ground counts. Any measure that took plain
			-- distance called every corpse ragdolling down the void a live faker, and that
			-- flag is what lets validTarget say yes to a dead man - so the sweep chased
			-- falling bodies and the anti-void used one as a landing spot. Falling is not
			-- evidence of anything. Under the line the flag is dropped outright.
			local claimsGone = pAlive == false or p:GetAttribute("Spectating")
			local movedNow = false
			if t.lastPos then
				local flat = Vector3.new(pos.X - t.lastPos.X, 0, pos.Z - t.lastPos.Z)
				movedNow = flat.Magnitude > 0.5 and below < K.GROUND_MISS and vel.Y > -K.FALL_SPEED
			end
			if claimsGone and movedNow then
				spoofed[p] = true
			elseif not claimsGone or pos.Y < K.VOID_Y then
				spoofed[p] = nil
			end

			-- Measure BEFORE classifying. These two counters used to be updated after the role
			-- was decided, so every role was judged on the previous tick's numbers and a
			-- teleport killer stayed unlabelled for one extra scan. Nothing was ever misfiled
			-- by it, but there is no reason to be a tick late about a player who is actively
			-- taking the round off us.
			--
			-- FLYING USER: airborne with nothing under him for more than 5 seconds. Someone
			-- bridging across on placed blocks always has ground under his feet, so he never
			-- accumulates this - that is the whole point of measuring it this way.
			local dt = t.lastT and (now - t.lastT) or 0
			t.lastT = now
			if not onGround and below >= K.GROUND_MISS then
				t.airT = (t.airT or 0) + dt
			else
				t.airT = 0
			end

			-- HACKER: position jumps no legitimate movement can produce, plus a kill count
			-- that is climbing. Either alone is noise; together they are a teleport killer.
			if t.lastPos then
				local jump = (pos - t.lastPos).Magnitude
				if jump > 50 and dt < 0.5 then
					t.tpJumps = (t.tpJumps or 0) + 1
					t.lastJumpT = now
				end
			end

			-- A flyer's own hardware, read straight off his character. The fly script everyone
			-- here uses (arceus x fly v2, decoded 2026-08-03) builds a BodyGyro and a
			-- BodyVelocity on the Torso or UpperTorso and sets PlatformStand, and because he
			-- owns his own character every one of those replicates to us. That is a fact about
			-- him, not an inference from how he is moving: it is true the instant he presses
			-- the button, where the airborne timer needs five seconds of watching, and it can
			-- never fire on our own bots because they move by writing CFrame and own no
			-- BodyMover at all. The timer stays as a second opinion for other fly scripts.
			local rig = p.Character
			local torso = rig and (rig:FindFirstChild("UpperTorso") or rig:FindFirstChild("Torso"))
			local hum = rig and rig:FindFirstChildOfClass("Humanoid")
			t.bodyMover = (torso ~= nil and (torso:FindFirstChildOfClass("BodyVelocity") ~= nil or torso:FindFirstChildOfClass("BodyGyro") ~= nil))
				or (hum ~= nil and hum.PlatformStand == true)

			t.role = nil
			t.bot = K.isBot(p)
			if p == lp or isOwner(p) or t.bot then
				-- He plays the same way the bots do - teleporting, flying, killing - so he
				-- trips every one of these detectors perfectly. Left alone, BOTH RUSH THREATS
				-- would drop the whole round and send all three bots to hunt their own owner.
				t.role = nil
				t.owner = true
			elseif spoofed[p] then
				t.role = "HACKER FAKE DEAD"
			elseif (t.tpJumps or 0) >= 3 and (t.killEvents or 0) >= 1 then
				t.role = "HACKER"
			elseif t.bodyMover
				or (t.airT or 0) > K.FLY_AIR_T
				or ((t.airT or 0) > K.FLY_MIN_AIR and vel.Y > K.FLY_RISE_Y)
				or ((t.airT or 0) > K.FLY_MIN_AIR and speed > K.FLY_SPEED)
			then
				t.role = "FLYING USER"
			end

			t.speed = speed
			t.below = below
			t.y = pos.Y
			t.onGround = onGround
			t.lastPos = pos
		end

		if t.lastAlive ~= false and pAlive == false then
			if t.level and t.level >= 2 then
				t.action = "DIED IN VOID"
				pushVoid(string.format("%s DIED IN VOID", p.Name))
			else
				t.action = "died"
			end
			t.actionT = now
		end
		t.lastAlive = pAlive

		local skip = cfg.trackEnemiesOnly and myTeam and p:GetAttribute("TeamId") == myTeam and p ~= lp
		local row = rowFor(p)
		if skip then
			row.Visible = false
		else
			row.Visible = true
			shown = shown + 1
			local team = p:GetAttribute("TeamId")
			local lvlText = ""
			if t.level == 1 then
				lvlText = " R1 EDGE"
			elseif t.level == 2 then
				lvlText = " R2 JUMP"
			elseif t.level == 3 then
				lvlText = " R3 FALL"
			end
			if t.y and t.y < K.VOID_GONE then
				lvlText = " GONE"
			elseif t.y and t.y < K.VOID_Y then
				lvlText = " VOID PLAYER"
			elseif t.role then
				lvlText = " " .. t.role
			end

			local statusText
			if pAlive == false then
				statusText = "DEAD"
			elseif p:GetAttribute("Spectating") then
				statusText = "SPEC"
			elseif not r then
				statusText = "----"
			elseif not t.onGround then
				statusText = string.format("AIR %3.0f", t.speed or 0)
			elseif (t.speed or 0) > 60 then
				statusText = string.format("FLY %3.0f", t.speed)
			elseif (t.speed or 0) > 3 then
				statusText = string.format("RUN %3.0f", t.speed)
			else
				statusText = "IDLE    "
			end

			local recent = (now - (t.actionT or 0)) < 6 and t.action ~= "" and ("  " .. t.action) or ""
			row.Text = string.format(
				"%s%-13s L%-3s %s %s%s%s",
				p == lp and ">" or " ",
				string.sub(p.Name, 1, 13),
				tostring(p:GetAttribute("Level") or "?"),
				K.TEAM_SHORT[team] or "--",
				statusText,
				lvlText,
				recent
			)

			if t.level == 3 then
				row.TextColor3 = Color3.fromRGB(255, 90, 90)
			elseif t.level == 2 then
				row.TextColor3 = Color3.fromRGB(255, 160, 70)
			elseif t.level == 1 then
				row.TextColor3 = Color3.fromRGB(255, 220, 110)
			elseif pAlive == false then
				row.TextColor3 = Color3.fromRGB(95, 95, 105)
			else
				row.TextColor3 = K.TEAM_COLOR[team] or Color3.fromRGB(190, 190, 200)
			end
			if p == lp and t.level == 0 and pAlive ~= false then
				row.TextColor3 = Color3.fromRGB(240, 240, 250)
			end

			if p ~= lp then
				local word
				if pAlive == false then
					word = "DEAD"
				elseif t.y and t.y < K.VOID_GONE then
					word = "GONE PLAYER"
				elseif t.y and t.y < K.VOID_Y then
					word = "VOID PLAYER"
				elseif t.level == 3 then
					word = "FALLING"
				elseif t.level == 2 then
					word = "JUMPING"
				elseif t.role then
					word = t.role
				elseif t.level == 1 then
					word = "AT EDGE"
				elseif not t.onGround then
					word = "IN AIR"
				elseif (t.speed or 0) > 60 then
					word = "FLYING"
				elseif (t.speed or 0) > 3 then
					word = "WALKING"
				else
					word = "STANDING"
				end
				local head = char and (char:FindFirstChild("Head") or r)
				local myR = root()
				local dist = (myR and r) and (r.Position - myR.Position).Magnitude or nil
				updateEsp(
					p,
					head,
					p.Name,
					p:GetAttribute("Level"),
					word,
					dist,
					p:GetAttribute("Health"),
					K.TEAM_COLOR[team] or Color3.fromRGB(200, 200, 210),
					row.TextColor3
				)
			end
		end
	end

	for p, row in pairs(rows) do
		if not p.Parent then
			row:Destroy()
			rows[p] = nil
			track[p] = nil
			spoofed[p] = nil
			destroyEsp(p)
		end
	end
	if not cfg.esp then
		destroyAllEsp()
	end

	scroll.CanvasSize = UDim2.new(0, 0, 0, shown * 17 + 8)
	trackHeader.Text = string.format("players %d   at void risk %d   events %d", shown, atRisk, stats.voidEvents)
	voidLog.Text = table.concat(voidLines, "\n")
end

local function claimIdentity()
	pcall(setthreadidentity, 8)
end


-- RAM downgrade. Everything here is client-side only, so nothing is sent to the server and
-- no other player sees any of it. Destroying an instance is what actually frees memory -
-- hiding it does not - so ON is one-way: the stripped instances only come back next round.
local ramStripped = 0
local ramLastReport = "not run yet"

local function memMb()
	local ok, v = pcall(function()
		return game:GetService("Stats"):GetTotalMemoryUsageMb()
	end)
	return ok and v or 0
end

K.STRIP_CLASSES = {
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
	Highlight = false,
}

local function ramApply()
	local before = memMb()
	local n = 0

	pcall(function()
		settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
	end)

	pcall(function()
		local L = game:GetService("Lighting")
		L.GlobalShadows = false
		L.FogEnd = 1000000
		L.Brightness = 2
		for _, v in ipairs(L:GetChildren()) do
			if v:IsA("PostEffect") or v:IsA("Atmosphere") or v:IsA("Sky") then
				v:Destroy()
				n = n + 1
			end
		end
	end)

	pcall(function()
		workspace.Terrain:Clear()
	end)

	-- Every pickup on the map is shadowed by a visual-only twin whose name ends in
	-- "Render". They are pure decoration - a MeshPart each - and deleting them costs
	-- nothing but frees a mesh and a draw call per coin on the field.
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

	-- Yield every so often. This walks about 22000 descendants and touches a property on
	-- most of them; done in one go it is a single frame hundreds of milliseconds long, and
	-- during that frame nothing else in this script runs - including the anti-void catch,
	-- which is exactly how a bot gets from the catch line to below -500 and is deleted.
	-- Spread over frames it costs the same total work and blocks nothing.
	local STRIP_CHUNK = 1200
	pcall(function()
		local seen = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			seen = seen + 1
			if seen % STRIP_CHUNK == 0 then
				RunService.Heartbeat:Wait()
			end
			if K.STRIP_CLASSES[d.ClassName] then
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
	ramStripped = ramStripped + n
	ramLastReport = string.format("%d stripped, %.0f -> %.0f MB", n, before, after)
end

local function ramRestore()
	pcall(function()
		settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
	end)
	pcall(function()
		local L = game:GetService("Lighting")
		L.GlobalShadows = true
		L.Brightness = 3
	end)
	ramLastReport = "quality restored - deleted parts return next round"
end

bind(ramButton.MouseButton1Click, function()
	cfg.ramOn = not cfg.ramOn
	ramError.Text = ""
	task.spawn(function()
		pcall(setthreadidentity, 8)
		local ok, err = pcall(cfg.ramOn and ramApply or ramRestore)
		if not ok then
			ramError.Text = "! " .. tostring(err)
		end
	end)
end)

-- There is no getter for this, so the label can only report what the last call did. If the
-- call fails the flag is put back, otherwise the button lies about a blank screen you can
-- still see.
bind(ram3dButton.MouseButton1Click, function()
	local want = not cfg.ram3d
	local ok, err = pcall(function()
		RunService:Set3dRenderingEnabled(want)
	end)
	if ok then
		cfg.ram3d = want
		ramError.Text = ""
	else
		ramError.Text = "! 3d toggle failed: " .. tostring(err)
	end
end)

-- Turning the cycle OFF leaves Vape exactly as it is rather than forcing it back on. If he
-- switched it off because he is standing in a round looking at something, the last thing that
-- should happen is a reinject wiping the menu he has open.
-- DEATH RECORDER.
--
-- "I cannot understand why it dies" is not a question the round log can answer. That file is
-- written once at the end and records what happened, not the two seconds before it, and the
-- one thing that separates a bot killed by a player from a bot that walked off an edge is the
-- shape of its Y in those two seconds.
--
-- So this keeps the last twelve seconds at five samples a second and throws them away
-- continuously, and the only time any of it reaches disk is the moment the bot dies. Then the
-- whole window goes into RobloxComm/deaths_<name>.log with a verdict on the front: a fall
-- reads as Y dropping with nothing touching it, a kill reads as health stepping down while Y
-- barely moves.
--
-- Everything lives inside the spawned function. Nothing new goes at the top level of this
-- file - see the note on the VAPE ON DEMAND block for what that cost.
do (function()
	task.spawn(function()
		claimIdentity()

		-- K.roundT and K.event are defined further down this file, and task.spawn starts
		-- running before the main chunk has got there. Without this wait the very first
		-- sample calls a nil value and the recorder dies before it has recorded anything.
		while alive and type(K.roundT) ~= "function" do
			task.wait(0.5)
		end

		local FILE = "RobloxComm/deaths_" .. lp.Name .. ".log"
		local CAP = 60
		local buf = {}
		local wasAlive = nil
		local deaths = 0

		-- The last stretch at frame rate, kept beside the twelve second ring.
		--
		-- The handoff said the fix for 0.2s sampling was 0.05s and paying for it in fps. That
		-- trade does not exist: this client runs at four to ten frames a second, so
		-- task.wait(0.05) does not buy five extra looks, it buys one per frame and charges a
		-- timer for it. Heartbeat gives exactly one per frame for nothing, and one per frame is
		-- the finest resolution this data can physically have.
		local hot = {}
		local hotConn
		local function stopHot()
			if hotConn then
				hotConn:Disconnect()
				hotConn = nil
			end
		end
		-- The callback hangs itself up rather than trusting the loop below to do it.
		--
		-- The loop body is not wrapped in a pcall by anything above it, so a throw inside it
		-- would leave a per-frame connection running for the lifetime of the DataModel - and
		-- one more every time the farm reloads, which is every teleport. Checking the
		-- generation here costs one comparison a frame and means the connection cannot outlive
		-- its thread no matter how that thread ends.
		hotConn = RunService.Heartbeat:Connect(function()
			if not alive or getgenv().__EWCOIN_GEN ~= MY_GEN then
				stopHot()
				return
			end
			local rr = root()
			if not rr then
				return
			end
			hot[#hot + 1] = {
				t = K.roundT(),
				y = rr.Position.Y,
				vy = rr.AssemblyLinearVelocity.Y,
			}
			if #hot > 120 then
				table.remove(hot, 1)
			end
		end)

		while alive and getgenv().__EWCOIN_GEN == MY_GEN do
			local r = root()
			local hp = lp:GetAttribute("Health")
			local aliveAttr = lp:GetAttribute("Alive")
			local nowAlive = aliveAttr ~= false and r ~= nil
			-- Which half of that line went false, written down instead of merged away.
			--
			-- "Alive is false" and "the character is gone" are two different failures and they
			-- were sharing one word. On 2026-08-06, 50 of 269 deaths flipped while the body was
			-- still standing with a position and with health that had not moved once in twelve
			-- seconds - the server declared the bot out, nothing hit it. That is not the same
			-- event as a corpse being removed, and the log could not say so.
			local flipWhy = (aliveAttr == false and r == nil) and "Alive=false and body gone"
				or (aliveAttr == false) and "server set Alive=false, body still there"
				or (r == nil) and "character removed, Alive not set false"
				or "-"

			buf[#buf + 1] = {
				t = K.roundT(),
				y = r and r.Position.Y or nil,
				-- The whole position, not just the height. The first version kept Y alone and
				-- then, when the character had already been removed, measured "who was near"
				-- from Vector3.new(0, y, 0) - a point in the middle of the map that nobody is
				-- ever standing on. Every death came out as "nobody within 250 studs", which
				-- is the exact sentence that would make him call it a cheat.
				pos = r and r.Position or nil,
				vy = r and r.AssemblyLinearVelocity.Y or nil,
				-- What is underneath, sampled beside the height instead of guessed from it.
				--
				-- Height alone cannot say void any more, and that is this script's own doing:
				-- avPass caps the fall at -K.FALL_CAP every frame and hauls the body back the
				-- moment it passes K.VOID_Y, so the two things that used to mark a void death - a
				-- huge negative Y and a huge negative velocity - have both been engineered
				-- away. Of 269 deaths written on 2026-08-06 not one classed KILLED reached
				-- y = -69. This is only ever an annotation on the verdict, never the thing that
				-- decides it: groundBelow gives up after five retries and returns 999, and the
				-- parts it skips include Hitbox, which is the same mechanism that made a coin
				-- hanging in mid air look like it had a floor under it on 2026-08-04.
				gap = r and groundBelow(r.Position) or nil,
				hp = hp,
			}
			if #buf > CAP then
				table.remove(buf, 1)
			end

			if wasAlive == true and nowAlive == false then
				deaths = deaths + 1

				-- Who was standing close enough to have done it.
				--
				-- "It died" is not an answer he can act on; "it died with nobody within 200
				-- studs" and "it died with one player 6 studs away holding a sword" are two
				-- completely different problems. Anyone who was near is written down with
				-- their distance and their level, so a killer can be named afterwards - and
				-- so a kill from across the map, which is what a cheat looks like, is visible
				-- as a death with no one anywhere near it.
				local near = {}
				do
					local rr = root()
					local myPos = rr and rr.Position
					if not myPos then
						-- The character is usually already gone by the time Alive flips, so
						-- fall back to the last real position the buffer saw.
						for i = #buf, 1, -1 do
							if buf[i].pos then
								myPos = buf[i].pos
								break
							end
						end
					end
					for _, p in ipairs(Players:GetPlayers()) do
						if p ~= lp then
							local pr = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
							if pr and myPos then
								local d = (pr.Position - myPos).Magnitude
								if d < 250 then
									near[#near + 1] = string.format("    %-20s %6.1f studs  lvl=%s  team=%s",
										p.Name, d, tostring(p:GetAttribute("Level")),
										tostring(p:GetAttribute("TeamId")))
								end
							end
						end
					end
					table.sort(near)
				end

				-- Start the verdict at the moment this life began, not at the top of the
				-- buffer. The window can reach back past the previous death into the seconds
				-- the bot spent as a corpse waiting to respawn - no position, health 0 - and
				-- those samples turned the summary into "health 0 -> 89", which reads as the
				-- bot HEALING to death. The life starts at the first sample that has a
				-- position after the last one that does not.
				local lifeFrom = 1
				for i = #buf, 2, -1 do
					if buf[i].pos and not buf[i - 1].pos then
						lifeFrom = i
						break
					end
				end

				local lines = {}
				local lowest, highest, hpDrops = 9e9, -9e9, 0
				local hpLost, hpFirst, hpLast = 0, nil, nil
				local prevHp = nil
				for si = lifeFrom, #buf do
					local s = buf[si]
					if s.y then
						lowest = math.min(lowest, s.y)
						highest = math.max(highest, s.y)
					end
					if type(s.hp) == "number" then
						hpFirst = hpFirst or s.hp
						hpLast = s.hp
						if type(prevHp) == "number" and s.hp < prevHp then
							hpDrops = hpDrops + 1
							hpLost = hpLost + (prevHp - s.hp)
						end
					end
					prevHp = s.hp
					lines[#lines + 1] = string.format("  %7.1fs  y=%s  vy=%s  hp=%s",
						s.t,
						s.y and string.format("%8.1f", s.y) or "    none",
						s.vy and string.format("%7.1f", s.vy) or "   none",
						tostring(s.hp))
				end

				-- A fall is a RUN of downward samples, not a range.
				--
				-- The first version called it a fall whenever the highest and lowest samples
				-- were forty studs apart, and at 00:23 that labelled a bot walking up and down
				-- an island for twelve seconds - health climbing back from 84 to 89 the whole
				-- time - as "FELL - lost 52 studs of height". It had not fallen anywhere; it
				-- was hit once for fifteen and died. A range says where it has been. Only a
				-- run of consecutive drops says it is falling.
				local runDrop, bestRun = 0, 0
				do
					local prevY, prevT = nil, nil
					for si = lifeFrom, #buf do
						local y = buf[si].y
						local t = buf[si].t
						-- A gap in TIME breaks the run, not just a gap in height.
						--
						-- K.roundT() restarts at every teleport, so a buffer can hold 143 from
						-- the old world and -24 from the new one with nothing in between. At
						-- 00:28 that produced "FELL - 167 studs straight down" out of five
						-- samples whose timestamps ran 0.8, 15.2, 29.5, 0.8 - two different
						-- rounds glued together and called a single dive.
						local sane = prevT and t and t > prevT and (t - prevT) < 1.5
						if y and prevY and sane and y < prevY - 1 then
							runDrop = runDrop + (prevY - y)
							if runDrop > bestRun then
								bestRun = runDrop
							end
						else
							runDrop = 0
						end
						prevY = y
						prevT = t
					end
				end
				local biggestHit = 0
				do
					local prevH = nil
					for si = lifeFrom, #buf do
						local h = buf[si].hp
						if type(h) == "number" and type(prevH) == "number" and prevH - h > biggestHit then
							biggestHit = prevH - h
						end
						prevH = h
					end
				end
				-- The last thing the body was standing on, and how fast it was going down AT
				-- THE FLIP. Both were already being measured and neither reached the verdict:
				-- vy was collected and only ever printed, and the raycast answer lived in
				-- K.lastGap in a different loop that this block cannot see.
				local lastGap, lastVy, lastYSeen = nil, nil, nil
				for si = #buf, lifeFrom, -1 do
					if buf[si].y then
						lastGap, lastVy, lastYSeen = buf[si].gap, buf[si].vy, buf[si].y
						break
					end
				end
				-- Frame resolution for the final descent, printed but never used to classify.
				-- hotWorstVy is the minimum over the whole 120 frame ring, not the speed at the
				-- moment of death: of the 152 deaths already classed KILLED - one hit, 56 have
				-- a ring minimum at or under -30 and 40 at or under -50, because being knocked
				-- about in a fight puts you there. Classifying on it would relabel a third of
				-- the confirmed kills as void deaths, which is the 12-second-drop mistake from
				-- 2026-08-06 with velocity substituted for height.
				local hotDrop, hotWorstVy = 0, 0
				do
					local pv, pt = nil, nil
					for hi = 1, #hot do
						local h = hot[hi]
						local sane = pt and h.t > pt and (h.t - pt) < 0.6
						if pv and sane and h.y < pv then
							hotDrop = hotDrop + (pv - h.y)
						elseif not sane or (pv and h.y >= pv) then
							hotDrop = 0
						end
						if h.vy < hotWorstVy then
							hotWorstVy = h.vy
						end
						pv, pt = h.y, h.t
					end
				end
				local noFloor = (lastGap ~= nil) and lastGap >= K.GROUND_MISS
				local wentUnder = lowest < 9e8 and lowest < K.VOID_Y
				local diving = (lastVy ~= nil and lastVy <= -K.FALL_SPEED)
				local fell = bestRun > 40 or hotDrop > 40
				-- Ordered by whether this particular death involved losing health, not by which
				-- sensor the evidence came from. Passing the void line is first because it is
				-- the one signal with zero measured contamination - across the 269 deaths not a
				-- single one classed KILLED or UNCLEAR ever reached y = -69. After that, a
				-- health step means something hit him, and "no floor under the body" rides
				-- along as an annotation rather than overruling it: a man killed in mid air
				-- over a gap while bridging is an ordinary EggWars death, and calling it VOID
				-- would hide the fifteen damage that actually did it.
				local verdict
				if wentUnder then
					verdict = string.format("VOID - passed the void line at y=%.0f", lowest)
				elseif biggestHit >= 12 then
					verdict = string.format("KILLED - one hit took %.0f health, floor %s studs under the body",
						biggestHit, lastGap and string.format("%.0f", lastGap) or "unknown")
				elseif hpDrops >= 2 then
					verdict = string.format("KILLED - health stepped down %d times, %.0f lost in total",
						hpDrops, hpLost)
				elseif fell then
					verdict = string.format("FELL - %.0f studs straight down without stopping (frame view %.0f)",
						bestRun, hotDrop)
				elseif noFloor and diving then
					verdict = string.format("VOID - nothing under the body (%.0f studs of empty air) and it was going down at %.0f/s",
						lastGap or 999, lastVy or 0)
				elseif hpDrops == 0 and hpFirst == hpLast and lastYSeen then
					verdict = "NOT A KILL - health never moved and the body was still standing when Alive went false"
				elseif hpDrops == 0 and lastYSeen then
					verdict = "NOT A KILL - health only went up, nothing damaged it, body still standing"
				else
					verdict = "UNCLEAR - no drop, no floor answer and no health movement"
				end
				-- The numbers behind the word, always, so the verdict can be argued with. A
				-- one-word conclusion with nothing under it is the kind of answer he has been
				-- burned by before.
				verdict = verdict .. string.format(
					"\n  trigger %s"
					.. "\n  health %s -> %s, %d drops, %.0f lost, biggest single hit %.0f"
					.. "\n  height %.0f to %.0f, longest unbroken drop %.0f studs, %d samples this life"
					.. "\n  at the flip: floor %s studs under, falling %.0f/s"
					.. "\n  worst frame in the last %d frames: %.0f/s",
					flipWhy,
					tostring(hpFirst), tostring(hpLast), hpDrops, hpLost, biggestHit,
					lowest < 9e8 and lowest or 0, highest > -9e8 and highest or 0,
					bestRun, #buf - lifeFrom + 1,
					lastGap and string.format("%.0f", lastGap) or "unknown",
					lastVy or 0,
					#hot, hotWorstVy)
				K.deathLine = verdict:match("^[^\n]*") or "-"

				pcall(function()
					appendfile(FILE, string.format(
						"\n=== death %d  %s  place=%s  state=%s  jobId=%s  doing=[%s] [%s] ===\n%s\n%s\n%s\n%s\n",
						deaths, os.date("%Y-%m-%d %H:%M:%S"), tostring(game.PlaceId),
						tostring(K.gameState), tostring(game.JobId),
						-- What the farm was in the middle of when it died.
						--
						-- His question 2026-08-15: was it killed while it was breaking an egg.
						-- The honest answer at the time was that nothing recorded it - the death
						-- block carried the place, the state, the height and who was nearby, but
						-- not what this client was actually doing, so the phase had to be guessed
						-- from "standing still on solid floor". These two strings are the farm's
						-- own live status lines, so the next one answers it outright.
						tostring(K.eggLine or eggState or "-"),
						tostring(K.tpLine or tpState or "-"),
						verdict,
						#near > 0 and ("  within 250 studs at the moment of death:\n" .. table.concat(near, "\n"))
							or "  nobody within 250 studs - if health dropped, it came from off screen",
						"  last 12 seconds:",
						table.concat(lines, "\n")))
				end)
				loud("death", verdict)
				K.event("death " .. deaths .. ": " .. verdict)
				buf = {}
				hot = {}
			end

			wasAlive = nowAlive
			task.wait(0.2)
		end
		stopHot()
	end)
end)() end

-- OBEY THE LEADER'S KILL ALL SWITCH.
--
-- His spec, 2026-08-15: when a flying player is detected the bots unlock battle mode and go
-- for him; when nothing is detected B and C stay at their own base and do not move. He drives
-- A himself for the egg range test, so A is deliberately exempt - the leader's switch never
-- touches it.
--
-- One decider, three followers. The leader writes RobloxComm/killall.txt and every bot reads
-- it; nobody decides for themselves. That is on purpose: three bots each making their own
-- call is exactly how this farm ended up with three separate invite loops firing at once and
-- 2336 invites to one account in a day.
--
-- What it flips: AUTO TP on or off. Off is what "stay at base" means here - the bot keeps its
-- character, keeps answering the roll call, keeps its panel, and simply stops teleporting onto
-- people. Nothing is killed, so turning it back on costs nothing.
--
-- Everything lives inside this do block on purpose. This file compiles at Luau's 200-local
-- ceiling and a single new top-level local broke the whole script at 17:4x - "Out of local
-- registers when trying to allocate MY_FORGOT_GEN" - which silently left all three bots with
-- no farm at all.
do
	task.spawn(function()
		getgenv().__KILLOBEY_GEN = (getgenv().__KILLOBEY_GEN or 0) + 1
		local MY_GEN = getgenv().__KILLOBEY_GEN
		local FILE = "RobloxComm/killall.txt"
		local last = nil
		-- What AUTO EGG was before the hunt started, so it can be given back afterwards.
		local eggBeforeKill = nil

		-- Start held, before the first read.
		--
		-- The watcher only reacts to a change, so on a fresh load it sits for a full second
		-- with whatever tpOn the rest of the file left behind. One second of a four-bot squad
		-- charging players is exactly what he saw. Clear it first, then let the file decide.
		cfg.tpOn = false

		-- No exemptions. A obeys the switch too.
		--
		-- I had A skip this so he could drive it by hand for the egg range test. That
		-- was backwards and he said so: "i need controlling it, u make it dont stop how
		-- i control it". Skipping the switch does not hand him control, it takes the
		-- stop button away from him - the one control that makes a bot sit still while
		-- he works on it. All three obey now; STOP KILL ALL stops all three.

		while alive and getgenv().__KILLOBEY_GEN == MY_GEN do
			task.wait(1)
			local ok, raw = pcall(function()
				if isfile(FILE) then
					return readfile(FILE)
				end
			end)
			if ok and type(raw) == "string" then
				local want = raw:match("^%s*(%u+)")
				if want == "ON" or want == "OFF" then
					if want ~= last then
						last = want
						if want == "ON" then
							cfg.tpOn = true
							-- KILL ALL no longer closes the egg pass. 2026-08-20, his order after watching
							-- a bot leave a live shell to go and fight: "it was fucking didnt detect any
							-- blacklist bro why the fuck it need to kill player before done kill all egg
							-- then?". The egg gate above runs first anyway, so turning tpOn on here simply
							-- means the killing starts the instant the last shell falls.
							-- KILL ALL is him giving an order, so it outranks the gates.
							--
							-- He pressed it and nothing happened: "fix the kill all, why it
							-- was not kill all". Both gates added earlier tonight were holding
							-- it shut - the gold-sword rule broke out of the target loop on
							-- its first line, and the two-bots-together rule made every bot
							-- wait for a partner who was also waiting. Those exist to stop the
							-- farm starting fights on its own. An order from him is not the
							-- farm deciding, so they stand down until STOP KILL ALL.
							cfg.killOverride = true
							K.event("KILL ALL from the leader - battle mode, eggs held")
							pcall(writefile, "RobloxComm/killack_" .. lp.Name .. ".txt",
								string.format("%s %d", want, os.time()))
						else
							cfg.tpOn = false
							cfg.killOverride = false
							-- Hold means hold. Turning AUTO TP off alone did not stop them.
							--
							-- Measured 2026-08-15 22:4x: killall.txt said OFF, the watcher was
							-- running on this bot (obeyGen=1) and cfg.tpOn was already false -
							-- and they were still fighting. The egg pass is the OTHER thing that
							-- moves this character, and it was still on, so the bot kept walking
							-- itself into an enemy base and swinging at whoever stood there.
							-- Off has to mean both movers, not just the one I remembered.
							-- Give the egg pass back. Both branches used to write false, and
							-- nothing in the whole file ever wrote true except the panel button,
							-- so one KILL ALL closed the egg pass for the rest of the session.
							if eggBeforeKill ~= nil then
								cfg.eggOn = eggBeforeKill
								eggBeforeKill = nil
							else
								cfg.eggOn = true
							end
							K.event("kill all off - back to eggs, no player hunting")
							pcall(writefile, "RobloxComm/killack_" .. lp.Name .. ".txt",
								string.format("%s %d", want, os.time()))
						end
					end
				end
			end
		end
	end)
end

bind(K.vapeCycleButton.MouseButton1Click, function()
	cfg.vapeCycle = not cfg.vapeCycle
	ramError.Text = ""
	K.event("vape on demand " .. (cfg.vapeCycle and "ON" or "OFF") .. " by hand")
end)

-- One pass was not a downgrade, it was a snapshot.
--
-- Measured at 22:0x on 2026-08-05, forty minutes into a match client with RAM DOWNGRADE ON:
-- 15134 Decals, Textures and SurfaceAppearances and 3934 meshes still in the DataModel, and
-- GraphicsTexture holding 203 MB. The sweep ran once at six seconds, which is before the map
-- has finished streaming in - so it swept an empty room and reported success, and everything
-- that arrived afterwards was never touched. He is right that this is not what the button
-- says it does.
--
-- The old objection to re-running it still stands: walking 22000 descendants every eight
-- seconds is a frame long enough to lose the anti-void catch. So it is not repeated. Instead
-- there are three early passes while the map is still arriving, and then a DescendantAdded
-- hook that costs one comparison per new instance and nothing at all when nothing is added.
-- After that, anything that gets created is downgraded as it is born.
task.spawn(function()
	pcall(setthreadidentity, 8)

	local function downgradeOne(d)
		if K.STRIP_CLASSES[d.ClassName] or d:IsA("Accessory") then
			pcall(function()
				d:Destroy()
			end)
			ramStripped = ramStripped + 1
			return
		end
		if d:IsA("MeshPart") then
			pcall(function()
				d.RenderFidelity = Enum.RenderFidelity.Performance
				d.CastShadow = false
				d.Reflectance = 0
			end)
		elseif d:IsA("BasePart") then
			pcall(function()
				d.CastShadow = false
				d.Reflectance = 0
				if d.Material ~= Enum.Material.SmoothPlastic then
					d.Material = Enum.Material.SmoothPlastic
				end
			end)
		end
	end

	-- Match only. Stripping decals, textures, sounds and terrain in the LOBBY wrecks the place
	-- you actually have to read and click - it is where team invites are accepted and where the
	-- queue lives. There is nothing to gain there either: a lobby is cheap to render.
	task.wait(6)
	if not (alive and getgenv().__EWCOIN_GEN == MY_GEN and cfg.ramOn and inMatch()) then
		return
	end

	pcall(ramApply)

	-- The hook goes on before the later passes, so nothing can slip in between them.
	bind(workspace.DescendantAdded, function(d)
		if cfg.ramOn and alive and getgenv().__EWCOIN_GEN == MY_GEN then
			downgradeOne(d)
		end
	end)
	K.event("ram downgrade: live hook armed, new instances are stripped as they arrive")

	-- Twenty and sixty seconds. A map that streams in over half a minute is fully there by
	-- the last one, and three chunked passes cost far less than one pass every eight seconds
	-- for the whole round.
	for _, wait in ipairs({ 14, 40 }) do
		task.wait(wait)
		if not (alive and getgenv().__EWCOIN_GEN == MY_GEN and cfg.ramOn and inMatch()) then
			return
		end
		pcall(ramApply)
	end
	K.event(string.format("ram downgrade: three passes done, %d stripped in total", ramStripped))
end)

-- Pauses only this script's farming. Vape is a separate script and is not touched.
local farmSaved = nil
local function setFarmPaused(on)
	if on then
		farmSaved = { enabled = cfg.enabled, autoBuy = cfg.autoBuy, tpOn = cfg.tpOn, eggOn = cfg.eggOn }
		cfg.enabled, cfg.autoBuy, cfg.tpOn, cfg.eggOn = false, false, false, false
	elseif farmSaved then
		cfg.enabled, cfg.autoBuy, cfg.tpOn, cfg.eggOn =
			farmSaved.enabled, farmSaved.autoBuy, farmSaved.tpOn, farmSaved.eggOn
		farmSaved = nil
	end
	cfg.farmPaused = on
end

do (function()
	local teamFrame = makePanel(945, 756, 248, 236, "TEAMMATE", "TEAM", false)
	TEAM.on = button(teamFrame, "TEAM MODE: ON", 8, 34, 232, 26)
	TEAM.on.Font = Enum.Font.GothamBold
	TEAM.rush = button(teamFrame, "BOTH RUSH THREATS: ON", 8, 64, 232, 22)
	TEAM.status = label(teamFrame, "", 94, 108)
	TEAM.err = label(teamFrame, "", 206, 24, Color3.fromRGB(255, 92, 92))
	bind(TEAM.on.MouseButton1Click, function()
		cfg.teamOn = not cfg.teamOn
	end)
	bind(TEAM.rush.MouseButton1Click, function()
		cfg.teamFocusThreat = not cfg.teamFocusThreat
	end)
end)() end

-- ROUND WATCH. This panel deliberately does not try to press anything. Real's executor core
-- makes firesignal and Connection:Fire silent no-ops, so a script cannot click the lobby's
-- own Play button, and Real's native input only works while that window is focused - which is
-- the one thing this whole setup exists to avoid. So instead of pretending, this watches the
-- round state, names exactly which stage is stuck, and writes it to disk. The disk part is the
-- point: if the client loses injection or the panel disappears, the file is still there and
-- still says what the client was doing in its last five seconds.
do (function()
	-- 236 wide was 220 pixels of usable text, and label() leaves TextWrapped off, so at
	-- TextSize 12 in the Code font that is about thirty characters and everything past it is
	-- simply not drawn. Two more status lines went in tonight and the countdown box needs a
	-- row of its own, so the panel grows rather than quietly cutting the new lines in half.
	-- 1214 + 420 is 1634, still inside 1920.
	local roundFrame = makePanel(1214, 756, 420, 306, "ROUND WATCH", "RND", false)
	local roundStatus = label(roundFrame, "", 34, 170)
	local roundWarn = label(roundFrame, "", 206, 34, Color3.fromRGB(255, 92, 92))
	local holdLabel = label(roundFrame, "", 240, 18, Color3.fromRGB(255, 214, 120), 12)
	local rejoinButton = button(roundFrame, "GO TO LOBBY NOW", 8, 266, 196, 26)
	local stayButton = button(roundFrame, "STAY", 212, 266, 196, 26)

	local LOBBY_PLACE = 8542259458
	-- The last line of TeleController.teleportToHub, fired raw. teleportToHub itself asks
	-- PartyUtil.isHostingMultiplayerParty first and calls leaveParty for anyone who is not the
	-- host, so calling the function would drop this client out of the party; firing the event
	-- skips that. Read out of the game's own source on 2026-08-05.
	local LOBBY_EVENT = "87a02d63-f3a1-4197-9e7b-13faa920d53c"
	local STATE_FILE = "RobloxComm/status_" .. lp.Name .. ".txt"
	local ROUND_LOG = "RobloxComm/round_log.txt"

	local lastState, stateSince = nil, os.clock()
	local noCharSince = nil
	local warned = {}

	-- The automatic route out of a finished round, back but on a much shorter leash.
	--
	-- Deleting it entirely was wrong for a measured reason. The old switch called
	-- TeleportService:Teleport(LOBBY_PLACE, lp) and was written off on the strength of a
	-- comment in BOT-FOLLOW.lua saying that call "returned OK and moved nobody". round_log.txt
	-- disagrees: TRY REJOIN fired six times on 2026-08-03 - 15:34:04, 15:34:26, 15:34:48,
	-- 16:19:07 and twice at 16:19:08 - and all six are followed within 7 to 16 seconds by
	-- "script loaded, place 8542259458", which is the lobby. Six fires, six arrivals, zero
	-- failures. It is the only exit from a match anybody has ever watched work.
	--
	-- What was genuinely wrong with it was its trigger list and its silence. It also fired on
	-- "never-spawned", which is a state that occurs in Pregame - 32 of those lines in the log,
	-- the sampled ones all reading "91s in the match with no character, state Pregame" - and
	-- that is a third exit nobody authorised. So:
	--
	--   * only ended-no-teleport, which is the server having declared the round over
	--   * sixty seconds on the panel first, and a STAY button that cancels it outright
	--   * and not until BOT-FOLLOW.lua has tried three times and written down that it is stuck
	--
	-- That last condition is what stops the two scripts reaching for the same client. Leaving
	-- a finished round is BOT-FOLLOW's job; this only picks it up after BOT-FOLLOW has said on
	-- disk that it cannot.
	local lastLobbyTry = "not pressed yet"
	local lobbyTried = false
	local autoHoldUntil, autoStayed = nil, false
	local STUCK_NEEDED = 3
	local STUCK_FILE = "RobloxComm/leave_stuck_" .. lp.Name .. ".txt"

	local function note(line)
		pcall(
			appendfile,
			ROUND_LOG,
			string.format("%s  %-14s %s\n", os.date("%Y-%m-%d %H:%M:%S"), lp.Name, line)
		)
	end

	-- THE ONE AUTHORISED REASON TO GO BACK TO THE LOBBY, READ FROM DISK.
	--
	-- 2026-08-10, his words: we wont back to lobby unless it was 3 bot not at the team.
	-- LEADER.lua is the only client that owns the party, so it measures the count off
	-- Party.Players and writes lobby_gate.txt every two seconds. Unreadable, unparsable and
	-- stale all mean shut - a file that cannot be read is not evidence of anything.
	local LOBBY_GATE = "RobloxComm/lobby_gate.txt"
	local function lobbyGate()
		local ok, raw = pcall(function()
			return readfile(LOBBY_GATE)
		end)
		if not ok or type(raw) ~= "string" then
			return false, "shut - lobby_gate.txt unreadable", "?"
		end
		local stamp, allow, out, held = raw:gsub("^\239\187\191", ""):match("^%s*(%d+)%s+(%d)%s+(%d)%s+(%d+)")
		if not stamp then
			return false, "shut - lobby_gate.txt unparsable", "?"
		end
		local age = os.time() - tonumber(stamp)
		if age < 0 or age > 30 then
			return false, string.format("shut - lobby_gate.txt is %ds old", age), out
		end
		if allow ~= "1" then
			return false, string.format("shut - %s of 3 bots out of the party for %ss", out, held), out
		end
		return true, string.format("OPEN - all 3 bots out of the party for %ss", held), out
	end

	local function followIsStuck()
		local ok, raw = pcall(readfile, STUCK_FILE)
		if not ok or type(raw) ~= "string" then
			return 0
		end
		return tonumber(raw:match("%d+")) or 0
	end

	-- One routine for both the button and the countdown, so the manual path and the automatic
	-- path cannot drift apart and cannot be told apart in the log by accident - the `src`
	-- prefix is what says which one fired.
	local function goToLobby(src)
		claimIdentity()
		lobbyTried = true
		if game.PlaceId == LOBBY_PLACE then
			lastLobbyTry = "already in the lobby, did nothing"
			note(src .. " " .. lastLobbyTry)
			return
		end
		local okMod, events = pcall(function()
			return require(lp.PlayerScripts.TS.events).Events
		end)
		if not okMod or type(events) ~= "table" then
			lastLobbyTry = "events table unreachable: " .. tostring(events)
			note(src .. " " .. lastLobbyTry)
			return
		end
		local ev = events[LOBBY_EVENT]
		if type(ev) ~= "table" or type(ev.fire) ~= "function" then
			lastLobbyTry = "event 87a02d63 is not on place " .. tostring(game.PlaceId)
			note(src .. " " .. lastLobbyTry)
			return
		end
		-- Written down BEFORE the fire. A successful lobby event tears this DataModel down in
		-- the same frame, so a line written after it never reaches disk.
		local job = tostring(game.JobId)
		note(src .. " firing in job " .. job:sub(1, 8))
		local okFire, fireErr = pcall(function()
			ev:fire()
		end)
		lastLobbyTry = okFire and "STAGE1 fired, 8s to see if it moved" or ("STAGE1 threw: " .. tostring(fireErr))
		if not okFire then
			note(src .. " " .. lastLobbyTry)
		end
		-- Stage two: the call the log says actually moves a bot, given its own eight seconds
		-- and its own line so one night of logs can say which of the two works.
		task.delay(8, function()
			if tostring(game.JobId) ~= job then
				return
			end
			note(src .. " STAGE1 did not move this client - escalating to TeleportService:Teleport")
			claimIdentity()
			local okTp, tpErr = pcall(function()
				game:GetService("TeleportService"):Teleport(LOBBY_PLACE, lp)
			end)
			if not okTp then
				lastLobbyTry = "STAGE2 threw: " .. tostring(tpErr)
				note(src .. " " .. lastLobbyTry)
				return
			end
			lastLobbyTry = "STAGE2 Teleport accepted, 12s to see if it moved"
			task.delay(12, function()
				if tostring(game.JobId) == job then
					lastLobbyTry = "STILL HERE after both the lobby event and Teleport"
					note(src .. " " .. lastLobbyTry)
				end
			end)
		end)
	end

	-- Bound after note exists, not before. A handler written above the local would capture a
	-- global that is nil and every failure inside it would be lost.
	bind(rejoinButton.MouseButton1Click, function()
		autoHoldUntil = nil
		goToLobby("LOBBY BUTTON")
	end)

	bind(stayButton.MouseButton1Click, function()
		autoStayed = true
		autoHoldUntil = nil
		holdLabel.Text = ""
		note("STAY pressed - this client will not leave this server by itself")
	end)

	task.spawn(function()
		claimIdentity()
		note("script loaded, place " .. tostring(game.PlaceId))
		while alive and getgenv().__EWCOIN_GEN == MY_GEN do
			local ok, err = pcall(function()
				local placeId = game.PlaceId
				local where = placeId == K.MATCH_PLACE and "MATCH"
					or placeId == LOBBY_PLACE and "LOBBY"
					or tostring(placeId)

				local st = state()
				local gs = st and tostring(st.GameState) or "unknown"
				if gs ~= lastState then
					if lastState then
						note(string.format("%s -> %s in %s", tostring(lastState), gs, where))
					end
					lastState = gs
					stateSince = os.clock()
					warned = {}
				end
				local held = os.clock() - stateSince

				local r = root()
				if r then
					noCharSince = nil
				elseif not noCharSince then
					noCharSince = os.clock()
				end
				local noCharFor = noCharSince and (os.clock() - noCharSince) or 0

				local aliveAttr = lp:GetAttribute("Alive")
				local spect = lp:GetAttribute("Spectating")

				-- Who is actually driving matchmaking. In a party ONLY the owner can start a
				-- match; everyone else is just pulled in with them. So a follower sitting in the
				-- lobby is not stalled, it is doing the only thing it can do - and calling that a
				-- fault fills the log with false alarms and buries the real ones.
				local party = st and st.Party
				local owner = party and party.Owner
				local waitingForLeader = false
				local partyNote = "no party"
				if owner and owner.UserId then
					if owner.UserId == lp.UserId then
						partyNote = "you lead this party"
					else
						waitingForLeader = true
						partyNote = "waiting for leader " .. tostring(owner.UserName)
					end
				end

				-- Each of these is a different stall with a different fix, so they are never
				-- collapsed into one "stuck" message. The number in brackets is how long.
				local warn, warnKind = "", nil
				if placeId == K.MATCH_PLACE and gs == "Ended" and held > 90 then
					warn = string.format("! match ended %.0fs ago, no teleport", held)
					warnKind = "ended-no-teleport"
					-- RESCUE A FAILED TELEPORT. This is not the round cycle he banned.
					--
					-- His rule stands: "bakc to lobby was only fixing the player got kicked",
					-- and nothing here fires at the end of a normal round - the game moves us
					-- itself and this branch is never reached. What it catches is the state
					-- measured on four clients at 10:22 on 2026-08-20: the server has declared
					-- the round Ended, two full minutes have passed, and no teleport has
					-- happened. Left alone that client drops out to the Roblox home screen,
					-- where no script of ours can run and nothing can bring it back but a
					-- launch - four of the six clients were sitting exactly there, and that is
					-- what stops the farm running through the night.
					--
					-- Once per round, keyed on the jobId, so a server that refuses to let go
					-- is asked once and not hammered.
					if held > 120 and K.rescuedRound ~= tostring(game.JobId) then
						K.rescuedRound = tostring(game.JobId)
						note(string.format(
							"RESCUE: round Ended %.0fs ago and the game has not moved us - going to the lobby myself",
							held))
						pcall(function()
							game:GetService("TeleportService"):Teleport(K.LOBBY_HOP, lp)
						end)
					end
				elseif placeId == LOBBY_PLACE and held > 150 and not waitingForLeader then
					warn = string.format("! in lobby %.0fs - queue not moving", held)
					warnKind = "lobby-stuck"
				elseif gs == "InGame" and noCharFor > 75 then
					warn = string.format("! no character for %.0fs mid round", noCharFor)
					warnKind = "no-character"
				-- The one that was missing, and it is the state three bots sat in for over three
				-- minutes: in the MATCH place, no character, and GameState still Pregame with
				-- GameStateChangeTime never set. That is a match server that will not start - it
				-- was entered by a party that then lost its leader, so it has three players and
				-- needs eleven. Every other check watched a round in progress and none of them
				-- covered a round that never begins.
				elseif placeId == K.MATCH_PLACE and noCharFor > 90 then
					warn = string.format("! never spawned - %.0fs in the match with no character, state %s", noCharFor, gs)
					warnKind = "never-spawned"
				elseif placeId ~= K.MATCH_PLACE and placeId ~= LOBBY_PLACE then
					warn = "! not in a known EggWars place"
					warnKind = "unknown-place"
				end
				roundWarn.Text = warn
				-- Deduplicate on the KIND, never on the message. The message carries a seconds
				-- counter, so it is a different string every five seconds and a table keyed on it
				-- deduplicates nothing - round_log.txt was growing three lines every five seconds,
				-- forever, all of them saying exactly the same thing.
				if warnKind and not warned[warnKind] then
					warned[warnKind] = true
					note(warn)
				end

				-- The sixty second window, and only for the one state the server itself has
				-- declared finished. never-spawned is deliberately not in this condition.
				local stuck = followIsStuck()
				-- ONE CONDITION, AND IT IS NOT THE ROUND.
				--
				-- What used to be here left on the server having declared this round Ended AND BOT-FOLLOW
				-- having failed to get out three times, which is a different question with a different
				-- answer. stuck is still read and still shown, because the handoff to BOT-FOLLOW is worth
				-- seeing, but it no longer decides anything and neither does warnKind.
				local gateOk, gateWhy = lobbyGate()
				local mayLeave = gateOk and not autoStayed
				if mayLeave and not autoHoldUntil then
					autoHoldUntil = os.clock() + 60
					note(string.format(
						"LOBBY AUTO leaving in 60s unless STAY is pressed - %s (BOT-FOLLOW stuck %d, state held %.0fs)",
						gateWhy, stuck, held))
				elseif autoHoldUntil and not mayLeave then
					note("LOBBY AUTO countdown cancelled - " .. gateWhy)
					autoHoldUntil = nil
				end
				if autoHoldUntil then
					if os.clock() >= autoHoldUntil then
						autoHoldUntil = nil
						goToLobby("LOBBY AUTO")
					else
						holdLabel.Text = string.format("LEAVING IN %.0fs - press STAY to cancel",
							autoHoldUntil - os.clock())
					end
				else
					-- The gate, always on the panel, so the question of why it is not going back is answered
					-- on screen and not only in a log. Four states, never collapsed into one word.
					holdLabel.Text = autoStayed and "STAY pressed - will not leave by itself"
						or ("lobby gate " .. gateWhy)
				end

				-- The desktop keeper writes one line into keeper.txt every pass, with a full
				-- date on the front. Reading it in means a client that is alive can show what
				-- happened to the ones that were not - and a keeper that has stopped writing
				-- shows up as an explicit STALE line rather than as an hours-old line that
				-- still reads "ok".
				do
					local okK, rawK = pcall(readfile, "RobloxComm/keeper.txt")
					if okK and type(rawK) == "string" then
						local line = rawK:gsub("%s+$", "")
						local y, mo, d, hh, mm, ss = line:match("^(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
						if y then
							local age = os.time() - os.time({
								year = tonumber(y), month = tonumber(mo), day = tonumber(d),
								hour = tonumber(hh), min = tonumber(mm), sec = tonumber(ss),
							})
							if age > 120 then
								line = string.format("STALE %ds - the desktop keeper is not writing", age)
							end
						end
						K.keeperLine = line
					else
						K.keeperLine = "keeper.txt unreadable - desktop keeper may be down"
					end
				end

				roundStatus.Text = string.format(
					"place    %s\nstate    %s\nheld     %.0fs\ncharacter %s\nalive    %s\nspectating %s\nserver   %.1f min\n%s\nlast death %s\nkeeper   %s",
					where,
					gs,
					held,
					r and "yes" or string.format("no (%.0fs)", noCharFor),
					tostring(aliveAttr),
					tostring(spect),
					workspace.DistributedGameTime / 60,
					partyNote,
					-- Cut to what the label can actually draw. TextWrapped is off, so a longer
					-- string is not wrapped, it is simply not shown past the edge - and the
					-- part that would be lost is the end, which is where the reason lives. The
					-- full text is in deaths_<name>.log and keeper.txt either way.
					tostring(K.deathLine or "none yet"):sub(1, 52),
					tostring(K.keeperLine or "not reporting"):sub(1, 52)
				)

				-- Readable from the disk even with the MCP down or the client uninjected.
				pcall(
					writefile,
					STATE_FILE,
					string.format(
						-- vape and killaura are on this line for one reason: without Real
						-- attached there is no other way to find out whether the bots are
						-- defending themselves. On 2026-08-06 rounds started collapsing in
						-- twenty seconds right after VAPE ON DEMAND went in, and the first
						-- question - is Killaura even loaded when they land - could not be
						-- answered from the laptop at all.
						"time=%s\nuser=%s\nplace=%s\nstate=%s\nheld=%.0f\nchar=%s\nalive=%s\nspectating=%s\nparty=%s\nrole=%s prime=%s\nteam here=%d known=%d\ntpTargets=%d eggsMine=%d\navCatches=%d avState=%s\nvape=%s killaura=%s cycle=%s\ntp=%s\negg=%s\nwarn=%s\ndeath=%s\nkeeper=%s\n",
						os.date("%Y-%m-%d %H:%M:%S"),
						lp.Name,
						where,
						gs,
						held,
						r and "yes" or "no",
						tostring(aliveAttr),
						tostring(spect),
						partyNote,
						TEAM.role,
						tostring(TEAM.prime),
						#TEAM.here,
						#TEAM.roster,
						tpLastTargets,
						eggAliveCount,
						avCatches,
						avState,
						rawget(shared, "vape") and "loaded" or "gone",
						(function()
							local v = rawget(shared, "vape")
							local m = v and type(v.Modules) == "table" and v.Modules["Killaura"]
							if type(m) ~= "table" then
								return "missing"
							end
							return m.Enabled and "on" or "OFF"
						end)(),
						tostring(K.vapeCycle),
						-- Why it is standing still, in its own words.
						--
						-- At 00:32 a round log showed the bot motionless at y=-46 for seven
						-- seconds while other players moved, and there was no way to tell
						-- "waiting for the countdown" from "no target" from "settling after
						-- spawn" from outside the client. Three different guesses were made
						-- about that gap tonight and none of them could be checked.
						tostring(tpState),
						tostring(eggState),
						warn == "" and "none" or warn,
						tostring(K.deathLine or "none yet"),
						tostring(K.keeperLine or "not reporting")
					)
				)

				-- The button's own verdict, on the panel. A fire that threw and a fire that was
				-- accepted and then ignored look identical from outside this client, and this
				-- label is the only place either of them is ever shown.
				if lobbyTried then
					roundWarn.Text = (warn ~= "" and (warn .. "   |   ") or "") .. "lobby: " .. lastLobbyTry
				end
			end)
			if not ok then
				loud("round watch", err)
				pcall(function()
					roundWarn.Text = "! watch " .. tostring(err)
				end)
			end
			task.wait(5)
		end
	end)
end)() end

-- TELEMETRY. The round files are only worth writing if they answer the question you actually
-- have when you come back, and so far they could not answer the one that was asked: a flying
-- hacker took five minutes to kill and nothing recorded WHY. Totals cannot tell you that. A
-- timeline can: it shows which pass was driving the character each second, who it was standing
-- on, whether a sword was even in its hand, and whether the target's health was moving.
--
-- Everything here is sampling, not hooking. It reads values the rest of the script already
-- maintains, so it cannot change behaviour, and if it throws it takes only itself down.
do (function()
	local SAMPLE = 0.5
	local MAX_SAMPLES = 400

	-- Count real frames. The first version divided one by the gap between samples, which is
	-- the sampler own 0.5s interval, so the column read "2" forever no matter what the client
	-- was doing - a number that looks like data and is not.
	local frames = 0
	bind(RunService.Heartbeat, function()
		frames = frames + 1
	end)

	K.tl = {}
	K.ev = {}
	K.tlStart = os.clock()

	-- A1. Every clock in this file used to be os.clock(), which counts from the moment THIS
	-- process started. So each bot measured the round from its own load, and three bots that
	-- loaded a few seconds apart reported 14s, 17s and 20s for the same moment of the same
	-- round - which also made every duration in two hundred round logs incomparable.
	-- GameStateChangeTime is a unix second written by the SERVER, so anchoring to it makes all
	-- three agree exactly. The anchor is kept in os.clock() units so the timeline keeps its
	-- sub-second resolution instead of being rounded to whole seconds by os.time().
	K.roundAnchor = nil
	K.joinDelay = nil

	function K.roundT()
		if K.roundAnchor then
			return os.clock() - K.roundAnchor
		end
		return os.clock() - K.tlStart
	end

	local function syncRoundClock(st)
		if not st then
			return
		end
		local changed = st.GameStateChangeTime
		-- The server does not always put a unix second in this field. Round 6fd5dbf5 was
		-- handed 182, so joinDelay came out as os.time() minus 182 and that round wrote itself
		-- down as "round len 1785921014s" and "joined 1785920832s after the server started the
		-- round". 14 of the 698 rows in index.csv are that shape and each one poisons any
		-- average taken over the file. A round clock that is wrong is worse than no round
		-- clock, so refuse the value unless it really is a timestamp from about now, and say
		-- so on the panel rather than quietly falling back.
		local sane = type(changed) == "number" and math.abs(os.time() - changed) < 3600
		if tostring(st.GameState) == "InGame" and sane and K.roundStartUnix ~= changed then
			K.roundStartUnix = changed
			K.joinDelay = math.floor(os.time() - changed)
			K.roundAnchor = os.clock() - K.joinDelay
			K.clockBad = nil
			-- This is C1: how late this bot actually got into the round, in server seconds.
			K.event(string.format("clock synced to server, joined %ds after round start", K.joinDelay))
		elseif changed ~= nil and not sane then
			-- Said once, not once every ten seconds. Three bots sharing round_log.txt for eight
			-- hours turns a chatty warning into thousands of lines in a file that is already
			-- past six megabytes; the panel keeps saying it for as long as it is true.
			if not K.clockBad then
				loud("round clock", "GameStateChangeTime is not a timestamp: " .. tostring(changed))
			end
			K.clockBad = changed
		end
	end

	function K.event(text)
		if #K.ev > 120 then
			return
		end
		K.ev[#K.ev + 1] = string.format("%6.1fs  %s", K.roundT(), tostring(text))
	end

	function K.resetTimeline()
		K.tl, K.ev, K.tlStart = {}, {}, os.clock()
	end

	-- Which loop is actually driving the character right now. This is the single most useful
	-- column: five minutes of "TP" with an unchanging target is a completely different bug
	-- from five minutes of "IDLE", and the totals look identical either way.
	local function driving()
		if belowVoid() then
			return "VOID"
		end
		if lp:GetAttribute("Alive") == false then
			return "DEAD"
		end
		if eggState == "sweeping" then
			return "EGG"
		end
		if tpState == "sweeping" then
			return "TP"
		end
		-- coinPaused is only ever written from inside the collector loop, and that loop only
		-- runs while the round is live, so outside a round it keeps whatever it was last set
		-- to. Round b8974dcb is the cost: 42 seconds of Pregame all labelled COIN with the y
		-- column reading -999, which is no character at all. A drive column that lies is worse
		-- than no drive column, because every count taken off it afterwards is wrong too.
		if cfg.enabled and not coinPaused and K.roundLive() then
			return "COIN"
		end
		return "IDLE"
	end

	-- Is a melee weapon actually in hand. The whole farm silently does nothing without this,
	-- so it is worth one call every half second to be able to prove it either way.
	local function swordHeld()
		local hot = resolve("845")
		if not hot then
			return "?"
		end
		local ok, info = pcall(function()
			return hot:getHeldItemInfo()
		end)
		if not ok or not info then
			return "?"
		end
		return info.Melee and "y" or "NO"
	end

	task.spawn(function()
		claimIdentity()
		local lastAlive, lastEggs, lastTarget, lastState, lastKills = nil, 0, nil, nil, 0
		local myKey = nil
		local lastPos, stillSince, stillFlagged = nil, os.clock(), false
		local lastCycles, cyclesSince, sweepFlagged = -1, os.clock(), false
		local eggSince, eggFlagged = nil, false
		local seenThreat = {}
		local lastT = os.clock()

		while alive and getgenv().__EWCOIN_GEN == MY_GEN do
			local ok, err = pcall(function()
				if not inMatch() then
					return
				end
				-- A new server is a new round. The sampler resets itself here rather than being reset
				-- from the round logger, because the buffers and the last-seen values below have to
				-- go at the same moment or the first events of a round are recorded and then thrown
				-- away, leaving an event list that is permanently empty.
				local key = (tostring(game.JobId):gsub("%-", "")):sub(1, 8)
				if key ~= myKey then
					myKey = key
					K.tl, K.ev, K.tlStart = {}, {}, os.clock()
					K.roundAnchor, K.roundStartUnix, K.joinDelay = nil, nil, nil
					K.slowed = false
					lastPos, stillSince, stillFlagged = nil, os.clock(), false
					lastCycles, cyclesSince, sweepFlagged = -1, os.clock(), false
					eggSince, eggFlagged = nil, false
					lastAlive, lastEggs, lastTarget, lastState, lastKills = nil, 0, nil, nil, 0
					frames = 0
					K.event("watch started on round " .. key)
				end

				local now = os.clock()
				local dt = now - lastT
				lastT = now
				local fps = dt > 0 and (frames / dt) or 0
				frames = 0
				local t = K.roundT()

				local st = state()
				local gs = st and tostring(st.GameState) or "?"
				syncRoundClock(st)
				K.gameState = gs
				-- The moment this round went live, which is what the spawn settle counts
				-- against. Cleared the moment it stops being live so the next round starts
				-- its own two seconds rather than inheriting a stamp from the last one.
				if gs == "InGame" then
					if not K.liveAt then
						K.liveAt = os.clock()
						K.settleDone = false
					end
				else
					K.liveAt = nil
					K.settleDone = false
				end
				local kills = (st and st.GameStats and st.GameStats.Kills) or 0
				local r = root()
				local hp = lp:GetAttribute("Health")
				local aliveNow = lp:GetAttribute("Alive")
				local drv = driving()

				-- Target health is what proves whether the swings are landing at all.
				local tgtHp, tgtDist = nil, nil
				for _, p in ipairs(Players:GetPlayers()) do
					if tpCurrent and tpCurrent ~= "-" and string.find(tpCurrent, p.Name, 1, true) then
						tgtHp = p:GetAttribute("Health")
						local pr = targetRoot(p)
						if pr and r then
							tgtDist = (pr.Position - r.Position).Magnitude
						end
						break
					end
				end

				if #K.tl < MAX_SAMPLES then
					K.tl[#K.tl + 1] = string.format(
						"%6.1f %7.0f %5s %-5s %-3s %-16s %5s %6s %5d %5.0f",
						t,
						r and r.Position.Y or -999,
						tostring(hp),
						drv,
						swordHeld(),
						tostring(tpCurrent):sub(1, 16),
						tgtHp and string.format("%.0f", tgtHp) or "-",
						tgtDist and string.format("%.0f", tgtDist) or "-",
						tpLastTargets,
						fps
					)
				end

				-- Remember the last sample where the body still existed, so the death event can
				-- say WHY. The timeline column writes -999 the instant the character is gone, and
				-- that is true of every death - sword, void, fall - so on its own it settles
				-- nothing. What settles it is where the body was one moment earlier and whether
				-- anything was underneath it.
				if r then
					K.lastY = r.Position.Y
					K.lastVY = r.AssemblyLinearVelocity.Y
					K.lastGap = groundBelow(r.Position)
				end

				-- Events are emitted on change so the timeline stays readable.
				if gs ~= lastState then
					K.event("state " .. tostring(lastState) .. " -> " .. gs)
					lastState = gs
				end
				if aliveNow ~= lastAlive then
					if aliveNow == false then
						local gap = K.lastGap or 999
						K.event(string.format(
							"I DIED   last y=%.0f  fall=%.0f/s  under me: %s",
							K.lastY or -999,
							K.lastVY or 0,
							gap >= K.GROUND_MISS and "NOTHING - this is a void death"
								or string.format("ground %.0f studs down", gap)))
					else
						K.event("alive = " .. tostring(aliveNow))
					end
					lastAlive = aliveNow
				end
				if eggsBroken ~= lastEggs then
					K.event(string.format("egg broken (%d total)", eggsBroken))
					lastEggs = eggsBroken
				end
				if kills ~= lastKills then
					K.event(string.format("kill (%d this round)", kills))
					lastKills = kills
				end
				if tpCurrent ~= lastTarget and tpCurrent and tpCurrent ~= "-" then
					K.event("target -> " .. tostring(tpCurrent))
					lastTarget = tpCurrent
				end
				-- Stall detectors. Every failure so far has looked identical from the outside - the bot
			-- stands there and nothing says why - and each time it was found only after it had cost a
			-- round or a client. These three turn the three known stalls into events in the log the
			-- moment they start, so the next one is read rather than investigated.
			if gs == "InGame" and r then
				local moved = (not lastPos) or (r.Position - lastPos).Magnitude > 3
				lastPos = r.Position
				if moved then
					stillSince = now
					stillFlagged = false
				elseif not stillFlagged and now - stillSince > 25 then
					stillFlagged = true
					K.event(string.format("NOT MOVING for 25s while %s, targets %d, eggs %d", drv, tpLastTargets, eggAliveCount))
				end

				-- AUTO TP says it is on and has targets, but the sweep counter is frozen: the sweep
				-- thread is stuck or dead, which no panel number would ever show.
				if cfg.tpOn and tpLastTargets > 0 then
					if tpCycles ~= lastCycles then
						lastCycles = tpCycles
						cyclesSince = now
						sweepFlagged = false
					elseif not sweepFlagged and now - cyclesSince > 20 then
						sweepFlagged = true
						K.event("SWEEP FROZEN - AUTO TP on with targets but no cycle completed in 20s")
					end
				else
					cyclesSince = now
				end

				-- The egg phase holding forever is what "it never attacks anyone" looks like.
				if cfg.eggOn and eggAliveCount > 0 then
					if not eggSince then
						eggSince = now
					elseif not eggFlagged and now - eggSince > 60 then
						eggFlagged = true
					K.event(string.format("EGG PHASE STUCK 60s - %d eggs still up, my team %s", eggAliveCount, tostring(lp:GetAttribute("TeamId"))))
					end
				else
					eggSince, eggFlagged = nil, false
				end
			end

			for p, tr in pairs(track) do
					if tr.role and p.Parent and not seenThreat[p.Name] then
						seenThreat[p.Name] = true
						local pr = targetRoot(p)
						K.event(string.format(
							"THREAT %s = %s   y=%s  ground=%s",
							p.Name,
							tr.role,
							pr and string.format("%.0f", pr.Position.Y) or "?",
							tr.below and string.format("%.0f", tr.below) or "?"
						))
					end
				end
			end)
			if not ok then
				loud("telemetry", err)
			end
			-- A8. At a flat 0.5s and a 400 sample cap the timeline stopped at 3m20s - which is
			-- exactly where a five minute chase gets interesting. Halve the rate once past 200s so
			-- a long round is still covered end to end, and say so in the timeline when it happens.
			if K.roundT() > 200 then
				if not K.slowed then
					K.slowed = true
					K.event("long round - timeline drops to one sample every 2s")
				end
				task.wait(2)
			else
				task.wait(SAMPLE)
			end
		end
	end)
end)() end

-- ROUND LOG. One folder per round under RobloxComm/rounds/, named by the server's jobId so
-- all three bots land in the same folder without having to agree on a clock. Inside it: one
-- file per bot (A.txt / B.txt / C.txt) plus TOTAL.txt written by whichever bot is prime.
--
-- This exists so that coming back after four hours does not mean reading a console. Every
-- round leaves a self-contained record of what that bot did, what it saw, and whether it hit
-- an error, and index.csv gives you two hundred rounds at a glance to find the bad one.
do (function()
	local DIR = "RobloxComm/rounds"
	local INDEX = DIR .. "/index.csv"

	local roundKey, roundStart, wrote = nil, 0, false
	local killsBase, seenThreats = {}, {}

	local function ensureDir()
		pcall(function()
			if not isfolder("RobloxComm") then
				makefolder("RobloxComm")
			end
			if not isfolder(DIR) then
				makefolder(DIR)
			end
			if not isfile(INDEX) then
				writefile(INDEX, "unixtime,round,map,role,bot,team,result,secs,kills,dealt,taken,eggs,coins,buys,adren,voidcatches,threats,errors\n")
			end
		end)
	end

	-- The jobId is the only identifier all three bots already agree on for "this round".
	local function keyFor()
		local j = tostring(game.JobId)
		return (j:gsub("%-", "")):sub(1, 8)
	end

	local function beginRound()
		roundKey = keyFor()
		roundStart = os.clock()
		wrote = false
		killsBase, seenThreats = {}, {}
		for _, p in ipairs(Players:GetPlayers()) do
			killsBase[p] = p:GetAttribute("Kills") or 0
		end
		ensureDir()
		pcall(function()
			if not isfolder(DIR .. "/" .. roundKey) then
				makefolder(DIR .. "/" .. roundKey)
			end
		end)
	end

	-- Threats are recorded as they appear, not at the end: by the time the round is over the
	-- flyer has usually been killed and the tracker has already forgotten him.
	local function noteThreats()
		for p, t in pairs(track) do
			if t.role and p.Parent and not seenThreats[p.Name] then
				seenThreats[p.Name] = string.format("%s (%s) at %.0fs", p.Name, t.role, os.clock() - roundStart)
			end
		end
	end

	local function myLine(st)
		local gs = st and st.GameStats or {}
		local q = (st and st.GameCurrency and st.GameCurrency.Quantities) or {}
		return {
			secs = K.roundT(),
			team = tostring(lp:GetAttribute("TeamId")),
			kills = gs.Kills or 0,
			dealt = math.floor(gs.DamageDealt or 0),
			taken = math.floor(gs.DamageTaken or 0),
			podium = gs.PodiumPosition,
			bronze = q.TierOne or 0,
			iron = q.TierTwo or 0,
			gold = q.TierThree or 0,
			shard = q.TierFour or 0,
		}
	end

	local function writeMine(st, m)
		-- index.csv is appended, not overwritten, so a second copy of this script does not
		-- replace the row for this round, it adds another one. Eight rounds in the file are
		-- already doubled that way and one of them carries six rows for a single bot: the
		-- wrote flag is a local of the script instance, and a re-inject starts a new instance
		-- with it back at false. getgenv survives the re-inject, and the key carries the
		-- jobId, so a new server is always a new key and a real round is never skipped.
		-- Keyed on the account, not on the letter. The letter is recomputed every three seconds and
		-- index.csv shows it moving between accounts across sessions, so a copy that came back
		-- holding a different letter sails straight past a key built from it and adds a second row
		-- for the same bot in the same round. The name cannot change inside a round.
		local gk = "__EW_WROTE_" .. tostring(roundKey) .. "_" .. lp.Name
		if getgenv()[gk] then
			-- A refused write has to leave a trace. Without one, a round that really did
			-- vanish reads exactly like a duplicate that was correctly turned away, and that
			-- is the same blind spot the boot claim already has.
			pcall(function()
				appendfile("RobloxComm/autoexec_status.txt", os.date("%Y-%m-%d %H:%M:%S")
					.. "  [panels] round " .. tostring(roundKey) .. " " .. tostring(TEAM.role)
					.. " was already written by an earlier copy of this script - second row refused\n")
			end)
			return
		end
		getgenv()[gk] = true

		local threats = {}
		for _, v in pairs(seenThreats) do
			threats[#threats + 1] = v
		end
		local body = table.concat({
			"round      " .. tostring(roundKey) .. "   jobId " .. tostring(game.JobId),
			"map        " .. tostring(st and st.GameSettings and st.GameSettings.MapName),
			"bot        " .. lp.Name .. "   role " .. TEAM.role .. (TEAM.prime and " [prime]" or ""),
			"team       " .. m.team,
			"ended      " .. os.date("%Y-%m-%d %H:%M:%S") .. "   round len " .. string.format("%.0fs", m.secs),
			"joined     " .. (K.joinDelay and (K.joinDelay .. "s after the server started the round") or "clock never synced - server time unavailable"),
			"podium     " .. tostring(m.podium),
			"",
			"kills      " .. m.kills,
			"damage     dealt " .. m.dealt .. "   taken " .. m.taken,
			"eggs       broken while I was on them: " .. eggsBroken,
			"coins      collected " .. stats.collected .. "   held B/I/G/S " .. m.bronze .. "/" .. m.iron .. "/" .. m.gold .. "/" .. m.shard,
			"buys       " .. stats.buys .. "   adrenaline bought " .. stats.adrenBought,
			"anti-void  catches " .. avCatches,
			"sweeps     tp " .. tpCycles .. "   visits " .. tpVisited .. "   last targets " .. tpLastTargets,
			"teammates  here " .. #TEAM.here .. " of " .. #TEAM.roster .. " known",
			"",
			"threats seen:",
			#threats > 0 and ("  " .. table.concat(threats, "\n  ")) or "  none",
			"",
			"errors this round:",
			#K.loudLog > 0 and ("  " .. table.concat(K.loudLog, "\n  ")) or "  none",
			"",
			"events:",
			#K.ev > 0 and ("  " .. table.concat(K.ev, "\n  ")) or "  none",
			"",
			"timeline  (one line per 0.5s)",
			"      t       y    hp drive sw target             tHp   dist  tgts   fps",
			#K.tl > 0 and (" " .. table.concat(K.tl, "\n ")) or "  none",
			"",
		}, "\n")
		-- Named for the account, not for the role letter. The letter is worked out locally and it
		-- drifts: across the recorded rounds BOT C has filed as A, B and C. Two clients on one
		-- letter write one path, and the second writefile replaced the first bot's whole round with
		-- no error anywhere. The letter is still in the body, on the bot line, where a collision
		-- costs nothing, and index.csv already keys on the account name.
		pcall(writefile, DIR .. "/" .. roundKey .. "/" .. lp.Name .. ".txt", body)

		pcall(
			appendfile,
			INDEX,
			string.format(
				"%d,%s,%s,%s,%s,%s,%s,%.0f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
				os.time(),
				tostring(roundKey),
				tostring(st and st.GameSettings and st.GameSettings.MapName):gsub(",", " "),
				TEAM.role,
				lp.Name,
				m.team,
				tostring(m.podium),
				m.secs,
				m.kills,
				m.dealt,
				m.taken,
				eggsBroken,
				stats.collected,
				stats.buys,
				stats.adrenBought,
				avCatches,
				#threats,
				#K.loudLog
			)
		)
	end

	-- TOTAL is the server's view rather than one bot's, so exactly one bot writes it.
	local function writeTotal(st)
		local lines = {
			"round      " .. tostring(roundKey) .. "   jobId " .. tostring(game.JobId),
			"map        " .. tostring(st and st.GameSettings and st.GameSettings.MapName),
			"ended      " .. os.date("%Y-%m-%d %H:%M:%S") .. "   after " .. string.format("%.0fs", os.clock() - roundStart),
			"written by " .. lp.Name .. " (prime)",
			"",
			"teams:",
		}
		local teams = st and st.GameTeams
		if teams then
			for id, t in pairs(teams) do
				lines[#lines + 1] = string.format(
					"  %-8s %-14s alive %s   eliminated %s",
					tostring(id),
					tostring(t.Name),
					tostring(t.AliveCount),
					tostring(t.Eliminated)
				)
			end
		else
			lines[#lines + 1] = "  (GameTeams unavailable)"
		end

		lines[#lines + 1] = ""
		lines[#lines + 1] = "players (kills gained this round, from the lifetime counter):"
		for _, p in ipairs(Players:GetPlayers()) do
			local base = killsBase[p]
			local now = p:GetAttribute("Kills")
			local gained = (base and now) and (now - base) or nil
			local t = track[p]
			lines[#lines + 1] = string.format(
				"  %-16s uid %-12s team %-7s lv %-4s kills +%s%s",
				p.Name,
				tostring(p.UserId),
				tostring(p:GetAttribute("TeamId")),
				tostring(p:GetAttribute("Level")),
				gained and tostring(gained) or "?",
				(t and t.role) and ("   <<< " .. t.role)
					or (isOwner(p) and "   (owner)" or (K.isBot(p) and "   [bot]" or ""))
			)
		end

		-- The point of the whole farm is the owner's Wins counter, so record it directly instead
		-- of inferring progress from how many rounds happened. If he was not in the round, that
		-- fact is the important one: a round he was not in earns him nothing however well it went.
		lines[#lines + 1] = ""
		local ownerHere, ownerWins = nil, nil
		for _, p2 in ipairs(Players:GetPlayers()) do
			if isOwner(p2) then
				ownerHere = p2.Name
				ownerWins = p2:GetAttribute("Wins")
			end
		end
		if ownerHere then
			lines[#lines + 1] = string.format("OWNER      %s in this round, Wins = %s", ownerHere, tostring(ownerWins))
		else
			lines[#lines + 1] = "OWNER      NOT IN THIS ROUND - nothing earned towards the 10k"
		end
		pcall(
			appendfile,
			"RobloxComm/owner_wins.csv",
			string.format("%d,%s,%s,%s\n", os.time(), tostring(roundKey), tostring(ownerWins or ""), ownerHere and "present" or "absent")
		)
		lines[#lines + 1] = ""
		lines[#lines + 1] = "bots this round:"
		for _, e in ipairs(TEAM.here) do
			lines[#lines + 1] = "  " .. e.name .. "  uid " .. tostring(e.userId)
		end
		lines[#lines + 1] = ""
		pcall(writefile, DIR .. "/" .. roundKey .. "/TOTAL.txt", table.concat(lines, "\n"))
	end

	task.spawn(function()
		claimIdentity()
		beginRound()
		while alive and getgenv().__EWCOIN_GEN == MY_GEN do
			local ok, err = pcall(function()
				if not inMatch() then
					return
				end
				local st = state()
				local gs = st and tostring(st.GameState) or "?"

				-- A new server means a new round even if we never saw the old one finish.
				if keyFor() ~= roundKey then
					beginRound()
					return
				end
				noteThreats()

				-- Only write if we actually watched this round. Loading into a round that has already
				-- finished used to produce a file full of zeroes and an empty timeline, and worse, it
				-- overwrote the real one that the previous copy had just written.
				if gs == "Ended" and not wrote and #K.tl >= 8 then
					wrote = true
					local m = myLine(st)
					writeMine(st, m)
					if TEAM.prime then
						writeTotal(st)
					end
				elseif gs == "Ended" and not wrote then
					-- Four round folders on 2026-08-03 were created and then left completely
					-- empty, which reads exactly like a crash and is not one: the folder is made
					-- at beginRound and the file is only written with eight timeline samples
					-- behind it, so a bot that arrived in the last four seconds of a round wrote
					-- nothing at all and left no clue why. A stub is written instead - still
					-- never over a real file, which is the whole reason the sample floor exists.
					wrote = true
					local path = DIR .. "/" .. roundKey .. "/" .. lp.Name .. ".txt"
					local exists = false
					pcall(function()
						exists = isfile(path)
					end)
					if not exists then
						pcall(writefile, path, table.concat({
							"round      " .. tostring(roundKey) .. "   jobId " .. tostring(game.JobId),
							"bot        " .. lp.Name .. "   role " .. tostring(TEAM.role),
							"",
							string.format("NOT WATCHED. Only %d timeline samples when the round ended, and %d are", #K.tl, 8),
							"needed before the numbers mean anything. This bot loaded into a round that was",
							"already over, or the round ended within about four seconds of it arriving.",
							"Nothing crashed - there was simply nothing to record.",
						}, "\n"))
					end
				end
			end)
			if not ok then
				loud("round log", err)
			end
			task.wait(1)
		end
	end)
end)() end

do (function()
	-- FREE MOUSE. Two earlier versions of this failed, and both failed for the same reason: I
	-- was fighting the symptom. Roblox's own shift lock and CameraMode had nothing to do with
	-- it. Reading the game's code settled it - TS.util.input-util binds LeftControl to
	-- isShiftLock, and TS.controllers.camera-controller answers it with invertCameraLock(),
	-- which flips its own self.locked and drives the mouse from there. Measured on a live
	-- client: locked was true, and unlockCamera() set it false and released the cursor.
	--
	-- So this asks the game to unlock, rather than overwriting the property the game is
	-- setting. That also fixes an ordering problem the property approach could never win: the
	-- camera runs on BindToRenderStep at priority Camera, which is AFTER every RenderStepped
	-- connection, so anything written there is overwritten in the same frame - which is why
	-- the value read back correct and the cursor still behaved as locked.
	local freeMouse = true
	local mouseBtn = button(stopFrame, "FREE MOUSE: ON", 8, 72, 340, 26)
	mouseBtn.Font = Enum.Font.GothamBold
	mouseBtn.BackgroundColor3 = Color3.fromRGB(38, 110, 60)

	-- Found by identity rather than by its id string: Flamework ids are build output and can
	-- change when the game updates, but the controller that owns unlockCamera is the one we
	-- want whatever it ends up being called. "EPe" today, checked first only because it is
	-- cheap, with the scan as the answer that keeps working.
	-- The screen controller is the one that actually decides. camera-controller runs a
	-- Heartbeat loop that reads screenController:isCursorLocked() EVERY frame and sets the
	-- mouse from it, so unlocking the camera is undone on the next heartbeat - which is why
	-- the previous two attempts kept coming undone. Making that one function answer false is
	-- what makes the game itself keep the cursor free, using its own code path.
	-- Our own right-button flag, because the game's one gets stuck.
	--
	-- Measured on bot A, 2026-08-16 02:5x: UserInputService:IsMouseButtonPressed(MouseButton2)
	-- returned true with nobody touching the mouse, and MouseBehavior sat on
	-- LockCurrentPosition and would not come back - setting it to LockCenter and reading a
	-- second later gave LockCurrentPosition again. A press had been delivered without its
	-- release, so from the client's side the right button is held forever.
	--
	-- My first fix trusted that reading and made it worse: freeIt stopped restoring the
	-- cursor because it believed he was mid-drag, permanently. So the flag is now kept from
	-- the events themselves, cleared when the window loses focus, and force-cleared after
	-- eight seconds - nobody turns a camera for eight seconds straight, and a stuck button
	-- must never be able to hold the cursor hostage again.
	local rmbDown, rmbSince = false, 0
	local function rmbHeld()
		if not rmbDown then
			return false
		end
		if os.clock() - rmbSince > 8 then
			rmbDown = false
			return false
		end
		return true
	end
	bind(UserInputService.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rmbDown, rmbSince = true, os.clock()
		end
	end)
	bind(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rmbDown = false
		end
	end)
	bind(UserInputService.WindowFocusReleased, function()
		rmbDown = false
	end)

	local screenCtrl, screenOrig
	local function scCtrl()
		if screenCtrl then
			return screenCtrl
		end
		if not K.fwReady then
			return nil
		end
		pcall(function()
			local core = require(ReplicatedStorage.rbxts_include.node_modules["@flamework"].core.out)
			local got = K.ctrl("screen-controller", "r8A")
			if type(got) == "table" and type(got.isCursorLocked) == "function" then
				screenCtrl = got
				screenOrig = got.isCursorLocked
			end
		end)
		return screenCtrl
	end

	local cam
	local function camCtrl()
		if cam then
			return cam
		end
		if not K.fwReady then
			return nil
		end
		pcall(function()
			local core = require(ReplicatedStorage.rbxts_include.node_modules["@flamework"].core.out)
			local c = K.ctrl("camera-controller", "EPe")
			if type(c) == "table" and type(c.unlockCamera) == "function" then
				cam = c
				return
			end
			-- No registry-wide scan. Resolving every id instantiates every controller in the
			-- game, which is what broke the lobby UI. If this id ever stops being right, fix the
			-- id here rather than brute forcing it at runtime.
		end)
		return cam
	end

	-- Stand down while a human is on this window. That is the whole fix for bug 1.
	--
	-- FREE MOUSE rewrites CameraMode, DevEnableMouseLock, MouseBehavior and the game's own
	-- isCursorLocked five times a second. On an unattended bot that is exactly right - the
	-- cursor stays free and nothing steals it. On the window HE is playing on it is a
	-- tug-of-war with the game's control script at 5 Hz, and that is what he feels as the
	-- pointer jumping and the camera not answering: "the mouse position will be buggy and
	-- not like normal".
	--
	-- So it now watches for real input. Any mouse move, click or key press on this client
	-- means a person is here, and for the next five seconds the game owns the mouse
	-- completely. Five seconds after he stops touching it, the cursor is freed again. He
	-- does not have to press anything and neither do I - the window he is using fixes
	-- itself, and the three he is not carry on as before.
	local lastHuman = 0
	bind(UserInputService.InputBegan, function(_, typing)
		if not typing then
			lastHuman = os.clock()
		end
	end)
	bind(UserInputService.InputChanged, function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.MouseWheel then
			lastHuman = os.clock()
		end
	end)

	local function freeIt()
		if not freeMouse then
			return
		end
		if os.clock() - lastHuman < 5 then
			return
		end
		-- The one that actually matters: stop the game deciding it wants a locked cursor.
		local sc = scCtrl()
		if sc and rawget(sc, "__ewFree") == nil then
			rawset(sc, "__ewFree", true)
			-- Hand the game its cursor back while the right button is down.
			--
			-- His report, 2026-08-16 after a shower: "the mouse right long press on it was
			-- for changing view but it will change the mouse position". That is this line.
			-- Holding right-mouse turns the camera by LOCKING the cursor in place and reading
			-- the delta; FREE MOUSE was answering isCursorLocked() with a flat false every
			-- frame, so the cursor was never locked and the drag moved the pointer across the
			-- screen instead of turning the view.
			--
			-- While the right button is held, the original answer is used, so the camera
			-- behaves exactly like a normal client. The moment he lets go the cursor is free
			-- again, which is the whole point of FREE MOUSE.
			sc.isCursorLocked = function(...)
				if rmbHeld() then
					if type(screenOrig) == "function" then
						local ok, was = pcall(screenOrig, ...)
						if ok then
							return was
						end
					end
					return true
				end
				return false
			end
		end
		local c = camCtrl()
		if c and c.locked then
			pcall(function()
				c:unlockCamera()
			end)
		end
		-- Backstops, in case a future update moves the lock somewhere else.
		pcall(function()
			if lp.DevEnableMouseLock then
				lp.DevEnableMouseLock = false
			end
			if lp.CameraMode ~= Enum.CameraMode.Classic then
				lp.CameraMode = Enum.CameraMode.Classic
			end
			if lp.CameraMinZoomDistance < 8 then
				lp.CameraMinZoomDistance = 8
			end
			-- Same exception here: forcing Default every frame is the other half of what
			-- broke the right-drag, because that is the property the camera sets to lock.
			if not rmbHeld()
				and UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
			if not UserInputService.MouseIconEnabled then
				UserInputService.MouseIconEnabled = true
			end
		end)
	end

	bind(mouseBtn.MouseButton1Click, function()
		freeMouse = not freeMouse
		if not freeMouse and screenCtrl and screenOrig then
			-- Hand the real function back rather than leaving a stub behind.
			screenCtrl.isCursorLocked = screenOrig
			rawset(screenCtrl, "__ewFree", nil)
		end
		mouseBtn.Text = freeMouse and "FREE MOUSE: ON" or "FREE MOUSE: OFF (game controls it)"
		mouseBtn.BackgroundColor3 = freeMouse and Color3.fromRGB(38, 110, 60) or Color3.fromRGB(38, 38, 48)
		freeIt()
	end)

	-- Respawn puts the game back into whatever Profile.FirstPerson says, so catch it there.
	bind(lp.CharacterAdded, function()
		task.wait(0.15)
		freeIt()
	end)

	task.spawn(function()
		claimIdentity()
		while alive and getgenv().__EWCOIN_GEN == MY_GEN do
			freeIt()
			task.wait(0.2)
		end
	end)
end)() end

-- AUTO ACCEPT PARTY INVITE.
--
-- The owner has to press Accept on three separate windows every single time he rebuilds the
-- party, which is every time his phone crashes or a session restarts. This answers for them.
--
-- It does not click the notification button - there is no way to click a button on an
-- unfocused window. It listens for the same event the notification is built from and fires
-- the same reply the Accept button fires, with the same arguments, taken from the game's own
-- party-controller: the incoming event hands over (partyId, invitingPlayer, token) and Accept
-- is that token replied to with true.
--
-- It accepts ONLY from an owner UserId. Auto-accepting anything would let any stranger drag
-- all three bots into their party, and a bot in someone else's party earns nothing.
do
	-- Both ids come out of the game's own party-controller, not from guessing: the incoming
	-- event is the one it connects next to the string "has invited you to their party", and
	-- Accept is its updateInvite(partyId, token, true), which fires the reply. The game updated
	-- on 2026-08-03 and both ids changed, so every round from 16:17 to 17:40 - 257 of them -
	-- logged "invite event ids no longer present" and nothing was ever accepted. If that line
	-- comes back, grep the decompiled party-controller for that same invite string and take
	-- the pair again; the argument order has not changed across either update.
	-- Writes straight to disk instead of K.event. K.event appends to K.ev, which is
	-- flushed only by the round writer, which returns early when not inMatch(), and
	-- K.ev is wiped on every teleport. The party is rebuilt in the LOBBY, so every
	-- line this feature has ever produced there was thrown away unread. Inlined path
	-- rather than the ROUND_LOG local, which is out of scope in this block.
	local function inviteLog(text)
		K.inviteLine = text
		pcall(appendfile, "RobloxComm/round_log.txt", string.format("%s  %-14s auto-accept: %s\n",
			os.date("%Y-%m-%d %H:%M:%S"), lp.Name, text))
	end
	-- Read out of the game's own source on 2026-08-05, place version 399, not
	-- guessed and not caught by watching. Both live in the party controller at
	-- Players.<you>.PlayerScripts.TS.controllers.party-controller:
	--
	--   line 53   Events["da9e0627-..."]:connect(function(a1, p2, p3)   <- the invite arriving
	--             and the notification it builds says "has invited you to their party"
	--   line 111  Events["4315d525-..."]:fire(p2, p3, p4)               <- updateInvite, the reply
	--             called as  updateInvite(partyId, token, true)  by the notification's Accept
	--
	-- which is why the handler below takes (partyId, fromPlayer, token) and replies
	-- with (partyId, token, true) - that ordering is the game's, not a convention.
	--
	-- The pair before this was ed7cfb91 / 53989916. Those ids are simply gone from
	-- the events table now, which is what "invite event ids no longer present" in
	-- round_log.txt was reporting correctly all along. Expect the same again after
	-- a game update: rebuild the script index and grep the party controller.
	-- ACCEPT ANY PENDING INVITE, EVERY 2 SECONDS.
	--
	-- His call, 2026-08-14: mkae sure it will auto accpt any ivnite, the bot it will eahc
	-- 2sec auto accpt any ivnite.
	--
	-- This one does not go through the events table, and that is the point. Measured
	-- 2026-08-14 on two live clients: the lobby exposes 101 events, the match exposes 101
	-- events, and the two lists share not a single id - so an id hooked in the lobby means
	-- nothing inside a round. The party controller is the same object in both places, and it
	-- carries updateInvite(partyId, token, accept), which is exactly what the game's own
	-- Accept button calls.
	--
	-- The old comment in this file claiming a match has no PlayerScripts.TS.events was wrong.
	-- It is there, with 101 entries. He caught that.
	task.spawn(function()
		getgenv().__ACCEPT_GEN = (getgenv().__ACCEPT_GEN or 0) + 1
		local MY_ACCEPT_GEN = getgenv().__ACCEPT_GEN
		while getgenv().__ACCEPT_GEN == MY_ACCEPT_GEN do
			task.wait(2)
			pcall(function()
				local prb = K.ctrl("party-controller", "PrB")

				-- Say what was found, once in a while, instead of leaving silently.
				--
				-- Measured 2026-08-15 across 6.8 MB of round_log.txt: this poller has written
				-- exactly zero lines since it was added. Not one AUTO ACCEPTED and not one
				-- "auto accept failed" either - which is the tell. Every accept in that file,
				-- all 396 of them, came from the event hook instead.
				--
				-- The reason is the guard that used to be here: it returned on anything it did
				-- not recognise without writing a word, so a controller whose pending invites
				-- do not live in a field called notifications looked identical to a lobby with
				-- no invites in it. A check that cannot fail out loud cannot be debugged, and
				-- this one hid its own failure for a day.
				local shape = type(prb)
				local nshape = (shape == "table") and type(prb.notifications) or "n/a"
				local now = os.clock()
				if (now - (getgenv().__ACCEPT_SAID or 0)) > 30 then
					getgenv().__ACCEPT_SAID = now
					local keys = {}
					if shape == "table" then
						for k, v in pairs(prb) do
							if #keys < 12 then
								keys[#keys + 1] = tostring(k) .. ":" .. type(v)
							end
						end
					end
					inviteLog(string.format("poll sees prb=%s notifications=%s fields[%s]",
						shape, nshape, table.concat(keys, " ")))
				end

				if shape ~= "table" or nshape ~= "table" then
					return
				end
				for key, v in pairs(prb.notifications) do
					local partyId, token
					if type(v) == "table" then
						partyId = v.partyId or v.PartyId or v.id or key
						token = v.token or v.Token or v.inviteToken
					else
						partyId, token = key, v
					end
					if partyId ~= nil and token ~= nil then
						local ok, err = pcall(function()
							prb:updateInvite(partyId, token, true)
						end)
						inviteLog(ok
							and ("AUTO ACCEPTED " .. tostring(partyId):sub(1, 8))
							or ("auto accept failed: " .. tostring(err)))
					end
				end
			end)
		end
	end)

	local INVITE_IN = "da9e0627-ff7e-44a2-9453-e021c0a66f5e"
	local INVITE_REPLY = "4315d525-6b6f-467e-9b0d-f7c72ab200a4"
	local accepted, lastFrom = 0, "-"

	task.spawn(function()
		claimIdentity()
		-- Arm as early as the events module can be reached, NOT after Flamework is
		-- ready like everything else here.
		--
		-- 2026-08-05: the owner invited all three at 16:20:11. BOT B had armed
		-- at 16:20:10 and accepted at 16:20:11. BOT C loaded twelve seconds later
		-- and only armed at 16:20:27, so the invite arrived sixteen seconds before it
		-- was listening and it had to be accepted by hand. Nothing was broken - it
		-- was not there yet.
		--
		-- The connection is to an event, so it only ever sees what fires after it.
		-- Waiting for K.fwReady bought nothing: requiring PlayerScripts.TS.events
		-- needs PlayerScripts to exist and nothing more, which is what this waits
		-- for now. That removes almost the whole window.
		local t0 = os.clock()
		while alive and getgenv().__EWCOIN_GEN == MY_GEN
			and not lp:FindFirstChild("PlayerScripts") and os.clock() - t0 < 90 do
			task.wait(0.25)
		end

		-- Keep trying instead of giving up. The old version returned on the first failure, so
		-- one early miss killed auto accept for the whole session - including in the lobby,
		-- which is the only place it matters, because that is where the owner rebuilds the
		-- party. Only the first failure and then every sixth are written out, so a genuinely
		-- broken id still reaches the panel without a line every ten seconds.
		-- Same id as LOBBY_PLACE further up, redeclared because that one is a local
		-- inside another do block and is not in scope here.
		local INVITE_LOBBY = 8542259458

		local tries = 0
		while alive and getgenv().__EWCOIN_GEN == MY_GEN do
			-- Only the lobby. The match place has no PlayerScripts.TS.events at all,
			-- so every attempt there failed and wrote a line, on three clients, every
			-- sixty seconds, for the whole of every round - round_log.txt reached 6.2 MB
			-- of it. Invites only ever arrive in the lobby anyway, so there was never
			-- anything to arm in a match.
			-- The event hook still only arms where its two ids exist, which is the lobby.
			-- The poller above is what covers a round.
			while alive and getgenv().__EWCOIN_GEN == MY_GEN
				and game.PlaceId ~= INVITE_LOBBY do
				task.wait(10)
			end
			if not alive or getgenv().__EWCOIN_GEN ~= MY_GEN then
				return
			end
			tries = tries + 1
			local why
			local okEv, events = pcall(function()
				return require(lp.PlayerScripts.TS.events).Events
			end)
			if not okEv or type(events) ~= "table" then
				why = "cannot reach the events table: " .. tostring(events)
			else
				local incoming, reply = events[INVITE_IN], events[INVITE_REPLY]
				if not incoming or not reply then
					why = "invite event ids no longer present - the game was probably updated"
				else
					local ok, err = pcall(function()
						incoming:connect(function(partyId, fromPlayer, token)
							-- The whole body is wrapped. An error thrown in here is swallowed by
							-- the game's own dispatcher, so without this a broken handler and an
							-- event that never fires look identical from outside - which is the
							-- ambiguity that made me read this feature wrong in the first place.
							local okCb, cbErr = pcall(function()
							-- Accept anything. His call, 2026-08-14: the account is already set so that
							-- only friends can invite it, so the filtering has already happened before
							-- the invite ever reaches here, and a second filter on this side only creates
							-- a way to miss a real one.
							local okFire, fireErr = pcall(function()
								reply:fire(partyId, token, true)
							end)
							if okFire then
								accepted = accepted + 1
								lastFrom = tostring(type(fromPlayer) == "number" and fromPlayer or (fromPlayer and fromPlayer.Name))
								inviteLog("ACCEPTED from " .. lastFrom .. "  (total " .. accepted .. ")")
							else
								inviteLog("FIRE FAILED: " .. tostring(fireErr))
							end
							end)
							if not okCb then
								inviteLog("HANDLER THREW: " .. tostring(cbErr))
							end
						end)
					end)
					if ok then
						inviteLog(string.format("armed in place %d%s", game.PlaceId, tries > 1 and (" after " .. tries .. " tries") or ""))
						return
					end
					why = tostring(err)
				end
			end
			if tries == 1 or tries % 6 == 0 then
				inviteLog(why .. "  (try " .. tries .. ", still retrying)")
			end
			task.wait(10)
		end
	end)
end

-- VAPE VISUALS OFF - this is the 10 GB client.
--
-- Vape V4 leaks, and it is not the farm. Measured 2026-08-03 with two clients side by side:
-- with the farm killed outright the client still grew 50 MB a minute, and the growth stopped
-- dead - 0.5 MB a minute - the moment shared.vape:Uninject() ran, while the untouched control
-- carried on at 68. Roblox's own Stats never sees it (it reported 3 GB while the process held
-- 13) and cleardrawcache frees none of it, so it is not leaked Drawing handles either. At 60
-- to 70 MB a minute that is 4 GB an hour: three clients on a 16 GB laptop reach swap in about
-- three hours, which is the whole of "the client is at 10 GB again".
--
-- Uninjecting stops the growth but never gives the memory back, so the only cure is a smaller
-- rate. Turning off the eight purely visual modules halved it, 68 MB a minute down to 29, and
-- nobody is looking at a bot's screen so there is nothing to lose. The remaining 29 still has
-- to be bisected module by module; that needs live clients.
--
-- Deliberately once per round and not in a loop: if he opens Vape's own menu and switches ESP
-- back on to look at something, it stays on.
do (function()
	-- HitBoxes is NOT in this list even though it was in the first version. Vape's own tooltip
	-- says "Expands entities hitboxes" and it has a Part dropdown and an Expand slider - it
	-- grows the target's collision box so the aura connects. That is the attack side, and the
	-- attack side stays untouched. Everything below draws something and nothing more.
	local VISUAL = { "Chams", "ESP", "NameTags", "Tracers", "Arrows", "Waypoints", "Search" }

	-- And the two that must be ON, because Vape's saved settings are keyed by PLACE, not by
	-- account: every client on this machine shares
	-- newvape/profiles/default8768229691.txt, and the last one to change anything wins. On
	-- 2026-08-03 a test account on a fourth client turned Breaker off and the bots would have
	-- loaded that file on their next round with no egg breaking at all and nothing on screen
	-- to say why. Killaura is where every kill comes from and Breaker is where every win comes
	-- from; if either is off the round is already lost, so they are asserted rather than
	-- trusted. Everything else is left exactly as the profile says.
	local REQUIRED = { "Killaura", "Breaker" }

	-- Four more that a bot provably cannot use, turned off for the same reason as the visuals:
	-- every module Vape runs is more of the 29 MB a minute it leaks. AutoClicker only ticks
	-- while MouseButton1 is physically held (its InputBegan starts it, InputEnded cancels it),
	-- and nobody is holding a button on a bot. Fullbright is lighting. InvMove only matters
	-- with a menu open. Anti-AFK is already done by this file, permanently, further down.
	-- AntiFall has to be off, and it has to be turned off again after every reinject.
--
-- His report, 2026-08-16: below about -15 the bot would not go down, it stood on nothing
-- and hopped back up. That is Vape's AntiFall doing its job - it exists to stop you walking
-- off an edge, and going ten studs under an egg looks exactly like walking off an edge.
-- Killing it by hand is not enough because the vape cycle reloads a fresh copy each round
-- and the profile brings it back on, so it goes in this list, which vapeTidy re-applies on
-- every load.
--
-- Falling is still covered: NoFall stays on for the damage, and the farm's own ANTI VOID
-- floor sits at Y -70 with catch-back, far below anything he needs for the egg.
local USELESS = { "AutoClicker", "Fullbright", "InvMove", "Anti-AFK", "AntiFall" }

	-- Lifted out of the loop below and hung on K so the on demand cycle can call it too. A
	-- reinjected Vape is a brand new Vape: it reads the shared profile off disk again, so it
	-- comes back with every visual switched on and possibly with Killaura off. Without this
	-- being callable, bringing Vape back would quietly undo the halving that this whole block
	-- exists to achieve, and nothing on screen would say so.
	function K.vapeTidy()
		local v = rawget(shared, "vape")
		if type(v) ~= "table" or type(v.Modules) ~= "table" then
			return false
		end
		local off = {}
		for _, list in ipairs({ VISUAL, USELESS }) do
			for _, n in ipairs(list) do
				local m = v.Modules[n]
				if type(m) == "table" and m.Enabled then
					if pcall(function() m:Toggle(false) end) then
						off[#off + 1] = n
					end
				end
			end
		end
		local back = {}
		for _, n in ipairs(REQUIRED) do
			local m = v.Modules[n]
			if type(m) == "table" and not m.Enabled then
				if pcall(function() m:Toggle(true) end) then
					back[#back + 1] = n
				end
			end
		end
		K.event("vape visuals off: " .. (#off > 0 and table.concat(off, ", ") or "none were on"))
		if #back > 0 then
			loud("vape", "turned BACK ON: " .. table.concat(back, ", ") .. " - the shared profile had them off")
		end
		return true
	end

	task.spawn(function()
		claimIdentity()
		local t0 = os.clock()
		while alive and getgenv().__EWCOIN_GEN == MY_GEN do
			if K.vapeTidy() then
				return
			end
			if os.clock() - t0 > 120 then
				K.event("vape visuals: vape never loaded, nothing to turn off")
				return
			end
			task.wait(2)
		end
	end)
end)() end

-- VAPE ON DEMAND - the other half of the 10 GB client.
--
-- Uninjecting stops the leak dead - 68 MB a minute down to 0.5, measured 2026-08-03 - but it
-- never hands back what has already gone. Turning the visuals off halved the rate and that is
-- as far as a smaller rate can go. The only thing left to shrink is how long Vape is loaded
-- at all, and a bot needs it in exactly one situation: alive, in the match place, in a round
-- that has actually started. The lobby, the queue, Pregame, and every second it spends dead
-- waiting for the next round are all time it is paying rent for nothing.
--
-- shared.vape:Uninject() is precisely what Vape's own red Self destruct button calls, and
-- re-running the loader is its Reinject - the loader's first line is
-- "if shared.vape then shared.vape:Uninject() end", so a reinject cleans up after itself and
-- the two can never end up stacked.
--
-- The trigger is the round state and never an enemy walking into range. Reinjecting rebuilds
-- the entire menu on a client running at four frames a second and is not instant, so it has
-- to start well before the first fight rather than at it.
--
-- Anti-AFK does not ride on Vape here, so dropping Vape cannot get a bot kicked: this file
-- does its own, further down, and it deliberately keeps Vape's Anti-AFK module switched off.
-- Every single name below lives inside the spawned function and not out here. The main chunk
-- of this file is one Luau function and Luau gives a function 200 registers; eight constants
-- at this level plus one button is what pushed it over on 2026-08-05 and stopped the whole
-- farm compiling. Nothing new belongs at the top level of this file, ever.
do (function()
	K.vapeCycle = "waiting"
	K.vapeFlips = 0

	task.spawn(function()
		claimIdentity()

		local VAPE_SRC = "https://rawscripts.net/raw/Vape-V4-For-Roblox_316"

		-- Twenty five seconds of not needing it before it goes. Short enough that a whole lobby
		-- wait is reclaimed, long enough that the gap between dying and the round ending does
		-- not turn into a reinject the moment the bot respawns.
		local DROP_AFTER = 25

		-- And a floor on how often the pair may happen at all. Without it a bot flickering
		-- between alive and dead would spend the round loading Vape instead of using it.
		local MIN_GAP = 45

		local busy = false
		local idleSince = nil
		local lastFlip = 0

		local function loaded()
			return type(rawget(shared, "vape")) == "table"
		end

		-- Spectating is asked separately from Alive on purpose. A spectator sits inside InGame
		-- with the round running and never reports itself dead - that is the exact state three
		-- bots were stuck in, and it is the one where Vape is most obviously useless.
		local function needed()
			if not cfg.vapeCycle then
				return true
			end
			-- Being in the match place is enough, and that is deliberate.
			--
			-- The first version waited for InGame, which meant the loader started rebuilding
			-- the whole menu at the exact moment the round did - on a client at two frames a
			-- second that is seconds of a fight with no Killaura. Arriving in the match place
			-- happens during Pregame, half a minute before anyone can be hit, so by the time
			-- the round starts Vape is already up. He asked for it to be there instantly; the
			-- way to be instant at the start of a round is to be early, not fast.
			if not inMatch() then
				return false
			end
			-- A finished round needs nothing. This is where the bots spend most of their
			-- wasted time, so it is worth as much as the lobby.
			if K.gameState == "Ended" then
				return false
			end
			if lp:GetAttribute("Spectating") then
				return false
			end
			return true
		end

		while alive and getgenv().__EWCOIN_GEN == MY_GEN do
			task.wait(3)
			if not cfg.vapeCycle then
				K.vapeCycle = loaded() and "cycle off - vape stays loaded" or "cycle off - vape not loaded"
			elseif busy then
				-- nothing; a flip is in flight
			else
				local want = needed()
				local have = loaded()
				local gap = os.clock() - lastFlip

				if want and not have then
					if gap > MIN_GAP or lastFlip == 0 then
						busy = true
						K.vapeCycle = "reinjecting"
						task.spawn(function()
							claimIdentity()
							local ok, err = pcall(function()
								loadstring(game:HttpGet(VAPE_SRC))()
							end)
							if ok then
								lastFlip = os.clock()
								K.vapeFlips = K.vapeFlips + 1
								K.event("vape reinjected for the round")
								-- Wait for the loader to finish building before straightening it
								-- out, then straighten it out. A fresh Vape has the profile's
								-- visuals back on and this is the only thing that removes them.
								task.wait(6)
								K.vapeTidy()
								K.vapeCycle = "loaded"
							else
								K.vapeCycle = "REINJECT FAILED"
								loud("vape-cycle", "reinject failed: " .. tostring(err))
							end
							busy = false
						end)
					else
						K.vapeCycle = string.format("waiting %.0fs to reinject", MIN_GAP - gap)
					end
				elseif (not want) and have then
					idleSince = idleSince or os.clock()
					local idle = os.clock() - idleSince
					if idle > DROP_AFTER and (gap > MIN_GAP or lastFlip == 0) then
						busy = true
						local v = rawget(shared, "vape")
						local ok, err = pcall(function()
							v:Uninject()
						end)
						if ok then
							lastFlip = os.clock()
							K.vapeFlips = K.vapeFlips + 1
							idleSince = nil
							K.vapeCycle = "self destructed - idle"
							K.event("vape uninjected, nothing to fight")
						else
							K.vapeCycle = "UNINJECT FAILED"
							loud("vape-cycle", "uninject failed: " .. tostring(err))
						end
						busy = false
					else
						K.vapeCycle = string.format("idle %.0fs, dropping at %ds", idle, DROP_AFTER)
					end
				else
					idleSince = nil
					K.vapeCycle = have and "loaded - in the round" or "gone - idle"
				end
			end
		end
	end)
end)() end

bind(stopButton.MouseButton1Click, function()
	setFarmPaused(not cfg.farmPaused)
end)

-- Apply the 3D flag once at load. Without this the flag says OFF while the screen is
-- still drawing, so the first click only puts reality back in sync and it takes two.
task.spawn(function()
	claimIdentity()
	local applied
	local fails = 0
	local lastInMatch = inMatch()
	while alive and getgenv().__EWCOIN_GEN == MY_GEN do
		-- Blanking the screen saves real work during a match, where nobody is looking. In the
		-- lobby it leaves the owner staring at nothing while trying to accept a team invite,
		-- which is exactly what it did. So the lobby always renders, whatever the flag says.
		local want = true
		if inMatch() then
			want = cfg.ram3d
		end
		-- The give-up counter must never be able to strand the screen OFF.
		--
		-- `fails < 3` on its own is a one way gate: it only resets on success, so if the call
		-- ever works once (screen off in a match) and then throws three times, this client
		-- spends the rest of the night black with nothing but a line on a panel nobody can see
		-- because the panel is not being drawn. Turning the picture back ON is the recovery
		-- direction and is never rationed, and a change of place clears the count so a new
		-- round always gets three fresh attempts.
		if inMatch() ~= lastInMatch then
			lastInMatch = inMatch()
			fails = 0
		end
		if want ~= applied and (fails < 3 or want == true) then
			-- applied used to be written BEFORE the call and the pcall result was thrown away,
			-- so a call that threw was recorded as a success, never retried, and never shown
			-- anywhere. Set3dRenderingEnabled is not in the API dump Real ships - checked
			-- against roblox-api-docs.json with BindToRenderStep as the control, 15 hits for
			-- the control and 0 for this one - so the throwing case is the likely one, which
			-- would mean the screen has been drawing every round while the panel said OFF.
			-- Three failures is enough to know; after that it stops asking and leaves the
			-- reason on the panel instead of overwriting it once a second forever.
			local ok3d, err3d = pcall(function()
				RunService:Set3dRenderingEnabled(want)
			end)
			if ok3d then
				applied = want
				fails = 0
			else
				fails = fails + 1
				pcall(function()
					ramError.Text = "! 3d render unavailable: " .. tostring(err3d)
				end)
			end
		end
		task.wait(1)
	end
end)

-- Anti-AFK, permanently on and deliberately given no switch: a farm that gets kicked for
-- idling after 20 minutes is not a farm.
do (function()
	-- This one goes FIRST. It disables every existing listener on Idled, and the VirtualUser
	-- reply below is a listener on Idled - run the other way round it would switch off the
	-- thing it had just installed.
	--
	-- The stronger of the two, and taken from Vape's own Anti-AFK module in
	-- newvape/games/universal.lua line 6678. It does not answer the idle signal at all - it
	-- disables Roblox's own listener on it, so the kick is never delivered rather than being
	-- answered. Measured on the phone at 19:59:54 on 2026-08-05: one listener on Idled, and
	-- that one listener is the kick.
	--
	-- Both are kept because they fail for different reasons and neither costs anything.
	local ok2, err2 = pcall(function()
		local gc = getconnections
		if type(gc) ~= "function" then
			error("getconnections not available")
		end
		local n = 0
		for _, c in ipairs(gc(lp.Idled)) do
			if typeof(c.Disable) == "function" then
				c:Disable()
				n = n + 1
			end
		end
		K.event(string.format("anti-afk: disabled %d roblox listeners on Idled", n))
	end)
	if not ok2 then
		loud("anti-afk", "could not disable the Idled listeners: " .. tostring(err2))
	end

	local ok, err = pcall(function()
		local vu = game:GetService("VirtualUser")
		bind(lp.Idled, function()
			vu:CaptureController()
			vu:ClickButton2(Vector2.new())
		end)
	end)
	if not ok then
		warn("[panels] anti-afk failed: " .. tostring(err))
	end
end)() end


-- DistributedGameTime is seconds since this client's DataModel started running, which is
-- exactly "how long since I joined this server". Its own loop so the milliseconds move.
task.spawn(function()
	claimIdentity()
	while alive and getgenv().__EWCOIN_GEN == MY_GEN do
		local ok = pcall(function()
			local t = workspace.DistributedGameTime
			timerLabel.Text = string.format("%02d:%02d.%03d", math.floor(t / 60), math.floor(t % 60), math.floor((t % 1) * 1000))
			timerSub.Text = K.clockBad
					and ("! round clock refused: " .. tostring(K.clockBad))
				or string.format("%.1f min in this server", t / 60)
		end)
		if not ok then
			timerSub.Text = "timer unavailable"
		end
		RunService.Heartbeat:Wait()
	end
end)

task.spawn(function()
	claimIdentity()
	while alive and getgenv().__EWCOIN_GEN == MY_GEN do
		if cfg.enabled and K.roundLive() then
			-- Eggs decide the round, coins do not. While AUTO EGG still has eggs to break
			-- the collector holds off completely, then picks straight back up.
			-- Eggs first, then people. The collector only takes over once there is nobody
			-- left to hit; while AUTO TP has targets it grabs coins on the way instead, so
			-- the two never fight over where the character stands.
			-- The collector is the fourth thing that writes HumanoidRootPart.CFrame and it was
			-- the only mover with no settle at all: with TeamId not replicated yet there are no
			-- eggs and no targets, so it took over and moved the fresh body itself. Held only
			-- while the sweep loop is running, because that loop is the only thing that clears
			-- the flag - a stopped sweep must not be able to freeze coins with no reason shown.
			if (cfg.tpOn or cfg.eggOn) and not K.settleDone then
				coinPaused = true
			elseif (cfg.eggOn and eggsLeft() > 0) or (cfg.tpOn and tpLastTargets > 0) then
				coinPaused = true
			else
				coinPaused = false
				local ok, err = pcall(collectPass)
				if not ok then
					-- Show it, do not switch the farm off.
					--
					-- One thrown error used to set cfg.enabled = false, and because
					-- farmPaused stayed false the saver wrote that off state to disk about
					-- four seconds later - so a single bad frame killed coin collecting for
					-- good, on a panel that looked exactly like he had pressed STOP himself.
					pcall(setError, tostring(err))
				end
			end
		end
		task.wait(0.03)
	end
end)

task.spawn(function()
	claimIdentity()
	while alive and getgenv().__EWCOIN_GEN == MY_GEN do
		pcall(ensureMeleeHeld)
		if cfg.autoBuy and inMatch() then
			pcall(retuneCoinTypes)
			local ok, err = pcall(buyPass)
			if not ok then
				pcall(setBuyError, tostring(err))
			end
		end
		RunService.Heartbeat:Wait()
	end
end)

task.spawn(function()
	claimIdentity()
	while alive and getgenv().__EWCOIN_GEN == MY_GEN do
		local ok, err = pcall(trackPass)
		if not ok then
			loud("tracker", err)
			pcall(function()
				trackHeader.Text = "! tracker " .. tostring(err)
			end)
		end
		task.wait(0.06)
	end
end)

bind(avSnapButton.MouseButton1Click, function()
	local r = root()
	if not r then
		avError.Text = "! no character"
		return
	end
	local hit = workspace:Raycast(r.Position, Vector3.new(0, -400, 0), rayParams)
	cfg.avY = math.floor((hit and hit.Position.Y or r.Position.Y) - 35)
	avError.Text = ""
end)

task.spawn(function()
	claimIdentity()
	while alive and getgenv().__EWCOIN_GEN == MY_GEN do
		if cfg.avFloor or cfg.avCatch then
			local ok, err = pcall(avPass)
			if not ok then
				-- The anti void loop above all: if this is throwing every frame the character is
				-- unprotected and the label it writes to is overwritten faster than anyone can read.
				loud("anti-void", err)
				pcall(function()
					avError.Text = "! " .. tostring(err)
				end)
			end
		else
			destroyFloor()
		end

		RunService.Heartbeat:Wait()
	end
end)

task.spawn(function()
	claimIdentity()
	while alive and getgenv().__EWCOIN_GEN == MY_GEN do
		if (cfg.tpOn or cfg.eggOn) and K.roundLive() then
			local ok, err = pcall(tpPass)
			if not ok then
				loud("tp/egg sweep", err)
				pcall(function()
					tpError.Text = "! " .. tostring(err)
					eggError.Text = "! " .. tostring(err)
				end)
			end
		else
			tpState = "off"
			tpCurrent = "-"
			K.tpCurrent = tpCurrent
			eggState = "off"
			eggCurrent = "-"
		end
		RunService.Heartbeat:Wait()
	end
end)

task.spawn(function()
	claimIdentity()
	local lastCollected, lastClock, nextSplit = 0, os.clock(), 10
	while alive and getgenv().__EWCOIN_GEN == MY_GEN do
		local ok, err = pcall(function()
			master.Text = cfg.enabled
					and (coinPaused and ((K.liveAt and not K.settleDone) and "PAUSED - SETTLING" or eggsLeft() > 0 and "PAUSED - EGGS FIRST" or "PAUSED - KILLING") or "STOP")
				or "START"
			master.BackgroundColor3 = cfg.enabled
					and (coinPaused and Color3.fromRGB(120, 96, 30) or Color3.fromRGB(150, 40, 40))
				or Color3.fromRGB(38, 90, 48)
			autoMaster.Text = cfg.autoBuy and "AUTO BUY: ON" or "AUTO BUY: OFF"
			autoMaster.BackgroundColor3 = cfg.autoBuy and Color3.fromRGB(150, 40, 40) or Color3.fromRGB(38, 90, 48)
			enemyButton.Text = cfg.trackEnemiesOnly and "SHOW: ENEMIES ONLY" or "SHOW: EVERYONE"

			avFloorButton.Text = cfg.avFloor and "FLOOR: ON" or "FLOOR: OFF"
			avFloorButton.BackgroundColor3 = cfg.avFloor and Color3.fromRGB(38, 110, 60) or Color3.fromRGB(34, 34, 40)
			avCatchButton.Text = cfg.avCatch and "CATCH BACK: ON" or "CATCH BACK: OFF"
			avCatchButton.BackgroundColor3 = cfg.avCatch and Color3.fromRGB(46, 62, 46) or Color3.fromRGB(34, 34, 40)
			avFollowButton.Text = cfg.avFollow and "FOLLOW ME: ON" or "FOLLOW ME: OFF (static)"
			avFollowButton.BackgroundColor3 = cfg.avFollow and Color3.fromRGB(46, 62, 46) or Color3.fromRGB(34, 34, 40)

			ramButton.Text = cfg.ramOn and "RAM DOWNGRADE: ON" or "RAM DOWNGRADE: OFF"
			ramButton.BackgroundColor3 = cfg.ramOn and Color3.fromRGB(38, 110, 60) or Color3.fromRGB(60, 60, 70)
			ram3dButton.Text = cfg.ram3d and "3D RENDER: ON" or "3D RENDER: OFF (blank screen)"
			ram3dButton.BackgroundColor3 = cfg.ram3d and Color3.fromRGB(34, 34, 40) or Color3.fromRGB(150, 40, 40)

			TEAM.on.Text = cfg.teamOn
					and ("TEAM MODE: ON  -  YOU ARE " .. TEAM.role .. (TEAM.prime and "  [SHARDS]" or ""))
				or "TEAM MODE: OFF"
			TEAM.on.BackgroundColor3 = cfg.teamOn and Color3.fromRGB(38, 110, 60) or Color3.fromRGB(60, 60, 70)
			TEAM.rush.Text = cfg.teamFocusThreat and "BOTH RUSH THREATS: ON" or "BOTH RUSH THREATS: OFF"
			TEAM.rush.BackgroundColor3 = cfg.teamFocusThreat and Color3.fromRGB(46, 62, 46)
				or Color3.fromRGB(34, 34, 40)
			local lines = {}
			for i, e in ipairs(TEAM.roster) do
				lines[#lines + 1] = string.format("%s  %s%s", TEAM.roles[i] or i, e.name, e.name == lp.Name and "  <- you" or "")
			end
			TEAM.status.Text = string.format(
				"known bots %d   here now %d\n%s\n\n%s\neggs mine %d",
				#TEAM.roster,
				#TEAM.here,
				#lines > 0 and table.concat(lines, "\n") or "  none seen yet",
				TEAM.note,
				eggAliveCount
			)

			stopButton.Text = cfg.farmPaused and "FARM STOPPED - CLICK TO RESUME"
				or "FARM RUNNING - CLICK TO STOP"
			stopButton.BackgroundColor3 = cfg.farmPaused and Color3.fromRGB(38, 90, 48)
				or Color3.fromRGB(150, 40, 40)
			K.vapeCycleButton.Text = cfg.vapeCycle and "VAPE ON DEMAND: ON" or "VAPE ON DEMAND: OFF"
			ramStatus.Text = string.format(
				"roblox now  %.0f MB\nstripped    %d\nlast run\n  %s\nvape  %s\n  %d flips this session",
				memMb(),
				ramStripped,
				ramLastReport,
				tostring(K.vapeCycle),
				K.vapeFlips or 0
			)

			espButton.Text = cfg.esp and "ESP: ON" or "ESP: OFF"
			espButton.BackgroundColor3 = cfg.esp and Color3.fromRGB(46, 62, 46) or Color3.fromRGB(34, 34, 40)

			tpButton.Text = cfg.tpOn and "AUTO TP: ON" or "AUTO TP: OFF"
			tpButton.BackgroundColor3 = cfg.tpOn and Color3.fromRGB(150, 40, 40) or Color3.fromRGB(38, 90, 48)
			tpRangeLabel.Text = cfg.tpRange <= 0 and "range 0 (inside him)"
				or string.format("range %.1f behind", cfg.tpRange)
			tpFramesLabel.Text = string.format("frames each %d", cfg.tpFrames)

			local voidCount = 0
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= lp and isVoidPlayer(p) then
					voidCount = voidCount + 1
				end
			end
			local runFor = cfg.tpOn and (os.clock() - tpStartT) or 0
			local kills = cfg.tpOn and math.max(0, myKills() - tpKillsBase) or 0
			tpStatus.Text = string.format(
				"running  %02d:%02d\nkills    %d\ntargets  %d   void-skip %d/%d\non       %s\nsweep    %.0f ms  x%d\nvoid players %d",
				math.floor(runFor / 60),
				math.floor(runFor % 60),
				kills,
				tpLastTargets,
				K.tpBlockedPass,
				K.tpBlocked,
				tpCurrent,
				tpCycleMs,
				tpCycles,
				voidCount
			)

			eggButton.Text = cfg.eggOn and "AUTO EGG: ON" or "AUTO EGG: OFF"
			eggButton.BackgroundColor3 = cfg.eggOn and Color3.fromRGB(150, 40, 40) or Color3.fromRGB(38, 90, 48)
			eggThenButton.Text = cfg.eggThenTp and "THEN AUTO TP: ON" or "THEN AUTO TP: OFF"
			eggThenButton.BackgroundColor3 = cfg.eggThenTp and Color3.fromRGB(46, 62, 46)
				or Color3.fromRGB(34, 34, 40)
			eggDownLabel.Text = cfg.eggUp >= 0 and string.format("up  %d studs", cfg.eggUp) or string.format("under  %d studs", -cfg.eggUp)
			eggFramesLabel.Text = string.format("frames each %d", cfg.eggFrames)

			K.settleButton.Text = cfg.settleSecs <= 0 and "SETTLE OFF"
				or string.format("SETTLE %.1fs", cfg.settleSecs)
			-- Amber while a settle is actually holding the sweep back, which is the only time
			-- the number on it is doing anything.
			K.settleButton.BackgroundColor3 = (K.liveAt and not K.settleDone)
					and Color3.fromRGB(120, 96, 30)
				or Color3.fromRGB(38, 38, 48)
			K.eggCoinButton.Text = cfg.eggGrabCoins and "EGG-PHASE COINS: ON" or "EGG-PHASE COINS: OFF"
			K.eggCoinButton.BackgroundColor3 = cfg.eggGrabCoins and Color3.fromRGB(120, 96, 30)
				or Color3.fromRGB(38, 38, 48)

			local eggRun = cfg.eggOn and (os.clock() - eggStartT) or 0
			eggStatus.Text = string.format(
				"running  %02d:%02d\nbroken   %d\neggs up  %d\non       %s\nsweeps   %d\nstate    %s",
				math.floor(eggRun / 60),
				math.floor(eggRun % 60),
				eggsBroken,
				eggAliveCount,
				eggCurrent,
				eggCycles,
				eggState
			)
			avYLabel.Text = string.format("floor Y  %d", cfg.avY)
			avSizeLabel.Text = string.format("size     %d", cfg.avSize)

			local myR = root()
			avStatus.Text = string.format(
				"your Y   %s\nfloor Y  %d\ndrop     %s\nstate    %s\ncaught   %d",
				myR and string.format("%.0f", myR.Position.Y) or "-",
				cfg.avY,
				myR and string.format("%.0f", myR.Position.Y - cfg.avY) or "-",
				avState,
				avCatches
			)

			for key, entry in pairs(typeButtons) do
				local on = cfg.types[key]
				entry.button.BackgroundColor3 = on and Color3.fromRGB(46, 62, 46) or Color3.fromRGB(34, 34, 40)
				entry.button.TextColor3 = on and entry.def.color or Color3.fromRGB(110, 110, 120)
				entry.button.Text = (on and "[x] " or "[ ] ") .. entry.def.label
				entry.count.Text = tostring(stats.byType[key] or 0)
			end

			for key, entry in pairs(buyToggles) do
				local on = cfg[key]
				entry.button.BackgroundColor3 = on and Color3.fromRGB(46, 62, 46) or Color3.fromRGB(34, 34, 40)
				entry.button.TextColor3 = on and Color3.fromRGB(225, 225, 235) or Color3.fromRGB(110, 110, 120)
				entry.button.Text = (on and "[x] " or "[ ] ") .. entry.label
			end

			local dwell = K.DWELLS[cfg.dwellIndex] or 0
			dwellLabel.Text = "dwell  " .. (dwell == 0 and "1 frame" or string.format("%.2fs", dwell))
			radiusLabel.Text = string.format("radius %d", cfg.radius)
			perPassLabel.Text = string.format("per pass %d", cfg.perPass)
			homeButton.Text = cfg.returnHome and "RETURN HOME: ON" or "RETURN HOME: OFF"
			homeButton.BackgroundColor3 = cfg.returnHome and Color3.fromRGB(46, 62, 46) or Color3.fromRGB(34, 34, 40)

			local now = os.clock()
			if now - lastClock >= 0.5 then
				stats.rate = (stats.collected - lastCollected) / (now - lastClock)
				lastCollected = stats.collected
				lastClock = now
			end

			stats.elapsed = cfg.enabled and (os.clock() - stats.startClock) or stats.elapsed

			local b, i2, g, s4 = currencyTotals()
			statsLabel.Text = string.format(
				"time     %.1fs\non map   %d\nvisited  %d   got %d\nrate     %.1f /s\npass     %.0f ms\nheld     %d / %d / %d / %d",
				stats.elapsed,
				stats.found,
				stats.visited,
				stats.collected,
				stats.rate,
				stats.lastPassMs,
				b,
				i2,
				g,
				s4
			)

			local swordNext = nextUpgrade("Sword")
			local swordText = swordNext
					and string.format("%s  %d %s", swordNext.ItemType, swordNext.Price, swordNext.CurrencyType)
				or "MAXED"
			local armourText
			if swordNext then
				armourText = "locked - sword not max"
			else
				local armourNext = nextUpgrade("Armour")
				armourText = armourNext
						and string.format("%s  %d %s", armourNext.ItemType, armourNext.Price, armourNext.CurrencyType)
					or "MAXED"
			end
			local vt = vampTier()
			local vampText = vt >= 3 and "MAXED"
				or string.format("tier %d/3  next %d shard", vt, K.TEAM_TIER_PRICE[vt + 1])

			buyStatus.Text = string.format(
				"sword\n  %s\narmour\n  %s\nvampyrism\n  %s\nadrenaline\n  %d bought\nbuys total %d",
				swordText,
				armourText,
				vampText,
				stats.adrenBought,
				stats.buys
			)
			buyLog.Text = table.concat(logLines, "\n")

			if cfg.enabled then
				if stats.elapsed >= nextSplit then
					local line = string.format(
						"%3ds  got %-4d  %d/%d/%d/%d",
						math.floor(stats.elapsed),
						stats.collected,
						b,
						i2,
						g,
						s4
					)
					table.insert(splits, 1, line)
					if #splits > 4 then
						table.remove(splits)
					end
					appendCsv(
						string.format(
							"%.1f,%d,%d,%.2f,%d,%d,%d,%d",
							stats.elapsed,
							stats.visited,
							stats.collected,
							stats.rate,
							b,
							i2,
							g,
							s4
						)
					)
					nextSplit = nextSplit + 10
				end
			else
				nextSplit = 10
			end
			splitLabel.Text = table.concat(splits, "\n")
		end)
		if not ok then
			-- errorLabel is rewritten by the collector every 0.03s, so a ui error posted only
			-- there is invisible. Warn as well; the console keeps it.
			pcall(function()
				errorLabel.Text = "! ui " .. tostring(err)
				warn("[panels] ui error: " .. tostring(err))
			end)
		end
		task.wait(0.2)
	end
end)

getgenv().__EWCOIN_KILL = function()
	alive = false
	-- Silence the saver BEFORE the values are zeroed. Without this line the kill's own
	-- cfg.enabled=false reached the disk and came back on the next load.
	cfg.farmPaused = true
	getgenv().__CFG_GEN = (getgenv().__CFG_GEN or 0) + 1
	cfg.enabled = false
	cfg.autoBuy = false
	for _, c in ipairs(conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	pcall(destroyFloor)
	pcall(destroyAllEsp)
	pcall(function()
		gui:Destroy()
	end)
end

local killIcon = Instance.new("TextButton")
killIcon.Name = "Unload"
killIcon.Size = UDim2.fromOffset(34, 34)
killIcon.AnchorPoint = Vector2.new(1, 0.5)
killIcon.Position = UDim2.new(1, -6, 0.5, 0)
killIcon.BackgroundColor3 = Color3.fromRGB(96, 28, 28)
killIcon.BorderSizePixel = 0
killIcon.Text = "!"
killIcon.TextColor3 = Color3.fromRGB(255, 210, 210)
killIcon.Font = Enum.Font.GothamBold
killIcon.TextSize = 18
killIcon.Parent = iconBar
Instance.new("UICorner", killIcon).CornerRadius = UDim.new(0, 5)

-- The lock, on the bar, immediately left of the ! - which is where he pointed.
--
-- I put it on every panel titlebar first. Wrong furniture: he said "next to the [!]",
-- and the ! lives on this bar at the top left, beside the : grip. One button here locks
-- every panel at once, which is the point - he moves several at a time.
--
-- Locked, it is green and nothing can be dragged. Unlocked, it is grey, he drags freely,
-- and nothing walks the panels back afterwards; the arranger only places them on arrival.
do (function()
	local lockIcon = Instance.new("TextButton")
	lockIcon.Name = "LockAll"
	lockIcon.Size = UDim2.fromOffset(34, 34)
	lockIcon.AnchorPoint = Vector2.new(1, 0.5)
	lockIcon.Position = UDim2.new(1, -44, 0.5, 0)
	lockIcon.BorderSizePixel = 0
	lockIcon.Text = "#"
	lockIcon.Font = Enum.Font.GothamBold
	lockIcon.TextSize = 18
	lockIcon.Parent = iconBar
	Instance.new("UICorner", lockIcon).CornerRadius = UDim.new(0, 5)

	local function paintLockIcon()
		local on = getgenv().__GUI_LOCKED and true or false
		lockIcon.BackgroundColor3 = on and Color3.fromRGB(31, 111, 67) or Color3.fromRGB(52, 52, 64)
		lockIcon.TextColor3 = on and Color3.fromRGB(210, 255, 220) or Color3.fromRGB(180, 180, 195)
	end
	getgenv().__LOCK_PAINT = paintLockIcon
	paintLockIcon()

	lockIcon.MouseButton1Click:Connect(function()
		getgenv().__GUI_LOCKED = not getgenv().__GUI_LOCKED
		paintLockIcon()
		pcall(function()
			appendfile("RobloxComm/autoexec_status.txt", os.date("%Y-%m-%d %H:%M:%S")
				.. "  [panels] " .. (getgenv().__GUI_LOCKED and "LOCKED" or "unlocked")
				.. " by # on " .. lp.Name .. "\n")
		end)
	end)
end)() end
killIcon.MouseButton1Click:Connect(function()
	pcall(writefile, FLAG, "0")
	-- OFF is now honoured by eggwars_autostart as well as by the queued stub, so it lasts
	-- past a teleport instead of a median of 63 seconds. That also means the only way back
	-- on is to delete one file, and where that file is has to be written somewhere that is
	-- actually read in the morning rather than left to be worked out from the source.
	pcall(function()
		appendfile("RobloxComm/autoexec_status.txt", os.date("%Y-%m-%d %H:%M:%S")
			.. "  [panels] OFF pressed - " .. FLAG
			.. " set to 0. Write 1 into that one file, or delete it, to load the farm on this account again; the other three clients are untouched.\n")
	end)
	local k = getgenv().__EWCOIN_KILL
	if k then
		pcall(k)
	end
end)

-- ONE SWITCH, and it is deliberately two files.
--
-- ew_panels_<UserId>.txt is this account and nothing else. The "!" button in the icon bar
-- writes 0 into it and no other client on the machine can see that happen - which is the
-- entire point: all four share Real's single workspace folder, so before this file was named
-- after the UserId one OFF press took the farm off all four.
--
-- ew_stop_all.txt is the machine. It has to be a separate file AND carry a different word,
-- because the two are read by the same loop three seconds apart and a "1" that means RUN in
-- one file and STOP in the other is a mistake waiting for 3am. Only the exact word STOP stops
-- anything. Missing, empty, half written, unreadable - all of those run, because a false stop
-- costs the whole night and a false run costs one button press.
--
-- STOP ALL never writes to the per-account files. Clearing it has to bring everything back by
-- itself; if it wrote 0 into four flags on the way out, coming back on would mean finding and
-- undoing four separate writes in the dark.
K.STOPALL = "RobloxComm/ew_stop_all.txt"
-- Far in the past, not zero. The arm check is os.clock() - K.stopAllArmed > 5, and
-- os.clock() counts from the start of this process, so a zero here would make the very
-- first press count as the confirming second press for the first five seconds of a
-- client's life. One click must never be able to stop four clients.
K.stopAllArmed = -1e9
stopFrame.Size = UDim2.fromOffset(356, 224)
K.switchLabel = label(stopFrame, "reading switches", 166, 26, Color3.fromRGB(150, 150, 165), 11)
K.stopAllButton = button(stopFrame, "STOP ALL FOUR CLIENTS", 8, 196, 340, 24)
K.stopAllButton.BackgroundColor3 = Color3.fromRGB(96, 28, 28)
K.stopAllButton.Font = Enum.Font.GothamBold

K.readSwitch = function(path)
	local ok, raw = pcall(function()
		if isfile(path) then
			return readfile(path)
		end
		return nil
	end)
	if not ok then
		return nil, "UNREADABLE"
	end
	return raw, nil
end

-- Two presses, not one. This button stops four clients at once and it sits on a panel whose
-- other buttons are all harmless, so a single click is not enough to fire it.
bind(K.stopAllButton.MouseButton1Click, function()
	if os.clock() - K.stopAllArmed > 5 then
		K.stopAllArmed = os.clock()
		K.stopAllButton.Text = "PRESS AGAIN TO STOP ALL FOUR"
		return
	end
	K.stopAllArmed = 0
	local okW = pcall(writefile, K.STOPALL, "STOP")
	-- Read it back before claiming anything. The old text was built from the pcall alone, and a
	-- panel that says four clients stopped while the word never reached the disk is worse than a
	-- panel that says nothing at all.
	local back = K.readSwitch(K.STOPALL)
	local onDisk = type(back) == "string" and back:match("^%s*STOP%s*$") ~= nil
	K.stopAllButton.Text = onDisk and "STOP ALL is on disk - the loaders stand down within 3s"
		or (okW and "WROTE, BUT THE FILE DOES NOT SAY STOP - nothing stopped"
		or "STOP ALL WRITE FAILED - nothing stopped")
	K.stopAllButton.BackgroundColor3 = onDisk and Color3.fromRGB(96, 28, 28)
		or Color3.fromRGB(150, 40, 40)
	pcall(function()
		appendfile("RobloxComm/autoexec_status.txt", os.date("%Y-%m-%d %H:%M:%S")
			.. "  [panels] STOP ALL pressed by " .. lp.Name .. " - write "
			.. (okW and "ok" or "FAILED") .. " to " .. K.STOPALL .. string.char(10))
	end)
end)

task.spawn(function()
	while alive and getgenv().__EWCOIN_GEN == MY_GEN do
		local ok, err = pcall(function()
			if K.stopAllArmed > 0 and os.clock() - K.stopAllArmed > 5 then
				K.stopAllArmed = 0
				K.stopAllButton.Text = "STOP ALL FOUR CLIENTS"
			end
			local mine, mineErr = K.readSwitch(FLAG)
			local all, allErr = K.readSwitch(K.STOPALL)
			local stopAll = type(all) == "string" and all:match("^%s*STOP%s*$") ~= nil
			local mineText
			if mineErr then
				mineText = mineErr
			elseif mine == nil then
				mineText = "MISSING"
			elseif mine:match("^%s*1%s*$") then
				mineText = "ON"
			else
				mineText = "OFF"
			end
			if getgenv().__EWCOIN_FLAG_WRITE == false then
				mineText = mineText .. " (write failed at load)"
			end
			if getgenv().__EWCOIN_ARMED == false then
				mineText = mineText .. " (ARM FAILED - nothing queued for the next teleport)"
			end
			local allText
			if allErr then
				allText = allErr .. " - treated as clear"
			elseif stopAll then
				allText = "SET - this client is standing down"
			else
				allText = "clear"
			end
			K.switchLabel.Text = string.format("this account %s   %s\nSTOP ALL %s", mineText, FLAG, allText)
			K.switchLabel.TextColor3 = (stopAll or mineText ~= "ON") and Color3.fromRGB(255, 150, 120)
				or Color3.fromRGB(150, 150, 165)
			if stopAll then
				pcall(function()
					appendfile("RobloxComm/autoexec_status.txt", os.date("%Y-%m-%d %H:%M:%S")
						.. "  [panels] STOP ALL seen in " .. K.STOPALL .. " - unloading on " .. lp.Name
						.. ". Clear that one file to run again; the per-account switches are untouched."
						.. string.char(10))
				end)
				-- The other two bot side scripts live in this same client and answer to the same
				-- switch. Stopping them from here is what stops STOP ALL having to wait for a
				-- teleport to reach the thing that walks the bot back to the lobby.
				pcall(function()
					if getgenv().__FOLLOW_STOP then
						getgenv().__FOLLOW_STOP()
					end
				end)
				pcall(function()
					if getgenv().__REC_STOP then
						getgenv().__REC_STOP()
					end
				end)
				local k = getgenv().__EWCOIN_KILL
				if k then
					pcall(k)
				end
			end
		end)
		if not ok then
			-- A switch that cannot be read has to say so where he is actually looking. warn on its
			-- own is not enough: the console is closed on all four windows.
			pcall(function()
				K.switchLabel.Text = "! switch " .. tostring(err)
				K.switchLabel.TextColor3 = Color3.fromRGB(255, 92, 92)
			end)
		end
		task.wait(3)
	end
end)

print("[panels] loaded and queued for the next teleport - press OFF in the icon bar to unload for good")


-- Park amnesty. The other half of the threatDropped test now sitting in validTarget.
--
-- Excluding a parked player is right, but on its own it can leave the farm with no target at
-- all: on a nearly-finished round the flyer really is the only name left, and a bot with no
-- target and no eggs does nothing for the rest of the round just as surely as one that was
-- frozen on him. So the park is a timeout, not a life sentence. Twenty seconds with every
-- remaining player parked and the slate is wiped: he may have landed, run out of flight, or
-- lost the tool that was blocking the teleport, and none of those show up anywhere the farm
-- can read. Retrying costs one more threat budget; never retrying costs the whole round.
do (function()
	task.spawn(function()
		claimIdentity()
		local dry = 0
		while alive and getgenv().__EWCOIN_GEN == MY_GEN do
			task.wait(2)
			local ok = pcall(function()
				if not K.roundLive() then
					dry = 0
					return
				end
				local live, parked = false, false
				for _, p in ipairs(Players:GetPlayers()) do
					if p ~= lp and not isOwner(p) and not K.isBot(p) then
						local t = track[p]
						if t and t.threatDropped and t.threatRound == tostring(game.JobId) then
							parked = true
						elseif validTarget(p) then
							live = true
						end
					end
				end
				if live or not parked then
					dry = 0
					return
				end
				dry = dry + 2
				if dry >= 20 then
					local n = 0
					for _, t in pairs(track) do
						if t.threatDropped then
							t.threatDropped = false
							t.threatSpent = 0
							n = n + 1
						end
					end
					K.threatNote = ""
					dry = 0
					K.event(string.format(
						"park amnesty: every remaining target was parked for 20s - unparked %d, trying again", n))
				end
			end)
			if not ok then
				dry = 0
			end
		end
	end)
end)() end


-- ANTI-AFK-ATTACK. His name, his rules, written down on 2026-08-11 after the bots stalled a
-- third time. It runs on its own ten second beat and does two separate jobs: it decides
-- whether the round is going wrong, and if the normal sweep cannot fix it, it takes the
-- character over and does the simplest thing that ever works - stand behind somebody on
-- another team and stay there.
--
-- The five things that make it look, straight from him: leader dead, round older than a
-- minute, took damage, any bot dead, and a team still standing whose egg is already broken.
-- They are not five features, they are five ways of noticing the same thing - the round is
-- live and this client is contributing nothing.
--
-- STICKY is the fallback and it is deliberately blunt. Nearest player whose TeamId is not
-- mine, hop in behind him, keep hopping in behind him every frame until he dies or the round
-- ends, then take the next one. No threat budget, no coins, no eggs, no giving up on a flyer.
do (function()
	local STILL_NEEDED = 20
	local BEAT = 10

	K.__ANTIAFK_ATK = { fires = 0, sticky = false, why = "-", since = 0 }

	local function myTeam()
		return lp:GetAttribute("TeamId")
	end

	local function enemyOf(p)
		if p == lp or isOwner(p) or K.isBot(p) then
			return false
		end
		if p:GetAttribute("Alive") == false or p:GetAttribute("Spectating") then
			return false
		end
		local mine = myTeam()
		if mine and p:GetAttribute("TeamId") == mine then
			return false
		end
		return true
	end

	local function nearestEnemy()
		local c = lp.Character
		local r = c and c:FindFirstChild("HumanoidRootPart")
		if not r then
			return nil
		end
		local best, bestRoot, bestDist
		for _, p in ipairs(Players:GetPlayers()) do
			if enemyOf(p) then
				local tr = targetRoot(p)
				if tr and tr.Position.Y > K.VOID_Y then
					local d = (tr.Position - r.Position).Magnitude
					if not bestDist or d < bestDist then
						best, bestRoot, bestDist = p, tr, d
					end
				end
			end
		end
		return best, bestRoot, bestDist
	end

	-- One colour still standing with its egg already broken. Those players cannot come back,
	-- so a round that is not ending with them alive is a round this client is not finishing.
	local function brokenEggTeamStanding()
		local mine = myTeam()
		for _, p in ipairs(Players:GetPlayers()) do
			if enemyOf(p) then
				local t = p:GetAttribute("TeamId")
				if t and t ~= mine and p:GetAttribute("EggAlive") == false then
					return true
				end
			end
		end
		return false
	end

	local function stickyChase()
		local S = K.__ANTIAFK_ATK
		S.sticky = true
		S.since = os.clock()
		K.event("ANTI-AFK-ATTACK: going STICKY - " .. S.why)
		loud("anti-afk-atk", "STICKY chase on - " .. S.why)
		while alive and getgenv().__EWCOIN_GEN == MY_GEN do
			if not K.roundLive() then
				break
			end
			local c = lp.Character
			local hum = c and c:FindFirstChildOfClass("Humanoid")
			local r = c and c:FindFirstChild("HumanoidRootPart")
			if not r or not hum or hum.Health <= 0 then
				break
			end
			local p, tr = nearestEnemy()
			if not p or not tr then
				break
			end
			-- Front here too, and this was the one that mattered most.
			--
			-- He caught it live, 2026-08-16: "those bot was now still at the behind killing,
			-- it should go to front". The tpPass was switched to the front already; this
			-- sticky chase is a second, separate mover, and it is the one that holds longest
			-- - it stays locked on one man until he dies or the round ends, which is exactly
			-- the shape the kick watches for. Both movers now stand in the face.
			local face = tr.CFrame.LookVector * (cfg.tpFront and 1 or -1)
			local flat = Vector3.new(face.X, 0, face.Z)
			flat = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, -1)
			-- Underneath here too. This mover is the one that holds longest, so it is the one
			-- the kick watches, and the whole point of going under is that neither arc has it.
			-- Under, or over. Same rule as the pass above, and this is the mover that holds
			-- longest, so it is the one the kick watches.
			local off = math.clamp(math.max(cfg.tpRange or 3.5, 3), 3, K.EGG_REACH)
			local dest = tr.Position - Vector3.new(0, off, 0)
			if dest.Y <= K.VOID_Y + 5 then
				dest = tr.Position + Vector3.new(0, off, 0)
			end
			K.hop(r, K.faceFlat(r, dest, tr.Position))
			K.hitPlayer(p)
			pcall(function()
				if type(K.ensureMelee) == "function" then
					K.ensureMelee()
				end
			end)
			K.tpCurrent = "STICKY " .. p.Name
			RunService.Heartbeat:Wait()
		end
		S.sticky = false
		K.event("ANTI-AFK-ATTACK: sticky ended after " .. string.format("%.0fs", os.clock() - S.since))
	end

	task.spawn(function()
		claimIdentity()
		local lastPos, still, lastHp, roundAt = nil, 0, 100, os.clock()
		local lastBots, lastJob = nil, nil
		while alive and getgenv().__EWCOIN_GEN == MY_GEN do
			task.wait(BEAT)
			pcall(function()
				local S = K.__ANTIAFK_ATK
				if S.sticky then
					return
				end
				if not K.roundLive() then
					still, lastPos, roundAt = 0, nil, os.clock()
					return
				end
				if lastJob ~= tostring(game.JobId) then
					lastJob = tostring(game.JobId)
					roundAt = os.clock()
				end

				local c = lp.Character
				local hum = c and c:FindFirstChildOfClass("Humanoid")
				local r = c and c:FindFirstChild("HumanoidRootPart")
				if not r or not hum or hum.Health <= 0 then
					still, lastPos = 0, nil
					return
				end

				local pos = r.Position
				if lastPos and (pos - lastPos).Magnitude < 2 then
					still = still + BEAT
				else
					still = 0
				end
				lastPos = pos

				local why = nil
				if hum.Health < lastHp then
					why = "took damage"
				end
				lastHp = hum.Health

				local leaderDead = false
				for _, p in ipairs(Players:GetPlayers()) do
					if isOwner(p) and p:GetAttribute("Alive") == false then
						leaderDead = true
					end
				end
				if leaderDead then
					why = why or "the leader is dead"
				end

				local botsAlive = 0
				for _, name in pairs(K.BOTS or {}) do
					local bp = Players:FindFirstChild(name)
					if bp and bp:GetAttribute("Alive") ~= false then
						botsAlive = botsAlive + 1
					end
				end
				if lastBots and botsAlive < lastBots then
					why = why or "a bot died"
				end
				lastBots = botsAlive

				if os.clock() - roundAt > 60 then
					why = why or "the round is over a minute old"
				end
				if brokenEggTeamStanding() then
					why = why or "a team is still standing with its egg broken"
				end

				if still < STILL_NEEDED or not why then
					return
				end

				S.fires = S.fires + 1
				S.why = string.format("%s, and not moved for %ds", why, still)
				still = 0

				pcall(function()
					hum.Jump = true
				end)
				pcall(function()
					local vu = game:GetService("VirtualUser")
					vu:CaptureController()
					vu:ClickButton1(Vector2.new())
				end)
				pcall(function()
					if type(K.ensureMelee) == "function" then
						K.ensureMelee()
					end
				end)
				pcall(function()
					K.tpBlockedPass = 0
					K.threatNote = ""
					for _, t in pairs(K.__track or {}) do
						t.threatDropped = false
						t.threatSpent = 0
					end
				end)
				K.event(string.format("ANTI-AFK-ATTACK fire %d: %s - shoved and reset", S.fires, S.why))

				task.wait(6)
				local c2 = lp.Character
				local r2 = c2 and c2:FindFirstChild("HumanoidRootPart")
				if r2 and lastPos and (r2.Position - lastPos).Magnitude < 2 then
					stickyChase()
				end
			end)
		end
	end)
end)() end


-- MOVED OUT OF onKickCode, 2026-08-14 20:5x. Same shape of mistake as the leader's.
--
-- It sat inside onKickCode, which returns immediately unless GuiService:GetErrorCode() has
-- gone non-OK - so the watcher only ever started once the client was already disconnecting.
-- During a healthy round it was never spawned at all, which means the whole [U FORGOT ME]
-- rescue built today had never run once. Out here it starts with the script and watches for
-- as long as the client is alive.

-- LEFT BEHIND IN A ROUND.
--
-- His ask, 2026-08-14: a bot still in the round that cannot get back to the lobby writes
-- into the log so the leader can come and get it.
--
-- Being in a match while the leader is in the lobby is normal for a few seconds at every
-- round change, so this holds for 15s before it believes it. leader_where.txt carries a raw
-- os.time() as its last field for exactly this kind of check - both clients are on the one
-- machine, so the two clocks are the same clock.
--
-- It hops itself out at the same moment it writes. An invite cannot reach a bot inside a
-- match: the auto-accept further down this file only arms in the lobby, because the match
-- place has no PlayerScripts.TS.events to hook.
do
	local FORGOT_LOBBY = 8542259458
	-- Down from 15. The hold is only there to survive the seconds at the start of a round when
	-- leader_where.txt still shows the lobby, and the arrival guard below already handles that
	-- case exactly - a line stamped before I landed is ignored outright. With a precise test
	-- in front of it, a long blind wait buys nothing and costs him the twenty seconds he
	-- measured on 2026-08-14.
	local FORGOT_HOLD = 4
	local held = 0
	local sent = 0

	-- WHEN I ARRIVED. This is the whole fix for the false alarm.
	--
	-- 2026-08-14 21:1x, straight after this watcher was moved out to file scope and started
	-- running for the first time: the bots were in the round, healthy, and the LEADER went
	-- back to the lobby because it received [U FORGOT ME] from all of them.
	--
	-- The mechanism. At the start of every round the four clients teleport together. The bots
	-- land first. leader_where.txt still holds the line the leader wrote from the LOBBY a few
	-- seconds earlier, and that line's timestamp is only seconds old, so it passes the
	-- "fresher than 30s" test. Fifteen seconds later every bot concludes it has been left
	-- behind, writes the file and hops out of a perfectly good round - and the leader, doing
	-- what it was told, goes to the lobby to collect them.
	--
	-- Freshness against the wall clock was the wrong question. The right one is whether the
	-- leader's line is newer than MY OWN ARRIVAL. The script is reloaded on every teleport,
	-- so the moment this runs is the moment I landed. A lobby line written before I got here
	-- describes where the leader was on the way in, not where it is now.
	local MY_ARRIVAL = os.time()

	getgenv().__FORGOT_GEN = (getgenv().__FORGOT_GEN or 0) + 1
	local MY_FORGOT_GEN = getgenv().__FORGOT_GEN

	task.spawn(function()
		while getgenv().__FORGOT_GEN == MY_FORGOT_GEN do
			task.wait(1)
			if game.PlaceId == FORGOT_LOBBY then
				held = 0
				sent = 0
			else
				-- The leader said so. No hold, no guessing, no waiting to become suspicious.
				local told, toldAt = false, 0
				pcall(function()
					local raw = readfile("RobloxComm/come_to_lobby.txt")
					toldAt = tonumber(raw:match("^(%d+)")) or 0
					told = (os.time() - toldAt) < 45 and toldAt > MY_ARRIVAL
				end)
				if told and sent == 0 then
					sent = 1
					local hop = getgenv().__HOP_TO_LOBBY
					if type(hop) == "function" then
						hopFired = false
						hop("the leader asked everybody to come to the lobby")
					end
				end
				local leaderPlace, stamp
				pcall(function()
					local raw = readfile("RobloxComm/leader_where.txt")
					leaderPlace = tonumber(raw:match("^(%d+)"))
					stamp = tonumber(raw:match("(%d+)%s*$"))
				end)
				-- Three things, all required. The leader says it is in the lobby; that line is
				-- still fresh; and it was written at least 10s AFTER I landed here, so it cannot
				-- be the line it left behind on its way into this round with me.
				if leaderPlace == FORGOT_LOBBY and stamp
					and (os.time() - stamp) < 30
					and stamp > (MY_ARRIVAL + 10) then
					held = held + 1
					if held >= FORGOT_HOLD and sent == 0 then
						sent = 1
						pcall(writefile, "RobloxComm/forgot_me_" .. lp.Name .. ".txt",
							string.format("%d %s [U FORGOT ME] stuck in place %s for %ds",
								os.time(), lp.Name, tostring(game.PlaceId), held))
						hopFired = false
						local hop = getgenv().__HOP_TO_LOBBY
						if type(hop) == "function" then
							hop("left behind, the leader is in the lobby")
						else
							warn("[forgot] no hop function published - cannot leave")
						end
					end
				else
					held = 0
				end
			end
		end
	end)
end

K.queueKeeper()
