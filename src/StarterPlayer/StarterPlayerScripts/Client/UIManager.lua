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
local StatusUI = require(UI.StatusUI)
local CraftingUI = require(UI.CraftingUI)
local ShopUI = require(UI.ShopUI)
local TechUI = require(UI.TechUI)
local InteractUI = require(UI.InteractUI)
local BuildUI = require(UI.BuildUI)
local EquipmentUI = require(UI.EquipmentUI)

local C = Theme.Colors
local F = Theme.Fonts

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
local isInvOpen, isStatusOpen, isCraftOpen, isShopOpen, isTechOpen = false, false, false, false, false

-- 0. UI 관리 헬퍼
local function closeAllWindows(except)
	if isInvOpen and except ~= "INV" then UIManager.closeInventory() end
	if isStatusOpen and except ~= "STATUS" then UIManager.closeStatus() end
	if isCraftOpen and except ~= "CRAFT" then UIManager.closeCrafting() end
	if isShopOpen and except ~= "SHOP" then UIManager.closeShop() end
	if isTechOpen and except ~= "TECH" then UIManager.closeTechTree() end
	if isBuildOpen and except ~= "BUILD" then UIManager.closeBuild() end
	if isEquipmentOpen and except ~= "EQUIP" then UIManager.closeEquipment() end
----------------------------------------------------------------
-- Public API: Tech (K키)
----------------------------------------------------------------
function UIManager.openTechTree()
	if isTechOpen then return end
	closeAllWindows("TECH")
	isTechOpen = true
	TechUI.SetVisible(true)
	InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
end

function UIManager.closeTechTree()
	if not isTechOpen then return end
	isTechOpen = false
	TechUI.SetVisible(false)
	if not isInvOpen and not isShopOpen and not isCraftOpen and not isStatusOpen and not isBuildOpen and not isEquipmentOpen then
		InputManager.setUIOpen(false)
		UIManager._setMainHUDVisible(true)
	end
end

function UIManager.toggleTechTree()
	if isTechOpen then UIManager.closeTechTree() else UIManager.openTechTree() end
end
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
local buildUIFrame
local isBuildOpen = false
local equipmentUIFrame
local isEquipmentOpen = false
----------------------------------------------------------------
-- Public API: Equipment (장비창)
----------------------------------------------------------------
function UIManager.openEquipment()
	if isEquipmentOpen then return end
	closeAllWindows("EQUIP")
	isEquipmentOpen = true
	if not equipmentUIFrame then
		EquipmentUI.Init(playerGui, UIManager)
		equipmentUIFrame = EquipmentUI.Refs.Frame
	end
	-- 실제 장비/스탯 데이터 연동
	local equipmentData = InventoryController.getEquipment() -- 예시: {Head=..., Body=..., ...}
	local statData = InventoryController.getStats() -- 예시: {strength=..., ...}
	EquipmentUI.Refresh(equipmentData, statData, getItemIcon)
	EquipmentUI.SetVisible(true)
	InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
end

function UIManager.closeEquipment()
	if not isEquipmentOpen then return end
	isEquipmentOpen = false
	EquipmentUI.SetVisible(false)
	if not isInvOpen and not isShopOpen and not isCraftOpen and not isStatusOpen and not isTechOpen and not isBuildOpen then
		InputManager.setUIOpen(false)
		UIManager._setMainHUDVisible(true)
	end
end

function UIManager.toggleEquipment()
	if isEquipmentOpen then UIManager.closeEquipment() else UIManager.openEquipment() end
end
----------------------------------------------------------------
-- Public API: Build (건축)
----------------------------------------------------------------
function UIManager.openBuild()
	if isBuildOpen then return end
	closeAllWindows("BUILD")
	isBuildOpen = true
	if not buildUIFrame then
		BuildUI.Init(playerGui, UIManager)
		buildUIFrame = BuildUI.Refs.Frame
	end
	BuildUI.SetVisible(true)
	InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
end

