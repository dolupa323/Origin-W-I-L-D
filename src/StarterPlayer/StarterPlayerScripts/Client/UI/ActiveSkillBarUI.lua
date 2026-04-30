-- ActiveSkillBarUI.lua
-- 액티브 스킬 바 HUD (우하단 6각형 역삼각형 배치)
-- 키: Q / F / V (또는 모바일 터치)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Data = ReplicatedStorage:WaitForChild("Data")
local SkillTreeData = require(Data.SkillTreeData)

local Client = script.Parent.Parent
local UI = script.Parent
local Theme = require(UI.UITheme)
local Utils = require(UI.UIUtils)

local Controllers = Client:WaitForChild("Controllers")
local SkillController = require(Controllers.SkillController)
local MovementController = require(Controllers.MovementController)

local C = Theme.Colors
local F = Theme.Fonts
local isMobile = UserInputService.TouchEnabled or (game:GetService("RunService"):IsStudio() and (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X <= 1024))
local ActiveSkillBarUI = {}

--========================================
-- Constants
--========================================
local HEX_SIZE = isMobile and 96 or 88
local HEX_GAP = isMobile and 44 or 40
local SLOT_COUNT = 4
local KEY_LABELS = { "Q", "F", "V", "Ctrl" }
local COOLDOWN_COLOR = Color3.fromRGB(0, 0, 0)
local BORDER_READY = Color3.fromRGB(80, 80, 70)

local CAPTURE_KEY = "G"
local CAPTURE_SCAN_RANGE = Balance and Balance.CAPTURE_RANGE or 30
local CAPTURE_DISABLED_TRANSPARENCY = 0.7
local CAPTURE_ACTIVE_COLOR = Color3.fromRGB(255, 200, 40) -- 활성화 시 보더 색 (노란색)
local INTERACT_DISABLED_TRANSPARENCY = 0.5
local INTERACT_ACTIVE_COLOR = Color3.fromRGB(255, 255, 255)

-- 3-bar 합성 6각형 상수 (Pointy-Topped 형태로 수정)
local HEX_BAR_ROTATIONS = { 0, 60, 120 }
local HEX_BAR_W_RATIO = 0.88
local HEX_BAR_H_RATIO = 0.50

--========================================
-- Refs
--========================================
local barFrame
local slotRefs = {}
local updateConnection
local captureRef = nil  -- 포획 버튼 참조
local interactRef = nil -- 상호작용 버튼 참조
local captureTarget = nil -- 현재 포획 가능한 크리처 모델
local captureBlinkTweens = {} -- 깜빡임 트윈 참조
local NetClient = require(Client.NetClient)

--========================================
-- Icon Helper
--========================================
local SkillIcons = nil
do
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		SkillIcons = assets:FindFirstChild("SkillIcons")
	end
end

local function _getIconImage(iconName)
	if not SkillIcons or not iconName then return nil end
	local asset = SkillIcons:FindFirstChild(iconName)
	if not asset then return nil end
	if asset:IsA("Decal") or asset:IsA("Texture") then return asset.Texture end
	if asset:IsA("ImageLabel") or asset:IsA("ImageButton") then return asset.Image end
	if asset:IsA("StringValue") then return asset.Value end
	return nil
end

--========================================
-- Target Helper (createBar보다 앞에 선언 — closure 참조 필요)
--========================================
local InputManager = require(Client.InputManager)

--- 스킬 사용 전: 정면 방향으로 타겟 탐색 (캠릭터 회전 없음)
local function _orientAndGetTarget(): string?
	local ok, CombatController = pcall(function()
		return require(Controllers.CombatController)
	end)
	if ok and CombatController and CombatController.getCurrentTarget then
		return CombatController.getCurrentTarget()
	end
	return nil
end

--========================================
-- Hex Helper: 3-bar 합성으로 6각형 생성 (HarvestUI와 동일)
--========================================
local function _createHexShape(parent, hexSize, color, transparency, zIndex, padding)
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

