-- SOLO_LOOT - the map and loot half of the solo recorder.
--
-- Answers the things a timeline cannot: which map is this, where every chest
-- is, what came out of which chest, which sword was the best one on the map,
-- where everybody spawned, and how much of that changes from round to round.
--
-- It never opens anything and never moves anyone. It watches and writes.
-- Loaded by SOLO_REC. If this file errors the recorder keeps running.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local env = getgenv and getgenv() or _G
local lp = Players.LocalPlayer
local DIR = "RobloxComm/solo"

env.__SOLOLOOT_GEN = (env.__SOLOLOOT_GEN or 0) + 1
local MYGEN = env.__SOLOLOOT_GEN

local function stillMine()
	return env.__SOLOLOOT_GEN == MYGEN
end

local L = {
	round = 0,
	map = "?",
	fp = "?",
	chests = 0,
	opened = 0,
	items = 0,
	spawns = 0,
	err = "",
}
env.__SOLOLOOT = L

local function put(file, text)
	pcall(function()
		if not isfolder("RobloxComm") then makefolder("RobloxComm") end
		if not isfolder(DIR) then makefolder(DIR) end
		if isfile(file) then
			appendfile(file, text)
		else
			writefile(file, text)
		end
	end)
end

local function stamp()
	return os.date("%H:%M:%S")
end

local function myRoot()
	local ch = lp.Character
	return ch and ch:FindFirstChild("HumanoidRootPart") or nil
end

local function posOf(inst)
	local p
	pcall(function()
		if inst:IsA("BasePart") then
			p = inst.Position
		elseif inst:IsA("Model") then
			local ok, pv = pcall(function() return inst:GetPivot().Position end)
			if ok and pv then
				p = pv
			elseif inst.PrimaryPart then
				p = inst.PrimaryPart.Position
			else
				local ok2, cf = pcall(function() return inst:GetBoundingBox() end)
				if ok2 and cf then p = cf.Position end
			end
		end
	end)
	return p
end

-- A chest is whatever this game calls one. Rather than guess a class, take
-- anything whose name or an ancestor's name reads like loot, then record the
-- whole subtree so the real structure shows itself in the file.

local CHEST_WORDS = { "chest", "crate", "loot", "barrel", "supply", "cache" }

-- Armour is called Chestplate. It is not a chest.
local NOT_CHEST = { "chestplate", "chestpiece", "chestarmor", "chestarmour" }

local function looksLikeChest(name)
	local n = name:lower()
	for _, w in ipairs(NOT_CHEST) do
		if n:find(w, 1, true) then return false end
	end
	for _, w in ipairs(CHEST_WORDS) do
		if n:find(w, 1, true) then return true end
	end
	return false
end

-- ChestTierOne .. ChestTierFour. Higher tier, better loot.
local TIER_WORD = { one = 1, two = 2, three = 3, four = 4, five = 5 }

local function tierOf(name)
	local w = name:match("^ChestTier(%a+)")
	if w then return TIER_WORD[w:lower()] or 0, w end
	return 0, ""
end

-- The map keeps every chest in one folder. Reading that folder is exact and
-- instant; the word scan below it is only a fallback for a map laid out
-- differently.
local function chestFolder()
	local f
	pcall(function()
		local bc = Workspace:FindFirstChild("BlockContainer")
		local map = bc and bc:FindFirstChild("Map")
		f = map and map:FindFirstChild("Chests")
	end)
	if not f then
		pcall(function()
			for _, d in ipairs(Workspace:GetDescendants()) do
				if d:IsA("Folder") and d.Name == "Chests" then f = d break end
			end
		end)
	end
	return f
end

