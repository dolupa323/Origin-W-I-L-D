-- TechUI.lua (Durango Style Full Rewrite)
-- 탭 분류, 화살표 트리형 디자인, 상세 텍스트를 줄이고 시각적 기호에 집중

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local C = Theme.Colors
local F = Theme.Fonts

local TechUI = {}
TechUI.Refs = { Tabs = {}, Nodes = {}, Lines = {} }

local currentUIManager = nil
local activeTab = 1
local CATEGORY_TABS = {
	{ name = "근접전/생존", keys = {"SURVIVAL", "FARMING"} },
	{ name = "도구/무기", keys = {"WEAPONS", "TOOLS"} },
	{ name = "건축/설비", keys = {"SETTLEMENT", "FACILITIES"} },
	{ name = "포획/이동", keys = {"PAL"} },
}

local selectedNodeId = nil

----------------------------------------------------------------
-- 유틸: 아이콘 해결
----------------------------------------------------------------
local function resolveNodeIcon(node, getItemIcon)
	local icon = getItemIcon and getItemIcon(node.id) or ""
	if icon ~= "" and not icon:find("15573752528") then return icon end
	if node.unlocks then
		if node.unlocks.facilities and #node.unlocks.facilities > 0 then
			local i = getItemIcon and getItemIcon(node.unlocks.facilities[1]) or ""
			if i ~= "" then return i end
		end
		if node.unlocks.recipes and #node.unlocks.recipes > 0 then
			local i = getItemIcon and getItemIcon(node.unlocks.recipes[1]) or ""
			if i ~= "" then return i end
		end
	end
	return "" -- 기본 아이콘 추가 가능
end

----------------------------------------------------------------
-- 유틸: 선긋기 (Arrow)
----------------------------------------------------------------
local function drawLine(parent, ptA, ptB, isRed, zIndex)
	local f = Instance.new("Frame")
	f.Name = "Line"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	
	local center = (ptA + ptB) / 2
	local len = (ptB - ptA).Magnitude
	local angle = math.deg(math.atan2(ptB.Y - ptA.Y, ptB.X - ptA.X))
	
	f.Position = UDim2.new(0, center.X, 0, center.Y)
	f.Size = UDim2.new(0, len, 0, 3)
	f.Rotation = angle
	f.BackgroundColor3 = isRed and Color3.fromRGB(180, 50, 50) or Color3.fromRGB(100, 100, 100)
	f.BorderSizePixel = 0
	f.ZIndex = zIndex
	f.Parent = parent
	
	table.insert(TechUI.Refs.Lines, f)
	
	local arr = Instance.new("TextLabel")
	arr.Size = UDim2.new(0, 15, 0, 15)
	arr.AnchorPoint = Vector2.new(1, 0.5)
	arr.Position = UDim2.new(1, 3, 0.5, 0)
	arr.BackgroundTransparency = 1
	arr.Text = "▶"
	arr.TextColor3 = f.BackgroundColor3
	arr.TextSize = 14
	arr.Font = Enum.Font.ArialBold
	arr.ZIndex = zIndex + 1
	arr.Parent = f
end

----------------------------------------------------------------
-- 선택 상태 업데이트
----------------------------------------------------------------
local function updateSelectionHighlight()
	for id, ui in pairs(TechUI.Refs.Nodes) do
		local st = ui:FindFirstChildOfClass("UIStroke")
		local tag = ui:FindFirstChild("_isUnlocked")
		local glow = ui:FindFirstChild("GlowBox")
		
		local isUnlocked = tag and tag.Value == true
		
		if id == selectedNodeId then
			if st then st.Color = C.GOLD; st.Thickness = 2.5 end
			if glow then glow.Visible = true end
		else
			if st then
				st.Color = isUnlocked and Color3.fromRGB(180, 150, 50) or Color3.fromRGB(60, 60, 60)
				st.Thickness = isUnlocked and 1.5 or 1
			end
			if glow then glow.Visible = false end
		end
	end
end

