local Settings = {
    CamLock = {
        Enabled = false,
        ToggleKey = Enum.KeyCode.C,
        BodyPart = "Head",
        UnlockOnKO = false,
        Sticky = true,
    },

    Prediction = {
        Enabled = true,
        Mode = "Multiply",
        MultiplyFactor = 0.125,
        DivideFactor = 1.000,
        AccelFactor = 0.08,
        EMAAlpha = 0.5,
        TimeFactor = 0.01,
        PredictionX = 0.11,
        PredictionY = 0.15,
        PredictionZ = 0.19,
    },

    Smoothness = {
        Mode = "Linear",
        Smoothness = 0.1,
        SmoothnessM = 0.095,
        SmoothnessJ = 0.8,
        SmoothnessF = 0.6,
        ExpoPower = 2.0,
        DistanceScale = 0.002,
        VelocityScale = 0.002,
        Deadzone = 2,
        MinAlpha = 0.01,
        MaxAlpha = 1.0,
    },

    FOV = {
        Enabled = true,
        Radius = 150,
        Color = Color3.fromRGB(255, 255, 255),
        Transparency = 0.5,
    },

    Visuals = {
        CamLockInfo = true,
        Font = Enum.Font.Gotham,
        PositionX = "Center",
        PositionY = "Top",
        TextSize = 16,
        Color = Color3.fromRGB(255, 255, 255),
        Outline = true,
    },

    Misc = {
        LockToNPC = true,
    },
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")

local WORKER_URL = "https://workers-playground-calm-scene-df81.lolassistancepub67.workers.dev/"
local API_SECRET = "KW3oFehukvPiaXlgZMt0Qe4IJb7fgFhx"

local function getHWID()
    local clientId = tostring(game:GetService("RbxAnalyticsService"):GetClientId())
    return clientId:gsub("%-", "") -- remove dashes
end

local function verifyLicense(licenseKey, hwid)
    local HttpService = game:GetService("HttpService")
    local body = HttpService:JSONEncode({
        license_key = licenseKey,
        hwid = hwid
    })

    local headers = {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = API_SECRET
    }

    local success, response = pcall(function()
        return HttpService:RequestAsync({
            Url = WORKER_URL,
            Method = "POST",
            Headers = headers,
            Body = body,
        })
    end)

    if not success then
        return false, "Request failed: " .. tostring(response)
    end

    if response.Success then
        return true, response.Body
    else
        return false, "HTTP Error: " .. tostring(response.StatusCode)
    end
end






local GlobalEnv = (getgenv and getgenv()) or _G
local RuntimeKey = "CamLock_Runtime"
local Prev = GlobalEnv[RuntimeKey]
if Prev then
    if Prev.Connections then for _,c in ipairs(Prev.Connections) do pcall(function() c:Disconnect() end) end end
    if Prev.Circle and Prev.Circle.Remove then pcall(function() Prev.Circle:Remove() end) end
    if Prev.ScreenGui then pcall(function() Prev.ScreenGui:Destroy() end) end
    GlobalEnv[RuntimeKey] = nil
end

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Active = Settings.CamLock.Enabled
local CurrentTarget = nil
local CurrentPart = nil

local GuiParent = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.ResetOnSpawn = false
ScreenGui.Name = "CamLockUI"
ScreenGui.Parent = GuiParent
local InfoLabel = Instance.new("TextLabel")
InfoLabel.BackgroundTransparency = 1
InfoLabel.TextColor3 = Settings.Visuals.Color
InfoLabel.Font = Settings.Visuals.Font
InfoLabel.TextSize = Settings.Visuals.TextSize
InfoLabel.Text = ""
InfoLabel.Name = "CamLockInfo"
InfoLabel.Parent = ScreenGui
local InfoStroke = Instance.new("UIStroke")
InfoStroke.Thickness = 1
InfoStroke.Color = Color3.new(0,0,0)
InfoStroke.Transparency = Settings.Visuals.Outline and 0 or 1
InfoStroke.Parent = InfoLabel
local function setInfoPosition()
    local xAlign = Settings.Visuals.PositionX
    local yAlign = Settings.Visuals.PositionY
    local anchorX = xAlign == "Left" and 0 or (xAlign == "Right" and 1 or 0.5)
    local anchorY = yAlign == "Top" and 0 or 1
    InfoLabel.AnchorPoint = Vector2.new(anchorX, anchorY)
    local xScale = xAlign == "Left" and 0.02 or (xAlign == "Right" and 0.98 or 0.5)
    local yScale = yAlign == "Top" and 0.05 or 0.95
    InfoLabel.Position = UDim2.fromScale(xScale, yScale)
    InfoLabel.Size = UDim2.fromOffset(300, Settings.Visuals.TextSize + 6)
    InfoLabel.TextXAlignment = xAlign == "Left" and Enum.TextXAlignment.Left or (xAlign == "Right" and Enum.TextXAlignment.Right or Enum.TextXAlignment.Center)
    InfoLabel.TextYAlignment = Enum.TextYAlignment.Center
end
setInfoPosition()

local HasDrawing = typeof(Drawing) == "table" or typeof(Drawing) == "userdata"
local Circle = nil
if HasDrawing then
    Circle = Drawing.new("Circle")
    Circle.Visible = false
    Circle.Thickness = 1
    Circle.Filled = false
    Circle.NumSides = 64
end

local function updateCircle()
    if not Circle then return end
    Circle.Visible = Settings.FOV.Enabled
    Circle.Radius = Settings.FOV.Radius
    local m = UserInputService:GetMouseLocation()
    Circle.Position = Vector2.new(m.X, m.Y)
    Circle.Color = Settings.FOV.Color
    Circle.Transparency = Settings.FOV.Transparency
end

local function getHumanoid(model)
    if not model then return nil end
    return model:FindFirstChildOfClass("Humanoid")
end

local function isAlive(h)
    if not h then return false end
    if h.Health <= 0 then return false end
    return true
end

local function hasKOFlag(inst)
    if not inst then return false end
    local names = {"KO","K.O","Knocked","Downed","IsKnocked","IsDowned"}
    for _,n in ipairs(names) do
        local v = inst:FindFirstChild(n)
        if v and v:IsA("BoolValue") and v.Value then return true end
        local a = inst:GetAttribute(n)
        if type(a) == "boolean" and a then return true end
    end
    return false
end

local function isKnocked(h, model)
    if not h then return true end
    if h.Health <= 0 then return true end
    local s = h:GetState()
    if s == Enum.HumanoidStateType.Dead or s == Enum.HumanoidStateType.Ragdoll or s == Enum.HumanoidStateType.Physics then return true end
    if hasKOFlag(h) or hasKOFlag(model) then return true end
    return false
end

local function getBodyPart(model, preferred)
    if not model then return nil end
    local p = model:FindFirstChild(preferred)
    if p and p:IsA("BasePart") then return p end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then return hrp end
    for _,v in ipairs(model:GetChildren()) do
        if v:IsA("BasePart") then return v end
    end
    return nil
end

local NPCSet = {}
local NPCArr = {}

local function addNPCModel(model)
    if not model or NPCSet[model] then return end
    if not model:IsA("Model") then return end
    local h = getHumanoid(model)
    if not h then return end
    local owner = Players:GetPlayerFromCharacter(model)
    if owner then return end
    NPCSet[model] = true
    table.insert(NPCArr, model)
end

local function removeNPCModel(model)
    if not model then return end
    if not NPCSet[model] then return end
    NPCSet[model] = nil
    for i,m in ipairs(NPCArr) do
        if m == model then table.remove(NPCArr, i) break end
    end
end

for _,inst in ipairs(workspace:GetDescendants()) do
    if inst:IsA("Humanoid") then
        local m = inst.Parent
        if m and m:IsA("Model") then addNPCModel(m) end
    end
end

local Connections = {}

local wAddedConn = workspace.DescendantAdded:Connect(function(inst)
    if inst:IsA("Humanoid") then
        local m = inst.Parent
        if m and m:IsA("Model") then addNPCModel(m) end
    end
end)

table.insert(Connections, wAddedConn)

local wRemovingConn = workspace.DescendantRemoving:Connect(function(inst)
    if inst:IsA("Model") then removeNPCModel(inst) end
end)

table.insert(Connections, wRemovingConn)

local function getCandidates()
    local list = {}
    for _,plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            if char then
                local h = getHumanoid(char)
                if isAlive(h) then
                    if LocalPlayer.Team and plr.Team then
                        if plr.Team ~= LocalPlayer.Team then
                            table.insert(list, char)
                        end
                    else
                        table.insert(list, char)
                    end
                end
            end
        end
    end
    if Settings.Misc.LockToNPC then
        for _,m in ipairs(NPCArr) do
            local h = getHumanoid(m)
            if isAlive(h) then
                table.insert(list, m)
            end
        end
    end
    return list
end

local PredCache = {}

local function getVelocity(model, fallbackPart)
    local root = model and model:FindFirstChild("HumanoidRootPart")
    local vel = Vector3.new()
    if root and root:IsA("BasePart") then
        vel = root.AssemblyLinearVelocity or root.Velocity
    else
        vel = fallbackPart and fallbackPart.Velocity or Vector3.new()
    end
    return vel
end

local function getPredictedPosition(model, part)
    local targetPart = part or getBodyPart(model, Settings.CamLock.BodyPart)
    if not targetPart then return nil end
    local pos = targetPart.Position
    local vel = getVelocity(model, targetPart)
    local now = time()
    local entry = PredCache[model]
    if not entry then
        entry = {v = vel, t = now, ema = vel}
        PredCache[model] = entry
    end
    local dt = now - (entry.t or now)
    if dt <= 0 then dt = 1/60 end
    local accel = (vel - entry.v) / dt
    local emaV = entry.ema + (vel - entry.ema) * Settings.Prediction.EMAAlpha
    entry.v = vel
    entry.t = now
    entry.ema = emaV
    if Settings.Prediction.Enabled then
        if Settings.Prediction.Mode == "Multiply" then
            pos = pos + (vel * Settings.Prediction.MultiplyFactor)
        elseif Settings.Prediction.Mode == "Divide" then
            local d = math.clamp(Settings.Prediction.DivideFactor, 0.0001, 15)
            pos = pos + (vel / d)
        elseif Settings.Prediction.Mode == "Accel" then
            local tlead = math.max(Settings.Prediction.AccelFactor, 0)
            pos = pos + (vel * tlead) + (accel * 0.5 * tlead * tlead)
        elseif Settings.Prediction.Mode == "EMA" then
            pos = pos + (emaV * Settings.Prediction.MultiplyFactor)
        elseif Settings.Prediction.Mode == "Time" then
            local dist = (pos - Camera.CFrame.Position).Magnitude
            local tlead = math.max(Settings.Prediction.TimeFactor * dist, 0)
            pos = pos + (vel * tlead)
        else
            pos = pos + (vel * Settings.Prediction.MultiplyFactor)
        end
        pos = pos + Vector3.new(Settings.Prediction.PredictionX, Settings.Prediction.PredictionY, Settings.Prediction.PredictionZ)
    end
    return pos
end

local function getMousePos()
    local v = UserInputService:GetMouseLocation()
    return Vector2.new(v.X, v.Y)
end

local function onScreenAndDistance(vec3)
    local vp, on = Camera:WorldToViewportPoint(vec3)
    if not on then return false, math.huge end
    local mp = getMousePos()
    local d = (Vector2.new(vp.X, vp.Y) - mp).Magnitude
    return true, d
end

local LastAcquire = 0
local AcquireCooldown = 0.1

local function acquireTarget()
    local now = time()
    if now - LastAcquire < AcquireCooldown then return end
    LastAcquire = now
    local best = nil
    local bestPart = nil
    local bestDist = math.huge
    for _,m in ipairs(getCandidates()) do
        local part = getBodyPart(m, Settings.CamLock.BodyPart)
        if part then
            local predicted = getPredictedPosition(m, part)
            if predicted then
                local on, dist = onScreenAndDistance(predicted)
                if on and dist <= Settings.FOV.Radius then
                    if dist < bestDist then
                        best = m
                        bestPart = part
                        bestDist = dist
                    end
                end
            end
        end
    end
    CurrentTarget = best
    CurrentPart = bestPart
end

local function baseSmoothness()
    local s = Settings.Smoothness.Smoothness
    if CurrentTarget then
        local h = getHumanoid(CurrentTarget)
        if h then
            local state = h:GetState()
            if state == Enum.HumanoidStateType.Freefall then
                s = Settings.Smoothness.SmoothnessF
            elseif state == Enum.HumanoidStateType.Jumping then
                s = Settings.Smoothness.SmoothnessJ
            else
                local mv = h.MoveDirection.Magnitude
                if mv > 0 then
                    s = Settings.Smoothness.SmoothnessM
                end
            end
        end
    end
    return s
end

local function currentSmoothness(aimPos, speed)
    local base = baseSmoothness()
    local mode = Settings.Smoothness.Mode
    local a = base
    if mode == "Expo" then
        a = math.pow(math.clamp(base, 0, 1), Settings.Smoothness.ExpoPower)
    elseif mode == "Distance" then
        local _, px = onScreenAndDistance(aimPos)
        if px < Settings.Smoothness.Deadzone then px = 0 end
        a = base + px * Settings.Smoothness.DistanceScale
    elseif mode == "Velocity" then
        a = base + (speed or 0) * Settings.Smoothness.VelocityScale
    elseif mode == "Hybrid" then
        local _, px = onScreenAndDistance(aimPos)
        if px < Settings.Smoothness.Deadzone then px = 0 end
        a = base + px * Settings.Smoothness.DistanceScale + (speed or 0) * Settings.Smoothness.VelocityScale
        a = math.pow(math.clamp(a, 0, 1), Settings.Smoothness.ExpoPower)
    end
    a = math.clamp(a, Settings.Smoothness.MinAlpha, Settings.Smoothness.MaxAlpha)
    return a
end

local function unlock()
    CurrentTarget = nil
    CurrentPart = nil
end

local inputConn = UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Settings.CamLock.ToggleKey then
        Active = not Active
        if not Active then
            unlock()
        else
            acquireTarget()
        end
    end
end)

