-- SkillTreeUI.lua
-- 스킬 트리 UI (Dark Glass + Gold Metallic 스타일)
-- 좌측 탭 선택 + 우측 다이아몬드 그리드 노드 + 하단 디테일 패널

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local SkillTreeData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("SkillTreeData"))

local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local SkillTreeUI = {}
SkillTreeUI.Refs = {
	Frame = nil,
	TabButtons = {},
	ContentArea = nil,
	SPLabel = nil,
	LockLabel = nil,
	ConfirmDialog = nil,
	NodeArea = nil,
	DetailPanel = nil,
}

local activeTabIndex = 1
local currentUIManager = nil
local skillController = nil  -- injected via SetController
local isSmall = false

-- 택1 확인 다이얼로그 대기용
local pendingConfirmSkillId = nil
local selectedSkillId = nil
local nodeFrameRefs = {} -- { [skillId] = diamondFrame }
local lastClickInfo = { skillId = nil, time = 0 } -- 더블클릭 감지용

-- 전방 선언 (콜백에서 사용되므로 먼저 선언)
local _updateDetailPanel
local _renderSkillNodes
local _layoutDetailPanel
local _tryUnlockSkill

----------------------------------------------------------------
-- 아이콘 헬퍼
----------------------------------------------------------------
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

----------------------------------------------------------------
-- 다이아몬드 노드 생성
----------------------------------------------------------------
local NODE_TYPE_COLORS = {
	PASSIVE = Color3.fromRGB(255, 210, 60),
	ACTIVE = Color3.fromRGB(255, 140, 40),
	BUILD_TIER = Color3.fromRGB(140, 200, 100),
}

----------------------------------------------------------------
-- 스킬 해금 시도 (더블클릭 / 버튼 공용)
----------------------------------------------------------------
_tryUnlockSkill = function(skillId)
	if not skillController then return end
	local canUnlock, _reason = skillController.canUnlock(skillId)
	if not canUnlock then return end

	local treeIdForSkill = SkillTreeData.GetTreeIdForSkill(skillId)
	if treeIdForSkill and SkillTreeData.IsCombatTree(treeIdForSkill) and not skillController.getCombatTreeId() then
		local treeName = ""
		local otherNames = {}
		for _, t in ipairs(SkillTreeData.TABS) do
			if t.isCombat then
				if t.id == treeIdForSkill then
					treeName = t.name
				else
					table.insert(otherNames, t.name)
				end
			end
		end
		if currentUIManager and currentUIManager.notify then
			currentUIManager.notify("⚔ " .. treeName .. " 선택! " .. table.concat(otherNames, ", ") .. " 계열은 배울 수 없습니다.", Color3.fromRGB(255, 200, 80))
		end
	end
	skillController.requestUnlock(skillId)
end

local function _createDiamondNode(parent, skill, cx, cy, nodeSize, isUnlocked, canUnlockResult, isTreeLocked, playerLevel)
	local typeColor = NODE_TYPE_COLORS[skill.type] or C.GOLD

	-- 다이아몬드 프레임 (45° 회전)
	local diamond = Instance.new("Frame")
	diamond.Name = "Diamond_" .. skill.id
	diamond.Size = UDim2.new(0, nodeSize, 0, nodeSize)
	diamond.Position = UDim2.new(0, cx, 0, cy)
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Rotation = 45
	diamond.BorderSizePixel = 0
	diamond.ZIndex = 3
	diamond.Parent = parent

	-- 배경색 + 투명도
	if isUnlocked then
		diamond.BackgroundColor3 = Color3.fromRGB(50, 45, 35)
		diamond.BackgroundTransparency = 0.1
	elseif isTreeLocked then
		diamond.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
		diamond.BackgroundTransparency = 0.55
	elseif canUnlockResult then
		diamond.BackgroundColor3 = Color3.fromRGB(45, 42, 30)
		diamond.BackgroundTransparency = 0.15
	else
		diamond.BackgroundColor3 = Color3.fromRGB(30, 28, 32)
		diamond.BackgroundTransparency = 0.3
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, math.floor(math.clamp(nodeSize * 0.07, 3, 10)))
	corner.Parent = diamond

	-- 테두리 (UIStroke)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	if isUnlocked then
		stroke.Color = typeColor
		stroke.Thickness = math.clamp(nodeSize * 0.032, 1.5, 3.5)
		stroke.Transparency = 0
	elseif isTreeLocked then
		stroke.Color = C.BORDER_DIM
		stroke.Thickness = 1
		stroke.Transparency = 0.5
	elseif canUnlockResult then
		stroke.Color = C.GOLD
		stroke.Thickness = math.clamp(nodeSize * 0.025, 1, 3)
		stroke.Transparency = 0.1
	else
		stroke.Color = C.BORDER_DIM
		stroke.Thickness = math.clamp(nodeSize * 0.02, 0.8, 2.5)
		stroke.Transparency = 0.3
	end
	stroke.Parent = diamond

	-- 해금 노드 글로우 효과
	if isUnlocked then
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.Size = UDim2.new(1, 8, 1, 8)
		glow.Position = UDim2.new(0.5, 0, 0.5, 0)
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.BackgroundTransparency = 0.82
		glow.BackgroundColor3 = typeColor
		glow.BorderSizePixel = 0
		glow.ZIndex = 2
		glow.Parent = diamond
		local gc = Instance.new("UICorner")
		gc.CornerRadius = UDim.new(0, 8)
		gc.Parent = glow
	end

	-- 아이콘 이미지 (역회전 -45°)
	local iconImage = _getIconImage(skill.icon)
	if iconImage then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.Size = UDim2.new(0.78, 0, 0.78, 0)
		img.Position = UDim2.new(0.5, 0, 0.5, 0)
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Rotation = -45
		img.BackgroundTransparency = 1
		img.Image = iconImage
		img.ScaleType = Enum.ScaleType.Fit
		img.ImageTransparency = isTreeLocked and 0.55 or 0
		img.ImageColor3 = isTreeLocked and Color3.fromRGB(120, 120, 120) or Color3.new(1, 1, 1)
		img.ZIndex = 4
		img.Parent = diamond
	else
		-- 아이콘 없으면 텍스트 플레이스홀더
		local ph = Instance.new("TextLabel")
		ph.Name = "IconPH"
		ph.Size = UDim2.new(0.8, 0, 0.8, 0)
		ph.Position = UDim2.new(0.5, 0, 0.5, 0)
		ph.AnchorPoint = Vector2.new(0.5, 0.5)
		ph.Rotation = -45
		ph.BackgroundTransparency = 1
		ph.Text = skill.type == "ACTIVE" and "⚔" or (skill.type == "BUILD_TIER" and "🏗" or "◆")
		ph.TextColor3 = isTreeLocked and C.DIM or typeColor
		ph.TextSize = math.floor(math.clamp(nodeSize * 0.4, 18, 50))
		ph.Font = Enum.Font.GothamBold
		ph.ZIndex = 4
		ph.Parent = diamond
	end

	-- 선택 표시 (선택된 노드에만)
	if selectedSkillId == skill.id then
		local sel = Instance.new("UIStroke")
		sel.Name = "SelectStroke"
		sel.Color = C.WHITE
		sel.Thickness = 2
		sel.Transparency = 0.2
		sel.Parent = diamond
	end

	-- 클릭 버튼
	local click = Instance.new("TextButton")
	click.Name = "Click"
	click.Size = UDim2.new(1, 0, 1, 0)
	click.BackgroundTransparency = 1
	click.Text = ""
	click.ZIndex = 10
	click.Parent = diamond

	local capturedId = skill.id
	click.MouseButton1Click:Connect(function()
		local now = tick()
		-- 더블클릭 감지 (동일 스킬 0.4초 내 재클릭 → 해금)
		if lastClickInfo.skillId == capturedId and (now - lastClickInfo.time) < 0.4 then
			lastClickInfo.skillId = nil
			lastClickInfo.time = 0
			if not isUnlocked then
				_tryUnlockSkill(capturedId)
			end
			return
		end
		lastClickInfo.skillId = capturedId
		lastClickInfo.time = now

		selectedSkillId = capturedId
		_updateDetailPanel()
		if SkillTreeUI.Refs.NodeArea then
			_renderSkillNodes(SkillTreeUI.Refs.NodeArea)
		end
		_updateDetailPanel()
	end)

	-- 스킬 이름 라벨 (다이아몬드 아래)
	local halfDiag = nodeSize * 0.71
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name_" .. skill.id
	nameLabel.Size = UDim2.new(0, nodeSize * 2.0, 0, math.floor(math.clamp(nodeSize * 0.26, 14, 28)))
	nameLabel.Position = UDim2.new(0, cx, 0, cy + halfDiag + math.floor(math.clamp(nodeSize * 0.1, 4, 14)))
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = skill.name
	nameLabel.TextColor3 = isUnlocked and C.WHITE or (isTreeLocked and C.DIM or (canUnlockResult and C.GOLD or C.GRAY))
	nameLabel.TextSize = math.floor(math.clamp(nodeSize * 0.22, 13, 30))
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = 3
	nameLabel.Parent = parent

	nodeFrameRefs[skill.id] = diamond
	return diamond
