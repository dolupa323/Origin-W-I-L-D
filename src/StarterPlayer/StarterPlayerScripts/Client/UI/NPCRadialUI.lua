-- NPCRadialUI.lua
-- NPC 상호작용 방사형 UI (육각형 카드 형태: 퀘스트, 대화하기, 닫기)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)

local Client = script.Parent.Parent
local InputManager = require(Client.InputManager)
local UITheme = require(Client.UI.UITheme)
local WindowManager = require(Client.Utils.WindowManager)

local NPCRadialUI = {}

--========================================
-- Constants
--========================================
local HEX_SIZE = 120
local CLOSE_HEX_SIZE = 90
local INTERACT_DISTANCE = 18
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
local currentNPC = nil
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
	if actionId == "Quest" then
		iconName = "FACILITY_ACTION_ACTIVATE"
	elseif actionId == "Talk" then
		iconName = "FACILITY_ACTION_MOVE"
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
	createHexBars(frame, slotSize, UITheme.Colors.BG_PANEL, 0.1, 2, 3, false)
	createHexBars(frame, slotSize, UITheme.Colors.BG_PANEL, 0, 3, 3, true)

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
	textLabel.TextSize = math.floor((actionId == "Close" and 11 or 15) * (slotSize / HEX_SIZE))
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
local function handleQuest()
	if not UIManager then UIManager = require(Client.UIManager) end
	NPCRadialUI.Close()
	-- 퀘스트 UI 열기 (추후 구현)
	if UIManager.openQuestList then
		UIManager.openQuestList(currentNPC)
	else
		UIManager.notify("퀘스트 시스템 준비 중입니다.")
	end
end

local function handleTalk()
	local npc = currentNPC
	if not npc then return end
	
	local quotes = {
		"여기서 사람을 다시 보게 될 줄은 몰랐군… 꽤 오래 혼자였어.",
		"처음엔 단순한 조사였는데… 상황이 이렇게 될 줄은 예상 못 했지.",
		"이 섬, 겉보기보다 훨씬 위험해. 공룡들 움직임이… 뭔가 달라.",
		"무작정 돌아다니지 마. 준비 없이 나가면 금방 당한다.",
		"난 여기서 계속 조사 중이야. 혹시 도와줄 생각 있나?"
	}
	local randomQuote = quotes[math.random(1, #quotes)]
	
	if not UIManager then UIManager = require(Client.UIManager) end
	
	if UIManager then
		UIManager.notify(string.format("%s: %s", npc.Name, randomQuote))
	end
	NPCRadialUI.Close()
end

--========================================
-- Public API
--========================================
function NPCRadialUI.Init(uiManager)
	UIManager = uiManager
end

function NPCRadialUI.Open(npcModel)
	if isOpen then NPCRadialUI.Close(); return end
	if tick() - lastCloseTime < 0.3 then return end
	if not npcModel then return end

	if not UIManager then UIManager = require(Client.UIManager) end
	InputManager.setUIOpen(true)
	UIManager.hideInteractPrompt()

	currentNPC = npcModel
	isOpen = true

	local viewportSize = workspace.CurrentCamera.ViewportSize
	local baseHeight = 1080
	local scale = math.clamp(viewportSize.Y / baseHeight, 0.6, 1.1)
	if UserInputService.TouchEnabled then
		scale = scale * 0.9 -- 모바일 보정
	end
	
	local scaledHexSize = math.floor(HEX_SIZE * scale)
	local scaledCloseSize = math.floor(CLOSE_HEX_SIZE * scale)
	local scaledRadius = 145 * scale

	local adornee = npcModel.PrimaryPart or npcModel:FindFirstChildWhichIsA("BasePart") or npcModel
	
	billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "NPCRadialBillboard"
	billboardGui.Size = UDim2.new(0, math.floor(500 * scale), 0, math.floor(500 * scale))
	billboardGui.StudsOffset = Vector3.new(0, 2, 0) -- 머리 위쪽으로 약간 오프셋
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

	-- NPC 이름
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, math.floor(40 * scale))
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.BackgroundTransparency = 1
	title.Text = npcModel:GetAttribute("DisplayName") or npcModel.Name
	title.TextColor3 = UITheme.Colors.GOLD
	title.Font = UITheme.Fonts.TITLE
	title.TextSize = math.floor(22 * scale)
	title.TextStrokeTransparency = 0.5
	title.Parent = container

	-- 슬롯 배치 (삼각형 형태)
	
	-- 1. 퀘스트 (왼쪽 상단)
	local questBtn = createActionSlot(container, "Quest", "퀘스트", -scaledRadius * 0.86, -scaledRadius * 0.5, scaledHexSize)
	questBtn.MouseButton1Click:Connect(handleQuest)

	-- 2. 대화하기 (오른쪽 상단)
	local talkBtn = createActionSlot(container, "Talk", "대화하기", scaledRadius * 0.86, -scaledRadius * 0.5, scaledHexSize)
	talkBtn.MouseButton1Click:Connect(handleTalk)

	-- 3. 닫기 (하단)
	local closeBtn = createActionSlot(container, "Close", "닫기", 0, scaledRadius * 0.7, scaledCloseSize)
	closeBtn.MouseButton1Click:Connect(function() NPCRadialUI.Close() end)

	-- 거리 체크
	updateConn = RunService.Heartbeat:Connect(function()
		local char = player.Character
		if char and char.PrimaryPart and adornee then
			local dist = (char.PrimaryPart.Position - adornee.Position).Magnitude
			if dist > INTERACT_DISTANCE + 5 then
				NPCRadialUI.Close()
			end
		end
	end)
end

function NPCRadialUI.IsOpen()
	return isOpen
end

function NPCRadialUI.Close()
	if not isOpen then return end
	isOpen = false
	lastCloseTime = tick()

	if billboardGui then 
		billboardGui:Destroy()
		billboardGui = nil 
	end
	if updateConn then 
		updateConn:Disconnect()
		updateConn = nil 
	end

	currentNPC = nil
	InputManager.setUIOpen(false)
	WindowManager.close("NPC_RADIAL")
	
	task.defer(function()
		local InteractController = require(Client.Controllers.InteractController)
		if InteractController and InteractController.rebindDefaultKeys then
			InteractController.rebindDefaultKeys()
		end
	end)
end

return NPCRadialUI
