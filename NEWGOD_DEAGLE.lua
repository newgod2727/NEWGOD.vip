-- NEWGOD DEAGLE v2

local BUILD = "2026-08-25 07:37"

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local TextChatService = game:GetService("TextChatService")

local LP = Players.LocalPlayer

-- the name goes first, before anything is required and before one frame is drawn,
-- so no label ever renders the real account even once
local realName = LP.Name
local realDisplay = LP.DisplayName
local wantName = "DEAGLEONTOP"
local spoofOn = true
pcall(function()
    if isfile and isfile("NEWGOD_DEAGLE_cfg.json") then
        local t = HttpService:JSONDecode(readfile("NEWGOD_DEAGLE_cfg.json"))
        if type(t.username) == "string" and t.username ~= "" then
            wantName = t.username
        end
        if type(t.spoofname) == "boolean" then
            spoofOn = t.spoofname
        end
    end
end)
pcall(function()
    if spoofOn then
        LP.DisplayName = wantName
    end
end)

local function swapText(d)
    if not spoofOn then
        return
    end
    if d:IsA("TextLabel") or d:IsA("TextButton") then
        local t = d.Text
        if t and t ~= "" and string.find(t, realName, 1, true) then
            pcall(function()
                d.Text = string.gsub(t, realName, wantName)
            end)
        end
    end
end

for _, h in ipairs({LP:FindFirstChild("PlayerGui"), game:GetService("CoreGui")}) do
    if h then
        pcall(function()
            h.DescendantAdded:Connect(swapText)
        end)
    end
end
LP.ChildAdded:Connect(function(c)
    if c:IsA("PlayerGui") then
        pcall(function()
            c.DescendantAdded:Connect(swapText)
        end)
    end
end)

local function nukeOldPanels()
    local hosts = {game:GetService("CoreGui")}
    pcall(function()
        table.insert(hosts, gethui())
    end)
    for _, h in ipairs(hosts) do
        if h then
            for _, g in ipairs(h:GetChildren()) do
                if g.Name == "NEWGOD_DEAGLE" then
                    pcall(function()
                        g:Destroy()
                    end)
                end
            end
        end
    end
end
nukeOldPanels()

local GEN = (tonumber(getgenv().NEWGOD_GEN) or 0) + 1
getgenv().NEWGOD_GEN = GEN
local function mine()
    return getgenv().NEWGOD_GEN == GEN
end

if getgenv().NEWGOD and getgenv().NEWGOD.F then
    for k in pairs(getgenv().NEWGOD.F) do
        if type(getgenv().NEWGOD.F[k]) == "boolean" then
            getgenv().NEWGOD.F[k] = false
        end
    end
end
task.wait(0.15)

local Network = require(ReplicatedStorage.Modules.Packages.Network)
local ML = LP:WaitForChild("PlayerScripts"):WaitForChild("ModuleLoader")
local RoundController = require(ML.RoundController)
local ClientData = require(ML.ClientData)

-- measured out of the game, not guessed
local HIT_GAP = 0.9
local MISS_GAP = 1.1
local ELO_NO_BOTS = 1250
local SPIN_COOLDOWN = 900
local MAIN_PLACE = 84556640895285
local RANKED_PLACE = 112087763192016
local GREEK_PLACE = 94334870778766
local FAST_SKINS = {["Frozen Deagle"] = true, ["Samurai Deagle"] = true, ["Evil Deagle"] = true, ["Ninja Deagle"] = true}

local LIM = {
    gapFloor = 0.9,
    gapCeil = 1.30,
    speed = 500,
    flyspeed = 900,
    safeheight = 900,
    victimGap = 8,
    killCap = 200,
    safedepth = 160,
    claimEvery = 45,
    caseEvery = 15,
    codeEvery = 300,
    shopEvery = 30,
}

local BG = Color3.fromRGB(11, 11, 14)
local BAR = Color3.fromRGB(24, 20, 14)
local GOLD = Color3.fromRGB(255, 179, 71)
local TXT = Color3.fromRGB(236, 236, 236)
local DIM = Color3.fromRGB(150, 146, 138)
local OFFC = Color3.fromRGB(30, 30, 36)
local RED = Color3.fromRGB(196, 62, 48)

local DEFAULTS = {
    forceon = true,
    autofarm = true,
    autocoin = true,
    autodeploy = true,
    autorespawn = true,
    eloguard = true,
    elobleed = false,
    silent = true,
    esp = true,
    fly = false,
    noclip = false,
    infjump = true,
    antivoid = true,
    safemode = false,
    nopopup = true,
    hidevape = true,
    vapesync = true,
    spoofname = true,
    scrubname = true,
    autoclaim = true,
    autospin = true,
    autocase = true,
    autocode = true,
    autoskin = true,
    autovote = true,
    targetBots = true,
    targetPlayers = true,
    botsfirst = true,
    norepeat = true,
    watchchat = true,
    antiafk = true,
    revenge = true,
    hunt = true,
    speed = 250,
    flyspeed = 400,
    safeheight = 320,
    victimGap = 1.2,
    killCap = 200,
    username = "DEAGLEONTOP",
    basement = false,
    phase = true,
    autohide = true,
    fastcoin = true,
    safedepth = 5,
    offlist = {},
}

local F = {}
for k, v in pairs(DEFAULTS) do
    F[k] = v
end

local ALWAYS_ON = {
    "autofarm", "autocoin", "autodeploy", "autorespawn", "silent", "esp", "infjump",
    "antivoid", "nopopup", "autohide", "fastcoin", "hidevape", "vapesync", "spoofname", "scrubname",
    "autoclaim", "autospin", "autocase", "autocode", "autoskin", "autovote",
    "targetBots", "targetPlayers", "botsfirst", "eloguard", "forceon", "revenge", "hunt", "antiafk",
}

local CFG_PATH = "NEWGOD_DEAGLE_cfg.json"
local VAPE_PATH = "NEWGOD_DEAGLE_vape.json"

local function clampCfg()
    F.speed = math.clamp(tonumber(F.speed) or 25, 16, LIM.speed)
    F.flyspeed = math.clamp(tonumber(F.flyspeed) or 120, 20, LIM.flyspeed)
    F.safeheight = math.clamp(tonumber(F.safeheight) or 320, 60, LIM.safeheight)
    F.victimGap = math.clamp(tonumber(F.victimGap) or 1.2, 0, LIM.victimGap)
    F.killCap = math.clamp(math.floor(tonumber(F.killCap) or 200), 0, LIM.killCap)
    F.safedepth = math.clamp(tonumber(F.safedepth) or 5, 2, LIM.safedepth)
    if type(F.offlist) ~= "table" then
        F.offlist = {}
    end
    -- under the map is banned for good. it killed the farm and it is never used again
    F.basement = false
    if type(F.username) ~= "string" or F.username == "" then
        F.username = DEFAULTS.username
    end
    F.username = string.sub(F.username, 1, 20)
end

local function saveCfg()
    pcall(function()
        writefile(CFG_PATH, HttpService:JSONEncode(F))
    end)
end

local function loadCfg()
    pcall(function()
        if isfile and isfile(CFG_PATH) then
            local t = HttpService:JSONDecode(readfile(CFG_PATH))
            for k, v in pairs(t) do
                if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then
                    F[k] = v
                end
            end
        end
    end)
    clampCfg()
    if F.forceon then
        for _, k in ipairs(ALWAYS_ON) do
            if not F.offlist[k] then
                F[k] = true
            end
        end
    end
end
loadCfg()

local stats = {
    shots = 0, landed = 0, miss = 0, dry = 0, coins = 0, claims = 0, spins = 0,
    cases = 0, t0 = os.clock(), gap = HIT_GAP + 0.01, pending = 0, blocked = 0,
    startElo = nil, saved = 0, streak = 0, backoff = 0, kills0 = nil, killsNow = 0, diedTo = 0,
    holdFor = 0, holdStart = 0, eventMap = false, achClaimed = 0, spinRefused = 0,
}
local statusText = "loading"
local lastErr = ""
local noticeText = ""

local function setStatus(s)
    statusText = s
end

local function notice(s)
    noticeText = s
end

