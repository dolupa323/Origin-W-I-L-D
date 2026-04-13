-- NPCShopService.lua
-- NPC 상점 시스템 서비스 (Phase 9)
-- 골드 관리, 상점 조회, 구매/판매 처리

local NPCShopService = {}

--========================================
-- Dependencies (Init에서 주입)
--========================================
local initialized = false
local NetController
local InventoryService
local SaveService
local DataService

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)
local SpawnConfig = require(Shared.Config.SpawnConfig)

local DataFolder = ReplicatedStorage:WaitForChild("Data")
local NPCShopData = require(DataFolder:WaitForChild("NPCShopData"))
local MaterialAttributeData = require(DataFolder:WaitForChild("MaterialAttributeData"))

--========================================
-- Internal State
--========================================
local playerGold = {}        -- [userId] = goldAmount
local shopStock = {}         -- [shopId] = { [itemIndex] = remainingStock }
local lastRestockTime = os.time()

-- 상점 데이터 캐시
local shopDataMap = {}       -- [shopId] = shopData
local spawnedNpcMap = {}     -- [shopId] = Model
local RARITY_BASE_SELL_PRICE = {
	COMMON = 6,
	UNCOMMON = 11,
	RARE = 18,
	EPIC = 32,
	LEGENDARY = 55,
}
local TYPE_SELL_MULTIPLIER = {
	RESOURCE = 1.0,
	FOOD = 0.9,
	TOOL = 1.8,
	WEAPON = 2.2,
	ARMOR = 2.0,
	CONSUMABLE = 1.1,
	AMMO = 1.1,
	PLACEABLE = 1.6,
}

local function _getPlayerStateWithRetry(userId: number, timeoutSeconds: number?): any
	if not SaveService or not SaveService.getPlayerState then
		return nil
	end

	local state = SaveService.getPlayerState(userId)
	local deadline = os.clock() + (timeoutSeconds or 5)

	while not state and os.clock() < deadline do
		task.wait(0.05)
		state = SaveService.getPlayerState(userId)
	end

	return state
end

--========================================
-- Internal: Shop Data
--========================================

--- 상점 데이터 초기화
local function _loadShopData()
	local count = 0
	for key, shop in pairs(NPCShopData) do
		if type(shop) == "table" and shop.id then
			shopDataMap[shop.id] = shop
			-- 재고 초기화
			shopStock[shop.id] = {}
			for i, item in ipairs(shop.buyList or {}) do
				if item.stock and item.stock > 0 then
					shopStock[shop.id][i] = item.stock
				end
			end
			count = count + 1
		end
	end
	print(string.format("[NPCShopService] Loaded %d shops", count))
end

local function _getSellEntry(shop: any, itemId: string): any?
	for _, item in ipairs(shop.sellList or {}) do
		if item.itemId == itemId then
			return item
		end
	end

	if shop.acceptAllItems == true then
		local bestExplicitSell = nil
		local bestDerivedSell = nil

		for _, otherShop in pairs(shopDataMap) do
			for _, otherSell in ipairs(otherShop.sellList or {}) do
				if otherSell.itemId == itemId then
					local sellPrice = tonumber(otherSell.price) or 0
					if sellPrice > 0 and (not bestExplicitSell or sellPrice > bestExplicitSell) then
						bestExplicitSell = sellPrice
					end
				end
			end

			for _, otherBuy in ipairs(otherShop.buyList or {}) do
				if otherBuy.itemId == itemId then
					local buyPrice = tonumber(otherBuy.price) or 0
					local derivedSell = math.max(1, math.floor((buyPrice * (otherShop.sellMultiplier or Balance.SHOP_DEFAULT_SELL_MULT)) + 0.5))
					if buyPrice > 0 and (not bestDerivedSell or derivedSell > bestDerivedSell) then
						bestDerivedSell = derivedSell
					end
				end
			end
		end

		local fallbackPrice = bestExplicitSell or bestDerivedSell
		if not fallbackPrice or fallbackPrice <= 0 then
			local itemData = DataService and DataService.getItem and DataService.getItem(itemId)
			if itemData then
				local rarityBase = RARITY_BASE_SELL_PRICE[itemData.rarity or "COMMON"] or RARITY_BASE_SELL_PRICE.COMMON
				local typeMultiplier = TYPE_SELL_MULTIPLIER[itemData.type or "RESOURCE"] or 1
				local weightBonus = math.clamp(math.floor(((tonumber(itemData.weight) or 0) * 2) + 0.5), 0, 10)
				local utilityBonus = 0

				if tonumber(itemData.foodValue) and itemData.foodValue > 0 then
					utilityBonus += math.min(6, math.floor(itemData.foodValue / 10))
				end

				if tonumber(itemData.fuelValue) and itemData.fuelValue > 0 then
					utilityBonus += math.min(6, math.floor(itemData.fuelValue / 8))
				end

				fallbackPrice = math.max(1, math.floor((rarityBase * typeMultiplier) + weightBonus + utilityBonus + 0.5))
			end
		end

		if fallbackPrice and fallbackPrice > 0 then
			return {
				itemId = itemId,
				price = fallbackPrice,
				synthetic = true,
			}
		end
	end

	return nil
