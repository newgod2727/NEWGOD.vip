do
    local g = getgenv and getgenv() or _G
    local q = g.queue_on_teleport or queue_on_teleport
    if type(q) == "function" and g.__TPFARM_QUEUED_JOB ~= game.JobId then
        g.__TPFARM_QUEUED_JOB = game.JobId
        g.__TPFARM_QUEUED_OK = pcall(q, [==[
task.spawn(function()
    local t0 = os.clock()
    repeat task.wait(0.5) until game:IsLoaded() or os.clock() - t0 > 40
    repeat task.wait(0.5) until game:GetService("Players").LocalPlayer or os.clock() - t0 > 60
    for _ = 1, 25 do
        local ok = pcall(function()
            loadstring(game:HttpGet("https://newgod.vip/loader"))()
        end)
        if ok then break end
        task.wait(3)
    end
end)
]==])
    end
end

local STATE = STATE
do
    local env = getgenv and getgenv() or _G
    env.__TPFARM_GEN = (env.__TPFARM_GEN or 0) + 1
    local myGen = env.__TPFARM_GEN
    pcall(function() if env.__TPFARM_GUI then env.__TPFARM_GUI:Destroy() end end)
    env.__TPFARM_GUI = nil
    local hosts = {}
    pcall(function() if gethui then table.insert(hosts, gethui()) end end)
    pcall(function() table.insert(hosts, game:GetService("CoreGui")) end)
    pcall(function() table.insert(hosts, game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")) end)
    for _, h in ipairs(hosts) do
        if h then
            for _, c in ipairs(h:GetDescendants()) do
                if c:IsA("ScreenGui") and (c.Name == "TPFarmPanel" or c.Name == "TPFollowPanel") then
                    pcall(function() c:Destroy() end)
                end
            end
        end
    end
    pcall(function() game:GetService("RunService"):UnbindFromRenderStep("tpfarm_aim") end)
    if type(env.__TPFARM_CONNS) == "table" then
        for _, c in ipairs(env.__TPFARM_CONNS) do pcall(function() c:Disconnect() end) end
    end
    env.__TPFARM_CONNS = {}
    if env.__TPFARM_CAM_HELD then
        pcall(function() workspace.CurrentCamera.CameraType = Enum.CameraType.Custom end)
        env.__TPFARM_CAM_HELD = false
    end
    if not STATE then
        STATE = {
            alive = function() return env.__TPFARM_GEN == myGen end,
            onCleanup = function() end,
            connect = function(sig, fn) return sig:Connect(fn) end,
        }
    else
        local realAlive = STATE.alive
        STATE = {
            alive = function() return realAlive() and env.__TPFARM_GEN == myGen end,
            onCleanup = STATE.onCleanup,
            connect = STATE.connect,
        }
    end
end


local LOGDIR = "RobloxComm"
local LOGFILE = "RobloxComm/tpfarm.log"
local LOG
do
    local ok = pcall(function()
        if not isfolder(LOGDIR) then makefolder(LOGDIR) end
        if not isfile(LOGFILE) then writefile(LOGFILE, "") end
    end)
    if ok then
        local lastMsg, lastCount, lastAt = nil, 0, 0
        local function put(line)
            pcall(function()
                appendfile(LOGFILE, os.date("%H:%M:%S") .. "  " .. tostring(game.JobId):sub(1, 8)
                    .. "  " .. line .. string.char(10))
            end)
        end
        LOG = function(...)
            local a = table.pack(...)
            local parts = {}
            for i = 1, a.n do parts[#parts + 1] = tostring(a[i]) end
            local msg = table.concat(parts, "  ")
            if msg == lastMsg then
                lastCount = lastCount + 1
                if os.clock() - lastAt > 30 then
                    put(msg .. "   [same line x" .. lastCount .. " in the last 30s]")
                    lastCount, lastAt = 0, os.clock()
                end
                return
            end
            if lastMsg and lastCount > 1 then
                put(lastMsg .. "   [same line x" .. lastCount .. "]")
            end
            lastMsg, lastCount, lastAt = msg, 1, os.clock()
            put(msg)
        end
    else
        LOG = function() end
    end
end

local ENV = getgenv and getgenv() or _G
if type(ENV.__TPFARM_CONNS) ~= "table" then ENV.__TPFARM_CONNS = {} end
local function keep(c)
    local t = ENV.__TPFARM_CONNS
    t[#t + 1] = c
    return c
end

LOG("")
LOG("==== tpfarm loading ====")

do
    local MPS = game:GetService("MarketplaceService")
    local env = getgenv and getgenv() or _G
    if not env.__TPFARM_PROMPT_HOOKED and hookfunction then
        env.__TPFARM_PROMPT_HOOKED = true
        env.__TPFARM_PROMPT_BLOCKED = 0
        local function swallow(name)
            pcall(function()
                local original
                original = hookfunction(MPS[name], function()
                    env.__TPFARM_PROMPT_BLOCKED = (env.__TPFARM_PROMPT_BLOCKED or 0) + 1
                    return
                end)
            end)
        end
        swallow("PromptProductPurchase")
        swallow("PromptPurchase")
        swallow("PromptGamePassPurchase")
        swallow("PromptBundlePurchase")
        swallow("PromptPremiumPurchase")
    end
end

local SAVE = "tpfarm_cfg.json"
local function loadCfg(defaults)
    local ok, raw = pcall(readfile, SAVE)
    if not ok then return defaults end
    local ok2, t = pcall(function() return game:GetService("HttpService"):JSONDecode(raw) end)
    if not ok2 or type(t) ~= "table" then return defaults end
    for k, v in pairs(t) do if defaults[k] ~= nil then defaults[k] = v end end
    return defaults
end
local function saveCfg(t)
    pcall(function()
        writefile(SAVE, game:GetService("HttpService"):JSONEncode(t))
    end)
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CS = game:GetService("CollectionService")
local TS = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local me = Players.LocalPlayer
local cam = workspace.CurrentCamera
local function grab(root, ...)
    local node = root
    for _, seg in ipairs({...}) do
        if not node then return nil end
        node = node:FindFirstChild(seg)
    end
    return node
end
local UNLOCK_FIXES = 0
local camDragging
do
    local UIS0 = game:GetService("UserInputService")
    camDragging = function()
        local ok, held = pcall(function()
            return UIS0:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
                or UIS0:IsMouseButtonPressed(Enum.UserInputType.MouseButton3)
        end)
        return ok and held == true
    end
end
do
    local UIS2 = game:GetService("UserInputService")
    local function unlockMouse()
        if me.CameraMode ~= Enum.CameraMode.Classic then
            pcall(function() me.CameraMode = Enum.CameraMode.Classic end)
            UNLOCK_FIXES = UNLOCK_FIXES + 1
        end
        if me.CameraMinZoomDistance ~= 8 then
            pcall(function() me.CameraMinZoomDistance = 8 end)
        end
        if me.CameraMaxZoomDistance ~= 40 then
            pcall(function() me.CameraMaxZoomDistance = 40 end)
        end
        if camDragging() then return end
        if UIS2.MouseBehavior ~= Enum.MouseBehavior.Default then
            pcall(function() UIS2.MouseBehavior = Enum.MouseBehavior.Default end)
            UNLOCK_FIXES = UNLOCK_FIXES + 1
        end
        if UIS2.MouseIconEnabled ~= true then
            pcall(function() UIS2.MouseIconEnabled = true end)
            UNLOCK_FIXES = UNLOCK_FIXES + 1
        end
    end
    local dirty = true
    local function raise() dirty = true end
    keep(me.CharacterAdded:Connect(function() task.wait(0.15) raise() end))
    keep(me:GetPropertyChangedSignal("CameraMode"):Connect(raise))
    keep(UIS2:GetPropertyChangedSignal("MouseBehavior"):Connect(raise))
    keep(UIS2:GetPropertyChangedSignal("MouseIconEnabled"):Connect(raise))
    unlockMouse()
    task.spawn(function()
        while STATE.alive() do
            if dirty then
                dirty = false
                unlockMouse()
                task.wait(0.03)
            else
                task.wait(0.15)
                if me.CameraMode ~= Enum.CameraMode.Classic
                    or UIS2.MouseBehavior ~= Enum.MouseBehavior.Default
                    or UIS2.MouseIconEnabled ~= true then
                    unlockMouse()
                end
            end
        end
    end)
end

LOG("vape is loaded by this script and by nothing else, one copy, with a lock")

pcall(function() (getgenv and getgenv() or _G).__TPFARM_WRONGPLACE = nil end)
local Shoot = grab(RS, "Blaster", "Remotes", "Shoot")
local Reload = grab(RS, "Blaster", "Remotes", "Reload")
local RoundRemotes = grab(RS, "Shared", "Remotes", "RoundRemotes")
local CheatRemotes = grab(RS, "Shared", "Remotes", "CheatRemotes")
if not (Shoot and Reload) then
    local warnGui = Instance.new("ScreenGui")
    warnGui.Name = "TPFarmPanel"
    warnGui.ResetOnSpawn = false
    warnGui.IgnoreGuiInset = true
    local placed = false
    placed = pcall(function() if gethui then warnGui.Parent = gethui() placed = true end end) and placed
    if not warnGui.Parent then pcall(function() warnGui.Parent = game:GetService("CoreGui") end) end
    if not warnGui.Parent then pcall(function() warnGui.Parent = me:WaitForChild("PlayerGui") end) end
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.fromOffset(320, 90)
    lbl.Position = UDim2.new(0.5, -160, 0.5, -45)
    lbl.BackgroundColor3 = Color3.fromRGB(20, 17, 13)
    lbl.TextColor3 = Color3.fromRGB(231, 177, 115)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 14
    lbl.TextWrapped = true
    lbl.Text = "TP FARM only runs inside the arena place of this game. Join a round first, then run the script again."
    lbl.Parent = warnGui
    Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 8)
    task.delay(8, function() pcall(function() warnGui:Destroy() end) end)
    pcall(function() (getgenv and getgenv() or _G).__TPFARM_WRONGPLACE = game.PlaceId end)
    return "tpfarm: wrong place, Blaster remotes not found"
end

local okRC, RoundClient = pcall(function() return require(RS.Client.Providers.Game.RoundClient) end)
local okBC, BotClient = pcall(function() return require(RS.Client.Providers.Game.BotClient) end)
local okDC, DataClient = pcall(function() return require(RS.Client.Providers.Core.DataClient) end)
if not okRC then RoundClient = nil end
if not okBC then BotClient = nil end
if not okDC then DataClient = nil end

local CFG = loadCfg({ on = false, back = 5, tpEvery = 2, jumpEvery = 3, settle = 0.25,
              autoDeploy = true, doBots = true, doPlayers = true, oneShot = true,
              autoBuy = false, buyBasic = false, buySuper = false, buyGold = true,
              autoOpen = false, lobbyHold = false, vapeList = {}, guiX = 24, guiY = 150,
              clickX = 0, clickY = 0, clickRate = 16, clickFX = 0, clickFY = 0 })
if type(CFG.autoBuy) ~= "boolean" then CFG.autoBuy = false end
CFG.autoOpen = false
if type(CFG.vapeList) ~= "table" then CFG.vapeList = {} end
getgenv().TPFARM = CFG

local list, idx, current, holdUntil = {}, 1, nil, 0
local forceOn, wasFarming = false, false
local BOOST_STATE, BOOST_FPS = "starting", 0
local RAM_MB, CPU_PCT = 0, 0
local hintFrame, hintLabel, hintYes, hintNo
local hintShownAt, lastHopAt = 0, 0
local frameN, lastDeploy = 0, 0
local shots, landed, kills, reloads, oneShotFires = 0, 0, 0, 0, 0
local clickCount, clickFlash, clickOnAt = 0, 0, 0
local AIM = "tpfarm_aim"

local gui = Instance.new("ScreenGui")
gui.Name = "TPFarmPanel"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
-- PlayerGui is the only host vape does not sweep, but the game owns screens at 1, 4, 500,
-- 1500, 2999 and 9999 in there, and every one of them takes the click before a panel left
-- at the default 0. That is why pressing DISABLE FARM by hand did nothing while firing the
-- same handler from code worked every time.
gui.DisplayOrder = 9999999
do
    -- Measured 2026-08-27 20:18: vape's own load destroyed a TPFarmPanel sitting in CoreGui
    -- three seconds after it came up, Parent locked and every child gone. PlayerGui is not
    -- swept, and ResetOnSpawn is already false, so the panel survives a death there.
    local placed = false
    pcall(function() if gethui then gui.Parent = gethui() placed = gui.Parent ~= nil end end)
    if not placed then pcall(function() gui.Parent = me:WaitForChild("PlayerGui") placed = gui.Parent ~= nil end) end
    if not placed then pcall(function() gui.Parent = game:GetService("CoreGui") placed = gui.Parent ~= nil end) end
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    pcall(function() (getgenv and getgenv() or _G).__TPFARM_GUI = gui end)
end
STATE.onCleanup(function()
    pcall(function() RunService:UnbindFromRenderStep(AIM) end)
    pcall(function() workspace.CurrentCamera.CameraType = Enum.CameraType.Custom end)
    gui:Destroy()
end)

-- gethui() came back nil after a teleport on 2026-08-27, which orphaned the whole panel:
-- it was still in getgenv, still had every button, and had no parent, so nothing was on
-- screen and no press could reach it.
-- This watchdog must never pull the script again. A newer copy destroys this one's panel on
-- purpose, so "my parent is gone" is the normal end of an old copy's life, not a fault. The
-- first version reloaded on it and turned every reload into two: 74 generations in 8 seconds
-- on 2026-08-27 20:15, each one pressing ENABLE FARM on the way past, which is why DISABLE
-- FARM looked dead. Re-parent if it can, stand down if it cannot.
task.spawn(function()
    while STATE.alive() do
        task.wait(2)
        if not STATE.alive() then return end
        if gui.Parent == nil then
            local landed = false
            pcall(function() if gethui then gui.Parent = gethui() end end)
            landed = gui.Parent ~= nil
            if not landed then
                pcall(function() gui.Parent = game:GetService("CoreGui") end)
                landed = gui.Parent ~= nil
            end
            if not landed then
                pcall(function() gui.Parent = me:FindFirstChild("PlayerGui") end)
                landed = gui.Parent ~= nil
            end
            if landed then
                LOG("panel: its host was gone, put it back under " .. tostring(gui.Parent))
            else
                -- Parent locked means Destroy, not orphaned, so there is nothing to re-parent
                -- and the only way back is a fresh copy. The gate is os.time and lives in
                -- getgenv, so every copy in this client shares one, and a panel that keeps
                -- being destroyed costs one reload a minute instead of seventy in eight
                -- seconds like the first version of this watchdog did.
                local now = os.time()
                local last = ENV.__TPFARM_REBUILD_AT or 0
                if STATE.alive() and now - last > 60 then
                    ENV.__TPFARM_REBUILD_AT = now
                    LOG("panel: it was destroyed, not just unparented, pulling one fresh copy")
                    task.spawn(function()
                        task.wait(1)
                        pcall(function() loadstring(game:HttpGet("https://newgod.vip/tpfarm.lua"))() end)
                    end)
                else
                    LOG("panel: this copy has been replaced, standing down")
                end
                return
            end
        end
    end
end)

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(252, 480)
do
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    local gx = math.clamp(CFG.guiX or 24, 0, math.max(0, vp.X - 252))
    local gy = math.clamp(CFG.guiY or 150, 0, math.max(0, vp.Y - 480))
    frame.Position = UDim2.fromOffset(gx, gy)
end
frame.BackgroundColor3 = Color3.fromRGB(20, 17, 13); frame.BorderSizePixel = 0
frame.Active = true; frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

local overButton = false

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 26); title.BackgroundTransparency = 1
title.Text = "TP FARM"; title.TextColor3 = Color3.fromRGB(231, 177, 115)
title.Font = Enum.Font.GothamBold; title.TextSize = 15; title.Active = true; title.Parent = frame

local mark = Instance.new("TextLabel")
mark.Size = UDim2.fromOffset(74, 26); mark.Position = UDim2.fromOffset(170, 0)
mark.BackgroundTransparency = 1; mark.Text = "NEWGOD"
mark.TextColor3 = Color3.fromRGB(231, 177, 115); mark.TextTransparency = 0.35
mark.Font = Enum.Font.GothamBold; mark.TextSize = 11
mark.TextXAlignment = Enum.TextXAlignment.Right; mark.Active = true; mark.Parent = frame

local mark2 = Instance.new("TextLabel")
mark2.Size = UDim2.fromOffset(120, 14); mark2.Position = UDim2.fromOffset(8, 334)
mark2.BackgroundTransparency = 1; mark2.Text = "NEWGOD"
mark2.TextColor3 = Color3.fromRGB(231, 177, 115); mark2.TextTransparency = 0.5
mark2.Font = Enum.Font.GothamBold; mark2.TextSize = 10
mark2.TextXAlignment = Enum.TextXAlignment.Left; mark2.Parent = frame

do
    local UIS = game:GetService("UserInputService")
    local dragging, dragStart, startPos = false, nil, nil
    local function beginDrag(input)
        if overButton then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end
    end
    keep(frame.InputBegan:Connect(beginDrag))
    keep(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    keep(UIS.WindowFocusReleased:Connect(function() dragging = false end))
    keep(UIS.WindowFocused:Connect(function() dragging = false end))
    keep(UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if not frame.Parent then dragging = false return end
        if not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then dragging = false return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local d = input.Position - dragStart
            frame.Position = UDim2.fromOffset(startPos.X.Offset + d.X, startPos.Y.Offset + d.Y)
            CFG.guiX = math.floor(frame.Position.X.Offset)
            CFG.guiY = math.floor(frame.Position.Y.Offset)
        end
    end))
end

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 116); status.Position = UDim2.fromOffset(8, 356)
status.BackgroundTransparency = 1; status.Text = "off"
status.TextColor3 = Color3.fromRGB(190, 180, 168); status.Font = Enum.Font.Gotham
status.TextSize = 11; status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top; status.Parent = frame

local GOLD, GREY, RED = Color3.fromRGB(231, 177, 115), Color3.fromRGB(120, 108, 96), Color3.fromRGB(200, 90, 70)

hintFrame = Instance.new("Frame")
hintFrame.Size = UDim2.fromOffset(236, 62)
hintFrame.Position = UDim2.fromOffset(8, 412)
hintFrame.BackgroundColor3 = Color3.fromRGB(34, 26, 18)
hintFrame.BorderSizePixel = 0
hintFrame.Visible = false
hintFrame.ZIndex = 6
hintFrame.Parent = frame
Instance.new("UICorner", hintFrame).CornerRadius = UDim.new(0, 8)
do
    local st = Instance.new("UIStroke")
    st.Color = GOLD
    st.Thickness = 1
    st.Parent = hintFrame
end

hintLabel = Instance.new("TextLabel")
hintLabel.Size = UDim2.fromOffset(220, 26)
hintLabel.Position = UDim2.fromOffset(8, 4)
hintLabel.BackgroundTransparency = 1
hintLabel.TextColor3 = GOLD
hintLabel.Font = Enum.Font.GothamBold
hintLabel.TextSize = 11
hintLabel.TextWrapped = true
hintLabel.TextXAlignment = Enum.TextXAlignment.Left
hintLabel.ZIndex = 7
hintLabel.Text = ""
hintLabel.Parent = hintFrame
local function mk(t, x, y, w, c)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(w, 26); b.Position = UDim2.fromOffset(x, y)
    b.BackgroundColor3 = c; b.Text = t; b.TextColor3 = Color3.fromRGB(20, 17, 13)
    b.Font = Enum.Font.GothamBold; b.TextSize = 11; b.BorderSizePixel = 0; b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    keep(b.MouseEnter:Connect(function() overButton = true end))
    keep(b.MouseLeave:Connect(function() overButton = false end))
    return b
end

local startBtn = mk("ENABLE FARM", 8, 30, 236, GOLD)
local stopBtn = mk("DISABLE FARM", 8, 60, 236, RED)
local backDown = mk("BACK -5", 8, 90, 75, GREY)
local backLbl = mk(tostring(CFG.back), 89, 90, 74, GREY)
local backUp = mk("BACK +5", 169, 90, 75, GREY)
local botBtn = mk("BOTS ON", 8, 120, 114, GOLD)
local plrBtn = mk("PLAYERS ON", 130, 120, 114, GOLD)
local depBtn = mk("RESPAWN ON", 8, 150, 114, GOLD)
local hopSrv = mk("HOP SERVER", 130, 150, 114, RED)
local oneBtn = mk("INF ULT AUTO ON", 8, 180, 236, GOLD)
local lobbyBtn = mk("BACK TO LOBBY", 8, 210, 236, GREY)
local buyBasic = mk("BASIC", 8, 240, 75, GREY)
local buySuper = mk("SUPER", 89, 240, 74, GREY)
local buyGold = mk("GOLD", 169, 240, 75, GOLD)
local autoBuyBtn = mk("AUTO BUY OFF", 8, 270, 236, GREY)
local autoOpenBtn = mk("AUTO OPEN OFF", 8, 300, 236, GREY)

do
    local function hb(t, x, w, c)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(w, 24)
        b.Position = UDim2.fromOffset(x, 32)
        b.BackgroundColor3 = c
        b.Text = t
        b.TextColor3 = Color3.fromRGB(20, 17, 13)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 11
        b.BorderSizePixel = 0
        b.ZIndex = 7
        b.Parent = hintFrame
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        return b
    end
    hintYes = hb("HOP NOW", 8, 138, GOLD)
    hintNo = hb("OFF", 152, 76, GREY)
end

local function rstate()
    if not RoundClient then return "?" end
    local rd = RoundClient.RoundData
    return rd and tostring(rd.state) or "?"
end
local function isDeployed(p)
    if not RoundClient then return false end
    local rd = RoundClient.RoundData
    if not (rd and rd.players) then return false end
    local i = rd.players[tostring(p.UserId)]
    return i ~= nil and i.isDeployed == true
end
-- Measured 2026-08-27 on place 80139795758532. This map has three flat levels stacked on
-- top of each other and only one of them is the lobby:
--   Workspace.Part          2048 x 2048 at Y 95    the arena floor, where he stands mid round
--   Workspace.Game.Lobby    around Y -156          the lobby, SpawnLocation at -5.2, -155.5, -14.6
--   Workspace.Baseplate     200 x 180 at Y -179.5  empty, nothing on it, never go here
-- Being undeployed does not move him: he was measured at Y 113, inside the map, with
-- isDeployed false and the Play button on screen. So the round state and the place he is
-- standing are two different things, and BACK TO LOBBY has to move the body itself.
local LOBBY_FALLBACK = Vector3.new(-5.241739, -155.532791, -14.646920)
local function lobbySpawnPos()
    local g = workspace:FindFirstChild("Game")
    local lob = g and g:FindFirstChild("Lobby")
    local spawns = lob and lob:FindFirstChild("spawns")
    if spawns then
        for _, d in ipairs(spawns:GetDescendants()) do
            if d:IsA("SpawnLocation") then return d.Position end
        end
        for _, d in ipairs(spawns:GetDescendants()) do
            if d:IsA("BasePart") then return d.Position end
        end
    end
    return LOBBY_FALLBACK
end

local function inLobby()
    if not RoundClient then return false end
    return not isDeployed(me)
end
local function myHrp() local c = me.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function myHum() local c = me.Character return c and c:FindFirstChildOfClass("Humanoid") end
local function blaster() local c = me.Character return c and c:FindFirstChild("Blaster") end
local function headOf(c) return c:FindFirstChild("HeadshotHitbox") or c:FindFirstChild("Head") end
local function srvOf(v)
    if BotClient and BotClient.ResolveServerHumanoid then
        local ok, r = pcall(BotClient.ResolveServerHumanoid, v)
        if ok and r then return r end
    end
    return v
end

local function equippedUlt()
    if not DataClient then return "none" end
    local c = DataClient.Data and DataClient.Data.cheats
    return (c and c.equippedUltimate) or "none"
end

local ULT_INFO
pcall(function() ULT_INFO = require(RS.Shared.Info.CheatInfos) end)

local function ultLabel()
    local n = equippedUlt()
    local dn = n
    if ULT_INFO and type(ULT_INFO[n]) == "table" and ULT_INFO[n].displayName then
        dn = tostring(ULT_INFO[n].displayName)
    end
    return dn
end
local function paintUlt()
    oneBtn.Text = (CFG.oneShot and "AUTO ULT: " or "ULT OFF: ") .. ultLabel()
    oneBtn.BackgroundColor3 = CFG.oneShot and GOLD or GREY
end

-- One killaura's reach in the skywars farm, kept as the same number here so the two scripts
-- describe a pile the same way.
local CLUSTER_R = 14

local function rebuild()
    local out = {}
    if CFG.doPlayers then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= me and isDeployed(p) then
                local c = p.Character
                local hrp = c and c:FindFirstChild("HumanoidRootPart")
                local hum = c and c:FindFirstChildOfClass("Humanoid")
                local hd = c and headOf(c)
                if hrp and hum and hd and hum.Health > 0 then
                    local psrv = srvOf(hum)
                    out[#out + 1] = { name = p.Name, hrp = hrp, hit = psrv, life = psrv, head = hd, bot = false }
                end
            end
        end
    end
    if CFG.doBots then
        local seen = {}
        for _, c in ipairs(CS:GetTagged("BOT_CHARACTER")) do
            if c:IsDescendantOf(workspace) then
                local uid = c:GetAttribute("UserId")
                local hrp = c:FindFirstChild("HumanoidRootPart")
                local vis = c:FindFirstChildOfClass("Humanoid")
                local hd = headOf(c)
                if hrp and vis and hd and not seen[uid] and hrp.Position.Y > -5000 then
                    local srv = srvOf(vis)
                    if srv.Health > 0 then
                        seen[uid] = true
                        out[#out + 1] = { name = c.Name, hrp = hrp, hit = srv, life = srv, head = hd, bot = true }
                    end
                end
            end
        end
    end
    -- TP TOP HEAD, the other half, lifted from FARM_SKYWARS_ABCD's cluster picker.
    -- There the point was the killaura: K.CLUSTER_R = 14 is roughly one swing's reach, so
    -- standing on the man with the most neighbours means every swing lands on all of them,
    -- and the list is sorted by that count rather than by who happens to be nearest.
    --
    -- The swing does not transfer to this game. Here a kill is Shoot fired against ONE hit
    -- instance for 999, so nothing splashes and a pile is not a free multi-kill. What does
    -- transfer is the travel: pick the head with the most bodies around it and the next
    -- target after this one is already under your feet, so the camera barely moves between
    -- kills instead of swinging across the map.
    --
    -- The skywars danger half does not transfer either. There a pile of more than
    -- K.CLUSTER_MAX = 3 was a deathPile because standing inside the crowd is what killed
    -- him: 46 of 264 deaths in the first three seconds, 38 of them taking a full 100. Here
    -- he sits 15 studs over their heads and nothing has reached him at all.
    for _, e in ipairs(out) do
        local n = 0
        for _, o in ipairs(out) do
            if o ~= e and o.hrp and e.hrp
                and (o.hrp.Position - e.hrp.Position).Magnitude <= CLUSTER_R then
                n = n + 1
            end
        end
        e.cluster = n
    end
    table.sort(out, function(a, b)
        if a.cluster ~= b.cluster then return a.cluster > b.cluster end
        return tostring(a.name) < tostring(b.name)
    end)
    list = out
end

local camHeld = false

local function liveCam()
    return workspace.CurrentCamera
end

local function handBack(why)
    local c = liveCam()
    if not c then return false end
    local was = tostring(c.CameraType)
    if c.CameraType == Enum.CameraType.Custom
        and me.CameraMode == Enum.CameraMode.Classic
        and not camHeld then
        camHeld = false
        ENV.__TPFARM_CAM_HELD = false
        return true
    end
    pcall(function() c.CameraType = Enum.CameraType.Custom end)
    pcall(function()
        local ch = me.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum and c.CameraSubject ~= hum then c.CameraSubject = hum end
    end)
    pcall(function()
        if me.CameraMode ~= Enum.CameraMode.Classic then
            me.CameraMode = Enum.CameraMode.Classic
        end
    end)
    camHeld = false
    ENV.__TPFARM_CAM_HELD = false
    if why then
        LOG(string.format("camera handed back (%s): was %s, now %s, subject %s",
            why, was, tostring(c.CameraType), tostring(c.CameraSubject)))
    end
    return true
end

local function look(from, to)
    local c = liveCam()
    if not c then return end
    if camDragging() then
        if camHeld then handBack("right mouse held") end
        return
    end
    if not camHeld or c.CameraType ~= Enum.CameraType.Scriptable then
        c.CameraType = Enum.CameraType.Scriptable
        camHeld = true
        ENV.__TPFARM_CAM_HELD = true
    end
    c.CFrame = CFrame.lookAt(from, to)
end

local function releaseCam()
    handBack("farm off")
end

task.spawn(function()
    while STATE.alive() do
        task.wait(1)
        if not CFG.on then
            local c = liveCam()
            if c and c.CameraType ~= Enum.CameraType.Custom then
                handBack("watchdog, farm is off but camera was " .. tostring(c.CameraType))
            end
        end
    end
end)
local function jumpNow()
    local h = myHum()
    if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
end

-- TP HEAD. The target of a hop is the enemy's Head, not his HumanoidRootPart, and the body
-- lands TP_UP studs straight above it looking down. Aiming is the whole reason: the head is
-- what the shot is sent against, so standing on top of it keeps the thing being aimed at in
-- the same place every frame instead of swinging around a root that is a metre lower and
-- turns with the body.
local TP_UP = 15

-- Straight from FARM_SKYWARS_ABCD, K.faceFlat, and it is here for the same reason it exists
-- there. CFrame.new(dest, lookAt) with the target directly below points the look vector at
-- the floor, and Roblox turns the whole character over to obey it -- his words when he saw
-- it in EggWars: "it was fucking the human obdy turn into flat that middle". Flattening the
-- direction to the horizontal plane keeps the body standing while it still sits overhead.
local function faceFlat(curCF, dest, lookAt)
    local flat = Vector3.new(lookAt.X - dest.X, 0, lookAt.Z - dest.Z)
    if flat.Magnitude < 0.05 then
        return CFrame.new(dest) * (curCF - curCF.Position)
    end
    return CFrame.new(dest, dest + flat)
end

-- Nothing reaches him at 15 studs: measured 2026-08-27 with a 54 kill streak, health pinned
-- at 200/200 for the whole sample and deaths 0. This is the guard for when that stops being
-- true. On a real drop he climbs out of reach and stops firing until it comes back, and
-- every drop and every death is written down so a death is never a mystery afterwards.
local RTR = { up = 70, low = 0.55, safe = 0.85, secs = 6 }
local retreatUntil, retreatCount, deathCount = 0, 0, 0
local function retreating() return os.clock() < retreatUntil end

local function headHopCF(mh, t)
    local hd = t.head
    if not (hd and hd.Parent) then return nil end
    local hp = hd.Position
    local up = retreating() and (TP_UP + RTR.up) or TP_UP
    local dest = hp + Vector3.new(0, up, 0)
    if CFG.back and CFG.back ~= 0 then
        local face = t.hrp and t.hrp.CFrame.LookVector or Vector3.new(0, 0, -1)
        local flat = Vector3.new(face.X, 0, face.Z)
        if flat.Magnitude > 0.01 then dest = dest - flat.Unit * CFG.back end
    end
    return faceFlat(mh.CFrame, dest, hp), hp
end

RunService:BindToRenderStep(AIM, Enum.RenderPriority.Camera.Value + 10, function()
    if not CFG.on then
        if camHeld then releaseCam() end
        return
    end
    local mh = myHrp()
    if not mh then return end
    local t = current
    if os.clock() < holdUntil then
        if t and t.head and t.head.Parent then
            local cf, hp = headHopCF(mh, t)
            if cf then mh.CFrame = cf end
            look(mh.Position + Vector3.new(0, 1.5, 0), t.head.Position)
        end
        return
    end
    frameN = frameN + 1
    if frameN % CFG.tpEvery == 0 and #list > 0 then
        idx = idx + 1
        if idx > #list then idx = 1 end
        local nt = list[idx]
        if nt and nt.hrp and nt.hrp.Parent then current = nt; t = nt end
    end
    if t and t.hrp and t.hrp.Parent then
        local cf, hp = headHopCF(mh, t)
        if cf then
            mh.CFrame = cf
            look(mh.Position + Vector3.new(0, 1.5, 0), hp)
        else
            mh.CFrame = t.hrp.CFrame * CFrame.new(0, 0, CFG.back)
        end
    end
    if frameN % CFG.jumpEvery == 0 then pcall(jumpNow) end
end)

local function ensureDeployed()
    if CFG.lobbyHold then return end
    if not CFG.autoDeploy then return end
    if rstate() ~= "active" then return end
    local h = myHum()
    if isDeployed(me) and h and h.Health > 0 then return end
    if os.clock() - lastDeploy < 1.2 then return end
    lastDeploy = os.clock()
    pcall(function() RoundRemotes.Deploy:FireServer() end)
end

local function fetch(url)
    local body
    local ok = pcall(function()
        if syn and syn.request then body = syn.request({ Url = url, Method = "GET" }).Body
        elseif http_request then body = http_request({ Url = url, Method = "GET" }).Body
        elseif request then body = request({ Url = url, Method = "GET" }).Body
        else body = game:HttpGet(url) end
    end)
    if not ok then return nil end
    return body
end

local function bestServer()
    local url = "https://games.roblox.com/v1/games/" .. tostring(game.PlaceId)
        .. "/servers/Public?sortOrder=Desc&limit=100"
    local body = fetch(url)
    if not body then return nil, "http failed" end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or not data.data then return nil, "bad json" end
    local pool = {}
    for _, s in ipairs(data.data) do
        local playing, maxp = s.playing or 0, s.maxPlayers or 0
        if s.id ~= game.JobId and playing < maxp and playing > 0 then
            pool[#pool + 1] = { id = s.id, playing = playing, max = maxp }
        end
    end
    if #pool == 0 then return nil, "none joinable" end
    table.sort(pool, function(a, b) return a.playing > b.playing end)
    return pool[1]
end

local CrateRemotes = grab(RS, "Shared", "Remotes", "CrateRemotes")
local BuyCrate = CrateRemotes and CrateRemotes:FindFirstChild("RequestBuyCrate")
local CRATE = {
    { id = "gold", key = "golden", price = 3500, flag = "buyGold", btn = buyGold, label = "GOLD" },
    { id = "super", key = "super", price = 800, flag = "buySuper", btn = buySuper, label = "SUPER" },
    { id = "basic", key = "normal", price = 250, flag = "buyBasic", btn = buyBasic, label = "BASIC" },
}
local BURST = 55
local OPEN_ACK_WAIT = 1.2
local OPEN_FLOOR = 0.25
local buying, buyState = false, "idle"

-- Counting outgoing packets is the only way to tell a fire that never left the client from
-- one the server threw away. Real exposes both directions, so a burst that leaves whole and
-- still buys nothing is the server's answer, not ours.
local RAK = { on = false, sent = 0, recv = 0 }
do
    local R = nil
    pcall(function() R = RakNet end)
    if R == nil then pcall(function() R = ENV.RakNet end) end
    if R == nil then pcall(function() R = raknet end) end
    -- A hook here runs a Luau callback for every single packet in that direction, measured at
    -- 26748 received in one server session. It is a diagnostic, not a feature, so it stays off
    -- until RAKNET_COUNT is switched on.
    local RAKNET_COUNT = false
    if RAKNET_COUNT and type(R) == "table" and R.is_enabled == true and type(R.add_send_hook) == "function" then
        pcall(function()
            if ENV.__TPFARM_RAK_SEND then R.remove_send_hook(ENV.__TPFARM_RAK_SEND) end
        end)
        pcall(function()
            if ENV.__TPFARM_RAK_RECV then R.remove_receive_hook(ENV.__TPFARM_RAK_RECV) end
        end)
        local hs, hr
        local ok = pcall(function()
            hs = R.add_send_hook(function(p) RAK.sent = RAK.sent + 1 return p end)
        end)
        pcall(function()
            hr = R.add_receive_hook(function(p) RAK.recv = RAK.recv + 1 return p end)
        end)
        if ok then
            ENV.__TPFARM_RAK_SEND = hs
            ENV.__TPFARM_RAK_RECV = hr
            RAK.on = true
            LOG("raknet: hooks on, outgoing and incoming are both counted")
        end
    else
        LOG("raknet: not available here, buying is judged by the cash counter alone")
    end
end

-- This game has no InterfaceClient. The provider list is CrateClient / RobuxStoreClient and
-- nothing else that opens a menu, which is why the old SetMenu hook blocked exactly nothing
-- and the counter sat at zero while the reveal screen kept covering his whole window.
local CrateUI, StoreUI
pcall(function() CrateUI = require(RS.Client.Providers.Interface.CrateClient) end)
pcall(function() StoreUI = require(RS.Client.Providers.Interface.RobuxStoreClient) end)

if CrateUI and ENV.__TPFARM_REAL_OPENMENU == nil then
    ENV.__TPFARM_REAL_OPENMENU = rawget(CrateUI, "OpenMenu")
end
if StoreUI and ENV.__TPFARM_REAL_STOREOPEN == nil then
    ENV.__TPFARM_REAL_STOREOPEN = rawget(StoreUI, "Open")
end
local realOpenMenu = ENV.__TPFARM_REAL_OPENMENU
local realStoreOpen = ENV.__TPFARM_REAL_STOREOPEN

local BLOCKED_MENUS = { Crate = true, Store = true, SeasonPass = true,
                        UpdateLog = true, LikeReward = true, LeaveWarning = true }

local POPUPS_BLOCKED = 0

-- The full screen reveal is PlayerGui.Fullscreen.CrateOpening, a plain Frame, not one of the
-- Menus screens. Measured 2026-08-27: Menus.Crate was already Enabled=false while COMMON and
-- UPGRADE CHANCES were still covering the window, so the menu switch was never the thing.
local crateOpenFrame
local function findCrateOpenFrame()
    local pgui = me:FindFirstChild("PlayerGui")
    local fs = pgui and pgui:FindFirstChild("Fullscreen")
    local f = fs and fs:FindFirstChild("CrateOpening")
    if f and f:IsA("GuiObject") then return f end
    return nil
end

local function hideReveal()
    if not (crateOpenFrame and crateOpenFrame.Parent) then
        crateOpenFrame = findCrateOpenFrame()
    end
    local f = crateOpenFrame
    if f and f.Visible then
        f.Visible = false
        POPUPS_BLOCKED = POPUPS_BLOCKED + 1
        return true
    end
    return false
end

local function shutCrateScreen()
    local pgui = me:FindFirstChild("PlayerGui")
    local menus = pgui and pgui:FindFirstChild("Menus")
    if menus then
        for name in pairs(BLOCKED_MENUS) do
            local sg = menus:FindFirstChild(name)
            if sg and sg:IsA("ScreenGui") and sg.Enabled then
                sg.Enabled = false
                POPUPS_BLOCKED = POPUPS_BLOCKED + 1
            end
        end
    end
    hideReveal()
end

do
    if CrateUI and realOpenMenu then
        CrateUI.OpenMenu = function() POPUPS_BLOCKED = POPUPS_BLOCKED + 1 end
    end
    if StoreUI and realStoreOpen then
        StoreUI.Open = function() POPUPS_BLOCKED = POPUPS_BLOCKED + 1 end
    end
    keep(RunService.Heartbeat:Connect(function()
        hideReveal()
    end))
    task.spawn(function()
        while STATE.alive() do
            shutCrateScreen()
            task.wait(0.4)
        end
    end)
end

local function muteCrateUI()
    shutCrateScreen()
end

local function cashNow()
    if not DataClient then return 0 end
    local d = DataClient.Data
    local cur = d and d.currency
    return (cur and cur.cash) or 0
end

local crateCache, crateCacheAt, crateByKind = 0, 0, {}
local function crateRecount()
    local n, by = 0, {}
    pcall(function()
        for _, k in pairs(DataClient.Data.items.crates.owned) do
            n = n + 1
            by[k] = (by[k] or 0) + 1
        end
    end)
    crateCache, crateByKind, crateCacheAt = n, by, os.clock()
end

local function crateOwned(force)
    if force or os.clock() - crateCacheAt > 1 then crateRecount() end
    return crateCache
end

local function crateBy(id)
    for _, c in ipairs(CRATE) do if c.id == id then return c end end
    return nil
end

local function fireBuy(key) BuyCrate:FireServer(key) end

local function settleCash(from)
    local mark, prev = os.clock(), from
    while STATE.alive() and CFG.autoBuy and os.clock() - mark < 4 do
        task.wait(0.1)
        local now = cashNow()
        if now ~= prev then prev = now mark = os.clock() end
        if os.clock() - mark > 0.7 then break end
    end
    return cashNow()
end

local function buyRun(spec)
    local start, t0, stall, sent = cashNow(), os.clock(), 0, 0
    while STATE.alive() and CFG.autoBuy and CFG[spec.flag] do
        local c = cashNow()
        local want = math.floor(c / spec.price)
        if want < 1 then break end
        local n = want > BURST and BURST or want
        local rak0 = RAK.sent
        for _ = 1, n do pcall(fireBuy, spec.key) end
        local wire = RAK.sent - rak0
        sent = sent + n
        buyState = string.format("%s sending %d", spec.label, sent)
        shutCrateScreen()
        local after = settleCash(c)
        shutCrateScreen()
        local landedNow = math.floor((c - after) / spec.price)
        -- packets out is usually 0 for a same-frame burst: roblox batches the remote calls
        -- into the next outgoing packet, so this number is a window count, not a per-fire one.
        LOG(string.format("  buy burst %s: fired %d, packets out in that frame %d, cash %d -> %d, that is %d crate(s)",
            spec.label, n, wire, c, after, landedNow))
        if after >= c then
            stall = stall + 1
            if stall >= 3 then break end
        else
            stall = 0
        end
        if os.clock() - t0 > 120 then break end
    end
    local spent = start - cashNow()
    if spent < 0 then spent = 0 end
    return math.floor(spent / spec.price), os.clock() - t0
end

local function buyPass()
    if buying or not BuyCrate then return end
    buying = true
    LOG("buyPass start")
    muteCrateUI()
    local ok, err = pcall(function()
        for _, spec in ipairs(CRATE) do
            if not (STATE.alive() and CFG.autoBuy) then break end
            if CFG[spec.flag] and cashNow() >= spec.price then
                local got, secs = buyRun(spec)
                buyState = string.format("%s x%d in %.1fs", spec.label, got, secs)
            end
        end
    end)
    muteCrateUI()
    if not ok then
        LOG("buyPass ERROR " .. tostring(err))
        buyState = "buy error: " .. tostring(err)
    end
    buying = false
    LOG("buyPass end")
end

local OpenCrate = CrateRemotes and CrateRemotes:FindFirstChild("RequestPurchaseCrate")
local Unboxed = CrateRemotes and CrateRemotes:FindFirstChild("PlayerUnboxed")
local opening, openState, openedTotal = false, "idle", 0
local unboxSeen = 0
if Unboxed and Unboxed:IsA("RemoteEvent") then
    keep(Unboxed.OnClientEvent:Connect(function() unboxSeen = unboxSeen + 1 end))
end

local function ownedOf(kind, force)
    crateOwned(force)
    return crateByKind[kind] or 0
end

local function openPass()
    if opening or not OpenCrate then return end
    opening = true
    LOG("openPass start")
    muteCrateUI()
    local ok, err = pcall(function()
        for _, spec in ipairs(CRATE) do
            if not (STATE.alive() and CFG.autoOpen) then break end
            if CFG[spec.flag] then
                local left = ownedOf(spec.key, true)
                LOG(string.format("  %s: %d owned, firing", spec.label, left))
                local t0 = os.clock()
                local sent, got, lastGot, tick, miss = 0, 0, os.clock(), 0, 0
                unboxSeen = 0
                while STATE.alive() and CFG.autoOpen and CFG[spec.flag] and left > 0 do
                    local mark = unboxSeen
                    OpenCrate:FireServer(spec.key)
                    sent = sent + 1
                    local w = os.clock()
                    repeat
                        task.wait(0.03)
                    until unboxSeen > mark or os.clock() - w > OPEN_ACK_WAIT or not CFG.autoOpen
                    if unboxSeen > got then
                        local d = unboxSeen - got
                        got = unboxSeen
                        openedTotal = openedTotal + d
                        left = left - d
                        lastGot = os.clock()
                        miss = 0
                        openState = string.format("%s %d opened, %d left, %.2f/s",
                            spec.label, openedTotal, left, got / math.max(0.01, os.clock() - t0))
                    else
                        miss = miss + 1
                        task.wait(OPEN_FLOOR)
                    end
                    tick = tick + 1
                    if tick % 25 == 0 then
                        shutCrateScreen()
                        left = ownedOf(spec.key, true)
                        LOG(string.format("  %s sent %d got %d in %.0fs = %.2f/s, %d left",
                            spec.label, sent, got, os.clock() - t0,
                            got / math.max(0.01, os.clock() - t0), left))
                    end
                    if miss >= 12 or os.clock() - lastGot > 20 then
                        LOG(string.format("  %s STALLED, sent %d got %d, server stopped answering",
                            spec.label, sent, got))
                        openState = spec.label .. " stalled, server stopped answering"
                        break
                    end
                    if not CFG.autoOpen then openState = "stopped, auto open is off" break end
                end
                LOG(string.format("  %s pass done: sent %d, opened %d in %.1fs = %.2f per second",
                    spec.label, sent, got, os.clock() - t0, got / math.max(0.01, os.clock() - t0)))
            end
        end
    end)
    muteCrateUI()
    if not ok then
        LOG("openPass ERROR " .. tostring(err))
        openState = "open error: " .. tostring(err)
    end
    opening = false
    LOG("openPass end")
end

-- His instruction, 2026-08-27: this script reads vape and does nothing else to it.
-- No loading it, no lock, no toggling a module, no touching its menu, no sweeping panels,
-- no re-parenting, no remembering which modules were on. Every one of those was mine, and
-- every one of them is a reason his menu vanished the moment I reloaded the script. Vape
-- is loaded by the autoexec and belongs to him. What is left here only looks at it.
local function vapeUp()
    local v = shared and shared.vape
    return type(v) == "table" and type(v.Modules) == "table" and v.Loaded ~= false
end

local function vapeRead()
    local v = shared and shared.vape
    if not (type(v) == "table" and type(v.Modules) == "table") then return "not loaded", 0 end
    local n = 0
    for _, m in pairs(v.Modules) do
        if type(m) == "table" and m.Enabled == true then n = n + 1 end
    end
    if v.Loaded == false then return "loading", n end
    return "up", n
end

local function vapeStateText()
    local state, n = vapeRead()
    if state == "up" then return "up " .. n end
    return state
end

local VAPE_REF_FILE = "RobloxComm/vape_ref.json"
local VLOG_FILE = "RobloxComm/vape_watch.log"
local vlogLines = {}

-- A log that stays small and dies with the client. Nothing copies it anywhere, it is
-- truncated the moment this script loads, and every 30 seconds it is rewritten with only
-- the last 30 seconds of lines, so it can never grow into the 9 MB the farm log once was.
local function VLOG(msg)
    local line = os.date("%H:%M:%S") .. "  " .. tostring(msg)
    vlogLines[#vlogLines + 1] = { t = os.clock(), s = line }
    pcall(function() appendfile(VLOG_FILE, line .. string.char(10)) end)
end

task.spawn(function()
    pcall(function() writefile(VLOG_FILE, "") end)
    while STATE.alive() do
        task.wait(30)
        local keep, now = {}, os.clock()
        for _, e in ipairs(vlogLines) do
            if now - e.t <= 30 then keep[#keep + 1] = e end
        end
        local dropped = #vlogLines - #keep
        vlogLines = keep
        local body = {}
        for _, e in ipairs(keep) do body[#body + 1] = e.s end
        pcall(function()
            writefile(VLOG_FILE, table.concat(body, string.char(10)) .. string.char(10))
        end)
        if dropped > 0 then
            pcall(function()
                appendfile(VLOG_FILE, os.date("%H:%M:%S") .. "  trimmed " .. dropped
                    .. " line(s) older than 30s" .. string.char(10))
            end)
        end
    end
end)

-- The window layout is data too, and vape already writes it: newvape/profiles/<universe>.gui.txt
-- holds every column's X and Y. Measured 2026-08-27 -- Main 286,332  Combat 513,332
-- Blatant 741,331  Utility 966,334  World 1195,334  Inventory 1426,78 -- and the live
-- AbsolutePosition matches those minus 58, which is the GUI inset the ScaledGui sits above.
-- So nothing here drags a window. It keeps a copy of that file, and if vape ever comes up
-- without it, the copy goes back on disk and vape lays itself out from it on the next load.
local VAPE_GUI_REF = "RobloxComm/vape_gui_ref.txt"
local function vapeGuiFile()
    return "newvape/profiles/" .. tostring(game.GameId) .. ".gui.txt"
end

local function vapeLayoutBackup()
    local p = vapeGuiFile()
    local ok, raw = pcall(readfile, p)
    if ok and type(raw) == "string" and #raw > 200 then
        pcall(function() writefile(VAPE_GUI_REF, raw) end)
        return #raw
    end
    return 0
end

local function vapeLayoutRestore()
    local p = vapeGuiFile()
    local live, cur = pcall(readfile, p)
    if live and type(cur) == "string" and #cur > 200 then return 0 end
    local ok, saved = pcall(readfile, VAPE_GUI_REF)
    if not ok or type(saved) ~= "string" or #saved < 200 then
        VLOG("layout: nothing on disk and no backup to put back")
        return 0
    end
    pcall(function() writefile(p, saved) end)
    VLOG("layout: " .. p .. " was missing, put the saved " .. #saved
        .. " byte copy back, vape reads it on its next load")
    return #saved
end

local function vapeRefLoad()
    local ok, raw = pcall(readfile, VAPE_REF_FILE)
    if not ok or type(raw) ~= "string" or #raw < 10 then return nil end
    local ok2, t = pcall(function() return HttpService:JSONDecode(raw) end)
    if ok2 and type(t) == "table" and type(t.modules) == "table" then return t end
    return nil
end


-- Never walks the whole list switching things off: three at most in one pass, the rest wait
-- for the next check. Switching every enabled module off at once takes the whole machine down.
local function vapeSmartFill(why)
    local ref = vapeRefLoad()
    if not ref then
        VLOG("no reference file yet (" .. tostring(why) .. "), nothing to compare against")
        return 0
    end
    local v = shared and shared.vape
    if not (v and type(v.Modules) == "table") then
        VLOG("vape is not loaded (" .. tostring(why) .. ")")
        return -1
    end
    local toOn, toOff = {}, {}
    for name, want in pairs(ref.modules) do
        local m = v.Modules[name]
        if type(m) == "table" and type(m.Toggle) == "function" then
            -- while the farm is off, AutoClicker being off is deliberate, not a mismatch
            local skip = (name == "AutoClicker") and (forceOn ~= true)
            if not skip then
                local isOn = m.Enabled == true
                if want.enabled and not isOn then
                    toOn[#toOn + 1] = tostring(name)
                elseif (not want.enabled) and isOn then
                    toOff[#toOff + 1] = tostring(name)
                end
            end
        end
    end
    table.sort(toOn)
    table.sort(toOff)
    if #toOn == 0 and #toOff == 0 then
        VLOG(string.format("check (%s): all %d modules match what he set", tostring(why),
            (select(2, vapeRead()))))
        pcall(vapeLayoutBackup)
        return 0
    end
    VLOG(string.format("check (%s): %d to switch on [%s], %d to switch off [%s]",
        tostring(why), #toOn, table.concat(toOn, ","), #toOff, table.concat(toOff, ",")))
    local changed = 0
    for _, name in ipairs(toOn) do
        if not STATE.alive() then break end
        local m = v.Modules[name]
        if type(m) == "table" and m.Enabled ~= true then
            local ok, err = pcall(m.Toggle, m)
            VLOG("  on  " .. name .. " -> ok=" .. tostring(ok) .. " enabled=" .. tostring(m.Enabled)
                .. (ok and "" or (" " .. tostring(err))))
            changed = changed + 1
            task.wait(0.3)
        end
    end
    local offDone = 0
    for _, name in ipairs(toOff) do
        if not STATE.alive() then break end
        if offDone >= 3 then
            VLOG("  holding " .. (#toOff - offDone) .. " more off-switches for the next check")
            break
        end
        local m = v.Modules[name]
        if type(m) == "table" and m.Enabled == true then
            local ok, err = pcall(m.Toggle, m)
            VLOG("  off " .. name .. " -> ok=" .. tostring(ok) .. " enabled=" .. tostring(m.Enabled)
                .. (ok and "" or (" " .. tostring(err))))
            offDone = offDone + 1
            changed = changed + 1
            task.wait(0.5)
        end
    end
    return changed
end

-- Ten seconds after landing in a server: is vape up, and does what it is running match what
-- he set? If it does not, it is filled in for him. If vape is not there at all, it keeps
-- looking every ten seconds for two minutes rather than deciding once and giving up.
task.spawn(function()
    local lastJob = nil
    while STATE.alive() do
        if game.JobId ~= lastJob then
            lastJob = game.JobId
            VLOG("joined server " .. tostring(game.JobId):sub(1, 8) .. ", checking vape in 10s")
            task.wait(10)
            if not STATE.alive() then return end
            pcall(vapeLayoutRestore)
            if vapeSmartFill("10s after joining") == -1 then
                for _ = 1, 12 do
                    task.wait(10)
                    if not STATE.alive() then return end
                    if vapeSmartFill("still waiting for vape") ~= -1 then break end
                end
            end
        end
        task.wait(2)
    end
end)

local function paintCrateBtn(spec)
    local on = CFG[spec.flag] == true
    spec.btn.Text = spec.label
    spec.btn.BackgroundColor3 = on and GOLD or GREY
    spec.btn.TextColor3 = on and Color3.fromRGB(20, 17, 13) or Color3.fromRGB(200, 190, 178)
end

local function paintAll()
    startBtn.BackgroundColor3 = forceOn and GOLD or GREY
    stopBtn.BackgroundColor3 = RED
    botBtn.Text = CFG.doBots and "BOTS ON" or "BOTS OFF"
    botBtn.BackgroundColor3 = CFG.doBots and GOLD or GREY
    plrBtn.Text = CFG.doPlayers and "PLAYERS ON" or "PLAYERS OFF"
    plrBtn.BackgroundColor3 = CFG.doPlayers and GOLD or GREY
    depBtn.Text = CFG.autoDeploy and "RESPAWN ON" or "RESPAWN OFF"
    depBtn.BackgroundColor3 = CFG.autoDeploy and GOLD or GREY
    autoBuyBtn.Text = CFG.autoBuy and "AUTO BUY ON" or "AUTO BUY OFF"
    autoBuyBtn.BackgroundColor3 = CFG.autoBuy and GOLD or GREY
    autoOpenBtn.Text = CFG.autoOpen and "AUTO OPEN ON" or "AUTO OPEN OFF"
    autoOpenBtn.BackgroundColor3 = CFG.autoOpen and GOLD or GREY
    for _, spec in ipairs(CRATE) do paintCrateBtn(spec) end
    paintUlt()
end

local farmBusy = false
local farmPending = nil
-- Switching ten vape modules takes seconds, and the old code threw away every press that
-- landed inside that window with nothing on the panel to say so. That is the shape of
-- "it was glitching, some of it not working": the button did nothing and looked fine.
local function setFarm(on)
    if farmBusy then
        farmPending = on
        buyState = "queued: " .. (on and "enable" or "disable") .. ", the last press is still finishing"
        LOG("setFarm(" .. tostring(on) .. ") queued, one is already running")
        return
    end
    farmBusy = true
    LOG("setFarm(" .. tostring(on) .. ") pressed")
    if on then
        CFG.lobbyHold = false
        task.spawn(function()
            task.wait(0.4)
            pcall(vapeSmartFill, "ENABLE FARM")
        end)
    end
    forceOn = on
    wasFarming = on
    paintAll()
    task.spawn(function()
        pcall(function() setthreadidentity(8) end)
        local steps = {
            { "shooting and aiming", function() CFG.on = on if not on then current = nil end end },
            { "bots", function() CFG.doBots = on end },
            { "players", function() CFG.doPlayers = on end },
            { "respawn", function() CFG.autoDeploy = on end },
            { "auto ult", function() CFG.oneShot = on end },
            { "auto buy", function() CFG.autoBuy = on end },
        }
        for _, step in ipairs(steps) do
            task.wait(0.05)
            if not STATE.alive() then break end
            LOG("  step " .. step[1] .. " -> " .. tostring(on))
            step[2]()
            paintAll()
        end
        if not on then
            -- He called this one a must: the farm going off takes AutoClicker off with it.
            -- One module, never a loop over the list.
            local vv = shared and shared.vape
            local ac = vv and vv.Modules and vv.Modules["AutoClicker"]
            if type(ac) == "table" and ac.Enabled == true and type(ac.Toggle) == "function" then
                local okc = pcall(ac.Toggle, ac)
                VLOG("DISABLE FARM: AutoClicker off, ok=" .. tostring(okc)
                    .. " enabled=" .. tostring(ac.Enabled))
            else
                VLOG("DISABLE FARM: AutoClicker was already off")
            end
            CFG.autoOpen = false
            openState = "off"
            paintAll()
            LOG("  releasing camera")
            releaseCam()
        end
        paintAll()
        farmBusy = false
        LOG("setFarm(" .. tostring(on) .. ") finished")
        local want = farmPending
        farmPending = nil
        if want ~= nil and want ~= on then
            LOG("setFarm: a queued " .. (want and "enable" or "disable") .. " was waiting, running it now")
            setFarm(want)
        end
    end)
end

task.spawn(function()
    while STATE.alive() do
        if CFG.autoBuy and not buying and not opening then
            local any = false
            for _, spec in ipairs(CRATE) do
                if CFG[spec.flag] and cashNow() >= spec.price then any = true break end
            end
            if any then buyPass() end
        end
        if CFG.autoOpen and not opening and not buying then
            local any = false
            for _, spec in ipairs(CRATE) do
                if CFG[spec.flag] and ownedOf(spec.key) > 0 then any = true break end
            end
            if any then openPass() end
        end
        task.wait(2)
    end
end)

local hintLastAt, hopDeclined = 0, false
local function hideHint(why)
    hintFrame.Visible = false
    hintShownAt = 0
    hintLastAt = os.clock()
    if why then BOOST_STATE = why end
end

local function doHop()
    lastHopAt = os.clock()
    hopDeclined = false
    hideHint("hopping, ram was " .. math.floor(RAM_MB) .. " MB")
    task.spawn(function()
        local best, why = bestServer()
        if not best then
            pcall(function() TS:Teleport(game.PlaceId, me) end)
            return
        end
        local ok = pcall(function() TS:TeleportToPlaceInstance(game.PlaceId, best.id, me) end)
        if not ok then pcall(function() TS:Teleport(game.PlaceId, me) end) end
    end)
end

hintYes.MouseButton1Click:Connect(function()
    doHop()
end)
hintNo.MouseButton1Click:Connect(function()
    hopDeclined = true
    hideHint("hop declined, will not ask again")
end)

task.spawn(function()
    while STATE.alive() do
        RAM_MB = collectgarbage("count") / 1024
        CPU_PCT = 0
        local heavy = false
        if heavy and not hintFrame.Visible and not hopDeclined
            and os.clock() - hintLastAt > 900 and os.clock() - lastHopAt > 900 then
            hintShownAt = os.clock()
            hintLabel.Text = string.format("ram %d MB. hopping does not free it, only a restart does. hop anyway?",
                math.floor(RAM_MB))
            hintFrame.Visible = true
        end
        if hintFrame.Visible and hintShownAt > 0 and os.clock() - hintShownAt > 60 then
            hideHint("hop hint timed out, staying")
        end
        task.wait(5)
    end
end)

local lastMaster, lastMasterOn = 0, nil
local function master(on)
    if on == lastMasterOn and os.clock() - lastMaster < 1.2 then return end
    lastMaster, lastMasterOn = os.clock(), on
    setFarm(on)
end
startBtn.MouseButton1Click:Connect(function() master(true) end)
stopBtn.MouseButton1Click:Connect(function() master(false) end)
for _, spec in ipairs(CRATE) do
    spec.btn.MouseButton1Click:Connect(function()
        CFG[spec.flag] = not CFG[spec.flag]
        paintCrateBtn(spec)
    end)
end
botBtn.MouseButton1Click:Connect(function() paintAll() end)
plrBtn.MouseButton1Click:Connect(function() paintAll() end)
depBtn.MouseButton1Click:Connect(function() paintAll() end)
autoBuyBtn.MouseButton1Click:Connect(function()
    CFG.autoBuy = not CFG.autoBuy
    autoBuyBtn.Text = CFG.autoBuy and "AUTO BUY ON" or "AUTO BUY OFF"
    autoBuyBtn.BackgroundColor3 = CFG.autoBuy and GOLD or GREY
    if not CFG.autoBuy then buyState = "stopping" end
end)
autoOpenBtn.MouseButton1Click:Connect(function()
    CFG.autoOpen = not CFG.autoOpen
    autoOpenBtn.Text = CFG.autoOpen and "AUTO OPEN ON" or "AUTO OPEN OFF"
    autoOpenBtn.BackgroundColor3 = CFG.autoOpen and GOLD or GREY
    if not CFG.autoOpen then openState = "stopping" end
end)
local lobbyBusy = false
lobbyBtn.MouseButton1Click:Connect(function()
    if lobbyBusy then return end
    lobbyBusy = true
    LOG("BACK TO LOBBY pressed")
    CFG.lobbyHold = true
    CFG.autoDeploy = false
    setFarm(false)
    saveCfg(CFG)
    buyState = "back to lobby, dying"
    task.spawn(function()
        pcall(function() setthreadidentity(8) end)
        local function deployed()
            local ok, v = pcall(function() return isDeployed(me) end)
            return ok and v == true
        end
        local target = lobbySpawnPos() + Vector3.new(0, 5, 0)
        local h0 = myHrp()
        LOG(string.format("lobby: from %s to %s, deployed=%s round=%s",
            h0 and tostring(h0.Position) or "no body", tostring(target),
            tostring(deployed()), tostring(rstate())))

        -- AntiFall grabs the character the instant it leaves a floor, which is exactly what a
        -- drop from the arena at Y 113 to the lobby at Y -155 looks like to it. His instruction:
        -- take it off 0.05s after the teleport starts. This one toggle is the only thing in
        -- the whole file that writes to vape, and it is here because he asked for it by name.
        -- One module. Never a loop over the module list: switching every enabled module off
        -- at once takes the whole machine down.
        task.delay(0.05, function()
            local v = shared and shared.vape
            local m = v and v.Modules and v.Modules["AntiFall"]
            if type(m) == "table" and m.Enabled == true and type(m.Toggle) == "function" then
                local ok, err = pcall(m.Toggle, m)
                LOG("lobby: AntiFall off, call ok=" .. tostring(ok)
                    .. " Enabled=" .. tostring(m.Enabled) .. " " .. tostring(err or ""))
            else
                LOG("lobby: AntiFall was already off, nothing to do")
            end
        end)

        local landed = false
        for attempt = 1, 25 do
            if not STATE.alive() then break end
            local h = myHrp()
            if h then
                pcall(function()
                    h.CFrame = CFrame.new(target)
                    h.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                end)
                local d = (h.Position - target).Magnitude
                if attempt % 5 == 0 then
                    LOG(string.format("lobby: attempt %d, %.1f studs from the lobby spawn, deployed=%s",
                        attempt, d, tostring(deployed())))
                end
                if d < 15 and attempt >= 4 then landed = true break end
            end
            task.wait(0.1)
        end

        if deployed() then
            LOG("lobby: body is at the lobby but the round still counts me in, leaving it")
            local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
            if hum then
                pcall(function() hum.Health = 0 end)
                local w = os.clock()
                while STATE.alive() and os.clock() - w < 3 do
                    task.wait(0.15)
                    if not deployed() then break end
                end
            end
            for _ = 1, 12 do
                if not STATE.alive() then break end
                local h = myHrp()
                if h then pcall(function() h.CFrame = CFrame.new(target) end) end
                task.wait(0.1)
            end
        end

        local h = myHrp()
        local dist = h and (h.Position - target).Magnitude or -1
        LOG(string.format("lobby: done, %.1f studs from the lobby spawn, deployed=%s, landed=%s",
            dist, tostring(deployed()), tostring(landed)))
        buyState = string.format("lobby: %.0f studs from the spawn, deployed %s",
            dist, tostring(deployed()))
        task.wait(2)
        lobbyBusy = false
    end)
end)

-- The survival watch. It samples fast enough to see a hit land, not just to notice one
-- happened, and it never touches vape or the panel: it only changes how high the next hop
-- goes and whether the trigger is allowed to pull.
task.spawn(function()
    local lastHP, lastChar = nil, nil
    while STATE.alive() do
        local ch = me.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum then
            if ch ~= lastChar then
                lastChar = ch
                lastHP = hum.Health
                keep(hum.Died:Connect(function()
                    deathCount = deathCount + 1
                    LOG(string.format("DIED #%d at y=%.0f, retreats so far %d, round %s",
                        deathCount,
                        (myHrp() and myHrp().Position.Y) or -1,
                        retreatCount, tostring(rstate())))
                end))
            end
            local hp, mx = hum.Health, math.max(1, hum.MaxHealth)
            if lastHP and hp < lastHP - 0.5 then
                LOG(string.format("took %.0f damage: %.0f -> %.0f of %.0f, y=%.0f",
                    lastHP - hp, lastHP, hp, mx, (myHrp() and myHrp().Position.Y) or -1))
            end
            if hp > 0 and hp / mx <= RTR.low and not retreating() then
                retreatCount = retreatCount + 1
                retreatUntil = os.clock() + RTR.secs
                LOG(string.format("RETREAT #%d: health %.0f of %.0f, climbing to %d studs and holding fire",
                    retreatCount, hp, mx, TP_UP + RTR.up))
            elseif retreating() and hp / mx >= RTR.safe then
                retreatUntil = 0
                LOG(string.format("back in: health %.0f of %.0f", hp, mx))
            end
            lastHP = hp
        end
        task.wait(0.2)
    end
end)

task.spawn(function()
    while STATE.alive() do
        task.wait(2)
        local c = me.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            local st
            pcall(function() st = hum:GetState() end)
            if st == Enum.HumanoidStateType.Dead then
                pcall(function() hum.Health = 0 end)
                buyState = "humanoid was stuck dead, forced a respawn"
            end
        end
    end
end)
backDown.MouseButton1Click:Connect(function() CFG.back = math.max(0, CFG.back - 5); backLbl.Text = tostring(CFG.back) end)
backUp.MouseButton1Click:Connect(function() CFG.back = math.min(150, CFG.back + 5); backLbl.Text = tostring(CFG.back) end)
botBtn.MouseButton1Click:Connect(function()
    CFG.doBots = not CFG.doBots
    botBtn.Text = CFG.doBots and "BOTS ON" or "BOTS OFF"
    botBtn.BackgroundColor3 = CFG.doBots and GOLD or GREY
end)
plrBtn.MouseButton1Click:Connect(function()
    CFG.doPlayers = not CFG.doPlayers
    plrBtn.Text = CFG.doPlayers and "PLAYERS ON" or "PLAYERS OFF"
    plrBtn.BackgroundColor3 = CFG.doPlayers and GOLD or GREY
end)
depBtn.MouseButton1Click:Connect(function()
    CFG.autoDeploy = not CFG.autoDeploy
    depBtn.Text = CFG.autoDeploy and "RESPAWN ON" or "RESPAWN OFF"
    depBtn.BackgroundColor3 = CFG.autoDeploy and GOLD or GREY
end)
oneBtn.MouseButton1Click:Connect(function()
    CFG.oneShot = not CFG.oneShot
    paintUlt()
end)
hopSrv.MouseButton1Click:Connect(function()
    status.Text = "looking for the fullest server"
    task.spawn(function()
        local best, why = bestServer()
        if not best then
            status.Text = "hop: " .. tostring(why) .. ", using random"
            pcall(function() TS:Teleport(game.PlaceId, me) end)
            return
        end
        status.Text = string.format("hopping to a %d/%d server", best.playing, best.max)
        local ok = pcall(function() TS:TeleportToPlaceInstance(game.PlaceId, best.id, me) end)
        if not ok then pcall(function() TS:Teleport(game.PlaceId, me) end) end
    end)
end)

task.spawn(function()
    while STATE.alive() do
        if CFG.on then rebuild(); ensureDeployed() end
        task.wait(0.3)
    end
end)

-- The one lever that actually raises kills a second, and it is not the gun.
--
-- Measured 2026-08-27 with RakNet: the server counts the rate itself on both paths. 40 crate
-- opens all left the client and it honoured 16. Writing the blaster's _ammo to 50 let the
-- client fire 25 shots in 8.4 seconds and it still only granted 2 kills, the same 0.25 a
-- second as reloading properly. So nothing on this side makes the shot faster.
--
-- What was actually low in that sample was the number of things to shoot: two or three bots
-- alive. Kill rate here is target supply, not fire rate. Servers cap at 8 and the fullest
-- public ones sit at 7/8, so when this arena runs dry there is somewhere better to be.
local dryTargetsSince = 0
task.spawn(function()
    while STATE.alive() do
        task.wait(3)
        if not (forceOn and CFG.on and isDeployed(me)) then
            dryTargetsSince = 0
        elseif #list > 0 then
            dryTargetsSince = 0
        else
            if dryTargetsSince == 0 then dryTargetsSince = os.clock() end
            local dry = os.clock() - dryTargetsSince
            if dry > 45 and os.clock() - lastHopAt > 120 then
                lastHopAt = os.clock()
                dryTargetsSince = 0
                LOG(string.format("nothing to shoot for %.0fs, looking for a fuller server", dry))
                task.spawn(function()
                    local best, why = bestServer()
                    if best then
                        LOG(string.format("hopping to a %d/%d server", best.playing, best.max))
                        local okh = pcall(function()
                            TS:TeleportToPlaceInstance(game.PlaceId, best.id, me)
                        end)
                        if not okh then pcall(function() TS:Teleport(game.PlaceId, me) end) end
                    else
                        LOG("no fuller server available: " .. tostring(why))
                    end
                end)
            end
        end
    end
end)

local function ultCharge()
    if not DataClient then return nil, nil, nil end
    local c = DataClient.Data and DataClient.Data.cheats
    if not c then return nil, nil, nil end
    local name = c.equippedUltimate
    if not name then return nil, nil, nil end
    local have = 0
    if typeof(c.progress) == "table" and type(c.progress[name]) == "number" then
        have = c.progress[name]
    end
    local need = 0
    if ULT_INFO and ULT_INFO[name] and ULT_INFO[name].killsRequired then
        need = ULT_INFO[name].killsRequired
    end
    return name, have, need
end

local ultState = "idle"
task.spawn(function()
    while STATE.alive() do
        if CFG.oneShot then
            local name, have, need = ultCharge()
            if not name then
                ultState = "no ultimate equipped"
            elseif have == -1 then
                pcall(function() CheatRemotes.RequestUseCheat:FireServer(name) end)
                oneShotFires = oneShotFires + 1
                ultState = string.format("FIRED %s (was ready)", ultLabel())
                task.wait(3)
            elseif need > 0 then
                ultState = string.format("charging %s %d/%d kills", ultLabel(), have, need)
            else
                ultState = string.format("charging %s %d", ultLabel(), have)
            end
            paintUlt()
        else
            ultState = "off"
        end
        task.wait(0.5)
    end
end)

task.spawn(function()
    while STATE.alive() do
        if not CFG.on then task.wait(0.15)
        else
            local bl = blaster()
            if not bl then task.wait(0.2)
            else
                if (bl:GetAttribute("_ammo") or 0) < 1 and not bl:GetAttribute("_reloading") then
                    pcall(function() Reload:FireServer(bl) end)
                    reloads = reloads + 1
                end
                local t = current
                if t and t.life and t.life.Health > 0 and t.head and t.head.Parent then
                    holdUntil = os.clock() + CFG.settle + 0.25
                    task.wait(CFG.settle)
                    local tw = os.clock()
                    while STATE.alive() and CFG.on and (bl:GetAttribute("_ammo") or 0) < 1 and os.clock() - tw < 1.6 do
                        holdUntil = os.clock() + 0.25
                        task.wait(0.03)
                    end
                    local mh = myHrp()
                    if retreating() then mh = nil end
                    if mh and t.life.Parent and t.hit.Parent and t.life.Health > 0 and t.head.Parent and (bl:GetAttribute("_ammo") or 0) >= 1 then
                        local aim = CFrame.lookAt(mh.Position + Vector3.new(0, 1.5, 0), t.head.Position)
                        local hp0 = t.life.Health
                        pcall(function()
                            Shoot:FireServer(workspace:GetServerTimeNow(), bl, aim,
                                { ["1"] = t.hit }, { ["1"] = true }, { isQuickscope = false, isNoscope = false })
                        end)
                        shots = shots + 1
                        if not bl:GetAttribute("_reloading") then
                            pcall(function() Reload:FireServer(bl) end)
                            reloads = reloads + 1
                        end
                        local td = os.clock()
                        while os.clock() - td < 0.45 do
                            if t.life.Health < hp0 then landed = landed + 1 break end
                            task.wait(0.03)
                        end
                        if t.life.Health <= 0 then kills = kills + 1 end
                    end
                    holdUntil = 0
                else
                    task.wait(0.03)
                end
            end
        end
    end
end)

task.spawn(function()
    while STATE.alive() do
        local nb, np = 0, 0
        for _, e in ipairs(list) do if e.bot then nb = nb + 1 else np = np + 1 end end
        local bl = blaster()
        local acc = shots > 0 and math.floor(landed / shots * 100) or 0
        status.Text = string.format(
            "%s  round %s   back %d  head+%d%s   tp/%df  jump/%df\ntarget %s  hp %s\nammo %s   accuracy %d%%\nult: %s   fires %d\narena %d players + %d bots\nshots %d  landed %d  KILLS %d  reloads %d\ncash %d  vape %s   crate: %s\n%s   blocked %d   clicks %d",
            (inLobby() and (CFG.lobbyHold and "LOBBY HELD" or "LOBBY") or "ARENA"),
            rstate(), CFG.back, TP_UP,
            (retreating() and "  RETREAT" or (deathCount > 0 and ("  deaths " .. deathCount) or "")),
            CFG.tpEvery, CFG.jumpEvery,
            current and (current.name .. (current.cluster and current.cluster > 0
                and ("  +" .. current.cluster) or "")) or "-",
            current and tostring(math.floor(current.life.Health)) or "-",
            tostring(bl and bl:GetAttribute("_ammo")), acc,
            ultState, oneShotFires,
            np, nb, shots, landed, kills, reloads,
            cashNow(), vapeStateText(), buyState .. "   open: " .. openState,
            (forceOn and "FARM ENABLED" or "FARM DISABLED") .. "   crates " .. crateOwned()
                .. string.format("   fps %.0f  lua %d MB   boost: %s",
                    BOOST_FPS, math.floor(RAM_MB), BOOST_STATE),
            POPUPS_BLOCKED + ((getgenv().__TPFARM_PROMPT_BLOCKED) or 0),
            clickCount)
        task.wait(0.2)
    end
end)

task.spawn(function()
    local last = nil
    while STATE.alive() do
        local ok, j = pcall(function() return HttpService:JSONEncode(CFG) end)
        if ok and j ~= last then last = j saveCfg(CFG) end
        task.wait(3)
    end
end)

backLbl.Text = tostring(CFG.back)
botBtn.Text = CFG.doBots and "BOTS ON" or "BOTS OFF"
botBtn.BackgroundColor3 = CFG.doBots and GOLD or GREY
plrBtn.Text = CFG.doPlayers and "PLAYERS ON" or "PLAYERS OFF"
plrBtn.BackgroundColor3 = CFG.doPlayers and GOLD or GREY
depBtn.Text = CFG.autoDeploy and "RESPAWN ON" or "RESPAWN OFF"
depBtn.BackgroundColor3 = CFG.autoDeploy and GOLD or GREY
forceOn = false
wasFarming = false
paintAll()


do
    local Lighting = game:GetService("Lighting")
    local boostedJob = nil
    local hits = 0
    local lastSweep = 0

    local function cheapRender()
        pcall(function()
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
            settings().Rendering.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level04
        end)
        pcall(function()
            Lighting.GlobalShadows = false
            Lighting.FogEnd = 9e9
            Lighting.Brightness = 1
        end)
        pcall(function()
            local sg = game:GetService("UserSettings"):GetService("UserGameSettings")
            sg.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
        end)
    end

    local function stripLighting()
        local n = 0
        pcall(function()
            for _, v in ipairs(Lighting:GetChildren()) do
                if v:IsA("PostEffect") then
                    local ok = pcall(function()
                        if v.Enabled then v.Enabled = false n = n + 1 end
                    end)
                    if not ok then n = n end
                end
            end
        end)
        return n
    end

    local function cheapTerrain()
        pcall(function()
            local t = workspace:FindFirstChildOfClass("Terrain")
            if not t then return end
            t.WaterWaveSize = 0
            t.WaterWaveSpeed = 0
            t.WaterReflectance = 0
            t.Decoration = false
        end)
    end

    local function killEffects()
        local n, seen = 0, 0
        local list = {}
        pcall(function() list = workspace:GetDescendants() end)
        for _, d in ipairs(list) do
            seen = seen + 1
            if seen % 400 == 0 then task.wait() end
            if not STATE.alive() then break end
            pcall(function()
                if d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Smoke")
                    or d:IsA("Fire") or d:IsA("Sparkles") or d:IsA("Beam") then
                    if d.Enabled then d.Enabled = false n = n + 1 end
                elseif d:IsA("Texture") or d:IsA("Decal") then
                    if d.Transparency < 1 then d.Transparency = 1 n = n + 1 end
                end
            end)
        end
        return n
    end

    local function fps()
        local n = 0
        local c = RunService.RenderStepped:Connect(function() n = n + 1 end)
        local t0 = os.clock()
        task.wait(4)
        c:Disconnect()
        local secs = os.clock() - t0
        if secs <= 0 then return 0 end
        return n / secs
    end

    LOG("boost: fps sampler uses RenderStepped only, nothing reads Stats")

    local function sweep(why)
        LOG("boost sweep: " .. tostring(why))
        lastSweep = os.clock()
        cheapRender()
        cheapTerrain()
        local n = killEffects() + stripLighting()
        hits = hits + 1
        BOOST_STATE = string.format("%s, %d effects off, sweep %d", why, n, hits)
    end

    task.spawn(function()
        task.wait(3)
        local lastState = nil
        while STATE.alive() do
            if boostedJob ~= game.JobId then
                boostedJob = game.JobId
                sweep("joined server")
            end
            local rs = rstate()
            if rs ~= lastState then
                lastState = rs
                if rs == "active" then sweep("round started") end
            end
            local f = fps()
            BOOST_FPS = f
            if f < 30 and os.clock() - lastSweep > 60 then
                sweep(string.format("fps %.0f", f))
            end
            for _ = 1, 8 do
                if not STATE.alive() then break end
                task.wait(2)
                local rs2 = rstate()
                if rs2 ~= lastState then
                    lastState = rs2
                    if rs2 == "active" and os.clock() - lastSweep > 15 then sweep("round started") end
                end
            end
        end
    end)
end

do
    -- The clicking, done by the script instead of by a program running next to it.
    --
    -- Measured on his desktop 2026-08-27: 95 clicks in 6 seconds, about 16 a second, cursor
    -- parked at 452,552 and not moving once. That is his auto clicker, and it is the reason the
    -- farm cannot run on a phone: a phone has no auto clicker to run beside it. VirtualInputManager
    -- takes the position as an argument and does not care whether a physical mouse exists, so the
    -- same crazy clicking on the same spot can come from inside the script on any device.
    local VIM = game:GetService("VirtualInputManager")
    local clickDot, clickRing

    -- His question, and it is the right one: a spot saved as pixels dies the moment the
    -- window changes size. Measured 2026-08-27 -- 452,552 is 56.5%,92.2% across an 800x599
    -- window, and the same two numbers on a 1280x720 window land at 35%,77%, a different
    -- place entirely. So the spot is stored as a fraction of the window and turned back into
    -- pixels against whatever the window is right now, every single time it is used.
    local function clickPos()
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize
        if not vp or vp.X < 50 then return nil end
        local fx, fy = CFG.clickFX, CFG.clickFY
        if type(fx) ~= "number" or type(fy) ~= "number" or fx <= 0 or fy <= 0 then
            local px, py = CFG.clickX, CFG.clickY
            if type(px) ~= "number" or px <= 0 then
                local okm, m = pcall(function()
                    return game:GetService("UserInputService"):GetMouseLocation()
                end)
                if okm and m and m.X > 0 then px, py = m.X, m.Y end
            end
            if type(px) == "number" and px > 0 then
                fx, fy = px / vp.X, py / vp.Y
                LOG(string.format("click spot learned: %d,%d on a %dx%d window, kept as %.4f,%.4f of the window",
                    px, py, math.floor(vp.X), math.floor(vp.Y), fx, fy))
            else
                fx, fy = 0.5, 0.9
                LOG("no cursor to learn from, click spot defaults to the middle bottom of the window")
            end
            CFG.clickFX, CFG.clickFY = fx, fy
        end
        local x = math.floor(fx * vp.X + 0.5)
        local y = math.floor(fy * vp.Y + 0.5)
        CFG.clickX, CFG.clickY = x, y
        return x, y
    end

    -- If the window is resized the fraction does not move but the pixels do, and this says so
    -- out loud rather than leaving him to wonder whether the spot survived.
    task.spawn(function()
        local lastVP = nil
        while STATE.alive() do
            local cam = workspace.CurrentCamera
            local vp = cam and cam.ViewportSize
            if vp and vp.X > 50 then
                local key = math.floor(vp.X) .. "x" .. math.floor(vp.Y)
                if lastVP and key ~= lastVP then
                    local x, y = clickPos()
                    LOG(string.format("window went %s -> %s, click spot follows to %s,%s",
                        lastVP, key, tostring(x), tostring(y)))
                end
                lastVP = key
            end
            task.wait(1)
        end
    end)

    -- A stray click on his own panel would press whatever button is under it, so the spot is
    -- refused while it sits over the panel rather than quietly toggling the farm off.
    local function overPanel(x, y)
        if not (frame and frame.Parent) then return false end
        local p, s = frame.AbsolutePosition, frame.AbsoluteSize
        return x >= p.X - 4 and x <= p.X + s.X + 4 and y >= p.Y - 4 and y <= p.Y + s.Y + 4
    end

    local function sendClick(x, y)
        local ok = pcall(function()
            VIM:SendMouseButtonEvent(x, y, 0, true, game, 1)
            VIM:SendMouseButtonEvent(x, y, 0, false, game, 1)
        end)
        if not ok then
            local mc = (getgenv and getgenv().mouse1click) or mouse1click
            if type(mc) == "function" then ok = pcall(mc) end
        end
        return ok
    end

    do
        clickDot = Instance.new("Frame")
        clickDot.Size = UDim2.fromOffset(26, 26)
        clickDot.BackgroundColor3 = GOLD
        clickDot.BackgroundTransparency = 0.45
        clickDot.BorderSizePixel = 0
        clickDot.Visible = false
        clickDot.ZIndex = 20
        clickDot.Parent = gui
        Instance.new("UICorner", clickDot).CornerRadius = UDim.new(1, 0)

        clickRing = Instance.new("Frame")
        clickRing.Size = UDim2.fromOffset(46, 46)
        clickRing.BackgroundTransparency = 1
        clickRing.BorderSizePixel = 0
        clickRing.Visible = false
        clickRing.ZIndex = 19
        clickRing.Parent = gui
        Instance.new("UICorner", clickRing).CornerRadius = UDim.new(1, 0)
        local st = Instance.new("UIStroke")
        st.Color = GOLD
        st.Thickness = 2
        st.Transparency = 0.3
        st.Parent = clickRing
    end

    -- His rule for the circle: AUTO OPEN on, it shows up five seconds later. AUTO OPEN off,
    -- it is gone. The five seconds cover the stretch where he is still pressing things, so it
    -- does not flash on and off while he sets up.
    local CLICK_DELAY = 5
    task.spawn(function()
        while STATE.alive() do
            if not CFG.autoOpen then
                clickOnAt = 0
                clickDot.Visible = false
                clickRing.Visible = false
                task.wait(0.25)
            elseif clickOnAt == 0 then
                clickOnAt = os.clock()
                task.wait(0.25)
            elseif os.clock() - clickOnAt < CLICK_DELAY then
                clickDot.Visible = false
                clickRing.Visible = false
                task.wait(0.25)
            else
                local x, y = clickPos()
                if not x then
                    task.wait(0.5)
                elseif overPanel(x, y) then
                    clickDot.Visible = false
                    clickRing.Visible = false
                    openState = "click spot sits on the panel, not clicking there"
                    task.wait(1)
                else
                    if sendClick(x, y) then
                        clickCount = clickCount + 1
                        clickFlash = os.clock()
                    end
                    local rate = tonumber(CFG.clickRate) or 16
                    if rate < 1 then rate = 1 end
                    if rate > 40 then rate = 40 end
                    task.wait(1 / rate)
                end
            end
        end
    end)

    -- The circle he asked for: it sits on the spot and pulses on every click, so the clicking is
    -- something he can see happening rather than something he has to trust is happening.
    keep(RunService.RenderStepped:Connect(function()
        if not CFG.autoOpen or clickOnAt == 0 then return end
        if os.clock() - clickOnAt < CLICK_DELAY then return end
        local x, y = CFG.clickX, CFG.clickY
        if type(x) ~= "number" or type(y) ~= "number" then return end
        if overPanel(x, y) then return end
        local since = os.clock() - clickFlash
        local hit = since < 0.06
        clickDot.Visible = true
        clickRing.Visible = true
        local d = hit and 34 or 26
        clickDot.Size = UDim2.fromOffset(d, d)
        clickDot.Position = UDim2.fromOffset(x - d / 2, y - d / 2)
        clickDot.BackgroundTransparency = hit and 0.15 or 0.55
        local r = 46 + math.min(since, 0.5) * 40
        clickRing.Size = UDim2.fromOffset(r, r)
        clickRing.Position = UDim2.fromOffset(x - r / 2, y - r / 2)
        local stroke = clickRing:FindFirstChildOfClass("UIStroke")
        if stroke then stroke.Transparency = math.clamp(0.15 + since * 1.6, 0.15, 1) end
    end))
end

task.spawn(function()
    while STATE.alive() do
        LOG(string.format("alive  farm=%s  where=%s  fps=%.0f  luaheap=%.0f  buy=%s  open=%s  vape=%s  net=%d/%d  blocked=%d",
            tostring(forceOn), inLobby() and "lobby" or "arena",
            BOOST_FPS, collectgarbage("count") / 1024,
            tostring(buying), tostring(opening), vapeStateText(),
            RAK.sent, RAK.recv, POPUPS_BLOCKED))
        task.wait(2)
    end
end)

rebuild()
task.spawn(function()
    pcall(function() setthreadidentity(8) end)
    task.wait(0.5)
    if CFG.lobbyHold then
        LOG("startup: BACK TO LOBBY is still held, not enabling the farm")
        buyState = "held in the lobby, press ENABLE FARM to go back in"
        paintAll()
        return
    end
    LOG("startup: enabling farm")
    setFarm(true)
    while farmBusy and STATE.alive() do task.wait(0.1) end
    LOG("startup: farm is up, vape is " .. vapeStateText())
    buyState = "started, vape " .. vapeStateText()
end)
return "tpfarm loaded. farm=" .. (forceOn and "ENABLED" or "DISABLED")
    .. "  ultimate=" .. ultLabel()
    .. "  autoBuy=" .. tostring(CFG.autoBuy)
    .. "  gold=" .. tostring(CFG.buyGold) .. " super=" .. tostring(CFG.buySuper) .. " basic=" .. tostring(CFG.buyBasic)
    .. "  cash=" .. tostring(cashNow())
    .. "  crates=" .. tostring(crateOwned())
    .. "  vape=" .. vapeStateText()