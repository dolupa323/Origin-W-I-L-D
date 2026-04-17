-- CollectionUI.lua
-- 생존 도감 (일반 동물 표본실 디자인 레이아웃 컨벤션)
-- 탭 메뉴, 스크롤링 프레임, 상세정보, 업그레이드 표시

local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent.UITheme)
local Utils = require(script.Parent.UIUtils)
local UILocalizer = require(script.Parent.Parent.Localization.UILocalizer)
local WindowManager = require(script.Parent.Parent.Utils.WindowManager)
local DataHelper = require(game:GetService("ReplicatedStorage").Shared.Util.DataHelper)
local CollectionController = require(script.Parent.Parent.Controllers.CollectionController)
local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local CollectionUI = {}
CollectionUI.Refs = {}
local isUIInitialized = false
local UIManager = nil

-- 상단 가로 탭 (인벤토리/간이제작 스타일)
local TOP_MODE = "CODEX"  -- "CODEX" or "PET"

-- 좌측 세로 탭: 지역 구분 (도감 모드 전용)
local REGION_TABS = {
	{ label = "전체", key = "ALL" },
	{ label = "초원", key = "GRASSLAND" },
	{ label = "열대", key = "TROPICAL" },
	{ label = "사막", key = "DESERT" },
	{ label = "설원", key = "SNOWY" },
}

-- 현재 운영 기준: 초원섬 도감은 3종 중심으로 노출
local REGION_MAP = {
	COMPY = "GRASSLAND",
	DODO = "GRASSLAND",
	BABY_TRICERATOPS = "GRASSLAND",
	PARASAUR = "TROPICAL",
	TRICERATOPS = "TROPICAL",
	STEGOSAURUS = "TROPICAL",
	ANKYLOSAURUS = "DESERT",
	RAPTOR = "DESERT",
	TREX = "SNOWY"
}

local activeTabKey = "ALL"
local selectedCreatureId = nil
local selectedPetSlot = nil
local selectedPetCreatureId = nil

--========================================
-- Helpers
--========================================

local PASSIVE_STAT_NAMES = {
	attackMult = "공격력",
	maxHealth = "최대 체력",
	maxStamina = "최대 스태미나",
	defense = "방어력",
	workSpeed = "작업 속도",
}

local function getPassiveEffectText(creatureId)
	local cData = DataHelper.GetData("CreatureData", creatureId)
	if not cData or not cData.passiveEffect then return nil end
	local eff = cData.passiveEffect
	local statName = PASSIVE_STAT_NAMES[eff.stat] or eff.stat
	local sign = (eff.value >= 0) and "+" or ""
	return string.format("%s %s%s", statName, sign, tostring(eff.value))
end

local function getCreatureIcon(cid)
	-- 1. CreatureData 아이콘 ID 확인 (DataHelper 경유)
	local creature = DataHelper.GetData("CreatureData", cid)
	if creature and creature.icon then
		return creature.icon
	end

	local function normalize(name: string): string
		return string.lower(tostring(name or "")):gsub("[^%w]", "")
	end

	local function extractImageAsset(inst)
		if inst:IsA("Decal") or inst:IsA("Texture") then return inst.Texture end
		if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then return inst.Image end
		if inst:IsA("StringValue") then return inst.Value end
		return ""
	end

	-- 2. Assets 폴더 내 다중 후보 경로를 순회해 가장 먼저 매칭되는 아이콘 사용
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local searchFolders = {
			assets:FindFirstChild("CreatureIcons"),
			assets:FindFirstChild("ItemIcons"),
			assets:FindFirstChild("Icons"),
		}

		local aliases = {
			cid,
			creature and creature.modelName,
			creature and creature.name,
		}

		for _, folder in ipairs(searchFolders) do
			if folder then
				for _, child in ipairs(folder:GetChildren()) do
					local cname = normalize(child.Name)
					for _, alias in ipairs(aliases) do
						if alias and cname == normalize(alias) then
							local imageId = extractImageAsset(child)
							if imageId and imageId ~= "" then
								return imageId
							end
						end
					end
				end
			end
		end
	end
	return "rbxassetid://0" -- 투명 아이콘
