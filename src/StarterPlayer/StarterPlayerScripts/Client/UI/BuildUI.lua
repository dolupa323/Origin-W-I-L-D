-- BuildUI.lua
-- 듀랑고 스타일 건축 설계도 UI 리팩토링
-- 기술 연구 및 제작 UI와 통일된 디자인 언어 적용

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts

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

function BuildUI.Init(parent, UIManager, isMobile)
	local isSmall = isMobile
	
	-- 1. Full screen overlay
	BuildUI.Refs.Frame = Utils.mkFrame({
		name = "BuildMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0,0,0),
		bgT = 0.7,
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
		bg = Color3.fromRGB(15, 15, 18),
		bgT = 0.5, -- 투명 컨셉 유지
		r = 0,
		stroke = 1,
		strokeC = Color3.fromRGB(60, 60, 60),
		parent = BuildUI.Refs.Frame
	})
	
	-- [Header]
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,50), bgT=1, parent=main})
	Utils.mkLabel({
		text="건축 설계도", pos=UDim2.new(0, 20, 0.5, 0), anchor=Vector2.new(0, 0.5), 
		ts=24, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=header
	})
	
	-- Close Button
	Utils.mkBtn({
		text="X", size=UDim2.new(0, 40, 0, 40), pos=UDim2.new(1, -5, 0, 5), anchor=Vector2.new(1, 0), 
		bgT=1, ts=24, color=C.WHITE, 
		fn=function() UIManager.closeBuild() end, 
		parent=main
	})

	-- [Content Area]
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -60), pos=UDim2.new(0, 10, 0, 50), bgT=1, parent=main})
	
	-- 3. Left Sidebar (Categories)
	local sidebarWidth = 120
	local sidebar = Utils.mkFrame({name="Sidebar", size=UDim2.new(0, sidebarWidth, 1, 0), bgT=1, parent=content})
	local sList = Instance.new("UIListLayout"); sList.Padding=UDim.new(0, 10); sList.Parent=sidebar
	
	local categories = {
		{id="STRUCTURES", name="구조물"},
		{id="PRODUCTION", name="생산 시설"},
		{id="SURVIVAL", name="생존 시설"},
	}
	
	for _, cat in ipairs(categories) do
		local btn = Utils.mkBtn({
			text = cat.name,
			size = UDim2.new(1, 0, 0, 45),
			bg = Color3.fromRGB(40, 40, 45),
			bgT = 0.3,
			ts = 16,
			font = F.TITLE,
			color = C.GRAY,
			parent = sidebar
		})
		btn.MouseButton1Click:Connect(function() UIManager._onBuildCategoryClick(cat.id) end)
		BuildUI.Refs.CategoryBtns[cat.id] = btn
	end
	
	-- 4. Right Side: Detail Panel (320px)
	local detailSize = 320
	local detail = Utils.mkFrame({
		name="Detail", size=UDim2.new(0, detailSize, 1, -8),
		pos=UDim2.new(1, -detailSize - 4, 0, 4),
		bg=Color3.fromRGB(12,12,15), bgT=0.4, r=6, stroke=1, strokeC=Color3.fromRGB(60,60,60),
		parent=content
	})
	BuildUI.Refs.DetailFrame = detail
	
	local dtHead = Utils.mkLabel({
		text="설계도 상세", size=UDim2.new(1,0,0,40),
		bg=Color3.fromRGB(30,30,30), bgT=0.2, color=C.GOLD, ts=16, font=F.TITLE,
		parent=detail
	})
	
	BuildUI.Refs.Detail.Name = Utils.mkLabel({
		text="시설을 선택하세요", size=UDim2.new(1,-30,0,40), pos=UDim2.new(0,15,0,50),
		color=C.WHITE, ts=22, font=F.TITLE, ax=Enum.TextXAlignment.Left, parent=detail
	})
	
	BuildUI.Refs.Detail.Icon = Instance.new("ImageLabel")
	BuildUI.Refs.Detail.Icon.Size = UDim2.new(0, 90, 0, 90); BuildUI.Refs.Detail.Icon.Position = UDim2.new(0,15,0,95)
	BuildUI.Refs.Detail.Icon.BackgroundTransparency = 1; BuildUI.Refs.Detail.Icon.Visible = false; BuildUI.Refs.Detail.Icon.Parent = detail
	
	BuildUI.Refs.Detail.Desc = Utils.mkLabel({
		text="", size=UDim2.new(1,-120,0,100), pos=UDim2.new(0,115,0,95),
		color=Color3.fromRGB(200,200,200), ts=16, wrap=true,
		ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, parent=detail
	})
	
	BuildUI.Refs.Detail.Mats = Utils.mkLabel({
		text="", size=UDim2.new(1,-30,1,-310), pos=UDim2.new(0,15,0,240),
		ts=16, color=C.GOLD, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, rich=true, parent=detail
	})
	
	local buildBtn = Utils.mkBtn({
		text="건설 하기", size=UDim2.new(1,-30,0,50), pos=UDim2.new(0.5,0,1,-15), anchor=Vector2.new(0.5,1),
		bg=C.GOLD, r=5, ts=20, font=F.TITLE, color=Color3.fromRGB(20,20,20), vis=false, parent=detail
	})
	BuildUI.Refs.Detail.Btn = buildBtn
	buildBtn.MouseButton1Click:Connect(function() UIManager._doStartBuild() end)

	-- 5. Center: Grid (The scrollable part)
	local gridArea = Utils.mkFrame({
		name="GridArea", 
		size=UDim2.new(1, -sidebarWidth - detailSize - 40, 1, 0), 
		pos=UDim2.new(0, sidebarWidth + 15, 0, 0), 
		bgT=1, parent=content
	})
	
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1,0,1,0); scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = gridArea
	
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 85, 0, 85)
	grid.CellPadding = UDim2.new(0, 10, 0, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	
	local pad = Instance.new("UIPadding"); pad.PaddingTop=UDim.new(0, 5); pad.PaddingLeft=UDim.new(0, 5); pad.Parent=scroll
	BuildUI.Refs.Grid = scroll
end

function BuildUI.Refresh(facilityList, unlockedTech, catId, getIcon, UIManager)
	local grid = BuildUI.Refs.Grid
	if not grid then return end
	
	-- Clear
	for _, ch in ipairs(grid:GetChildren()) do if ch:IsA("GuiObject") then ch:Destroy() end end
	
	-- Category Highlight
	for cid, btn in pairs(BuildUI.Refs.CategoryBtns) do
		local isSel = (cid == catId)
		btn.TextColor3 = isSel and C.GOLD or C.GRAY
		btn.BackgroundColor3 = isSel and Color3.fromRGB(55, 50, 40) or Color3.fromRGB(35, 35, 40)
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
			slot.icon.ImageColor3 = Color3.fromRGB(100, 100, 100)
			slot.frame.BackgroundColor3 = Color3.fromRGB(35, 30, 30)
			
			local lock = Instance.new("ImageLabel")
			lock.Size = UDim2.new(0, 24, 0, 24); lock.Position = UDim2.new(1,0,0,0); lock.AnchorPoint = Vector2.new(1,0)
			lock.BackgroundTransparency = 1; lock.Image = "rbxassetid://6031084651"; lock.ZIndex = 10; lock.Parent = slot.frame
		else
			slot.frame.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
		end
		
		slot.click.MouseButton1Click:Connect(function() UIManager._onBuildItemClick(data) end)
	end
end

function BuildUI.UpdateDetail(data, canAfford, getIcon, isUnlocked, playerItemCounts, DataHelper)
	playerItemCounts = playerItemCounts or {}
	local d = BuildUI.Refs.Detail
	if not d.Name then return end
	
	d.Name.Text = data.name or data.id
	d.Icon.Image = getIcon(data.id)
	d.Icon.Visible = true
	d.Icon.ImageColor3 = isUnlocked and Color3.new(1,1,1) or Color3.fromRGB(100,100,100)
	d.Desc.Text = data.description or ""
	
	if not isUnlocked then
		d.Mats.Text = "<font color='#ff6464'>[미해금] 기술 연구가 필요합니다.</font>"
		d.Btn.Visible = false
		return
	end
	
	local matStr = "[ 필요 재료 ]\n"
	if data.requirements then
		for _, req in ipairs(data.requirements) do
			local have = playerItemCounts[req.itemId] or 0
			local ok = have >= req.amount
			local color = ok and "#8CDC64" or "#ff6464"
			local prefix = ok and "✓ " or "✗ "
			
			local mName = req.itemId
			if DataHelper then
				local md = DataHelper.GetData("ItemData", mName)
				if md then mName = md.name end
			end
			
			matStr = matStr .. string.format("<font color='%s'>%s%s: %d / %d</font>\n", color, prefix, mName, have, req.amount)
		end
	end
	d.Mats.Text = matStr
	
	d.Btn.Visible = true
	if canAfford then
		d.Btn.BackgroundColor3 = C.GOLD
		d.Btn.TextColor3 = Color3.fromRGB(20,20,20)
		d.Btn.AutoButtonColor = true
	else
		d.Btn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
		d.Btn.TextColor3 = Color3.fromRGB(120, 120, 120)
		d.Btn.AutoButtonColor = false
	end
end

return BuildUI
