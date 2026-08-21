-- SOLO_FARM - SkyWars Solo, end to end.
--
-- Every constant was read off this account, never guessed:
--   queue        SkyWarsSolo, TeamSize 1, MaxTeams 12   (game-mode module)
--   places       match 8542275097, lobby 8542259458
--   chests       Workspace.BlockContainer.Map.Chests, ChestTierOne..Four
--   hit event    0f825f49 player, 61be77c1 entity, under ReplicatedStorage.rM9
--   hit reach    MAXIMUM_HIT_RANGE_BLOCKS 4.5 * 2.3 = 10.35 studs
--   swords       Bronze 18, Iron 23, Gold 25, Diamond 29, Onyx 32
--
-- Two kill modes, switchable, both timed into ab_test.tsv so which is faster
-- is something we read rather than argue about:
--   VIPER  lowest on the Y axis first, sit under them, 0.2s each
--   FRAME  hop each living player, N frames each, hit, next
--
-- No chest menu is ever opened. Standing in range is the whole job.
--
-- 2026-08-21 09:3x - four faults measured on the live client, all four fixed here.
--
-- 1. ONE TIER FOUR CHEST PER ROUND, NEVER MORE.
--    visited was keyed by tostring(chest). tostring on an Instance gives its
--    Name, and every tier four chest on this map is literally named
--    "ChestTierFour". Measured in game: 8 tier four chests produced 1 distinct
--    tostring key and 8 distinct instance keys. So the first chest marked all
--    of them visited, rankedChests went empty, and the farm decided there was
--    nothing left to loot. ab_test.tsv agrees - the chests column reads 1 for
--    every recent round while the map census counts 16 to 17 tier fours.
--    The key is the instance now.
--
-- 2. IT COULD NOT SEE THE SWORD IT WAS HOLDING.
--    bestSword read lp.Backpack and the character's Tools. Measured: Backpack
--    has 0 children in this game - items live in the flamework
--    hotbar-controller (id p4Q), and only the active slot is ever a real Tool.
--    The probe caught the account holding a DiamondSword at 09:37:46 while the
--    farm panel still said "sword none". So the "I have diamond or onyx, stop
--    looting and go kill" rule could never fire. The sword is read off
--    hotbar:getSword() now, which returns Name and Melee.Damage, and equipping
--    is setActiveSlot on the slot getHotbarItems reports.
--
-- 3. IT TELEPORTED ITSELF INTO THE VOID AND STAYED THERE.
--    VIPER sorts the living by lowest Y and sits BELOW=4.5 under the winner.
--    In SkyWars the lowest living player is normally the one already falling to
--    his death, so the farm followed him down and then went 4.5 further. Round
--    27 samples: 09:32:43 to 09:32:48 parked at y -49 to -40, twenty five studs
--    under a map whose lowest floor is y -24. Round 30 at 09:35:37: -67.4,
--    -73.6, -103.4. There was no clamp, no catch and no velocity freeze in this
--    file at all, while FARM_SKYWARS_ABCD has had all three since 2026-08-11.
--    Carried over here, plus a tracker in the same shape as the ABCD one so a
--    man on his way into the void is struck off for the round instead of being
--    picked again next frame. The line itself is not a constant - see the
--    mapFloor block below. EggWars can hardcode -69 because it has one map;
--    this rotates, and two maps measured twenty minutes apart had floors at
--    y -24 and y -39.
--
-- 4. IT SPENT THE WHOLE COUNTDOWN FIGHTING THE LOBBY.
--    The chest folder is empty for the first nine seconds: chest_tiers.tsv
--    reads 0/0/0/0 at start and at plus6s, then 24/32/12/17 at plus9s. The old
--    guard was "no ranked chests AND unopened > 0", and with the folder empty
--    both halves were zero, so it fell straight through to the kill code. Round
--    30 samples show y bouncing 133 to 138 from 09:35:23 to 09:35:30 - seven
--    seconds of hopping at players standing in the lobby holding pen. Nothing
--    attacks until the character is on the map and the chests exist.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local env = getgenv and getgenv() or _G
env.__SOLOFARM_GEN = (env.__SOLOFARM_GEN or 0) + 1
local MYGEN = env.__SOLOFARM_GEN
local function alive() return env.__SOLOFARM_GEN == MYGEN end

local lp = Players.LocalPlayer

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
while not lp do task.wait(0.2) lp = Players.LocalPlayer end

local MATCH_PLACE = 8542275097
local LOBBY_PLACE = 8542259458
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



local HIT_PLAYER_IDS = { "0f825f49-002e-4b7b-8d8c-24dbb3494845", "93b2718b-2b2a-4859-b36e-fd4614c7f0c9" }
local HIT_ENTITY_IDS = { "61be77c1-2605-42b3-a731-0d5509527598", "f32c9bc1-cb4b-4616-96ac-bddaefd35e92" }

local HIT_RANGE = 10.35
local CHEST_REACH = 12

-- Viper's own numbers, from the SkyWars Discord #general on 2026-08-20 22:38 to
-- 22:41. These are not tuning knobs any more, they are a spec:
--
--   "it will first hit the lowest Y-axis players, that way it doesn't get hit
--    by the ones hiding above, because hitting upward exposes your body. Once
--    it clears the low-Y group - the majority - it moves to the others."
--
--   "at 50 ping, 0.08 seconds is enough for one attack to be accepted by the
--    server, so think about how long 0.2 seconds really is"   -> HIT_GAP 0.08
--
--   "it changes attack target every 0.2 seconds"              -> VIPER_DWELL 0.2
--
--   breter: "just make it always go behind the player, plus up-down blinking"
--   viper:  "mobile players hit you from behind fine, and going behind is
--            predictable - you should go UNDER them instead. You don't want to
--            go up."  ... "hiding under works as well as behind, better even."
--            "I could probably add an offset."
--
-- So BELOW is the only legal place to stand, and there is no fallback that puts
-- the body level with a man or behind him. If under is not available the target
-- is skipped, not approached another way.
-- HOW FAR BELOW - this is now the thing being measured, not assumed.
--
-- 2026-08-21 18:0x, his words: "i cam see it was still not lwoer the fucking
-- the bot, it was sitll fucking at thd down that close, it was not able to fast
-- killing wihtout got atk".
--
-- He is right that 4.5 is not "lower", it is "directly underneath and touching".
-- The melee reach measured out of the game's own constants is 10.35 studs and it
-- works both ways, so at 4.5 the target can always swing back. To be genuinely
-- out of his reach the body has to sit MORE than 10.35 studs below him.
--
-- Whether a hit still lands from down there is an open question and must not be
-- assumed either way: the game's client refuses to send a strike past 10.35, but
-- this file fires the networking event directly and skips that check. Whether
-- the SERVER also checks has never been measured with a sword in hand - the two
-- earlier probes that said "no damage" both ran with no sword and are void.
--
-- So the farm cycles this ladder one value per round and writes damage per swing
-- for each distance into below_test.tsv. The largest distance that still deals
-- damage is the answer, and it comes out of the file.
-- 2026-08-21 18:1x - the ladder is gone, he already knows the answer.
--
--   "why the fuck u need to test bro, the killl aura was suprot to do the fuck
--    of killing, u dont need to care the fuck as i befor tried it was suporot
--    over 5 x player size that far bro ... we cant let any player to see we
--    killing it"
--
-- He has tested the reach himself and it carries well past five player heights.
-- His own measurement outranks my wanting to measure it again, and the thing he
-- actually cares about is that nobody can hit back and nobody can see it happen.
-- A Roblox character is about 5 studs, so five of them is 25, and 25 is also
-- comfortably outside the 10.35 stud melee reach the game's own constants set -
-- which is the whole point: down there the target cannot answer.
--
-- The damage and damage-taken counters stay on. That is not a test, it is the
-- instrumentation that was already there, and if 25 ever stops landing it will
-- show up as damage falling to zero in ab_test.tsv rather than as a surprise.
-- 2026-08-21 18:2x, he cut it down: "dont, 25 studs that far bro, try 16 studs".
-- 16 is still comfortably outside the 10.35 stud melee reach, so nobody can
-- answer, and it keeps the body nearer the target than 25 did.
-- 2026-08-21 18:3x: "try 15 studs, mkae sure ti defult telpeting to the player
-- was that, dnt ever trying to near player that". 15 is the standing default for
-- every teleport that goes to a man, and it is still outside the 10.35 reach.
local BELOW = 15
local BELOW_OFFSET = 1.5

-- 2026-08-21 15:5x, he corrected this and he is right.
--
-- "it was not telpting bro, u just misatke it was go to the down bro ... the
--  vieo showed suepr clear that was the player not abel to see the player,
--  that was instead telpting to the down"
--
-- The first cut read "under the target" on its own and computed
-- target.Y - 4.5. For a man standing on one of the high platforms that is a
-- teleport UPWARD - the bot flew up to sit under him - and Viper's own words
-- rule that out in one line: "you don't want to go up". Going up is what puts
-- your body on somebody's screen, which is the whole reason he stays low.
--
-- So the bot keeps a ceiling. It may descend freely and it may never ascend to
-- reach a man. A target is only legal while the spot under him is at or below
-- that ceiling; everyone else waits. That is also Viper's own order of play -
-- "once it clears the low-Y group, the majority, it moves to the others" - so
-- the ceiling only lifts when there is nobody left under it, one band at a
-- time, and it says so in the log when it does.
-- HIT_GAP is no longer a constant, it is the thing being searched for.
--
-- His words, 2026-08-21 17:2x: "it was also need to fast broke the kill limit
-- try make it fastest". Viper's 0.08 is the slowest gap he says is definitely
-- accepted at 50 ping - that is a statement about what the server allows, not a
-- measurement of where the ceiling actually is. So the farm cycles the gap round
-- by round and writes damage-per-swing for each one into gap_test.tsv. If a gap
-- is too fast the server drops the extra swings and damage per swing falls, and
-- that shows up in the table instead of in an argument.
-- The gap search is parked at Viper's own number while the DISTANCE search
-- runs. Two variables moving at once produce a table nobody can read.
local HIT_GAPS = { 0.08 }
local HIT_GAP = HIT_GAPS[1]
local gapIndex = 1
local VIPER_DWELL = 0.2

-- A man who has not moved for this long is parked - disconnected, alt tabbed or
-- dead weight. His rule, 2026-08-21 17:2x:
--
--   "adda a detect that was kill moveing playe frist, if afk player like not
--    moving the whole time or over 6 sec not moving dont kill frit as that was
--    very ez to kill, we need to done kill all others player"
--
-- So a parked man is still killed, he is just never killed while a real one is
-- still standing.
local PARKED_SECS = 6

-- How far the body is allowed to rise in one move to reach a man. Just under
-- the 10.35 stud hit range, so a climb never buys more than one platform. When
-- nobody at all is within this, and only then, the limit is relaxed once - that
-- is Viper's "once it clears the low-Y group it moves on to the others".
local MAX_CLIMB = 10
local CLIMB_RELAXED = 400

-- Declared here, not next to the loop that uses it: the round reset assigns it
-- and the reset lives earlier in the file, so a local declared later would be a
-- different variable and the reset would silently do nothing.
local EARLY_QUEUE_HP = 50
local NEAR_LAST = 30
local queuedEarly = false
local dryReset = false
local NUDGE_DRY = 1.5
local GIVEUP_DRY = 8

-- His completion times in the same conversation, which is what "normal farming"
-- has to be measured against rather than "it did not die":
--   solos 12 seconds, duos 21 seconds, eggwars 18 to 25 seconds.
-- The duo clip agrees: 22/24 alive at 1s, 14/24 at 12s, 12/24 at 17s, 3/24 at
-- 23s, won by 24.5s, then "Joining queue in 00:06".
local VIPER_SOLO_SECS = 12

-- 40 studs a step, at most 8 steps, straight off FARM_SKYWARS_ABCD where those
-- two numbers were tuned against the server. The old pair here was 18 and 8,
-- which silently broke itself on exactly the trip that matters: spawn to the
-- centre tier four cluster is 200 to 240 studs, and 200 over 8 steps is 25 a
-- step - larger than the 18 the constant claimed to enforce.
local HOP_MAX = 40
local MAX_HOPS = 8

