--// Salty Mini // Auto Level
--// Instant Win -> Auto Retry -> Auto Execute After Teleport
--// Execute once, then it keeps reloading itself <3

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

--==================================================
-- YOUR RAW SCRIPT URL
--==================================================
--
-- When you upload this script to GitHub, replace this:
--
local SALTY_RAW_URL = "https://github.com/MrRos3/SaltyAutoLevel/edit/main/SaltyAutoLevel.lua"

-- Example:
-- local SALTY_RAW_URL =
--     "https://raw.githubusercontent.com/MrRos3/SaltyMini/main/SaltyMini.lua"

--==================================================
-- QUEUE AFTER TELEPORT
--==================================================

local QueueOnTeleport =
	queue_on_teleport
	or queueonteleport
	or (
		syn
		and syn.queue_on_teleport
	)
	or (
		fluxus
		and fluxus.queue_on_teleport
	)

local function QueueSalty()

	if not QueueOnTeleport then
		warn(
			"[Salty] queue_on_teleport unsupported"
		)

		return false
	end

	if not SALTY_RAW_URL
		or SALTY_RAW_URL == ""
		or SALTY_RAW_URL:find(
			"PUT_YOUR_RAW_GITHUB_URL_HERE",
			1,
			true
		)
	then

		warn(
			"[Salty] Add your raw GitHub URL for auto execute"
		)

		return false
	end

	local Loader = string.format([[
		repeat
			task.wait(0.25)
		until game:IsLoaded()

		task.wait(0.75)

		local ok, err = pcall(function()
			loadstring(game:HttpGet(%q))()
		end)

		if not ok then
			warn("[Salty] Auto execute failed:", err)
		end
	]], SALTY_RAW_URL)

	local Success =
		pcall(function()
			QueueOnTeleport(
				Loader
			)
		end)

	if Success then
		print(
			"[Salty] Auto execute queued <3"
		)
	else
		warn(
			"[Salty] Could not queue teleport loader"
		)
	end

	return Success
end

-- Queue immediately.
-- When the new copy loads after teleport,
-- it queues itself again for the NEXT retry.
QueueSalty()

--==================================================
-- KILL PREVIOUS COPY
--==================================================

_G.SaltyMiniRun =
	(_G.SaltyMiniRun or 0) + 1

local THIS_RUN =
	_G.SaltyMiniRun

local function Running()
	return
		_G.SaltyMiniRun
		== THIS_RUN
end

local OldGui =
	PlayerGui:FindFirstChild(
		"SaltyMini"
	)

if OldGui then
	OldGui:Destroy()
end

if _G.SaltyMiniConnections then

	for _, Connection in ipairs(
		_G.SaltyMiniConnections
	) do

		pcall(function()
			Connection:Disconnect()
		end)

	end
end

_G.SaltyMiniConnections = {}

local function Track(Connection)

	table.insert(
		_G.SaltyMiniConnections,
		Connection
	)

	return Connection
end

--==================================================
-- SETTINGS
--==================================================

local AutoInstantWin = true
local AutoRetry = true

local WinBusy = false
local RetryBusy = false

local LastWin = 0

local RETRY_SCAN_DELAY = 0.03
local RETRY_CLICK_WAIT = 0.07

local ScreenGui

--==================================================
-- CHARACTER
--==================================================

local Character =
	LocalPlayer.Character

local Humanoid = nil

local function RefreshCharacter()

	Character =
		LocalPlayer.Character

	if Character then

		Humanoid =
			Character:
			FindFirstChildOfClass(
				"Humanoid"
			)

	end
end

RefreshCharacter()

Track(
	LocalPlayer.CharacterAdded:
	Connect(function(Char)

		Character = Char

		Humanoid =
			Char:WaitForChild(
				"Humanoid",
				5
			)

	end)
)

--==================================================
-- REMOTE HELPER
--==================================================

local function GetRemote(
	Path,
	Timeout
)

	Timeout =
		Timeout or 3

	local Current =
		ReplicatedStorage

	for _, Name in ipairs(Path) do

		Current =
			Current:FindFirstChild(Name)
			or Current:WaitForChild(
				Name,
				Timeout
			)

		if not Current then
			return nil
		end
	end

	return Current
end

local function GetQuickEvent()

	return GetRemote({
		"Events",
		"QuickEvent"
	})

end

local function GetLevel0Event()

	return GetRemote({
		"Events",
		"Levels",
		"Level0",
		"Level0Event"
	})

end

local function GetLevelSettings()

	return GetRemote({
		"LevelSettings",
		"CurrentLevel"
	})

