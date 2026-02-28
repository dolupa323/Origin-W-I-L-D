local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local TechUI = {}
TechUI.Refs = {
	Detail = {}
}

local currentCategory = "ALL"
local nodeRefs = {} -- [techId] = slot object

function TechUI.Init(parent, UIManager, isMobile)
	local isSmall = isMobile
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
		size = UDim2.new(isSmall and 0.95 or 0.9, 0, isSmall and 0.95 or 0.85, 0),
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = T.PANEL,
		r = 0, stroke = 2, strokeC = C.BORDER_DIM,
		ratio = isSmall and 1.3 or 1.6,
		parent = TechUI.Refs.Frame
	})

	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,45), bgT=1, parent=main})
	TechUI.Refs.Title = Utils.mkLabel({text="기술 및 연구", pos=UDim2.new(0, 15, 0, 0), ts=24, font=F.TITLE, color=C.WHITE, ax=Enum.TextXAlignment.Left, parent=header})
	TechUI.Refs.TPText = Utils.mkLabel({text="보유 TP: 0", pos=UDim2.new(0, 180, 0, 5), ts=isSmall and 15 or 18, font=F.TITLE, color=C.GOLD, ax=Enum.TextXAlignment.Left, parent=header})
	
	-- Relinquish (Reset) Button
	Utils.mkBtn({
		text="전체 초기화", size=UDim2.new(0, 100, 0, 30), pos=UDim2.new(1, -60, 0, 7), anchor=Vector2.new(1,0),
		bg=C.RED, ts=14, font=F.TITLE, fn=function() UIManager._doResetTech() end, parent=header
	})
	
	Utils.mkBtn({text="X", size=UDim2.new(0, 30, 0, 30), pos=UDim2.new(1, -15, 0, 7), anchor=Vector2.new(1,0), bgT=1, ts=26, color=C.WHITE, fn=function() UIManager.closeTechTree() end, parent=header})

	-- Category Tabs
	local tabArea = Utils.mkFrame({name="Tabs", size=UDim2.new(1,0,0,35), pos=UDim2.new(0,0,0,45), bgT=0.5, bg=C.BG_PANEL_L, parent=main})
	local tList = Instance.new("UIListLayout"); tList.FillDirection=Enum.FillDirection.Horizontal; tList.Padding=UDim.new(0,10); tList.HorizontalAlignment=Enum.HorizontalAlignment.Center; tList.Parent=tabArea
	local cats = {"ALL", "SURVIVAL", "SETTLEMENT", "WEAPONS", "TOOLS", "FACILITIES"}
	TechUI.Refs.Tabs = {}
	for _, cat in ipairs(cats) do
		local btn = Utils.mkBtn({
			text = cat,
			size = UDim2.new(0, isSmall and 75 or 100, 1, 0),
			bgT = 1,
			ts = 12,
			bold = true,
			color = C.GRAY,
			fn = function() 
				currentCategory = cat
				for c, b in pairs(TechUI.Refs.Tabs) do b.TextColor3 = (c == cat) and C.GOLD_SEL or C.GRAY end
				if TechUI.lastTechList then TechUI.Refresh(TechUI.lastTechList, TechUI.lastUnlocked, TechUI.lastTP, TechUI.lastIconFn, UIManager) end
			end,
			parent = tabArea
		})
		TechUI.Refs.Tabs[cat] = btn
	end
	TechUI.Refs.Tabs["ALL"].TextColor3 = C.GOLD_SEL

	local content = Utils.mkFrame({name="Content", size=UDim2.new(1, -20, 1, -95), pos=UDim2.new(0, 10, 0, 85), bgT=1, parent=main})
	
	-- Left Side: Tree Area
	local gridArea = Utils.mkFrame({name="GridArea", size=UDim2.new(0.65, -10, 1, 0), bgT=1, bg=Color3.new(0,0,0), parent=content})
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "GridScroll"
	scroll.Size = UDim2.new(1, 0, 1, 0); scroll.BackgroundTransparency = 1; scroll.BorderSizePixel = 0; scroll.ScrollBarThickness = 2
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.XY -- Both X and Y for tree
	scroll.ClipsDescendants = true
	scroll.Parent = gridArea
	TechUI.Refs.GridScroll = scroll
	
	-- Line Container (under nodes)
	TechUI.Refs.LineContainer = Utils.mkFrame({name="Lines", size=UDim2.new(1,0,1,0), bgT=1, z=0, parent=scroll})
	
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
	TechUI.lastTechList = techList; TechUI.lastUnlocked = unlocked; TechUI.lastTP = tp; TechUI.lastIconFn = getItemIcon
	if TechUI.Refs.TPText then TechUI.Refs.TPText.Text = "보유 TP: " .. tp end
	local scroll = TechUI.Refs.GridScroll
	if not scroll then return end

	-- Cleanup
	for _, ch in pairs(scroll:GetChildren()) do
		if ch:IsA("GuiObject") and ch.Name ~= "Lines" then ch:Destroy() end
	end
	TechUI.Refs.LineContainer:ClearAllChildren()
	nodeRefs = {}

	-- Calculate Depth based on prerequisites
	local depth = {}
	local function getDepth(id, visited)
		if depth[id] then return depth[id] end
		if visited[id] then return 0 end -- Cyclic dep guard
		visited[id] = true
		
		local node = nil
		for _, n in ipairs(techList) do if n.id == id then node = n; break end end
		if not node or not node.prerequisites or #node.prerequisites == 0 then
			depth[id] = 1
			return 1
		end
		
		local maxD = 0
		for _, pid in ipairs(node.prerequisites) do
			maxD = math.max(maxD, getDepth(pid, visited))
		end
		depth[id] = maxD + 1
		return depth[id]
	end
	
	for _, node in ipairs(techList) do
		getDepth(node.id, {})
	end

	local spacingX, spacingY = 180, 110
	local levelOffsets = {} -- [depth] = lastY
	
	-- Filtered List
	local filtered = {}
	for _, node in ipairs(techList) do
		if currentCategory == "ALL" or node.category == currentCategory then
			table.insert(filtered, node)
		end
	end

	-- Create Nodes
	for _, node in ipairs(filtered) do
		local d = depth[node.id] or 1
		local yIdx = levelOffsets[d] or 0
		levelOffsets[d] = yIdx + 1
		
		local posX = (d - 1) * spacingX + 50
		local posY = yIdx * spacingY + 50
		
		local isUnlocked = unlocked[node.id]
		local canAfford = tp >= (node.cost or 0)
		-- Prerequisites check (logic from controller)
		local preMet = true
		if node.prerequisites then
			for _, pid in ipairs(node.prerequisites) do if not unlocked[pid] then preMet = false; break end end
		end

		local slotSize = 75
		local slot = Utils.mkSlot({
			name = node.id, 
			size = UDim2.new(0, slotSize, 0, slotSize),
			pos = UDim2.new(0, posX, 0, posY),
			r = 4, bgT = 0.3, 
			strokeC = isUnlocked and C.GOLD_SEL or (preMet and C.WHITE or C.BORDER_DIM),
			stroke = isUnlocked and 2 or 1,
			parent = scroll
		})
		
		nodeRefs[node.id] = slot
		slot.icon.Image = getItemIcon(node.id)
		
		if isUnlocked then
			slot.icon.ImageColor3 = Color3.new(1, 1, 1)
			slot.frame.BackgroundColor3 = C.SUCCESS
			slot.frame.BackgroundTransparency = 0.4
			Utils.mkLabel({text = "완료", size = UDim2.new(1, 0, 0, 20), pos=UDim2.new(0,0,1,2), ts = 12, bold=true, color = C.GOLD_SEL, parent = slot.frame})
		elseif preMet then
			slot.icon.ImageColor3 = Color3.new(0.8, 0.8, 0.8)
			if canAfford then
				-- 해금 가능 발광 효과 (UIStroke 애니메이션 선호하지만 간단히 색상 강조)
				local st = slot.frame:FindFirstChildOfClass("UIStroke")
				if st then st.Color = C.GOLD; st.Thickness = 2 end
			end
		else
			slot.icon.ImageColor3 = Color3.new(0.3, 0.3, 0.3)
			local lock = Instance.new("ImageLabel")
			lock.Size = UDim2.new(0.4,0,0.4,0); lock.Position = UDim2.new(0.5,0,0.5,0); lock.AnchorPoint = Vector2.new(0.5,0.5); lock.BackgroundTransparency = 1; lock.Image = "rbxassetid://6031084651"; lock.Parent = slot.frame
		end
		
		slot.click.MouseButton1Click:Connect(function()
			UIManager._onTechNodeClick(node)
		end)
	end
	
	-- Draw Lines (After all nodes created)
	for _, node in ipairs(filtered) do
		if node.prerequisites and nodeRefs[node.id] then
			for _, pid in ipairs(node.prerequisites) do
				if nodeRefs[pid] then
					local startPos = Vector2.new(nodeRefs[pid].frame.AbsolutePosition.X - scroll.AbsolutePosition.X + 37, nodeRefs[pid].frame.AbsolutePosition.Y - scroll.AbsolutePosition.Y + 37)
					-- AbsolutePosition is tricky with scrolling, use relative Offset math instead
					local p1 = Vector2.new(nodeRefs[pid].frame.Position.X.Offset + 37, nodeRefs[pid].frame.Position.Y.Offset + 37)
					local p2 = Vector2.new(nodeRefs[node.id].frame.Position.X.Offset + 37, nodeRefs[node.id].frame.Position.Y.Offset + 37)
					
					Utils.mkLine({
						p1 = p1, p2 = p2,
						thick = 2,
						color = unlocked[pid] and C.GOLD_SEL or C.BORDER_DIM,
						bgT = 0.5,
						parent = TechUI.Refs.LineContainer
					})
				end
			end
		end
	end
	
	-- Canvas size update
	local maxLevel = 1; for _, n in ipairs(filtered) do maxLevel = math.max(maxLevel, n.requireLevel or 1) end
	local maxY = 0; for _, y in pairs(levelOffsets) do maxY = math.max(maxY, y) end
	scroll.CanvasSize = UDim2.new(0, maxLevel * spacingX + 200, 0, maxY * spacingY + 200)
