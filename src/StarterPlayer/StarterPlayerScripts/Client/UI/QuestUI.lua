-- QuestUI.lua
-- 프리미엄 퀘스트 선택 UI (이미지 레퍼런스 기반)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NetClient = require(script.Parent.Parent.NetClient)
local UITheme = require(script.Parent.UITheme)
local UIUtils = require(script.Parent.UIUtils)
local DataHelper = require(Shared.Util.DataHelper)
local UserInputService = game:GetService("UserInputService")
local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local WindowManager = require(script.Parent.Parent.Utils.WindowManager)

local QuestUI = {}
QuestUI.Refs = {
	Frame = nil,
}

--========================================
-- State
--========================================
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainOverlay = nil
local isOpen = false
local selectedQuestId = nil
local questPool = {}
local UIManager = nil

--========================================
-- Layout Constants
--========================================
local PANEL_SIZE = UDim2.new(0.85, 0, 0.85, 0)
local CARD_SIZE = UDim2.new(0.46, 0, 0.46, 0)

-- 아이콘 폴더 캐시 (최초 1회 로드)
local cachedFolders = {}
local function preloadFolders()
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	if not assets then return end
	
	local folderNames = {"ItemIcons", "CreatureIcons", "FacilityIcons", "Images", "Icons"}
	for _, name in ipairs(folderNames) do
		local f = assets:WaitForChild(name, 2)
		if f then
			cachedFolders[name] = f
		end
	end
end

-- 스크립트 로드 시 미리 폴더 확보 (비동기)
task.spawn(preloadFolders)

local function getIcon(id, questData)
	if not id or id == "" then return "" end
	
	-- 캐시된 폴더 사용
	local itemIcons = cachedFolders["ItemIcons"]
	local creatureIcons = cachedFolders["CreatureIcons"]
	local facilityIcons = cachedFolders["FacilityIcons"]
	
	local targetFolders = {}
	local questType = questData and (questData.kind or questData.type) or ""
	
	-- 1. 우선순위 폴더 배치
	if questType == "KILL" and creatureIcons then
		table.insert(targetFolders, creatureIcons)
	elseif questType == "BUILD" and facilityIcons then
		table.insert(targetFolders, facilityIcons)
	elseif itemIcons then
		table.insert(targetFolders, itemIcons)
	end
	
	-- 2. 보조 폴더들 추가
	for _, f in pairs(cachedFolders) do
		if not table.find(targetFolders, f) then
			table.insert(targetFolders, f)
		end
	end
	
	-- 3. 검색 대상 후보군
	local candidates = { id }
	local itemData = DataHelper.GetData("ItemData", id)
	if itemData then
		if itemData.iconName then table.insert(candidates, itemData.iconName) end
		if itemData.modelName then table.insert(candidates, itemData.modelName) end
	end

	local lowerTarget = id:lower():gsub("_", "")
	local searchPrefixes = { "", "item", "icon", "creature", "creaturefull", "facility", "craft" }
	
	-- 4. 검색 실행
	for _, folder in ipairs(targetFolders) do
		if not folder then continue end
		
		-- 직접 매칭 시도
		for _, cand in ipairs(candidates) do
			local directMatch = folder:FindFirstChild(cand)
			if directMatch then
				if directMatch:IsA("ImageLabel") or directMatch:IsA("ImageButton") then return directMatch.Image end
				if directMatch:IsA("Decal") or directMatch:IsA("Texture") then return directMatch.Texture end
				if directMatch:IsA("StringValue") then return directMatch.Value end
			end
		end
		
		-- 전수 조사 (대소문자 무시)
		for _, child in ipairs(folder:GetChildren()) do
			local cname = child.Name:lower():gsub("_", "")
			for _, pref in ipairs(searchPrefixes) do
				if cname == lowerTarget or cname == (pref .. lowerTarget) or lowerTarget == (pref .. cname) then
					if child:IsA("ImageLabel") or child:IsA("ImageButton") then return child.Image end
					if child:IsA("Decal") or child:IsA("Texture") then return child.Texture end
					if child:IsA("StringValue") then return child.Value end
				end
			end
		end
	end
	
	return "rbxassetid://13515086700" 
end

--========================================
-- Core UI Logic
--========================================

function QuestUI:Init(uiManager)
	UIManager = uiManager
end

