-- UIManager.lua
-- WildForge UI — 듀랑고 스타일 레퍼런스 기반
-- HUD(우측) + 원형슬롯 인벤토리 + 풀스크린 제작 + 채집바(상단)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local GuiService = game:GetService("GuiService")
local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local UI_SCALE = isMobile and 1.4 or 1.0

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)
local DataHelper = require(Shared.Util.DataHelper)

-- Load Creature Data for combat UI
local CreatureData = {}
local function loadCreatureData()
	local Data = ReplicatedStorage:FindFirstChild("Data")
	if Data then
		local ok, result = pcall(function()
			return require(Data:WaitForChild("CreatureData", 5))
		end)
		if ok and result then
			CreatureData = result
		end
	end
end
loadCreatureData()

local Client = script.Parent
local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)
local LocaleService = require(Client.Localization.LocaleService)
local UILocalizer = require(Client.Localization.UILocalizer)

local Controllers = Client:WaitForChild("Controllers")
local InventoryController = require(Controllers.InventoryController)
local ShopController = require(Controllers.ShopController)
local BuildController = require(Controllers.BuildController)
local StorageController = require(Controllers.StorageController)
local FacilityController = require(Controllers.FacilityController)
local TechController = require(Controllers.TechController)
local TimeController = require(Controllers.TimeController)
local DragDropController = require(Controllers.DragDropController)
local InteractController = require(Controllers.InteractController)

local WindowManager = require(Client.Utils.WindowManager)

local UIManager = {}

----------------------------------------------------------------
-- ★ 에러코드 → 사용자 친화적 한글 메시지 변환
-- 이 테이블에 없는 코드는 일반 메시지로 표시 (코드 노출 금지)
----------------------------------------------------------------
local ERROR_MESSAGES = {
	-- 팰/동물 관련
	PARTY_FULL = "파티가 가득 찼습니다. 먼저 다른 동물을 회수하세요.",
	FAINTED = "기절한 동물은 소환할 수 없습니다.",
	PALBOX_FULL = "동물 보관함이 가득 찼습니다.",
	PAL_IN_PARTY = "이미 파티에 포함된 동물입니다.",
	PAL_ALREADY_ASSIGNED = "이미 다른 곳에 배치된 동물입니다.",
	PARTY_ADD_FAILED = "파티에 추가할 수 없습니다.",
	NO_PARTY = "파티 정보를 찾을 수 없습니다.",
	NOT_IN_PARTY = "파티에 포함되지 않은 동물입니다.",
	SUMMON_FAILED = "소환에 실패했습니다. 잠시 후 다시 시도하세요.",
	
	-- 공통
	BAD_REQUEST = "잘못된 요청입니다.",
	NOT_FOUND = "대상을 찾을 수 없습니다.",
	INVALID_STATE = "현재 상태에서는 수행할 수 없습니다.",
	OUT_OF_RANGE = "대상과 거리가 너무 멉니다. 더 가까이 이동하세요.",
	COOLDOWN = "재사용 대기 중입니다.",
	UNKNOWN = "알 수 없는 오류가 발생했습니다.",
	
	-- 전투/스킬
	WEAPON_MISMATCH = "해당 스킬에 맞는 무기를 장착해주세요.",
	SKILL_NOT_IN_SLOT = "스킬이 슬롯에 장착되어 있지 않습니다.",
	SKILL_NOT_UNLOCKED = "스킬이 해금되지 않았습니다.",
	NOT_ENOUGH_STAMINA = "스태미나가 부족합니다.",
	PLAYER_DEAD = "사용할 수 없는 상태입니다.",
	SKILL_NOT_FOUND = "스킬을 찾을 수 없습니다.",
	
	-- 인벤토리/제작
	INV_FULL = "인벤토리가 가득 찼습니다.",
	INVENTORY_FULL = "인벤토리가 가득 찼습니다.",
	NO_ITEM = "재료가 부족합니다.",
	CRAFT_NOT_FOUND = "제작법을 찾을 수 없습니다.",
	
	-- 채집
	NODE_NOT_FOUND = "채집 대상을 찾을 수 없습니다.",
	
	-- 거점/시설
	NO_PERMISSION = "토템 보호가 활성화된 시설입니다.",
	INSUFFICIENT_GOLD = "골드가 부족합니다.",
	TOTEM_NOT_OWNER = "소유한 토템에서만 유지비를 결제할 수 있습니다.",
	TOTEM_NOT_FOUND = "토템을 찾을 수 없습니다.",
	INVALID_COUNT = "결제 기간이 올바르지 않습니다.",
	
	-- 포획
	INVALID_TARGET = "포획할 수 없는 대상입니다.",
	CREATURE_NOT_FOUND = "크리처를 찾을 수 없습니다.",
	NOT_COLLAPSED = "먼저 크리처를 쓰러뜨려야 합니다.",
	ALREADY_DEAD = "이미 죽은 크리처입니다.",
	ALREADY_ATTEMPTED = "이미 포획을 시도한 크리처입니다.",
	SKILL_LOCKED = "포획 스킬이 해금되지 않았습니다.",
	NO_BOX_ITEM = "포획 상자가 없습니다.",
	
	-- 기타
	NOTHING_TO_RESET = "초기화할 항목이 없습니다.",
	MAX_SLOTS_REACHED = "인벤토리 칸 스탯이 최대치에 도달했습니다.",
	MAX_WORKSPEED_REACHED = "작업속도 스탯이 최대치에 도달했습니다.",
	INSUFFICIENT_STAT_POINTS = "스탯 포인트가 부족합니다.",
}

--- 에러코드를 사용자 친화적 한글 메시지로 변환
--- @param errCode any 서버로부터 받은 에러코드
--- @param fallbackAction string? 행동 설명 (예: "소환", "제작")
--- @return string 사용자에게 보여줄 한글 메시지
local function friendlyError(errCode, fallbackAction)
	local code = tostring(errCode or "UNKNOWN")
	local msg = ERROR_MESSAGES[code]
	if msg then return msg end
	-- 매핑에 없는 코드 → 일반 메시지 (코드 노출 금지, Output에만 출력)
	warn("[UIManager] Unmapped error code:", code)
	if fallbackAction then
		return fallbackAction .. "에 실패했습니다. 잠시 후 다시 시도하세요."
	end
	return "요청을 처리할 수 없습니다. 잠시 후 다시 시도하세요."
end



-- UI Modules
local UI = script.Parent.UI
local Theme = require(UI.UITheme)
local Utils = require(UI.UIUtils)
local HUDUI = require(UI.HUDUI)
local InventoryUI = require(UI.InventoryUI)
local CraftingUI = require(UI.CraftingUI)
local ShopUI = require(UI.ShopUI)
local InteractUI = require(UI.InteractUI)
local BuildUI = require(UI.BuildUI)
local EquipmentUI = require(UI.EquipmentUI)
local StorageUI = require(UI.StorageUI)
local FacilityUI = require(UI.FacilityUI)
local MaterialSelectUI = require(UI.MaterialSelectUI)

local PromptUI = require(UI.PromptUI)
local TotemUI = require(UI.TotemUI)
local PortalUI = require(UI.PortalUI)
local SkillTreeUI = require(UI.SkillTreeUI)
local ActiveSkillBarUI = require(UI.ActiveSkillBarUI)
local HarvestUI = require(UI.HarvestUI)
local PortalRadialUI = require(UI.PortalRadialUI)
local QuestUI = require(UI.QuestUI)
local FacilityRadialUI = require(UI.FacilityRadialUI)
local PalRadialUI = require(UI.PalRadialUI)
local NPCRadialUI = require(UI.NPCRadialUI)


local SkillController = require(Controllers.SkillController)

local C = Theme.Colors
local F = Theme.Fonts
local T = Theme.Transp

local mainGui

-- HUD refs
local healthBar, staminaBar, xpBar, levelLabel, statPointAlert

-- Hotbar
local hotbarFrame
local hotbarSlots = {}
local selectedSlot = 1

-- Panels
local inventoryFrame, craftingOverlay, shopFrame, techOverlay, interactPrompt
local actionContainer, hotbarFrame -- Store refs for visibility control
-- [Refactor] 개별 상태 플래그를 WindowManager로 통합 관리 (유지보수 지옥 탈출)
local cachedStats = {}
local pendingStats = {}
local activeDebuffs = {} -- { [debuffId] = {id, name, startTime, duration} }
local selectedBuildCat = "BUILD_T0"
local selectedFacilityId = nil -- shared with Crafting or use separate variable
local selectedBuildId = nil
local currentFacilityStructureId = nil
local currentFacilityType = nil
local currentFacilityId = nil
local selectedFacilityRecipe = nil
local currentTotemStructureId = nil

-- 0. UI 관리 헬퍼
local function isAnyWindowOpen()
	return WindowManager.isAnyOpen()
end


local function updateUIMode()
	local anyOpen = WindowManager.isAnyOpen()
	local hasFullWindow = WindowManager.hasFullWindowOpen()
	
	InputManager.setUIOpen(anyOpen)
	
	-- 전체 화면 창(인벤토리 등)이 열릴 때만 메인 HUD를 숨김
	UIManager._setMainHUDVisible(not hasFullWindow)
	
	-- 액티브 스킬바도 전체 화면 UI가 열릴 때만 숨김
	if ActiveSkillBarUI and ActiveSkillBarUI.SetVisible then
		ActiveSkillBarUI.SetVisible(not hasFullWindow)
	end
end

local function closeAllWindows(except)
	WindowManager.closeOthers(except)
end

-- [중복 제거] openTechTree/closeTechTree/toggleTechTree는 하단에서 올바르게 정의됩니다.

function UIManager._setMainHUDVisible(visible)
	HUDUI.SetVisible(visible)
end

-- Harvest progress
local harvestFrame, harvestBar, harvestPctLabel, harvestNameLabel

-- Combat State
local currentCombatCreatureId = nil

-- Inventory
local invSlots = {}
local invDetailPanel
local selectedInvSlot = nil
local hoveredStorageSlotInfo = nil
local currentStorageData = nil
local categoryButtons = {}

-- Crafting / Building
local craftNodes = {}
local selectedRecipeId = nil
local craftDetailPanel
local equipmentUIFrame

function UIManager.updateHealth(cur, max) HUDUI.UpdateHealth(cur, max) end
function UIManager.updateStamina(cur, max) HUDUI.UpdateStamina(cur, max) end
function UIManager.updateHunger(cur, max) HUDUI.UpdateHunger(cur, max) end
function UIManager.updateXP(cur, max) HUDUI.UpdateXP(cur, max) end
function UIManager.updateLevel(lvl) HUDUI.UpdateLevel(lvl) end
function UIManager.updateStatPoints(pts) HUDUI.UpdateStatPoints(pts) end
function UIManager.setTutorialVisible(visible) HUDUI.SetTutorialVisible(visible) end
function UIManager.updateTutorialStatus(status) HUDUI.UpdateTutorialStatus(status) end

function UIManager.requestTutorialStepComplete()
	local ok, data = NetClient.Request("Tutorial.Step.Complete.Request", {})
	if not ok then
		local statusOk, statusData = NetClient.Request("Tutorial.GetStatus.Request", {})
		if statusOk and type(statusData) == "table" then
			UIManager.updateTutorialStatus(statusData)
			if statusData.stepReady == true then
				ok, data = NetClient.Request("Tutorial.Step.Complete.Request", {})
			end
		end
	end

	if not ok then
		UIManager.notify("완료 조건을 확인할 수 없습니다. 목표를 다시 확인해 주세요.", C.WHITE)
		return false
	end

	if type(data) == "table" then
		UIManager.updateTutorialStatus(data)
	end

	return true
end

function UIManager.getPendingStatCount(statId)
	return pendingStats[statId] or 0
end

-- refreshStats는 하단에 isEquipmentOpen 가드와 함께 올바르게 정의됩니다.

function UIManager.addPendingStat(statId)
	local available = (cachedStats and cachedStats.statPointsAvailable or 0)
	local currentTotalPending = 0
	for _, v in pairs(pendingStats) do currentTotalPending = currentTotalPending + (v or 0) end
	
	-- 인벤토리 칸 스탯: 120칸 상한 검사
	if statId == Enums.StatId.INV_SLOTS then
		local calc = cachedStats and cachedStats.calculated or {}
		local currentMaxSlots = calc.maxSlots or Balance.BASE_INV_SLOTS
		local pendingSlots = (pendingStats[Enums.StatId.INV_SLOTS] or 0) * Balance.SLOTS_PER_POINT
		if currentMaxSlots + pendingSlots >= Balance.MAX_INV_SLOTS then
			UIManager.notify("인벤토리 최대 칸수(" .. Balance.MAX_INV_SLOTS .. "칸)에 도달했습니다.", C.RED)
			return
		end
	end
	
	if currentTotalPending < available then
		pendingStats[statId] = (pendingStats[statId] or 0) + 1
		UIManager.refreshStats()
	else
		UIManager.notify("강화 포인트가 부족합니다.", C.RED)
	end
end

function UIManager.cancelPendingStats()
	pendingStats = {}
	UIManager.refreshStats()
end

function UIManager.confirmPendingStats()
	local total = 0
	for _, v in pairs(pendingStats) do total = total + v end
	if total <= 0 then return end
	
	task.spawn(function()
		local ok, data = NetClient.Request("Player.Stats.Upgrade.Request", {stats = pendingStats})
		if ok then
			pendingStats = {}
			UIManager.refreshStats()
			-- cachedStats는 Player.Stats.Changed 이벤트로 업데이트됨
		else
			UIManager.notify(friendlyError(data, "강화"), C.RED)
		end
	end)
end

function UIManager.resetAllStats()
	-- 투자된 스탯이 하나라도 있는지 확인
	local invested = cachedStats and cachedStats.statInvested
	if not invested then
		UIManager.notify("초기화할 스탯이 없습니다.", C.RED)
		return
	end
	local totalInvested = 0
	for _, v in pairs(invested) do totalInvested = totalInvested + (v or 0) end
	if totalInvested <= 0 then
		UIManager.notify("초기화할 스탯이 없습니다.", C.RED)
		return
	end
	
	-- 보류 중인 강화 취소
	pendingStats = {}
	
	task.spawn(function()
		local ok, data = NetClient.Request("Player.Stats.Reset.Request", {})
		if ok then
			local refunded = data and data.refunded or 0
			local dropped = data and data.droppedCount or 0
			UIManager.notify(string.format("스탯 초기화 완료! %d 포인트 환급", refunded), C.GREEN)
			if dropped > 0 then
				UIManager.notify(string.format("초과 아이템 %d종이 발 밑에 드랍되었습니다.", dropped), C.GOLD)
			end
			UIManager.refreshStats()
			UIManager.refreshInventory()
		else
			UIManager.notify(friendlyError(data, "스탯 초기화"), C.RED)
		end
	end)
end
----------------------------------------------------------------
-- Public API: Equipment (장비창)
----------------------------------------------------------------
----------------------------------------------------------------
-- Public API: Equipment (장비창)
----------------------------------------------------------------
function UIManager.openEquipment()
	WindowManager.open("EQUIP")
end

function UIManager._onOpenEquipment()
	-- UI 상태 즉시 반영
	EquipmentUI.SetVisible(true)
	updateUIMode()
	EquipmentUI.UpdateCharacterPreview(player.Character)
	
	-- 데이터 최신화 요청 (백그라운드)
	task.spawn(function()
		local ok, d = NetClient.Request("Player.Stats.Request", {})
		if ok and d then cachedStats = d end
		
		local equipmentData = InventoryController.getEquipment and InventoryController.getEquipment() or {}
		UIManager.refreshStats() 
	end)