end

--==================================================
-- CURRENT LEVEL
--==================================================

local function GetCurrentLevel()

	local Current =
		GetLevelSettings()

	if not Current then
		return "Level0"
	end

	local Value =
		Current:FindFirstChild(
			"Value"
		)

	if Value then
		return Value.Value
	end

	if Current:IsA(
		"StringValue"
	) then

		return Current.Value

	end

	return "Level0"
end

--==================================================
-- INSTANT COMPLETE
--==================================================

local function InstantComplete()

	if not Running() then
		return
	end

	if WinBusy then
		return
	end

	if tick() - LastWin < 1 then
		return
	end

	local QE =
		GetQuickEvent()

	if not QE then

		warn(
			"[Salty] QuickEvent missing"
		)

		return
	end

	WinBusy = true
	LastWin = tick()

	RefreshCharacter()

	local LevelName =
		GetCurrentLevel()

	print(
		"[Salty] Instant Win:",
		LevelName
	)

	--==================================================
	-- COMPLETE
	--==================================================

	pcall(function()

		QE:FireServer(
			"CompleteLevel",
			LevelName
		)

	end)

	task.wait(0.8)

	--==================================================
	-- CHARACTER STATE
	--==================================================

	if Character then

		local State =
			Character:
			FindFirstChild(
				"State"
			)

		if State then

			pcall(function()
				State.Value = ""
			end)

		end

		local Spectating =
			Character:
			FindFirstChild(
				"Spectating"
			)

		if Spectating then

			pcall(function()
				Spectating.Value = nil
			end)

		end

		local Action =
			Character:
			FindFirstChild(
				"Action"
			)

		if Action then

			pcall(function()
				Action.Value = ""
			end)

		end
	end

	--==================================================
	-- PLAYER RESTORE
	--==================================================

	pcall(function()

		QE:FireServer(
			"MakePlayerAliveClient"
		)

	end)

	task.wait(0.35)

	pcall(function()

		QE:FireServer(
			"MakePlayerPlayable"
		)

	end)

	task.wait(0.35)

	pcall(function()

		QE:FireServer(
			"IsNotBusy",
			false
		)

	end)

	--==================================================
	-- LOADING SCREEN
	--==================================================

	local Loading =
		PlayerGui:
		FindFirstChild(
			"LoadingScreen"
		)

	if Loading then

		local Black =
			Loading:
			FindFirstChild(
				"BlackScreen"
			)

		if Black then

			pcall(function()

				Black.BackgroundTransparency =
					1

				Black.Visible =
					false

			end)

		end

		pcall(function()
			Loading.Enabled = false
		end)

	end

	--==================================================
	-- RESULT SCREEN
	--==================================================

	local Lobby =
		PlayerGui:
		FindFirstChild(
			"LobbyScreen"
		)

	if Lobby then

		pcall(function()
			Lobby.Enabled = true
		end)

	end

	--==================================================
	-- FIRST PERSON FIX
	--==================================================

	local FirstPerson =
		PlayerGui:
		FindFirstChild(
			"FirstPerson"
		)

	if FirstPerson then

		local MouseLock =
			FirstPerson:
			FindFirstChild(
				"MouseLock"
			)

		if MouseLock then

			pcall(function()
				MouseLock.Modal = true
			end)

		end
	end

	--==================================================
	-- HUMANOID
	--==================================================

	if Humanoid then

		pcall(function()

			Humanoid.AutoRotate =
				true

			Humanoid.WalkSpeed =
				16

		end)

	end

	--==================================================
	-- JOINT FIX
	--==================================================

	if Character then

		local Neck =
			Character:
			FindFirstChild(
				"Neck",
				true
			)

		if Neck
			and Neck:IsA(
				"Motor6D"
			)
		then

			pcall(function()

				Neck.C0 =
					CFrame.new(
						0,
						Neck.C0.Y,
						0
					)

			end)

		end

		local RightUpperArm =
			Character:
			FindFirstChild(
				"RightUpperArm"
			)

		if RightUpperArm then

			local RightShoulder =
				RightUpperArm:
				FindFirstChild(
					"RightShoulder"
				)

			if RightShoulder
				and RightShoulder:IsA(
					"Motor6D"
				)
			then

				pcall(function()

					RightShoulder.C0 =
						CFrame.new(
							0.701,
							0.901,
							0.007
						)

				end)

			end
		end

		local LeftUpperArm =
			Character:
			FindFirstChild(
				"LeftUpperArm"
			)

		if LeftUpperArm then

			local LeftShoulder =
				LeftUpperArm:
				FindFirstChild(
					"LeftShoulder"
				)

			if LeftShoulder
				and LeftShoulder:IsA(
					"Motor6D"
				)
			then

				pcall(function()

					LeftShoulder.C0 =
						CFrame.new(
							-0.73,
							0.879,
							0.007
						)

				end)

			end
		end
	end

	--==================================================
	-- LEVEL 0 END
	--==================================================

	local L0 =
		GetLevel0Event()

	if L0 then

		pcall(function()

			L0:FireServer(
				"EndedLastCutScene"
			)

		end)

		task.wait(0.05)

		pcall(function()

			L0:FireServer(
				"BlackScreenEnded"
			)

		end)

	end

	WinBusy = false
