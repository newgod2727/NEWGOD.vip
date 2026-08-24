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



local HIT_PLAYER_IDS = { "0f825f49-002e-4b7b-8d8c-24dbb3494845", "93b2718b-2b2a-4859-b36e-fd4614c7f0c9" }
local HIT_ENTITY_IDS = { "61be77c1-2605-42b3-a731-0d5509527598", "f32c9bc1-cb4b-4616-96ac-bddaefd35e92" }

local HIT_RANGE = 10.35

-- HOW FAR WE ARE ALLOWED TO SWING FROM. THIS IS THE THING BEING SEARCHED.
--
-- 2026-08-24 05:39:00, ViperForTheVipe took Jay_skywars from 100 to 0 in 3.4
-- seconds. The sample log has every frame of it. Five hits of exactly 20, and
-- his distance on the frames our health dropped:
--
--   100 -> 80   he was 14.0 studs away
--    80 -> 60   406 studs
--    60 -> 40   65.0 studs
--    40 -> 20   497 studs
--    20 ->  0   16.1 studs
--
-- He is 380 to 500 studs away on almost every one of the 145 samples and only
-- inside 16 on the frames that hurt: he blinks in, hits, blinks out. And 14.0,
-- 12.3 and 16.1 are all PAST the game's own 10.35 refusal line, so the server
-- accepts a melee hit from at least 16 studs. We were capping ourselves at
-- 10.35 - he could reach us and we could not reach him.
--
-- His instruction, 2026-08-24 05:4x: "those was ALT, i dont need to care will i
-- got ban ... i need to do was testing how hack limit to the ghihest".
--
-- So this starts well past what he demonstrated, and every damage window writes
-- its distance and whether it landed into range_test.tsv. The real ceiling comes
-- out of that file, not out of this number.
-- MEASURED, THEN CUT BACK TO WHAT ACTUALLY LANDS.
--
-- 211 damage windows with the gate open to 30 studs, 2026-08-24 05:5x:
--
--   3-5    studs   29 windows   136 swings   359 damage   52% landed
--   6-8    studs  164 windows   630 swings  1947 damage   45% landed
--   9-11   studs    6 windows    18 swings    56 damage   33% landed
--   12-14  studs    3 windows     9 swings     0 damage    0%
--   15-17  studs    2 windows     6 swings     0 damage    0%
--   18-20  studs    3 windows     9 swings     0 damage    0%
--   21-23  studs    4 windows    12 swings     0 damage    0%
--
-- Past eleven studs: 13 windows, 36 swings, zero health taken off anybody. The
-- server enforces the range on us whatever the client does, so reach is not the
-- thing that can be pushed. 12 keeps the 9-11 band that does land and stops
-- throwing swings that provably cannot.
--
-- This also kills what I told him earlier. I read Viper's 14.0, 12.3 and 16.1
-- stud hits off the sample log and called it extra reach. The sampler runs every
-- 0.3 seconds - long enough for him to blink in, hit from close, and blink out
-- between two samples - so that log cannot tell where he struck from, only where
-- he ended up. The claim was not supported by the sample rate.
-- 2026-08-24 06:3x. NINE, NOT TWELVE, AND THE NUMBER IS MEASURED NOT CHOSEN.
--
-- range_test.tsv, 7393 attack windows. Damage landed at every distance from 1
-- to 9. At 10 and beyond it landed exactly nothing - 27 windows, 59 swings,
-- 0 damage, at 10, 11, 12, 13, 15, 18, 20 and 21 studs alike. So the server's
-- real ceiling is 9, and every stud we claimed above that was a lie the farm
-- told itself: it would pin on a foe at 11, stand there swinging, and register
-- as "in range and working" while doing zero.
--
-- The old 12 came from opening HIT_RANGE up on the theory that the client gate
-- of 4.5 * 2.3 = 10.35 was the limit. It is not the limit that matters - the
-- client gate only applies to the game's own melee-controller, and we fire the
-- damage event directly. What matters is what the server accepts, and the
-- answer measured from our own swings is 9.
local STRIKE_RANGE = 9
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
--   "it changes attack target every 0.2 seconds"              -> tested, and 0.4 beat it
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
-- 4.5, WHICH IS VIPER'S OWN NUMBER, BECAUSE 15 CANNOT REACH.
--
-- 2026-08-24 03:1x. He said the killing was too slow and he was right, and it
-- was never the teleport or the detection. Three measurements, one cause:
--
--   kills.tsv, four finishes in a row: 34, 66, 99, 135 swings for 100, 200,
--   300, 400 damage. Every man costs exactly 100 damage and about 33 swings.
--   At 29 damage a hit that is 3.4 landed swings out of 33 - nine in ten do
--   nothing at all.
--
--   a live probe on the client, 14 samples while a man was in front of it:
--   distance 15.1 studs every time, and ZERO of the 14 inside the melee box.
--
--   the game's own melee-constants: MAXIMUM_HIT_RANGE_BLOCKS = 4.5, and
--   melee-controller refuses anything past MAXIMUM_HIT_RANGE_BLOCKS * 2.3 =
--   10.35 studs. Sitting 15 studs under a man is outside his reach, which was
--   the point - but it is outside ours by the same 4.65 studs.
--
-- So the farm was standing in the one place where nobody can hit anybody, and
-- only scored when the target happened to drift down inside 10.35 on his own.
-- That is the 2.6 seconds a kill, and 2.6 x 5 kills is the 14.6 seconds that
-- makes a 27 second round out of Viper's 12.
--
-- 4.5 is what Viper said and what every comment in this file already assumes -
-- "stand 4.5 studs UNDER the target" is written three times above. With
-- BELOW_OFFSET the body sits about 5.0 studs away, inside 10.35 and inside the
-- 12x6x9 box. It also means he can reach us, which is the trade Viper made.
-- 6, his number, 2026-08-24 03:2x: "it should be stand 6 studs underster".
-- Still well inside the game's 10.35 refusal line, and one and a half
-- studs further out of his swing than Viper's 4.5.
local BELOW = 6
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
-- THE SEARCH IS BACK ON, BECAUSE 1.33 IS NOT 1.1 AND THE GAP IS WHY.
--
-- Measured 22:43, seven kills: 1.25 1.29 1.32 1.33 1.35 1.40 1.48. Four hits a
-- man, so three intervals, so the server is booking a hit about every 0.44s.
-- The record's own fastest kills run 0.37s between hits - and 0.37 is not a
-- multiple of 0.08. If the server's real cooldown sits just under 0.40 then
-- firing every 0.08 makes us miss the window and wait a whole extra tick, which
-- is exactly the 0.04 to 0.07 we are losing per hit.
--
-- One value per round, cycled, recorded in ab_test.tsv and now in hitgap.tsv
-- with the REAL interval between health drops. Three rounds and the answer is a
-- number instead of an argument.
-- HIS QUESTION, 2026-08-24 23:2x, and it is the right one: "why he can mkaing
-- it over the atk speed of the sever but we cant? beucase his atk speed was
-- overed the sever alreayd".
--
-- If the server truly held a 0.4s timer per player nobody could beat it, and
-- somebody visibly does. So the thing on the server is almost certainly not a
-- wall-clock gate at all - it is a check that reads a last-hit stamp, and a
-- stamp is only safe if it is written before the next packet is read.
--
-- Everything we have tried so far spaces hits out in TIME: 0.08, then 0.05,
-- 706 landed hits and a median of 0.435s regardless. Spacing is exactly what a
-- stamp check is built to reject. What has never been tried is the opposite -
-- several hits inside ONE FRAME, arriving together, before the stamp from the
-- first one is written back.
--
-- BURSTS cycles per round and lands in ab_test next to the damage, so this is
-- one round per value and then a number instead of a theory. 1 is today's
-- behaviour and is the control.
-- ANSWERED, 2026-08-24 23:3x, and the answer is no.
--
-- Eight rounds at burst 3 against two at burst 1:
--   swings   232 -> 939   (four times as many packets)
--   damage   812 -> 854 to 997   (five to twenty percent)
--   hits inside 0.30s of the previous one: 3% before, 3% after
--   median interval between landed hits: 0.435s before, 0.435s after
--
-- 842 landed hits and the median did not move by a millisecond. Firing several
-- times inside one frame does NOT arrive as one batch - the server books them
-- one after another and the cooldown rejects all but the first, exactly as it
-- does with spaced fire. So the thing on the server really is a time gate, not
-- a stamp race, and no Lua-side firing pattern gets under it.
--
-- Back to 1. Three extra packets per swing that land nothing are pure exposure.
--
-- The cycling itself was also broken, and it is the same trap the memory file
-- already names: SOLO_ENTRY reloads this whole file every round, so every local
-- resets. burstIndex went 1 -> 2 on the first round of every round, so every
-- round ran BURSTS[2] and burst 6 was never once tested. HIT_GAP had the same
-- fault, which is why 842 samples all say gap=0.05. Anything meant to vary ACROSS
-- rounds has to be derived from something that survives a reload - a file, or
-- the JobId - never from a local counter.
local BURSTS = { 1 }
local burstIndex = 1
local BURST = 1
local HIT_GAPS = { 0.05 }
local HIT_GAP = HIT_GAPS[1]
local gapIndex = 1
-- DWELL IS THE VARIABLE NOW, AND HERE IS THE NUMBER THAT MADE IT ONE.
--
-- 2026-08-24. kills.tsv, 912 kills decumulated: 33376 swings produced 113460
-- damage, so 3.40 damage per swing while holding a sword that hits for 29.
-- That is one swing in nine landing. range_test.tsv then rules out the obvious
-- explanation - across 7393 windows the landing rate is flat at about 11% at
-- EVERY distance from 2 to 9 studs. Standing closer does not help. So the
-- misses are not a reach problem, and swinging harder cannot be the answer.
--
-- The game's own constant says why: ReplicatedStorage.TS.health.health-constants
-- carries DAMAGE_COOLDOWN = 0.4. At a 0.08 gap we throw 12.5 swings a second
-- into a window that can only accept one every 0.4, so the ceiling on landing
-- rate is 20% and we measure 11% - a bit over half of what the cooldown alone
-- would allow.
--
-- The suspect is this very number. Dwell 0.2 means we leave a man before his
-- 0.4 cooldown has even expired, and every departure is also a teleport to sit
-- under somebody else. If the swings we throw in the first moments after a
-- teleport are landing on a server that has not seen us arrive yet, then a
-- shorter dwell buys nothing and costs a whole cooldown window.
--
-- So it cycles, one value per round, the same way HIT_GAP did, and the answer
-- lands in dwell_test.tsv instead of in an argument. 0.2 is Viper's own number
-- and stays in the set so it has to win on the table rather than on authority.
--
-- Nothing else may move while this runs. HIT_GAP is parked at 0.08 and BELOW at
-- 6 for exactly that reason - two variables at once produce a table nobody can
-- read. The set lives on F rather than in two new top-level locals because this
-- file sits on Luau's 200 local ceiling and one more would stop it compiling.
local VIPER_DWELL = 0.4

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
-- His ceiling for a whole pile, not for one chest: "i really cant accpt more
-- then 0.5 sec". The per-chest slice is whatever is left of it divided by the
-- chests still to go, never under 0.06s so a slow round trip still has a chance.
-- THE SERVER TAKES 275 TO 476 MILLISECONDS TO ANSWER ONE openChest.
--
-- Measured 2026-08-24 21:14 in chestspeed.tsv, thirteen consecutive single
-- chest rows: 460, 321, 476, 310, 462, 297, 456, 450, 318, 453, 455, 275, 459.
-- That is one network round trip and it cannot be argued with.
--
-- This budget is for the WHOLE pile and the per chest slice is this divided by
-- how many are left, so at 0.45 a pile of five gave each chest 90ms - a fifth
-- of what the answer costs. Every one timed out as "no reply", five failures
-- in a row handed the job to Vape's ChestSteal at about half a second a chest,
-- and that is where the six seconds he saw went. chestowner.tsv: VAPE 5 0/5.
--
-- 21:14 read wrong the first time and it cost him a round of standing still.
-- Those 450 to 476ms rows are the budget running out, not the server answering.
-- The rows UNDER the budget are the real answers: 275, 297, 310, 318, 321. So a
-- reply is about three tenths of a second and 0.6 is already generous.
--
-- A CEILING, NOT A FLOOR. The slice below was written max(0.55, left/remaining)
-- and a pile of ONE chest therefore claimed the entire pile budget - 3.0
-- seconds standing on a single chest, which is exactly what he saw: "stading on
-- some chest over 1 sec+, then 2 sec then 3 sec". chestspeed.tsv 21:20:34 to
-- 21:21:29, six single-chest rows: 3014, 1812, 3029, 3012, 1900, 3006.
local CHEST_CLUSTER_BUDGET = 1.8
local CHEST_GRACE = 0.35

local SWORD = { BronzeSword = 18, IronSword = 23, GoldSword = 25, DiamondSword = 29, OnyxSword = 32 }
local GOOD_ENOUGH = 29

-- THE GATE IS THE EXPERIMENT NOW.
--
-- His rule was tier four first, diamond or onyx, then teleport to a man. It was
-- never tested against the alternative, and 2026-08-24 the record says the price
-- is enormous. Across 182,801 live-round frames a living player is inside 9
-- studs only 54.6% of the time; 39.8% of the time the nearest one is more than
-- 60 studs away, with almost nothing in between - we are either on top of
-- somebody or across the map. First contact lands at 7.8 seconds. A 23.4 second
-- round holds 58 damage windows and we deal 629 damage against a 1,696 ceiling.
--
-- What the gate buys, measured over 2,267 rounds: diamond rounds deal 632
-- damage, onyx rounds 644. Twelve damage, for the seven and a half seconds it
-- costs to go and find the sword.
--
-- So half the rounds now run open: fight from the first second with whatever is
-- in hand, and only go to the chests when nobody is left alive to hit. Bronze is
-- 18 a swing against diamond's 29, so it needs six landed hits instead of four -
-- the question the A/B answers is whether starting 7.8 seconds earlier is worth
-- more than the bigger sword. Arm chosen by JobId so a rejoin cannot reset it
-- and both bots in one server pick the same arm.
local GATE_OPEN = false
local MULTI_SWORD = true

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
	on = false, auto = true, mode = "VIPER", frames = 2, byHand = false,
	phase = "idle", round = 0, roundStart = 0, firstKill = 0, lastKill = 0,
	-- MEASURED FROM THE WRONG ZERO UNTIL NOW.
	--
	-- 2026-08-24, his correction: "viper bot was using less then 1 sec then at
	-- the after done the round countdown, then got to tier 4 then just got the
	-- blakc or dimond sowrd". His clock starts when the countdown ENDS. Ours
	-- started when the JobId changed, which is when we joined the server - so
	-- our 7.8 second "first contact" has the whole pre-round countdown baked
	-- into it and cannot be compared with his one second at all.
	--
	-- dropAt is the moment the body actually leaves the holding pen. Everything
	-- that is meant to race him is timed from there.
	dropAt = 0, firstChestAt = 0, firstKillFromDrop = 0,
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
	hpMin = 100, hpTaken = 0, hitsTaken = 0, clock = 0, below = 6, clusterSize = 0, clockAtFirstKill = -1, freeSwings = 0, freeChests = 0,
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

-- ONE FILE PER CLIENT. THE PANELS ARE INDEPENDENT AGAIN.
--
-- 2026-08-24, his correction: "if i was at one cleint press the auto on itno
-- off, make it stop it should stop this cleint and not sotp all client beuasd
-- that will ruin the whole plan".
--
-- I built the opposite this morning and it was my misreading, not his. Four
-- clients shared one settings file, so STOP on one panel stopped the fleet -
-- which makes it impossible to park one account for a test while the other
-- three keep farming, and that is exactly the plan he needs.
--
-- So the settings are per account now. The old shared file is still read ONCE,
-- the first time this account runs, so nothing he had set is lost - after that
-- it is never touched again.
local CFG_SHARED = "RobloxComm/solo/solo_farm_cfg.json"
local CFG_FILE = "RobloxComm/solo/cfg_" .. tostring(lp.Name) .. ".json"
-- byHand travels with the rest of the settings on purpose.
--
-- STOP has to mean stop on ALL FOUR clients, not just the panel he touched. If
-- this stayed local, the other three would sync on=false from the file, see
-- their own byHand still false, and their auto-restart would put them straight
-- back to work - which is the same complaint in a different shape.
local KEEP = { "mode", "frames", "auto", "on", "byHand" }