end

function UIManager.closeEquipment()
	WindowManager.close("EQUIP")
end

function UIManager._onCloseEquipment()
	EquipmentUI.SetVisible(false)
end

function UIManager.toggleEquipment()
	WindowManager.toggle("EQUIP")
end
----------------------------------------------------------------
-- Public API: Settings/Etc 
----------------------------------------------------------------

-- Personal Crafting
local invPersonalCraftGrid = nil
local invCraftContainer = nil
local personalCraftNodes = {}
local selectedPersonalRecipeId = nil
local bagTabBtn, craftTabBtn

-- Tech Tree
local techNodes = {}
local selectedTechId = nil
local techLines = {} -- 연결선용

-- Notification State
local notifyQueue = {}
local sideNotifyStack = {} -- [frame] = { startTime, label }
local sideNotifyContainer = nil

-- Drag & Drop
-- Drag & Drop state managed via DragDropController
local DRAG_THRESHOLD = 5 -- Lower threshold for easier dragging
local pendingDragIdx = nil
local draggingSlotIdx = nil
local dragStartPos = Vector2.zero
local dragDummy = nil

local cachedPersonalRecipes = nil
local activeShopId = nil


----------------------------------------------------------------
-- UI Helpers (Module Aliases)
----------------------------------------------------------------
local mkFrame = Utils.mkFrame
local mkLabel = Utils.mkLabel
local mkBtn   = Utils.mkBtn
local mkSlot  = Utils.mkSlot
local mkBar   = Utils.mkBar


-- Legacy creation functions removed (moved to UI/ modules)


-- Notifications are handled by the modern notify() function below.

function UIManager.upgradeStat(statId)
	UIManager.addPendingStat(statId)
end

function UIManager.updateStatPoints(available)
	HUDUI.SetStatPointAlert(available)
end

function UIManager.updateGold(amt)
	InventoryUI.UpdateCurrency(amt)
	ShopUI.UpdateGold(amt)
	if WindowManager.isOpen("STORAGE") then
		UIManager.refreshStorage()
	end
	if shopFrame then
		local g = shopFrame:FindFirstChild("TB")
		if g then g = g:FindFirstChild("Gold"); if g then g.Text = "💰 "..tostring(amt) end end
	end
end

----------------------------------------------------------------
-- Public API: Hotbar
----------------------------------------------------------------
function UIManager.selectHotbarSlot(idx, skipSync)
	selectedSlot = idx
	HUDUI.SelectHotbarSlot(idx, skipSync, UIManager, C)

	-- 채집 중 도구 교체 시 HarvestUI 닫기 (혼동 방지)
	if HarvestUI.IsOpen() then
		HarvestUI.Close()
	end

	if not skipSync then
		InventoryController.requestSetActiveSlot(idx)
	end
end

function UIManager.getSelectedSlot()
	return selectedSlot
end

local ICON_FOLDERS = {}
task.spawn(function()
	local assets = ReplicatedStorage:WaitForChild("Assets", 5)
	if assets then
		local folderNames = {"ItemIcons", "UIIcons", "Images", "Icons"}
		for _, name in ipairs(folderNames) do
			local f = assets:FindFirstChild(name)
			if f then
				table.insert(ICON_FOLDERS, f)
			end
		end
	end
	
	-- 아이콘 폴더가 로드되면 UI를 한 번 새로고침 해줍니다. (처음에 안 보이던 아이템 렌더링 복구)
	if UIManager.refreshInventory then
		task.wait(0.5) -- 완전히 복제될 시간을 약간 부여
		UIManager.refreshInventory()
		UIManager.refreshHotbar()
	end
end)

-- 아이템 아이콘 가져오기 (폴더 검색 우선, 데이터 폴백)
local function getItemIcon(itemId: string): string
	if not itemId then return "" end
	
	-- 0. 아이템/시설 데이터 조회 (alias 확인용)
	local itemDataRef = DataHelper and DataHelper.GetData("ItemData", itemId)
	local facilityDataRef = DataHelper and DataHelper.GetData("FacilityData", itemId)
	local searchCandidates = {}
	local function pushCandidate(value)
		if type(value) ~= "string" or value == "" then
			return
		end
		for _, existing in ipairs(searchCandidates) do
			if existing == value then
				return
			end
		end
		table.insert(searchCandidates, value)
	end

	pushCandidate(itemDataRef and itemDataRef.iconName)
	pushCandidate(itemId)

	if facilityDataRef then
		pushCandidate(facilityDataRef.iconName)
		pushCandidate(facilityDataRef.modelName)
		pushCandidate(facilityDataRef.id)
		if type(facilityDataRef.iconAliases) == "table" then
			for _, alias in ipairs(facilityDataRef.iconAliases) do
				pushCandidate(alias)
			end
		end
	end

	if itemId == "BASIC_WORKBENCH" then
		pushCandidate("PRIMITIVE_WORKBENCH")
		pushCandidate("PrimitiveWorkbench")
	end
	if itemId == "BED_T1" then
		pushCandidate("BED_T1")
		pushCandidate("LeanTo")
		pushCandidate("Lean_To")
	end
	
	-- CRAFT_ 나 SMELT_ 접두사가 있으면 제거된 형태도 후보로 추가
	local expandedCandidates = {}
	for _, name in ipairs(searchCandidates) do
		table.insert(expandedCandidates, name)
		local core = name:gsub("^CRAFT_", ""):gsub("^SMELT_", "")
		if core ~= name then
			table.insert(expandedCandidates, core)
		end
	end
	
	-- 1. 로드된 아이콘 폴더들에서 검색
	for _, folder in ipairs(ICON_FOLDERS) do
		local iconObj = nil
		for _, candidate in ipairs(expandedCandidates) do
			iconObj = folder:FindFirstChild(candidate)
			if iconObj then
				break
			end
		end
		
		if not iconObj then
			-- Case & Underscore insensitive search
			local targetMap = {}
			for _, candidate in ipairs(expandedCandidates) do
				targetMap[candidate:lower():gsub("_", "")] = true
			end
			for _, child in ipairs(folder:GetChildren()) do
				local cname = child.Name:lower():gsub("_", "")
				if targetMap[cname] then
					iconObj = child
					break
				end
			end
		end
		
		if iconObj then
			if iconObj:IsA("Decal") or iconObj:IsA("Texture") then
				return iconObj.Texture
			elseif iconObj:IsA("ImageLabel") or iconObj:IsA("ImageButton") then
				return iconObj.Image
			elseif iconObj:IsA("StringValue") then
				return iconObj.Value
			end
		end
	end

	-- 2. ItemData에서 직접 아이콘 ID 확인 (데이터 기반 우선)
	if itemDataRef and itemDataRef.icon then
		return itemDataRef.icon
	end
	if facilityDataRef and facilityDataRef.icon then
		return facilityDataRef.icon
	end

	-- 3. If it's not found in folders or data, we return an empty string or placeholder.
	return "rbxassetid://0" -- 투명 아이콘
end
UIManager.getItemIcon = getItemIcon

function UIManager.refreshHotbar()
	local items = InventoryController.getItems()
	for i=1,8 do
		local s = hotbarSlots and hotbarSlots[i]
		if s then
			local item = items[i]
			if item and item.itemId then
				local icon = getItemIcon(item.itemId)
				s.icon.Image = icon
				s.countLabel.Text = (item.count and item.count > 1) and ("x"..item.count) or ""
				s.icon.Visible = (icon ~= "")
				
				local itemData = DataHelper.GetData("ItemData", item.itemId)
				
				if item.durability and itemData and itemData.durability then
					local ratio = math.clamp(item.durability / itemData.durability, 0, 1)
					s.durBg.Visible = true
					s.durFill.Size = UDim2.new(ratio, 0, 1, 0)
					if ratio > 0.5 then
						s.durFill.BackgroundColor3 = Color3.fromRGB(150, 255, 150)
					elseif ratio > 0.2 then
						s.durFill.BackgroundColor3 = Color3.fromRGB(255, 200, 100)
					else
						s.durFill.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
					end
				else
					if s.durBg then s.durBg.Visible = false end
				end
			else
				s.icon.Image = ""; s.countLabel.Text = ""
				if s.durBg then s.durBg.Visible = false end
			end
		end
	end
end

----------------------------------------------------------------
-- Public API: Inventory
----------------------------------------------------------------
----------------------------------------------------------------
-- Public API: Inventory
----------------------------------------------------------------
function UIManager.openInventory(startTab)
	WindowManager.open("INV", startTab)
end

function UIManager._onOpenInventory(startTab)
	-- 가방 열 때마다 선택 초기화 (사용자 요청: 선택된 게 있어야 정보창 나옴)
	selectedInvSlot = nil 
	
	-- 만약 단축키 등으로 직접 여는 것이라면 시설 정보 초기화
	if not startTab or startTab == "BAG" then
		activeFacilityId = nil
		activeStructureId = nil
	end

	InventoryUI.SetVisible(true)
	InventoryUI.SetTab(startTab or "BAG")
	InventoryUI.UpdateCurrency(ShopController.getGold())
	ShopController.requestGold(function(ok, gold)
		if ok then
			InventoryUI.UpdateCurrency(gold)
		end
	end)
	UIManager.refreshInventory()
	if startTab == "CRAFT" then
		UIManager.refreshPersonalCrafting(true)
	elseif startTab == "ANIMAL" then
		UIManager.refreshAnimalManagement()
	end
end

function UIManager.closeInventory()
	WindowManager.close("INV")
end

function UIManager._onCloseInventory()
	-- 드래그 상태 강제 초기화
	if DragDropController.isDragging() then
		DragDropController.handleDragEnd()
	end
	
	InventoryUI.SetVisible(false)
	selectedInvSlot = nil -- 선택 초기화 (사용자 요청: 열 때 선택된 거 없게)
end

function UIManager.toggleInventory(startTab)
	WindowManager.toggle("INV", startTab)
end

function UIManager.toggleQuest()
	WindowManager.toggle("QUEST")
end

function UIManager._onOpenQuest()
	QuestUI:Open()
end

function UIManager._onCloseQuest()
	QuestUI:Close()
end

function UIManager.refreshInventory()
	local items = InventoryController.getItems()
	local _, currentMaxSlots = InventoryController.getSlotInfo()
	InventoryUI.RefreshSlots(items, getItemIcon, C, DataHelper, currentMaxSlots)
	
	-- 상세창 정보 업데이트 (선택된 슬롯이 있는 경우 실시간 반영, 없으면 숨김)
	if selectedInvSlot and items[selectedInvSlot] then
		InventoryUI.UpdateDetail(items[selectedInvSlot], getItemIcon, Enums, DataHelper, InventoryController.getItemCounts())
	elseif selectedInvSlot == nil and WindowManager.isOpen("INV") and InventoryUI.Refs.CraftFrame and InventoryUI.Refs.CraftFrame.Visible then
		-- [추가] 제작 탭이 활성화된 상태라면, 소지품 슬롯이 선택되지 않았더라도 상세창을 유지
		if selectedPersonalRecipeId and cachedPersonalRecipes then
			for _, r in ipairs(cachedPersonalRecipes) do
				if r.id == selectedPersonalRecipeId then
					UIManager._updatePersonalCraftDetail(r)
					break
				end
			end
		end
	else
		-- [유지] 선택된 대상이 없으면 상세창 숨김 (사용자 요청 반영)
		InventoryUI.UpdateDetail(nil) 
	end
	
	local usedSlots, maxSlots = InventoryController.getSlotInfo()
	InventoryUI.UpdateSlotInfo(usedSlots, maxSlots, C)
	
	UIManager.refreshHotbar()
end

function UIManager.refreshStats()
	local totalPending = 0
	for _, v in pairs(pendingStats) do totalPending = totalPending + v end
	
	if WindowManager.isOpen("EQUIP") then
		local equipmentData = InventoryController.getEquipment and InventoryController.getEquipment() or {}
		EquipmentUI.Refresh(cachedStats, totalPending, equipmentData, getItemIcon, Enums)
	end
end

function UIManager.onEquipmentSlotClick(slotName)
	local equip = InventoryController.getEquipment()
	local item = equip[slotName]
	if item then
		local itemData = DataHelper.GetData("ItemData", item.itemId)
		if itemData then
			UIManager.notify(string.format("[%s] %s", slotName, itemData.name), C.GOLD)
		end
	end
end

function UIManager.onEquipmentSlotRightClick(slotName)
	if slotName == "HAND" then
		UIManager.notify("도구/무기 표시는 핫바 1번 슬롯 기준입니다.", C.WHITE)
		return
	end
	local equip = InventoryController.getEquipment()
	if equip[slotName] then
		InventoryController.requestUnequip(slotName)
	end
end

----------------------------------------------------------------
-- [Refactor] Inventory Drag & Drop Logic (DragDropController로 이관)
----------------------------------------------------------------
function UIManager.handleDragStart(idx, input) DragDropController.handleDragStart(idx) end
function UIManager.handleDragUpdate(input) DragDropController.handleDragUpdate() end
function UIManager.handleDragEnd(input) DragDropController.handleDragEnd() end
function UIManager.isDragging() return DragDropController.isDragging() end

-- Controller에서 UI 요소에 접근하기 위한 Getter들
function UIManager.getInvSlots() return invSlots end
function UIManager.getHotbarSlots() return hotbarSlots end
function UIManager.getEquipSlots() return equipSlots end
function UIManager.isWindowOpen(winId) return WindowManager.isOpen(winId) end
function UIManager.getIsMobile() return isMobile end

-- UIManager.isDragging()은 이미 위(L456)에서 DragDropController를 통해 정의됨 (중복 제거)

local modalActionType = "DROP" -- DROP, SPLIT, DROP_GOLD, STORAGE_DEPOSIT_GOLD, STORAGE_WITHDRAW_GOLD

local function openCountModal(title, amount)
	local safeAmount = math.max(1, math.floor(tonumber(amount) or 1))
	local m = InventoryUI.Refs.DropModal
	m.Frame.Visible = true
	m.Input.Text = tostring(safeAmount)
	m.MaxLabel.Text = "(최대: " .. safeAmount .. ")"
	if m.Title then
		m.Title.Text = title or "수량 입력"
	end
end

function UIManager.openDropModal()
	if not selectedInvSlot then return end
	local item = InventoryController.getSlot(selectedInvSlot)
	if not item then return end
	
	modalActionType = "DROP"
	
	-- 동일 itemId를 가진 모든 슬롯의 총 개수 계산
	local totalCount = 0
	local items = InventoryController.getItems()
	for _, slotData in pairs(items) do
		if slotData and slotData.itemId == item.itemId then
			totalCount = totalCount + (slotData.count or 1)
		end
	end
	if totalCount < 1 then totalCount = 1 end
	
	openCountModal("수량 입력", totalCount)
end

function UIManager.openGoldDropModal()
	local currentGold = ShopController.getGold()
	if currentGold <= 0 then
		UIManager.notify("드랍할 골드가 없습니다.", C.RED)
		return
	end

	modalActionType = "DROP_GOLD"
	openCountModal("드랍할 골드", currentGold)
end