local function _setHexBarsColor(bars, color)
	for _, bar in ipairs(bars) do
		bar.BackgroundColor3 = color
	end
end

local function _setHexBarsTransparency(bars, t)
	for _, bar in ipairs(bars) do
		bar.BackgroundTransparency = t
	end
end

--========================================
-- Create Hexagonal Skill Cluster
--========================================
local function createBar(parent)
	local isMobile = UserInputService.TouchEnabled or (game:GetService("RunService"):IsStudio() and (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X <= 1024))
	
	-- 조화로운 육각형 맞물림을 위해 크기와 갭 조절
	local HEX_SIZE = isMobile and 84 or 76
	local HEX_GAP = 4 -- 전방향 동일한 두께의 틈새를 위해 양수 갭 사용

	-- 정육각형의 실제 가로세로 비율(Width 0.88 : Height 1.01)에 기반한 완벽한 1:1 간격 공식
	local hexBase = HEX_SIZE + HEX_GAP
	local dx = hexBase * 0.44 -- 가로 간격
	local dy = hexBase * 0.76 -- 세로 간격

	-- 컴포넌트들의 바운딩 박스 (Q,F 상단 / Cap, V 하단)
	-- 가로: capX (cx-2*dx) ~ F (cx+dx) => 폭 3*dx + HEX_SIZE
	-- 세로: Q (cy-dy/2) ~ V (cy+dy/2) => 높이 dy + HEX_SIZE
	-- 육각형 배치를 위한 확장된 계산 (Q, F 상단 / Cap, V 중단 / Roll 하단)
	local areaW = 4 * dx + HEX_SIZE + 20
	local areaH = 2 * dy + HEX_SIZE + 20
	local cx = 3 * dx + HEX_SIZE / 2 + 10
	local cy = 0.5 * dy + HEX_SIZE / 2 + 10

	barFrame = Utils.mkFrame({
		name = "ActiveSkillBar",
		size = UDim2.new(0, areaW, 0, areaH),
		pos = UDim2.new(1, isMobile and -10 or -8, 1, isMobile and -95 or -160), -- PC 모드 높이 추가 상향
		anchor = Vector2.new(1, 1),
		bgT = 1,
		parent = parent,
	})

	-- 기존 스킬 역삼각형 배치 (Cap은 Q자리 좌하단)
	local positions = {
		{x = cx - dx, y = cy - dy / 2}, -- Q (좌상)
		{x = cx + dx, y = cy - dy / 2}, -- F (우상)
		{x = cx,      y = cy + dy / 2}, -- V (중단 우)
		{x = cx - 3 * dx, y = cy + 1.5 * dy}, -- Roll (하단 좌)
	}

	for i = 1, SLOT_COUNT do
		local pos = positions[i]

		-- 슬롯 컨테이너 (채집 UI와 동일하게 HEX_SIZE 정확히 일치)
		local slotFrame = Instance.new("TextButton")
		slotFrame.Name = "SkillSlot" .. i
		slotFrame.Size = UDim2.new(0, HEX_SIZE, 0, HEX_SIZE)
		slotFrame.Position = UDim2.new(0, pos.x, 0, pos.y)
		slotFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		slotFrame.BackgroundTransparency = 1
		slotFrame.Text = ""
		slotFrame.AutoButtonColor = false
		slotFrame.ZIndex = 0
		slotFrame.Parent = barFrame

		-- [층1] 보더 (HarvestUI 동일: BORDER_DIM, padding=0)
		local strokeBars = _createHexShape(slotFrame, HEX_SIZE, C.BORDER_DIM, 0, 1, 0)

		-- [층1.5] 별모양 틈 채움 (bg와 같은 padding=3, UICorner 없이 → 직각 바가 별틈을 메움)
		do
			local p = 3
			local bw = HEX_SIZE * HEX_BAR_W_RATIO - p * 2
			local bh = HEX_SIZE * HEX_BAR_H_RATIO - p
			for _, rot in ipairs(HEX_BAR_ROTATIONS) do
				local bar = Instance.new("Frame")
				bar.Size = UDim2.new(0, bw, 0, bh)
				bar.Position = UDim2.fromScale(0.5, 0.5)
				bar.AnchorPoint = Vector2.new(0.5, 0.5)
				bar.Rotation = rot
				bar.BackgroundColor3 = C.BG_PANEL
				bar.BackgroundTransparency = 0
				bar.BorderSizePixel = 0
				bar.ZIndex = 1
				bar.Parent = slotFrame
			end
		end

		-- [층2] 배경 채움 (HarvestUI 동일: BG_PANEL, padding=3)
		local bgBars = _createHexShape(slotFrame, HEX_SIZE, C.BG_PANEL, 0, 2, 3)

		-- [층3] 스킬 아이콘
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0.5, 0, 0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0.5, 0)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ImageTransparency = 0
		icon.ZIndex = 3
		icon.Parent = slotFrame

		-- [층4] 쿨다운 오버레이 (HarvestUI 동일: padding=3)
		local cdBars = _createHexShape(slotFrame, HEX_SIZE, COOLDOWN_COLOR, 1, 4, 3)

		-- [층5] 쿨다운 텍스트
		local cdText = Utils.mkLabel({
			name = "CDText",
			size = UDim2.new(1, 0, 1, 0),
			text = "",
			ts = isMobile and 18 or 15,
			font = F.TITLE,
			color = C.WHITE,
			z = 5,
			parent = slotFrame,
		})

		-- [층6] 키 라벨 (좌측 상단)
		local keyLabel = Utils.mkLabel({
			name = "KeyLabel",
			size = UDim2.new(0, 24, 0, 24),
			pos = UDim2.new(0.15, 0, 0.12, 0),
			text = KEY_LABELS[i],
			ts = isMobile and 15 or 13,
			font = F.TITLE,
			color = C.WHITE,
			st = 0,
			ax = Enum.TextXAlignment.Left,
			ay = Enum.TextYAlignment.Top,
			z = 6,
			parent = slotFrame,
		})
		if isMobile then keyLabel.Visible = false end

		-- 터치/클릭 이벤트
		slotFrame.MouseButton1Click:Connect(function()
			if i == 4 then
				MovementController.performDodge()
			else
				SkillController.useSkillBySlot(i, _orientAndGetTarget())
			end
		end)

		slotRefs[i] = {
			frame = slotFrame,
			icon = icon,
			cooldownBars = cdBars,
			cooldownText = cdText,
			keyLabel = keyLabel,
			strokeBars = strokeBars,
			bgBars = bgBars,
			wasOnCooldown = false,
		}
	end

	--========================================
	-- 포획 버튼 (Q스킬 좌측 하단 대각선)
	--========================================
	do
		local capX = cx - 2 * dx
		local capY = cy + dy / 2

		local capFrame = Instance.new("TextButton")
		capFrame.Name = "CaptureButton"
		capFrame.Size = UDim2.new(0, HEX_SIZE, 0, HEX_SIZE)
		capFrame.Position = UDim2.new(0, capX, 0, capY)
		capFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		capFrame.BackgroundTransparency = 1
		capFrame.Text = ""
		capFrame.AutoButtonColor = false
		capFrame.ZIndex = 0
		capFrame.Visible = false
		capFrame.Parent = barFrame

		-- [층1] 보더
		local capStrokeBars = _createHexShape(capFrame, HEX_SIZE, C.BORDER_DIM, 0, 1, 0)

		-- [층1.5] 틈 채움
		do
			local p = 3
			local bw = HEX_SIZE * HEX_BAR_W_RATIO - p * 2
			local bh = HEX_SIZE * HEX_BAR_H_RATIO - p
			for _, rot in ipairs(HEX_BAR_ROTATIONS) do
				local bar = Instance.new("Frame")
				bar.Size = UDim2.new(0, bw, 0, bh)
				bar.Position = UDim2.fromScale(0.5, 0.5)
				bar.AnchorPoint = Vector2.new(0.5, 0.5)
				bar.Rotation = rot
				bar.BackgroundColor3 = C.BG_PANEL
				bar.BackgroundTransparency = 0
				bar.BorderSizePixel = 0
				bar.ZIndex = 1
				bar.Parent = capFrame
			end
		end

		-- [층2] 배경
		local capBgBars = _createHexShape(capFrame, HEX_SIZE, C.BG_PANEL, 0, 2, 3)

		-- [층3] 아이콘 (TAMING_TIER)
		local capIcon = Instance.new("ImageLabel")
		capIcon.Name = "Icon"
		capIcon.Size = UDim2.new(0.5, 0, 0.5, 0)
		capIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
		capIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		capIcon.BackgroundTransparency = 1
		capIcon.ScaleType = Enum.ScaleType.Fit
		capIcon.ZIndex = 3
		capIcon.Parent = capFrame
		local tamingImg = _getIconImage("TAMING_TIER")
		capIcon.Image = tamingImg or ""

		-- [층6] 키 라벨
		local capKeyLabel = Utils.mkLabel({
			name = "KeyLabel",
			size = UDim2.new(0, 24, 0, 24),
			pos = UDim2.new(0.15, 0, 0.12, 0),
			text = CAPTURE_KEY,
			ts = isMobile and 15 or 13,
			font = F.TITLE,
			color = C.WHITE,
			st = 0,
			ax = Enum.TextXAlignment.Left,
			ay = Enum.TextYAlignment.Top,
			z = 6,
			parent = capFrame,
		})
		if isMobile then capKeyLabel.Visible = false end

		-- 클릭 이벤트
		capFrame.MouseButton1Click:Connect(function()
			ActiveSkillBarUI._tryCapture()
		end)

		captureRef = {
			frame = capFrame,
			icon = capIcon,
			strokeBars = capStrokeBars,
			bgBars = capBgBars,
			keyLabel = capKeyLabel,
			active = false,
		}
	end

	--========================================
	-- 상호작용 버튼 (포획 버튼 좌측)
	--========================================
	do
		local intX = cx - 4 * dx
		local intY = cy + 0.5 * dy

		local intFrame = Instance.new("TextButton")
		intFrame.Name = "InteractButton"
		intFrame.Size = UDim2.new(0, HEX_SIZE, 0, HEX_SIZE)
		intFrame.Position = UDim2.new(0, intX, 0, intY)
		intFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		intFrame.BackgroundTransparency = 1
		intFrame.Text = ""
		intFrame.AutoButtonColor = false
		intFrame.ZIndex = 0
		intFrame.Parent = barFrame

		-- [층1] 보더
		local intStrokeBars = _createHexShape(intFrame, HEX_SIZE, C.BORDER_DIM, 0, 1, 0)

		-- [층1.5] 틈 채움
		do
			local p = 3
			local bw = HEX_SIZE * HEX_BAR_W_RATIO - p * 2
			local bh = HEX_SIZE * HEX_BAR_H_RATIO - p
			for _, rot in ipairs(HEX_BAR_ROTATIONS) do
				local bar = Instance.new("Frame")
				bar.Size = UDim2.new(0, bw, 0, bh)
				bar.Position = UDim2.fromScale(0.5, 0.5)
				bar.AnchorPoint = Vector2.new(0.5, 0.5)
				bar.Rotation = rot
				bar.BackgroundColor3 = C.BG_PANEL
				bar.BackgroundTransparency = 0
				bar.BorderSizePixel = 0
				bar.ZIndex = 1
				bar.Parent = intFrame
			end
		end

		-- [층2] 배경
		local intBgBars = _createHexShape(intFrame, HEX_SIZE, C.BG_PANEL, 0, 2, 3)

		-- [층3] 아이콘 (HUD_ACTION_INTERACT)
		local intIcon = Instance.new("ImageLabel")
		intIcon.Name = "Icon"
		intIcon.Size = UDim2.new(0.55, 0, 0.55, 0)
		intIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
		intIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		intIcon.BackgroundTransparency = 1
		intIcon.ScaleType = Enum.ScaleType.Fit
		intIcon.ZIndex = 3
		intIcon.Parent = intFrame
		local intImg = _getIconImage("HUD_ACTION_INTERACT")
		intIcon.Image = intImg or ""

		-- [층6] 키 라벨
		local intKeyLabel = Utils.mkLabel({
			name = "KeyLabel",
			size = UDim2.new(0, 24, 0, 24),
			pos = UDim2.new(0.15, 0, 0.12, 0),
			text = "R",
			ts = isMobile and 15 or 13,
			font = F.TITLE,
			color = C.WHITE,
			st = 0,
			ax = Enum.TextXAlignment.Left,
			ay = Enum.TextYAlignment.Top,
			z = 6,
			parent = intFrame,
		})
		if isMobile then intKeyLabel.Visible = false end

		-- 클릭 이벤트
		intFrame.MouseButton1Click:Connect(function()
			local IC = require(Controllers.InteractController)
			if IC.onFacilityInteractPress then
				IC.onFacilityInteractPress()
			end
		end)

		interactRef = {
			frame = intFrame,
			icon = intIcon,
			strokeBars = intStrokeBars,
			bgBars = intBgBars,
			keyLabel = intKeyLabel,
			active = false,
		}
	end