local function createQuestCard(parent, questData, index)
	local isLocked = questData.kind == "NONE" -- 임시 슬롯 처리
	
	local card = Instance.new("TextButton")
	card.Name = "QuestCard_" .. (questData.id or index)
	card.Size = CARD_SIZE
	card.BackgroundColor3 = UITheme.Colors.BG_PANEL_L
	card.BackgroundTransparency = 0.2
	card.BorderSizePixel = 0
	card.Text = ""
	card.AutoButtonColor = false
	card.Parent = parent
	
	local corner = Instance.new("UICorner", card)
	corner.CornerRadius = UDim.new(0.05, 0)
	
	local stroke = Instance.new("UIStroke", card)
	stroke.Thickness = 1.2
	stroke.Color = UITheme.Colors.BORDER_DIM
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	
	if isLocked then
		local lockLabel = Instance.new("TextLabel")
		lockLabel.Size = UDim2.fromScale(0.8, 0.4)
		lockLabel.Position = UDim2.fromScale(0.5, 0.5)
		lockLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		lockLabel.BackgroundTransparency = 1
		lockLabel.Text = questData.desc or "수준이 도달하면 개방됩니다."
		lockLabel.TextColor3 = UITheme.Colors.DIM
		lockLabel.Font = UITheme.Fonts.NORMAL
		lockLabel.TextSize = 14
		lockLabel.TextWrapped = true
		lockLabel.Parent = card
		card.Active = false
		return card
	end

	-- 제목 (좌측 상단)
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(0.85, 0, 0.2, 0)
	title.Position = UDim2.new(0.05, 0, 0.08, 0)
	title.BackgroundTransparency = 1
	title.Text = questData.title or "퀘스트 제목"
	title.TextColor3 = UITheme.Colors.WHITE
	title.Font = UITheme.Fonts.TITLE
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = card

	-- 설명
	local desc = Instance.new("TextLabel")
	desc.Size = UDim2.new(0.85, 0, 0.4, 0)
	desc.Position = UDim2.new(0.05, 0, 0.3, 0)
	desc.BackgroundTransparency = 1
	desc.Text = questData.desc or ""
	desc.TextColor3 = UITheme.Colors.INK
	desc.Font = UITheme.Fonts.NORMAL
	desc.TextSize = 14
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.Parent = card

	-- 아이콘 표시 (추가)
	local targetId = questData.target or (questData.targets and questData.targets[1])
	if targetId then
		local iconImg = Instance.new("ImageLabel")
		iconImg.Name = "TargetIcon"
		iconImg.Size = UDim2.fromScale(0.35, 0.35)
		iconImg.Position = UDim2.new(0.95, 0, 0.5, 0)
		iconImg.AnchorPoint = Vector2.new(1, 0.5)
		iconImg.BackgroundTransparency = 1
		iconImg.Image = getIcon(targetId, questData)
		iconImg.Parent = card
		
		local iRatio = Instance.new("UIAspectRatioConstraint", iconImg)
		iRatio.AspectRatio = 1

		-- 텍스트 영역 조정 (아이콘 공간 확보)
		title.Size = UDim2.new(0.65, 0, 0.2, 0)
		desc.Size = UDim2.new(0.65, 0, 0.4, 0)
	end

	-- 보상 정보 (하단)
	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Size = UDim2.new(0.9, 0, 0.15, 0)
	rewardLabel.Position = UDim2.new(0.05, 0, 0.92, 0)
	rewardLabel.AnchorPoint = Vector2.new(0, 1)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Text = string.format("보상: %d 골드", questData.rewardGold or 0)
	rewardLabel.TextColor3 = UITheme.Colors.GOLD
	rewardLabel.Font = UITheme.Fonts.NORMAL
	rewardLabel.TextSize = 14
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Left
	rewardLabel.Parent = card

	-- 선택 핸들러
	card.MouseButton1Click:Connect(function()
		selectedQuestId = questData.id
		-- 모든 카드 스트로크 초기화 후 현재 것만 강조
		for _, c in ipairs(parent:GetChildren()) do
			if c:IsA("TextButton") then
				c:FindFirstChildOfClass("UIStroke").Color = UITheme.Colors.BORDER_DIM
				c:FindFirstChildOfClass("UIStroke").Thickness = 1.2
			end
		end
		stroke.Color = UITheme.Colors.GOLD_SEL
		stroke.Thickness = 2.5
	end)

	return card
end

local TIER_LIST = { "TUTORIAL", "TIER_10", "TIER_20", "TIER_30", "TIER_40" }
local TIER_NAMES = {
	TUTORIAL = "튜토리얼",
	TIER_10 = "Lv.10",
	TIER_20 = "Lv.20",
	TIER_30 = "Lv.30",
	TIER_40 = "Lv.40"
}

