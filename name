-- NEWGOD NAME - any length, any characters, every server, on by itself.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer

for _, h in ipairs({game:GetService("CoreGui"), (function()
    local ok, g = pcall(gethui)
    return ok and g or nil
end)()}) do
    if h then
        for _, g in ipairs(h:GetChildren()) do
            if g.Name == "NEWGOD_NAME" then
                pcall(function()
                    g:Destroy()
                end)
            end
        end
    end
end

local GEN = (tonumber(getgenv().NEWGOD_NAME_GEN) or 0) + 1
getgenv().NEWGOD_NAME_GEN = GEN
local function mine()
    return getgenv().NEWGOD_NAME_GEN == GEN
end

local CFG_PATH = "NEWGOD_NAME_cfg.json"

local F = {
    on = true,
    name = string.rep("hi", 60),
    cycle = false,
    every = 1,
    scrub = true,
    target = "",
}

pcall(function()
    if isfile and isfile(CFG_PATH) then
        local t = HttpService:JSONDecode(readfile(CFG_PATH))
        for k, v in pairs(t) do
            if F[k] ~= nil and type(v) == type(F[k]) then
                F[k] = v
            end
        end
    end
end)

local function save()
    pcall(function()
        writefile(CFG_PATH, HttpService:JSONEncode(F))
    end)
end

local realName = LP.Name
local realDisplay = LP.DisplayName
local applied = 0
local status = "starting"

-- the whole point: this runs before the first frame is drawn, and again on every
-- respawn and every server, so the account name is never on screen even once
local function wanted()
    if F.target ~= "" then
        return F.target
    end
    return F.name
end

local function paintOne(d)
    if not F.scrub then
        return
    end
    if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
        local t = d.Text
        if t and t ~= "" and (t == realName or t == realDisplay or string.find(t, realName, 1, true)) then
            pcall(function()
                d.Text = string.gsub(t, realName, wanted())
                applied = applied + 1
            end)
        end
    end
end

local function apply()
    if not F.on then
        return
    end
    local w = wanted()
    pcall(function()
        LP.DisplayName = w
    end)
    local c = LP.Character
    if c then
        local h = c:FindFirstChildOfClass("Humanoid")
        if h then
            pcall(function()
                h.DisplayName = w
            end)
        end
        for _, d in ipairs(c:GetDescendants()) do
            paintOne(d)
        end
    end
    for _, hostGui in ipairs({LP:FindFirstChild("PlayerGui"), game:GetService("CoreGui")}) do
        if hostGui then
            for _, d in ipairs(hostGui:GetDescendants()) do
                paintOne(d)
            end
        end
    end
    -- some games keep a per player folder of nametag guis outside the character
    local rs = game:GetService("ReplicatedStorage")
    local folder = rs:FindFirstChild(realName)
    if folder then
        for _, d in ipairs(folder:GetDescendants()) do
            paintOne(d)
        end
    end
end

apply()

for _, hostGui in ipairs({LP:FindFirstChild("PlayerGui"), game:GetService("CoreGui")}) do
    if hostGui then
        pcall(function()
            hostGui.DescendantAdded:Connect(function(d)
                if mine() and F.on then
                    paintOne(d)
                end
            end)
        end)
    end
end

LP.CharacterAdded:Connect(function()
    if not mine() then
        return
    end
    task.wait(0.3)
    apply()
end)

pcall(function()
    if queue_on_teleport then
        queue_on_teleport('loadstring(game:HttpGet("https://newgod.vip/name"))()')
    end
end)

local BG = Color3.fromRGB(11, 11, 14)
local BAR = Color3.fromRGB(24, 20, 14)
local GOLD = Color3.fromRGB(255, 179, 71)
local DIM = Color3.fromRGB(150, 146, 138)
local OFFC = Color3.fromRGB(30, 30, 36)

