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
              autoOpen = false, lobbyHold = false, vapeList = {}, guiX = 24, guiY = 150 })
if type(CFG.autoBuy) ~= "boolean" then CFG.autoBuy = false end
if type(CFG.autoOpen) ~= "boolean" then CFG.autoOpen = false end
if type(CFG.vapeList) ~= "table" then CFG.vapeList = {} end
getgenv().TPFARM = CFG

local list, idx, current, holdUntil = {}, 1, nil, 0
local forceOn, wasFarming = false, false
local BOOST_STATE, BOOST_FPS = "starting", 0
local RAM_MB, CPU_PCT = 0, 0
local hintFrame, hintLabel, hintYes, hintNo
local autoHopOK, hintShownAt, lastHopAt = false, 0, 0
local frameN, lastDeploy = 0, 0
local shots, landed, kills, reloads, oneShotFires = 0, 0, 0, 0, 0
local AIM = "tpfarm_aim"

local gui = Instance.new("ScreenGui")
gui.Name = "TPFarmPanel"; gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true
do
    local placed = false
    pcall(function() if gethui then gui.Parent = gethui() placed = gui.Parent ~= nil end end)
    if not placed then pcall(function() gui.Parent = game:GetService("CoreGui") placed = gui.Parent ~= nil end) end
    if not placed then pcall(function() gui.Parent = me:WaitForChild("PlayerGui") end) end
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
                LOG("panel: this copy has been replaced, standing down")
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
        mh.CFrame = t.hrp.CFrame * CFrame.new(0, 0, CFG.back)
        if t.head and t.head.Parent then
            look(mh.Position + Vector3.new(0, 1.5, 0), t.head.Position)
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
    if type(R) == "table" and R.is_enabled == true and type(R.add_send_hook) == "function" then
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

local VAPE_URL = "https://rawscripts.net/raw/Vape-V4-For-Roblox_316"
local VAPE_ALL = { "Anti-AFK", "AntiFall", "AutoClicker", "Invisible", "Killaura",
                   "Phase", "Reach", "SilentAim", "Speed", "TriggerBot" }
local VAPE_STATE = "unknown"

local function vapeUp()
    local v = shared and shared.vape
    return type(v) == "table" and type(v.Modules) == "table" and v.Loaded ~= false
end

local function vapeGui()
    local v = shared and shared.vape
    local g = v and rawget(v, "gui")
    if typeof(g) == "Instance" and g:IsA("ScreenGui") then return g end
    return nil
end