function UIManager.openStorageGoldModal(sourceType)
	if not currentStorageData then
		return
	end

	if sourceType == "player" then
		local currentGold = ShopController.getGold()
		if currentGold <= 0 then
			UIManager.notify("보관할 골드가 없습니다.", C.RED)
			return
		end
		modalActionType = "STORAGE_DEPOSIT_GOLD"
		openCountModal("보관할 골드", currentGold)
	else
		local storageGold = tonumber(currentStorageData.gold) or 0
		if storageGold <= 0 then
			UIManager.notify("인출할 골드가 없습니다.", C.RED)
			return
		end
		modalActionType = "STORAGE_WITHDRAW_GOLD"
		openCountModal("인출할 골드", storageGold)
	end
end

function UIManager.openSplitModal()
	if not selectedInvSlot then return end
	local item = InventoryController.getSlot(selectedInvSlot)
	if not item or not item.count or item.count <= 1 then return end
	
	modalActionType = "SPLIT"
	
	openCountModal("수량 입력", math.floor(item.count / 2))
	InventoryUI.Refs.DropModal.MaxLabel.Text = "(최대: " .. (item.count - 1) .. ")"
end

function UIManager.getSelectedInvSlot()
	return selectedInvSlot
end

function UIManager.confirmModalAction(count)
	if modalActionType == "DROP_GOLD" then
		local currentGold = ShopController.getGold()
		local validCount = math.max(1, math.min(count, currentGold))
		InventoryController.requestDropGold(validCount)
		InventoryUI.Refs.DropModal.Frame.Visible = false
		return
	end

	if modalActionType == "STORAGE_DEPOSIT_GOLD" then
		local currentGold = ShopController.getGold()
		local validCount = math.max(1, math.min(count, currentGold))
		StorageController.moveGold("player", validCount)
		InventoryUI.Refs.DropModal.Frame.Visible = false
		return
	end

	if modalActionType == "STORAGE_WITHDRAW_GOLD" then
		local storageGold = currentStorageData and (tonumber(currentStorageData.gold) or 0) or 0
		local validCount = math.max(1, math.min(count, storageGold))
		StorageController.moveGold("storage", validCount)
		InventoryUI.Refs.DropModal.Frame.Visible = false
		return
	end

	if not selectedInvSlot then return end
	local item = InventoryController.getSlot(selectedInvSlot)
	if not item then return end
	
	if modalActionType == "DROP" then
		-- 동일 itemId 총 개수 기준으로 벌크 드랍
		local totalCount = 0
		local items = InventoryController.getItems()
		for _, slotData in pairs(items) do
			if slotData and slotData.itemId == item.itemId then
				totalCount = totalCount + (slotData.count or 1)
			end
		end
		if totalCount < 1 then totalCount = 1 end
		
		local validCount = math.max(1, math.min(count, totalCount))
		InventoryController.requestDropByItemId(item.itemId, validCount)
	elseif modalActionType == "SPLIT" then
		local maxCount = (item.count or 1) - 1
		if maxCount >= 1 then
			local validCount = math.max(1, math.min(count, maxCount))
			-- Find empty slot
			local emptySlot = nil
			local items = InventoryController.getItems()
			for i=1, Balance.MAX_INV_SLOTS do
				if not items[i] then emptySlot = i; break end
			end
			if emptySlot then
				task.spawn(function()
					NetClient.Request("Inventory.Split.Request", {
						fromSlot = selectedInvSlot,
						toSlot = emptySlot,
						count = validCount
					})
				end)
			else
				UIManager.notify("빈 슬롯이 없습니다.", C.RED)
			end
		end
	end
	
	InventoryUI.Refs.DropModal.Frame.Visible = false
end

function UIManager._onInvSlotClick(idx)
	if not WindowManager.isOpen("INV") then return end
	selectedInvSlot = idx
	local items = InventoryController.getItems()
	local data = items[idx]
	InventoryUI.UpdateDetail(data, getItemIcon, Enums, DataHelper)
	InventoryUI.UpdateSlotSelectionHighlight(idx, items, DataHelper)
end

function UIManager.onInventorySlotClick(idx)
	UIManager._onInvSlotClick(idx)
end

function UIManager._onInvSlotDoubleClick(idx)
	local items = InventoryController.getItems()
	local item = items[idx]
	if not item or not item.itemId then return end
	
	local itemData = DataHelper.GetData("ItemData", item.itemId)
	if not itemData then return end
	
	if itemData.type == "ARMOR" then
		local slot = itemData.slot and itemData.slot:upper() or nil
		if slot ~= "HEAD" and slot ~= "SUIT" then
			UIManager.notify("장착 가능한 방어구가 아닙니다.", C.RED)
			return
		end
		InventoryController.requestEquip(idx, slot)
	elseif itemData.type == "TOOL" or itemData.type == "WEAPON" then
		UIManager.notify("무기/도구는 핫바(1~8)를 통해 장착하세요.", C.YELLOW)
	elseif itemData.type == "FOOD" or itemData.type == "CONSUMABLE" then
		InventoryController.requestUse(idx)
	end
end

function UIManager.onUseItem()
	if not selectedInvSlot then return end
	local item = InventoryController.getSlot(selectedInvSlot)
	if not item or not item.itemId then return end

	local itemData = DataHelper.GetData("ItemData", item.itemId)
	if not itemData then return end

	if itemData.type == "ARMOR" or itemData.type == "TOOL" or itemData.type == "WEAPON" then
		local slot = itemData.slot and itemData.slot:upper() or nil
		if itemData.type == "ARMOR" then
			if slot ~= "HEAD" and slot ~= "SUIT" then
				UIManager.notify("방어구 슬롯 정보가 올바르지 않습니다.", C.RED)
				return
			end
		end
		if not slot then
			slot = "HAND"
		end
		InventoryController.requestEquip(selectedInvSlot, slot)
		return
	end

	InventoryController.requestUse(selectedInvSlot)
end

function UIManager.onInventorySlotRightClick(idx)
	if not WindowManager.isOpen("INV") or not idx then return end
	-- 클릭 효과를 위해 좌클릭 선택 로직 선행 실행 (옵션)
	UIManager._onInvSlotClick(idx)
	-- 실제 사용 요청
	InventoryController.requestUse(idx)
end

----------------------------------------------------------------
-- Public API: Crafting
----------------------------------------------------------------
--- [수정] C키는 건축(건물을 짓는 행위) 전용입니다.
function UIManager.openCrafting(mode)
	UIManager.openBuild()
end

function UIManager.toggleCrafting()
	UIManager.toggleBuild()
end

function UIManager.closeCrafting()
	UIManager.closeBuild()
end

--- [제거] 작업대라는 개념은 존재하지 않습니다. 모든 아이템 제작은 인벤토리에서 진행됩니다.
function UIManager.openWorkbench(structureId, facilityId)
	UIManager.notify("시설에 접근했습니다. (제작은 인벤토리[I]에서 가능합니다)", C.GOLD)
end

-- [Legacy] Removed refreshCrafting and _onCraftSlotClick as all logic moved to refreshPersonalCrafting.

-- 재료 체크 헬퍼
function UIManager.checkMaterials(item, playerItemCounts)
	playerItemCounts = playerItemCounts or InventoryController.getItemCounts()
	local inputs = item.inputs or item.requirements
	if not inputs then return true, "" end

	-- alternateWoodIds 집합 생성
	local altSet = {}
	local altList = item.alternateWoodIds
	if altList then
		for _, id in ipairs(altList) do
			altSet[id] = true
		end
	end

	local missing = {}
	for _, inp in ipairs(inputs) do
		local reqId = inp.itemId or inp.id
		local req = inp.count or inp.amount or 0

		if altSet[reqId] and altList then
			-- 대체 재료 중 하나라도 충분하면 OK
			local found = false
			for _, altId in ipairs(altList) do
				if (playerItemCounts[altId] or 0) >= req then
					found = true
					break
				end
			end
			if not found then
				local itemName = reqId
				local itemData = DataHelper.GetData("ItemData", itemName)
				if itemData then itemName = itemData.name end
				table.insert(missing, string.format("%s (%d/%d)", itemName, playerItemCounts[reqId] or 0, req))
			end
		else
			local have = playerItemCounts[reqId] or 0
			if have < req then
				local itemName = reqId
				local itemData = DataHelper.GetData("ItemData", itemName)
				if itemData then itemName = itemData.name end
				table.insert(missing, string.format("%s (%d/%d)", itemName, have, req))
			end
		end
	end

	if #missing > 0 then
		return false, "부족한 재료: " .. table.concat(missing, ", ")
	end
	return true, ""
end

----------------------------------------------------------------
-- Personal Crafting (Inventory Tab)
----------------------------------------------------------------
function UIManager.refreshPersonalCrafting(forceRefresh)
	if not invPersonalCraftGrid then return end
	
	if forceRefresh or not cachedPersonalRecipes then
		for _, ch in pairs(invPersonalCraftGrid:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
		personalCraftNodes = {}; selectedPersonalRecipeId = nil
		
		-- [수정] 인벤토리 제작탭은 '아이템 레시피'만 표시합니다.
		local allRecipes = require(ReplicatedStorage.Data.RecipeData)
		cachedPersonalRecipes = {}
		
		for _, recipe in ipairs(allRecipes) do
			-- [필터] 인벤토리 제작탭은 시설이 필요 없는(Hand Craft) 레시피만 보여줍니다.
			if not recipe.requiredFacility then
				local r = table.clone(recipe)
				r._isFacility = false
				table.insert(cachedPersonalRecipes, r)
			end
		end
		
		table.sort(cachedPersonalRecipes, function(a, b) 
			local lvA = a.techLevel or 0
			local lvB = b.techLevel or 0
			if lvA ~= lvB then return lvA < lvB end
			return (a.name or "") < (b.name or "")
		end)
	end

	local gridLayout = invPersonalCraftGrid:FindFirstChildOfClass("UIGridLayout")
	if not gridLayout then
		gridLayout = Instance.new("UIGridLayout")
		local sSize = isMobile and 64 or 56
		gridLayout.CellSize = UDim2.new(0, sSize, 0, sSize)
		gridLayout.CellPadding = UDim2.new(0, 10, 0, 10)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.Parent = invPersonalCraftGrid
		
		local uiPadding = Instance.new("UIPadding")
		uiPadding.PaddingLeft = UDim.new(0, 4)
		uiPadding.PaddingTop = UDim.new(0, 4)
		uiPadding.Parent = invPersonalCraftGrid
	end
	
	invPersonalCraftGrid.ClipsDescendants = true

	local function updateNodes(recipes)
		local playerItemCounts = InventoryController.getItemCounts()
		
		for _, recipe in ipairs(recipes) do
			local isLocked = not TechController.isRecipeUnlocked(recipe.id) -- TechController 사용
			local canCraft, _ = UIManager.checkMaterials(recipe)
			local node = personalCraftNodes[recipe.id]
			
			if not node then
				local nodeCount = 0
				for _ in pairs(personalCraftNodes) do nodeCount = nodeCount + 1 end
				local idx = nodeCount + 1
				local nf = mkFrame({
					name="PNode"..idx,
					size=UDim2.new(1,0,1,0),
					bg=C.BG_SLOT,
					bgT=0.3,
					r=0,
					stroke=1,
					strokeC=isLocked and C.DIM or C.BORDER_DIM,
					z=12,
					parent=invPersonalCraftGrid
				})
				
				local icon = Instance.new("ImageLabel")
				icon.Name="Icon"; icon.Size=UDim2.new(0.7,0,0.7,0); icon.Position=UDim2.new(0.5,0,0.5,0)
				icon.AnchorPoint=Vector2.new(0.5,0.5); icon.BackgroundTransparency=1; icon.ScaleType=Enum.ScaleType.Fit; icon.ZIndex=13; icon.Parent=nf
				
				-- Priority: Output item icon > Recipe ID icon
				local iconId = ""
				if recipe.outputs and recipe.outputs[1] then
					iconId = getItemIcon(recipe.outputs[1].itemId)
				end
				if iconId == "" then
					local ridIcon = getItemIcon(recipe.id)
					if ridIcon ~= "" then iconId = ridIcon end
				end
				icon.Image = iconId
				
				local iconLbl = mkLabel({text=recipe.name, size=UDim2.new(0.9,0,0.9,0), pos=UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5), ts=8, color=C.WHITE, wrap=true, z=14, parent=nf})
				iconLbl.Visible = (iconId == "")

				local lockBG = mkFrame({name="LockBG", size=UDim2.new(1,0,1,0), bg=Color3.new(0.1,0.1,0.1), bgT=0.5, r=0, z=20, parent=nf})
				local lockIcon = Instance.new("ImageLabel")
				lockIcon.Name = "LockIcon"; lockIcon.Size = UDim2.new(0.5,0,0.5,0); lockIcon.Position = UDim2.new(0.5,0,0.5,0)
				lockIcon.AnchorPoint = Vector2.new(0.5,0.5); lockIcon.BackgroundTransparency = 1; lockIcon.ZIndex = 21
				lockIcon.Image = "rbxassetid://6031084651"; lockIcon.ImageColor3 = Color3.new(1,1,1); lockIcon.Parent = lockBG
				
				local btn = mkBtn({name="B", size=UDim2.new(1,0,1,0), bgT=1, z=25, parent=nf})
				btn.MouseButton1Click:Connect(function()
				selectedPersonalRecipeId = recipe.id
					UIManager.refreshPersonalCrafting() -- Refresh strokes
					UIManager._updatePersonalCraftDetail(recipe)
				end)
				
				node = {frame=nf, icon=icon, lockBG=lockBG, nameLabel=iconLbl, recipe=recipe}
				personalCraftNodes[recipe.id] = node
			end
			
			-- Update visual state
			local nf = node.frame
			local icon = node.icon
			local lockBG = node.lockBG
			local st = nf:FindFirstChildOfClass("UIStroke")
			
			if isLocked then
				icon.ImageColor3 = Color3.fromRGB(100,100,100)
				nf.BackgroundColor3 = C.BG_DARK
				nf.BackgroundTransparency = 0.8
				lockBG.Visible = true
				if st then st.Color = (recipe.id == selectedPersonalRecipeId) and C.GOLD or C.DIM end
			else
				lockBG.Visible = false
				nf.BackgroundTransparency = T.SLOT
				if canCraft then
					icon.ImageColor3 = Color3.new(1,1,1)
					nf.BackgroundColor3 = Color3.fromRGB(45, 65, 45) -- Subtle Green Hint
				else
					icon.ImageColor3 = Color3.fromRGB(150,150,150)
					nf.BackgroundColor3 = C.BG_SLOT
				end
				if st then 
					st.Color = (recipe.id == selectedPersonalRecipeId) and C.GOLD or C.BORDER 
					st.Thickness = (recipe.id == selectedPersonalRecipeId) and 2.5 or 1.5
				end
			end
		end
		
		local rows = math.ceil(#recipes / 4)
		local sSize = isMobile and 64 or 56
		invPersonalCraftGrid.CanvasSize = UDim2.new(0, 0, 0, rows * (sSize + 10) + 10)
	end

	updateNodes(cachedPersonalRecipes)
end

function UIManager._updatePersonalCraftDetail(recipe)
	if not recipe then 
		InventoryUI.UpdateDetail(nil)
		return 
	end
	
	local isLocked = not TechController.isRecipeUnlocked(recipe.id) -- TechController 사용
	
	-- InventoryUI의 공통 UpdateDetail을 사용하여 통일성 및 버그 방지
	InventoryUI.UpdateDetail(recipe, getItemIcon, Enums, DataHelper, InventoryController.getItemCounts(), isLocked)
	
	-- 제작 진행률 UI 초기화 (이전 진행률 잔상 제거)
	local refs = InventoryUI.Refs.Detail
	if refs and refs.ProgFill then
		refs.ProgFill.Size = UDim2.new(0,0,1,0)
		if refs.ProgWrap then refs.ProgWrap.Visible = false end
		if refs.ProgBar then refs.ProgBar.Visible = false end
	end
end

-- [추가] 풀스크린 제작 메뉴용 클라이언트 액션 (CraftingUI 호출용)
function UIManager._onCraftSlotClick(recipe, mode)
	if not recipe then return end
	
	-- 전역 선택 ID 동기화
	selectedPersonalRecipeId = recipe.id
	
	local playerItemCounts = InventoryController.getItemCounts()
	local isLocked = not TechController.isRecipeUnlocked(recipe.id) -- TechController 사용
	local canMake, _ = UIManager.checkMaterials(recipe, playerItemCounts)
	
	-- 풀스크린 상세창 업데이트
	CraftingUI.UpdateDetail(recipe, mode, isLocked, canMake, playerItemCounts, DataHelper, getItemIcon)
	
	-- 인벤토리 상세창도 만약 열려있다면 동기화
	if WindowManager.isOpen("INV") then
		UIManager._updatePersonalCraftDetail(recipe)
	end
end

local isCrafting = false
local spinnerTween = nil
local progConn = nil

function UIManager.isCrafting()
	-- 상호작용 차단은 제작 UI가 열린 상태에서만 적용
	return isCrafting and (WindowManager.isOpen("INV") or WindowManager.isOpen("CRAFT"))
end

function UIManager.showCraftingProgress(duration)
	if isCrafting then return end
	isCrafting = true
	
	-- 1. 상단 채집바 표시 (사용자 요청으로 제거: UI 내부 바 사용)
	-- HUDUI.ShowHarvestProgress(duration, "제작 중...")
	
	-- 2. 상세 정보창 내부 진행률 표시 (돌아가는 표시)
	local isInvOpen = WindowManager.isOpen("INV")
	local isCraftOpen = WindowManager.isOpen("CRAFT")
	local refs = (isInvOpen and InventoryUI.Refs.Detail) or (isCraftOpen and CraftingUI.Refs.Detail)
	
	if refs and refs.ProgWrap then
		refs.ProgWrap.Visible = true
		if refs.ProgBar then refs.ProgBar.Visible = true end
		
		-- 스피너 회전 루프 (Durango 스타일)
		if spinnerTween then spinnerTween:Cancel() end
		if refs.Spinner then
			refs.Spinner.Rotation = 0
			spinnerTween = TweenService:Create(refs.Spinner, TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), {Rotation = 360})
			spinnerTween:Play()
		end
		
		-- 프로그레스바 루프
		if progConn then progConn:Disconnect() end
		local start = tick()
		progConn = RunService.RenderStepped:Connect(function()
			local p = math.clamp((tick() - start) / duration, 0, 1)
			if refs.ProgFill then refs.ProgFill.Size = UDim2.new(p, 0, 1, 0) end
		end)
	end