end

--========================================
-- Render Loop
--========================================

local function _updateTopTabs()
	local tabCodex = CollectionUI.Refs.TabCodex
	local tabPet = CollectionUI.Refs.TabPet
	if tabCodex then
		tabCodex.TextColor3 = (TOP_MODE == "CODEX") and C.GOLD_SEL or C.GRAY
	end
	if tabPet then
		tabPet.TextColor3 = (TOP_MODE == "PET") and C.GOLD_SEL or C.GRAY
	end

	-- 도감 모드: 좌측 지역 탭 + 중앙 스크롤 표시
	-- 펫 모드: 좌측 탭 숨기고 스크롤 영역 확장
	local tabList = CollectionUI.Refs.TabList
	local scroll = CollectionUI.Refs.Scroll
	if tabList then
		tabList.Visible = (TOP_MODE == "CODEX")
	end
	if scroll then
		if TOP_MODE == "CODEX" then
			scroll.Size = UDim2.new(0.56, -10, 1, -70)
			scroll.Position = UDim2.new(0.14, 10, 0, 60)
		else
			scroll.Size = UDim2.new(0.70, -10, 1, -70)
			scroll.Position = UDim2.new(0, 10, 0, 60)
		end
	end
end

local function _renderRegionTabs()
	for _, c in ipairs(CollectionUI.Refs.TabList:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	
	for i, tab in ipairs(REGION_TABS) do
		local isSelected = (activeTabKey == tab.key)
		local btn = Utils.mkBtn({
			name = "Tab_" .. tab.key,
			text = UILocalizer.Localize(tab.label),
			size = UDim2.new(1, 0, 0, 50),
			bg = isSelected and C.GOLD_SEL or C.BTN_GRAY,
			bgT = isSelected and 0.2 or 0.6,
			color = isSelected and C.WHITE or C.GRAY,
			ts = 22,
			font = F.TITLE,
			noHover = true,
			parent = CollectionUI.Refs.TabList
		})
		
		btn.MouseButton1Click:Connect(function()
			activeTabKey = tab.key
			_renderRegionTabs()
			CollectionUI.refreshData()
		end)
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
			mt = Utils.CreateTextLabel("EmptyText", UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), UILocalizer.Localize("동물을 선택하세요."))
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
		
		local nameTxt = Utils.CreateTextLabel("NameTxt", UDim2.new(1, 0, 0, 36), UDim2.new(0, 0, 0, 130), UILocalizer.Localize("이름"))
		nameTxt.Font = F.TITLE
		nameTxt.TextSize = 28
		
		local dnaTxt = Utils.CreateTextLabel("DnaTxt", UDim2.new(1, 0, 0, 26), UDim2.new(0, 0, 0, 168), UILocalizer.Localize("DNA: 0/5"))
		dnaTxt.TextColor3 = C.GOLD
		dnaTxt.TextSize = 18
		
		local infoTxt = Utils.CreateTextLabel("InfoTxt", UDim2.new(0.9, 0, 0, 70), UDim2.new(0.05, 0, 0, 198), UILocalizer.Localize("동물 정보"))
		infoTxt.TextColor3 = C.DIM
		infoTxt.TextSize = 17
		infoTxt.TextXAlignment = Enum.TextXAlignment.Left
		infoTxt.TextYAlignment = Enum.TextYAlignment.Top
		
		iconBg.Parent = pnl
		nameTxt.Parent = pnl
		dnaTxt.Parent = pnl
		infoTxt.Parent = pnl
		
		-- 장착 효과
		local effBg = Utils.CreateFrame("EffBg", UDim2.new(0.9,0,0,90), UDim2.new(0.05,0,0,275), C.BTN)
		Instance.new("UICorner", effBg).CornerRadius = UDim.new(0,8)
		
		local effTit = Utils.CreateTextLabel("EffTit", UDim2.new(1,0,0,20), UDim2.new(0,0,0,5), UILocalizer.Localize("장착 시 플레이어 효과"))
		effTit.TextSize = 18
		effTit.Font = F.TITLE
		effTit.Parent = effBg
		
		local effVal = Utils.CreateTextLabel("EffVal", UDim2.new(0.9,0,0,50), UDim2.new(0.05,0,0,32), UILocalizer.Localize("[장착 보너스 비활성]\n준비 중인 기능입니다."))
		effVal.TextSize = 16
		effVal.TextXAlignment = Enum.TextXAlignment.Left
		effVal.Parent = effBg
		effBg.Parent = pnl
		
	end
	pnl.Visible = true
	
	local data = CollectionController.getCreatureData(selectedCreatureId)
	local dnaCount = CollectionController.getDnaCount(selectedCreatureId)
	local dnaRequired = (data and data.dnaRequired) or 5
	local isComplete = CollectionController.isCodexComplete(selectedCreatureId)
	
	local iconBg = pnl:FindFirstChild("IconBg")
	if iconBg and iconBg:FindFirstChild("IconImg") then
		iconBg.IconImg.Image = getCreatureIcon(selectedCreatureId)
	end
	local nameTxt = pnl:FindFirstChild("NameTxt")
	if nameTxt then
		local sourceName = (data and data.name) or selectedCreatureId
		nameTxt.Text = UILocalizer.LocalizeDataText("CreatureData", selectedCreatureId, "name", sourceName)
	end
	local dnaTxt = pnl:FindFirstChild("DnaTxt")
	if dnaTxt then
		if isComplete then
			dnaTxt.Text = UILocalizer.Localize(string.format("DNA: %d/%d ✓ 완성!", dnaCount, dnaRequired))
			dnaTxt.TextColor3 = Color3.fromRGB(120, 200, 80)
		else
			dnaTxt.Text = UILocalizer.Localize(string.format("DNA: %d/%d", dnaCount, dnaRequired))
			dnaTxt.TextColor3 = C.GOLD
		end
	end
	
	local effVal = pnl:FindFirstChild("EffBg") and pnl.EffBg:FindFirstChild("EffVal")
	local effTit = pnl:FindFirstChild("EffBg") and pnl.EffBg:FindFirstChild("EffTit")
	if effTit then
		effTit.Text = UILocalizer.Localize("도감 패시브 효과")
	end
	if effVal then
		local passiveText = getPassiveEffectText(selectedCreatureId)
		if isComplete and passiveText then
			effVal.Text = UILocalizer.Localize("✓ " .. passiveText .. "\n펫 활성화 가능!")
			effVal.TextColor3 = Color3.fromRGB(120, 200, 80)
		elseif passiveText then
			effVal.Text = UILocalizer.Localize(passiveText .. "\n(도감 완성 시 활성화)")
			effVal.TextColor3 = C.DIM
		else
			effVal.Text = UILocalizer.Localize("효과 없음")
			effVal.TextColor3 = C.DIM
		end
	end
