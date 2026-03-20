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
local CollectionUI = require(UI.CollectionUI)
local PromptUI = require(UI.PromptUI)
local TotemUI = require(UI.TotemUI)

local CollectionController = require(Controllers.CollectionController)

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
local selectedBuildCat = "BASIC"
local selectedFacilityId = nil -- shared with Crafting or use separate variable
local selectedBuildId = nil
local currentFacilityStructureId = nil
local currentFacilityType = nil
local selectedFacilityRecipe = nil
local currentTotemStructureId = nil

-- 0. UI 관리 헬퍼
local function isAnyWindowOpen()
	return WindowManager.isAnyOpen()
end


local function updateUIMode()
	local anyOpen = WindowManager.isAnyOpen()
	InputManager.setUIOpen(anyOpen)
	UIManager._setMainHUDVisible(not anyOpen)
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

-- Inventory
local invSlots = {}
local invDetailPanel
local selectedInvSlot = nil
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
		UIManager.notify("완료 조건을 확인할 수 없습니다. 무전기를 다시 확인해 주세요.", C.WHITE)
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
			UIManager.notify("강화 실패: " .. tostring(data), C.RED)
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
local notifyConn
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
	
	if not skipSync then
		InventoryController.requestSetActiveSlot(idx)
	end
end

function UIManager.getSelectedSlot()
	return selectedSlot
end

local ITEM_ICONS_FOLDER = nil
task.spawn(function()
	local assets = ReplicatedStorage:WaitForChild("Assets", 5)
	if assets then
		ITEM_ICONS_FOLDER = assets:WaitForChild("ItemIcons", 3) or assets:WaitForChild("Images", 2) or assets:WaitForChild("Icons", 2)
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
	if itemId == "LEAN_TO" then
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
	
	-- 1. 로드된 아이콘 폴더에서 검색
	if ITEM_ICONS_FOLDER then
		local iconObj = nil
		for _, candidate in ipairs(expandedCandidates) do
			iconObj = ITEM_ICONS_FOLDER:FindFirstChild(candidate)
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
			for _, child in ipairs(ITEM_ICONS_FOLDER:GetChildren()) do
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

function UIManager.refreshInventory()
	local items = InventoryController.getItems()
	InventoryUI.RefreshSlots(items, getItemIcon, C, DataHelper)
	
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
	
	local totalWeight, maxWeight = InventoryController.getWeightInfo()
	InventoryUI.UpdateWeight(totalWeight, maxWeight, C)
	
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

local modalActionType = "DROP" -- DROP or SPLIT

function UIManager.openDropModal()
	if not selectedInvSlot then return end
	local item = InventoryController.getSlot(selectedInvSlot)
	if not item then return end
	
	modalActionType = "DROP"
	
	local m = InventoryUI.Refs.DropModal
	m.Frame.Visible = true
	m.Input.Text = tostring(item.count or 1)
	m.MaxLabel.Text = "(최대: " .. (item.count or 1) .. ")"
end

function UIManager.openSplitModal()
	if not selectedInvSlot then return end
	local item = InventoryController.getSlot(selectedInvSlot)
	if not item or not item.count or item.count <= 1 then return end
	
	modalActionType = "SPLIT"
	
	local m = InventoryUI.Refs.DropModal
	m.Frame.Visible = true
	m.Input.Text = tostring(math.floor(item.count / 2))
	m.MaxLabel.Text = "(최대: " .. (item.count - 1) .. ")"
end

function UIManager.getSelectedInvSlot()
	return selectedInvSlot
end

function UIManager.confirmModalAction(count)
	if not selectedInvSlot then return end
	local item = InventoryController.getSlot(selectedInvSlot)
	if not item then return end
	
	if modalActionType == "DROP" then
		local maxCount = item.count or 1
		local validCount = math.max(1, math.min(count, maxCount))
		InventoryController.requestDrop(selectedInvSlot, validCount)
	elseif modalActionType == "SPLIT" then
		local maxCount = (item.count or 1) - 1
		if maxCount >= 1 then
			local validCount = math.max(1, math.min(count, maxCount))
			-- Find empty slot
			local emptySlot = nil
			local items = InventoryController.getItems()
			for i=1, Balance.INV_SLOTS do
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
		InventoryController.requestEquip(idx, slot)
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
	
	local missing = {}
	for _, inp in ipairs(inputs) do
		local req = inp.count or inp.amount or 0
		local have = playerItemCounts[inp.itemId or inp.id] or 0
		if have < req then
			local itemName = inp.itemId or inp.id
			local itemData = DataHelper.GetData("ItemData", itemName)
			if itemData then itemName = itemData.name end
			table.insert(missing, string.format("%s (%d/%d)", itemName, have, req))
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
				nf.BackgroundColor3 = Color3.fromRGB(35,35,40)
				lockBG.Visible = true
				if st then st.Color = (recipe.id == selectedPersonalRecipeId) and C.GOLD or C.DIM end
			else
				lockBG.Visible = false
				if canCraft then
					icon.ImageColor3 = Color3.new(1,1,1)
					nf.BackgroundColor3 = Color3.fromRGB(50, 70, 50) -- Success hint
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
				UIManager.notify("제작 실패: " .. tostring(response), C.RED)
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
				UIManager.notify("제작 실패: " .. tostring(response), C.RED)
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
			UIManager.notify("구매 실패: "..(err or "잔액 부족"), C.RED)
		end
	end)