end

local function _computeSellUnitPrice(shop: any, slotData: any): (number?, string?)
	if not slotData or not slotData.itemId then
		return nil, Enums.ErrorCode.SLOT_EMPTY
	end

	local sellEntry = _getSellEntry(shop, slotData.itemId)
	if not sellEntry then
		return nil, Enums.ErrorCode.ITEM_NOT_SELLABLE
	end

	local price = tonumber(sellEntry.price) or 0
	if price <= 0 then
		return nil, Enums.ErrorCode.ITEM_NOT_SELLABLE
	end

	if shop.dynamicSellPricing and slotData.attributes then
		local pricing = shop.sellPricing or {}
		local positivePenalty = tonumber(pricing.positiveLevelPenaltyPerLevel) or 0.08
		local positiveMin = tonumber(pricing.positiveMinMultiplier) or 0.35
		local negativeBonus = tonumber(pricing.negativeLevelBonusPerLevel) or 0.12

		for attrId, attrLevel in pairs(slotData.attributes) do
			local level = math.max(1, math.floor(tonumber(attrLevel) or 1))
			local attrInfo = MaterialAttributeData.getAttribute(attrId)
			if attrInfo then
				if attrInfo.positive then
					price *= math.max(positiveMin, 1 - (positivePenalty * level))
				else
					price *= (1 + (negativeBonus * level))
				end
			end
		end
	end

	return math.max(1, math.floor(price + 0.5)), nil
end

local function _buildSellQuotes(userId: number, shop: any): {any}
	if not InventoryService or not InventoryService.getFullInventory then
		return {}
	end

	local quotes = {}
	local inventory = InventoryService.getFullInventory(userId)
	for _, slotData in ipairs(inventory) do
		local unitPrice = _computeSellUnitPrice(shop, slotData)
		if unitPrice then
			table.insert(quotes, {
				slot = slotData.slot,
				itemId = slotData.itemId,
				count = slotData.count or 1,
				unitPrice = unitPrice,
				totalPrice = unitPrice * (slotData.count or 1),
				attributes = slotData.attributes,
			})
		end
	end

	table.sort(quotes, function(a, b)
		return a.slot < b.slot
	end)

	return quotes
end

local function _getShopGroundPosition(basePosition: Vector3): Vector3
	local rayResult = workspace:Raycast(basePosition + Vector3.new(0, 50, 0), Vector3.new(0, -200, 0))
	if rayResult then
		return rayResult.Position
	end
	return basePosition
end

local function _findPlacedShopNPC(folder: Folder, shopId: string): Instance?
	for _, child in ipairs(folder:GetChildren()) do
		if child.Name == shopId or child:GetAttribute("NPCId") == shopId then
			return child
		end
	end
	return nil
end

