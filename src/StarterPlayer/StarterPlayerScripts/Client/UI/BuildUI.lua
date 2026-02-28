-- BuildUI.lua
-- 듀랑고 스타일 건축 UI (별도 창)

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts

local BuildUI = {}
BuildUI.Refs = {
	Frame = nil,
	Grid = nil,
	Preview = nil,
}

function BuildUI.Init(parent, UIManager, isMobile)
	local isSmall = isMobile
	
	-- Main Container (Full screen overlay)
	BuildUI.Refs.Frame = Utils.mkFrame({
		name = "BuildMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0,0,0),
		bgT = 0.7,
		vis = false,
		parent = parent
	})
	
	-- Main Window
	local main = Utils.mkWindow({
		name = "BuildWindow",
		size = UDim2.new(isSmall and 0.95 or 0.9, 0, isSmall and 0.95 or 0.85, 0),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = Theme.Transp.PANEL,
		r = 0,
		stroke = 2,
		strokeC = C.BORDER_DIM,
		parent = BuildUI.Refs.Frame,
		ratio = isSmall and 1.3 or 1.6
	})
	
	-- [Header]
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,45), bgT=1, parent=main})
	Utils.mkLabel({text="건축 설계도", pos=UDim2.new(0, 15, 0, 0), ts=24, font=F.TITLE, color=C.GOLD_SEL, ax=Enum.TextXAlignment.Left, parent=header})
	Utils.mkBtn({text="X", size=UDim2.new(0, 30, 0, 30), pos=UDim2.new(1, -15, 0, 7), anchor=Vector2.new(1, 0), bgT=1, ts=26, color=C.WHITE, fn=function() UIManager.closeBuild() end, parent=main})
	
	-- [Content Area]
	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -55), pos=UDim2.new(0, 10, 0, 45), bgT=1, parent=main})
	
	-- Left Sidebar: Categories
	local sidebar = Utils.mkFrame({name="Sidebar", size=UDim2.new(0.2, -10, 1, 0), bg=C.BG_PANEL_L, bgT=0.5, parent=content})
	local sList = Instance.new("UIListLayout"); sList.Padding=UDim.new(0, 5); sList.Parent=sidebar
	local sPad = Instance.new("UIPadding"); sPad.PaddingTop=UDim.new(0, 5); sPad.PaddingLeft=UDim.new(0, 5); sPad.PaddingRight=UDim.new(0, 5); sPad.Parent=sidebar
	
	local categories = {
		{id="STRUCTURES", name="구조물", icon="rbxassetid://10452331908"},
		{id="PRODUCTION", name="생산 시설", icon="rbxassetid://6031267325"},
		{id="SURVIVAL", name="생존 시설", icon="rbxassetid://6034805332"},
	}
	
	BuildUI.Refs.CategoryBtns = {}
	for _, cat in ipairs(categories) do
		local btn = Utils.mkBtn({
			text = cat.name,
			size = UDim2.new(1, 0, 0, 40),
			bg = Color3.fromRGB(50, 50, 50),
			ts = 16,
			font = F.TITLE,
			color = C.GRAY,
			parent = sidebar
		})
		btn.MouseButton1Click:Connect(function() UIManager._onBuildCategoryClick(cat.id) end)
		BuildUI.Refs.CategoryBtns[cat.id] = btn
	end
	
	-- Center: Grid
	local gridArea = Utils.mkFrame({name="GridArea", size=UDim2.new(0.5, -10, 1, 0), pos=UDim2.new(0.2, 0, 0, 0), bgT=1, parent=content})
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1,0,1,0); scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=2; scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
	scroll.Parent = gridArea
	
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, isSmall and 75 or 85, 0, isSmall and 75 or 85)
	grid.CellPadding = UDim2.new(0, 8, 0, 8)
	grid.Parent = scroll
	
	local pad = Instance.new("UIPadding"); pad.PaddingTop=UDim.new(0, 10); pad.PaddingLeft=UDim.new(0, 10); pad.Parent=scroll
	BuildUI.Refs.Grid = scroll
	
	-- Right Sidebar: Detail
	local detail = Utils.mkFrame({name="Detail", size=UDim2.new(0.3, 0, 1, 0), pos=UDim2.new(1, 0, 0, 0), anchor=Vector2.new(1, 0), bg=C.BG_PANEL_L, bgT=0.3, stroke=1, parent=content})
	BuildUI.Refs.DetailFrame = detail
	
	local dBody = Utils.mkFrame({size=UDim2.new(1,-20,1,-100), pos=UDim2.new(0,10,0,10), bgT=1, parent=detail})
	local dList = Instance.new("UIListLayout"); dList.Padding=UDim.new(0, 10); dList.HorizontalAlignment=Enum.HorizontalAlignment.Center; dList.Parent=dBody
	
	local dName = Utils.mkLabel({text="시설을 선택하세요", ts=20, font=F.TITLE, color=C.GOLD_SEL, parent=dBody})
	local dIcon = Instance.new("ImageLabel"); dIcon.Size=UDim2.new(0, 100, 0, 100); dIcon.BackgroundTransparency=1; dIcon.Visible=false; dIcon.Parent=dBody
	local dDesc = Utils.mkLabel({text="", size=UDim2.new(1,0,0,60), ts=14, color=C.WHITE, wrap=true, ay=Enum.TextYAlignment.Top, parent=dBody})
	local dMats = Utils.mkLabel({text="", size=UDim2.new(1,0,0,100), ts=14, color=C.GOLD, ax=Enum.TextXAlignment.Left, wrap=true, ay=Enum.TextYAlignment.Top, parent=dBody})
	
	local buildBtn = Utils.mkBtn({text="건설 시작", size=UDim2.new(1,-20,0,50), pos=UDim2.new(0.5,0,1,-10), anchor=Vector2.new(0.5,1), bg=C.GOLD_SEL, ts=20, font=F.TITLE, color=C.BG_PANEL, vis=false, parent=detail})
	
	BuildUI.Refs.Detail = {
		Name = dName,
		Icon = dIcon,
		Desc = dDesc,
		Mats = dMats,
		Btn = buildBtn
	}
	
	buildBtn.MouseButton1Click:Connect(function() UIManager._doStartBuild() end)
