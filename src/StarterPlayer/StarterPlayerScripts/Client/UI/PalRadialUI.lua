-- PalRadialUI.lua
-- 팰(공룡) 상호작용 방사형 UI (채집 UI와 유사한 육각형 카드 형태)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)
local UITheme = require(Client.UI.UITheme)

local StorageController = require(Client.Controllers.StorageController)

local PalRadialUI = {}

--========================================
-- Constants
--========================================
local HEX_SIZE = 95
local CLOSE_HEX_SIZE = 78
local INTERACT_DISTANCE = (Balance.HARVEST_RANGE or 10) + 4
local BILLBOARD_MAX_DIST = 50

-- 6각형 바 비율
local HEX_BAR_ROTATIONS = { 30, 90, 150 }
local HEX_BAR_W_RATIO = 0.88
local HEX_BAR_H_RATIO = 0.50

--========================================
-- State
--========================================
local player = Players.LocalPlayer
local billboardGui = nil
local isOpen = false
local currentPalModel = nil

local updateConn = nil
local keyboardConn = nil

local UIManager = nil
local originalWalkSpeed = nil
local itemIconsFolder = nil

local ACTION_LAYOUT = {
	Mount = { x = 0, y = -132, size = HEX_SIZE },
	Recall = { x = -116, y = 44, size = HEX_SIZE },
	Bag = { x = 116, y = 44, size = HEX_SIZE },
	Close = { x = 0, y = 132, size = CLOSE_HEX_SIZE },
}

local ACTION_LAYOUT_NO_MOUNT = {
	Recall = { x = -92, y = 18, size = HEX_SIZE },
	Bag = { x = 92, y = 18, size = HEX_SIZE },
	Close = { x = 0, y = 124, size = CLOSE_HEX_SIZE },
}

local ACTION_ICONS = {
	Mount = "PAL_ACTION_MOUNT",
	Recall = "PAL_ACTION_RECALL",
	Bag = "PAL_ACTION_BAG",
	Close = "PAL_ACTION_CLOSE",
}

do
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		itemIconsFolder = assets:FindFirstChild("ItemIcons")
	end
end

--========================================
-- 6각형 UI 헬퍼
--========================================

local function createHexBars(parent, hexSize, color, transparency, zIndex, padding, useCorner)
	padding = padding or 0
	if useCorner == nil then
		useCorner = true
	end
	local barW = hexSize * HEX_BAR_W_RATIO - padding * 2
	local barH = hexSize * HEX_BAR_H_RATIO - padding
	local bars = {}
	for _, rot in ipairs(HEX_BAR_ROTATIONS) do
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(0, barW, 0, barH)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Rotation = rot
		bar.BackgroundColor3 = color
		bar.BackgroundTransparency = transparency
		bar.BorderSizePixel = 0
		bar.ZIndex = zIndex
		bar.Parent = parent
		if useCorner then
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 4)
			c.Parent = bar
		end
		table.insert(bars, bar)
	end
	return bars
end

local function setHexBorderColor(strokeBars, color)
	for _, bar in ipairs(strokeBars) do
		if bar and bar.Parent then
			bar.BackgroundColor3 = color
		end
	end
end

local function getActionIconImage(actionId)
	if not itemIconsFolder then
		return nil
	end

	local iconName = ACTION_ICONS[actionId]
	if not iconName or iconName == "" then
		return nil
	end

	local asset = itemIconsFolder:FindFirstChild(iconName)
	if not asset then
		return nil
	end

	if asset:IsA("Decal") or asset:IsA("Texture") then
		return asset.Texture
	end
	if asset:IsA("ImageLabel") or asset:IsA("ImageButton") then
		return asset.Image
	end
	if asset:IsA("StringValue") then
		return asset.Value
	end

	return nil
end

