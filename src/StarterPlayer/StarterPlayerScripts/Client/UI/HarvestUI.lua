-- HarvestUI.lua
-- 채집 UI (R키 상호작용 → 모델 중심 BillboardGui → 6각형 슬롯 선택 → 프로그레스 → 인벤토리 획득)
-- v2: (1) 차오르는 프로그레스 모션 (2) 대기큐=소형 육각형 줄 (3) BillboardGui 3D 모델 중심 배치

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local AnimationIds = require(Shared.Config.AnimationIds)

local Client = script.Parent.Parent
local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)
local UITheme = require(Client.UI.UITheme)
local DataHelper = require(ReplicatedStorage.Shared.Util.DataHelper)
local UILocalizer = require(Client.Localization.UILocalizer)
local AnimationManager = require(Client.Utils.AnimationManager)

local HarvestUI = {}

--========================================
-- Constants
--========================================
local GATHER_TIME_OPTIMAL = 3
local GATHER_TIME_WRONG   = 15
local GATHER_TIME_BARE    = 30

local HEX_SIZE = 110          -- 6각형 외접원 지름 (메인 슬롯)
local HEX_GAP = 14
local MAX_RANGE = (Balance.HARVEST_RANGE or 10) + 5

-- 대기큐 미니 육각형 크기
local MINI_HEX_SIZE = 36
local MINI_HEX_GAP = 4

-- 6각형 바 비율 (pointy-top: 30°, 90°, 150°)
local HEX_BAR_ROTATIONS = { 30, 90, 150 }
local HEX_BAR_W_RATIO = 0.88   -- 바 폭 / HEX_SIZE
local HEX_BAR_H_RATIO = 0.50   -- 바 높이 / HEX_SIZE

-- BillboardGui 설정
local BILLBOARD_OFFSET = Vector3.new(0, 2.5, 0)
local BILLBOARD_MAX_DIST = 50

--========================================
-- State
--========================================
local player = Players.LocalPlayer
local billboardGui = nil   -- BillboardGui (3D 모델에 부착)
local isOpen = false
local currentNodeUID = nil
local currentNodeId = nil
local currentNodeModel = nil

local slots = {}  -- 각 슬롯 독립 큐 관리
local updateConn = nil
local escConn = nil
local nodeDestroyConn = nil  -- 노드 모델 파괴 감지

local gatherAnimTrack = nil

local UIManager = nil
local getItemIcon = nil

--========================================
-- Tool / GatherTime Calculation
--========================================
local function getEquippedToolType()
	local character = player.Character
	if not character then return nil end
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then return nil end
	local attr = tool:GetAttribute("ToolType")
	if attr and attr ~= "" then return attr end
	local itemData = DataHelper.GetData("ItemData", tool.Name)
	if itemData and itemData.type == "TOOL" then
		return itemData.optimalTool or itemData.id:upper()
	end
	return nil
end

local function estimateGatherTime(nodeData)
	local toolType = getEquippedToolType()
	local optimal = nodeData.optimalTool
	if not optimal or optimal == "" then
		return GATHER_TIME_OPTIMAL, "optimal"
	end
	if toolType and toolType:upper() == optimal:upper() then
		return GATHER_TIME_OPTIMAL, "optimal"
	elseif toolType then
		return GATHER_TIME_WRONG, "wrong"
	else
		return GATHER_TIME_BARE, "bare"
	end
end

-- 도구 이름 한국어 매핑
local TOOL_DISPLAY_NAMES = {
	AXE = "도끼",
	PICKAXE = "곡괭이",
	HOE = "괭이",
	SHOVEL = "삽",
	KNIFE = "칼",
	HAMMER = "망치",
	SICKLE = "낫",
}

--========================================
-- Animation (AnimationManager 패턴 사용)
--========================================
local function stopGatherAnimation()
	if gatherAnimTrack then
		gatherAnimTrack:Stop(0.1)
		gatherAnimTrack = nil
	end
end

local function playGatherAnimation()
	stopGatherAnimation()
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- [설계] R키 채집은 항상 맨손 채집 모션 사용 (도구 무관)
	local animName = AnimationIds.HARVEST.GATHER

	local ok, track = pcall(function()
		return AnimationManager.play(humanoid, animName, 0.05, nil, 1.0)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		gatherAnimTrack = track
	end
end

local function isAnyGathering()
	for _, slot in ipairs(slots) do
		if slot.isGathering then return true end
	end
	return false
end

local function syncAnimation()
	if isAnyGathering() then
		if not gatherAnimTrack then playGatherAnimation() end
	else
		stopGatherAnimation()
	end
end

--========================================
-- 6각형 UI 헬퍼
--========================================

--- 6각형 배경 생성 (3개 회전 바 합성, pointy-top)
local function createHexBars(parent, hexSize, color, transparency, zIndex, padding)
	padding = padding or 0
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
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 4)
		c.Parent = bar
		table.insert(bars, bar)
	end
	return bars
end

