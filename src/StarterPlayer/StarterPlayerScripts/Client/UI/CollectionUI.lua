-- CollectionUI.lua
-- 생존 도감 (일반 동물 표본실 디자인 레이아웃 컨벤션)
-- 탭 메뉴, 스크롤링 프레임, 상세정보, 업그레이드 표시

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local WindowManager = require(script.Parent.Parent.Utils.WindowManager)
local DataHelper = require(game:GetService("ReplicatedStorage").Shared.Util.DataHelper)
local CollectionController = require(script.Parent.Parent.Controllers.CollectionController)
local C = Theme.Colors
local F = Theme.Fonts

local CollectionUI = {}
CollectionUI.Refs = {}
local isUIInitialized = false
local UIManager = nil

local CATEGORY_TABS = {
	{ name = "전체", key = "ALL" },
	{ name = "초원", key = "GRASSLAND" },
	{ name = "열대", key = "TROPICAL" },
	{ name = "사막", key = "DESERT" },
	{ name = "툰드라", key = "TUNDRA" }
}

-- 공룡들을 임의로 기후에 매핑 (초원섬 위주이므로 대부분 초원에 배정)
local REGION_MAP = {
	COMPY = "GRASSLAND",
	DODO = "GRASSLAND",
	PARASAUR = "GRASSLAND",
	TRICERATOPS = "GRASSLAND",
	STEGOSAURUS = "GRASSLAND",
	ANKYLOSAURUS = "GRASSLAND",
	RAPTOR = "GRASSLAND",
	TREX = "GRASSLAND" -- 일단 임의로
}

local activeTabKey = "ALL"
local selectedCreatureId = nil

--========================================
-- Helpers
--========================================

local function getCreatureIcon(cid)
	-- 1. CreatureData에서 직접 아이콘 ID 확인 (우선 순위)
	local CreatureData = require(game:GetService("ReplicatedStorage").Data.CreatureData)
	for _, data in ipairs(CreatureData) do
		if data.id == cid and data.icon then
			return data.icon
		end
	end

	-- 2. Assets/ItemIcons 폴더에서 검색 (기존 방식)
	local Assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local Icons = Assets and Assets:FindFirstChild("ItemIcons")
	
	if Icons then
		for _, child in ipairs(Icons:GetChildren()) do
			local cname = child.Name:lower():gsub("_", "")
			if cname == cid:lower():gsub("_", "") then
				if child:IsA("Decal") or child:IsA("Texture") then return child.Texture end
				if child:IsA("ImageLabel") or child:IsA("ImageButton") then return child.Image end
				if child:IsA("StringValue") then return child.Value end
			end
		end
	end
	return "rbxassetid://0" -- 투명 아이콘
end

--========================================
-- Render Loop
--========================================

