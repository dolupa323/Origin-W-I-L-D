-- EquipmentUI.lua
-- 듀랑고 레퍼런스 스타일 장비 및 스탯 종합 UI 창

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts

local EquipmentUI = {}

EquipmentUI.Refs = {
	Frame = nil,
	Viewport = nil,
	Slots = {},
	StatPoints = nil,
	StatLines = {},
	ActionFrame = nil,
}

local _UIManager = nil -- UIManager 참조 저장용

function EquipmentUI.SetVisible(visible)
	if EquipmentUI.Refs.Frame then
		EquipmentUI.Refs.Frame.Visible = visible
	end
end

function EquipmentUI.Init(parent, UIManager, Enums)
	_UIManager = UIManager
	EquipmentUI.Refs.Frame = Utils.mkWindow({
		name = "EquipmentMenu",
		size = UDim2.new(0.6, 0, 0.7, 0), -- 가로 크기 축소
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		r = 0, stroke = 2,
		vis = false,
		ratio = 1.1, -- 가로 세로 비율 조정
		parent = parent
	})
	
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,45), bgT=1, parent=EquipmentUI.Refs.Frame})
	Utils.mkLabel({text="장비", pos=UDim2.new(0, 15, 0, 0), ts=24, font=F.TITLE, ax=Enum.TextXAlignment.Left, parent=header})
	Utils.mkBtn({text="X", size=UDim2.new(0, 30, 0, 30), pos=UDim2.new(1, -15, 0, 7), anchor=Vector2.new(1,0), bgT=1, ts=26, color=C.WHITE, fn=function() UIManager.closeEquipment() end, parent=header})
	
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -55), pos=UDim2.new(0, 10, 0, 45), bgT=1, parent=EquipmentUI.Refs.Frame})
	
	-- [Left: Equip Slots] (40%)
	local eqArea = Utils.mkFrame({name="EquipArea", size=UDim2.new(0.4, -10, 1, 0), pos=UDim2.new(0, 0, 0, 0), bgT=1, parent=content})
	local eList = Instance.new("UIListLayout"); eList.Padding=UDim.new(0,10); eList.HorizontalAlignment=Enum.HorizontalAlignment.Center; eList.Parent=eqArea
	
	local slotConfigs = {
		{id="Head"},
		{id="Body"},
		{id="Feet"},
		{id="Hand"}
	}
	for _, conf in ipairs(slotConfigs) do
		local slot = Utils.mkSlot({name=conf.id.."Slot", size=UDim2.new(0,80,0,80), bgT=0.3, stroke=1, parent=eqArea})
		EquipmentUI.Refs.Slots[conf.id] = slot
	end
	
	-- [Right: Stats Distribution] (60%)
	local statArea = Utils.mkFrame({name="StatArea", size=UDim2.new(0.6, 0, 1, 0), pos=UDim2.new(1, 0, 0, 0), anchor=Vector2.new(1,0), bg=C.BG_PANEL_L, parent=content})
	EquipmentUI.Refs.StatPoints = Utils.mkLabel({text="보유 포인트: 0", size=UDim2.new(1, -20, 0, 40), pos=UDim2.new(0,10,0,0), ts=18, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=statArea})
	
	local sList = Utils.mkFrame({size=UDim2.new(1,-20,1,-120), pos=UDim2.new(0,10,0,50), bgT=1, parent=statArea})
	local sLayout = Instance.new("UIListLayout"); sLayout.Padding=UDim.new(0, 5); sLayout.Parent=sList
	
	local stats = {
		{id=Enums.StatId.MAX_HEALTH, name="최대 체력"}, 
		{id=Enums.StatId.MAX_STAMINA, name="최대 스태미나"}, 
		{id=Enums.StatId.WEIGHT, name="최대 소지 무게"}, 
		{id=Enums.StatId.WORK_SPEED, name="작업 속도"}, 
		{id=Enums.StatId.ATTACK, name="공격력"}
	}
	for _, s in ipairs(stats) do
		local line = Utils.mkFrame({size=UDim2.new(1,0,0,45), bg=C.BG_SLOT, bgT=0.3, parent=sList})
		Utils.mkLabel({text=s.name, size=UDim2.new(0.4,0,1,0), pos=UDim2.new(0,10,0,0), ts=14, ax=Enum.TextXAlignment.Left, parent=line})
		local val = Utils.mkLabel({text="0", size=UDim2.new(0.4,0,1,0), pos=UDim2.new(0.8,-40,0,0), anchor=Vector2.new(1,0), ts=15, font=F.NUM, ax=Enum.TextXAlignment.Right, parent=line})
		
		local btn = Utils.mkBtn({text="+", size=UDim2.new(0,35,0,35), pos=UDim2.new(1,-5,0.5,0), anchor=Vector2.new(1,0.5), bg=C.GOLD_SEL, ts=20, font=F.NUM, parent=line})
		
		btn.MouseButton1Click:Connect(function() UIManager.addPendingStat(s.id) end)
		EquipmentUI.Refs.StatLines[s.id] = {val=val, btn=btn}
	end
	
	-- Action Frame (Apply/Cancel) at the bottom right
	local actionFrame = Utils.mkFrame({size=UDim2.new(1,-20,0,50), pos=UDim2.new(0,10,1,-15), anchor=Vector2.new(0,1), bgT=1, vis=false, parent=statArea})
	EquipmentUI.Refs.ActionFrame = actionFrame
	local aList = Instance.new("UIListLayout"); aList.FillDirection=Enum.FillDirection.Horizontal; aList.Padding=UDim.new(0,10); aList.HorizontalAlignment=Enum.HorizontalAlignment.Center; aList.Parent=actionFrame
	
	Utils.mkBtn({text="적용", size=UDim2.new(0.48,0,1,0), bg=C.GREEN, font=F.TITLE, color=C.BG_PANEL, fn=function() UIManager.confirmPendingStats() end, parent=actionFrame})
	Utils.mkBtn({text="초기화", size=UDim2.new(0.48,0,1,0), bg=C.BTN, font=F.TITLE, fn=function() UIManager.cancelPendingStats() end, parent=actionFrame})