-- The void line is MEASURED off the live map every round, never assumed.
--
-- The first cut of this file hardcoded -26 and -35, taken from the r026 census
-- where the lowest chest sits at y -24. Then the very next map measured at
-- 09:4x bottomed out at y -39 with tier four chests down at -30 - so those two
-- constants would have refused to let the bot reach half the chests it is being
-- sent to, and would have yanked it off the ones it did reach. A number read
-- off one map is not a property of the game.
--
--   mapFloor  the lowest chest on this map, read from the chest folder
--   SAFE_Y    mapFloor - 2, the lowest this file may ever place the character
--   VOID_Y    mapFloor - 11, under this you are falling and so is everyone else
--   LOBBY_Y   above this you are in the pre-round holding pen, not on the map
--
-- Until the chests stream in both lines sit far below anything real, so an
-- unmeasured state can never fight the map.
local SAFE_Y = -60
local VOID_Y = -75
local LOBBY_Y = 100
local mapFloor = nil

-- One long frame at terminal velocity can carry the body past the catch line
-- between two looks. Capping the fall keeps every frame short enough that the
-- catch stays ahead of it. Same reason and same number as the EggWars farm.
local FALL_CAP = 140

-- The chest drains item by item once Vape has it in range. r026 chestopen.log:
-- six items gone between 09:31:54 and 09:31:55. 0.4s was cutting that short.
-- A pile needs a beat longer than a single chest: five chests drain in sequence,
-- not at once.
local CHEST_MAX_WAIT = 1.4
local CHEST_GRACE = 0.35

local SWORD = { BronzeSword = 18, IronSword = 23, GoldSword = 25, DiamondSword = 29, OnyxSword = 32 }
local GOOD_ENOUGH = 29

-- Tier four and nothing else. His rule, said more than once: only ChestTierFour
-- carries the diamond and the onyx, so a tier one at your feet is worth less
-- than no chest at all - it costs the walk and the seconds and gives a sword
-- that changes nothing. When the tier fours are gone there is no reason left to
-- loot, so the farm goes hunting instead.
local ONLY_TIER = 4

-- 2026-08-21, his rule, said twice in one morning: "make sure it was must get
-- the dimond or onyx then go telpting player, it was not allow to telpting
-- player until get that". So there is no time backstop and no "fight anyway"
-- branch. Below GOOD_ENOUGH the farm may still swing at anything that walks
-- into HIT_RANGE, but it may not teleport to a man. Ever.
local F = {
	on = false, auto = true, mode = "VIPER", frames = 2,
	phase = "idle", round = 0, roundStart = 0, firstKill = 0, lastKill = 0,
	kills = 0, chests = 0, sword = "none", swordDmg = 0, target = "none",
	err = "", queued = false, boosted = false, hitId = "",
	voidCatches = 0, clamped = 0, skippedVoid = 0, rescuing = false, swordVia = "-",
	tpAllowed = false, dropped = 0, ceiling = nil, bandLifts = 0,
	dmgSeen = 0, dmgWindows = 0, dmgHits = 0, finishes = 0,
	gap = 0.08, parked = 0, dryFor = 0,
	-- Viper's clients end the round on 100 health. Manus read the bottom bar at
	-- video 01.00, 06.00 and 21.00 seconds and it says 100 every time, so across
	-- the whole DUO round he is never hit once. That is the real measure of
	-- whether the positioning works, and it is the thing he keeps telling me is
	-- wrong on ours. So the farm now counts what it takes, not just what it deals.
	hpMin = 100, hpTaken = 0, hitsTaken = 0, clock = 0, below = 15, clusterSize = 0, clockAtFirstKill = -1, freeSwings = 0, freeChests = 0,
	tpErrSum = 0, tpErrN = 0, tpErrMax = 0,
	-- Every counter starts as a number, never nil. A reload in the middle of a
	-- round only ran the round-change block on the NEXT round, so until then
	-- swings, viaMobile and killBase were all nil - and a nil killBase sent
	-- countKill down its fallback branch, which meant the kill count could not
	-- move at all. Measured 2026-08-21 17:0x on a live client.
	swings = 0, tps = 0, leavers = 0, viaMobile = 0, viaFire = 0,
	skippedNoUnder = 0, killBase = nil,
}
env.__SOLOFARM = F

-- ---------------------------------------------------------------- settings
--
-- His words, 2026-08-21: "i at the last round set frame 1 but next roudn was
-- viper, fix that and also all others button can save must save it funcaiton
-- status also". A teleport builds a new Luau VM and this file loads again from
-- its own defaults, so anything the panel does has to be on disk the moment it
-- happens - not at round end, which never runs when the VM dies mid round.

local CFG_FILE = "RobloxComm/solo/solo_farm_cfg.json"
local KEEP = { "mode", "frames", "auto", "on" }

-- A save that fails silently is a save that puts FRAME 1 back to VIPER on the
-- next round without telling anybody, which is the exact complaint. It reports
-- on the panel either way.
local function saveCfg()
	local ok, e = pcall(function()
		if not isfolder("RobloxComm") then makefolder("RobloxComm") end
		if not isfolder("RobloxComm/solo") then makefolder("RobloxComm/solo") end
		local t = {}
		for _, k in ipairs(KEEP) do t[k] = F[k] end
		writefile(CFG_FILE, game:GetService("HttpService"):JSONEncode(t))
	end)
	if ok then
		F.saved = os.date("%H:%M:%S")
	else
		F.saved = "SAVE FAILED"
		F.err = "save: " .. tostring(e):sub(1, 55)
	end
	return ok
end
env.__SOLOFARM_SAVE = saveCfg

local function loadCfg()
	pcall(function()
		if not isfile(CFG_FILE) then return end
		local t = game:GetService("HttpService"):JSONDecode(readfile(CFG_FILE))
		if type(t) ~= "table" then return end
		for _, k in ipairs(KEEP) do
			if t[k] ~= nil and type(t[k]) == type(F[k]) then F[k] = t[k] end
		end
		if F.mode ~= "VIPER" and F.mode ~= "FRAME" then F.mode = "VIPER" end
		if F.frames ~= 1 and F.frames ~= 2 then F.frames = 2 end
	end)
end
loadCfg()

-- The game's own round clock, which is the clock Viper's numbers are on.
--
-- Manus read the in-game timer off the DUO video and it does not agree with the
-- video clock: video 01.00s is round 00:00, video 12s is round 00:09, video 23s
-- is round 00:20. So "duos 21 seconds" is 21 seconds of ROUND time, and every
-- comparison this file has made against 12 seconds so far started its stopwatch
-- when the client joined the server, which is minutes too early.
--
-- Found on the live client at PlayerGui.GameScoreboard, a label reading mm:ss.
local function roundClock()
	local v
	pcall(function()
		local gs = lp.PlayerGui:FindFirstChild("GameScoreboard")
		if not gs then return end
		for _, d in ipairs(gs:GetDescendants()) do
			if d:IsA("TextLabel") then
				local m, sec = tostring(d.Text):match("^(%d%d):(%d%d)$")
				if m then v = tonumber(m) * 60 + tonumber(sec) return end
			end
		end
	end)
	return v
end

local function inMatch() return game.PlaceId == MATCH_PLACE end
local function inLobby() return game.PlaceId == LOBBY_PLACE end
local function fail(w, e) F.err = w .. ": " .. tostring(e):sub(1, 55) end

local function put(file, text)
	pcall(function()
		if not isfolder("RobloxComm") then makefolder("RobloxComm") end
		if not isfolder("RobloxComm/solo") then makefolder("RobloxComm/solo") end
		if isfile(file) then appendfile(file, text) else writefile(file, text) end
	end)
end

-- Frame rate is the one lever that cuts both sides at once: the picture draws
-- per frame and this loop runs per frame. On the EggWars side capping took
-- seven clients from 97 percent of the CPU down to 66.
-- Quality has ONE owner and it is SOLO_PLAY's downgrade button.
--
-- 2026-08-21 18:4x: this function used to cap fps at 30 and mute the game on its
-- own, which is not his downgrade and was never asked for, and having two
-- scripts writing the same render settings is the exact shape of bug that wastes
-- a night. SOLO_PLAY now carries the ABCD RAM DOWNGRADE verbatim and this one
-- keeps out of it.
local function downgrade()
	if F.boosted then return end
	F.boosted = true
end

local function myChar() return lp.Character end
local function myRoot() local c = myChar() return c and c:FindFirstChild("HumanoidRootPart") or nil end
local function myHum() local c = myChar() return c and c:FindFirstChildOfClass("Humanoid") or nil end
local function amAlive() local h = myHum() return h ~= nil and h.Health > 0 end

-- Falls back to the character pivot when the root part has not appeared yet.
local function myPos()
	local r = myRoot()
	if r then return r.Position end
	local c = myChar()
	if c then
		local ok, pv = pcall(function() return c:GetPivot().Position end)
		if ok and pv then return pv end
	end
	return nil
end

-- On the map means below the holding pen and above the void, with a body.
local function onMap()
	local p = myPos()
	return p ~= nil and p.Y < LOBBY_Y and p.Y > VOID_Y
end

-- ---------------------------------------------------------------- moving

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundUnder(pos)
	local hit
	pcall(function()
		local c = myChar()
		rayParams.FilterDescendantsInstances = c and { c } or {}
		hit = workspace:Raycast(pos, Vector3.new(0, -26, 0), rayParams)
	end)
	return hit
end

local lastSafe = nil

local function mapSpawn()
	local p
	pcall(function()
		local bc = workspace:FindFirstChild("BlockContainer")
		local map = bc and bc:FindFirstChild("Map")
		local sl = map and map:FindFirstChild("SpawnLocation")
		if sl then p = sl.Position + Vector3.new(0, 4, 0) end
	end)
	return p or Vector3.new(0, 2, 0)
end

-- One door. Every move in this file goes through it, so the clamp only has to
-- exist once. freeze is for the rescue climb: a normal hop leaves velocity
-- alone, but climbing out of a fall means cancelling gravity at every step or
-- the lerp spends the whole climb fighting a body still accelerating downwards.
local hopBusy = false

