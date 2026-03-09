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

local Controllers = Client:WaitForChild("Controllers")
local InventoryController = require(Controllers.InventoryController)
local ShopController = require(Controllers.ShopController)
local BuildController = require(Controllers.BuildController)
local TechController = require(Controllers.TechController)
local StorageController = require(Controllers.StorageController)
local FacilityController = require(Controllers.FacilityController)
local DragDropController = require(Controllers.DragDropController)

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
local TechUI = require(UI.TechUI)
local InteractUI = require(UI.InteractUI)
local BuildUI = require(UI.BuildUI)
local EquipmentUI = require(UI.EquipmentUI)
local StorageUI = require(UI.StorageUI)
local FacilityUI = require(UI.FacilityUI)

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
local selectedBuildCat = "STRUCTURES"
local selectedFacilityId = nil -- shared with Crafting or use separate variable
local selectedBuildId = nil
local currentStorageData = nil
local currentFacilityData = nil
local currentFacilityStructureId = nil

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

-- 아이템 아이콘 가져오기 (폴더 검색 우선, 데이터 폴백)
local function getItemIcon(itemId: string): string
	if not itemId then return "" end
	
	-- CRAFT_ 나 SMELT_ 접두사가 있으면 제거
	local coreId = itemId:gsub("^CRAFT_", ""):gsub("^SMELT_", "")
	
	-- 1. Assets/ItemIcons 폴더에서 검색
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local iconsFolder = assets and (assets:FindFirstChild("ItemIcons") or assets:FindFirstChild("Images") or assets:FindFirstChild("Icons"))
	if iconsFolder then
		local iconObj = iconsFolder:FindFirstChild(coreId) or iconsFolder:FindFirstChild(itemId)
		if not iconObj then
			-- Case & Underscore insensitive search
			local target = coreId:lower():gsub("_", "")
			for _, child in ipairs(iconsFolder:GetChildren()) do
				local cname = child.Name:lower():gsub("_", "")
				if cname == target or cname:match("^"..target) then
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

	-- 2. If it's not found in folders, we return an empty string to be safe.
	return ""
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
		local slot = itemData.slot and itemData.slot:upper() or "HAND"
		-- [Phase 11] 한벌옷(SUIT) 장착 시 상하의가 해제됨을 유도하거나, 
		-- 그냥 서버에서 처리하도록 요청 (InventoryController.requestEquip)
		print("[UIManager] Quick Equip:", item.itemId, "to", slot)
		InventoryController.requestEquip(idx, slot)
	elseif itemData.type == "FOOD" or itemData.type == "CONSUMABLE" then
		InventoryController.requestUse(idx)
	end
end

function UIManager.onUseItem()
	if not selectedInvSlot then return end
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
			-- 작업대가 없으므로 모든 레시피를 인벤토리에서 보여줍니다 (단, 기술 해금 필요)
			local r = table.clone(recipe)
			r._isFacility = false
			table.insert(cachedPersonalRecipes, r)
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
		local TechController = require(Controllers.TechController)
		
		for _, recipe in ipairs(recipes) do
			local isLocked = not TechController.isRecipeUnlocked(recipe.id)
			local canCraft, _ = UIManager.checkMaterials(recipe)
			local node = personalCraftNodes[recipe.id]
			
			if not node then
				local nodeCount = 0
				for _ in pairs(personalCraftNodes) do nodeCount = nodeCount + 1 end
				local idx = nodeCount + 1
				local nf = mkFrame({name="PNode"..idx, size=UDim2.new(1,0,1,0), bg=C.BG_SLOT, r=6, stroke=1.5, strokeC=isLocked and C.DIM or C.BORDER, z=12, parent=invPersonalCraftGrid})
				
				local icon = Instance.new("ImageLabel")
				icon.Name="Icon"; icon.Size=UDim2.new(0.7,0,0.7,0); icon.Position=UDim2.new(0.5,0,0.5,0)
				icon.AnchorPoint=Vector2.new(0.5,0.5); icon.BackgroundTransparency=1; icon.ScaleType=Enum.ScaleType.Fit; icon.ZIndex=13; icon.Parent=nf
				
				-- Priority: Output item icon > Recipe ID icon
				local iconId = ""
				if recipe.outputs and recipe.outputs[1] then
					iconId = getItemIcon(recipe.outputs[1].itemId)
				end
				if iconId == "" or iconId == "rbxassetid://15573752528" then
					local ridIcon = getItemIcon(recipe.id)
					if ridIcon ~= "" and ridIcon ~= "rbxassetid://15573752528" then iconId = ridIcon end
				end
				icon.Image = iconId
				
				local iconLbl = mkLabel({text=recipe.name, size=UDim2.new(0.9,0,0.9,0), pos=UDim2.new(0.5,0,0.5,0), anchor=Vector2.new(0.5,0.5), ts=8, color=C.WHITE, wrap=true, z=14, parent=nf})
				iconLbl.Visible = (iconId == "" or iconId == "rbxassetid://15573752528")

				local lockBG = mkFrame({name="LockBG", size=UDim2.new(1,0,1,0), bg=Color3.new(0.1,0.1,0.1), bgT=0.5, r=6, z=20, parent=nf})
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
	
	local isLocked = not TechController.isRecipeUnlocked(recipe.id)
	
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
	local isLocked = not TechController.isRecipeUnlocked(recipe.id)
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