function QuestUI:Open(npcModel)
	if isOpen then return end
	
	local currentTier = nil
	local isAdmin = false
	local isTodayDone = false

	local function refresh(targetTier)
		local ok, result = NetClient.Request("Quest.GetList.Request", { tier = targetTier })
		if not ok or not result.success then
			if UIManager then UIManager.notify("임무 목록을 가져오지 못했습니다.") end
			return
		end
		
		questPool = result.quests
		selectedQuestId = nil
		isAdmin = result.isAdmin
		currentTier = result.currentTier
		isTodayDone = result.isTodayDone
		
		if mainOverlay then
			QuestUI:UpdateDisplay(currentTier, isAdmin, isTodayDone)
		end
	end

	-- 초기 요청
	local ok, result = NetClient.Request("Quest.GetList.Request", {})
	if not ok or not result.success then
		if UIManager then UIManager.notify("임무 목록을 가져오지 못했습니다.") end
		return
	end
	
	questPool = result.quests
	selectedQuestId = nil
	isAdmin = result.isAdmin
	currentTier = result.currentTier
	isTodayDone = result.isTodayDone
	isOpen = true

	-- Overlay 생성
	mainOverlay = Instance.new("Frame")
	mainOverlay.Name = "QuestOverlay"
	mainOverlay.Size = UDim2.fromScale(1, 1)
	mainOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	mainOverlay.BackgroundTransparency = 1
	mainOverlay.Active = true
	mainOverlay.Parent = playerGui:WaitForChild("GameUI")
	QuestUI.Refs.Frame = mainOverlay
	
	TweenService:Create(mainOverlay, TweenInfo.new(0.3), {BackgroundTransparency = 0.4}):Play()

	local panel = Instance.new("Frame")
	panel.Name = "QuestPanel"
	panel.Size = PANEL_SIZE
	panel.Position = UDim2.fromScale(0.5, 0.45)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = UITheme.Colors.BG_PANEL
	panel.BorderSizePixel = 0
	panel.Parent = mainOverlay
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
	local pStroke = Instance.new("UIStroke", panel)
	pStroke.Color = UITheme.Colors.BORDER
	pStroke.Thickness = 1.5

	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1.6
	ratio.Parent = panel

	-- 상단 헤더
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, -40, 0, 60)
	header.Position = UDim2.new(0, 20, 0, 10)
	header.BackgroundTransparency = 1
	header.Text = "임무"
	header.TextColor3 = UITheme.Colors.WHITE
	header.Font = UITheme.Fonts.TITLE
	header.TextSize = 24
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = panel

	local closeX = Instance.new("TextButton")
	closeX.Size = UDim2.new(0, 40, 0, 40)
	closeX.Position = UDim2.new(1, -10, 0, 10)
	closeX.AnchorPoint = Vector2.new(1, 0)
	closeX.BackgroundTransparency = 1
	closeX.Text = "X"
	closeX.TextColor3 = UITheme.Colors.GRAY
	closeX.Font = UITheme.Fonts.TITLE
	closeX.TextSize = 24
	closeX.Parent = panel
	closeX.MouseButton1Click:Connect(function() 
		WindowManager.close("QUEST") 
	end)

	-- [Admin] 탭 바
	local tabBar = Instance.new("Frame")
	tabBar.Name = "AdminTabs"
	tabBar.Size = UDim2.new(1, -40, 0, 40)
	tabBar.Position = UDim2.new(0, 20, 0, 70)
	tabBar.BackgroundTransparency = 1
	tabBar.Visible = isAdmin
	tabBar.Parent = panel
	
	local tabLayout = Instance.new("UIListLayout", tabBar)
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 10)

	for _, tId in ipairs(TIER_LIST) do
		local tab = Instance.new("TextButton")
		tab.Name = tId
		tab.Size = UDim2.new(0, 100, 1, 0)
		tab.BackgroundColor3 = UITheme.Colors.BTN_GRAY
		tab.Text = TIER_NAMES[tId]
		tab.TextColor3 = UITheme.Colors.WHITE
		tab.Font = UITheme.Fonts.NORMAL
		tab.TextSize = 14
		tab.Parent = tabBar
		Instance.new("UICorner", tab).CornerRadius = UDim.new(0, 6)
		
		tab.MouseButton1Click:Connect(function()
			refresh(tId)
		end)
	end

	-- 퀘스트 그리드 컨테이너
	local gridContainer = Instance.new("ScrollingFrame")
	gridContainer.Name = "GridContainer"
	gridContainer.Size = UDim2.new(1, -40, 1, isAdmin and -170 or -130)
	gridContainer.Position = UDim2.new(0, 20, 0, isAdmin and 115 or 75)
	gridContainer.BackgroundTransparency = 1
	gridContainer.ScrollBarThickness = 4
	gridContainer.CanvasSize = UDim2.new(0, 0, 0, 0) -- 자동 조절
	gridContainer.Parent = panel
	
	local uigrid = Instance.new("UIGridLayout", gridContainer)
	uigrid.CellSize = CARD_SIZE
	uigrid.CellPadding = UDim2.new(0, 15, 0, 15)
	uigrid.HorizontalAlignment = Enum.HorizontalAlignment.Center

	function QuestUI:UpdateDisplay(tier, adminMode, done)
		gridContainer:ClearAllChildren()
		
		local uigrid = Instance.new("UIGridLayout")
		uigrid.CellSize = CARD_SIZE
		uigrid.CellPadding = UDim2.new(0, 15, 0, 15)
		uigrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
		uigrid.Parent = gridContainer

		for i = 1, 4 do
			local qData = questPool[i] or { kind = "NONE", desc = "아직 준비된 임무가 없습니다." }
			createQuestCard(gridContainer, qData, i)
		end
		
		-- CanvasSize 업데이트
		task.defer(function()
			if gridContainer then
				gridContainer.CanvasSize = UDim2.new(0, 0, 0, gridContainer:FindFirstChildOfClass("UIListLayout") and gridContainer:FindFirstChildOfClass("UIListLayout").AbsoluteContentSize.Y or (gridContainer:FindFirstChildOfClass("UIGridLayout") and gridContainer:FindFirstChildOfClass("UIGridLayout").AbsoluteContentSize.Y or 500))
			end
		end)
		
		-- 탭 버튼 강조
		if adminMode then
			for _, child in ipairs(tabBar:GetChildren()) do
				if child:IsA("TextButton") then
					child.BackgroundColor3 = (child.Name == tier) and UITheme.Colors.BTN or UITheme.Colors.BTN_GRAY
					child.TextColor3 = (child.Name == tier) and Color3.new(0,0,0) or UITheme.Colors.WHITE
				end
			end
		end
		
		-- 푸터 상태 갱신은 이번엔 생략 (필요시 추가)
	end

	-- 초기 디스플레이
	QuestUI:UpdateDisplay(currentTier, isAdmin, isTodayDone)

	-- 하단 바 및 시작 버튼
	local footer = Instance.new("Frame")
	footer.Size = UDim2.new(1, 0, 0, 60)
	footer.Position = UDim2.new(0, 0, 1, 0)
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	footer.BackgroundTransparency = 0.5
	footer.Parent = panel
	Instance.new("UICorner", footer).CornerRadius = UDim.new(0, 12)

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(0.6, 0, 1, 0)
	hint.Position = UDim2.new(0, 20, 0, 0)
	hint.BackgroundTransparency = 1
	hint.Text = isTodayDone and "오늘의 임무를 이미 완료했습니다." or "오늘의 첫 임무 보상을 받을 수 있습니다."
	hint.TextColor3 = isTodayDone and UITheme.Colors.RED or UITheme.Colors.ORANGE
	hint.Font = UITheme.Fonts.NORMAL
	hint.TextSize = 14
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Parent = footer

	local startBtn = Instance.new("TextButton")
	startBtn.Size = UDim2.new(0, 160, 0, 44)
	startBtn.Position = UDim2.new(1, -10, 0.5, 0)
	startBtn.AnchorPoint = Vector2.new(1, 0.5)
	startBtn.BackgroundColor3 = isTodayDone and UITheme.Colors.BTN_DIS or UITheme.Colors.BTN
	startBtn.Text = "임무 시작"
	startBtn.TextColor3 = Color3.fromRGB(20, 20, 20)
	startBtn.Font = UITheme.Fonts.TITLE
	startBtn.TextSize = 18
	startBtn.Parent = footer
	Instance.new("UICorner", startBtn).CornerRadius = UDim.new(0, 6)

	startBtn.MouseButton1Click:Connect(function()
		if not selectedQuestId then
			if UIManager then UIManager.notify("수행할 임무를 먼저 선택하세요.") end
			return
		end
		
		local okAcc, resAcc = NetClient.Request("Quest.Accept.Request", { questId = selectedQuestId })
		if okAcc and resAcc.success then
			if UIManager then UIManager.notify("임무를 시작합니다!", UITheme.Colors.GREEN) end
			QuestUI:Close()
		else
			if UIManager then UIManager.notify(resAcc.message or "임무 수락에 실패했습니다.") end
		end
	end)
end

function QuestUI:Close()
	if not isOpen then return end
	isOpen = false
	if mainOverlay then
		mainOverlay:Destroy()
		mainOverlay = nil
		QuestUI.Refs.Frame = nil
	end
end

function QuestUI:IsOpen()
	return isOpen
end

function QuestUI:Toggle()
	if isOpen then
		self:Close()
	else
		self:Open()
	end
end

return QuestUI
