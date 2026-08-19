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


local BLOCK_ULT_PROMPT = 3612256554
do
    local MPS = game:GetService("MarketplaceService")
    local env = getgenv and getgenv() or _G
    if not env.__TPFARM_PROMPT_HOOKED and hookfunction then
        env.__TPFARM_PROMPT_HOOKED = true
        env.__TPFARM_PROMPT_BLOCKED = 0
        local original
        original = hookfunction(MPS.PromptProductPurchase, function(self, plr, id, ...)
            if id == BLOCK_ULT_PROMPT then
                env.__TPFARM_PROMPT_BLOCKED = (env.__TPFARM_PROMPT_BLOCKED or 0) + 1
                return
            end
            return original(self, plr, id, ...)
        end)
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
              guiX = 24, guiY = 150 })
getgenv().TPFARM = CFG

local list, idx, current, holdUntil = {}, 1, nil, 0
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
    pcall(function() cam.CameraType = Enum.CameraType.Custom end)
    gui:Destroy()
end)

local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(252, 336)
do
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    local gx = math.clamp(CFG.guiX or 24, 0, math.max(0, vp.X - 252))
    local gy = math.clamp(CFG.guiY or 150, 0, math.max(0, vp.Y - 336))
    frame.Position = UDim2.fromOffset(gx, gy)
end
frame.BackgroundColor3 = Color3.fromRGB(20, 17, 13); frame.BorderSizePixel = 0
frame.Active = true; frame.Parent = gui
do
    local UIS = game:GetService("UserInputService")
    local dragging, dragStart, startPos = false, nil, nil
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            frame.Position = UDim2.fromOffset(startPos.X.Offset + d.X, startPos.Y.Offset + d.Y)
        end
    end)
end
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 26); title.BackgroundTransparency = 1
title.Text = "TP FARM"; title.TextColor3 = Color3.fromRGB(231, 177, 115)
title.Font = Enum.Font.GothamBold; title.TextSize = 15; title.Parent = frame

local mark = Instance.new("TextLabel")
mark.Size = UDim2.fromOffset(74, 26); mark.Position = UDim2.fromOffset(170, 0)
mark.BackgroundTransparency = 1; mark.Text = "NEWGOD"
mark.TextColor3 = Color3.fromRGB(231, 177, 115); mark.TextTransparency = 0.35
mark.Font = Enum.Font.GothamBold; mark.TextSize = 11
mark.TextXAlignment = Enum.TextXAlignment.Right; mark.Parent = frame

local mark2 = Instance.new("TextLabel")
mark2.Size = UDim2.fromOffset(120, 14); mark2.Position = UDim2.fromOffset(8, 214)
mark2.BackgroundTransparency = 1; mark2.Text = "NEWGOD"
mark2.TextColor3 = Color3.fromRGB(231, 177, 115); mark2.TextTransparency = 0.5
mark2.Font = Enum.Font.GothamBold; mark2.TextSize = 10
mark2.TextXAlignment = Enum.TextXAlignment.Left; mark2.Parent = frame

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 96); status.Position = UDim2.fromOffset(8, 236)
status.BackgroundTransparency = 1; status.Text = "off"
status.TextColor3 = Color3.fromRGB(190, 180, 168); status.Font = Enum.Font.Gotham
status.TextSize = 11; status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top; status.Parent = frame

local GOLD, GREY, RED = Color3.fromRGB(231, 177, 115), Color3.fromRGB(120, 108, 96), Color3.fromRGB(200, 90, 70)
local function mk(t, x, y, w, c)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(w, 26); b.Position = UDim2.fromOffset(x, y)
    b.BackgroundColor3 = c; b.Text = t; b.TextColor3 = Color3.fromRGB(20, 17, 13)
    b.Font = Enum.Font.GothamBold; b.TextSize = 11; b.BorderSizePixel = 0; b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6); return b
end