-- A save that fails silently is a save that puts FRAME 1 back to VIPER on the
-- next round without telling anybody, which is the exact complaint. It reports
-- on the panel either way.
local function saveCfg()
	local ok, e = pcall(function()
		if not isfolder("RobloxComm") then makefolder("RobloxComm") end
		if not isfolder("RobloxComm/solo") then makefolder("RobloxComm/solo") end
		local t = {}
		for _, k in ipairs(KEEP) do t[k] = F[k] end
		local raw = game:GetService("HttpService"):JSONEncode(t)
		writefile(CFG_FILE, raw)
		-- Remember our own write so the follower below does not read it back and
		-- announce it as somebody else's change.
		F.cfgSeen = raw
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
-- Seed from the old shared file the first time only, then own our own.
pcall(function()
	if not isfile(CFG_FILE) and isfile(CFG_SHARED) then
		writefile(CFG_FILE, readfile(CFG_SHARED))
	end
end)
loadCfg()
pcall(function() if isfile(CFG_FILE) then F.cfgSeen = readfile(CFG_FILE) end end)

-- ONE PANEL, FOUR CLIENTS. THIS IS THE SYNC HE WAS MISSING.
--
-- 2026-08-24, his words: the script "was only effect to one cline tonly to that
-- i clcikd cleint and not happend on others client alos". He is right and the
-- cause is one line: loadCfg() is called once, above, and never again. All four
-- clients already share ONE settings file, and every button press already writes
-- it the instant it is pressed - but the other three never look at it again, so
-- pressing STOP on one panel stopped one bot and left three farming.
--
-- So each client now follows the file. It compares the RAW TEXT rather than the
-- decoded values, which is what makes it cheap enough to do every second and
-- also what stops a client reacting to its own save.
--
-- It applies and does NOT save. If every follower wrote back, four clients would
-- take turns rewriting the same file forever.
local function syncCfg()
	pcall(function()
		if not isfile(CFG_FILE) then return end
		local raw = readfile(CFG_FILE)
		if raw == F.cfgSeen then return end
		F.cfgSeen = raw
		local t = game:GetService("HttpService"):JSONDecode(raw)
		if type(t) ~= "table" then return end
		local changed = {}
		for _, k in ipairs(KEEP) do
			if t[k] ~= nil and type(t[k]) == type(F[k]) and F[k] ~= t[k] then
				changed[#changed + 1] = k .. " " .. tostring(F[k]) .. " to " .. tostring(t[k])
				F[k] = t[k]
			end
		end
		if F.mode ~= "VIPER" and F.mode ~= "FRAME" then F.mode = "VIPER" end
		if F.frames ~= 1 and F.frames ~= 2 then F.frames = 2 end
		if #changed > 0 then
			F.synced = os.date("%H:%M:%S")
			-- Keep the three labels honest. This adds no button and moves nothing;
			-- it only stops a panel claiming START while the bot is running.
			if type(F.refreshBtns) == "function" then pcall(F.refreshBtns) end
			pcall(function()
				appendfile("RobloxComm/solo/cfg_sync.log", os.date("%Y-%m-%d %H:%M:%S")
					.. "  " .. tostring(game:GetService("Players").LocalPlayer.Name)
					.. "  followed the panel: " .. table.concat(changed, ", ") .. string.char(10))
			end)
		end
	end)
end
env.__SOLOFARM_SYNC = syncCfg

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

-- The rolling half of put, for the three files that grow without end.
--
-- Measured 2026-08-22 14:2x on the desktop: RobloxComm was 515 MB in 8767
-- files, and the top of the list was players_1s.log at 79.2 MB, the game script
-- dump at 78.5 MB, the workspace tree dump at 78.3 MB and solo_boot.log at
-- 18.7 MB. Most of that was the duplicate loading - twenty six writers instead
-- of one - but a per second per player log has no natural end even with one
-- writer, and a log too big to open is not a log.
--
-- Keeps the newest CAP bytes and drops the rest. The tsv tables are NOT rolled;
-- those are the measurement history and they stay whole.
-- NEVER READ THE LOG TO FIND OUT HOW BIG IT IS.
--
-- The first cut of this did exactly that, and it cost a measured 3302 ms frame
-- and dropped the client to 1 fps: the file it asked about was players_1s.log,
-- which was 79 MB. One readfile, one frame, one unplayable client.
--
-- So the size is counted as it is written, and the recent window is kept in
-- memory rather than re-read off disk. Rolling is then a single writefile of a
-- few hundred kilobytes with no read at all.
--
-- The two files that use this are NEW names. The old players_1s.log and
-- farm_state.log are left exactly where they are - 79 MB and 11.6 MB of his
-- measurements, and deleting them is his call, not mine.
local ROLL_CAP = 4000000
local ROLL_KEEP = 500000
local rollState = {}
local function putRoll(file, text)
	pcall(function()
		if not isfolder("RobloxComm") then makefolder("RobloxComm") end
		if not isfolder("RobloxComm/solo") then makefolder("RobloxComm/solo") end
		local st = rollState[file]
		if not st then
			st = { buf = {}, bufBytes = 0, disk = 0 }
			rollState[file] = st
			writefile(file, "-- opened " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
		end
		appendfile(file, text)
		st.disk = st.disk + #text
		st.buf[#st.buf + 1] = text
		st.bufBytes = st.bufBytes + #text
		while st.bufBytes > ROLL_KEEP and #st.buf > 1 do
			st.bufBytes = st.bufBytes - #st.buf[1]
			table.remove(st.buf, 1)
		end
		if st.disk > ROLL_CAP then
			writefile(file, "-- rolled at " .. os.date("%Y-%m-%d %H:%M:%S")
				.. ", keeping the last " .. st.bufBytes .. " bytes\n" .. table.concat(st.buf))
			st.disk = st.bufBytes
		end
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
	-- The floor clamp is off during a free for all. His words, 2026-08-24 04:1x:
	-- "whitelist was also mean off the anti-fall that thing" - the whole point of
	-- that phase is to go INTO the void, and this clamp is the thing that has been
	-- making that impossible.
	do
		local tm = env.__SOLOTEAM
		if goal.Y < SAFE_Y and not (tm and tm.freeForAll) then
			goal = Vector3.new(goal.X, SAFE_Y, goal.Z)
			F.clamped = F.clamped + 1
		end
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
-- BURY THE BODY
--
-- His instruction, 2026-08-24: "we need to mkae our body not abel to hit also
-- bro". Measured the same day, twice, and both halves matter.
--
-- One: phase.tsv caught the rival account eight samples in a row INSIDE Dirt, Stone and
-- SmoothStone, Y minus 26 down to minus 44.6. He does not stand under people,
-- he stands inside the island.
--
-- Two: a body written into the middle of a solid 3x3x3 block and re-asserted
-- every Heartbeat sat there six seconds, drifted 0.52 studs, was never pushed
-- out, never lost health, never got kicked. No Phase module was needed - this
-- file already writes CFrame every frame, which is exactly Vape's CFrame mode.
--
-- What it buys is not damage, it is not being interrupted. A round holds 58
-- damage windows of 0.4s; we opened 47 and landed 24. The missing half goes on
-- being knocked around and walking back. A body nobody can reach keeps its spot,
-- and a body that keeps its spot spends every window swinging.
--
-- The block has to be reachable from the target - centre inside STRIKE_RANGE -
-- or burying would trade the beating for a miss, which is the same loss.

local BURY = true
local BURY_BOX = 20
local buryParams = nil

local function buriedSpot(want, tp)
	if not BURY then return nil end
	if not buryParams then
		local made = pcall(function()
			buryParams = OverlapParams.new()
			buryParams.FilterType = Enum.RaycastFilterType.Exclude
			buryParams.MaxParts = 24
		end)
		if not made or not buryParams then return nil end
	end
	local skip = {}
	for _, pp in ipairs(Players:GetPlayers()) do
		if pp.Character then skip[#skip + 1] = pp.Character end
	end
	buryParams.FilterDescendantsInstances = skip
	local ok, parts = pcall(function()
		return workspace:GetPartBoundsInBox(CFrame.new(want),
			Vector3.new(BURY_BOX, BURY_BOX, BURY_BOX), buryParams)
	end)
	if not ok or type(parts) ~= "table" then return nil end
	-- Never aim at part.Position. A 3x3x3 block and a 200x1x200 island floor both
	-- come back from the same query, and the floor's CENTRE can be two hundred
	-- studs away while the slab itself is directly under our feet. Measured
	-- 2026-08-24: four solid parts around us, every one of them rejected on
	-- centre distance, so nothing was ever buried. Aim at the point INSIDE the
	-- part nearest to where we wanted to stand instead, pulled in by a margin so
	-- the body is in the material and not resting on its skin.
	local best, bestD = nil, nil
	for _, part in ipairs(parts) do
		local solid = false
		pcall(function()
			solid = part.CanCollide == true
				and part.Size.X >= 1.5 and part.Size.Y >= 1.5 and part.Size.Z >= 1.5
		end)
		-- A living body is not cover. The character filter only removes Players,
		-- and this map also carries BotBodyHitbox parts and loose UpperTorso
		-- parts that pass every other test - measured 2026-08-24, fourteen of
		-- them inside one 14 stud box. Burying inside a person would put us in
		-- his lap with no rock around us at all.
		if solid then
			local person = false
			pcall(function()
				local m = part:FindFirstAncestorOfClass("Model")
				person = (m ~= nil and m:FindFirstChildOfClass("Humanoid") ~= nil)
					or tostring(part.Name):find("Hitbox") ~= nil
			end)
			if person then solid = false end
		end
		if solid then
			local c = nil
			pcall(function()
				local h = part.Size * 0.5
				local rel = part.CFrame:PointToObjectSpace(want)
				local mx = math.min(0.6, h.X * 0.4)
				local my = math.min(0.6, h.Y * 0.4)
				local mz = math.min(0.6, h.Z * 0.4)
				c = part.CFrame:PointToWorldSpace(Vector3.new(
					math.clamp(rel.X, -h.X + mx, h.X - mx),
					math.clamp(rel.Y, -h.Y + my, h.Y - my),
					math.clamp(rel.Z, -h.Z + mz, h.Z - mz)))
			end)
			if c and (c - tp).Magnitude <= STRIKE_RANGE and c.Y >= SAFE_Y and c.Y <= tp.Y then
				local d = (c - want).Magnitude
				if not bestD or d < bestD then best, bestD = c, d end
			end
		end
	end
	return best
end

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
	local air = Vector3.new(tp.X + off, y, tp.Z - off)
	local rock = buriedSpot(air, tp)
	if rock then
		F.buriedFrames = (F.buriedFrames or 0) + 1
		return rock, why, true
	end
	return air, why, false
end

-- ---------------------------------------------------------------- anti void

task.spawn(function()
	while alive() do
		RunService.Heartbeat:Wait()
		if inMatch() then
			pcall(function()
				local r = myRoot()
				if not r or not r.Parent then return end
				-- THE ONE THE DICE PICKED IS THE ONE THAT COMES BACK.
				--
				-- Every bot dives, which is what he asked for. What separates them is
				-- this catcher: it is switched off for the ones the dice did not pick,
				-- so they keep falling and die, and left ON for the one it did, so that
				-- one gets pulled back out and takes the round. That is the 1 in n.
				--
				-- A brother can still finish the picked one on the way down - Killaura
				-- is on for everybody during the drop - which is the other way he said
				-- it can end.
				local tm = env.__SOLOTEAM
				if tm and tm.freeForAll and not tm.winner then return end
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
-- flamework() has to be declared ABOVE melee(), not below it. It used to sit 48
-- lines further down, so inside melee() the name was not a local yet and Luau
-- compiled it as a global lookup - nil at run time, the require threw, the pcall
-- ate it, meleeCache stayed nil, and mc.strikeMobile was never once reachable.
-- Every swing this farm has ever thrown fell through to the raw event fallback.
local flame
local function flamework()
	if flame then return flame end
	pcall(function()
		flame = require(ReplicatedStorage.rbxts_include.node_modules["@flamework"].core.out)
	end)
	return flame
end

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

-- FIRE EVERY CHANNEL, NOT THE FIRST ONE THAT ANSWERS.
--
-- His idea, 2026-08-24: "we can getting all swoard then just using 5 remote to
-- kill". The sword half does not work and he already knew why - Killaura proved
-- swapping the held item changes nothing, because the server reads whatever we
-- are holding rather than taking it as an argument. The remote half is real and
-- we were not doing it.
--
-- This place has four attack events, two for players and two for entities:
--   0f825f49-002e-4b7b-8d8c-24dbb3494845   player
--   93b2718b-2b2a-4859-b36e-fd4614c7f0c9   player
--   61be77c1-2605-42b3-a731-0d5509527598   entity
--   f32c9bc1-cb4b-4616-96ac-bddaefd35e92   entity
-- plus the controller's own strikeMobile, which runs the game's raycast and box
-- test and sends whatever the server is really listening for.
--
-- The old code returned on the first one that existed, so exactly one of them
-- ever ran. If the server keeps its last-hit time per entry point rather than
-- per attacker, firing all of them is more than one hit inside the window - and
-- if it does not, this costs nothing but packets. Either way it is measurable,
-- which quoting a cooldown at him is not.
-- HIS FIVE SWORDS.
--
-- 2026-08-24: "if we haev 5 sword at our package". Swapping the held sword the
-- normal way is dead and he already proved it with Killaura - but the normal way
-- is a slot change with an animation, and this game does not need one. The
-- server is TOLD what we hold, by one event:
--
--   8dd94a0e-0dd9-409c-8847-de1054173265   here is my held item
--
-- The potion code in this same file already uses it: declare the potion, use it,
-- declare the sword again, and the sword never leaves our hand on screen. So a
-- sword can be declared and struck with, then the next one declared and struck
-- with, inside the same frame. If the server keeps its last-hit time per weapon
-- rather than per attacker, five swords in the bag are five separate windows.
-- If it keeps it per attacker, this costs packets and nothing else - and either
-- way it is a number instead of an opinion.
--
-- Forward declared here because it needs hotbar(), which is defined further
-- down. Calling a local before its declaration line is how strikeMobile stayed
-- dead for this farm's entire life.
local cycleStrike

local function strike(thing, isPlayer)
	local fired = 0
	if isPlayer and cycleStrike and cycleStrike(thing) then return true end
	if isPlayer then
		local mc = melee()
		if mc and mc.strikeMobile then
			if pcall(function() mc:strikeMobile() end) then
				F.viaMobile = (F.viaMobile or 0) + 1
				fired = fired + 1
			end
		end
	end
	local ev = events()
	if not ev then
		if fired == 0 then fail("strike", "cannot reach the events table") end
		F.hitId = "mobile only"
		return fired > 0
	end
	for _, id in ipairs(isPlayer and HIT_PLAYER_IDS or HIT_ENTITY_IDS) do
		local e = ev[id]
		if e and e.fire then
			if pcall(function() e:fire(thing) end) then
				F.viaFire = (F.viaFire or 0) + 1
				fired = fired + 1
			end
		end
	end
	F.hitId = string.format("%d channels", fired)
	F.channels = fired
	if fired == 0 then
		fail("strike", "no damage event in this place")
		return false
	end
	return true
end

-- ---------------------------------------------------------------- flamework


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
-- The queue id is spelled out, always. See the long note in SOLO_PLAY: the
-- game's own joinQueue falls back to EggWarsQuads when nobody names a queue,
-- and joinQueueIn names nothing. That is how a solo farm ended up in place
-- 8951451142 at 14:47.
-- No event is ever fired by name here. Its id is generated per place - the
-- match place and the lobby carry two different strings for the same event -
-- so the controller, resolved by reflection, is the only safe caller. See the
-- long note in SOLO_PLAY.
local function queueNow()
	if BANNED_QUEUE[QUEUE_ID] then return false end
	local mm = matchmaking()
	if not mm then F.queued = false return false end
	local q, can = false, false
	pcall(function() q = mm:isInQueue() end)
	pcall(function() can = mm:canQueue() end)
	if q then F.queued = true return true end
	if not can then return false end
	armGameAutoQueue()
	local ok = pcall(function() mm:joinQueue(QUEUE_ID) end)
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


-- ------------------------------------------------------------ opening chests
--
-- His line, 2026-08-24: "na that was suck we need to fix tha tproblme, inot 0
-- sec delay ... i really cant accpt more then 0.5 sec".
--
-- Until now this file has never opened a chest. There were zero calls to
-- openChest in it. What it did was walk to a pile, stand inside CHEST_REACH and
-- wait up to CHEST_MAX_WAIT = 1.4 seconds for Vape's ChestSteal to do the work.
-- chesttime.txt caught the rate that produces: four chests between 15:50:21 and
-- 15:50:23, about half a second each, so sixteen tier 4 chests came to roughly
-- eight seconds - which is the 7.8 second first contact almost exactly.
--
-- The game's own path is three calls and no Vape, and CHEST_CLAIM.lua has been
-- running it by hand for days:
--   jg9:openChest(chest)              ask
--   Events 263ab5f8 comes back        the contents
--   jg9:updateChest(nil, type, -n)    take each line
--   jg9:closeChest()                  let go so the next one can open
--
-- The server keeps one chest open per player, so this is strictly one at a time
-- and the only real cost is the round trip. Nothing is claimed on a timeout: the
-- caller still reads ChestOpened afterwards, so a chest that did not really open
-- is not written off.

local CHEST_REPLY = "263ab5f8-5ee3-442f-9533-2a1274c10537"
local chestInbox = {}
local chestConn

local function chestListen()
	if chestConn then return end
	pcall(function()
		local ev = ReplicatedStorage:FindFirstChild(CHEST_REPLY, true)
		if ev and ev.OnClientEvent then
			chestConn = ev.OnClientEvent:Connect(function(chest, contents)
				chestInbox[chest] = (type(contents) == "table") and contents or {}
			end)
		end
	end)
end

local ccCache
local function chestCtl()
	if ccCache then return ccCache end
	pcall(function()
		local mod = flamework()
		ccCache = mod.Flamework.resolveDependency("jg9")
	end)
	if ccCache then return ccCache end
	pcall(function()
		local mod = flamework()
		local ps = lp:WaitForChild("PlayerScripts", 10)
		local cls = require(ps.TS.controllers["chest-controller"])
		local target = cls
		if type(cls) == "table" then
			for _, v in pairs(cls) do
				if type(v) == "table" and mod.Reflect.getMetadata(v, "identifier") then target = v break end
			end
		end
		ccCache = mod.Flamework.resolveDependency(mod.Reflect.getMetadata(target, "identifier"))
	end)
	return ccCache
end


-- WHO OWNS THE CHEST SLOT.
--
-- His question, 2026-08-24: does Vape cap us, or do we sit above Vape - because
-- if Vape wins, our 0 delay and every setting is ruined, and if ours wins he
-- wants Vape left there as an "at least" for when ours breaks.
--
-- Neither sits above the other. Both are just this client talking to the same
-- server, so they collide wherever the server has ONE of something. The chest is
-- exactly that: one chest open per player. Vape's ChestSteal calling openChest
-- while we are waiting on our own openChest closes ours, our reply never
-- arrives, and we burn the whole budget for nothing - the fast path would be
-- slower than the old one.
--
-- So the chest step is ours and ChestSteal is the safety net, not a peer. It is
-- switched off while our opener is working and switched back on after five
-- straight failures, which is what a dead jg9 or a renamed reply event looks
-- like from here. Every flip is written down.

local chestFails = 0
local stealState = nil

local function vapeModule(name)
	local m
	pcall(function()
		if type(shared) == "table" and type(shared.vape) == "table" then
			m = shared.vape.Modules and shared.vape.Modules[name]
		end
	end)
	return (type(m) == "table" and m.Toggle) and m or nil
end

local function setChestSteal(on)
	if stealState == on then return end
	local m = vapeModule("ChestSteal")
	if not m then return end
	if (m.Enabled == true) ~= on then
		if not pcall(function() m:Toggle() end) then return end
	end
	stealState = on
	F.chestOwner = on and "vape (ours failed)" or "ours"
	pcall(function()
		put("RobloxComm/solo/chestowner.tsv",
			os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
			.. tostring(game.JobId):sub(1, 8) .. string.char(9)
			.. (on and "VAPE" or "OURS") .. string.char(9)
			.. tostring(chestFails) .. string.char(9)
			.. tostring(F.chestOk or 0) .. "/" .. tostring(F.chestOpens or 0)
			.. string.char(10))
	end)
end

local function takeChest(inst, budget)
	local cc = chestCtl()
	if not cc then return false, "no chest controller" end
	chestListen()
	chestInbox[inst] = nil
	if not pcall(function() cc:openChest(inst) end) then return false, "openChest threw" end
	local t0 = os.clock()
	local contents
	while os.clock() - t0 < (budget or 0.6) do
		contents = chestInbox[inst]
		if contents then break end
		RunService.Heartbeat:Wait()
	end
	if not contents then
		pcall(function() cc:closeChest() end)
		-- WHY DID IT NOT ANSWER. 21:26 measured 1 success in 8: the one that came
		-- back took 98ms and every failure sat out the full 0.6s ceiling, so these
		-- are not slow replies, they are NO replies - the server refused. Distance
		-- is the first suspect because the farm opens a whole pile from its centre
		-- and a pile spreads 12 to 25 studs. One row per refusal, with the numbers
		-- that separate "too far" from "already open" from "not lootable".
		pcall(function()
			local r = myRoot()
			local d = -1
			local pos = nil
			pcall(function() pos = inst:IsA("BasePart") and inst.Position or inst:GetPivot().Position end)
			if r and pos then d = (pos - r.Position).Magnitude end
			local opened = "?"
			pcall(function() opened = tostring(inst:GetAttribute("ChestOpened")) end)
			put("RobloxComm/solo/chestfail.tsv",
				os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
				.. tostring(game.JobId):sub(1, 8) .. string.char(9)
				.. tostring(inst.Name) .. string.char(9)
				.. string.format("dist=%.1f", d) .. string.char(9)
				.. "opened=" .. opened .. string.char(9)
				.. string.format("waited=%.0fms", (os.clock() - t0) * 1000) .. string.char(10))
		end)
		return false, "no reply"
	end
	pcall(function()
		local r = myRoot()
		local pos = nil
		pcall(function() pos = inst:IsA("BasePart") and inst.Position or inst:GetPivot().Position end)
		if r and pos then
			put("RobloxComm/solo/chestok.tsv",
				os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
				.. tostring(game.JobId):sub(1, 8) .. string.char(9)
				.. string.format("dist=%.1f", (pos - r.Position).Magnitude) .. string.char(9)
				.. string.format("ms=%.0f", (os.clock() - t0) * 1000) .. string.char(10))
		end
	end)
	local took = 0
	-- WHAT CAME OUT IS KNOWN HERE, SO SAY SO HERE.
	--
	-- His line, 2026-08-24 21:2x: "i can see voer open the chest it have over
	-- 0.5 sec delay afk, that was wrong it should done detect if got the sword
	-- then jsut instead go to start killing player". The delay was real and it
	-- was structural: the loop asked swordNow() afterwards, which re-reads the
	-- hotbar controller, and the hotbar has not caught up in the same frame the
	-- item was claimed. The chest reply already names every item, so the sword
	-- is known the moment it is taken - no second lookup, no waiting a tick.
	local best = 0
	local bestName = nil
	for _, item in pairs(contents) do
		local ty = item.Type or item.ItemType
		local qty = tonumber(item.Quantity) or 1
		if ty then
			pcall(function() cc:updateChest(nil, ty, -qty) end)
			took = took + qty
			local d = SWORD[tostring(ty)]
			if d and d > best then best = d end
			if d then bestName = tostring(ty) end
		end
	end
	pcall(function() cc:closeChest() end)
	return true, took, best, bestName
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

local HOLD_EVENT = "8dd94a0e-0dd9-409c-8847-de1054173265"
local CYCLE_GAP = 0.30
local lastCycle = 0

-- BY TIER, NOT BY COPY.
--
-- His correction, 2026-08-24: "it only count the tier of the sowr di have".
-- Two DiamondSwords in the bag are one weapon as far as the server is
-- concerned, so declaring DiamondSword twice would just be a wasted packet on
-- a door that is already on cooldown. At most five entries come back - bronze,
-- iron, gold, diamond, onyx - best first.
local function swordsCarried()
	local seen, out = {}, {}
	local hb = hotbar()
	if not hb then return out end
	pcall(function()
		for _, it in ipairs(hb:getHotbarItems() or {}) do
			local nm = tostring(it.Type or it.Name or "")
			if SWORD[nm] and not seen[nm] and (tonumber(it.Quantity) or 1) > 0 then
				seen[nm] = true
				out[#out + 1] = nm
			end
		end
	end)
	table.sort(out, function(x, y) return (SWORD[x] or 0) > (SWORD[y] or 0) end)
	return out
end

-- DOES THE SERVER BELIEVE THE DECLARATION, OR DOES IT CHECK THE BAG?
--
-- The whole five-sword idea rests on one unmeasured assumption: that firing the
-- hold event with a sword name is enough for the server to book that hit on
-- that weapon's own cooldown. If it verifies we actually own it, the idea is
-- dead and no amount of chest opening helps, because measured 22:5x the hotbar
-- holds exactly ONE sword - swordsCarried reads 1, Backpack is empty, one held
-- tool. The sword we fight with came from Vape's ChestSteal, not from our own
-- openChest, which is why the chest reply never named it either.
--
-- So test it once a round, on a live target, and write the answer down:
-- declare BronzeSword (18 damage) while holding Diamond (29) or Onyx (32), fire
-- one hit, read what actually came off him, then put the real sword back.
--   drop 18        -> the server believes the declaration. Five swords is on.
--   drop 29 or 32  -> the server uses what we really hold. Declaring is a no-op.
--   drop 0         -> the server refused the hit outright. Do not do this again.
local declareTested = ""
local function declareProbe(who, ev, hold, realName)
	if declareTested == tostring(game.JobId) then return end
	if not (who and ev and hold and hold.fire) then return end
	-- hpOf is declared 550 lines BELOW this function, so calling it here is a nil
	-- global. Read the attribute directly, which is all hpOf does anyway.
	local hp0 = nil
	pcall(function() hp0 = tonumber(who:GetAttribute("Health")) end)
	if not hp0 or hp0 <= 40 then return end
	declareTested = tostring(game.JobId)
	pcall(function() hold:fire("BronzeSword") end)
	for _, id in ipairs(HIT_PLAYER_IDS) do
		local e = ev[id]
		if e and e.fire then pcall(function() e:fire(who) end) end
	end
	local t0 = os.clock()
	local hp1 = hp0
	while os.clock() - t0 < 0.6 do
		RunService.Heartbeat:Wait()
		local h = nil
		pcall(function() h = tonumber(who:GetAttribute("Health")) end)
		if h and h < hp0 then hp1 = h break end
	end
	pcall(function() hold:fire(realName) end)
	pcall(function()
		put("RobloxComm/solo/declaretest.tsv",
			os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
			.. tostring(game.JobId):sub(1, 8) .. string.char(9)
			.. "held=" .. tostring(realName) .. string.char(9)
			.. "declared=BronzeSword" .. string.char(9)
			.. string.format("hp %.0f -> %.0f", hp0, hp1) .. string.char(9)
			.. string.format("drop=%.0f", hp0 - hp1) .. string.char(9)
			.. string.format("waited=%.0fms", (os.clock() - t0) * 1000) .. string.char(10))
	end)
end

cycleStrike = function(thing)
	if not MULTI_SWORD then return false end
	if os.clock() - lastCycle < CYCLE_GAP then return false end
	local list = swordsCarried()
	F.swordsCarried = #list
	if #list < 2 then
		-- One sword is the normal case and it is exactly why this never fires.
		-- Spend one hit a round finding out whether that even matters.
		local ev0 = events()
		if ev0 and list[1] then
			pcall(function() declareProbe(thing, ev0, ev0[HOLD_EVENT], list[1]) end)
		end
		return false
	end
	local ev = events()
	if not ev then return false end
	local hold = ev[HOLD_EVENT]
	if not (hold and hold.fire) then return false end
	lastCycle = os.clock()
	for _, nm in ipairs(list) do
		pcall(function() hold:fire(nm) end)
		for _, id in ipairs(HIT_PLAYER_IDS) do
			local e = ev[id]
			if e and e.fire then pcall(function() e:fire(thing) end) end
		end
	end
	-- Put the best one back. The tier rule, the panel and swordNow all read what
	-- we are holding, so leaving a bronze declared would quietly unlock looting
	-- again and make every later reading wrong.
	pcall(function() hold:fire(list[1]) end)
	F.cycles = (F.cycles or 0) + 1
	F.hitId = string.format("cycle x%d", #list)
	F.viaFire = (F.viaFire or 0) + #list
	return true
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

-- How many times we have stood on a chest and it did not open. Only used to stop
-- a chest that genuinely refuses from becoming an endless orbit; a chest that
-- opens is struck off by its own ChestOpened attribute, never by arriving.
local chestTries = {}
local CHEST_MAX_TRIES = 3

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

-- THE ONE WAY OUT OF A ROUND WITH NO SWORD AT ALL.
--
-- His rule stands and this does not touch it: tier four first, always, and a
-- tier one at your feet is worth less than no chest at all WHEN YOU ALREADY
-- HAVE A SWORD. What the rule never covered is the round where tier four comes
-- up empty and we end holding nothing.
--
-- Measured 2026-08-24 over chest_contents_master.tsv, 71290 chests:
--     tier 1   32055 chests   43.5% held a sword
--     tier 2    8569 chests   34.3%
--     tier 3    3051 chests   38.4%
--     tier 4   27615 chests   35.4%
-- Tier four is the best tier for the QUALITY of a sword and the worst tier for
-- getting one AT ALL. That is the whole mechanism behind the complaint.
--
-- It bites 13 rounds in 1549, and every one of those is a total loss - the
-- round at 07:21:43 today ran 25.2 seconds, opened 8 chests, threw 83 swings
-- and did 0 damage, because with swordDmg 0 the bot may not teleport to anyone
-- and just swings at men it cannot reach. Its tier four chests held JumpBoost,
-- Capybara and LifeSteal, then three that were already empty.
--
-- So this is a rescue, not a change of policy: only when we hold NOTHING, and
-- only after tier four has had the first RESCUE_AFTER seconds to itself. A
-- BronzeSword at 18 is not the plan, but it beats 0 damage for 25 seconds.
local RESCUE_AFTER = 8

-- NOTHING I ADD MAY EVER STOP THE LOOTING.
--
-- His order, 2026-08-24: "adding a thing never block the code to get chest
-- insdie itme, beucae u this was the second time doing an eror, to cost that
-- getting itme was going to be errro".
--
-- He is right and the shape of the mistake is mine twice over. This function
-- sits on the critical path - both chest selection loops call it for every
-- chest - so the moment anything in it throws, the chest list comes back EMPTY
-- and the farm loots nothing at all, silently, while the panel looks normal.
-- A rescue feature that can starve the farm is worse than no rescue feature.
--
-- So the whole body runs inside a pcall and any failure falls straight back to
-- the plain rule this file shipped with: tier four and nothing else. The farm
-- degrades to its old behaviour instead of to nothing. F.tierFallbacks counts
-- it so a silent failure still leaves a number behind.
local function tierOK(c)
	local ok, res = pcall(function() return tierOKInner(c) end)
	if ok then return res end
	F.tierFallbacks = (F.tierFallbacks or 0) + 1
	local ok2, plain = pcall(function() return tierOf(c.Name) == ONLY_TIER end)
	return ok2 and plain or false
end

function tierOKInner(c)
	-- THE SWORD RESCUE IS OFF, AND IT IS OFF BECAUSE IT STARVED THE FARM.
	--
	-- I added it this morning: hold nothing for RESCUE_AFTER seconds and any
	-- tier becomes legal, on the theory that a BronzeSword beats no sword. The
	-- theory was fine and the effect was the opposite, measured live at 09:0x on
	-- f2387tgu9hq:
	--
	--   phase   killing VIPER with none
	--   chests  97 opened this round
	--   sword   none, swordDmg 0, tpAllowed false
	--   nearest tier four   221 studs away
	--   rescueTier  true
	--
	-- Once the rescue opened the gate, every tier one at our feet became a valid
	-- candidate, so bestChestCluster always found something local and the bot
	-- never travelled the 221 studs to the tier four pile. Junk chests carry no
	-- 29 damage sword, so it stayed swordless, so the rescue stayed on. A loop
	-- that feeds itself.
	--
	-- His rule was right the first time and it is restored: tier four, nothing
	-- else. The pcall wrapper above stays, because that part was worth keeping.
	return tierOf(c.Name) == ONLY_TIER
end

local function rankedChests()
	local folder = chestFolder()
	local here = myPos()
	if not folder or not here then return {} end
	local list = {}
	for _, c in ipairs(folder:GetChildren()) do
		if tierOK(c) and not visited[c] then
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
-- MY CHECKPOINT FIRST, the whole pile second.
--
-- His words, 2026-08-22: "it will detect atleast 2- 6+ chest in 12 studs that
-- place will be a chekc point, it will scan each bot ... and telling what chekc
-- point they will use". With three clients in one server the biggest pile is
-- the biggest pile for all three of them, so "always take the densest" sends
-- every bot to the same chests and two of the three get nothing.
--
-- SOLO_TEAM hands out one checkpoint per bot in whitelist order. This takes it
-- while it still has an unopened chest in it and falls back to the old greedy
-- pick the moment it is empty - so a bot never stands on a stripped pile.
local function myCheckpoint()
	local pos, n
	pcall(function()
		if env.__SOLOTEAM_CP then pos, n = env.__SOLOTEAM_CP() end
	end)
	if not pos then return nil end
	local folder = chestFolder()
	if not folder then return nil end
	local members = {}
	local sx, sy, sz = 0, 0, 0
	for _, c in ipairs(folder:GetChildren()) do
		if tierOK(c) and not visited[c] then
			local p
			pcall(function() p = c:GetPivot().Position end)
			if p and (p - pos).Magnitude <= CHEST_REACH then
				members[#members + 1] = { inst = c, pos = p }
				sx = sx + p.X sy = sy + p.Y sz = sz + p.Z
			end
		end
	end
	if #members == 0 then return nil end
	F.clusterSize = #members
	F.cpUsed = true
	return { centre = Vector3.new(sx / #members, sy / #members, sz / #members), members = members }
end

-- THE MIDDLE IS THE ANCHOR.
--
-- His instruction, 2026-08-24: "it should telepted to the midlde only ... i can
-- see it was at the countdown 3th sec go tto the middle then 2th go tot the
-- middle, and alos 1th sec then t was gog ot ohters sword that was wrong".
--
-- He watched it drift on the last second of the countdown and he is right about
-- why that is bad. The tier fours arrive in a tight knot around the map's chest
-- centroid - the census column map_master calls "chest centre" reads 0,-4,0 and
-- 0,-8,0 and 1,-2,0 round after round - so the middle IS the pile. Anything else
-- is a smaller pile bought with the whole countdown.
--
-- The drift came from the tie break: biggest pile wins, and equal piles were
-- settled by "closest to ME". Early in a round every pile is the same size, so
-- that tie break decided everything, and it pointed wherever the body happened
-- to spawn. While we are unarmed it now points at the middle instead. Teleport
-- costs nothing in studs, so being far from the middle is not a reason.
local function mapCentre()
	local folder = chestFolder()
	if not folder then return nil end
	local n, sx, sy, sz = 0, 0, 0, 0
	for _, c in ipairs(folder:GetChildren()) do
		local p
		pcall(function() p = c:GetPivot().Position end)
		if p then
			n = n + 1
			sx = sx + p.X sy = sy + p.Y sz = sz + p.Z
		end
	end
	if n == 0 then return nil end
	return Vector3.new(sx / n, sy / n, sz / n)
end

local function bestChestCluster()
	-- THE CHECKPOINT ONLY EARNS ITS PLACE WHEN A BROTHER IS ACTUALLY HERE.
	--
	-- 2026-08-24. myCheckpoint returned the moment it found ONE unopened chest,
	-- so a pile of one beat a pile of five and the greedy search below never
	-- ran at all. Measured over 5227 state lines: 19.5% of the time this farm
	-- was standing on a single chest.
	--
	-- The checkpoint exists for one reason and he said it himself on 2026-08-22 -
	-- three bots in one server must not strip the same pile. That reason is real
	-- and the rule stays. But this is SOLO: our accounts queue independently and
	-- land in different servers, and the roster data says only 6 of 43 shared
	-- rounds ever had two of ours in them. So for the large majority of rounds we
	-- were paying a collision tax against brothers who were not in the building.
	--
	-- So ask first. Mates here, keep his rule. Nobody here, take the biggest pile.
	-- Distance is not part of this decision at all - with a zero delay teleport
	-- the far pile costs exactly the same as the near one, which is why the
	-- greedy search below only uses distance as a tie break.
	local mates = 0
	pcall(function()
		local T = env.__SOLOTEAM
		mates = tonumber(T and T.matesHere) or 0
	end)
	F.mates = mates
	if mates > 0 then
		local mine = myCheckpoint()
		if mine then return mine end
	end
	F.cpUsed = false
	local list = rankedChests()
	if #list == 0 then return nil end
	-- Unarmed, the yardstick is the middle. Armed, it is us again, because by
	-- then the job is finishing the map rather than reaching the pile.
	local here = myPos()
	local anchorPt = here
	if (F.swordDmg or 0) <= 0 then
		local mid = mapCentre()
		if mid then
			anchorPt = mid
			F.aim = "middle"
		end
	else
		F.aim = "me"
	end
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
		local d = anchorPt and (centre - anchorPt).Magnitude or 0
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

-- THE WHITELIST. SOLO_TEAM owns it; this is only the question, asked in the one
-- place that decides who may be hit.
--
-- His words, 2026-08-22: "it will having a whitelist number that it was will be
-- detect whihc was my self, and not em, so we need to tell bot to kill all
-- others em". A whitelisted account is never a target while the whitelist is
-- up, and SOLO_TEAM drops it by itself once every em is dead - which is the
-- free for all he described and accepted.
--
-- If SOLO_TEAM is not loaded this returns false for everybody, so the farm
-- behaves exactly as it did before, with one client and no team.
local function teamFriend(p)
	local fn = env.__SOLOTEAM_FRIEND
	if not fn then return false end
	local ok, res = pcall(fn, p)
	return ok and res == true
end

-- IS THIS MAN MINE TO KILL.
--
-- His words, 2026-08-22: "so nlcuky was the bot was stealing kills ... it need
-- to fris tot do was kill eahc part of player". Two bots on one man is one kill
-- counted once and the seconds paid twice, so SOLO_TEAM cuts the em into parts
-- and each bot only hunts its own.
--
-- It answers true for everybody when there is no team, when the handshake has
-- not confirmed, and once my own part is already dead - so a lone client behaves
-- exactly as it always did, and a bot that has finished its three never stands
-- around while eight strangers walk past.
local function teamMine(p)
	local fn = env.__SOLOTEAM_MINE
	if not fn then return true end
	local ok, res = pcall(fn, p)
	if not ok then return true end
	return res == true
end

-- How much trouble is this man, and how cheap is he to finish.
--
-- His words: "the bot will smart thinning whihc em was need to kill first".
-- Every term in here is a number read off the player, never a guess:
--   Health     the attribute, the one the game plays with
--   Level      read off the player, his own account was 21 at 10:0x
--   Kills      lifetime, an account with 1200 kills is not a bystander
--   distance   near men can hit me back and cost no travel
--   Y          Viper's low-first rule, kept as the smallest term
local function threatOf(p, dist, y)
	local hp = 100
	local a = p:GetAttribute("Health")
	if type(a) == "number" then hp = a end
	local lvl = tonumber(p:GetAttribute("Level")) or 0
	local kills = tonumber(p:GetAttribute("Kills")) or 0
	local danger = math.min(lvl / 20, 3) + math.min(kills / 400, 3)
	return hp + (dist or 0) * 0.25 + (y or 0) * 0.15 - danger * 6
end

local function living()
	local r = myRoot()
	if not r then return {} end
	local out, raw = {}, {}
	local skipped = 0
	local friends = 0
	local notMine = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= lp and teamFriend(p) then
			friends = friends + 1
		elseif p ~= lp and not teamMine(p) then
			-- Somebody else's part of the split. Not a friend, just not mine.
			notMine = notMine + 1
		elseif p ~= lp then
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
	F.friends = friends
	F.notMine = notMine
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
			if F.firstKillFromDrop == 0 and F.dropAt > 0 then
				F.firstKillFromDrop = os.clock() - F.dropAt
			end
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

-- TRAP THE MAN.
--
-- His design, and his numbers: a tier one trap is a nine cell hollow cage -
-- four sides at foot level, the same four one block up, and a lid. Measured
-- 2026-08-24 on the testing client: 228 milliseconds for the nine, eight of
-- nine landing, when they go bottom up in three waves. He asked for it back on
-- 2026-08-24 and for it to keep spamming so a trapped man stays trapped.
--
-- Why it is worth a slot in the combat loop rather than a toy: the record says
-- 40% of every live round has nobody within 60 studs of us and only 54.6% of
-- frames have anybody inside the 9 stud strike range. A man who cannot walk out
-- of the cage is a man inside that range for every window that follows, and
-- windows are the whole currency.
--
-- Three hard numbers from the game, none of them negotiable:
--   the grid is 3 studs, and a position that is not a multiple of 3 is refused
--   placement reaches 6 blocks, which is 18 studs, and it is a sphere not a box
--   a player is 6.48 studs tall, so two levels of cage is head height

local TRAP_GAP = 0.6
local TRAP_RANGE = 18
local lastTrap = {}
local bnzCache

local function blockCtl()
	if bnzCache then return bnzCache end
	pcall(function()
		local mod = flamework()
		bnzCache = mod.Flamework.resolveDependency("BnZ")
	end)
	return bnzCache
end

-- The grid is 3 studs and a position that is not a multiple of 3 is refused.
local function snap3(v)
	return math.floor(v / 3 + 0.5) * 3
end

-- The real contract, read out of block-controller on 2026-08-24:
--
--   placeBlock(pos, heldName, itemDef, rotation)
--     BlockUtil.canPlace(pos)            the cell must be empty
--     BlockUtil.hasAdjacentBlock(pos)    it must TOUCH something already there
--     BlockUtil.validateConstraints(...) the round's build rules
--     bDe:registerItemPrediction(heldName, -1)   we must really own one
--     itemDef.Block.Ref:Clone()          so the def cannot be nil
--
-- heldName is what the hotbar says we hold - "TeamConcrete" - and the def is
-- the rewritten one, Items[ConcreteSmooth<our team colour>]. Passing the pretty
-- colour name as heldName, or nil as the def, is what my first version did and
-- both of those are silently refused.
--
-- Adjacency is why the cage goes bottom ring, head ring, lid: the bottom ring
-- touches the floor he stands on, the head ring touches the bottom ring, the lid
-- touches the head ring. A cage built top down would be nine refusals.

-- Look the definition up straight out of the item table instead of asking the
-- client what it is holding. Telling the server we hold a block is one event -
-- the LOCAL hotbar does not change on the same frame, so getHeldItemInfo would
-- still answer DiamondSword and the rewrite would never fire.
--
-- Resolved live on this client 2026-08-24: Items.TeamConcrete has no Block of
-- its own, it carries Rewrite.Type = "ConcreteSmooth{TeamId}", our team reads
-- Cyan, and Items.ConcreteSmoothCyan has Block.Ref. That last table is what
-- placeBlock clones, so it is the one that has to be passed.
local defCache
local function blockDef()
	if defCache then return defCache, "TeamConcrete", "cached" end
	local def, why
	pcall(function()
		local RS = game:GetService("ReplicatedStorage")
		local mod = flamework()
		local Items = require(RS.TS.item.item)
		local tbl = Items.Items or Items
		local base = tbl["TeamConcrete"]
		if not base or not base.Rewrite then why = "no TeamConcrete in the item table" return end
		local team = mod.Flamework.resolveDependency("Pl"):getPlayerTeamId() or "White"
		local key = string.gsub(base.Rewrite.Type, "{TeamId}", tostring(team))
		local d = tbl[key]
		if not d or not d.Block then why = "no block def for " .. key return end
		def = d
		why = key
	end)
	if def then defCache = def end
	return def, "TeamConcrete", why
end

local function haveBlocks()
	local hb = hotbar()
	if not hb then return nil end
	local slot, name, qty
	pcall(function()
		for _, it in ipairs(hb:getHotbarItems() or {}) do
			local nm = tostring(it.Type or it.Name or "")
			if nm:find("Concrete") and (tonumber(it.Quantity) or 0) > 0 then
				slot, name, qty = it.Slot, nm, tonumber(it.Quantity)
				break
			end
		end
	end)
	return name, slot, qty
end

local function trapPlayer(rr)
	if not rr or not rr.Parent then return false end
	local me = myPos()
	if not me then return false end
	if (rr.Position - me).Magnitude > TRAP_RANGE then return false end
	if os.clock() - (lastTrap[rr] or 0) < TRAP_GAP then return false end

	local have, _, qty = haveBlocks()
	if not have then
		F.trapWhy = "no blocks carried"
		return false
	end
	local bc = blockCtl()
	if not bc then F.trapWhy = "no block controller" return false end

	-- Tell the server we are holding the block, place, then hand the sword back,
	-- exactly the way the potion code does it. No slot change, no animation.
	local holdEv = game:GetService("ReplicatedStorage")
		:FindFirstChild("8dd94a0e-0dd9-409c-8847-de1054173265", true)
	local swordName = F.sword
	if holdEv then pcall(function() holdEv:FireServer(have) end) end

	local def, held, why = blockDef()
	F.trapDef = tostring(why)
	if not def then
		F.trapWhy = tostring(why)
		if holdEv and swordName and swordName ~= "none" then
			pcall(function() holdEv:FireServer(swordName) end)
		end
		return false
	end

	lastTrap[rr] = os.clock()
	local p = rr.Position
	local foot = Vector3.new(snap3(p.X), snap3(p.Y - 3), snap3(p.Z))
	local waves = {
		{ Vector3.new(3, 0, 0), Vector3.new(-3, 0, 0), Vector3.new(0, 0, 3), Vector3.new(0, 0, -3) },
		{ Vector3.new(3, 3, 0), Vector3.new(-3, 3, 0), Vector3.new(0, 3, 3), Vector3.new(0, 3, -3) },
		{ Vector3.new(0, 6, 0) },
	}
	local sent = 0
	for _, wave in ipairs(waves) do
		for _, off in ipairs(wave) do
			local ok = pcall(function() bc:placeBlock(foot + off, held, def, 0) end)
			if ok then sent = sent + 1 end
		end
	end

	if holdEv and swordName and swordName ~= "none" then
		pcall(function() holdEv:FireServer(swordName) end)
	end

	F.trapBlocks = (F.trapBlocks or 0) + sent
	F.traps = (F.traps or 0) + 1
	F.trapWhy = "fired"
	pcall(function()
		put("RobloxComm/solo/trap.tsv",
			os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
			.. tostring(game.JobId):sub(1, 8) .. string.char(9)
			.. tostring(rr.Parent and rr.Parent.Name) .. string.char(9)
			.. tostring(sent) .. string.char(9)
			.. tostring(held) .. string.char(9)
			.. tostring(qty) .. string.char(9)
			.. string.format("%.0f", (rr.Position - me).Magnitude) .. string.char(10))
	end)
	return sent > 0
end


-- Moved up here from below killViper on 2026-08-24. pin needs both of them and
-- pin is declared 270 lines earlier, so down there they were nil globals inside
-- it and every finish comparison silently compared against nil.
local FINISH_HP = 45
local FINISH_EXTRA = 0.5

-- WHAT IS THE COOLDOWN KEYED ON? THAT ONE ANSWER DECIDES EVERYTHING.
--
-- 539 landed hits measured 2026-08-24 23:2x: median 0.436s between hits, 79%
-- of them in the 0.4 and 0.5 buckets, only 3% inside 0.30s. That is a hard
-- server cooldown of about 0.4s and no firing rate we choose changes it - we
-- were already firing every 0.05s.
--
-- projectile-controller checks `EZr:isOnCooldown(Name)` - BY ITEM NAME - and
-- fires a completely different remote to the melee one. So if melee is keyed
-- the same way, two different swords are two different cooldowns and cycling
-- is real; and a thrown item is a third, parallel one. If it is keyed on
-- something global like "Melee", none of that works and the 0.4s is the floor.
--
-- The client's own cooldown table is the answer and it is readable. Dump it the
-- first time we land a hit each round, then again a tenth of a second later so
-- the entry that just went on cooldown is visible.
local cdDumped = ""
local function dumpCooldowns(when)
	pcall(function()
		local GlobalStore = require(lp.PlayerScripts.TS.ui.rodux["global-store"]).GlobalStore
		local st = GlobalStore:getState()
		local cd = st and st.Cooldowns
		local bits = {}
		if type(cd) == "table" then
			for k, v in pairs(cd) do
				bits[#bits + 1] = tostring(k) .. "=" .. tostring(v)
			end
		end
		put("RobloxComm/solo/cooldowns.tsv",
			os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
			.. tostring(game.JobId):sub(1, 8) .. string.char(9)
			.. tostring(when) .. string.char(9)
			.. "sword=" .. tostring(F.sword) .. string.char(9)
			.. "entries=" .. tostring(#bits) .. string.char(9)
			.. (#bits > 0 and table.concat(bits, " | "):sub(1, 300) or "(empty)") .. string.char(10))
	end)
end

local function pin(rr, stopAt, hitIt, who)
	local last = 0
	local moved = false
	local hp0 = who and hpOf(who) or nil
	local swung = false
	local swungAt, swungN = -1, 0
	local lastHp = hp0
	local windowDrop = 0
	-- HIS QUESTION, 2026-08-24 21:1x: is every player dying inside 1.1 seconds,
	-- or at worst 1.3? Nothing in the files could answer it. kills.tsv only had
	-- `gap`, the seconds between one finish and the next, and that includes
	-- picking the next man and hopping to him. What he is asking about is the
	-- exchange itself, so it gets its own clock: from the first health that
	-- comes off him to the moment he is down.
	local firstHitAt = nil
	local lastDropAt = nil
	local extended = false
	-- The window may never run past this, however much he bleeds. Without it a
	-- man who keeps healing would hold the body for the whole round.
	local hardStop = os.clock() + 4.0
	if stopAt > hardStop then hardStop = stopAt end
	while alive() and F.on and os.clock() < stopAt do
		if F.rescuing then return false end
		if not amAlive() then return false end
		-- Same reason as the health check below: his character being gone is
		-- usually him dying, and a return here skips the finish counter too.
		if not rr or not rr.Parent then break end
		-- He is down. Leave now instead of standing on a corpse for the rest of
		-- the window - that was one of the four tolls.
		-- HEARTBEAT, NOT A FLAG. Every return in this loop would have to clear
		-- a boolean and one of them would eventually not, so the pin publishes
		-- a timestamp instead and the dry nudge treats anything older than a
		-- third of a second as "no pin running". It expires by itself.
		F.pinBeat = os.clock()
		if who then
			local nowhp = hpOf(who)
			-- DAMAGE HAS TO BE PUBLISHED WHEN IT LANDS, NOT WHEN THE WINDOW SHUTS.
			--
			-- F.dmgSeen was only written after this loop, so a 2.0s pin looked
			-- like 2.0s of nothing to the 0.1s self check, whose dry threshold
			-- is 1.5s. LOCK_SECS 2.0 is longer than NUDGE_DRY 1.5, so EVERY pin
			-- was guaranteed to be torn open by the nudge before it could
			-- finish anybody. Measured 2026-08-24 in range_test.tsv: three
			-- windows in a row reading dist=6 swings=23 lost=96 - four hits
			-- landed, four health short of a kill, then the body walked away.
			if nowhp and lastHp and nowhp < lastHp then
				local drop = lastHp - nowhp
				if not firstHitAt then firstHitAt = os.clock() end
				-- THE INTERVAL IS THE THING, NOT THE TOTAL.
				--
				-- hold tells us a kill took 1.33s. It cannot tell us whether that
				-- is four hits at 0.44 or five at 0.33, and those need opposite
				-- fixes. One row per landed hit with the seconds since the last
				-- one and the HIT_GAP that produced it.
				if cdDumped ~= tostring(game.JobId) then
					cdDumped = tostring(game.JobId)
					dumpCooldowns("right after a landed hit")
					task.delay(0.12, function() dumpCooldowns("120ms later") end)
				end
				if lastDropAt then
					pcall(function()
						put("RobloxComm/solo/hitgap_" .. lp.Name .. ".tsv",
							os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
							.. tostring(game.JobId):sub(1, 8) .. string.char(9)
							.. string.format("gap=%.2f", HIT_GAP) .. string.char(9)
							.. "burst=" .. tostring(BURST) .. string.char(9)
							.. string.format("since=%.3f", os.clock() - lastDropAt) .. string.char(9)
							.. string.format("drop=%.0f", drop) .. string.char(9)
							.. "sword=" .. tostring(F.sword) .. string.char(10))
					end)
				end
				lastDropAt = os.clock()
				windowDrop = windowDrop + drop
				F.dmgSeen = F.dmgSeen + drop
				F.lastLandT = os.clock()
			end
			if nowhp then lastHp = nowhp end
			-- He is down. Stop swinging, but LEAVE THROUGH THE BOTTOM OF THE
			-- LOOP, not through a return.
			--
			-- This was `return true`, and the finish counter, kills.tsv and the
			-- window counters all live BELOW the loop, so every single time the
			-- farm actually killed somebody it jumped over its own scoreboard.
			-- Measured 2026-08-24 21:11 and 21:12: two rounds with 767 and 732
			-- damage - about twenty-six landed hits, six or seven men - and
			-- ab_test recorded 0/0 windows and 0 finishes for both.
			if nowhp and nowhp <= 0 then break end
			-- dwell was computed from the health he had when we ARRIVED, so
			-- nothing could extend it once he got low. One extension, capped.
			if nowhp > 0 and nowhp <= FINISH_HP and not extended then
				extended = true
				local want = os.clock() + FINISH_EXTRA + 0.4
				if want > stopAt then
					stopAt = (want < hardStop) and want or hardStop
					F.finishHolds = (F.finishHolds or 0) + 1
				end
			end
		end
		local r = myRoot()
		if not r then return false end
		if F.tpAllowed then
			local want, _, buried = strikeSpot(rr.Position, swingSeq)
			if not want then return false end
			if buried then
				-- Re-assert the exact spot, not the one we drifted to. Reading
				-- r.Position back and writing that is what let physics lift the
				-- body out of the block one frame at a time.
				F.buried = true
				pcall(function()
					r.CFrame = CFrame.new(want, rr.Position)
					r.AssemblyLinearVelocity = Vector3.zero
				end)
			elseif (want - r.Position).Magnitude > 3 then
				F.buried = false
				hop(want, false, rr.Position)
				moved = true
			else
				F.buried = false
				pcall(function()
					r.CFrame = CFrame.new(r.Position, rr.Position)
					r.AssemblyLinearVelocity = Vector3.zero
				end)
			end
		end
		-- Cage him while we are on him. It is rate limited to TRAP_GAP so this
		-- cannot become a packet storm, and it costs nothing when he is already
		-- boxed in - the server simply refuses a cell that is occupied.
		pcall(function() trapPlayer(rr) end)
		local r2 = myRoot()
		-- Deliberately NOT gated on HIT_RANGE any more. HIT_RANGE is the client's
		-- own refusal threshold and this file does not go through the client's
		-- check; gating on it here would have made every rung of the ladder above
		-- 10.35 silently swing zero times and produce a fake "no damage" result.
		if r2 and (rr.Position - r2.Position).Magnitude <= math.max(STRIKE_RANGE, BELOW + 3) then
			if os.clock() - last >= HIT_GAP then
				-- Same frame, no yield between them. If the server stamps after it
				-- reads, these arrive while the stamp still says the previous hit.
				for _ = 1, BURST do hitIt() end
				F.swings = (F.swings or 0) + BURST
				swungAt = (rr.Position - r2.Position).Magnitude
				swungN = swungN + 1
				swung = true
				last = os.clock()
			end
		end
		RunService.Heartbeat:Wait()
	end
	if swung and hp0 and who then
		local hp1 = hpOf(who)
		F.dmgWindows = F.dmgWindows + 1
		-- The health drop was already added frame by frame inside the loop.
		-- Adding it again here would double every round total, so only the
		-- window counter is settled at this point.
		if windowDrop > 0 then
			F.dmgHits = F.dmgHits + 1
		end
		-- One row per damage window: how far the last swing was thrown from, how
		-- many went out, and how much health actually came off. Bucketed by the
		-- whole stud so the ceiling reads straight off the file - the distance
		-- where "lost" stops being greater than zero is the server's real limit.
		pcall(function()
			put("RobloxComm/solo/range_test.tsv",
				os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
				.. string.format("dist=%.0f", swungAt) .. string.char(9)
				.. "swings=" .. tostring(swungN) .. string.char(9)
				.. string.format("lost=%.0f", windowDrop) .. string.char(9)
				.. "sword=" .. tostring(F.sword) .. string.char(10))
		end)
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
				-- ONE LINE PER FINISH, BECAUSE "30 SECONDS" IS NOT A CAUSE.
				--
				-- Measured over the last twenty rounds: sword at 5.0s, first finish at
				-- 9.0s, last finish at 23.6s, round closes at 27.4s. So the killing
				-- itself is 14.6 of the 27.4 seconds and about 2.8s per man, against
				-- Viper's whole round of 12s. What is not measured yet is what those
				-- 2.8 seconds are spent on, and that cannot be guessed from a total.
				--
				-- gap is the seconds since the previous finish, dist is how far he was
				-- when he went down, and the swing and damage counters are cumulative,
				-- so the difference between two rows is what that one kill cost.
				pcall(function()
					local at = F.lastKill
					local gap = at - (F.prevFinishAt or 0)
					F.prevFinishAt = at
					local dn = tostring(who.DisplayName)
					local dist = -1
					local rme, rw = myRoot(), who.Character and who.Character:FindFirstChild("HumanoidRootPart")
					if rme and rw then dist = (rw.Position - rme.Position).Magnitude end
					put("RobloxComm/solo/kills.tsv",
						os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
						.. string.format("r%03d", F.round) .. string.char(9)
						.. tostring(who.Name) .. ((dn ~= who.Name) and ("(" .. dn .. ")") or "") .. string.char(9)
						.. string.format("at=%.1f", at) .. string.char(9)
						.. string.format("gap=%.1f", gap) .. string.char(9)
						-- hold is the answer to his 1.1 second question: first blood
						-- on this man to this man down, nothing else in it.
						.. string.format("hold=%.2f", firstHitAt and (os.clock() - firstHitAt) or -1) .. string.char(9)
						.. string.format("dist=%.0f", dist) .. string.char(9)
						.. "n=" .. tostring(F.finishes) .. string.char(9)
						.. "swings=" .. tostring(F.swings or 0) .. string.char(9)
						.. string.format("dmg=%.0f", F.dmgSeen) .. string.char(9)
						.. "skipped=" .. tostring(F.skippedNoUnder or 0) .. string.char(10))
				end)
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
-- FIGHT BACK. HIS ORDER, 2026-08-24: the goal is to kill Viper.
--
-- Until now this farm did not know he existed. Target choice was threatOf plus
-- a parked penalty and nothing else, so a man on the blacklist standing three
-- studs away lost the pick to a stranger who happened to be one stud lower. It
-- is measurable how badly that goes: in the window at 06:30:56 our bot lost 72
-- health in four seconds while it was busy on somebody else, and two of the
-- three damage ticks landed 0.40 seconds apart, which is exactly the game's own
-- DAMAGE_COOLDOWN - two attackers alternating, so half the survival time.
--
-- The counter is not cleverness, it is order. Both sides carry the same 0.4
-- second cooldown and the same 100 health, so a straight exchange is decided by
-- who starts first. Onyx at 32 needs four landing hits, which is 1.6 seconds.
-- If we are the one already swinging when the exchange opens, we win it.
--
-- So a blacklisted man inside VIPER_LOCK studs gets a score nothing else can
-- beat and we stay on him. Outside that range he is scored normally and we do
-- NOT chase - chasing across a map is the slow death his EggWars rules already
-- ruled out, and 74% of the frames we have of him are beyond 20 studs anyway.
local BLACK = {}
pcall(function()
	for _, p in ipairs({ "RobloxComm/blacklist.txt", "RobloxComm/solo/blacklist.txt" }) do
		if isfile(p) then
			for line in readfile(p):gmatch("[^\r\n]+") do
				local nm = line:match("^%s*%d*%s*(%S+)%s*$")
				if nm then BLACK[string.lower(nm)] = true end
			end
		end
	end
end)

-- 20, not 9. Nine is where our sword starts working; twenty is where we should
-- already have decided he is the one being hit, so the swing is going in as he
-- arrives rather than a beat after it.
local VIPER_LOCK = 20

local function isBlack(p)
	if not p then return false end
	-- NEVER LET THE BAIT NAME POINT AT US.
	--
	-- 2026-08-24 06:5x, found while checking the new set before arming it. All
	-- four of our display names are deliberately built to be found by him:
	-- four decoy accounts of ours. The
	-- blacklist carries ViperInTheSkywars. Those two do not collide today, and
	-- that is the whole problem - they are one new account apart, and this
	-- function tests DisplayName as well as Name. A collision would not degrade
	-- gracefully either: a blacklisted man gets his score cut by 100000, which
	-- nothing else in the ranking can outweigh, so the entire fleet would lock
	-- onto itself and hold, with the extra second of dwell, for the whole round.
	--
	-- The team module already owns the question of who is mine, so ask it rather
	-- than keeping a second list that can drift. It answers true for me and for
	-- any whitelisted account, and it deliberately answers false once the free
	-- for all opens - which is correct here too, because at that point brothers
	-- really are targets and the normal ranking should apply to them.
	local fr = env.__SOLOTEAM_FRIEND
	if type(fr) == "function" then
		local ok, mine = pcall(fr, p)
		if ok and mine then return false end
	end
	-- A LIST OF NAMES CANNOT KEEP UP WITH HIM. A SHAPE CAN.
	--
	-- 2026-08-24 11:02:57, from f2387tgu9hq's ring: a man called ViperIsInTheSky
	-- crossed 128.3 studs to 4.5 studs inside one 0.1 second frame and took 18
	-- health. He was not on the blacklist - the list had ViperForTheVipe,
	-- ViperAgainstUrGame and ViperInTheSkywars - so the lock-on never fired and
	-- keep-clear never fired. He fought us with our guard down purely by having
	-- signed up under a fourth name.
	--
	-- Every account of his so far starts with "viper" and none of them uses an
	-- underscore. Every account of OURS starts with "viper_". That is a clean
	-- split and it costs him a rename to break, which is more than a hand
	-- maintained list costs us.
	--
	-- The exact list stays as well, because it also carries the two non-viper
	-- names, and the team friend check above still runs first, so this can never
	-- point at one of ours even if he registers something that collides.
	local low = string.lower(tostring(p.Name))
	local lowd = string.lower(tostring(p.DisplayName or ""))
	if BLACK[low] == true or BLACK[lowd] == true then return true end
	-- Anyone SOLO_REC has caught standing inside solid rock is him, whatever he
	-- is calling himself this round. The friend guard above has already run, so
	-- this can never point at one of ours.
	local ph = env.__SOLO_PHASERS
	if type(ph) == "table" and (ph[low] or (lowd ~= "" and ph[lowd])) then return true end
	if low:sub(1, 5) == "viper" and low:sub(1, 6) ~= "viper_" then return true end
	if lowd:sub(1, 5) == "viper" and lowd:sub(1, 6) ~= "viper_" then return true end
	return false
end

-- STOP PAYING THE TOLL FOUR TIMES.
--
-- His measurement, 2026-08-24, after the first live test: "it need to use 0.2
-- to find and telpte to the next player". That 0.2s is not a rounding error, it
-- is the whole shape of the problem:
--
--   find the next man and teleport   0.2
--   stand there for one window       0.4
--   one visit                        0.6
--   four visits, because we leave after every single hit   2.4
--
-- and 2.5s is exactly what the record says a kill costs us. So the dwell number
-- was never the lever - LEAVING was. A man costs four hits; if we stay for all
-- four the 0.2 is paid once instead of four times.
--
-- pin now holds until he is dead, he leaves reach, or LOCK_SECS runs out, so a
-- man who cannot be finished cannot hold us for ever either.
local LOCK_SECS = 2.0

-- TWO THINGS THE SCORE GOT WRONG, BOTH MEASURED 2026-08-24.
--
-- One: distance was worth almost nothing. threatOf adds dist * 0.25, so a man
-- four hundred studs away costs 100 - exactly what a full health bar costs. A
-- wounded stranger across the map therefore outranked a healthy man standing in
-- front of us, and the farm went and got him. Teleporting is free in studs but
-- it is not free in TIME: the hop, the settle and the re-aim all fall inside
-- 0.4 second damage windows. The record says that is where the round goes -
-- across 182,801 live frames somebody is inside 9 studs only 54.6% of the time,
-- and 39.8% of the time the nearest living man is more than 60 studs away, with
-- almost nothing in between. So anyone already in reach now wins outright.
--
-- Two: a dying man who stops moving was being thrown to the back. The parked
-- penalty is 10000 and nothing in threatOf can outweigh it, but a man on 10
-- health who stands still is one swing from a kill, and standing still is
-- exactly what a cornered man does. Measured cost: 629 damage dealt a round
-- against 5 kills collected - 129 damage a round, 21%, sunk into people who
-- lived. Below FINISH_HP the parked penalty no longer applies.
--
-- Both terms stay far under the blacklist's 100000, so Viper still outranks
-- everything either of these can promote.
local REACH_WINS = 500

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
	-- One score, ascending, kill the smallest first. Parked men are pushed
	-- behind every moving man by a term nothing else can outweigh, which is his
	-- rule; everything below that line is threatOf, which is weakest first with
	-- level and lifetime kills pulling a dangerous man forward and Viper's low-Y
	-- rule as the smallest term.
	local blackNear = nil
	for _, t in ipairs(list) do
		local thp = hpOf(t.p) or 100
		local reallyParked = t.parked and thp > FINISH_HP
		t.score = threatOf(t.p, t.dist, t.y)
			+ (reallyParked and 10000 or 0)
			- ((t.dist <= STRIKE_RANGE) and REACH_WINS or 0)
		-- A blacklisted man in reach outranks everything, including the parked
		-- penalty - if he is standing still he is still the one we want.
		t.black = isBlack(t.p)
		if t.black and t.dist <= VIPER_LOCK then
			t.score = t.score - 100000
			if (not blackNear) or t.dist < blackNear.dist then blackNear = t end
		end
	end
	F.black = blackNear and (blackNear.p.Name .. string.format(" d=%.1f", blackNear.dist)) or "-"
	if blackNear then
		F.blackSeen = (F.blackSeen or 0) + 1
		if os.clock() - (F.blackLog or 0) > 2 then
			F.blackLog = os.clock()
			-- TAB and NL are declared at line 1935, BELOW this block, so up here
			-- they are nil globals and every one of these concatenations throws.
			-- The pcall would have swallowed it and the file would simply never
			-- have appeared - a silent hole exactly where the evidence was meant
			-- to be. Spell the two characters out instead of reaching upward.
			pcall(function()
				local t9, t10 = string.char(9), string.char(10)
				put("RobloxComm/solo/viper_fight.tsv",
					os.date("%Y-%m-%d %H:%M:%S") .. t9
					.. tostring(game.JobId):sub(1, 8) .. t9
					.. tostring(blackNear.p.Name) .. t9
					.. string.format("%.1f", blackNear.dist) .. t9
					.. string.format("%.1f", blackNear.y) .. t9
					.. string.format("%.0f", hpOf(blackNear.p) or -1) .. t9
					.. string.format("%.0f", hpOf(game.Players.LocalPlayer) or -1) .. t9
					.. tostring(F.sword or "?") .. t9
					.. tostring(F.swings or 0) .. t9
					.. tostring(F.finishes or 0) .. t10)
			end)
		end
	end
	table.sort(list, function(a, b) return a.score < b.score end)
	do
		local bits = {}
		for i = 1, math.min(3, #list) do
			bits[#bits + 1] = string.format("%s(%.0f)", list[i].p.Name, list[i].score)
		end
		F.rank = table.concat(bits, " > ")
	end
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
	-- Never let go of him mid exchange. Leaving a blacklisted man after 0.2
	-- seconds hands back the one thing that decides the trade, which is who is
	-- already swinging, and every hit already landed on him is wasted.
	local dwell = LOCK_SECS + ((hp <= FINISH_HP) and FINISH_EXTRA or 0)
		+ ((t.black and t.dist <= VIPER_LOCK) and 1.0 or 0)
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
			local want, _, buried = strikeSpot(rr.Position, swingSeq)
			if not want then
				F.skippedNoUnder = (F.skippedNoUnder or 0) + 1
			else
				F.buried = buried and true or false
				F.target = t.p.Name .. " x" .. F.frames
					.. (F.tpAllowed and " (under)" or " (no tp, sword too weak)")
				local r = myRoot()
				if r and F.tpAllowed and not buried and (want - r.Position).Magnitude > 3 then
					hop(want, false, rr.Position)
				end
				for _ = 1, F.frames do
					local r2 = myRoot()
					if r2 then
						if buried and F.tpAllowed then
							pcall(function() r2.CFrame = CFrame.new(want, rr.Position) end)
						end
						pcall(function() r2.AssemblyLinearVelocity = Vector3.zero end)
						-- Opened from HIT_RANGE to STRIKE_RANGE. The pin windows only ever
						-- record 3 to 8 studs because the farm parks itself 6 under the
						-- man, so it could never sample the long end. These are the
						-- swings thrown at whoever happens to be nearby, and they are
						-- what will fill in the top of range_test.tsv.
						if (rr.Position - r2.Position).Magnitude <= STRIKE_RANGE then
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
		.. tostring(why) .. TAB
		-- Two columns added 2026-08-24 evening so the pin fix reads off the
		-- file instead of off memory. nudges is how many times the dry rescue
		-- fired - it was ten in nine seconds on the last broken round, each one
		-- teleporting the body to a different man mid-exchange. holds is how
		-- many windows were extended because he dropped under FINISH_HP while
		-- we were on him, which could not happen at all before: dwell was fixed
		-- at the moment the pin opened, so three windows in a row ended at
		-- lost=96 with the man four health from dead.
		.. tostring(F.nudges or 0) .. TAB
		.. tostring(F.finishHolds or 0) .. TAB
		.. tostring(F.penRescues or 0) .. TAB
		.. "burst=" .. tostring(F.burst or BURST) .. NL)
	-- One row per round per gap, so "the fastest gap that still lands" ends up
	-- being a number in a file rather than an opinion.
	put("RobloxComm/solo/sword_test.tsv",
		os.date("%Y-%m-%d %H:%M:%S") .. TAB
		.. (F.multiSword and "CYCLE" or "SINGLE") .. TAB
		.. tostring(F.swordsCarried or 0) .. TAB
		.. tostring(F.cycles or 0) .. TAB
		.. string.format("%.1f", dur) .. TAB
		.. string.format("%.0f", F.dmgSeen) .. TAB
		.. tostring(F.finishes) .. TAB
		.. tostring(F.swings or 0) .. TAB
		.. tostring(F.sword) .. NL)
	put("RobloxComm/solo/gate_test.tsv",
		os.date("%Y-%m-%d %H:%M:%S") .. TAB
		.. (F.gateOpen and "OPEN" or "SWORD") .. TAB
		.. string.format("%.2f", F.firstChestAt) .. TAB
		.. string.format("%.2f", F.firstKillFromDrop) .. TAB
		.. string.format("%.1f", dur) .. TAB
		.. string.format("%.1f", F.firstKill) .. TAB
		.. string.format("%.0f", F.dmgSeen) .. TAB
		.. tostring(F.finishes) .. TAB
		.. tostring(F.chests) .. TAB
		.. tostring(F.sword) .. TAB
		.. tostring(F.swordDmg) .. TAB
		.. tostring(F.swings or 0) .. TAB
		.. string.format("%.0f", F.hpTaken) .. NL)
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
	put("RobloxComm/solo/dwell_test.tsv",
		os.date("%Y-%m-%d %H:%M:%S") .. TAB
		.. string.format("%.2f", F.dwell or VIPER_DWELL) .. TAB
		.. tostring(F.swings) .. TAB
		.. string.format("%.0f", F.dmgSeen) .. TAB
		.. string.format("%.2f", (F.swings or 0) > 0 and (F.dmgSeen / F.swings) or 0) .. TAB
		.. tostring(F.finishes) .. TAB
		.. tostring(F.clock) .. TAB
		.. tostring(F.clockAtFirstKill) .. TAB
		.. string.format("%.0f", F.hpTaken) .. TAB
		.. tostring(F.tps) .. TAB
		.. tostring(F.skippedNoUnder) .. NL)
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
		-- Same clock as the SOLO_PLAY panel now: count from the drop when there
		-- is one, so the two panels never disagree by the length of a countdown.
		local base = (F.dropAt or 0) > 0 and F.dropAt or F.roundStart
		local t = (base > 0 and inMatch()) and (os.clock() - base) or 0
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
			.. "   next " .. tostring(F.rank or "-")
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
				.. "   whitelisted " .. tostring(F.friends or 0)
				.. "   not mine " .. tostring(F.notMine or 0)
				.. "   saved " .. tostring(F.saved or "-"))
		lbl.err.TextColor3 = F.err ~= "" and Color3.fromRGB(224, 145, 129) or Color3.fromRGB(162, 147, 127)
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
	soloSweep("SoloFarm", nil)
	env.__SOLOFARM_GUI = nil
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
		-- REMEMBER THAT HE PRESSED IT.
		--
		-- 2026-08-24, his words: "fixing the auto farm that scirpt beucae i clcik
		-- it it sotp, it didnt really sotp".
		--
		-- The cause is the AUTO watchdog near line 2964. I first wrote here that
		-- it runs every 0.4 seconds; it does not, and the correction matters for
		-- anyone reading this later. It sits INSIDE the round-change block, so it
		-- fires once per round: press STOP, the farm really does stop, and then
		-- about twenty five seconds later the next round begins and AUTO puts it
		-- straight back to work. Same complaint, slower clock - and worse to
		-- diagnose, because the button looks like it worked at the time.
		--
		-- The watchdog exists to restart a farm that fell over by itself, and
		-- that job is still worth doing. It just has no business overruling a
		-- hand on the button. So the press records who did it, and START clears
		-- it again.
		F.byHand = not F.on
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

	-- The three labels are locals in here, so the follower cannot reach them
	-- directly. Hand it a closure instead. No new control, no moved control.
	F.refreshBtns = function()
		pcall(function()
			btnRun.Text = F.on and "STOP" or "START"
			btnAuto.Text = F.auto and "AUTO ON" or "AUTO OFF"
			btnMode.Text = F.mode .. (F.mode == "FRAME" and (" " .. F.frames) or "")
		end)
	end

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

task.spawn(function()
	for _ = 1, 4 do
		task.wait(2)
		if not alive() then return end
		pcall(soloSweep, "SoloFarm", env.__SOLOFARM_GUI)
	end
end)

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

				-- NO EM LEFT: THE LOSER WALKS INTO THE VOID.
				--
				-- His words, 2026-08-24 04:1x: "all bot at the sver should jsut go to
				-- void, as that while dropping to void it will random luck, whcih mean
				-- who got killed by the void, then another guy win top 1, or jsut the
				-- bot done killl the antoehr bot before the both bot get into void".
				--
				-- EVERY bot drops, not just the loser. His correction, 2026-08-24
				-- 04:3x: "na wrong, it should be all bot dorped".
				--
				-- I had the draw's pick stay safe on the map, which quietly turned his
				-- luck into my rule. He wants the void to decide: everyone goes in,
				-- whoever it takes first loses, and whoever is still alive takes top 1.
				-- The other way it ends is one bot killing the other on the way down,
				-- which is why the swing below runs before the drop.
				do
					local tm = env.__SOLOTEAM
					if tm and tm.freeForAll then
						F.phase = "free for all - into the void"
						F.target = "none"
						local rr = myRoot()
						if rr then
							for _, foe in ipairs(living()) do
								if (foe.root.Position - rr.Position).Magnitude <= STRIKE_RANGE then
									strike(foe.p, true)
									F.swings = (F.swings or 0) + 1
									break
								end
							end
							hop(Vector3.new(rr.Position.X, (mapFloor or -30) - 60, rr.Position.Z), false)
						end
						task.wait(0.2)
						return
					end
				end

				local _, dmg = swordNow()
				F.tpAllowed = GATE_OPEN or (dmg >= GOOD_ENOUGH)

				-- His rule: tier four, get diamond or onyx, THEN teleport to a
				-- man. There is no timer that unlocks it and no round state that
				-- unlocks it - only the sword does.
				-- BARE HANDS ARE NOT A WEAPON.
				--
				-- The open arm was written as "fight from the first second instead
				-- of looting", and it read that as "never loot while anyone is
				-- alive" - including when we are carrying nothing at all. Round
				-- 2344 is what that looks like: sword none(0), 16 tier 4 chests
				-- untouched, 332 swings, 0 kills, 75 seconds. Fighting with an
				-- empty hand is not fighting, so no sword still means go and get
				-- one, in either arm.
				if dmg < GOOD_ENOUGH and (dmg <= 0 or not (GATE_OPEN and #living() > 0)) then
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
									if (foe.root.Position - rf.Position).Magnitude <= STRIKE_RANGE then
										strike(foe.p, true)
										F.swings = (F.swings or 0) + 1
										F.freeSwings = F.freeSwings + 1
										break
									end
								end
							end
							local r2 = myRoot()
							if r2 and (c.pos - r2.Position).Magnitude <= CHEST_REACH then
								-- ARRIVING IS NOT OPENING.
								--
								-- 2026-08-24, his words: "i only tleptined before hte
								-- countdonw, after countdonw jsut think i alreayd open
								-- and ingore that ... i dind topen 5 chest in the 12
								-- studs that hvaing manty chest, it jsut might missed
								-- the backlsword".
								--
								-- He is exactly right. This used to claim the entire pile
								-- the instant the body was inside CHEST_REACH, before the
								-- wait loop below had even looked. Land on a pile during
								-- the countdown, when the server will not open anything,
								-- and all five chests were struck off for the rest of the
								-- round - including whichever one held the onyx.
								--
								-- The chest itself carries the truth: ChestOpened. So
								-- nothing is claimed here any more. The wait loop runs,
								-- and afterwards only the ones that really opened are
								-- marked. Attempts are counted so a pile that genuinely
								-- refuses cannot become an endless loop.
								for _, m in ipairs(cluster.members) do
									chestTries[m.inst] = (chestTries[m.inst] or 0) + 1
								end
								local t0 = os.clock()
								-- TWO DIFFERENT SWORDS IS WHAT UNLOCKS THE FAST KILL.
								--
								-- Measured 22:43, seven kills in one round: hold = 1.25,
								-- 1.29, 1.32, 1.33, 1.35, 1.40, 1.48. Median 1.33 and
								-- nothing under 1.1. That spread is far too tight to be
								-- luck - it is four hits against a fixed server cooldown,
								-- about 0.44s between the ones the server books.
								--
								-- cycleStrike exists to beat exactly that: it declares a
								-- different sword between hits so each one is booked on its
								-- own cooldown. It has never once fired, because it needs
								-- `#swordsCarried() >= 2` and swordsCarried DEDUPES BY NAME
								-- - two Diamond Swords count as one. sword_test.tsv agrees:
								-- every round reads CYCLE 1 0, one sword carried, zero
								-- cycles.
								--
								-- Tier 4 is 81% Diamond and 19% Onyx, so a second chest is
								-- usually a second sword but not usually a DIFFERENT one.
								-- Two extra chests is about 0.6 to 1.2 seconds; if cycling
								-- takes even 0.2s off each of seven kills it pays for
								-- itself. If sword_test still reads CYCLE 1 next round,
								-- this idea is wrong and the two chests come back out.
								local haveSword = {}
								local extraForSecond = 0
								local todo = {}
								for _, m in ipairs(cluster.members) do
									local already = false
									pcall(function()
										already = m.inst:GetAttribute("ChestOpened") == true
									end)
									if not already then todo[#todo + 1] = m.inst end
								end
								for idx, inst in ipairs(todo) do
									if not alive() or not F.on or F.rescuing then break end
									local budgetLeft = CHEST_CLUSTER_BUDGET - (os.clock() - t0)
									if budgetLeft <= 0 then break end
									-- One reply is ~0.3s, so 0.6 is a full round trip plus headroom
									-- and there is no reason to ever wait longer than that on one
									-- chest. takeChest returns the instant the contents arrive, so
									-- this is a ceiling that a healthy chest never reaches.
									local slice = (budgetLeft < 0.6) and budgetLeft or 0.6
									local c0 = os.clock()
									local ok, _took, gotDmg, gotName = takeChest(inst, slice)
									F.chestOpens = (F.chestOpens or 0) + 1
									if ok then
										F.chestOk = (F.chestOk or 0) + 1
										chestFails = 0
										setChestSteal(false)
									else
										chestFails = chestFails + 1
										if chestFails >= 5 then setChestSteal(true) end
									end
									F.chestMs = math.floor((os.clock() - c0) * 1000)
									local rr = myRoot()
									if rr then pcall(function() rr.AssemblyLinearVelocity = Vector3.zero end) end
									-- The chest reply is the fastest truth there is. Only fall back
									-- to reading the hotbar when this chest gave us nothing.
									if gotName then haveSword[gotName] = true end
									local kinds = 0
									for _ in pairs(haveSword) do kinds = kinds + 1 end
									F.swordKinds = kinds
									if (gotDmg or 0) >= GOOD_ENOUGH then
										F.swordFromChest = gotDmg
										-- Two KINDS is the bar, not two swords.
										if kinds >= 2 then break end
										extraForSecond = extraForSecond + 1
										if extraForSecond > 2 then break end
									end
									local _, d2 = swordNow()
									if d2 >= GOOD_ENOUGH then break end
								end
								-- OPENING A CHEST IS NOT THE SAME AS GETTING WHAT IS IN IT.
								--
								-- 22:59, round at 166 SECONDS: chests=4, chestOk=4/13, T4=0,
								-- sword=none(0). Four tier 4 chests opened successfully and
								-- not one sword came out - and tier 4 is 81% Diamond, so four
								-- empty ones is a 0.13% event, not luck. Our openChest is
								-- being answered but updateChest is not actually taking the
								-- items, and because our own success rate looked healthy the
								-- five-failure rule never handed the job back to Vape. The
								-- chest is now marked opened, so ChestSteal will not touch it
								-- either, and the bot stands there with no sword while Viper
								-- is on the map - which is the "keeps at the top" he saw.
								--
								-- The honest test is not "did the call succeed", it is "am I
								-- holding a sword". If chests have been opened this round and
								-- there is still nothing in hand, hand the job to Vape now.
								do
									local _, dNow = swordNow()
									if dNow <= 0 and (F.chestOpens or 0) >= 2 then
										setChestSteal(true)
										F.chestOwnerWhy = "opened chests, still no sword"
									end
								end
								F.clusterMs = math.floor((os.clock() - t0) * 1000)
								pcall(function()
									put("RobloxComm/solo/chestspeed.tsv",
										os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
										.. tostring(game.JobId):sub(1, 8) .. string.char(9)
										.. tostring(#todo) .. string.char(9)
										.. tostring(F.clusterMs) .. string.char(9)
										.. tostring(F.chestMs or -1) .. string.char(9)
										.. tostring(F.chestOk or 0) .. "/" .. tostring(F.chestOpens or 0)
										.. string.char(10))
								end)
								-- Now mark what actually opened, and only that.
								for _, m in ipairs(cluster.members) do
									local realOpen = false
									pcall(function()
										realOpen = m.inst:GetAttribute("ChestOpened") == true
									end)
									if realOpen and not visited[m.inst] then
									if F.firstChestAt == 0 and F.dropAt > 0 then
										F.firstChestAt = os.clock() - F.dropAt
									end
										visited[m.inst] = true
										F.chests = F.chests + 1
									elseif not realOpen and (chestTries[m.inst] or 0) >= CHEST_MAX_TRIES then
										-- Tried it enough times in a live round. Give up on
										-- this one rather than orbit it for ever, and say so
										-- in the count so it is visible.
										visited[m.inst] = true
										F.chestsGivenUp = (F.chestsGivenUp or 0) + 1
									end
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
								-- Same rule as the pile above: only the chest's own
								-- ChestOpened attribute may strike it off the list.
								local realOpen = false
								pcall(function()
									realOpen = c.inst:GetAttribute("ChestOpened") == true
								end)
								if realOpen then
									visited[c.inst] = true
									F.chests = F.chests + 1
									F.freeChests = F.freeChests + 1
								end
							end
							break
						end
					end
				end

				-- The end he wrote himself: "after donekill all em then waht?, it
				-- will instead all bot togher go to t he middle to klll each
				-- others of couse that i cant fix beucase that was luck deiced
				-- which bot srruvie".
				--
				-- SOLO_TEAM drops the whitelist when the last em dies, so the
				-- teammates are already back in the target list by the time this
				-- runs. All that is left is the walk. The middle is the origin -
				-- measured on this map, the map SpawnLocation is (0, 19.5, 0) and
				-- the centroid of all 26 tier four chests is (0, 7, 0).
				do
					local mid
					pcall(function()
						if env.__SOLOTEAM_MIDDLE then mid = env.__SOLOTEAM_MIDDLE() end
					end)
					if mid then
						local rm = myRoot()
						if rm and (mid - rm.Position).Magnitude > 45 then
							F.phase = "free for all - walking to the middle"
							F.target = string.format("middle %.0f,%.0f,%.0f", mid.X, mid.Y, mid.Z)
							hop(mid, false)
							task.wait(0.15)
							return
						end
					end
				end

				-- VIPER IS IN THIS SERVER: ARM FIRST, FIGHT SECOND.
				--
				-- His order, 2026-08-24: "while detect viper was not at the sver
				-- then keep farming in nromal, and also if detect viper tje acount
				-- then we will trying to get blakc sowrd and psotiton for protect".
				-- So this is not the trap. With no rival in the server nothing
				-- below fires and the farm behaves exactly as it always has.
				--
				-- Why keeping clear while unarmed is the whole fix for "my bots
				-- keep getting killed": both sides carry the same 100 health and
				-- the same 0.4s DAMAGE_COOLDOWN, so a duel is four landing hits
				-- either way and it is decided by who is already swinging. Below
				-- GOOD_ENOUGH we cannot win that trade and we are not even allowed
				-- to teleport to him, so standing in his reach is a free death -
				-- exactly the 07:21:43 round, 25 seconds and 83 swings for 0
				-- damage while men we could not hurt walked through us.
				--
				-- The distance is measured, not chosen. Across 2073 frames of him
				-- the whole engagement envelope is -15.4 to +10.6 studs vertically
				-- and the server needs 9 studs to land damage, so 30 above is
				-- twice outside anything he has ever done.
				--
				-- Once the sword is good enough this branch stops firing and the
				-- lock-on in pickLowest takes him as the target nothing outranks.
				if (F.vipNext or 0) < os.clock() then
					F.vipNext = os.clock() + 0.5
					local found = nil
					for _, t in ipairs(living()) do
						if isBlack(t.p) then found = t break end
					end
					F.viperHere = found and found.p.Name or nil
					F.viperY = found and found.y or nil
				end
				if F.viperHere and (F.swordDmg or 0) < GOOD_ENOUGH then
					local rm = myRoot()
					if rm and F.viperY then
						local gap = rm.Position.Y - F.viperY
						F.phase = string.format("VIPER HERE and my sword is %d - keeping clear",
							F.swordDmg or 0)
						F.target = "keep clear of " .. tostring(F.viperHere)
						if gap < 30 then
							hop(Vector3.new(rm.Position.X, F.viperY + 32, rm.Position.Z), false)
						end
						if (F.vipLog or 0) < os.clock() then
							F.vipLog = os.clock() + 3
							pcall(function()
								put("RobloxComm/solo/viper_present.tsv",
									os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
									.. tostring(game.JobId):sub(1, 8) .. string.char(9)
									.. tostring(F.viperHere) .. string.char(9)
									.. "unarmed" .. string.char(9)
									.. tostring(F.sword or "none") .. string.char(9)
									.. tostring(F.swordDmg or 0) .. string.char(9)
									.. string.format("%.1f", gap) .. string.char(9)
									.. string.format("%.0f", hpOf(game.Players.LocalPlayer) or -1) .. string.char(10))
							end)
						end
						task.wait(0.1)
						return
					end
				elseif F.viperHere and (F.vipLog or 0) < os.clock() then
					F.vipLog = os.clock() + 3
					pcall(function()
						put("RobloxComm/solo/viper_present.tsv",
							os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
							.. tostring(game.JobId):sub(1, 8) .. string.char(9)
							.. tostring(F.viperHere) .. string.char(9)
							.. "ARMED - engaging" .. string.char(9)
							.. tostring(F.sword or "none") .. string.char(9)
							.. tostring(F.swordDmg or 0) .. string.char(9)
							.. "-" .. string.char(9)
							.. string.format("%.0f", hpOf(game.Players.LocalPlayer) or -1) .. string.char(10))
					end)
				end

				-- TRAP MODE. His test, 2026-08-24: sit 100 studs above the rival
				-- and see whether he ever comes up, and whether a round with a
				-- survivor he cannot reach simply never ends.
				--
				-- The data says the idea is sound. Across 2073 frames of him, the
				-- most he has EVER been above one of us is 10.6 studs, and every
				-- one of the 60 moments we actually lost health with him inside
				-- 20 studs sits between -15.4 and +10.6 vertically. A hundred
				-- studs is six times outside anything he has ever done, and by
				-- his own rule - "you don't want to go up" - we would also sort
				-- last in his target list, because he takes lowest Y first.
				--
				-- It is a trap and not a defence, and the difference matters: we
				-- cannot stop him teleporting. His movement is a CFrame write on
				-- his own machine and we have no server authority over another
				-- client. What we can do is be the least attractive target on his
				-- list and stay outside the 9 studs the server needs for damage.
				--
				-- No new button: it is armed by the presence of a file, so it can
				-- be turned on and off without touching his panel. Put a number
				-- in the file to change the height.
				if (F.trapNext or 0) < os.clock() then
					F.trapNext = os.clock() + 2
					local on, h = false, 100
					pcall(function()
						if isfile("RobloxComm/solo/trap.txt") then
							on = true
							local v = tonumber((readfile("RobloxComm/solo/trap.txt"):gsub("%s", "")))
							if v and v >= 10 and v <= 3000 then h = v end
						end
					end)
					F.trapOn, F.trapH = on, h
				end
				if F.trapOn then
					local rm = myRoot()
					if rm then
						local list = living()
						local topY, topName, nearest = nil, "-", nil
						for _, t in ipairs(list) do
							if topY == nil or t.y > topY then topY = t.y topName = t.p.Name end
							local d = (t.root.Position - rm.Position).Magnitude
							if nearest == nil or d < nearest then nearest = d end
						end
						local base = topY or rm.Position.Y
						F.phase = string.format("TRAP - holding %.0f above the highest man", F.trapH or 100)
						F.target = "trap over " .. tostring(topName)
						hop(Vector3.new(rm.Position.X, base + (F.trapH or 100), rm.Position.Z), false)
						if (F.trapLog or 0) < os.clock() then
							F.trapLog = os.clock() + 2
							pcall(function()
								put("RobloxComm/solo/trap.tsv",
									os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
									.. tostring(game.JobId):sub(1, 8) .. string.char(9)
									.. string.format("%.1f", rm.Position.Y) .. string.char(9)
									.. string.format("%.1f", topY or -999) .. string.char(9)
									.. string.format("%.1f", rm.Position.Y - (topY or 0)) .. string.char(9)
									.. string.format("%.1f", nearest or -1) .. string.char(9)
									.. tostring(#list) .. string.char(9)
									.. string.format("%.0f", hpOf(game.Players.LocalPlayer) or -1) .. string.char(9)
									.. string.format("%.1f", os.clock() - (F.roundStart or os.clock())) .. string.char(10))
							end)
						end
					end
					task.wait(0.1)
					return
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
					F.dropAt = 0 F.firstChestAt = 0 F.firstKillFromDrop = 0
					F.voidCatches = 0 F.clamped = 0 F.dropped = 0 F.tpAllowed = false F.rescueTier = false
					F.swings = 0 F.skippedNoUnder = 0 F.afkEvents = 0
					combatCeiling = nil F.ceiling = nil F.bandLifts = 0
					MAX_CLIMB = 10
					queuedEarly = false F.eqId = nil F.eqHp0 = nil F.eqT0 = nil
					F.gaveUp = false F.nudges = 0 F.finishHolds = 0 F.bailed = false
					F.penRescues = 0
					F.earlyQueue = "-"
					F.tps = 0 F.leavers = 0
					F.dmgSeen = 0 F.dmgWindows = 0 F.dmgHits = 0 F.finishes = 0 F.prevFinishAt = 0
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
					burstIndex = (burstIndex % #BURSTS) + 1
					BURST = BURSTS[burstIndex]
					F.burst = BURST
					F.below = BELOW
					-- PICK THE DWELL FROM THE JOB ID, NOT FROM A COUNTER.
					--
					-- A counter on F was the obvious way and it is wrong here. This
					-- client rejoins on every single round - generation 96 to 140 in
					-- one stretch this morning - and a rejoin builds a new Luau VM,
					-- so F is new, F.dwellIndex is nil, and ((nil or 0) % 3) + 1 is
					-- 1 every time. The set would have looked like it was cycling
					-- while sitting on 0.2 for ever, which is the worst kind of
					-- broken experiment: it produces a full table of results that
					-- all came from one arm.
					--
					-- The JobId is the one thing that changes per round and is the
					-- same for every bot in that round, and rollWinner already uses
					-- it for exactly this reason. Uniform over servers, needs no
					-- state to survive the rejoin, and two bots in one server pick
					-- the same arm so the round is not a mixture.
					local dhex = tostring(game.JobId):gsub("[^0-9a-f]", "")
					local dseed = tonumber(dhex:sub(-6), 16) or 0
					-- THE DWELL A/B IS OVER. 0.40 WON.
					--
					-- It looked flat for weeks because it was being judged on
					-- damage per round, and damage per round IS flat - leaving a
					-- man early does not destroy the swing, it just spends it on
					-- somebody else. Judged on FINISHES, over 825 rounds:
					--
					--   dwell 0.20   mean 4.18 kills   32% of rounds reached 6+
					--   dwell 0.40   mean 4.73 kills   44% of rounds reached 6+
					--   dwell 0.60   mean 4.23 kills   31% of rounds reached 6+
					--
					-- and kills per 100 damage went 0.72, 0.83, 0.77 the same way.
					--
					-- The reason is arithmetic. The server's damage window is about
					-- 0.4s, so a 0.2s dwell guarantees we walk away BEFORE a second
					-- hit on that body is even possible - every visit is worth one
					-- hit and the four hits a man costs get spread over four trips.
					-- 0.6s is the other error: the window has already reopened and
					-- we are standing there not using it.
					--
					-- Matching the dwell to the window is what closes the gap he is
					-- chasing: four hits at 0.37s is 1.1 seconds, and eight kills in
					-- the record were exactly that.
					-- AND IT KEEPS PROBING, BECAUSE HE MOVES.
					--
					-- His words the same day: "viper was can able any time
					-- fchaning it more and upgrading". A number tuned against
					-- today's opponent and then frozen is a number that goes
					-- wrong quietly. So four rounds in five run the winner and
					-- the fifth tries a neighbour - if the real window ever
					-- shifts, dwell_test.tsv shows it instead of him noticing.
					local dprobe = math.floor(dseed / 12) % 10
					VIPER_DWELL = (dprobe == 0 and 0.3) or (dprobe == 1 and 0.5) or 0.4
					F.dwell = VIPER_DWELL
					-- THE GATE EXPERIMENT IS OVER AND HIS ORIGINAL RULE WINS.
					--
					-- 2026-08-24, after watching round 2344: "it should wait to
					-- until i get the sword". He is right and the round proves it.
					-- Forcing the gate open made tpAllowed true with no sword, and
					-- tpAllowed is also what arms the dry nudge, so the farm spent
					-- 75 seconds teleporting at people and swinging an empty hand
					-- while 16 tier four chests sat untouched.
					--
					-- The lesson is not about the gate, it is that tpAllowed was
					-- carrying two meanings at once - "may I go to a man" and "am I
					-- armed". Opening it for one purpose silently opened it for the
					-- other. Wait for the sword.
					GATE_OPEN = false
					F.gateOpen = GATE_OPEN
					-- He carries two swords now and asked for both remotes to go
					-- every time, so this is no longer half the rounds. The natural
					-- experiment is still there: sword_test.tsv records how many
					-- swords were carried, so one-sword rounds are the control.
					MULTI_SWORD = true
					F.multiSword = MULTI_SWORD
					F.cycles = 0 F.swordsCarried = 0
					F.tpErrSum = 0 F.tpErrN = 0 F.tpErrMax = 0
					F.viaMobile = 0 F.viaFire = 0
					F.killBase = myKills()
					-- THIS MUST NOT WRITE THE SETTINGS FILE.
					--
					-- 2026-08-24, and it is my bug from an hour ago. Once every client
					-- started following the shared file, this line became a second
					-- writer - and a writer that broadcasts its own whole config, not
					-- the change it meant. He turned AUTO off on one panel, a different
					-- client whose memory still held auto=true reached this line, saved,
					-- and put auto=true back in the file for everybody. From his side
					-- AUTO switched itself on again for no reason.
					--
					-- Turning the farm back on here is local recovery, not something he
					-- pressed, so it stays in memory and never touches the file. The file
					-- now means exactly one thing: the last button he actually pressed.
					if F.auto and not F.on and not F.byHand then F.on = true F.err = "" end
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
	while alive() do
		task.wait(0.25)
		pcall(paint)
		if (F.syncNext or 0) < os.clock() then
			F.syncNext = os.clock() + 1
			-- syncCfg is deliberately NOT called any more. Each panel owns its own
			-- client and nothing follows anybody else. See CFG_FILE above.
		end
	end
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

-- WILL I KILL HIM BEFORE THE MATCHMAKER MOVES ME? THAT IS THE WHOLE DECISION.
--
-- 2026-08-24, his report: "only kille to 50 then jsut going to start game that
-- was suck beucae th waw as a hacker, the bot dindt done kill the hacker yet".
-- Then, on the first fix: "u cant do that that will be suck, it should be auto
-- smart detectin". He is right - waiting for the man to fall throws away the
-- head start that this whole check exists to buy.
--
-- Both numbers are measured, not chosen:
--
--   the pull-out - queue sent mid fight to landing in the next round, from
--   afk.log against each account's timeline: 2, 2, 4, 4, 4, 4 seconds.
--
--   the finish - armed to the last man being down, seventeen samples the same
--   night: 1 or 2 seconds, never more.
--
-- So it is close, and that is exactly why it went wrong only sometimes. A fixed
-- rule cannot answer it. What can is the question itself, asked every tenth of
-- a second: at the rate he is actually losing health, how long until he is
-- down, and is that inside the pull-out window?
--
--   under it   -> send now, and keep the speed he built this for
--   over it    -> hold, keep hitting, ask again in 0.1s
--
-- A tank, a healer or a hacker who is not losing health gives a time-to-kill of
-- infinity, so the queue never goes out and the round can never be handed to
-- him. A normal player on 30 hp gives well under a second and it fires at once.
--
-- The pull-out measures itself: every send writes the moment down, and the next
-- round start reads it back and keeps the running minimum in pullout.tsv.
local function earlyQueueCheck()
	if not F.on or not inMatch() or queuedEarly == "sent" then return end
	local foes = living()

	if F.pullOut == nil then
		F.pullOut = 2.0
		pcall(function()
			if not isfile("RobloxComm/solo/pullout.tsv") then return end
			local mn
			for line in readfile("RobloxComm/solo/pullout.tsv"):gmatch("[^\n]+") do
				local v = tonumber(line:match("([%d%.]+)%s*$"))
				-- Only a real pull-out counts. A send is followed by our own
				-- spacing wait in SOLO_PLAY - 5s for bot 2, 10s for bot 3 - so a
				-- 14 second gap is that wait plus the matchmaker, not the danger
				-- window. Anything past 8 is thrown away and the minimum of what
				-- is left is used, because being early here is what loses rounds.
				if v and v >= 1 and v <= 8 and (not mn or v < mn) then mn = v end
			end
			if mn then F.pullOut = math.max(1.5, math.min(4, mn)) end
		end)
	end

	local function send(why)
		queuedEarly = "sent"
		F.earlyQueue = "sent"
		F.eqWhy = why
		pcall(function()
			writefile("RobloxComm/solo/pullout_pending.txt",
				tostring(os.time()) .. "|" .. tostring(game.JobId))
		end)
		-- OFF THIS THREAD.
		--
		-- SOLO_PLAY's queueNow waits (num-1)*5 seconds so three map loads do not
		-- land together, then polls isInQueue for up to two more. Called straight
		-- from here that froze this 0.1s self check for five to twelve seconds,
		-- and this thread also carries the AFK ladder, the dry nudge and the
		-- rescue - so the farm went deaf at the exact moment it mattered.
		local fn = env.__SOLOPLAY_QUEUE or env.__SOLOFARM_QUEUE
		if fn then task.spawn(function() pcall(fn, "early: " .. why) end) end
		local TAB, NL = string.char(9), string.char(10)
		put("RobloxComm/solo/afk.log",
			os.date("%Y-%m-%d %H:%M:%S") .. TAB
			.. string.format("r%03d", F.round) .. TAB
			.. string.format("%.1fs", F.roundStart > 0 and (os.clock() - F.roundStart) or 0) .. TAB
			.. "early queue sent" .. TAB .. why .. NL)
	end

	-- He is already down. Nothing left to weigh.
	if #foes == 0 then
		if queuedEarly == "armed" then send("last man is down") end
		return
	end

	if #foes ~= 1 then
		F.eqWhy = "not the last man (" .. #foes .. " left)"
		F.eqId = nil
		return
	end

	local t = foes[1]
	local hp = hpOf(t.p)
	if hp == nil then F.eqWhy = "no health reading" return end

	-- His four conditions still choose when this starts thinking at all.
	if hp > EARLY_QUEUE_HP then
		F.eqWhy = string.format("last man still on %.0f hp", hp)
		F.eqId = nil
		return
	end
	if (os.clock() - (F.lastLandT or 0)) > 1.0 then F.eqWhy = "not landing hits on him" return end
	local r = myRoot()
	if not r then F.eqWhy = "no body" return end
	local d = (t.root.Position - r.Position).Magnitude
	if d > NEAR_LAST then F.eqWhy = string.format("too far from him (%.0f studs)", d) return end

	-- Start the clock on this man the first time he qualifies.
	if F.eqId ~= t.p.UserId then
		F.eqId = t.p.UserId
		F.eqHp0 = hp
		F.eqT0 = os.clock()
		queuedEarly = "armed"
		F.earlyQueue = "armed"
		local TAB, NL = string.char(9), string.char(10)
		put("RobloxComm/solo/afk.log",
			os.date("%Y-%m-%d %H:%M:%S") .. TAB
			.. string.format("r%03d", F.round) .. TAB
			.. string.format("%.1fs", F.roundStart > 0 and (os.clock() - F.roundStart) or 0) .. TAB
			.. "early queue watching" .. TAB
			.. string.format("%s on %.0f hp, %.0f studs, pull-out measured at %.1fs",
				tostring(t.p.Name), hp, d, F.pullOut) .. NL)
	end

	local span = os.clock() - (F.eqT0 or os.clock())
	local lost = (F.eqHp0 or hp) - hp

	-- Half a second of evidence before a rate means anything.
	if span < 0.5 then F.eqWhy = string.format("watching %s, %.0f hp", tostring(t.p.Name), hp) return end

	if lost <= 0 then
		-- Not losing health. Tank, heal, or a hacker. The queue stays in.
		F.eqWhy = string.format("%s not losing health in %.1fs - holding the queue", tostring(t.p.Name), span)
		-- Re-base so a heal does not poison the rate for the rest of the round.
		if span > 2.0 then F.eqHp0 = hp F.eqT0 = os.clock() end
		return
	end

	local dps = lost / span
	local ttk = hp / dps

	-- 0.4s of margin: one send, one round trip, one last swing.
	if ttk + 0.4 <= F.pullOut then
		send(string.format("%s on %.0f hp, %.1f dps, dead in %.1fs inside a %.1fs pull-out",
			tostring(t.p.Name), hp, dps, ttk, F.pullOut))
	else
		F.eqWhy = string.format("%s needs %.1fs at %.1f dps, pull-out is %.1fs - holding",
			tostring(t.p.Name), ttk, dps, F.pullOut)
	end
end

-- The pull-out is not a constant I picked, it is a thing this farm times.
-- Every send writes the second it happened; the next round start reads it back,
-- and the gap between the two is how long the matchmaker took to move us.
task.spawn(function()
	task.wait(2)
	pcall(function()
		if not isfile("RobloxComm/solo/pullout_pending.txt") then return end
		local raw = readfile("RobloxComm/solo/pullout_pending.txt")
		local at, job = raw:match("^(%d+)|(.*)$")
		if delfile then pcall(delfile, "RobloxComm/solo/pullout_pending.txt")
		else pcall(writefile, "RobloxComm/solo/pullout_pending.txt", "") end
		if not at or job == tostring(game.JobId) then return end
		local gap = os.time() - tonumber(at)
		if gap < 1 or gap > 8 then return end
		put("RobloxComm/solo/pullout.tsv",
			os.date("%Y-%m-%d %H:%M:%S") .. string.char(9) .. tostring(gap) .. string.char(10))
	end)
end)


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
			-- THE PEN EXEMPTION HAD NO CLOCK ON IT, AND THAT IS THE WHOLE BUG.
			--
			-- 23:14 measured: y=153, phase "in the pen, waiting for the drop",
			-- 131 SECONDS into the round, sword DiamondSword(29), tp=true,
			-- finishes=4, nearest man 249 studs away, afkStep "pen". It had
			-- already dropped, already killed four men, and then ended up back on
			-- the holding platform - and this one line said "pen is fine" and
			-- returned before every check below it, including the two hard stops
			-- added an hour ago. The 0.1s tracker was running the whole time and
			-- was structurally forbidden from noticing.
			--
			-- Before the drop the pen is the rule. AFTER the drop, being up here
			-- is never right: F.dropAt is reset to 0 every round, so dropAt > 0
			-- plus pen height can only mean something threw us back up.
			if p.Y >= LOBBY_Y then
				if A.penSince == nil then A.penSince = os.clock() end
				local penFor = os.clock() - A.penSince
				local afterDrop = (F.dropAt or 0) > 0
				if afterDrop or penFor > 20 then
					F.afkStep = afterDrop and "PEN AFTER DROP - getting out"
						or string.format("PEN %.0fs - countdown is long over", penFor)
					F.penRescues = (F.penRescues or 0) + 1
					if (F.penLog or 0) + 3 < os.clock() then
						F.penLog = os.clock()
						afkLog(string.format(
							"STUCK IN THE PEN: y=%.0f for %.0fs, dropped=%s, sword=%s, going back down",
							p.Y, penFor, tostring(afterDrop), tostring(F.sword)))
					end
					local goal = nil
					pcall(function()
						local cl = bestChestCluster()
						if cl then goal = cl.centre + Vector3.new(0, 3, 0) end
					end)
					if not goal then
						local foes = living()
						if #foes > 0 and foes[1].root then
							goal = foes[1].root.Position + Vector3.new(0, BELOW, 0)
						end
					end
					if not goal then goal = Vector3.new(0, (SAFE_Y or -40) + 12, 0) end
					pcall(function() hop(goal) end)
					A.pos = p
					return
				end
				A.since = 0 A.step = 0 F.afkStep = "pen"
				A.pos = p
				return
			end
			A.penSince = nil
			if F.dropAt == 0 and F.roundStart > 0 then F.dropAt = os.clock() end
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
			-- AND THE DRY NUDGE HAS TO KNOW THAT TOO.
			--
			-- This fired on F.tpAllowed alone, and the open arm forces that true,
			-- so with no sword it teleported to the nearest man every 0.4s and
			-- swung at him with nothing - while the keep-clear rule was pulling
			-- the other way. That tug of war is the y bouncing between 44 and 87
			-- in farm_live.log. If the hand is empty the dry answer is a chest,
			-- not a man.
			if (F.swordDmg or 0) <= 0 and F.dryFor > NUDGE_DRY and not F.rescuing then
				local cluster = bestChestCluster()
				if cluster then
					hop(cluster.centre + Vector3.new(0, 3, 0))
					A.lastDmg = os.clock() - NUDGE_DRY + 1.0
					F.nudges = (F.nudges or 0) + 1
					afkLog(string.format("nudge: dry %.1fs and no sword, went to a pile of %d chests",
						F.dryFor, #cluster.members))
				end
			-- AND IT MUST NOT FIGHT THE PIN FOR THE BODY.
			--
			-- pin holds a man for LOCK_SECS 2.0 while this check fires at 1.5,
			-- so the nudge used to teleport the body to a DIFFERENT man in the
			-- middle of every exchange and the pin dragged it straight back.
			-- 2026-08-24 19:01:41 to 19:01:50: ten nudges to five different
			-- names in nine seconds, 192 swings, 0 kills.
			elseif F.tpAllowed and (F.swordDmg or 0) > 0 and F.dryFor > NUDGE_DRY and not F.rescuing
				and (os.clock() - (F.pinBeat or 0)) > 0.35 then
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
						-- 0.4s was shorter than one landed hit. The record says the
						-- server books a hit about every 0.4s and the hop plus re-aim
						-- costs another 0.2, so the old grace period guaranteed the
						-- nudge re-fired before its own swing could ever be credited,
						-- which is the 0.4s repeat rate in afk.log.
						A.lastDmg = os.clock() - NUDGE_DRY + 1.0
						afkLog(string.format("nudge: dry %.1fs, went to nearest %s at %.0f studs",
							F.dryFor, near.p.Name, nd))
					end
				end
			end

			-- THE 0.1 SECOND CHECK NOW HAS THE POWER TO END A ROUND.
			--
			-- His words, 2026-08-24 23:0x: "if dtect was a coding, then this cmd
			-- will be the highest cmd it was a backup to mkaing sure the killing
			-- was ok ... to making sure the bot will done go to the player and
			-- dont killed ... i was using some misn over 5 mins to done kill the
			-- last pplayer?"
			--
			-- He is right that it was useless. The 22:59 round shows the check
			-- working perfectly and achieving nothing: quiet 0.9s, quiet 1.5s,
			-- quiet 1.9s, STUCK 2s, STUCK 3s, working - a label changing while the
			-- bot stood at y=41 for 166 seconds with 0 swings. Every rung of the
			-- rescue ladder was a dead end that round: re-read the sword (there is
			-- none), go to a tier 4 chest (T4 was 0, all opened), stand under a man
			-- (blocked, tpAllowed is false without a sword), get back on the map
			-- (already on it). Nothing above those rungs existed.
			--
			-- So two hard stops sit above the ladder now. They do not try to fix
			-- the round, they end it - a round we cannot swing in is already lost
			-- and the only cost that matters is the seconds spent standing in it.
			if not F.bailed and F.roundStart > 0 and inMatch() then
				local age = os.clock() - F.roundStart
				local why = nil
				if age > 40 and (F.swings or 0) == 0 then
					why = string.format("%.0fs into the round and not one swing thrown", age)
				elseif age > 25 and (F.swordDmg or 0) <= 0 then
					local _, t4left = countT4()
					if (t4left or 0) == 0 then
						why = string.format("%.0fs in, no sword and no tier 4 chest left to get one", age)
					end
				end
				if why then
					F.bailed = true
					pcall(function()
						put("RobloxComm/solo/bail.tsv",
							os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
							.. tostring(game.JobId):sub(1, 8) .. string.char(9)
							.. why .. string.char(9)
							.. "sword=" .. tostring(F.sword) .. string.char(9)
							.. "chests=" .. tostring(F.chests) .. string.char(9)
							.. "swings=" .. tostring(F.swings or 0) .. string.char(9)
							.. "finishes=" .. tostring(F.finishes or 0) .. string.char(10))
					end)
					afkLog("BAILED OUT: " .. why)
					local fn = env.__SOLOPLAY_QUEUE or env.__SOLOFARM_QUEUE
					if fn then pcall(fn, "bailed - " .. why) end
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
				-- Only worth a line if the quiet stretch actually reached the AFK
				-- threshold, or the ladder had already acted. Standing at a chest
				-- pile waiting for the opener is not AFK: not moving, not swinging,
				-- no kill and no chest are all true and all correct. Between 17:58
				-- and 18:45 that wrote 1428 of the 1616 step-0 recoveries, and
				-- because afkLog is what increments afkEvents, the ab_test column
				-- read 1425 events over 114 rounds - a count of log lines, not of
				-- stalls, which is the one thing that column is for.
				local quiet = A.since > 0 and (os.clock() - A.since) or 0
				if A.since > 0 and (A.step > 0 or quiet >= AFK_SECS) then
					afkLog(string.format("recovered after %.1fs at step %d", quiet, A.step))
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
			putRoll("RobloxComm/solo/players_live_" .. lp.Name .. ".log", table.concat(rows, NL) .. NL)
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
				putRoll("RobloxComm/solo/farm_live_" .. lp.Name .. ".log", line .. "\n")
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

-- ---------------------------------------------------------------- potions
--
-- OURS, NOT VAPE'S. His correction, 2026-08-24: "why the fuck u dont writee the
-- lfiesteal auto using on the my sciprt, why u need to care the fucking vape v4?
-- vape v4 was a coding that let u have idea might u didnt have think bro".
--
-- He is right. Vape's AutoConsume has the string "Shield" written into it and
-- nothing else, so LifeSteal - 2464 of them pulled out of tier four chests, and
-- tier four is the only tier that carries it - has been rotting in the hotbar
-- every round. Vape was worth reading for the shape of the trick. It was never
-- the place to put our own behaviour.
--
-- The trick, read out of the game's own power-up-controller: usePowerUp does
-- not take the potion as an argument. It drinks WHATEVER IS IN YOUR HAND, and
-- it only sends the remote once the drink animation has reached 90% of its
-- length. So the honest sequence is hold it, send, put the sword back - and
-- sending it ourselves skips the animation wait the game imposes on players.
--
--   Events["8dd94a0e-0dd9-409c-8847-de1054173265"]:FireServer(potionName)
--   Events["19099ce9-58cc-4e1a-9616-52e6e88ad8f4"]:FireServer()   no arguments
--   Events["8dd94a0e-0dd9-409c-8847-de1054173265"]:FireServer(swordName)
--
-- m32:hasPowerUp(name) says whether it is already running, so we never waste a
-- second bottle on an effect that is still live.
-- LIFTED OUT OF THE TASK.SPAWN BELOW, 2026-08-24, found by luau-lsp.
--
-- dep was declared inside the drink loop's closure. A SECOND task.spawn further
-- down - the one that reads the hotbar and puts armour on - calls dep() too, and
-- from there dep is a nil GLOBAL, not this function. That call sits inside a
-- pcall, so every tick it threw "attempt to call a nil value" and was swallowed:
-- the whole auto-armour and hotbar read has never run once.
--
-- luaqc could not see it, because luaqc only tracks TOP LEVEL locals and this
-- one lived a closure deep. luau-lsp with the real Roblox definitions does.
local function dep(id)
	local ok, v = pcall(function()
		local RS = game:GetService("ReplicatedStorage")
		local Flamework = require(RS.rbxts_include.node_modules["@flamework"].core.out).Flamework
		return Flamework.resolveDependency(id)
	end)
	return ok and v or nil
end

task.spawn(function()
	local USE_EVENT = "19099ce9-58cc-4e1a-9616-52e6e88ad8f4"
	local WANT = { "LifeSteal", "Shield", "SpeedBoost", "JumpBoost" }

	-- DO NOT TAKE THE SWORD OUT OF HIS HAND.
	--
	-- His correction, 2026-08-24: "it sould be auto use and nto fucking swtihc
	-- that bro, beucase it should let me keep using the sowrd". He is right, and
	-- setActiveSlot was the wrong door - it walks the whole client path, swaps
	-- the visible tool, restarts the idle animation and leaves Killaura swinging
	-- at nothing for those frames.
	--
	-- The server never sees a slot. It sees one remote saying what we hold:
	--   8dd94a0e-0dd9-409c-8847-de1054173265   here is my held item
	--   19099ce9-58cc-4e1a-9616-52e6e88ad8f4   drink what I am holding, no args
	-- so we tell it "potion", drink, tell it "sword" again. Three fires, no slot
	-- change, no animation, the sword never leaves his hand on screen and the
	-- swing loop never pauses. The game makes real players wait for 90% of a
	-- drink animation before it sends the second one; we do not.
	local function drink(hb, pu, ev, name, slot, backTo, holdEv, swordName)
		if not holdEv then return false end
		pcall(function() holdEv:FireServer(name) end)
		task.wait(0.03)
		pcall(function() ev:FireServer() end)
		task.wait(0.03)
		if swordName then pcall(function() holdEv:FireServer(swordName) end) end
		F.drank = (F.drank or 0) + 1
		pcall(function()
			put("RobloxComm/solo/potion.tsv",
				os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
				.. tostring(game.JobId):sub(1, 8) .. string.char(9)
				.. tostring(name) .. string.char(9)
				.. tostring(F.round) .. string.char(9)
				.. string.format("%.0f", hpOf(game.Players.LocalPlayer) or -1) .. string.char(9)
				.. tostring(F.viperHere or "-") .. string.char(10))
		end)
		return true
	end

	while alive() do
		task.wait(0.4)
		if inMatch() then
			pcall(function()
				local ev = game:GetService("ReplicatedStorage"):FindFirstChild(USE_EVENT, true)
				if not ev then return end
				local hb = dep("p4Q")
				local pu = dep("m32")
				if not hb then return end

				local items
				local ok = pcall(function() items = hb:getHotbarItems() end)
				if not ok or type(items) ~= "table" then return end

				local holdEv = game:GetService("ReplicatedStorage")
					:FindFirstChild("8dd94a0e-0dd9-409c-8847-de1054173265", true)
				local swordSlot, swordName
				for _, it in ipairs(items) do
					if tostring(it.Type):find("Sword") then
						swordSlot = it.Slot
						swordName = tostring(it.Type)
						break
					end
				end

				-- DO NOT DRINK SPEED WHILE SOMEBODY IS HITTING US.
				--
				-- Measured 2026-08-24 in potion.tsv: 490 SpeedBoost against 335
				-- LifeSteal and 80 Shield, and the last four rows of round
				-- 4f2b1536 are SpeedBoost, SpeedBoost, SpeedBoost, JumpBoost
				-- while our health went 100, 81, 81, 62, 24 with the rival account stood
				-- next to us. Speed does not stop that; the other two do.
				--
				-- It is worse than a waste. drink() declares the potion as the
				-- held item, uses it, then declares the sword again - so for that
				-- moment the server thinks we are holding a bottle, and any swing
				-- inside it is a swing with no sword.
				local hurt = (hpOf(game.Players.LocalPlayer) or 100) < 90
				local list = (hurt or F.viperHere) and { "LifeSteal", "Shield" } or WANT
				for _, name in ipairs(list) do
					local live = false
					if pu then
						pcall(function() live = pu:hasPowerUp(name) == true end)
					end
					if not live then
						for _, it in ipairs(items) do
							if tostring(it.Type) == name and (tonumber(it.Quantity) or 0) > 0 then
								F.potion = name
								drink(hb, pu, ev, name, it.Slot, swordSlot, holdEv, swordName)
								return
							end
						end
					end
				end
			end)
		end
	end
end)

-- ---------------------------------------------------------------- armour
--
-- His words, 2026-08-24, on being told we had never worn any: "make sure it
-- will auto equite the best armrmo, beucase i seem like forogt tha".
--
-- The chests have handed us 909 OnyxChestplates, 4,190 DiamondChestplates and
-- 15,567 Bronze ones over the recorded rounds and not one of them was ever put
-- on. It shows in the damage log from the other side: hits on other players
-- read 24, 26 and 27 where ours read the sword's full 29, because they are
-- wearing something and we are not.
--
-- The equip call is not known yet - armour is not a hotbar weapon and there is
-- no live client in SkyWars to look at while this is being written. So this
-- tries every shape that could plausibly be it, one at a time, and writes down
-- which one the game accepted. Once armour.tsv names the winner this collapses
-- to a single call.

local ARMOUR_RANK = { Onyx = 5, Diamond = 4, Gold = 3, Iron = 2, Bronze = 1 }
local ARMOUR_SLOTS = { "Helmet", "Chestplate", "Leggings" }

local function armourRank(name)
	for k, v in pairs(ARMOUR_RANK) do
		if string.find(name, k, 1, true) then return v end
	end
	return 0
end

local function bestArmour(items)
	local best = {}
	for _, it in ipairs(items) do
		local nm = tostring(it.Type or it.Name or "")
		for _, slot in ipairs(ARMOUR_SLOTS) do
			if string.find(nm, slot, 1, true) and (tonumber(it.Quantity) or 0) > 0 then
				local r = armourRank(nm)
				if r > 0 and (not best[slot] or r > best[slot].rank) then
					best[slot] = { name = nm, rank = r, slot = it.Slot }
				end
			end
		end
	end
	return best
end

task.spawn(function()
	local reported = {}
	local worked = nil
	while alive() do
		task.wait(2)
		if inMatch() then
			pcall(function()
				local hb = dep("p4Q")
				local inv = dep("bDe")
				if not hb then return end
				local items
				if not pcall(function() items = hb:getHotbarItems() end) then return end
				if type(items) ~= "table" then return end

				local best = bestArmour(items)
				local wearing = {}
				for _, slot in ipairs(ARMOUR_SLOTS) do
					local a = lp:GetAttribute(slot)
					if a then wearing[slot] = tostring(a) end
				end
				F.armour = (wearing.Helmet or "-") .. "/" .. (wearing.Chestplate or "-")
					.. "/" .. (wearing.Leggings or "-")

				for _, slot in ipairs(ARMOUR_SLOTS) do
					local want = best[slot]
					if want and wearing[slot] ~= want.name then
						local tries = {
							{ "hotbar:equipArmor", function() hb:equipArmor(want.name) end },
							{ "hotbar:equip", function() hb:equip(want.name) end },
							{ "hotbar:setActiveSlot", function() hb:setActiveSlot(want.slot) end },
							{ "inventory:equipArmor", function() inv:equipArmor(want.name) end },
							{ "inventory:equip", function() inv:equip(want.name) end },
							{ "inventory:moveItemToSlot", function() inv:moveItemToSlot(want.slot, slot) end },
						}
						for _, t in ipairs(tries) do
							if worked == nil or worked == t[1] then
								local ok = pcall(t[2])
								local now = lp:GetAttribute(slot)
								local on = ok and now and tostring(now) == want.name
								local key = t[1] .. "|" .. slot
								if on or not reported[key] then
									reported[key] = true
									put("RobloxComm/solo/armour.tsv",
										os.date("%Y-%m-%d %H:%M:%S") .. string.char(9)
										.. tostring(game.JobId):sub(1, 8) .. string.char(9)
										.. slot .. string.char(9)
										.. want.name .. string.char(9)
										.. t[1] .. string.char(9)
										.. (ok and "called" or "threw") .. string.char(9)
										.. (on and "WORE IT" or tostring(now or "-")) .. string.char(10))
								end
								if on then worked = t[1] break end
							end
						end
					end
				end
			end)
		end
	end
end)

paint()
return "SOLO_FARM up, gen " .. MYGEN .. ", mode " .. F.mode .. ", auto " .. tostring(F.auto)