----------------------------------------------------------------
-- 뷰 렌더링 (단일 탭)
----------------------------------------------------------------
local function renderTree(techList, unlocked, playerLevel, getItemIcon, UIManager)
	local canvas = TechUI.Refs.Canvas
	local bgGrid = TechUI.Refs.BgGrid
	if not canvas then return end

	-- 기존 노드, 선 삭제
	for _, c in ipairs(canvas:GetChildren()) do
		if c:IsA("GuiObject") and c ~= bgGrid then c:Destroy() end
	end
	for _, c in ipairs(bgGrid:GetChildren()) do
		if c.Name == "VLine" then c:Destroy() end
	end
	
	TechUI.Refs.Nodes = {}
	TechUI.Refs.Lines = {}
	
	local currentKeys = CATEGORY_TABS[activeTab].keys
	local filteredReqs = {}
	
	local nodePositions = {}
	local nodeSize = Vector2.new(78, 78)
	local xSpacing = 160
	local ySpacing = 120
	
	local lvlCols = {} -- lvlCols[lvl] = current_row
	
	-- 노드 위치 계산
	local maxX = 0
	local maxY = 0
	
	for _, node in ipairs(techList) do
		local inTab = false
		for _, k in ipairs(currentKeys) do
			if node.category == k then inTab = true; break end
		end
		
		if inTab then
			table.insert(filteredReqs, node)
			local lvl = tonumber(node.requireLevel) or 1
			
			local row = (lvlCols[lvl] or 0)
			local cx = (lvl - 1) * xSpacing + 70
			local cy = row * ySpacing + 80
			
			nodePositions[node.id] = Vector2.new(cx, cy)
			lvlCols[lvl] = row + 1
			
			if cx > maxX then maxX = cx end
			if cy > maxY then maxY = cy end
		end
	end
	
	-- 배경 그리선 배치 (Lv 표시)
	local maxLevelMark = maxX > 0 and math.floor(maxX / xSpacing) + 2 or 10
	for l = 1, maxLevelMark do
		local cx = (l - 1) * xSpacing + 70 + nodeSize.X/2
		-- 선
		local line = Instance.new("Frame")
		line.Name = "VLine"
		line.Size = UDim2.new(0, 1, 1, 0)
		line.Position = UDim2.new(0, cx, 0, 0)
		line.BackgroundColor3 = Color3.fromRGB(30,30,30)
		line.BorderSizePixel = 0
		line.ZIndex = 0
		line.Parent = bgGrid
		-- 글씨
		if true then -- 매 레벨마다 선 표시
			local txt = Instance.new("TextLabel")
			txt.Name = "VLine" -- 같이 삭제되게
			txt.Size = UDim2.new(0, 50, 0, 20)
			txt.Position = UDim2.new(0, cx - 25, 0, 8)
			txt.BackgroundTransparency = 1
			txt.Text = "Lv. " .. l
			txt.Font = F.TITLE
			txt.TextSize = 13
			txt.TextColor3 = Color3.fromRGB(150, 150, 150)
			txt.ZIndex = 1
			txt.Parent = bgGrid
		end
	end
	
	canvas.CanvasSize = UDim2.new(0, maxX + 300, 0, maxY + 200)
	
	-- 노드 생성 및 선 그리기
	local lvl = type(playerLevel)=="number" and playerLevel or (tonumber(tostring(playerLevel)) or 1)
	
	for _, node in ipairs(filteredReqs) do
		local pos = nodePositions[node.id]
		local isUnlocked = unlocked[node.id] == true
		local preMet = true
		
		-- 선 연결 처리
		if node.prerequisites then
			for _, pid in ipairs(node.prerequisites) do
				local pDone = unlocked[pid] == true
				if not pDone then preMet = false end
				
				local pPos = nodePositions[pid]
				if pPos then
					-- 현재 탭 내에 선행이 있음
					local ptA = pPos + Vector2.new(nodeSize.X, nodeSize.Y/2)
					local ptB = pos + Vector2.new(0, nodeSize.Y/2)
					-- 꺾인 선 보단 직관적인 직선 사용
					drawLine(canvas, ptA, ptB, not pDone, 100)
				else
					-- 타 탭의 선행 (유령 노드)
					local pname = pid
					for _, tn in ipairs(techList) do if tn.id == pid then pname = tn.name or pid break end end
					
					local gIdx = math.random(1, 1000)
					local gx = pos.X - 90
					local gy = pos.Y + 15
					
					local g = Instance.new("TextLabel")
					g.Size = UDim2.new(0, 70, 0, 22)
					g.Position = UDim2.new(0, gx, 0, gy)
					g.BackgroundColor3 = Color3.fromRGB(30, 20, 20)
					g.BorderSizePixel = 0
					g.Text = "선행: " .. pname
					g.TextColor3 = pDone and Color3.fromRGB(150,150,150) or Color3.fromRGB(200, 80, 80)
					g.TextSize = 10
					g.Font = F.TITLE
					g.ZIndex = 110
					local gc = Instance.new("UICorner"); gc.CornerRadius = UDim.new(0,3); gc.Parent = g
					local gs = Instance.new("UIStroke"); gs.Color = pDone and Color3.fromRGB(60,60,60) or Color3.fromRGB(120,50,50); gs.Parent = g
					g.Parent = canvas
					
					local ptA = Vector2.new(gx + 70, gy + 11)
					local ptB = pos + Vector2.new(0, nodeSize.Y/2)
					drawLine(canvas, ptA, ptB, not pDone, 100)
				end
			end
		end
		
		local reqLevel = tonumber(node.requireLevel) or 1
		local lvlMet = lvl >= reqLevel
		
		-- 노드 시각화 (테두리를 날카롭게 깎은 육각형 스타일을 위해 둥근 코너의 다이아/사각 혼합 사용)
		-- 듀랑고는 육각형/기울어진 사각이지만, 우리는 모던한 둥근 사각+금색 장식으로
		local cell = Instance.new("Frame")
		cell.Name = node.id
		cell.Size = UDim2.new(0, nodeSize.X, 0, nodeSize.Y)
		cell.Position = UDim2.new(0, pos.X, 0, pos.Y)
		
		if isUnlocked then
			cell.BackgroundColor3 = Color3.fromRGB(30, 80, 40)
			cell.BackgroundTransparency = 0.2
		elseif not preMet or not lvlMet then
			cell.BackgroundColor3 = Color3.fromRGB(40, 25, 25)
			cell.BackgroundTransparency = 0.4
		else
			cell.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
			cell.BackgroundTransparency = 0.2
		end
		
		local cor = Instance.new("UICorner"); cor.CornerRadius = UDim.new(0, 10); cor.Parent = cell
		local stk = Instance.new("UIStroke")
		stk.Color = isUnlocked and Color3.fromRGB(180, 150, 50) or Color3.fromRGB(60, 60, 60)
		stk.Thickness = isUnlocked and 1.5 or 1
		stk.Parent = cell
		
		local tag = Instance.new("BoolValue"); tag.Name = "_isUnlocked"; tag.Value = isUnlocked; tag.Parent = cell
		
		-- 아이콘
		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(0, 48, 0, 48)
		icon.Position = UDim2.new(0.5, 0, 0.5, -6)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.BackgroundTransparency = 1
		icon.Image = resolveNodeIcon(node, getItemIcon)
		if not isUnlocked and not preMet then icon.ImageColor3 = Color3.fromRGB(80, 80, 80) end
		icon.ZIndex = 200
		icon.Parent = cell
		
		-- 해금 완료 마크
		if isUnlocked then
			local d = Instance.new("TextLabel")
			d.Size=UDim2.new(0,20,0,20); d.Position=UDim2.new(0,2,0,2)
			d.BackgroundColor3=Color3.fromRGB(20,50,20); d.Text="✓"; d.TextColor3=Color3.fromRGB(100,255,100)
			d.TextSize=14; d.Font=F.TITLE; d.ZIndex=202; d.Parent=cell
			local dc=Instance.new("UICorner"); dc.CornerRadius=UDim.new(0,4); dc.Parent=d
		end
		
		-- 이름
		local nameL = Instance.new("TextLabel")
		nameL.Size = UDim2.new(1, 0, 0, 20)
		nameL.Position = UDim2.new(0, 0, 1, 0)
		nameL.BackgroundTransparency = 1
		nameL.Text = node.name or node.id
		nameL.Font = F.TITLE; nameL.TextSize = 12
		nameL.TextColor3 = isUnlocked and C.GOLD or (preMet and lvlMet and C.WHITE or Color3.fromRGB(150,150,150))
		nameL.ZIndex = 201; nameL.Parent = cell
		
		-- 필요포인트 (SP) 뱃지
		local tpBadge = Instance.new("TextLabel")
		tpBadge.Size=UDim2.new(0,34,0,16); tpBadge.Position=UDim2.new(1,-4,0,-10); tpBadge.AnchorPoint=Vector2.new(1,0)
		tpBadge.BackgroundColor3=Color3.fromRGB(20,20,20)
		tpBadge.Text="SP " .. tostring(node.techPointCost or 0)
		tpBadge.TextColor3=Color3.fromRGB(220,180,80)
		tpBadge.TextSize=11; tpBadge.Font=F.TITLE; tpBadge.ZIndex=205; tpBadge.Parent=cell
		local tbc=Instance.new("UICorner"); tbc.CornerRadius=UDim.new(0,4); tbc.Parent=tpBadge

		local glow = Instance.new("Frame")
		glow.Name = "GlowBox"
		glow.Size = UDim2.new(1, 6, 1, 6)
		glow.Position = UDim2.new(0.5, 0, 0.5, 0)
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.BackgroundColor3 = C.GOLD
		glow.BackgroundTransparency = 0.8
		glow.Visible = false
		glow.ZIndex = 199
		local glc = Instance.new("UICorner"); glc.CornerRadius = UDim.new(0,10); glc.Parent = glow
		glow.Parent = cell

		local clicker = Instance.new("TextButton")
		clicker.Size = UDim2.new(1, 0, 1, 0)
		clicker.BackgroundTransparency = 1
		clicker.Text = ""
		clicker.ZIndex = 300
		clicker.Parent = cell
		
		clicker.MouseButton1Click:Connect(function()
			selectedNodeId = node.id
			updateSelectionHighlight()
			if UIManager then UIManager._onTechNodeClick(node) end
		end)
		
		cell.ZIndex = 150
		cell.Parent = canvas
		TechUI.Refs.Nodes[node.id] = cell
	end
	
	updateSelectionHighlight()