end

function UIManager.stopCraftingProgress()
	isCrafting = false
	HUDUI.HideHarvestProgress()
	
	if spinnerTween then spinnerTween:Cancel(); spinnerTween = nil end
	if progConn then progConn:Disconnect(); progConn = nil end
	
	local isInvOpen = WindowManager.isOpen("INV")
	local isCraftOpen = WindowManager.isOpen("CRAFT")
	local refs = (isInvOpen and InventoryUI.Refs.Detail) or (isCraftOpen and CraftingUI.Refs.Detail)
	if refs and refs.ProgWrap then
		refs.ProgWrap.Visible = false
		if refs.ProgBar then refs.ProgBar.Visible = false end
	end
end

function UIManager._doCraft()
	local isInvOpen = WindowManager.isOpen("INV")
	local isCraftOpen = WindowManager.isOpen("CRAFT")
	
	-- 1. 인벤토리 내 제작 탭 처리 (아이템 제작 전용)
	if isInvOpen and invCraftContainer and invCraftContainer.Visible then
		if not selectedPersonalRecipeId then return end
		
		local recipe = nil
		for _, r in ipairs(cachedPersonalRecipes or {}) do
			if r.id == selectedPersonalRecipeId then recipe = r; break end
		end
		if not recipe then return end

		-- [기술 잠금 체크] - 임시 비활성화 (전면 삭제 요청)
		-- if not TechController.isRecipeUnlocked(recipe.id) then
		-- 	UIManager.notify("기술 해금이 필요합니다.", C.RED)
		-- 	return
		-- end

		-- 재료 체크
		local ok, msg = UIManager.checkMaterials(recipe)
		if not ok then UIManager.notify(msg, C.RED); return end

		-- 제작 프로세스 시작
		local craftTime = recipe.craftTime or 3
		UIManager.showCraftingProgress(craftTime)
		
		task.spawn(function()
			local resultOk, response = NetClient.Request("Craft.Start.Request", {
				recipeId = selectedPersonalRecipeId
			})
			
			if resultOk then
				if response and response.instant then
					UIManager.stopCraftingProgress()
					local craftedName = UILocalizer.LocalizeDataText("RecipeData", tostring(recipe.id or ""), "name", recipe.name or "아이템")
					UIManager.notify(craftedName .. " 제작 완료!", C.GREEN)
					UIManager.refreshInventory()
					UIManager.refreshPersonalCrafting() 
				else
					-- 큐 등록형 제작은 즉시 진행 UI를 해제하여 상호작용 잠금이 남지 않게 함
					UIManager.stopCraftingProgress()
					UIManager.notify("제작 의뢰 완료!", C.GOLD)
				end
			else
				UIManager.stopCraftingProgress()
				UIManager.notify(friendlyError(response, "제작"), C.RED)
			end
		end)
		return
	end

	-- 2. 풀스크린 제작 메뉴 처리 (시설 제작 또는 건축)
	if isCraftOpen then
		if not selectedPersonalRecipeId then return end
		-- 현재 풀스크린 제작 메뉴에서도 selectedPersonalRecipeId를 공유하거나, 
		-- CraftingUI에서 관리하는 별도의 변수가 필요할 수 있음. 
		-- 일단 로직 흐름상 동일 변수 사용 가정.
		
		local recipe = DataHelper.GetData("RecipeData", selectedPersonalRecipeId)
		if not recipe then return end

		-- [기술 잠금 체크]
		if not TechController.isRecipeUnlocked(recipe.id) then
			UIManager.notify("기술 해금이 필요합니다.", C.RED)
			return
		end
		
		-- 재료 체크
		local ok, msg = UIManager.checkMaterials(recipe)
		if not ok then UIManager.notify(msg, C.RED); return end
		
		local craftTime = recipe.craftTime or 3
		UIManager.showCraftingProgress(craftTime)
		
		task.spawn(function()
			local resultOk, response = NetClient.Request("Craft.Start.Request", {
				recipeId = selectedPersonalRecipeId,
				structureId = currentFacilityStructureId
			})
			
			if resultOk then
				if response and response.instant then
					UIManager.stopCraftingProgress()
					UIManager.refreshInventory()
					if currentFacilityStructureId then
						UIManager.refreshFacilityCrafting(currentFacilityStructureId)
					end
				else
					-- 맡김 제작(비즉시)은 요청 승인 후 진행바 잠금 해제
					UIManager.stopCraftingProgress()
					UIManager.notify("제작 의뢰 완료!", C.GOLD)
				end
			else
				UIManager.stopCraftingProgress()
				UIManager.notify(friendlyError(response, "제작"), C.RED)
			end
		end)
	end
end

----------------------------------------------------------------
-- Public API: Shop
----------------------------------------------------------------
function UIManager.openShop(shopId)
	WindowManager.open("SHOP", shopId)
end

function UIManager.openQuestList(npcModel)
	QuestUI:Open(npcModel)
end

function UIManager._onOpenShop(shopId)
	activeShopId = shopId
	ShopUI.SetVisible(true)
	updateUIMode()
	
	ShopController.requestShopInfo(shopId, function(ok, shopInfo)
		if ok then
			UIManager.refreshShop(shopId)
		end
	end)
end

function UIManager.closeShop()
	WindowManager.close("SHOP")
end

function UIManager._onCloseShop()
	activeShopId = nil
	ShopUI.SetVisible(false)
end

function UIManager.refreshShop(shopId)
	local sid = shopId or activeShopId
	local shopInfo = ShopController.getShopInfo(sid)
	local playerItems = InventoryController.getItems()
	local gold = ShopController.getGold()
	
	ShopUI.UpdateGold(gold)
	ShopUI.Refresh(shopInfo, playerItems, getItemIcon, C, UIManager)
end

function UIManager.requestBuy(itemId, count)
	ShopController.requestBuy(activeShopId, itemId, count or 1, function(ok, err)
		if ok then
			UIManager.notify("구매 완료!", C.GOLD)
			UIManager.refreshShop()
		else
			UIManager.notify(friendlyError(err, "구매"), C.RED)
		end
	end)
end

function UIManager.requestSell(slotIdx, count)
	ShopController.requestSell(activeShopId, slotIdx, count or 1, function(ok, err)
		if ok then
			UIManager.notify("판매 완료!", C.GOLD)
			UIManager.refreshShop()
		else
			UIManager.notify(friendlyError(err, "판매"), C.RED)
		end
	end)
end

----------------------------------------------------------------
-- Public API: Build (건축 설계도)
----------------------------------------------------------------
function UIManager.openBuild()
	WindowManager.open("BUILD")
end

function UIManager._onOpenBuild()
	BuildUI.Refs.Frame.Visible = true
	updateUIMode()
	
	if not WindowManager.isOpen("CRAFT") then
		blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	end
	
	UIManager.refreshBuild()
end

function UIManager.closeBuild()
	WindowManager.close("BUILD")
end

function UIManager._onCloseBuild()
	if blurEffect and not WindowManager.isOpen("CRAFT") then blurEffect:Destroy(); blurEffect = nil end
	BuildUI.Refs.Frame.Visible = false
end

function UIManager.toggleBuild()
	WindowManager.toggle("BUILD")
end

function UIManager.refreshBuild()
	local allFacilities = require(ReplicatedStorage.Data.FacilityData)

	-- buildTier 기반 필터링 (선택된 카테고리의 시설만 표시)
	local list = {}
	for _, f in pairs(allFacilities) do
		if f.buildTier == selectedBuildCat then
			local fData = table.clone(f)
			-- 해당 티어 스킬 해금 여부에 따라 잠금 상태 설정
			fData.isLocked = not SkillController.isSkillUnlocked(selectedBuildCat)
			table.insert(list, fData)
		end
	end

	-- 스킬 해금 체크 함수를 BuildUI에 전달
	local function isTierUnlocked(skillId)
		return SkillController.isSkillUnlocked(skillId)
	end

	BuildUI.Refresh(list, {}, selectedBuildCat, UIManager.getItemIcon, UIManager, isTierUnlocked)
end

----------------------------------------------------------------
-- Storage UI
----------------------------------------------------------------

function UIManager.openStorage(storageId, data)
	WindowManager.open("STORAGE", storageId, data)
end

function UIManager._onOpenStorage(storageId, data)
	currentStorageData = data
	hoveredStorageSlotInfo = nil
	StorageUI.Refs.Frame.Visible = true
	updateUIMode()
	
	if not blurEffect then
		blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	end
	
	ShopController.requestGold(function()
		if WindowManager.isOpen("STORAGE") then
			UIManager.refreshStorage()
		end
	end)

	UIManager.refreshStorage()
end

function UIManager.closeStorage()
	WindowManager.close("STORAGE")
end

function UIManager._onCloseStorage()
	if blurEffect then blurEffect:Destroy(); blurEffect = nil end
	currentStorageData = nil
	hoveredStorageSlotInfo = nil
	StorageUI.Refs.Frame.Visible = false
	-- 서버에 닫기 요청
	StorageController.closeStorage()
end

function UIManager.refreshStorage()
	if not WindowManager.isOpen("STORAGE") or not currentStorageData then return end
	
	local invData = InventoryController.getItems()
	local playerGold = ShopController.getGold()
	local _, inventoryMaxSlots = InventoryController.getSlotInfo()
	StorageUI.Refresh(currentStorageData, invData, playerGold, UIManager.getItemIcon, UIManager, inventoryMaxSlots)
end

function UIManager._onStorageSlotClick(slot, fromType)
	StorageController.moveItem(slot, fromType)
end

function UIManager.onStorageSlotHover(slot, fromType, isHovering)
	if not isHovering then
		hoveredStorageSlotInfo = nil
		StorageUI.HideTooltip()
		return
	end

	if fromType == "storage" then
		hoveredStorageSlotInfo = StorageController.getStorageSlot(slot)
	else
		local item = InventoryController.getSlot(slot)
		hoveredStorageSlotInfo = item and table.clone(item) or nil
	end

	StorageUI.ShowTooltip(hoveredStorageSlotInfo)
end

function UIManager.getHoveredStorageSlotInfo()
	return hoveredStorageSlotInfo
end

function UIManager.handleStorageDragStart(slot, fromType)
	DragDropController.handleDragStart(slot, fromType, "storage")
end

function UIManager.getStorageSlots()
	return StorageUI.Refs.StorageSlots
end

function UIManager.getStorageInventorySlots()
	return StorageUI.Refs.InventorySlots
end

function UIManager.getStorageDragItem(slot, fromType)
	if fromType == "storage" then
		return StorageController.getStorageSlot(slot)
	end
	return InventoryController.getSlot(slot)
end

function UIManager.moveStorageItem(sourceSlot, sourceType, targetSlot, targetType)
	StorageController.moveItem(sourceSlot, sourceType, targetSlot, targetType)
end

function UIManager.requestStorageGoldMove(sourceType)
	if not currentStorageData then return end

	if sourceType == "player" then
		local amount = ShopController.getGold()
		if amount <= 0 then
			UIManager.notify("보관할 골드가 없습니다.", C.RED)
			return
		end
		UIManager.openStorageGoldModal("player")
	else
		local amount = tonumber(currentStorageData.gold) or 0
		if amount <= 0 then
			UIManager.notify("인출할 골드가 없습니다.", C.RED)
			return
		end
		UIManager.openStorageGoldModal("storage")
	end
end

----------------------------------------------------------------
-- Facility UI
----------------------------------------------------------------

function UIManager.openFacility(structureId, data)
	WindowManager.open("FACILITY", structureId, data)
end

