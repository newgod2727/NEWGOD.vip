-- XP_BAR - the level bar the game will not draw big enough.
--
-- Reads the same two functions the game's own lobby bar reads, so the numbers
-- are the game's, not a guess:
--   ExperienceUtil.getLevel(xp)        -> level
--   ExperienceUtil.getExperience(lvl)  -> total xp that level starts at
-- The game's bar is Progress = (xp - getExperience(lvl)) / (getExperience(lvl+1) - getExperience(lvl)).
-- This draws that same fraction, with the raw numbers spelled out.
--
-- It also watches the total climb and works out the real rate per minute, so
-- "how long to the next level" is measured from this account rather than
-- copied off somebody's video.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
env.__XPBAR_GEN = (env.__XPBAR_GEN or 0) + 1
local MYGEN = env.__XPBAR_GEN
local function alive() return env.__XPBAR_GEN == MYGEN end

local lp = Players.LocalPlayer
while not lp do task.wait(0.2) lp = Players.LocalPlayer end

-- See the note in SOLO_FARM: gethui() answers RobloxGui, PlayerGui holds its own
-- copies, and PlayerGui is not always there when this first runs. Three XpBars
-- were counted on screen at 15:0x for exactly that reason.
local function xpSweep(keep)
	local hosts = {}
	pcall(function() if gethui then hosts[#hosts + 1] = gethui() end end)
	pcall(function() hosts[#hosts + 1] = game:GetService("CoreGui") end)
	pcall(function() hosts[#hosts + 1] = game:GetService("CoreGui"):FindFirstChild("RobloxGui") end)
	pcall(function() hosts[#hosts + 1] = lp:FindFirstChild("PlayerGui") end)
	for _, h in ipairs(hosts) do
		if h then
			pcall(function()
				for _, c in ipairs(h:GetChildren()) do
					if c:IsA("ScreenGui") and c.Name == "XpBar" and c ~= keep then c:Destroy() end
				end
			end)
		end
	end
end
xpSweep(nil)
task.spawn(function()
	for _ = 1, 4 do
		task.wait(2)
		if not alive() then return end
		pcall(xpSweep, env.__XPBAR_GUI)
	end
end)
for _, h in ipairs({}) do
	if h then
		pcall(function()
			for _, c in ipairs(h:GetChildren()) do
				if c:IsA("ScreenGui") and c.Name == "XpBar" then c:Destroy() end
			end
		end)
	end
end

local X = { xp = 0, lvl = 0, into = 0, span = 1, toNext = 0, rate = 0, err = "" }
env.__XPBAR = X

local EU, ctrl
local function wire()
	local ok, err = pcall(function()
		EU = require(ReplicatedStorage.TS.experience["experience-util"]).ExperienceUtil
		local core = ReplicatedStorage.rbxts_include.node_modules["@flamework"].core.out
		ctrl = require(core).Flamework.resolveDependency("Qlm")
	end)
	if not ok then X.err = tostring(err):sub(1, 60) end
	return EU ~= nil and ctrl ~= nil
end

local function read()
	if not (EU and ctrl) then
		if not wire() then return false end
	end
	local ok = pcall(function()
		X.xp = ctrl:getExperience() or 0
		X.lvl = EU.getLevel(X.xp)
		local base = EU.getExperience(X.lvl)
		local nxt = EU.getExperience(X.lvl + 1)
		X.into = X.xp - base
		X.span = math.max(1, nxt - base)
		X.toNext = nxt - X.xp
	end)
	return ok
end

-- ---------------------------------------------------------------- panel

local ui = {}

local function build()
	local host = (gethui and gethui()) or game:GetService("CoreGui") or lp:FindFirstChild("PlayerGui")
	if not host then return end

	local gui = Instance.new("ScreenGui")
	gui.Name = "XpBar"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9200
	gui.Parent = host
	env.__XPBAR_GUI = gui

	local f = Instance.new("Frame")
	f.Size = UDim2.new(0, 460, 0, 158)
	f.Position = UDim2.new(0.5, -230, 0, 16)
	f.BackgroundColor3 = Color3.fromRGB(11, 11, 14)
	f.BorderSizePixel = 0
	f.Parent = gui
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 12)
	local st = Instance.new("UIStroke", f)
	st.Color = Color3.fromRGB(201, 142, 74)
	st.Thickness = 2

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 28)
	bar.BackgroundColor3 = Color3.fromRGB(24, 20, 14)
	bar.BorderSizePixel = 0
	bar.Parent = f
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 12)

	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.new(0, 14, 0, 0)
	t.Size = UDim2.new(1, -80, 1, 0)
	t.Font = Enum.Font.GothamBold
	t.TextSize = 13
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = Color3.fromRGB(255, 179, 71)
	t.Text = "XP"
	t.Parent = bar

	local hide = Instance.new("TextButton")
	hide.Size = UDim2.new(0, 52, 0, 20)
	hide.Position = UDim2.new(1, -62, 0, 4)
	hide.BackgroundColor3 = Color3.fromRGB(201, 142, 74)
	hide.BorderSizePixel = 0
	hide.Font = Enum.Font.GothamBold
	hide.TextSize = 10
	hide.TextColor3 = Color3.fromRGB(26, 20, 9)
	hide.Text = "HIDE"
	hide.Parent = bar
	Instance.new("UICorner", hide).CornerRadius = UDim.new(0, 6)

	-- the big level number
	ui.level = Instance.new("TextLabel")
	ui.level.BackgroundTransparency = 1
	ui.level.Position = UDim2.new(0, 16, 0, 34)
	ui.level.Size = UDim2.new(0, 150, 0, 42)
	ui.level.Font = Enum.Font.GothamBold
	ui.level.TextSize = 34
	ui.level.TextXAlignment = Enum.TextXAlignment.Left
	ui.level.TextColor3 = Color3.fromRGB(243, 207, 153)
	ui.level.Text = "LEVEL -"
	ui.level.Parent = f

	-- the big readable fraction, the thing the game draws too small
	ui.frac = Instance.new("TextLabel")
	ui.frac.BackgroundTransparency = 1
	ui.frac.Position = UDim2.new(1, -300, 0, 38)
	ui.frac.Size = UDim2.new(0, 284, 0, 34)
	ui.frac.Font = Enum.Font.GothamBold
	ui.frac.TextSize = 26
	ui.frac.TextXAlignment = Enum.TextXAlignment.Right
	ui.frac.TextColor3 = Color3.fromRGB(255, 255, 255)
	ui.frac.Text = "- / -"
	ui.frac.Parent = f

	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 16, 0, 86)
	track.Size = UDim2.new(1, -32, 0, 22)
	track.BackgroundColor3 = Color3.fromRGB(30, 26, 20)
	track.BorderSizePixel = 0
	track.Parent = f
	Instance.new("UICorner", track).CornerRadius = UDim.new(0, 11)

	ui.fill = Instance.new("Frame")
	ui.fill.Size = UDim2.new(0, 0, 1, 0)
	ui.fill.BackgroundColor3 = Color3.fromRGB(255, 179, 71)
	ui.fill.BorderSizePixel = 0
	ui.fill.Parent = track
	Instance.new("UICorner", ui.fill).CornerRadius = UDim.new(0, 11)

	-- The percentage is drawn TWICE, and which copy you see depends on whether
	-- the gold has reached that letter yet.
	--
	-- His words, 2026-08-21 20:0x: "the % at the levle that 32.9%? now that it
	-- should be gold while it didnt tocuh the gold colour, if the word tcouehd
	-- the gold that progess then it should be blakc word".
	--
	-- One label cannot do that - a TextLabel has a single colour. So the gold
	-- copy sits on the empty track, and a black copy lives INSIDE the fill with
	-- ClipsDescendants on. The black copy is kept the full width of the track,
	-- not the width of the fill, so its glyphs sit in exactly the same pixels as
	-- the gold ones; the clip then reveals precisely the part of the number the
	-- gold has swallowed. Nothing has to be measured per character.
	ui.pct = Instance.new("TextLabel")
	ui.pct.BackgroundTransparency = 1
	ui.pct.Size = UDim2.new(1, 0, 1, 0)
	ui.pct.Font = Enum.Font.GothamBold
	ui.pct.TextSize = 13
	ui.pct.TextColor3 = Color3.fromRGB(255, 179, 71)
	ui.pct.Text = ""
	ui.pct.ZIndex = 3
	ui.pct.Parent = track

	ui.fill.ClipsDescendants = true

	ui.pctOn = Instance.new("TextLabel")
	ui.pctOn.BackgroundTransparency = 1
	ui.pctOn.Size = UDim2.new(0, 0, 1, 0)
	ui.pctOn.Position = UDim2.new(0, 0, 0, 0)
	ui.pctOn.Font = Enum.Font.GothamBold
	ui.pctOn.TextSize = 13
	ui.pctOn.TextColor3 = Color3.fromRGB(20, 17, 13)
	ui.pctOn.Text = ""
	ui.pctOn.ZIndex = 4
	ui.pctOn.Parent = ui.fill

	ui.track = track

	ui.foot = Instance.new("TextLabel")
	ui.foot.BackgroundTransparency = 1
	ui.foot.Position = UDim2.new(0, 16, 0, 114)
	ui.foot.Size = UDim2.new(1, -32, 0, 18)
	ui.foot.Font = Enum.Font.Gotham
	ui.foot.TextSize = 12
	ui.foot.TextXAlignment = Enum.TextXAlignment.Left
	ui.foot.TextColor3 = Color3.fromRGB(200, 190, 175)
	ui.foot.Text = ""
	ui.foot.Parent = f

	ui.foot2 = Instance.new("TextLabel")
	ui.foot2.BackgroundTransparency = 1
	ui.foot2.Position = UDim2.new(0, 16, 0, 132)
	ui.foot2.Size = UDim2.new(1, -32, 0, 18)
	ui.foot2.Font = Enum.Font.Gotham
	ui.foot2.TextSize = 12
	ui.foot2.TextXAlignment = Enum.TextXAlignment.Left
	ui.foot2.TextColor3 = Color3.fromRGB(162, 147, 127)
	ui.foot2.Text = ""
	ui.foot2.Parent = f

	local shown = true
	hide.MouseButton1Click:Connect(function()
		shown = not shown
		for _, k in ipairs({ "level", "frac", "foot", "foot2" }) do ui[k].Visible = shown end
		track.Visible = shown
		f.Size = shown and UDim2.new(0, 460, 0, 158) or UDim2.new(0, 460, 0, 28)
		hide.Text = shown and "HIDE" or "SHOW"
	end)

	makeDraggable("XpBar", f, bar)
end

pcall(build)

local function comma(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function paint()
	if not ui.level then return end
	pcall(function()
		ui.level.Text = "LEVEL " .. X.lvl
		ui.frac.Text = comma(X.into) .. " / " .. comma(X.span)
		local p = math.clamp(X.into / X.span, 0, 1)
		ui.fill.Size = UDim2.new(p, 0, 1, 0)
		local txt = string.format("%.1f%%", p * 100)
		ui.pct.Text = txt
		ui.pctOn.Text = txt
		-- Full track width, so the two copies land on the same pixels. Read live
		-- because the panel can be resized or the viewport can change.
		if ui.track and ui.track.AbsoluteSize.X > 0 then
			ui.pctOn.Size = UDim2.new(0, ui.track.AbsoluteSize.X, 1, 0)
		end
		ui.foot.Text = comma(X.toNext) .. " XP to level " .. (X.lvl + 1)
			.. "     total " .. comma(X.xp)
		if X.rate > 0 then
			local mins = X.toNext / X.rate
			ui.foot2.Text = string.format("measured %s XP/min  ->  about %d min to level %d",
				comma(X.rate), math.ceil(mins), X.lvl + 1)
		else
			ui.foot2.Text = X.err ~= "" and ("! " .. X.err) or "watching the rate, play a round and it will fill in"
		end
	end)
end

-- Rate is measured here, not assumed. Keep the first reading and how long ago
-- it was, so XP per minute comes from this account's own climb.
local t0, xp0 = os.clock(), nil

task.spawn(function()
	while alive() do
		if read() then
			if xp0 == nil then xp0 = X.xp t0 = os.clock() end
			local dt = (os.clock() - t0) / 60
			if dt > 0.5 and X.xp > xp0 then
				X.rate = (X.xp - xp0) / dt
			end
		end
		pcall(paint)
		task.wait(1)
	end
end)

read()
paint()
return "XP_BAR up, level " .. X.lvl .. ", " .. X.into .. "/" .. X.span