end

----------------------------------------------------------------
-- Pet Tab Detail Panel
----------------------------------------------------------------
local function _renderPetDetails()
	local detailFrame = CollectionUI.Refs.DetailFrame
	if not detailFrame then return end
	
	for _, c in ipairs(detailFrame:GetChildren()) do
		if c:IsA("GuiObject") then c.Visible = false end
	end
	
	if not selectedPetCreatureId then
		local mt = detailFrame:FindFirstChild("PetEmptyText")
		if not mt then
			mt = Utils.CreateTextLabel("PetEmptyText", UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), UILocalizer.Localize("펫을 선택하세요."))
			mt.TextColor3 = C.DIM
			mt.Parent = detailFrame
		end
		mt.Visible = true
		return
	end
	
	local pnl = detailFrame:FindFirstChild("PetDetailPnl")
	if not pnl then
		pnl = Instance.new("Frame")
		pnl.Name = "PetDetailPnl"
		pnl.Size = UDim2.new(1,0,1,0)
		pnl.BackgroundTransparency = 1
		pnl.Parent = detailFrame
		
		local iconBg = Utils.CreateFrame("PetIconBg", UDim2.new(0, 100, 0, 100), UDim2.new(0.5, 0, 0, 20), C.BG_SLOT)
		iconBg.AnchorPoint = Vector2.new(0.5, 0)
		Instance.new("UICorner", iconBg).CornerRadius = UDim.new(0, 12)
		local iconImg = Utils.CreateImage("IconImg", UDim2.new(0.8,0,0.8,0), UDim2.new(0.1,0,0.1,0), "")
		iconImg.Parent = iconBg
		iconBg.Parent = pnl
		
		local nameTxt = Utils.CreateTextLabel("PetNameTxt", UDim2.new(1,0,0,30), UDim2.new(0,0,0,130), "")
		nameTxt.Font = F.TITLE; nameTxt.TextSize = 26
		nameTxt.Parent = pnl
		
		local statsTxt = Utils.CreateTextLabel("PetStatsTxt", UDim2.new(0.9,0,0,55), UDim2.new(0.05,0,0,165), "")
		statsTxt.TextColor3 = C.DIM; statsTxt.TextXAlignment = Enum.TextXAlignment.Left
		statsTxt.TextYAlignment = Enum.TextYAlignment.Top; statsTxt.TextSize = 18
		statsTxt.Parent = pnl
		
		local equipBtn = Utils.CreateFrame("EquipBtn", UDim2.new(0.8,0,0,40), UDim2.new(0.1,0,0,230), C.GOLD)
		Instance.new("UICorner", equipBtn).CornerRadius = UDim.new(0, 8)
		local equipTxt = Utils.CreateTextLabel("Txt", UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), UILocalizer.Localize("장착"))
		equipTxt.Font = F.TITLE; equipTxt.TextSize = 22; equipTxt.TextColor3 = C.BG_OVERLAY
		equipTxt.Parent = equipBtn
		local equipBtnClick = Instance.new("TextButton")
		equipBtnClick.Name = "Click"; equipBtnClick.Size = UDim2.new(1,0,1,0)
		equipBtnClick.BackgroundTransparency = 1; equipBtnClick.Text = ""
		equipBtnClick.Parent = equipBtn
		equipBtn.Parent = pnl
		
		local unequipBtn = Utils.CreateFrame("UnequipBtn", UDim2.new(0.8,0,0,36), UDim2.new(0.1,0,0,280), C.BTN)
		Instance.new("UICorner", unequipBtn).CornerRadius = UDim.new(0, 8)
		local unequipTxt = Utils.CreateTextLabel("Txt", UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), UILocalizer.Localize("해제"))
		unequipTxt.Font = F.TITLE; unequipTxt.TextSize = 20; unequipTxt.TextColor3 = C.WHITE
		unequipTxt.Parent = unequipBtn
		local unequipBtnClick = Instance.new("TextButton")
		unequipBtnClick.Name = "Click"; unequipBtnClick.Size = UDim2.new(1,0,1,0)
		unequipBtnClick.BackgroundTransparency = 1; unequipBtnClick.Text = ""
		unequipBtnClick.Parent = unequipBtn
		unequipBtn.Parent = pnl
	end
	pnl.Visible = true
	
	local cData = CollectionController.getCreatureData(selectedPetCreatureId)
	local slots = CollectionController.getPetSlots()
	
	-- 이미 장착된 슬롯 찾기
	local equippedSlot = nil
	for i, cid in pairs(slots) do
		if cid == selectedPetCreatureId then equippedSlot = i; break end
	end
	
	local iconBg = pnl:FindFirstChild("PetIconBg")
	if iconBg and iconBg:FindFirstChild("IconImg") then
		iconBg.IconImg.Image = getCreatureIcon(selectedPetCreatureId)
	end
	
	local nameTxt = pnl:FindFirstChild("PetNameTxt")
	if nameTxt then
		local sourceName = (cData and cData.name) or selectedPetCreatureId
		nameTxt.Text = UILocalizer.LocalizeDataText("CreatureData", selectedPetCreatureId, "name", sourceName)
	end
	
	local statsTxt = pnl:FindFirstChild("PetStatsTxt")
	if statsTxt and cData then
		statsTxt.Text = UILocalizer.Localize(string.format(
			"체력: %d | 공격력: %d\n크기: %.0f%%",
			cData.petHealth or 50, cData.petDamage or 5, (cData.petScale or 0.3) * 100
		))
	end
	
	local equipBtn = pnl:FindFirstChild("EquipBtn")
	local unequipBtn = pnl:FindFirstChild("UnequipBtn")
	
	if equippedSlot then
		-- 이미 장착중 → 해제 버튼만 보여줌
		if equipBtn then equipBtn.Visible = false end
		if unequipBtn then
			unequipBtn.Visible = true
			local click = unequipBtn:FindFirstChild("Click")
			if click then
				-- 기존 연결 제거 및 새 연결
				for _, conn in ipairs(click:GetChildren()) do
					if conn:IsA("BindableEvent") then conn:Destroy() end
				end
				click.MouseButton1Click:Connect(function()
					task.spawn(function()
						CollectionController.requestUnequipPet(equippedSlot)
					end)
				end)
			end
		end
	else
		-- 미장착 → 장착 버튼 보여줌 (첫 빈 슬롯에 장착)
		if unequipBtn then unequipBtn.Visible = false end
		if equipBtn then
			equipBtn.Visible = true
			local click = equipBtn:FindFirstChild("Click")
			if click then
				click.MouseButton1Click:Connect(function()
					task.spawn(function()
						local maxSlots = CollectionController.getPetMaxSlots()
						local freeSlot = nil
						for i = 1, maxSlots do
							if not slots[i] and not slots[tostring(i)] then
								freeSlot = i; break
							end
						end
						if not freeSlot then freeSlot = 1 end -- 빈 슬롯 없으면 1번 교체
						CollectionController.requestEquipPet(freeSlot, selectedPetCreatureId)
					end)
				end)
			end
		end
	end
