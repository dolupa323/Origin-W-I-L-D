-- BuildUI.lua
-- 듀랑고 스타일 건축 설계도 UI 리팩토링
-- 기술 연구 및 제작 UI와 통일된 디자인 언어 적용

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local BuildUI = {}
BuildUI.Refs = {
	Frame = nil,
	Grid = nil,
	DetailFrame = nil,
	CategoryBtns = {},
	Detail = {
		Name = nil,
		Icon = nil,
		Desc = nil,
		Mats = nil,
		Btn = nil,
	}
}

-- 건축 티어별 카테고리 (스킬트리 BUILD_T0~T4 연동)
local BUILD_CATEGORIES = {
	{ id = "BUILD_T0", name = "기초 건축",   skillId = "BUILD_T0" },
	{ id = "BUILD_T1", name = "초급 건축",   skillId = "BUILD_T1" },
	{ id = "BUILD_T2", name = "중급 건축",   skillId = "BUILD_T2" },
	{ id = "BUILD_T3", name = "고급 건축",   skillId = "BUILD_T3" },
	{ id = "BUILD_T4", name = "마스터 건축", skillId = "BUILD_T4" },
}

function BuildUI.Init(parent, UIManager, isMobile)
	local isSmall = isMobile
	
	-- 1. Full screen overlay
	BuildUI.Refs.Frame = Utils.mkFrame({
		name = "BuildMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = C.BG_OVERLAY,
		bgT = 0.5,
		vis = false,
		parent = parent
	})
	
	-- 2. Main Window (Translucent Concept)
	local main = Utils.mkWindow({
		name = "BuildWindow",
		size = UDim2.new(isSmall and 1 or 0.7, 0, isSmall and 1 or 0.85, 0),
		maxSize = Vector2.new(950, 850),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 6,
		stroke = 1.5,
		strokeC = C.BORDER,
		parent = BuildUI.Refs.Frame
	})
	
	-- [Header]
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,50), bgT=1, parent=main})
	Utils.mkLabel({
		text="BLUEPRINTS [C]", pos=UDim2.new(0, 20, 0.5, 0), anchor=Vector2.new(0, 0.5), 
		ts=20, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=header
	})
	
	-- Close Button (Fixed)
	Utils.mkBtn({
		text="X", size=UDim2.new(0, 36, 0, 36), pos=UDim2.new(1, -10, 0.5, 0), anchor=Vector2.new(1, 0.5), 
		bg=C.BTN, bgT=0.5, ts=20, color=C.WHITE, r=4,
		fn=function() UIManager.closeBuild() end, 
		parent=header
	})

	-- [Content Area]
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -60), pos=UDim2.new(0, 10, 0, 50), bgT=1, parent=main})
	
	-- 3. Left Sidebar (Categories)
	local sidebarScale = 0.14
	local sidebar = Utils.mkFrame({name="Sidebar", size=UDim2.new(sidebarScale, 0, 1, 0), bgT=1, parent=content})
	local sList = Instance.new("UIListLayout"); sList.Padding=UDim.new(0, 10); sList.Parent=sidebar
	
	local categories = BUILD_CATEGORIES
	
	for _, cat in ipairs(categories) do
		local btn = Utils.mkBtn({
			text = UILocalizer.Localize(cat.name),
			size = UDim2.new(1, 0, 0, 45),
			bg = C.BTN,
			bgT = 0.3,
			ts = 16,
			font = F.TITLE,
			color = C.GRAY,
			parent = sidebar
		})
		btn.MouseButton1Click:Connect(function() UIManager._onBuildCategoryClick(cat.id) end)
		BuildUI.Refs.CategoryBtns[cat.id] = btn
	end
	
	-- 4. Right Side: Detail Panel
	local detailScale = 0.35
	local detail = Utils.mkFrame({
		name="Detail", size=UDim2.new(detailScale, -4, 1, -8),
		pos=UDim2.new(1 - detailScale, 0, 0, 4),
		bg=C.BG_PANEL, bgT=T.PANEL, r=6, stroke=false,
		parent=content
	})
	BuildUI.Refs.DetailFrame = detail
	
	local dtHead = Utils.mkLabel({
		text=UILocalizer.Localize("설계도 상세"), size=UDim2.new(1,0,0,40),
		bg=C.BG_DARK, bgT=0.3, color=C.GOLD, ts=16, font=F.TITLE,
		parent=detail
	})
	
	BuildUI.Refs.Detail.Name = Utils.mkLabel({
		text=UILocalizer.Localize("시설을 선택하세요"), size=UDim2.new(1,-30,0,40), pos=UDim2.new(0,15,0,50),
		color=C.WHITE, ts=22, font=F.TITLE, ax=Enum.TextXAlignment.Left, parent=detail
	})
	
	BuildUI.Refs.Detail.Icon = Instance.new("ImageLabel")
	BuildUI.Refs.Detail.Icon.Size = UDim2.new(0, 90, 0, 90); BuildUI.Refs.Detail.Icon.Position = UDim2.new(0,15,0,95)
	BuildUI.Refs.Detail.Icon.BackgroundTransparency = 1; BuildUI.Refs.Detail.Icon.Visible = false; BuildUI.Refs.Detail.Icon.Parent = detail
	
	BuildUI.Refs.Detail.Desc = Utils.mkLabel({
		text="", size=UDim2.new(1,-120,0,100), pos=UDim2.new(0,115,0,95),
		color=C.GRAY, ts=16, wrap=true,
		ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, parent=detail
	})
	
	BuildUI.Refs.Detail.Mats = Utils.mkLabel({
		text="", size=UDim2.new(1,-30,1,-310), pos=UDim2.new(0,15,0,240),
		ts=16, color=C.GOLD, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, rich=true, parent=detail
	})
	
	local buildBtn = Utils.mkBtn({
		text=UILocalizer.Localize("건설 하기"), size=UDim2.new(1,-30,0,50), pos=UDim2.new(0.5,0,1,-15), anchor=Vector2.new(0.5,1),
		bg=C.GOLD, r=5, ts=20, font=F.TITLE, color=C.BG_DARK, vis=false, parent=detail
	})
	BuildUI.Refs.Detail.Btn = buildBtn
	buildBtn.MouseButton1Click:Connect(function() UIManager._doStartBuild() end)

	-- 5. Center: Grid (The scrollable part)
	local gridArea = Utils.mkFrame({
		name="GridArea", 
		size=UDim2.new(1 - sidebarScale - detailScale, -20, 1, 0), 
		pos=UDim2.new(sidebarScale, 10, 0, 0), 
		bgT=1, parent=content
	})
	
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -5, 1, 0); scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = C.GOLD
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = gridArea
	
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 85, 0, 85)
	grid.CellPadding = UDim2.new(0, 10, 0, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10); pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 20)
	pad.Parent = scroll
	
	BuildUI.Refs.Grid = scroll
