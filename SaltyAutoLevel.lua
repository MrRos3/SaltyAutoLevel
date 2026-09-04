--// Salty Auto Level
--// Instant Win -> Auto Retry -> wait for REAL level load -> Auto Win

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local RAW_URL = "https://raw.githubusercontent.com/MrRos3/SaltyAutoLevel/main/SaltyAutoLevel.lua"

--==================================================
-- AUTO RE-EXECUTE AFTER TELEPORT
--==================================================

local QueueOnTeleport =
    queue_on_teleport
    or queueonteleport
    or (syn and syn.queue_on_teleport)
    or (fluxus and fluxus.queue_on_teleport)

if QueueOnTeleport then
    local queuedCode = string.format([[
        repeat task.wait(0.1) until game:IsLoaded()
        task.wait(0.5)
        local ok, err = pcall(function()
            loadstring(game:HttpGet(%q))()
        end)
        if not ok then
            warn("[Salty] queued re-execute failed:", err)
        end
    ]], RAW_URL)

    pcall(function()
        QueueOnTeleport(queuedCode)
    end)
else
    warn("[Salty] queue_on_teleport unsupported; use SaltyAutoExec.lua in your executor autoexec folder")
end

--==================================================
-- STOP OLD COPY
--==================================================

_G.SaltyMiniRun = (_G.SaltyMiniRun or 0) + 1
local RUN_ID = _G.SaltyMiniRun

local function Running()
    return _G.SaltyMiniRun == RUN_ID
end

local oldGui = PlayerGui:FindFirstChild("SaltyMini")
if oldGui then
    oldGui:Destroy()
end

