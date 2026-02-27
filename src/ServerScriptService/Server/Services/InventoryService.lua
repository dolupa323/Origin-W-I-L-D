-- InventoryService.lua
-- 인벤토리 서비스 (서버 권위, SSOT)
-- 슬롯 수: Balance.INV_SLOTS (40)
-- 최대 스택: Balance.MAX_STACK (99)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)

local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")

local InventoryService = {}

--========================================
-- Private State
--========================================
local initialized = false
local playerInventories = {}  -- [userId] = { slots = { [1] = {itemId, count}, ... } }
local playerActiveSlots = {} -- [userId] = hotbarIndex (1-8)

-- NetController 참조
local NetController = nil
-- DataService 참조 (아이템 검증용)
local DataService = nil
-- SaveService 참조 (영속용)
local SaveService = nil
-- PlayerStatService 참조 (스탯용)
local PlayerStatService = nil
-- EquipService 참조 (시각화용)
local EquipService = nil

--========================================
-- Internal: Validation Functions
--========================================

--- 슬롯 범위 검증 (1 ~ INV_SLOTS)
local function _validateSlotRange(slot: number): (boolean, string?)
	if type(slot) ~= "number" then
		return false, Enums.ErrorCode.INVALID_SLOT
	end
	if slot < 1 or slot > Balance.INV_SLOTS or slot ~= math.floor(slot) then
		return false, Enums.ErrorCode.INVALID_SLOT
	end
	return true, nil
end

--- 슬롯에 아이템이 있는지 검증
local function _validateHasItem(inv: any, slot: number): (boolean, string?)
	local slotData = inv.slots[slot]
	if slotData == nil then
		return false, Enums.ErrorCode.SLOT_EMPTY
	end
	return true, nil
end

--- 슬롯이 비어있는지 검증
local function _validateSlotEmpty(inv: any, slot: number): (boolean, string?)
	local slotData = inv.slots[slot]
	if slotData ~= nil then
		return false, Enums.ErrorCode.SLOT_NOT_EMPTY
	end
	return true, nil
end

--- 수량이 유효한지 검증
local function _validateCount(count: number?): (boolean, string?)
	if count == nil then
		return true, nil  -- nil은 "전체"를 의미
	end
	if type(count) ~= "number" then
		return false, Enums.ErrorCode.INVALID_COUNT
	end
	if count < 1 or count ~= math.floor(count) then
		return false, Enums.ErrorCode.INVALID_COUNT
	end
	return true, nil
end

--- 사용 가능한 수량 검증
local function _validateCountAvailable(inv: any, slot: number, count: number): (boolean, string?)
	local slotData = inv.slots[slot]
	if slotData == nil then
		return false, Enums.ErrorCode.SLOT_EMPTY
	end
	if count > slotData.count then
		return false, Enums.ErrorCode.INVALID_COUNT
	end
	return true, nil
end

--- 스택 규칙 검증 (합치기 가능 여부)
local function _validateStackRules(inv: any, toSlot: number, movingItemId: string, movingCount: number): (boolean, string?)
	local targetSlot = inv.slots[toSlot]
	
	if targetSlot == nil then
		-- 빈 슬롯이면 무조건 OK
		return true, nil
	end
	
	-- 다른 아이템이면 합치기 불가
	if targetSlot.itemId ~= movingItemId then
		return false, Enums.ErrorCode.ITEM_MISMATCH
	end
	
	return true, nil
end

--========================================
-- Internal: Weight Calculations
--========================================

--- 아이템 무게 조회
local function _getItemWeight(itemId: string): number
	if not DataService then return 0.1 end
	local item = DataService.getItem(itemId)
	return (item and item.weight) or 0.1
end

--- 인벤토리 현재 총 무게 계산
local function _getTotalWeight(inv: any): number
	local total = 0
	for _, slotData in pairs(inv.slots) do
		if slotData then
			total = total + (_getItemWeight(slotData.itemId) * slotData.count)
		end
	end
	return total
end

--- 플레이어 최대 소지 무게 조회
local function _getMaxWeight(userId: number): number
	if PlayerStatService then
		local stats = PlayerStatService.GetCalculatedStats(userId)
		return stats.maxWeight or Balance.BASE_WEIGHT_CAPACITY
	end
	return Balance.BASE_WEIGHT_CAPACITY
end

--========================================
-- Internal: Apply Functions (Atomic)
--========================================