end

----------------------------------------------------------------
-- 연결 화살표 생성
----------------------------------------------------------------
local function _createArrow(parent, fromX, fromY, toX, toY, nodeSize, isActive)
	local halfDiag = nodeSize * 0.71
	local dy = toY - fromY
	local arrowColor = isActive and Color3.fromRGB(190, 175, 120) or Color3.fromRGB(75, 70, 55)
	local arrowTransp = isActive and 0.15 or 0.55

	if math.abs(dy) < 10 then
		-- 수평 화살표
		local sx = fromX + halfDiag + 3
		local ex = toX - halfDiag - 3
		local length = ex - sx
		if length < 2 then return end

		local line = Instance.new("Frame")
		line.Name = "ArrowH"
		line.Size = UDim2.new(0, length, 0, 2)
		line.Position = UDim2.new(0, sx, 0, fromY)
		line.AnchorPoint = Vector2.new(0, 0.5)
		line.BackgroundColor3 = arrowColor
		line.BackgroundTransparency = arrowTransp
		line.BorderSizePixel = 0
		line.ZIndex = 1
		line.Parent = parent

		-- 화살표 머리
		local head = Instance.new("Frame")
		head.Name = "ArrowHd"
		head.Size = UDim2.new(0, 6, 0, 6)
		head.Position = UDim2.new(0, ex, 0, fromY)
		head.AnchorPoint = Vector2.new(0.5, 0.5)
		head.Rotation = 45
		head.BackgroundColor3 = arrowColor
		head.BackgroundTransparency = arrowTransp
		head.BorderSizePixel = 0
		head.ZIndex = 1
		head.Parent = parent
	else
		-- 수직 화살표
		local sy = fromY + halfDiag + 3
		local ey = toY - halfDiag - 3
		local length = ey - sy
		if length < 2 then return end

		local line = Instance.new("Frame")
		line.Name = "ArrowV"
		line.Size = UDim2.new(0, 2, 0, length)
		line.Position = UDim2.new(0, fromX, 0, sy)
		line.AnchorPoint = Vector2.new(0.5, 0)
		line.BackgroundColor3 = arrowColor
		line.BackgroundTransparency = arrowTransp
		line.BorderSizePixel = 0
		line.ZIndex = 1
		line.Parent = parent

		local head = Instance.new("Frame")
		head.Name = "ArrowHd"
		head.Size = UDim2.new(0, 6, 0, 6)
		head.Position = UDim2.new(0, fromX, 0, ey)
		head.AnchorPoint = Vector2.new(0.5, 0.5)
		head.Rotation = 45
		head.BackgroundColor3 = arrowColor
		head.BackgroundTransparency = arrowTransp
		head.BorderSizePixel = 0
		head.ZIndex = 1
		head.Parent = parent
	end
end