if _G.SaltyMiniConnections then
    for _, connection in ipairs(_G.SaltyMiniConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
end

_G.SaltyMiniConnections = {}

local function Track(connection)
    table.insert(_G.SaltyMiniConnections, connection)
    return connection
end

--==================================================
-- STATE
--==================================================

local AutoInstantWin = true
local AutoRetry = true
local WinBusy = false
local RetryBusy = false
local WaitingForLevel = false
local LastWin = 0
local ScreenGui
local StatusLabel
local LevelWaitToken = 0

local RETRY_SCAN_DELAY = 0.03
local RETRY_CLICK_WAIT = 0.06
local LEVEL_SCAN_DELAY = 0.05

local function SetStatus(text)
    if StatusLabel then
        StatusLabel.Text = text
    end
    print("[Salty] " .. text)
end

--==================================================
-- CHARACTER
--==================================================

local Character = LocalPlayer.Character
local Humanoid
local HumanoidRootPart

local function RefreshCharacter()
    Character = LocalPlayer.Character

    if Character then
        Humanoid = Character:FindFirstChildOfClass("Humanoid")
        HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
    else
        Humanoid = nil
        HumanoidRootPart = nil
    end
end

RefreshCharacter()

Track(LocalPlayer.CharacterAdded:Connect(function(char)
    Character = char
    Humanoid = char:WaitForChild("Humanoid", 5)
    HumanoidRootPart = char:WaitForChild("HumanoidRootPart", 5)
end))

--==================================================
-- GAME HELPERS
--==================================================

local function GetRemote(path, timeout)
    timeout = timeout or 3
    local current = ReplicatedStorage

    for _, name in ipairs(path) do
        current = current:FindFirstChild(name) or current:WaitForChild(name, timeout)
        if not current then
            return nil
        end
    end

    return current
end

local function GetQuickEvent()
    return GetRemote({"Events", "QuickEvent"})
end

local function GetLevel0Event()
    return GetRemote({"Events", "Levels", "Level0", "Level0Event"})
end

local function GetLevelSettings()
    return GetRemote({"LevelSettings", "CurrentLevel"})
end

local function GetCurrentLevel()
    local current = GetLevelSettings()
    if not current then
        return "Level0"
    end

    local childValue = current:FindFirstChild("Value")
    if childValue then
        return childValue.Value
    end

    if current:IsA("StringValue") then
        return current.Value
    end

    return "Level0"
end

--==================================================
-- GUI VISIBILITY
--==================================================

local function IsVisible(object)
    if not object then
        return false
    end

    if object:IsA("GuiObject") and not object.Visible then
        return false
    end

    local current = object.Parent

    while current and current ~= PlayerGui do
        if current:IsA("GuiObject") and not current.Visible then
            return false
        end

        if current:IsA("ScreenGui") and not current.Enabled then
            return false
        end

        current = current.Parent
    end

    return true
end

--==================================================
-- RETRY DETECTION
--==================================================

local function IsRetryText(object)
    if not (object:IsA("TextLabel") or object:IsA("TextButton")) then
        return false
    end

    local text = tostring(object.Text or ""):lower():gsub("%s+", " ")
    return text:find("retry level", 1, true) ~= nil
end

local function FindRetryText()
    for _, object in ipairs(PlayerGui:GetDescendants()) do
        if ScreenGui and object:IsDescendantOf(ScreenGui) then
            continue
        end

        if IsRetryText(object) and IsVisible(object) then
            return object
        end
    end

    return nil
end

local function RetryVisible()
    return FindRetryText() ~= nil
end

--==================================================
-- REAL LEVEL LOADING DETECTION
--==================================================

local function GetVisibleLoadingPhase()
    for _, object in ipairs(PlayerGui:GetDescendants()) do
        if ScreenGui and object:IsDescendantOf(ScreenGui) then
            continue
        end

        if (object:IsA("TextLabel") or object:IsA("TextButton")) and IsVisible(object) then
            local text = tostring(object.Text or ""):lower():gsub("%s+", " ")

            if text:find("loading assets", 1, true) then
                return "LOADING ASSETS..."
            end

            if text:find("loading level", 1, true) then
                return "LOADING LEVEL..."
            end
        end
    end

    return nil
end

local function CharacterReady()
    RefreshCharacter()

    return Character ~= nil
        and Humanoid ~= nil
        and Humanoid.Parent ~= nil
        and HumanoidRootPart ~= nil
        and HumanoidRootPart.Parent ~= nil
        and Humanoid.Health > 0
end

-- Forward declaration because WaitForLevelReady calls it.
local InstantComplete

local function WaitForLevelReady(reason)
    LevelWaitToken += 1
    local myToken = LevelWaitToken

    WaitingForLevel = true

    task.spawn(function()
        local startedAt = tick()
        local sawLoadingPhase = false
        local clearSince = nil
        local lastPhase = nil

        while Running()
            and AutoInstantWin
            and myToken == LevelWaitToken
        do
            local phase = GetVisibleLoadingPhase()

            if phase then
                sawLoadingPhase = true
                clearSince = nil

                if phase ~= lastPhase then
                    lastPhase = phase
                    SetStatus(phase)
                end
            else
                local ready = CharacterReady() and not RetryVisible()

                if ready then
                    if not clearSince then
                        clearSince = tick()
                    end

                    -- If we actually saw Loading Level / Loading Assets,
                    -- fire shortly after those phases disappear.
                    -- If the script was manually executed inside an already
                    -- loaded level, use a longer fallback instead.
                    local stableTime = sawLoadingPhase and 0.65 or 2.0
                    local canFallback = sawLoadingPhase or (tick() - startedAt >= 4.0)

                    if canFallback and tick() - clearSince >= stableTime then
                        WaitingForLevel = false
                        SetStatus("LEVEL READY")

                        task.wait(0.15)

                        if Running()
                            and AutoInstantWin
                            and myToken == LevelWaitToken
                            and not RetryVisible()
                        then
                            InstantComplete()
                        end

                        return
                    end
                else
                    clearSince = nil
                end
            end

            task.wait(LEVEL_SCAN_DELAY)
        end

        if myToken == LevelWaitToken then
            WaitingForLevel = false
        end
    end)
end

--==================================================
-- INSTANT COMPLETE
--==================================================

InstantComplete = function()
    if not Running() or WinBusy or WaitingForLevel then
        return
    end

    if tick() - LastWin < 1 then
        return
    end

    local qe = GetQuickEvent()
    if not qe then
        SetStatus("QuickEvent missing")
        return
    end

    WinBusy = true
    LastWin = tick()
    RefreshCharacter()

    local levelName = GetCurrentLevel()
    SetStatus("WINNING...")

    pcall(function()
        qe:FireServer("CompleteLevel", levelName)
    end)

    task.wait(0.8)

    if Character then
        local state = Character:FindFirstChild("State")
        if state then
            pcall(function()
                state.Value = ""
            end)
        end

        local spectating = Character:FindFirstChild("Spectating")
        if spectating then
            pcall(function()
                spectating.Value = nil
            end)
        end

        local action = Character:FindFirstChild("Action")
        if action then
            pcall(function()
                action.Value = ""
            end)
        end
    end

    pcall(function()
        qe:FireServer("MakePlayerAliveClient")
    end)

    task.wait(0.35)

    pcall(function()
        qe:FireServer("MakePlayerPlayable")
    end)

    task.wait(0.35)

    pcall(function()
        qe:FireServer("IsNotBusy", false)
    end)

    local loadingGui = PlayerGui:FindFirstChild("LoadingScreen")
    if loadingGui then
        local black = loadingGui:FindFirstChild("BlackScreen")

        if black then
            pcall(function()
                black.BackgroundTransparency = 1
                black.Visible = false
            end)
        end

        pcall(function()
            loadingGui.Enabled = false
        end)
    end

    local lobbyScreen = PlayerGui:FindFirstChild("LobbyScreen")
    if lobbyScreen then
        pcall(function()
            lobbyScreen.Enabled = true
        end)
    end

    local firstPerson = PlayerGui:FindFirstChild("FirstPerson")
    if firstPerson then
        local mouseLock = firstPerson:FindFirstChild("MouseLock")
        if mouseLock then
            pcall(function()
                mouseLock.Modal = true
            end)
        end
    end

    if Humanoid then
        pcall(function()
            Humanoid.AutoRotate = true
            Humanoid.WalkSpeed = 16
        end)
    end

    if Character then
        local neck = Character:FindFirstChild("Neck", true)
        if neck and neck:IsA("Motor6D") then
            pcall(function()
                neck.C0 = CFrame.new(0, neck.C0.Y, 0)
            end)
        end

        local rightUpperArm = Character:FindFirstChild("RightUpperArm")
        if rightUpperArm then
            local rightShoulder = rightUpperArm:FindFirstChild("RightShoulder")
            if rightShoulder and rightShoulder:IsA("Motor6D") then
                pcall(function()
                    rightShoulder.C0 = CFrame.new(0.701, 0.901, 0.007)
                end)
            end
        end

        local leftUpperArm = Character:FindFirstChild("LeftUpperArm")
        if leftUpperArm then
            local leftShoulder = leftUpperArm:FindFirstChild("LeftShoulder")
            if leftShoulder and leftShoulder:IsA("Motor6D") then
                pcall(function()
                    leftShoulder.C0 = CFrame.new(-0.73, 0.879, 0.007)
                end)
            end
        end
    end

    local l0e = GetLevel0Event()
    if l0e then
        pcall(function()
            l0e:FireServer("EndedLastCutScene")
        end)

        task.wait(0.05)

        pcall(function()
            l0e:FireServer("BlackScreenEnded")
        end)
    end

    WinBusy = false
    SetStatus("WAITING RETRY...")
end

--==================================================
-- RETRY CLICKING
--==================================================

local function FindRetryButton(textObject)
    if not textObject then
        return nil
    end

    if textObject:IsA("GuiButton") then
        return textObject
    end

    local current = textObject.Parent

    for _ = 1, 10 do
        if not current or current == PlayerGui then
            break
        end

        if current:IsA("GuiButton") then
            return current
        end

        current = current.Parent
    end

    return nil
end

local function SilentClick(x, y)
    return pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.015)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