end

----------------------------------------------------------------
-- Pet Tab Scroll Content
----------------------------------------------------------------
local function _renderPetTab()
	local scroll = CollectionUI.Refs.Scroll
	
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	
	local slots = CollectionController.getPetSlots()
	local maxSlots = CollectionController.getPetMaxSlots()
	local y = 10
	
	-- 섹션 헤더: 펫 슬롯
	local slotHeader = Utils.CreateTextLabel("SlotHeader", UDim2.new(1, -20, 0, 28), UDim2.new(0, 10, 0, y), UILocalizer.Localize("펫 슬롯"))
	slotHeader.Font = F.TITLE; slotHeader.TextSize = 22; slotHeader.TextXAlignment = Enum.TextXAlignment.Left
	slotHeader.Parent = scroll
	y = y + 35
	
	-- 슬롯 렌더링 (Balance.MAX_PARTY 기준)
	local SLOT_W = 140
	local SLOT_H = 150
	for i = 1, maxSlots do
		local isUnlocked = (i <= maxSlots)
		local creatureId = slots[i] or slots[tostring(i)]
		local xPos = 10 + (i - 1) * (SLOT_W + 12)
		
		local slotBg = Utils.CreateFrame("Slot_" .. i, UDim2.new(0, SLOT_W, 0, SLOT_H), UDim2.new(0, xPos, 0, y), isUnlocked and C.BG_SLOT or C.BG_DARK)
		Instance.new("UICorner", slotBg).CornerRadius = UDim.new(0, 10)
		
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = (selectedPetSlot == i) and C.GOLD or C.BORDER_DIM
		stroke.Parent = slotBg
		
		if not isUnlocked then
			-- 잠긴 슬롯
			local lockTxt = Utils.CreateTextLabel("Lock", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0.5, -15), UILocalizer.Localize("🔒 잠김"))
			lockTxt.TextColor3 = C.DIM; lockTxt.TextSize = 20
			lockTxt.Parent = slotBg
			
			local infoTxt = Utils.CreateTextLabel("Info", UDim2.new(0.9, 0, 0, 22), UDim2.new(0.05, 0, 0.7, 0), UILocalizer.Localize("(상점에서 해제)"))
			infoTxt.TextColor3 = C.DIM; infoTxt.TextSize = 14
			infoTxt.Parent = slotBg
		elseif creatureId then
			-- 장착된 펫
			local icon = Utils.CreateImage("Icon", UDim2.new(0, 60, 0, 60), UDim2.new(0.5, -30, 0, 15), getCreatureIcon(creatureId))
			icon.Parent = slotBg
			
			local cData = CollectionController.getCreatureData(creatureId)
			local sourceName = (cData and cData.name) or creatureId
			local localizedName = UILocalizer.LocalizeDataText("CreatureData", creatureId, "name", sourceName)
			local nameL = Utils.CreateTextLabel("Name", UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 0, 80), localizedName)
			nameL.TextSize = 16; nameL.Parent = slotBg
			
			local slotLabel = Utils.CreateTextLabel("Label", UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 0, 105), UILocalizer.Localize(string.format("슬롯 %d", i)))
			slotLabel.TextSize = 14; slotLabel.TextColor3 = C.GOLD; slotLabel.Parent = slotBg
		else
			-- 빈 슬롯
			local emptyTxt = Utils.CreateTextLabel("Empty", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0.5, -15), UILocalizer.Localize("비어있음"))
			emptyTxt.TextColor3 = C.DIM; emptyTxt.TextSize = 18
			emptyTxt.Parent = slotBg
			
			local slotLabel = Utils.CreateTextLabel("Label", UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 0, 105), UILocalizer.Localize(string.format("슬롯 %d", i)))
			slotLabel.TextSize = 14; slotLabel.TextColor3 = C.DIM; slotLabel.Parent = slotBg
		end
		
		-- Click
		if isUnlocked then
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundTransparency = 1; btn.Text = ""; btn.Parent = slotBg
			btn.MouseButton1Click:Connect(function()
				selectedPetSlot = i
				selectedPetCreatureId = creatureId
				CollectionUI.refreshData()
			end)
		end
		
		slotBg.Parent = scroll
	end
	y = y + SLOT_H + 20
	
	-- 섹션 헤더: 사용 가능한 펫
	local availHeader = Utils.CreateTextLabel("AvailHeader", UDim2.new(1, -20, 0, 28), UDim2.new(0, 10, 0, y), UILocalizer.Localize("사용 가능한 펫"))
	availHeader.Font = F.TITLE; availHeader.TextSize = 22; availHeader.TextXAlignment = Enum.TextXAlignment.Left
	availHeader.Parent = scroll
	y = y + 35
	
	-- 완성된 도감 엔트리로부터 펫 리스트 (도감 완성한 크리처 전부)
	local creatures = CollectionController.getCreatureList()
	local CARD_W = 110
	local CARD_H = 130
	local SPACING = 10
	local cols = 4
	local x = 10
	local count = 0
	local hasAny = false
	
	for _, data in ipairs(creatures) do
		local cid = data.id
		if CollectionController.isCodexComplete(cid) then
			hasAny = true
			
			local card = Utils.CreateFrame("PetCard_" .. cid, UDim2.new(0, CARD_W, 0, CARD_H), UDim2.new(0, x, 0, y), C.BG_SLOT)
			card.BackgroundTransparency = T.SLOT
			
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2
			stroke.Color = (selectedPetCreatureId == cid) and C.GOLD_SEL or C.BORDER_DIM
			stroke.Parent = card
			
			local icon = Utils.CreateImage("Icon", UDim2.new(0, 60, 0, 60), UDim2.new(0.5, -30, 0, 15), getCreatureIcon(cid))
			icon.Parent = card
			
			local sourceName = data.name or cid
			local localizedName = UILocalizer.LocalizeDataText("CreatureData", cid, "name", sourceName)
			local nameL = Utils.CreateTextLabel("Name", UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 0, 80), localizedName)
			nameL.TextSize = 16; nameL.Parent = card
			
			-- 장착 여부 표시
			local equipped = false
			for _, sid in pairs(slots) do if sid == cid then equipped = true; break end end
			if equipped then
				local eqTag = Utils.CreateTextLabel("Eq", UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0, 105), UILocalizer.Localize("장착중"))
				eqTag.TextColor3 = Color3.fromRGB(120, 200, 80); eqTag.TextSize = 15; eqTag.Parent = card
			end
			
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundTransparency = 1; btn.Text = ""; btn.Parent = card
			btn.MouseButton1Click:Connect(function()
				selectedPetCreatureId = cid
				selectedPetSlot = nil
				CollectionUI.refreshData()
			end)
			
			card.Parent = scroll
			count = count + 1
			if count % cols == 0 then
				x = 10
				y = y + CARD_H + SPACING
			else
				x = x + CARD_W + SPACING
			end
		end
	end
	
	if not hasAny then
		local noTxt = Utils.CreateTextLabel("NoPet", UDim2.new(1, -20, 0, 30), UDim2.new(0, 10, 0, y), UILocalizer.Localize("도감을 완성하면 펫이 활성화됩니다."))
		noTxt.TextColor3 = C.DIM; noTxt.TextSize = 18
		noTxt.Parent = scroll
		y = y + 40
	end
	
	scroll.CanvasSize = UDim2.new(0, 0, 0, y + CARD_H + SPACING)
	_renderPetDetails()