local function guard(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        lastErr = name .. ": " .. tostring(err)
        setStatus("ERR " .. lastErr)
    end
    return ok
end

local function hum()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function root()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function alive()
    local h = hum()
    return h ~= nil and h.Health > 0
end

local function inRound()
    return LP:GetAttribute("InRound") == true
end

local function elo()
    local d = ClientData.Data
    return (d and tonumber(d.Elo)) or nil
end

local function botBand(e)
    if not e then
        return "?"
    end
    if e >= ELO_NO_BOTS then
        return "0 bots"
    elseif e >= 875 then
        return "4 bots"
    elseif e >= 500 then
        return "6 bots"
    end
    return "8 bots"
end

local KILLER_PATH = "NEWGOD_DEAGLE_killers.json"
local killersHere = {}
local loadedAt = os.clock()
local killers = {}
local killerOrder = {}
local lastKilledBy = ""

-- the list has to outlive a reload and a rejoin, otherwise he gets a free kill
-- every time the script restarts
pcall(function()
    if isfile and isfile(KILLER_PATH) then
        local t = HttpService:JSONDecode(readfile(KILLER_PATH))
        if type(t) == "table" then
            for _, row in ipairs(t) do
                if type(row) == "table" and type(row.name) == "string" then
                    killers[row.name] = tonumber(row.n) or 1
                    killerOrder[#killerOrder + 1] = row.name
                end
            end
        end
    end
end)

local function saveKillers()
    pcall(function()
        local t = {}
        for _, nm in ipairs(killerOrder) do
            t[#t + 1] = {name = nm, n = killers[nm]}
        end
        writefile(KILLER_PATH, HttpService:JSONEncode(t))
    end)
end

local function isKiller(model)
    if not F.revenge then
        return false
    end
    local p = Players:GetPlayerFromCharacter(model)
    return p ~= nil and killers[p.Name] ~= nil
end

local function noteKiller(name)
    if not killers[name] then
        killers[name] = 0
        killerOrder[#killerOrder + 1] = name
    end
    killers[name] = killers[name] + 1
    killersHere[name] = (killersHere[name] or 0) + 1
    lastKilledBy = name
    saveKillers()
end

local function hitboxOf(model)
    return model:FindFirstChild("HeadHitbox") or model:FindFirstChild("Head") or model:FindFirstChild("BodyHitbox")
end

-- target book keeping
local deadUntil = {}
local victimAt = {}
local killTimes = {}
local sweptAt = 0
local cacheList = {}
local cacheAt = 0

local function usable(model, isBot)
    if not model or not model.Parent then
        return nil
    end
    if model:GetAttribute("Alive") == false then
        return nil
    end
    if model:GetAttribute("Dead") == true then
        return nil
    end
    if model:GetAttribute("SpawnProtection") == true then
        return nil
    end
    local h = model:FindFirstChildOfClass("Humanoid")
    if not h or h.Health <= 0 then
        return nil
    end
    local hb = hitboxOf(model)
    if not hb or not hb.Parent then
        return nil
    end
    local now = os.clock()
    local hold = deadUntil[model] or 0
    if isKiller(model) then
        hold = hold - 1.2
    end
    if hold > now then
        return nil
    end
    if isBot == false and F.norepeat and not isKiller(model) then
        local p = Players:GetPlayerFromCharacter(model)
        local key = p and p.UserId or model
        if (victimAt[key] or 0) + F.victimGap > now then
            return nil
        end
    end
    return hb
end

-- these two tables are keyed by instances that die every respawn, so drop the stale rows
local function sweepMemory()
    local now = os.clock()
    if now - sweptAt < 30 then
        return
    end
    sweptAt = now
    for k, t in pairs(deadUntil) do
        if t < now then
            deadUntil[k] = nil
        end
    end
    for k, t in pairs(victimAt) do
        if t + 120 < now then
            victimAt[k] = nil
        end
    end
end

local function buildTargets()
    local out = {}
    if F.targetBots then
        for _, m in ipairs(workspace:GetChildren()) do
            if m:IsA("Model") and m:GetAttribute("IsBot") == true then
                if usable(m, true) then
                    out[#out + 1] = {m = m, bot = true}
                end
            end
        end
    end
    if F.targetPlayers then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Character then
                if usable(p.Character, false) then
                    out[#out + 1] = {m = p.Character, bot = false, plr = p}
                end
            end
        end
    end
    return out
end

local function targetList()
    local now = os.clock()
    if now - cacheAt > 0.06 then
        cacheList = buildTargets()
        cacheAt = now
    end
    return cacheList
end

local floorY = nil
local floorAt = 0
local floorFrom = "none"

-- the play floor is where living people stand, not the lowest decoration in the
-- map folder. measured on the ranked map: other players at y 2, lowest map part
-- at y -33, so the old reference let the body sit 7 studs underground and
-- called it fine
local function readFloor()
    local now = os.clock()
    if floorY and now - floorAt < 1 then
        return floorY
    end
    floorAt = now
    local ys = {}
    for _, e in ipairs(targetList()) do
        local hb = hitboxOf(e.m)
        if hb then
            ys[#ys + 1] = hb.Position.Y
        end
    end
    if #ys > 0 then
        table.sort(ys)
        floorY = ys[math.ceil(#ys / 2)]
        floorFrom = #ys .. " players"
        return floorY
    end
    local sp = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
    if sp then
        floorY = sp.Position.Y
        floorFrom = "spawn"
        return floorY
    end
    if floorY then
        floorFrom = "last known"
        return floorY
    end
    -- never seen a living soul yet. remember the highest place this body has
    -- actually stood, which is the only floor we can prove
    local h = hum()
    local r = root()
    if h and r and h.FloorMaterial ~= Enum.Material.Air then
        floorY = r.Position.Y
        floorFrom = "own footing"
        return floorY
    end
    return nil
end

local function pickTarget()
    local r = root()
    if not r then
        return nil
    end
    local list = targetList()
    local best, bd, bestBot, bestRev = nil, math.huge, false, false
    for _, e in ipairs(list) do
        local hb = hitboxOf(e.m)
        if hb then
            local d = (hb.Position - r.Position).Magnitude
            local rev = isKiller(e.m)
            local better
            if rev ~= bestRev then
                better = rev
            elseif F.botsfirst and e.bot ~= bestBot then
                better = e.bot
            else
                better = d < bd
            end
            if best == nil or better then
                best, bd, bestBot, bestRev = e, d, e.bot, rev
            end
        end
    end
    return best, bd, bestRev
end

local rawFire = Network.FireServer

local function fireAt(entry)
    local m = entry.m
    local hb = usable(m, entry.bot)
    if not hb then
        return false
    end
    local origin = workspace.CurrentCamera.CFrame.Position
    rawFire(Network, "Shoot", origin, hb.Position, hb, hb.Position)
    local now = os.clock()
    deadUntil[m] = now + 1.8
    local p = entry.plr or Players:GetPlayerFromCharacter(m)
    victimAt[p and p.UserId or m] = now
    killTimes[#killTimes + 1] = now
    stats.shots = stats.shots + 1
    return true
end

-- kill rate limit, his "everything to a limit"
local function killRateOk()
    if F.killCap <= 0 then
        return true
    end
    local cut = os.clock() - 60
    local n = 0
    for i = #killTimes, 1, -1 do
        if killTimes[i] < cut then
            table.remove(killTimes, i)
        else
            n = n + 1
        end
    end
    if n >= F.killCap then
        stats.blocked = stats.blocked + 1
        return false
    end
    return true
end

local coinBusyUntil = 0

local function coinsMoving()
    return os.clock() < coinBusyUntil
end

local function sweepCoins()
    local f = workspace:FindFirstChild("LocalEventCoins")
    local r = root()
    if not f or not r then
        return 0
    end
    if r.Anchored then
        r.Anchored = false
    end
    local home = r.CFrame
    coinBusyUntil = os.clock() + 12
    local dwell = F.fastcoin and 0.07 or 0.25
    local settle = F.fastcoin and 0.04 or 0.1
    local n = 0
    for _, c in ipairs(f:GetChildren()) do
        local id = c:GetAttribute("CoinId")
        if id and r.Parent then
            r.CFrame = CFrame.new(c:GetPivot().Position + Vector3.new(0, 3, 0))
            task.wait(dwell)
            rawFire(Network, "CollectEventCoin", id, r.Position)
            n = n + 1
            task.wait(settle)
        end
    end
    if r.Parent then
        r.AssemblyLinearVelocity = Vector3.zero
        r.CFrame = home
    end
    coinBusyUntil = 0
    return n
end

-- pop up window killer
-- read off MainGui, not guessed. these are the top level frames that pop up
-- over the game and none of them are needed to play
local POPUP_GUIS = {
    "OneTimeOfferGui", "RoundStatsGui", "RankStatsGui", "VotingGui", "EventUI",
    "ExclusiveShopGuiNEW", "ExclusiveButtons", "FreeButtons", "DivineBundleGui",
    "AbyssBundleGui", "GiftList", "DailyShopGui", "LevelUpGui", "RankUpGui",
    "UnboxGui", "CaseOpeningGui", "CaseInspectGui", "GroupRewardGui", "RewardsGui",
    "TimeRewardsGui", "PopupsGui", "NotificationGui", "NewFrames", "CodeGui",
    "SellConfirmGui", "BackgroundBlur", "EdgeBlur", "BlackGui",
}

local popupHooked2 = {}

local function clearScreenEffects()
    local L = game:GetService("Lighting")
    for _, e in ipairs(L:GetDescendants()) do
        if (e:IsA("BlurEffect") or e:IsA("DepthOfFieldEffect")) and e.Enabled then
            e.Enabled = false
        end
    end
end

local function killClickCatchers(frame)
    for _, d in ipairs(frame:GetDescendants()) do
        if (d:IsA("ImageButton") or d:IsA("TextButton")) and d.Active
           and d.AbsoluteSize.X > 1000 and d.AbsoluteSize.Y > 500 then
            d.Active = false
            d.Visible = false
        end
    end
end

local function hidePopupFrames()
    local pg = LP:FindFirstChild("PlayerGui")
    local mg = pg and pg:FindFirstChild("MainGui")
    if not mg then
        return
    end
    clearScreenEffects()
    for _, name in ipairs(POPUP_GUIS) do
        local f = mg:FindFirstChild(name)
        if f then
            if f:IsA("GuiObject") then
                if f.Visible then
                    f.Visible = false
                    killClickCatchers(f)
                    clearScreenEffects()
                end
                killClickCatchers(f)
                if not popupHooked2[f] then
                    popupHooked2[f] = true
                    -- put it back down the instant the game raises it again
                    f:GetPropertyChangedSignal("Visible"):Connect(function()
                        if F.nopopup and f.Visible then
                            f.Visible = false
                            killClickCatchers(f)
                            clearScreenEffects()
                        end
                    end)
                end
            else
                for _, c in ipairs(f:GetChildren()) do
                    if c:IsA("GuiObject") and c.Visible then
                        c.Visible = false
                    end
                end
            end
        end
    end
end

local MONETIZE_NAMES = {
    "ExclusiveButtons", "FreeButtons", "StarterPackButton", "DivineBundleButton",
    "AbyssBundleButton", "RoundMonetization", "OneTimeOffer", "BoostOffer",
    "NukeOffer", "PromptGui", "GiftGui", "RewardedAds", "Popups", "LevelUpReward",
    "DailyShopPopup", "OfferFrame", "AdPrompt",
}

local function killPopups()
    hidePopupFrames()
    local pg = LP:FindFirstChild("PlayerGui")
    if pg then
        for _, sg in ipairs(pg:GetChildren()) do
            if sg:IsA("ScreenGui") then
                for _, name in ipairs(MONETIZE_NAMES) do
                    local f = sg:FindFirstChild(name, true)
                    if f and f:IsA("GuiObject") and f.Visible then
                        f.Visible = false
                    end
                end
            end
        end
    end
    pcall(function()
        local cg = game:GetService("CoreGui")
        for _, n in ipairs({"PurchasePromptApp", "RewardedVideoAdPlayer", "ImmersiveBrandedAds"}) do
            local g = cg:FindFirstChild(n)
            if g and g:IsA("ScreenGui") and g.Enabled then
                g.Enabled = false
            end
        end
    end)
end

local popupHooked = false
local function hookPopups()
    if popupHooked then
        return
    end
    popupHooked = true
    pcall(function()
        local Popup = require(ReplicatedStorage.Modules.Shared.Utils.Popup)
        for _, k in ipairs({"Notification", "Error", "SetTimer"}) do
            if type(Popup[k]) == "function" then
                local old = Popup[k]
                Popup[k] = function(...)
                    if F.nopopup then
                        return
                    end
                    return old(...)
                end
            end
        end
    end)
    pcall(function()
        local oldP = MarketplaceService.PromptProductPurchase
        hookfunction(oldP, function(self, plr, id, ...)
            if F.nopopup then
                return
            end
            return oldP(self, plr, id, ...)
        end)
    end)
    pcall(function()
        local oldG = MarketplaceService.PromptGamePassPurchase
        hookfunction(oldG, function(self, plr, id, ...)
            if F.nopopup then
                return
            end
            return oldG(self, plr, id, ...)
        end)
    end)
end

-- vape v4, remember his modules and put them back when vape drops them
local vapeWant = {}
local function loadVapeWant()
    pcall(function()
        if isfile and isfile(VAPE_PATH) then
            local t = HttpService:JSONDecode(readfile(VAPE_PATH))
            if type(t) == "table" then
                vapeWant = t
            end
        end
    end)
end
loadVapeWant()

local function vapeModules()
    if not shared or not shared.vape then
        return nil
    end
    return shared.vape.Modules
end

local function vapeSnapshot()
    local mods = vapeModules()
    if not mods then
        return 0, 0
    end
    local live, on = 0, 0
    for name, m in pairs(mods) do
        if type(m) == "table" and m.Enabled ~= nil then
            live = live + 1
            if m.Enabled then
                on = on + 1
                if not vapeWant[name] then
                    vapeWant[name] = true
                    stats.saved = stats.saved + 1
                    pcall(function()
                        writefile(VAPE_PATH, HttpService:JSONEncode(vapeWant))
                    end)
                end
            end
        end
    end
    return live, on
end

local function vapeRestore(force)
    local mods = vapeModules()
    if not mods then
        return 0
    end
    local want, on = 0, 0
    for name in pairs(vapeWant) do
        if mods[name] then
            want = want + 1
            if mods[name].Enabled then
                on = on + 1
            end
        end
    end
    if want == 0 then
        return 0
    end
    -- only step in when the profile collapsed, never undo a deliberate off
    if not force and on * 2 >= want then
        return 0
    end
    local fixed = 0
    for name in pairs(vapeWant) do
        local m = mods[name]
        if m and not m.Enabled then
            pcall(function()
                if type(m.ToggleButton) == "function" then
                    m:ToggleButton(true)
                elseif type(m.Toggle) == "function" then
                    m:Toggle()
                end
            end)
            if m.Enabled then
                fixed = fixed + 1
            end
        end
    end
    return fixed
end

local VAPE_HINTS = {"vape", "linoria", "orion"}
local function hideVape()
    local hosts = {game:GetService("CoreGui")}
    pcall(function()
        table.insert(hosts, gethui())
    end)
    for _, h in ipairs(hosts) do
        if h then
            for _, g in ipairs(h:GetChildren()) do
                if g:IsA("ScreenGui") and g.Name ~= "NEWGOD_DEAGLE" then
                    for _, hint in ipairs(VAPE_HINTS) do
                        if string.find(string.lower(g.Name), hint) then
                            g.Enabled = false
                        end
                    end
                end
            end
        end
    end
end

-- server still owns the real account, this only cleans his screen
local function applyName()
    spoofOn = F.spoofname
    if F.username ~= "" then
        wantName = F.username
    end
    pcall(function()
        if spoofOn then
            LP.DisplayName = wantName
        else
            LP.DisplayName = realDisplay
        end
    end)
end

local function scrubNames()
    if not F.scrubname or not F.spoofname then
        return
    end
    local want = wantName
    local hosts = {LP:FindFirstChild("PlayerGui"), game:GetService("CoreGui")}
    for _, h in ipairs(hosts) do
        if h then
            for _, d in ipairs(h:GetDescendants()) do
                if d:IsA("TextLabel") or d:IsA("TextButton") then
                    local t = d.Text
                    if t and t ~= "" and (t == realName or t == realDisplay or string.find(t, realName, 1, true)) then
                        pcall(function()
                            d.Text = string.gsub(t, realName, want)
                        end)
                    end
                end
            end
        end
    end
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == realName then
            pcall(function()
                d.Text = want
            end)
        end
    end
end

-- safe spot. the server does no distance check on Shoot, so height costs nothing
-- the floor is read off the people standing on it, never off our own height,
-- otherwise every reload anchors another safeheight above the last one
local safeAnchor = nil
local groundY = nil
local mapUnderY = nil
local mapReadAt = 0

local function readGround()
    local low = nil
    for _, e in ipairs(targetList()) do
        local hb = hitboxOf(e.m)
        if hb and (not low or hb.Position.Y < low) then
            low = hb.Position.Y
        end
    end
    if low then
        groundY = low
    end
    return groundY
end

local function fallY()
    local fp = workspace:FindFirstChild("FallPart")
    if fp and fp:IsA("BasePart") then
        return fp.Position.Y
    end
    return -200
end

-- the underside of the map, measured off the map parts themselves, so the basement
-- lands between the map and the plane that kills you
local function readUnder()
    if mapUnderY and os.clock() - mapReadAt < 10 then
        return mapUnderY
    end
    mapReadAt = os.clock()
    local low = nil
    local m = workspace:FindFirstChild("Map")
    if m then
        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then
                local b = d.Position.Y - d.Size.Y / 2
                if not low or b < low then
                    low = b
                end
            end
        end
    end
    mapUnderY = low
    return mapUnderY
end

local function basementY()
    local under = readUnder()
    local kill = fallY()
    if not under then
        under = (groundY or 0) - 12
    end
    local want = under - F.safedepth
    return math.clamp(want, kill + 30, under - 2)
end

local standPad = nil
local holdPos = nil

local function killPad()
    if standPad and standPad.Parent then
        standPad:Destroy()
    end
    standPad = nil
    if holdPos and holdPos.Parent then
        holdPos:Destroy()
    end
    holdPos = nil
end

local function makePad(pos)
    if not standPad or not standPad.Parent then
        standPad = Instance.new("Part")
        standPad.Name = "NG_PAD"
        standPad.Size = Vector3.new(80, 2, 80)
        standPad.Anchored = true
        standPad.CanCollide = true
        standPad.Material = Enum.Material.Neon
        standPad.Color = GOLD
        standPad.Transparency = 0.65
        standPad.Parent = workspace
    end
    local want = Vector3.new(pos.X, pos.Y - 3.5, pos.Z)
    if (standPad.Position - want).Magnitude > 1 then
        standPad.Position = want
    end
end

local function holdAt(pos)
    local r = root()
    if not r then
        return
    end
    if not holdPos or not holdPos.Parent then
        holdPos = Instance.new("BodyPosition")
        holdPos.Name = "NG_HOLD"
        holdPos.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        holdPos.P = 40000
        holdPos.D = 2500
        holdPos.Parent = r
    end
    holdPos.Position = pos
end

-- phase: stand inside a solid block. a real player cannot walk into one, so the only
-- thing that still reaches is another script, and those are on the killers list
local phaseCF = nil
local phasePart = nil
local phaseChecks = 0
local phaseIn = 0

local function insideSolid(pos, ignorePart)
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LP.Character, standPad}
    params.MaxParts = 200
    local hits = workspace:GetPartBoundsInBox(CFrame.new(pos), Vector3.new(3, 5, 3), params)
    for _, h in ipairs(hits) do
        if h:IsA("BasePart") and h.CanCollide and (not ignorePart or h == ignorePart) then
            return h
        end
    end
    return nil
end

-- whether a point is inside a part is a question about that part, so answer it with
-- the part's own bounds instead of asking the world what happens to be nearby
local function pointIsInPart(pt, part)
    local lp = part.CFrame:PointToObjectSpace(pt)
    local sz = part.Size
    return math.abs(lp.X) <= sz.X / 2 - 1.6
       and math.abs(lp.Y) <= sz.Y / 2 - 2.6
       and math.abs(lp.Z) <= sz.Z / 2 - 1.6
end

local PHASE_SAMPLES = {
    Vector3.new(0, 0, 0),
    Vector3.new(0, 0.25, 0), Vector3.new(0, -0.25, 0),
    Vector3.new(0.25, 0, 0), Vector3.new(-0.25, 0, 0),
    Vector3.new(0, 0, 0.25), Vector3.new(0, 0, -0.25),
    Vector3.new(0.3, 0.2, 0.3), Vector3.new(-0.3, 0.2, -0.3),
    Vector3.new(0.3, -0.2, -0.3), Vector3.new(-0.3, -0.2, 0.3),
}

local function pointInside(part)
    local sz = part.Size
    for _, f in ipairs(PHASE_SAMPLES) do
        local pt = part.CFrame:PointToWorldSpace(Vector3.new(sz.X * f.X, sz.Y * f.Y, sz.Z * f.Z))
        -- the bounds test only rules a point OUT cheaply; whether it is really
        -- buried is a question only the world can answer
        if insideSolid(pt, nil) then
            return pt
        end
    end
    return nil
end

local function findPhaseSpot()
    local map = workspace:FindFirstChild("Map")
    if not map then
        return nil, nil
    end
    local ranked = {}
    for _, d in ipairs(map:GetDescendants()) do
        if d:IsA("BasePart") and d.CanCollide and d.Transparency < 0.9 then
            local sz = d.Size
            if math.min(sz.X, sz.Y, sz.Z) >= 8 then
                ranked[#ranked + 1] = {part = d, vol = sz.X * sz.Y * sz.Z}
            end
        end
    end
    table.sort(ranked, function(a, b)
        return a.vol > b.vol
    end)
    -- biggest first, and the first one that really has solid material inside wins
    -- prefer a spot at or above where people stand, but a solid one below is far
    -- better than no spot at all. measured on the ranked map: the only block big
    -- enough to hold a body is the floor slab itself, solid at 9 of 9 samples.
    local floor = readFloor()
    local fallbackPart, fallbackPt = nil, nil
    for i = 1, math.min(#ranked, 25) do
        local pt = pointInside(ranked[i].part)
        if pt then
            if not floor or pt.Y >= floor - 4 then
                return ranked[i].part, pt
            end
            if not fallbackPart then
                fallbackPart, fallbackPt = ranked[i].part, pt
            end
        end
    end
    return fallbackPart, fallbackPt
end

local function enterPhase()
    local part, pt = findPhaseSpot()
    if not part or not pt then
        return nil
    end
    phasePart = part
    phaseCF = CFrame.new(pt)
    return phaseCF
end

local function unanchorMe()
    local r = root()
    if r and r.Anchored then
        r.Anchored = false
    end
end

local function clearPhase()
    phaseCF = nil
    phasePart = nil
    unanchorMe()
end

local function restoreCollide()
    local c = LP.Character
    if not c then
        return
    end
    for _, d in ipairs(c:GetDescendants()) do
        if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and not d.CanCollide then
            d.CanCollide = true
        end
    end
end

local function noclipMe()
    local c = LP.Character
    if not c then
        return
    end
    for _, d in ipairs(c:GetDescendants()) do
        if d:IsA("BasePart") and d.CanCollide then
            d.CanCollide = false
        end
    end
end

local function safeSpot()
    local r = root()
    if not r then
        return nil
    end
    local g = readGround()
    if F.basement then
        local by = basementY()
        if not safeAnchor or math.abs(safeAnchor.Position.Y - by) > 3 then
            local px, pz = r.Position.X, r.Position.Z
            if safeAnchor then
                px, pz = safeAnchor.Position.X, safeAnchor.Position.Z
            end
            safeAnchor = CFrame.new(Vector3.new(px, by, pz))
        end
        return safeAnchor
    end
    if not safeAnchor or safeAnchor.Position.Y < (g or 0) then
        local baseY = g or math.min(r.Position.Y, 0)
        safeAnchor = CFrame.new(Vector3.new(r.Position.X, baseY + F.safeheight, r.Position.Z))
    elseif g and safeAnchor.Position.Y > g + F.safeheight + 40 then
        safeAnchor = CFrame.new(Vector3.new(safeAnchor.Position.X, g + F.safeheight, safeAnchor.Position.Z))
    end
    return safeAnchor
end

local function resetSafeSpot()
    safeAnchor = nil
end

local function eloBlocked()
    if not F.eloguard then
        return false
    end
    local e = elo()
    return type(e) == "number" and e >= ELO_NO_BOTS and not F.targetPlayers
end

local function ensureDeployed()
    if inRound() and alive() then
        return true
    end
    local r0 = root()
    if r0 and r0.Anchored then
        r0.Anchored = false
    end
    if ClientData.RoundOnGoing ~= true then
        return false
    end
    local ok = false
    pcall(function()
        ok = RoundController.Spawn() and true or false
    end)
    return ok
end

-- silent aim, redirect anything the game itself fires
Network.FireServer = function(self, name, ...)
    if F.silent and name == "Shoot" then
        local e = pickTarget()
        if e then
            local hb = hitboxOf(e.m)
            if hb then
                local origin = workspace.CurrentCamera.CFrame.Position
                return rawFire(self, name, origin, hb.Position, hb, hb.Position)
            end
        end
    end
    return rawFire(self, name, ...)
end

local espTags = {}
local function clearEsp()
    for m, h in pairs(espTags) do
        if h and h.Parent then
            h:Destroy()
        end
        espTags[m] = nil
    end
end

local function updateEsp()
    local want = {}
    for _, e in ipairs(targetList()) do
        want[e.m] = true
        if not espTags[e.m] or not espTags[e.m].Parent then
            local hl = Instance.new("Highlight")
            hl.FillColor = e.bot and GOLD or RED
            hl.FillTransparency = 0.55
            hl.OutlineColor = GOLD
            hl.OutlineTransparency = 0
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Adornee = e.m
            hl.Parent = e.m
            espTags[e.m] = hl
        end
    end
    for m, h in pairs(espTags) do
        if not want[m] then
            if h and h.Parent then
                h:Destroy()
            end
            espTags[m] = nil
        end
    end
end

local flyVel, flyGyro
local function stopFly()
    if flyVel then
        flyVel:Destroy()
        flyVel = nil
    end
    if flyGyro then
        flyGyro:Destroy()
        flyGyro = nil
    end
    local h = hum()
    if h then
        h.PlatformStand = false
    end
end

local function startFly()
    local r = root()
    if not r then
        return
    end
    stopFly()
    flyVel = Instance.new("BodyVelocity")
    flyVel.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    flyVel.Velocity = Vector3.zero
    flyVel.Parent = r
    flyGyro = Instance.new("BodyGyro")
    flyGyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    flyGyro.P = 9000
    flyGyro.CFrame = workspace.CurrentCamera.CFrame
    flyGyro.Parent = r
end

local safeCF = nil
local function voidLine()
    local fp = workspace:FindFirstChild("FallPart")
    if fp and fp:IsA("BasePart") then
        return fp.Position.Y + 12
    end
    return -180
end

-- panel
local gui = Instance.new("ScreenGui")
gui.Name = "NEWGOD_DEAGLE"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9200
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local host = nil
pcall(function()
    host = gethui()
end)
gui.Parent = host or game:GetService("CoreGui")

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(330, 430)
main.Position = UDim2.fromOffset(40, 120)
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
bar.Size = UDim2.new(1, 0, 0, 34)
bar.BackgroundColor3 = BAR
bar.BorderSizePixel = 0
bar.Active = true
bar.Parent = main
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -80, 1, 0)
title.Position = UDim2.fromOffset(12, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextColor3 = GOLD
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "NEWGOD DEAGLE  " .. BUILD
title.Parent = bar

local mini = Instance.new("TextButton")
mini.Size = UDim2.fromOffset(26, 22)
mini.Position = UDim2.new(1, -62, 0, 6)
mini.BackgroundColor3 = GOLD
mini.BorderSizePixel = 0
mini.Font = Enum.Font.GothamBold
mini.TextSize = 15
mini.TextColor3 = Color3.fromRGB(20, 16, 8)
mini.Text = "-"
mini.Parent = bar
Instance.new("UICorner", mini).CornerRadius = UDim.new(0, 6)

local panic = Instance.new("TextButton")
panic.Size = UDim2.fromOffset(26, 22)
panic.Position = UDim2.new(1, -32, 0, 6)
panic.BackgroundColor3 = RED
panic.BorderSizePixel = 0
panic.Font = Enum.Font.GothamBold
panic.TextSize = 13
panic.TextColor3 = Color3.fromRGB(255, 235, 230)
panic.Text = "X"
panic.Parent = bar
Instance.new("UICorner", panic).CornerRadius = UDim.new(0, 6)

local tabRow = Instance.new("ScrollingFrame")
tabRow.Size = UDim2.new(1, -16, 0, 26)
tabRow.Position = UDim2.fromOffset(8, 40)
tabRow.BackgroundTransparency = 1
tabRow.BorderSizePixel = 0
tabRow.ScrollBarThickness = 0
tabRow.ScrollingDirection = Enum.ScrollingDirection.X
tabRow.CanvasSize = UDim2.new(0, 0, 0, 0)
tabRow.AutomaticCanvasSize = Enum.AutomaticSize.X
tabRow.Parent = main
local tabLayout = Instance.new("UIListLayout", tabRow)
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 5)

local body = Instance.new("Frame")
body.Size = UDim2.new(1, -16, 1, -110)
body.Position = UDim2.fromOffset(8, 72)
body.BackgroundTransparency = 1
body.Parent = main

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 30)
status.Position = UDim2.new(0, 8, 1, -34)
status.BackgroundColor3 = BAR
status.BorderSizePixel = 0
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.TextColor3 = DIM
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextWrapped = true
status.Text = " ready"
status.Parent = main
Instance.new("UICorner", status).CornerRadius = UDim.new(0, 6)

local pages = {}
local tabs = {}
local repaint = {}
local function showPage(name)
    for n, p in pairs(pages) do
        p.Visible = (n == name)
        tabs[n].BackgroundColor3 = (n == name) and GOLD or OFFC
        tabs[n].TextColor3 = (n == name) and Color3.fromRGB(20, 16, 8) or DIM
    end
end

local function makeTab(name)
    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = GOLD
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false
    page.Parent = body
    local lay = Instance.new("UIListLayout", page)
    lay.Padding = UDim.new(0, 4)
    pages[name] = page

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(52, 26)
    btn.BackgroundColor3 = OFFC
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.TextColor3 = DIM
    btn.Text = name
    btn.Parent = tabRow
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    btn.MouseButton1Click:Connect(function()
        showPage(name)
    end)
    tabs[name] = btn
    return page
end

local function button(page, text, fn)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -6, 0, 26)
    b.BackgroundColor3 = GOLD
    b.BorderSizePixel = 0
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.TextColor3 = Color3.fromRGB(20, 16, 8)
    b.Text = text
    b.Parent = page
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    b.MouseButton1Click:Connect(function()
        guard(text, fn)
    end)
    return b
end

local function note(page, text)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -6, 0, 30)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Gotham
    l.TextSize = 10
    l.TextColor3 = DIM
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Top
    l.TextWrapped = true
    l.Text = text
    l.Parent = page
    return l
end

local function toggle(page, text, key, onChange)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -6, 0, 26)
    b.BackgroundColor3 = OFFC
    b.BorderSizePixel = 0
    b.Font = Enum.Font.Gotham
    b.TextSize = 11
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Parent = page
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    local pad = Instance.new("UIPadding", b)
    pad.PaddingLeft = UDim.new(0, 10)
    local function paint()
        b.Text = (F[key] and "[ON]  " or "[  ]  ") .. text
        b.TextColor3 = F[key] and GOLD or DIM
    end
    paint()
    repaint[#repaint + 1] = paint
    b.MouseButton1Click:Connect(function()
        F[key] = not F[key]
        if F[key] then
            F.offlist[key] = nil
        else
            F.offlist[key] = true
        end
        paint()
        saveCfg()
        if onChange then
            guard(text, function()
                onChange(F[key])
            end)
        end
        setStatus(text .. " -> " .. (F[key] and "ON" or "off"))
    end)
    return b, paint
end

local function slider(page, text, key, minv, maxv, onChange)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -6, 0, 40)
    holder.BackgroundColor3 = OFFC
    holder.BorderSizePixel = 0
    holder.Parent = page
    Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 6)

    local lab = Instance.new("TextLabel")
    lab.Size = UDim2.new(1, -12, 0, 16)
    lab.Position = UDim2.fromOffset(10, 3)
    lab.BackgroundTransparency = 1
    lab.Font = Enum.Font.Gotham
    lab.TextSize = 10
    lab.TextColor3 = DIM
    lab.TextXAlignment = Enum.TextXAlignment.Left
    lab.Parent = holder

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -20, 0, 6)
    track.Position = UDim2.fromOffset(10, 24)
    track.BackgroundColor3 = Color3.fromRGB(52, 46, 36)
    track.BorderSizePixel = 0
    track.Active = true
    track.Parent = holder
    Instance.new("UICorner", track).CornerRadius = UDim.new(0, 3)

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = GOLD
    fill.BorderSizePixel = 0
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 3)

    local function paint()
        local v = tonumber(F[key]) or minv
        lab.Text = text .. "   " .. string.format(((maxv <= 10) and "%.2f" or "%.0f"), v) .. "   max " .. tostring(maxv)
        fill.Size = UDim2.new(math.clamp((v - minv) / math.max(maxv - minv, 0.001), 0, 1), 0, 1, 0)
    end
    paint()
    repaint[#repaint + 1] = paint

    local drag = false
    local function setFrom(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
        local v = minv + rel * (maxv - minv)
        if maxv > 10 then
            v = math.floor(v + 0.5)
        else
            v = math.floor(v * 100 + 0.5) / 100
        end
        F[key] = v
        clampCfg()
        paint()
        if onChange then
            guard(text, onChange)
        end
    end
    track.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag = true
            setFrom(i.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            setFrom(i.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
            drag = false
            saveCfg()
        end
    end)
    return paint
end

local function textbox(page, label, key, onSet)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -6, 0, 40)
    holder.BackgroundColor3 = OFFC
    holder.BorderSizePixel = 0
    holder.Parent = page
    Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 6)

    local lab = Instance.new("TextLabel")
    lab.Size = UDim2.new(1, -12, 0, 14)
    lab.Position = UDim2.fromOffset(10, 3)
    lab.BackgroundTransparency = 1
    lab.Font = Enum.Font.Gotham
    lab.TextSize = 10
    lab.TextColor3 = DIM
    lab.TextXAlignment = Enum.TextXAlignment.Left
    lab.Text = label
    lab.Parent = holder

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -20, 0, 18)
    box.Position = UDim2.fromOffset(10, 18)
    box.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
    box.BorderSizePixel = 0
    box.Font = Enum.Font.Gotham
    box.TextSize = 11
    box.TextColor3 = GOLD
    box.ClearTextOnFocus = false
    box.Text = tostring(F[key])
    box.Parent = holder
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
    box.FocusLost:Connect(function()
        F[key] = box.Text
        clampCfg()
        box.Text = tostring(F[key])
        saveCfg()
        if onSet then
            guard(label, onSet)
        end
        setStatus(label .. " -> " .. tostring(F[key]))
    end)
    return box
end

local pFarm = makeTab("FARM")
local pAdv = makeTab("ADV")
local pAuto = makeTab("AUTO")
local pSet = makeTab("SET")
local pRisk = makeTab("RISK")
local pInfo = makeTab("INFO")

toggle(pFarm, "AUTO FARM", "autofarm")
toggle(pFarm, "AUTO COIN", "autocoin")
toggle(pFarm, "FAST COIN", "fastcoin")
toggle(pFarm, "AUTO HIDE - biggest hide spot", "autohide")
toggle(pFarm, "AUTO DEPLOY", "autodeploy")
toggle(pFarm, "AUTO RESPAWN", "autorespawn")
toggle(pFarm, "TARGET BOTS", "targetBots")
toggle(pFarm, "TARGET PLAYERS", "targetPlayers")
toggle(pFarm, "BOTS FIRST", "botsfirst")
toggle(pFarm, "ELO GUARD", "eloguard")
local ALL_KEYS = {
    "autofarm", "autocoin", "autodeploy", "autorespawn", "targetBots", "targetPlayers",
    "botsfirst", "eloguard", "silent", "esp", "infjump", "antivoid", "autoclaim",
    "autospin", "autocase", "autocode", "autoskin", "autovote", "nopopup", "hidevape",
    "vapesync", "spoofname", "scrubname", "autohide", "fastcoin", "revenge", "hunt",
}

local allBtn
allBtn = button(pFarm, "TURN ALL ON", function()
    local allOn = true
    for _, k in ipairs(ALL_KEYS) do
        if not F[k] then
            allOn = false
            break
        end
    end
    for _, k in ipairs(ALL_KEYS) do
        F[k] = not allOn
        if allOn then
            F.offlist[k] = true
        else
            F.offlist[k] = nil
        end
    end
    if allOn then
        F.safemode = false
        F.phase = false
        F.fly = false
        F.noclip = false
        F.offlist.safemode = true
        F.offlist.phase = true
        stopFly()
        clearEsp()
        killPad()
        clearPhase()
        restoreCollide()
    end
    allBtn.Text = allOn and "TURN ALL ON" or "TURN ALL OFF"
    saveCfg()
    for _, fn in ipairs(repaint) do
        pcall(fn)
    end
    setStatus(allOn and "everything off, body released" or "everything on")
end)
button(pFarm, "DEPLOY NOW", function()
    setStatus(ensureDeployed() and "deployed" or "round not ready")
end)
button(pFarm, "RETURN TO LOBBY", function()
    local ok = false
    pcall(function()
        ok = RoundController.ReturnToLobby(nil, true) and true or false
    end)
    if not ok then
        pcall(function()
            ok = RoundController.ReturnToLobby(nil, false) and true or false
        end)
    end
    setStatus(ok and "back to lobby" or "lobby refused - round controller said no")
end)

toggle(pAdv, "SILENT AIM", "silent")
toggle(pAdv, "X-RAY ESP", "esp", function(on)
    if not on then
        clearEsp()
    end
end)
toggle(pAdv, "FLY", "fly", function(on)
    if on then
        startFly()
    else
        stopFly()
    end
end)
toggle(pAdv, "NOCLIP", "noclip")
toggle(pAdv, "INF JUMP", "infjump")
toggle(pAdv, "ANTI VOID", "antivoid")
slider(pAdv, "WALK SPEED", "speed", 16, LIM.speed, function()
    local h = hum()
    if h then
        h.WalkSpeed = F.speed
    end
end)
slider(pAdv, "FLY SPEED", "flyspeed", 20, LIM.flyspeed)
button(pAdv, "TP TO NEAREST", function()
    local e = pickTarget()
    local r = root()
    if e and r then
        local hb = hitboxOf(e.m)
        r.CFrame = CFrame.new(hb.Position + Vector3.new(0, 6, 0), hb.Position)
        setStatus("tp -> " .. e.m.Name)
    else
        setStatus("no target")
    end
end)
button(pAdv, "TP UP 300", function()
    local r = root()
    if r then
        r.AssemblyLinearVelocity = Vector3.zero
        r.CFrame = r.CFrame + Vector3.new(0, 300, 0)
        resetSafeSpot()
        setStatus("moved up 300")
    end
end)

local AUTO_KEYS = {
    "autoclaim", "autospin", "autocase", "autocode", "autoskin", "autovote", "nopopup",
}

local autoBtn
autoBtn = button(pAuto, "ALL AUTO ON", function()
    local allOn = true
    for _, k in ipairs(AUTO_KEYS) do
        if not F[k] then
            allOn = false
            break
        end
    end
    for _, k in ipairs(AUTO_KEYS) do
        F[k] = not allOn
        if allOn then
            F.offlist[k] = true
        else
            F.offlist[k] = nil
        end
    end
    autoBtn.Text = allOn and "ALL AUTO ON" or "ALL AUTO OFF"
    saveCfg()
    for _, fn in ipairs(repaint) do
        pcall(fn)
    end
    setStatus(allOn and "every auto on this page is off" or "every auto on this page is on")
end)

toggle(pAuto, "AUTO KILL ALL POP UP", "nopopup")
button(pAuto, "UNSTICK SCREEN - blur and clicks", function()
    clearScreenEffects()
    local mg = LP.PlayerGui:FindFirstChild("MainGui")
    if mg then
        killClickCatchers(mg)
    end
    setStatus("blur cleared, full screen click catchers removed")
end)
button(pAuto, "KILL POP UPS NOW", function()
    hookPopups()
    killPopups()
    setStatus("hidden: join event, one time offer, round stats, map voting and 24 more")
end)
toggle(pAuto, "AUTO CLAIM ALL", "autoclaim")
toggle(pAuto, "AUTO FREE SPIN", "autospin")
toggle(pAuto, "AUTO OPEN CASES", "autocase")
toggle(pAuto, "AUTO REDEEM CODES", "autocode")
toggle(pAuto, "AUTO BUY FAST SKIN", "autoskin")
toggle(pAuto, "AUTO VOTE / FAVORITE", "autovote")

local CLAIMS = {
    "ClaimDailyChest", "ClaimGroupChest", "ClaimDailyReward",
    "ClaimTimeReward", "ClaimGreekDailyPoints",
}

local function claimsWork()
    return game.PlaceId ~= GREEK_PLACE
end

local function claimPass()
    if not claimsWork() then
        setStatus("claims held - this place ignores them, will fire when you are back")
        return
    end
    for _, v in ipairs(CLAIMS) do
        rawFire(Network, v, nil)
        task.wait(0.25)
    end
    rawFire(Network, "RequestGreekRewardState")
    task.wait(0.2)
    stats.achClaimed = stats.achClaimed or 0
    local items = ClientData.Achievements and ClientData.Achievements.Items or {}
    for id, v in pairs(items) do
        if type(v) == "table" then
            local ready = tonumber(v.ReadyCount) or 0
            local gap = (tonumber(v.EarnedTier) or 0) - (tonumber(v.ClaimedTier) or 0)
            local n = math.max(ready, gap)
            for _ = 1, math.min(n, 10) do
                rawFire(Network, "ClaimAchievement", id)
                stats.achClaimed = stats.achClaimed + 1
                task.wait(0.2)
            end
        end
    end
    local tasks = ClientData.DailyTasks and ClientData.DailyTasks.Tasks or {}
    for _, t in pairs(tasks) do
        if t.Claimed == false and (t.Progress or 0) >= (t.Goal or 1e9) then
            rawFire(Network, "ClaimDailyTask", t.Difficulty)
            task.wait(0.2)
        end
    end
    stats.claims = stats.claims + 1
end

local spinState = {Spins = 0, NextFreeSpinTime = 0, FreeSpinPlaytime = 0, at = 0}

pcall(function()
    Network.OnClientEvent("SpinWheelState", function(p1)
        if type(p1) == "table" then
            spinState.Spins = tonumber(p1.Spins) or 0
            spinState.NextFreeSpinTime = tonumber(p1.NextFreeSpinTime) or 0
            spinState.FreeSpinPlaytime = tonumber(p1.FreeSpinPlaytime) or 0
            spinState.at = os.time()
        end
    end)
end)
pcall(function()
    Network.OnClientEvent("SpinWheelError", function(p1)
        stats.spinRefused = (stats.spinRefused or 0) + 1
        setStatus("spin refused: " .. tostring(p1))
    end)
end)

local function spinNow(force)
    rawFire(Network, "RequestSpinWheelState")
    task.wait(0.6)
    local owed = spinState.Spins > 0
    local due = spinState.NextFreeSpinTime > 0 and os.time() >= spinState.NextFreeSpinTime
    if not force and not owed and not due then
        return false
    end
    rawFire(Network, "RequestSpinWheelSpin")
    task.wait(4.4)
    rawFire(Network, "SpinWheelAnimationFinished")
    stats.spins = stats.spins + 1
    task.wait(0.5)
    rawFire(Network, "RequestSpinWheelState")
    return true
end

local function openCases()
    local n = 0
    for name, count in pairs(ClientData.Inventory and ClientData.Inventory.OwnedCases or {}) do
        for _ = 1, math.min(tonumber(count) or 0, LIM.caseEvery) do
            pcall(function()
                Network:InvokeServer("OpenCase", name)
            end)
            n = n + 1
            task.wait(0.35)
        end
    end
    stats.cases = stats.cases + n
    return n
end

local function buyFastSkin()
    local shop = ClientData.DailyShop
    if type(shop) ~= "table" then
        return nil
    end
    local owned = ClientData.Inventory and ClientData.Inventory.OwnedSkins or {}
    local function scan(tbl)
        for k, v in pairs(tbl) do
            local nm = (type(v) == "table" and (v.Name or v.Skin or v.Item)) or (type(v) == "string" and v) or (type(k) == "string" and k)
            if type(nm) == "string" and FAST_SKINS[nm] and not owned[nm] then
                return nm, (type(v) == "table" and (v.Id or v.Index)) or k
            end
        end
        return nil
    end
    local nm, id = scan(shop)
    if not nm and type(shop.Skins) == "table" then
        nm, id = scan(shop.Skins)
    end
    if not nm and type(shop.Items) == "table" then
        nm, id = scan(shop.Items)
    end
    if not nm then
        return nil
    end
    rawFire(Network, "BuyDailySkin", id)
    task.wait(0.6)
    if (ClientData.Inventory.OwnedSkins or {})[nm] then
        rawFire(Network, "EquipSkin", nm)
        notice("bought and equipped " .. nm .. " - reload is now half")
        return nm
    end
    rawFire(Network, "BuyDailySkinGems", id)
    task.wait(0.6)
    if (ClientData.Inventory.OwnedSkins or {})[nm] then
        rawFire(Network, "EquipSkin", nm)
        notice("bought with gems and equipped " .. nm)
        return nm
    end
    return nil
end

local function equipBestOwnedSkin()
    local owned = ClientData.Inventory and ClientData.Inventory.OwnedSkins or {}
    for nm in pairs(FAST_SKINS) do
        if owned[nm] then
            if ClientData.Inventory.EquippedSkin ~= nm then
                rawFire(Network, "EquipSkin", nm)
                notice("equipped " .. nm .. ", half reload")
            end
            return nm
        end
    end
    return nil
end

button(pAuto, "CLAIM ACHIEVEMENTS NOW", function()
    local items = ClientData.Achievements and ClientData.Achievements.Items or {}
    local fired = 0
    for id, v in pairs(items) do
        if type(v) == "table" then
            local ready = tonumber(v.ReadyCount) or 0
            local gap = (tonumber(v.EarnedTier) or 0) - (tonumber(v.ClaimedTier) or 0)
            for _ = 1, math.min(math.max(ready, gap), 10) do
                rawFire(Network, "ClaimAchievement", id)
                fired = fired + 1
                task.wait(0.2)
            end
        end
    end
    stats.achClaimed = stats.achClaimed + fired
    setStatus("achievement claims sent " .. fired)
end)
button(pAuto, "CLAIM EVERYTHING NOW", function()
    claimPass()
    setStatus("claim pass done")
end)
button(pAuto, "FREE SPIN NOW", function()
    setStatus(spinNow(true) and "spin sent" or "no spin to use")
end)
button(pAuto, "OPEN ALL CASES NOW", function()
    setStatus("opened " .. openCases() .. " cases")
end)
button(pAuto, "REDEEM CODES NOW", function()
    for _, c in ipairs({"DISCORD", "GREEKWARRIOR"}) do
        rawFire(Network, "RedeemCode", c)
        task.wait(0.5)
    end
    setStatus("codes sent")
end)
button(pAuto, "COLLECT ALL COINS NOW", function()
    rawFire(Network, "RequestEventCoins")
    task.wait(0.3)
    setStatus("coins collected " .. sweepCoins())
end)
button(pAuto, "BUY FAST SKIN NOW", function()
    local nm = equipBestOwnedSkin() or buyFastSkin()
    setStatus(nm and ("fast skin " .. nm) or "no half reload skin in shop yet")
end)
note(pAuto, "half reload skins: Frozen, Samurai, Evil, Ninja. Every other skin is x1. Bought with cash or gems only, never robux.")

toggle(pSet, "FORCE ALL ON AT LOAD", "forceon")
toggle(pSet, "SAFE MODE - hold a safe spot", "safemode", function(on)
    if on then
        resetSafeSpot()
    end
end)
toggle(pSet, "PHASE - stand inside a wall", "phase", function()
    clearPhase()
    killPad()
    resetSafeSpot()
    setStatus(F.phase and "phase on" or "phase off")
end)
button(pSet, "PHASE NOW - pick a block", function()
    F.phase = true
    F.safemode = true
    F.offlist.safemode = nil
    F.offlist.phase = nil
    clearPhase()
    local cf = enterPhase()
    saveCfg()
    if cf and phasePart then
        local r = root()
        if r then
            r.AssemblyLinearVelocity = Vector3.zero
            r.CFrame = cf
        end
        setStatus("inside " .. phasePart.Name .. " " .. tostring(phasePart.Size) .. " at y " .. math.floor(cf.Position.Y))
    else
        setStatus("no block on this map is thick enough")
    end
end)
slider(pSet, "SKY HEIGHT", "safeheight", 60, LIM.safeheight, resetSafeSpot)
button(pSet, "RESET SAFE SPOT HERE", function()
    resetSafeSpot()
    setStatus("safe spot reset")
end)
toggle(pSet, "DISABLE POP UP WINDOW", "nopopup")
toggle(pSet, "HIDE VAPE / OTHER GUI", "hidevape")
toggle(pSet, "VAPE SYNC - keep my modules", "vapesync")
button(pSet, "SAVE VAPE NOW", function()
    local live, on = vapeSnapshot()
    saveCfg()
    setStatus("vape saved, " .. on .. " on of " .. live)
end)
button(pSet, "RESTORE VAPE NOW", function()
    setStatus("vape restored " .. vapeRestore(true) .. " modules")
end)
button(pSet, "FORGET SAVED VAPE", function()
    vapeWant = {}
    pcall(function()
        writefile(VAPE_PATH, "{}")
    end)
    setStatus("vape memory cleared")
end)
toggle(pSet, "CHANGE USERNAME", "spoofname", applyName)
textbox(pSet, "USERNAME", "username", applyName)
toggle(pSet, "SCRUB NAME OFF SCREEN", "scrubname")
note(pSet, "the name change is on your screen only. the server keeps the real account, so this hides you in screenshots and recordings, it does not hide you from a report.")
button(pSet, "SAVE CONFIG", function()
    saveCfg()
    setStatus("saved to " .. CFG_PATH)
end)
button(pSet, "RESET TO DEFAULT", function()
    for k, v in pairs(DEFAULTS) do
        F[k] = v
    end
    clampCfg()
    saveCfg()
    for _, fn in ipairs(repaint) do
        pcall(fn)
    end
    setStatus("defaults restored")
end)

toggle(pRisk, "REVENGE - killers go first", "revenge")
toggle(pRisk, "HUNT - shoot nothing else", "hunt")
button(pRisk, "CLEAR KILLERS LIST", function()
    killers = {}
    killerOrder = {}
    killersHere = {}
    lastKilledBy = ""
    saveKillers()
    setStatus("killers list cleared")
end)
toggle(pRisk, "NO REPEAT VICTIM", "norepeat")
slider(pRisk, "SAME PLAYER GAP", "victimGap", 0, LIM.victimGap)
slider(pRisk, "KILLS PER MINUTE CAP", "killCap", 0, LIM.killCap)
toggle(pRisk, "ANTI AFK - no teleport", "antiafk")
toggle(pRisk, "WATCH CHAT FOR HACKER", "watchchat")
toggle(pRisk, "ELO BLEED - lose on purpose", "elobleed")
button(pRisk, "LOW PROFILE PRESET", function()
    F.killCap = 40
    F.victimGap = 6
    F.norepeat = true
    F.fly = false
    F.noclip = false
    F.esp = false
    F.safeheight = 220
    stopFly()
    clearEsp()
    clampCfg()
    resetSafeSpot()
    saveCfg()
    for _, fn in ipairs(repaint) do
        pcall(fn)
    end
    setStatus("low profile on - 40 kills a minute, 6s per player")
end)
button(pRisk, "LIMIT MODE - MAX ALL", function()
    for _, k in ipairs(ALWAYS_ON) do
        F[k] = true
    end
    F.speed = LIM.speed
    F.flyspeed = LIM.flyspeed
    F.safeheight = 400
    F.victimGap = 0
    F.killCap = LIM.killCap
    F.norepeat = false
    stats.gap = LIM.gapFloor
    clampCfg()
    resetSafeSpot()
    applyName()
    saveCfg()
    for _, fn in ipairs(repaint) do
        pcall(fn)
    end
    setStatus("LIMIT MODE - every value at its measured ceiling")
end)
note(pRisk, "the server never checks your aim, your distance or your rate. the only thing that can report you is another real player, so these three sliders are the whole ban surface.")

local info = Instance.new("TextLabel")
info.Size = UDim2.new(1, -6, 0, 340)
info.BackgroundTransparency = 1
info.Font = Enum.Font.Gotham
info.TextSize = 12
info.TextColor3 = TXT
info.TextXAlignment = Enum.TextXAlignment.Left
info.TextYAlignment = Enum.TextYAlignment.Top
info.TextWrapped = true
info.Text = ""
info.Parent = pInfo

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

local collapsed = false
mini.MouseButton1Click:Connect(function()
    collapsed = not collapsed
    body.Visible = not collapsed
    tabRow.Visible = not collapsed
    status.Visible = not collapsed
    main.Size = collapsed and UDim2.fromOffset(330, 34) or UDim2.fromOffset(330, 430)
end)

button(pSet, "BACK TO NORMAL", function()
    F.safemode = false
    F.phase = false
    F.basement = false
    F.noclip = false
    F.fly = false
    F.offlist.safemode = true
    F.offlist.phase = true
    stopFly()
    killPad()
    clearPhase()
    unanchorMe()
    resetSafeSpot()
    restoreCollide()
    saveCfg()
    for _, fn in ipairs(repaint) do
        pcall(fn)
    end
    setStatus("body released - collisions back, nothing is holding you")
end)
panic.MouseButton1Click:Connect(function()
    F.autofarm = false
    F.autocoin = false
    F.fly = false
    F.noclip = false
    F.esp = false
    F.silent = false
    F.infjump = false
    F.safemode = false
    F.safemode = false
    F.phase = false
    F.basement = false
    stopFly()
    clearEsp()
    killPad()
    clearPhase()
    unanchorMe()
    restoreCollide()
    setStatus("PANIC - all off, body back to normal")
end)

showPage("FARM")

-- the server answers a landed shot on this event, that is the only honest hit signal
pcall(function()
    Network.OnClientEvent("Kill", function(p1)
        if type(p1) ~= "table" then
            return
        end
        for killer, v in pairs(p1) do
            if type(v) == "table" and v.Killed ~= nil then
                local kname = tostring(killer)
                local victim = tostring(v.Killed)
                if victim == realName or victim == LP.Name then
                    noteKiller(kname)
                    stats.diedTo = (stats.diedTo or 0) + 1
                    setStatus("KILLED BY " .. kname .. " x" .. killers[kname] .. " - he is top of the list now")
                elseif kname == realName or kname == LP.Name then
                    stats.landed = stats.landed + 1
                    if stats.pending > 0 then
                        stats.pending = stats.pending - 1
                    end
                    stats.streak = 0
                    if stats.backoff > 0 then
                        stats.backoff = stats.backoff - 1
                        stats.gap = math.max(HIT_GAP + 0.01, stats.gap - 0.05)
                    end
                end
            end
        end
    end)
end)

-- shooting runs on Heartbeat so the shot lands on the cooldown boundary, not up to
-- one wait() late. that jitter was most of the lost rate
local nextShot = 0
local hbConn
hbConn = RunService.Heartbeat:Connect(function()
    if not mine() then
        hbConn:Disconnect()
        return
    end
    if not F.autofarm then
        return
    end
    local now = os.clock()
    if now < nextShot then
        return
    end
    if not alive() or not inRound() then
        return
    end
    if F.elobleed then
        return
    end
    if eloBlocked() then
        return
    end
    if not killRateOk() then
        return
    end
    local e, _, isRev = pickTarget()
    if not e then
        stats.dry = stats.dry + 1
        return
    end
    if F.hunt and F.revenge and not isRev and #killerOrder > 0 then
        for _, nm in ipairs(killerOrder) do
            local p = Players:FindFirstChild(nm)
            if p and p.Character and usable(p.Character, false) then
                stats.holdFor = (stats.holdFor or 0) + 1
                if os.clock() - (stats.holdStart or 0) > 2.5 then
                    stats.holdStart = os.clock()
                    break
                end
                if not stats.holdStart or stats.holdStart == 0 then
                    stats.holdStart = os.clock()
                end
                stats.dry = stats.dry + 1
                setStatus("hunt: holding for " .. nm)
                return
            end
        end
        stats.holdStart = 0
    end
    if fireAt(e) then
        nextShot = now + stats.gap
        stats.pending = stats.pending + 1
        setStatus((isRev and "REVENGE -> " or "farm -> ") .. e.m.Name .. (e.bot and " (bot)" or " (player)"))
        task.delay(1.4, function()
            if stats.pending > 0 then
                stats.pending = stats.pending - 1
                stats.miss = stats.miss + 1
                stats.streak = stats.streak + 1
                -- five in a row is the server refusing, anything less is a dead target
                if stats.streak >= 5 then
                    stats.streak = 0
                    stats.backoff = 3
                    stats.gap = math.min(LIM.gapCeil, math.min(MISS_GAP, stats.gap + 0.05))
                end
            end
        end)
    end
end)

task.spawn(function()
    while gui.Parent and mine() do
        if (F.autodeploy or F.autorespawn) and not F.elobleed then
            guard("deploy", function()
                if not alive() or not inRound() then
                    ensureDeployed()
                end
            end)
        end
        task.wait(1.5)
    end
end)

task.spawn(function()
    while gui.Parent and mine() do
        guard("shield", function()
            if F.nopopup then
                hookPopups()
                killPopups()
            end
            if F.hidevape then
                hideVape()
            end
            applyName()
            scrubNames()
            sweepMemory()
            if F.vapesync then
                vapeSnapshot()
                vapeRestore(false)
            end
        end)
        task.wait(1)
    end
end)

task.spawn(function()
    while gui.Parent and mine() do
        if F.autocoin then
            guard("autocoin", function()
                rawFire(Network, "RequestEventCoins")
                local f = workspace:FindFirstChild("LocalEventCoins")
                if not f then
                    stats.eventMap = false
                    return
                end
                local live = #f:GetChildren()
                if live == 0 then
                    return
                end
                stats.eventMap = true
                -- event map. clear the whole board, then check again, until it is empty
                local rounds = 0
                while live > 0 and rounds < 6 and mine() and F.autocoin do
                    setStatus("EVENT MAP - " .. live .. " coins left, taking them")
                    stats.coins = stats.coins + sweepCoins()
                    rounds = rounds + 1
                    rawFire(Network, "RequestEventCoins")
                    task.wait(0.25)
                    f = workspace:FindFirstChild("LocalEventCoins")
                    live = f and #f:GetChildren() or 0
                end
                if live == 0 then
                    setStatus("event map cleared, " .. stats.coins .. " coins total")
                end
            end)
            task.wait(F.fastcoin and 0.5 or 4)
        else
            task.wait(2)
        end
    end
end)

task.spawn(function()
    while gui.Parent and mine() do
        if F.esp then
            guard("esp", updateEsp)
        end
        task.wait(1)
    end
end)

task.spawn(function()
    while gui.Parent and mine() do
        if F.autoclaim then
            if claimsWork() then
                guard("autoclaim", claimPass)
                task.wait(LIM.claimEvery)
            else
                task.wait(5)
            end
        else
            task.wait(5)
        end
    end
end)

task.spawn(function()
    while gui.Parent and mine() do
        if F.autospin then
            guard("autospin", function()
                spinNow(false)
            end)
            local wait = 30
            if spinState.NextFreeSpinTime > 0 then
                wait = math.clamp(spinState.NextFreeSpinTime - os.time() + 3, 15, SPIN_COOLDOWN)
            end
            task.wait(wait)
        else
            task.wait(10)
        end
    end
end)

task.spawn(function()
    while gui.Parent and mine() do
        if F.autocase then
            guard("autocase", function()
                local n = openCases()
                if n > 0 then
                    setStatus("opened " .. n .. " cases")
                end
            end)
            task.wait(25)
        else
            task.wait(10)
        end
    end
end)

task.spawn(function()
    while gui.Parent and mine() do
        if F.autocode then
            guard("autocode", function()
                for _, c in ipairs({"DISCORD", "GREEKWARRIOR"}) do
                    rawFire(Network, "RedeemCode", c)
                    task.wait(0.5)
                end
            end)
            task.wait(LIM.codeEvery * 2)
        else
            task.wait(15)
        end
    end
end)

task.spawn(function()
    while gui.Parent and mine() do
        if F.autoskin then
            guard("autoskin", function()
                if not equipBestOwnedSkin() then
                    buyFastSkin()
                end
            end)
        end
        if F.autovote then
            guard("autovote", function()
                rawFire(Network, "Favorite")
            end)
        end
        task.wait(LIM.shopEvery)
    end
end)

task.spawn(function()
    while gui.Parent and mine() do
        guard("antivoid", function()
            local r = root()
            if not r then
                return
            end
            local vy = voidLine()
            local falling = r.AssemblyLinearVelocity.Y < -110
            if r.Position.Y > vy + 30 and math.abs(r.AssemblyLinearVelocity.Y) < 60 then
                safeCF = r.CFrame
            elseif F.antivoid and (r.Position.Y < vy or (falling and r.Position.Y < vy + 90)) then
                r.AssemblyLinearVelocity = Vector3.zero
                if safeCF then
                    r.CFrame = safeCF
                    setStatus("anti void: pulled back")
                else
                    ensureDeployed()
                    setStatus("anti void: redeployed")
                end
            end
        end)
        task.wait(0.1)
    end
end)

-- elo bleed. below 1250 the server starts giving bots again, and bots cannot report
task.spawn(function()
    while gui.Parent and mine() do
        if F.elobleed then
            guard("elobleed", function()
                local e = elo()
                if e and e < ELO_NO_BOTS - 30 then
                    F.elobleed = false
                    saveCfg()
                    notice("elo is " .. math.floor(e) .. ", bots are back, bleed off")
                    setStatus("ELO BLEED done at " .. math.floor(e))
                    return
                end
                if alive() and inRound() then
                    local h = hum()
                    if h then
                        h.Health = 0
                    end
                end
                setStatus("ELO BLEED: elo " .. tostring(e and math.floor(e)) .. ", losing on purpose")
            end)
            task.wait(3)
        else
            task.wait(5)
        end
    end
end)

task.spawn(function()
    while gui.Parent and mine() do
        if F.autohide then
            guard("autohide", function()
                if coinsMoving() then
                    return
                end
                if not F.safemode or not F.phase then
                    F.safemode = true
                    F.phase = true
                    F.basement = false
                end
                if not phaseCF or not phasePart or not phasePart.Parent then
                    local cf = enterPhase()
                    if cf and phasePart then
                        setStatus("hiding inside " .. phasePart.Name .. " " .. tostring(phasePart.Size))
                    end
                end
            end)
        end
        task.wait(2)
    end
end)

local afkKicksDodged = 0
pcall(function()
    local VirtualUser = game:GetService("VirtualUser")
    LP.Idled:Connect(function()
        if not mine() or not F.antiafk then
            return
        end
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
        afkKicksDodged = afkKicksDodged + 1
        setStatus("anti afk: idle kick dodged x" .. afkKicksDodged .. " (nothing moved)")
    end)
end)

-- someone typing hacker or report in chat is the only real warning this game gives
local chatHits = 0
if TextChatService then
    pcall(function()
        TextChatService.MessageReceived:Connect(function(msg)
            if not F.watchchat or not mine() then
                return
            end
            local t = string.lower(tostring(msg.Text or ""))
            for _, w in ipairs({"hack", "cheat", "report", "aimbot", "exploit"}) do
                if string.find(t, w, 1, true) then
                    chatHits = chatHits + 1
                    notice("chat said '" .. w .. "' x" .. chatHits .. " - RISK tab has the throttles")
                    setStatus("WARNING chat mentioned " .. w)
                    return
                end
            end
        end)
    end)
end

local underBlocks = 0
local function neverBelowMap()
    local r = root()
    if not r then
        return
    end
    local floor = readFloor()
    if not floor then
        return
    end
    if r.Position.Y >= floor - 8 then
        return
    end
    -- encased in rock is allowed and is the whole point. open air down there is not.
    if insideSolid(r.Position, nil) then
        return
    end
    underBlocks = underBlocks + 1
    F.basement = false
    local lift = floor + 6
    r.AssemblyLinearVelocity = Vector3.zero
    r.CFrame = CFrame.new(Vector3.new(r.Position.X, lift, r.Position.Z))
    setStatus("UNDER THE FLOOR at y " .. math.floor(r.Position.Y) .. ", floor is " .. math.floor(floor) .. " - pulled up (x" .. underBlocks .. ")")
end

local DBG = {branch = "none", phaseSet = false, part = "none", cfY = -9999, n = 0}
pcall(function()
    getgenv().NEWGOD_DBG = DBG
end)

local renderConn
renderConn = RunService.RenderStepped:Connect(function()
    if not mine() then
        renderConn:Disconnect()
        return
    end
    neverBelowMap()
    if F.noclip then
        local c = LP.Character
        if c then
            for _, d in ipairs(c:GetDescendants()) do
                if d:IsA("BasePart") and d.CanCollide then
                    d.CanCollide = false
                end
            end
        end
    end
    DBG.n = DBG.n + 1
    DBG.phaseSet = phaseCF ~= nil
    DBG.part = phasePart and (phasePart.Name .. " " .. tostring(phasePart.Size)) or "none"
    DBG.cfY = phaseCF and phaseCF.Position.Y or -9999
    DBG.gate = tostring(F.safemode) .. "/" .. tostring(F.phase) .. "/fly=" .. tostring(F.fly)
        .. "/bleed=" .. tostring(F.elobleed) .. "/coins=" .. tostring(coinsMoving())
    if F.safemode and F.phase and not F.fly and not F.elobleed and not coinsMoving() then
        DBG.branch = "phase"
        killPad()
        local r = root()
        local h = hum()
        if r and h and h.Health > 0 then
            if not phaseCF or not phasePart or not phasePart.Parent then
                local got = enterPhase()
                DBG.lastEnter = got and "ok" or "FAILED to find a block"
            end
            DBG.inPhaseBody = true
            if phaseCF then
                DBG.wrote = true
                noclipMe()
                unanchorMe()
                -- rewrite the ORIGINAL point every frame. anchoring the root was
                -- tried and measured worse: inside fell from 92% to 2%
                r.AssemblyLinearVelocity = Vector3.zero
                r.CFrame = phaseCF
                phaseChecks = phaseChecks + 1
                if phaseChecks % 60 == 0 then
                    if insideSolid(phaseCF.Position, nil) then
                        phaseIn = phaseIn + 1
                    else
                        clearPhase()
                        setStatus("that block did not hold, picking another")
                    end
                end
            end
        end
    elseif F.safemode and not F.fly and not F.elobleed and not coinsMoving() then
        DBG.branch = "sky"
        unanchorMe()
        killPad()
        local r = root()
        local h = hum()
        if r and h and h.Health > 0 then
            local sp = safeSpot()
            if sp then
                r.AssemblyLinearVelocity = Vector3.zero
                r.CFrame = sp
            end
        end
    elseif not F.safemode or F.fly then
        killPad()
        clearPhase()
        unanchorMe()
        if not F.noclip then
            restoreCollide()
        end
    end
    if F.fly then
        local r = root()
        local h = hum()
        if r and h then
            if not flyVel or not flyVel.Parent then
                startFly()
            end
            h.PlatformStand = true
            local cam = workspace.CurrentCamera.CFrame
            local dir = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
            if flyVel then
                flyVel.Velocity = (dir.Magnitude > 0 and dir.Unit or Vector3.zero) * F.flyspeed
            end
            if flyGyro then
                flyGyro.CFrame = cam
            end
        end
    end
end)

UserInputService.JumpRequest:Connect(function()
    if F.infjump and mine() then
        local h = hum()
        if h then
            h:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

LP:GetAttributeChangedSignal("InRound"):Connect(function()
    if not mine() then
        return
    end
    if LP:GetAttribute("InRound") == false then
        local r = root()
        if r and groundY then
            pcall(function()
                r.AssemblyLinearVelocity = Vector3.zero
                r.CFrame = CFrame.new(Vector3.new(r.Position.X, groundY + 5, r.Position.Z))
            end)
        end
        resetSafeSpot()
        setStatus("round over - set down on the floor, not dropped")
    end
end)

LP.CharacterAdded:Connect(function()
    task.wait(0.6)
    if not mine() then
        return
    end
    resetSafeSpot()
    local h = hum()
    if h then
        pcall(function()
            h.WalkSpeed = F.speed
        end)
    end
    applyName()
end)

task.spawn(function()
    while gui.Parent and mine() do
        guard("hud", function()
            local d = ClientData.Data or {}
            if not stats.startElo and tonumber(d.Elo) then
                stats.startElo = tonumber(d.Elo)
            end
            local k = tonumber(d.Kills)
            if k then
                if not stats.kills0 then
                    stats.kills0 = k
                end
                stats.killsNow = k - stats.kills0
            end
            local mins = math.max((os.clock() - stats.t0) / 60, 0.01)
            status.Text = " " .. statusText
            local live, on = vapeSnapshot()
            local e = tonumber(d.Elo)
            info.Text = table.concat({
                "cash        " .. tostring(d.Cash),
                "gems        " .. tostring(d.Gems),
                "exp / lvl   " .. tostring(d.Exp) .. " / " .. tostring(d.Level),
                "elo / rank  " .. tostring(d.Elo) .. "  " .. tostring(d.Rank),
                "elo band    " .. botBand(e) .. "   no bots at " .. ELO_NO_BOTS,
                "kills       " .. tostring(d.Kills) .. "   hs " .. tostring(d.Headshots),
                "streak      " .. tostring(d.Streak),
                "greek pts   " .. tostring(d.GreekPoints),
                "",
                "targets now " .. #targetList() .. "   players " .. (#Players:GetPlayers() - 1),
                "shots sent  " .. stats.shots .. "   killed " .. stats.killsNow,
                "kills / min " .. string.format("%.1f", stats.killsNow / mins) .. "   hit " .. string.format("%.0f%%", 100 * stats.killsNow / math.max(stats.shots, 1)),
                "gap now     " .. string.format("%.3f", stats.gap) .. "s   floor " .. LIM.gapFloor,
                "miss run    " .. stats.streak .. "   backoff " .. stats.backoff,
                "no-target   " .. stats.dry .. "   event miss " .. stats.miss .. "   hunt hold " .. stats.holdFor,
                "rate held   " .. stats.blocked .. "   cap " .. F.killCap .. "/min",
                "anti afk    " .. (F.antiafk and ("on, dodged " .. afkKicksDodged) or "off"),
                "died to     " .. stats.diedTo .. (lastKilledBy ~= "" and ("   last " .. lastKilledBy) or ""),
                "event map   " .. (stats.eventMap and "YES - clearing coins" or "no") ,
                "coins sent  " .. stats.coins .. (coinsMoving() and "   ON THE FLOOR NOW" or ""),
                "achievements " .. tostring(ClientData.Achievements and ClientData.Achievements.ReadyCount) .. " ready, claimed " .. stats.achClaimed,
                "claims here  " .. (claimsWork() and "server answers" or "IGNORED in this place"),
                "spins       " .. spinState.Spins .. " banked, next in " .. math.max(0, spinState.NextFreeSpinTime - os.time()) .. "s, playtime " .. math.floor(spinState.FreeSpinPlaytime) .. "/" .. SPIN_COOLDOWN,
                "spin used   " .. stats.spins .. "   refused " .. stats.spinRefused,
                "claims      " .. stats.claims .. "   spins " .. stats.spins .. "   cases " .. stats.cases,
                "",
                "skin        " .. tostring(ClientData.Inventory and ClientData.Inventory.EquippedSkin),
                "vape        " .. on .. " on of " .. live .. ", remembered " .. stats.saved,
                "phase       " .. (phasePart and ("inside " .. phasePart.Name .. " " .. tostring(phasePart.Size) .. " y " .. math.floor(phaseCF.Position.Y)) or "not in a wall"),
                "phase held  " .. phaseIn .. " of " .. math.floor(phaseChecks / 30) .. " checks, anchored " .. tostring(root() and root().Anchored),
                "pad         " .. ((standPad and standPad.Parent) and ("standing on it, y " .. math.floor(standPad.Position.Y)) or "none") .. (holdPos and "   frozen" or ""),
                "safe mode   " .. (F.safemode and (F.phase and "PHASE in a wall" or ("SKY +" .. F.safeheight)) or "off"),
                "build       " .. BUILD,
                "floor       y " .. tostring(floorY and math.floor(floorY)) .. " from " .. floorFrom .. ", blocked " .. underBlocks,
                "name shown  " .. tostring(LP.DisplayName),
                "",
                (function()
                    if #killerOrder == 0 then
                        return "killers     none yet"
                    end
                    local t = {}
                    for i = 1, math.min(#killerOrder, 5) do
                        t[#t + 1] = killerOrder[i] .. " x" .. killers[killerOrder[i]]
                    end
                    return "killers     " .. table.concat(t, ", ")
                end)(),
                (noticeText ~= "" and ("note  " .. noticeText) or ""),
                "last error  " .. (lastErr == "" and "none" or lastErr),
            }, "\n")
        end)
        task.wait(0.5)
    end
end)

pcall(function()
    getgenv().NEWGOD = {
        F = F, stats = stats, LIM = LIM, targets = targetList, fireAt = fireAt,
        setStatus = setStatus, vapeWant = vapeWant,
    }
end)

applyName()
task.spawn(function()
    local t0 = os.clock()
    while mine() and os.clock() - t0 < 10 do
        guard("namefast", scrubNames)
        task.wait(0.15)
    end
end)
hookPopups()
vapeSnapshot()
saveCfg()

local e0 = elo()
if e0 and e0 >= ELO_NO_BOTS then
    notice("elo " .. math.floor(e0) .. " is over " .. ELO_NO_BOTS .. ", server gives 0 bots. RISK tab has ELO BLEED.")
end
setStatus("v2 build " .. BUILD .. " - everything auto on, 6 tabs")