local function _findShopModelTemplate(modelTemplateName: string?, fallbackName: string?): Instance?
	local candidateNames = {}
	local function pushName(value: string?)
		if type(value) ~= "string" or value == "" then
			return
		end
		for _, existing in ipairs(candidateNames) do
			if existing == value then
				return
			end
		end
		table.insert(candidateNames, value)
	end

	pushName(modelTemplateName)
	pushName(fallbackName)

	if #candidateNames == 0 then
		return nil
	end

	local candidateFolders = {
		ReplicatedStorage:FindFirstChild("NPCModels"),
		ServerStorage:FindFirstChild("NPCModels"),
	}

	local replicatedAssets = ReplicatedStorage:FindFirstChild("Assets")
	if replicatedAssets then
		table.insert(candidateFolders, replicatedAssets:FindFirstChild("NPCModels"))
		table.insert(candidateFolders, replicatedAssets:FindFirstChild("ShopNPCs"))
	end

	local serverAssets = ServerStorage:FindFirstChild("Assets")
	if serverAssets then
		table.insert(candidateFolders, serverAssets:FindFirstChild("NPCModels"))
		table.insert(candidateFolders, serverAssets:FindFirstChild("ShopNPCs"))
	end

	for _, folder in ipairs(candidateFolders) do
		if folder then
			for _, candidateName in ipairs(candidateNames) do
				local template = folder:FindFirstChild(candidateName)
				if template then
					return template
				end
			end
		end
	end

	return nil
end

local function _coerceShopInstanceToModel(instance: Instance, shopId: string): Model?
	if not instance then
		return nil
	end

	if instance:IsA("Model") then
		instance.Name = shopId
		return instance
	end

	local basePart = instance:IsA("BasePart") and instance or instance:FindFirstChildWhichIsA("BasePart", true)
	if not basePart then
		return nil
	end

	local wrapper = Instance.new("Model")
	wrapper.Name = shopId
	instance.Parent = wrapper
	return wrapper
end

local function _ensureShopPrimaryPart(model: Model): BasePart?
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	local preferredRoot = model:FindFirstChild("HumanoidRootPart", true)
	if preferredRoot and preferredRoot:IsA("BasePart") then
		model.PrimaryPart = preferredRoot
		return preferredRoot
	end

	local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
	if firstPart then
		model.PrimaryPart = firstPart
		return firstPart
	end

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CanCollide = false
	root.Anchored = true
	root.Parent = model
	model.PrimaryPart = root
	return root
end

local function _attachShopLabel(root: BasePart, shop: any)
	if not root or root:FindFirstChild("NpcLabel") then
		return
	end

	local label = Instance.new("BillboardGui")
	label.Name = "NpcLabel"
	label.Size = UDim2.new(0, 180, 0, 44)
	label.StudsOffset = shop.labelOffset or Vector3.new(0, 4.8, 0)
	label.AlwaysOnTop = true
	label.MaxDistance = tonumber(shop.labelMaxDistance) or 36
	label.Parent = root

	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, 0, 1, 0)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.SourceSansBold
	text.TextColor3 = Color3.fromRGB(255, 233, 184)
	text.TextStrokeTransparency = 0.35
	text.Text = string.format("%s\n%s", shop.npcName or shop.name or shop.id, shop.name or "")
	text.Parent = label
end

local function _ensureShopInteractPart(model: Model, root: BasePart?, shop: any)
	local interactPart = model:FindFirstChild("InteractPart")
	if interactPart and not interactPart:IsA("BasePart") then
		interactPart:Destroy()
		interactPart = nil
	end

	if not interactPart then
		interactPart = Instance.new("Part")
		interactPart.Name = "InteractPart"
		interactPart.Transparency = 1
		interactPart.CanCollide = false
		interactPart.CanTouch = false
		interactPart.CanQuery = true
		interactPart.Anchored = true
		interactPart.Parent = model
	end

	local partSize = shop.interactPartSize
	if typeof(partSize) ~= "Vector3" then
		local size = model:GetExtentsSize()
		local minimumSize = shop.interactPartMinSize or Vector3.new(4, 4, 4)
		local maximumSize = shop.interactPartMaxSize or Vector3.new(6, 6, 6)
		partSize = Vector3.new(
			math.clamp(size.X, minimumSize.X, maximumSize.X),
			math.clamp(size.Y, minimumSize.Y, maximumSize.Y),
			math.clamp(size.Z, minimumSize.Z, maximumSize.Z)
		)
	end
	interactPart.Size = partSize

	local baseCFrame = (root and root.CFrame) or model:GetPivot()
	local partOffset = shop.interactPartOffset
	if typeof(partOffset) == "Vector3" then
		baseCFrame *= CFrame.new(partOffset)
	end
	interactPart.CFrame = baseCFrame
	interactPart:SetAttribute("NPCId", shop.id)
	interactPart:SetAttribute("NPCType", "shop")
	interactPart:SetAttribute("DisplayName", shop.npcName or shop.name or shop.id)