end

----------------------------------------------------------------
-- Refresh Items (Scroll List)
----------------------------------------------------------------
function CollectionUI.refreshData()
	if not isUIInitialized then return end
	
	_updateTopTabs()
	
	-- 펫 모드이면 별도 렌더링
	if TOP_MODE == "PET" then
		_renderPetTab()
		return
	end
	
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
			local dRequired = data.dnaRequired or 5
			
			local card = Utils.CreateFrame("Card_"..cid, UDim2.new(0, CARD_W, 0, CARD_H), UDim2.new(0, x, 0, y), C.BG_SLOT)
			card.BackgroundTransparency = T.SLOT
			local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 8); corner.Parent = card
			
			-- 선택 하이라이트
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2
			stroke.Color = (cid == selectedCreatureId) and C.GOLD_SEL or C.BORDER_DIM
			stroke.Parent = card
			
			-- 아이콘
			local icon = Utils.CreateImage("Icon", UDim2.new(0, 60, 0, 60), UDim2.new(0.5, -30, 0, 15), getCreatureIcon(cid))
			icon.Parent = card
			
			-- 이름
			local sourceName = data.name or cid
			local localizedName = UILocalizer.LocalizeDataText("CreatureData", cid, "name", sourceName)
			local nameL = Utils.CreateTextLabel("Name", UDim2.new(1,0,0,20), UDim2.new(0,0,0,80), localizedName)
			nameL.TextSize = 16
			nameL.Parent = card
			
			-- DNA 바
			local barBg = Utils.CreateFrame("BarBg", UDim2.new(0.8, 0, 0, 12), UDim2.new(0.1, 0, 0, 105), C.BG_DARK)
			Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 5)
			
			local fillRatio = math.clamp(dCount / dRequired, 0, 1)
			local barFill = Utils.CreateFrame("BarFill", UDim2.new(fillRatio, 0, 1, 0), UDim2.new(0,0,0,0), C.GOLD)
			Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 5)
			barFill.Parent = barBg
			
			local countT = Utils.CreateTextLabel("Cnt", UDim2.new(1,0,1,0), UDim2.new(0,0,0,0), UILocalizer.Localize(string.format("%d/%d", dCount, dRequired)))
			countT.TextSize = 13
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