function UIManager._onOpenFacility(structureId, data)
	currentFacilityStructureId = structureId
	local fId = data and data.facilityId
	currentFacilityId = fId
	currentFacilityType = data and data.functionType or (fId and DataHelper.GetData("FacilityData", fId) and DataHelper.GetData("FacilityData", fId).functionType)
	selectedFacilityRecipe = nil
	
	FacilityUI.SetVisible(true)
	updateUIMode()

	if FacilityUI.Refs and FacilityUI.Refs.Title then
		if currentFacilityType == "CRAFTING_T1" then
			if currentFacilityId == "NOVICE_WORKBENCH" then
				FacilityUI.Refs.Title.Text = UILocalizer.Localize("초급 작업대 제작 / 나무 블럭가공")
			else
				FacilityUI.Refs.Title.Text = UILocalizer.Localize("기초 작업대 제작 / 나무 블럭가공")
			end
		elseif currentFacilityType == "CRAFTING_T2" then
			FacilityUI.Refs.Title.Text = UILocalizer.Localize("청동기 작업대 제작 / 뼈 및 금속 가공")
		elseif currentFacilityType == "CRAFTING_T3" then
			FacilityUI.Refs.Title.Text = UILocalizer.Localize("철기 작업대 제작")
		elseif currentFacilityType == "COOKING" then
			FacilityUI.Refs.Title.Text = UILocalizer.Localize("요리")
		elseif currentFacilityType and string.find(currentFacilityType, "SMELTING") then
			if currentFacilityId == "STONE_FURNACE" then
				FacilityUI.Refs.Title.Text = UILocalizer.Localize("제련 및 요리")
			else
				FacilityUI.Refs.Title.Text = UILocalizer.Localize("제련")
			end
		else
			FacilityUI.Refs.Title.Text = UILocalizer.Localize("제작")
		end
	end
	
	-- [추가] 초기 내구도 정보 반영
	if data and data.health and data.maxHealth then
		FacilityUI.UpdateHealth(data.health, data.maxHealth)
	end
	
	if not blurEffect then
		blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	end
	
	-- [추가] 시설 유형에 맞는 탭 구성
	if FacilityUI.SetupTabs then
		FacilityUI.SetupTabs(currentFacilityType or "", currentFacilityId or "")
	end
	
	UIManager.refreshFacility()
end

function UIManager._onCraftUpdate()
	if WindowManager.isOpen("FACILITY") then
		UIManager.refreshFacility()
	end
end

function UIManager.closeFacility()
	WindowManager.close("FACILITY")
end

function UIManager._onCloseFacility()
	if blurEffect then blurEffect:Destroy(); blurEffect = nil end
	currentFacilityStructureId = nil
	currentFacilityType = nil
	currentFacilityId = nil
	selectedFacilityRecipe = nil
	FacilityUI.SetVisible(false)
	FacilityController.closeFacility()
end

----------------------------------------------------------------
-- Totem UI
----------------------------------------------------------------

function UIManager.openTotem(structureId, data)
	WindowManager.open("TOTEM", structureId, data)
end

function UIManager._onOpenTotem(structureId, data)
	currentTotemStructureId = structureId
	TotemUI.SetVisible(true)
	updateUIMode()

	if not blurEffect then
		blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	end

	if data then
		TotemUI.Refresh(data)
	else
		UIManager.refreshTotem()
	end
end

function UIManager.closeTotem()
	WindowManager.close("TOTEM")
end

function UIManager._onCloseTotem()
	if blurEffect then blurEffect:Destroy(); blurEffect = nil end
	currentTotemStructureId = nil
	TotemUI.SetVisible(false)
end

function UIManager.refreshTotem()
	if not currentTotemStructureId then
		return
	end
	local TotemController = require(Controllers.TotemController)
	TotemController.refreshInfo(currentTotemStructureId, function(ok, data)
		if ok and type(data) == "table" then
			TotemUI.Refresh(data)
		end
	end)
end

function UIManager.requestTotemPay(days)
	if not currentTotemStructureId then
		UIManager.notify("토템 정보를 먼저 열어주세요.", C.RED)
		return
	end

	local TotemController = require(Controllers.TotemController)
	TotemController.requestPay(days, function(ok, data)
		if ok then
			TotemUI.Refresh(data)
			UIManager.notify(string.format("유지비 결제 완료: %d일 연장", days), C.GOLD)
		else
			local code = tostring(data)
			UIManager.notify(friendlyError(code, "유지비 결제"), C.RED)
		end
	end)
end

function UIManager.requestTotemExpand(direction)
	if not currentTotemStructureId then
		UIManager.notify("토템 정보를 먼저 열어주세요.", C.RED)
		return
	end

	local directionNames = {
		NORTH = "북쪽",
		SOUTH = "남쪽",
		EAST = "동쪽",
		WEST = "서쪽",
	}

	local TotemController = require(Controllers.TotemController)
	TotemController.requestExpand(direction, function(ok, data)
		if ok then
			TotemUI.Refresh(data)
			UIManager.notify((directionNames[direction] or "선택한 방향") .. " 영토를 확장했습니다.", C.GOLD)
		else
			local code = tostring(data)
			UIManager.notify(friendlyError(code, "영토 확장"), C.RED)
		end
	end)
end

function UIManager.highlightTotemZone()
	local TotemController = require(Controllers.TotemController)
	TotemController.flashPreview()
	UIManager.notify("영역 효과 범위를 확인하세요.", C.WHITE)
end

----------------------------------------------------------------
-- Portal UI (Radial Menu)
----------------------------------------------------------------

function UIManager.openPortalRadial(status)
	WindowManager.open("PORTAL_RADIAL", status)
end

function UIManager.closePortalRadial()
	WindowManager.close("PORTAL_RADIAL")
end

function UIManager._onOpenPortal(data)
	UIManager.openPortalRadial(data)
end

function UIManager._onClosePortal()
	UIManager.closePortalRadial()
end

function UIManager.refreshPortal(newData)
	PortalUI.Refresh(newData)
end

function UIManager.openPortalGoldInput(data)
	PortalUI.SetData(data)
	PortalUI.SetVisible(true)
end

function UIManager.requestPortalDeposit(itemId, amount)
	-- itemId가 nil 또는 빈 문자열이면 골드로 취급
	local ok, data = NetClient.Request("Portal.Deposit.Request", {
		itemId = itemId,
		amount = amount
	})
	if ok then
		PortalUI.Refresh(data)
		if data and data.repaired then
			UIManager.notify("🌀 고대 포탈이 수리되었습니다!", Color3.fromRGB(255, 200, 0))
		end
	else
		UIManager.notify(friendlyError(data, "포탈 활성화"), C.RED)
	end
end

function UIManager.sortInventory()
	InventoryController.requestSort()
end

function UIManager.requestPortalTeleport()
	local ok, err = NetClient.Request("Portal.Teleport.Request", {})
	if not ok then
		if err == "OUT_OF_RANGE" then
			UIManager.sideNotify("❌ 포탈에 더 가까이 접근해야 합니다.", C.RED)
		else
			warn("[UIManager] Portal teleport failed:", err)
			UIManager.sideNotify("❌ 포탈을 이용할 수 없습니다. 다시 시도해주세요.", C.RED)
		end
	end
end



-- ============ Skill Tree ============
function UIManager._onOpenSkillTree()
	if not blurEffect and not WindowManager.isOpen("INV") then
		blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	end
	-- 열 때마다 서버에서 최신 스킬 데이터 재요청 (SP 소급 반영)
	SkillController.requestData()
	SkillTreeUI.SetVisible(true)
end

function UIManager._onCloseSkillTree()
	if blurEffect and not WindowManager.isAnyOpen() then blurEffect:Destroy(); blurEffect = nil end
	SkillTreeUI.SetVisible(false)
end

function UIManager.toggleSkillTree()
	WindowManager.toggle("SKILL")
end

function UIManager.refreshFacility()
	if not currentFacilityType then return end
	
	task.spawn(function()
		local function recipeMatchesFacilityId(recipe, facilityId)
			local allowedFacilityIds = recipe and recipe.allowedFacilityIds
			if type(allowedFacilityIds) ~= "table" or #allowedFacilityIds == 0 then
				return true
			end
			if not facilityId then
				return false
			end
			for _, allowedId in ipairs(allowedFacilityIds) do
				if allowedId == facilityId then
					return true
				end
			end
			return false
		end

		-- 1. Get recipes
		local allRecipes = require(ReplicatedStorage.Data.RecipeData)
		local recipes = {}
		for _, r in pairs(allRecipes) do
			local typeMatch = (r.requiredFacility == currentFacilityType)
			local idMatch = false
			if r.allowedFacilityIds then
				for _, aid in ipairs(r.allowedFacilityIds) do
					if aid == currentFacilityId then idMatch = true; break end
				end
			end

			-- 타입이 일치하고 ID 제약이 없거나 일치할 때, OR ID가 명시적으로 허용되었을 때
			if (typeMatch and recipeMatchesFacilityId(r, currentFacilityId)) or idMatch then
				local buildSkillId = r.buildSkillId
				if not buildSkillId or SkillController.isSkillUnlocked(buildSkillId) then
					table.insert(recipes, r)
				end
			end
		end

		if currentFacilityType == "CRAFTING_T1" then
			local pinnedOrder
			if currentFacilityId == "NOVICE_WORKBENCH" then
				pinnedOrder = {
					CRAFT_SPLIT_LOG_TO_PLANK = 1,
					CRAFT_SPLIT_PALM_LOG_TO_PLANK = 2,
					CRAFT_LOG_BLOCK = 3,
					CRAFT_PALM_BLOCK = 4,
					CRAFT_REED_BLOCK = 5,
					CRAFT_OBSIDIAN_AXE = 6,
					CRAFT_OBSIDIAN_PICKAXE = 7,
					CRAFT_OBSIDIAN_SWORD = 8,
					CRAFT_OBSIDIAN_BOW = 9,
					CRAFT_STONE_ARROW = 10,
				}
			else
				pinnedOrder = {
					CRAFT_SPLIT_LOG_TO_PLANK = 1,
					CRAFT_SPLIT_PALM_LOG_TO_PLANK = 2,
					CRAFT_FIRM_STONE_AXE = 3,
					CRAFT_FIRM_STONE_PICKAXE = 4,
					CRAFT_BONE_SWORD = 5,
					CRAFT_LOG_BLOCK = 6,
					CRAFT_PALM_BLOCK = 7,
					CRAFT_REED_BLOCK = 8,
					CRAFT_LEATHER_ARMOR = 9,
					CRAFT_FEATHER_HELMET = 10,
					CRAFT_STONE_ARROW = 11,
				}
			end
			table.sort(recipes, function(a, b)
				local ap = pinnedOrder[a.id] or 999
				local bp = pinnedOrder[b.id] or 999
				if ap ~= bp then
					return ap < bp
				end
				return (a.id or "") < (b.id or "")
			end)
		elseif currentFacilityType == "CRAFTING_T2" then
			local pinnedOrder = {
				CRAFT_DESERT_PLANK = 1,
				CRAFT_BONE_BLOCK = 2,
				CRAFT_BRONZE_BLOCK = 3,
				CRAFT_BRONZE_PICKAXE = 4,
				CRAFT_BRONZE_AXE = 5,
				CRAFT_BRONZE_SWORD = 6,
				CRAFT_BRONZE_BOW = 7,
				CRAFT_BRONZE_HELMET = 8,
				CRAFT_BRONZE_ARMOR = 9,
				CRAFT_BRONZE_ARROW = 10,
			}
			table.sort(recipes, function(a, b)
				local ap = pinnedOrder[a.id] or 999
				local bp = pinnedOrder[b.id] or 999
				if ap ~= bp then
					return ap < bp
				end
				return (a.id or "") < (b.id or "")
			end)
		end
		
		-- 2. Get current queue for this facility
		local ok, qData = NetClient.Request("Craft.GetQueue.Request", {})
		local facilityQueue = {}
		if ok and qData and qData.queue then
			for _, entry in ipairs(qData.queue) do
				-- structureId가 일치하는 항목만 필터링 (CraftingService에서 structureId를 넘겨줌)
				-- Note: CraftingService entry has 'structureId'
				-- But 'Craft.GetQueue.Request' handler filtered data might not have it depending on implementation
				-- Let's check CraftingService.getQueue again.
				-- It returns craftId, recipeId, state, startedAt, completesAt, remaining.
				-- It DOES NOT return structureId in the simplified result. I need to fix that.
			end
		end
		
		-- 3. Get facility info (for health, fuel, etc.)
		local ok2, fInfo = NetClient.Request("Facility.GetInfo.Request", { structureId = currentFacilityStructureId or "" })
		if ok2 and fInfo then
			local d = fInfo
			if d.health and d.maxHealth then
				FacilityUI.UpdateHealth(d.health, d.maxHealth)
			end
		elseif fInfo == "OUT_OF_RANGE" then
			UIManager.notify("시설과 거리가 멀어 창을 닫았습니다.", C.RED)
			UIManager.closeFacility()
			return
		end

		FacilityUI.Refresh(recipes, UIManager.getItemIcon, UIManager)
		
		-- Also need to update FacilityUI with queue data
		-- I will also pass the full qData.queue for now and let FacilityUI filter (or I fix CraftingService)
		FacilityUI.RefreshQueue(qData and qData.queue or {}, currentFacilityStructureId, UIManager.getItemIcon, UIManager)

		if selectedFacilityRecipe then
			UIManager._onFacilityRecipeClick(selectedFacilityRecipe)
		else
			FacilityUI.UpdateDetail(nil)
		end
	end)
end

function UIManager._onFacilityRecipeClick(recipe)
	selectedFacilityRecipe = recipe
	local playerItemCounts = InventoryController.getItemCounts()
	local canCraft, _ = UIManager.checkMaterials(recipe, playerItemCounts)
	
	local getItemData = function(id) return DataHelper.GetData("ItemData", id) end
	FacilityUI.UpdateDetail(recipe, playerItemCounts, getItemData, UIManager.getItemIcon, canCraft)
end

function UIManager._onStartFacilityCraft(recipe, count)
	if not currentFacilityStructureId then return end
	local batchCount = tonumber(count) or 1
	batchCount = math.max(1, math.floor(batchCount))
	local structureId = currentFacilityStructureId

	-- 재료 선택 모달 열기
	MaterialSelectUI.Open(recipe, batchCount, function(materialSlots)
		task.spawn(function()
			local success, response = NetClient.Request("Craft.Start.Request", {
				recipeId = recipe.id,
				structureId = structureId,
				count = batchCount,
				materialSlots = materialSlots,
			})

			if success then
				UIManager.notify(string.format("제작 의뢰 완료! x%d", batchCount), C.GOLD)
				UIManager.refreshFacility()
			else
				UIManager.notify(friendlyError(response, "제작"), C.RED)
			end
		end)
	end)
end

function UIManager._onCollectFacilityCraft(craftId, collectCount)
	task.spawn(function()
		local success, response = NetClient.Request("Craft.Collect.Request", {
			craftId = craftId,
			count = collectCount,
		})
		
		if success then
			local data = response
			local got = tonumber(data and data.collectedCount) or 1
			UIManager.notify(string.format("수령 완료! x%d", got), C.GOLD)
			UIManager.refreshFacility()
			UIManager.refreshInventory()
		else
			UIManager.notify(friendlyError(response, "수령"), C.RED)
		end
	end)
end



function UIManager._onBuildCategoryClick(catId)
	-- 미해금 탭 클릭 시 알림 표시
	if not SkillController.isSkillUnlocked(catId) then
		UIManager.notify("건축 연구에서 해당 스킬을 먼저 해금하세요.", C.RED)
		return
	end
	selectedBuildCat = catId
	UIManager.refreshBuild()
end

function UIManager._onBuildItemClick(data)
	selectedBuildId = data.id
	local isUnlocked = UIManager.checkFacilityUnlocked(data.id)
	local playerItemCounts = InventoryController.getItemCounts()
	local ok, _ = UIManager.checkMaterials(data, playerItemCounts)
	BuildUI.UpdateDetail(data, ok, UIManager.getItemIcon, isUnlocked, playerItemCounts, DataHelper)