local function createActionSlot(parent, actionId, labelText, layoutOverride)
	local layoutSource = layoutOverride or ACTION_LAYOUT
	local layout = layoutSource[actionId] or { x = 0, y = 0, size = HEX_SIZE }
	local slotSize = layout.size or HEX_SIZE

	local frame = Instance.new("TextButton")
	frame.Name = "Action_" .. actionId
	frame.Size = UDim2.new(0, slotSize, 0, slotSize)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Text = ""
	frame.AutoButtonColor = false
	frame.Parent = parent

	local strokeBars = createHexBars(frame, slotSize, UITheme.Colors.BORDER_DIM, 0, 1, 0, true)
	createHexBars(frame, slotSize, UITheme.Colors.BG_PANEL, 0, 1, 3, false)
	createHexBars(frame, slotSize, UITheme.Colors.BG_PANEL, 0, 2, 3, true)

	local iconImage = getActionIconImage(actionId)
	if iconImage and iconImage ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0, slotSize * 0.34, 0, slotSize * 0.34)
		icon.Position = UDim2.fromScale(0.5, actionId == "Close" and 0.42 or 0.38)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = iconImage
		icon.ZIndex = 5
		icon.Parent = frame
	elseif actionId == "Close" then
		local closeGlyph = Instance.new("TextLabel")
		closeGlyph.Name = "CloseGlyph"
		closeGlyph.Size = UDim2.new(0, slotSize * 0.34, 0, slotSize * 0.34)
		closeGlyph.Position = UDim2.fromScale(0.5, 0.4)
		closeGlyph.AnchorPoint = Vector2.new(0.5, 0.5)
		closeGlyph.BackgroundTransparency = 1
		closeGlyph.Text = "X"
		closeGlyph.TextColor3 = UITheme.Colors.DIM
		closeGlyph.Font = UITheme.Fonts.TITLE
		closeGlyph.TextSize = math.floor(slotSize * 0.32)
		closeGlyph.ZIndex = 5
		closeGlyph.Parent = frame
	end

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(0.9, 0.3)
	textLabel.Position = UDim2.fromScale(0.5, actionId == "Close" and 0.7 or 0.74)
	textLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = labelText
	textLabel.Font = UITheme.Fonts.NORMAL
	textLabel.TextColor3 = UITheme.Colors.WHITE
	textLabel.TextSize = actionId == "Close" and 11 or 12
	textLabel.ZIndex = 5
	textLabel.Parent = frame

	frame.MouseEnter:Connect(function()
		setHexBorderColor(strokeBars, UITheme.Colors.GOLD_SEL)
		TweenService:Create(frame, TweenInfo.new(0.1), {
			Size = UDim2.new(0, math.floor(slotSize * 1.05), 0, math.floor(slotSize * 1.05))
		}):Play()
	end)
	frame.MouseLeave:Connect(function()
		setHexBorderColor(strokeBars, UITheme.Colors.BORDER_DIM)
		TweenService:Create(frame, TweenInfo.new(0.1), {
			Size = UDim2.new(0, slotSize, 0, slotSize)
		}):Play()
	end)

	task.defer(function()
		local targetPos = UDim2.new(0.5, layout.x, 0.5, layout.y)
		TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = targetPos
		}):Play()
	end)

	return {
		frame = frame,
		strokeBars = strokeBars,
	}
end

--========================================
-- Helpers
--========================================

local function setPalMovementPaused(isPaused)
	if not currentPalModel then return end
	local humanoid = currentPalModel:FindFirstChildOfClass("Humanoid")
	
	if isPaused then
		if humanoid then
			originalWalkSpeed = humanoid.WalkSpeed
			humanoid.WalkSpeed = 0
		end
		-- 로컬에서 강제 위치 고정 (서버 업데이트에 의한 밀림 방지)
		local hrp = currentPalModel.PrimaryPart or currentPalModel:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.Anchored = true
		end
	else
		if humanoid and originalWalkSpeed ~= nil then
			humanoid.WalkSpeed = originalWalkSpeed
		end
		local hrp = currentPalModel.PrimaryPart or currentPalModel:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.Anchored = false
		end
	end
end

local function handleRecall()
	local ok, _res = NetClient.Request("Party.Recall.Request")
	if ok then
		if UIManager then UIManager.notify("공룡을 소환 해제했습니다.", Color3.fromRGB(150, 255, 150)) end
	end
	PalRadialUI.Close()
end

local function handleBag()
	local palUID = currentPalModel:GetAttribute("PalUID")
	if palUID then
		StorageController.openStorage("PAL_" .. palUID)
	else
		if UIManager then UIManager.notify("가방 정보를 찾을 수 없습니다.", Color3.fromRGB(255, 100, 100)) end
	end
	PalRadialUI.Close()
