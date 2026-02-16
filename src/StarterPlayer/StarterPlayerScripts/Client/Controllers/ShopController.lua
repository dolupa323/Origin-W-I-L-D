-- ShopController.lua
-- 클라이언트 상점 컨트롤러 (Phase 9)
-- 서버 Shop 이벤트 수신 및 로컬 캐시 관리

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetClient = require(script.Parent.Parent.NetClient)

local ShopController = {}

--========================================
-- Private State
--========================================
local initialized = false

-- 로컬 상태 캐시
local goldCache = 0                    -- 현재 보유 골드
local shopListCache = {}               -- 상점 목록 캐시
local shopInfoCache = {}               -- [shopId] = shopInfo (상세 정보)

-- 이벤트 리스너들
local listeners = {
	goldChanged = {},
	shopUpdated = {},
}

--========================================
-- Public API: Cache Access
--========================================

--- 현재 골드 조회 (캐시)
function ShopController.getGold(): number
	return goldCache
end

--- 상점 목록 조회 (캐시)
function ShopController.getShopList(): table
	return shopListCache
end

--- 특정 상점 정보 조회 (캐시)
function ShopController.getShopInfo(shopId: string): any?
	return shopInfoCache[shopId]
end

--========================================
-- Public API: Server Requests
--========================================

--- 골드 정보 요청
function ShopController.requestGold(callback: ((boolean, number?) -> ())?)
	NetClient.Request("Shop.GetGold.Request", {}, function(response)
		if response.success and response.data then
			goldCache = response.data.gold or 0
			_fireListeners("goldChanged", goldCache)
		end
		if callback then
			callback(response.success, goldCache)
		end
	end)
end

--- 상점 목록 요청
function ShopController.requestShopList(callback: ((boolean, any?) -> ())?)
	NetClient.Request("Shop.List.Request", {}, function(response)
		if response.success and response.data and response.data.shops then
			shopListCache = response.data.shops
		end
		if callback then
			callback(response.success, shopListCache)
		end
	end)
end

--- 특정 상점 정보 요청
function ShopController.requestShopInfo(shopId: string, callback: ((boolean, any?) -> ())?)
	NetClient.Request("Shop.GetInfo.Request", { shopId = shopId }, function(response)
		if response.success and response.data and response.data.shop then
			shopInfoCache[shopId] = response.data.shop
			_fireListeners("shopUpdated", response.data.shop)
		end
		if callback then
			callback(response.success, shopInfoCache[shopId])
		end
	end)
end

--- 아이템 구매 요청
function ShopController.requestBuy(shopId: string, itemId: string, count: number?, callback: ((boolean, string?) -> ())?)
	NetClient.Request("Shop.Buy.Request", {
		shopId = shopId,
		itemId = itemId,
		count = count or 1,
	}, function(response)
		-- 성공 시 상점 정보 갱신
		if response.success then
			ShopController.requestShopInfo(shopId)
		end
		if callback then
			callback(response.success, response.errorCode)
		end
	end)
end

--- 아이템 판매 요청
function ShopController.requestSell(shopId: string, slot: number, count: number?, callback: ((boolean, string?) -> ())?)
	NetClient.Request("Shop.Sell.Request", {
		shopId = shopId,
		slot = slot,
		count = count,
	}, function(response)
		if callback then
			callback(response.success, response.errorCode)
		end
	end)
end

--========================================
-- Event Listener API
--========================================

--- 골드 변경 이벤트 리스너 등록
function ShopController.onGoldChanged(callback: (number) -> ())
	table.insert(listeners.goldChanged, callback)
end

--- 상점 정보 업데이트 이벤트 리스너 등록
function ShopController.onShopUpdated(callback: (any) -> ())
	table.insert(listeners.shopUpdated, callback)
end

--========================================
-- Internal: Event Firing
--========================================

local function _fireListeners(eventName: string, data: any)
	local eventListeners = listeners[eventName]
	if not eventListeners then return end
	
	for _, callback in ipairs(eventListeners) do
		pcall(callback, data)
	end
end

--========================================
-- Event Handlers
--========================================

local function onGoldChanged(data)
	if not data then return end
	
	local newGold = data.gold or 0
	goldCache = newGold
	
	_fireListeners("goldChanged", newGold)
	
	print(string.format("[ShopController] Gold updated: %d", newGold))
end

--========================================
-- Initialization
--========================================

function ShopController.Init()
	if initialized then
		warn("[ShopController] Already initialized!")
		return
	end
	
	-- 서버 이벤트 리스너 등록
	if NetClient.On then
		NetClient.On("Shop.GoldChanged", onGoldChanged)
	end
	
	-- 초기 골드 요청
	task.spawn(function()
		ShopController.requestGold()
	end)
	
	initialized = true
	print("[ShopController] Initialized")
end

return ShopController