end

----------------------------------------------------------------
-- 초기화
----------------------------------------------------------------
function TechUI.Init(parent, UIManager, isMobile)
	currentUIManager = UIManager

	TechUI.Refs.Frame = Utils.mkFrame({
		name = "TechMenu", size = UDim2.new(1,0,1,0),
		bg = Color3.new(0,0,0), bgT = 0.85, vis = false, parent = parent,
	})

	local main = Utils.mkWindow({
		name = "Main",
		size = UDim2.new(isMobile and 1 or 0.95, 0, isMobile and 1 or 0.9, 0),
		maxSize = Vector2.new(1400, 900),
		pos = UDim2.new(0.5,0,0.5,0), anchor = Vector2.new(0.5,0.5),
		bg = Color3.fromRGB(15, 15, 18), bgT = 0, stroke = 1, strokeC = Color3.fromRGB(40,40,40),
		parent = TechUI.Refs.Frame,
	})

	-- 헤더 (듀랑고 느낌의 슬림한 상단바)
	local header = Utils.mkFrame({
		name="Header", size=UDim2.new(1,0,0,45),
		bg=Color3.fromRGB(10,10,12), parent=main,
	})
	Utils.mkLabel({
		text="  ⚙ 기술 및 연구", pos=UDim2.new(0,0,0,0),
		size=UDim2.new(0.3,0,1,0), ts=20, font=F.TITLE, color=C.WHITE,
		ax=Enum.TextXAlignment.Left, parent=header,
	})
	TechUI.Refs.TPText = Utils.mkLabel({
		text="SP: 0", pos=UDim2.new(0.6,0,0,0),
		size=UDim2.new(0.3,0,1,0), ts=18, font=F.TITLE, color=C.GOLD,
		ax=Enum.TextXAlignment.Right, parent=header,
	})
	Utils.mkBtn({
		text="X", size=UDim2.new(0,40,0,40),
		pos=UDim2.new(1,-6,0.5,0), anchor=Vector2.new(1,0.5),
		bg=Color3.fromRGB(40,40,40), bgT=0.5, ts=20, font=F.TITLE, color=C.WHITE, r=5,
		fn=function() UIManager.closeTechTree() end, parent=header,
	})

	local contentBox = Utils.mkFrame({
		name="ContentHBox", size=UDim2.new(1,0,1,-45),
		pos=UDim2.new(0,0,0,45), bgT=1, parent=main
	})
	
	-- 좌측 탭 영역
	local tabListPanel = Utils.mkFrame({
		name="TabList", size=UDim2.new(0, 180, 1, 0), bg=Color3.fromRGB(12,12,15), parent=contentBox
	})
	local tlLayout = Instance.new("UIListLayout"); tlLayout.Padding=UDim.new(0,1); tlLayout.Parent=tabListPanel
	
	for i, cat in ipairs(CATEGORY_TABS) do
		local tBtn = Utils.mkBtn({
			text = "   " .. cat.name, size = UDim2.new(1,0,0,50),
			bg = Color3.fromRGB(20,20,25), bgT = 0, color=Color3.fromRGB(180,180,180),
			ts = 15, font = F.TITLE, r=0,
			parent = tabListPanel
		})
		tBtn.TextXAlignment = Enum.TextXAlignment.Left
		
		local ind = Instance.new("Frame")
		ind.Size = UDim2.new(0,4,1,0)
		ind.BackgroundColor3 = C.GOLD
		ind.BorderSizePixel = 0
		ind.Visible = false
		ind.Parent = tBtn
		
		TechUI.Refs.Tabs[i] = { Btn = tBtn, Ind = ind }
		
		tBtn.MouseButton1Click:Connect(function()
			activeTab = i
			for j, tref in ipairs(TechUI.Refs.Tabs) do
				if j == activeTab then
					tref.Btn.BackgroundColor3 = Color3.fromRGB(35,35,30)
					tref.Btn.TextColor3 = C.GOLD
					tref.Ind.Visible = true
				else
					tref.Btn.BackgroundColor3 = Color3.fromRGB(20,20,25)
					tref.Btn.TextColor3 = Color3.fromRGB(180,180,180)
					tref.Ind.Visible = false
				end
			end
			if TechUI.lastTechList then
				renderTree(TechUI.lastTechList, TechUI.lastUnlocked, TechUI.lastLevel, TechUI.lastIconFn, currentUIManager)
				UIManager._onTechNodeClick(nil) -- 선택 초기화
				selectedNodeId = nil
				updateSelectionHighlight()
			end
		end)
	end
	
	-- 초기 탭 세팅
	TechUI.Refs.Tabs[1].Btn.BackgroundColor3 = Color3.fromRGB(35,35,30)
	TechUI.Refs.Tabs[1].Btn.TextColor3 = C.GOLD
	TechUI.Refs.Tabs[1].Ind.Visible = true

	-- 중앙 캔버스 영역
	local canvasWrapper = Utils.mkFrame({
		name="CanvasWrap", size=UDim2.new(1, -180, 1, 0),
		pos=UDim2.new(0,180,0,0), bg=Color3.fromRGB(20,22,25), parent=contentBox
	})
	
	TechUI.Refs.Canvas = Instance.new("ScrollingFrame")
	TechUI.Refs.Canvas.Name = "TreeCanvas"
	TechUI.Refs.Canvas.Size = UDim2.new(1, 0, 1, 0)
	TechUI.Refs.Canvas.BackgroundTransparency = 1
	TechUI.Refs.Canvas.BorderSizePixel = 0
	TechUI.Refs.Canvas.ScrollBarThickness = 6
	TechUI.Refs.Canvas.Parent = canvasWrapper
	
	TechUI.Refs.BgGrid = Instance.new("Frame")
	TechUI.Refs.BgGrid.Name = "BgGrid"
	TechUI.Refs.BgGrid.Size = UDim2.new(1,0,1,0)
	TechUI.Refs.BgGrid.BackgroundTransparency = 1
	TechUI.Refs.BgGrid.ZIndex = 0
	TechUI.Refs.BgGrid.Parent = TechUI.Refs.Canvas
	
	-- 우측 상세 패널 (팝업 대신 사이드 바 고정)
	local detailSize = 250
	TechUI.Refs.DetailFrame = Utils.mkFrame({
		name="Detail", size=UDim2.new(0, detailSize, 1, -16),
		pos=UDim2.new(1, -detailSize - 8, 0, 8),
		bg=Color3.fromRGB(12,12,15), bgT=0.1, r=6, stroke=1, strokeC=Color3.fromRGB(40,40,40),
		parent=canvasWrapper
	})
	-- 선택 전엔 숨김
	TechUI.Refs.DetailFrame.Visible = false
	
	local dtHead = Utils.mkLabel({
		text="해당 노드 정보", size=UDim2.new(1,0,0,40),
		bg=Color3.fromRGB(30,30,30), bgT=0.2, color=C.GOLD, ts=16, font=F.TITLE,
		parent=TechUI.Refs.DetailFrame
	})
	TechUI.Refs.D_Name = Utils.mkLabel({
		text="이름", size=UDim2.new(1,-20,0,30), pos=UDim2.new(0,10,0,50),
		color=C.WHITE, ts=18, font=F.TITLE, ax=Enum.TextXAlignment.Left, parent=TechUI.Refs.DetailFrame
	})
	TechUI.Refs.D_Icon = Instance.new("ImageLabel")
	TechUI.Refs.D_Icon.Size = UDim2.new(0, 60, 0, 60); TechUI.Refs.D_Icon.Position = UDim2.new(0,10,0,85)
	TechUI.Refs.D_Icon.BackgroundTransparency = 1; TechUI.Refs.D_Icon.Parent = TechUI.Refs.DetailFrame
	
	TechUI.Refs.D_Desc = Utils.mkLabel({
		text="설명", size=UDim2.new(1,-90,0,60), pos=UDim2.new(0,80,0,85),
		color=Color3.fromRGB(180,180,180), ts=12, wrap=true,
		ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, parent=TechUI.Refs.DetailFrame
	})
	
	-- 통합된 경고 메시지 박스
	TechUI.Refs.D_WarnBox = Instance.new("Frame")
	TechUI.Refs.D_WarnBox.Size=UDim2.new(1,-20,0,0); TechUI.Refs.D_WarnBox.Position=UDim2.new(0,10,0,160)
	TechUI.Refs.D_WarnBox.AutomaticSize=Enum.AutomaticSize.Y
	TechUI.Refs.D_WarnBox.BackgroundColor3=Color3.fromRGB(40,15,15); TechUI.Refs.D_WarnBox.BorderSizePixel=0
	local wc=Instance.new("UICorner"); wc.CornerRadius=UDim.new(0,4); wc.Parent=TechUI.Refs.D_WarnBox
	local wp=Instance.new("UIPadding"); wp.PaddingTop=UDim.new(0,8); wp.PaddingBottom=UDim.new(0,8)
	wp.PaddingLeft=UDim.new(0,10); wp.PaddingRight=UDim.new(0,10); wp.Parent=TechUI.Refs.D_WarnBox
	TechUI.Refs.D_WarnTxt = Utils.mkLabel({
		text="", size=UDim2.new(1,0,0,0), ts=12, color=Color3.fromRGB(255,100,100), font=F.TITLE,
		ax=Enum.TextXAlignment.Left, wrap=true, parent=TechUI.Refs.D_WarnBox
	})
	TechUI.Refs.D_WarnTxt.AutomaticSize = Enum.AutomaticSize.Y
	TechUI.Refs.D_WarnBox.Parent = TechUI.Refs.DetailFrame
	
	TechUI.Refs.D_ActionBtn = Utils.mkBtn({
		text="연구 시작", size=UDim2.new(1, -20, 0, 45), pos=UDim2.new(0, 10, 1, -55),
		bg=C.GOLD, color=Color3.fromRGB(20,20,20), ts=16, font=F.TITLE, r=5,
		fn=function() UIManager._doUnlockTech() end, parent=TechUI.Refs.DetailFrame
	})