----------------------------------------------------------------
-- 디테일 패널 업데이트
----------------------------------------------------------------
_updateDetailPanel = function()
	local panel = SkillTreeUI.Refs.DetailPanel
	if not panel then return end

	if not selectedSkillId then
		panel.Visible = false
		return
	end

	local skill = SkillTreeData.GetSkill(selectedSkillId)
	if not skill then
		panel.Visible = false
		return
	end

	panel.Visible = true
	task.defer(_layoutDetailPanel)

	local isUnlocked = skillController and skillController.isSkillUnlocked(selectedSkillId) or false
	local canUnlock, reason = false, nil
	if skillController then
		canUnlock, reason = skillController.canUnlock(selectedSkillId)
	end
	local combatTreeId = skillController and skillController.getCombatTreeId() or nil
	local treeIdForSkill = SkillTreeData.GetTreeIdForSkill(selectedSkillId)
	local isCombat = treeIdForSkill and SkillTreeData.IsCombatTree(treeIdForSkill)
	local isTreeLocked = isCombat and combatTreeId ~= nil and combatTreeId ~= treeIdForSkill

	-- 아이콘
	local detailIcon = panel:FindFirstChild("DetailIcon")
	if detailIcon then
		local iconImage = _getIconImage(skill.icon)
		if iconImage then
			detailIcon.Image = iconImage
			detailIcon.Visible = true
		else
			detailIcon.Visible = false
		end
	end

	-- 이름
	local nameLabel = panel:FindFirstChild("DetailName")
	if nameLabel then nameLabel.Text = skill.name end

	-- 타입 + 레벨 + SP 정보
	local infoLabel = panel:FindFirstChild("DetailInfo")
	if infoLabel then
		local typeText = skill.type == "PASSIVE" and "패시브" or (skill.type == "ACTIVE" and "액티브" or "건축")
		local parts = { typeText, "Lv." .. skill.reqLevel }
		if skill.spCost and skill.spCost > 0 then
			table.insert(parts, "SP " .. skill.spCost)
		end
		if skill.cooldown then
			table.insert(parts, "쿨타임 " .. skill.cooldown .. "s")
		end
		infoLabel.Text = table.concat(parts, "  |  ")
	end

	-- 설명
	local descLabel = panel:FindFirstChild("DetailDesc")
	if descLabel then descLabel.Text = skill.description or "" end

	-- 효과 요약
	local effectsLabel = panel:FindFirstChild("DetailEffects")
	if effectsLabel then
		local effectTexts = {}
		for _, eff in ipairs(skill.effects or {}) do
			local val = eff.value
			local stat = eff.stat
			if stat == "DAMAGE_MULT" then
				table.insert(effectTexts, "공격력 +" .. math.floor(val * 100) .. "%")
			elseif stat == "CRIT_CHANCE" then
				table.insert(effectTexts, "치명타 +" .. math.floor(val * 100) .. "%")
			elseif stat == "CRIT_DAMAGE_MULT" then
				table.insert(effectTexts, "치명타 피해 +" .. math.floor(val * 100) .. "%")
			elseif stat == "NO_ARROW_CONSUME" then
				table.insert(effectTexts, "화살 소모 없음")
			elseif stat == "HEAL_ON_HIT_CHANCE" then
				table.insert(effectTexts, "적중 회복 " .. math.floor(val * 100) .. "%")
			elseif stat == "HEAL_ON_HIT_PCT" then
				table.insert(effectTexts, "HP " .. math.floor(val * 100) .. "% 회복")
			elseif stat == "SKILL_DAMAGE_MULT" then
				table.insert(effectTexts, "스킬 " .. math.floor(val * 100) .. "%")
			elseif stat == "SKILL_MULTI_HIT" then
				table.insert(effectTexts, math.floor(val) .. "회 타격")
			elseif stat == "SKILL_AOE_RADIUS" then
				table.insert(effectTexts, "범위 " .. val .. "스터드")
			elseif stat == "SLOW_DURATION" then
				table.insert(effectTexts, "둔화 " .. val .. "초")
			elseif stat == "STAGGER_DURATION" then
				table.insert(effectTexts, "경직 " .. val .. "초")
			elseif stat == "STUN_DURATION" then
				table.insert(effectTexts, "기절 " .. val .. "초")
			end
		end
		effectsLabel.Text = #effectTexts > 0 and table.concat(effectTexts, ", ") or ""
	end

	-- 해금 상태 / 버튼
	local unlockBtn = panel:FindFirstChild("DetailUnlockBtn")
	local statusLabel = panel:FindFirstChild("DetailStatus")

	if unlockBtn then
		if isUnlocked or isTreeLocked or not canUnlock then
			unlockBtn.Visible = false
		else
			unlockBtn.Visible = true
		end
	end

	-- 슬롯 할당 버튼 (해금된 ACTIVE 스킬만 표시)
	local SLOT_KEYS = { "Q", "F", "V" }
	local SLOT_ASSIGNED_COLORS = {
		Color3.fromRGB(80, 140, 220),
		Color3.fromRGB(220, 160, 60),
		Color3.fromRGB(180, 80, 200),
	}
	local showSlotBtns = isUnlocked and skill.type == "ACTIVE"
	local activeSlots = skillController and skillController.getActiveSkillSlots() or {}
	for si = 1, 3 do
		local slotBtn = panel:FindFirstChild("SlotBtn" .. si)
		if slotBtn then
			slotBtn.Visible = showSlotBtns
			if showSlotBtns then
				local isAssigned = activeSlots[si] == selectedSkillId
				local stroke = slotBtn:FindFirstChildOfClass("UIStroke")
				if isAssigned then
					slotBtn.BackgroundColor3 = SLOT_ASSIGNED_COLORS[si]
					slotBtn.BackgroundTransparency = 0.15
					slotBtn.TextColor3 = C.WHITE
					if stroke then stroke.Color = C.WHITE stroke.Thickness = 2 end
				else
					slotBtn.BackgroundColor3 = Color3.fromRGB(45, 42, 35)
					slotBtn.BackgroundTransparency = 0.15
					slotBtn.TextColor3 = C.GRAY
					if stroke then stroke.Color = C.BORDER_DIM stroke.Thickness = 1 end
				end
			end
		end
	end

	if statusLabel then
		if isUnlocked and skill.type == "ACTIVE" then
			local assignedSlot = nil
			for si = 1, 3 do
				if activeSlots[si] == selectedSkillId then assignedSlot = SLOT_KEYS[si] break end
			end
			if assignedSlot then
				statusLabel.Text = "✓ [" .. assignedSlot .. "] 슬롯 배치됨"
				statusLabel.TextColor3 = C.GREEN
			else
				statusLabel.Text = "아래 슬롯에 배치하세요"
				statusLabel.TextColor3 = C.GOLD
			end
			statusLabel.Visible = true
		elseif isUnlocked then
			statusLabel.Text = "✓ 해금됨"
			statusLabel.TextColor3 = C.GREEN
			statusLabel.Visible = true
		elseif isTreeLocked then
			statusLabel.Text = "🔒 다른 계열 선택됨"
			statusLabel.TextColor3 = C.RED
			statusLabel.Visible = true
		elseif not canUnlock and reason then
			local lockReason = ""
			if reason == "LEVEL_TOO_LOW" then
				lockReason = "Lv." .. (skill.reqLevel or "?") .. " 필요"
			elseif reason == "NOT_ENOUGH_SP" then
				lockReason = "SP 부족"
			elseif reason == "PREREQS_NOT_MET" then
				lockReason = "선행 스킬 미해금"
			else
				lockReason = "잠김"
			end
			statusLabel.Text = lockReason
			statusLabel.TextColor3 = C.DIM
			statusLabel.Visible = true
		else
			statusLabel.Visible = false
		end
	end
end