-- 2026-08-21 17:0x - why every swing missed.
--
-- Measured first, so this is not another guess: teleports stick (average error
-- 1.72 studs, worst 4.1 over 17 samples), so the body really is where this file
-- puts it. What it was NOT doing was facing anybody. Every move here wrote
-- CFrame.new(goal), and CFrame.new with one argument throws the rotation away -
-- the character ends up facing world forward, whatever that happens to be.
--
-- That matters because the game's own strike is not a sphere around you. From
-- the decompiled melee-controller:
--     GetPartBoundsInBox(cf * CFrame.new(0, 0, -5), Vector3.new(12, 6, 9))
-- a box five studs IN FRONT of the character. Stand 4.5 studs under a man while
-- facing an arbitrary direction and he is simply not in the box, which is
-- exactly what 544 swings across five rounds for zero health lost looks like.
--
-- So every combat move now carries a look target, and the strike goes through
-- the game's own strikeMobile so the raycast, the box test and the payload are
-- the game's rather than this file's imitation of them.
local function hop(goal, freeze, lookAt)
	local r = myRoot()
	if not r or not r.Parent then return false end
	if goal.Y < SAFE_Y then
		goal = Vector3.new(goal.X, SAFE_Y, goal.Z)
		F.clamped = F.clamped + 1
	end
	if hopBusy then
		local untilT = os.clock() + 0.5
		while hopBusy and os.clock() < untilT do RunService.Heartbeat:Wait() end
		if hopBusy then
			pcall(function()
				r.CFrame = (lookAt and (goal - lookAt).Magnitude > 0.5)
					and CFrame.new(goal, lookAt) or CFrame.new(goal)
				r.AssemblyLinearVelocity = Vector3.zero
			end)
			return true
		end
	end
	-- ONE WRITE. His words, 2026-08-21 16:0x: "u need to remvoe the moving, as it
	-- now was not telpting it was moving tept0ing that was suck".
	--
	-- He is describing exactly what the old code did: a gap larger than HOP_MAX
	-- was walked as a lerp of up to eight steps, one per Heartbeat, so a 200 stud
	-- trip took eight frames and looked like gliding across the map instead of
	-- vanishing and reappearing. That glide is also what let other players track
	-- and hit the body on the way.
	--
	-- The multi step version existed for the EggWars server, which answered a
	-- single long jump with "Unexpected behaviour, code 10449" on 2026-08-11.
	-- That was a different game mode and a different server; if a kick shows up
	-- here it will be in the kick log and HOP_STEPS goes back above 1.
	hopBusy = true
	local rr = myRoot()
	if rr and rr.Parent then
		pcall(function()
			rr.CFrame = (lookAt and (goal - lookAt).Magnitude > 0.5)
				and CFrame.new(goal, lookAt) or CFrame.new(goal)
			rr.AssemblyLinearVelocity = Vector3.zero
		end)
		F.tps = (F.tps or 0) + 1

		-- Does the write stick?
		--
		-- 2026-08-21 16:5x: five rounds, 544 swings, 190 measurement windows, a
		-- Diamond and an Onyx in hand, and the targets lost exactly zero health.
		-- The swing call matches what the game's own melee-controller does, so
		-- the next suspect is position: if the server never accepts where this
		-- file puts the body, then from the server's side every swing is thrown
		-- from wherever it last believed we were, and every one of them misses.
		-- That would also explain the other half of his complaint - being hit
		-- while apparently standing somewhere safe.
		--
		-- So every teleport now checks itself one frame later and keeps the
		-- error. A number near zero means the write sticks and the swing is the
		-- problem; a large number means the position is, and nothing about the
		-- attack code is worth touching until that is settled.
		task.spawn(function()
			local want = goal
			RunService.Heartbeat:Wait()
			RunService.Heartbeat:Wait()
			local r2 = myRoot()
			if r2 and r2.Parent then
				local e = (r2.Position - want).Magnitude
				F.tpErrSum = F.tpErrSum + e
				F.tpErrN = F.tpErrN + 1
				if e > F.tpErrMax then F.tpErrMax = e end
			end
		end)
	end
	hopBusy = false
	return true
end

-- UNDER HIM OR NOWHERE. This is the one place the Viper rule turns into code,
-- so there is deliberately no second branch: the earlier version fell back to
-- standing level with the target when under was unsafe, and standing level is
-- the exact thing he says gets you hit. If the spot under a man is below the
-- map floor, he is not a target this instant - the caller skips him.
--
-- The offset is the one Viper said he would add: a stud and a half off the
-- vertical axis so the body is not on a perfectly predictable line under the
-- target, alternating side by target so consecutive picks do not stack.
local combatCeiling = nil

-- Returns the spot, or nil and the reason it refused. The reason is what gets
-- written into the per-second tracker, because "the farm stood still for five
-- seconds while a man was walking around" is not debuggable without it.
--
-- 2026-08-21 17:3x, the stall he caught: a man standing on the lowest island
-- has his root about three studs above the floor, so "four and a half studs
-- under him" is below SAFE_Y, and the old code answered that with nil - no spot,
-- no target, nothing to do, forever. Standing as low as is legal is still under
-- him and still in reach, so that is what it does now. nil is reserved for the
-- cases where under genuinely is not available.
local function strikeSpot(tp, seed)
	local y = tp.Y - BELOW
	local why = nil
	if y < SAFE_Y then
		y = SAFE_Y
		if y >= tp.Y - 1 then return nil, "floor is level with him" end
		-- Only refuse when the floor forces us ABOVE him. How far below is
		-- allowed is what the ladder is testing, so it is not clamped here.
		if (tp.Y - y) > math.max(HIT_RANGE - 1, BELOW + 2) then
			return nil, "floor is out of reach below him"
		end
		why = "clamped to floor"
	end
	-- 2026-08-21 17:4x - the ceiling as first written was self-defeating and the
	-- per-second tracker proved it in one line. At 17:39:27 every living player
	-- read "no spot: above ceiling -11" - the man at 6 studs on 42 health, the
	-- man at 247 studs on 19 health, and the man at 456 studs on full health.
	--
	-- The reason is circular. The ceiling was pinned to my own Y and only ever
	-- fell. But the whole tactic is to stand 4.5 studs UNDER the target, so my Y
	-- is by construction below his, which drags the ceiling under him, which
	-- makes him illegal on the very next frame. It fought itself: lift the band,
	-- take one swing, sink, re-block, lift again.
	--
	-- Viper's actual words are "you don't want to go up" - that is a rule against
	-- CLIMBING to chase somebody, not a rule that everybody above my head is
	-- untouchable. So the limit is on the size of the ascent, not on an absolute
	-- height, and the low-first ordering in pickLowest is what carries the rest
	-- of his rule.
	local mine = myPos()
	if mine and (y - mine.Y) > MAX_CLIMB then
		return nil, string.format("would climb %.0f studs", y - mine.Y)
	end
	local off = ((seed or 0) % 2 == 0) and BELOW_OFFSET or -BELOW_OFFSET
	return Vector3.new(tp.X + off, y, tp.Z - off), why
end

-- ---------------------------------------------------------------- anti void

task.spawn(function()
	while alive() do
		RunService.Heartbeat:Wait()
		if inMatch() then
			pcall(function()
				local r = myRoot()
				if not r or not r.Parent then return end
				local pos = r.Position
				if pos.Y >= SAFE_Y and pos.Y < LOBBY_Y and groundUnder(pos) then
					lastSafe = pos
				end
				if pos.Y < SAFE_Y then
					local v = r.AssemblyLinearVelocity
					if v.Y < -FALL_CAP then
						r.AssemblyLinearVelocity = Vector3.new(v.X, -FALL_CAP, v.Z)
					end
				end
				if pos.Y < VOID_Y then
					F.rescuing = true
					local goal = lastSafe and (lastSafe + Vector3.new(0, 4, 0)) or mapSpawn()
					hop(goal, true)
					F.voidCatches = F.voidCatches + 1
					F.phase = string.format("anti void catch from y %.0f", pos.Y)
					F.rescuing = false
				end
			end)
		end
	end
end)

-- ---------------------------------------------------------------- hitting

-- 2026-08-21 16:0x - the farm was firing the wrong thing and dealing nothing.
--
-- Measured: 16 fires at a target 3.0 studs away took a player from 100 health
-- to 100 health. Zero. The reason is in the game's own melee-controller, read
-- by decompiling it rather than guessing:
--
--   local Events = RuntimeLib.import(script, script.Parent.Parent, "events").Events
--   ...
--   Events["0f825f49-002e-4b7b-8d8c-24dbb3494845"]:fire(PlayerFromCharacter)
--
-- It is a networking wrapper with a :fire method, not a RemoteEvent with
-- :FireServer. This file was doing FindFirstChild(id, true):FireServer(target),
-- which reaches a raw instance the server is not listening to in that shape, so
-- every swing since this file was written has been a blank. The kill counter hid
-- it, because that counted anybody leaving the server - see countKill below.
--
-- The client's own range test lives at melee-controller line 169:
--   if v7 >= MeleeConstants.MAXIMUM_HIT_RANGE_BLOCKS * 2.3 then fire(nil)
-- so beyond 10.35 studs the game deliberately sends a miss. Calling :fire(target)
-- ourselves skips that test; whether the SERVER also tests is a separate
-- question and is answered by rangetest2.txt, not by this comment.
local eventsTable
local function events()
	if eventsTable then return eventsTable end
	pcall(function()
		local ps = lp:WaitForChild("PlayerScripts", 10)
		eventsTable = require(ps.TS.events).Events
	end)
	return eventsTable
end

-- The game's own melee controller, resolved once. Calling its strikeMobile is
-- the whole point: it runs the game's raycast and the game's box test and sends
-- whatever the server is actually listening for, instead of this file guessing
-- the payload. The direct event fire stays as a fallback and is counted
-- separately so the logs can tell which path did the work.
local meleeCache
local function melee()
	if meleeCache then return meleeCache end
	pcall(function()
		local mod = flamework()
		local ps = lp:WaitForChild("PlayerScripts", 10)
		local cls = require(ps.TS.controllers["melee-controller"])
		local target = cls
		if type(cls) == "table" then
			for _, v in pairs(cls) do
				if type(v) == "table" and mod.Reflect.getMetadata(v, "identifier") then target = v break end
			end
		end
		meleeCache = mod.Flamework.resolveDependency(mod.Reflect.getMetadata(target, "identifier"))
	end)
	return meleeCache
end

local function strike(thing, isPlayer)
	if isPlayer then
		local mc = melee()
		if mc and mc.strikeMobile then
			F.hitId = "strikeMobile"
			local ok = pcall(function() mc:strikeMobile() end)
			if ok then
				F.viaMobile = (F.viaMobile or 0) + 1
				return true
			end
		end
	end
	local ev = events()
	if not ev then
		fail("strike", "cannot reach the events table")
		return false
	end
	for _, id in ipairs(isPlayer and HIT_PLAYER_IDS or HIT_ENTITY_IDS) do
		local e = ev[id]
		if e and e.fire then
			F.hitId = id
			F.viaFire = (F.viaFire or 0) + 1
			return pcall(function() e:fire(thing) end)
		end
	end
	fail("strike", "no damage event in this place")
	return false
end

-- ---------------------------------------------------------------- flamework

local flame
local function flamework()
	if flame then return flame end
	pcall(function()
		flame = require(ReplicatedStorage.rbxts_include.node_modules["@flamework"].core.out)
	end)
	return flame
end