end

function TechUI.UpdateDetail(node, isUnlocked, canAfford, UIManager, getItemIcon)
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
		if d.UnlockList then d.UnlockList.Visible = false end
		return
	end

	d.Name.Text = (isUnlocked and "[연구 완료] " or "") .. (node.name or node.id)
	d.Icon.Image = getItemIcon(node.id)
	d.Icon.Visible = true

	d.Desc.Text = node.desc or "새로운 능력을 해금합니다."
	d.CostText.Text = "요구 기술 포인트 (TP): " .. (node.techPointCost or 0)
	
	-- Unlocks List
	if not d.UnlockList then
		d.UnlockList = Utils.mkFrame({name="UnlockList", size=UDim2.new(1,0,0,80), bgT=1, parent=d.Frame})
		d.UnlockList.Position = UDim2.new(0, 5, 0, 260)
		local l = Instance.new("UIListLayout"); l.FillDirection=Enum.FillDirection.Horizontal; l.Padding=UDim.new(0,5); l.Parent=d.UnlockList
	end
	d.UnlockList.Visible = true
	d.UnlockList:ClearAllChildren()
	Instance.new("UIListLayout", d.UnlockList).FillDirection = Enum.FillDirection.Horizontal
	
	if node.unlocks then
		local all = {}
		for _, r in ipairs(node.unlocks.recipes or {}) do table.insert(all, {id=r, type="RECIPE"}) end
		for _, f in ipairs(node.unlocks.facilities or {}) do table.insert(all, {id=f, type="FACILITY"}) end
		
		for _, item in ipairs(all) do
			local slot = Utils.mkFrame({size=UDim2.new(0,40,0,40), bg=C.BG_SLOT, stroke=1, parent=d.UnlockList})
			local img = Instance.new("ImageLabel")
			img.Size = UDim2.new(1,-4,1,-4); img.Position = UDim2.new(0.5,0,0.5,0); img.AnchorPoint = Vector2.new(0.5,0.5); img.BackgroundTransparency=1
			img.Image = getItemIcon(item.id)
			img.Parent = slot
		end
	end

	if isUnlocked then
		d.ReqText.Text = "이미 마스터한 기술입니다."
		d.ReqText.TextColor3 = C.GREEN
		d.BtnUnlock.Visible = false
	else
		local preMet = true
		if node.prerequisites then
			for _, pid in ipairs(node.prerequisites) do if not UIManager.isTechUnlocked(pid) then preMet = false; break end end
		end
		
		if not preMet then
			d.ReqText.Text = "선행 기술 연구가 먼저 필요합니다."
			d.ReqText.TextColor3 = C.RED
			d.BtnUnlock.Visible = false
		else
			d.ReqText.Text = ""
			d.BtnUnlock.Visible = true
			d.BtnUnlock.Text = "연구 시작하기"
			d.BtnUnlock.BackgroundColor3 = canAfford and C.GOLD_SEL or C.BTN_DIS
			d.BtnUnlock.AutoButtonColor = canAfford
		end
	end