end

function BuildUI.Refresh(facilityList, unlockedTech, catId, getIcon, UIManager, isTierUnlocked)
	local grid = BuildUI.Refs.Grid
	if not grid then return end
	
	-- Clear
	for _, ch in ipairs(grid:GetChildren()) do if ch:IsA("GuiObject") then ch:Destroy() end end
	
	-- Category Highlight + 스킬 해금 상태 반영
	for _, cat in ipairs(BUILD_CATEGORIES) do
		local btn = BuildUI.Refs.CategoryBtns[cat.id]
		if not btn then continue end
		local isSel = (cat.id == catId)
		local unlocked = isTierUnlocked and isTierUnlocked(cat.skillId) or (cat.id == "BUILD_T0")
		
		if not unlocked then
			-- 미해금: 회색 비활성화
			btn.TextColor3 = Color3.fromRGB(80, 75, 65)
			btn.BackgroundColor3 = Color3.fromRGB(30, 28, 25)
			btn.BackgroundTransparency = 0.5
		elseif isSel then
			btn.TextColor3 = C.GOLD
			btn.BackgroundColor3 = C.BTN_H
			btn.BackgroundTransparency = 0.3
		else
			btn.TextColor3 = C.GRAY
			btn.BackgroundColor3 = C.BTN
			btn.BackgroundTransparency = 0.3
		end
		-- 과한 효과 제거 (UIStroke 등)
		local stroke = btn:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Enabled = false end
	end
	
	for _, data in ipairs(facilityList) do
		local isUnlocked = UIManager.checkFacilityUnlocked(data.id)
		
		local slot = Utils.mkSlot({name=data.id, size=UDim2.new(0,85,0,85), parent=grid})
		slot.icon.Image = getIcon(data.id)
		slot.icon.Visible = true
		
		if not isUnlocked then
			slot.icon.ImageColor3 = Color3.fromRGB(65, 62, 55)
			slot.frame.BackgroundColor3 = C.BG_SLOT
			
			local lock = Instance.new("ImageLabel")
			lock.Size = UDim2.new(0, 24, 0, 24); lock.Position = UDim2.new(1,0,0,0); lock.AnchorPoint = Vector2.new(1,0)
			lock.BackgroundTransparency = 1; lock.Image = "rbxassetid://6031084651"; lock.ZIndex = 10; lock.Parent = slot.frame
		else
			slot.frame.BackgroundColor3 = C.BG_SLOT
		end
		
		slot.click.MouseButton1Click:Connect(function() UIManager._onBuildItemClick(data) end)
	end