end

local function GetClickPositions(object)
    local position = object.AbsolutePosition
    local size = object.AbsoluteSize
    local x = position.X + size.X / 2
    local y = position.Y + size.Y / 2
    local inset = GuiService:GetGuiInset()

    return {
        {X = x + inset.X, Y = y + inset.Y},
        {X = x, Y = y},
        {X = x + inset.X, Y = y + inset.Y + 8},
    }
end

local function RetryLevel(textObject)
    if RetryBusy or not AutoRetry then
        return
    end

    RetryBusy = true
    SetStatus("RETRYING...")

    local button = FindRetryButton(textObject)

    if button and firesignal then
        pcall(function()
            firesignal(button.Activated)
        end)

        task.wait(0.04)

        if RetryVisible() then
            pcall(function()
                firesignal(button.MouseButton1Click)
            end)
            task.wait(0.04)
        end
    end

    if RetryVisible() then
        local target = button or textObject

        for _, point in ipairs(GetClickPositions(target)) do
            if not AutoRetry or not RetryVisible() then
                break
            end

            SilentClick(point.X, point.Y)
            task.wait(RETRY_CLICK_WAIT)
        end
    end

    local success = false

    for _ = 1, 100 do
        if not Running() then
            return
        end

        task.wait(0.02)

        if not RetryVisible() then
            success = true
            break
        end
    end

    if success then
        SetStatus("RETRY SUCCESS")
        RetryBusy = false

        -- Critical fix: do NOT instant-win on a blind timer.
        -- Wait through Loading Level -> Loading Assets -> actual level.
        WaitForLevelReady("RETRY")
        return
    end

    SetStatus("RETRY FAILED")
    RetryBusy = false
end

task.spawn(function()
    while Running() do
        task.wait(RETRY_SCAN_DELAY)

        if AutoRetry
            and not RetryBusy
            and not WinBusy
            and not WaitingForLevel
        then
            local retryText = FindRetryText()

            if retryText then
                task.spawn(RetryLevel, retryText)
            end
        end
    end
end)

