--[[
    MM2 Own  •  самостоятельный скрипт для Murder Mystery 2
    Вкладки: Farm • Visual • Move • Combat • Misc
    Меню: RightShift (или кнопка "MM2" на экране) — показать/скрыть.
    Никаких внешних загрузок: всё внутри файла.
]]

if _G.__MM2OWN_UNLOAD then pcall(_G.__MM2OWN_UNLOAD) end

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local UIS           = game:GetService("UserInputService")
local TweenService  = game:GetService("TweenService")
local RepStorage    = game:GetService("ReplicatedStorage")
local Lighting      = game:GetService("Lighting")
local LocalPlayer   = Players.LocalPlayer

local conns, cleanups = {}, {}
local alive = true
local function bind(sig, fn) local c = sig:Connect(fn); conns[#conns + 1] = c; return c end
local function onUnload(fn) cleanups[#cleanups + 1] = fn end

local Cfg = {
    -- farm
    coinFarm = false, farmSpeed = 25, farmRadius = 500, farmDelay = 0.15,
    autoGun = false,
    -- visual
    hlESP = false, nameESP = false, gunESP = false,
    skeleton = false, healthBar = false, arrows = false, espDist = 1500,
    -- move
    fly = false, flySpeed = 60, noclip = false,
    speedOn = false, speed = 32, infJump = false,
    wallClimb = false, climbSpeed = 28,
    -- combat
    aim = false, aimMurd = true, aimVis = true, aimGun = true, aimRMB = false,
    aimFov = 150, aimSmooth = 6, aimDist = 300, aimCircle = false,
}

-- ============================================================
--  Helpers
-- ============================================================
local function getHum()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid"), c, c and c:FindFirstChild("HumanoidRootPart")
end

local hasDrawing = false
pcall(function() hasDrawing = (Drawing ~= nil and Drawing.new ~= nil) end)
local function newDraw(class, props)
    if not hasDrawing then return nil end
    local ok, o = pcall(Drawing.new, class)
    if not ok or not o then return nil end
    for k, v in pairs(props or {}) do pcall(function() o[k] = v end) end
    return o
end
local function hideD(o) if o then pcall(function() o.Visible = false end) end end
local function killD(o) if o then pcall(function() o:Remove() end) end end

-- ============================================================
--  Roles (GetPlayerData remote + tool fallback)
-- ============================================================
local RoleData = {}
local function refreshRoles()
    local rem = RepStorage:FindFirstChild("GetPlayerData", true)
    if rem and rem:IsA("RemoteFunction") then
        local ok, res = pcall(function() return rem:InvokeServer() end)
        if ok and type(res) == "table" then RoleData = res end
    end
end
task.spawn(function()
    while alive do
        refreshRoles()
        task.wait(0.6)
    end
end)

local VALID = {Murderer = true, Sheriff = true, Hero = true, Innocent = true}
local function getRole(pl)
    local d = RoleData[pl.Name] or RoleData[tostring(pl.UserId)]
    if type(d) == "table" and VALID[d.Role] then return d.Role end
    local c, bp = pl.Character, pl:FindFirstChild("Backpack")
    local function has(n)
        return (c and c:FindFirstChild(n)) or (bp and bp:FindFirstChild(n))
    end
    if has("Knife") then return "Murderer" end
    if has("Gun") or has("Revolver") then return "Sheriff" end
    return "Innocent"
end
local ROLE_COLOR = {
    Murderer = Color3.fromRGB(255, 60, 60), Sheriff = Color3.fromRGB(70, 140, 255),
    Hero = Color3.fromRGB(255, 210, 60), Innocent = Color3.fromRGB(235, 235, 235),
}

-- ============================================================
--  FARM: coins + gun
-- ============================================================
local coinContainer, lastScan = nil, 0
local function findContainer()
    if coinContainer and coinContainer.Parent then return coinContainer end
    if os.clock() - lastScan < 1 then return nil end
    lastScan = os.clock()
    for _, m in ipairs(workspace:GetChildren()) do
        local c = m:FindFirstChild("CoinContainer")
        if c then coinContainer = c; return c end
    end
    return nil
end

local visited = {}
local function nearestCoin(root)
    local cont = findContainer()
    if not cont then return nil end
    local best, bestD = nil, Cfg.farmRadius
    local now = os.clock()
    for _, coin in ipairs(cont:GetChildren()) do
        if coin:IsA("BasePart") and (visited[coin] or 0) < now then
            local d = (coin.Position - root.Position).Magnitude
            if d < bestD then best, bestD = coin, d end
        end
    end
    return best
end

local function moveTo(root, pos, speed)
    local dist = (root.Position - pos).Magnitude
    local t = math.max(dist / math.max(speed, 1), 0.03)
    local tw = TweenService:Create(root, TweenInfo.new(t, Enum.EasingStyle.Linear), {CFrame = CFrame.new(pos)})
    tw:Play()
    tw.Completed:Wait()
end

task.spawn(function()
    while alive do
        task.wait(0.05)
        if Cfg.coinFarm then
            pcall(function()
                local hum, _, root = getHum()
                if not hum or not root or hum.Health <= 0 then return end
                local coin = nearestCoin(root)
                if coin then
                    visited[coin] = os.clock() + 3 -- не зацикливаться на монете, которую не берёт (полный мешок)
                    moveTo(root, coin.Position, Cfg.farmSpeed)
                    root.AssemblyLinearVelocity = Vector3.zero
                    task.wait(Cfg.farmDelay)
                end
            end)
        end
    end
end)

local gunBusy = false
local function grabGun()
    if gunBusy then return end
    local drop = workspace:FindFirstChild("GunDrop")
    local hum, _, root = getHum()
    if not drop or not hum or not root or hum.Health <= 0 then return end
    gunBusy = true
    pcall(function()
        local home = root.CFrame
        moveTo(root, drop.Position, 120)
        task.wait(0.35)
        root.CFrame = home
    end)
    gunBusy = false
end
task.spawn(function()
    while alive do
        task.wait(0.5)
        if Cfg.autoGun then pcall(grabGun) end
    end
end)

-- ============================================================
--  VISUAL: Highlight + name tags + gun ESP
-- ============================================================
local function clearVisual(pl)
    local c = pl.Character
    if not c then return end
    local h = c:FindFirstChild("OWN_HL"); if h then h:Destroy() end
    local head = c:FindFirstChild("Head")
    local b = head and head:FindFirstChild("OWN_TAG"); if b then b:Destroy() end
end

local function updateVisuals()
    local _, _, myRoot = getHum()
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer then
            local c = pl.Character
            local hum = c and c:FindFirstChildOfClass("Humanoid")
            local head = c and c:FindFirstChild("Head")
            local root = c and c:FindFirstChild("HumanoidRootPart")
            local ok = hum and head and root and hum.Health > 0
            if ok and myRoot and (root.Position - myRoot.Position).Magnitude > Cfg.espDist then ok = false end
            if not ok then
                if c then clearVisual(pl) end
            else
                local role = getRole(pl)
                local color = ROLE_COLOR[role] or ROLE_COLOR.Innocent
                local hl = c:FindFirstChild("OWN_HL")
                if Cfg.hlESP then
                    if not hl then
                        hl = Instance.new("Highlight")
                        hl.Name = "OWN_HL"
                        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        hl.FillTransparency = 0.55
                        hl.Parent = c
                    end
                    hl.FillColor = color
                    hl.OutlineColor = color
                elseif hl then
                    hl:Destroy()
                end

                local tag = head:FindFirstChild("OWN_TAG")
                if Cfg.nameESP then
                    if not tag then
                        tag = Instance.new("BillboardGui")
                        tag.Name = "OWN_TAG"
                        tag.Size = UDim2.new(0, 160, 0, 34)
                        tag.StudsOffset = Vector3.new(0, 2.4, 0)
                        tag.AlwaysOnTop = true
                        local lbl = Instance.new("TextLabel")
                        lbl.Name = "L"
                        lbl.Size = UDim2.new(1, 0, 1, 0)
                        lbl.BackgroundTransparency = 1
                        lbl.Font = Enum.Font.GothamBold
                        lbl.TextSize = 13
                        lbl.TextStrokeTransparency = 0.4
                        lbl.Parent = tag
                        tag.Parent = head
                    end
                    local lbl = tag:FindFirstChild("L")
                    if lbl then
                        local d = myRoot and math.floor((root.Position - myRoot.Position).Magnitude) or 0
                        lbl.Text = pl.DisplayName .. " [" .. tostring(role) .. "]\n" .. d .. " st"
                        lbl.TextColor3 = color
                    end
                elseif tag then
                    tag:Destroy()
                end
            end
        end
    end

    -- gun drop
    local drop = workspace:FindFirstChild("GunDrop")
    local gh = drop and drop:FindFirstChild("OWN_GUNHL")
    if Cfg.gunESP and drop then
        if not gh then
            gh = Instance.new("Highlight")
            gh.Name = "OWN_GUNHL"
            gh.FillColor = Color3.fromRGB(255, 210, 60)
            gh.OutlineColor = Color3.fromRGB(255, 255, 255)
            gh.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            gh.Parent = drop
        end
    elseif gh then
        gh:Destroy()
    end
end

task.spawn(function()
    while alive do
        pcall(updateVisuals)
        task.wait(0.25)
    end
end)
onUnload(function()
    for _, pl in ipairs(Players:GetPlayers()) do pcall(clearVisual, pl) end
    local drop = workspace:FindFirstChild("GunDrop")
    local gh = drop and drop:FindFirstChild("OWN_GUNHL")
    if gh then gh:Destroy() end
end)

-- ---------- Drawing ESP: skeleton / health / arrows ----------
local R15 = {
    {"Head", "UpperTorso"}, {"UpperTorso", "LowerTorso"},
    {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"},
}
local R6 = {
    {"Head", "Torso"}, {"Torso", "Left Arm"}, {"Torso", "Right Arm"},
    {"Torso", "Left Leg"}, {"Torso", "Right Leg"},
}
local pool = {}
local function getPool(pl)
    local p = pool[pl]
    if p then return p end
    p = {
        bones = {},
        bg = newDraw("Line", {Thickness = 4, Color = Color3.new(0, 0, 0), Visible = false}),
        fg = newDraw("Line", {Thickness = 2, Visible = false}),
        arrow = newDraw("Triangle", {Filled = true, Thickness = 1, Visible = false}),
    }
    for i = 1, 14 do p.bones[i] = newDraw("Line", {Thickness = 1.5, Visible = false}) end
    pool[pl] = p
    return p
end
local function hidePool(p)
    for i = 1, 14 do hideD(p.bones[i]) end
    hideD(p.bg); hideD(p.fg); hideD(p.arrow)
end
local function dropPool(pl)
    local p = pool[pl]
    if not p then return end
    for i = 1, 14 do killD(p.bones[i]) end
    killD(p.bg); killD(p.fg); killD(p.arrow)
    pool[pl] = nil
end

local function drawStep()
    if not hasDrawing then return end
    local cam = workspace.CurrentCamera
    if not cam or not (Cfg.skeleton or Cfg.healthBar or Cfg.arrows) then
        for _, p in pairs(pool) do hidePool(p) end
        return
    end
    local _, _, myRoot = getHum()
    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer then
            local p = getPool(pl)
            local c = pl.Character
            local hum = c and c:FindFirstChildOfClass("Humanoid")
            local root = c and c:FindFirstChild("HumanoidRootPart")
            local head = c and c:FindFirstChild("Head")
            local ok = hum and root and head and hum.Health > 0
            if ok and myRoot and (root.Position - myRoot.Position).Magnitude > Cfg.espDist then ok = false end
            if not ok then
                hidePool(p)
            else
                local color = ROLE_COLOR[getRole(pl)] or ROLE_COLOR.Innocent
                local rp = cam:WorldToViewportPoint(root.Position)
                local onScreen = rp.Z > 0 and rp.X >= 0 and rp.X <= vp.X and rp.Y >= 0 and rp.Y <= vp.Y

                if Cfg.skeleton and rp.Z > 0 then
                    local set = c:FindFirstChild("UpperTorso") and R15 or R6
                    for i = 1, 14 do
                        local line, pair = p.bones[i], set[i]
                        if line then
                            local drawn = false
                            if pair then
                                local a, b = c:FindFirstChild(pair[1]), c:FindFirstChild(pair[2])
                                if a and b then
                                    local pa = cam:WorldToViewportPoint(a.Position)
                                    local pb = cam:WorldToViewportPoint(b.Position)
                                    if pa.Z > 0 and pb.Z > 0 then
                                        line.From = Vector2.new(pa.X, pa.Y)
                                        line.To = Vector2.new(pb.X, pb.Y)
                                        line.Color = color
                                        line.Visible = true
                                        drawn = true
                                    end
                                end
                            end
                            if not drawn then line.Visible = false end
                        end
                    end
                else
                    for i = 1, 14 do hideD(p.bones[i]) end
                end

                if Cfg.healthBar and rp.Z > 0 and p.bg and p.fg then
                    local top = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.8, 0))
                    local bot = cam:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
                    local h = math.abs(bot.Y - top.Y)
                    local x = rp.X - h * 0.32 - 5
                    local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                    p.bg.From = Vector2.new(x, bot.Y + 1); p.bg.To = Vector2.new(x, top.Y - 1); p.bg.Visible = true
                    p.fg.From = Vector2.new(x, bot.Y); p.fg.To = Vector2.new(x, bot.Y - h * frac)
                    p.fg.Color = Color3.fromRGB(math.floor(255 * (1 - frac)), math.floor(255 * frac), 40)
                    p.fg.Visible = true
                else
                    hideD(p.bg); hideD(p.fg)
                end

                if Cfg.arrows and not onScreen and p.arrow then
                    local dir = Vector2.new(rp.X - center.X, rp.Y - center.Y)
                    if rp.Z < 0 then dir = -dir end
                    if dir.Magnitude < 1 then dir = Vector2.new(0, 1) end
                    local u = dir.Unit
                    local perp = Vector2.new(-u.Y, u.X)
                    local tip = center + u * 220
                    local base = tip - u * 14
                    p.arrow.PointA = tip
                    p.arrow.PointB = base + perp * 8
                    p.arrow.PointC = base - perp * 8
                    p.arrow.Color = color
                    p.arrow.Visible = true
                else
                    hideD(p.arrow)
                end
            end
        end
    end
end
bind(RunService.RenderStepped, function() pcall(drawStep) end)
bind(Players.PlayerRemoving, dropPool)
onUnload(function() for pl in pairs(pool) do dropPool(pl) end end)

-- ============================================================
--  MOVE: fly / noclip / speed / infinite jump / wall climb
-- ============================================================
local flyBV, flyBG
local function stopFly()
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
    local hum = getHum()
    if hum then pcall(function() hum.PlatformStand = false end) end
end
local function flyStep()
    local hum, _, root = getHum()
    local cam = workspace.CurrentCamera
    if not Cfg.fly or not hum or not root or not cam or hum.Health <= 0 then
        if flyBV then stopFly() end
        return
    end
    if not flyBV then
        flyBV = Instance.new("BodyVelocity")
        flyBV.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        flyBV.Velocity = Vector3.zero
        flyBV.Parent = root
        flyBG = Instance.new("BodyGyro")
        flyBG.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        flyBG.P = 9e4
        flyBG.Parent = root
    end
    hum.PlatformStand = true
    local look = cam.CFrame.LookVector
    local right = cam.CFrame.RightVector
    local flatLook = Vector3.new(look.X, 0, look.Z)
    local flatRight = Vector3.new(right.X, 0, right.Z)
    local md = hum.MoveDirection
    local dir = Vector3.zero
    if md.Magnitude > 0.05 and flatLook.Magnitude > 0.01 and flatRight.Magnitude > 0.01 then
        dir = look * md:Dot(flatLook.Unit) + right * md:Dot(flatRight.Unit)
    end
    if UIS:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
    if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
    flyBV.Velocity = dir.Magnitude > 0 and dir.Unit * Cfg.flySpeed or Vector3.zero
    flyBG.CFrame = cam.CFrame
end
onUnload(stopFly)

local lastClimb = 0
bind(RunService.Heartbeat, function()
    pcall(function()
        flyStep()
        local hum, c, root = getHum()
        if not hum or not root or hum.Health <= 0 then return end
        if Cfg.speedOn then hum.WalkSpeed = Cfg.speed end
        if Cfg.wallClimb and os.clock() - lastClimb > 0.05 then
            lastClimb = os.clock()
            local md = hum.MoveDirection
            if md.Magnitude > 0.05 then
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = {c}
                local hit = workspace:Raycast(root.Position + Vector3.new(0, 1, 0), md.Unit * 2.6, params)
                if hit and hit.Instance and hit.Normal.Y < 0.65 then
                    local v = root.AssemblyLinearVelocity
                    root.AssemblyLinearVelocity = Vector3.new(v.X * 0.35, Cfg.climbSpeed, v.Z * 0.35)
                end
            end
        end
    end)
end)
bind(RunService.Stepped, function()
    if not Cfg.noclip and not Cfg.fly then return end
    local c = LocalPlayer.Character
    if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
    end
end)
bind(UIS.JumpRequest, function()
    if not Cfg.infJump then return end
    local hum = getHum()
    if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end) end
end)

