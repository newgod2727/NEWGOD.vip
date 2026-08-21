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
--    bug also auto, as i think many hub or just scirpt will ruin ... after detect
--    the cleint got banned or kicked it will hop to the sever again"
--
-- So: no panel, no timer, no readout, no notification, nothing to click. It draws
-- zero pixels of its own - the only two things it ever creates are a UICorner and
-- a UIStroke, and both of those are edits to something that already exists.
--
-- Four jobs.
--   FORMAT   every menu any script drew, repainted into the gold style, and kept
--            that way as new ones arrive.
--   BOOST    the render side stripped down, in one pass, only once the map has
--            actually arrived, in bites small enough not to make the stutter.
--   REPAIR   the bugs other hubs ship with - stacked copies, panels off screen,
--            panels destroyed on respawn, panels buried under the game, a
--            character thrown into the void.
--   SURVIVE  the things that close the client, fixed without being asked, and a
--            hop to a fresh server if the client is thrown out.
--
-- Run it before or after everything else. It formats what exists now and hooks
-- what arrives later.

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
HF.VERSION = "2026-08-21b"

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

-- A bar is a wide, short frame sitting at the very top of its panel. That shape
-- is what a title bar is, so it is found by shape and not by name - a name would
-- only ever match the panels I happened to write myself.
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

-- Three bugs that ship with half the hubs on the internet, all fixed here rather
-- than in their code, because their code is not mine to edit.
local function repairGui(gui)
	-- One. A panel parented into PlayerGui with ResetOnSpawn left true is thrown
	-- away every time the character respawns, and the user reads that as "the
	-- script stopped working".
	pcall(function() gui.ResetOnSpawn = false end)
	-- Two. A panel drawn under the game's own interface cannot be clicked and
	-- looks like it never opened.
	pcall(function()
		if gui.DisplayOrder < 1000 then gui.DisplayOrder = 9200 end
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	end)
	-- Three. Two copies of the same hub stack on top of each other and every
	-- click lands on the dead one underneath. The newest copy wins.
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

-- A panel whose top left corner is outside the window is a panel the user cannot
-- reach. Saved positions from a bigger screen do this constantly.
local function pullOnScreen(top)
	pcall(function()
		local cam = workspace.CurrentCamera
		if not cam then return end
		local vp = cam.ViewportSize
		local p = top.AbsolutePosition
		if p.X < -40 or p.Y < -10 or p.X > vp.X - 40 or p.Y > vp.Y - 20 then
			top.Position = UDim2.new(0, 24, 0, 120)
			note("pulled " .. top.Name .. " back on screen")
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

-- Walking the whole tree on every single change is the long frame this file
-- exists to prevent, so a change only marks its panel dirty and one pass a
-- second repaints whatever is dirty.
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

-- ------------------------------------------------------------ survive

-- Measured three times in one day: the client reached the new server, started
-- loading, and died eight seconds in, right after the Terrain texture array and
-- the D3D9 device were rebuilt. The only thing in the whole system that reaches
-- into terrain during a load is Terrain:Clear, so it is a no-op until the map has
-- actually arrived, and comes back on its own after.
local function mapSettled()
	local ok = false
	pcall(function()
		local bc = workspace:FindFirstChild("BlockContainer")
		local map = bc and bc:FindFirstChild("Map")
		local chests = map and map:FindFirstChild("Chests")
		ok = chests ~= nil and #chests:GetChildren() > 0
	end)
	if ok then return true end
	-- No knowledge of this game: the tree has stopped growing.
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

-- The twenty minute idle kick is the single most common way a client closes on
-- its own overnight.
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
-- the only way to pick a specific instance; if it cannot be read, the plain
-- teleport still lands somewhere with room.
local lastHop = 0

local function hop(why)
	if os.clock() - lastHop < 45 then return end
	lastHop = os.clock()
	note("hop: " .. why)
	local placed = false
	pcall(function()
		local url = "https://games.roblox.com/v1/games/" .. tostring(game.PlaceId)
			.. "/servers/Public?sortOrder=Asc&limit=100"
		local body = game:HttpGet(url)
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

-- Every error any script throws, into a file. He does not keep a console open
-- and this file draws nothing, so a file is the only place it can go.
local function catchErrors()
	pcall(function()
		game:GetService("ScriptContext").Error:Connect(function(msg)
			note("error: " .. tostring(msg):sub(1, 120))
		end)
	end)
end

-- A long frame is what fires HangMonitor, and HangMonitor is what killed the
-- client. This cannot stop somebody else's loop, but it names the second it
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

-- A script that writes the character below the map leaves it falling forever.
-- The floor is read from the map every time, because the void line is not a
-- constant - it was measured at -24 on one map and -39 on the next.
local function guardVoid()
	task.spawn(function()
		local lastGood
		while alive() do
			task.wait(0.4)
			pcall(function()
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

-- Brightness is the one line that separates a downgrade from a black screen.
-- Measured on his farm: the old code set EnvironmentDiffuseScale and
-- EnvironmentSpecularScale to zero and never set Brightness, and the screen went
-- black. Two is what the working version uses.
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

-- One walk, 300 at a time. 1200 in a frame was measured as the long frame that
-- fired HangMonitor, which is the whole reason this file exists.
local function boostSweep()
	local seen, hit = 0, 0
	for _, inst in ipairs(workspace:GetDescendants()) do
		seen = seen + 1
		if EFFECT[inst.ClassName] then
			pcall(function() inst.Enabled = false end)
			hit = hit + 1
		elseif inst:IsA("MeshPart") then
			pcall(function() inst.RenderFidelity = Enum.RenderFidelity.Performance end)
		elseif inst:IsA("BasePart") then
			pcall(function()
				inst.CastShadow = false
				inst.Reflectance = 0
			end)
		elseif inst:IsA("Decal") or inst:IsA("Texture") then
			pcall(function() inst.Transparency = 1 end)
		end
		if seen % 300 == 0 then task.wait() end
	end
	return seen, hit
end

local function boost()
	if boostedJob == tostring(game.JobId) then return end
	boostedJob = tostring(game.JobId)
	note("BOOST START")
	boostLighting()
	local seen, hit = boostSweep()
	note("boost finished, walked " .. seen .. ", switched off " .. hit)
end

-- ------------------------------------------------------------ run

pcall(function()
	local line = 'loadstring(game:HttpGet("https://newgod.vip/format"))()'
	if queue_on_teleport then queue_on_teleport(line)
	elseif queueonteleport then queueonteleport(line)
	elseif syn and syn.queue_on_teleport then syn.queue_on_teleport(line) end
end)

note("hackformat " .. HF.VERSION .. " up, place " .. tostring(game.PlaceId))

guardTerrain()
guardIdle()
guardKick()
guardVoid()
catchErrors()
watchFrames()
beat()

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

-- A round change is a new job id, so the boost has to run again on the new map.
task.spawn(function()
	local job = tostring(game.JobId)
	while alive() do
		task.wait(3)
		if tostring(game.JobId) ~= job then
			job = tostring(game.JobId)
			loading = true
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
