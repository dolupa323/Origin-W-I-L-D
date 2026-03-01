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
local inventoryFrame, statusFrame, craftingOverlay, shopFrame, techOverlay, interactPrompt
local actionContainer, hotbarFrame -- Store refs for visibility control
local craftDetailPanel, progFill, craftSpinner
local isInvOpen, isStatusOpen, isCraftOpen, isShopOpen, isTechOpen, isBuildOpen, isEquipmentOpen = false, false, false, false, false, false, false
local cachedStats = {}
local pendingStats = {}
local activeDebuffs = {} -- { [debuffId] = {id, name, startTime, duration} }
local selectedBuildCat = "STRUCTURES"
local selectedFacilityId = nil -- shared with Crafting or use separate variable
local selectedBuildId = nil

-- 0. UI 관리 헬퍼
local function isAnyWindowOpen()
	return isInvOpen or isCraftOpen or isShopOpen or isTechOpen or isBuildOpen or isEquipmentOpen or isStatusOpen
end

local function updateUIMode()
	local anyOpen = isAnyWindowOpen()
	InputManager.setUIOpen(anyOpen)
	UIManager._setMainHUDVisible(not anyOpen)
end

local function closeAllWindows(except)
	if isInvOpen and except ~= "INV" then UIManager.closeInventory() end
	if isCraftOpen and except ~= "CRAFT" then UIManager.closeCrafting() end
	if isShopOpen and except ~= "SHOP" then UIManager.closeShop() end
	if isTechOpen and except ~= "TECH" then UIManager.closeTechTree() end
	if isBuildOpen and except ~= "BUILD" then UIManager.closeBuild() end
	if isEquipmentOpen and except ~= "EQUIP" then UIManager.closeEquipment() end
end

----------------------------------------------------------------
-- Public API: Tech (K키)
----------------------------------------------------------------
function UIManager.openTechTree()
	if isTechOpen then return end
	closeAllWindows("TECH")
	isTechOpen = true
	InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
	
	-- Blur
	if not blurEffect then
		blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	end
	
	TechUI.SetVisible(true)
	UIManager.refreshTechTree()
end

function UIManager.closeTechTree()
	if not isTechOpen then return end
	if blurEffect then blurEffect:Destroy(); blurEffect = nil end
	isTechOpen = false
	TechUI.SetVisible(false)
	updateUIMode()
end

function UIManager.toggleTechTree()
	if isTechOpen then UIManager.closeTechTree() else UIManager.openTechTree() end
end

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

function UIManager.refreshStats()
	if not cachedStats then return end
	local equipmentData = InventoryController.getEquipment and InventoryController.getEquipment() or {}
	local totalPending = 0
	for _, v in pairs(pendingStats) do totalPending = totalPending + (v or 0) end
	EquipmentUI.Refresh(cachedStats, totalPending, equipmentData, getItemIcon, Enums)
end

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
		local ok, data = NetClient.Request("Player.Stats.Upgrade", {stats = pendingStats})
		if ok then
			pendingStats = {}
			-- cachedStats는 Player.Stats.Changed 이벤트로 업데이트됨
		else
			UIManager.notify("강화 실패: " .. tostring(data), C.RED)
		end
	end)
end
----------------------------------------------------------------
-- Public API: Equipment (장비창)
----------------------------------------------------------------
function UIManager.openEquipment()
	if isEquipmentOpen then return end
	closeAllWindows("EQUIP")
	isEquipmentOpen = true
	
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
	if not isEquipmentOpen then return end
	isEquipmentOpen = false
	EquipmentUI.SetVisible(false)
	updateUIMode()
end

function UIManager.toggleEquipment()
	if isEquipmentOpen then UIManager.closeEquipment() else UIManager.openEquipment() end
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

-- Drag & Drop
local isDragging = false
local DRAG_THRESHOLD = 5 -- Lower threshold for easier dragging
local pendingDragIdx = nil
local draggingSlotIdx = nil
local dragStartPos = Vector2.zero
local dragDummy = nil

local cachedPersonalRecipes = nil


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