end

function BuildUI.UpdateDetail(data, canAfford, getIcon, isUnlocked, playerItemCounts, DataHelper)
	playerItemCounts = playerItemCounts or {}
	local d = BuildUI.Refs.Detail
	if not d.Name then return end
	
	local resolvedName = data.name or data.id
	if type(data.id) == "string" then
		resolvedName = UILocalizer.LocalizeDataText("FacilityData", data.id, "name", resolvedName)
	else
		resolvedName = UILocalizer.Localize(resolvedName)
	end
	d.Name.Text = resolvedName
	d.Icon.Image = getIcon(data.id)
	d.Icon.Visible = true
	d.Icon.ImageColor3 = isUnlocked and Color3.new(1,1,1) or Color3.fromRGB(65,62,55)
	if type(data.id) == "string" then
		d.Desc.Text = UILocalizer.LocalizeDataText("FacilityData", data.id, "description", data.description or "")
	else
		d.Desc.Text = UILocalizer.Localize(data.description or "")
	end
	
	if not isUnlocked then
		d.Mats.Text = string.format("<font color='#ff6464'>%s</font>", UILocalizer.Localize("[미해금] 기술 연구가 필요합니다."))
		d.Btn.Visible = false
		return
	end
	
	local matStr = UILocalizer.Localize("[ 필요 재료 ]") .. "\n"
	if data.requirements then
		-- alternateWoodIds 집합 생성
		local altSet = {}
		local altList = data.alternateWoodIds
		if altList then
			for _, id in ipairs(altList) do
				altSet[id] = true
			end
		end

		for _, req in ipairs(data.requirements) do
			if altSet[req.itemId] and altList then
				-- 대체 가능 재료: 보유한 것 중 하나 찾기
				local bestId, bestHave = req.itemId, playerItemCounts[req.itemId] or 0
				for _, altId in ipairs(altList) do
					local h = playerItemCounts[altId] or 0
					if h >= req.amount then
						bestId = altId
						bestHave = h
						break
					elseif h > bestHave then
						bestId = altId
						bestHave = h
					end
				end
				local ok = bestHave >= req.amount
				local color = ok and "#8CDC64" or "#ff6464"
				local prefix = ok and "✓ " or "✗ "

				local mName = bestId
				if DataHelper then
					local md = DataHelper.GetData("ItemData", mName)
					if md then mName = md.name end
				end
				mName = UILocalizer.Localize(mName)

				matStr = matStr .. string.format("<font color='%s'>%s%s: %d / %d</font> <font color='#aaaaaa'>(나무류)</font>\n", color, prefix, mName, bestHave, req.amount)
			else
				local have = playerItemCounts[req.itemId] or 0
				local ok = have >= req.amount
				local color = ok and "#8CDC64" or "#ff6464"
				local prefix = ok and "✓ " or "✗ "

				local mName = req.itemId
				if DataHelper then
					local md = DataHelper.GetData("ItemData", mName)
					if md then mName = md.name end
				end
				mName = UILocalizer.Localize(mName)

				matStr = matStr .. string.format("<font color='%s'>%s%s: %d / %d</font>\n", color, prefix, mName, have, req.amount)
			end
		end
	end
	d.Mats.Text = matStr
	
	d.Btn.Visible = true
	if canAfford then
		d.Btn.BackgroundColor3 = C.GOLD
		d.Btn.TextColor3 = C.BG_DARK
		d.Btn.AutoButtonColor = true
	else
		d.Btn.BackgroundColor3 = C.BG_SLOT
		d.Btn.TextColor3 = Color3.fromRGB(95, 90, 80)
		d.Btn.AutoButtonColor = false
	end
end

return BuildUI
