-- MaterialSelectUI.lua
-- 제작 재료 선택 모달 (기초 작업대 이상 시설 제작 시 재료 개별 선택)
-- 속성이 있는 재료는 인벤토리 슬롯별로 선택, 속성 없는 재료는 자동 선택

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)

local Data = ReplicatedStorage:WaitForChild("Data")
local MaterialAttributeData = require(Data.MaterialAttributeData)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local DataHelper = require(Shared.Util.DataHelper)

local Controllers = script.Parent.Parent:WaitForChild("Controllers")
local InventoryController = require(Controllers.InventoryController)

local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local MaterialSelectUI = {}
MaterialSelectUI.Refs = {
	Frame = nil,
	Title = nil,
	ContentScroll = nil,
	BtnConfirm = nil,
	BtnCancel = nil,
}

-- UIManager.getItemIcon 참조 (Init에서 설정)
local _getItemIcon = nil

-- Internal state
local isOpen = false
local currentRecipe = nil
local currentBatchCount = 1
local onConfirmCallback = nil

-- selectedSlots[inputIndex] = { [slot] = true } (속성 재료: 수동 선택)
-- autoSlots[inputIndex] = { slot1, slot2, ... } (비속성 재료: 자동 선택)
local selectedSlots = {}
local autoSlots = {}
local materialRows = {} -- UI row frames

local function hasAttributeCategory(itemId)
	return MaterialAttributeData.getCategory(itemId) ~= nil
end

-- 인벤토리에서 특정 itemId를 가진 모든 슬롯 조회
local function findSlotsWithItem(itemId)
	local cache = InventoryController.getInventoryCache()
	local result = {}
	for slot, data in pairs(cache) do
		if data and data.itemId == itemId then
			table.insert(result, {
				slot = slot,
				itemId = data.itemId,
				count = data.count or 1,
				attributes = data.attributes,
			})
		end
	end
	table.sort(result, function(a, b) return a.slot < b.slot end)
	return result
end

-- 모든 요구 재료가 충족되었는지 확인
local function isAllFulfilled()
	if not currentRecipe or not currentRecipe.inputs then return false end
	for i, input in ipairs(currentRecipe.inputs) do
		local needed = (input.count or 1) * currentBatchCount
		if hasAttributeCategory(input.itemId) then
			local count = 0
			if selectedSlots[i] then
				for _ in pairs(selectedSlots[i]) do count = count + 1 end
			end
			if count < needed then return false end
		else
			if not autoSlots[i] or #autoSlots[i] < needed then return false end
		end
	end
	return true
end

-- 이미 다른 재료 행에서 선택된 슬롯인지 확인
local function isSlotUsedElsewhere(slot, excludeIndex)
	for i, slots in pairs(selectedSlots) do
		if i ~= excludeIndex and slots[slot] then
			return true
		end
	end
	for i, slots in pairs(autoSlots) do
		if i ~= excludeIndex then
			for _, s in ipairs(slots) do
				if s == slot then return true end
			end
		end
	end
	return false
end

-- 비속성 재료의 자동 슬롯 선택
local function autoSelectSlots(inputIndex, itemId, needed)
	local available = findSlotsWithItem(itemId)
	local result = {}
	for _, info in ipairs(available) do
		if #result >= needed then break end
		if not isSlotUsedElsewhere(info.slot, inputIndex) then
			table.insert(result, info.slot)
		end
	end
	autoSlots[inputIndex] = result
end

-- 확인 버튼 상태 갱신
local function updateConfirmButton()
	if not MaterialSelectUI.Refs.BtnConfirm then return end
	local ok = isAllFulfilled()
	MaterialSelectUI.Refs.BtnConfirm.BackgroundColor3 = ok and C.BTN or C.BTN_GRAY
	MaterialSelectUI.Refs.BtnConfirm.TextColor3 = ok and C.BG_PANEL or C.GRAY
	MaterialSelectUI.Refs.BtnConfirm.Text = ok and UILocalizer.Localize("제작 시작") or UILocalizer.Localize("재료를 선택하세요")
	MaterialSelectUI.Refs.BtnConfirm.Active = ok
	MaterialSelectUI.Refs.BtnConfirm.AutoButtonColor = ok
