-- FacilityRadialUI.lua
-- 시설(건물) 상호작용 방사형 UI (육각형 카드 형태)

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
local DataHelper = require(ReplicatedStorage.Shared.Util.DataHelper)
local WindowManager = require(Client.Utils.WindowManager)

local FacilityRadialUI = {}

--========================================
-- Constants
--========================================
local HEX_SIZE = 110
local CLOSE_HEX_SIZE = 80
local INTERACT_DISTANCE = (Balance.HARVEST_RANGE or 10) + 6
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
local currentTarget = nil
local currentStructureId = nil

local updateConn = nil
local keyboardConn = nil

local UIManager = nil
local itemIconsFolder = nil

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

local function getActionIconImage(actionId, facilityData)
	if not itemIconsFolder then return nil end
	
	local iconName = nil
	if actionId == "Use" then
		iconName = "FACILITY_ACTION_USE"
	elseif actionId == "Remove" then
		iconName = "FACILITY_ACTION_REMOVE"
	elseif actionId == "Rest" then
		iconName = "FACILITY_ACTION_REST"
	elseif actionId == "Sleep" then
		iconName = "FACILITY_ACTION_SLEEP"
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

local function createActionSlot(parent, actionId, labelText, posX, posY, size, facilityData)
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

	local strokeBars = createHexBars(frame, slotSize, UITheme.Colors.BORDER_DIM, 0, 1, 0, true)
	createHexBars(frame, slotSize, UITheme.Colors.BG_PANEL, 0, 1, 3, false)
	createHexBars(frame, slotSize, UITheme.Colors.BG_PANEL, 0, 2, 3, true)

	local iconImage = getActionIconImage(actionId, facilityData)
	if iconImage and iconImage ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0, slotSize * 0.4, 0, slotSize * 0.4)
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
	textLabel.TextSize = math.floor((actionId == "Close" and 11 or 13) * (slotSize / HEX_SIZE))
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
-- Action Handlers
--========================================

local function getFacilityData(target)
	local facilityId = target:GetAttribute("FacilityId")
	if not facilityId then return nil end
	return DataHelper.GetData("FacilityData", facilityId)
end

local function handleUse()
	local data = getFacilityData(currentTarget)
	if not data then return end
	
	local structureId = currentStructureId
	FacilityRadialUI.Close()
	
	local fType = data.functionType
	if fType:find("CRAFTING") or fType == "COOKING" or fType:find("SMELTING") then
		local FacilityController = require(Client.Controllers.FacilityController)
		FacilityController.openFacility(structureId)
	elseif fType == "STORAGE" then
		local StorageController = require(Client.Controllers.StorageController)
		StorageController.openStorage(structureId)
	elseif fType == "BASE_CORE" then
		local TotemController = require(Client.Controllers.TotemController)
		TotemController.openTotem(structureId)
	end
end

local function handleRemove()
	local InteractController = require(Client.Controllers.InteractController)
	FacilityRadialUI.Close()
	InteractController.onFacilityRemovePress(true)
end

local function handleRest()
	FacilityRadialUI.Close()
	local InteractController = require(Client.Controllers.InteractController)
	InteractController.startRest()
end

local function handleSleep()
	local structureId = currentStructureId
	FacilityRadialUI.Close()
	local InteractController = require(Client.Controllers.InteractController)
	if InteractController.showSleepConfirm then
		InteractController.showSleepConfirm(structureId)
	end
end

--========================================
-- Public API
--========================================

function FacilityRadialUI.IsOpen()
	return isOpen
end