function UIManager.confirmPendingStats()
	local toUpgrade = {}
	for statId, amount in pairs(pendingStats) do
		if amount > 0 then
			for i=1, amount do table.insert(toUpgrade, statId) end
		end
	end
	
	if #toUpgrade == 0 then return end
	
	task.spawn(function()
		local allOk = true
		for _, statId in ipairs(toUpgrade) do
			local ok, _ = NetClient.Request("Player.Stats.Upgrade.Request", {statId = statId})
			if not ok then allOk = false break end
		end
		
		if allOk then
			local ok2, stats = NetClient.Request("Player.Stats.Request", {})
			if ok2 and stats then
				cachedStats = stats
				pendingStats = {}
				UIManager.refreshStats()
			end
			UIManager.notify("추가 완료!", C.GOLD)
		else
			pendingStats = {}
			UIManager.refreshStats()
			UIManager.notify("일부 적용에 실패했습니다.", C.RED)
		end
	end)
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
		task.spawn(function()
			NetClient.Request("Inventory.ActiveSlot.Request", {slot = idx})
		end)
	end
end

function UIManager.getSelectedSlot()
	return selectedSlot
end

-- 아이템 아이콘 가져오기 (폴더 검색 우선, 데이터 폴백)
local function getItemIcon(itemId: string): string
	-- 1. Assets/ItemIcons 폴더에서 검색
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local iconsFolder = assets and assets:FindFirstChild("ItemIcons")
	if iconsFolder then
		local iconObj = iconsFolder:FindFirstChild(itemId)
		if not iconObj then
			-- Case-insensitive & Prefix search
			local target = itemId:lower()
			for _, child in ipairs(iconsFolder:GetChildren()) do
				local cname = child.Name:lower()
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
			end
		end
	end

	-- 2. ItemData.lua 필드 확인
	local itemData = DataHelper.GetData("ItemData", itemId)
	if itemData and itemData.icon and itemData.icon ~= "" then
		return itemData.icon
	end

	-- 3. 기본 이미지 (플레이스홀더)
	return "rbxassetid://15573752528" -- Stone icon as fallback for now
end

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
function UIManager.openInventory(startTab)
	if isInvOpen then 
		if startTab then InventoryUI.SetTab(startTab) end
		return 
	end
	
	-- 만약 단축키 등으로 직접 여는 것이라면 시설 정보 초기화
	-- (openWorkbench를 통해 들어온 것이 아님을 보장)
	if not startTab or startTab == "BAG" then
		activeFacilityId = nil
		activeStructureId = nil
	end

	closeAllWindows("INV")
	isInvOpen = true
	InventoryUI.SetVisible(true)
	InventoryUI.SetTab(startTab or "BAG")
	InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
	UIManager.refreshInventory()
	if startTab == "CRAFT" then
		UIManager.refreshPersonalCrafting(true)
	end
end

function UIManager.closeInventory()
	if not isInvOpen then return end
	
	-- 드래그 상태 강제 초기화 (Drag & Drop Cleanup)
	if isDragging then
		isDragging = false
		if dragDummy then
			dragDummy:Destroy()
			dragDummy = nil
		end
		pendingDragIdx = nil
		draggingSlotIdx = nil
	end
	
	isInvOpen = false
	InventoryUI.SetVisible(false)
	updateUIMode()
end

function UIManager.toggleInventory(startTab)
	if isInvOpen then UIManager.closeInventory() else UIManager.openInventory(startTab) end
end

function UIManager.refreshInventory()
	local items = InventoryController.getItems()
	InventoryUI.RefreshSlots(items, getItemIcon, C, DataHelper)
	
	local totalWeight, maxWeight = InventoryController.getWeightInfo()
	InventoryUI.UpdateWeight(totalWeight, maxWeight, C)
	
	UIManager.refreshHotbar()
end

function UIManager.refreshStats()
	local totalPending = 0
	for _, v in pairs(pendingStats) do totalPending = totalPending + v end
	
	if isEquipmentOpen then
		local equipmentData = InventoryController.getEquipment and InventoryController.getEquipment() or {}
		EquipmentUI.Refresh(cachedStats, totalPending, equipmentData, getItemIcon, Enums)
	end
end

