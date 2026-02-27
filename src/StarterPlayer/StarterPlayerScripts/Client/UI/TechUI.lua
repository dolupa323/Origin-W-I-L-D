-- TechUI.lua
-- 듀랑고 레퍼런스 스타일 기술 트리 UI

local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local TechUI = {}

TechUI.Refs = {
	Frame = nil,
	Title = nil,
	TPText = nil,
	GridScroll = nil,
	Detail = {
		Frame = nil,
		Name = nil,
		Icon = nil,
		Desc = nil,
		ReqText = nil,
		CostText = nil,
		BtnUnlock = nil,
	}
}

function TechUI.Init(parent, UIManager)
	TechUI.Refs.Frame = Utils.mkFrame({
		name = "TechMenu",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0, 0, 0),
		bgT = 0.7,
		vis = false,
		parent = parent
	})
	
	local main = Utils.mkWindow({
		name = "Main",
		size = UDim2.new(0.9, 0, 0.85, 0),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 0, stroke = 2, strokeC = C.BORDER_DIM,
		ratio = 1.6,
		parent = TechUI.Refs.Frame
	})

	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,45), bgT=1, parent=main})
	TechUI.Refs.Title = Utils.mkLabel({text="기술 및 연구", pos=UDim2.new(0, 15, 0, 0), ts=24, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=header})
	TechUI.Refs.TPText = Utils.mkLabel({text="보유 TP: 0", pos=UDim2.new(0, 180, 0, 5), ts=18, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=header})
	Utils.mkBtn({text="X", size=UDim2.new(0, 30, 0, 30), pos=UDim2.new(1, -15, 0, 7), anchor=Vector2.new(1,0), bgT=1, ts=26, color=C.WHITE, fn=function() UIManager.closeTechTree() end, parent=header})

	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -55), pos=UDim2.new(0, 10, 0, 45), bgT=1, parent=main})
	
	-- Left Side: Grid
	local gridArea = Utils.mkFrame({name="GridArea", size=UDim2.new(0.65, -10, 1, 0), bgT=1, parent=content})
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GridScroll"
	scroll.Size = UDim2.new(1, 0, 1, 0); scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 2
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ClipsDescendants = true
	scroll.Parent = gridArea
	
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 90, 0, 90)
	grid.CellPadding = UDim2.new(0, 10, 0, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	TechUI.Refs.GridScroll = scroll
	
	-- Right Side: Detail Panel
	local detail = Utils.mkFrame({
		name="Detail", size=UDim2.new(0.35, 0, 1, 0), pos=UDim2.new(1, 0, 0, 0), anchor=Vector2.new(1, 0),
		bg=C.BG_PANEL_L, stroke=1, parent=content
	})
	TechUI.Refs.Detail.Frame = detail
	
	local dHeader = Utils.mkFrame({size=UDim2.new(1,0,0,40), bg=C.GOLD_SEL, bgT=0.3, parent=detail})
	TechUI.Refs.Detail.Name = Utils.mkLabel({text="연구 대상을 선택하세요", ts=18, font=F.TITLE, parent=dHeader})
	
	local dBody = Utils.mkFrame({size=UDim2.new(1,-20,1,-120), pos=UDim2.new(0,10,0,50), bgT=1, parent=detail})
	local dBList = Instance.new("UIListLayout"); dBList.Padding=UDim.new(0, 10); dBList.HorizontalAlignment=Enum.HorizontalAlignment.Center; dBList.Parent=dBody
	
	local iconFrame = Utils.mkFrame({size=UDim2.new(0, 80, 0, 80), bg=C.BG_SLOT, stroke=1, strokeC=C.BORDER_DIM, parent=dBody})
	TechUI.Refs.Detail.Icon = Instance.new("ImageLabel"); TechUI.Refs.Detail.Icon.Size=UDim2.new(1,-10,1,-10); TechUI.Refs.Detail.Icon.Position=UDim2.new(0.5,0,0.5,0); TechUI.Refs.Detail.Icon.AnchorPoint=Vector2.new(0.5,0.5); TechUI.Refs.Detail.Icon.BackgroundTransparency=1; TechUI.Refs.Detail.Icon.Parent=iconFrame
	
	TechUI.Refs.Detail.Desc = Utils.mkLabel({text="", size=UDim2.new(1,0,0,60), ts=14, color=C.WHITE, ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, wrap=true, parent=dBody})
	
	TechUI.Refs.Detail.ReqText = Utils.mkLabel({text="", size=UDim2.new(1,0,0,20), ts=14, color=C.RED, ax=Enum.TextXAlignment.Left, parent=dBody})
	TechUI.Refs.Detail.CostText = Utils.mkLabel({text="", size=UDim2.new(1,0,0,20), ts=14, color=C.GOLD, ax=Enum.TextXAlignment.Left, font=F.NUM, parent=dBody})
	
	local dFoot = Utils.mkFrame({size=UDim2.new(1,-20,0,50), pos=UDim2.new(0.5,0,1,-15), anchor=Vector2.new(0.5,1), bgT=1, parent=detail})
	TechUI.Refs.Detail.BtnUnlock = Utils.mkBtn({text="연구 시작", size=UDim2.new(1,0,1,0), bg=C.GOLD_SEL, font=F.TITLE, ts=20, color=C.BG_PANEL, fn=function() UIManager._doUnlockTech() end, parent=dFoot})
end

function TechUI.SetVisible(visible)
	if TechUI.Refs.Frame then
		TechUI.Refs.Frame.Visible = visible
	end
end

function TechUI.Refresh(techList, unlocked, tp, getItemIcon, UIManager)
	if TechUI.Refs.TPText then TechUI.Refs.TPText.Text = "보유 TP: " .. tp end
	local scroll = TechUI.Refs.GridScroll
	if not scroll then return end

	for _, ch in pairs(scroll:GetChildren()) do
		if ch:IsA("GuiObject") and not ch:IsA("UIGridLayout") then ch:Destroy() end
	end

	for _, node in ipairs(techList) do
		local isUnlocked = unlocked[node.id]
		local isLocked = not isUnlocked
		
		local slot = Utils.mkSlot({
			name = node.id, r = 0, bgT = 0.3, 
			strokeC = isUnlocked and C.GOLD_SEL or C.BORDER_DIM,
			parent = scroll
		})

		slot.icon.Image = getItemIcon(node.id) -- Assuming node.id acts as an implicit itemId, or DataHelper matches it
		
		if isUnlocked then
			slot.icon.ImageColor3 = Color3.new(1, 1, 1)
			slot.frame.BackgroundColor3 = C.SUCCESS
			slot.frame.BackgroundTransparency = 0.4
			Utils.mkLabel({text = "완료", size = UDim2.new(1, 0, 1, 0), ts = 14, z = 5, color = C.GOLD_SEL, parent = slot.frame})
		else
			slot.icon.ImageColor3 = Color3.new(0.4, 0.4, 0.4)
			Utils.mkLabel({text = "잠김", size = UDim2.new(1, 0, 1, 0), ts = 16, z = 5, parent = slot.frame})
		end
		
		slot.click.MouseButton1Click:Connect(function()
			UIManager._onTechNodeClick(node)
		end)
	end
end

function TechUI.UpdateDetail(node, isUnlocked, canAfford, UIManager)
	local d = TechUI.Refs.Detail
	if not d.Frame then return end
	
	if not node then
		d.Name.Text = "연구 대상을 선택하세요"
		d.Desc.Text = ""
		d.ReqText.Text = ""
		d.CostText.Text = ""
		d.Icon.Image = ""
		d.Icon.Visible = false
		d.BtnUnlock.Visible = false
		return
	end

	d.Name.Text = (isUnlocked and "[완료] " or "") .. (node.name or node.id)
	d.Icon.Image = "" -- Wait for asset map to be defined in getItemIcon logic
	d.Icon.Visible = true

	d.Desc.Text = node.desc or "새로운 능력을 해금합니다."
	d.CostText.Text = "요구 TP: " .. (node.cost or 0)
	
	if isUnlocked then
		d.ReqText.Text = "이미 연구된 기술입니다."
		d.ReqText.TextColor3 = C.GREEN
		d.BtnUnlock.Visible = false
	else
		d.ReqText.Text = ""
		d.BtnUnlock.Visible = true
		d.BtnUnlock.Text = "연구 완료하기"
		d.BtnUnlock.BackgroundColor3 = canAfford and C.GOLD_SEL or C.BTN_DIS
		d.BtnUnlock.AutoButtonColor = canAfford
	end
end

return TechUI