-- ============================================================
--  COMBAT: camera aim assist
-- ============================================================
local fovDraw = newDraw("Circle", {Thickness = 1.5, Transparency = 0.6, Filled = false, NumSides = 64, Visible = false})
onUnload(function() killD(fovDraw) end)

local function holdingGun()
    local c = LocalPlayer.Character
    return c and (c:FindFirstChild("Gun") or c:FindFirstChild("Revolver")) ~= nil
end
local function visibleTo(cam, myChar, tChar, part)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {myChar, tChar}
    local o = cam.CFrame.Position
    return workspace:Raycast(o, part.Position - o, params) == nil
end
local function pickTarget(cam)
    local _, myChar, myRoot = getHum()
    if not myRoot then return nil end
    local vp = cam.ViewportSize
    local center = Vector2.new(vp.X / 2, vp.Y / 2)
    local best, bestD = nil, math.huge
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer then
            local c = pl.Character
            local hum = c and c:FindFirstChildOfClass("Humanoid")
            local head = c and c:FindFirstChild("Head")
            if hum and head and hum.Health > 0 and ((not Cfg.aimMurd) or getRole(pl) == "Murderer") then
                if (head.Position - myRoot.Position).Magnitude <= Cfg.aimDist then
                    local sp = cam:WorldToViewportPoint(head.Position)
                    if sp.Z > 0 then
                        local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                        if d <= Cfg.aimFov and d < bestD and ((not Cfg.aimVis) or visibleTo(cam, myChar, c, head)) then
                            best, bestD = head, d
                        end
                    end
                end
            end
        end
    end
    return best