end

--========================================
-- Capture: 포획 가능 크리처 탐색
--========================================
local function _getUnlockedCreatureSet()
	local unlocked = SkillController.getUnlockedSkills()
	local tamingSkills = {}
	for skillId, _ in pairs(unlocked) do
		if tostring(skillId):sub(1, 7) == "TAMING_" then
			table.insert(tamingSkills, skillId)
		end
	end
	if #tamingSkills == 0 then return nil end
	return SkillTreeData.GetUnlockedCreatures(tamingSkills)
end

local function _findCaptureTarget()
	local char = player.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	local creatureSet = _getUnlockedCreatureSet()
	if not creatureSet then return nil end

	local creaturesFolder = workspace:FindFirstChild("ActiveCreatures") or workspace:FindFirstChild("Creatures")
	if not creaturesFolder then return nil end

	local bestModel = nil
	local bestDist = CAPTURE_SCAN_RANGE + 1

	for _, model in ipairs(creaturesFolder:GetChildren()) do
		if not model:IsA("Model") then continue end
		local state = model:GetAttribute("State")
		local isDead = model:GetAttribute("IsDead")
		local hasCollapsed = model:GetAttribute("HasCollapsed")
		local creatureId = model:GetAttribute("CreatureId")

		local captureAttempted = model:GetAttribute("CaptureAttempted")

		-- 쓰러짐 상태 + 실제 사망 아님 + 포획 미시도 + 포획 해금된 크리처
		if state == "DEAD" and hasCollapsed == true and isDead ~= true and captureAttempted ~= true and creatureId then
			if creatureSet[creatureId] then
				local rootPart = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
				if rootPart then
					local dist = (rootPart.Position - hrp.Position).Magnitude
					if dist <= CAPTURE_SCAN_RANGE and dist < bestDist then
						bestDist = dist
						bestModel = model
					end
				end
			end
		end
	end

	return bestModel
