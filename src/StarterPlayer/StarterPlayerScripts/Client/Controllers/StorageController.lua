-- StorageController.lua
-- 클라이언트 창고 컨트롤러
-- 서버 Storage 이벤트 수신 및 로컬 캐시 관리

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetClient = require(script.Parent.Parent.NetClient)

local StorageController = {}

--========================================
-- Private State
--========================================
local initialized = false

-- 열려있는 창고 캐시 [storageId] = { slots = {...} }
local openStorages = {}

--========================================
-- Public API: Cache Access
--========================================

function StorageController.getOpenStorages()
	return openStorages
end

function StorageController.getStorage(storageId: string)
	return openStorages[storageId]
end

function StorageController.isStorageOpen(storageId: string): boolean
	return openStorages[storageId] ~= nil
end

--========================================
-- Public API: Storage Operations
--========================================

--- 창고 열기 요청
function StorageController.open(storageId: string): (boolean, any)
	local ok, result = NetClient.Request("Storage.Open.Request", { storageId = storageId })
	
	if ok and result and result.success then
		-- 로컬 캐시에 저장
		local data = result.data
		openStorages[storageId] = {
			slots = {},
			maxSlots = data.maxSlots,
			maxStack = data.maxStack,
		}
		
		-- 슬롯 데이터 채우기
		for _, slotData in ipairs(data.slots) do
			openStorages[storageId].slots[slotData.slot] = {
				itemId = slotData.itemId,
				count = slotData.count,
			}
		end
		
		return true, data
	end
	
	return false, result
end

--- 창고 닫기
function StorageController.close(storageId: string): (boolean, any)
	local ok, result = NetClient.Request("Storage.Close.Request", { storageId = storageId })
	
	-- 로컬 캐시에서 제거
	openStorages[storageId] = nil
	
	return ok, result
end

--- 아이템 이동 요청
function StorageController.move(storageId: string, sourceType: string, sourceSlot: number, targetType: string, targetSlot: number, count: number?): (boolean, any)
	local ok, result = NetClient.Request("Storage.Move.Request", {
		storageId = storageId,
		sourceType = sourceType,
		sourceSlot = sourceSlot,
		targetType = targetType,
		targetSlot = targetSlot,
		count = count,
	})
	
	return ok, result
end

--========================================
-- Event Handlers
--========================================

local function onStorageChanged(data)
	if not data or not data.storageId or not data.changes then return end
	
	local storageId = data.storageId
	local storage = openStorages[storageId]
	
	-- 열려있는 창고만 업데이트
	if storage then
		for _, change in ipairs(data.changes) do
			local slot = change.slot
			if change.empty then
				storage.slots[slot] = nil
			else
				storage.slots[slot] = {
					itemId = change.itemId,
					count = change.count,
				}
			end
		end
	end
	
	-- 디버그 로그 (필요시 활성화)
	-- print(string.format("[StorageController] Changed: %s, %d slots", storageId, #data.changes))
end

--========================================
-- Initialization
--========================================

function StorageController.Init()
	if initialized then
		warn("[StorageController] Already initialized")
		return
	end
	
	-- 이벤트 리스너 등록
	NetClient.On("Storage.Changed", onStorageChanged)
	
	initialized = true
	print("[StorageController] Initialized - listening for Storage events")
end

return StorageController