local function _renderTabs()
	for _, c in ipairs(CollectionUI.Refs.TabList:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	
	for i, tab in ipairs(CATEGORY_TABS) do
		local btn = Instance.new("TextButton")
		btn.Name = "Tab_" .. tab.key
		btn.Size = UDim2.new(1, 0, 0, 50)
		btn.Font = F.TITLE
		btn.TextSize = 18
		btn.Text = tab.name
		
		if activeTabKey == tab.key then
			btn.BackgroundColor3 = C.GOLD
			btn.TextColor3 = C.BG_OVERLAY
		else
			btn.BackgroundColor3 = C.BG_PANEL
			btn.TextColor3 = C.DIM
		end
		
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = btn
		
		btn.MouseButton1Click:Connect(function()
			activeTabKey = tab.key
			_renderTabs()
			CollectionUI.refreshData()
		end)
		
		btn.Parent = CollectionUI.Refs.TabList
	end
end

local function _renderDetails()
	local detailFrame = CollectionUI.Refs.DetailFrame
	if not detailFrame then return end
	
	for _, c in ipairs(detailFrame:GetChildren()) do
		if c:IsA("GuiObject") then c.Visible = false end
	end
	
	if not selectedCreatureId then
		local mt = detailFrame:FindFirstChild("EmptyText")
		if not mt then
			mt = Utils.CreateTextLabel("EmptyText", UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), "동물을 선택하세요.")
			mt.TextColor3 = C.DIM
			mt.Parent = detailFrame
		end
		mt.Visible = true
		return
	end
	
	-- 상세 내용물
	local pnl = detailFrame:FindFirstChild("ContentPnl")
	if not pnl then
		pnl = Instance.new("Frame")
		pnl.Name = "ContentPnl"
		pnl.Size = UDim2.new(1,0,1,0)
		pnl.BackgroundTransparency = 1
		pnl.Parent = detailFrame
		
		local iconBg = Utils.CreateFrame("IconBg", UDim2.new(0, 100, 0, 100), UDim2.new(0.5, 0, 0, 20), C.BG_SLOT)
		iconBg.AnchorPoint = Vector2.new(0.5, 0)
		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = iconBg
		
		local iconImg = Utils.CreateImage("IconImg", UDim2.new(0.8,0,0.8,0), UDim2.new(0.1,0,0.1,0), "")
		iconImg.Parent = iconBg
		
		local nameTxt = Utils.CreateTextLabel("NameTxt", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 130), "이름")
		nameTxt.Font = F.TITLE
		nameTxt.TextSize = 24
		
		local dnaTxt = Utils.CreateTextLabel("DnaTxt", UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 0, 160), "DNA: 0/5")
		dnaTxt.TextColor3 = C.GOLD
		
		local infoTxt = Utils.CreateTextLabel("InfoTxt", UDim2.new(0.9, 0, 0, 60), UDim2.new(0.05, 0, 0, 190), "동물 정보 및 연구 보너스\n[연구 완료 시 상시 효과가 적용됩니다]")
		infoTxt.TextColor3 = C.DIM
		infoTxt.TextXAlignment = Enum.TextXAlignment.Left
		infoTxt.TextYAlignment = Enum.TextYAlignment.Top
		
		iconBg.Parent = pnl
		nameTxt.Parent = pnl
		dnaTxt.Parent = pnl
		infoTxt.Parent = pnl
		
		-- 장착 효과
		local effBg = Utils.CreateFrame("EffBg", UDim2.new(0.9,0,0,80), UDim2.new(0.05,0,0,260), C.BTN)
		Instance.new("UICorner", effBg).CornerRadius = UDim.new(0,8)
		
		local effTit = Utils.CreateTextLabel("EffTit", UDim2.new(1,0,0,20), UDim2.new(0,0,0,5), "장착 시 플레이어 효과")
		effTit.TextSize = 14
		effTit.Font = F.TITLE
		effTit.Parent = effBg
		
		local effVal = Utils.CreateTextLabel("EffVal", UDim2.new(0.9,0,0,40), UDim2.new(0.05,0,0,30), "초원 이동 속도 +5.0%")
		effVal.TextXAlignment = Enum.TextXAlignment.Left
		effVal.Parent = effBg
		effBg.Parent = pnl
		
		-- 상시 효과
		local pasBg = Utils.CreateFrame("PasBg", UDim2.new(0.9,0,0,100), UDim2.new(0.05,0,0,350), C.BTN)
		Instance.new("UICorner", pasBg).CornerRadius = UDim.new(0,8)
		
		local pasTit = Utils.CreateTextLabel("PasTit", UDim2.new(1,0,0,20), UDim2.new(0,0,0,5), "업그레이드 상시 효과")
		pasTit.TextSize = 14
		pasTit.Font = F.TITLE
		pasTit.Parent = pasBg
		
		local pasVal = Utils.CreateTextLabel("PasVal", UDim2.new(0.9,0,0,60), UDim2.new(0.05,0,0,30), "초원 공격력 +3\n최대 생명력 +15")
		pasVal.TextXAlignment = Enum.TextXAlignment.Left
		pasVal.TextYAlignment = Enum.TextYAlignment.Top
		pasVal.Parent = pasBg
		pasBg.Parent = pnl
	end
	pnl.Visible = true
	
	local data = CollectionController.getCreatureData(selectedCreatureId)
	local dnaCount = CollectionController.getDnaCount(selectedCreatureId)
	
	local iconBg = pnl:FindFirstChild("IconBg")
	if iconBg and iconBg:FindFirstChild("IconImg") then
		iconBg.IconImg.Image = getCreatureIcon(selectedCreatureId)
	end
	local nameTxt = pnl:FindFirstChild("NameTxt")
	if nameTxt then nameTxt.Text = data and data.name or selectedCreatureId end
	
	local pasVal = pnl:FindFirstChild("PasBg") and pnl.PasBg:FindFirstChild("PasVal")
	if pasVal then
		if selectedCreatureId == "COMPY" then
			local bonus = math.min(10, math.floor(dnaCount / 20))
			pasVal.Text = string.format("공격력 보너스: +%d%%\n(20개당 1%% 증가, 최대 10%%)", bonus)
			pasVal.TextColor3 = (bonus > 0) and C.GOLD or C.DIM
		else
			pasVal.Text = "연구 보너스 정보가 없습니다.\n(추후 업데이트 예정)"
			pasVal.TextColor3 = C.DIM
		end
	end
	
	local effVal = pnl:FindFirstChild("EffBg") and pnl.EffBg:FindFirstChild("EffVal")
	if effVal then
		effVal.Text = "[장착 보너스 비활성]\n준비 중인 기능입니다."
		effVal.TextColor3 = C.DIM
	end