end
bind(RunService.RenderStepped, function()
    pcall(function()
        local cam = workspace.CurrentCamera
        if not cam then return end
        if fovDraw then
            if Cfg.aim and Cfg.aimCircle then
                fovDraw.Position = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
                fovDraw.Radius = Cfg.aimFov
                fovDraw.Color = Color3.new(1, 1, 1)
                fovDraw.Visible = true
            else
                fovDraw.Visible = false
            end
        end
        if not Cfg.aim then return end
        if Cfg.aimGun and not holdingGun() then return end
        if Cfg.aimRMB and not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end
        local head = pickTarget(cam)
        if head then
            local goal = CFrame.new(cam.CFrame.Position, head.Position)
            cam.CFrame = cam.CFrame:Lerp(goal, 1 / math.max(Cfg.aimSmooth, 1))
        end
    end)
end)

-- ============================================================
--  MISC
-- ============================================================
local origLight
local function nightMode(on)
    if on then
        origLight = origLight or {
            Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient,
            ExposureCompensation = Lighting.ExposureCompensation, ClockTime = Lighting.ClockTime,
        }
        Lighting.Brightness = 0
        Lighting.Ambient = Color3.new(0, 0, 0)
        Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
        Lighting.ExposureCompensation = -1
        Lighting.ClockTime = 0
    elseif origLight then
        for k, v in pairs(origLight) do pcall(function() Lighting[k] = v end) end
    end