end

local function _buildShopModelPlacement(shop: any, worldCFrame: CFrame?): CFrame?
	if not worldCFrame then
		return nil
	end

	local placement = worldCFrame
	local positionOffset = shop.modelPositionOffset
	if typeof(positionOffset) == "Vector3" then
		placement *= CFrame.new(positionOffset)
	end

	local rotationOffset = shop.modelRotationOffset
	if typeof(rotationOffset) == "Vector3" then
		placement *= CFrame.Angles(
			math.rad(rotationOffset.X),
			math.rad(rotationOffset.Y),
			math.rad(rotationOffset.Z)
		)
	end

	return placement
end

local function _configureShopModel(model: Model, shop: any, root: BasePart?, worldCFrame: CFrame?, preservePosition: boolean?)
	root = root or _ensureShopPrimaryPart(model)
	model.Name = shop.id
	model:SetAttribute("NPCId", shop.id)
	model:SetAttribute("NPCType", "shop")
	model:SetAttribute("DisplayName", shop.npcName or shop.name or shop.id)
	model:SetAttribute("ZoneName", shop.zoneName)

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant:SetAttribute("NPCId", shop.id)
			descendant:SetAttribute("NPCType", "shop")
			descendant:SetAttribute("DisplayName", shop.npcName or shop.name or shop.id)
		end
	end

	local placementCFrame = _buildShopModelPlacement(shop, worldCFrame)
	if root and not preservePosition and placementCFrame then
		model:PivotTo(placementCFrame)
	end

	_ensureShopInteractPart(model, root, shop)

	if root and shop.showAutoLabel ~= false then
		_attachShopLabel(root, shop)
	end
end

local function _ensureNPCFolder(): Folder
	local folder = workspace:FindFirstChild("NPCs")
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = "NPCs"
	folder.Parent = workspace
	return folder
end