--- 6각형 프로그레스 오버레이 (ClipsDescendants + 3-bar hex, 아래→위 차오르는 채움)
local function createHexProgressClip(parent, hexSize)
	-- 클립 프레임: 아래에서 시작, 높이가 0→hexSize로 트윈 (절대 픽셀 사용)
	local clip = Instance.new("Frame")
	clip.Name = "ProgressClip"
	clip.Size = UDim2.new(0, hexSize, 0, 0)      -- 높이 0부터 시작 (절대 픽셀)
	clip.Position = UDim2.new(0.5, 0, 1, 0)       -- 프레임 하단 중앙에 고정
	clip.AnchorPoint = Vector2.new(0.5, 1)         -- 하단 중앙 앵커
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.ZIndex = 3
	clip.Parent = parent

	-- 클립 안에 전체 크기 육각형을 배치 (클립 하단 기준 고정 위치)
	-- 클립이 커지면서 아래→위로 드러나는 효과
	local barW = hexSize * HEX_BAR_W_RATIO - 6
	local barH = hexSize * HEX_BAR_H_RATIO - 3
	for _, rot in ipairs(HEX_BAR_ROTATIONS) do
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(0, barW, 0, barH)
		-- 바 중심 = 클립 하단에서 hexSize/2 위 (= 부모 육각형의 중심)
		-- Scale Y=1 사용: 클립 높이가 변할 때 바가 클립 하단 기준으로 고정됨
		bar.Position = UDim2.new(0.5, 0, 1, -hexSize / 2)
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Rotation = rot
		bar.BackgroundColor3 = UITheme.Colors.GOLD_SEL
		bar.BackgroundTransparency = 0    -- 완전 불투명 (겹침 별모양 방지)
		bar.BorderSizePixel = 0
		bar.ZIndex = 3
		bar.Parent = clip
		Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 4)
	end

	return clip
end

--========================================
-- 미니 육각형 (대기큐용 — 본래 슬롯 축소판)
--========================================

--- 대기큐 미니 육각형 생성 (아이콘+이름+시간 포함한 축소판)
local function createMiniBadge(parent, badgeIndex, itemId, gatherTime)
	local itemInfo = DataHelper.GetData("ItemData", itemId)
	local displayName = itemInfo and (UILocalizer.LocalizeDataText("ItemData", itemId, "name", itemInfo.name) or itemInfo.name) or itemId

	local badge = Instance.new("Frame")
	badge.Name = "QueueBadge_" .. badgeIndex
	badge.Size = UDim2.new(0, MINI_HEX_SIZE, 0, MINI_HEX_SIZE)
	badge.BackgroundTransparency = 1
	badge.ZIndex = 8
	badge.Parent = parent

	-- 미니 6각형 테두리
	createHexBars(badge, MINI_HEX_SIZE, UITheme.Colors.BORDER_DIM, 0, 8, 0)
	-- 미니 6각형 배경
	createHexBars(badge, MINI_HEX_SIZE, UITheme.Colors.BG_PANEL, 0, 9, 2)

	-- 미니 아이콘
	local miniIcon = Instance.new("ImageLabel")
	miniIcon.Name = "MiniIcon"
	miniIcon.Size = UDim2.new(0, MINI_HEX_SIZE * 0.5, 0, MINI_HEX_SIZE * 0.5)
	miniIcon.Position = UDim2.new(0.5, 0, 0.35, 0)
	miniIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	miniIcon.BackgroundTransparency = 1
	miniIcon.ScaleType = Enum.ScaleType.Fit
	miniIcon.ZIndex = 10
	miniIcon.Parent = badge
	if getItemIcon then
		local iconImage = getItemIcon(itemId)
		if iconImage and iconImage ~= "" then
			miniIcon.Image = iconImage
		end
	end

	-- 미니 채집 시간
	local miniTime = Instance.new("TextLabel")
	miniTime.Name = "MiniTime"
	miniTime.Size = UDim2.new(1, 0, 0, 10)
	miniTime.Position = UDim2.new(0.5, 0, 0.72, 0)
	miniTime.AnchorPoint = Vector2.new(0.5, 0)
	miniTime.BackgroundTransparency = 1
	miniTime.TextColor3 = UITheme.Colors.GRAY
	miniTime.TextSize = 8
	miniTime.Font = UITheme.Fonts.NUM
	miniTime.Text = string.format("%.1fs", gatherTime)
	miniTime.ZIndex = 10
	miniTime.Parent = badge

	return badge
end

--========================================
-- 6각형 허니콤 배치 계산 (모델 중심으로 방사형)
--========================================

--- n개 슬롯을 허니콤 형태로 배치할 좌표 반환
--- 중심 (0,0) 기준, pointy-top 헥스 배치
local function getHoneycombPositions(numSlots, hexSize, gap)
	if numSlots <= 0 then return {} end
	local positions = {}

	-- 허니콤 축 간격 (pointy-top)
	local hStep = (hexSize + gap) * 0.866  -- horizontal = size * sqrt(3)/2
	local vStep = (hexSize + gap) * 0.75   -- vertical = size * 3/4

	-- ★ 모든 레이아웃에서 중앙을 비워 노드가 보이도록 링 형태 배치
	if numSlots == 1 then
		-- 1개: 위쪽에 배치 (중앙 비움)
		positions[1] = { x = 0, y = -vStep }
	elseif numSlots == 2 then
		-- 좌우 배치 (중앙 비움)
		positions[1] = { x = -hStep * 0.6, y = 0 }
		positions[2] = { x = hStep * 0.6, y = 0 }
	elseif numSlots == 3 then
		-- 120° 간격 링 (중앙 비움, 노드를 둘러쌈)
		local radius = vStep * 1.05
		for i = 1, 3 do
			local angle = math.rad(-90 + (i - 1) * 120)
			positions[i] = { x = math.cos(angle) * radius, y = math.sin(angle) * radius }
		end
	elseif numSlots == 4 then
		-- 90° 간격 마름모 링 (중앙 비움)
		positions[1] = { x = 0, y = -vStep }
		positions[2] = { x = -hStep, y = 0 }
		positions[3] = { x = hStep, y = 0 }
		positions[4] = { x = 0, y = vStep }
	elseif numSlots == 5 then
		-- 72° 간격 오각형 링 (중앙 비움)
		local radius = vStep * 1.1
		for i = 1, 5 do
			local angle = math.rad(-90 + (i - 1) * 72)
			positions[i] = { x = math.cos(angle) * radius, y = math.sin(angle) * radius }
		end
	elseif numSlots == 6 then
		-- 60° 간격 육각 링 (중앙 비움)
		positions[1] = { x = 0, y = -vStep }
		positions[2] = { x = -hStep, y = -vStep * 0.5 }
		positions[3] = { x = hStep, y = -vStep * 0.5 }
		positions[4] = { x = -hStep, y = vStep * 0.5 }
		positions[5] = { x = hStep, y = vStep * 0.5 }
		positions[6] = { x = 0, y = vStep }
	elseif numSlots == 7 then
		-- 중앙 1 + 6개 링 (7개는 중앙 채움 허용)
		positions[1] = { x = 0, y = 0 }
		positions[2] = { x = 0, y = -vStep }
		positions[3] = { x = -hStep, y = -vStep * 0.5 }
		positions[4] = { x = hStep, y = -vStep * 0.5 }
		positions[5] = { x = -hStep, y = vStep * 0.5 }
		positions[6] = { x = hStep, y = vStep * 0.5 }
		positions[7] = { x = 0, y = vStep }
	else
		-- 8개 이상: 원형 링 배치 (중앙 비움)
		local radius = hStep * math.max(1, numSlots / 6)
		for i = 1, numSlots do
			local angle = math.rad(-90 + (i - 1) * (360 / numSlots))
			positions[i] = {
				x = math.cos(angle) * radius,
				y = math.sin(angle) * radius,
			}
		end
	end

	return positions