end

function UIManager._doStartBuild()
	if not selectedBuildId then return end
	local data = DataHelper.GetData("FacilityData", selectedBuildId)
	if not data then return end
	
	local ok, msg = UIManager.checkMaterials(data)
	if not ok then
		UIManager.notify(msg, C.RED)
		return
	end

	-- [기술 잠금 체크] - 임시 비활성화 (전면 삭제 요청)
	-- if not TechController.isFacilityUnlocked(data.id) then
	-- 	UIManager.notify("건축 기술이 해금되지 않았습니다.", C.RED)
	-- 	return
	-- end
	
	UIManager.closeBuild()
	BuildController.startPlacement(selectedBuildId)
end

----------------------------------------------------------------
-- Public API: Interact / Harvest
----------------------------------------------------------------
function UIManager.showInteractPrompt(text, targetName, durability)
	local keyHint = UILocalizer.Localize(text or "[R] 상호작용")
	local buildingName = targetName and targetName ~= "" and targetName or ""

	InteractUI.UpdatePrompt(buildingName, keyHint)
	if durability and durability.current ~= nil and durability.max ~= nil then
		InteractUI.SetDurabilityVisible(true)
		InteractUI.UpdateDurability(durability.current, durability.max)
	else
		InteractUI.SetDurabilityVisible(false)
	end
	InteractUI.SetVisible(true)
end

function UIManager.hideInteractPrompt()
	InteractUI.SetDurabilityVisible(false)
	InteractUI.SetVisible(false)
end

function UIManager.showHarvestProgress(totalTime, targetName)
	HUDUI.ShowHarvestProgress(totalTime, targetName)
end

function UIManager.hideHarvestProgress()
	HUDUI.HideHarvestProgress()
end

-- 건축 조작 가이드 표시
function UIManager.showBuildPrompt(visible, mode)
	if mode == "BLOCK" then
		InteractUI.SetBuildVisible(false)
		return
	end
	InteractUI.SetBuildMode(mode)
	InteractUI.SetBuildVisible(visible)
end

function UIManager.notify(text, color)
	if not mainGui then return end
	text = UILocalizer.Localize(text)
	
	-- 이전 알림창이 남아있다면 즉시 제거 (글자 겹침 방지)
	if currentToast and currentToast.Parent then
		currentToast:Destroy()
	end
	
	-- Toast style (Durango Torn Paper style)
	local toast = Utils.mkFrame({
		name = "Toast",
		size = UDim2.new(0, 320, 0, 45),
		pos = UDim2.new(0.5, 0, 0.2, -50),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.9, -- 요청 사항: 거의 투명하게
		r = 4,
		stroke = false,
		parent = mainGui
	})
	
	local label = Utils.mkLabel({
		text = text,
		ts = 18,
		color = color or C.WHITE, -- 컬러 지정 가능하도록 수정
		ink = not color, -- 컬러가 없을 때만 잉크 스타일 적용
		parent = toast
	})
	
	currentToast = toast
	
	-- Animation
	toast.Position = UDim2.new(0.5, 0, 0.15, 0)
	local ti = TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(toast, ti, {Position = UDim2.new(0.5, 0, 0.2, 0)}):Play()
	
	task.delay(2.5, function()
		if not toast or not toast.Parent then return end
		local fade = TweenService:Create(toast, TweenInfo.new(0.5), {BackgroundTransparency = 1})
		TweenService:Create(label, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
		fade:Play()
		fade.Completed:Connect(function() toast:Destroy() end)
	end)
end

--- DNA 획득 특별 연출 (화면 중앙 대형 알림)
function UIManager.showDnaObtained(data)
	if not mainGui then return end
	local creatureName = data.creatureId or ""
	local creatureData = nil
	pcall(function()
		local DataHelper = require(game.ReplicatedStorage.Shared.Util.DataHelper)
		creatureData = DataHelper.GetData("CreatureData", creatureName)
	end)
	local displayName = (creatureData and creatureData.name) or creatureName

	-- 희귀도별 색상
	local rarityColors = {
		COMMON = Color3.fromRGB(200, 200, 200),
		UNCOMMON = Color3.fromRGB(30, 255, 30),
		RARE = Color3.fromRGB(0, 170, 255),
		EPIC = Color3.fromRGB(200, 80, 255),
		LEGENDARY = Color3.fromRGB(255, 200, 0),
	}
	local glowColor = rarityColors[data.rarity] or rarityColors.RARE

	-- 전체 화면 오버레이 (살짝 어둡게)
	local overlay = Utils.mkFrame({
		name = "DnaOverlay",
		size = UDim2.new(1, 0, 1, 0),
		bg = Color3.new(0, 0, 0),
		bgT = 1,
		parent = mainGui
	})
	overlay.ZIndex = 50

	-- 중앙 컨테이너
	local container = Utils.mkFrame({
		name = "DnaContainer",
		size = UDim2.new(0, 400, 0, 200),
		pos = UDim2.new(0.5, 0, 0.4, 0),
		anchor = Vector2.new(0.5, 0.5),
		bgT = 1,
		parent = overlay
	})
	container.ZIndex = 51

	-- 🧬 DNA 아이콘 텍스트 (이모지 대용)
	local dnaIcon = Utils.mkLabel({
		text = "🧬",
		size = UDim2.new(0, 80, 0, 80),
		pos = UDim2.new(0.5, 0, 0, 0),
		anchor = Vector2.new(0.5, 0),
		ts = 60,
		color = glowColor,
		parent = container
	})
	dnaIcon.ZIndex = 52
	dnaIcon.TextTransparency = 1

	-- "DNA 획득!" 타이틀
	local title = Utils.mkLabel({
		text = "DNA 획득!",
		size = UDim2.new(1, 0, 0, 40),
		pos = UDim2.new(0.5, 0, 0, 85),
		anchor = Vector2.new(0.5, 0),
		ts = 28,
		color = glowColor,
		parent = container
	})
	title.ZIndex = 52
	title.TextTransparency = 1
	title.Font = Enum.Font.GothamBold

	-- 크리처 이름
	local subtitle = Utils.mkLabel({
		text = displayName .. " DNA",
		size = UDim2.new(1, 0, 0, 30),
		pos = UDim2.new(0.5, 0, 0, 130),
		anchor = Vector2.new(0.5, 0),
		ts = 20,
		color = C.WHITE,
		parent = container
	})
	subtitle.ZIndex = 52
	subtitle.TextTransparency = 1

	-- 희귀도 텍스트
	local rarityText = Utils.mkLabel({
		text = "[" .. (data.rarity or "RARE") .. "]",
		size = UDim2.new(1, 0, 0, 22),
		pos = UDim2.new(0.5, 0, 0, 165),
		anchor = Vector2.new(0.5, 0),
		ts = 16,
		color = glowColor,
		parent = container
	})
	rarityText.ZIndex = 52
	rarityText.TextTransparency = 1

	-- 애니메이션 시퀀스
	local fadeIn = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local fadeInSlow = TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

	-- 1. 오버레이 살짝 어둡게
	TweenService:Create(overlay, fadeIn, {BackgroundTransparency = 0.7}):Play()

	-- 2. DNA 아이콘 페이드인 + 스케일 팝
	task.delay(0.1, function()
		TweenService:Create(dnaIcon, fadeIn, {TextTransparency = 0}):Play()
		dnaIcon.TextScaled = false
		dnaIcon.TextSize = 20
		TweenService:Create(dnaIcon, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {TextSize = 60}):Play()
	end)

	-- 3. 타이틀/서브 순차 페이드인
	task.delay(0.3, function()
		TweenService:Create(title, fadeInSlow, {TextTransparency = 0}):Play()
	end)
	task.delay(0.5, function()
		TweenService:Create(subtitle, fadeInSlow, {TextTransparency = 0}):Play()
	end)
	task.delay(0.7, function()
		TweenService:Create(rarityText, fadeInSlow, {TextTransparency = 0}):Play()
	end)

	-- 4. 3초 후 전체 페이드아웃
	task.delay(3.0, function()
		if not overlay or not overlay.Parent then return end
		local fadeOut = TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		TweenService:Create(overlay, fadeOut, {BackgroundTransparency = 1}):Play()
		TweenService:Create(dnaIcon, fadeOut, {TextTransparency = 1}):Play()
		TweenService:Create(title, fadeOut, {TextTransparency = 1}):Play()
		TweenService:Create(subtitle, fadeOut, {TextTransparency = 1}):Play()
		TweenService:Create(rarityText, fadeOut, {TextTransparency = 1}):Play()
		task.delay(1.0, function()
			if overlay and overlay.Parent then overlay:Destroy() end
		end)
	end)
end

-- [New] Side Notification (Corner stack)
function UIManager.sideNotify(text, color, icon)
	if not mainGui then return end
	text = UILocalizer.Localize(text)
	
	if not sideNotifyContainer then
		sideNotifyContainer = Utils.mkFrame({
			name = "SideNotifyContainer",
			size = UDim2.new(0, 250, 0.6, 0),
			pos = UDim2.new(1, -20, 0.5, 0),
			anchor = Vector2.new(1, 0.5),
			bgT = 1,
			parent = mainGui
		})
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 5)
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.Parent = sideNotifyContainer
	end
	
	local item = Utils.mkFrame({
		name = "NotifyItem",
		size = UDim2.new(1, 0, 0, 45),
		bg = C.BG_PANEL,
		bgT = 0.9, -- 훨씬 더 투명하게
		r = 4,
		stroke = false,
		parent = sideNotifyContainer
	})
	
	local content = Utils.mkFrame({size=UDim2.new(1,0,1,0), bgT=1, parent=item})
	
	if icon then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.new(0, 30, 0, 30)
		img.Position = UDim2.new(0, 10, 0.5, 0)
		img.AnchorPoint = Vector2.new(0, 0.5)
		img.BackgroundTransparency = 1
		img.Image = icon
		img.Parent = content
	end
	
	local lbl = Utils.mkLabel({
		text = text,
		size = UDim2.new(1, icon and -50 or -20, 1, 0),
		pos = UDim2.new(0, icon and 45 or 10, 0, 0),
		ts = 14,
		color = C.WHITE,
		ax = Enum.TextXAlignment.Left,
		parent = content
	})
	
	-- FX: Slide in from right
	item.Position = UDim2.new(1, 100, 0, 0)
	TweenService:Create(item, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0, 0, 0, 0)}):Play()
	
	-- Auto cleanup
	task.delay(4, function()
		if not item or not item.Parent then return end
		local out = TweenService:Create(item, TweenInfo.new(0.5), {BackgroundTransparency = 1, Position = UDim2.new(1, 50, 0, 0)})
		TweenService:Create(lbl, TweenInfo.new(0.5), {TextTransparency = 1}):Play()
		out:Play()
		out.Completed:Connect(function() item:Destroy() end)
	end)
end

function UIManager.refreshStatusEffects()
	local list = {}
	for _, data in pairs(activeDebuffs) do
		table.insert(list, data)
	end
	HUDUI.UpdateStatusEffects(list)
end
function UIManager.updateHealth(cur, max)
	HUDUI.UpdateHealth(cur, max)
end

function UIManager.updateStamina(cur, max)
	HUDUI.UpdateStamina(cur, max)
end

function UIManager.updateHunger(cur, max)
	HUDUI.UpdateHunger(cur, max)
end

function UIManager.updateXP(cur, max)
	HUDUI.UpdateXP(cur, max)
end

function UIManager.updateLevel(lv)
	HUDUI.UpdateLevel(lv)
end

function UIManager.updateStatPoints(available)
	HUDUI.SetStatPointAlert(available)
end

function UIManager.checkFacilityUnlocked(facilityId)
	-- buildTier 기반 스킬 해금 체크
	local allFacilities = require(ReplicatedStorage.Data.FacilityData)
	for _, f in ipairs(allFacilities) do
		if f.id == facilityId and f.buildTier then
			return SkillController.isSkillUnlocked(f.buildTier)
		end
	end
	return true -- buildTier 없으면 기본 해금
end