end

function EquipmentUI.Refresh(cachedStats, totalPending, equipmentData, getItemIcon, Enums)
	local refs = EquipmentUI.Refs
	if not refs.Frame or not refs.Frame.Visible then return end
	
	-- 장비 아이콘 업데이트
	if equipmentData then
		for name, slot in pairs(refs.Slots) do
			local item = equipmentData[name]
			if item then
				slot.icon.Image = getItemIcon(item.itemId)
				slot.icon.Visible = true
			else
				slot.icon.Image = ""
				slot.icon.Visible = false
			end
		end
	end
	
	-- 스탯 업데이트
	if not cachedStats then return end
	local available = (cachedStats.statPointsAvailable or 0) - (totalPending or 0)
	refs.StatPoints.Text = "남은 강화 포인트: " .. available
	
	local calc = cachedStats.calculated or {}
	local invested = cachedStats.statInvested or {}
	
	for statId, line in pairs(refs.StatLines) do
		local valText = ""
		local baseValue = 0
		if statId == Enums.StatId.MAX_HEALTH then baseValue = calc.maxHealth or 100; valText = string.format("%d HP", baseValue)
		elseif statId == Enums.StatId.MAX_STAMINA then baseValue = calc.maxStamina or 100; valText = string.format("%d STA", baseValue)
		elseif statId == Enums.StatId.WEIGHT then baseValue = calc.maxWeight or 300; valText = string.format("%.1f kg", baseValue)
		elseif statId == Enums.StatId.WORK_SPEED then baseValue = calc.workSpeed or 100; valText = string.format("%d%%", baseValue)
		elseif statId == Enums.StatId.ATTACK then baseValue = (calc.attackMult or 1.0) * 100; valText = string.format("%.0f%%", baseValue) end
		
		-- PendingStats: 저장된 UIManager 참조 사용
		local added = _UIManager and _UIManager.getPendingStatCount(statId) or 0
		if added > 0 then
			line.val.Text = string.format("%s <font color='#8CDC64'>+%d</font>", valText, added)
			line.val.RichText = true
		else
			line.val.Text = valText
			line.val.RichText = false
		end
		line.btn.Visible = true
		line.btn.BackgroundTransparency = (available > 0) and 0 or 0.6
		line.btn.TextTransparency = (available > 0) and 0 or 0.6
		line.btn.Active = (available > 0)
	end
	
	refs.ActionFrame.Visible = (totalPending > 0)
end

function EquipmentUI.UpdateCharacterPreview(character)
	-- 실제 로블록스 캐릭터 클론 및 ViewportFrame에 렌더링 로직 (향후 구현 확장성)
	-- 캐릭터 복사 후 camera CFrame 조정 역할만 마련
end

return EquipmentUI
