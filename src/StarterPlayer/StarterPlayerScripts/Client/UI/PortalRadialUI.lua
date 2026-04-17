-- PortalRadialUI.lua
-- 고대 포탈 상호작용 방사형 UI (육각형 카드 형태)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)

local Client = script.Parent.Parent
local InputManager = require(Client.InputManager)
local UITheme = require(Client.UI.UITheme)

local PortalRadialUI = {}

--========================================
-- Constants
--========================================
local HEX_SIZE = 110
local CLOSE_HEX_SIZE = 85
local INTERACT_DISTANCE = 22
local BILLBOARD_MAX_DIST = 60

local HEX_BAR_ROTATIONS = { 30, 90, 150 }
local HEX_BAR_W_RATIO = 0.88
local HEX_BAR_H_RATIO = 0.50

--========================================
-- State
--========================================
local player = Players.LocalPlayer
local billboardGui = nil
local isOpen = false
local currentPortalId = nil
local currentPortalData = nil
local currentIsReturn = false

local updateConn = nil
local UIManager = nil
local itemIconsFolder = nil
local lastCloseTime = 0

do
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		itemIconsFolder = assets:FindFirstChild("ItemIcons")
	end
end

--========================================
-- Helper: Hexagonal UI
--========================================
local function createHexBars(parent, hexSize, color, transparency, zIndex, padding, useCorner)
	padding = padding or 0
	if useCorner == nil then useCorner = true end
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
	if not itemIconsFolder then return nil end
	
	local iconName = nil
	if actionId == "Move" then
		iconName = "FACILITY_ACTION_MOVE"
	elseif actionId == "Activate" then
		iconName = "FACILITY_ACTION_ACTIVATE"
	elseif actionId == "Close" then
		iconName = "FACILITY_ACTION_CLOSE"
	end

	if not iconName then return nil end

	local asset = itemIconsFolder:FindFirstChild(iconName)
	if not asset then return nil end

	if asset:IsA("Decal") or asset:IsA("Texture") then return asset.Texture end
	if asset:IsA("ImageLabel") or asset:IsA("ImageButton") then return asset.Image end
	if asset:IsA("StringValue") then return asset.Value end

	return nil
end

local function createActionSlot(parent, actionId, labelText, posX, posY, size)
	local slotSize = size or HEX_SIZE

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

	local strokeBars = createHexBars(frame, slotSize, UITheme.Colors.BORDER_DIM, 0.4, 1, 0, true)
	createHexBars(frame, slotSize, UITheme.Colors.BG_PANEL, 0.1, 2, 3, false) -- ZIndex 2
	createHexBars(frame, slotSize, UITheme.Colors.BG_PANEL, 0, 3, 3, true)    -- ZIndex 3

	local iconImage = getActionIconImage(actionId)
	if iconImage and iconImage ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0, slotSize * 0.42, 0, slotSize * 0.42)
		icon.Position = UDim2.fromScale(0.5, actionId == "Close" and 0.42 or 0.38)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = iconImage
		icon.ZIndex = 5
		icon.Parent = frame
	elseif actionId == "Close" then
		local closeGlyph = Instance.new("TextLabel")
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
	textLabel.TextSize = actionId == "Close" and 11 or 14
	textLabel.ZIndex = 5
	textLabel.Parent = frame

	frame.MouseEnter:Connect(function()
		setHexBorderColor(strokeBars, UITheme.Colors.GOLD_SEL)
		TweenService:Create(frame, TweenInfo.new(0.1), {
			Size = UDim2.new(0, math.floor(slotSize * 1.08), 0, math.floor(slotSize * 1.08))
		}):Play()
	end)
	frame.MouseLeave:Connect(function()
		setHexBorderColor(strokeBars, UITheme.Colors.BORDER_DIM)
		TweenService:Create(frame, TweenInfo.new(0.1), {
			Size = UDim2.new(0, slotSize, 0, slotSize)
		}):Play()
	end)

	task.defer(function()
		TweenService:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, posX, 0.5, posY)
		}):Play()
	end)

	return frame
end

--========================================
-- Handlers
--========================================
local function handleMove()
	if not UIManager then UIManager = require(Client.UIManager) end
	PortalRadialUI.Close()
	UIManager.requestPortalTeleport()