function UIManager.showCraftingProgress(duration)
	if isCrafting then return end
	isCrafting = true
	
	-- 1. 상단 채집바 표시 (기존 유지)
	HUDUI.ShowHarvestProgress(duration, "제작 중...")
	
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

		-- [기술 잠금 체크]
		if not TechController.isRecipeUnlocked(recipe.id) then
			UIManager.notify("기술 해금이 필요합니다.", C.RED)
			return
		end

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
					UIManager.notify((recipe.name or "아이템") .. " 제작 완료!", C.GREEN)
					UIManager.refreshInventory()
					UIManager.refreshPersonalCrafting() 
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
				end
			else
				UIManager.stopCraftingProgress()
				UIManager.notify("제작 실패: " .. tostring(response), C.RED)
			end
		end)
	end
end

----------------------------------------------------------------
-- Public API: Tech Tree
----------------------------------------------------------------
function UIManager.openTechTree()
	WindowManager.open("TECH")
end

function UIManager._onOpenTechTree()
	TechUI.SetVisible(true)
	updateUIMode()
	
	-- Blur
	if not WindowManager.isOpen("CRAFT") then
		blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	end
	
	task.spawn(function()
		TechController.requestTechInfo()
	end)
	
	UIManager.refreshTechTree()
end

function UIManager.closeTechTree()
	WindowManager.close("TECH")
end

function UIManager._onCloseTechTree()
	if blurEffect and not WindowManager.isOpen("CRAFT") then blurEffect:Destroy(); blurEffect = nil end
	TechUI.SetVisible(false)
	selectedTechId = nil
end

function UIManager.toggleTechTree()
	WindowManager.toggle("TECH")
end