end

function BuildUI.Refresh(facilityList, unlockedTech, catId, getIcon, UIManager)
	local grid = BuildUI.Refs.Grid
	if not grid then return end
	
	-- Clear
	for _, ch in ipairs(grid:GetChildren()) do if ch:IsA("GuiObject") then ch:Destroy() end end
	
	-- Category Highlight
	for cid, btn in pairs(BuildUI.Refs.CategoryBtns) do
		btn.TextColor3 = (cid == catId) and C.GOLD_SEL or C.GRAY
		btn.BackgroundColor3 = (cid == catId) and Color3.fromRGB(80, 80, 80) or Color3.fromRGB(50, 50, 50)
	end
	
	for _, data in ipairs(facilityList) do
		local isUnlocked = UIManager.checkFacilityUnlocked(data.id)
		
		local uigrid = grid:FindFirstChildOfClass("UIGridLayout")
		local cellSize = uigrid and uigrid.CellSize or UDim2.new(0, 85, 0, 85)
		local slot = Utils.mkSlot({name=data.id, size=cellSize, parent=grid})
		slot.icon.Image = getIcon(data.id)
		slot.icon.Visible = true
		
		if not isUnlocked then
			slot.icon.ImageColor3 = Color3.fromRGB(80, 80, 80)
			slot.frame.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
			
			local lock = Instance.new("ImageLabel")
			lock.Size = UDim2.new(0.5, 0, 0.5, 0)
			lock.Position = UDim2.new(0.5, 0, 0.5, 0)
			lock.AnchorPoint = Vector2.new(0.5, 0.5)
			lock.BackgroundTransparency = 1
			lock.Image = "rbxassetid://6031084651"
			lock.ImageTransparency = 0.5
			lock.ZIndex = 10
			lock.Parent = slot.frame
		end
		
		slot.click.MouseButton1Click:Connect(function() UIManager._onBuildItemClick(data) end)
	end
end

function BuildUI.UpdateDetail(data, canAfford, getIcon, isUnlocked)
	local d = BuildUI.Refs.Detail
	d.Name.Text = data.name
	d.Icon.Image = getIcon(data.id)
	d.Icon.Visible = true
	d.Icon.ImageColor3 = isUnlocked and Color3.new(1,1,1) or Color3.fromRGB(100,100,100)
	d.Desc.Text = data.description or ""
	
	if not isUnlocked then
		d.Mats.Text = "<font color='#ff5050'>[미해금] 기술 연구가 필요합니다.</font>"
		d.Btn.Visible = false
		return
	end
	
	local matStr = "필요 재료:\n"
	if data.requirements then
		for _, req in ipairs(data.requirements) do
			matStr = matStr .. string.format("- %s x%d\n", req.itemId, req.amount)
		end
	end
	d.Mats.Text = matStr
	d.Btn.Visible = true
	d.Btn.BackgroundColor3 = canAfford and C.GOLD_SEL or C.GRAY
	d.Btn.Text = "건축 시작"
end

return BuildUI