end

function UIManager.requestSell(slotIdx, count)
	ShopController.requestSell(activeShopId, slotIdx, count or 1, function(ok, err)
		if ok then
			UIManager.notify("판매 완료!", C.GOLD)
			UIManager.refreshShop()
		else
			UIManager.notify("판매 실패", C.RED)
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
	local allFacilities = require(ReplicatedStorage.Data.FacilityData) -- 최신 데이터 로드
	
	local CatFacMap = {
		BASIC = {"BUILDING", "CRAFTING_T1", "COOKING", "BASE_CORE", "RESPAWN"},
	}
	
	-- [Phase 1 리소스] 초원섬 기초 시설물만 허용
	local allowedIds = {
		CAMPFIRE = true,
		CAMP_TOTEM = true,
		LEAN_TO = true,
		BASIC_WORKBENCH = true
	}
	
	local targetTypes = CatFacMap[selectedBuildCat] or {}
	local list = {}
	for _, f in pairs(allFacilities) do
		if not allowedIds[f.id] then continue end -- 화이트리스트 필터링
		
		-- Filter by Category
		local match = false
		for _, tt in ipairs(targetTypes) do if f.functionType == tt then match = true; break end end
		
		if match then
			local fData = table.clone(f)
			-- 현재는 기술 해금 조건 없이 모두 해금된 것으로 처리 (사용자 요청)
			fData.isLocked = false 
			table.insert(list, fData)
		end
	end
	
	BuildUI.Refresh(list, {}, selectedBuildCat, UIManager.getItemIcon, UIManager)
end

----------------------------------------------------------------
-- Storage UI
----------------------------------------------------------------

function UIManager.openStorage(storageId, data)
	WindowManager.open("STORAGE", storageId, data)
end

function UIManager._onOpenStorage(storageId, data)
	currentStorageData = data
	StorageUI.Refs.Frame.Visible = true
	updateUIMode()
	
	if not blurEffect then
		blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	end
	
	UIManager.refreshStorage()
end

function UIManager.closeStorage()
	WindowManager.close("STORAGE")
end

function UIManager._onCloseStorage()
	if blurEffect then blurEffect:Destroy(); blurEffect = nil end
	currentStorageData = nil
	StorageUI.Refs.Frame.Visible = false
	-- 서버에 닫기 요청
	StorageController.closeStorage()
end

function UIManager.refreshStorage()
	if not WindowManager.isOpen("STORAGE") or not currentStorageData then return end
	
	local invData = InventoryController.getItems()
	StorageUI.Refresh(currentStorageData, invData, UIManager.getItemIcon, UIManager)
end

function UIManager._onStorageSlotClick(slot, fromType)
	StorageController.moveItem(slot, fromType)
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
	currentFacilityType = data and data.functionType or (fId and DataHelper.GetData("FacilityData", fId) and DataHelper.GetData("FacilityData", fId).functionType)
	selectedFacilityRecipe = nil
	
	FacilityUI.SetVisible(true)
	updateUIMode()

	if FacilityUI.Refs and FacilityUI.Refs.Title then
		if currentFacilityType == "CRAFTING_T1" then
			FacilityUI.Refs.Title.Text = UILocalizer.Localize("기초 작업대 제작")
		elseif currentFacilityType == "COOKING" then
			FacilityUI.Refs.Title.Text = UILocalizer.Localize("요리")
		elseif currentFacilityType and string.find(currentFacilityType, "SMELTING") then
			FacilityUI.Refs.Title.Text = UILocalizer.Localize("제련")
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
			local map = {
				INSUFFICIENT_GOLD = "골드가 부족합니다.",
				TOTEM_NOT_OWNER = "소유한 토템에서만 유지비를 결제할 수 있습니다.",
				TOTEM_NOT_FOUND = "토템을 찾을 수 없습니다.",
				BAD_REQUEST = "요청 정보가 올바르지 않습니다.",
				INVALID_COUNT = "결제 기간이 올바르지 않습니다.",
			}
			UIManager.notify(map[code] or ("유지비 결제 실패: " .. code), C.RED)
		end
	end)
end

function UIManager.highlightTotemZone()
	local TotemController = require(Controllers.TotemController)
	TotemController.flashPreview()
	UIManager.notify("영역 효과 범위를 확인하세요.", C.WHITE)
end

----------------------------------------------------------------
-- Collection UI
----------------------------------------------------------------

function UIManager.openCollection()
	WindowManager.open("COLLECTION")
end

function UIManager._onOpenCollection()
	if not blurEffect and not WindowManager.isOpen("INV") then
		blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	end
	
	CollectionUI.Show()
end

function UIManager.closeCollection()
	WindowManager.close("COLLECTION")