function UIManager.refreshTechTree()
	local tp = TechController.getTechPoints()
	local tree = TechController.getTechTree()
	local unlocked = TechController.getUnlockedTech()
	local playerLevel = (cachedStats and cachedStats.level) or 1
	
	-- techTreeData가 비어있으면 TechUnlockData를 클라이언트에서 직접 로드 (서버 응답 대기 불필요)
	local isEmpty = true
	for _ in pairs(tree) do isEmpty = false; break end
	
	if isEmpty then
		local TechUnlockData = require(ReplicatedStorage.Data.TechUnlockData)
		tree = {}
		for _, techEntry in ipairs(TechUnlockData) do
			tree[techEntry.id] = techEntry
		end
		print("[UIManager] Tech tree loaded from local data (", 0 + #TechUnlockData, "entries)")
	end
	
	local techList = {}
	for id, data in pairs(tree) do table.insert(techList, data) end
	table.sort(techList, function(a,b) 
		local al = a.requireLevel or 1
		local bl = b.requireLevel or 1
		if al ~= bl then return al < bl end
		return (a.id or "") < (b.id or "")
	end)
	
	TechUI.Refresh(techList, unlocked, tp, playerLevel, getItemIcon, UIManager)
end

function UIManager.isTechUnlocked(techId)
	return TechController.isUnlocked(techId)
end

function UIManager._onTechNodeClick(node)
	if not node then
		selectedTechId = nil
		TechUI.UpdateDetail(nil, false, false, 1, UIManager, getItemIcon)
		return
	end
	
	selectedTechId = node.id
	local unlocked = TechController.getUnlockedTech()
	local isUnlocked = unlocked[node.id]
	
	local canAfford = true
	local playerItemCounts = InventoryController.getItemCounts()
	if node.cost then
		for _, req in ipairs(node.cost) do
			local amount = playerItemCounts[req.itemId] or 0
			if amount < req.amount then
				canAfford = false
				break
			end
		end
	end
	
	local playerLevel = (cachedStats and cachedStats.level) or 1
	
	TechUI.UpdateDetail(node, isUnlocked, canAfford, playerLevel, UIManager, getItemIcon)
end

function UIManager._doUnlockTech()
	if not selectedTechId then return end
	TechController.requestUnlock(selectedTechId, function(success, err)
		if success then
			-- Popup handled by event listener
			UIManager.refreshTechTree()
		else
			UIManager.notify("연구 실패: " .. (err or "포인트 부족"), C.RED)
		end
	end)
end

function UIManager._doResetTech()
	-- Simple confirmation toast first? Or just do it.
	TechController.requestReset(function(success)
		if success then
			UIManager.notify("기술 트리가 초기화되었습니다.", C.GOLD)
			UIManager.refreshTechTree()
			if WindowManager.isOpen("INV") and invCraftContainer and invCraftContainer.Visible then
				UIManager.refreshPersonalCrafting(true)
			end
			if WindowManager.isOpen("BUILD") then UIManager.refreshBuild() end
		end
	end)
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
	
	if not WindowManager.isOpen("CRAFT") and not WindowManager.isOpen("TECH") then
		blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	end
	
	UIManager.refreshBuild()
end

function UIManager.closeBuild()
	WindowManager.close("BUILD")
end

function UIManager._onCloseBuild()
	if blurEffect and not WindowManager.isOpen("CRAFT") and not WindowManager.isOpen("TECH") then blurEffect:Destroy(); blurEffect = nil end
	BuildUI.Refs.Frame.Visible = false
end

function UIManager.toggleBuild()
	WindowManager.toggle("BUILD")
end

function UIManager.refreshBuild()
	local allFacilities = require(ReplicatedStorage.Data.FacilityData) -- 최신 데이터 로드
	
	local CatFacMap = {
		STRUCTURES = {"BUILDING"},
		PRODUCTION = {"CRAFTING_T1", "CRAFTING_T2", "CRAFTING_T3", "SMELTING_T1", "SMELTING_T2", "COOKING", "REPAIR"},
		SURVIVAL = {"STORAGE", "BASE_CORE", "FARMING", "FEEDING", "RESTING"}
	}
	
	local targetTypes = CatFacMap[selectedBuildCat] or {}
	local list = {}
	for _, f in pairs(allFacilities) do
		-- Filter by Category
		local match = false
		for _, tt in ipairs(targetTypes) do if f.functionType == tt then match = true; break end end
		
		if match then
			local fData = table.clone(f)
			-- 건축물도 잠금 상태를 표시하기 위해 정보 추가
			fData.isLocked = not TechController.isFacilityUnlocked(fData.id)
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
	if not isStorageOpen or not currentStorageData then return end
	
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
	currentFacilityData = data
	FacilityUI.Refs.Frame.Visible = true
	updateUIMode()
	
	if not blurEffect then
		blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	end
	
	UIManager.refreshFacility()
end

function UIManager.closeFacility()
	WindowManager.close("FACILITY")
end

function UIManager._onCloseFacility()
	if blurEffect then blurEffect:Destroy(); blurEffect = nil end
	currentFacilityStructureId = nil
	currentFacilityData = nil
	FacilityUI.Refs.Frame.Visible = false
	FacilityController.closeFacility()
end

function UIManager.refreshFacility()
	if not isFacilityOpen or not currentFacilityData then return end
	
	local invData = InventoryController.getItems()
	FacilityUI.Refresh(currentFacilityData, invData, UIManager.getItemIcon, DataHelper.GetData, UIManager)
end

function UIManager._onInventoryToFacility(slot)
	local item = InventoryController.getSlot(slot)
	if not item then return end
	
	local itemData = DataHelper.GetData("ItemData", item.itemId)
	if not itemData then return end
	
	-- 연료 우선 판정
	if itemData.fuelValue and itemData.fuelValue > 0 then
		FacilityController.addFuel(slot)
	else
		-- 아니면 재료로 투입
		FacilityController.addInput(slot)
	end
end

function UIManager._onCollectFacility()
	FacilityController.collectOutput()
end

function UIManager._onFacilityFuelClick()
	FacilityController.removeFuel()
end

function UIManager._onFacilityInputClick()
	FacilityController.removeInput()
end



function UIManager._onBuildCategoryClick(catId)
	selectedBuildCat = catId
	UIManager.refreshBuild()
end

function UIManager._onBuildItemClick(data)
	selectedBuildId = data.id
	local isUnlocked = TechController.isFacilityUnlocked(data.id)
	local playerItemCounts = InventoryController.getItemCounts()
	local ok, _ = UIManager.checkMaterials(data, playerItemCounts)
	BuildUI.UpdateDetail(data, ok, getItemIcon, isUnlocked, playerItemCounts, DataHelper)
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
	
	UIManager.closeBuild()
	BuildController.startPlacement(selectedBuildId)
end

----------------------------------------------------------------
-- Public API: Interact / Harvest
----------------------------------------------------------------
function UIManager.showInteractPrompt(text, targetName)
	local displayText = text or "[Z] 상호작용"
	if targetName and targetName ~= "" then
		displayText = string.format("%s\n<font color='#ffd250'>%s</font>", displayText, targetName)
	end
	HUDUI.showInteractPrompt(displayText)
end

function UIManager.hideInteractPrompt()
	HUDUI.hideInteractPrompt()
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
	
	-- 이전 알림창이 남아있다면 즉시 제거 (글자 겹침 방지)
	if currentToast and currentToast.Parent then
		currentToast:Destroy()
	end
	
	-- Toast style (Durango 반투명 컨벤션에 맞춤)
	local toast = Utils.mkFrame({
		name = "Toast",
		size = UDim2.new(0, 300, 0, 40),
		pos = UDim2.new(0.5, 0, 0.2, -50),
		anchor = Vector2.new(0.5, 0.5),
		bg = C.BG_PANEL,
		bgT = 0.95, -- 유리 수준으로 매우 투명하게 변경
		r = 20,
		parent = mainGui
	})
	
	local label = Utils.mkLabel({
		text = text,
		ts = 16,
		color = color or C.WHITE,
		font = F.TITLE,
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

-- [New] Side Notification (Corner stack)
function UIManager.sideNotify(text, color, icon)
	if not mainGui then return end
	
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
		bgT = 0.3,
		stroke = 1,
		strokeC = color or C.GOLD,
		r = 8,
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

function UIManager.checkFacilityUnlocked(facilityId)
	return TechController.isFacilityUnlocked(facilityId)
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
					UIManager.notify(" 레벨업! Lv. "..d.level, C.GOLD)
				end
				if d.statPointsAvailable ~= nil then UIManager.updateStatPoints(d.statPointsAvailable) end
				if WindowManager.isOpen("EQUIP") then UIManager.refreshStats() end
			end
		end)
		
		NetClient.On("Player.Stats.Upgraded", function(data)
			UIManager.notify(" 💪 능력치 강화 성공!", C.GREEN)
			-- refreshStats는 Stats.Changed에 의해 호출됨
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
	
	-- Tech Events
	TechController.onTechUpdated(function()
		if WindowManager.isOpen("TECH") then UIManager.refreshTechTree() end
		if WindowManager.isOpen("CRAFT") then UIManager.refreshPersonalCrafting() end
		if WindowManager.isOpen("BUILD") then UIManager.refreshBuild() end
	end)
	
	TechController.onTechUnlocked(function(data)
		if data and data.name then
			UIManager.notify("💡 기술 연구 완료: " .. data.name, C.GOLD_SEL)
			if WindowManager.isOpen("TECH") and data.techId then
				local node = {id = data.techId, name = data.name}
				TechUI.ShowUnlockSuccessPopup(node, getItemIcon, mainGui)
			end
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
				if recipe then itemName = recipe.name end
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
	TechUI.Init(mainGui, UIManager, isMobile)
	InteractUI.Init(mainGui, isMobile)
	EquipmentUI.Init(mainGui, UIManager, Enums, isMobile)
	equipmentUIFrame = EquipmentUI.Refs.Frame
	BuildUI.Init(mainGui, UIManager, isMobile)
	StorageUI.Init(mainGui, UIManager, isMobile)
	FacilityUI.Init(mainGui, UIManager, isMobile)

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
	WindowManager.register("TECH", UIManager._onOpenTechTree, UIManager._onCloseTechTree)
	WindowManager.register("SHOP", UIManager._onOpenShop, UIManager._onCloseShop)
	WindowManager.register("BUILD", UIManager._onOpenBuild, UIManager._onCloseBuild)
	WindowManager.register("STORAGE", UIManager._onOpenStorage, UIManager._onCloseStorage)
	WindowManager.register("FACILITY", UIManager._onOpenFacility, UIManager._onCloseFacility)

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