--==================================================
-- MINI GUI
--==================================================

ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SaltyMini"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = false
ScreenGui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(210, 194)
Main.Position = UDim2.new(0.5, -105, 0.16, 0)
Main.BackgroundColor3 = Color3.fromRGB(14, 14, 16)
Main.BorderSizePixel = 0
Main.Active = true
Main.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 12)
Corner.Parent = Main

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(55, 55, 62)
Stroke.Thickness = 1
Stroke.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -20, 0, 26)
Title.Position = UDim2.fromOffset(10, 5)
Title.BackgroundTransparency = 1
Title.Text = "SALTY"
Title.TextColor3 = Color3.fromRGB(245, 245, 245)
Title.TextSize = 15
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local Subtitle = Instance.new("TextLabel")
Subtitle.Size = UDim2.new(1, -20, 0, 18)
Subtitle.Position = UDim2.fromOffset(10, 27)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "Auto Level"
Subtitle.TextColor3 = Color3.fromRGB(125, 125, 135)
Subtitle.TextSize = 10
Subtitle.Font = Enum.Font.Gotham
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = Main

StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -20, 0, 18)
StatusLabel.Position = UDim2.fromOffset(10, 45)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "READY"
StatusLabel.TextColor3 = Color3.fromRGB(135, 190, 255)
StatusLabel.TextSize = 9
StatusLabel.Font = Enum.Font.GothamMedium
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = Main

local function CreateToggle(text, y, default, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -20, 0, 34)
    button.Position = UDim2.fromOffset(10, y)
    button.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
    button.BorderSizePixel = 0
    button.Text = ""
    button.AutoButtonColor = false
    button.Parent = Main

    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 8)
    buttonCorner.Parent = button

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -55, 1, 0)
    label.Position = UDim2.fromOffset(9, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(225, 225, 230)
    label.TextSize = 11
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = button

    local state = Instance.new("TextLabel")
    state.Size = UDim2.fromOffset(38, 21)
    state.Position = UDim2.new(1, -45, 0.5, -10)
    state.BorderSizePixel = 0
    state.TextSize = 9
    state.Font = Enum.Font.GothamBold
    state.Parent = button

    local stateCorner = Instance.new("UICorner")
    stateCorner.CornerRadius = UDim.new(1, 0)
    stateCorner.Parent = state

    local value = default

    local function Refresh()
        if value then
            state.Text = "ON"
            state.BackgroundColor3 = Color3.fromRGB(32, 54, 39)
            state.TextColor3 = Color3.fromRGB(120, 255, 155)
        else
            state.Text = "OFF"
            state.BackgroundColor3 = Color3.fromRGB(54, 37, 40)
            state.TextColor3 = Color3.fromRGB(255, 125, 135)
        end
    end

    Refresh()

    button.MouseButton1Click:Connect(function()
        value = not value
        Refresh()
        callback(value)
    end)
end

CreateToggle("Auto Instant Win", 65, true, function(value)
    AutoInstantWin = value

    if value then
        if WaitingForLevel then
            return
        end

        task.spawn(function()
            WaitForLevelReady("TOGGLE")
        end)
    else
        LevelWaitToken += 1
        WaitingForLevel = false
    end
end)

CreateToggle("Auto Retry", 104, true, function(value)
    AutoRetry = value

    if not value then
        RetryBusy = false
    end
end)

local WinButton = Instance.new("TextButton")
WinButton.Size = UDim2.new(1, -20, 0, 29)
WinButton.Position = UDim2.fromOffset(10, 145)
WinButton.BackgroundColor3 = Color3.fromRGB(29, 29, 34)
WinButton.BorderSizePixel = 0
WinButton.Text = "WIN NOW"
WinButton.TextColor3 = Color3.fromRGB(240, 240, 245)
WinButton.TextSize = 10
WinButton.Font = Enum.Font.GothamBold
WinButton.AutoButtonColor = false
WinButton.Parent = Main

local WinCorner = Instance.new("UICorner")
WinCorner.CornerRadius = UDim.new(0, 8)
WinCorner.Parent = WinButton

WinButton.MouseButton1Click:Connect(function()
    task.spawn(InstantComplete)
end)

--==================================================
-- DRAG
--==================================================

local Dragging = false
local DragStart
local StartPosition

Main.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        Dragging = true
        DragStart = input.Position
        StartPosition = Main.Position
    end
end)

Main.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
    then
        Dragging = false
    end
end)

Track(UserInputService.InputChanged:Connect(function(input)
    if not Dragging then
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    then
        local delta = input.Position - DragStart

        Main.Position = UDim2.new(
            StartPosition.X.Scale,
            StartPosition.X.Offset + delta.X,
            StartPosition.Y.Scale,
            StartPosition.Y.Offset + delta.Y
        )
    end
end))

--==================================================
-- AUTO START
--==================================================

SetStatus("WAITING LEVEL...")

-- Do not instant-win just because game:IsLoaded().
-- The game still has its own Loading Level / Loading Assets phases.
WaitForLevelReady("AUTO START")