end

local function _updateCaptureButton()
	if not captureRef then return end

	-- 포획 스킬 하나도 없으면 아예 숨김
	local creatureSet = _getUnlockedCreatureSet()
	if not creatureSet then
		captureRef.frame.Visible = false
		captureRef.active = false
		captureTarget = nil
		return
	end

	-- 쓰러진 포획 가능 크리처 탐색
	local target = _findCaptureTarget()
	captureTarget = target

	if target then
		-- 활성화 (노란색 깜빡임)
		captureRef.frame.Visible = true
		captureRef.active = true
		captureRef.icon.ImageTransparency = 0
		_setHexBarsTransparency(captureRef.bgBars, 0)
		-- 깜빡임 트윈 시작 (이미 실행 중이면 스킵)
		if #captureBlinkTweens == 0 then
			for _, bar in ipairs(captureRef.strokeBars) do
				bar.BackgroundColor3 = CAPTURE_ACTIVE_COLOR
				local tw = TweenService:Create(bar, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
					BackgroundColor3 = C.BORDER_DIM,
				})
				tw:Play()
				table.insert(captureBlinkTweens, tw)
			end
		end
	else
		-- 비활성 (회색) + 깜빡임 정지
		captureRef.frame.Visible = true
		captureRef.active = false
		captureRef.icon.ImageTransparency = CAPTURE_DISABLED_TRANSPARENCY
		for _, tw in ipairs(captureBlinkTweens) do
			tw:Cancel()
		end
		captureBlinkTweens = {}
		_setHexBarsColor(captureRef.strokeBars, C.BORDER_DIM)
		_setHexBarsTransparency(captureRef.bgBars, 0.3)
	end