-- A vape panel is any ScreenGui that owns a PRESS A KEY TO BIND label. Only the one
-- shared.vape.gui points at is the live one; every other is a leftover from a second load.
local function vapeLooksLikePanel(sg)
    for _, d in ipairs(sg:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "PRESS A KEY TO BIND" then return true end
    end
    return false
end

local function vapeSweepDuplicates()
    local live = vapeGui()
    -- Measured 2026-08-27 20:06: shared.vape survives a teleport but every Instance in it does
    -- not, so shared.vape.gui was already destroyed while a fresh vape was still loading. With
    -- no live panel to compare against, the sweep called the new one a leftover and killed it,
    -- and vape sat at Loaded=false with no window for the rest of the server.
    if not live then
        LOG("vape: no live panel to compare against, not destroying anything")
        return 0
    end
    local killed, seen = 0, 0
    local hosts = {}
    pcall(function() if gethui then table.insert(hosts, gethui()) end end)
    pcall(function() table.insert(hosts, game:GetService("CoreGui")) end)
    for _, h in ipairs(hosts) do
        for _, sg in ipairs(h:GetChildren()) do
            if sg:IsA("ScreenGui") and sg ~= live and vapeLooksLikePanel(sg) then
                seen = seen + 1
                pcall(function() sg:Destroy() end)
                killed = killed + 1
            end
        end
    end
    if killed > 0 then LOG("vape: destroyed " .. killed .. " leftover vape panel(s)") end
    return killed
end

local function vapeCloseOwnGui(why)
    local g = vapeGui()
    if not g then return false end
    if g.Parent == nil then
        pcall(function() g.Parent = game:GetService("CoreGui") end)
        if g.Parent then LOG("vape: its panel had no parent, put it under CoreGui") end
    end
    if g.Enabled then
        pcall(function() g.Enabled = false end)
        LOG("vape: closed its own panel (" .. tostring(why) .. "), the CAPSLOCK rebind list is off screen")
        return true
    end
    return false
end

-- Measured 2026-08-27 20:1x: after one teleport this client had no CoreGui.RobloxGui and
-- gethui() returned nil. Vape parents into CoreGui.RobloxGui, so it threw
-- "RobloxGui is not a valid member of CoreGui" and shared.vape never appeared, which read
-- from outside as vape simply refusing to load. Roblox's own RobloxGui is already gone in
-- that state, so a stand-in of the same name takes nothing away from anyone.
local function ensureVapeHost()
    local cg = game:GetService("CoreGui")
    if cg:FindFirstChild("RobloxGui") then return false end
    local made = false
    pcall(function()
        setthreadidentity(8)
        local sg = Instance.new("ScreenGui")
        sg.Name = "RobloxGui"
        sg.ResetOnSpawn = false
        sg.IgnoreGuiInset = true
        sg.DisplayOrder = 10
        sg.Parent = cg
        made = sg.Parent ~= nil
    end)
    if made then
        LOG("vape: this client lost CoreGui.RobloxGui, put a stand-in there so vape has a host")
    end
    return made
end

-- One loader for the whole client. The old shape was the autoexec asking every 8 seconds
-- whether shared.vape existed, and vape needs far longer than 8 seconds to set it, so the
-- question was answered no over and over and every no started another vape.
local function ensureVape()
    if vapeUp() then
        ENV.__TPFARM_VAPE = "up"
        VAPE_STATE = "up"
        return
    end
    if ENV.__TPFARM_VAPE == "loading" then
        local since = os.clock() - (ENV.__TPFARM_VAPE_AT or 0)
        if since < 200 then
            VAPE_STATE = "loading"
            return
        end
        LOG(string.format("vape: the loading marker is %.0fs old and nothing is up, trying again", since))
    end
    ENV.__TPFARM_VAPE = "loading"
    ENV.__TPFARM_VAPE_AT = os.clock()
    VAPE_STATE = "loading"
    LOG("vape: nothing loaded, this script is loading it once")
    ensureVapeHost()
    task.spawn(function()
        pcall(function() setthreadidentity(8) end)
        local t0 = os.clock()
        local dead = shared and shared.vape
        if type(dead) == "table" and dead.Loaded == false then
            LOG("vape: the old shared.vape is Loaded=false, clearing it so the loader will run")
            pcall(function() shared.vape = nil end)
        end
        -- vape's entry point never returns, so it gets a thread of its own or nothing below
        -- this line ever runs and the marker stays on loading for the whole session.
        task.spawn(function()
            pcall(function() setthreadidentity(8) end)
            pcall(function() loadstring(game:HttpGet(VAPE_URL))() end)
        end)
        while STATE.alive() and os.clock() - t0 < 180 do
            if vapeUp() then break end
            task.wait(0.5)
        end
        if vapeUp() then
            ENV.__TPFARM_VAPE = "up"
            VAPE_STATE = "up"
            LOG(string.format("vape: up after %.0fs, version %s", os.clock() - t0,
                tostring(shared.vape.Version)))
            task.wait(2)
            vapeSweepDuplicates()
            vapeCloseOwnGui("just loaded")
        else
            ENV.__TPFARM_VAPE = nil
            VAPE_STATE = "load failed"
            LOG("vape: 180s and shared.vape never appeared, giving this attempt up")
        end
    end)
end

task.spawn(function()
    ensureVape()
    while STATE.alive() do
        task.wait(20)
        if vapeUp() then
            ENV.__TPFARM_VAPE = "up"
            VAPE_STATE = "up"
            vapeSweepDuplicates()
        else
            ensureVape()
        end
    end
end)

local function vapeWanted()
    if type(CFG.vapeList) == "table" and #CFG.vapeList > 0 then
        return CFG.vapeList
    end
    return VAPE_ALL
end

-- The list of what to switch back on can never be replaced by an empty list, and it lives
-- in the json, because a table that only lives in memory is gone the moment this reloads.
local function vapeSnapshot()
    local v = shared and shared.vape
    if not (type(v) == "table" and type(v.Modules) == "table") then return 0 end
    local on = {}
    for name, m in pairs(v.Modules) do
        if type(m) == "table" and m.Enabled == true and type(m.Toggle) == "function" then
            on[#on + 1] = tostring(name)
        end
    end
    table.sort(on)
    if #on > 0 then
        CFG.vapeList = on
        saveCfg(CFG)
        LOG("vape: remembered " .. #on .. " module(s) to switch back on: " .. table.concat(on, ", "))
    end
    return #on
end

-- Everything that is on right now, so DISABLE really is everything off and not a fixed list.
local function vapeEnabledNow()
    local v = shared and shared.vape
    local out = {}
    if not (type(v) == "table" and type(v.Modules) == "table") then return out end
    for name, m in pairs(v.Modules) do
        if type(m) == "table" and m.Enabled == true and type(m.Toggle) == "function" then
            out[#out + 1] = tostring(name)
        end
    end
    table.sort(out)
    return out
end

local vapeWaiter = false
local vapeApply
local function vapeWhenReady(on)
    if vapeWaiter then return end
    vapeWaiter = true
    task.spawn(function()
        for _ = 1, 240 do
            if not STATE.alive() then break end
            if vapeUp() then
                vapeApply(on)
                break
            end
            task.wait(0.5)
        end
        vapeWaiter = false
    end)
end

local vapeDead = false
function vapeApply(on)
    if vapeDead then return 0 end
    local v = shared and shared.vape
    if not (type(v) == "table" and type(v.Modules) == "table") then
        if on then
            ensureVape()
            vapeWhenReady(true)
            buyState = "waiting for vape to finish loading"
        end
        return 0
    end
    pcall(function() setthreadidentity(8) end)
    LOG("vapeApply start on=" .. tostring(on))
    if not on then vapeSnapshot() end
    local n = 0
    for _, name in ipairs(on and vapeWanted() or vapeEnabledNow()) do
        if not STATE.alive() then break end
        local m = v.Modules[name]
        if type(m) == "table" and type(m.Toggle) == "function" then
            if (m.Enabled == true) ~= on then
                LOG("  toggle " .. name .. " -> " .. tostring(on) .. " ... calling")
                local ok, err = pcall(m.Toggle, m)
                if ok then
                    n = n + 1
                    LOG("  toggle " .. name .. " returned ok, Enabled=" .. tostring(m.Enabled))
                else
                    vapeDead = true
                    LOG("  toggle " .. name .. " THREW " .. tostring(err))
                    buyState = "vape " .. name .. " threw, not touching vape again: " .. tostring(err)
                    return n
                end
                local settle = os.clock()
                while STATE.alive() and os.clock() - settle < 2 do
                    task.wait(0.1)
                    if (m.Enabled == true) == on then break end
                end
                LOG(string.format("  %s settled after %.2fs, Enabled=%s", name, os.clock() - settle, tostring(m.Enabled)))
                task.wait(0.2)
            else
                LOG("  toggle " .. name .. " skipped, already " .. tostring(on))
                task.wait(0.05)
            end
        elseif m ~= nil then
            LOG("  toggle " .. name .. " missing from vape")
            task.wait(0.05)
        end
    end
    LOG("vapeApply done, changed " .. n)
    return n
end

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
    if on then CFG.lobbyHold = false end
    forceOn = on
    wasFarming = on
    paintAll()
    task.spawn(function()
        pcall(function() setthreadidentity(8) end)
        local n = vapeApply(on)
        if not vapeDead then buyState = (on and "vape on " or "vape off ") .. n end
        local steps = {
            { "shooting and aiming", function() CFG.on = on if not on then current = nil end end },
            { "bots", function() CFG.doBots = on end },
            { "players", function() CFG.doPlayers = on end },
            { "respawn", function() CFG.autoDeploy = on end },
            { "auto ult", function() CFG.oneShot = on end },
            { "auto buy", function() CFG.autoBuy = on end },
            { "auto open", function() CFG.autoOpen = on end },
        }
        for _, step in ipairs(steps) do
            task.wait(0.05)
            if not STATE.alive() then break end
            LOG("  step " .. step[1] .. " -> " .. tostring(on))
            step[2]()
            paintAll()
        end
        if not on then
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

local lastMaster = 0
local function master(on)
    if os.clock() - lastMaster < 1.2 then return end
    lastMaster = os.clock()
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
        LOG("lobby: deployed=" .. tostring(deployed())
            .. "  round=" .. tostring(rstate())
            .. "  character=" .. tostring(me.Character and me.Character.Name or "none"))

        if not deployed() then
            LOG("lobby: not deployed, already out of the round, nothing to kill")
            buyState = "already in the lobby"
            task.wait(2)
            lobbyBusy = false
            return
        end

        for attempt = 1, 3 do
            if not STATE.alive() then break end
            if not deployed() then break end
            local ch = me.Character
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            if not hum then
                LOG("lobby: attempt " .. attempt .. " has no humanoid, waiting")
                task.wait(1)
            else
                LOG(string.format("lobby: attempt %d, health %s, setting it to 0", attempt, tostring(hum.Health)))
                pcall(function() hum.Health = 0 end)
                pcall(function() hum:TakeDamage(hum.MaxHealth + 1000) end)
                local w = os.clock()
                while STATE.alive() and os.clock() - w < 3 do
                    task.wait(0.15)
                    if not deployed() then break end
                    if me.Character ~= ch then break end
                end
                LOG(string.format("lobby: after attempt %d, deployed=%s health=%s",
                    attempt, tostring(deployed()), tostring(hum.Parent and hum.Health or "gone")))
            end
        end

        if deployed() then
            LOG("lobby: STILL DEPLOYED after 3 attempts, the server is not letting me die")
            buyState = "server will not let me die, still in the round"
        else
            LOG("lobby: out of the round, back in the lobby")
            buyState = "back in the lobby"
        end
        task.wait(2)
        lobbyBusy = false
    end)
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
            "%s  round %s   back %d   tp/%df  jump/%df\ntarget %s  hp %s\nammo %s   accuracy %d%%\nult: %s   fires %d\narena %d players + %d bots\nshots %d  landed %d  KILLS %d  reloads %d\ncash %d  vape %s   crate: %s\n%s   blocked %d",
            (inLobby() and (CFG.lobbyHold and "LOBBY HELD" or "LOBBY") or "ARENA"),
            rstate(), CFG.back, CFG.tpEvery, CFG.jumpEvery,
            current and current.name or "-",
            current and tostring(math.floor(current.life.Health)) or "-",
            tostring(bl and bl:GetAttribute("_ammo")), acc,
            ultState, oneShotFires,
            np, nb, shots, landed, kills, reloads,
            cashNow(), VAPE_STATE, buyState .. "   open: " .. openState,
            (forceOn and "FARM ENABLED" or "FARM DISABLED") .. "   crates " .. crateOwned()
                .. string.format("   fps %.0f  lua %d MB   boost: %s",
                    BOOST_FPS, math.floor(RAM_MB), BOOST_STATE),
            POPUPS_BLOCKED + ((getgenv().__TPFARM_PROMPT_BLOCKED) or 0))
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

task.spawn(function()
    while STATE.alive() do
        LOG(string.format("alive  farm=%s  where=%s  fps=%.0f  luaheap=%.0f  buy=%s  open=%s  vape=%s  net=%d/%d  blocked=%d",
            tostring(forceOn), inLobby() and "lobby" or "arena",
            BOOST_FPS, collectgarbage("count") / 1024,
            tostring(buying), tostring(opening), VAPE_STATE,
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
    LOG("startup: farm is up with " .. #vapeWanted() .. " vape module(s)")
    for _ = 1, 120 do
        if not STATE.alive() then return end
        if vapeUp() then break end
        task.wait(1)
    end
    if vapeUp() then
        task.wait(2)
        vapeSweepDuplicates()
        vapeCloseOwnGui("startup")
    end
    buyState = "started, vape " .. VAPE_STATE
end)
return "tpfarm loaded. farm=" .. (forceOn and "ENABLED" or "DISABLED")
    .. "  ultimate=" .. ultLabel()
    .. "  autoBuy=" .. tostring(CFG.autoBuy)
    .. "  gold=" .. tostring(CFG.buyGold) .. " super=" .. tostring(CFG.buySuper) .. " basic=" .. tostring(CFG.buyBasic)
    .. "  cash=" .. tostring(cashNow())
    .. "  crates=" .. tostring(crateOwned())
    .. "  vapeList=" .. tostring(#vapeWanted())