--- 슬롯 설정 (내부용)
local function _setSlot(inv: any, slot: number, itemId: string?, count: number?)
	if itemId == nil or count == nil or count <= 0 then
		inv.slots[slot] = nil
	else
		inv.slots[slot] = {
			itemId = itemId,
			count = count,
		}
	end
end

--- 슬롯에서 수량 감소
local function _decreaseSlot(inv: any, slot: number, count: number)
	local slotData = inv.slots[slot]
	if slotData then
		local newCount = slotData.count - count
		if newCount <= 0 then
			inv.slots[slot] = nil
		else
			slotData.count = newCount
		end
	end
end

--- 슬롯에 수량 증가 (또는 새로 생성)
local function _increaseSlot(inv: any, slot: number, itemId: string, count: number)
	local slotData = inv.slots[slot]
	if slotData then
		slotData.count = slotData.count + count
	else
		inv.slots[slot] = {
			itemId = itemId,
			count = count,
		}
	end
end

--========================================
-- Internal: Emit Events
--========================================

--- 변경된 슬롯 델타 이벤트 발생 및 SaveService 동기화
local function _emitChanged(player: Player, changes: {{slot: number, itemId: string?, count: number?, empty: boolean?}})
	local userId = player.UserId
	local inv = playerInventories[userId]
	
	-- SaveService 동기화
	if SaveService and inv then
		SaveService.updatePlayerState(userId, function(state)
			state.inventory = inv.slots
			return state
		end)
	end

	-- 현재 활성 슬롯(1~8)의 아이템이 변경되었다면 장착 모델 업데이트
	local active = playerActiveSlots[userId]
	local activeSlotChanged = false
	for _, ch in ipairs(changes) do
		if ch.slot == active then
			activeSlotChanged = true
			break
		end
	end
	if activeSlotChanged and EquipService then
		local item = inv.slots[active]
		EquipService.equipItem(player, item and item.itemId)
	end

	if NetController and #changes > 0 then
		local totalWeight = _getTotalWeight(inv)
		local maxWeight = _getMaxWeight(userId)

		NetController.FireClient(player, "Inventory.Changed", {
			userId = userId,
			changes = changes,
			totalWeight = totalWeight,
			maxWeight = maxWeight,
		})
	end
end

--- 슬롯 데이터를 변경 델타로 변환
local function _makeChange(inv: any, slot: number): {slot: number, itemId: string?, count: number?, empty: boolean?, durability: number?}
	local slotData = inv.slots[slot]
	if slotData then
		return { slot = slot, itemId = slotData.itemId, count = slotData.count, durability = slotData.durability }
	else
		return { slot = slot, empty = true }
	end
end

--========================================
-- Public API: Inventory Management
--========================================

--- 플레이어 인벤토리 가져오기 또는 생성
function InventoryService.getOrCreateInventory(userId: number): any
	if playerInventories[userId] then
		return playerInventories[userId]
	end
	
	-- SaveService에서 로드 시도
	local savedInv = nil
	if SaveService then
		local state = SaveService.getPlayerState(userId)
		if state and state.inventory then
			savedInv = state.inventory
		end
	end

	-- 새 인벤토리 객체 생성
	local inv = {
		slots = savedInv or {},
	}
	
	-- (Optional) 슬롯 구조 정규화 등 필요 시 수행
	
	playerInventories[userId] = inv
	return inv
end

--- 플레이어 인벤토리 가져오기
function InventoryService.getInventory(userId: number): any?
	return playerInventories[userId]
end

--- 플레이어 인벤토리 삭제 (PlayerRemoving 시)
function InventoryService.removeInventory(userId: number)
	playerInventories[userId] = nil
	playerActiveSlots[userId] = nil
end

--- 활성 슬롯 설정
function InventoryService.setActiveSlot(userId: number, slot: number)
	if slot < 1 or slot > 8 then return end -- 핫바 범위만
	if playerActiveSlots[userId] == slot then return end -- 이미 활성 슬롯이면 무시
	
	playerActiveSlots[userId] = slot
	
	-- 시각적 장착 업데이트
	if EquipService then
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local item = InventoryService.getSlot(userId, slot)
			EquipService.equipItem(player, item and item.itemId)
		end
	end
	
	-- 클라이언트에 알림
	local player = Players:GetPlayerByUserId(userId)
	if player then
		NetController.FireClient(player, "Inventory.ActiveSlot.Changed", { slot = slot })
	end
end

--- 활성 슬롯 조회
function InventoryService.getActiveSlot(userId: number): number
	return playerActiveSlots[userId] or 1
end

--========================================
-- Public API: Move
--========================================

