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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

local DataFolder = ReplicatedStorage:WaitForChild("Data")
local NPCShopData = require(DataFolder:WaitForChild("NPCShopData"))

--========================================
-- Internal State
--========================================
local playerGold = {}        -- [userId] = goldAmount
local shopStock = {}         -- [shopId] = { [itemIndex] = remainingStock }

-- 상점 데이터 캐시
local shopDataMap = {}       -- [shopId] = shopData

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

--========================================
-- Internal: Gold Management
--========================================

--- 플레이어 골드 초기화/로드
local function _initPlayerGold(userId: number)
	if playerGold[userId] ~= nil then return end
	
	-- SaveService에서 로드
	local state = SaveService and SaveService.getPlayerState(userId)
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
local function _validateSellItem(shop: any, itemId: string): (number?, string?)
	for _, item in ipairs(shop.sellList or {}) do
		if item.itemId == itemId then
			return item.price, nil
		end
	end
	return nil, Enums.ErrorCode.ITEM_NOT_SELLABLE
end

--========================================
-- Public API: Gold
--========================================

--- 플레이어 골드 조회
function NPCShopService.getGold(userId: number): number
	return playerGold[userId] or 0
end

--- 골드 추가 (획득)
function NPCShopService.addGold(userId: number, amount: number): (boolean, string?)
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
		})
	end
	return list
end

--- 특정 상점 정보 조회 (buyList/sellList 포함)
function NPCShopService.getShopInfo(shopId: string): (any?, string?)
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
		buyList = buyListWithStock,
		sellList = shop.sellList,
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
	
	local addOk, addErr = InventoryService.addItem(userId, itemId, count)
	if not addOk then
		return false, addErr
	end
	
	-- 골드 차감
	playerGold[userId] = currentGold - totalCost
	_savePlayerGold(userId)
	_emitGoldChanged(userId)
	
	-- 재고 차감
	local stock = shopStock[shopId][itemIndex]
	if stock ~= nil and stock > 0 then
		shopStock[shopId][itemIndex] = stock - count
	end
	
	print(string.format("[NPCShopService] Player %d bought %dx %s from %s (cost: %d)", 
		userId, count, itemId, shopId, totalCost))
	
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
	local sellPrice, sellErr = _validateSellItem(shop, itemId)
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
	local removeOk, removeErr = InventoryService.removeFromSlot(userId, slot, count)
	if not removeOk then
		return false, removeErr
	end
	
	-- 골드 추가
	playerGold[userId] = currentGold + totalEarned
	_savePlayerGold(userId)
	_emitGoldChanged(userId)
	
	print(string.format("[NPCShopService] Player %d sold %dx %s to %s (earned: %d)", 
		userId, count, itemId, shopId, totalEarned))
	
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
			errorCode = Enums.ErrorCode.INVALID_REQUEST,
		}
	end
	
	local shopInfo, err = NPCShopService.getShopInfo(shopId)
	
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
			errorCode = Enums.ErrorCode.INVALID_REQUEST,
		}
	end
	
	local ok, err = NPCShopService.buy(userId, shopId, itemId, count)
	
	if not ok then
		return {
			success = false,
			errorCode = err,
		}
	end
	
	return { success = true }
end

local function _onShopSellRequest(player: Player, payload: any)
	local userId = player.UserId
	local shopId = payload and payload.shopId
	local slot = payload and payload.slot
	local count = payload and payload.count
	
	if not shopId or not slot then
		return {
			success = false,
			errorCode = Enums.ErrorCode.INVALID_REQUEST,
		}
	end
	
	local ok, err = NPCShopService.sell(userId, shopId, slot, count)
	
	if not ok then
		return {
			success = false,
			errorCode = err,
		}
	end
	
	return { success = true }
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
	
	-- 플레이어 이벤트
	Players.PlayerAdded:Connect(_onPlayerAdded)
	Players.PlayerRemoving:Connect(_onPlayerRemoving)
	
	-- 이미 접속한 플레이어 처리
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(_onPlayerAdded, player)
	end
	
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