local function _spawnShopNPC(shop: any)
	if not shop.zoneName then
		return
	end

	if spawnedNpcMap[shop.id] and spawnedNpcMap[shop.id].Parent then
		return
	end

	local zoneInfo = SpawnConfig.GetZoneInfo(shop.zoneName)
	if not zoneInfo or not zoneInfo.spawnPoint then
		warn(string.format("[NPCShopService] Missing zone info for shop NPC %s", tostring(shop.id)))
		return
	end

	local folder = _ensureNPCFolder()
	local existing = _findPlacedShopNPC(folder, shop.id)
	if existing then
		local existingModel = _coerceShopInstanceToModel(existing, shop.id)
		if existingModel and existingModel.Parent ~= folder then
			existingModel.Parent = folder
		end
		if existingModel then
			_configureShopModel(existingModel, shop, nil, nil, true)
			spawnedNpcMap[shop.id] = existingModel
			return
		end
		warn(string.format("[NPCShopService] Existing NPC %s has no BasePart for interaction", tostring(shop.id)))
		return
	end

	local spawnOffset = shop.npcSpawnOffset or Vector3.new(12, 0, 12)
	local groundPos = _getShopGroundPosition(zoneInfo.spawnPoint + spawnOffset)
	local spawnPos = groundPos + Vector3.new(0, 3, 0)
	local lookAt = zoneInfo.spawnPoint + Vector3.new(0, 3, 0)
	local spawnCFrame = CFrame.lookAt(spawnPos, lookAt)

	local template = _findShopModelTemplate(shop.modelTemplateName, shop.id)
	if template then
		local clonedTemplate = template:Clone()
		local model = _coerceShopInstanceToModel(clonedTemplate, shop.id)
		if model then
			local root = _ensureShopPrimaryPart(model)
			_configureShopModel(model, shop, root, spawnCFrame, false)
			model.Parent = folder
			spawnedNpcMap[shop.id] = model
			return
		end
		warn(string.format("[NPCShopService] Template %s has no BasePart for interaction", tostring(template.Name)))
	end

	local model = Instance.new("Model")
	model.Name = shop.id
	model:SetAttribute("NPCId", shop.id)
	model:SetAttribute("NPCType", "shop")
	model:SetAttribute("DisplayName", shop.npcName or shop.name or shop.id)
	model:SetAttribute("ZoneName", shop.zoneName)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CanCollide = false
	root.Anchored = true
	root.CFrame = spawnCFrame
	root.Parent = model
	root:SetAttribute("NPCId", shop.id)
	root:SetAttribute("NPCType", "shop")
	root:SetAttribute("DisplayName", shop.npcName or shop.name or shop.id)

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2.2, 2.6, 1.2)
	torso.Color = Color3.fromRGB(109, 77, 58)
	torso.Material = Enum.Material.SmoothPlastic
	torso.CanCollide = false
	torso.Anchored = true
	torso.CFrame = root.CFrame * CFrame.new(0, 0.8, 0)
	torso.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.6, 1.6, 1.6)
	head.Color = Color3.fromRGB(240, 206, 168)
	head.Material = Enum.Material.SmoothPlastic
	head.CanCollide = false
	head.Anchored = true
	head.CFrame = root.CFrame * CFrame.new(0, 2.9, 0)
	head.Parent = model

	local hat = Instance.new("Part")
	hat.Name = "Hat"
	hat.Size = Vector3.new(2.2, 0.4, 2.2)
	hat.Color = Color3.fromRGB(78, 57, 38)
	hat.Material = Enum.Material.SmoothPlastic
	hat.CanCollide = false
	hat.Anchored = true
	hat.CFrame = head.CFrame * CFrame.new(0, 1.0, 0)
	hat.Parent = model

	model.PrimaryPart = root
	_attachShopLabel(root, shop)
	model.Parent = folder
	spawnedNpcMap[shop.id] = model
end

local function _spawnWorldShopNPCs()
	for _, shop in pairs(shopDataMap) do
		if shop.zoneName then
			_spawnShopNPC(shop)
		end
	end
end

--- 모든 상점 재고 리필
local function _restockShops()
	for shopId, shop in pairs(shopDataMap) do
		if not shopStock[shopId] then shopStock[shopId] = {} end
		for i, item in ipairs(shop.buyList or {}) do
			if item.stock and item.stock > 0 then
				shopStock[shopId][i] = item.stock
			end
		end
	end
	lastRestockTime = os.time()
	print("[NPCShopService] All shops restocked to initial levels.")
end

--========================================
-- Internal: Gold Management
--========================================

--- 플레이어 골드 초기화/로드
local function _initPlayerGold(userId: number)
	if playerGold[userId] ~= nil then return end
	
	-- SaveService에서 로드
	local state = _getPlayerStateWithRetry(userId)
	local savedGold = state and state.gold
	
	playerGold[userId] = savedGold or Balance.STARTING_GOLD
	print(string.format("[NPCShopService] Player %d gold initialized: %d", userId, playerGold[userId]))
end

--- 플레이어 골드 저장
local function _savePlayerGold(userId: number)
	local gold = playerGold[userId]
	if gold == nil then return end
	
	if SaveService and SaveService.updatePlayerState then
		SaveService.updatePlayerState(userId, function(state)
			state.gold = gold
			return state
		end)
	end
end

--- 골드 변경 이벤트 발행
local function _emitGoldChanged(userId: number)
	if not NetController then return end
	
	local player = Players:GetPlayerByUserId(userId)
	if not player then return end
	
	NetController.FireClient(player, "Shop.GoldChanged", {
		gold = playerGold[userId] or 0,
	})
end

--========================================
-- Internal: Validation
--========================================