--- 아이템 이동 (fromSlot -> toSlot)
--- count가 nil이면 전체 이동
function InventoryService.move(player: Player, fromSlot: number, toSlot: number, count: number?): (boolean, string?, any?)
	local userId = player.UserId
	local inv = playerInventories[userId]
	
	if not inv then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- 슬롯 범위 검증 (먼저!)
	local ok, err = _validateSlotRange(fromSlot)
	if not ok then return false, err, nil end
	
	ok, err = _validateSlotRange(toSlot)
	if not ok then return false, err, nil end
	
	-- 같은 슬롯이면 무시
	if fromSlot == toSlot then
		return true, nil, nil
	end
	
	-- 출발 슬롯에 아이템이 있는지
	ok, err = _validateHasItem(inv, fromSlot)
	if not ok then return false, err, nil end
	
	-- 수량 검증
	ok, err = _validateCount(count)
	if not ok then return false, err, nil end
	
	local fromData = inv.slots[fromSlot]
	local moveCount = count or fromData.count  -- nil이면 전체
	
	-- 이동 수량 검증
	ok, err = _validateCountAvailable(inv, fromSlot, moveCount)
	if not ok then return false, err, nil end
	
	local toData = inv.slots[toSlot]
	local changes = {}
	
	if toData == nil then
		-- 대상 슬롯이 비어있으면: 단순 이동
		_increaseSlot(inv, toSlot, fromData.itemId, moveCount)
		_decreaseSlot(inv, fromSlot, moveCount)
		
		table.insert(changes, _makeChange(inv, fromSlot))
		table.insert(changes, _makeChange(inv, toSlot))
		
	elseif toData.itemId == fromData.itemId then
		-- 같은 아이템이면: 합치기
		ok, err = _validateStackRules(inv, toSlot, fromData.itemId, moveCount)
		if not ok then return false, err, nil end
		
		_increaseSlot(inv, toSlot, fromData.itemId, moveCount)
		_decreaseSlot(inv, fromSlot, moveCount)
		
		table.insert(changes, _makeChange(inv, fromSlot))
		table.insert(changes, _makeChange(inv, toSlot))
		
	else
		-- 다른 아이템이면: 스왑 (전체 이동일 때만)
		if count ~= nil then
			-- 부분 이동은 다른 아이템과 불가
			return false, Enums.ErrorCode.ITEM_MISMATCH, nil
		end
		
		-- 스왑
		inv.slots[fromSlot] = toData
		inv.slots[toSlot] = fromData
		
		table.insert(changes, _makeChange(inv, fromSlot))
		table.insert(changes, _makeChange(inv, toSlot))
	end
	
	-- 이벤트 발생
	_emitChanged(player, changes)
	
	return true, nil, { changes = changes }
end

--========================================
-- Public API: Split
--========================================

--- 스택 분할 (fromSlot에서 count만큼 떼서 toSlot에 새 스택)
--- toSlot은 반드시 비어있어야 함
function InventoryService.split(player: Player, fromSlot: number, toSlot: number, count: number): (boolean, string?, any?)
	local userId = player.UserId
	local inv = playerInventories[userId]
	
	if not inv then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- 슬롯 범위 검증 (먼저!)
	local ok, err = _validateSlotRange(fromSlot)
	if not ok then return false, err, nil end
	
	ok, err = _validateSlotRange(toSlot)
	if not ok then return false, err, nil end
	
	-- 같은 슬롯이면 불가
	if fromSlot == toSlot then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end
	
	-- 출발 슬롯에 아이템이 있는지
	ok, err = _validateHasItem(inv, fromSlot)
	if not ok then return false, err, nil end
	
	-- 대상 슬롯이 비어있는지
	ok, err = _validateSlotEmpty(inv, toSlot)
	if not ok then return false, err, nil end
	
	-- 수량 검증 (split은 count 필수)
	if count == nil then
		return false, Enums.ErrorCode.INVALID_COUNT, nil
	end
	
	ok, err = _validateCount(count)
	if not ok then return false, err, nil end
	
	-- 이동 수량 검증
	ok, err = _validateCountAvailable(inv, fromSlot, count)
	if not ok then return false, err, nil end
	
	local fromData = inv.slots[fromSlot]
	
	-- 분할 적용
	_setSlot(inv, toSlot, fromData.itemId, count)
	_decreaseSlot(inv, fromSlot, count)
	
	local changes = {
		_makeChange(inv, fromSlot),
		_makeChange(inv, toSlot),
	}
	
	-- 이벤트 발생
	_emitChanged(player, changes)
	
	return true, nil, { changes = changes }