local mmCache
local function matchmaking()
	if mmCache then return mmCache end
	local ok, err = pcall(function()
		local mod = flamework()
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
	if not ok then fail("matchmaking", err) end
	return mmCache
end

-- Kept for anything that still calls it, but SOLO_PLAY owns queueing now:
-- gating on the place was the bug, because the end screen sits inside the
-- match place where canQueue is already true.
local function queueNow()
	local mm = matchmaking()
	if not mm then return false end
	local q, can = false, false
	pcall(function() q = mm:isInQueue() end)
	pcall(function() can = mm:canQueue() end)
	if q then F.queued = true return true end
	if not can then return false end
	local ok = pcall(function() if BANNED_QUEUE[QUEUE_ID] then error("refusing to queue into " .. QUEUE_ID) end
		armGameAutoQueue()
		mm:joinQueueIn(0) end)
	F.queued = ok
	return ok
end
env.__SOLOFARM_QUEUE = queueNow

-- The hotbar controller is where this game keeps the inventory. Its flamework
-- id is p4Q in the match place; resolve it by name as well so a place update
-- that renames it does not silently take the sword reading away again.
local hbCache
local function hotbar()
	if hbCache then return hbCache end
	pcall(function()
		local mod = flamework()
		hbCache = mod.Flamework.resolveDependency("p4Q")
	end)
	if hbCache then return hbCache end
	pcall(function()
		local mod = flamework()
		local ps = lp:WaitForChild("PlayerScripts", 10)
		local cls = require(ps.TS.controllers["hotbar-controller"])
		local target = cls
		if type(cls) == "table" then
			for _, v in pairs(cls) do
				if type(v) == "table" and mod.Reflect.getMetadata(v, "identifier") then target = v break end
			end
		end
		hbCache = mod.Flamework.resolveDependency(mod.Reflect.getMetadata(target, "identifier"))
	end)
	return hbCache
end

-- Reads the real inventory first and only falls back to the Roblox Backpack,
-- which measured 0 children in this game and is why the panel used to say
-- "sword none" while the account was holding a Diamond Sword.
local function swordNow()
	local name, dmg, via = "none", 0, "-"
	local hb = hotbar()
	if hb then
		pcall(function()
			local s = hb:getSword()
			if s then
				name = tostring(s.Name or s.ToolRef or "?")
				dmg = (s.Melee and tonumber(s.Melee.Damage)) or SWORD[name] or 0
				via = "hotbar"
			end
		end)
	end
	if dmg == 0 then
		local function look(c)
			if not c then return end
			for _, t in ipairs(c:GetChildren()) do
				local d = SWORD[t.Name]
				if d and d > dmg then name, dmg, via = t.Name, d, "backpack" end
			end
		end
		pcall(function() look(lp:FindFirstChild("Backpack")) end)
		pcall(function() look(myChar()) end)
	end
	F.sword, F.swordDmg, F.swordVia = name, dmg, via
	return name, dmg
end

-- Equipping is a slot change, not EquipTool: the item only becomes a real Tool
-- once it is the active slot.
local function equipSword()
	local name = F.sword
	if name == "none" then return end
	local hb = hotbar()
	if not hb then return end
	pcall(function()
		if hb.lastHeldItem and tostring(hb.lastHeldItem.Name) == name then return end
		local items = hb:getHotbarItems()
		for _, it in pairs(items) do
			if tostring(it.Type) == name and it.Slot ~= nil then
				hb:setActiveSlot(it.Slot)
				return
			end
		end
	end)
end

-- ---------------------------------------------------------------- chests

local function tierOf(name)
	local w = name:match("^ChestTier(%a+)")
	local m = { One = 1, Two = 2, Three = 3, Four = 4 }
	return w and (m[w] or 0) or 0
end

local function chestFolder()
	local f
	pcall(function()
		local bc = workspace:FindFirstChild("BlockContainer")
		local map = bc and bc:FindFirstChild("Map")
		f = map and map:FindFirstChild("Chests")
	end)
	if not f then
		pcall(function()
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:IsA("Folder") and d.Name == "Chests" then f = d break end
			end
		end)
	end
	return f
end

-- The chest folder is also the map's own statement of where its floor is: the
-- lowest chest is sitting on the lowest island. Read it every second until it
-- settles rather than trusting a number taken off a different map.
-- 2026-08-21 10:0x - the lowest chest is NOT the lowest standing surface, and
-- believing it was cost sixty seconds of a live round.
--
-- Measured at 10:00:35: the farm had a DiamondSword, tp unlocked, 24 tier four
-- chests left, and stood at y -4.3 for sixty seconds with foes=0 while four
-- players were alive on the map at y -20.4, -1.3, -25.3 and 4.5, every one of
-- them at 100 health. F.dropped read 4. The tier four chest the ladder tried to
-- walk to was at y -9, so this map's lowest chest is shallow, VOID_Y came out
-- around -20, and two men standing on perfectly solid low islands were written
-- off as falling into the void. The tracker then kept that verdict for the rest
-- of the round, living() returned nothing, and the farm had nobody to fight.
--
-- So the floor is the lowest of three measurements, not one:
--   the lowest chest,
--   the lowest ALIVE player who has ground under him right now,
--   the lowest point I have stood on with ground under me.
-- and it only ever ratchets downwards within a round.
local function recalcFloor()
	local mn
	local folder = chestFolder()
	if folder then
		for _, c in ipairs(folder:GetChildren()) do
			local ok, p = pcall(function() return c:GetPivot().Position end)
			if ok and p and (not mn or p.Y < mn) then mn = p.Y end
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		local rr = ch and ch:FindFirstChild("HumanoidRootPart")
		local h = ch and ch:FindFirstChildOfClass("Humanoid")
		if rr and h and h.Health > 0 and rr.Position.Y < LOBBY_Y then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { ch }
			local hit
			pcall(function()
				hit = workspace:Raycast(rr.Position, Vector3.new(0, -12, 0), params)
			end)
			if hit and (not mn or rr.Position.Y < mn) then mn = rr.Position.Y end
		end
	end
	if mapFloor and (not mn or mapFloor < mn) then mn = mapFloor end
	if not mn then return end
	mapFloor = mn
	SAFE_Y = mn - 2
	VOID_Y = mn - 11
end

task.spawn(function()
	while alive() do
		task.wait(1)
		if inMatch() then pcall(recalcFloor) end
	end
end)

-- Keyed by the instance itself. See fault 1 in the header - keyed by
-- tostring(chest) this was one shared key for all sixteen.
local visited = {}

local function countT4()
	local folder = chestFolder()
	if not folder then return 0, 0 end
	local total, left = 0, 0
	for _, c in ipairs(folder:GetChildren()) do
		if tierOf(c.Name) == ONLY_TIER then
			total = total + 1
			if not visited[c] then left = left + 1 end
		end
	end
	return total, left
end

local function rankedChests()
	local folder = chestFolder()
	local here = myPos()
	if not folder or not here then return {} end
	local list = {}
	for _, c in ipairs(folder:GetChildren()) do
		if tierOf(c.Name) == ONLY_TIER and not visited[c] then
			local p
			pcall(function() p = c:GetPivot().Position end)
			if p then
				list[#list + 1] = { inst = c, pos = p, dist = (p - here).Magnitude }
			end
		end
	end
	-- every entry is tier four now, so nearest first is the whole ordering
	table.sort(list, function(a, b) return a.dist < b.dist end)
	return list
end

-- Stand in the middle of a pile of chests, not on top of one.
--
-- His words, 2026-08-21 18:3x: "u need to k to detecting the middle of the chest
-- beucase u k that there is having a place was super many tier 4 chest at there,
-- so need to be at the middle then the vape will at one time to getting over 5
-- chest at one time ... telpting to oen chest = lwoer chance fast get dimond
-- sowrd, that will cost over 1-2 sec".
--
-- He is describing the actual cost. Every hop to a single chest is a second or
-- two of walking and waiting for one roll of the dice, and the map census keeps
-- showing the tier fours arriving in tight clusters - twelve of the sixteen on
-- one map sat inside a thirty stud box around the origin. Landing on the
-- centroid of a cluster puts every chest in it inside Vape's pickup radius at
-- once, so one hop buys five rolls instead of one.
--
-- The radius is CHEST_REACH, which is the distance chests have actually been
-- taken from in the open logs, not a guess at Vape's internals. The score is
-- how many unvisited tier fours a spot covers, with distance only as the tie
-- break, so a pile of five never loses to a single chest underfoot.
local function bestChestCluster()
	local list = rankedChests()
	if #list == 0 then return nil end
	local here = myPos()
	local best, bestN, bestD = nil, 0, math.huge
	for _, c in ipairs(list) do
		local members = {}
		local sx, sy, sz = 0, 0, 0
		for _, o in ipairs(list) do
			if (o.pos - c.pos).Magnitude <= CHEST_REACH then
				members[#members + 1] = o
				sx = sx + o.pos.X
				sy = sy + o.pos.Y
				sz = sz + o.pos.Z
			end
		end
		local n = #members
		local centre = Vector3.new(sx / n, sy / n, sz / n)
		local d = here and (centre - here).Magnitude or 0
		if n > bestN or (n == bestN and d < bestD) then
			best, bestN, bestD = { centre = centre, members = members }, n, d
		end
	end
	F.clusterSize = bestN
	return best
end

-- ---------------------------------------------------------------- targets

-- The tracker, the ABCD way. Over there a target the threat budget gave up on
-- is struck off for the rest of the round and every mover reads the same
-- verdict; the same shape is what this needs, because "he is above the line
-- right now" is not the same as "he is worth teleporting to". A man who has
-- walked off an island stays above VOID_Y for the whole first second of the
-- fall, and that first second is exactly when the old code picked him: VIPER
-- sorts by lowest Y, and the lowest living player in SkyWars is nearly always
-- the one on his way out. Round 27 samples, 09:32:43 to 09:32:48, parked at
-- y -49 under a map whose floor is -24.
--
-- So a man is written off the moment either is true, and it sticks:
--   he is under VOID_Y, or
--   he is falling faster than FALLING_Y a second with nothing under him.
local FALLING_Y = 55
local track = {}

-- Kept on the same record as the void tracker so there is one row per player.
local function movedRecently(p)
	local t = track[p]
	if not t or not t.lastMove then return true end
	return (os.clock() - t.lastMove) < PARKED_SECS
end

local function trackerPass()
	local now = os.clock()
	local dropped = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= lp then
			local ch = p.Character
			local rr = ch and ch:FindFirstChild("HumanoidRootPart")
			local t = track[p]
			if not t then t = { y = nil, at = now, gone = false } track[p] = t end
			if rr then
				local y = rr.Position.Y
				-- Has he moved at all? Under a stud between samples is standing
				-- still, not walking.
				if t.movePos == nil or (rr.Position - t.movePos).Magnitude > 1.0 then
					t.movePos = rr.Position
					t.lastMove = now
				end
				-- A verdict that never expires is how four standing men stayed
				-- written off for a whole round. Anyone back above the line with
				-- health is back on the list.
				if t.gone and y >= VOID_Y + 4 then
					local h = ch and ch:FindFirstChildOfClass("Humanoid")
					if h and h.Health > 0 then t.gone = false t.why = nil end
				end
				if not t.gone then
					if y < VOID_Y then
						t.gone = true
						t.why = "under the line"
					else
						local dt = now - t.at
						local vy
						pcall(function() vy = rr.AssemblyLinearVelocity.Y end)
						local rate = (t.y and dt > 0.05) and ((y - t.y) / dt) or 0
						local falling = (vy ~= nil and vy < -FALLING_Y) or rate < -FALLING_Y
						-- Two consecutive samples, not one. A man hopping between
						-- islands is briefly falling with nothing under him and is
						-- not lost; a man in the void stays that way.
						if falling then
							local params = RaycastParams.new()
							params.FilterType = Enum.RaycastFilterType.Exclude
							params.FilterDescendantsInstances = { ch }
							local hit
							pcall(function()
								hit = workspace:Raycast(rr.Position, Vector3.new(0, -30, 0), params)
							end)
							if not hit then
								t.falls = (t.falls or 0) + 1
								if t.falls >= 2 then
									t.gone = true
									t.why = "falling with no floor twice"
								end
							else
								t.falls = 0
							end
						else
							t.falls = 0
						end
					end
				end
				if now - t.at > 0.1 then t.y = y t.at = now end
			end
			if t.gone then dropped = dropped + 1 end
		end
	end
	F.dropped = dropped
end

task.spawn(function()
	while alive() do
		task.wait(0.15)
		if inMatch() then pcall(trackerPass) end
	end
end)

-- NO SILENT CAP. The tracker is allowed to trim the target list, never to empty
-- it: if every living man has been written off but men are still alive on the
-- map, the tracker is wrong and gets ignored for this call. Sixty seconds of
-- foes=0 with four healthy players on screen is what this line is for.
-- Health lives on the Player, not on the Humanoid.
--
-- 2026-08-21 17:0x: this is the correction to the "544 swings, zero damage"
-- finding. Humanoid.Health in this game reads 100 for everybody; the number the
-- game actually plays with is the Health ATTRIBUTE on the Player, which was
-- measured at 68, 42 and 17 on three different players at 10:0x while every
-- Humanoid in the same sample said 100. So the damage probe was reading a field
-- that never moves and calling the result zero.
--
-- The kill baseline is the other half of the correction: it read 1112 at 16:04
-- and 1263 at 17:05, so 151 kills happened on this account in that hour while
-- the farm was the only thing playing.
local function hpOf(p)
	if not p then return nil end
	local a = p:GetAttribute("Health")
	if type(a) == "number" then return a end
	local ch = p.Character
	local h = ch and ch:FindFirstChildOfClass("Humanoid")
	return h and h.Health or nil
end

local function living()
	local r = myRoot()
	if not r then return {} end
	local out, raw = {}, {}
	local skipped = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= lp then
			local ch = p.Character
			local rr = ch and ch:FindFirstChild("HumanoidRootPart")
			local h = ch and ch:FindFirstChildOfClass("Humanoid")
			-- Alive is an attribute too, and it is the one the game believes.
			local aliveAttr = p:GetAttribute("Alive")
			local hp = hpOf(p)
			local reallyAlive = (aliveAttr ~= false) and ((hp == nil) or hp > 0)
			if rr and h and reallyAlive then
				local y = rr.Position.Y
				local t = track[p]
				if y < LOBBY_Y then
					local e = { p = p, root = rr, y = y, dist = (rr.Position - r.Position).Magnitude }
					raw[#raw + 1] = e
					if y >= VOID_Y and not (t and t.gone) then
						out[#out + 1] = e
					else
						skipped = skipped + 1
					end
				else
					skipped = skipped + 1
				end
			end
		end
	end
	F.skippedVoid = skipped
	if #out == 0 and #raw > 0 then
		F.trackerOverruled = (F.trackerOverruled or 0) + 1
		for _, p in pairs(track) do p.gone = false p.falls = 0 end
		return raw
	end
	return out
end

-- The kill count is read off the account, not counted from who left.
--
-- Players.PlayerRemoving fires when anybody quits, rage quits, is kicked or is
-- teleported out, and the old counter called every one of those a kill. That is
-- how a round could report nine kills while the swing code was dealing no
-- damage at all. Every player in this game carries a Kills attribute - measured
-- 2026-08-21 10:0x, his account read Kills 299 - so the number for a round is
-- simply the difference across it.
local function myKills()
	local v
	pcall(function() v = lp:GetAttribute("Kills") end)
	return tonumber(v)
end

local function countKill()
	local now = myKills()
	if now and F.killBase then
		local n = now - F.killBase
		if n > F.kills then
			F.kills = n
			if F.firstKill == 0 then F.firstKill = os.clock() - F.roundStart end
			F.lastKill = os.clock() - F.roundStart
		end
		return
	end
	F.leavers = (F.leavers or 0) + 1
end

-- Hold position under the target for the dwell, cancelling gravity every frame.
-- Without the freeze the body builds fall speed for the whole dwell and leaves
-- the exchange already moving downwards, which is the other half of fault 3.
local swingSeq = 0

-- Does a swing do anything at all?
--
-- 2026-08-21 16:0x this stopped being a rhetorical question. Two separate probes
-- fired the hit event 15 times at a man 3 and 9 studs away and took him from 100
-- health to 100 health, and the round counter still reported kills - because it
-- was counting anybody who left the server. Both of those probes ran with no
-- sword in hand, so neither proves the swing is broken; what they prove is that
-- nothing in this file was ever measuring its own damage.
--
-- So the farm measures it now, every round, on itself. It is deliberately a
-- weak claim and it is labelled as one: health lost by a man while we were the
-- ones standing under him hitting him. Somebody else may have hit him in the
-- same window. What it can settle is the only question that matters right now -
-- whether the number is zero.

local function pin(rr, stopAt, hitIt, who)
	local last = 0
	local moved = false
	local hp0 = who and hpOf(who) or nil
	local swung = false
	while alive() and F.on and os.clock() < stopAt do
		if F.rescuing then return false end
		if not amAlive() then return false end
		if not rr or not rr.Parent then return true end
		local r = myRoot()
		if not r then return false end
		if F.tpAllowed then
			local want = strikeSpot(rr.Position, swingSeq)
			if not want then return false end
			if (want - r.Position).Magnitude > 3 then
				hop(want, false, rr.Position)
				moved = true
			else
				pcall(function()
					r.CFrame = CFrame.new(r.Position, rr.Position)
					r.AssemblyLinearVelocity = Vector3.zero
				end)
			end
		end
		local r2 = myRoot()
		-- Deliberately NOT gated on HIT_RANGE any more. HIT_RANGE is the client's
		-- own refusal threshold and this file does not go through the client's
		-- check; gating on it here would have made every rung of the ladder above
		-- 10.35 silently swing zero times and produce a fake "no damage" result.
		if r2 and (rr.Position - r2.Position).Magnitude <= math.max(HIT_RANGE, BELOW + 3) then
			if os.clock() - last >= HIT_GAP then
				hitIt()
				F.swings = (F.swings or 0) + 1
				swung = true
				last = os.clock()
			end
		end
		RunService.Heartbeat:Wait()
	end
	if swung and hp0 and who then
		local hp1 = hpOf(who)
		F.dmgWindows = F.dmgWindows + 1
		if hp1 and hp1 < hp0 then
			F.dmgSeen = F.dmgSeen + (hp0 - hp1)
			F.dmgHits = F.dmgHits + 1
			F.lastLandT = os.clock()
		end
		-- The account's Kills attribute only moves when the round commits, so it
		-- reads zero for the whole match and cannot say whether the farm is
		-- finishing anybody while it plays. This is the in-round stand-in: the
		-- man we were standing under, hitting, went from alive to not alive
		-- inside our own window. Another player could have landed the last blow
		-- in the same fifth of a second, so it is called finishes and not kills.
		if hp0 > 0 then
			local dead = (hp1 ~= nil and hp1 <= 0) or (who:GetAttribute("Alive") == false)
			if dead then
				F.finishes = F.finishes + 1
				if F.clockAtFirstKill < 0 then F.clockAtFirstKill = F.clock end
				if F.firstKill == 0 and F.roundStart > 0 then
					F.firstKill = os.clock() - F.roundStart
				end
				F.lastKill = F.roundStart > 0 and (os.clock() - F.roundStart) or 0
			end
		end
	end
	return moved or F.swings ~= nil
end

-- Lowest Y first, exactly as he described it, and the sort is redone on every
-- call rather than cached - the whole point of the 0.2 second switch is that
-- the priority is recomputed while it runs.
-- The ceiling only ever falls on its own. This is the one place it is allowed
-- to rise, and only when nobody is left underneath it.
local function liftBand(list)
	local best
	for _, t in ipairs(list) do
		local y = t.root.Position.Y - BELOW
		if y >= SAFE_Y and (not best or y < best) then best = y end
	end
	if not best then return false end
	MAX_CLIMB = CLIMB_RELAXED
	combatCeiling = best
	F.ceiling = best
	F.bandLifts = F.bandLifts + 1
	put("RobloxComm/solo/afk.log", string.format("%s\tr%03d\t-\tband\tlow group clear, ceiling lifted to y %.0f\n",
		os.date("%Y-%m-%d %H:%M:%S"), F.round, best))
	return true
end

-- Finish somebody instead of bruising everybody.
--
-- Measured 2026-08-21 17:0x: two rounds dealt 202 and 218 damage across 9 of
-- 28 and 9 of 30 windows, and killed nobody. About 22 damage a visit against
-- 100 health means five visits to finish one man, and with the target changing
-- every 0.2 seconds the farm was starting five fights and ending none. Viper
-- switches every 0.2s too, but he is switching between men he is about to
-- finish, not spreading a thin layer over the lobby.
--
-- So among the men it is legal to stand under, the weakest goes first. Lowest Y
-- stays as the tie break, which keeps his rule intact: the low group still gets
-- cleared before the ceiling lifts.
local function pickLowest(list, skip)
	-- Moving men first, parked men last, and inside each group the weakest first
	-- with lowest Y as the tie break. His rule and Viper's rule stack in that
	-- order: never spend a swing on a man who is standing still while a real one
	-- is alive, and never lift the ceiling before the low group is clear.
	local parked = 0
	for _, t in ipairs(list) do
		t.parked = not movedRecently(t.p)
		if t.parked then parked = parked + 1 end
	end
	F.parked = parked
	table.sort(list, function(a, b)
		if a.parked ~= b.parked then return b.parked end
		local ha = hpOf(a.p) or 100
		local hb = hpOf(b.p) or 100
		if math.abs(ha - hb) > 5 then return ha < hb end
		return a.y < b.y
	end)
	for _, t in ipairs(list) do
		if t.p ~= skip and strikeSpot(t.root.Position, swingSeq) then return t end
	end
	if liftBand(list) then
		for _, t in ipairs(list) do
			if t.p ~= skip and strikeSpot(t.root.Position, swingSeq) then return t end
		end
	end
	return nil
end

-- A man under this much health is worth staying on past the 0.2 second switch,
-- because leaving now wastes every hit already landed on him.
local FINISH_HP = 45
local FINISH_EXTRA = 0.5

local function killViper()
	local list = living()
	if #list == 0 then return false end
	swingSeq = swingSeq + 1
	local t = pickLowest(list, nil)
	if not t then
		F.target = "no one has a legal spot under him"
		F.skippedNoUnder = (F.skippedNoUnder or 0) + 1
		RunService.Heartbeat:Wait()
		return true
	end
	F.target = t.p.Name .. " y" .. string.format("%.0f", t.y)
		.. (t.parked and " PARKED" or "")
		.. (F.tpAllowed and " (under)" or " (no tp, sword too weak)")
	local hp = hpOf(t.p) or 100
	local dwell = VIPER_DWELL + ((hp <= FINISH_HP) and FINISH_EXTRA or 0)
	F.target = F.target .. ((hp <= FINISH_HP) and (" FINISH hp" .. string.format("%.0f", hp)) or "")
	return pin(t.root, os.clock() + dwell, function() strike(t.p, true) end, t.p)
end

local function killFrame()
	local list = living()
	if #list == 0 then return false end
	table.sort(list, function(a, b) return a.y < b.y end)
	for _, t in ipairs(list) do
		if not alive() or not F.on or not amAlive() or F.rescuing then return false end
		local rr = t.root
		if rr and rr.Parent then
			swingSeq = swingSeq + 1
			local want = strikeSpot(rr.Position, swingSeq)
			if not want then
				F.skippedNoUnder = (F.skippedNoUnder or 0) + 1
			else
				F.target = t.p.Name .. " x" .. F.frames
					.. (F.tpAllowed and " (under)" or " (no tp, sword too weak)")
				local r = myRoot()
				if r and F.tpAllowed and (want - r.Position).Magnitude > 3 then
					hop(want, false, rr.Position)
				end
				for _ = 1, F.frames do
					local r2 = myRoot()
					if r2 then
						pcall(function() r2.AssemblyLinearVelocity = Vector3.zero end)
						if (rr.Position - r2.Position).Magnitude <= HIT_RANGE then
							strike(t.p, true)
							F.swings = (F.swings or 0) + 1
						end
					end
					RunService.Heartbeat:Wait()
				end
			end
		end
	end
	return true
end

-- ---------------------------------------------------------------- round log

local function closeRound(why)
	if F.roundStart == 0 then return end
	local dur = os.clock() - F.roundStart
	local TAB, NL = string.char(9), string.char(10)
	put("RobloxComm/solo/ab_test.tsv",
		os.date("%Y-%m-%d %H:%M:%S") .. TAB
		.. string.format("r%03d", F.round) .. TAB
		.. F.mode .. TAB
		.. (F.mode == "FRAME" and tostring(F.frames) or tostring(VIPER_DWELL)) .. TAB
		.. string.format("%.1f", dur) .. TAB
		.. tostring(F.kills) .. TAB
		.. string.format("%.1f", F.firstKill) .. TAB
		.. string.format("%.1f", F.lastKill) .. TAB
		.. tostring(F.chests) .. TAB
		.. tostring(F.sword) .. TAB
		.. tostring(F.swordDmg) .. TAB
		.. tostring(F.voidCatches) .. TAB
		.. tostring(F.swings or 0) .. TAB
		.. tostring(F.afkEvents or 0) .. TAB
		.. tostring(F.skippedNoUnder or 0) .. TAB
		.. string.format("%.0f", F.dmgSeen) .. TAB
		.. tostring(F.dmgHits) .. "/" .. tostring(F.dmgWindows) .. TAB
		.. tostring(F.finishes) .. TAB
		.. string.format("%.1f", F.tpErrN > 0 and (F.tpErrSum / F.tpErrN) or -1) .. TAB
		.. string.format("%.0f", F.tpErrMax) .. TAB
		-- Viper says a solo round is twelve seconds. Anything else is the
		-- number this farm has to answer for, so it is written next to ours.
		.. string.format("%+.1f", dur - VIPER_SOLO_SECS) .. TAB
		.. tostring(why) .. NL)
	-- One row per round per gap, so "the fastest gap that still lands" ends up
	-- being a number in a file rather than an opinion.
	put("RobloxComm/solo/below_test.tsv",
		os.date("%Y-%m-%d %H:%M:%S") .. TAB
		.. string.format("%.1f", F.below) .. TAB
		.. tostring(F.swings) .. TAB
		.. string.format("%.0f", F.dmgSeen) .. TAB
		.. string.format("%.2f", (F.swings or 0) > 0 and (F.dmgSeen / F.swings) or 0) .. TAB
		.. tostring(F.finishes) .. TAB
		.. string.format("%.0f", F.hpTaken) .. TAB
		.. tostring(F.hitsTaken) .. TAB
		.. tostring(F.clock) .. NL)
	put("RobloxComm/solo/gap_test.tsv",
		os.date("%Y-%m-%d %H:%M:%S") .. TAB
		.. string.format("%.2f", F.gap) .. TAB
		.. string.format("%.0f", F.hpTaken) .. TAB
		.. tostring(F.hitsTaken) .. TAB
		.. string.format("%.0f", F.hpMin) .. TAB
		.. tostring(F.clock) .. TAB
		.. tostring(F.clockAtFirstKill) .. TAB
		.. tostring(F.freeSwings) .. "/" .. tostring(F.freeChests) .. TAB
		.. string.format("%.1f", F.below) .. TAB
		.. tostring(F.swings) .. TAB
		.. string.format("%.0f", F.dmgSeen) .. TAB
		.. string.format("%.2f", (F.swings or 0) > 0 and (F.dmgSeen / F.swings) or 0) .. TAB
		.. tostring(F.finishes) .. TAB
		.. string.format("%.1f", dur) .. NL)
	F.roundStart = 0
end
env.__SOLOFARM_CLOSE = closeRound

-- ---------------------------------------------------------------- panel

local panel, lbl = nil, {}

local function fmt(s)
	if s <= 0 then return "00:00" end
	return string.format("%02d:%02d", math.floor(s / 60), math.floor(s % 60))
end

local function paint()
	if not panel then return end
	pcall(function()
		lbl.state.Text = F.on and ("RUNNING - " .. F.phase)
			or (F.auto and "ARMED - starts on the next round" or "IDLE - press START")
		lbl.state.TextColor3 = F.on and Color3.fromRGB(155, 191, 149) or Color3.fromRGB(224, 145, 129)
		lbl.who.Text = "bot " .. lp.Name .. "  |  mode " .. F.mode
			.. (F.mode == "FRAME" and (" x" .. F.frames) or " 0.2s")
			.. "  |  " .. (inMatch() and "match" or (inLobby() and "lobby" or "menu"))
		local t = (F.roundStart > 0 and inMatch()) and (os.clock() - F.roundStart) or 0
		local _, left = countT4()
		lbl.timer.Text = "round " .. F.round .. "   timer " .. fmt(t)
			.. "   T4 left " .. left
			.. "   floor " .. (mapFloor and string.format("%.0f", mapFloor) or "?")
			.. (F.firstKill > 0 and ("   first kill " .. string.format("%.1fs", F.firstKill)) or "")
		lbl.stats.Text = F.finishes .. " finishes   took " .. string.format("%.0f", F.hpTaken)
			.. " in " .. tostring(F.hitsTaken) .. " (viper takes 0)   "
			.. F.chests .. " T4 chests   sword " .. F.sword
			.. (F.swordDmg > 0 and (" (" .. F.swordDmg .. ")") or "")
			.. "   tp " .. (F.tpAllowed and "UNLOCKED" or "LOCKED")
		lbl.tgt.Text = "target " .. F.target .. "   swings " .. tostring(F.swings or 0)
			.. "   ceil " .. (F.ceiling and string.format("%.0f", F.ceiling) or "-")
			.. "/" .. tostring(F.bandLifts)
			.. "   afk " .. tostring(F.afkStep)
		lbl.err.Text = F.err ~= "" and ("! " .. F.err)
			or ((F.boosted and "quality down, " or "") .. "queue " .. (F.queued and "in" or "out")
				.. "   void catch " .. F.voidCatches .. " clamp " .. F.clamped
				.. " dropped " .. F.dropped
				.. "   dmg " .. string.format("%.0f", F.dmgSeen)
				.. " in " .. tostring(F.dmgHits) .. "/" .. tostring(F.dmgWindows)
				.. "   tp err " .. string.format("%.1f", F.tpErrN > 0 and (F.tpErrSum / F.tpErrN) or -1)
				.. " max " .. string.format("%.0f", F.tpErrMax)
				.. "   via mobile " .. tostring(F.viaMobile or 0) .. " fire " .. tostring(F.viaFire or 0)
				.. "   below " .. string.format("%.1f", F.below)
				.. "   pile " .. tostring(F.clusterSize)
				.. "   climb " .. tostring(MAX_CLIMB)
				.. "   gap " .. string.format("%.2f", F.gap)
				.. "   parked " .. tostring(F.parked)
				.. "   dry " .. string.format("%.1f", F.dryFor or 0)
				.. "   nudge " .. tostring(F.nudges or 0)
				.. "   sword via " .. F.swordVia
				.. "   saved " .. tostring(F.saved or "-"))
		lbl.err.TextColor3 = F.err ~= "" and Color3.fromRGB(224, 145, 129) or Color3.fromRGB(162, 147, 127)
	end)
end

local function build()
	for _, h in ipairs({ (gethui and gethui()) or nil, game:GetService("CoreGui"), lp:FindFirstChild("PlayerGui") }) do
		if h then
			pcall(function()
				for _, c in ipairs(h:GetChildren()) do
					if c:IsA("ScreenGui") and c.Name == "SoloFarm" then c:Destroy() end
				end
			end)
		end
	end
	local host = (gethui and gethui()) or game:GetService("CoreGui") or lp:FindFirstChild("PlayerGui")
	if not host then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SoloFarm" gui.ResetOnSpawn = false gui.DisplayOrder = 9100 gui.Parent = host
	env.__SOLOFARM_GUI = gui

	local f = Instance.new("Frame")
	f.Size = UDim2.new(0, 352, 0, 160)
	f.Position = UDim2.new(1, -366, 0, 250)
	f.BackgroundColor3 = Color3.fromRGB(11, 11, 14)
	f.BorderSizePixel = 0 f.Parent = gui
	panel = f
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
-- The golden ring. Measured off the live client 2026-08-21 19:3x, which is what
-- he meant both times he asked and what I kept missing:
--   SoloPlay  stroke RGB(201,142,74) thickness 2   <- gold
--   XpBar     stroke RGB(201,142,74) thickness 2   <- gold
--   SoloFarm  stroke RGB(51,41,27)   thickness 1   <- dull brown
--   SoloRec   stroke RGB(51,41,27)   thickness 1   <- dull brown
-- Two of four had it. These two did not.
	local fStroke = Instance.new("UIStroke", f)
	fStroke.Color = Color3.fromRGB(201, 142, 74)
	fStroke.Thickness = 2

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 27)
	bar.BackgroundColor3 = Color3.fromRGB(24, 20, 14)
	bar.BorderSizePixel = 0 bar.Parent = f
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 10)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1 title.Position = UDim2.new(0, 11, 0, 0)
	title.Size = UDim2.new(1, -250, 1, 0) title.Font = Enum.Font.GothamBold
	title.TextSize = 12 title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 179, 71) title.Text = "SOLO FARM" title.Parent = bar

	local function mkBtn(text, x, w, cb)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, w, 0, 19) b.Position = UDim2.new(1, x, 0, 4)
		b.BackgroundColor3 = Color3.fromRGB(201, 142, 74) b.BorderSizePixel = 0
		b.Font = Enum.Font.GothamBold b.TextSize = 10
		b.TextColor3 = Color3.fromRGB(26, 20, 9) b.Text = text b.Parent = bar
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
		b.MouseButton1Click:Connect(function() pcall(cb) end)
		return b
	end

	local btnRun, btnAuto, btnMode
	-- Every one of the three writes to disk the instant it is pressed. See the
	-- settings block at the top for why it cannot wait until round end.
	btnRun = mkBtn(F.on and "STOP" or "START", -60, 52, function()
		F.on = not F.on
		btnRun.Text = F.on and "STOP" or "START"
		F.err = ""
		saveCfg()
		paint()
	end)
	btnAuto = mkBtn(F.auto and "AUTO ON" or "AUTO OFF", -128, 64, function()
		F.auto = not F.auto
		btnAuto.Text = F.auto and "AUTO ON" or "AUTO OFF"
		saveCfg()
		paint()
	end)
	btnMode = mkBtn(F.mode .. (F.mode == "FRAME" and (" " .. F.frames) or ""), -196, 64, function()
		if F.mode == "VIPER" then F.mode = "FRAME" F.frames = 2
		elseif F.frames == 2 then F.frames = 1
		else F.mode = "VIPER" end
		btnMode.Text = F.mode .. (F.mode == "FRAME" and (" " .. F.frames) or "")
		saveCfg()
		paint()
	end)

	local function mkLbl(y, size, col)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1 l.Position = UDim2.new(0, 12, 0, y)
		l.Size = UDim2.new(1, -24, 0, 18) l.Font = Enum.Font.Gotham
		l.TextSize = size l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = col l.TextTruncate = Enum.TextTruncate.AtEnd l.Text = "" l.Parent = f
		return l
	end
	lbl.state = mkLbl(32, 13, Color3.fromRGB(155, 191, 149))
	lbl.who = mkLbl(52, 11, Color3.fromRGB(255, 179, 71))
	lbl.timer = mkLbl(74, 12, Color3.fromRGB(243, 207, 153))
	lbl.stats = mkLbl(96, 11, Color3.fromRGB(239, 230, 216))
	lbl.tgt = mkLbl(116, 11, Color3.fromRGB(200, 190, 175))
	lbl.err = mkLbl(134, 10, Color3.fromRGB(162, 147, 127))

	makeDraggable("SoloFarm", f, bar)
end

pcall(build)

-- ---------------------------------------------------------------- brain

task.spawn(function()
	while alive() do
		RunService.Heartbeat:Wait()
		if not F.on then
			F.phase = "idle"
			task.wait(0.3)
		else
			local ok, e = pcall(function()
				downgrade()

				if not inMatch() then
					F.phase = "waiting to be put in a game"
					task.wait(0.5)
					return
				end

				-- Anti void wins outright. Nothing else moves the character while
				-- it is climbing out, or the two fight and the bot parks under the
				-- map, which is the tug of war the EggWars farm already paid for.
				if F.rescuing then
					task.wait(0.05)
					return
				end

				if not amAlive() then
					F.phase = "dead"
					F.target = "none"
					task.wait(0.5)
					return
				end

				-- Fault 4. The holding pen sits at y 143 and the map at y -24 to
				-- 30. Until the drop happens there is no chest to stand on and no
				-- player worth hitting, so the countdown is spent waiting rather
				-- than hopping around the pen.
				if not onMap() then
					F.phase = "in the pen, waiting for the drop"
					F.target = "none"
					task.wait(0.2)
					return
				end

				local _, dmg = swordNow()
				F.tpAllowed = dmg >= GOOD_ENOUGH

				-- His rule: tier four, get diamond or onyx, THEN teleport to a
				-- man. There is no timer that unlocks it and no round state that
				-- unlocks it - only the sword does.
				if dmg < GOOD_ENOUGH then
					local total, left = countT4()
					if total == 0 then
						-- The map streams in about nine seconds after the round
						-- opens. Waiting here is the whole of fault 4.
						F.phase = "map streaming - waiting for the tier 4 chests"
						F.target = "none"
						task.wait(0.2)
						return
					end
					if left > 0 then
						local cluster = bestChestCluster()
						if cluster then
							local c = { pos = cluster.centre }
							local n = #cluster.members
							F.phase = "T4 pile of " .. n .. " (" .. left .. " of " .. total .. " left)"
							F.target = string.format("centre of %d chests at %.0f,%.0f,%.0f",
								n, c.pos.X, c.pos.Y, c.pos.Z)
							local r = myRoot()
							if r and (c.pos - r.Position).Magnitude > CHEST_REACH - 3 then
								hop(c.pos + Vector3.new(0, 3, 0))
							end
							-- Free damage on the way. His rule bans TELEPORTING to a man
							-- before the sword exists; it does not ban hitting one who is
							-- already standing inside reach. Viper's own round has two
							-- players down by round 00:03 while he is still at chests, so
							-- the loot phase is not meant to be a damage vacuum - ours was
							-- spending ten to twenty seconds dealing nothing at all.
							local rf = myRoot()
							if rf then
								for _, foe in ipairs(living()) do
									if (foe.root.Position - rf.Position).Magnitude <= HIT_RANGE then
										strike(foe.p, true)
										F.swings = (F.swings or 0) + 1
										F.freeSwings = F.freeSwings + 1
										break
									end
								end
							end
							local r2 = myRoot()
							if r2 and (c.pos - r2.Position).Magnitude <= CHEST_REACH then
								-- The whole pile is claimed, not one chest, because the
								-- whole pile is inside the pickup radius from here.
								for _, m in ipairs(cluster.members) do
									if not visited[m.inst] then
										visited[m.inst] = true
										F.chests = F.chests + 1
									end
								end
								local t0 = os.clock()
								local opened = false
								while os.clock() - t0 < CHEST_MAX_WAIT do
									if not alive() or not F.on or F.rescuing then break end
									pcall(function()
										opened = cluster.members[1]
											and cluster.members[1].inst:GetAttribute("ChestOpened") == true
									end)
									local _, d2 = swordNow()
									if d2 >= GOOD_ENOUGH then break end
									if opened and os.clock() - t0 >= CHEST_GRACE then break end
									local rr = myRoot()
									if rr then pcall(function() rr.AssemblyLinearVelocity = Vector3.zero end) end
									RunService.Heartbeat:Wait()
								end
								equipSword()
								local _, d3 = swordNow()
								if d3 >= GOOD_ENOUGH then
									F.phase = "got " .. F.sword .. ", hunting"
								end
							end
							return
						end
					end
					-- Every tier four is done and it still is not a diamond. The
					-- teleport stays locked, so this is a stand and swing: hit
					-- whoever comes inside 10.35 studs and nobody gets chased.
					F.phase = "T4 used up, sword " .. F.sword .. " - holding, no tp"
				end

				equipSword()

				-- The ceiling follows the body down and never back up. Set on the
				-- first combat frame of the round, then only lowered.
				-- The ceiling is no longer pinned to my own Y - see strikeSpot for
				-- why that was circular. It is kept only as a display of the last
				-- band lift.
				F.ceiling = combatCeiling

				local foes = living()
				if #foes == 0 then
					F.phase = "waiting for the round"
					F.target = "none"
					task.wait(0.4)
					return
				end
				-- A tier four chest I am already standing on is a free upgrade, and
				-- Viper is visibly still opening chests at round 00:17 on the DUO
				-- video. Costs nothing: no walk, no detour, just do not step over it.
				do
					local rr2 = myRoot()
					if rr2 then
						for _, c in ipairs(rankedChests()) do
							if (c.pos - rr2.Position).Magnitude <= CHEST_REACH then
								visited[c.inst] = true
								F.chests = F.chests + 1
								F.freeChests = F.freeChests + 1
							end
							break
						end
					end
				end

				F.phase = "killing " .. F.mode .. " with " .. F.sword
				if F.mode == "VIPER" then killViper() else killFrame() end
			end)
			if not ok then fail("brain", e) end
		end
	end
end)

-- Auto pickup and round accounting live outside the main loop, because that
-- loop only turns while it is already running and so can never start itself.
task.spawn(function()
	local seenJob = ""
	local wasMatch = false
	while alive() do
		task.wait(0.4)
		pcall(function()
			local job = tostring(game.JobId)
			if inMatch() then
				if job ~= seenJob then
					seenJob = job
					visited = {}
					track = {}
					lastSafe = nil
					mapFloor = nil
					SAFE_Y = -60
					VOID_Y = -75
					F.round = F.round + 1
					F.roundStart = os.clock()
					F.kills = 0 F.chests = 0 F.firstKill = 0 F.lastKill = 0 F.queued = false
					F.voidCatches = 0 F.clamped = 0 F.dropped = 0 F.tpAllowed = false
					F.swings = 0 F.skippedNoUnder = 0 F.afkEvents = 0
					combatCeiling = nil F.ceiling = nil F.bandLifts = 0
					MAX_CLIMB = 10
					queuedEarly = false
					F.gaveUp = false F.nudges = 0
					F.earlyQueue = "-"
					F.tps = 0 F.leavers = 0
					F.dmgSeen = 0 F.dmgWindows = 0 F.dmgHits = 0 F.finishes = 0
					F.parked = 0 F.dryFor = 0
					F.hpMin = 100 F.hpTaken = 0 F.hitsTaken = 0
					F.clock = 0 F.clockAtFirstKill = -1 F.freeSwings = 0 F.freeChests = 0
					-- The dry clock has to restart with the round. Without this it
					-- carried the gap between rounds in with it and reported
					-- "SWINGING BUT NOT HURTING ANYBODY for 6.1s" three seconds
					-- into a round that was going fine - a false alarm I wrote.
					dryReset = true
					gapIndex = (gapIndex % #HIT_GAPS) + 1
					HIT_GAP = HIT_GAPS[gapIndex]
					F.gap = HIT_GAP
					F.below = BELOW
					F.tpErrSum = 0 F.tpErrN = 0 F.tpErrMax = 0
					F.viaMobile = 0 F.viaFire = 0
					F.killBase = myKills()
					if F.auto and not F.on then F.on = true F.err = "" saveCfg() end
				end
				wasMatch = true
			else
				if wasMatch then
					closeRound("left match")
					wasMatch = false
					seenJob = ""
				end
			end
		end)
	end
end)

task.spawn(function()
	while alive() do task.wait(0.25) pcall(paint) end
end)

-- The chain he corrected on 2026-08-21 19:0x. The old version fired on "one man
-- left and he is under 50", and he says that is wrong:
--
--   "we last time that lower then 50healht thne start was wron git should while
--    hitting the last player and the lower then 50ehath then detecting am i
--    hitting the player, if then must detectin was am i near the last player
--    now? if was then just start the queue"
--
-- So all four have to be true at once, in his order, and the whole test has to
-- cost less than a tenth of a second - it is four comparisons and one distance,
-- so it runs on the same 0.1s tick as the self check rather than a loop of its
-- own:
--   1  exactly one opponent left
--   2  I am HITTING him - something of his has come off in the last second
--   3  he is under 50 health
--   4  I am NEAR him right now
-- Only then is the queue worth paying for early, because only then is the win
-- actually about to happen.

local function earlyQueueCheck()
	if not F.on or not inMatch() or queuedEarly then return end
	local foes = living()
	if #foes ~= 1 then F.eqWhy = "not the last man (" .. #foes .. " left)" return end
	local t = foes[1]
	local hp = hpOf(t.p)
	if hp == nil then F.eqWhy = "no health reading" return end
	if hp > EARLY_QUEUE_HP then F.eqWhy = string.format("last man still on %.0f hp", hp) return end
	if (os.clock() - (F.lastLandT or 0)) > 1.0 then F.eqWhy = "not landing hits on him" return end
	local r = myRoot()
	if not r then F.eqWhy = "no body" return end
	local d = (t.root.Position - r.Position).Magnitude
	if d > NEAR_LAST then F.eqWhy = string.format("too far from him (%.0f studs)", d) return end

	queuedEarly = true
	F.eqWhy = "fired"
	local fn = env.__SOLOPLAY_QUEUE or env.__SOLOFARM_QUEUE
	local ok, res = false, nil
	if fn then ok, res = pcall(fn, "early: last man, hitting, under 50, near") end
	F.earlyQueue = ok and "fired" or "failed"
	local TAB, NL = string.char(9), string.char(10)
	put("RobloxComm/solo/afk.log",
		os.date("%Y-%m-%d %H:%M:%S") .. TAB
		.. string.format("r%03d", F.round) .. TAB
		.. string.format("%.1fs", F.roundStart > 0 and (os.clock() - F.roundStart) or 0) .. TAB
		.. "early queue" .. TAB
		.. string.format("%s on %.0f hp, %.0f studs away, landing - queue ok=%s res=%s",
			tostring(t.p.Name), hp, d, tostring(ok), tostring(res)) .. NL)
end

-- ---------------------------------------------------------------- self check
--
-- His words, 2026-08-21 09:5x: "dont frogot each 0.1 sec doing chekcing self
-- did it afk or others bug ... i can whle time seeing it was fucking do the
-- afk". Same four questions the EggWars TICK.lua asks every half second, asked
-- five times as often, because a solo round is meant to last twelve seconds and
-- half a second of nothing is already four percent of the round:
--
--   did I move?  did I swing?  did I kill?  did I take a chest?
--
-- All four "no" for AFK_SECS means this client is doing nothing, whatever the
-- panel says. Then it climbs a ladder rather than just logging, because a log
-- that nobody reads at 4am is not a fix.

local AFK_TICK = 0.1
local AFK_SECS = 2.0
local AFK_HARD = 6.0

local A = { pos = nil, swings = 0, kills = 0, chests = 0, since = 0, step = 0, events = 0 }
F.afkEvents = 0
F.afkStep = "-"

local function afkLog(text)
	F.afkEvents = F.afkEvents + 1
	put("RobloxComm/solo/afk.log", string.format("%s\tr%03d\t%.1fs\t%s\t%s\n",
		os.date("%Y-%m-%d %H:%M:%S"), F.round,
		F.roundStart > 0 and (os.clock() - F.roundStart) or 0,
		tostring(F.phase), text))
end

task.spawn(function()
	while alive() do
		task.wait(AFK_TICK)
		pcall(function()
			if not F.on or not inMatch() or F.rescuing then
				A.since = 0 A.step = 0 F.afkStep = "-"
				return
			end
			if not amAlive() then
				A.since = 0 A.step = 0 F.afkStep = "dead"
				return
			end
			local r = myRoot()
			local p = r and r.Position or nil
			if not p then
				A.since = 0 A.step = 0 F.afkStep = "no body"
				return
			end
			-- Standing in the pen before the drop is not AFK, it is the rule.
			if p.Y >= LOBBY_Y then
				A.since = 0 A.step = 0 F.afkStep = "pen"
				A.pos = p
				return
			end
			-- The fifth question, added 2026-08-21 17:2x on his instruction:
			-- "add a thing that was each 0.1 sec chekcing are u killing player".
			--
			-- Moving, swinging and looting are all things the farm can do all
			-- round while achieving nothing, which is exactly what it did before
			-- the facing fix: 544 swings, no damage, no kills. So being busy is
			-- no longer enough. If the farm has a sword, has a target and is
			-- swinging, but nobody has lost health for DRY_SECS, that is its own
			-- kind of AFK and it gets said out loud.
			if F.finishes ~= (A.finishes or 0) or F.dmgSeen ~= (A.dmg or 0) then
				A.lastDmg = os.clock()
			end
			A.finishes = F.finishes
			A.dmg = F.dmgSeen
			pcall(earlyQueueCheck)
			if dryReset then dryReset = false A.lastDmg = os.clock() A.dryTold = nil end
			if A.lastDmg == nil then A.lastDmg = os.clock() end
			F.dryFor = os.clock() - A.lastDmg
			-- His rule, 2026-08-21 18:2x: "make sure it was again 0.1 sec each
			-- killing the player or hitting, if not then just telpting to the near
			-- player then". This is the escape hatch that does not care about
			-- clusters, ceilings, weakest-first or parked-last. If nobody has bled
			-- for NUDGE_DRY seconds and there is a man on the map, go and stand
			-- under the CLOSEST one and swing. Simple beats clever when the clever
			-- version is standing still.
			if F.tpAllowed and F.dryFor > NUDGE_DRY and not F.rescuing then
				local foes = living()
				if #foes > 0 then
					local near, nd = nil, math.huge
					for _, t in ipairs(foes) do
						if t.dist < nd then near, nd = t, t.dist end
					end
					if near then
						local spot = strikeSpot(near.root.Position, swingSeq + 1)
						if not spot then
							-- Even the fallback is not allowed to stand level with a
							-- man, so if under is impossible take the safe floor
							-- directly beneath him.
							spot = Vector3.new(near.root.Position.X, math.max(SAFE_Y, near.root.Position.Y - BELOW), near.root.Position.Z)
						end
						hop(spot, false, near.root.Position)
						strike(near.p, true)
						F.swings = (F.swings or 0) + 1
						F.nudges = (F.nudges or 0) + 1
						A.lastDmg = os.clock() - NUDGE_DRY + 0.4
						afkLog(string.format("nudge: dry %.1fs, went to nearest %s at %.0f studs",
							F.dryFor, near.p.Name, nd))
					end
				end
			end

			-- His other rule in the same message: a last man under 50 health who
			-- is NOT being hit means something is wrong with this round, and
			-- standing there is worse than starting a new one.
			if F.tpAllowed and F.dryFor > GIVEUP_DRY and not F.gaveUp then
				local foes = living()
				if #foes == 1 and (hpOf(foes[1].p) or 100) <= 50 then
					F.gaveUp = true
					local fn = env.__SOLOPLAY_QUEUE or env.__SOLOFARM_QUEUE
					if fn then pcall(fn, "gave up - last man under 50 and nothing landing") end
					afkLog(string.format("GAVE UP: last man %s on %s hp, dry %.1fs, requeued",
						tostring(foes[1].p.Name), tostring(hpOf(foes[1].p)), F.dryFor))
				end
			end

			if F.tpAllowed and (F.swings or 0) > A.swings and F.dryFor > 4 then
				if (A.dryTold or 0) + 5 < os.clock() then
					A.dryTold = os.clock()
					afkLog(string.format(
						"SWINGING BUT NOT HURTING ANYBODY for %.1fs - %d swings, sword %s, target %s",
						F.dryFor, F.swings or 0, tostring(F.sword), tostring(F.target)))
				end
			end

			local busy = false
			if A.pos == nil or (p - A.pos).Magnitude > 0.5 then busy = true end
			if (F.swings or 0) ~= A.swings then busy = true end
			if F.kills ~= A.kills then busy = true end
			if F.chests ~= A.chests then busy = true end
			A.pos = p
			A.swings = F.swings or 0
			A.kills = F.kills
			A.chests = F.chests
			if busy then
				if A.since > 0 then
					afkLog(string.format("recovered after %.1fs at step %d", os.clock() - A.since, A.step))
				end
				A.since = 0 A.step = 0 F.afkStep = "working"
				return
			end
			if A.since == 0 then A.since = os.clock() return end
			local stuckFor = os.clock() - A.since
			if stuckFor < AFK_SECS then
				F.afkStep = string.format("quiet %.1fs", stuckFor)
				return
			end

			-- The ladder. One rung per pass so each one gets a chance to work
			-- before the next is tried, and every rung says what it did.
			A.step = A.step + 1
			if A.step == 1 then
				F.afkStep = "1 re-read sword"
				F.target = "none"
				swordNow()
				equipSword()
				afkLog("step 1 - re-read and re-equipped, sword " .. tostring(F.sword))
			elseif A.step == 2 then
				F.afkStep = "2 go to a tier 4 chest"
				local list = rankedChests()
				if list[1] then
					hop(list[1].pos + Vector3.new(0, 3, 0))
					afkLog(string.format("step 2 - hopped to a T4 chest at %.0f,%.0f,%.0f",
						list[1].pos.X, list[1].pos.Y, list[1].pos.Z))
				else
					afkLog("step 2 - no tier 4 chest left to go to")
				end
			elseif A.step == 3 then
				F.afkStep = "3 go under a target"
				local list = living()
				local best = nil
				table.sort(list, function(a, b) return a.y < b.y end)
				for _, t in ipairs(list) do
					local want = strikeSpot(t.root.Position, swingSeq + 1)
					if want then best = { t = t, want = want } break end
				end
				if best then
					hop(best.want)
					afkLog("step 3 - hopped under " .. best.t.p.Name)
				else
					afkLog("step 3 - nobody has a legal spot under him")
				end
			elseif A.step == 4 then
				F.afkStep = "4 back onto the map"
				local under = groundUnder(p)
				if not under then
					hop(lastSafe or mapSpawn(), true)
					afkLog("step 4 - no floor under me, moved back onto the map")
				else
					afkLog("step 4 - floor is there, so this is not a falling problem")
				end
			else
				F.afkStep = string.format("STUCK %.0fs", stuckFor)
				if stuckFor > AFK_HARD and (stuckFor % 3) < AFK_TICK * 2 then
					afkLog(string.format(
						"STUCK %.1fs  y=%.1f sword=%s(%s) tp=%s foes=%d T4left=%s phase=%s",
						stuckFor, p.Y, tostring(F.sword), tostring(F.swordDmg),
						tostring(F.tpAllowed), #living(), tostring(select(2, countT4())),
						tostring(F.phase)))
				end
			end
		end)
	end
end)

-- ---------------------------------------------------------------- state log
--
-- Two lines a second, one file, so that a round can be debugged from disk
-- afterwards instead of from a panel nobody was looking at. This is what the
-- ten minute watchdog reads.

-- ---------------------------------------------------------------- early queue
--
-- His words, 2026-08-21 17:4x: "while detect the whole round only have 2 player,
-- then it need to start the game auto queue ... becuase the quque will cost over
-- 2-3 sec, as that it while done kill the last player and win was alreayd was
-- ready to join another game ... while detect the last player left near 50
-- health then will auto start the quee".
--
-- So the queue is paid for while the last man is still dying, not after. Two
-- conditions, both his: one living opponent left, and he is at or under 50
-- health. Fires once per round, and it writes down whether the game actually
-- accepted a queue request from inside a live match rather than assuming it did
-- - if canQueue is false mid-round this is a no-op and the log will say so.


-- ---------------------------------------------------------------- 1s tracker
--
-- His words, 2026-08-21 17:3x: "i need to tracking all player data at the each
-- 1 sec, that was detect is there any player alive or not, or i was hitting or
-- the player was on the floor or at the void ... i jsut find out it was afk for
-- 5+ sec and the player was not afking he was moving, i ant unded why that
-- happend".
--
-- One row per player per second, and crucially the REASON the farm did or did
-- not treat him as a target. A stall with a live man walking around is not
-- debuggable from a phase string; it is debuggable from "he was legal and I
-- ignored him" versus "he was above my ceiling".

-- Damage taken, sampled fast enough to catch a hit between two one-second rows.
task.spawn(function()
	local last = nil
	while alive() do
		task.wait(0.2)
		pcall(function()
			if not inMatch() or not F.on then return end
			local hp = hpOf(lp)
			if hp == nil then last = nil return end
			if last and hp < last then
				F.hpTaken = F.hpTaken + (last - hp)
				F.hitsTaken = F.hitsTaken + 1
			end
			if hp < F.hpMin then F.hpMin = hp end
			last = hp
		end)
	end
end)

task.spawn(function()
	local lastSwings = 0
	while alive() do
		task.wait(1)
		pcall(function()
			if not inMatch() then return end
			local r = myRoot()
			local me = r and r.Position or nil
			F.clock = roundClock() or F.clock
			local hitting = (F.swings or 0) > lastSwings
			lastSwings = F.swings or 0
			local TAB = string.char(9)
			local NL = string.char(10)
			local stampNow = os.date("%H:%M:%S")
			local rows = {}
			rows[#rows + 1] = table.concat({
				stampNow, "ME", lp.Name,
				me and string.format("%.1f", me.Y) or "nobody",
				"alive=" .. tostring(amAlive()),
				"hp=" .. tostring(hpOf(lp)),
				"taken=" .. string.format("%.0f", F.hpTaken) .. "/" .. tostring(F.hitsTaken),
				"roundclock=" .. tostring(F.clock),
				"floor=" .. (mapFloor and string.format("%.0f", mapFloor) or "?"),
				"safeY=" .. string.format("%.0f", SAFE_Y),
				"voidY=" .. string.format("%.0f", VOID_Y),
				"ceiling=" .. (combatCeiling and string.format("%.0f", combatCeiling) or "-"),
				"hitting=" .. tostring(hitting),
				"swings=" .. tostring(F.swings or 0),
				"phase=" .. tostring(F.phase),
				"target=" .. tostring(F.target),
			}, TAB)
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= lp then
					local ch = p.Character
					local rr = ch and ch:FindFirstChild("HumanoidRootPart")
					local hp = hpOf(p)
					local aliveAttr = p:GetAttribute("Alive")
					local t = track[p]
					local pos = rr and rr.Position or nil
					local onFloor = "?"
					if pos then onFloor = tostring(groundUnder(pos) ~= nil) end
					local why
					if not rr then
						why = "no body"
					elseif aliveAttr == false or (hp ~= nil and hp <= 0) then
						why = "dead"
					elseif pos.Y >= LOBBY_Y then
						why = "still in the pen"
					elseif pos.Y < VOID_Y then
						why = "under the void line"
					elseif t and t.gone then
						why = "tracker wrote him off: " .. tostring(t.why)
					else
						local spot, reason = strikeSpot(pos, swingSeq)
						why = spot and ("LEGAL" .. (reason and (" (" .. reason .. ")") or "")) or ("no spot: " .. tostring(reason))
					end
					rows[#rows + 1] = table.concat({
						stampNow, "P", p.Name,
						pos and string.format("%.1f", pos.Y) or "-",
						"alive=" .. tostring(aliveAttr),
						"hp=" .. tostring(hp),
						"onfloor=" .. onFloor,
						"invoid=" .. tostring(pos ~= nil and pos.Y < VOID_Y),
						"stillfor=" .. ((t and t.lastMove) and string.format("%.1f", os.clock() - t.lastMove) or "?"),
						"dist=" .. ((pos and me) and string.format("%.0f", (pos - me).Magnitude) or "-"),
						"parked=" .. tostring(t ~= nil and t.lastMove ~= nil and (os.clock() - t.lastMove) >= PARKED_SECS),
						why,
					}, TAB)
				end
			end
			put("RobloxComm/solo/players_1s.log", table.concat(rows, NL) .. NL)
		end)
	end
end)