local startBtn = mk("START FARM", 8, 30, 236, GOLD)
local stopBtn = mk("STOP", 8, 60, 236, GREY)
local backDown = mk("BACK -5", 8, 90, 75, GREY)
local backLbl = mk(tostring(CFG.back), 89, 90, 74, GREY)
local backUp = mk("BACK +5", 169, 90, 75, GREY)
local botBtn = mk("BOTS ON", 8, 120, 114, GOLD)
local plrBtn = mk("PLAYERS ON", 130, 120, 114, GOLD)
local depBtn = mk("RESPAWN ON", 8, 150, 114, GOLD)
local hopSrv = mk("HOP SERVER", 130, 150, 114, RED)
local oneBtn = mk("INF ONESHOT ON", 8, 180, 236, GOLD)

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

local function ownsOneShot()
    if not DataClient then return false end
    local c = DataClient.Data and DataClient.Data.cheats
    return c and c.equippedUltimate == "oneShot" and c.owned and c.owned.oneShot == true
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

RunService:BindToRenderStep(AIM, Enum.RenderPriority.Camera.Value + 10, function()
    if not CFG.on then return end
    local mh = myHrp()
    if not mh then return end
    local t = current
    if os.clock() < holdUntil then
        if t and t.head and t.head.Parent then
            cam.CameraType = Enum.CameraType.Scriptable
            cam.CFrame = CFrame.lookAt(mh.Position + Vector3.new(0, 1.5, 0), t.head.Position)
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
            cam.CameraType = Enum.CameraType.Scriptable
            cam.CFrame = CFrame.lookAt(mh.Position + Vector3.new(0, 1.5, 0), t.head.Position)
        end
    end
    if frameN % CFG.jumpEvery == 0 then
        local h = myHum()
        if h then pcall(function() h:ChangeState(Enum.HumanoidStateType.Jumping) end) end
    end
end)

local function ensureDeployed()
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

startBtn.MouseButton1Click:Connect(function() CFG.on = true end)
stopBtn.MouseButton1Click:Connect(function()
    CFG.on = false; current = nil
    pcall(function() cam.CameraType = Enum.CameraType.Custom end)
    status.Text = "off"
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
    oneBtn.Text = CFG.oneShot and "INF ONESHOT ON" or "INF ONESHOT OFF"
    oneBtn.BackgroundColor3 = CFG.oneShot and GOLD or GREY
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

local ULT_INFO
pcall(function() ULT_INFO = require(RS.Shared.Info.CheatInfos) end)

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
                ultState = string.format("FIRED %s (was ready)", name)
                task.wait(3)
            elseif need > 0 then
                ultState = string.format("charging %s %d/%d kills", name, have, need)
            else
                ultState = string.format("charging %s %d", name, have)
            end
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
            "round %s   back %d   tp/%df  jump/%df\ntarget %s  hp %s\nammo %s   accuracy %d%%\noneShot: %s   fires %d\narena %d players + %d bots\nshots %d  landed %d  KILLS %d  reloads %d",
            rstate(), CFG.back, CFG.tpEvery, CFG.jumpEvery,
            current and current.name or "-",
            current and tostring(math.floor(current.life.Health)) or "-",
            tostring(bl and bl:GetAttribute("_ammo")), acc,
            ultState .. "   robux popups blocked " .. tostring((getgenv().__TPFARM_PROMPT_BLOCKED) or 0), oneShotFires,
            np, nb, shots, landed, kills, reloads)
        task.wait(0.2)
    end
end)

task.spawn(function()
    while STATE.alive() do
        CFG.guiX = math.floor(frame.Position.X.Offset)
        CFG.guiY = math.floor(frame.Position.Y.Offset)
        saveCfg(CFG)
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
oneBtn.Text = CFG.oneShot and "INF ONESHOT ON" or "INF ONESHOT OFF"
oneBtn.BackgroundColor3 = CFG.oneShot and GOLD or GREY

rebuild()
return "tpfarm loaded, resumed last settings, farming=" .. tostring(CFG.on) .. " oneShot loaded. owns+equipped oneShot = " .. tostring(ownsOneShot())