end

local function handleMount()
	local ok, err = NetClient.Request("Party.Mount.Request", {})
	if ok then
		if UIManager then
			UIManager.notify("공룡에 탑승했습니다. R 키로 내릴 수 있습니다.", Color3.fromRGB(120, 220, 255))
		end
		PalRadialUI.Close()
	else
		if UIManager then
			local message = "지금은 탈 수 없습니다."
			if err == "NOT_SUPPORTED" then
				message = "이 공룡은 아직 탈 수 없습니다."
			elseif err == "OUT_OF_RANGE" then
				message = "공룡에 더 가까이 가야 탑승할 수 있습니다."
			elseif err == "INVALID_STATE" then
				message = "현재 상태에서는 탑승할 수 없습니다."
			end
			UIManager.notify(message, Color3.fromRGB(255, 140, 120))
		end
	end
end

--========================================
-- Public API
--========================================

function PalRadialUI.IsOpen()
	return isOpen
end

function PalRadialUI.Open(palModel)
	if isOpen then PalRadialUI.Close(); return end

	if not UIManager then UIManager = require(Client.UIManager) end
	InputManager.setUIOpen(true)
	UIManager.hideInteractPrompt()

	currentPalModel = palModel
	isOpen = true
	setPalMovementPaused(true)

	local adornee = palModel.PrimaryPart or palModel:FindFirstChildWhichIsA("BasePart")
	
	billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "PalRadialBillboard"
	billboardGui.Size = UDim2.new(0, 450, 0, 450)
	billboardGui.StudsOffset = Vector3.new(0, 3, 0)
	billboardGui.AlwaysOnTop = true
	billboardGui.MaxDistance = BILLBOARD_MAX_DIST
	billboardGui.ClipsDescendants = false
	billboardGui.ResetOnSpawn = false
	billboardGui.Active = true
	billboardGui.Adornee = adornee
	billboardGui.Parent = player.PlayerGui

	local container = Instance.new("Frame")
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.Parent = billboardGui

	local isMountable = palModel:GetAttribute("CanMount") == true
	local layout = isMountable and ACTION_LAYOUT or ACTION_LAYOUT_NO_MOUNT

	local closeSlot = createActionSlot(container, "Close", "닫기", layout)
	closeSlot.frame.MouseButton1Click:Connect(function() PalRadialUI.Close() end)

	local recallSlot = createActionSlot(container, "Recall", "소환 해제", layout)
	local bagSlot = createActionSlot(container, "Bag", "가방", layout)

	recallSlot.frame.MouseButton1Click:Connect(handleRecall)
	bagSlot.frame.MouseButton1Click:Connect(handleBag)

	if isMountable then
		local mountSlot = createActionSlot(container, "Mount", "타기", layout)
		mountSlot.frame.MouseButton1Click:Connect(handleMount)
	end

	-- 키보드 바인딩 (R, Esc)
	keyboardConn = UserInputService.InputBegan:Connect(function(input, gp)
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.R then
			PalRadialUI.Close()
		end
	end)

	-- 거리 및 유효성 체크 루프
	updateConn = RunService.Heartbeat:Connect(function()
		if not palModel or not palModel.Parent or not adornee then
			PalRadialUI.Close()
			return
		end
		
		local char = player.Character
		if char and char.PrimaryPart then
			local dist = (char.PrimaryPart.Position - adornee.Position).Magnitude
			if dist > INTERACT_DISTANCE + 2 then
				PalRadialUI.Close()
				if UIManager then UIManager.notify("대상과 멀어졌습니다.", Color3.fromRGB(255, 180, 100)) end
			end
		end
	end)
end

function PalRadialUI.Close()
	if not isOpen then return end
	isOpen = false

	if billboardGui then billboardGui:Destroy(); billboardGui = nil end
	if updateConn then updateConn:Disconnect(); updateConn = nil end
	if keyboardConn then keyboardConn:Disconnect(); keyboardConn = nil end
	
	setPalMovementPaused(false)
	currentPalModel = nil
	InputManager.setUIOpen(false)
end

return PalRadialUI