end

-- 재료 행 헤더 텍스트 갱신
local function updateRowHeader(inputIndex, input)
	local row = materialRows[inputIndex]
	if not row or not row.header then return end
	
	local needed = (input.count or 1) * currentBatchCount
	local selected = 0
	
	if hasAttributeCategory(input.itemId) then
		if selectedSlots[inputIndex] then
			for _ in pairs(selectedSlots[inputIndex]) do selected = selected + 1 end
		end
	else
		selected = autoSlots[inputIndex] and #autoSlots[inputIndex] or 0
	end
	
	local itemData = DataHelper.GetData("ItemData", input.itemId)
	local name = itemData and itemData.name or input.itemId
	name = UILocalizer.LocalizeDataText("ItemData", tostring(input.itemId), "name", name)
	
	local color = (selected >= needed) and "#8CDC64" or "#E63232"
	local suffix = hasAttributeCategory(input.itemId) and "" or "  <font color=\"#AAAAAA\">(자동)</font>"
	row.header.Text = string.format(
		"◆ %s  <font color=\"%s\">%d/%d</font>%s",
		name, color, selected, needed, suffix
	)
end

-- 슬롯 셀 UI 생성 (속성 재료용)
local function buildSlotCell(parent, slotInfo, inputIndex, input)
	local needed = (input.count or 1) * currentBatchCount
	local isSelected = selectedSlots[inputIndex] and selectedSlots[inputIndex][slotInfo.slot]
	
	local cell = Utils.mkFrame({
		name = "Slot_" .. slotInfo.slot,
		size = UDim2.new(0, 130, 0, 160),
		bg = isSelected and C.GOLD or C.BG_SLOT,
		bgT = isSelected and 0.15 or 0.1,
		r = 8,
		stroke = isSelected and 3 or 1,
		strokeC = isSelected and C.GOLD or C.BORDER_DIM,
		parent = parent,
	})
	
	-- 아이콘 (UIManager.getItemIcon 사용)
	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0, 70, 0, 70)
	icon.Position = UDim2.new(0.5, 0, 0, 8)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.BackgroundTransparency = 1
	icon.Image = _getItemIcon and _getItemIcon(slotInfo.itemId) or ""
	icon.Parent = cell
	
	-- 속성 뱃지 (다중 속성 지원)
	local attrs = slotInfo.attributes
	if attrs and next(attrs) then
		local badgeY = 82
		for attrId, level in pairs(attrs) do
			local attrInfo = MaterialAttributeData.getAttribute(attrId)
			if attrInfo then
				local badgeColor = attrInfo.positive and Color3.fromRGB(30, 100, 30) or Color3.fromRGB(120, 25, 25)
				local textColor = attrInfo.positive and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
				local symbol = attrInfo.positive and "▲" or "▼"
				
				local badgeBg = Utils.mkFrame({
					name = "AttrBadge_" .. attrId,
					size = UDim2.new(1, -6, 0, 24),
					pos = UDim2.new(0.5, 0, 0, badgeY),
					anchor = Vector2.new(0.5, 0),
					bg = badgeColor,
					bgT = 0.3,
					r = 5,
					parent = cell,
				})
				
				Utils.mkLabel({
					text = string.format("%s%s Lv.%d", symbol, attrInfo.name, level),
					size = UDim2.new(1, 0, 1, 0),
					ts = 14,
					color = textColor,
					font = Enum.Font.GothamBold,
					ax = Enum.TextXAlignment.Center,
					parent = badgeBg,
				})
				
				badgeY = badgeY + 26
			end
		end
	else
		-- 무속성 표시
		local noBadgeBg = Utils.mkFrame({
			name = "NoAttr",
			size = UDim2.new(1, -6, 0, 30),
			pos = UDim2.new(0.5, 0, 0, 82),
			anchor = Vector2.new(0.5, 0),
			bg = Color3.fromRGB(60, 60, 60),
			bgT = 0.4,
			r = 5,
			parent = cell,
		})
		Utils.mkLabel({
			text = "무속성",
			size = UDim2.new(1, 0, 1, 0),
			ts = 14,
			color = C.GRAY,
			font = Enum.Font.GothamBold,
			ax = Enum.TextXAlignment.Center,
			parent = noBadgeBg,
		})
	end
	
	-- 선택 체크마크
	if isSelected then
		Utils.mkLabel({
			text = "✓",
			size = UDim2.new(0, 28, 0, 28),
			pos = UDim2.new(1, -3, 0, 3),
			anchor = Vector2.new(1, 0),
			ts = 22,
			color = C.GOLD,
			font = Enum.Font.GothamBold,
			parent = cell,
		})
	end
	
	-- 클릭 처리
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.Parent = cell
	
	btn.MouseButton1Click:Connect(function()
		if not selectedSlots[inputIndex] then selectedSlots[inputIndex] = {} end
		
		if selectedSlots[inputIndex][slotInfo.slot] then
			selectedSlots[inputIndex][slotInfo.slot] = nil
		else
			if isSlotUsedElsewhere(slotInfo.slot, inputIndex) then return end
			local count = 0
			for _ in pairs(selectedSlots[inputIndex]) do count = count + 1 end
			if count >= needed then return end
			selectedSlots[inputIndex][slotInfo.slot] = true
		end
		
		-- 자동 선택 재료 갱신
		for j, inp in ipairs(currentRecipe.inputs) do
			if not hasAttributeCategory(inp.itemId) then
				autoSelectSlots(j, inp.itemId, (inp.count or 1) * currentBatchCount)
				updateRowHeader(j, inp)
			end
		end
		
		MaterialSelectUI._rebuildRow(inputIndex, input)
		updateRowHeader(inputIndex, input)
		updateConfirmButton()
	end)
	
	return cell