----------------------------------------------------------------
-- Inventory Drag & Drop Logic
----------------------------------------------------------------
function UIManager.handleDragStart(idx, input)
	if isDragging then return end
	
	local items = InventoryController.getItems()
	local item = items[idx]
	if not item or not item.itemId then return end

	pendingDragIdx = idx
	dragStartPos = UserInputService:GetMouseLocation()
end

function UIManager.handleDragUpdate(input)
	if pendingDragIdx and not isDragging then
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local mousePos = UserInputService:GetMouseLocation()
			if (mousePos - dragStartPos).Magnitude > DRAG_THRESHOLD then
				isDragging = true
				draggingSlotIdx = pendingDragIdx
				pendingDragIdx = nil
				
				local items = InventoryController.getItems()
				local item = items[draggingSlotIdx]
				
				-- Create dummy
				if dragDummy then dragDummy:Destroy() end
				dragDummy = Instance.new("ImageLabel")
				dragDummy.Name = "DragDummy"
				dragDummy.Size = UDim2.new(0, 56, 0, 56)
				dragDummy.BackgroundTransparency = 0.4
				dragDummy.Image = getItemIcon(item.itemId)
				dragDummy.ZIndex = 2000
				dragDummy.Parent = mainGui
				
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 8)
				corner.Parent = dragDummy
			end
		end
	end

	if not isDragging or not dragDummy then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		local inset = GuiService:GetGuiInset()
		local mousePos = UserInputService:GetMouseLocation()
		local actualX = mousePos.X - inset.X
		local actualY = mousePos.Y - inset.Y
		dragDummy.Position = UDim2.new(0, actualX - 28, 0, actualY - 28) -- Center dummy on mouse
	end
end

function UIManager.handleDragEnd(input)
	if not isDragging then 
		pendingDragIdx = nil
		return 
	end
	isDragging = false

	if dragDummy then
		dragDummy:Destroy()
		dragDummy = nil
	end

	-- Check which slot we are over
	local mousePos = UserInputService:GetMouseLocation()
	local foundSlot = nil
	local padding = 10 -- Broader detection
	
	-- Check Bag Slots
	if isInvOpen and invSlots then
		for i, s in pairs(invSlots) do
			if s and s.frame and s.frame.Visible and s.frame.AbsoluteSize.X > 0 then
				local absPos = s.frame.AbsolutePosition
				local absSize = s.frame.AbsoluteSize
				if mousePos.X >= absPos.X - padding and mousePos.X <= absPos.X + absSize.X + padding and
				   mousePos.Y >= absPos.Y - padding and mousePos.Y <= absPos.Y + absSize.Y + padding then
					foundSlot = i
					break
				end
			end
		end
	end

	-- Check Hotbar Slots
	if not foundSlot and hotbarSlots then
		for i, s in pairs(hotbarSlots) do
			if s and s.frame and s.frame.Visible and s.frame.AbsoluteSize.X > 0 then
				local absPos = s.frame.AbsolutePosition
				local absSize = s.frame.AbsoluteSize
				if mousePos.X >= absPos.X - padding and mousePos.X <= absPos.X + absSize.X + padding and
				   mousePos.Y >= absPos.Y - padding and mousePos.Y <= absPos.Y + absSize.Y + padding then
					foundSlot = i
					break
				end
			end
		end
	end

	if foundSlot and foundSlot ~= draggingSlotIdx then
		print("[UIManager] Swapping:", draggingSlotIdx, "->", foundSlot)
		InventoryController.swapSlots(draggingSlotIdx, foundSlot)
	else
		print("[UIManager] No valid target slot found")
	end

	draggingSlotIdx = nil
	pendingDragIdx = nil
end

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
	if not isInvOpen then return end
	selectedInvSlot = idx
	local items = InventoryController.getItems()
	local data = items[idx]
	InventoryUI.UpdateDetail(data, getItemIcon, Enums, DataHelper)
	InventoryUI.UpdateSlotSelectionHighlight(idx, items, DataHelper)
end

function UIManager.onInventorySlotClick(idx)
	UIManager._onInvSlotClick(idx)
end

function UIManager.onUseItem()
	if not selectedInvSlot then return end
	InventoryController.requestUse(selectedInvSlot)