end

--========================================
-- Public API: Drop
--========================================

--- 아이템 드롭 (인벤에서 감소만, 월드 드롭은 나중에)
--- count가 nil이면 전체 드롭
function InventoryService.drop(player: Player, slot: number, count: number?): (boolean, string?, any?)
	local userId = player.UserId
	local inv = playerInventories[userId]
	
	if not inv then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- 슬롯 범위 검증
	local ok, err = _validateSlotRange(slot)
	if not ok then return false, err, nil end
	
	-- 슬롯에 아이템이 있는지
	ok, err = _validateHasItem(inv, slot)
	if not ok then return false, err, nil end
	
	-- 수량 검증
	ok, err = _validateCount(count)
	if not ok then return false, err, nil end
	
	local slotData = inv.slots[slot]
	local dropCount = count or slotData.count  -- nil이면 전체
	
	-- 드롭 수량 검증
	ok, err = _validateCountAvailable(inv, slot, dropCount)
	if not ok then return false, err, nil end
	
	local droppedItem = {
		itemId = slotData.itemId,
		count = dropCount,
	}
	
	-- 인벤에서 감소
	_decreaseSlot(inv, slot, dropCount)
	
	local changes = {
		_makeChange(inv, slot),
	}
	
	-- 이벤트 발생
	_emitChanged(player, changes)
	
	return true, nil, {
		dropped = droppedItem,
		changes = changes,
	}
end

--========================================
-- Public API: MoveInternal (범용 컨테이너 간 이동)
-- StorageService 등에서 재사용
--========================================

--- 슬롯 범위 검증 (커스텀 maxSlots)
local function _validateSlotRangeCustom(slot: number, maxSlots: number): (boolean, string?)
	if type(slot) ~= "number" then
		return false, Enums.ErrorCode.INVALID_SLOT
	end
	if slot < 1 or slot > maxSlots or slot ~= math.floor(slot) then
		return false, Enums.ErrorCode.INVALID_SLOT
	end
	return true, nil
end

--- 범용 컨테이너 간 아이템 이동
--- sourceContainer, targetContainer: { slots = { [slot] = {itemId, count} } }
--- maxSlots: 슬롯 최대 수
--- 이벤트 발행은 호출자 책임
function InventoryService.MoveInternal(
	sourceContainer: any,
	sourceSlot: number,
	sourceMaxSlots: number,
	targetContainer: any,
	targetSlot: number,
	targetMaxSlots: number,
	count: number?
): (boolean, string?, any?)
	
	-- 소스/타겟 검증
	if not sourceContainer or not sourceContainer.slots then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	if not targetContainer or not targetContainer.slots then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- 슬롯 범위 검증
	local ok, err = _validateSlotRangeCustom(sourceSlot, sourceMaxSlots)
	if not ok then return false, err, nil end
	
	ok, err = _validateSlotRangeCustom(targetSlot, targetMaxSlots)
	if not ok then return false, err, nil end
	
	-- 같은 컨테이너 + 같은 슬롯이면 무시
	if sourceContainer == targetContainer and sourceSlot == targetSlot then
		return true, nil, nil
	end
	
	-- 소스에 아이템 있는지
	ok, err = _validateHasItem(sourceContainer, sourceSlot)
	if not ok then return false, err, nil end
	
	-- 수량 검증
	ok, err = _validateCount(count)
	if not ok then return false, err, nil end
	
	local sourceData = sourceContainer.slots[sourceSlot]
	local moveCount = count or sourceData.count  -- nil이면 전체
	
	-- 이동 수량 검증
	ok, err = _validateCountAvailable(sourceContainer, sourceSlot, moveCount)
	if not ok then return false, err, nil end
	
	local targetData = targetContainer.slots[targetSlot]
	
	local sourceChanges = {}
	local targetChanges = {}
	
	if targetData == nil then
		-- 타겟 슬롯이 비어있으면: 단순 이동
		_increaseSlot(targetContainer, targetSlot, sourceData.itemId, moveCount)
		_decreaseSlot(sourceContainer, sourceSlot, moveCount)
		
		table.insert(sourceChanges, _makeChange(sourceContainer, sourceSlot))
		table.insert(targetChanges, _makeChange(targetContainer, targetSlot))
		
	elseif targetData.itemId == sourceData.itemId then
		-- 같은 아이템이면: 합치기
		local newCount = targetData.count + moveCount
		if newCount > Balance.MAX_STACK then
			return false, Enums.ErrorCode.STACK_OVERFLOW, nil
		end
		
		_increaseSlot(targetContainer, targetSlot, sourceData.itemId, moveCount)
		_decreaseSlot(sourceContainer, sourceSlot, moveCount)
		
		table.insert(sourceChanges, _makeChange(sourceContainer, sourceSlot))
		table.insert(targetChanges, _makeChange(targetContainer, targetSlot))
		
	else
		-- 다른 아이템이면: 스왑 (전체 이동일 때만, 같은 컨테이너 내에서만)
		if count ~= nil then
			return false, Enums.ErrorCode.ITEM_MISMATCH, nil
		end
		
		if sourceContainer ~= targetContainer then
			-- 다른 컨테이너 간 스왑은 복잡하므로 금지
			return false, Enums.ErrorCode.ITEM_MISMATCH, nil
		end
		
		-- 스왑
		sourceContainer.slots[sourceSlot] = targetData
		sourceContainer.slots[targetSlot] = sourceData
		
		table.insert(sourceChanges, _makeChange(sourceContainer, sourceSlot))
		table.insert(targetChanges, _makeChange(sourceContainer, targetSlot))
	end
	
	return true, nil, {
		sourceChanges = sourceChanges,
		targetChanges = targetChanges,
		movedItem = { itemId = sourceData.itemId, count = moveCount },
	}