--- 상점 존재 검증
local function _validateShop(shopId: string): (any?, string?)
	local shop = shopDataMap[shopId]
	if not shop then
		return nil, Enums.ErrorCode.SHOP_NOT_FOUND
	end
	return shop, nil
end

--- 구매 가능 검증 (buyList 내 아이템 및 재고)
local function _validateBuyItem(shop: any, itemId: string, count: number): (number?, number?, string?)
	for i, item in ipairs(shop.buyList or {}) do
		if item.itemId == itemId then
			local stock = shopStock[shop.id][i]
			
			-- 재고 검증 (-1 = 무한)
			if stock ~= nil and stock >= 0 and stock < count then
				return nil, nil, Enums.ErrorCode.SHOP_OUT_OF_STOCK
			end
			
			return i, item.price, nil
		end
	end
	return nil, nil, Enums.ErrorCode.ITEM_NOT_IN_SHOP
end

--- 판매 가능 검증 (sellList 내 아이템)
local function _validateSellItem(shop: any, slotData: any): (number?, string?)
	return _computeSellUnitPrice(shop, slotData)
end

--========================================
-- Public API: Gold
--========================================

--- 플레이어 골드 조회
function NPCShopService.getGold(userId: number): number
	_initPlayerGold(userId)
	return playerGold[userId] or 0
end

--- 골드 추가 (획득)
function NPCShopService.addGold(userId: number, amount: number): (boolean, string?)
	_initPlayerGold(userId)
	if amount <= 0 then
		return false, Enums.ErrorCode.INVALID_COUNT
	end
	
	local current = playerGold[userId] or 0
	local newGold = current + amount
	
	-- 골드 상한 확인
	if newGold > Balance.GOLD_CAP then
		newGold = Balance.GOLD_CAP
	end
	
	playerGold[userId] = newGold
	_savePlayerGold(userId)
	_emitGoldChanged(userId)
	
	return true, nil
end

--- 골드 차감 (소비)
function NPCShopService.removeGold(userId: number, amount: number): (boolean, string?)
	_initPlayerGold(userId)
	if amount <= 0 then
		return false, Enums.ErrorCode.INVALID_COUNT
	end
	
	local current = playerGold[userId] or 0
	if current < amount then
		return false, Enums.ErrorCode.INSUFFICIENT_GOLD
	end
	
	playerGold[userId] = current - amount
	_savePlayerGold(userId)
	_emitGoldChanged(userId)
	
	return true, nil
end

--========================================
-- Public API: Shop Info
--========================================

--- 모든 상점 목록 조회
function NPCShopService.getShopList(): table
	local list = {}
	for shopId, shop in pairs(shopDataMap) do
		table.insert(list, {
			id = shop.id,
			name = shop.name,
			description = shop.description,
			npcName = shop.npcName,
			zoneName = shop.zoneName,
		})
	end
	return list
end

--- 특정 상점 정보 조회 (buyList/sellList 포함)
function NPCShopService.getShopInfo(shopId: string, userId: number?): (any?, string?)
	local shop, err = _validateShop(shopId)
	if not shop then
		return nil, err
	end
	
	-- 현재 재고 반영
	local buyListWithStock = {}
	for i, item in ipairs(shop.buyList or {}) do
		local stock = shopStock[shopId][i]
		table.insert(buyListWithStock, {
			itemId = item.itemId,
			price = item.price,
			stock = stock or -1,  -- nil이면 무한(-1)
		})
	end
	
	return {
		id = shop.id,
		name = shop.name,
		description = shop.description,
		npcName = shop.npcName,
		zoneName = shop.zoneName,
		sellOnly = shop.sellOnly == true,
		acceptAllItems = shop.acceptAllItems == true,
		buyList = buyListWithStock,
		sellList = shop.sellList,
		sellQuotes = userId and _buildSellQuotes(userId, shop) or {},
		sellMultiplier = shop.sellMultiplier or Balance.SHOP_DEFAULT_SELL_MULT,
	}, nil
end

--========================================
-- Public API: Buy/Sell
--========================================