function CollectionUI.Init(mainGui, uiManager, isMobile)
	if isUIInitialized then return end
	UIManager = uiManager
	local isSmall = isMobile
	
	-- Main Window (Using Modern Theme style)
	local Frame = Utils.mkFrame({
		name = "CollectionFrame", 
		size = UDim2.new(isSmall and 0.95 or 0.75, 0, isSmall and 0.92 or 0.82, 0), 
		pos = UDim2.new(0.5, 0, 0.5, 0),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL, bgT = T.PANEL, r = 6, stroke = 1.5, strokeC = C.BORDER
	})
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(900, 580)
	sizeConstraint.Parent = Frame
	Frame.Visible = false
	CollectionUI.Refs.Frame = Frame
	
	-- Header (인벤토리 스타일: 가로 탭 + 닫기)
	local header = Utils.mkFrame({name="Header", size=UDim2.new(1,0,0,50), bgT=1, parent=Frame})

	local leftHeader = Utils.mkFrame({size=UDim2.new(0.6, -20, 1, 0), pos=UDim2.new(0, 15, 0, 0), bgT=1, parent=header})
	local titleList = Instance.new("UIListLayout")
	titleList.FillDirection = Enum.FillDirection.Horizontal
	titleList.VerticalAlignment = Enum.VerticalAlignment.Center
	titleList.Padding = UDim.new(0, 20)
	titleList.Parent = leftHeader

	CollectionUI.Refs.TabCodex = Utils.mkBtn({text=UILocalizer.Localize("도감 [P]"), size=UDim2.new(0, 160, 0, 42), bgT=1, font=F.TITLE, ts=24, color=C.GOLD_SEL, parent=leftHeader})
	CollectionUI.Refs.TabPet = Utils.mkBtn({text=UILocalizer.Localize("펫"), size=UDim2.new(0, 110, 0, 42), bgT=1, font=F.TITLE, ts=24, color=C.GRAY, parent=leftHeader})

	CollectionUI.Refs.TabCodex.MouseButton1Click:Connect(function()
		TOP_MODE = "CODEX"
		activeTabKey = "ALL"
		selectedCreatureId = nil
		selectedPetCreatureId = nil
		selectedPetSlot = nil
		_renderRegionTabs()
		CollectionUI.refreshData()
	end)

	CollectionUI.Refs.TabPet.MouseButton1Click:Connect(function()
		TOP_MODE = "PET"
		selectedCreatureId = nil
		selectedPetCreatureId = nil
		selectedPetSlot = nil
		CollectionUI.refreshData()
	end)

	Utils.mkBtn({text="X", size=UDim2.new(0, 42, 0, 42), pos=UDim2.new(1, -10, 0.5, 0), anchor=Vector2.new(1, 0.5), bg=C.BTN, bgT=0.5, ts=24, color=C.WHITE, r=4, fn=function() UIManager.closeCollection() end, parent=header})
	
	-- 좌측 탭 영역
	local TabList = Instance.new("ScrollingFrame")
	TabList.Name = "TabList"
	TabList.Size = UDim2.new(0.14, 0, 1, -60)
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
	Scroll.Size = UDim2.new(0.56, -10, 1, -70)
	Scroll.Position = UDim2.new(0.14, 10, 0, 60)
	Scroll.BackgroundColor3 = C.BG_SLOT
	Scroll.BackgroundTransparency = 0.35
	Scroll.ScrollBarThickness = 5
	Scroll.ScrollBarImageColor3 = C.GOLD
	Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	Scroll.CanvasSize = UDim2.new(0,0,0,0)
	
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10); pad.PaddingLeft = UDim.new(0, 10); pad.PaddingRight = UDim.new(0, 20)
	pad.Parent = Scroll
	
	Utils.AddCorner(Scroll, 8)
	CollectionUI.Refs.Scroll = Scroll
	Scroll.Parent = Frame
	
	-- 우측 상세 정보창
	local DetailFrame = Instance.new("Frame")
	DetailFrame.Name = "DetailFrame"
	DetailFrame.Size = UDim2.new(0.28, -5, 1, -60)
	DetailFrame.Position = UDim2.new(0.72, 0, 0, 50)
	DetailFrame.BackgroundColor3 = C.BG_PANEL_L
	DetailFrame.BackgroundTransparency = 0.15
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
	
	TOP_MODE = "CODEX"
	activeTabKey = "ALL"
	_renderRegionTabs()
	CollectionUI.refreshData()
	
	-- Data Event Hook (DNA 획득 시 UI에 열려있으면 즉시 반영)
	CollectionController.onDnaUpdated(function()
		if WindowManager.isOpen("COLLECTION") then
			CollectionUI.refreshData()
		end
	end)
	
	-- 펫 슬롯 업데이트 반영
	CollectionController.onPetUpdated(function()
		if WindowManager.isOpen("COLLECTION") then
			CollectionUI.refreshData()
		end
	end)
end

function CollectionUI.Hide()
	if not CollectionUI.Refs.Frame then return end
	CollectionUI.Refs.Frame.Visible = false
	selectedCreatureId = nil
	selectedPetCreatureId = nil
	selectedPetSlot = nil
end

return CollectionUI