end

function UIManager.onInventorySlotRightClick(idx)
	if not isInvOpen or not idx then return end
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
	if not invDetailPanel then return end
	
	local playerItemCounts = InventoryController.getItemCounts()
	local isLocked = not TechController.isRecipeUnlocked(recipe.id)
	local canCraft, _ = UIManager.checkMaterials(recipe, playerItemCounts)
	
	-- Reuse CraftingUI's logic but tailored for Inventory's refactored detail panel if possible. 
	-- For now, let's just manually update InventoryUI.Refs.Detail components.
	local d = InventoryUI.Refs.Detail
	if d.Frame then
		d.Name.Text = recipe.name or recipe.id
		local outItem = recipe.outputs and recipe.outputs[1] and recipe.outputs[1].itemId or recipe.id
		d.PreviewIcon.Image = getItemIcon(outItem)
		d.PreviewIcon.Visible = true
		
		local DataHelper = require(ReplicatedStorage.Shared.Util.DataHelper)
		local itemData = DataHelper.GetData("ItemData", outItem)
		d.Desc.Text = ""
		
		d.Stats.Visible = false
		d.Weight.Text = ""
		
		local recipe = recipe -- Redundant but safe
		d.Mats.RichText = true
		if isLocked then
			d.Mats.Text = "<font color=\"#E63232\">기술 트리(K)에서 해금이 필요합니다.</font>"
			d.BtnUse.Text = "잠김 (해금 필요)"
			d.BtnUse.BackgroundColor3 = C.BTN_DIS
		else
			local matsText = ""
			for _, inp in ipairs(recipe.inputs or {}) do
				local have = playerItemCounts[inp.itemId or inp.id] or 0
				local req = inp.count or 0
				local matId = inp.itemId or inp.id
				local matData = DataHelper.GetData("ItemData", matId)
				local matName = matData and matData.name or matId
				local color = (have >= req) and "#8CDC64" or "#E63232"
				matsText = matsText .. string.format("<font color=\"%s\">%s %d/%d</font>\n", color, matName, have, req)
			end
			d.Mats.Text = "필요 재료:\n" .. matsText
			d.BtnUse.Text = "제작하기"
			d.BtnUse.BackgroundColor3 = canCraft and C.GOLD_SEL or C.BTN_DIS
		end
		d.BtnUse.Visible = true
		d.BtnDrop.Visible = false
	end
	
	if progFill then progFill.Size = UDim2.new(0,0,1,0) end
end

local isCrafting = false
local craftTween = nil
local spinnerConn = nil

function UIManager.showCraftingProgress(duration)
	if isCrafting then return end
	isCrafting = true
	HUDUI.ShowHarvestProgress(duration, "제작 중...")
end

function UIManager.stopCraftingProgress()
	isCrafting = false
	HUDUI.HideHarvestProgress()
end
function UIManager._doCraft()
	-- 인벤토리 내 제작 탭 처리 (아이템 제작 전용)
	if isInvOpen and invCraftContainer and invCraftContainer.Visible then
		if not selectedPersonalRecipeId then return end
		
		local recipe = nil
		for _, r in ipairs(cachedPersonalRecipes or {}) do
			if r.id == selectedPersonalRecipeId then recipe = r; break end
		end
		if not recipe then return end

		-- [기술 잠금 체크] - 인벤토리 제작은 RecipeData이므로 isRecipeUnlocked 사용
		if not TechController.isRecipeUnlocked(recipe.id) then
			UIManager.notify("기술 해금이 필요합니다.", C.RED)
			return
		end

		-- 재료 체크
		local ok, msg = UIManager.checkMaterials(recipe)
		if not ok then UIManager.notify(msg, C.RED); return end

		-- 제작 프로세스 시작
		UIManager.showCraftingProgress(recipe.craftTime or 3)
		
		task.spawn(function()
			local resultOk, response = NetClient.Request("Recipe.Craft.Request", {
				recipeId = selectedPersonalRecipeId
			})
			
			UIManager.stopCraftingProgress()
			if resultOk then
				UIManager.notify((recipe.name or "아이템") .. " 제작 완료!", C.GREEN)
				UIManager.refreshInventory()
				UIManager.refreshPersonalCrafting() 
			else
				UIManager.notify("제작 실패: " .. tostring(response), C.RED)
			end
		end)
	end