end

--========================================
-- UI Construction (BillboardGui)
--========================================

--- 노드 모델의 월드 높이를 계산하여 BillboardGui 오프셋 결정
--- 나무 등 키 큰 모델도 시선 높이(지면 +3~4.5 studs)에 고정
local function getNodeTopOffset(nodeModel, adorneePart)
	if not nodeModel or not adorneePart then return BILLBOARD_OFFSET end

	local ok, result = pcall(function()
		-- 플레이어 캐릭터의 현재 높이 확보 (HumanoidRootPart 기준)
		local char = player.Character
		local playerY = (char and char:FindFirstChild("HumanoidRootPart")) and char.HumanoidRootPart.Position.Y or 3
		
		-- ★ 플레이어 눈높이 (지면에서 약 4.5~5 스터드 높이)
		-- HumanoidRootPart가 지면에서 약 3 스터드 위에 있으므로 +1.5~2를 가산
		local targetY = playerY + 1.8
		
		-- Adornee 파트 중심과의 차이 계산
		local offsetFromAdornee = targetY - adorneePart.Position.Y
		
		-- 너무 멀리 떨어지는 것 방지 (모델 근처에 머물게 함)
		local cf, size = 0, Vector3.new(0, 5, 0)
		if nodeModel:IsA("Model") then
			cf, size = nodeModel:GetBoundingBox()
		end
		local maxY = (nodeModel:IsA("BasePart") and nodeModel.Position.Y or cf.Position.Y) + (size.Y/2)
		local minY = (nodeModel:IsA("BasePart") and nodeModel.Position.Y or cf.Position.Y) - (size.Y/2)
		
		-- 최종 Y가 모델의 범위를 너무 벗어나지 않도록 보정 (최소 모델 하단 + 2)
		local finalY = math.clamp(targetY, minY + 2, maxY + 2)
		local finalOffset = finalY - adorneePart.Position.Y

		return { offset = finalOffset }
	end)

	if ok and result then
		return Vector3.new(0, result.offset, 0), true -- WorldSpace
	end
	return BILLBOARD_OFFSET, false
end