end

--==================================================
-- VISIBILITY
--==================================================

local function IsVisible(Object)

	if not Object then
		return false
	end

	if Object:IsA(
		"GuiObject"
	) and not Object.Visible
	then

		return false

	end

	local Current =
		Object.Parent

	while Current
		and Current ~= PlayerGui
	do

		if Current:IsA(
			"GuiObject"
		) and not Current.Visible
		then

			return false

		end

		if Current:IsA(
			"ScreenGui"
		) and not Current.Enabled
		then

			return false

		end

		Current =
			Current.Parent
	end

	return true
end

--==================================================
-- RETRY TEXT
--==================================================

local function IsRetryText(Object)

	if not (
		Object:IsA("TextLabel")
		or Object:IsA("TextButton")
	) then

		return false

	end

	local Text =
		tostring(
			Object.Text or ""
		)
		:lower()
		:gsub(
			"%s+",
			" "
		)

	return Text:find(
		"retry level",
		1,
		true
	) ~= nil
end

local function FindRetryText()

	for _, Object in ipairs(
		PlayerGui:GetDescendants()
	) do

		if ScreenGui
			and Object:IsDescendantOf(
				ScreenGui
			)
		then

			continue

		end

		if IsRetryText(Object)
			and IsVisible(Object)
		then

			return Object

		end
	end

	return nil
end

local function RetryVisible()

	return
		FindRetryText()
		~= nil

end

--==================================================
-- FIND RETRY BUTTON
--==================================================

local function FindRetryButton(
	TextObject
)

	if not TextObject then
		return nil
	end

	if TextObject:IsA(
		"GuiButton"
	) then

		return TextObject

	end

	local Current =
		TextObject.Parent

	for _ = 1, 10 do

		if not Current
			or Current == PlayerGui
		then

			break

		end

		if Current:IsA(
			"GuiButton"
		) then

			return Current

		end

		Current =
			Current.Parent
	end

	return nil
end

--==================================================
-- RETRY CLICK COORDINATES
--==================================================

local function GetClickPositions(
	Object
)

	local Position =
		Object.AbsolutePosition

	local Size =
		Object.AbsoluteSize

	local X =
		Position.X
		+ Size.X / 2

	local Y =
		Position.Y
		+ Size.Y / 2

	local Inset =
		GuiService:GetGuiInset()

	return {

		{
			X =
				X + Inset.X,

			Y =
				Y + Inset.Y
		},

		{
			X = X,
			Y = Y
		},

		{
			X =
				X + Inset.X,

			Y =
				Y + Inset.Y + 8
		}

	}
end

--==================================================
-- SILENT CLICK
--==================================================

local function SilentClick(
	X,
	Y
)

	return pcall(function()

		VirtualInputManager:
			SendMouseButtonEvent(
				X,
				Y,
				0,
				true,
				game,
				0
			)

		task.wait(0.015)

		VirtualInputManager:
			SendMouseButtonEvent(
				X,
				Y,
				0,
				false,
				game,
				0
			)

	end)
end

--==================================================
-- RETRY
--==================================================

local function RetryLevel(
	TextObject
)

	if RetryBusy
		or not AutoRetry
	then

		return

	end

	RetryBusy = true

	print(
		"[Salty] Retry Level"
	)

	local Button =
		FindRetryButton(
			TextObject
		)

	--==================================================
	-- DIRECT SIGNAL
	--==================================================

	if Button and firesignal then

		pcall(function()

			firesignal(
				Button.Activated
			)

		end)

		task.wait(0.04)

		if RetryVisible() then

			pcall(function()

				firesignal(
					Button.MouseButton1Click
				)

			end)

		end
	end

	--==================================================
	-- SILENT CLICK
	--==================================================

	if RetryVisible() then

		local Target =
			Button
			or TextObject

		local Positions =
			GetClickPositions(
				Target
			)

		for _, Point in ipairs(
			Positions
		) do

			if not RetryVisible()
				or not AutoRetry
			then

				break

			end

			SilentClick(
				Point.X,
				Point.Y
			)

			task.wait(
				RETRY_CLICK_WAIT
			)

		end
	end

	--==================================================
	-- WAIT FOR RETRY TO START
	--==================================================

	for _ = 1, 100 do

		if not Running() then
			return
		end

		task.wait(0.02)

		if not RetryVisible() then

			print(
				"[Salty] Retry successful <3"
			)

			break
		end
	end

	RetryBusy = false
