-- EquipmentUI.lua
-- 듀랑고 레퍼런스 스타일 장비 및 스탯 종합 UI 창

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MaterialAttributeData = require(ReplicatedStorage:WaitForChild("Data").MaterialAttributeData)

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
	if not visible and EquipmentUI.Refs.Tooltip then
		EquipmentUI.Refs.Tooltip.Visible = false
	end
end

function EquipmentUI.Init(parent, UIManager, Enums, isMobile)
	local isSmall = isMobile
	_UIManager = UIManager
	EquipmentUI.Refs.Frame = Utils.mkFrame({
		name = "EquipmentMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = C.BG_OVERLAY,
		bgT = 0.5,
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
			local now = tick()
			if slot._lastClickTime and (now - slot._lastClickTime) < 0.4 then
				-- 더블클릭 → 장비 해제
				if _UIManager.onEquipmentSlotRightClick then _UIManager.onEquipmentSlotRightClick(conf.id) end
				slot._lastClickTime = nil
			else
				slot._lastClickTime = now
				if _UIManager.onEquipmentSlotClick then _UIManager.onEquipmentSlotClick(conf.id) end
			end
		end)
		slot.click.MouseButton2Click:Connect(function()
			if _UIManager.onEquipmentSlotRightClick then _UIManager.onEquipmentSlotRightClick(conf.id) end
		end)
		
		EquipmentUI.Refs.Slots[conf.id] = slot
	end
	
	-- [Right: Stats Distribution] (55%)
	local statArea = Utils.mkFrame({name="StatArea", size=UDim2.new(0.55, 0, 1, 0), pos=UDim2.new(1, 0, 0, 0), anchor=Vector2.new(1,0), bg=C.BG_PANEL_L, parent=content})
	EquipmentUI.Refs.StatPoints = Utils.mkLabel({text=UILocalizer.Localize("보유 포인트: 0"), size=UDim2.new(1, -110, 0, 40), pos=UDim2.new(0,10,0,0), ts=18, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=statArea})
	
	-- 전부 초기화 버튼 (StatPoints 라벨 오른쪽)
	EquipmentUI.Refs.ResetAllBtn = Utils.mkBtn({
		text=UILocalizer.Localize("초기화"),
		size=UDim2.new(0, 90, 0, 30),
		pos=UDim2.new(1, -10, 0, 5),
		anchor=Vector2.new(1, 0),
		bg=C.RED or Color3.fromRGB(200, 60, 60),
		ts=13,
		font=F.TITLE,
		parent=statArea
	})
	EquipmentUI.Refs.ResetAllBtn.MouseButton1Click:Connect(function()
		if UIManager.resetAllStats then UIManager.resetAllStats() end
	end)
	
	local statsScroll = Instance.new("ScrollingFrame")
	statsScroll.Size = UDim2.new(1,-20,1,-120); statsScroll.Position = UDim2.new(0,10,0,50); statsScroll.BackgroundTransparency = 1; statsScroll.BorderSizePixel = 0; statsScroll.ScrollBarThickness = 2; statsScroll.Parent = statArea
	local sLayout = Instance.new("UIListLayout"); sLayout.Padding=UDim.new(0, 5); sLayout.Parent=statsScroll
	
	local stats = {
		{id=Enums.StatId.MAX_HEALTH, name="최대 체력", up=true}, 
		{id=Enums.StatId.MAX_STAMINA, name="최대 스태미나", up=true}, 
		{id=Enums.StatId.INV_SLOTS, name="인벤토리 칸", up=true}, 
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
	local TT_W = 280
	EquipmentUI.Refs.Tooltip = Utils.mkFrame({
		name = "Tooltip",
		size = UDim2.new(0, TT_W, 0, 40),
		bg = C.BG_DARK,
		bgT = 0.08,
		r = 6, stroke = 1.5, strokeC = C.GOLD,
		vis = false,
		parent = parent
	})
	EquipmentUI.Refs.Tooltip.ZIndex = 100
	EquipmentUI.Refs.Tooltip.AutomaticSize = Enum.AutomaticSize.Y
	
	local tt = EquipmentUI.Refs.Tooltip
	
	-- 내부 레이아웃 컨테이너
	local ttContent = Instance.new("Frame")
	ttContent.Name = "Content"
	ttContent.Size = UDim2.new(1, -16, 0, 0)
	ttContent.Position = UDim2.new(0, 8, 0, 8)
	ttContent.BackgroundTransparency = 1
	ttContent.AutomaticSize = Enum.AutomaticSize.Y
	ttContent.Parent = tt
	
	-- 하단 패딩용
	local ttPadding = Instance.new("UIPadding")
	ttPadding.PaddingBottom = UDim.new(0, 10)
	ttPadding.Parent = tt
	
	local ttLayout = Instance.new("UIListLayout")
	ttLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ttLayout.Padding = UDim.new(0, 3)
	ttLayout.Parent = ttContent
	EquipmentUI.Refs.TooltipContent = ttContent
	EquipmentUI.Refs.TooltipLayout = ttLayout

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
		local ArmorSetData = require(ReplicatedStorage:WaitForChild("Data").ArmorSetData)
		local DataHelper = require(ReplicatedStorage:WaitForChild("Shared").Util.DataHelper)
		
		-- 현재 장착 중인 아이템 ID 목록 (세트효과 판정용)
		local equippedItemIds = {}
		for _, eqItem in pairs(equipmentData) do
			if eqItem and eqItem.itemId then
				equippedItemIds[eqItem.itemId] = true
			end
		end
		
		for name, slot in pairs(refs.Slots) do
			if slot._hoverConnEnter then
				slot._hoverConnEnter:Disconnect()
				slot._hoverConnEnter = nil
			end
			if slot._hoverConnLeave then
				slot._hoverConnLeave:Disconnect()
				slot._hoverConnLeave = nil
			end

			if slot._hoverConnLeave2 then
				slot._hoverConnLeave2:Disconnect()
				slot._hoverConnLeave2 = nil
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
					if ratio > 0.5 then slot.durFill.BackgroundColor3 = Color3.fromRGB(120, 200, 80)
					elseif ratio > 0.2 then slot.durFill.BackgroundColor3 = Color3.fromRGB(230, 180, 60)
					else slot.durFill.BackgroundColor3 = Color3.fromRGB(200, 70, 50) end
				else
					if slot.durBg then slot.durBg.Visible = false end
				end
				
				-- 툴팁 이벤트 연결
				slot._hoverConnEnter = slot.click.MouseEnter:Connect(function()
					local ttRef = EquipmentUI.Refs.Tooltip
					local ttCont = EquipmentUI.Refs.TooltipContent
					if not ttRef or not ttCont then return end
					
					-- 기존 행 정리
					for _, child in ipairs(ttCont:GetChildren()) do
						if child:IsA("Frame") or child:IsA("TextLabel") then child:Destroy() end
					end
					
					local order = 0
					local TT_TS = 13 -- 툴팁 텍스트 사이즈
					
					-- 헬퍼: 제목 라벨
					local function addTitle(text, color, fontSize)
						order = order + 1
						local lbl = Instance.new("TextLabel")
						lbl.Name = "TT_" .. order
						lbl.Size = UDim2.new(1, 0, 0, fontSize + 6)
						lbl.BackgroundTransparency = 1
						lbl.Text = text
						lbl.TextColor3 = color
						lbl.TextSize = fontSize
						lbl.Font = F.TITLE
						lbl.TextXAlignment = Enum.TextXAlignment.Left
						lbl.LayoutOrder = order
						lbl.Parent = ttCont
					end
					
					-- 헬퍼: 스탯 행 (라벨 + 값)
					local function addStatRow(label, value, hexColor)
						order = order + 1
						local row = Instance.new("Frame")
						row.Name = "Row_" .. order
						row.Size = UDim2.new(1, 0, 0, TT_TS + 4)
						row.BackgroundTransparency = 1
						row.LayoutOrder = order
						row.Parent = ttCont
						
						local nameL = Instance.new("TextLabel")
						nameL.Size = UDim2.new(0.55, 0, 1, 0)
						nameL.BackgroundTransparency = 1
						nameL.Text = label
						nameL.TextColor3 = Color3.fromHex("#AAAAAA")
						nameL.TextSize = TT_TS
						nameL.Font = F.NORMAL
						nameL.TextXAlignment = Enum.TextXAlignment.Left
						nameL.Parent = row
						
						local valL = Instance.new("TextLabel")
						valL.Size = UDim2.new(0.45, 0, 1, 0)
						valL.Position = UDim2.new(0.55, 0, 0, 0)
						valL.BackgroundTransparency = 1
						valL.Text = value
						valL.TextColor3 = Color3.fromHex(hexColor)
						valL.TextSize = TT_TS
						valL.Font = F.TITLE
						valL.TextXAlignment = Enum.TextXAlignment.Left
						valL.Parent = row
					end
					
					-- 헬퍼: 구분선
					local function addSep()
						order = order + 1
						local sep = Instance.new("Frame")
						sep.Name = "Sep_" .. order
						sep.Size = UDim2.new(1, 0, 0, 1)
						sep.BackgroundColor3 = Color3.fromHex("#555555")
						sep.BackgroundTransparency = 0.5
						sep.BorderSizePixel = 0
						sep.LayoutOrder = order
						sep.Parent = ttCont
					end
					
					local iType = itemData.type
					
					-- 아이템 이름
					addTitle(itemData.name, C.GOLD, 15)
					
					-- 등급
					addStatRow("등급", itemData.rarity or "COMMON", "#CCCCCC")
					addSep()
					
					-- =====================
					-- 무기/도구 스탯
					-- =====================
					if iType == "WEAPON" or iType == "TOOL" then
						local bonusDmg, bonusCrit, bonusCritDmg, bonusDur = 0, 0, 0, 0
						if item.attributes then
							for attrId, level in pairs(item.attributes) do
								local fx = MaterialAttributeData.getEffectValues(attrId, level)
								if fx then
									bonusDmg = bonusDmg + (fx.damageMult or 0)
									bonusCrit = bonusCrit + (fx.critChance or 0)
									bonusCritDmg = bonusCritDmg + (fx.critDamageMult or 0)
									bonusDur = bonusDur + (fx.durabilityMult or 0)
								end
							end
						end
						
						local baseDmg = itemData.damage or 0
						local finalDmg = math.floor(baseDmg * (1 + bonusDmg) + 0.5)
						local finalCrit = math.floor(bonusCrit * 100 + 0.5)
						local finalCritDmg = math.floor((1.5 + bonusCritDmg) * 100 + 0.5)
						local baseDur = itemData.durability or 0
						local curDur = item.durability or baseDur
						local maxDur = math.floor(baseDur * (1 + bonusDur) + 0.5)
						
						addStatRow("공격력", tostring(finalDmg), bonusDmg > 0 and "#8CDC64" or "#FFFFFF")
						addStatRow("치명타 확률", finalCrit .. "%", bonusCrit > 0 and "#8CDC64" or "#FFFFFF")
						addStatRow("치명타 피해량", finalCritDmg .. "%", bonusCritDmg > 0 and "#8CDC64" or "#FFFFFF")
						addStatRow("내구도", math.floor(curDur) .. " / " .. maxDur, bonusDur > 0 and "#8CDC64" or "#FFFFFF")
						
					-- =====================
					-- 방어구 스탯
					-- =====================
					elseif iType == "ARMOR" then
						local bonusDef, bonusHp, bonusDur = 0, 0, 0
						local bonusHeat, bonusCold, bonusHumid = 0, 0, 0
						if item.attributes then
							for attrId, level in pairs(item.attributes) do
								local fx = MaterialAttributeData.getEffectValues(attrId, level)
								if fx then
									bonusDef = bonusDef + (fx.defenseMult or 0)
									bonusHp = bonusHp + (fx.maxHealthMult or 0)
									bonusDur = bonusDur + (fx.durabilityMult or 0)
									bonusHeat = bonusHeat + (fx.heatResist or 0)
									bonusCold = bonusCold + (fx.coldResist or 0)
									bonusHumid = bonusHumid + (fx.humidResist or 0)
								end
							end
						end
						
						local baseDef = itemData.defense or 0
						local finalDef = math.floor(baseDef * (1 + bonusDef) + 0.5)
						local finalHp = math.floor(bonusHp * 100 + 0.5)
						local baseDur = itemData.durability or 0
						local curDur = item.durability or baseDur
						local maxDur = math.floor(baseDur * (1 + bonusDur) + 0.5)
						
						addStatRow("방어력", tostring(finalDef), bonusDef > 0 and "#8CDC64" or "#FFFFFF")
						addStatRow("추가 체력", "+" .. finalHp .. "%", bonusHp > 0 and "#8CDC64" or "#FFFFFF")
						addStatRow("내구도", math.floor(curDur) .. " / " .. maxDur, bonusDur > 0 and "#8CDC64" or "#FFFFFF")
						
						local heatPct = math.floor(bonusHeat * 100 + 0.5)
						local coldPct = math.floor(bonusCold * 100 + 0.5)
						local humidPct = math.floor(bonusHumid * 100 + 0.5)
						if heatPct ~= 0 then
							addStatRow("더위 내성", "+" .. heatPct .. "%", "#8CDC64")
						end
						if coldPct ~= 0 then
							addStatRow("추위 내성", "+" .. coldPct .. "%", "#8CDC64")
						end
						if humidPct ~= 0 then
							addStatRow("습기 내성", "+" .. humidPct .. "%", "#8CDC64")
						end
					else
						-- 기타 타입
						if itemData.durability then
							addStatRow("내구도", math.floor(item.durability or 0) .. " / " .. (itemData.durability or 0), "#FFFFFF")
						end
					end
					
					-- =====================
					-- 부여된 속성 효과 뱃지
					-- =====================
					if item.attributes and next(item.attributes) then
						addSep()
						local isProduct = (iType == "TOOL" or iType == "WEAPON" or iType == "ARMOR")
						for attrId, level in pairs(item.attributes) do
							local attrInfo = MaterialAttributeData.getAttribute(attrId)
							if attrInfo then
								local symbol = attrInfo.positive and "▲" or "▼"
								local displayName = isProduct and attrInfo.effect or attrInfo.name
								local hexC = attrInfo.positive and "#8CDC64" or "#E63232"
								addStatRow(symbol .. " " .. displayName, "Lv." .. level, hexC)
							end
						end
					end
					
					-- =====================
					-- 세트 효과
					-- =====================
					if itemData.armorSet then
						local setData = ArmorSetData[itemData.armorSet]
						if setData then
							addSep()
							
							-- 장착 현황 계산
							local totalPieces = #setData.items
							local equippedCount = 0
							for _, setItemId in ipairs(setData.items) do
								if equippedItemIds[setItemId] then
									equippedCount = equippedCount + 1
								end
							end
							
							local setActive = (equippedCount >= totalPieces)
							local setColor = setActive and Color3.fromRGB(120, 200, 80) or Color3.fromHex("#888888")
							
							-- 세트 이름 + 장착 현황
							order = order + 1
							local setTitle = Instance.new("TextLabel")
							setTitle.Name = "SetTitle"
							setTitle.Size = UDim2.new(1, 0, 0, TT_TS + 6)
							setTitle.BackgroundTransparency = 1
							setTitle.RichText = true
							setTitle.Text = string.format(
								"<b>세트: %s</b>  <font color='%s'>(%d/%d)</font>",
								setData.name,
								setActive and "#78C850" or "#888888",
								equippedCount, totalPieces
							)
							setTitle.TextColor3 = setColor
							setTitle.TextSize = TT_TS
							setTitle.Font = F.TITLE
							setTitle.TextXAlignment = Enum.TextXAlignment.Left
							setTitle.LayoutOrder = order
							setTitle.Parent = ttCont
							
							-- 세트 구성품 목록
							for _, setItemId in ipairs(setData.items) do
								local setPieceData = DataHelper.GetData("ItemData", setItemId)
								local pieceName = setPieceData and setPieceData.name or setItemId
								local isEquipped = equippedItemIds[setItemId]
								order = order + 1
								local pieceL = Instance.new("TextLabel")
								pieceL.Name = "Piece_" .. order
								pieceL.Size = UDim2.new(1, 0, 0, TT_TS + 2)
								pieceL.BackgroundTransparency = 1
								pieceL.Text = (isEquipped and "  ✓ " or "  ✗ ") .. pieceName
								pieceL.TextColor3 = isEquipped and Color3.fromRGB(120, 200, 80) or Color3.fromHex("#666666")
								pieceL.TextSize = TT_TS - 1
								pieceL.Font = F.NORMAL
								pieceL.TextXAlignment = Enum.TextXAlignment.Left
								pieceL.LayoutOrder = order
								pieceL.Parent = ttCont
							end
							
							-- 세트 보너스 설명
							order = order + 1
							local bonusL = Instance.new("TextLabel")
							bonusL.Name = "SetBonus"
							bonusL.Size = UDim2.new(1, 0, 0, TT_TS + 4)
							bonusL.BackgroundTransparency = 1
							bonusL.Text = (setActive and "★ " or "  ") .. setData.bonusText
							bonusL.TextColor3 = setActive and Color3.fromRGB(255, 220, 80) or Color3.fromHex("#666666")
							bonusL.TextSize = TT_TS
							bonusL.Font = setActive and F.TITLE or F.NORMAL
							bonusL.TextXAlignment = Enum.TextXAlignment.Left
							bonusL.LayoutOrder = order
							bonusL.Parent = ttCont
						end
					end
					
					-- 툴팁 높이 자동 계산 (AutomaticSize.Y 사용)
					
					ttRef.Visible = true
				end)
				
				local function hideTooltip()
					if EquipmentUI.Refs.Tooltip then EquipmentUI.Refs.Tooltip.Visible = false end
				end
				slot._hoverConnLeave = slot.click.MouseLeave:Connect(hideTooltip)
				-- 프레임 MouseLeave도 연결 (안전장치)
				slot._hoverConnLeave2 = slot.frame.MouseLeave:Connect(hideTooltip)
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
		elseif statId == Enums.StatId.INV_SLOTS then baseValue = calc.maxSlots or 60; valText = string.format("%d 칸", baseValue)
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
