-- TechUI.lua (Durango Style Full Rewrite)
-- 탭 분류, 화살표 트리형 디자인, 상세 텍스트를 줄이고 시각적 기호에 집중

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local DataHelper = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("DataHelper"))
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

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
	if icon ~= "" then return icon end
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
				st.Color = isUnlocked and C.GOLD or C.BORDER_DIM
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
		if c.Name == "HLine" then c:Destroy() end
	end
	
	TechUI.Refs.Nodes = {}
	TechUI.Refs.Lines = {}
	
	-- 존재하는 레벨 수집 및 정렬 (빈 레벨 스킵)
	local currentKeys = CATEGORY_TABS[activeTab].keys
	local filteredReqs = {}
	local nodePositions = {}
	local nodeSize = Vector2.new(68, 68) -- 노드 크기 살짝 축소
	local xSpacing = 90  -- 가로 간격 대폭 축소
	local ySpacing = 110 -- 세로 간격 대폭 축소 (레벨 섹션간 간격)
	
	local levelSet = {}
	for _, node in ipairs(techList) do
		local inTab = false
		for _, k in ipairs(currentKeys) do
			if node.category == k then inTab = true; break end
		end
		if inTab then
			table.insert(filteredReqs, node)
			local lvl = tonumber(node.requireLevel) or 1
			levelSet[lvl] = true
		end
	end
	
	local activeLevels = {}
	for l, _ in pairs(levelSet) do table.insert(activeLevels, l) end
	table.sort(activeLevels)
	
	local levelToRow = {}
	for row, l in ipairs(activeLevels) do
		levelToRow[l] = row
	end
	
	local lvlCols = {} -- lvlCols[lvl] = current_row
	
	-- 노드 위치 계산
	local maxX = 0
	local maxY = 0
	
	for _, node in ipairs(filteredReqs) do
		local lvl = tonumber(node.requireLevel) or 1
		local row = levelToRow[lvl] or 1
		
		local col = (lvlCols[lvl] or 0)
		-- 세로 배치: cx 시작점을 레벨 글씨 바로 옆으로 당김
		local cx = col * xSpacing + 75 
		local cy = (row - 1) * ySpacing + 45 -- 위쪽 여백 줄임
		
		nodePositions[node.id] = Vector2.new(cx, cy)
		lvlCols[lvl] = col + 1
		
		if cx > maxX then maxX = cx end
		if cy > maxY then maxY = cy end
	end
	
	-- 배경 그리선 배치 제거 (사용요청)
	-- for row, l in ipairs(activeLevels) do
	--     ...
	-- end
	
	canvas.CanvasSize = UDim2.new(0, maxX + 200, 0, maxY + 200)
	
	-- 노드 생성 및 선 그리기
	local lvl = type(playerLevel)=="number" and playerLevel or (tonumber(tostring(playerLevel)) or 1)
	
	for _, node in ipairs(filteredReqs) do
		local pos = nodePositions[node.id]
		local isUnlocked = unlocked[node.id] == true
		local preMet = true
		
		-- 선행 조건 체크 (UI 시각화 로직만 남김)
		if node.prerequisites then
			for _, pid in ipairs(node.prerequisites) do
				if not unlocked[pid] then preMet = false break end
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
			cell.BackgroundColor3 = Color3.fromRGB(25, 50, 28)
			cell.BackgroundTransparency = 0.25
		elseif not preMet or not lvlMet then
			cell.BackgroundColor3 = Color3.fromRGB(40, 20, 25)
			cell.BackgroundTransparency = 0.4
		else
			cell.BackgroundColor3 = C.BG_SLOT
			cell.BackgroundTransparency = 0.2
		end
		
		local cor = Instance.new("UICorner"); cor.CornerRadius = UDim.new(0, 10); cor.Parent = cell
		local stk = Instance.new("UIStroke")
		stk.Color = isUnlocked and C.GOLD or C.BORDER_DIM
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
		-- [FIX] 모든 아이콘이 원래 색상으로 보이도록, 회색조 필터 제거
		icon.ImageColor3 = Color3.fromRGB(255, 255, 255) 
		icon.ZIndex = 200
		icon.Parent = cell
		
		-- 해금 완료 마크
		if isUnlocked then
			local d = Instance.new("TextLabel")
			d.Size=UDim2.new(0,20,0,20); d.Position=UDim2.new(0,2,0,2)
			d.BackgroundColor3=Color3.fromRGB(20,38,22); d.Text="✓"; d.TextColor3=Color3.fromRGB(120,200,80)
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
		nameL.TextColor3 = isUnlocked and C.GOLD or (preMet and lvlMet and C.WHITE or Color3.fromRGB(110,105,95))
		nameL.ZIndex = 201; nameL.Parent = cell
		
		-- (SP 뱃지 제거)
		local tbc=Instance.new("UICorner"); tbc.CornerRadius=UDim.new(0,4)
		-- (사용처가 없지만 레이아웃 버그 생길 수 있어 빈 Frame 삽입)
		local tpBadge = Instance.new("Frame")
		tpBadge.BackgroundTransparency = 1
		tpBadge.Parent = cell

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
		bg = C.BG_OVERLAY, bgT = 0.5, vis = false, parent = parent,
	})

	local main = Utils.mkWindow({
		name = "Main",
		size = UDim2.new(isMobile and 1 or 0.8, 0, isMobile and 1 or 0.85, 0),
		maxSize = Vector2.new(1100, 850),
		pos = UDim2.new(0.5,0,0.5,0), anchor = Vector2.new(0.5,0.5),
		bg = C.BG_PANEL, bgT = T.PANEL, stroke = 1.5, strokeC = C.BORDER, r = 6,
		parent = TechUI.Refs.Frame,
	})

	-- 헤더 (Modern Thin Header)
	local header = Utils.mkFrame({
		name="Header", size=UDim2.new(1,0,0,50),
		bg=C.BG_OVERLAY, parent=main,
	})
	Utils.mkLabel({
		text="  ⚙ KNOWLEDGE TREE", pos=UDim2.new(0,0,0,0),
		size=UDim2.new(0.5,0,1,0), ts=18, font=F.TITLE, color=C.WHITE,
		ax=Enum.TextXAlignment.Left, parent=header,
	})
	TechUI.Refs.TPText = Utils.mkLabel({
		text="SP: 0", pos=UDim2.new(0.5,0,0,0),
		size=UDim2.new(0.4,0,1,0), ts=16, font=F.NUM, color=C.GOLD,
		ax=Enum.TextXAlignment.Right, parent=header,
	})
	-- Close Button (Fixed)
	Utils.mkBtn({
		text="X", size=UDim2.new(0,36,0,36),
		pos=UDim2.new(1,-10,0.5,0), anchor=Vector2.new(1,0.5),
		bg=C.BTN, bgT=0.5, ts=20, font=F.TITLE, color=C.WHITE, r=4,
		fn=function() UIManager.closeTechTree() end, parent=header,
	})

	local contentBox = Utils.mkFrame({
		name="ContentHBox", size=UDim2.new(1,0,1,-45),
		pos=UDim2.new(0,0,0,45), bgT=1, parent=main
	})
	
	-- 좌측 탭 영역
	local tabListPanel = Utils.mkFrame({
		name="TabList", size=UDim2.new(0, 180, 1, 0), bg=C.BG_SLOT, bgT=0.3, parent=contentBox
	})
	local tlLayout = Instance.new("UIListLayout"); tlLayout.Padding=UDim.new(0,1); tlLayout.Parent=tabListPanel
	
	for i, cat in ipairs(CATEGORY_TABS) do
		local isDefault = (i == activeTab)
		local tBtn = Utils.mkBtn({
			text = "   " .. cat.name, size = UDim2.new(1,0,0,50),
			bg = isDefault and C.GOLD_SEL or C.BTN_GRAY, 
			bgT = isDefault and 0.2 or 0.6, 
			color = isDefault and C.WHITE or C.GRAY,
			ts = 15, font = F.TITLE, r=0,
			noHover = true,
			parent = tabListPanel
		})
		tBtn.TextXAlignment = Enum.TextXAlignment.Left
		
		local ind = Instance.new("Frame")
		ind.Size = UDim2.new(0,4,1,0)
		ind.BackgroundColor3 = C.GOLD
		ind.BorderSizePixel = 0
		ind.Visible = isDefault
		ind.Parent = tBtn
		
		TechUI.Refs.Tabs[i] = { Btn = tBtn, Ind = ind }
		
		tBtn.MouseButton1Click:Connect(function()
			activeTab = i
			for j, tref in ipairs(TechUI.Refs.Tabs) do
				local isSelected = (j == activeTab)
				if isSelected then
					Utils.setBtnState(tref.Btn, C.GOLD_SEL, 0.2)
					tref.Btn.TextColor3 = C.WHITE
					tref.Ind.Visible = true
				else
					Utils.setBtnState(tref.Btn, C.BTN_GRAY, 0.6)
					tref.Btn.TextColor3 = C.GRAY
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
	TechUI.Refs.Tabs[1].Btn.BackgroundColor3 = C.BTN
	TechUI.Refs.Tabs[1].Btn.BackgroundTransparency = 0
	TechUI.Refs.Tabs[1].Btn.TextColor3 = C.BG_DARK
	TechUI.Refs.Tabs[1].Ind.Visible = true

	-- 중앙 캔버스 영역
	local canvasWrapper = Utils.mkFrame({
		name="CanvasWrap", size=UDim2.new(1, -180, 1, 0),
		pos=UDim2.new(0,180,0,0), bgT=1, parent=contentBox
	})
	
	TechUI.Refs.Canvas = Instance.new("ScrollingFrame")
	TechUI.Refs.Canvas.Name = "TreeCanvas"
	TechUI.Refs.Canvas.Size = UDim2.new(1, 0, 1, 0)
	TechUI.Refs.Canvas.BackgroundTransparency = 1
	TechUI.Refs.Canvas.BorderSizePixel = 0
	TechUI.Refs.Canvas.ScrollBarThickness = 6
	TechUI.Refs.Canvas.CanvasSize = UDim2.new(0, 0, 0, 0)
	TechUI.Refs.Canvas.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	TechUI.Refs.Canvas.Parent = canvasWrapper
	
	TechUI.Refs.BgGrid = Instance.new("Frame")
	TechUI.Refs.BgGrid.Name = "BgGrid"
	TechUI.Refs.BgGrid.Size = UDim2.new(1,0,1,0)
	TechUI.Refs.BgGrid.BackgroundTransparency = 1
	TechUI.Refs.BgGrid.ZIndex = 0
	TechUI.Refs.BgGrid.Parent = TechUI.Refs.Canvas
	
	-- 우측 상세 패널 (팝업 대신 사이드 바 고정)
	local detailSize = 320
	TechUI.Refs.DetailFrame = Utils.mkFrame({
		name="Detail", size=UDim2.new(0, detailSize, 1, -16),
		pos=UDim2.new(1, -detailSize - 8, 0, 8),
		bg=C.BG_PANEL, bgT=T.PANEL, r=6,
		parent=canvasWrapper
	})
	-- 선택 전엔 숨김
	TechUI.Refs.DetailFrame.Visible = false
	
	local dtHead = Utils.mkLabel({
		text="해당 노드 정보", size=UDim2.new(1,0,0,40),
		bg=C.BG_DARK, bgT=0.3, color=C.GOLD, ts=16, font=F.TITLE,
		parent=TechUI.Refs.DetailFrame
	})
	TechUI.Refs.D_Name = Utils.mkLabel({
		text="이름", size=UDim2.new(1,-20,0,40), pos=UDim2.new(0,12,0,50),
		color=C.WHITE, ts=20, font=F.TITLE, ax=Enum.TextXAlignment.Left, parent=TechUI.Refs.DetailFrame
	})
	TechUI.Refs.D_Icon = Instance.new("ImageLabel")
	TechUI.Refs.D_Icon.Size = UDim2.new(0, 80, 0, 80); TechUI.Refs.D_Icon.Position = UDim2.new(0,12,0,95)
	TechUI.Refs.D_Icon.BackgroundTransparency = 1; TechUI.Refs.D_Icon.Parent = TechUI.Refs.DetailFrame
	
	TechUI.Refs.D_Desc = Utils.mkLabel({
		text="설명", size=UDim2.new(1,-110,0,100), pos=UDim2.new(0,100,0,95),
		color=C.GRAY, ts=16, wrap=true,
		ax=Enum.TextXAlignment.Left, ay=Enum.TextYAlignment.Top, parent=TechUI.Refs.DetailFrame
	})
	
	-- 통합된 경고 메시지 박스
	TechUI.Refs.D_WarnBox = Instance.new("Frame")
	TechUI.Refs.D_WarnBox.Size=UDim2.new(1,-24,0,0); TechUI.Refs.D_WarnBox.Position=UDim2.new(0,12,0,210)
	TechUI.Refs.D_WarnBox.AutomaticSize=Enum.AutomaticSize.Y
	TechUI.Refs.D_WarnBox.BackgroundColor3=Color3.fromRGB(42,20,22); TechUI.Refs.D_WarnBox.BorderSizePixel=0
	local wc=Instance.new("UICorner"); wc.CornerRadius=UDim.new(0,4); wc.Parent=TechUI.Refs.D_WarnBox
	local wp=Instance.new("UIPadding"); wp.PaddingTop=UDim.new(0,12); wp.PaddingBottom=UDim.new(0,12)
	wp.PaddingLeft=UDim.new(0,15); wp.PaddingRight=UDim.new(0,15); wp.Parent=TechUI.Refs.D_WarnBox
	TechUI.Refs.D_WarnTxt = Utils.mkLabel({
		text="", size=UDim2.new(1,0,0,0), ts=16, color=Color3.fromRGB(220,120,100), font=F.TITLE,
		ax=Enum.TextXAlignment.Left, wrap=true, parent=TechUI.Refs.D_WarnBox
	})
	TechUI.Refs.D_WarnTxt.AutomaticSize = Enum.AutomaticSize.Y
	TechUI.Refs.D_WarnBox.Parent = TechUI.Refs.DetailFrame
	
	TechUI.Refs.D_ActionBtn = Utils.mkBtn({
		text="RESEARCH", size=UDim2.new(1, -20, 0, 45), pos=UDim2.new(0, 10, 1, -55),
		bg=C.GOLD, color=C.BG_DARK, ts=16, font=F.TITLE, r=5,
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
	
	if TechUI.Refs.TPText then TechUI.Refs.TPText.Text = UILocalizer.Localize("SP: ") .. tostring(tp) end
	
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
	TechUI.Refs.D_Name.Text = UILocalizer.Localize(node.name or node.id)
	TechUI.Refs.D_Icon.Image = resolveNodeIcon(node, getItemIcon)
	TechUI.Refs.D_Desc.Text = UILocalizer.Localize(node.description or "이 레시피와 시설을 활성화합니다.")
	
	-- 조건/경고 로직
	local lvl = type(playerLevel)=="number" and playerLevel or (tonumber(tostring(playerLevel)) or 1)
	local reqLvl = tonumber(node.requireLevel) or 1
	
	local box = TechUI.Refs.D_WarnBox
	local txt = TechUI.Refs.D_WarnTxt
	local btn = TechUI.Refs.D_ActionBtn

	txt.RichText = true
	
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
					table.insert(lines, "✗ " .. UILocalizer.Localize("선행 필요: ") .. UILocalizer.Localize(pname))
				end
			end
		end
		
		if lvl < reqLvl then table.insert(lines, "✗ " .. UILocalizer.Localize(string.format("레벨 부족: Lv.%d 필요", reqLvl))) 		end
		
		-- 비용 표시 문자열 생성
		local costStr = ""
		if node.cost and #node.cost > 0 then
			local invCounts = require(game.Players.LocalPlayer.PlayerScripts.Client.Controllers.InventoryController).getItemCounts()
			
			local cLines = {}
			for _, req in ipairs(node.cost) do
				local currentAmount = invCounts[req.itemId] or 0
				
				local name = req.itemId
				local itemData = DataHelper.GetData("ItemData", req.itemId)
				if itemData and itemData.name then
					name = itemData.name
				end
				name = UILocalizer.Localize(name)
				
				local color = currentAmount >= req.amount and "#aaffaa" or "#ffaaaa"
				table.insert(cLines, string.format(" • %s: <font color='%s'>%d</font> / %d", name, color, currentAmount, req.amount))
			end
			costStr = UILocalizer.Localize("필요 자원:") .. "\n" .. table.concat(cLines, "\n")
		end
		
		if #lines > 0 then
			txt.Text = table.concat(lines, "\n")
			if costStr ~= "" then txt.Text = txt.Text .. "\n\n" .. costStr end
			txt.TextColor3 = Color3.fromRGB(220, 100, 80)
			box.BackgroundColor3 = Color3.fromRGB(42, 18, 20)
			box.Visible = true
			
			btn.Visible = true
			btn.Text = UILocalizer.Localize("조건 미충족")
			btn.BackgroundColor3 = C.BG_SLOT
			btn.TextColor3 = Color3.fromRGB(110,105,95)
			btn.AutoButtonColor = false
		else
			if not canAfford then
				txt.Text = UILocalizer.Localize("💰 자원 부족") .. "\n" .. costStr
				txt.TextColor3 = Color3.fromRGB(200, 198, 190)
				box.BackgroundColor3 = Color3.fromRGB(38, 35, 18)
				box.Visible = true
				
				btn.Visible = true
				btn.Text = UILocalizer.Localize("자원 부족")
				btn.BackgroundColor3 = C.BG_SLOT
				btn.TextColor3 = Color3.fromRGB(110,105,95)
				btn.AutoButtonColor = false
			else
				if costStr ~= "" then
					txt.Text = UILocalizer.Localize("✅ 필요 자원") .. "\n" .. costStr
					txt.TextColor3 = Color3.fromRGB(200, 198, 190)
					box.BackgroundColor3 = Color3.fromRGB(20, 35, 22)
					box.Visible = true
				else
					box.Visible = false
				end
				
				btn.Visible = true
				btn.Text = UILocalizer.Localize("연구 시작")
				btn.BackgroundColor3 = C.GOLD
				btn.TextColor3 = C.BG_DARK
				btn.AutoButtonColor = true
			end
		end
	end
end

function TechUI.ShowUnlockSuccessPopup(node, getItemIcon, parent)
	local popup = Utils.mkFrame({
		useCanvas = true,
		name="UnlockPopup", size=UDim2.new(0,250,0,80),
		pos=UDim2.new(0.5,0,0.85,0), anchor=Vector2.new(0.5,0.5),
		bg=C.BG_PANEL, bgT=T.PANEL, stroke=false, r=6, z=1000, parent=parent,
	})
	Utils.mkLabel({text="연구 완료!", size=UDim2.new(1,0,0,30), pos=UDim2.new(0,0,0,10), ts=15, font=F.TITLE, color=Color3.fromRGB(120,200,80), parent=popup})
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