local function chestList()
	local list = {}
	local folder = chestFolder()
	if folder then
		for _, d in ipairs(folder:GetChildren()) do
			list[#list + 1] = d
		end
		return list, "folder"
	end
	pcall(function()
		for _, d in ipairs(Workspace:GetDescendants()) do
			if looksLikeChest(d.Name) and (d:IsA("Model") or d:IsA("BasePart")) then
				list[#list + 1] = d
			end
			if #list > 400 then break end
		end
	end)
	return list, "scan"
end

local function describe(inst, depth)
	local out = {}
	local function walk(d, lvl)
		for _, c in ipairs(d:GetChildren()) do
			local extra = ""
			pcall(function()
				if c:IsA("ValueBase") then
					extra = " = " .. tostring(c.Value)
				elseif c:IsA("Tool") then
					extra = " [TOOL]"
				end
				local at = c:GetAttributes()
				local pieces = {}
				for k, v in pairs(at) do pieces[#pieces + 1] = k .. "=" .. tostring(v) end
				if #pieces > 0 then
					table.sort(pieces)
					extra = extra .. " {" .. table.concat(pieces, ",") .. "}"
				end
			end)
			out[#out + 1] = string.rep("   ", lvl) .. c.ClassName .. " " .. c.Name .. extra
			if lvl < depth and #out < 400 then
				pcall(walk, c, lvl + 1)
			end
		end
	end
	pcall(walk, inst, 1)
	return out
end

local function fingerprint()
	local names, n = {}, 0
	local xs, zs, ys = 0, 0, 0
	for _, d in ipairs(Workspace:GetChildren()) do
		names[#names + 1] = d.Name
	end
	table.sort(names)
	local chestPos = {}
	pcall(function()
		local list = chestList()
		for _, d in ipairs(list) do
			local p = posOf(d)
			if p then
				n = n + 1
				xs = xs + p.X
				ys = ys + p.Y
				zs = zs + p.Z
				local t = select(1, tierOf(d.Name))
				chestPos[#chestPos + 1] = string.format("%.0f,%.0f,%.0f,t%d", p.X, p.Y, p.Z, t)
			end
		end
	end)
	table.sort(chestPos)
	local joined = table.concat(chestPos, "|")
	local h = 5381
	for i = 1, #joined do
		h = (h * 33 + string.byte(joined, i)) % 2147483647
	end
	return {
		top = table.concat(names, ","):sub(1, 300),
		chestCount = n,
		hash = string.format("%08x", h),
		centre = n > 0 and string.format("%.0f,%.0f,%.0f", xs / n, ys / n, zs / n) or "-",
		positions = chestPos,
	}
end

local function mapName()
	local best = "?"
	pcall(function()
		for _, d in ipairs(Workspace:GetChildren()) do
			local n = d.Name:lower()
			if n:find("map") or n:find("island") or n:find("arena") or n:find("board") then
				best = d.Name
				break
			end
		end
		if best == "?" then
			local biggest, count = nil, -1
			for _, d in ipairs(Workspace:GetChildren()) do
				if d:IsA("Model") then
					local c = #d:GetChildren()
					if c > count then count = c; biggest = d.Name end
				end
			end
			if biggest then best = biggest .. " (largest model, " .. count .. " children)" end
		end
	end)
	return best
end

-- ---------------------------------------------------------------- census

local chestIndex = {}

local function censusChests(tag)
	local rows = {}
	local detail = {}
	local n = 0
	local byTier = { 0, 0, 0, 0, 0 }
	local openedNow = 0
	chestIndex = {}
	local r = myRoot()
	local list, how = chestList()
	pcall(function()
		for _, d in ipairs(list) do
			local p = posOf(d)
			if p then
				n = n + 1
				local tier, tierWord = tierOf(d.Name)
				local opened = false
				pcall(function() opened = d:GetAttribute("ChestOpened") == true end)
				if opened then openedNow = openedNow + 1 end
				if tier >= 1 and tier <= 5 then byTier[tier] = byTier[tier] + 1 end
				chestIndex[#chestIndex + 1] =
					{ inst = d, pos = p, name = d.Name, id = n, tier = tier }
				local dist = r and (p - r.Position).Magnitude or -1
				local kids = {}
				pcall(function()
					for _, c in ipairs(d:GetChildren()) do
						kids[#kids + 1] = c.ClassName .. ":" .. c.Name
					end
				end)
				rows[#rows + 1] = string.format(
					"%d\t%s\t%d\t%.1f\t%.1f\t%.1f\t%.0f\t%s\t%s\t%s",
					n, d.Name, tier, p.X, p.Y, p.Z, dist,
					tostring(opened), d.ClassName, table.concat(kids, " "))
				if n <= 6 then
					detail[#detail + 1] = "===== chest " .. n .. "  tier " .. tier .. "  "
						.. d:GetFullName()
						.. string.format("  (%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
					for _, line in ipairs(describe(d, 3)) do
						detail[#detail + 1] = line
					end
					detail[#detail + 1] = ""
				end
			end
		end
	end)
	L.tiers = string.format("t1=%d t2=%d t3=%d t4=%d", byTier[1], byTier[2], byTier[3], byTier[4])
	L.opened = openedNow
	L.how = how
	put(DIR .. "/chest_tiers.tsv", string.format("%s\tr%03d\t%s\t%s\t%d\t%d\t%d\t%d\t%d\t%s\n",
		os.date("%Y-%m-%d %H:%M:%S"), L.round, L.fp, tag,
		byTier[1], byTier[2], byTier[3], byTier[4], n, how))
	L.chests = n
	local head = "id\tname\ttier\tx\ty\tz\tdist\topened\tclass\tchildren\n"
	put(DIR .. "/" .. lp.Name .. "_r" .. string.format("%03d", L.round) .. "_chests_" .. tag .. ".tsv",
		head .. table.concat(rows, "\n") .. "\n")
	if #detail > 0 then
		put(DIR .. "/" .. lp.Name .. "_r" .. string.format("%03d", L.round) .. "_chest_detail_" .. tag .. ".txt",
			table.concat(detail, "\n") .. "\n")
	end
	return n
end

local function censusSpawns()
	local rows = {}
	pcall(function()
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("SpawnLocation") then
				rows[#rows + 1] = string.format("SpawnLocation\t%s\t%.1f\t%.1f\t%.1f\t%s",
					d:GetFullName(), d.Position.X, d.Position.Y, d.Position.Z, tostring(d.Enabled))
			end
			if #rows > 200 then break end
		end
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		local rr = ch and ch:FindFirstChild("HumanoidRootPart")
		if rr then
			rows[#rows + 1] = string.format("player\t%s\t%.1f\t%.1f\t%.1f\t%s",
				p.Name, rr.Position.X, rr.Position.Y, rr.Position.Z,
				p == lp and "ME" or "")
		end
	end
	L.spawns = #rows
	put(DIR .. "/" .. lp.Name .. "_r" .. string.format("%03d", L.round) .. "_spawns.tsv",
		"kind\twho\tx\ty\tz\tnote\n" .. table.concat(rows, "\n") .. "\n")
	return #rows
end


-- ---------------------------------------------------------------- chest event

local CHEST_CONTENTS_EVENT = "263ab5f8-5ee3-442f-9533-2a1274c10537"

local SWORD_DAMAGE = {
	BronzeSword = 18,
	IronSword = 23,
	GoldSword = 25,
	DiamondSword = 29,
	OnyxSword = 32,
}

local function describeItem(entry)
	local bits = {}
	pcall(function()
		local id = entry.Id or entry.Item or entry.Name or entry.Type
		if id == nil and type(entry) == "table" then
			for k, v in pairs(entry) do
				if type(v) == "string" and k ~= "Slot" then id = v break end
			end
		end
		bits[#bits + 1] = tostring(id)
		if entry.Amount then bits[#bits + 1] = "x" .. tostring(entry.Amount) end
		local dmg = SWORD_DAMAGE[tostring(id)]
		if dmg then bits[#bits + 1] = "damage=" .. tostring(dmg) end
	end)
	if #bits == 0 then bits[1] = "?" end
	return table.concat(bits, " ")
end

local function watchChestEvent()
	local ok, err = pcall(function()
		local ps = lp:WaitForChild("PlayerScripts", 10)
		local Events = require(ps.TS.events).Events
		local ev = Events[CHEST_CONTENTS_EVENT]
		if not ev or not ev.connect then
			error("chest contents event not found")
		end
		ev:connect(function(chest, contents, shownOnScreen)
			pcall(function()
				local TAB = string.char(9)
				local NL = string.char(10)
				local name = chest and tostring(chest.Name) or "?"
				local tier = select(1, tierOf(name))
				local pos = chest and posOf(chest)
				local r = myRoot()
				local dist = (pos and r) and (pos - r.Position).Magnitude or -1

				local items = {}
				local best, bestDmg = "none", 0
				if type(contents) == "table" then
					for _, entry in pairs(contents) do
						if type(entry) == "table" then
							local d = describeItem(entry)
							items[#items + 1] = "slot" .. tostring(entry.Slot or "?") .. "=" .. d
							pcall(function()
								local id = tostring(entry.Id or entry.Item or entry.Name or "")
								local dm = SWORD_DAMAGE[id]
								if dm and dm > bestDmg then bestDmg = dm; best = id end
							end)
						end
					end
				end
				table.sort(items)

				L.chestOpens = (L.chestOpens or 0) + 1
				if bestDmg > 0 then
					L.bestSeen = (L.bestSeen and SWORD_DAMAGE[L.bestSeen] or 0) >= bestDmg and L.bestSeen or best
				end

				put(DIR .. "/" .. lp.Name .. "_r" .. string.format("%03d", L.round) .. "_chestopen.log",
					stamp() .. TAB .. name .. TAB .. "tier=" .. tostring(tier)
					.. TAB .. string.format("dist=%.1f", dist)
					.. TAB .. "items=" .. tostring(#items)
					.. TAB .. "best_sword=" .. best .. "(" .. tostring(bestDmg) .. ")"
					.. TAB .. "ui=" .. tostring(shownOnScreen)
					.. TAB .. table.concat(items, " | ") .. NL)

				put(DIR .. "/chest_contents_master.tsv",
					os.date("%Y-%m-%d %H:%M:%S") .. TAB
					.. string.format("r%03d", L.round) .. TAB
					.. tostring(L.fp) .. TAB
					.. name .. TAB
					.. tostring(tier) .. TAB
					.. tostring(#items) .. TAB
					.. best .. TAB
					.. table.concat(items, " | ") .. NL)
			end)
		end)
	end)
	if not ok then
		L.err = "chest event: " .. tostring(err):sub(1, 60)
	else
		L.chestEvent = true
	end
end

-- ---------------------------------------------------------------- loot

local function nearestChest()
	local r = myRoot()
	if not r then return nil, -1 end
	local best, bestd = nil, 1e9
	for _, c in ipairs(chestIndex) do
		local d = (c.pos - r.Position).Magnitude
		if d < bestd then bestd = d; best = c end
	end
	return best, bestd
end

local function itemInfo(inst)
	local bits = { inst.ClassName .. ":" .. inst.Name }
	pcall(function()
		local at = inst:GetAttributes()
		local ks = {}
		for k, v in pairs(at) do ks[#ks + 1] = k .. "=" .. tostring(v) end
		table.sort(ks)
		if #ks > 0 then bits[#bits + 1] = "{" .. table.concat(ks, ",") .. "}" end
		for _, c in ipairs(inst:GetChildren()) do
			if c:IsA("ValueBase") then
				bits[#bits + 1] = c.Name .. "=" .. tostring(c.Value)
			end
		end
	end)
	return table.concat(bits, " ")
end

local logged = setmetatable({}, { __mode = "k" })

local function onGained(inst, how)
	if logged[inst] then return end
	logged[inst] = true
	L.items = L.items + 1
	local c, d = nearestChest()
	local r = myRoot()
	put(DIR .. "/" .. lp.Name .. "_r" .. string.format("%03d", L.round) .. "_loot.log",
		string.format("%s\t%s\t%s\tnearest_chest=%s\tchest_dist=%.1f\tmy_y=%.1f\n",
			stamp(), how, itemInfo(inst),
			c and (c.name .. "#" .. c.id) or "none",
			d >= 0 and d or -1,
			r and r.Position.Y or -9999))
	put(DIR .. "/loot_master.tsv",
		string.format("%s\t%s\tr%03d\t%s\t%s\t%s\t%.1f\n",
			os.date("%Y-%m-%d %H:%M:%S"), L.fp, L.round, lp.Name, how,
			itemInfo(inst), d >= 0 and d or -1))
end

local function watchInventory()
	local function hook(container, how)
		if not container then return end
		container.ChildAdded:Connect(function(c)
			pcall(function()
				if c:IsA("Tool") or c:IsA("Accessory") then
					onGained(c, how)
				end
			end)
		end)
		for _, c in ipairs(container:GetChildren()) do
			pcall(function()
				if c:IsA("Tool") then onGained(c, how .. "-had") end
			end)
		end
	end
	pcall(function() hook(lp:FindFirstChild("Backpack"), "backpack") end)
	pcall(function() hook(lp.Character, "equipped") end)
	lp.CharacterAdded:Connect(function(ch)
		task.wait(0.5)
		pcall(function() hook(ch, "equipped") end)
		pcall(function() hook(lp:FindFirstChild("Backpack"), "backpack") end)
	end)
	pcall(function()
		lp.ChildAdded:Connect(function(c)
			if c.Name == "Backpack" then
				task.wait(0.3)
				hook(c, "backpack")
			end
		end)
	end)
end

local function watchPrompts()
	pcall(function()
		local UIS = game:GetService("ProximityPromptService")
		UIS.PromptTriggered:Connect(function(prompt, player)
			if player ~= lp then return end
			L.opened = L.opened + 1
			local p = prompt.Parent
			local pos = p and posOf(p)
			put(DIR .. "/" .. lp.Name .. "_r" .. string.format("%03d", L.round) .. "_loot.log",
				string.format("%s\tPROMPT\t%s\t%s%s\n", stamp(),
					tostring(prompt.ObjectText) .. "/" .. tostring(prompt.ActionText),
					p and p:GetFullName() or "?",
					pos and string.format("  (%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z) or ""))
		end)
	end)
end


-- ---------------------------------------------------------------- xp per round

local XP = { at = nil, ctrl = nil, EU = nil }

local function xpNow()
	if not XP.ctrl then
		pcall(function()
			local RS = game:GetService("ReplicatedStorage")
			local core = RS.rbxts_include.node_modules["@flamework"].core.out
			local m = require(core)
			XP.ctrl = m.Flamework.resolveDependency("Qlm")
			XP.EU = require(RS.TS.experience["experience-util"]).ExperienceUtil
		end)
	end
	local v
	pcall(function() v = XP.ctrl and XP.ctrl:getExperience() end)
	return v
end

local function xpOpen()
	XP.at = xpNow()
	L.xpStart = XP.at
end

local function xpClose(why)
	local now = xpNow()
	if not now or not XP.at then return end
	local gained = now - XP.at
	L.xpGained = gained
	local TAB = string.char(9)
	local NL = string.char(10)
	local lvl = XP.EU and XP.EU.getLevel(now) or -1
	put(DIR .. "/xp_per_round.tsv",
		os.date("%Y-%m-%d %H:%M:%S") .. TAB
		.. string.format("r%03d", L.round) .. TAB
		.. lp.Name .. TAB
		.. tostring(game.PlaceId) .. TAB
		.. tostring(XP.at) .. TAB
		.. tostring(now) .. TAB
		.. tostring(gained) .. TAB
		.. tostring(lvl) .. TAB
		.. tostring(L.chests or 0) .. TAB
		.. tostring(why) .. NL)
	XP.at = now
end

-- ---------------------------------------------------------------- rounds

local seenJob = {}

local function openRound(n)
	local shared, fresh = nil, nil
	pcall(function()
		shared = env.__SOLOREC and env.__SOLOREC.round
		fresh = env.__SOLOREC and env.__SOLOREC.fresh
	end)
	L.round = (type(shared) == "number" and shared > 0) and shared or n
	local job = tostring(game.JobId)
	if seenJob[job] or fresh == false then
		L.err = ""
		return
	end
	seenJob[job] = true
	local fp = fingerprint()
	L.fp = fp.hash
	L.map = mapName()
	local head = {
		"round " .. n,
		"when " .. os.date("%Y-%m-%d %H:%M:%S"),
		"place " .. tostring(game.PlaceId),
		"job " .. tostring(game.JobId),
		"map " .. L.map,
		"fingerprint " .. fp.hash,
		"chest count " .. fp.chestCount,
		"chest centre " .. fp.centre,
		"workspace top " .. fp.top,
	}
	put(DIR .. "/" .. lp.Name .. "_r" .. string.format("%03d", n) .. "_map.txt",
		table.concat(head, "\n") .. "\n\nchest positions sorted:\n" .. table.concat(fp.positions, "\n") .. "\n")

	put(DIR .. "/map_master.tsv", string.format("%s\tr%03d\t%s\t%s\t%s\t%d\t%s\t%s\n",
		os.date("%Y-%m-%d %H:%M:%S"), n, lp.Name, tostring(game.PlaceId),
		fp.hash, fp.chestCount, fp.centre, L.map))

	xpOpen()

	task.spawn(function()
		censusChests("start")
		censusSpawns()
		for _, wait_s in ipairs({ 6, 9, 15 }) do
			task.wait(wait_s)
			censusChests("plus" .. tostring(wait_s + 0) .. "s")
		end
		-- The map streams in after the round opens, so the fingerprint taken at
		-- t=0 hashed an empty chest list and every map came out as the same
		-- 00001505. Take it again once the chests are really there, and only
		-- then write the row that says which map this was.
		if L.chests > 0 then
			local again = fingerprint()
			L.fp = again.hash
			local TAB = string.char(9)
			local NL = string.char(10)
			put(DIR .. "/map_master.tsv",
				os.date("%Y-%m-%d %H:%M:%S") .. TAB
				.. string.format("r%03d", L.round) .. TAB
				.. lp.Name .. TAB
				.. tostring(game.PlaceId) .. TAB
				.. again.hash .. TAB
				.. tostring(again.chestCount) .. TAB
				.. again.centre .. TAB
				.. tostring(L.tiers) .. TAB
				.. "SETTLED" .. NL)
			put(DIR .. "/" .. lp.Name .. "_r" .. string.format("%03d", L.round) .. "_map.txt",
				NL .. NL .. "SETTLED FINGERPRINT - taken after the map finished streaming" .. NL
				.. "fingerprint " .. again.hash .. NL
				.. "chest count " .. tostring(again.chestCount) .. NL
				.. "chest centre " .. again.centre .. NL
				.. "tiers " .. tostring(L.tiers) .. NL .. NL
				.. "chest positions sorted:" .. NL
				.. table.concat(again.positions, NL) .. NL)
		end
	end)

	task.spawn(function()
		task.wait(4)
		local folder = chestFolder()
		if not folder then return end
		for _, d in ipairs(folder:GetChildren()) do
			pcall(function()
				d:GetAttributeChangedSignal("ChestOpened"):Connect(function()
					if d:GetAttribute("ChestOpened") ~= true then return end
					local tier = select(1, tierOf(d.Name))
					local p = posOf(d)
					local r = myRoot()
					local dist = (p and r) and (p - r.Position).Magnitude or -1
					put(DIR .. "/" .. lp.Name .. "_r" .. string.format("%03d", L.round) .. "_loot.log",
						string.format("%s\tCHEST_OPENED\t%s\ttier=%d\tdist_from_me=%.1f%s\n",
							stamp(), d.Name, tier, dist,
							p and string.format("\tat=(%.0f,%.0f,%.0f)", p.X, p.Y, p.Z) or ""))
				end)
			end)
		end
	end)
end

local lastJob = ""
local lastPlace = 0

task.spawn(function()
	watchInventory()
	watchPrompts()
	watchChestEvent()
	local n = 0
	while stillMine() do
		local job = tostring(game.JobId)
		local place = game.PlaceId
		if job ~= lastJob or place ~= lastPlace then
			pcall(xpClose, "server changed")
			if lastJob ~= "" then
				put(DIR .. "/map_master.tsv", string.format("%s\t--\t%s\tTELEPORT\tfrom_place=%s\tto_place=%s\n",
					os.date("%Y-%m-%d %H:%M:%S"), lp.Name, tostring(lastPlace), tostring(place)))
			end
			lastJob = job
			lastPlace = place
			n = n + 1
			pcall(openRound, n)
		end
		task.wait(1)
	end
end)

task.spawn(function()
	while stillMine() do
		task.wait(5)
		pcall(function()
			writefile(DIR .. "/loot_status.txt", table.concat({
				"when " .. os.date("%Y-%m-%d %H:%M:%S"),
				"round " .. L.round,
				"map " .. L.map,
				"fingerprint " .. L.fp,
				"chests " .. L.chests,
				"tiers " .. tostring(L.tiers or "?"),
				"found via " .. tostring(L.how or "?"),
				"already opened " .. L.opened,
				"chest event wired " .. tostring(L.chestEvent == true),
				"chests I opened " .. tostring(L.chestOpens or 0),
				"xp at round start " .. tostring(L.xpStart or "?"),
				"xp gained last round " .. tostring(L.xpGained or "?"),
				"items " .. L.items,
				"spawn rows " .. L.spawns,
				"err " .. (L.err ~= "" and L.err or "none"),
			}, "\n") .. "\n")
		end)
	end
end)

return "SOLO_LOOT up"