----------------------------------------------------------------
-- 디테일 패널 반응형 레이아웃
----------------------------------------------------------------
_layoutDetailPanel = function()
	local panel = SkillTreeUI.Refs.DetailPanel
	if not panel or not panel.Visible then return end

	local pw = panel.AbsoluteSize.X
	local ph = panel.AbsoluteSize.Y
	if pw < 50 or ph < 30 then return end

	local s = math.clamp(math.min(pw / 400, ph / 140), 0.6, 3.0)
	local iconSz = math.floor(math.clamp(86 * s, 44, 150))
	local nameX = iconSz + math.floor(22 * s)

	local icon = panel:FindFirstChild("DetailIcon")
	if icon then
		icon.Size = UDim2.new(0, iconSz, 0, iconSz)
		icon.Position = UDim2.new(0, math.floor(16 * s), 0.5, 0)
	end

	local name = panel:FindFirstChild("DetailName")
	if name then
		name.Size = UDim2.new(0.5, -nameX, 0, math.floor(34 * s))
		name.Position = UDim2.new(0, nameX, 0, math.floor(6 * s))
		name.TextSize = math.floor(math.clamp(28 * s, 18, 44))
	end

	local info = panel:FindFirstChild("DetailInfo")
	if info then
		info.Size = UDim2.new(0.55, -nameX, 0, math.floor(26 * s))
		info.Position = UDim2.new(0, nameX, 0, math.floor(42 * s))
		info.TextSize = math.floor(math.clamp(20 * s, 15, 32))
	end

	local desc = panel:FindFirstChild("DetailDesc")
	if desc then
		desc.Size = UDim2.new(0.55, -nameX, 0, math.floor(56 * s))
		desc.Position = UDim2.new(0, nameX, 0, math.floor(70 * s))
		desc.TextSize = math.floor(math.clamp(20 * s, 15, 32))
	end

	local effects = panel:FindFirstChild("DetailEffects")
	if effects then
		effects.Size = UDim2.new(0.55, -nameX, 0, math.floor(26 * s))
		effects.Position = UDim2.new(0, nameX, 1, -math.floor(30 * s))
		effects.TextSize = math.floor(math.clamp(19 * s, 14, 30))
	end

	local status = panel:FindFirstChild("DetailStatus")
	if status then
		status.Size = UDim2.new(0, math.floor(200 * s), 0, math.floor(34 * s))
		status.Position = UDim2.new(1, -math.floor(214 * s), 0.5, -math.floor(38 * s))
		status.TextSize = math.floor(math.clamp(20 * s, 15, 32))
	end

	local btn = panel:FindFirstChild("DetailUnlockBtn")
	if btn then
		btn.Size = UDim2.new(0, math.floor(130 * s), 0, math.floor(48 * s))
		btn.Position = UDim2.new(1, -math.floor(144 * s), 0.5, math.floor(4 * s))
		btn.TextSize = math.floor(math.clamp(23 * s, 16, 36))
	end

	-- 슬롯 할당 버튼 (Q/F/V) 레이아웃
	local slotBtnW = math.floor(math.clamp(52 * s, 36, 80))
	local slotBtnH = math.floor(math.clamp(42 * s, 30, 64))
	local slotGap = math.floor(math.clamp(6 * s, 3, 12))
	local totalSlotW = slotBtnW * 3 + slotGap * 2
	for si = 1, 3 do
		local slotBtn = panel:FindFirstChild("SlotBtn" .. si)
		if slotBtn then
			slotBtn.Size = UDim2.new(0, slotBtnW, 0, slotBtnH)
			slotBtn.Position = UDim2.new(1, -math.floor(totalSlotW + 14 * s) + (si - 1) * (slotBtnW + slotGap), 0.5, math.floor(4 * s))
			slotBtn.TextSize = math.floor(math.clamp(19 * s, 14, 32))
		end
	end
end