----------------------------------------------------------------
-- Event Listeners
----------------------------------------------------------------
local function setupEventListeners()
	InventoryController.onChanged(function()
		if WindowManager.isOpen("INV") then UIManager.refreshInventory() end
		if WindowManager.isOpen("STORAGE") then UIManager.refreshStorage() end
		UIManager.refreshHotbar()
		if WindowManager.isOpen("EQUIP") then UIManager.refreshStats() end
		if invCraftContainer and invCraftContainer.Visible then
			UIManager.refreshPersonalCrafting()
		end
	end)
	ShopController.onGoldChanged(function(g) UIManager.updateGold(g) end)
	-- [수정] 구 refreshCrafting() 제거 — 하단 onTechUpdated 콜백이 올바르게 처리합니다.

	-- HUD Update Loop
	RunService.RenderStepped:Connect(function()
		local didPruneDebuff = false
		local now = os.time()
		for debuffId, debuff in pairs(activeDebuffs) do
			if type(debuff) == "table" and (debuff.duration or -1) > 0 then
				local started = debuff.startTime or now
				if (now - started) >= (debuff.duration or 0) then
					activeDebuffs[debuffId] = nil
					didPruneDebuff = true
				end
			end
		end
		if didPruneDebuff then
			UIManager.refreshStatusEffects()
		end

		-- Update Coordinates & Compass
		local char = player.Character
		if char and char.PrimaryPart then
			local pos = char.PrimaryPart.Position
			HUDUI.UpdateCoordinates(pos.X, pos.Z)
		end
		
		local cam = workspace.CurrentCamera
		if cam then
			local look = cam.CFrame.LookVector
			-- Camera North is -Z in world coords
			local angle = math.atan2(look.X, look.Z)
			HUDUI.UpdateCompass(angle)
		end

		HUDUI.UpdateDayNightClock(TimeController.getDayTime(), Balance.DAY_LENGTH)
	end)

	-- 활성 슬롯 동기화 (서버 -> 클라)
	NetClient.On("Inventory.ActiveSlot.Changed", function(data)
		if data and data.slot then
			UIManager.selectHotbarSlot(data.slot, true) -- 루프 방지 위해 skipSync=true
			if WindowManager.isOpen("EQUIP") then
				EquipmentUI.UpdateCharacterPreview(player.Character)
			end
		end
	end)
	-- [Phase 5] UI Toggle Key Bindings are handled in ClientInit.client.lua
	-- (Redundant bindings removed to avoid conflicts)

	-- Hotbar number keys / Touch selection
	local hotbarKeys = {Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight}
	for i = 1, 8 do
		InputManager.bindKey(hotbarKeys[i], "HB"..i, function() UIManager.selectHotbarSlot(i) end)
		
		-- [추가] 모바일 터치 및 마우스 클릭 선택 지원
		local s = hotbarSlots[i]
		if s and s.click then
			s.click.MouseButton1Click:Connect(function()
				UIManager.selectHotbarSlot(i)
			end)
		end
	end

	-- Mouse Wheel (Hotbar scroll) - DISABLED as per user request to allow zoom only
	-- UserInputService.InputChanged:Connect(function(input, processed)
	-- 	if processed or isUIOpen or isCraftOpen or isShopOpen or isTechOpen then return end
	-- 	if input.UserInputType == Enum.UserInputType.MouseWheel then
	-- 		local delta = input.Position.Z
	-- 		local newSlot = selectedSlot
	-- 		if delta > 0 then
	-- 			newSlot = selectedSlot - 1
	-- 		else
	-- 			newSlot = selectedSlot + 1
	-- 		end
	-- 		
	-- 		if newSlot < 1 then newSlot = 8 end
	-- 		if newSlot > 8 then newSlot = 1 end
	-- 		
	-- 		if newSlot ~= selectedSlot then
	-- 			UIManager.selectHotbarSlot(newSlot)
	-- 		end
	-- 	end
	-- end)

	-- Stats event
	if NetClient.On then
		NetClient.On("Player.Stats.Changed", function(d)
			if d then
				for k, v in pairs(d) do cachedStats[k] = v end
				if d.level then UIManager.updateLevel(d.level) end
				if d.currentXP and d.requiredXP then UIManager.updateXP(d.currentXP, d.requiredXP) end
				if d.leveledUp then 
					UIManager.notify(" 레벨업! Lv. "..d.level, C.WHITE)
				end
				if d.upgradedStat then
					UIManager.notify(" 💪 능력치 강화 성공!", C.GREEN)
				end
				if d.statPointsAvailable ~= nil then UIManager.updateStatPoints(d.statPointsAvailable) end
				if WindowManager.isOpen("EQUIP") then UIManager.refreshStats() end
				-- 스탯 변경 시 인벤토리 슬롯 수 즉시 동기화
				if d.calculated and d.calculated.maxSlots then
					InventoryController.setMaxSlots(d.calculated.maxSlots)
				end
				UIManager.refreshInventory()
			end
		end)
	end


	-- DNA 획득 이벤트
	if NetClient.On then
		NetClient.On("DNA.Obtained", function(data)
			if data then
				UIManager.showDnaObtained(data)
			end
		end)
		
		NetClient.On("DNA.Registered", function(data)
			if data then
				local creatureName = data.creatureId or ""
				local displayName = creatureName
				pcall(function()
					local DataHelper = require(game.ReplicatedStorage.Shared.Util.DataHelper)
					local cd = DataHelper.GetData("CreatureData", creatureName)
					if cd and cd.name then displayName = cd.name end
				end)
				UIManager.notify("🧬 " .. displayName .. " DNA가 도감에 등록되었습니다!", Color3.fromRGB(0, 255, 180))
			end
		end)
		
		-- 펫 사망/재소환 알림
		NetClient.On("Pet.Died", function(data)
			if data and data.creatureId then
				local displayName = data.creatureId
				pcall(function()
					local DataHelper = require(game.ReplicatedStorage.Shared.Util.DataHelper)
					local cd = DataHelper.GetData("CreatureData", data.creatureId)
					if cd and cd.name then displayName = cd.name end
				end)
				UIManager.notify("🐾 " .. displayName .. " 펫이 쓰러졌습니다! (재소환 대기중)", Color3.fromRGB(255, 100, 100))
			end
		end)
		
		NetClient.On("Pet.Respawned", function(data)
			if data and data.creatureId then
				local displayName = data.creatureId
				pcall(function()
					local DataHelper = require(game.ReplicatedStorage.Shared.Util.DataHelper)
					local cd = DataHelper.GetData("CreatureData", data.creatureId)
					if cd and cd.name then displayName = cd.name end
				end)
				UIManager.notify("🐾 " .. displayName .. " 펫이 재소환되었습니다!", Color3.fromRGB(100, 255, 150))
			end
		end)

		-- 팰박스 업데이트 시 동물 관리 탭 자동 갱신
		NetClient.On("Palbox.Updated", function(data)
			UIManager.refreshAnimalManagement()
		end)
		
		-- 팰 기절 알림
		NetClient.On("Party.Pal.Fainted", function(data)
			if data and data.palName then
				UIManager.notify("💀 " .. data.palName .. "이(가) 기절했습니다!", Color3.fromRGB(255, 80, 80))
			end
			UIManager.refreshAnimalManagement()
		end)

		NetClient.On("Party.Mounted", function(data)
			local palName = data and data.palName or "공룡"
			UIManager.sideNotify(palName .. " 탑승 중", Color3.fromRGB(120, 220, 255))
		end)

		NetClient.On("Party.Dismounted", function(data)
			local palName = data and data.palName or "공룡"
			UIManager.sideNotify(palName .. "에서 내렸습니다.", Color3.fromRGB(180, 220, 255))
		end)
	end

	-- Debuff Events
	if NetClient.On then
		NetClient.On("Debuff.Applied", function(data)
			if data and data.debuffId then
				activeDebuffs[data.debuffId] = {
					id = data.debuffId,
					name = data.name,
					description = data.description, -- 설명 추가
					startTime = os.time(),
					duration = data.duration
				}
				UIManager.refreshStatusEffects()
			end
		end)
		
		NetClient.On("Debuff.Removed", function(data)
			if data and data.debuffId then
				activeDebuffs[data.debuffId] = nil
				UIManager.refreshStatusEffects()
			end
		end)
	end

	-- Combat Engagement UI
	if NetClient.On then
		NetClient.On("Combat.Engagement.Changed", function(data)
			if not data then return end
			
			if data.inCombat then
				currentCombatCreatureId = data.instanceId
				
				-- Find creature model by instanceId
				local creatureModel = nil
				local workspace_creatures = workspace:FindFirstChild("Creatures") or workspace
				
				-- Search for creature with matching instanceId
				for _, model in ipairs(workspace_creatures:GetDescendants()) do
					if model:IsA("Model") and model:GetAttribute("InstanceId") == data.instanceId then
						creatureModel = model
						break
					end
				end
				
				-- Fallback: search in Workspace directly
				if not creatureModel then
					for _, child in ipairs(workspace:GetChildren()) do
						if child:IsA("Model") and child:GetAttribute("InstanceId") == data.instanceId then
							creatureModel = child
							break
						end
					end
				end
				
				if creatureModel then
					local displayName = creatureModel:GetAttribute("DisplayName") or creatureModel.Name
					local creatureId = creatureModel:GetAttribute("CreatureId") or creatureModel.Name
					
					-- Clean up display name (remove "Lv.X" if already included)
					displayName = string.match(displayName, "([^L][^v]*?)%s*Lv%.%d+$") or displayName
					displayName = string.match(displayName, "^(.+?)%s*Lv%.") or displayName
					
					-- Look up creature data for actual level
					local creatureLevel = creatureModel:GetAttribute("Level") or 1
					if CreatureData and type(CreatureData) == "table" then
						for _, cData in ipairs(CreatureData) do
							if cData.id == creatureId or cData.name == displayName then
								creatureLevel = cData.level or creatureLevel
								break
							end
						end
					end
					
					local currentHP = creatureModel:GetAttribute("CurrentHealth") or 100
					local maxHP = creatureModel:GetAttribute("MaxHealth") or 100
					
					HUDUI.ShowCombatUI(displayName, creatureLevel, currentHP, maxHP)
				end
			else
				-- 전투 해제 시: 짧은 딜레이 후 숨김 (사망 시 HP바=0 반영을 위해)
				-- Hit.Result 이벤트가 먼저 도착하여 HP바를 0으로 업데이트할 여유를 줌
				local disengagedId = currentCombatCreatureId
				task.delay(0.8, function()
					-- 딜레이 중 새 전투가 시작되지 않았으면 숨김
					if currentCombatCreatureId == disengagedId then
						currentCombatCreatureId = nil
						HUDUI.HideCombatUI()
					end
				end)
			end
		end)

		-- 플레이어 공격 히트 시 체력바 즉시 반영
		NetClient.On("Combat.Hit.Result", function(data)
			if data and data.currentHP and data.maxHP and currentCombatCreatureId then
				if data.targetId == currentCombatCreatureId then
					HUDUI.UpdateCombatUI(data.currentHP, data.maxHP)
				end
			end
		end)

		-- 팰 공격 히트 시 체력바 즉시 반영
		NetClient.On("Combat.Pal.Hit.Result", function(data)
			if data and data.currentHP and data.maxHP and currentCombatCreatureId then
				if data.targetId == currentCombatCreatureId then
					HUDUI.UpdateCombatUI(data.currentHP, data.maxHP)
				end
			end
		end)
	end

	-- Portal Events (고대 포탈 시스템)
	if NetClient.On then
		NetClient.On("Portal.UI.Open", function(data)
			UIManager.openPortalRadial(data)
		end)

		NetClient.On("Portal.MissingMaterials", function()
			UIManager.notify("⚡ 골드가 부족하거나 잘못된 요청입니다.", Color3.fromRGB(255, 120, 80))
		end)

		NetClient.On("Portal.Repaired", function(_data)
			UIManager.notify("🌀 고대 포탈이 수리되었습니다!", Color3.fromRGB(255, 200, 0))
			UIManager.sideNotify("포탈 UI의 [포탈 이용] 탭에서 이동할 수 있습니다", Color3.fromRGB(100, 200, 255))
			UIManager.refreshPortal({ repaired = true })
		end)

		NetClient.On("Portal.Teleporting", function(data)
			local dest = (data and data.destination) or "다음 섬"
			UIManager.closePortalRadial()

			local oldFadeGui = player.PlayerGui:FindFirstChild("PortalFadeGui")
			if oldFadeGui then
				oldFadeGui:Destroy()
			end

			-- 페이드 스크린 생성
			local fadeGui = Instance.new("ScreenGui")
			fadeGui.Name = "PortalFadeGui"
			fadeGui.DisplayOrder = 999
			fadeGui.IgnoreGuiInset = true
			fadeGui.ResetOnSpawn = false
			fadeGui.Parent = player.PlayerGui

			local overlay = Instance.new("Frame")
			overlay.Size = UDim2.new(1, 0, 1, 0)
			overlay.BackgroundColor3 = Color3.new(0, 0, 0)
			overlay.BackgroundTransparency = 1
			overlay.BorderSizePixel = 0
			overlay.Parent = fadeGui

			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 0, 60)
			label.Position = UDim2.new(0, 0, 0.45, -40)
			label.BackgroundTransparency = 1
			label.Text = "🌀 " .. dest .. "(으)로 이동 중..."
			label.TextColor3 = Color3.fromRGB(200, 230, 255)
			label.TextSize = 28
			label.Font = Enum.Font.GothamBold
			label.TextTransparency = 1
			label.Parent = overlay

			-- 로딩바 배경
			local barBg = Instance.new("Frame")
			barBg.Name = "ProgressBarBg"
			barBg.Size = UDim2.new(0.4, 0, 0, 12)
			barBg.Position = UDim2.new(0.3, 0, 0.45, 30)
			barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
			barBg.BorderSizePixel = 0
			barBg.BackgroundTransparency = 1
			local bgCorner = Instance.new("UICorner")
			bgCorner.CornerRadius = UDim.new(0.5, 0)
			bgCorner.Parent = barBg
			barBg.Parent = overlay

			-- 로딩바 채움
			local barFill = Instance.new("Frame")
			barFill.Name = "ProgressBarFill"
			barFill.Size = UDim2.new(0, 0, 1, 0)
			barFill.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
			barFill.BorderSizePixel = 0
			barFill.BackgroundTransparency = 1
			local fillCorner = Instance.new("UICorner")
			fillCorner.CornerRadius = UDim.new(0.5, 0)
			fillCorner.Parent = barFill
			barFill.Parent = barBg

			-- 빛나는 효과 (가짜 진행률)
			local uigradient = Instance.new("UIGradient")
			uigradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 180, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 230, 255))
			})
			uigradient.Parent = barFill

			-- 페이드 인 (검정화면)
			TweenService:Create(overlay, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0}):Play()
			TweenService:Create(label, TweenInfo.new(0.8), {TextTransparency = 0}):Play()
			TweenService:Create(barBg, TweenInfo.new(0.8), {BackgroundTransparency = 0.3}):Play()
			TweenService:Create(barFill, TweenInfo.new(0.8), {BackgroundTransparency = 0}):Play()

			-- 모의 로딩 애니메이션 (85%까지 약 4초에 걸쳐 천천히 진입)
			task.delay(0.8, function()
				if barFill and barFill.Parent then
					TweenService:Create(barFill, TweenInfo.new(4.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Size = UDim2.new(0.85, 0, 1, 0)}):Play()
				end
			end)
		end)

		NetClient.On("Portal.Arrived", function(_data)
			local fadeGui = player.PlayerGui:FindFirstChild("PortalFadeGui")
			if fadeGui then
				local overlay = fadeGui:FindFirstChildWhichIsA("Frame")
				if overlay then
					local label = overlay:FindFirstChildWhichIsA("TextLabel")
					local barBg = overlay:FindFirstChild("ProgressBarBg")
					local barFill = barBg and barBg:FindFirstChild("ProgressBarFill")

					task.spawn(function()
						-- 1. 완료 시 잔여 로딩바를 빠르게 100%로 채움
						if barFill then
							TweenService:Create(barFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, 1, 0)}):Play()
						end
						if label then
							label.Text = "🌀 안전하게 도착했습니다!"
							label.TextColor3 = Color3.fromRGB(150, 255, 150)
						end
						task.wait(0.5)

						-- 2. 서서히 화면 페이드 아웃
						local fadeOut = TweenService:Create(overlay, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1})
						if label then TweenService:Create(label, TweenInfo.new(0.6), {TextTransparency = 1}):Play() end
						if barBg then TweenService:Create(barBg, TweenInfo.new(0.6), {BackgroundTransparency = 1}):Play() end
						if barFill then TweenService:Create(barFill, TweenInfo.new(0.6), {BackgroundTransparency = 1}):Play() end

						fadeOut:Play()
						fadeOut.Completed:Connect(function()
							fadeGui:Destroy()
						end)
					end)
				else
					fadeGui:Destroy()
				end
			end
		end)

		NetClient.On("Portal.Error", function(data)
			local msg = (data and data.message) or "포탈 오류"
			local fadeGui = player.PlayerGui:FindFirstChild("PortalFadeGui")
			if fadeGui then
				fadeGui:Destroy()
			end
			UIManager.sideNotify("❌ " .. msg, Color3.fromRGB(255, 80, 80))
		end)
	end

	-- Humanoid HP / Stats Sync
	local function connectHumanoid(hum)
		UIManager.updateHealth(hum.Health, hum.MaxHealth)
		
		hum.HealthChanged:Connect(function(h)
			UIManager.updateHealth(h, hum.MaxHealth)
		end)
		
		hum:GetPropertyChangedSignal("MaxHealth"):Connect(function()
			UIManager.updateHealth(hum.Health, hum.MaxHealth)
		end)
	end

	-- MovementController 연동 (스태미나)
	local function setupMovementController()
		local MovementController = require(Client.Controllers.MovementController)
		if MovementController and MovementController.onStaminaChanged then
			MovementController.onStaminaChanged(function(cur, max)
				UIManager.updateStamina(cur, max)
			end)
			
			-- 초기값 반영
			local c, m = MovementController.getStamina()
			UIManager.updateStamina(c, m)
		end
	end

	-- Hunger sync 연동
	NetClient.On("Hunger.Update", function(data)
		UIManager.updateHunger(data.current, data.max)
	end)

	task.spawn(function()
		setupMovementController()
		
		-- 초기 배고픔 요청
		local okH, dH = NetClient.Request("Hunger.GetState", {})
		if okH and dH then
			UIManager.updateHunger(dH.current, dH.max)
		end

		local char = player.Character or player.CharacterAdded:Wait()
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then connectHumanoid(hum) end
		
		player.CharacterAdded:Connect(function(c)
			local h2 = c:WaitForChild("Humanoid", 10)
			if h2 then 
				connectHumanoid(h2)
				-- [Safety] 리스폰 시 서버가 스탯을 적용할 시간을 주기 위해 약간 지연 후 강제 갱신
				task.delay(0.5, function()
					if h2 and h2.Parent then
						UIManager.updateHealth(h2.Health, h2.MaxHealth)
					end
				end)
			end
			
			-- 리스폰 시 레벨/XP/배고픔/스태미나 재동기화
			task.delay(0.5, function()
				local ok2, d2 = NetClient.Request("Player.Stats.Request", {})
				if ok2 and d2 then
					cachedStats = d2
					if d2.level then UIManager.updateLevel(d2.level) end
					if d2.currentXP and d2.requiredXP then UIManager.updateXP(d2.currentXP, d2.requiredXP) end
					if d2.statPointsAvailable then UIManager.updateStatPoints(d2.statPointsAvailable) end
				end
				
				local okH2, dH2 = NetClient.Request("Hunger.GetState", {})
				if okH2 and dH2 then
					UIManager.updateHunger(dH2.current, dH2.max)
				end
			end)
		end)
	end)

	-- Initial stats load (재시도 포함 — 서버 SaveService 로딩 대기 대응)
	task.spawn(function()
		task.wait(1)
		for _attempt = 1, 5 do
			local ok, d = NetClient.Request("Player.Stats.Request", {})
			if ok and d then
				cachedStats = d
				if d.level then UIManager.updateLevel(d.level) end
				if d.currentXP and d.requiredXP then UIManager.updateXP(d.currentXP, d.requiredXP) end
				if d.statPointsAvailable then UIManager.updateStatPoints(d.statPointsAvailable) end
				break
			end
			task.wait(2)
		end
	end)

	-- [FIX] 제작 서버 이벤트 동기화 (Phase 11)
	if NetClient.On then
		NetClient.On("Craft.Started", function(data)
			if data and data.craftTime then
				UIManager.showCraftingProgress(data.craftTime)
			end
		end)
		
		NetClient.On("Craft.Completed", function(data)
			UIManager.stopCraftingProgress()
			
			local itemName = "아이템"
			if data and data.recipeId then
				local recipe = DataHelper.GetData("RecipeData", data.recipeId)
				if recipe then
					itemName = UILocalizer.LocalizeDataText("RecipeData", tostring(data.recipeId), "name", recipe.name)
				end
			end
			
			UIManager.notify(itemName .. " 제작 완료!", C.GREEN)
			UIManager.refreshInventory()
			UIManager.refreshPersonalCrafting()
		end)
		
		NetClient.On("Craft.Cancelled", function(data)
			UIManager.stopCraftingProgress()
			UIManager.notify("제작이 취소되었습니다.", C.WHITE)
		end)

		-- 범용 서버 알림 메시지
		NetClient.On("Notify.Message", function(data)
			if data and data.text then
				local color = C.WHITE
				if data.color then
					color = Color3.fromRGB(data.color.r or 255, data.color.g or 255, data.color.b or 255)
				end
				UIManager.notify(data.text, color)
			end
		end)
	end

	-- Drag & Drop global listeners
	UserInputService.InputChanged:Connect(function(input) UIManager.handleDragUpdate(input) end)
	UserInputService.InputEnded:Connect(function(input) UIManager.handleDragEnd(input) end)