end

--========================================
-- Public API: Utility
--========================================

--- 아이템 추가 (빈 슬롯 또는 기존 스택에)
--- 반환: 추가된 수량, 남은 수량
function InventoryService.addItem(userId: number, itemId: string, count: number): (number, number)
	local inv = playerInventories[userId]
	if not inv then
		return 0, count
	end
	
	local player = Players:GetPlayerByUserId(userId)
	
	local remaining = count
	local added = 0
	local changedSlots = {}
	
	-- 무게 체크
	local currentWeight = _getTotalWeight(inv)
	local maxWeight = _getMaxWeight(userId)
	local itemWeight = _getItemWeight(itemId)

	-- 내구도 정보 조회 (새 스택 생성 시 사용)
	local maxDurability = nil
	if DataService then
		local itemData = DataService.getItem(itemId)
		if itemData then maxDurability = itemData.durability end
	end
	
	-- 1. 같은 아이템이 있는 슬롯에 먼저 채우기
	for slot = 1, Balance.INV_SLOTS do
		if remaining <= 0 then break end
		
		local slotData = inv.slots[slot]
		if slotData and slotData.itemId == itemId and slotData.count < Balance.MAX_STACK then
			local canAddByStack = Balance.MAX_STACK - slotData.count
			local canAddByWeight = math.floor((maxWeight - currentWeight) / itemWeight)
			
			local canAdd = math.min(remaining, canAddByStack, math.max(0, canAddByWeight))
			if canAdd <= 0 then break end -- 무게 초과

			slotData.count = slotData.count + canAdd
			remaining = remaining - canAdd
			added = added + canAdd
			currentWeight = currentWeight + (canAdd * itemWeight)
			changedSlots[slot] = true
		end
	end
	
	-- 2. 빈 슬롯에 새 스택 생성
	for slot = 1, Balance.INV_SLOTS do
		if remaining <= 0 then break end
		
		if inv.slots[slot] == nil then
			local canAddByStack = Balance.MAX_STACK
			local canAddByWeight = math.floor((maxWeight - currentWeight) / itemWeight)
			
			local canAdd = math.min(remaining, canAddByStack, math.max(0, canAddByWeight))
			if canAdd <= 0 then break end -- 무게 초과

			inv.slots[slot] = {
				itemId = itemId,
				count = canAdd,
				durability = maxDurability,
			}
			remaining = remaining - canAdd
			added = added + canAdd
			currentWeight = currentWeight + (canAdd * itemWeight)
			changedSlots[slot] = true
		end
	end
	
	if player then
		local changes = {}
		for slot, _ in pairs(changedSlots) do
			table.insert(changes, _makeChange(inv, slot))
		end
		_emitChanged(player, changes)
	end
	
	-- [FIX] Ensure items are always packed (Left-to-Right, Top-to-Bottom)
	InventoryService.sort(userId)
	
	return added, remaining
end