----------------------------------------------------------------
-- 스킬 노드 다이아몬드 그리드 렌더링
----------------------------------------------------------------
_renderSkillNodes = function(nodeArea)
	-- 기존 노드 정리
	for _, child in ipairs(nodeArea:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	nodeFrameRefs = {}

	local tabData = SkillTreeData.TABS[activeTabIndex]
	if not tabData then return end
	local treeId = tabData.id
	local skills = SkillTreeData[treeId]
	if not skills then return end

	local unlockedSkills = skillController and skillController.getUnlockedSkills() or {}
	local combatTreeId = skillController and skillController.getCombatTreeId() or nil
	local playerLevel = skillController and skillController.getPlayerLevel() or 1
	local isCombat = tabData.isCombat
	local isTreeLocked = isCombat and combatTreeId ~= nil and combatTreeId ~= treeId

	-- 트리 잠금 라벨 업데이트
	if SkillTreeUI.Refs.LockLabel then
		if isTreeLocked then
			local lockedName = ""
			for _, t in ipairs(SkillTreeData.TABS) do
				if t.id == combatTreeId then lockedName = t.name break end
			end
			SkillTreeUI.Refs.LockLabel.Text = "🔒 " .. lockedName .. " 계열 선택됨"
			SkillTreeUI.Refs.LockLabel.TextColor3 = C.RED
			SkillTreeUI.Refs.LockLabel.Visible = true
		else
			SkillTreeUI.Refs.LockLabel.Visible = false
		end
	end

	-- 디테일 패널 숨김 (탭 전환 시)
	if SkillTreeUI.Refs.DetailPanel and not selectedSkillId then
		SkillTreeUI.Refs.DetailPanel.Visible = false
	end

	-- 스킬 분류: 패시브/건축(상단행) + 액티브(하단행)
	local passives = {}
	local actives = {}
	for _, skill in ipairs(skills) do
		if skill.type == "ACTIVE" then
			table.insert(actives, skill)
		else
			table.insert(passives, skill)
		end
	end

	-- 영역 크기 (AbsoluteSize 미확정 대비)
	local areaWidth = nodeArea.AbsoluteSize.X
	if areaWidth < 50 then areaWidth = 600 end
	local areaHeight = nodeArea.AbsoluteSize.Y
	if areaHeight < 50 then areaHeight = 450 end

	-- 반응형 스케일 팩터 (높이 기준 — 수평 스크롤이므로 Y만 맞추면 됨)
	local scale = math.clamp(areaHeight / 250, 0.6, 3.0)
	local nodeSize = math.floor(math.clamp(80 * scale, 50, 180))

	-- 레이아웃 계산 (수평 배치 — 고정 간격, 스크롤로 해결)
	local nPassive = #passives
	if nPassive == 0 then return end

	local colSpacing = math.floor(nodeSize * 2.0)
	local marginX = math.floor(nodeSize * 1.2) -- 좌측 여백 (다이아몬드 절반+이름)
	local startX = marginX

	-- Y 좌표는 nodeSize 기준으로 비례 (화면 크기 독립)
	local markerY = math.floor(nodeSize * 0.15)
	local passiveY = markerY + math.floor(nodeSize * 1.15)
	local activeY = passiveY + math.floor(nodeSize * 2.1)

	-- 노드 위치 맵
	local nodePositions = {}

	-- ========== 패시브 행 ==========
	for i, skill in ipairs(passives) do
		local cx = startX + (i - 1) * colSpacing
		local cy = passiveY
		nodePositions[skill.id] = { x = cx, y = cy }

		-- 레벨 마커
		local marker = Instance.new("TextLabel")
		marker.Name = "LvMark_" .. i
		marker.Size = UDim2.new(0, nodeSize * 1.6, 0, math.floor(nodeSize * 0.24))
		marker.Position = UDim2.new(0, cx, 0, markerY)
		marker.AnchorPoint = Vector2.new(0.5, 0)
		marker.BackgroundTransparency = 1
		marker.Text = "Lv." .. skill.reqLevel
		marker.TextColor3 = playerLevel >= skill.reqLevel and Color3.fromRGB(170, 165, 140) or C.DIM
		marker.TextSize = math.floor(math.clamp(nodeSize * 0.22, 13, 30))
		marker.Font = Enum.Font.RobotoMono
		marker.ZIndex = 2
		marker.Parent = nodeArea

		-- 마커 → 노드 연결선
		local lineLen = passiveY - markerY - math.floor(nodeSize * 0.28) - nodeSize * 0.35
		if lineLen > 2 then
			local markLine = Instance.new("Frame")
			markLine.Name = "MarkLine"
			markLine.Size = UDim2.new(0, 1, 0, lineLen)
			markLine.Position = UDim2.new(0, cx, 0, markerY + math.floor(nodeSize * 0.22))
			markLine.AnchorPoint = Vector2.new(0.5, 0)
			markLine.BackgroundColor3 = C.BORDER_DIM
			markLine.BackgroundTransparency = 0.7
			markLine.BorderSizePixel = 0
			markLine.ZIndex = 0
			markLine.Parent = nodeArea
		end

		local isUnlocked = unlockedSkills[skill.id] == true
		local canUnlock = skillController and skillController.canUnlock(skill.id) or false
		_createDiamondNode(nodeArea, skill, cx, cy, nodeSize, isUnlocked, canUnlock, isTreeLocked, playerLevel)
	end

	-- ========== 액티브 행 ==========
	for _, skill in ipairs(actives) do
		local prereqId = skill.prereqs and skill.prereqs[1]
		local prereqPos = prereqId and nodePositions[prereqId]
		local cx = prereqPos and prereqPos.x or startX
		local cy = activeY
		nodePositions[skill.id] = { x = cx, y = cy }

		local isUnlocked = unlockedSkills[skill.id] == true
		local canUnlock = skillController and skillController.canUnlock(skill.id) or false
		_createDiamondNode(nodeArea, skill, cx, cy, nodeSize, isUnlocked, canUnlock, isTreeLocked, playerLevel)
	end

	-- ========== 화살표 (선행 연결) ==========
	for _, skill in ipairs(skills) do
		if skill.prereqs then
			for _, prereqId in ipairs(skill.prereqs) do
				local from = nodePositions[prereqId]
				local to = nodePositions[skill.id]
				if from and to then
					local bothUnlocked = (unlockedSkills[prereqId] == true)
					_createArrow(nodeArea, from.x, from.y, to.x, to.y, nodeSize, bothUnlocked)
				end
			end
		end
	end

	-- 선택된 노드 디테일 갱신
	if selectedSkillId then
		_updateDetailPanel()
	end

	-- 수평 스크롤 영역 설정 (마지막 노드 + 우측 여백)
	local contentRight = startX + (nPassive - 1) * colSpacing + marginX
	if contentRight > areaWidth then
		nodeArea.CanvasSize = UDim2.new(0, contentRight + 10, 0, 0)
	else
		nodeArea.CanvasSize = UDim2.new(0, 0, 0, 0)
	end
end

----------------------------------------------------------------
-- 택1 확인 다이얼로그
----------------------------------------------------------------
function _showConfirmDialog(skillId, treeId)
	if SkillTreeUI.Refs.ConfirmDialog then
		SkillTreeUI.Refs.ConfirmDialog.Visible = true
	end
	pendingConfirmSkillId = skillId

	local treeName = ""
	for _, t in ipairs(SkillTreeData.TABS) do
		if t.id == treeId then treeName = t.name break end
	end

	local msgLabel = SkillTreeUI.Refs.ConfirmDialog and SkillTreeUI.Refs.ConfirmDialog:FindFirstChild("Message")
	if msgLabel then
		msgLabel.Text = "'" .. treeName .. "' 계열을 선택하면\n다른 전투 계열은 영구 잠금됩니다.\n\n정말 선택하시겠습니까?"
	end
end

local function _hideConfirmDialog()
	if SkillTreeUI.Refs.ConfirmDialog then
		SkillTreeUI.Refs.ConfirmDialog.Visible = false
	end
	pendingConfirmSkillId = nil
end

local function _onConfirmYes()
	if pendingConfirmSkillId then
		_tryUnlockSkill(pendingConfirmSkillId)
	end
	_hideConfirmDialog()
end

----------------------------------------------------------------
-- 탭 선택 처리
----------------------------------------------------------------
local function selectTab(index)
	activeTabIndex = index
	selectedSkillId = nil -- 탭 전환 시 선택 초기화

	for i, btn in ipairs(SkillTreeUI.Refs.TabButtons) do
		local isActive = (i == index)
		btn.BackgroundColor3 = isActive and C.BG_SLOT_SEL or C.BG_PANEL_L
		btn.BackgroundTransparency = isActive and 0.2 or 0.5

		local stroke = btn:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = isActive and C.GOLD_SEL or C.BORDER_DIM
			stroke.Thickness = isActive and 1.5 or 1
		end

		local label = btn:FindFirstChild("Label")
		if label then
			label.TextColor3 = isActive and C.GOLD or C.GRAY
		end

		local indicator = btn:FindFirstChild("Indicator")
		if indicator then
			indicator.Visible = isActive
		end
	end

	-- 콘텐츠 헤더 업데이트
	local contentHeader = SkillTreeUI.Refs.ContentArea and SkillTreeUI.Refs.ContentArea:FindFirstChild("ContentHeader")
	if contentHeader then
		local tab = SkillTreeData.TABS[index]
		contentHeader.Text = tab and tab.name or ""
	end

	-- 스킬 노드 렌더링
	if SkillTreeUI.Refs.NodeArea then
		_renderSkillNodes(SkillTreeUI.Refs.NodeArea)
	end

	-- 디테일 패널 숨김
	if SkillTreeUI.Refs.DetailPanel then
		SkillTreeUI.Refs.DetailPanel.Visible = false
	end
end

----------------------------------------------------------------
-- SP 라벨 업데이트
----------------------------------------------------------------
local function _updateSPLabel()
	if not SkillTreeUI.Refs.SPLabel or not skillController then return end
	local sp = skillController.getSPAvailable()
	local spent = skillController.getSPSpent()
	SkillTreeUI.Refs.SPLabel.Text = "SP: " .. sp .. " (사용: " .. spent .. ")"
end

----------------------------------------------------------------
-- Init
----------------------------------------------------------------
function SkillTreeUI.Init(parent, UIManager, isMobile)
	currentUIManager = UIManager
	isSmall = isMobile

	local TS_TITLE = isSmall and 24 or 28
	local TS_TAB = isSmall and 16 or 19
	local TS_HEADER = isSmall and 18 or 22

	-- 전체 화면 오버레이
	SkillTreeUI.Refs.Frame = Utils.mkFrame({
		name = "SkillTreeMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = C.BG_OVERLAY,
		bgT = 0.5,
		vis = false,
		parent = parent,
	})

	-- 메인 패널
	local main = Utils.mkWindow({
		name = "Main",
		size = UDim2.new(isSmall and 0.98 or 0.82, 0, isSmall and 0.95 or 0.88, 0),
		maxSize = Vector2.new(1200, 850),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 6,
		stroke = 1.5,
		strokeC = C.BORDER,
		parent = SkillTreeUI.Refs.Frame,
	})

	-- ============ 헤더 ============
	local headerH = isSmall and 46 or 50
	local header = Utils.mkFrame({
		name = "Header",
		size = UDim2.new(1, 0, 0, headerH),
		bgT = 1,
		parent = main,
	})

	-- 타이틀
	Utils.mkLabel({
		name = "Title",
		text = "SKILL",
		size = UDim2.new(0, 120, 1, 0),
		pos = UDim2.new(0, 16, 0, 0),
		ax = Enum.TextXAlignment.Left,
		ts = TS_TITLE,
		font = F.TITLE,
		color = C.GOLD,
		parent = header,
	})

	-- [DEV] SP 초기화 버튼
	Utils.mkBtn({
		name = "ResetBtn",
		text = "SP 초기화",
		size = UDim2.new(0, isSmall and 80 or 100, 0, isSmall and 30 or 34),
		pos = UDim2.new(1, -(isSmall and 135 or 160), 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		bg = Color3.fromRGB(140, 50, 50),
		bgT = 0.3,
		ts = isSmall and 12 or 14,
		font = F.TITLE,
		color = Color3.fromRGB(255, 200, 200),
		r = 6,
		fn = function()
			if skillController and skillController.requestReset then
				if currentUIManager and currentUIManager.notify then
					currentUIManager.notify("SP 초기화 요청 중...", Color3.fromRGB(255, 255, 150))
				end
				skillController.requestReset(function(ok)
					if currentUIManager and currentUIManager.notify then
						if ok then
							currentUIManager.notify("SP 초기화 완료!", Color3.fromRGB(100, 255, 100))
						else
							currentUIManager.notify("SP 초기화 실패 (서버 오류)", Color3.fromRGB(255, 100, 100))
						end
					end
				end)
			else
				warn("[SkillTreeUI] ResetBtn: skillController missing", skillController ~= nil)
			end
		end,
		parent = header,
	})

	-- 닫기 버튼
	Utils.mkBtn({
		name = "CloseBtn",
		text = "X",
		size = UDim2.new(0, isSmall and 36 or 40, 0, isSmall and 36 or 40),
		pos = UDim2.new(1, -(isSmall and 42 or 48), 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		bg = C.BTN,
		bgT = 0.5,
		ts = 18,
		font = F.TITLE,
		color = C.GRAY,
		r = 6,
		fn = function()
			if currentUIManager and currentUIManager.toggleSkillTree then
				currentUIManager.toggleSkillTree()
			end
		end,
		parent = header,
	})

	-- 구분선
	Utils.mkFrame({
		name = "Divider",
		size = UDim2.new(1, -24, 0, 1),
		pos = UDim2.new(0, 12, 1, 0),
		bg = C.BORDER_DIM,
		bgT = 0.4,
		r = false,
		parent = header,
	})

	-- ============ 본체 (헤더 아래) ============
	local bodyTop = headerH + 4
	local body = Utils.mkFrame({
		name = "Body",
		size = UDim2.new(1, -16, 1, -(bodyTop + 8)),
		pos = UDim2.new(0, 8, 0, bodyTop),
		bgT = 1,
		parent = main,
	})

	-- ============ 좌측 탭 패널 ============
	local tabWidth = isSmall and 135 or 185
	local tabPanel = Utils.mkFrame({
		name = "TabPanel",
		size = UDim2.new(0, tabWidth, 1, 0),
		bg = C.BG_DARK,
		bgT = 0.4,
		r = 6,
		stroke = true,
		strokeC = C.BORDER_DIM,
		parent = body,
	})

	-- 탭 레이아웃
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Vertical
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 4)
	tabLayout.Parent = tabPanel

	local tabPad = Instance.new("UIPadding")
	tabPad.PaddingTop = UDim.new(0, 8)
	tabPad.PaddingLeft = UDim.new(0, 6)
	tabPad.PaddingRight = UDim.new(0, 6)
	tabPad.Parent = tabPanel

	-- 탭 버튼 생성
	SkillTreeUI.Refs.TabButtons = {}
	for i, tab in ipairs(SkillTreeData.TABS) do
		local tabH = isSmall and 48 or 54
		local btn = Utils.mkFrame({
			name = "Tab_" .. tab.id,
			size = UDim2.new(1, 0, 0, tabH),
			bg = C.BG_PANEL_L,
			bgT = 0.5,
			r = 4,
			stroke = true,
			strokeC = C.BORDER_DIM,
			parent = tabPanel,
		})

		-- 선택 인디케이터 (좌측 골드 바)
		local indicator = Utils.mkFrame({
			name = "Indicator",
			size = UDim2.new(0, 3, 0.6, 0),
			pos = UDim2.new(0, -1, 0.2, 0),
			bg = C.GOLD_SEL,
			bgT = 0,
			r = 2,
			vis = false,
			parent = btn,
		})

		-- 탭 텍스트
		local label = Utils.mkLabel({
			name = "Label",
			text = "• " .. tab.name,
			size = UDim2.new(1, -12, 1, 0),
			pos = UDim2.new(0, 10, 0, 0),
			ax = Enum.TextXAlignment.Left,
			ts = TS_TAB,
			font = F.NORMAL,
			color = C.GRAY,
			parent = btn,
		})

		-- 클릭 핸들러
		local clickBtn = Instance.new("TextButton")
		clickBtn.Name = "ClickArea"
		clickBtn.Size = UDim2.new(1, 0, 1, 0)
		clickBtn.BackgroundTransparency = 1
		clickBtn.Text = ""
		clickBtn.ZIndex = 5
		clickBtn.Parent = btn
		clickBtn.MouseButton1Click:Connect(function()
			selectTab(i)
		end)

		table.insert(SkillTreeUI.Refs.TabButtons, btn)
	end

	-- ============ 우측 콘텐츠 영역 ============
	local contentArea = Utils.mkFrame({
		name = "ContentArea",
		size = UDim2.new(1, -(tabWidth + 12), 1, 0),
		pos = UDim2.new(0, tabWidth + 8, 0, 0),
		bg = C.BG_DARK,
		bgT = 0.5,
		r = 6,
		stroke = true,
		strokeC = C.BORDER_DIM,
		parent = body,
	})
	SkillTreeUI.Refs.ContentArea = contentArea

	-- 콘텐츠 헤더 (선택된 탭 이름)
	Utils.mkLabel({
		name = "ContentHeader",
		text = SkillTreeData.TABS[1].name,
		size = UDim2.new(0.5, -24, 0, 36),
		pos = UDim2.new(0, 12, 0, 8),
		ax = Enum.TextXAlignment.Left,
		ts = TS_HEADER,
		font = F.TITLE,
		color = C.WHITE,
		parent = contentArea,
	})

	-- SP 표시 라벨 (우측 상단)
	SkillTreeUI.Refs.SPLabel = Utils.mkLabel({
		name = "SPLabel",
		text = "SP: 0",
		size = UDim2.new(0.4, 0, 0, 28),
		pos = UDim2.new(0.55, 0, 0, 10),
		ax = Enum.TextXAlignment.Right,
		ts = isSmall and 15 or 18,
		font = F.NUM,
		color = C.GOLD,
		parent = contentArea,
	})

	-- 잠금 상태 라벨
	SkillTreeUI.Refs.LockLabel = Utils.mkLabel({
		name = "LockLabel",
		text = "",
		size = UDim2.new(0.5, 0, 0, 22),
		pos = UDim2.new(0, 12, 0, 38),
		ax = Enum.TextXAlignment.Left,
		ts = 14,
		font = F.NORMAL,
		color = C.RED,
		parent = contentArea,
	})
	SkillTreeUI.Refs.LockLabel.Visible = false

	-- 레벨 구분선
	local levelBarY = 48
	Utils.mkFrame({
		name = "LevelBar",
		size = UDim2.new(1, -24, 0, 1),
		pos = UDim2.new(0, 12, 0, levelBarY),
		bg = C.BORDER_DIM,
		bgT = 0.5,
		r = false,
		parent = contentArea,
	})

	-- ============ 노드 그리드 영역 (다이아몬드 배치, 스크롤 지원) ============
	local detailHeight = isSmall and 140 or 180
	local nodeArea = Instance.new("ScrollingFrame")
	nodeArea.Name = "NodeArea"
	nodeArea.Size = UDim2.new(1, -16, 1, -(levelBarY + detailHeight + 16))
	nodeArea.Position = UDim2.new(0, 8, 0, levelBarY + 6)
	nodeArea.BackgroundTransparency = 1
	nodeArea.BorderSizePixel = 0
	nodeArea.ScrollBarThickness = 4
	nodeArea.ScrollBarImageColor3 = Color3.fromRGB(140, 130, 100)
	nodeArea.ScrollBarImageTransparency = 0.4
	nodeArea.CanvasSize = UDim2.new(0, 0, 0, 0) -- _renderSkillNodes에서 동적 설정
	nodeArea.AutomaticCanvasSize = Enum.AutomaticSize.None
	nodeArea.ScrollingDirection = Enum.ScrollingDirection.X
	nodeArea.ElasticBehavior = Enum.ElasticBehavior.Always
	nodeArea.Parent = contentArea
	SkillTreeUI.Refs.NodeArea = nodeArea

	-- ============ 스킬 상세 패널 (하단) ============
	local detailPanel = Utils.mkFrame({
		name = "DetailPanel",
		size = UDim2.new(1, -16, 0, detailHeight + 10),  -- 약간 여유
		pos = UDim2.new(0, 8, 1, -(detailHeight + 4)),
		bg = C.BG_PANEL_L,
		bgT = 0.4,
		r = 6,
		stroke = true,
		strokeC = C.BORDER_DIM,
		vis = false,
		parent = contentArea,
	})
	SkillTreeUI.Refs.DetailPanel = detailPanel

	-- 디테일: 아이콘
	local dIcon = Instance.new("ImageLabel")
	dIcon.Name = "DetailIcon"
	dIcon.Size = UDim2.new(0, isSmall and 52 or 68, 0, isSmall and 52 or 68)
	dIcon.Position = UDim2.new(0, isSmall and 10 or 14, 0.5, 0)
	dIcon.AnchorPoint = Vector2.new(0, 0.5)
	dIcon.BackgroundTransparency = 1
	dIcon.ScaleType = Enum.ScaleType.Fit
	dIcon.ZIndex = 3
	dIcon.Parent = detailPanel

	-- 디테일: 이름
	local dNameX = isSmall and 68 or 90
	Utils.mkLabel({
		name = "DetailName",
		text = "",
		size = UDim2.new(0.5, -dNameX, 0, isSmall and 24 or 28),
		pos = UDim2.new(0, dNameX, 0, isSmall and 8 or 10),
		ax = Enum.TextXAlignment.Left,
		ts = isSmall and 17 or 21,
		font = F.TITLE,
		color = C.WHITE,
		parent = detailPanel,
	})

	-- 디테일: 타입/레벨/SP 정보
	Utils.mkLabel({
		name = "DetailInfo",
		text = "",
		size = UDim2.new(0.55, -dNameX, 0, isSmall and 18 or 20),
		pos = UDim2.new(0, dNameX, 0, isSmall and 33 or 40),
		ax = Enum.TextXAlignment.Left,
		ts = isSmall and 13 or 15,
		font = F.NUM,
		color = C.GOLD,
		parent = detailPanel,
	})

	-- 디테일: 설명
	Utils.mkLabel({
		name = "DetailDesc",
		text = "",
		size = UDim2.new(0.55, -dNameX, 0, isSmall and 36 or 48),
		pos = UDim2.new(0, dNameX, 0, isSmall and 54 or 64),
		ax = Enum.TextXAlignment.Left,
		ts = isSmall and 13 or 15,
		font = F.NORMAL,
		color = C.GRAY,
		wrap = true,
		parent = detailPanel,
	})

	-- 디테일: 효과 목록
	Utils.mkLabel({
		name = "DetailEffects",
		text = "",
		size = UDim2.new(0.55, -dNameX, 0, isSmall and 18 or 20),
		pos = UDim2.new(0, dNameX, 1, -(isSmall and 22 or 26)),
		ax = Enum.TextXAlignment.Left,
		ts = isSmall and 12 or 14,
		font = F.NORMAL,
		color = C.UNCOMMON,
		parent = detailPanel,
	})

	-- 디테일: 상태 라벨
	Utils.mkLabel({
		name = "DetailStatus",
		text = "",
		size = UDim2.new(0, isSmall and 140 or 170, 0, isSmall and 24 or 28),
		pos = UDim2.new(1, -(isSmall and 150 or 182), 0.5, -(isSmall and 28 or 32)),
		ax = Enum.TextXAlignment.Center,
		ts = isSmall and 13 or 15,
		font = F.NORMAL,
		color = C.DIM,
		parent = detailPanel,
	})

	-- 디테일: 해금 버튼
	local unlockBtn = Utils.mkBtn({
		name = "DetailUnlockBtn",
		text = "해금",
		size = UDim2.new(0, isSmall and 95 or 120, 0, isSmall and 38 or 46),
		pos = UDim2.new(1, -(isSmall and 105 or 132), 0.5, (isSmall and 2 or 4)),
		bg = Color3.fromRGB(55, 50, 35),
		bgT = 0.1,
		ts = isSmall and 17 or 21,
		font = F.TITLE,
		color = C.WHITE,
		r = 6,
		stroke = true,
		strokeC = C.BORDER_DIM,
		vis = false,
		parent = detailPanel,
	})
	unlockBtn.MouseButton1Click:Connect(function()
		if not skillController or not selectedSkillId then return end
		_tryUnlockSkill(selectedSkillId)
	end)

	-- 디테일: 슬롯 할당 버튼 (Q / F / V) — 해금된 액티브 스킬 전용
	local SLOT_KEYS = { "Q", "F", "V" }
	local SLOT_COLORS = {
		Color3.fromRGB(80, 140, 220),
		Color3.fromRGB(220, 160, 60),
		Color3.fromRGB(180, 80, 200),
	}
	for si = 1, 3 do
		local slotBtn = Utils.mkBtn({
			name = "SlotBtn" .. si,
			text = SLOT_KEYS[si],
			size = UDim2.new(0, isSmall and 44 or 52, 0, isSmall and 36 or 42),
			pos = UDim2.new(1, -(isSmall and 150 or 185) + (si - 1) * (isSmall and 48 or 58), 0.5, isSmall and 2 or 4),
			bg = Color3.fromRGB(45, 42, 35),
			bgT = 0.15,
			ts = isSmall and 16 or 19,
			font = F.TITLE,
			color = C.WHITE,
			r = 6,
			stroke = true,
			strokeC = C.BORDER_DIM,
			vis = false,
			parent = detailPanel,
		})
		local slotIndex = si
		slotBtn.MouseButton1Click:Connect(function()
			if not skillController or not selectedSkillId then return end
			local skill = SkillTreeData.GetSkill(selectedSkillId)
			if not skill or skill.type ~= "ACTIVE" then return end
			if not skillController.isSkillUnlocked(selectedSkillId) then return end

			-- 이미 같은 슬롯이면 해제, 아니면 할당
			local currentSlots = skillController.getActiveSkillSlots()
			if currentSlots[slotIndex] == selectedSkillId then
				skillController.requestSetSlot(slotIndex, nil)
			else
				skillController.requestSetSlot(slotIndex, selectedSkillId)
			end
		end)
	end

	-- ============ 택1 확인 다이얼로그 (오버레이) ============
	local confirmDialog = Utils.mkFrame({
		name = "ConfirmDialog",
		size = UDim2.new(1, 0, 1, 0),
		bg = C.BG_OVERLAY,
		bgT = 0.3,
		vis = false,
		parent = SkillTreeUI.Refs.Frame,
	})
	confirmDialog.ZIndex = 10
	SkillTreeUI.Refs.ConfirmDialog = confirmDialog

	local confirmPanel = Utils.mkWindow({
		name = "ConfirmPanel",
		size = UDim2.new(0, isSmall and 300 or 380, 0, isSmall and 180 or 200),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.15,
		r = 8,
		stroke = 2,
		strokeC = C.RED,
		parent = confirmDialog,
	})
	confirmPanel.ZIndex = 11

	Utils.mkLabel({
		name = "ConfirmTitle",
		text = "⚠ 전투 계열 선택",
		size = UDim2.new(1, 0, 0, 30),
		pos = UDim2.new(0, 0, 0, 10),
		ts = isSmall and 16 or 18,
		font = F.TITLE,
		color = C.ORANGE,
		z = 12,
		parent = confirmPanel,
	})

	Utils.mkLabel({
		name = "Message",
		text = "",
		size = UDim2.new(1, -24, 0, isSmall and 70 or 80),
		pos = UDim2.new(0, 12, 0, 42),
		ts = isSmall and 11 or 13,
		font = F.NORMAL,
		color = C.WHITE,
		wrap = true,
		z = 12,
		parent = confirmPanel,
	})

	-- 확인 버튼
	Utils.mkBtn({
		name = "YesBtn",
		text = "선택 확정",
		size = UDim2.new(0, isSmall and 100 or 120, 0, isSmall and 32 or 36),
		pos = UDim2.new(0.5, -(isSmall and 110 or 130), 1, -(isSmall and 40 or 46)),
		bg = C.BG_SLOT_SEL,
		bgT = 0.2,
		ts = isSmall and 13 or 15,
		font = F.TITLE,
		color = C.GOLD,
		r = 6,
		stroke = true,
		strokeC = C.GOLD,
		z = 12,
		fn = _onConfirmYes,
		parent = confirmPanel,
	})

	-- 취소 버튼
	Utils.mkBtn({
		name = "NoBtn",
		text = "취소",
		size = UDim2.new(0, isSmall and 80 or 100, 0, isSmall and 32 or 36),
		pos = UDim2.new(0.5, 10, 1, -(isSmall and 40 or 46)),
		bg = C.BTN,
		bgT = 0.3,
		ts = isSmall and 13 or 15,
		font = F.NORMAL,
		color = C.GRAY,
		r = 6,
		z = 12,
		fn = _hideConfirmDialog,
		parent = confirmPanel,
	})

	-- 리사이즈 핸들러 (창 크기 변경 시 자동 재렌더)
	local resizeDebounce = false
	main:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if resizeDebounce then return end
		resizeDebounce = true
		task.defer(function()
			task.wait(0.1)
			resizeDebounce = false
			if SkillTreeUI.IsVisible() then
				SkillTreeUI.Refresh()
				_layoutDetailPanel()
			end
		end)
	end)

	-- 초기 탭 선택 (렌더링 대기)
	task.defer(function()
		selectTab(1)
	end)
end

----------------------------------------------------------------
-- Public API
----------------------------------------------------------------
function SkillTreeUI.SetVisible(visible)
	if SkillTreeUI.Refs.Frame then
		SkillTreeUI.Refs.Frame.Visible = visible
		if visible then
			SkillTreeUI.Refresh()
		end
	end
end

function SkillTreeUI.IsVisible()
	return SkillTreeUI.Refs.Frame and SkillTreeUI.Refs.Frame.Visible or false
end

function SkillTreeUI.Refresh()
	_updateSPLabel()
	if SkillTreeUI.Refs.NodeArea then
		_renderSkillNodes(SkillTreeUI.Refs.NodeArea)
	end
	_updateDetailPanel()
end

function SkillTreeUI.SetController(controller)
	skillController = controller
	-- 데이터 변경 시 자동 갱신 연결
	if controller and controller.onSkillDataUpdated then
		controller.onSkillDataUpdated(function()
			if SkillTreeUI.IsVisible() then
				SkillTreeUI.Refresh()
			end
		end)
	end
end

return SkillTreeUI