end

----------------------------------------------------------------
-- Public API: Tech Tree
----------------------------------------------------------------
function UIManager.openTechTree()
	if isTechOpen then return end
	closeAllWindows("TECH")
	isTechOpen = true
	TechUI.SetVisible(true)
	InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
	
	-- Blur
	if not isCraftOpen then
		blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	end
	
	UIManager.refreshTechTree()
end

function UIManager.closeTechTree()
	if not isTechOpen then return end
	if blurEffect and not isCraftOpen then blurEffect:Destroy(); blurEffect = nil end
	isTechOpen = false
	TechUI.SetVisible(false)
	selectedTechId = nil
	if not isInvOpen and not isShopOpen and not isStatusOpen and not isCraftOpen then 
		InputManager.setUIOpen(false) 
		UIManager._setMainHUDVisible(true)
	end
end

function UIManager.toggleTechTree()
	if isTechOpen then UIManager.closeTechTree() else UIManager.openTechTree() end
end

function UIManager.refreshTechTree()
	local tp = TechController.getTechPoints()
	local tree = TechController.getTechTree()
	local unlocked = TechController.getUnlockedTech()
	local playerLevel = (cachedStats and cachedStats.level) or 1
	
	local techList = {}
	for id, data in pairs(tree) do table.insert(techList, data) end
	table.sort(techList, function(a,b) 
		if a.techLevel ~= b.techLevel then return a.techLevel < b.techLevel end
		return a.id < b.id
	end)
	
	TechUI.Refresh(techList, unlocked, tp, getItemIcon, UIManager)
end

function UIManager.isTechUnlocked(techId)
	return TechController.isUnlocked(techId)
end

function UIManager._onTechNodeClick(node)
	selectedTechId = node.id
	local unlocked = TechController.getUnlockedTech()
	local tp = TechController.getTechPoints()
	local isUnlocked = unlocked[node.id]
	local canAfford = (tp >= (node.techPointCost or 0))
	
	TechUI.UpdateDetail(node, isUnlocked, canAfford, UIManager, getItemIcon)
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
			if isCraftOpen then UIManager.refreshCrafting() end
		end
	end)
end

----------------------------------------------------------------
-- Public API: Shop
----------------------------------------------------------------
function UIManager.openShop(shopId)
	if isShopOpen then return end
	closeAllWindows("SHOP")
	isShopOpen = true
	ShopUI.SetVisible(true)
	InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
	
	ShopController.requestShopInfo(shopId, function(ok, shopInfo)
		if ok then
			UIManager.refreshShop(shopId)
		end
	end)
end

function UIManager.closeShop()
	if not isShopOpen then return end
	isShopOpen = false
	ShopUI.SetVisible(false)
	updateUIMode()
end

function UIManager.refreshShop(shopId)
	local shopInfo = ShopController.getShopItems(shopId)
	local playerItems = InventoryController.getItems()
	local gold = InventoryController.getGold()
	
	ShopUI.UpdateGold(gold)
	ShopUI.Refresh(shopInfo, playerItems, getItemIcon, C, UIManager)
end

function UIManager.requestBuy(itemId)
	ShopController.requestBuy(itemId, function(ok, err)
		if ok then
			UIManager.notify("구매 완료!", C.GOLD)
			UIManager.refreshShop()
		else
			UIManager.notify("구매 실패: "..(err or "잔액 부족"), C.RED)
		end
	end)
end