--- 인벤토리 정렬 (빈 슬롯 채우기)
function InventoryService.sort(userId: number)
	local inv = playerInventories[userId]
	if not inv then return end
	
	local items = {}
	for slot = 1, Balance.INV_SLOTS do
		if inv.slots[slot] then
			table.insert(items, inv.slots[slot])
			inv.slots[slot] = nil
		end
	end
	
	-- 아이템 압축 (같은 아이템 합치기)
	local compressed = {}
	for _, item in ipairs(items) do
		local remaining = item.count
		
		for _, comp in ipairs(compressed) do
			if remaining <= 0 then break end
			if comp.itemId == item.itemId and comp.count < Balance.MAX_STACK then
				local space = Balance.MAX_STACK - comp.count
				local amount = math.min(remaining, space)
				comp.count = comp.count + amount
				remaining = remaining - amount
			end
		end
		
		if remaining > 0 then
			table.insert(compressed, {
				itemId = item.itemId,
				count = remaining,
				durability = item.durability
			})
		end
	end
	
	local player = Players:GetPlayerByUserId(userId)
	local changes = {}
	
	for i, item in ipairs(compressed) do
		inv.slots[i] = item
	end
	
	-- 모든 슬롯 델타 생성 (전량 전송)
	for slot = 1, Balance.INV_SLOTS do
		table.insert(changes, _makeChange(inv, slot))
	end
	
	if player then
		_emitChanged(player, changes)
	end
end

--- 빈 슬롯 개수
function InventoryService.getEmptySlotCount(userId: number): number
	local inv = playerInventories[userId]
	if not inv then return 0 end
	
	local count = 0
	for slot = 1, Balance.INV_SLOTS do
		if inv.slots[slot] == nil then
			count = count + 1
		end
	end
	return count
end

--- 전량 수용 가능 여부 검증 (순수 함수, 상태 변경 없음)
--- Loot 원자성 확보용
function InventoryService.canAdd(userId: number, itemId: string, count: number): boolean
	local inv = playerInventories[userId]
	if not inv then return false end
	
	local remaining = count
	
	-- 1. 같은 아이템 스택 여유분 계산
	for slot = 1, Balance.INV_SLOTS do
		if remaining <= 0 then break end
		
		local slotData = inv.slots[slot]
		if slotData and slotData.itemId == itemId and slotData.count < Balance.MAX_STACK then
			remaining = remaining - (Balance.MAX_STACK - slotData.count)
		end
	end
	
	-- 2. 빈 슬롯 개수 계산
	for slot = 1, Balance.INV_SLOTS do
		if remaining <= 0 then break end
		
		if inv.slots[slot] == nil then
			remaining = remaining - Balance.MAX_STACK
		end
	end
	
	return remaining <= 0
end

--- 아이템 보유 여부 확인 (순수 함수)
function InventoryService.hasItem(userId: number, itemId: string, count: number): boolean
	local inv = playerInventories[userId]
	if not inv then return false end
	
	local total = 0
	for slot = 1, Balance.INV_SLOTS do
		local slotData = inv.slots[slot]
		if slotData and slotData.itemId == itemId then
			total = total + slotData.count
			if total >= count then
				return true
			end
		end
	end
	return total >= count
end

--- 아이템 제거 (여러 슬롯에서 분산 제거)
--- 반환: 제거된 수량
function InventoryService.removeItem(userId: number, itemId: string, count: number): number
	local inv = playerInventories[userId]
	if not inv then return 0 end
	
	local remaining = count
	local removed = 0
	local changedSlots = {}
	
	-- 슬롯 순회하며 제거
	for slot = 1, Balance.INV_SLOTS do
		if remaining <= 0 then break end
		
		local slotData = inv.slots[slot]
		if slotData and slotData.itemId == itemId then
			local canRemove = math.min(remaining, slotData.count)
			_decreaseSlot(inv, slot, canRemove)
			remaining = remaining - canRemove
			removed = removed + canRemove
			changedSlots[slot] = true
		end
	end
	
	-- 이벤트 발생
	local player = Players:GetPlayerByUserId(userId)
	if player then
		local changes = {}
		for slot, _ in pairs(changedSlots) do
			table.insert(changes, _makeChange(inv, slot))
		end
		_emitChanged(player, changes)
	end
	
	return removed
end

--- 특정 슬롯에서 아이템 제거
function InventoryService.removeItemFromSlot(userId: number, slot: number, count: number): number
	local inv = playerInventories[userId]
	if not inv then return 0 end
	
	local ok, err = _validateSlotRange(slot)
	if not ok then return 0 end
	
	local slotData = inv.slots[slot]
	if not slotData then return 0 end
	
	local toRemove = math.min(count, slotData.count)
	_decreaseSlot(inv, slot, toRemove)
	
	-- 이벤트 발생
	local player = Players:GetPlayerByUserId(userId)
	if player then
		_emitChanged(player, { _makeChange(inv, slot) })
	end
	
	return toRemove