--- 아이템 구매
function NPCShopService.buy(userId: number, shopId: string, itemId: string, count: number?): (boolean, string?)
	count = count or 1
	
	-- 입력 검증
	if count < 1 then
		return false, Enums.ErrorCode.INVALID_COUNT
	end
	
	-- 상점 검증
	local shop, shopErr = _validateShop(shopId)
	if not shop then
		return false, shopErr
	end
	
	-- 아이템 및 재고 검증
	local itemIndex, price, buyErr = _validateBuyItem(shop, itemId, count)
	if not itemIndex then
		return false, buyErr
	end
	
	-- 총 비용 계산
	local totalCost = price * count
	
	-- 골드 검증
	local currentGold = playerGold[userId] or 0
	if currentGold < totalCost then
		return false, Enums.ErrorCode.INSUFFICIENT_GOLD
	end
	
	-- 인벤토리 공간 검증 및 추가
	if not InventoryService then
		return false, Enums.ErrorCode.INTERNAL_ERROR
	end
	
	local added, remaining = InventoryService.addItem(userId, itemId, count)
	if added <= 0 then
		return false, Enums.ErrorCode.INV_FULL
	end
	
	-- 실제 추가된 수량만큼 비용 재계산
	local actualCost = price * added
	
	-- 골드 차감
	playerGold[userId] = currentGold - actualCost
	_savePlayerGold(userId)
	_emitGoldChanged(userId)
	
	-- 재고 차감 (실제 추가된 만큼만)
	local stock = shopStock[shopId][itemIndex]
	if stock ~= nil and stock > 0 then
		shopStock[shopId][itemIndex] = stock - added
	end
	
	print(string.format("[NPCShopService] Player %d bought %dx %s from %s (cost: %d)", 
		userId, added, itemId, shopId, actualCost))
	
	return true, nil
end

--- 아이템 판매
function NPCShopService.sell(userId: number, shopId: string, slot: number, count: number?): (boolean, string?)
	-- 상점 검증
	local shop, shopErr = _validateShop(shopId)
	if not shop then
		return false, shopErr
	end
	
	-- 인벤토리에서 아이템 정보 확인
	if not InventoryService then
		return false, Enums.ErrorCode.INTERNAL_ERROR
	end
	
	local slotData = InventoryService.getSlot(userId, slot)
	if not slotData or not slotData.itemId then
		return false, Enums.ErrorCode.SLOT_EMPTY
	end
	
	local itemId = slotData.itemId
	local haveCount = slotData.count or 1
	count = count or haveCount
	
	-- 수량 검증
	if count < 1 or count > haveCount then
		return false, Enums.ErrorCode.INVALID_COUNT
	end
	
	-- 판매 가능 검증 및 가격 확인
	local sellPrice, sellErr = _validateSellItem(shop, slotData)
	if not sellPrice then
		return false, sellErr
	end
	
	-- 총 수익 계산
	local totalEarned = sellPrice * count
	
	-- 골드 상한 확인
	local currentGold = playerGold[userId] or 0
	if currentGold + totalEarned > Balance.GOLD_CAP then
		return false, Enums.ErrorCode.GOLD_CAP_REACHED
	end
	
	-- 인벤토리에서 아이템 제거
	local removed = InventoryService.removeItemFromSlot(userId, slot, count)
	if removed <= 0 then
		return false, Enums.ErrorCode.INTERNAL_ERROR
	end
	
	-- 실제 제거된 수량만큼 수익 재계산
	local actualEarned = sellPrice * removed
	
	-- 골드 추가
	playerGold[userId] = currentGold + actualEarned
	_savePlayerGold(userId)
	_emitGoldChanged(userId)
	
	print(string.format("[NPCShopService] Player %d sold %dx %s to %s (earned: %d)", 
		userId, removed, itemId, shopId, actualEarned))
	
	return true, nil
end

--========================================
-- Protocol Handlers
--========================================

local function _onShopListRequest(player: Player, _payload: any)
	local list = NPCShopService.getShopList()
	
	return {
		success = true,
		shops = list,
	}
end