local function createSlotFrame(parent, index, itemData, count, gatherTime)
	local itemId = itemData.itemId
	local itemInfo = DataHelper.GetData("ItemData", itemId)
	local displayName = itemInfo and (UILocalizer.LocalizeDataText("ItemData", itemId, "name", itemInfo.name) or itemInfo.name) or itemId

	-- 6각형 컨테이너 (클릭 가능)
	local frame = Instance.new("TextButton")
	frame.Name = "Slot_" .. index
	frame.Size = UDim2.new(0, HEX_SIZE, 0, HEX_SIZE)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Text = ""
	frame.AutoButtonColor = false
	frame.Parent = parent

	-- 6각형 테두리 (바깥 — 골드 보더)
	createHexBars(frame, HEX_SIZE, UITheme.Colors.BORDER_DIM, 0, 1, 0)

	-- 6각형 배경 채움 (안쪽 — 어두운 패널)
	createHexBars(frame, HEX_SIZE, UITheme.Colors.BG_PANEL, 0, 2, 3)

	-- 6각형 프로그레스 오버레이 (ClipsDescendants — 아래→위 차오르는 모션)
	local progressClip = createHexProgressClip(frame, HEX_SIZE)

	-- 콘텐츠 레이어
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromScale(0.72, 0.72)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.BackgroundTransparency = 1
	content.ZIndex = 5
	content.Parent = frame

	-- 아이콘
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, HEX_SIZE * 0.45, 0, HEX_SIZE * 0.45)
	icon.Position = UDim2.new(0.5, 0, 0.3, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 6
	icon.Parent = content

	if getItemIcon then
		local iconImage = getItemIcon(itemId)
		if iconImage and iconImage ~= "" then
			icon.Image = iconImage
		end
	end

	-- 수량 뱃지 (우측 상단)
	local countBadge = Instance.new("TextLabel")
	countBadge.Name = "Count"
	countBadge.Size = UDim2.new(0, 22, 0, 18)
	countBadge.Position = UDim2.new(1, 0, 0, 0)
	countBadge.AnchorPoint = Vector2.new(1, 0)
	countBadge.BackgroundColor3 = UITheme.Colors.BG_DARK
	countBadge.BackgroundTransparency = 0.2
	countBadge.BorderSizePixel = 0
	countBadge.TextColor3 = UITheme.Colors.WHITE
	countBadge.TextSize = 12
	countBadge.Font = UITheme.Fonts.NUM
	countBadge.Text = tostring(count)
	countBadge.ZIndex = 7
	countBadge.Parent = content
	Instance.new("UICorner", countBadge).CornerRadius = UDim.new(0, 4)

	-- 아이템 이름
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "ItemName"
	nameLabel.Size = UDim2.new(1, 0, 0, 14)
	nameLabel.Position = UDim2.new(0.5, 0, 0.55, 0)
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = UITheme.Colors.INK
	nameLabel.TextSize = 11
	nameLabel.Font = UITheme.Fonts.NORMAL
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = displayName
	nameLabel.ZIndex = 6
	nameLabel.Parent = content

	-- 레벨+채집 시간 (ex: "Lv.28   3.5초")
	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "GatherTime"
	timeLabel.Size = UDim2.new(1, 0, 0, 12)
	timeLabel.Position = UDim2.new(0.5, 0, 0.73, 0)
	timeLabel.AnchorPoint = Vector2.new(0.5, 0)
	timeLabel.BackgroundTransparency = 1
	timeLabel.TextColor3 = UITheme.Colors.GRAY
	timeLabel.TextSize = 10
	timeLabel.Font = UITheme.Fonts.NUM
	timeLabel.Text = string.format("%.1f초", gatherTime)
	timeLabel.ZIndex = 6
	timeLabel.Parent = content

	-- 완료 체크마크
	local checkLabel = Instance.new("TextLabel")
	checkLabel.Name = "Check"
	checkLabel.Size = UDim2.fromScale(1, 1)
	checkLabel.Position = UDim2.fromScale(0.5, 0.5)
	checkLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	checkLabel.BackgroundTransparency = 1
	checkLabel.TextColor3 = UITheme.Colors.GREEN
	checkLabel.TextSize = 40
	checkLabel.Font = UITheme.Fonts.TITLE
	checkLabel.Text = "✓"
	checkLabel.Visible = false
	checkLabel.ZIndex = 8
	checkLabel.Parent = frame

	-- 슬롯 하단 진행도 바 (직관적 시간 표시)
	local progressBarBg = Instance.new("Frame")
	progressBarBg.Name = "ProgressBarBg"
	progressBarBg.Size = UDim2.new(0, HEX_SIZE * 0.7, 0, 6)
	progressBarBg.Position = UDim2.new(0.5, 0, 1, 2)
	progressBarBg.AnchorPoint = Vector2.new(0.5, 0)
	progressBarBg.BackgroundColor3 = UITheme.Colors.BG_DARK
	progressBarBg.BackgroundTransparency = 0.3
	progressBarBg.BorderSizePixel = 0
	progressBarBg.ZIndex = 7
	progressBarBg.Visible = false  -- 채집 시작 시 표시
	progressBarBg.Parent = frame
	Instance.new("UICorner", progressBarBg).CornerRadius = UDim.new(0, 3)

	local progressBarFill = Instance.new("Frame")
	progressBarFill.Name = "Fill"
	progressBarFill.Size = UDim2.new(0, 0, 1, 0)
	progressBarFill.Position = UDim2.new(0, 0, 0, 0)
	progressBarFill.BackgroundColor3 = UITheme.Colors.GOLD_SEL
	progressBarFill.BackgroundTransparency = 0
	progressBarFill.BorderSizePixel = 0
	progressBarFill.ZIndex = 8
	progressBarFill.Parent = progressBarBg
	Instance.new("UICorner", progressBarFill).CornerRadius = UDim.new(0, 3)

	-- 대기큐 컨테이너 (슬롯 아래에 미니 육각형이 줄서는 영역)
	local queueContainer = Instance.new("Frame")
	queueContainer.Name = "QueueContainer"
	queueContainer.Size = UDim2.new(0, HEX_SIZE, 0, MINI_HEX_SIZE + 4)
	queueContainer.Position = UDim2.new(0.5, 0, 1, 12)  -- 진행도 바 아래로 위치 조정
	queueContainer.AnchorPoint = Vector2.new(0.5, 0)
	queueContainer.BackgroundTransparency = 1
	queueContainer.ZIndex = 8
	queueContainer.Parent = frame

	-- 클릭 핸들러
	frame.MouseButton1Click:Connect(function()
		HarvestUI._onSlotClick(index)
	end)

	return {
		frame = frame,
		progressClip = progressClip,
		progressBarBg = progressBarBg,
		progressBarFill = progressBarFill,
		icon = icon,
		nameLabel = nameLabel,
		countLabel = countBadge,
		timeLabel = timeLabel,
		checkLabel = checkLabel,
		queueContainer = queueContainer,
		itemId = itemId,
		remainingCount = count,
		gatherTime = gatherTime,
		isGathering = false,
		isComplete = false,
		gatherTween = nil,
		progressBarTween = nil,
		badges = {},
	}
end

--========================================
-- 6각형 테두리 색 변경 헬퍼
--========================================
local function setHexBorderColor(slot, color)
	for _, child in ipairs(slot.frame:GetChildren()) do
		if child:IsA("Frame") and child.ZIndex == 1 then
			child.BackgroundColor3 = color
		end
	end
end

local function setProgressColor(slot, color, transparency)
	for _, child in ipairs(slot.progressClip:GetChildren()) do
		if child:IsA("Frame") then
			child.BackgroundColor3 = color
			child.BackgroundTransparency = transparency
		end
	end
end

--========================================
-- Queue Badge Management (미니 육각형 줄)
--========================================

local function refreshQueueLayout(slot)
	local container = slot.queueContainer
	if not container then return end
	local count = #slot.badges
	-- 미니 육각형들을 중앙 정렬하여 가로로 나열
	local totalW = count * MINI_HEX_SIZE + math.max(0, count - 1) * MINI_HEX_GAP
	local startX = (HEX_SIZE - totalW) / 2
	for i, badge in ipairs(slot.badges) do
		badge.Position = UDim2.new(0, startX + (i - 1) * (MINI_HEX_SIZE + MINI_HEX_GAP), 0, 0)
	end
end

local function addBadge(slot)
	local idx = #slot.badges + 1
	local badge = createMiniBadge(slot.queueContainer, idx, slot.itemId, slot.gatherTime)
	table.insert(slot.badges, badge)
	refreshQueueLayout(slot)
end

local function removeBadge(slot)
	if #slot.badges > 0 then
		local badge = table.remove(slot.badges, 1)
		badge:Destroy()
		refreshQueueLayout(slot)
	end
end

local function clearBadges(slot)
	for _, badge in ipairs(slot.badges) do
		badge:Destroy()
	end
	slot.badges = {}
end

--========================================
-- Gather Logic (Per-slot independent)
--========================================

local function isInRange()
	if not currentNodeModel then return false end
	local character = player.Character
	if not character then return false end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local nodePos
	if currentNodeModel:IsA("Model") then
		local ok, pivot = pcall(function() return currentNodeModel:GetPivot().Position end)
		if not ok then return false end
		nodePos = pivot
	elseif currentNodeModel:IsA("BasePart") then
		nodePos = currentNodeModel.Position
	else
		return false
	end

	local p1 = Vector2.new(hrp.Position.X, hrp.Position.Z)
	local p2 = Vector2.new(nodePos.X, nodePos.Z)
	return (p1 - p2).Magnitude <= MAX_RANGE
end

--- 단일 슬롯의 1회 채집 실행 (1클릭 = 1개)
function HarvestUI._runSingleGather(slotIndex)
	local slot = slots[slotIndex]
	if not slot or slot.isComplete or slot.remainingCount <= 0 then return end

	slot.isGathering = true
	setHexBorderColor(slot, UITheme.Colors.GOLD_SEL)
	syncAnimation()

	-- nodeUID를 캡처 (Close→재Open 시 이전 세션 값 보호)
	local capturedNodeUID = currentNodeUID

	task.spawn(function()
		-- 1. 서버에 채집 요청 (1개)
		local ok, result = NetClient.Request("Harvest.Gather.Request", {
			nodeUID = capturedNodeUID,
			itemId = slot.itemId,
		})

		if not ok then
			slot.isGathering = false
			setHexBorderColor(slot, UITheme.Colors.BORDER_DIM)
			syncAnimation()
			if UIManager then
				UIManager.notify("채집에 실패했습니다. 다시 시도해주세요.", Color3.fromRGB(255, 120, 120))
				warn("[HarvestUI] Gather failed:", tostring(result))
			end
			-- 현재 시도 배지 제거 + 남은 큐 처리
			removeBadge(slot)
			if #slot.badges > 0 then
				task.defer(function() HarvestUI._runSingleGather(slotIndex) end)
			end
			return
		end

		-- Close() 중 파괴된 Instance 접근 방지
		if not isOpen then
			slot.isGathering = false
			syncAnimation()
			return
		end

		local serverGatherTime = result.gatherTime or slot.gatherTime
		slot.gatherTime = serverGatherTime
		slot.timeLabel.Text = string.format("%.1f초", serverGatherTime)

		-- 2. 프로그레스 트윈: 아래→위 차오르는 모션
		--    ProgressClip의 Size.Y를 0→HEX_SIZE로 트윈 (절대 픽셀)
		slot.progressClip.Size = UDim2.new(0, HEX_SIZE, 0, 0)
		setProgressColor(slot, UITheme.Colors.GOLD_SEL, 0)
		if slot.gatherTween then slot.gatherTween:Cancel() end
		slot.gatherTween = TweenService:Create(slot.progressClip,
			TweenInfo.new(serverGatherTime, Enum.EasingStyle.Linear),
			{ Size = UDim2.new(0, HEX_SIZE, 0, HEX_SIZE) }
		)
		slot.gatherTween:Play()

		-- 2-B. 진행도 바 트윈 (슬롯 하단 직관적 바)
		slot.progressBarBg.Visible = true
		slot.progressBarFill.Size = UDim2.new(0, 0, 1, 0)
		if slot.progressBarTween then slot.progressBarTween:Cancel() end
		slot.progressBarTween = TweenService:Create(slot.progressBarFill,
			TweenInfo.new(serverGatherTime, Enum.EasingStyle.Linear),
			{ Size = UDim2.new(1, 0, 1, 0) }
		)
		slot.progressBarTween:Play()

		-- 3. 채집 시간 대기
		task.wait(serverGatherTime)

		-- 4. 범위/UI 유효성 체크
		if not isOpen or not currentNodeModel or not currentNodeModel.Parent or not isInRange() then
			slot.isGathering = false
			setHexBorderColor(slot, UITheme.Colors.BORDER_DIM)
			clearBadges(slot)
			syncAnimation()
			if isOpen then
				HarvestUI.Close()
				if UIManager then
					UIManager.notify("대상과 너무 멀어졌습니다.", Color3.fromRGB(255, 180, 100))
				end
			end
			return
		end

		-- 5. 서버에 채집 완료 (캡처된 nodeUID 사용)
		local ok2, result2 = NetClient.Request("Harvest.Gather.Complete", {
			nodeUID = capturedNodeUID,
			itemId = slot.itemId,
		})

		slot.isGathering = false
		setHexBorderColor(slot, UITheme.Colors.BORDER_DIM)

		if ok2 then
			-- 인벤토리 가득 참 알림
			if result2 and result2.inventoryFull then
				if UIManager then
					UIManager.notify("가방이 가득 찼습니다! 남은 아이템이 발 밑에 떨어졌습니다.", Color3.fromRGB(255, 140, 140))
				end
				-- 더 이상 채집 불가 → 모든 슬롯 완료 처리 후 닫기
				removeBadge(slot)
				for _, s in ipairs(slots) do
					s.remainingCount = 0
					s.countLabel.Text = "0"
					s.isComplete = true
					clearBadges(s)
				end
				slot.isGathering = false
				setHexBorderColor(slot, UITheme.Colors.BORDER_DIM)
				syncAnimation()
				task.delay(1.2, function()
					if isOpen then HarvestUI.Close() end
				end)
				return
			end

			-- 1개 채집 성공: 배지 제거 + 남은 수량 감소
			removeBadge(slot)
			slot.remainingCount = math.max(0, slot.remainingCount - 1)
			slot.countLabel.Text = tostring(slot.remainingCount)

			-- 서버 응답에 남은 횟수가 있으면 보정
			if result2 and result2.remainingGathers ~= nil then
				local serverLeft = result2.remainingGathers
				if serverLeft <= 0 then
					-- 서버는 노드 고갈됨 → 모든 슬롯 완료 처리
					for _, s in ipairs(slots) do
						s.remainingCount = 0
						s.countLabel.Text = "0"
						s.isComplete = true
						setProgressColor(s, UITheme.Colors.GREEN, 0)
						s.progressClip.Size = UDim2.new(0, HEX_SIZE, 0, HEX_SIZE)
						s.progressBarBg.Visible = false
						s.checkLabel.Visible = true
						clearBadges(s)
					end
					slot.isGathering = false
					setHexBorderColor(slot, UITheme.Colors.BORDER_DIM)
					syncAnimation()
					-- 잠시 후 자동 닫기
					task.delay(0.8, function()
						if isOpen then HarvestUI.Close() end
					end)
					return
				end
			end

			if slot.remainingCount <= 0 then
				-- 이 슬롯 완전 완료
				slot.isComplete = true
				setProgressColor(slot, UITheme.Colors.GREEN, 0)
				slot.progressClip.Size = UDim2.new(0, HEX_SIZE, 0, HEX_SIZE)
				slot.progressBarBg.Visible = false
				slot.checkLabel.Visible = true
				clearBadges(slot)
			else
				-- 프로그레스 초기화 (다음 채집을 위해)
				slot.progressClip.Size = UDim2.new(0, HEX_SIZE, 0, 0)
				slot.progressBarFill.Size = UDim2.new(0, 0, 1, 0)
				slot.progressBarBg.Visible = false
			end
		else
			removeBadge(slot)
			slot.progressClip.Size = UDim2.new(0, HEX_SIZE, 0, 0)
			slot.progressBarFill.Size = UDim2.new(0, 0, 1, 0)
			slot.progressBarBg.Visible = false
			if UIManager then
				UIManager.notify("채집에 실패했습니다. 다시 시도해주세요.", Color3.fromRGB(255, 120, 120))
				warn("[HarvestUI] Gather failed:", tostring(result2))
			end
		end

		syncAnimation()

		-- 6. 큐에 남은 배지가 있으면 다음 채집
		if not slot.isComplete and #slot.badges > 0 then
			HarvestUI._runSingleGather(slotIndex)
			return
		end

		-- 7. 모든 슬롯 완료 체크 → 자동 닫기
		local allDone = true
		for _, s in ipairs(slots) do
			if not s.isComplete then allDone = false; break end
		end
		if allDone then
			task.delay(0.8, function()
				if isOpen then HarvestUI.Close() end
			end)
		end
	end)
end

--- 슬롯 클릭 핸들러 (모든 클릭 = 배지 추가, 큰 육각형 = 진행 표시만)
function HarvestUI._onSlotClick(slotIndex)
	local slot = slots[slotIndex]
	if not slot or slot.isComplete or slot.remainingCount <= 0 then return end

	-- 총 예약 수 (현재 배지 수) >= 남은 수량이면 추가 불가
	if #slot.badges >= slot.remainingCount then return end

	-- 배지 추가 (1번째 클릭부터)
	addBadge(slot)

	-- 현재 채집 중이 아니면 즉시 시작
	if not slot.isGathering then
		HarvestUI._runSingleGather(slotIndex)
	end
end

--========================================
-- Range Check Update Loop
--========================================
local function onUpdateLoop()
	if not isOpen then return end
	-- 노드 모델이 파괴되었으면 UI 종료
	if not currentNodeModel or not currentNodeModel.Parent then
		HarvestUI.Close()
		if UIManager then
			UIManager.notify("대상이 사라졌습니다.", Color3.fromRGB(255, 180, 100))
		end
		return
	end
	if not isInRange() then
		HarvestUI.Close()
		if UIManager then
			UIManager.notify("대상과 너무 멀어졌습니다.", Color3.fromRGB(255, 180, 100))
		end
	end
end

--========================================
-- Public API
--========================================

function HarvestUI.Open(nodeUID, nodeId, nodeModel)
	if isOpen then HarvestUI.Close() end

	if not nodeModel then
		warn("[HarvestUI] nodeModel is nil")
		return
	end

	local nodeData = DataHelper.GetData("ResourceNodeData", nodeId)
	if not nodeData then
		warn("[HarvestUI] Unknown nodeId:", nodeId)
		return
	end

	currentNodeUID = nodeUID
	currentNodeId = nodeId
	currentNodeModel = nodeModel

	-- 기존 BillboardGui 제거
	if billboardGui then
		billboardGui:Destroy()
		billboardGui = nil
	end

	slots = {}

	-- 서버에 채집 가능 횟수 조회 (수량 불일치 방지)
	local serverRemaining = nil
	local serverGatherTimeOverride = nil
	local infoOk, infoResult = NetClient.Request("Harvest.Gather.Info", { nodeUID = nodeUID })
	if infoOk and infoResult then
		serverRemaining = infoResult.remaining  -- { [itemId] = count }
		serverGatherTimeOverride = infoResult.gatherTime
	end

	local localGatherTime, toolStatus = estimateGatherTime(nodeData)
	local gatherTime = serverGatherTimeOverride or localGatherTime
	local resources = nodeData.resources or {}

	-- 실제 표시할 아이템만 필터링 (서버 응답 기준)
	local displayResources = {}
	if serverRemaining then
		for _, resource in ipairs(resources) do
			local count = serverRemaining[resource.itemId] or 0
			if count > 0 then
				table.insert(displayResources, { resource = resource, count = count })
			end
		end
	else
		-- [수정] 서버 응답이 없으면 자의적으로 자원을 생성하지 않음 (확률 불일치 방지)
		-- 단, 개발 환경 등에서 서버 응답이 누락된 경우를 위해 경고만 출력
		warn("[HarvestUI] No server response for node resources. UID:", nodeUID)
	end
	local numItems = #displayResources

	-- 허니콤 위치 계산 (실제 표시 아이템 수 기준)
	local hexPositions = getHoneycombPositions(numItems, HEX_SIZE, HEX_GAP)

	-- 바운딩 박스 계산 (BillboardGui 크기 결정)
	local minX, minY, maxX, maxY = 0, 0, 0, 0
	for _, pos in ipairs(hexPositions) do
		if pos.x - HEX_SIZE / 2 < minX then minX = pos.x - HEX_SIZE / 2 end
		if pos.x + HEX_SIZE / 2 > maxX then maxX = pos.x + HEX_SIZE / 2 end
		if pos.y - HEX_SIZE / 2 < minY then minY = pos.y - HEX_SIZE / 2 end
		if pos.y + HEX_SIZE / 2 + MINI_HEX_SIZE + 8 > maxY then maxY = pos.y + HEX_SIZE / 2 + MINI_HEX_SIZE + 8 end
	end
	local bbWidth = (maxX - minX) + 40
	local bbHeight = (maxY - minY) + 60
	local centerX = (minX + maxX) / 2
	local centerY = (minY + maxY) / 2

	-- BillboardGui를 모델에 부착 (기둥 중심의 파트 탐색 강화)
	local adornee = nodeModel
	if nodeModel:IsA("Model") then
		-- 1. 이름으로 기둥 파트 검색
		local trunk = nodeModel:FindFirstChild("Trunk", true) or nodeModel:FindFirstChild("Base", true) or nodeModel:FindFirstChild("Wood", true)
		if not trunk then
			-- 2. 이름이 없으면 전체 바운딩 박스 중심(XZ)에 가장 가까운 파트 탐색
			local cf, size = nodeModel:GetBoundingBox()
			local centerPos = cf.Position
			local minHandDist = math.huge
			
			for _, p in ipairs(nodeModel:GetDescendants()) do
				if p:IsA("BasePart") then
					-- 수평 거리(XZ)만 계산하여 기둥 라인에 있는 파트 찾기
					local horizontalDist = (Vector3.new(p.Position.X, 0, p.Position.Z) - Vector3.new(centerPos.X, 0, centerPos.Z)).Magnitude
					if horizontalDist < minHandDist then
						minHandDist = horizontalDist
						trunk = p
					end
				end
			end
		end
		
		adornee = trunk or nodeModel.PrimaryPart or nodeModel:FindFirstChildWhichIsA("BasePart")
		if not adornee then
			warn("[HarvestUI] No BasePart in nodeModel:", nodeModel:GetFullName())
			adornee = nodeModel
		end
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HarvestBillboard"
	billboard.Size = UDim2.new(0, bbWidth, 0, bbHeight)

	-- 시선 높이 오프셋 계산 (나무 등 키 큰 모델 대응)
	local offset, isWorldSpace = getNodeTopOffset(nodeModel, adornee)
	if isWorldSpace then
		billboard.StudsOffsetWorldSpace = offset
	else
		billboard.StudsOffset = offset
	end

	billboard.AlwaysOnTop = true
	billboard.MaxDistance = BILLBOARD_MAX_DIST
	billboard.ClipsDescendants = false
	billboard.ResetOnSpawn = false
	billboard.Active = true
	billboard.Adornee = adornee
	billboard.Parent = player:FindFirstChild("PlayerGui")

	-- 타이틀 (노드 이름)
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 24)
	title.Position = UDim2.new(0.5, 0, 0, 2)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.TextColor3 = UITheme.Colors.GOLD
	title.TextSize = 16
	title.Font = UITheme.Fonts.TITLE
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextStrokeTransparency = 0.4
	title.TextStrokeColor3 = Color3.new(0, 0, 0)
	title.Parent = billboard
	local nodeName = UILocalizer.LocalizeDataText("ResourceNodeData", nodeId, "name", nodeData.name) or nodeData.name
	title.Text = nodeName

	-- 슬롯 컨테이너 (BillboardGui 내부)
	local slotContainer = Instance.new("Frame")
	slotContainer.Name = "SlotContainer"
	slotContainer.Size = UDim2.new(1, 0, 1, -28)
	slotContainer.Position = UDim2.new(0, 0, 0, 28)
	slotContainer.BackgroundTransparency = 1
	slotContainer.Parent = billboard

	-- 슬롯 생성 (허니콤 배치) — 카드 펼침 애니메이션 준비
	local slotFinalPositions = {}  -- { [slotIndex] = UDim2 }
	for i, entry in ipairs(displayResources) do
		local resource = entry.resource
		local count = entry.count

		local slotData = createSlotFrame(slotContainer, i, resource, count, gatherTime)

		local pos = hexPositions[i]
		local finalPos = UDim2.new(
			0.5, pos.x - centerX,
			0.5, pos.y - centerY
		)

		-- 카드 펼침: 초기에는 중앙에 모여있고, 축소 + 투명 상태
		slotData.frame.AnchorPoint = Vector2.new(0.5, 0.5)
		slotData.frame.Position = UDim2.new(0.5, 0, 0.5, 0) -- 중앙
		slotData.frame.Size = UDim2.new(0, HEX_SIZE * 0.3, 0, HEX_SIZE * 0.3) -- 축소
		slotData.frame.Rotation = -15 + (i - 1) * 10  -- 카드처럼 살짝 기울임

		table.insert(slots, slotData)
		slotFinalPositions[#slots] = finalPos
	end

	-- 채집 가능한 슬롯이 없으면 UI 열지 않음
	if #slots == 0 then
		billboard:Destroy()
		if UIManager then
			UIManager.notify("채집할 자원이 없습니다.", Color3.fromRGB(255, 180, 100))
		end
		currentNodeUID = nil
		currentNodeId = nil
		currentNodeModel = nil
		return
	end

	billboardGui = billboard
	isOpen = true
	InputManager.setUIOpen(true)

	-- ★ 카드 펼침 애니메이션: 중앙에서 각자 위치로 촤르르 펼쳐짐
	for idx, slot in ipairs(slots) do
		local finalPos = slotFinalPositions[idx]
		if finalPos then
			local delay = (idx - 1) * 0.07  -- 순차 딜레이
			task.delay(delay, function()
				if not isOpen then return end
				-- 크기 복원 + 위치 이동 + 회전 복원을 동시에 트윈
				local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				local sizeTween = TweenService:Create(slot.frame, tweenInfo, {
					Position = finalPos,
					Size = UDim2.new(0, HEX_SIZE, 0, HEX_SIZE),
					Rotation = 0,
				})
				sizeTween:Play()
			end)
		end
	end

	-- ★ 도구 안내 메시지 (잘못된/없는 도구로 채집 시)
	if toolStatus ~= "optimal" and UIManager then
		local optimal = nodeData.optimalTool
		local toolName = TOOL_DISPLAY_NAMES[optimal and optimal:upper()] or optimal or "도구"
		if toolStatus == "bare" then
			UIManager.notify(
				string.format("💡 %s(이)가 있다면 훨씬 빠르게 채집할 수 있을 거야!", toolName),
				Color3.fromRGB(255, 220, 100)
			)
		elseif toolStatus == "wrong" then
			UIManager.notify(
				string.format("💡 이건 %s(으)로 해야 빠를 텐데… 도구를 바꿔볼까?", toolName),
				Color3.fromRGB(255, 200, 80)
			)
		end
	end

	if updateConn then updateConn:Disconnect() end
	updateConn = RunService.Heartbeat:Connect(onUpdateLoop)

	-- 노드 모델 파괴 감지 (서버에서 Depleted 처리 시 모델 제거됨)
	if nodeDestroyConn then nodeDestroyConn:Disconnect() end
	nodeDestroyConn = nodeModel.AncestryChanged:Connect(function(_, newParent)
		if not newParent and isOpen then
			HarvestUI.Close()
			if UIManager then
				UIManager.notify("대상이 사라졌습니다.", Color3.fromRGB(255, 180, 100))
			end
		end
	end)

	if escConn then escConn:Disconnect() end
	escConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			HarvestUI.Close()
		elseif input.KeyCode == Enum.KeyCode.R then
			-- 채집 진행 중이면 R키 닫기 무시 (실수 방지)
			if not isAnyGathering() then
				HarvestUI.Close()
			end
		end
	end)
end

function HarvestUI.Close()
	if not isOpen then return end
	isOpen = false

	-- 모든 슬롯의 진행 중 트윈 취소 + 대기큐 정리
	for _, slot in ipairs(slots) do
		if slot.gatherTween then slot.gatherTween:Cancel() end
		if slot.progressBarTween then slot.progressBarTween:Cancel() end
		clearBadges(slot)
	end
	stopGatherAnimation()

	if billboardGui then
		billboardGui:Destroy()
		billboardGui = nil
	end

	InputManager.setUIOpen(false)

	if updateConn then updateConn:Disconnect(); updateConn = nil end
	if escConn then escConn:Disconnect(); escConn = nil end
	if nodeDestroyConn then nodeDestroyConn:Disconnect(); nodeDestroyConn = nil end

	currentNodeUID = nil
	currentNodeId = nil
	currentNodeModel = nil
	slots = {}
end

function HarvestUI.IsOpen()
	return isOpen
end

function HarvestUI.Init(uiManager)
	UIManager = uiManager
	getItemIcon = UIManager and UIManager.getItemIcon or nil
	print("[HarvestUI] Initialized (BillboardGui mode)")
end

return HarvestUI