end

----------------------------------------------------------------
-- Refresh Items (Scroll List)
----------------------------------------------------------------
function CollectionUI.refreshData()
	if not isUIInitialized then return end
	
	local scroll = CollectionUI.Refs.Scroll
	
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	
	local creatures = CollectionController.getCreatureList()
	if not creatures then return end
	
	local x, y = 10, 10
	local CARD_W = 110
	local CARD_H = 130
	local SPACING = 10
	local cols = 4
	
	local count = 0
	
	for _, data in ipairs(creatures) do
		local cid = data.id
		local region = REGION_MAP[cid] or "GRASSLAND"
		
		if activeTabKey == "ALL" or activeTabKey == region then
			local dCount = CollectionController.getDnaCount(cid)
			
			local card = Utils.CreateFrame("Card_"..cid, UDim2.new(0, CARD_W, 0, CARD_H), UDim2.new(0, x, 0, y), C.BTN)
			local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = card
			
			-- 선택 하이라이트
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2
			stroke.Color = (cid == selectedCreatureId) and C.GOLD_SEL or Color3.fromRGB(60,60,60)
			stroke.Parent = card
			
			-- 아이콘
			local icon = Utils.CreateImage("Icon", UDim2.new(0, 60, 0, 60), UDim2.new(0.5, -30, 0, 15), getCreatureIcon(cid))
			icon.Parent = card
			
			-- 이름
			local nameL = Utils.CreateTextLabel("Name", UDim2.new(1,0,0,20), UDim2.new(0,0,0,80), data.name or cid)
			nameL.TextSize = 13
			nameL.Parent = card
			
			-- DNA 바
			local barBg = Utils.CreateFrame("BarBg", UDim2.new(0.8, 0, 0, 10), UDim2.new(0.1, 0, 0, 105), Color3.fromRGB(0,0,0))
			Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 5)
			
			local fillRatio = math.clamp(dCount / 5, 0, 1)
			local barFill = Utils.CreateFrame("BarFill", UDim2.new(fillRatio, 0, 1, 0), UDim2.new(0,0,0,0), C.GOLD)
			Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 5)
			barFill.Parent = barBg
			
			local countT = Utils.CreateTextLabel("Cnt", UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), dCount.."/5")
			countT.TextSize = 10
			countT.Parent = barBg
			
			barBg.Parent = card
			
			-- Click Event
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1,0,1,0)
			btn.BackgroundTransparency = 1
			btn.Text = ""
			btn.Parent = card
			
			btn.MouseButton1Click:Connect(function()
				selectedCreatureId = cid
				CollectionUI.refreshData() -- 재렌더링
			end)
			
			card.Parent = scroll
			
			-- Layout calculation
			count = count + 1
			if count % cols == 0 then
				x = 10
				y = y + CARD_H + SPACING
			else
				x = x + CARD_W + SPACING
			end
		end
	end
	
	scroll.CanvasSize = UDim2.new(0, 0, 0, y + CARD_H + SPACING)
	
	_renderDetails()
end

--========================================
-- Init
--========================================