end

-- 특정 재료 행 리빌드
function MaterialSelectUI._rebuildRow(inputIndex, input)
	local row = materialRows[inputIndex]
	if not row or not row.grid then return end
	
	-- 기존 셀 제거
	for _, ch in ipairs(row.grid:GetChildren()) do
		if ch:IsA("GuiObject") and not ch:IsA("UIGridLayout") and not ch:IsA("UIPadding") then
			ch:Destroy()
		end
	end
	
	local available = findSlotsWithItem(input.itemId)
	for _, slotInfo in ipairs(available) do
		if not isSlotUsedElsewhere(slotInfo.slot, inputIndex) or (selectedSlots[inputIndex] and selectedSlots[inputIndex][slotInfo.slot]) then
			buildSlotCell(row.grid, slotInfo, inputIndex, input)
		end
	end
end

function MaterialSelectUI.Init(parent, UIManager)
	-- UIManager.getItemIcon 참조 저장
	_getItemIcon = UIManager and UIManager.getItemIcon or nil
	
	-- Overlay (전체 화면 반투명 배경)
	MaterialSelectUI.Refs.Frame = Utils.mkFrame({
		name = "MaterialSelectOverlay",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.fromRGB(0, 0, 0),
		bgT = 0.5,
		vis = false,
		z = 50,
		parent = parent,
	})
	
	-- 메인 윈도우
	local main = Utils.mkWindow({
		name = "MaterialSelectWindow",
		size = UDim2.new(0.85, 0, 0.88, 0),
		maxSize = Vector2.new(900, 800),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 10,
		stroke = 2,
		strokeC = C.BORDER,
		parent = MaterialSelectUI.Refs.Frame,
	})
	
	-- 헤더
	local header = Utils.mkFrame({
		name = "Header",
		size = UDim2.new(1, 0, 0, 60),
		bg = C.BG_DARK,
		bgT = 0.3,
		parent = main,
	})
	
	MaterialSelectUI.Refs.Title = Utils.mkLabel({
		text = UILocalizer.Localize("재료 선택"),
		size = UDim2.new(1, -70, 1, 0),
		pos = UDim2.new(0, 24, 0, 0),
		ts = 26,
		font = F.TITLE,
		color = C.GOLD,
		ax = Enum.TextXAlignment.Left,
		parent = header,
	})
	
	-- 닫기 버튼
	local closeBtn = Utils.mkBtn({
		text = "X",
		size = UDim2.new(0, 50, 0, 50),
		pos = UDim2.new(1, -8, 0, 5),
		anchor = Vector2.new(1, 0),
		bgT = 0.6,
		ts = 28,
		isNegative = true,
		fn = function() MaterialSelectUI.Close() end,
		parent = main,
	})
	
	-- 스크롤 콘텐츠
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Content"
	scroll.Size = UDim2.new(1, -24, 1, -140)
	scroll.Position = UDim2.new(0, 12, 0, 65)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = main
	MaterialSelectUI.Refs.ContentScroll = scroll
	
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	
	-- 하단 버튼 영역
	local footer = Utils.mkFrame({
		name = "Footer",
		size = UDim2.new(1, -24, 0, 65),
		pos = UDim2.new(0.5, 0, 1, -10),
		anchor = Vector2.new(0.5, 1),
		bgT = 1,
		parent = main,
	})
	
	local footLayout = Instance.new("UIListLayout")
	footLayout.FillDirection = Enum.FillDirection.Horizontal
	footLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	footLayout.Padding = UDim.new(0, 16)
	footLayout.Parent = footer
	
	MaterialSelectUI.Refs.BtnCancel = Utils.mkBtn({
		text = UILocalizer.Localize("취소"),
		size = UDim2.new(0, 180, 0, 56),
		isNegative = true,
		r = 6,
		font = F.TITLE,
		ts = 22,
		fn = function() MaterialSelectUI.Close() end,
		parent = footer,
	})
	
	MaterialSelectUI.Refs.BtnConfirm = Utils.mkBtn({
		text = UILocalizer.Localize("재료를 선택하세요"),
		size = UDim2.new(0, 300, 0, 56),
		r = 6,
		font = F.TITLE,
		ts = 22,
		parent = footer,
	})
	
	MaterialSelectUI.Refs.BtnConfirm.MouseButton1Click:Connect(function()
		if not isAllFulfilled() then return end
		if not onConfirmCallback then return end
		
		-- 선택된 슬롯 목록 수집
		local resultSlots = {}
		for i, input in ipairs(currentRecipe.inputs) do
			if hasAttributeCategory(input.itemId) then
				if selectedSlots[i] then
					for slot, _ in pairs(selectedSlots[i]) do
						table.insert(resultSlots, { slot = slot, itemId = input.itemId })
					end
				end
			else
				if autoSlots[i] then
					for _, slot in ipairs(autoSlots[i]) do
						table.insert(resultSlots, { slot = slot, itemId = input.itemId })
					end
				end
			end
		end
		
		local cb = onConfirmCallback
		MaterialSelectUI.Close()
		cb(resultSlots)
	end)