end

local function _updateInteractButton()
	if not interactRef then return end
	
	local IC = require(Controllers.InteractController)
	local hasTarget = IC.currentTarget ~= nil

	if hasTarget then
		interactRef.active = true
		interactRef.icon.ImageTransparency = 0
		_setHexBarsTransparency(interactRef.bgBars, 0)
		_setHexBarsColor(interactRef.strokeBars, INTERACT_ACTIVE_COLOR)
	else
		interactRef.active = false
		interactRef.icon.ImageTransparency = INTERACT_DISABLED_TRANSPARENCY
		_setHexBarsTransparency(interactRef.bgBars, 0.3)
		_setHexBarsColor(interactRef.strokeBars, C.BORDER_DIM)
	end
end

function ActiveSkillBarUI._tryCapture()
	if not captureRef or not captureRef.active then return end
	if not captureTarget then return end

	local instanceId = captureTarget:GetAttribute("InstanceId")
	if not instanceId then return end

	-- 서버에 포획 시도 요청
	local ok, result = NetClient.Request("Capture.Attempt.Request", {
		targetId = instanceId,
	})

	if ok and result then
		if result.success then
			-- 포획 성공 시 버튼 즉시 비활성화
			captureTarget = nil
			_updateCaptureButton()
		end
	end
end