end

function TechUI.SetVisible(visible)
	if TechUI.Refs.Frame then TechUI.Refs.Frame.Visible = visible end
end

function TechUI.Refresh(techList, unlocked, tp, playerLevel, getItemIcon, UIManager)
	currentUIManager = UIManager
	TechUI.lastTechList = techList
	TechUI.lastUnlocked = unlocked
	TechUI.lastTP = tp
	TechUI.lastLevel = playerLevel
	TechUI.lastIconFn = getItemIcon
	
	if TechUI.Refs.TPText then TechUI.Refs.TPText.Text = "SP: " .. tostring(tp) end
	
	renderTree(techList, unlocked, playerLevel, getItemIcon, UIManager)
end

function TechUI.UpdateDetail(node, isUnlocked, canAfford, playerLevel, UIManager, getItemIcon)
	local d = TechUI.Refs.DetailFrame
	if not d then return end
	
	if not node then
		d.Visible = false
		return
	end
	
	d.Visible = true
	TechUI.Refs.D_Name.Text = node.name or node.id
	TechUI.Refs.D_Icon.Image = resolveNodeIcon(node, getItemIcon)
	TechUI.Refs.D_Desc.Text = node.description or "이 레시피와 시설을 활성화합니다."
	
	-- 조건/경고 로직
	local lvl = type(playerLevel)=="number" and playerLevel or (tonumber(tostring(playerLevel)) or 1)
	local reqLvl = tonumber(node.requireLevel) or 1
	
	local box = TechUI.Refs.D_WarnBox
	local txt = TechUI.Refs.D_WarnTxt
	local btn = TechUI.Refs.D_ActionBtn
	
	if isUnlocked then
		box.Visible = false
		btn.Visible = false
	else
		local preMet = true
		local lines = {}
		
		if node.prerequisites then
			for _, pid in ipairs(node.prerequisites) do
				local done = UIManager.isTechUnlocked(pid)
				if not done then
					preMet = false
					local pname = pid
					for _, tn in ipairs(TechUI.lastTechList) do if tn.id == pid then pname = tn.name or pid break end end
					table.insert(lines, "✗ 선행 필요: " .. pname)
				end
			end
		end
		
		if lvl < reqLvl then table.insert(lines, string.format("✗ 레벨 부족: Lv.%d 필요", reqLvl)) end
		
		if #lines > 0 then
			txt.Text = table.concat(lines, "\n")
			txt.TextColor3 = Color3.fromRGB(240, 100, 100)
			box.BackgroundColor3 = Color3.fromRGB(50, 15, 15)
			box.Visible = true
			
			btn.Visible = true
			btn.Text = "조건 미충족"
			btn.BackgroundColor3 = Color3.fromRGB(40,40,40)
			btn.TextColor3 = Color3.fromRGB(150,150,150)
			btn.AutoButtonColor = false
		else
			if not canAfford then
				txt.Text = string.format("💰 보유 SP 부족 (%d / %d)", TechUI.lastTP or 0, node.techPointCost or 0)
				txt.TextColor3 = Color3.fromRGB(230, 180, 50)
				box.BackgroundColor3 = Color3.fromRGB(40, 30, 10)
				box.Visible = true
				
				btn.Visible = true
				btn.Text = "SP 부족"
				btn.BackgroundColor3 = Color3.fromRGB(40,40,40)
				btn.TextColor3 = Color3.fromRGB(150,150,150)
				btn.AutoButtonColor = false
			else
				box.Visible = false
				btn.Visible = true
				btn.Text = "연구 시작 (SP: "..tostring(node.techPointCost or 0)..")"
				btn.BackgroundColor3 = C.GOLD
				btn.TextColor3 = Color3.fromRGB(20,20,20)
				btn.AutoButtonColor = true
			end
		end
	end