end

local function handleActivate()
	if not UIManager then UIManager = require(Client.UIManager) end
	local data = currentPortalData
	PortalRadialUI.Close()
	-- 골드 투입 UI (기존 PortalUI를 개조)
	UIManager.openPortalGoldInput(data)
end

--========================================
-- Public API
--========================================
function PortalRadialUI:Init(uiManager)
	UIManager = uiManager
end

function PortalRadialUI:Open(portalData)
	if isOpen then self.Close(); return end
	if tick() - lastCloseTime < 0.3 then return end -- 닫은 직후 다시 열기 방지 (연타/서버 지연 대응)
	if not portalData then return end

	if not UIManager then UIManager = require(Client.UIManager) end
	InputManager.setUIOpen(true)
	UIManager.hideInteractPrompt()

	currentPortalId = portalData.portalId
	currentPortalData = portalData
	currentIsReturn = portalData.isReturn == true
	isOpen = true

	-- 포탈 오브젝트(Adornee) 찾기
	local portalSearchName = portalData.isReturn and portalData.returnPortalName or portalData.portalName
	local portalObj = portalSearchName and workspace:FindFirstChild(portalSearchName, true) or nil
	local adornee = (portalObj and (portalObj.PrimaryPart or portalObj:FindFirstChildWhichIsA("BasePart") or portalObj)) or (player.Character and player.Character.PrimaryPart)

	billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "PortalRadialBillboard"
	billboardGui.Size = UDim2.new(0, 500, 0, 500)
	billboardGui.StudsOffset = Vector3.new(0, 0, 0)
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

	-- 포탈 제목
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.BackgroundTransparency = 1
	title.Text = portalData.displayName or "고대 포탈"
	title.TextColor3 = UITheme.Colors.GOLD
	title.Font = UITheme.Fonts.TITLE
	title.TextSize = 20
	title.TextStrokeTransparency = 0.5
	title.Parent = container

	local actions = {}
	-- 1. 이동 버튼: 활성화(repaired) 되었거나 귀환 포탈인 경우
	if portalData.repaired or portalData.isReturn then
		table.insert(actions, { id = "Move", label = "이동", callback = handleMove })
	end

	-- 2. 활성화 버튼: 아직 활성화되지 않았고 귀환 포탈이 아닌 경우
	if not portalData.repaired and not portalData.isReturn then
		table.insert(actions, { id = "Activate", label = "활성화", callback = handleActivate })
	end

	-- 슬롯 배치
	local radius = 140
	local numActions = #actions

	for i, action in ipairs(actions) do
		local angleDeg = 0
		if numActions == 1 then
			angleDeg = -90
		else
			angleDeg = (i == 1) and -145 or -35
		end

		local angle = math.rad(angleDeg)
		local posX = math.cos(angle) * radius
		local posY = math.sin(angle) * (radius * 0.8)

		local btn = createActionSlot(container, action.id, action.label, posX, posY)
		btn.MouseButton1Click:Connect(action.callback)
	end

	-- 닫기 버튼
	local closeBtn = createActionSlot(container, "Close", "닫기", 0, 150, CLOSE_HEX_SIZE)
	closeBtn.MouseButton1Click:Connect(function() PortalRadialUI.Close() end)

	-- R키 토글 닫기 지원
	InputManager.bindKey(Enum.KeyCode.R, "PortalRadialToggle", function()
		PortalRadialUI.Close()
	end)

	-- 거리 체크
	updateConn = RunService.Heartbeat:Connect(function()
		local char = player.Character
		if char and char.PrimaryPart and adornee then
			local dist = (char.PrimaryPart.Position - adornee.Position).Magnitude
			if dist > INTERACT_DISTANCE + 5 then
				PortalRadialUI.Close()
			end
		end
	end)
end

function PortalRadialUI.Close()
	if not isOpen then return end
	isOpen = false
	lastCloseTime = tick()

	InputManager.unbindKey(Enum.KeyCode.R)

	if billboardGui then billboardGui:Destroy(); billboardGui = nil end
	if updateConn then updateConn:Disconnect(); updateConn = nil end

	currentPortalId = nil
	InputManager.setUIOpen(false)
end

return PortalRadialUI
