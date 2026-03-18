-- EquipmentUI.lua
-- 듀랑고 레퍼런스 스타일 장비 및 스탯 종합 UI 창

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local EquipmentUI = {}

EquipmentUI.Refs = {
	Frame = nil,
	Viewport = nil,
	Slots = {},
	StatPoints = nil,
	StatLines = {},
	ActionFrame = nil,
}

local tooltipMoveConn = nil

local _UIManager = nil -- UIManager 참조 저장용

function EquipmentUI.SetVisible(visible)
	if EquipmentUI.Refs.Frame then
		EquipmentUI.Refs.Frame.Visible = visible
	end
end

function EquipmentUI.Init(parent, UIManager, Enums, isMobile)
	local isSmall = isMobile
	_UIManager = UIManager
	EquipmentUI.Refs.Frame = Utils.mkFrame({
		name = "EquipmentMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0, 0, 0),
		bgT = 0.7,
		vis = false,
		parent = parent
	})

	local main = Utils.mkWindow({
		name = "EquipmentMenu",
		size = UDim2.new(isSmall and 0.95 or 0.65, 0, isSmall and 0.9 or 0.8, 0),
		maxSize = Vector2.new(900, 750),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL, bgT = T.PANEL, r = 6, stroke = 1.5, strokeC = C.BORDER,
		parent = EquipmentUI.Refs.Frame
	})
	
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,50), bgT=1, parent=main})
	Utils.mkLabel({text="EQUIPMENT [E]", pos=UDim2.new(0, 15, 0, 0), ts=20, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=header})
	Utils.mkBtn({text="X", size=UDim2.new(0, 36, 0, 36), pos=UDim2.new(1, -10, 0.5, 0), anchor=Vector2.new(1,0.5), bg=C.BTN, bgT=0.5, ts=20, color=C.WHITE, r=4, fn=function() UIManager.closeEquipment() end, parent=header})
	
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -55), pos=UDim2.new(0, 10, 0, 45), bgT=1, parent=main})
	content.ClipsDescendants = true -- 캐릭터가 프레임 바깥으로 나가는 것 방지
	
	-- [Left: Character & Equip Slots] (45%)
	local eqArea = Utils.mkFrame({name="EquipArea", size=UDim2.new(0.45, -10, 1, 0), pos=UDim2.new(0, 0, 0, 0), bgT=1, parent=content})
	
	-- Slots Container
	local slotsContainer = Utils.mkFrame({name="SlotsContainer", size=UDim2.new(1, 0, 1, 0), pos=UDim2.new(0,0,0,0), bgT=1, parent=eqArea})
	local sList = Instance.new("UIListLayout")
	sList.SortOrder = Enum.SortOrder.LayoutOrder
	sList.Padding = UDim.new(0, 12)
	sList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sList.VerticalAlignment = Enum.VerticalAlignment.Center
	sList.Parent = slotsContainer
	
	local slotConfigs = {
		{id="HEAD", name="머리"},
		{id="SUIT", name="한벌옷"},
		{id="HAND", name="도구/무기"},
	}
	
	for i, conf in ipairs(slotConfigs) do
		local wrapper = Utils.mkFrame({
			name = conf.id.."Wrap",
			size = UDim2.new(0, 120, 0, 88),
			bgT = 1,
			parent = slotsContainer
		})
		wrapper.LayoutOrder = i
		
		local slot = Utils.mkSlot({
			name = conf.id.."Slot", 
			size = UDim2.new(0, 60, 0, 60),
			pos = UDim2.new(0.5, 0, 0, 0),
			anchor = Vector2.new(0.5, 0.5),
			bgT = 0.3, 
			stroke = 1, 
			parent = wrapper
		})
		
		Utils.mkLabel({
			text = UILocalizer.Localize(conf.name),
			size = UDim2.new(1, -8, 0, 24),
			pos = UDim2.new(0.5, -4, 1, -4),
			anchor = Vector2.new(0.5, 1),
			bgT = 1,
			ts = 14,
			font = F.NORMAL,
			color = C.WHITE,
			ax = Enum.TextXAlignment.Center,
			parent = wrapper
		})
		
		slot.click.MouseButton1Click:Connect(function()
			if _UIManager.onEquipmentSlotClick then _UIManager.onEquipmentSlotClick(conf.id) end
		end)
		slot.click.MouseButton2Click:Connect(function()
			if _UIManager.onEquipmentSlotRightClick then _UIManager.onEquipmentSlotRightClick(conf.id) end
		end)
		
		EquipmentUI.Refs.Slots[conf.id] = slot
	end
	
	-- [Right: Stats Distribution] (55%)
	local statArea = Utils.mkFrame({name="StatArea", size=UDim2.new(0.55, 0, 1, 0), pos=UDim2.new(1, 0, 0, 0), anchor=Vector2.new(1,0), bg=C.BG_PANEL_L, parent=content})
	EquipmentUI.Refs.StatPoints = Utils.mkLabel({text=UILocalizer.Localize("보유 포인트: 0"), size=UDim2.new(1, -20, 0, 40), pos=UDim2.new(0,10,0,0), ts=18, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=statArea})
	
	local statsScroll = Instance.new("ScrollingFrame")
	statsScroll.Size = UDim2.new(1,-20,1,-120); statsScroll.Position = UDim2.new(0,10,0,50); statsScroll.BackgroundTransparency = 1; statsScroll.BorderSizePixel = 0; statsScroll.ScrollBarThickness = 2; statsScroll.Parent = statArea
	local sLayout = Instance.new("UIListLayout"); sLayout.Padding=UDim.new(0, 5); sLayout.Parent=statsScroll
	
	local stats = {
		{id=Enums.StatId.MAX_HEALTH, name="최대 체력", up=true}, 
		{id=Enums.StatId.MAX_STAMINA, name="최대 스태미나", up=true}, 
		{id=Enums.StatId.WEIGHT, name="최대 소지 무게", up=true}, 
		{id=Enums.StatId.WORK_SPEED, name="작업 속도", up=true}, 
		{id=Enums.StatId.ATTACK, name="공격력", up=true},
		{id=Enums.StatId.DEFENSE, name="방어력", up=false}
	}
	for _, s in ipairs(stats) do
		-- 스텟 라인 크기 비율화 (0.18 Scale)
		local line = Utils.mkFrame({size=UDim2.new(1, 0, 0, 50), bg=C.BG_SLOT, bgT=0.3, parent=statsScroll})
		Utils.mkLabel({text=UILocalizer.Localize(s.name), size=UDim2.new(0.4,0,1,0), pos=UDim2.new(0,10,0,0), ts=14, ax=Enum.TextXAlignment.Left, parent=line})
		local val = Utils.mkLabel({text="0", size=UDim2.new(0.4,0,1,0), pos=UDim2.new(0.8,-40,0,0), anchor=Vector2.new(1,0), ts=15, font=F.NUM, ax=Enum.TextXAlignment.Right, parent=line})
		
		-- 강화 버튼: 필요한 스탯에만 노출
		local btn = nil
		if s.up then
			local bSize = isSmall and 40 or 35
			btn = Utils.mkBtn({
				text="+", 
				size=UDim2.new(0, bSize, 0.8, 0), -- 가로 오프셋 고정, 세로 비율 유지
				pos=UDim2.new(1, -10, 0.5, 0), 
				anchor=Vector2.new(1, 0.5), 
				bg=C.GOLD_SEL, 
				ts=isSmall and 24 or 20, 
				font=F.NUM, 
				parent=line
			})
			
			-- 텍스트가 잘리지 않도록 설정
			btn.TextScaled = false
			btn.TextWrapped = false
	
			btn.MouseButton1Click:Connect(function() UIManager.addPendingStat(s.id) end)
		else
			-- 강화 불가 스탯은 값 라벨을 오른쪽 끝으로 정렬
			val.Position = UDim2.new(1, -10, 0, 0)
		end
		
		EquipmentUI.Refs.StatLines[s.id] = {val=val, btn=btn}
	end
	
	-- Action Frame (Apply/Cancel) 가변 비율 조정
	local actionFrame = Utils.mkFrame({size=UDim2.new(1,-20,0.15,0), pos=UDim2.new(0,10,1,-5), anchor=Vector2.new(0,1), bgT=1, vis=false, parent=statArea})
	EquipmentUI.Refs.ActionFrame = actionFrame
	local aList = Instance.new("UIListLayout"); aList.FillDirection=Enum.FillDirection.Horizontal; aList.Padding=UDim.new(0.05,0); aList.HorizontalAlignment=Enum.HorizontalAlignment.Center; aList.VerticalAlignment=Enum.VerticalAlignment.Center; aList.Parent=actionFrame

	Utils.mkBtn({text=UILocalizer.Localize("적용"), size=UDim2.new(0.45,0,0.8,0), bg=C.GREEN, font=F.TITLE, color=C.BG_PANEL, fn=function() UIManager.confirmPendingStats() end, parent=actionFrame})
	Utils.mkBtn({text=UILocalizer.Localize("초기화"), size=UDim2.new(0.45,0,0.8,0), bg=C.BTN, font=F.TITLE, fn=function() UIManager.cancelPendingStats() end, parent=actionFrame})
	
	-- [New] Tooltip Frame (Initially Hidden)
	EquipmentUI.Refs.Tooltip = Utils.mkFrame({
		name = "Tooltip",
		size = UDim2.new(0, 220, 0, 160),
		bg = Color3.fromRGB(10, 10, 12),
		bgT = 0.2,
		r = 6, stroke = 1, strokeC = C.GOLD,
		vis = false,
		parent = parent -- ScreenGui parent to show above everything
	})
	EquipmentUI.Refs.Tooltip.ZIndex = 100
	
	local tt = EquipmentUI.Refs.Tooltip
	EquipmentUI.Refs.TooltipName = Utils.mkLabel({text=UILocalizer.Localize("아이템 이름"), size=UDim2.new(1,-20,0,30), pos=UDim2.new(0,10,0,5), ts=16, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=tt})
	EquipmentUI.Refs.TooltipInfo = Utils.mkLabel({text=UILocalizer.Localize("정보"), size=UDim2.new(1,-20,1,-70), pos=UDim2.new(0,10,0,35), ts=14, color=C.WHITE, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, rich=true, parent=tt})
	EquipmentUI.Refs.TooltipSet = Utils.mkLabel({text=UILocalizer.Localize("[ 세트 효과 ]"), size=UDim2.new(1,-20,0,30), pos=UDim2.new(0,10,1,-5), anchor=Vector2.new(0,1), ts=13, color=Color3.fromRGB(150, 255, 150), ax=Enum.TextXAlignment.Left, wrap=true, rich=true, parent=tt})

	if tooltipMoveConn then
		tooltipMoveConn:Disconnect()
		tooltipMoveConn = nil
	end
	tooltipMoveConn = game:GetService("RunService").RenderStepped:Connect(function()
		if EquipmentUI.Refs.Tooltip and EquipmentUI.Refs.Tooltip.Visible then
			local mousePos = game:GetService("UserInputService"):GetMouseLocation()
			EquipmentUI.Refs.Tooltip.Position = UDim2.new(0, mousePos.X + 20, 0, mousePos.Y + 20)
		end
	end)