function CollectionUI.Init(mainGui, uiManager)
	if isUIInitialized then return end
	UIManager = uiManager
	
	local Frame = Utils.CreateFrame("CollectionFrame", UDim2.new(0, 900, 0, 550), UDim2.new(0.5, -450, 0.5, -275), C.BG_PANEL)
	Frame.Visible = false
	Utils.AddCorner(Frame, 12)
	CollectionUI.Refs.Frame = Frame
	
	-- Title
	local Title = Utils.CreateTextLabel("Title", UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 0, 0), "생존 도감 (Collection)")
	Title.Font = F.TITLE
	Title.TextSize = 22
	Title.TextColor3 = C.GOLD
	Title.BackgroundColor3 = C.BG_PANEL_L
	Title.BackgroundTransparency = 0
	Utils.AddCorner(Title, 12)
	Title.Parent = Frame
	
	-- Bottom Flat
	local btnFlat = Instance.new("Frame")
	btnFlat.Size = UDim2.new(1, 0, 0.5, 0)
	btnFlat.Position = UDim2.new(0, 0, 0.5, 0)
	btnFlat.BackgroundColor3 = C.BG_PANEL_L
	btnFlat.BorderSizePixel = 0
	btnFlat.Parent = Title
	Title.Parent = Frame
	
	-- Close Button
	local CloseBtn = Utils.CreateCloseButton(UIManager, "COLLECTION")
	CloseBtn.Position = UDim2.new(1, -30, 0, 10)
	CloseBtn.Parent = Frame
	
	-- 좌측 탭 영역
	local TabList = Instance.new("ScrollingFrame")
	TabList.Name = "TabList"
	TabList.Size = UDim2.new(0, 120, 1, -60)
	TabList.Position = UDim2.new(0, 10, 0, 50)
	TabList.BackgroundTransparency = 1
	TabList.CanvasSize = UDim2.new(0, 0, 0, 500)
	TabList.ScrollBarThickness = 4
	local tlLayout = Instance.new("UIListLayout"); tlLayout.Padding = UDim.new(0, 10); tlLayout.Parent = TabList
	CollectionUI.Refs.TabList = TabList
	TabList.Parent = Frame
	
	-- 중앙 스크롤 (공룡카드)
	local Scroll = Instance.new("ScrollingFrame")
	Scroll.Name = "CreatureList"
	Scroll.Size = UDim2.new(0, 490, 1, -60)
	Scroll.Position = UDim2.new(0, 140, 0, 50)
	Scroll.BackgroundColor3 = C.BG_OVERLAY
	Scroll.BackgroundTransparency = 0.5
	Scroll.ScrollBarThickness = 6
	Utils.AddCorner(Scroll, 8)
	CollectionUI.Refs.Scroll = Scroll
	Scroll.Parent = Frame
	
	-- 우측 상세 정보창
	local DetailFrame = Instance.new("Frame")
	DetailFrame.Name = "DetailFrame"
	DetailFrame.Size = UDim2.new(0, 240, 1, -60)
	DetailFrame.Position = UDim2.new(0, 640, 0, 50)
	DetailFrame.BackgroundColor3 = C.BG_PANEL_L
	DetailFrame.BackgroundTransparency = 0.3
	Utils.AddCorner(DetailFrame, 8)
	CollectionUI.Refs.DetailFrame = DetailFrame
	DetailFrame.Parent = Frame
	
	Frame.Parent = mainGui
	
	isUIInitialized = true
	print("[CollectionUI] Initialized")
end

--========================================
-- API
--========================================

function CollectionUI.Show()
	if not CollectionUI.Refs.Frame then return end
	CollectionUI.Refs.Frame.Visible = true
	
	_renderTabs()
	CollectionUI.refreshData()
	
	-- Data Event Hook (DNA 획득 시 UI에 열려있으면 즉시 반영)
	CollectionController.onDnaUpdated(function()
		if WindowManager.isOpen("COLLECTION") then
			CollectionUI.refreshData()
		end
	end)
end

function CollectionUI.Hide()
	if not CollectionUI.Refs.Frame then return end
	CollectionUI.Refs.Frame.Visible = false
	selectedCreatureId = nil
end

return CollectionUI