--========================================
-- Update Loop
--========================================
local function refreshSlots()
	local slots = SkillController.getActiveSkillSlots()

	for i = 1, SLOT_COUNT do
		local ref = slotRefs[i]
		if not ref then continue end

		-- 4번째 슬롯은 구르기 고정
		if i == 4 then
			local img = _getIconImage("ICON_ROLL") or _getIconImage("ACTIVE_ROLL")
			ref.icon.Image = img or ""
			ref.icon.ImageTransparency = img and 0 or 0.8
			
			local remaining = MovementController.getDodgeCooldownRemaining()
			if remaining > 0 then
				_setHexBarsTransparency(ref.cooldownBars, 0.45)
				ref.cooldownText.Text = tostring(math.ceil(remaining))
				ref.icon.ImageTransparency = 0.5
				ref.wasOnCooldown = true
				_setHexBarsColor(ref.strokeBars, C.BORDER_DIM)
			else
				_setHexBarsTransparency(ref.cooldownBars, 1)
				ref.cooldownText.Text = ""
				ref.icon.ImageTransparency = 0
				_setHexBarsColor(ref.strokeBars, C.BORDER_DIM)
			end
			ref.frame.Visible = true
			continue
		end

		local skillId = slots[i]

		if skillId then
			local skill = SkillTreeData.GetSkill(skillId)
			if skill then
				local img = _getIconImage(skill.icon)
				if img then
					ref.icon.Image = img
					ref.icon.ImageTransparency = 0
				else
					ref.icon.Image = ""
					ref.icon.ImageTransparency = 0.5
				end

				local remaining = SkillController.getSlotCooldownRemaining(i)
				if remaining > 0 then
					_setHexBarsTransparency(ref.cooldownBars, 0.45)
					ref.cooldownText.Text = tostring(math.ceil(remaining))
					ref.icon.ImageTransparency = 0.5
					ref.wasOnCooldown = true
					_setHexBarsColor(ref.strokeBars, C.BORDER_DIM)
				else
					_setHexBarsTransparency(ref.cooldownBars, 1)
					ref.cooldownText.Text = ""
					ref.icon.ImageTransparency = 0
					if ref.wasOnCooldown then
						ref.wasOnCooldown = false
						_setHexBarsColor(ref.strokeBars, BORDER_READY)
						for _, bar in ipairs(ref.strokeBars) do
							TweenService:Create(bar, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
								BackgroundColor3 = C.BORDER_DIM,
							}):Play()
						end
					else
						_setHexBarsColor(ref.strokeBars, C.BORDER_DIM)
					end
				end

				ref.frame.Visible = true
			else
				ref.frame.Visible = false
			end
		else
			-- 빈 슬롯
			ref.icon.Image = ""
			ref.icon.ImageTransparency = 0.8
			_setHexBarsTransparency(ref.cooldownBars, 1)
			ref.cooldownText.Text = ""
			ref.frame.Visible = true
			_setHexBarsColor(ref.strokeBars, C.BORDER_DIM)
			_setHexBarsTransparency(ref.bgBars, 0.3)
		end
	end