function UIManager.closeBuild()
	if not isBuildOpen then return end
	isBuildOpen = false
	BuildUI.SetVisible(false)
	if not isInvOpen and not isShopOpen and not isCraftOpen and not isStatusOpen and not isTechOpen then
		InputManager.setUIOpen(false)
		UIManager._setMainHUDVisible(true)
	end
end

function UIManager.toggleBuild()
	if isBuildOpen then UIManager.closeBuild() else UIManager.openBuild() end
end

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


----------------------------------------------------------------
-- Public API: HUD
----------------------------------------------------------------
function UIManager.updateHealth(cur, max)
	HUDUI.UpdateHealth(cur, max)
end

function UIManager.updateStamina(cur, max)
	HUDUI.UpdateStamina(cur, max)
end

function UIManager.updateXP(cur, max)
	HUDUI.UpdateXP(cur, max)
end

function UIManager.updateLevel(lv)
	HUDUI.UpdateLevel(lv)
end

function UIManager.upgradeStat(statId)
	task.spawn(function()
		local ok, d = NetClient.Request("Player.Stats.Upgrade.Request", {statId = statId})
		if ok then
			local ok2, stats = NetClient.Request("Player.Stats.Request", {})
			if ok2 and stats then
				cachedStats = stats
				UIManager.refreshStats()
			end
			UIManager.notify("추가 완료!", C.GOLD)
		else
			UIManager.notify("포인트가 부족합니다.", C.RED)
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
		local s = hotbarSlots[i]
		if s then
			local item = items[i]
			if item and item.itemId then
				local icon = getItemIcon(item.itemId)
				s.icon.Image = icon
				s.countLabel.Text = (item.count and item.count > 1) and ("x"..item.count) or ""
				s.icon.Visible = (icon ~= "")
			else
				s.icon.Image = ""; s.countLabel.Text = ""
			end
		end
	end
end

----------------------------------------------------------------
-- Public API: Inventory
----------------------------------------------------------------
function UIManager.openInventory()
	if isInvOpen then return end
	closeAllWindows("INV")
	isInvOpen = true
	InventoryUI.SetVisible(true)
	InventoryUI.SetTab("BAG")
	InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
	UIManager.refreshInventory()
end

function UIManager.closeInventory()
	if not isInvOpen then return end
	isInvOpen = false
	InventoryUI.SetVisible(false)
	if not isShopOpen and not isCraftOpen and not isStatusOpen and not isTechOpen then 
		InputManager.setUIOpen(false) 
		UIManager._setMainHUDVisible(true)
	end
end

function UIManager.toggleInventory()
	if isInvOpen then UIManager.closeInventory() else UIManager.openInventory() end
end

----------------------------------------------------------------
-- Public API: Status / Stats
----------------------------------------------------------------
function UIManager.openStatus()
	if isStatusOpen then return end
	closeAllWindows("STATUS")
	isStatusOpen = true
	StatusUI.SetVisible(true)
	InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
	UIManager.refreshStats()
end

function UIManager.closeStatus()
	if not isStatusOpen then return end
	isStatusOpen = false
	StatusUI.SetVisible(false)
	if not isInvOpen and not isShopOpen and not isCraftOpen and not isTechOpen then 
		InputManager.setUIOpen(false) 
		UIManager._setMainHUDVisible(true)
	end
end

function UIManager.toggleStatus()
	if isStatusOpen then UIManager.closeStatus() else UIManager.openStatus() end
end

function UIManager.refreshInventory()
	local items = InventoryController.getItems()
	InventoryUI.RefreshSlots(items, getItemIcon, C, DataHelper)
	
	local totalWeight, maxWeight = InventoryController.getWeightInfo()
	InventoryUI.UpdateWeight(totalWeight, maxWeight, C)
	
	UIManager.refreshHotbar()
end

function UIManager.refreshStats()
	StatusUI.Refresh(cachedStats, Enums)
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

function UIManager._onInvSlotClick(idx)
	selectedInvSlot = idx
	
	local items = InventoryController.getItems()
	local data = items[idx]
	InventoryUI.UpdateDetail(data, getItemIcon, Enums, DataHelper)
end

function UIManager.onInventorySlotClick(idx)
	UIManager._onInvSlotClick(idx)
end

function UIManager.onUseItem()
	if not selectedInvSlot then return end
	InventoryController.requestUse(selectedInvSlot)
end

function UIManager.openDropModal()
	if not selectedInvSlot then return end
	local item = InventoryController.getSlot(selectedInvSlot)
	if not item then return end
	
	local m = InventoryUI.Refs.DropModal
	m.Frame.Visible = true
	m.Input.Text = tostring(item.count or 1)
	m.MaxLabel.Text = "(최대: " .. (item.count or 1) .. ")"
end

function UIManager.getSelectedInvSlot()
	return selectedInvSlot
end

function UIManager.confirmDrop(count)
	if not selectedInvSlot then return end
	local item = InventoryController.getSlot(selectedInvSlot)
	if not item then return end
	
	local maxCount = item.count or 1
	local validCount = math.max(1, math.min(count, maxCount))
	
	InventoryController.requestDrop(selectedInvSlot, validCount)
	InventoryUI.Refs.DropModal.Frame.Visible = false
end

----------------------------------------------------------------
-- Public API: Crafting
----------------------------------------------------------------
function UIManager.openCrafting(mode)
	if isCraftOpen then return end
	closeAllWindows("CRAFT")
	activeStructureId = nil
	activeFacilityId = nil
	isCraftOpen = true
	CraftingUI.SetVisible(true)
	InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
	
	menuMode = mode or "BUILDING"
	CraftingUI.UpdateTitle(menuMode == "CRAFTING" and "제작 벤치" or "건축 및 시설")

	blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	UIManager.refreshCrafting()
end

--- 작업대(가구)를 통한 제작 메뉴 열기
function UIManager.openWorkbench(structureId, facilityId)
	if isCraftOpen then return end
	closeAllWindows("CRAFT")
	activeStructureId = structureId
	activeFacilityId = facilityId
	isCraftOpen = true
	CraftingUI.SetVisible(true)
	InputManager.setUIOpen(true)
	UIManager._setMainHUDVisible(false)
	menuMode = "CRAFTING" -- 작업대는 여전히 제작 모
	
	CraftingUI.UpdateTitle(facilityId == "CAMPFIRE" and "요리 하기" or "작업대 제작")

	-- Blur
	blurEffect = Instance.new("BlurEffect"); blurEffect.Size = 15; blurEffect.Parent = Lighting
	UIManager.refreshCrafting()
end

function UIManager.closeCrafting()
	if not isCraftOpen then return end
	if blurEffect then blurEffect:Destroy(); blurEffect = nil end
	isCraftOpen = false
	CraftingUI.SetVisible(false)
	selectedRecipeId = nil
	if not isInvOpen and not isShopOpen and not isStatusOpen and not isTechOpen then 
		InputManager.setUIOpen(false) 
		UIManager._setMainHUDVisible(true)
	end
end

function UIManager.toggleCrafting()
	if isCraftOpen then UIManager.closeCrafting() else UIManager.openCrafting() end
end

function UIManager.refreshCrafting()
	task.spawn(function()
		local recipes, facilities = {}, {}
		if menuMode == "CRAFTING" then
			local ok, data = NetClient.Request("Recipe.List.Request", {
				structureId = activeStructureId,
				facilityId = activeFacilityId
			})
			if ok and data and data.recipes then recipes = data.recipes end
		else
			local ok, data = NetClient.Request("Facility.List.Request", {})
			if ok and data and data.facilities then facilities = data.facilities end
		end

		local itemsToShow = (menuMode == "CRAFTING") and recipes or facilities
		table.sort(itemsToShow, function(a, b)
			local lvA = a.techLevel or 0
			local lvB = b.techLevel or 0
			if lvA ~= lvB then return lvA < lvB end
			return (a.name or "") < (b.name or "")
		end)

		local playerItemCounts = InventoryController.getItemCounts()
		CraftingUI.Refresh(itemsToShow, playerItemCounts, getItemIcon, menuMode)
	end)
end

function UIManager._onCraftSlotClick(item, mode)
	if mode == "CRAFTING" then
		selectedRecipeId = item.id
		selectedFacilityId = nil
	else
		selectedRecipeId = nil
		selectedFacilityId = item.id
	end
	
	local playerItemCounts = InventoryController.getItemCounts()
	local isLocked = item.isLocked
	local canMake, _ = UIManager.checkMaterials(item, playerItemCounts)
	
	CraftingUI.UpdateDetail(item, mode, isLocked, canMake, playerItemCounts)
end

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
	
	-- Clear unless we're just updating states
	if forceRefresh or not cachedPersonalRecipes then
		for _, ch in pairs(invPersonalCraftGrid:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
		personalCraftNodes = {}; selectedPersonalRecipeId = nil
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

	if cachedPersonalRecipes and not forceRefresh then
		updateNodes(cachedPersonalRecipes)
	else
		task.spawn(function()
			local ok, data = NetClient.Request("Recipe.List.Request", {facilityId = nil})
			if ok and data and data.recipes then
				cachedPersonalRecipes = data.recipes
				table.sort(cachedPersonalRecipes, function(a, b) return (a.techLevel or 0) < (b.techLevel or 0) end)
				updateNodes(cachedPersonalRecipes)
			end
		end)
	end
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
		d.Name.Text = (isLocked and "🔒 " or "") .. (recipe.name or recipe.id)
		d.PreviewIcon.Image = getItemIcon(recipe.outputs and recipe.outputs[1] and recipe.outputs[1].itemId or recipe.id)
		d.Weight.Text = "제작 소요: " .. (recipe.craftTime or 0) .. "초"
		
		local matsText = ""
		for _, inp in ipairs(recipe.inputs or {}) do
			local have = playerItemCounts[inp.itemId or inp.id] or 0
			local req = inp.count or 0
			matsText = matsText .. string.format("%s %d/%d\n", inp.itemId, have, req)
		end
		d.Mats.Text = "필요 재료:\n" .. matsText
		d.BtnUse.Text = "제작하기"
		d.BtnUse.Visible = true
		d.BtnUse.BackgroundColor3 = canCraft and C.GOLD_SEL or C.BTN_DIS
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
	
	if craftSpinner then
		craftSpinner.Visible = true
		if spinnerConn then spinnerConn:Disconnect() end
		spinnerConn = RunService.RenderStepped:Connect(function(dt)
			craftSpinner.Rotation = craftSpinner.Rotation + 180 * dt
		end)
	end
	
	if progFill then
		progFill.Size = UDim2.new(0,0,1,0)
		craftTween = TweenService:Create(progFill, TweenInfo.new(duration, Enum.EasingStyle.Linear), {Size = UDim2.new(1,0,1,0)})
		craftTween:Play()
	end
	
	-- 버튼 텍스트 변경
	local craftLabel = craftingOverlay:FindFirstChild("CraftLabel", true)
	if craftLabel then craftLabel.Text = "제작 중..." end
end

function UIManager.stopCraftingProgress()
	isCrafting = false
	if spinnerConn then spinnerConn:Disconnect(); spinnerConn = nil end
	if craftSpinner then craftSpinner.Visible = false end
	if craftTween then craftTween:Cancel(); craftTween = nil end
	
	local craftLabel = craftingOverlay:FindFirstChild("CraftLabel", true)
	if craftLabel then craftLabel.Text = "제작" end
	
	if progFill then progFill.Size = UDim2.new(0,0,1,0) end
end
function UIManager._doCraft()
	-- 1. 인벤토리 내 개인 제작 처리
	if isInvOpen and invCraftContainer and invCraftContainer.Visible then
		if not selectedPersonalRecipeId then return end
		
		-- 기술 잠금 체크
		if not TechController.isRecipeUnlocked(selectedPersonalRecipeId) then
			UIManager.notify("레벨 2 달성 및 기술 해금이 필요합니다.", C.RED)
			return
		end

		local recipe = DataHelper.GetData("RecipeData", selectedPersonalRecipeId)
		if recipe then
			local ok, msg = UIManager.checkMaterials(recipe)
			if not ok then UIManager.notify(msg, C.RED); return end
		end

		task.spawn(function()
			local ok, data = NetClient.Request("Craft.Start.Request", {recipeId = selectedPersonalRecipeId})
			if ok then 
				-- 제작 시작 성공 (NetClient.Request는 response.success가 true일 때만 ok=true 반환)
				UIManager.notify("제작을 시작했습니다.", C.GREEN)
				-- 제작 시간 정보가 있으면 프로그레스바 시작
				if data and data.craftTime and data.craftTime > 0 then
					UIManager.showCraftingProgress(data.craftTime)
				end
				task.delay(0.5, function() UIManager.refreshPersonalCrafting() end)
			else
				local reason = tostring(data or "서버 오류")
				UIManager.notify("제작 실패: " .. reason, C.RED)
			end
		end)
		return
	end

	-- 2. 일반 공방/건축 처리
	if menuMode == "CRAFTING" then
		if not selectedRecipeId then return end
		
		-- 기술 잠금 체크
		if not TechController.isRecipeUnlocked(selectedRecipeId) then
			UIManager.notify("기술이 해금되지 않았습니다.", C.RED)
			return
		end
		
		local recipe = DataHelper.GetData("RecipeData", selectedRecipeId)
		if recipe then
			local ok, msg = UIManager.checkMaterials(recipe)
			if not ok then UIManager.notify(msg, C.RED); return end
		end

		task.spawn(function()
			local ok, data = NetClient.Request("Craft.Start.Request", {recipeId = selectedRecipeId})
			if ok then
				print("[UIManager] Craft Started:", selectedRecipeId)
				UIManager.notify("제작을 시작했습니다.", C.GREEN)
				-- 제작 시간 정보가 있으면 프로그레스바 시작
				if data and data.craftTime and data.craftTime > 0 then
					UIManager.showCraftingProgress(data.craftTime)
				end
				task.delay(0.5, function() if isCraftOpen then UIManager.refreshCrafting() end end)
			else
				local reason = tostring(data or "서버 오류")
				UIManager.notify("제작 실패: " .. reason, C.RED)
			end
		end)
	else
		-- BUILDING 모드
		if not selectedFacilityId then return end
		
		-- 1. Lock Check
		if not TechController.isFacilityUnlocked(selectedFacilityId) then
			UIManager.notify("기술이 해금되지 않았습니다.", C.RED)
			return
		end
		
		-- 2. Material Check
		local facility = DataHelper.GetData("FacilityData", selectedFacilityId)
		if facility then
			local ok, msg = UIManager.checkMaterials(facility)
			if not ok then UIManager.notify(msg, C.RED); return end
		end

		print("[UIManager] Start Placement:", selectedFacilityId)
		UIManager.closeCrafting()
		BuildController.startPlacement(selectedFacilityId)
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

function UIManager._onTechNodeClick(node)
	selectedTechId = node.id
	local unlocked = TechController.getUnlockedTech()
	local tp = TechController.getTechPoints()
	local isUnlocked = unlocked[node.id]
	local canAfford = (tp >= (node.cost or 0))
	
	TechUI.UpdateDetail(node, isUnlocked, canAfford, UIManager)
end

function UIManager._doUnlockTech()
	if not selectedTechId then return end
	TechController.requestUnlock(selectedTechId, function(success, err)
		if success then
			UIManager.notify("기술 연구 완료!", C.GREEN)
			UIManager.refreshTechTree()
		else
			UIManager.notify("연구 실패: TP가 부족하거나 선행 기술이 필요합니다.", C.RED)
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
	if not isInvOpen and not isCraftOpen and not isTechOpen then 
		InputManager.setUIOpen(false) 
		UIManager._setMainHUDVisible(true)
	end
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

function UIManager.closeStatus()
	if not isStatusOpen then return end
	isStatusOpen = false
	StatusUI.SetVisible(false)
	if not isInvOpen and not isShopOpen and not isCraftOpen and not isTechOpen then 
		InputManager.setUIOpen(false) 
		UIManager._setMainHUDVisible(true)
	end
end

function UIManager.closeShop()
	if not isShopOpen then return end
	isShopOpen = false
	ShopUI.SetVisible(false)
	if not isInvOpen and not isStatusOpen and not isCraftOpen and not isTechOpen then 
		InputManager.setUIOpen(false) 
		UIManager._setMainHUDVisible(true)
	end
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

function UIManager.updateHarvestProgress(pct)
	HUDUI.UpdateHarvestProgress(pct)
end

function UIManager.hideHarvestProgress()
	HUDUI.HideHarvestProgress()
end

-- 건축 조작 가이드 표시
function UIManager.showBuildPrompt(visible)
	InteractUI.SetBuildVisible(visible)
end

-- 알림 표시 (중앙 하단)
function UIManager.notify(text, color)
	local label = UIManager._notifyLabel
	if not label then return end
	
	-- 기존 애니메이션 중단 및 초기화
	label.Text = text
	label.TextColor3 = color or C.WHITE
	label.Visible = true
	label.BackgroundTransparency = 1
	label.TextTransparency = 1
	label.Position = UDim2.new(0.5, 0, 0.8, -80)
	
	TweenService:Create(label, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		Position = UDim2.new(0.5, 0, 0.8, -100)
	}):Play()
	
	if notifyConn then task.cancel(notifyConn) end
	notifyConn = task.delay(2.5, function()
		local fade = TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
			TextTransparency = 1,
			Position = UDim2.new(0.5, 0, 0.8, -120)
		})
		fade:Play()
		fade.Completed:Connect(function()
			label.Visible = false
		end)
		notifyConn = nil
	end)
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
		UIManager.notify("기술 해금: " .. (data.name or data.techId), C.GOLD)
	end)

	-- 활성 슬롯 동기화 (서버 -> 클라)
	NetClient.On("Inventory.ActiveSlot.Changed", function(data)
		if data and data.slot then
			UIManager.selectHotbarSlot(data.slot, true) -- 루프 방지 위해 skipSync=true
		end
	end)



	-- Hotbar number keys
	local hotbarKeys = {Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight}
	for i = 1, 8 do
		InputManager.bindKey(hotbarKeys[i], "HB"..i, function() UIManager.selectHotbarSlot(i) end)
	end

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
				if isStatusOpen then UIManager.refreshStats() end
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
	mainGui.IgnoreGuiInset = false
	mainGui.Parent = playerGui

	-- 신규 모듈형 UI 초기화
	HUDUI.Init(mainGui, UIManager, InputManager)
	InventoryUI.Init(mainGui, UIManager)
	StatusUI.Init(mainGui, UIManager, NetClient, Enums)
	CraftingUI.Init(mainGui, UIManager)
	ShopUI.Init(mainGui, UIManager)
	TechUI.Init(mainGui, UIManager)
	InteractUI.Init(mainGui)

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
	
	-- 알림 라벨 생성
	local notifyLabel = mkLabel({name="Notify", size=UDim2.new(0,400,0,40), pos=UDim2.new(0.5,0,0.8,-100), anchor=Vector2.new(0.5,0.5), text="", ts=16, font=F.TITLE, color=Color3.new(1,0.3,0.3), z=100, parent=mainGui})
	notifyLabel.TextStrokeTransparency = 0.5
	notifyLabel.Visible = false
	UIManager._notifyLabel = notifyLabel

	initialized = true
	print("[UIManager] Initialized — Durango-style UI")
end

return UIManager