task.spawn(function()
	local lastLine = ""
	while alive() do
		task.wait(0.5)
		pcall(function()
			if not inMatch() then return end
			local r = myRoot()
			local line = string.format(
				"%s\tr%03d\t%.1f\t%s\ty=%s\tfoes=%d\tsword=%s(%s)\ttp=%s\tT4=%s\tchests=%d\tkills=%d\tswings=%d\tvoid=%d\tafk=%s\tfloor=%s",
				os.date("%H:%M:%S"), F.round,
				F.roundStart > 0 and (os.clock() - F.roundStart) or 0,
				tostring(F.phase),
				r and string.format("%.0f", r.Position.Y) or "none",
				#living(),
				tostring(F.sword), tostring(F.swordDmg), tostring(F.tpAllowed),
				tostring(select(2, countT4())),
				F.chests, F.kills, F.swings or 0, F.voidCatches,
				tostring(F.afkStep),
				mapFloor and string.format("%.0f", mapFloor) or "?")
			if line:sub(10) ~= lastLine then
				lastLine = line:sub(10)
				put("RobloxComm/solo/farm_state.log", line .. "\n")
			end
		end)
	end
end)

-- Poll the account's own kill count rather than waiting for somebody to leave.
task.spawn(function()
	while alive() do
		task.wait(0.25)
		if F.on and inMatch() then pcall(countKill) end
	end
end)

-- Take the kill baseline now, not on the next round change.
pcall(function() F.killBase = myKills() end)
pcall(armGameAutoQueue)

paint()
return "SOLO_FARM up, gen " .. MYGEN .. ", mode " .. F.mode .. ", auto " .. tostring(F.auto)