end

--========================================
-- Public API
--========================================

function ActiveSkillBarUI.Init(parent)
	createBar(parent)

	SkillController.onSkillDataUpdated(function()
		refreshSlots()
		_updateCaptureButton()
	end)

	SkillController.onCooldownUpdated(function()
		refreshSlots()
	end)

	-- G 키: 포획 시도
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.G then
			ActiveSkillBarUI._tryCapture()
		elseif input.KeyCode == Enum.KeyCode.R then
			-- R키 입력 시 버튼 눌림 효과 (선택사항)
		end
	end)

	-- 버튼 상태 업데이트 (0.1초 간격)
	local lastScan = 0

	updateConnection = RunService.Heartbeat:Connect(function()
		local slots = SkillController.getActiveSkillSlots()
		for i = 1, SLOT_COUNT do
			local ref = slotRefs[i]
			if not ref then continue end

			local remaining = 0
			if i == 4 then
				remaining = MovementController.getDodgeCooldownRemaining()
			else
				remaining = SkillController.getSlotCooldownRemaining(i)
			end

			if remaining > 0 then
				_setHexBarsTransparency(ref.cooldownBars, 0.45)
				ref.cooldownText.Text = tostring(math.ceil(remaining))
				ref.icon.ImageTransparency = 0.5
				ref.wasOnCooldown = true
			elseif ref.wasOnCooldown then
				_setHexBarsTransparency(ref.cooldownBars, 1)
				ref.cooldownText.Text = ""
				ref.icon.ImageTransparency = 0
				ref.wasOnCooldown = false
				_setHexBarsColor(ref.strokeBars, BORDER_READY)
				for _, bar in ipairs(ref.strokeBars) do
					TweenService:Create(bar, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						BackgroundColor3 = C.BORDER_DIM,
					}):Play()
				end
			end
		end

		-- ★ 버튼 상태 업데이트 (0.1초 간격으로 부하 절감)
		local now = tick()
		if now - lastScan >= 0.1 then
			lastScan = now
			_updateCaptureButton()
			_updateInteractButton()
		end
	end)

	task.defer(refreshSlots)
	task.defer(_updateCaptureButton)
end

function ActiveSkillBarUI.SetVisible(visible: boolean)
	if barFrame then
		barFrame.Visible = visible
	end
end

function ActiveSkillBarUI.UseSlot(slotIndex: number)
	SkillController.useSkillBySlot(slotIndex, _orientAndGetTarget())
end

return ActiveSkillBarUI