end

function EquipmentUI.Refresh(cachedStats, totalPending, equipmentData, getItemIcon, Enums)
	local refs = EquipmentUI.Refs
	if not refs.Frame or not refs.Frame.Visible then return end
	
	-- 장비 아이콘 업데이트 및 호버 이벤트
	if equipmentData then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local ArmorSetData = require(ReplicatedStorage:WaitForChild("Data").ArmorSetData)
		local DataHelper = require(ReplicatedStorage:WaitForChild("Shared").Util.DataHelper)
		
		for name, slot in pairs(refs.Slots) do
			if slot._hoverConnEnter then
				slot._hoverConnEnter:Disconnect()
				slot._hoverConnEnter = nil
			end
			if slot._hoverConnLeave then
				slot._hoverConnLeave:Disconnect()
				slot._hoverConnLeave = nil
			end

			local item = equipmentData[name]
			if item then
				slot.icon.Image = getItemIcon(item.itemId)
				slot.icon.Visible = true
				
				local itemData = DataHelper.GetData("ItemData", item.itemId) or { id = item.itemId, name = item.itemId, type = "UNKNOWN", rarity = "COMMON" }
				
				-- 내구도 바
				if item.durability and itemData and itemData.durability then
					local ratio = math.clamp(item.durability / itemData.durability, 0, 1)
					slot.durBg.Visible = true
					slot.durFill.Size = UDim2.new(ratio, 0, 1, 0)
					if ratio > 0.5 then slot.durFill.BackgroundColor3 = Color3.fromRGB(150, 255, 150)
					elseif ratio > 0.2 then slot.durFill.BackgroundColor3 = Color3.fromRGB(255, 200, 100)
					else slot.durFill.BackgroundColor3 = Color3.fromRGB(255, 100, 100) end
				else
					if slot.durBg then slot.durBg.Visible = false end
				end
				
				-- 툴팁 이벤트 연결
				slot._hoverConnEnter = slot.click.MouseEnter:Connect(function()
					if not EquipmentUI.Refs.Tooltip then return end
					EquipmentUI.Refs.Tooltip.Visible = true
					EquipmentUI.Refs.TooltipName.Text = UILocalizer.Localize(itemData.name)

					local info = string.format("%s: %s", UILocalizer.Localize("등급"), itemData.rarity or "COMMON")
					if itemData.type == "ARMOR" then
						info = info .. string.format("\n%s: %d", UILocalizer.Localize("방어력"), itemData.defense or 0)
					elseif itemData.type == "TOOL" or itemData.type == "WEAPON" then
						info = info .. string.format("\n%s: %d", UILocalizer.Localize("공격력"), itemData.damage or 0)
					end

					if itemData.durability then
						info = info .. string.format("\n%s: %d/%d", UILocalizer.Localize("내구도"), item.durability or 0, itemData.durability or 0)
					end

					if itemData.description and itemData.description ~= "" then
						info = info .. string.format("\n\n%s", UILocalizer.Localize(itemData.description))
					end

					EquipmentUI.Refs.TooltipInfo.Text = UILocalizer.Localize(info)
					
					if itemData.armorSet then
						local setData = ArmorSetData[itemData.armorSet]
						if setData then
							EquipmentUI.Refs.TooltipSet.Text = string.format("<b>[%s]</b>\n%s", UILocalizer.Localize(setData.name), UILocalizer.Localize(setData.bonusText))
							EquipmentUI.Refs.TooltipSet.Visible = true
						else
							EquipmentUI.Refs.TooltipSet.Visible = false
						end
					else
						EquipmentUI.Refs.TooltipSet.Visible = false
					end
				end)
				
				slot._hoverConnLeave = slot.click.MouseLeave:Connect(function()
					if EquipmentUI.Refs.Tooltip then EquipmentUI.Refs.Tooltip.Visible = false end
				end)
			else
				slot.icon.Image = ""
				slot.icon.Visible = false
				if slot.durBg then slot.durBg.Visible = false end
			end
		end
	end
	
	-- 스탯 업데이트
	if not cachedStats then return end
	local available = (cachedStats.statPointsAvailable or 0) - (totalPending or 0)
	refs.StatPoints.Text = UILocalizer.Localize("남은 강화 포인트: " .. available)
	
	local calc = cachedStats.calculated or {}
	local invested = cachedStats.statInvested or {}
	
	for statId, line in pairs(refs.StatLines) do
		local valText = ""
		local baseValue = 0
		if statId == Enums.StatId.MAX_HEALTH then baseValue = calc.maxHealth or 100; valText = string.format("%d HP", baseValue)
		elseif statId == Enums.StatId.MAX_STAMINA then baseValue = calc.maxStamina or 100; valText = string.format("%d STA", baseValue)
		elseif statId == Enums.StatId.WEIGHT then baseValue = calc.maxWeight or 300; valText = string.format("%.1f kg", baseValue)
		elseif statId == Enums.StatId.WORK_SPEED then baseValue = calc.workSpeed or 100; valText = string.format("%d%%", baseValue)
		elseif statId == Enums.StatId.ATTACK then baseValue = (calc.attackMult or 1.0) * 100; valText = string.format("%.0f%%", baseValue)
		elseif statId == Enums.StatId.DEFENSE then baseValue = calc.defense or 0; valText = string.format("%d", baseValue) end
		
		-- PendingStats: 저장된 UIManager 참조 사용
		local added = _UIManager and _UIManager.getPendingStatCount(statId) or 0
		if added > 0 then
			line.val.Text = string.format("%s <font color='#8CDC64'>+%d</font>", valText, added)
			line.val.RichText = true
		else
			line.val.Text = valText
			line.val.RichText = false
		end
		
		if line.btn then
			line.btn.Visible = true
			line.btn.BackgroundTransparency = (available > 0) and 0 or 0.6
			line.btn.TextTransparency = (available > 0) and 0 or 0.6
			line.btn.Active = (available > 0)
		end
	end
	
	refs.ActionFrame.Visible = (totalPending > 0)
end

function EquipmentUI.UpdateCharacterPreview(character)
	-- [제거됨] 유저 요청으로 장비창 내 캐릭터 미리보기 기능 완전 삭제
end

return EquipmentUI