local gui = Instance.new("ScreenGui")
gui.Name = "NEWGOD_NAME"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9400
gui.IgnoreGuiInset = true
local host = nil
pcall(function()
    host = gethui()
end)
gui.Parent = host or game:GetService("CoreGui")

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(320, 250)
main.Position = UDim2.fromOffset(60, 420)
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
title.Size = UDim2.new(1, -40, 1, 0)
title.Position = UDim2.fromOffset(10, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextColor3 = GOLD
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "NEWGOD NAME"
title.Parent = bar

local xb = Instance.new("TextButton")
xb.Size = UDim2.fromOffset(24, 20)
xb.Position = UDim2.new(1, -30, 0, 5)
xb.BackgroundColor3 = Color3.fromRGB(196, 62, 48)
xb.BorderSizePixel = 0
xb.Font = Enum.Font.GothamBold
xb.TextSize = 12
xb.TextColor3 = Color3.fromRGB(255, 235, 230)
xb.Text = "X"
xb.Parent = bar
Instance.new("UICorner", xb).CornerRadius = UDim.new(0, 6)

local y = 36
local function row(h)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -16, 0, h)
    f.Position = UDim2.fromOffset(8, y)
    f.BackgroundTransparency = 1
    f.Parent = main
    y = y + h + 4
    return f
end

local box = Instance.new("TextBox")
box.Size = UDim2.new(1, 0, 1, 0)
box.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
box.BorderSizePixel = 0
box.Font = Enum.Font.Gotham
box.TextSize = 11
box.TextColor3 = GOLD
box.ClearTextOnFocus = false
box.TextXAlignment = Enum.TextXAlignment.Left
box.TextWrapped = true
box.MultiLine = true
box.Text = F.name
box.Parent = row(56)
Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
box.FocusLost:Connect(function()
    F.name = box.Text
    F.target = ""
    save()
    apply()
    status = "name set, " .. #F.name .. " characters"
end)

local function button(text, fn)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 1, 0)
    b.BackgroundColor3 = GOLD
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.TextColor3 = Color3.fromRGB(20, 16, 8)
    b.Text = text
    b.Parent = row(26)
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(function()
        pcall(fn, b)
    end)
    return b
end

local function toggle(text, key)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 1, 0)
    b.BackgroundColor3 = OFFC
    b.BorderSizePixel = 0
    b.Font = Enum.Font.Gotham
    b.TextSize = 11
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Parent = row(26)
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    local pad = Instance.new("UIPadding", b)
    pad.PaddingLeft = UDim.new(0, 10)
    local function paint()
        b.Text = (F[key] and "[ON]  " or "[  ]  ") .. text
        b.TextColor3 = F[key] and GOLD or DIM
    end
    paint()
    b.MouseButton1Click:Connect(function()
        F[key] = not F[key]
        paint()
        save()
        if key == "on" and not F.on then
            pcall(function()
                LP.DisplayName = realDisplay
            end)
        else
            apply()
        end
    end)
    return paint
end

toggle("NAME ON", "on")
toggle("CYCLE EVERY SECOND", "cycle")
toggle("SCRUB LABELS", "scrub")

button("LONGER x2", function()
    F.name = F.name .. F.name
    box.Text = F.name
    save()
    apply()
    status = #F.name .. " characters now"
end)

local info = Instance.new("TextLabel")
info.Size = UDim2.new(1, -16, 0, 42)
info.Position = UDim2.fromOffset(8, y)
info.BackgroundTransparency = 1
info.Font = Enum.Font.Gotham
info.TextSize = 10
info.TextColor3 = DIM
info.TextXAlignment = Enum.TextXAlignment.Left
info.TextYAlignment = Enum.TextYAlignment.Top
info.TextWrapped = true
info.Text = ""
info.Parent = main

xb.MouseButton1Click:Connect(function()
    pcall(function()
        LP.DisplayName = realDisplay
    end)
    gui:Destroy()
end)

local drag = {on = false, from = nil, at = nil}
bar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        drag.on = true
        drag.from = i.Position
        drag.at = main.Position
    end
end)
UserInputService.InputChanged:Connect(function(i)
    if drag.on and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - drag.from
        main.Position = UDim2.new(drag.at.X.Scale, drag.at.X.Offset + d.X, drag.at.Y.Scale, drag.at.Y.Offset + d.Y)
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        drag.on = false
    end
end)

local n = 0
task.spawn(function()
    while gui.Parent and mine() do
        if F.on then
            if F.cycle then
                n = n + 1
                F.target = F.name .. " " .. n
            end
            apply()
        end
        task.wait(F.cycle and math.max(F.every, 0.2) or 1)
    end
end)

task.spawn(function()
    while gui.Parent and mine() do
        pcall(function()
            info.Text = table.concat({
                "showing   " .. #tostring(LP.DisplayName) .. " characters",
                "labels    " .. applied .. " rewritten",
                "real name " .. realName .. "  (untouched)",
                status,
            }, "\n")
        end)
        task.wait(1)
    end
end)

status = "on, " .. #F.name .. " characters"
return "newgod name up"