end

function TechUI.ShowUnlockSuccessPopup(node, getItemIcon, parent)
	local popup = Utils.mkFrame({
		name="UnlockPopup", size=UDim2.new(0,250,0,80),
		pos=UDim2.new(0.5,0,0.85,0), anchor=Vector2.new(0.5,0.5),
		bg=Color3.fromRGB(20,50,20), stroke=1, strokeC=Color3.fromRGB(100,200,100), r=8, z=1000, parent=parent,
	})
	Utils.mkLabel({text="연구 완료!", size=UDim2.new(1,0,0,30), pos=UDim2.new(0,0,0,10), ts=15, font=F.TITLE, color=Color3.fromRGB(150,255,150), parent=popup})
	Utils.mkLabel({text=node.name or node.id, size=UDim2.new(1,0,0,30), pos=UDim2.new(0,0,0,40), ts=18, color=C.WHITE, parent=popup})
	
	popup.GroupTransparency = 1
	TweenService:Create(popup, TweenInfo.new(0.3, Enum.EasingStyle.Quart), {GroupTransparency=0, Position=UDim2.new(0.5,0,0.8,0)}):Play()
	task.delay(2.0, function()
		if popup and popup.Parent then
			TweenService:Create(popup, TweenInfo.new(0.4), {GroupTransparency=1}):Play()
			game.Debris:AddItem(popup, 0.5)
		end
	end)
end

return TechUI