end

function UIManager._onCloseCollection()
	if blurEffect and not WindowManager.isAnyOpen() then blurEffect:Destroy(); blurEffect = nil end
	CollectionUI.Hide()
end

function UIManager.toggleCollection()
	WindowManager.toggle("COLLECTION")
end

function UIManager.refreshFacility()
	if not currentFacilityType then return end
	
	task.spawn(function()
		-- 1. Get recipes
		local allRecipes = require(ReplicatedStorage.Data.RecipeData)
		local recipes = {}
		for _, r in pairs(allRecipes) do
			if r.requiredFacility == currentFacilityType then
				table.insert(recipes, r)
			end
		end

		if currentFacilityType == "CRAFTING_T1" then
			local pinnedOrder = {
				CRAFT_SPLIT_LOG_TO_PLANK = 1,
				CRAFT_FIRM_STONE_AXE = 2,
				CRAFT_FIRM_STONE_PICKAXE = 3,
				CRAFT_BONE_SPEAR = 4,
				CRAFT_LEATHER_ARMOR = 5,
				CRAFT_FEATHER_HELMET = 6,
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
	
	task.spawn(function()
		local success, response = NetClient.Request("Craft.Start.Request", {
			recipeId = recipe.id,
			structureId = currentFacilityStructureId,
			count = batchCount,
		})
		
		if success then
			UIManager.notify(string.format("제작 의뢰 완료! x%d", batchCount), C.GOLD)
			UIManager.refreshFacility() -- Refresh to show in queue
		else
			UIManager.notify("제작 실패: " .. (response or "알 수 없는 오류"), C.RED)
		end
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
			UIManager.notify("수령 실패: " .. (response or "알 수 없는 오류"), C.RED)
		end
	end)
end



function UIManager._onBuildCategoryClick(catId)
	selectedBuildCat = catId
	UIManager.refreshBuild()
end

function UIManager._onBuildItemClick(data)
	selectedBuildId = data.id
	local isUnlocked = TechController.isFacilityUnlocked(data.id) -- TechController 사용
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
	local displayText = UILocalizer.Localize(text or "[Z] 상호작용")
	if targetName and targetName ~= "" then
		displayText = string.format("%s\n<font color='#ffd250' size='14'>%s</font>", displayText, targetName)
	end
	
	InteractUI.UpdatePrompt(displayText)
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
function UIManager.showBuildPrompt(visible)
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
	return TechController.isFacilityUnlocked(facilityId) -- TechController 사용
end

----------------------------------------------------------------
-- Event Listeners
----------------------------------------------------------------
local function setupEventListeners()
	InventoryController.onChanged(function()
		if WindowManager.isOpen("INV") then UIManager.refreshInventory() end
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

	-- Hotbar number keys
	local hotbarKeys = {Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight}
	for i = 1, 8 do
		InputManager.bindKey(hotbarKeys[i], "HB"..i, function() UIManager.selectHotbarSlot(i) end)
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

	-- Humanoid HP
	task.spawn(function()
		local char = player.Character or player.CharacterAdded:Wait()
		local hum = char:WaitForChild("Humanoid")
		UIManager.updateHealth(hum.Health, hum.MaxHealth)
		hum.HealthChanged:Connect(function(h) UIManager.updateHealth(h, hum.MaxHealth) end)
		player.CharacterAdded:Connect(function(c)
			local h2 = c:WaitForChild("Humanoid")
			UIManager.updateHealth(h2.Health, h2.MaxHealth)
			h2.HealthChanged:Connect(function(h) UIManager.updateHealth(h, h2.MaxHealth) end)
		end)
	end)

	-- Initial stats load
	task.spawn(function()
		task.wait(1)
		local ok, d = NetClient.Request("Player.Stats.Request", {})
		if ok and d then
			cachedStats = d
			if d.level then UIManager.updateLevel(d.level) end
			if d.currentXP and d.requiredXP then UIManager.updateXP(d.currentXP, d.requiredXP) end
			if d.statPointsAvailable then UIManager.updateStatPoints(d.statPointsAvailable) end
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
		
		uiScale.Scale = math.clamp(finalScale, 0.7, 1.5)
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
	EquipmentUI.Init(mainGui, UIManager, Enums, isMobile)
	equipmentUIFrame = EquipmentUI.Refs.Frame
	BuildUI.Init(mainGui, UIManager, isMobile)
	StorageUI.Init(mainGui, UIManager, isMobile)
	FacilityUI.Init(mainGui, UIManager, isMobile)
	CollectionUI.Init(mainGui, UIManager)
	TotemUI.Init(mainGui, UIManager, isMobile)
	PromptUI.Init()
	UILocalizer.StartAuto(mainGui)

	StorageController.Init()
	FacilityController.Init()
	CollectionController.Init()

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
	UIManager.updateHealth(100,100)
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
	WindowManager.register("COLLECTION", UIManager._onOpenCollection, UIManager._onCloseCollection)
	WindowManager.register("TOTEM", UIManager._onOpenTotem, UIManager._onCloseTotem)

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

return UIManager