function FacilityRadialUI.Open(target)
	if isOpen then FacilityRadialUI.Close(); return end

	local data = getFacilityData(target)
	if not data then return end

	if not UIManager then UIManager = require(Client.UIManager) end
	InputManager.setUIOpen(true)
	UIManager.hideInteractPrompt()

	currentTarget = target
	currentStructureId = target:GetAttribute("StructureId") or target:GetAttribute("id") or target.Name
	isOpen = true
	
	local viewportSize = workspace.CurrentCamera.ViewportSize
	local baseHeight = 1080
	local scale = math.clamp(viewportSize.Y / baseHeight, 0.6, 1.1)
	if UserInputService.TouchEnabled then
		scale = scale * 0.9 -- 모바일은 살짝 더 작게 (기존에 너무 컸음)
	end
	
	local scaledHexSize = math.floor(HEX_SIZE * scale)
	local scaledCloseSize = math.floor(CLOSE_HEX_SIZE * scale)
	local scaledRadius = 135 * scale

	local adornee = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart") or target
	
	billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "FacilityRadialBillboard"
	billboardGui.Size = UDim2.new(0, math.floor(500 * scale), 0, math.floor(500 * scale))
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
	container.Active = true
	container.Parent = billboardGui

	-- 시설 이름 표시 (중앙)
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, math.floor(40 * scale))
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.BackgroundTransparency = 1
	title.Text = data.name or "시설"
	title.TextColor3 = UITheme.Colors.GOLD
	title.Font = UITheme.Fonts.TITLE
	title.TextSize = math.floor(18 * scale)
	title.TextStrokeTransparency = 0.4
	title.Parent = container

	-- 레이아웃 결정
	local fType = data.functionType
	local actions = {}
	
	-- 기본은 "제거" 항상 포함
	table.insert(actions, { id = "Remove", label = "제거", callback = handleRemove })

	if fType == "COOKING" then
		-- 모닥불: 제거, 휴식, 이용
		table.insert(actions, { id = "Rest", label = "휴식", callback = handleRest })
		table.insert(actions, { id = "Use", label = "이용", callback = handleUse })
	elseif fType == "RESPAWN" then
		-- 침대: 제거, 취침
		table.insert(actions, { id = "Sleep", label = "취침", callback = handleSleep })
	elseif fType:find("CRAFTING") or fType == "STORAGE" or fType == "BASE_CORE" or fType:find("SMELTING") then
		-- 제작대/보관함/토템: 제거, 이용
		table.insert(actions, { id = "Use", label = "이용", callback = handleUse })
	end

	-- 슬롯 생성
	local numActions = #actions
	
	for i, action in ipairs(actions) do
		local angleDeg = 0
		if numActions == 1 then
			angleDeg = -90
		elseif numActions == 2 then
			angleDeg = (i == 1) and -160 or -20
		elseif numActions == 3 then
			angleDeg = (i == 1) and -160 or (i == 2 and -90 or -20)
		else
			angleDeg = (i - 1) * (360 / numActions) - 90
		end
		
		local angle = math.rad(angleDeg)
		local posX = math.cos(angle) * scaledRadius
		local posY = math.sin(angle) * (scaledRadius * 0.8)
		
		local btn = createActionSlot(container, action.id, action.label, posX, posY, scaledHexSize, data)
		btn.MouseButton1Click:Connect(action.callback)
	end

	-- 닫기 버튼 (중앙 아래)
	local closeBtn = createActionSlot(container, "Close", "닫기", 0, 160 * scale, scaledCloseSize)
	closeBtn.MouseButton1Click:Connect(function() FacilityRadialUI.Close() end)

	-- 거리 체크
	updateConn = RunService.Heartbeat:Connect(function()
		if not target or not target.Parent then
			FacilityRadialUI.Close()
			return
		end
		
		local char = player.Character
		if char and char.PrimaryPart then
			local dist = (char.PrimaryPart.Position - adornee.Position).Magnitude
			if dist > INTERACT_DISTANCE + 4 then
				FacilityRadialUI.Close()
				if UIManager then UIManager.notify("대상과 멀어졌습니다.", Color3.fromRGB(255, 180, 100)) end
			end
		end
	end)
end

function FacilityRadialUI.Close()
	if not isOpen then return end
	isOpen = false

	if billboardGui then billboardGui:Destroy(); billboardGui = nil end
	if updateConn then updateConn:Disconnect(); updateConn = nil end
	
	currentTarget = nil
	currentStructureId = nil
	InputManager.setUIOpen(false)
	WindowManager.close("FACILITY_RADIAL")
end

return FacilityRadialUI