end

function MaterialSelectUI.Open(recipe, batchCount, callback)
	if not recipe or not recipe.inputs then return end
	
	currentRecipe = recipe
	currentBatchCount = math.max(1, math.floor(tonumber(batchCount) or 1))
	onConfirmCallback = callback
	selectedSlots = {}
	autoSlots = {}
	materialRows = {}
	
	-- 콘텐츠 영역 초기화
	local scroll = MaterialSelectUI.Refs.ContentScroll
	if not scroll then return end
	
	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("GuiObject") and not ch:IsA("UIListLayout") then
			ch:Destroy()
		end
	end
	
	-- 타이틀 갱신
	local outputName = ""
	if recipe.outputs and recipe.outputs[1] then
		local outData = DataHelper.GetData("ItemData", recipe.outputs[1].itemId)
		outputName = outData and outData.name or recipe.outputs[1].itemId
		outputName = UILocalizer.LocalizeDataText("ItemData", tostring(recipe.outputs[1].itemId), "name", outputName)
	end
	if MaterialSelectUI.Refs.Title then
		local countStr = currentBatchCount > 1 and string.format(" x%d", currentBatchCount) or ""
		MaterialSelectUI.Refs.Title.Text = UILocalizer.Localize("재료 선택") .. " - " .. outputName .. countStr
	end
	
	-- 각 재료별 행 생성
	for i, input in ipairs(recipe.inputs) do
		local needed = (input.count or 1) * currentBatchCount
		local isManual = hasAttributeCategory(input.itemId)
		
		-- 행 컨테이너
		local rowFrame = Utils.mkFrame({
			name = "Row_" .. i,
			size = UDim2.new(1, 0, 0, 0), -- AutomaticSize로 조절
			bgT = 1,
			parent = scroll,
		})
		rowFrame.AutomaticSize = Enum.AutomaticSize.Y
		rowFrame.LayoutOrder = i
		
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.Padding = UDim.new(0, 4)
		rowLayout.Parent = rowFrame
		
		-- 행 헤더
		local headerLabel = Utils.mkLabel({
			text = "",
			size = UDim2.new(1, 0, 0, 34),
			ts = 22,
			font = F.TITLE,
			color = C.WHITE,
			ax = Enum.TextXAlignment.Left,
			rich = true,
			parent = rowFrame,
		})
		headerLabel.LayoutOrder = 1
		
		if isManual then
			-- 수동 선택: 슬롯 그리드
			selectedSlots[i] = {}
			
			local gridFrame = Utils.mkFrame({
				name = "Grid",
				size = UDim2.new(1, 0, 0, 0),
				bgT = 1,
				parent = rowFrame,
			})
			gridFrame.AutomaticSize = Enum.AutomaticSize.Y
			gridFrame.LayoutOrder = 2
			
			local grid = Instance.new("UIGridLayout")
			grid.CellSize = UDim2.new(0, 130, 0, 160)
			grid.CellPadding = UDim2.new(0, 10, 0, 10)
			grid.Parent = gridFrame
			
			local pad = Instance.new("UIPadding")
			pad.PaddingTop = UDim.new(0, 4)
			pad.PaddingLeft = UDim.new(0, 4)
			pad.PaddingBottom = UDim.new(0, 4)
			pad.Parent = gridFrame
			
			materialRows[i] = { header = headerLabel, grid = gridFrame }
			
			-- 슬롯 셀 생성
			local available = findSlotsWithItem(input.itemId)
			for _, slotInfo in ipairs(available) do
				buildSlotCell(gridFrame, slotInfo, i, input)
			end
		else
			-- 자동 선택: 자동으로 슬롯 배정
			autoSelectSlots(i, input.itemId, needed)
			materialRows[i] = { header = headerLabel }
		end
		
		-- 구분선
		local sep = Utils.mkFrame({
			name = "Sep",
			size = UDim2.new(1, -10, 0, 1),
			bg = C.BORDER_DIM,
			bgT = 0.5,
			parent = rowFrame,
		})
		sep.LayoutOrder = 3
		
		updateRowHeader(i, input)
	end
	
	updateConfirmButton()
	
	MaterialSelectUI.Refs.Frame.Visible = true
	isOpen = true
end

function MaterialSelectUI.Close()
	if MaterialSelectUI.Refs.Frame then
		MaterialSelectUI.Refs.Frame.Visible = false
	end
	isOpen = false
	currentRecipe = nil
	onConfirmCallback = nil
	selectedSlots = {}
	autoSlots = {}
	materialRows = {}
end

function MaterialSelectUI.IsOpen()
	return isOpen
end

function MaterialSelectUI.SetVisible(v)
	if MaterialSelectUI.Refs.Frame then
		MaterialSelectUI.Refs.Frame.Visible = v
	end
	if not v then isOpen = false end
end

return MaterialSelectUI