end

--==================================================
-- AUTO RETRY WATCHER
--==================================================

task.spawn(function()

	while Running() do

		task.wait(
			RETRY_SCAN_DELAY
		)

		if AutoRetry
			and not RetryBusy
			and not WinBusy
		then

			local RetryText =
				FindRetryText()

			if RetryText then

				task.spawn(
					RetryLevel,
					RetryText
				)

			end
		end
	end
end)

--==================================================
-- MINI GUI
--==================================================

ScreenGui =
	Instance.new(
		"ScreenGui"
	)

ScreenGui.Name =
	"SaltyMini"

ScreenGui.ResetOnSpawn =
	false

ScreenGui.IgnoreGuiInset =
	false

ScreenGui.Parent =
	PlayerGui

local Main =
	Instance.new(
		"Frame"
	)

Main.Name =
	"Main"

Main.Size =
	UDim2.fromOffset(
		210,
		174
	)

Main.Position =
	UDim2.new(
		0.5,
		-105,
		0.16,
		0
	)

Main.BackgroundColor3 =
	Color3.fromRGB(
		14,
		14,
		16
	)

Main.BorderSizePixel =
	0

Main.Active =
	true

Main.Parent =
	ScreenGui

local Corner =
	Instance.new(
		"UICorner"
	)

Corner.CornerRadius =
	UDim.new(
		0,
		12
	)

Corner.Parent =
	Main

local Stroke =
	Instance.new(
		"UIStroke"
	)

Stroke.Color =
	Color3.fromRGB(
		55,
		55,
		62
	)

Stroke.Thickness =
	1

Stroke.Parent =
	Main

--==================================================
-- TITLE
--==================================================

local Title =
	Instance.new(
		"TextLabel"
	)

Title.Size =
	UDim2.new(
		1,
		-20,
		0,
		26
	)

Title.Position =
	UDim2.fromOffset(
		10,
		5
	)

Title.BackgroundTransparency =
	1

Title.Text =
	"SALTY"

Title.TextColor3 =
	Color3.fromRGB(
		245,
		245,
		245
	)

Title.TextSize =
	15

Title.Font =
	Enum.Font.GothamBold

Title.TextXAlignment =
	Enum.TextXAlignment.Left

Title.Parent =
	Main

local Subtitle =
	Instance.new(
		"TextLabel"
	)

Subtitle.Size =
	UDim2.new(
		1,
		-20,
		0,
		18
	)

Subtitle.Position =
	UDim2.fromOffset(
		10,
		27
	)

Subtitle.BackgroundTransparency =
	1

Subtitle.Text =
	"Auto Level"

Subtitle.TextColor3 =
	Color3.fromRGB(
		125,
		125,
		135
	)

Subtitle.TextSize =
	10

Subtitle.Font =
	Enum.Font.Gotham

Subtitle.TextXAlignment =
	Enum.TextXAlignment.Left

Subtitle.Parent =
	Main

--==================================================
-- TOGGLE CREATOR
--==================================================