end


----------------------------------------------------------------
-- Init
----------------------------------------------------------------
function UIManager.Init()
	if initialized then return end

	LocaleService.Init()

	mainGui = Instance.new("ScreenGui")
	mainGui.Name = "GameUI"
	mainGui.ResetOnSpawn = false
	mainGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	mainGui.IgnoreGuiInset = true -- SafeArea 제어를 위해 true 설정
	mainGui.Parent = playerGui

	-- [Click-Outside-to-Close] 전역 배경용 전용 레이어 (HUD 뒤에 배치하기 위해 분리)
	local dimGui = Instance.new("ScreenGui")
	dimGui.Name = "GlobalDimGui"
	dimGui.DisplayOrder = -10 -- HUD 및 모든 UI보다 뒤에 배치
	dimGui.IgnoreGuiInset = true
	dimGui.ResetOnSpawn = false
	dimGui.Parent = playerGui

	local globalDim = Instance.new("Frame")
	globalDim.Name = "GlobalDimBackground"
	globalDim.Size = UDim2.new(1, 0, 1, 0)
	globalDim.BackgroundTransparency = 1
	globalDim.BackgroundColor3 = Color3.new(0, 0, 0)
	globalDim.BorderSizePixel = 0
	globalDim.Active = false
	globalDim.Visible = false
	globalDim.Parent = dimGui
	WindowManager.setDimBackground(globalDim)

	-- [Responsive] UIScale 도입
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = mainGui
	
	local function updateScale()
		local viewportSize = workspace.CurrentCamera.ViewportSize
		local baseRes = Vector2.new(1280, 720)
		local scaleX = viewportSize.X / baseRes.X
		local scaleY = viewportSize.Y / baseRes.Y
		local finalScale = math.min(scaleX, scaleY)
		
		-- 모바일은 조금 더 크게 (가독성/터치 영역)
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
			finalScale = finalScale * 1.15
		end
		
		uiScale.Scale = math.clamp(finalScale, 0.5, 2.5)
	end
	
	updateScale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

	-- [수정] 기본 로블록스 UI 요소 비활성화 (모바일 쾌적성 극대화)
	local SG = game:GetService("StarterGui")
	SG:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	SG:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	SG:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	SG:SetCoreGuiEnabled(Enum.CoreGuiType.EmotesMenu, false)
	-- 모바일 점프 버튼 등은 ContextActionService로 제어되거나 HUDUI가 덮어씌움

	-- 신규 모듈형 UI 초기화
	HUDUI.Init(mainGui, UIManager, InputManager, isMobile)
	InventoryUI.Init(mainGui, UIManager, isMobile)
	CraftingUI.Init(mainGui, UIManager, isMobile)
	ShopUI.Init(mainGui, UIManager, isMobile)
	InteractUI.Init(mainGui, isMobile)
	if InteractUI.Refs.PromptFrame then
		InteractUI.Refs.PromptFrame.MouseButton1Click:Connect(function()
			if InteractController and InteractController.onFacilityInteractPress then
				InteractController.onFacilityInteractPress()
			end
		end)
	end
	EquipmentUI.Init(mainGui, UIManager, Enums, isMobile)
	equipmentUIFrame = EquipmentUI.Refs.Frame
	BuildUI.Init(mainGui, UIManager, isMobile)
	StorageUI.Init(mainGui, UIManager, isMobile)
	FacilityUI.Init(mainGui, UIManager, isMobile)
	MaterialSelectUI.Init(mainGui, UIManager)

	TotemUI.Init(mainGui, UIManager, isMobile)
	PortalUI.Init(mainGui, UIManager, isMobile)
	PortalRadialUI:Init(UIManager)
	QuestUI:Init(UIManager)
	SkillTreeUI.Init(mainGui, UIManager, isMobile)
	SkillTreeUI.SetController(SkillController)
	ActiveSkillBarUI.Init(mainGui)
	PromptUI.Init()
	HarvestUI.Init(UIManager)
	UILocalizer.StartAuto(mainGui)

	StorageController.Init()
	FacilityController.Init()


	-- 슬롯 참조만 유지 (드래그 앤 드롭 및 리프레시 로직용)
	hotbarSlots = HUDUI.Refs.hotbarSlots
	invSlots = InventoryUI.Refs.Slots
	equipSlots = EquipmentUI.Refs.Slots
	
	-- Personal Crafting references
	invPersonalCraftGrid = InventoryUI.Refs.CraftGrid
	invCraftContainer = InventoryUI.Refs.CraftFrame
	invDetailPanel = InventoryUI.Refs.Detail.Frame
	
	setupEventListeners()

	UIManager.refreshInventory()
	UIManager.refreshHotbar()
	-- UIManager.updateHealth(100,100) -- 제거: 캐릭터 스폰 리스너에서 처리함
	UIManager.updateStamina(100,100)
	UIManager.updateXP(0,100)
	UIManager.updateLevel(1)
	
	-- 알림 라벨 (사용 중단되거나 제거)
	UIManager._notifyLabel = nil

	-- [Refactor] WindowManager 창 등록 (관리 생산성 극대화)
	WindowManager.onUpdate(updateUIMode)
	WindowManager.register("INV", UIManager._onOpenInventory, UIManager._onCloseInventory)
	WindowManager.register("EQUIP", UIManager._onOpenEquipment, UIManager._onCloseEquipment)
	WindowManager.register("SHOP", UIManager._onOpenShop, UIManager._onCloseShop)
	WindowManager.register("BUILD", UIManager._onOpenBuild, UIManager._onCloseBuild)
	WindowManager.register("STORAGE", UIManager._onOpenStorage, UIManager._onCloseStorage)
	WindowManager.register("FACILITY", UIManager._onOpenFacility, UIManager._onCloseFacility)

	WindowManager.register("TOTEM", UIManager._onOpenTotem, UIManager._onCloseTotem)
	WindowManager.register("PORTAL", UIManager._onOpenPortal, UIManager._onClosePortal)
	WindowManager.register("SKILL", UIManager._onOpenSkillTree, UIManager._onCloseSkillTree)
	WindowManager.register("QUEST", UIManager._onOpenQuest, UIManager._onCloseQuest)

	-- [NEW] 상호작용 방사형 UI 등록
	WindowManager.register("HARVEST", HarvestUI.Open, HarvestUI.Close)
	WindowManager.register("FACILITY_RADIAL", FacilityRadialUI.Open, FacilityRadialUI.Close)
	WindowManager.register("PAL_RADIAL", PalRadialUI.Open, PalRadialUI.Close)
	WindowManager.register("PORTAL_RADIAL", function(...) PortalRadialUI:Open(...) end, PortalRadialUI.Close)
	WindowManager.register("NPC_RADIAL", NPCRadialUI.Open, NPCRadialUI.Close)

	-- ★ 오픈/닫기 애니메이션용 메인 패널 프레임 등록
	-- 오버레이 구조(INV, BUILD 등): 첫 자식 윈도우가 애니 대상
	-- 직접 윈도우 구조(TOTEM, PORTAL): Frame 자체가 애니 대상
	task.defer(function()
		-- 오버레이 내부의 메인 윈도우 패널 검색 헬퍼
		local function findMainPanel(overlay)
			if not overlay then return nil end
			for _, child in ipairs(overlay:GetChildren()) do
				if child:IsA("Frame") or child:IsA("CanvasGroup") then
					return child
				end
			end
			return nil
		end

		-- 오버레이 구조 UI들 (Refs.Frame이 전체 오버레이)
		WindowManager.registerFrame("INV", findMainPanel(InventoryUI.Refs.Frame))
		WindowManager.registerFrame("EQUIP", findMainPanel(EquipmentUI.Refs.Frame))
		WindowManager.registerFrame("SHOP", findMainPanel(ShopUI.Refs.Frame))
		WindowManager.registerFrame("BUILD", findMainPanel(BuildUI.Refs.Frame))
		WindowManager.registerFrame("STORAGE", findMainPanel(StorageUI.Refs.Frame))
		WindowManager.registerFrame("FACILITY", findMainPanel(FacilityUI.Refs.Frame))

		WindowManager.registerFrame("SKILL", findMainPanel(SkillTreeUI.Refs.Frame))
		WindowManager.registerFrame("QUEST", findMainPanel(QuestUI.Refs.Frame))

		-- 직접 윈도우 구조 UI들 (Refs.Frame이 곧 패널)
		WindowManager.registerFrame("TOTEM", TotemUI.Refs.Frame)
		WindowManager.registerFrame("PORTAL", PortalUI.Refs.Frame)
	end)

	-- [Refactor] DragDropController 초기화
	DragDropController.Init(UIManager, InventoryController, Balance, mainGui)

	initialized = true
	print("[UIManager] Initialized — WindowManager & Controllers decoupled")
end

function UIManager.hideAllLoading()
	if craftSpinner then
		craftSpinner.Visible = false
	end
	-- 추가적인 로딩 UI가 있다면 여기서 처리
end

-- =============================================
-- Combat UI Periodic Update
-- =============================================
RunService.RenderStepped:Connect(function()
	if currentCombatCreatureId then
		-- Find creature model by instanceId
		local creatureModel = nil
		local workspace_creatures = workspace:FindFirstChild("Creatures")
		
		if workspace_creatures then
			for _, model in ipairs(workspace_creatures:GetDescendants()) do
				if model:IsA("Model") and model:GetAttribute("InstanceId") == currentCombatCreatureId then
					creatureModel = model
					break
				end
			end
		end
		
		if not creatureModel then
			for _, child in ipairs(workspace:GetChildren()) do
				if child:IsA("Model") and child:GetAttribute("InstanceId") == currentCombatCreatureId then
					creatureModel = child
					break
				end
			end
		end
		
		if creatureModel then
			local currentHP = creatureModel:GetAttribute("CurrentHealth") or 0
			local maxHP = creatureModel:GetAttribute("MaxHealth") or 100
			HUDUI.UpdateCombatUI(currentHP, maxHP)
		end
	end
end)

----------------------------------------------------------------
-- 동물 관리 (Animal Management)
----------------------------------------------------------------

--- 팰 박스 목록을 서버에서 가져와 UI 갱신
function UIManager.refreshAnimalManagement()
	local ok, data = NetClient.Request("Palbox.List.Request", {})
	if ok and data then
		local palList = data.pals or {}
		InventoryUI.RefreshAnimalTab(palList)
	else
		InventoryUI.RefreshAnimalTab({})
	end
end

--- 소환하기 / 회수하기 버튼 콜백
function UIManager.onSummonPal()
	local uid = InventoryUI.GetSelectedPalUID()
	if not uid then
		UIManager.notify("소환할 동물을 선택하세요.", Color3.fromRGB(255, 200, 80))
		return
	end

	local ok, data = NetClient.Request("Palbox.QuickSummon.Request", { palUID = uid })
	if ok and data then
		local action = data.action
		if action == "RECALLED" then
			UIManager.notify("동물을 회수했습니다.", Color3.fromRGB(100, 200, 255))
		else
			UIManager.notify("동물을 소환했습니다!", Color3.fromRGB(100, 255, 180))
		end
	else
		local errCode = (type(data) == "table" and data.errorCode) or tostring(data or "UNKNOWN")
		UIManager.notify(friendlyError(errCode, "소환"), Color3.fromRGB(255, 100, 100))
	end

	UIManager.refreshAnimalManagement()
end

--- 풀어주기 버튼 콜백
function UIManager.onReleasePal()
	local uid = InventoryUI.GetSelectedPalUID()
	if not uid then
		UIManager.notify("풀어줄 동물을 선택하세요.", Color3.fromRGB(255, 200, 80))
		return
	end
	local ok, data = NetClient.Request("Palbox.QuickRelease.Request", { palUID = uid })
	if ok then
		UIManager.notify("동물을 풀어주었습니다.", Color3.fromRGB(180, 180, 180))
		UIManager.refreshAnimalManagement()
	else
		UIManager.notify(friendlyError(data, "풀어주기"), Color3.fromRGB(255, 100, 100))
	end
end

return UIManager