local function _onShopGetInfoRequest(player: Player, payload: any)
	local shopId = payload and payload.shopId
	
	if not shopId then
		return {
			success = false,
			errorCode = Enums.ErrorCode.BAD_REQUEST,
		}
	end
	
	local shopInfo, err = NPCShopService.getShopInfo(shopId, player.UserId)
	
	if not shopInfo then
		return {
			success = false,
			errorCode = err,
		}
	end
	
	return {
		success = true,
		shop = shopInfo,
	}
end

local function _onShopBuyRequest(player: Player, payload: any)
	local userId = player.UserId
	local shopId = payload and payload.shopId
	local itemId = payload and payload.itemId
	local count = payload and payload.count
	
	if not shopId or not itemId then
		return {
			success = false,
			errorCode = Enums.ErrorCode.BAD_REQUEST,
		}
	end
	
	local ok, err = NPCShopService.buy(userId, shopId, itemId, count)
	
	if not ok then
		return {
			success = false,
			errorCode = err,
		}
	end
	
	-- [최적화] 구매 성공 시 갱신된 상점 정보(재고 포함)를 함께 반환하여 추가 요청 방지
	local updatedShopInfo = NPCShopService.getShopInfo(shopId, userId)
	
	return { 
		success = true,
		shop = updatedShopInfo
	}
end

local function _onShopSellRequest(player: Player, payload: any)
	local userId = player.UserId
	local shopId = payload and payload.shopId
	local slot = payload and payload.slot
	local count = payload and payload.count
	
	if not shopId or not slot then
		return {
			success = false,
			errorCode = Enums.ErrorCode.BAD_REQUEST,
		}
	end
	
	local ok, err = NPCShopService.sell(userId, shopId, slot, count)
	
	if not ok then
		return {
			success = false,
			errorCode = err,
		}
	end
	
	local updatedShopInfo = NPCShopService.getShopInfo(shopId, userId)
	return {
		success = true,
		shop = updatedShopInfo,
	}
end

local function _onShopGetGoldRequest(player: Player, _payload: any)
	local userId = player.UserId
	local gold = NPCShopService.getGold(userId)
	
	return {
		success = true,
		gold = gold,
	}
end

--========================================
-- Player Events
--========================================

local function _onPlayerAdded(player: Player)
	_initPlayerGold(player.UserId)
	_emitGoldChanged(player.UserId)
end

local function _onPlayerRemoving(player: Player)
	local userId = player.UserId
	_savePlayerGold(userId)
	playerGold[userId] = nil
end

--========================================
-- Initialization
--========================================

function NPCShopService.Init(netController: any, dataService: any, inventoryService: any, timeService: any)
	if initialized then
		warn("[NPCShopService] Already initialized!")
		return
	end
	
	-- 의존성 주입
	NetController = netController
	DataService = dataService
	InventoryService = inventoryService
	-- timeService는 필요시 사용
	
	-- SaveService 로드
	local ServerScriptService = game:GetService("ServerScriptService")
	local Services = ServerScriptService:WaitForChild("Server"):WaitForChild("Services")
	SaveService = require(Services.SaveService)
	
	-- 상점 데이터 로드
	_loadShopData()
	_spawnWorldShopNPCs()
	
	-- 플레이어 이벤트
	Players.PlayerAdded:Connect(_onPlayerAdded)
	Players.PlayerRemoving:Connect(_onPlayerRemoving)
	
	-- 이미 접속한 플레이어 처리
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(_onPlayerAdded, player)
	end
	
	-- [FIX] 상점 재고 리필 루프 (Phase 11)
	task.spawn(function()
		while true do
			task.wait(30) -- 30초마다 체크
			if os.time() - lastRestockTime >= (Balance.SHOP_RESTOCK_TIME or 3600) then
				_restockShops()
			end
		end
	end)
	
	initialized = true
	print("[NPCShopService] Initialized")
end

--- 핸들러 반환
function NPCShopService.GetHandlers()
	return {
		["Shop.List.Request"] = _onShopListRequest,
		["Shop.GetInfo.Request"] = _onShopGetInfoRequest,
		["Shop.Buy.Request"] = _onShopBuyRequest,
		["Shop.Sell.Request"] = _onShopSellRequest,
		["Shop.GetGold.Request"] = _onShopGetGoldRequest,
	}
end

return NPCShopService