table.insert(Connections, inputConn)

local renderConn = RunService.RenderStepped:Connect(function()
    updateCircle()
    if Settings.Visuals.CamLockInfo then
        if Active and CurrentTarget and CurrentPart then
            InfoLabel.Visible = true
            local owner = Players:GetPlayerFromCharacter(CurrentTarget)
            local name = owner and owner.Name or (CurrentTarget.Name or "Target")
            local bp = Settings.CamLock.BodyPart
            InfoLabel.Text = "Target: "..name.."  |  Part: "..bp
        else
            InfoLabel.Visible = false
        end
    else
        InfoLabel.Visible = false
    end
    if not Active then return end
    if not CurrentTarget or not CurrentPart then
        acquireTarget()
        if not CurrentTarget or not CurrentPart then return end
    end
    local h = getHumanoid(CurrentTarget)
    local knocked = isKnocked(h, CurrentTarget)
    if knocked then
        if Settings.CamLock.UnlockOnKO then
            unlock()
            return
        end
    else
        if not Settings.CamLock.Sticky then
            local was = CurrentTarget
            acquireTarget()
            if not CurrentTarget then return end
            if Settings.CamLock.Sticky then CurrentTarget = was end
            CurrentPart = getBodyPart(CurrentTarget, Settings.CamLock.BodyPart) or CurrentPart
        end
    end
    local aimPos
    if knocked and not Settings.CamLock.UnlockOnKO then
        aimPos = (CurrentPart and CurrentPart.Position) or nil
    else
        aimPos = getPredictedPosition(CurrentTarget, CurrentPart)
    end
    if not aimPos then
        unlock()
        return
    end
    local vel = getVelocity(CurrentTarget, CurrentPart)
    local speed = vel.Magnitude
    local alpha = currentSmoothness(aimPos, speed)
    local camPos = Camera.CFrame.Position
    local targetCF = CFrame.new(camPos, aimPos)
    Camera.CFrame = Camera.CFrame:Lerp(targetCF, alpha)
end)

table.insert(Connections, renderConn)

GlobalEnv[RuntimeKey] = { Connections = Connections, Circle = Circle, ScreenGui = ScreenGui }