function UIManager.requestSell(slotIdx)
	ShopController.requestSell(slotIdx, function(ok, err)
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
	if isBuildOpen then return end
	closeAllWindows("BUILD")
	isBuildOpen = true
	BuildUI.Refs.Frame.Visible = true
	InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
	
	if not isCraftOpen and not isTechOpen then
		blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	end
	
	UIManager.refreshBuild()
end

function UIManager.closeBuild()
	if not isBuildOpen then return end
	if blurEffect and not isCraftOpen and not isTechOpen then blurEffect:Destroy(); blurEffect = nil end
	isBuildOpen = false
	BuildUI.Refs.Frame.Visible = false
	updateUIMode()
end

function UIManager.toggleBuild()
	if isBuildOpen then UIManager.closeBuild() else UIManager.openBuild() end
end

function UIManager.refreshBuild()
	local allFacilities = require(ReplicatedStorage.Data.FacilityData) -- 최신 데이터 로드
	
	local CatFacMap = {
		STRUCTURES = {"BUILDING"},
		PRODUCTION = {"CRAFTING", "SMELTING", "COOKING", "REPAIR"},
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
	
	BuildUI.Refresh(list, {}, selectedBuildCat, getItemIcon, UIManager)
end

function UIManager._onBuildCategoryClick(catId)
	selectedBuildCat = catId
	UIManager.refreshBuild()
end

function UIManager._onBuildItemClick(data)
	selectedBuildId = data.id
	local isUnlocked = TechController.isFacilityUnlocked(data.id)
	local ok, _ = UIManager.checkMaterials(data)
	BuildUI.UpdateDetail(data, ok, getItemIcon, isUnlocked)
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

-- 알림 표시 (중개 하단 -> 중앙 상단 토스트 스타일)
local currentToast = nil

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
		color = color or C.WHITE, -- 기존처럼 컬러를 받되 흰색 베이스 유지
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
		if isInvOpen then UIManager.refreshInventory() end
		UIManager.refreshHotbar()
		if invCraftContainer and invCraftContainer.Visible then
			UIManager.refreshPersonalCrafting()
		end
	end)
	ShopController.onGoldChanged(function(g) UIManager.updateGold(g) end)
	TechController.onTechUpdated(function()
		if isTechOpen then UIManager.refreshTechTree() end
		if isCraftOpen then UIManager.refreshCrafting() end
	end)
	TechController.onTechUnlocked(function(data)
		TechUI.ShowUnlockSuccessPopup(data, getItemIcon, mainGui)
		UIManager.notify("기술 연구 완료: " .. (data.name or data.techId), C.GOLD)
	end)

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
			if isEquipmentOpen then
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
				if isEquipmentOpen then UIManager.refreshStats() end
			end
		end)
		
		NetClient.On("Player.Stats.Upgraded", function(data)
			UIManager.notify(" 💪 능력치 강화 성공!", C.GREEN)
			-- refreshStats는 Stats.Changed에 의해 호출됨
		end)
	end

	-- Crafting Events
	if NetClient.On then
		NetClient.On("Craft.Started", function(data)
			if data and data.craftTime and data.craftTime > 0 then
				UIManager.showCraftingProgress(data.craftTime)
			end
		end)
		
		NetClient.On("Craft.Completed", function(data)
			UIManager.stopCraftingProgress()
			
			local name = "아이템"
			if data and data.recipeId then
				local recipe = DataHelper.GetData("RecipeData", data.recipeId)
				if recipe then name = recipe.name end
			end
			
			UIManager.notify("제작 완료: " .. name, C.GREEN)
			if isInvOpen then UIManager.refreshInventory() end
			if isCraftOpen then UIManager.refreshCrafting() end
		end)
		
		NetClient.On("Craft.Cancelled", function(data)
			UIManager.stopCraftingProgress()
			UIManager.notify("제작 취소됨", C.GRAY)
		end)
	end

	-- Debuff Events
	if NetClient.On then
		NetClient.On("Debuff.Applied", function(data)
			if data and data.debuffId then
				activeDebuffs[data.debuffId] = {
					id = data.debuffId,
					name = data.name,
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

	-- 슬롯 참조만 유지 (드래그 앤 드롭 및 리프레시 로직용)
	hotbarSlots = HUDUI.Refs.hotbarSlots
	invSlots = InventoryUI.Refs.Slots
	
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

	initialized = true
	print("[UIManager] Initialized — Responsive Scale applied")
end

function UIManager.hideAllLoading()
	if craftSpinner then
		craftSpinner.Visible = false
	end
	-- 추가적인 로딩 UI가 있다면 여기서 처리
end

return UIManager
