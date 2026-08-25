-- NEWGOD DEATHLOG - temporary. One hour of proof, then delete it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer

for _, h in ipairs({game:GetService("CoreGui"), (function()
    local ok, g = pcall(gethui)
    return ok and g or nil
end)()}) do
    if h then
        for _, g in ipairs(h:GetChildren()) do
            if g.Name == "NEWGOD_DEATHLOG" then
                pcall(function()
                    g:Destroy()
                end)
            end
        end
    end
end

local GEN = (tonumber(getgenv().NEWGOD_DLOG_GEN) or 0) + 1
getgenv().NEWGOD_DLOG_GEN = GEN
local function mine()
    return getgenv().NEWGOD_DLOG_GEN == GEN
end

local Network = require(ReplicatedStorage.Modules.Packages.Network)
local ML = LP:WaitForChild("PlayerScripts"):WaitForChild("ModuleLoader")
local ClientData = require(ML.ClientData)

local BG = Color3.fromRGB(11, 11, 14)
local BAR = Color3.fromRGB(24, 20, 14)
local GOLD = Color3.fromRGB(255, 179, 71)
local TXT = Color3.fromRGB(236, 236, 236)
local DIM = Color3.fromRGB(150, 146, 138)
local RED = Color3.fromRGB(196, 62, 48)

local LOG_PATH = "NEWGOD_DEAGLE_deathlog.txt"

local S = {
    t0 = os.clock(),
    deaths0 = nil,
    kills0 = nil,
    lastDeathAt = os.clock(),
    longestAlive = 0,
    lines = {},
    byKiller = {},
}

local function stamp()
    local t = math.floor(os.clock() - S.t0)
    return string.format("%02d:%02d:%02d", math.floor(t / 3600), math.floor(t % 3600 / 60), t % 60)
end