end

--- 전체 인벤토리 데이터 반환 (클라이언트 동기화용)
function InventoryService.getFullInventory(userId: number): {{slot: number, itemId: string?, count: number?}}
	local inv = playerInventories[userId]
	if not inv then return {} end
	
	local result = {}
	for slot = 1, Balance.INV_SLOTS do
		local slotData = inv.slots[slot]
		if slotData then
			table.insert(result, {
				slot = slot,
				itemId = slotData.itemId,
				count = slotData.count,
			})
		end
	end
	return result
end

--- 내구도 감소 (0 이하 파괴)
--- 반환: success, errorCode, currentDurability(or 0)
function InventoryService.decreaseDurability(userId: number, slot: number, amount: number)
	local inv = playerInventories[userId]
	if not inv then return false, Enums.ErrorCode.NOT_FOUND end
	
	local slotData = inv.slots[slot]
	
	-- 아이템이 없거나 내구도가 없는 아이템이면 무시 (또는 에러)
	if not slotData then return false, Enums.ErrorCode.SLOT_EMPTY end
	if not slotData.durability then return false, Enums.ErrorCode.INVALID_ITEM end
	
	slotData.durability = slotData.durability - amount
	local current = slotData.durability
	
	if current <= 0 then
		-- 파괴
		inv.slots[slot] = nil
	end
	
	-- 이벤트
	local player = Players:GetPlayerByUserId(userId)
	if player then
		_emitChanged(player, {_makeChange(inv, slot)})
	end
	
	return true, nil, math.max(0, current)
end

--- 현재 장착 중인(선택된 핫바) 아이템 조회
function InventoryService.getEquippedItem(userId: number): any?
	local inv = playerInventories[userId]
	if not inv then return nil end
	
	-- ActiveSlot 개념이 아직 없으므로 임시로 1번 슬롯이나, 클라이언트에서 보내주는 슬롯을 신뢰해야 함.
	-- 하지만 Server Auth를 위해선 서버에 activeSlot 상태가 있어야 함.
	-- 일단은 nil 반환하고, CombatService에서 payload.slot을 검증하는 방식으로 우회하거나,
	-- 추후 Hotbar System 구현 시 activeSlot 동기화 추가 필요.
	
	-- Phase 3-3: 임시로 클라이언트 요청 payload의 item을 신뢰하지 않고,
	-- CombatService가 인벤토리 슬롯을 조회하도록 함.
	
	local active = InventoryService.getActiveSlot(userId)
	return InventoryService.getSlot(userId, active)
end

--- 특정 슬롯 아이템 조회
function InventoryService.getSlot(userId: number, slot: number): any?
	local inv = playerInventories[userId]
	if not inv then return nil end
	return inv.slots[slot]
end

--========================================
-- Network Handlers
--========================================

local function handleMove(player: Player, payload: any)
	local fromSlot = payload.fromSlot
	local toSlot = payload.toSlot
	local count = payload.count  -- optional
	
	local success, errorCode, data = InventoryService.move(player, fromSlot, toSlot, count)
	
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = data }
end

local function handleSplit(player: Player, payload: any)
	local fromSlot = payload.fromSlot
	local toSlot = payload.toSlot
	local count = payload.count
	
	local success, errorCode, data = InventoryService.split(player, fromSlot, toSlot, count)
	
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = data }
end

local function handleDrop(player: Player, payload: any)
	local slot = payload.slot
	local count = payload.count  -- optional
	
	local success, errorCode, data = InventoryService.drop(player, slot, count)
	
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = data }  -- data.dropped 포함
end

local function handleActiveSlot(player: Player, payload: any)
	local slot = payload.slot
	if type(slot) ~= "number" or slot < 1 or slot > 8 then
		return { success = false, errorCode = Enums.ErrorCode.INVALID_SLOT }
	end
	
	InventoryService.setActiveSlot(player.UserId, slot)
	return { success = true }
end