end

function TechUI.ShowUnlockSuccessPopup(node, getItemIcon, parent)
	local popup = Utils.mkFrame({
		name = "UnlockPopup",
		size = UDim2.new(0, 300, 0, 150),
		pos = UDim2.new(0.5, 0, 0.4, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		useCanvas = true,
		stroke = 2, strokeC = C.GOLD_SEL,
		z = 1000,
		parent = parent
	})
	
	Utils.mkLabel({text = "연구 완료!", size = UDim2.new(1,0,0,40), ts = 22, font = F.TITLE, color = C.GOLD_SEL, parent = popup})
	Utils.mkLabel({text = node.name or node.id, size = UDim2.new(1,0,0,30), pos = UDim2.new(0,0,0,40), ts = 18, color = C.WHITE, parent = popup})
	
	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0, 50, 0, 50)
	icon.Position = UDim2.new(0.5, 0, 0, 85)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.BackgroundTransparency = 1
	icon.Image = getItemIcon(node.id)
	icon.Parent = popup
	
	popup.GroupTransparency = 1
	TweenService:Create(popup, TweenInfo.new(0.5), {GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0.5, 0)}):Play()
	
	task.delay(2.5, function()
		TweenService:Create(popup, TweenInfo.new(0.5), {GroupTransparency = 1}):Play()
		game.Debris:AddItem(popup, 0.6)
	end)
end

return TechUI