local function push(text)
    S.lines[#S.lines + 1] = stamp() .. "  " .. text
    if #S.lines > 200 then
        table.remove(S.lines, 1)
    end
    pcall(function()
        local head = "NEWGOD DEAGLE death log, run started at clock " .. math.floor(S.t0) .. "\n"
        writefile(LOG_PATH, head .. table.concat(S.lines, "\n"))
    end)
end

local function root()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function floorNow()
    local ys = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local rr = p.Character:FindFirstChild("HumanoidRootPart")
            if rr then
                ys[#ys + 1] = rr.Position.Y
            end
        end
    end
    for _, m in ipairs(workspace:GetChildren()) do
        if m:IsA("Model") and m:GetAttribute("IsBot") == true then
            local rr = m:FindFirstChild("HumanoidRootPart")
            if rr then
                ys[#ys + 1] = rr.Position.Y
            end
        end
    end
    if #ys == 0 then
        return nil
    end
    table.sort(ys)
    return ys[math.ceil(#ys / 2)]
end

local function noteDeath(killer)
    local alive = os.clock() - S.lastDeathAt
    if alive > S.longestAlive then
        S.longestAlive = alive
    end
    S.lastDeathAt = os.clock()
    local r = root()
    local f = floorNow()
    local NG = getgenv().NEWGOD
    local k = tostring(killer)
    S.byKiller[k] = (S.byKiller[k] or 0) + 1
    push(string.format("DIED  by %s  y=%s  floor=%s  underFloor=%s  aliveFor=%.0fs  phase=%s",
        k,
        r and math.floor(r.Position.Y) or "?",
        f and math.floor(f) or "?",
        (r and f and r.Position.Y < f - 8) and "YES" or "no",
        alive,
        NG and tostring(NG.F.phase) or "?"))
end

pcall(function()
    Network.OnClientEvent("Kill", function(p1)
        if not mine() or type(p1) ~= "table" then
            return
        end
        for killer, v in pairs(p1) do
            if type(v) == "table" and v.Killed ~= nil and tostring(v.Killed) == LP.Name then
                noteDeath(killer)
            end
        end
    end)
end)

local gui = Instance.new("ScreenGui")
gui.Name = "NEWGOD_DEATHLOG"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9300
gui.IgnoreGuiInset = true
local host = nil
pcall(function()
    host = gethui()
end)
gui.Parent = host or game:GetService("CoreGui")

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(320, 300)
main.Position = UDim2.fromOffset(400, 120)
main.BackgroundColor3 = BG
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", main)
stroke.Color = GOLD
stroke.Thickness = 1
stroke.Transparency = 0.35

local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, 0, 0, 30)
bar.BackgroundColor3 = BAR
bar.BorderSizePixel = 0
bar.Active = true
bar.Parent = main
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -70, 1, 0)
title.Position = UDim2.fromOffset(10, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextColor3 = GOLD
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "DEATH LOG  (temporary)"
title.Parent = bar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(24, 20)
closeBtn.Position = UDim2.new(1, -30, 0, 5)
closeBtn.BackgroundColor3 = RED
closeBtn.BorderSizePixel = 0
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.TextColor3 = Color3.fromRGB(255, 235, 230)
closeBtn.Text = "X"
closeBtn.Parent = bar
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

local head = Instance.new("TextLabel")
head.Size = UDim2.new(1, -16, 0, 96)
head.Position = UDim2.fromOffset(8, 34)
head.BackgroundTransparency = 1
head.Font = Enum.Font.Gotham
head.TextSize = 12
head.TextColor3 = TXT
head.TextXAlignment = Enum.TextXAlignment.Left
head.TextYAlignment = Enum.TextYAlignment.Top
head.Text = ""
head.Parent = main

local feed = Instance.new("ScrollingFrame")
feed.Size = UDim2.new(1, -16, 1, -172)
feed.Position = UDim2.fromOffset(8, 132)
feed.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
feed.BorderSizePixel = 0
feed.ScrollBarThickness = 3
feed.ScrollBarImageColor3 = GOLD
feed.CanvasSize = UDim2.new(0, 0, 0, 0)
feed.AutomaticCanvasSize = Enum.AutomaticSize.Y
feed.Parent = main
Instance.new("UICorner", feed).CornerRadius = UDim.new(0, 6)

local feedText = Instance.new("TextLabel")
feedText.Size = UDim2.new(1, -8, 0, 0)
feedText.Position = UDim2.fromOffset(6, 4)
feedText.AutomaticSize = Enum.AutomaticSize.Y
feedText.BackgroundTransparency = 1
feedText.Font = Enum.Font.Code
feedText.TextSize = 10
feedText.TextColor3 = DIM
feedText.TextXAlignment = Enum.TextXAlignment.Left
feedText.TextYAlignment = Enum.TextYAlignment.Top
feedText.TextWrapped = true
feedText.Text = "nothing yet"
feedText.Parent = feed

local saveBtn = Instance.new("TextButton")
saveBtn.Size = UDim2.new(1, -16, 0, 26)
saveBtn.Position = UDim2.new(0, 8, 1, -34)
saveBtn.BackgroundColor3 = GOLD
saveBtn.BorderSizePixel = 0
saveBtn.Font = Enum.Font.GothamBold
saveBtn.TextSize = 11
saveBtn.TextColor3 = Color3.fromRGB(20, 16, 8)
saveBtn.Text = "SAVE LOG TO FILE"
saveBtn.Parent = main
Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0, 6)

saveBtn.MouseButton1Click:Connect(function()
    push("saved by hand")
    saveBtn.Text = "SAVED to " .. LOG_PATH
    task.delay(2.5, function()
        saveBtn.Text = "SAVE LOG TO FILE"
    end)
end)

closeBtn.MouseButton1Click:Connect(function()
    push("closed by hand")
    gui:Destroy()
end)

local dragging, dragStart, startPos = false, nil, nil
bar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = i.Position
        startPos = main.Position
    end
end)
UserInputService.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

push("run started")

task.spawn(function()
    while gui.Parent and mine() do
        local ok = pcall(function()
            local d = ClientData.Data or {}
            if not S.deaths0 and tonumber(d.Deaths) then
                S.deaths0 = tonumber(d.Deaths)
                S.kills0 = tonumber(d.Kills) or 0
                S.t0 = os.clock()
                S.lastDeathAt = os.clock()
                push("baseline set: deaths " .. S.deaths0 .. ", kills " .. S.kills0)
            end
            if not S.deaths0 then
                head.Text = "waiting for the account data to arrive"
                return
            end
            local mins = math.max((os.clock() - S.t0) / 60, 0.01)
            local deaths = (tonumber(d.Deaths) or 0) - S.deaths0
            local kills = (tonumber(d.Kills) or 0) - S.kills0
            local aliveNow = os.clock() - S.lastDeathAt
            local best = math.max(S.longestAlive, aliveNow)
            local top, topN = "none", 0
            for k, v in pairs(S.byKiller) do
                if v > topN then
                    top, topN = k, v
                end
            end
            head.Text = table.concat({
                "run time     " .. stamp() .. "   of 60:00 target",
                "deaths       " .. deaths .. "   kills " .. kills,
                "kills / min  " .. string.format("%.1f", kills / mins),
                "alive now    " .. string.format("%.0f", aliveNow) .. "s",
                "longest run  " .. string.format("%.0f", best) .. "s without dying",
                "worst killer " .. (topN > 0 and (top .. " x" .. topN) or "nobody yet"),
                "verdict      " .. (deaths == 0 and "CLEAN so far" or (deaths .. " deaths this run")),
            }, "\n")
            local show = {}
            for i = math.max(1, #S.lines - 40), #S.lines do
                show[#show + 1] = S.lines[i]
            end
            feedText.Text = #show > 0 and table.concat(show, "\n") or "nothing yet"
        end)
        if not ok then
            head.Text = "log error - see " .. LOG_PATH
        end
        task.wait(1)
    end
end)

return "deathlog panel up"