end
local function fullbright()
    Lighting.Brightness = 2
    Lighting.Ambient = Color3.fromRGB(190, 190, 190)
    Lighting.OutdoorAmbient = Color3.fromRGB(190, 190, 190)
    Lighting.ClockTime = 14
end

-- ============================================================
--  UI (свой, без внешних библиотек)
-- ============================================================
local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local guiParent
pcall(function() guiParent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not guiParent then guiParent = LocalPlayer:WaitForChild("PlayerGui") end

local BG, CARD, ACC, TXT, DIM = Color3.fromRGB(18, 18, 26), Color3.fromRGB(30, 30, 42), Color3.fromRGB(153, 103, 255), Color3.fromRGB(235, 235, 245), Color3.fromRGB(150, 150, 170)

local gui = mk("ScreenGui", {Name = "MM2Own", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, guiParent)
onUnload(function() gui:Destroy() end)

local main = mk("Frame", {Size = UDim2.new(0, 330, 0, 410), Position = UDim2.new(0, 40, 0.5, -205), BackgroundColor3 = BG, BorderSizePixel = 0, Active = true}, gui)
mk("UICorner", {CornerRadius = UDim.new(0, 12)}, main)
mk("UIStroke", {Color = ACC, Thickness = 1.2, Transparency = 0.4}, main)

local title = mk("TextLabel", {Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, Text = "  MM2 Own", TextXAlignment = Enum.TextXAlignment.Left,
    Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = TXT, Active = true}, main)
mk("TextLabel", {Size = UDim2.new(1, -12, 1, 0), BackgroundTransparency = 1, Text = "RightShift = hide", TextXAlignment = Enum.TextXAlignment.Right,
    Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = DIM}, title)

-- drag
do
    local dragging, startPos, startInput
    bind(title.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, startInput, startPos = true, i.Position, main.Position
        end
    end)
    bind(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startInput
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    bind(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local tabBar = mk("Frame", {Size = UDim2.new(1, -16, 0, 28), Position = UDim2.new(0, 8, 0, 38), BackgroundTransparency = 1}, main)
mk("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4)}, tabBar)
local pages, tabBtns = {}, {}

local function showTab(name)
    for n, pg in pairs(pages) do pg.Visible = (n == name) end
    for n, b in pairs(tabBtns) do b.BackgroundColor3 = (n == name) and ACC or CARD end
end

local function addTab(name)
    local b = mk("TextButton", {Size = UDim2.new(0, 56, 1, 0), BackgroundColor3 = CARD, Text = name, Font = Enum.Font.GothamBold,
        TextSize = 12, TextColor3 = TXT, AutoButtonColor = false}, tabBar)
    mk("UICorner", {CornerRadius = UDim.new(0, 7)}, b)
    local pg = mk("ScrollingFrame", {Size = UDim2.new(1, -16, 1, -78), Position = UDim2.new(0, 8, 0, 72), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false}, main)
    mk("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, pg)
    pages[name], tabBtns[name] = pg, b
    bind(b.MouseButton1Click, function() showTab(name) end)
    return pg
end

local function addToggle(pg, text, key, cb)
    local row = mk("TextButton", {Size = UDim2.new(1, -4, 0, 30), BackgroundColor3 = CARD, Text = "", AutoButtonColor = false}, pg)
    mk("UICorner", {CornerRadius = UDim.new(0, 8)}, row)
    mk("TextLabel", {Size = UDim2.new(1, -60, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 1, Text = text,
        TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = TXT}, row)
    local pill = mk("Frame", {Size = UDim2.new(0, 36, 0, 18), Position = UDim2.new(1, -46, 0.5, -9), BackgroundColor3 = Cfg[key] and ACC or Color3.fromRGB(60, 60, 78)}, row)
    mk("UICorner", {CornerRadius = UDim.new(1, 0)}, pill)
    local dot = mk("Frame", {Size = UDim2.new(0, 14, 0, 14), Position = Cfg[key] and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7), BackgroundColor3 = Color3.new(1, 1, 1)}, pill)
    mk("UICorner", {CornerRadius = UDim.new(1, 0)}, dot)
    bind(row.MouseButton1Click, function()
        Cfg[key] = not Cfg[key]
        pill.BackgroundColor3 = Cfg[key] and ACC or Color3.fromRGB(60, 60, 78)
        dot.Position = Cfg[key] and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
        if cb then pcall(cb, Cfg[key]) end
    end)
end

local function addSlider(pg, text, key, min, max, step)
    local row = mk("Frame", {Size = UDim2.new(1, -4, 0, 44), BackgroundColor3 = CARD}, pg)
    mk("UICorner", {CornerRadius = UDim.new(0, 8)}, row)
    local lbl = mk("TextLabel", {Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 0, 3), BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = TXT, Text = ""}, row)
    local bar = mk("Frame", {Size = UDim2.new(1, -20, 0, 6), Position = UDim2.new(0, 10, 0, 29), BackgroundColor3 = Color3.fromRGB(55, 55, 72), Active = true}, row)
    mk("UICorner", {CornerRadius = UDim.new(1, 0)}, bar)
    local fill = mk("Frame", {Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = ACC}, bar)
    mk("UICorner", {CornerRadius = UDim.new(1, 0)}, fill)
    local function render()
        local a = (Cfg[key] - min) / (max - min)
        fill.Size = UDim2.new(math.clamp(a, 0, 1), 0, 1, 0)
        lbl.Text = text .. ": " .. tostring(Cfg[key])
    end
    render()
    local dragging = false
    local function setFromX(x)
        local a = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local v = min + (max - min) * a
        v = math.floor(v / step + 0.5) * step
        Cfg[key] = math.clamp(tonumber(string.format("%.3f", v)), min, max)
        render()
    end
    bind(bar.InputBegan, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; setFromX(i.Position.X)
        end
    end)
    bind(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then setFromX(i.Position.X) end
    end)
    bind(UIS.InputEnded, function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end

local function addButton(pg, text, cb)
    local b = mk("TextButton", {Size = UDim2.new(1, -4, 0, 30), BackgroundColor3 = CARD, Text = text, Font = Enum.Font.GothamBold,
        TextSize = 13, TextColor3 = TXT, AutoButtonColor = true}, pg)
    mk("UICorner", {CornerRadius = UDim.new(0, 8)}, b)
    bind(b.MouseButton1Click, function() pcall(cb) end)
end

local function addNote(pg, text)
    mk("TextLabel", {Size = UDim2.new(1, -4, 0, 28), BackgroundTransparency = 1, Text = text, TextWrapped = true,
        Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left}, pg)
end

-- Farm
local pFarm = addTab("Farm")
addToggle(pFarm, "Coin Farm", "coinFarm")
addSlider(pFarm, "Farm Speed", "farmSpeed", 10, 120, 1)
addSlider(pFarm, "Search Radius", "farmRadius", 50, 1000, 10)
addSlider(pFarm, "Delay (s)", "farmDelay", 0, 1, 0.05)
addToggle(pFarm, "Auto Grab Gun", "autoGun")
addButton(pFarm, "Grab Gun Now", function() task.spawn(grabGun) end)

-- Visual
local pVis = addTab("Visual")
if not hasDrawing then addNote(pVis, "Drawing API недоступен: скелет, здоровье и стрелки не будут отображаться.") end
addToggle(pVis, "Highlight ESP (roles)", "hlESP")
addToggle(pVis, "Name + Role + Distance", "nameESP")
addToggle(pVis, "Gun Drop ESP", "gunESP")
addToggle(pVis, "Skeleton", "skeleton")
addToggle(pVis, "Health Bar", "healthBar")
addToggle(pVis, "Off-screen Arrows", "arrows")
addSlider(pVis, "ESP Max Distance", "espDist", 100, 3000, 50)

-- Move
local pMove = addTab("Move")
addToggle(pMove, "Fly", "fly", function(v) if not v then stopFly() end end)
addSlider(pMove, "Fly Speed", "flySpeed", 10, 300, 5)
addToggle(pMove, "Noclip", "noclip")
addToggle(pMove, "Speed", "speedOn", function(v)
    if not v then local h = getHum(); if h then h.WalkSpeed = 16 end end
end)
addSlider(pMove, "WalkSpeed", "speed", 16, 150, 1)
addToggle(pMove, "Infinite Jump", "infJump")
addToggle(pMove, "Wall Climb", "wallClimb")
addSlider(pMove, "Climb Speed", "climbSpeed", 8, 60, 1)

-- Combat
local pCmb = addTab("Combat")
addToggle(pCmb, "Aim Assist", "aim")
addToggle(pCmb, "Murderer Only", "aimMurd")
addToggle(pCmb, "Visible Only", "aimVis")
addToggle(pCmb, "Require Gun", "aimGun")
addToggle(pCmb, "Hold Right Mouse", "aimRMB")
addToggle(pCmb, "Show FOV Circle", "aimCircle")
addSlider(pCmb, "FOV", "aimFov", 30, 500, 5)
addSlider(pCmb, "Smoothness", "aimSmooth", 1, 30, 1)
addSlider(pCmb, "Max Distance", "aimDist", 50, 1000, 10)

-- Misc
local pMisc = addTab("Misc")
addButton(pMisc, "Night Mode", function() nightMode(true) end)
addButton(pMisc, "Fullbright", fullbright)
addButton(pMisc, "Restore Lighting", function() nightMode(false) end)
addButton(pMisc, "Copy Job ID", function() if setclipboard then setclipboard(game.JobId) end end)
addButton(pMisc, "Rejoin Server", function()
    game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
end)
addButton(pMisc, "Unload Script", function() if _G.__MM2OWN_UNLOAD then _G.__MM2OWN_UNLOAD() end end)

showTab("Farm")

-- show/hide: RightShift + on-screen button (для телефона)
local function toggleMenu() main.Visible = not main.Visible end
bind(UIS.InputBegan, function(i, gp)
    if not gp and i.KeyCode == Enum.KeyCode.RightShift then toggleMenu() end
end)
local fab = mk("TextButton", {Size = UDim2.new(0, 44, 0, 44), Position = UDim2.new(0, 8, 0, 70), BackgroundColor3 = ACC, Text = "MM2",
    Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.new(1, 1, 1)}, gui)
mk("UICorner", {CornerRadius = UDim.new(1, 0)}, fab)
bind(fab.MouseButton1Click, toggleMenu)

-- ============================================================
--  Unload
-- ============================================================
_G.__MM2OWN_UNLOAD = function()
    alive = false
    for k, v in pairs(Cfg) do if type(v) == "boolean" then Cfg[k] = false end end
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _, f in ipairs(cleanups) do pcall(f) end
    local h = getHum()
    if h then pcall(function() h.WalkSpeed = 16 end) end
    _G.__MM2OWN_UNLOAD = nil
end