local function handleUse(player: Player, payload: any)
	local userId = player.UserId
	local slot = payload.slot
	
	local inv = playerInventories[userId]
	if not inv then return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND } end
	
	local slotData = inv.slots[slot]
	if not slotData then return { success = false, errorCode = Enums.ErrorCode.SLOT_EMPTY } end
	
	local itemData = DataService.getItem(slotData.itemId)
	if not itemData then return { success = false, errorCode = Enums.ErrorCode.INVALID_ITEM } end
	
	-- 1. 장착 가능 아이템 (무기, 도구 등)
	if itemData.type == Enums.ItemType.WEAPON or itemData.type == Enums.ItemType.TOOL or itemData.type == Enums.ItemType.ARMOR then
		-- 이미 핫바(1-8)에 있는 경우 -> 활성 슬롯으로 설정
		if slot >= 1 and slot <= 8 then
			InventoryService.setActiveSlot(userId, slot)
			NetController.FireClient(player, "Inventory.ActiveSlot.Changed", { slot = slot })
			return { success = true, data = { action = "SELECT", slot = slot } }
		else
			-- 가방(9-20)에 있는 경우 -> 현재 활성 핫바 슬롯과 교체(Swap)
			local activeSlot = InventoryService.getActiveSlot(userId)
			local success, err = InventoryService.move(player, slot, activeSlot, nil)
			if success then
				-- 이동 성공 시 활성 슬롯에 대한 장착 업데이트
				local newItem = InventoryService.getSlot(userId, activeSlot)
				if EquipService then
					EquipService.equipItem(player, newItem and newItem.itemId)
				end
				return { success = true, data = { action = "EQUIP", from = slot, to = activeSlot } }
			else
				return { success = false, errorCode = err }
			end
		end
	end
	
	-- 2. 소모성 아이템 (Phase 4-2 연동 예정)
	if itemData.type == Enums.ItemType.CONSUMABLE then
		-- 임시: 사용 알림만
		print(string.format("[InventoryService] User %d used %s", userId, slotData.itemId))
		return { success = true, data = { action = "USE", itemId = slotData.itemId } }
	end
	
	return { success = false, errorCode = Enums.ErrorCode.NOT_SUPPORTED }
end

local function handleGetInventory(player: Player, payload: any)
	local userId = player.UserId
	local slots = InventoryService.getFullInventory(userId)
	local inv = playerInventories[userId]
	
	return {
		success = true,
		data = {
			inventory = slots, -- Client expects 'inventory'
			totalWeight = inv and _getTotalWeight(inv) or 0,
			maxWeight = _getMaxWeight(userId),
			maxSlots = Balance.INV_SLOTS,
			maxStack = Balance.MAX_STACK,
		}
	}
end

--- 디버그: 아이템 지급
local function handleGiveItem(player: Player, payload: any)
	local itemId = payload.itemId or "STONE"
	local count = payload.count or 30
	
	local userId = player.UserId
	local added, remaining = InventoryService.addItem(userId, itemId, count)
	
	return {
		success = true,
		data = {
			itemId = itemId,
			requested = count,
			added = added,
			remaining = remaining,
		}
	}
end

--========================================
-- Event Handlers
--========================================

local function onPlayerAdded(player: Player)
	local userId = player.UserId
	InventoryService.getOrCreateInventory(userId)
	InventoryService.setActiveSlot(userId, 1) -- 초기 활성 슬롯 1번
	
	-- 디버그: 기본 아이템 지급 (Studio에서만)
	if game:GetService("RunService"):IsStudio() then
		InventoryService.addItem(userId, "STONE", 30)
	end
end

local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	-- SaveService에서 저장 후 제거하므로 여기서는 제거만
	InventoryService.removeInventory(userId)
end

--========================================
-- Initialization
--========================================

function InventoryService.Init(netController, dataService, saveService, playerStatService, equipService)
	if initialized then
		warn("[InventoryService] Already initialized")
		return
	end
	
	NetController = netController
	DataService = dataService
	SaveService = saveService
	PlayerStatService = playerStatService
	EquipService = equipService
	
	-- 플레이어 이벤트 연결
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
	-- 이미 접속한 플레이어 처리
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	
	initialized = true
	print(string.format("[InventoryService] Initialized - Slots: %d, MaxStack: %d", 
		Balance.INV_SLOTS, Balance.MAX_STACK))
end

function InventoryService.GetHandlers()
	return {
		["Inventory.Move.Request"] = handleMove,
		["Inventory.Split.Request"] = handleSplit,
		["Inventory.Drop.Request"] = handleDrop,
		["Inventory.Get.Request"] = handleGetInventory,
		["Inventory.ActiveSlot.Request"] = handleActiveSlot,
		["Inventory.Use.Request"] = handleUse,
		["Inventory.Sort.Request"] = function(player, payload)
			InventoryService.sort(player.UserId)
			return { success = true }
		end,
		["Inventory.GiveItem"] = handleGiveItem,
	}
end

return InventoryService
