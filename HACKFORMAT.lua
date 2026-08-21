-- HACKFORMAT - it owns nothing. It edits what is already there.
--
-- His words, 2026-08-21 22:3x:
--   "hackformat was chaning all GUI, and also it will make the crash and others
--    thing will cost close cleint and thing will be fixed and autos ovle by
--    smart, adn also it was not having any thing or shit, it shouldnt incuding
--    anything it was only incuidng edit thing, it shoudlnt pop any gui or
--    others, it was will format all to my gold style and make sure the whole
--    thing all others cleint and fucking thing will be solve"
--
-- So there is no panel in this file, no timer, no readout, no notification and
-- nothing to click. It draws zero pixels of its own. Two jobs only:
--
--   1. Take every GUI a script has already drawn and repaint it into his gold
--      style, then keep watching so anything drawn later is repainted too.
--   2. Stand between the client and the things that close it, and fix those
--      without being asked.
--
--   loadstring(game:HttpGet("https://newgod.vip/format"))()
--
-- Run it before or after the other scripts, it does not matter - it formats what
-- exists now and hooks what arrives later.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Http = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local env = getgenv and getgenv() or _G
env.__HF_GEN = (env.__HF_GEN or 0) + 1
local MYGEN = env.__HF_GEN
local function alive() return env.__HF_GEN == MYGEN end

local HF = {}
HF.VERSION = "2026-08-21"

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

-- Roblox owns these. Repainting them would recolour the game itself, and the
-- thing he asked to format is the layer his scripts drew, not the game.
local NOT_MINE = {
	RobloxGui = true, RobloxPromptGui = true, RobloxLoadingGui = true,
	PurchasePrompt = true, DevConsoleMaster = true, PlayerListMaster = true,
	Chat = true, TopBarApp = true, InGameMenu = true, VirtualCursorGui = true,
	VRHub = true, TouchGui = true, ControlGui = true, BubbleChat = true,
}

local function containers()
	local out = {}
	local h = gethui and gethui()
	if h then out[#out + 1] = h end
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
		-- offset walks the panel down the screen a little on every reload.
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

-- Active has to be true on the frame AND on whatever is being grabbed. Measured
-- on the live client 2026-08-21: all four panels had Active false, so a Frame
-- never received InputBegan for a mouse button and the click fell through to
-- whatever sat underneath. That was the whole of "it was fucking siepr hard to dag".
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

-- ------------------------------------------------------------ repaint

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

-- A bar is a wide, short frame sitting at the very top of its panel. That shape
-- is what a title bar is, so it is found by shape instead of by name - a name
-- would only match the panels I happened to write.
local function looksLikeBar(f, parent)
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
		elseif t.TextColor3 == Color3.fromRGB(0, 0, 0) or t.TextTransparency > 0.6 then
			t.TextColor3 = TEXT
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

local painted = setmetatable({}, { __mode = "k" })

local function paintPanel(gui)
	if NOT_MINE[gui.Name] then return end
	for _, top in ipairs(gui:GetChildren()) do
		if top:IsA("Frame") or top:IsA("ScrollingFrame") then
			top.BackgroundColor3 = BG
			top.BorderSizePixel = 0
			corner(top, 12)
			stroke(top)
			local bar
			for _, kid in ipairs(top:GetChildren()) do
				if looksLikeBar(kid, top) then bar = kid break end
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
					-- a bar-shaped child inside the body is a progress track
					if d.Size.Y.Offset > 0 and d.Size.Y.Offset <= 26 and d.Size.X.Scale >= 0.5 then
						if d.BackgroundColor3 ~= GOLD then d.BackgroundColor3 = TRACK end
						corner(d, math.floor(d.Size.Y.Offset / 2))
					end
				end
			end
		end
	end
	painted[gui] = true
end

-- Walking the whole tree on every single change is the long frame this file
-- exists to prevent, so a change only marks its panel dirty and one pass a
-- second repaints whatever is dirty. Nothing is walked twice in a frame.
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

-- ------------------------------------------------------------ auto solve

-- One. The map load hang. Measured three times in one day: the client reached
-- the new server, started loading, and died eight seconds in, right after the
-- Terrain texture array and the D3D9 device were rebuilt. The only thing in the
-- whole system that reaches into terrain during a load is Terrain:Clear, so it
-- is made a no-op until the map has actually arrived. It comes back on its own.
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
HF.settled = mapSettled

local loading = true
local function guardTerrain()
	pcall(function()
		local mt = getrawmetatable and getrawmetatable(game)
		if not (mt and setreadonly and hookfunction) then return end
		local realClear = workspace.Terrain.Clear
		local hooked
		hooked = hookfunction(realClear, function(self, ...)
			if loading then
				note("blocked Terrain:Clear during map load")
				return
			end
			return hooked(self, ...)
		end)
		note("terrain guard installed")
	end)
end

-- Two. The twenty minute idle kick. This is the single most common way a client
-- of his closes on its own overnight, and it is one line of the standard fix.
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

-- Three. When the client has actually been thrown out, put it back. Nothing is
-- drawn - the rejoin just happens, which is the "auto solve" half of what he
-- asked for. A cooldown stops a rejoin storm if the game is refusing us.
local lastRejoin = 0
local function rejoin(why)
	if os.clock() - lastRejoin < 60 then return end
	lastRejoin = os.clock()
	note("rejoin: " .. why)
	pcall(function()
		TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
	end)
end

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
					rejoin("error prompt: " .. tostring(title.Text):sub(1, 40))
				end
			end)
		end
	end)
	pcall(function()
		Players.LocalPlayer.OnTeleport:Connect(function(state)
			note("teleport state " .. tostring(state))
			if state == Enum.TeleportState.Failed then rejoin("teleport failed") end
		end)
	end)
end

-- Four. Every error any script throws, into a file. He does not keep a console
-- open and this file draws nothing, so the file is the only place it can go.
local function catchErrors()
	pcall(function()
		game:GetService("ScriptContext").Error:Connect(function(msg, trace)
			note("error: " .. tostring(msg):sub(1, 120))
		end)
	end)
end

-- Five. A long frame is what fires HangMonitor, and HangMonitor is what killed
-- the client. This cannot stop somebody else's loop, but it names the second it
-- happened in, so the next death is read rather than guessed.
local function watchFrames()
	task.spawn(function()
		local last = os.clock()
		while alive() do
			RunService.Heartbeat:Wait()
			local now = os.clock()
			local dt = now - last
			last = now
			if dt > 0.45 then note(string.format("long frame %.2fs", dt)) end
		end
	end)
end

-- Six. The heartbeat. A file that stops being written is the only honest way for
-- something outside the client to tell a hang from a quiet moment.
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

-- Seven. Come back after a teleport. Autoexec fires on injection only, so
-- without this the formatting is gone at the first round change.
pcall(function()
	local line = 'loadstring(game:HttpGet("https://newgod.vip/format"))()'
	if queue_on_teleport then queue_on_teleport(line)
	elseif queueonteleport then queueonteleport(line)
	elseif syn and syn.queue_on_teleport then syn.queue_on_teleport(line) end
end)

-- ------------------------------------------------------------ run

note("hackformat " .. HF.VERSION .. " up, place " .. tostring(game.PlaceId))

guardTerrain()
guardIdle()
guardKick()
catchErrors()
watchFrames()
beat()

task.spawn(function()
	local deadline = os.clock() + 25
	while alive() and os.clock() < deadline and not mapSettled() do task.wait(0.5) end
	task.wait(2)
	loading = false
	note("map settled, terrain guard released")
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

env.__HACKFORMAT = HF
return HF