local function CreateToggle(
	Text,
	Y,
	Default,
	Callback
)

	local Button =
		Instance.new(
			"TextButton"
		)

	Button.Size =
		UDim2.new(
			1,
			-20,
			0,
			34
		)

	Button.Position =
		UDim2.fromOffset(
			10,
			Y
		)

	Button.BackgroundColor3 =
		Color3.fromRGB(
			24,
			24,
			28
		)

	Button.BorderSizePixel =
		0

	Button.Text =
		""

	Button.AutoButtonColor =
		false

	Button.Parent =
		Main

	local BC =
		Instance.new(
			"UICorner"
		)

	BC.CornerRadius =
		UDim.new(
			0,
			8
		)

	BC.Parent =
		Button

	local Label =
		Instance.new(
			"TextLabel"
		)

	Label.Size =
		UDim2.new(
			1,
			-55,
			1,
			0
		)

	Label.Position =
		UDim2.fromOffset(
			9,
			0
		)

	Label.BackgroundTransparency =
		1

	Label.Text =
		Text

	Label.TextColor3 =
		Color3.fromRGB(
			225,
			225,
			230
		)

	Label.TextSize =
		11

	Label.Font =
		Enum.Font.GothamMedium

	Label.TextXAlignment =
		Enum.TextXAlignment.Left

	Label.Parent =
		Button

	local State =
		Instance.new(
			"TextLabel"
		)

	State.Size =
		UDim2.fromOffset(
			38,
			21
		)

	State.Position =
		UDim2.new(
			1,
			-45,
			0.5,
			-10
		)

	State.BorderSizePixel =
		0

	State.TextSize =
		9

	State.Font =
		Enum.Font.GothamBold

	State.Parent =
		Button

	local SC =
		Instance.new(
			"UICorner"
		)

	SC.CornerRadius =
		UDim.new(
			1,
			0
		)

	SC.Parent =
		State

	local Value =
		Default

	local function Refresh()

		if Value then

			State.Text =
				"ON"

			State.BackgroundColor3 =
				Color3.fromRGB(
					32,
					54,
					39
				)

			State.TextColor3 =
				Color3.fromRGB(
					120,
					255,
					155
				)

		else

			State.Text =
				"OFF"

			State.BackgroundColor3 =
				Color3.fromRGB(
					54,
					37,
					40
				)

			State.TextColor3 =
				Color3.fromRGB(
					255,
					125,
					135
				)

		end
	end

	Refresh()

	Button.MouseButton1Click:
	Connect(function()

		Value =
			not Value

		Refresh()

		Callback(
			Value
		)

	end)
end

--==================================================
-- AUTO WIN
--==================================================

CreateToggle(
	"Auto Instant Win",
	52,
	true,

	function(Value)

		AutoInstantWin =
			Value

		if Value then

			task.spawn(
				InstantComplete
			)

		end
	end
)

--==================================================
-- AUTO RETRY
--==================================================

CreateToggle(
	"Auto Retry",
	91,
	true,

	function(Value)

		AutoRetry =
			Value

		if not Value then
			RetryBusy =
				false
		end

	end
)

--==================================================
-- WIN NOW
--==================================================

local WinButton =
	Instance.new(
		"TextButton"
	)

WinButton.Size =
	UDim2.new(
		1,
		-20,
		0,
		29
	)

WinButton.Position =
	UDim2.fromOffset(
		10,
		132
	)

WinButton.BackgroundColor3 =
	Color3.fromRGB(
		29,
		29,
		34
	)

WinButton.BorderSizePixel =
	0

WinButton.Text =
	"WIN NOW"

WinButton.TextColor3 =
	Color3.fromRGB(
		240,
		240,
		245
	)

WinButton.TextSize =
	10

WinButton.Font =
	Enum.Font.GothamBold

WinButton.AutoButtonColor =
	false

WinButton.Parent =
	Main

local WC =
	Instance.new(
		"UICorner"
	)

WC.CornerRadius =
	UDim.new(
		0,
		8
	)

WC.Parent =
	WinButton

WinButton.MouseButton1Click:
Connect(function()

	task.spawn(
		InstantComplete
	)

end)

--==================================================
-- DRAG
--==================================================

local Dragging =
	false

local DragStart
local StartPosition

Main.InputBegan:
Connect(function(Input)

	if Input.UserInputType
			== Enum.UserInputType.MouseButton1

		or Input.UserInputType
			== Enum.UserInputType.Touch
	then

		Dragging =
			true

		DragStart =
			Input.Position

		StartPosition =
			Main.Position

	end
end)

Main.InputEnded:
Connect(function(Input)

	if Input.UserInputType
			== Enum.UserInputType.MouseButton1

		or Input.UserInputType
			== Enum.UserInputType.Touch
	then

		Dragging =
			false

	end
end)

Track(
	UserInputService.InputChanged:
	Connect(function(Input)

		if not Dragging then
			return
		end

		if Input.UserInputType
				== Enum.UserInputType.MouseMovement

			or Input.UserInputType
				== Enum.UserInputType.Touch
		then

			local Delta =
				Input.Position
				- DragStart

			Main.Position =
				UDim2.new(
					StartPosition.X.Scale,

					StartPosition.X.Offset
						+ Delta.X,

					StartPosition.Y.Scale,

					StartPosition.Y.Offset
						+ Delta.Y
				)

		end
	end)
)

--==================================================
-- INITIAL WIN
--==================================================

task.delay(
	1,
	function()

		if Running()
			and AutoInstantWin
		then

			InstantComplete()

		end

	end
)

print(
	"[Salty] Auto Level loaded <3"
)
