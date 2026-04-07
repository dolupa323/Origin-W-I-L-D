-- InventoryService.lua
-- ?�벤?�리 ?�비??(?�버 권위, SSOT)
-- ?�롯 ?? 기본 60�? ?�텟 ?�자�?최�? 120�?
-- 최�? ?�택: Balance.MAX_STACK (99)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

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
local playerInventories = {}  -- [userId] = { slots = { [1] = {itemId, count}, ... }, equipment = { Head, Body, Feet, Hand } }
local playerActiveSlots = {} -- [userId] = hotbarIndex (1-8)

-- NetController 참조
local NetController = nil
-- DataService 참조 (?�이??검증용)
local DataService = nil
-- SaveService 참조 (?�속??
local SaveService = nil
-- PlayerStatService 참조 (?�탯??
local PlayerStatService = nil
-- EquipService 참조 (?�각?�용)
local EquipService = nil
-- ?�토리얼/?�스?�용 ?�이???�득 콜백
local questItemCallback = nil
local questFoodEatenCallback = nil

local DEBUG_ITEM_GRANT_ADMIN_IDS = {
	[10311679477] = true,
}

local function _canUseDebugGrant(player: Player): boolean
	if not RunService:IsStudio() then
		return false
	end
	if DEBUG_ITEM_GRANT_ADMIN_IDS[player.UserId] then
		return true
	end
	if player.UserId == game.CreatorId then
		return true
	end
	return false
end

local function _getDefaultEquipment()
	return {
		HEAD = nil,
		SUIT = nil,
		HAND = nil,
	}
end

local HOTBAR_SLOT_MAX = 8

local function _isArmorItemId(itemId: string): boolean
	if not (DataService and DataService.getItem and itemId) then
		return false
	end
	local itemData = DataService.getItem(itemId)
	return itemData and itemData.type == "ARMOR" or false
end

--- 아이템 스택 가능 여부 (화살/탄약만 스택 가능)
local function _isStackable(itemId: string): boolean
	if not (DataService and DataService.getItem and itemId) then
		return false
	end
	local itemData = DataService.getItem(itemId)
	return itemData and itemData.type == "AMMO"
end

--- 아이템별 최대 스택 수량 (AMMO: 개별 maxStack, 그 외: 1)
local function _getMaxStack(itemId: string): number
	if not _isStackable(itemId) then return 1 end
	if DataService then
		local itemData = DataService.getItem(itemId)
		if itemData and itemData.maxStack then return itemData.maxStack end
	end
	return Balance.MAX_STACK
end

local function _normalizeEquipmentSlots(equipment: any): any
	local normalized = _getDefaultEquipment()
	if type(equipment) ~= "table" then
		return normalized
	end

	normalized.HEAD = equipment.HEAD or equipment.Head
	normalized.SUIT = equipment.SUIT or equipment.Suit
	normalized.HAND = equipment.HAND or equipment.Hand

	return normalized
end

--========================================
-- Internal: Validation Functions
--========================================

--- ?�롯 범위 검�?(1 ~ MAX_INV_SLOTS)
local function _validateSlotRange(slot: number): (boolean, string?)
	if type(slot) ~= "number" then
		return false, Enums.ErrorCode.INVALID_SLOT
	end
	if slot < 1 or slot > Balance.MAX_INV_SLOTS or slot ~= math.floor(slot) then
		return false, Enums.ErrorCode.INVALID_SLOT
	end
	return true, nil
end

--- ?�롯???�이?�이 ?�는지 검�?
local function _validateHasItem(inv: any, slot: number): (boolean, string?)
	local slotData = inv.slots[slot]
	if slotData == nil then
		return false, Enums.ErrorCode.SLOT_EMPTY
	end
	return true, nil
end

--- ?�롯??비어?�는지 검�?
local function _validateSlotEmpty(inv: any, slot: number): (boolean, string?)
	local slotData = inv.slots[slot]
	if slotData ~= nil then
		return false, Enums.ErrorCode.SLOT_NOT_EMPTY
	end
	return true, nil
end

--- ?�량???�효?��? 검�?
local function _validateCount(count: number?): (boolean, string?)
	if count == nil then
		return true, nil  -- nil?� "?�체"�??��?
	end
	if type(count) ~= "number" then
		return false, Enums.ErrorCode.INVALID_COUNT
	end
	if count < 1 or count ~= math.floor(count) then
		return false, Enums.ErrorCode.INVALID_COUNT
	end
	return true, nil
end

--- ?�용 가?�한 ?�량 검�?
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

--========================================
-- Internal: Slot Calculations
--========================================

--- ?�벤?�리 ?�용 중인 �???계산
local function _getUsedSlots(inv: any): number
	local count = 0
	for _, slotData in pairs(inv.slots) do
		if slotData then
			count = count + 1
		end
	end
	return count
end

--- ?�레?�어 최�? ?�벤?�리 �???조회
local function _getMaxSlots(userId: number): number
	if PlayerStatService then
		local stats = PlayerStatService.GetCalculatedStats(userId)
		return stats.maxSlots or Balance.BASE_INV_SLOTS
	end
	return Balance.BASE_INV_SLOTS
end

--========================================
-- Internal: Apply Functions (Atomic)
--========================================

--- ?�롯 ?�정 (?��???
local function _setSlot(inv: any, slot: number, itemId: string?, count: number?, durability: number?, attributes: any?)
	if itemId == nil or count == nil or count <= 0 then
		inv.slots[slot] = nil
	else
		inv.slots[slot] = {
			itemId = itemId,
			count = count,
			durability = durability,
			attributes = attributes,
		}
	end
end

--- ?�롯?�서 ?�량 감소
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

--- ?�롯???�량 증�? (?�는 ?�로 ?�성)
local function _increaseSlot(inv: any, slot: number, itemId: string, count: number, durability: number?, attributes: any?)
	local slotData = inv.slots[slot]
	if slotData then
		slotData.count = slotData.count + count
	else
		inv.slots[slot] = {
			itemId = itemId,
			count = count,
			durability = durability,
			attributes = attributes,
		}
	end
end

--========================================
-- Internal: Emit Events
--========================================

--- 변경된 ?�롯 ?��? ?�벤??발생 �?SaveService ?�기??
local function _emitChanged(player: Player, changes: {{slot: number, itemId: string?, count: number?, empty: boolean?}}, fullSyncData: any?)
	local userId = player.UserId
	local inv = playerInventories[userId]
	
	-- SaveService ?�기??
	if SaveService and inv then
		SaveService.updatePlayerState(userId, function(state)
			state.inventory = inv.slots
			state.equipment = inv.equipment
			return state
		end)
	end

	-- ?�재 ?�성 ?�롯(1~8)???�이?�이 변경되?�다�??�착 모델 ?�데?�트
	local active = playerActiveSlots[userId] or 1 -- [FIX] Default to 1 if nil
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

	if NetController then
		local usedSlots = _getUsedSlots(inv)
		local maxSlots = _getMaxSlots(userId)

		local payload = {
			userId = userId,
			usedSlots = usedSlots,
			maxSlots = maxSlots,
		}
		
		if fullSyncData then
			payload.fullInventory = fullSyncData
		else
			payload.changes = changes
		end

		NetController.FireClient(player, "Inventory.Changed", payload)
	end
end

--- ?�롯 ?�이?��? 변�??��?�?변??
local function _makeChange(inv: any, slot: number): {slot: number, itemId: string?, count: number?, empty: boolean?, durability: number?}
	local slotData = inv.slots[slot]
	if slotData then
		return { slot = slot, itemId = slotData.itemId, count = slotData.count, durability = slotData.durability, attributes = slotData.attributes }
	else
		return { slot = slot, empty = true }
	end
end

function InventoryService.getEquipment(userId: number)
	local inv = playerInventories[userId]
	return inv and inv.equipment or {}
end

function InventoryService.getTotalDefense(userId: number): number
	local inv = playerInventories[userId]
	if not inv or not inv.equipment then return 0 end
	
	local MaterialAttributeData = require(ReplicatedStorage:WaitForChild("Data").MaterialAttributeData)
	
	local defense = 0
	for _, item in pairs(inv.equipment) do
		local data = DataService.getItem(item.itemId)
		if data and data.defense then
			local bonusDef = 0
			if item.attributes then
				for attrId, level in pairs(item.attributes) do
					local fx = MaterialAttributeData.getEffectValues(attrId, level)
					if fx and fx.defenseMult then
						bonusDef = bonusDef + fx.defenseMult
					end
				end
			end
			defense = defense + math.floor(data.defense * (1 + bonusDef) + 0.5)
		end
	end
	
	-- ?�트 ?�과 추�? 방어??
	local setBonuses = InventoryService.getArmorSetBonuses(userId)
	if setBonuses and setBonuses.defense then
		defense = defense + setBonuses.defense
	end
	
	return defense
end

function InventoryService.getArmorSetBonuses(userId: number)
	local inv = playerInventories[userId]
	if not inv or not inv.equipment then return nil end
	
	local counts = {} -- { setID = count }
	for _, item in pairs(inv.equipment) do
		local data = DataService.getItem(item.itemId)
		if data and data.armorSet then
			counts[data.armorSet] = (counts[data.armorSet] or 0) + 1
		end
	end
	
	local ArmorSetData = require(ReplicatedStorage.Data.ArmorSetData)
	local bestSet = nil
	local bestBonus = nil
	
	for setId, count in pairs(counts) do
		local setData = ArmorSetData[setId]
		if setData and count >= #setData.items then
			-- ?�트 ?�성! (가??최근???�인???�트 ?�나�??�용?�거??중첩 가?�하�??????�음)
			-- ?�재??간단???�산?�거???�선?�위 ?��? �??�나�?반환
			bestSet = setId
			bestBonus = setData.bonuses
		end
	end
	
	return bestBonus, bestSet
end


function InventoryService.equipItem(player: Player, inventorySlot: number, equipmentSlotName: string)
	local userId = player.UserId
	local inv = playerInventories[userId]
	if not inv then return false, Enums.ErrorCode.NOT_FOUND end
	
	local slotData = inv.slots[inventorySlot]
	if not slotData then return false, Enums.ErrorCode.SLOT_EMPTY end
	
	local itemData = DataService.getItem(slotData.itemId)
	if not itemData then return false, Enums.ErrorCode.INVALID_ITEM end
	
	-- ?�롯 ?�??체크
	local targetSlot = equipmentSlotName:upper()
	if targetSlot ~= "HEAD" and targetSlot ~= "SUIT" and targetSlot ~= "HAND" then
		return false, Enums.ErrorCode.BAD_REQUEST
	end
	if itemData.slot and itemData.slot:upper() ~= targetSlot then
		warn(string.format("[InventoryService] Slot mismatch: %s vs %s", itemData.slot, targetSlot))
		return false, Enums.ErrorCode.BAD_REQUEST
	end

	-- 기존 ?�비?� 교체
	local oldEquip = inv.equipment[targetSlot]
	inv.equipment[targetSlot] = {
		itemId = slotData.itemId,
		durability = slotData.durability,
		attributes = slotData.attributes,
	}
	
	-- ?�벤?�리?�서 ?�거 (1개만)
	if slotData.count > 1 then
		slotData.count -= 1
	else
		inv.slots[inventorySlot] = nil
	end
	
	-- 기존 ?�비가 ?�었?�면 ?�벤?�리�?복구
	if oldEquip then
		InventoryService.addItem(userId, oldEquip.itemId, 1, oldEquip.durability, oldEquip.attributes)
	end
	
	-- ?�태 ?�???�청
	_emitChanged(player, { _makeChange(inv, inventorySlot) })
	
	-- ?�라?�언?�에 ?�비 변�??�보
	NetController.FireClient(player, "Inventory.Equipment.Changed", {
		equipment = inv.equipment
	})
	
	-- ?�비 변�??�보 (EquipService ?�동 - ?�구/무기거나 방어�??�각???�요 ??
	if EquipService then
		EquipService.updateAppearance(player) -- ?�체 ?�형 갱신 (?�의/?�의/?�트 ?�함)
		if targetSlot == "HAND" then
			EquipService.equipItem(player, inv.equipment[targetSlot].itemId)
		end
	end
	
	-- ?�탯 ?�계??(방어�???
	if PlayerStatService then
		PlayerStatService.applyStats(userId)
	end
	
	return true
end

function InventoryService.unequipItem(player: Player, equipmentSlotName: string)
	local userId = player.UserId
	local inv = playerInventories[userId]
	if not inv then return false, Enums.ErrorCode.NOT_FOUND end
	
	local oldEquip = inv.equipment[equipmentSlotName]
	if not oldEquip then return false, Enums.ErrorCode.SLOT_EMPTY end
	
	-- ?�벤?�리??공간 ?�는지 체크
	local added, remaining = InventoryService.addItem(userId, oldEquip.itemId, 1, oldEquip.durability, oldEquip.attributes)
	if added == 0 then
		return false, Enums.ErrorCode.INV_FULL
	end
	
	inv.equipment[equipmentSlotName] = nil
	
	-- ?�태 ?�???�청
	_emitChanged(player, {}) -- 무게 ?�산 ?�을 ?�해 �?change�??�출 가??
	
	-- ?�라?�언?�에 ?�비 변�??�보
	NetController.FireClient(player, "Inventory.Equipment.Changed", {
		equipment = inv.equipment
	})
	
	-- ?�비 ?�제 ?�보
	if EquipService then
		EquipService.updateAppearance(player)
		if equipmentSlotName == "HAND" then
			EquipService.equipItem(player, nil)
		end
	end
	
	if PlayerStatService then
		PlayerStatService.applyStats(userId)
	end
	
	return true
end

--========================================
-- Public API: Inventory Management
--========================================

--- ?�레?�어 ?�벤?�리 가?�오�??�는 ?�성
function InventoryService.getOrCreateInventory(userId: number): any
	if playerInventories[userId] then
		return playerInventories[userId]
	end
	
	-- SaveService?�서 로드 ?�도
	local savedInv = nil
	local savedEquip = nil
	local loadedState = nil
	
	-- [Race Condition FIX] ?�라?�언?�의 Get Request가 ServerInit 주입(Init)보다 먼�? ?�달??경우 ?�적 ?�당
	if not SaveService then
		local ServerService = game:GetService("ServerScriptService"):WaitForChild("Server"):WaitForChild("Services")
		SaveService = require(ServerService:WaitForChild("SaveService"))
	end
	if not DataService then
		local ServerService = game:GetService("ServerScriptService"):WaitForChild("Server"):WaitForChild("Services")
		DataService = require(ServerService:WaitForChild("DataService"))
	end

	if SaveService then
		local state = SaveService.getPlayerState(userId)
		if not state then
			-- SaveService가 ?��? PlayerAdded 루프?�서 로드�??�행?��?�? ?�기?�는 중복 ?�청 ?�이 ?�태 반영�??�기한??
			local deadline = os.clock() + 45
			while not state and os.clock() < deadline do
				task.wait(0.15)
				state = SaveService.getPlayerState(userId)
				if not game.Players:GetPlayerByUserId(userId) then break end
			end
		end

		if state then
			loadedState = state
			if state.inventory then savedInv = state.inventory end
			if state.equipment then savedEquip = state.equipment end
		else
			-- [FATAL FIX] 30초�? 지?�도 ?�이?��? ?�다�?�??�벤?�리�?부?�하??것이 "?�니?? ?�레?�어�??�하????��?�기 ?�고 방�?
			warn(string.format("[InventoryService] Timed out waiting for player state %d! Kicking to prevent wipe.", userId))
			local plr = game.Players:GetPlayerByUserId(userId)
			if plr then
				plr:Kick("?�이??로드 ?�간??초과?�었?�니?? ?�접?�해 주세??")
			end
			return nil -- 중단
		end
	end

	-- [중요] Yield(?��??�는 ?�안 ?�른 ?�레???? Get.Request)?�서 ?�벤?�리�??�성?�을 ???�으므�??�시 체크
	if playerInventories[userId] then
		return playerInventories[userId]
	end

	-- ?�이???�규??�?마이그레?�션 (?�구???�락 ???�??�??�자 ?�덱??강제)
	local normalizedSlots = {}
	if savedInv then
		for k, node in pairs(savedInv) do
			local numKey = tonumber(k) or (node and node.slot)
			if numKey and type(node) == "table" and node.itemId then
				local item = DataService.getItem(node.itemId)
				if item and item.durability and not node.durability then
					node.durability = item.durability -- ?�락???�구??초기??
				end
				
				-- 명시?�으�??�로???�자??기반 ?�셔?�리�?구축 (JSON 문자?????�류 ?�천 차단)
				normalizedSlots[numKey] = {
					itemId = node.itemId,
					count = node.count or 1,
					durability = node.durability,
					attributes = (node.attributes) or (node.attribute and node.attributeLevel and { [node.attribute] = node.attributeLevel }) or nil,
				}
			end
		end
	end
	
	if savedEquip then
		for _, node in pairs(savedEquip) do
			if node and node.itemId then
				local item = DataService.getItem(node.itemId)
				if item and item.durability and not node.durability then
					node.durability = item.durability
				end
			end
		end
	end

	-- [Defensive Fix] ?�토리얼 초반(1?�계)?�데 BRANCH가 비정??최�??�택?�로 로드?�면 1개로 보정
	-- ?�상 진행 �??�??보유 ?��?�?건드리�? ?�기 ?�해 "초반 + 미완�? ?�태?�서�??�용
	local sanitizedBranch = false
	if loadedState and type(loadedState.tutorialQuest) == "table" then
		local tq = loadedState.tutorialQuest
		local isEarlyTutorial = (tq.completed ~= true) and ((tonumber(tq.stepIndex) or 1) <= 1)
		if isEarlyTutorial then
			for slot, node in pairs(normalizedSlots) do
				if type(node) == "table" and node.itemId == "BRANCH" and (tonumber(node.count) or 0) >= Balance.MAX_STACK then
					normalizedSlots[slot].count = 1
					sanitizedBranch = true
					print(string.format("[InventoryService] Sanitized BRANCH stack for user %d at slot %s", userId, tostring(slot)))
				end
			end
		end
	end

	if sanitizedBranch and loadedState then
		loadedState.inventory = normalizedSlots
	end

	-- [Migration] 비스택 아이템 확장: count > 1인 비AMMO 아이템을 개별 슬롯으로 분리
	if DataService then
		local expandQueue = {}
		for slot = 1, Balance.MAX_INV_SLOTS do
			local node = normalizedSlots[slot]
			if node and node.itemId then
				local itemData = DataService.getItem(node.itemId)
				local isAmmo = itemData and itemData.type == "AMMO"
				if not isAmmo and node.count and node.count > 1 then
					table.insert(expandQueue, {
						slot = slot,
						itemId = node.itemId,
						extra = node.count - 1,
						durability = node.durability,
						attributes = node.attributes,
					})
					node.count = 1
				end
			end
		end
		for _, expand in ipairs(expandQueue) do
			for i = 1, expand.extra do
				local placed = false
				for s = 1, Balance.MAX_INV_SLOTS do
					if normalizedSlots[s] == nil then
						normalizedSlots[s] = {
							itemId = expand.itemId,
							count = 1,
							durability = expand.durability,
							attributes = expand.attributes,
						}
						placed = true
						break
					end
				end
				if not placed then
					warn(string.format("[InventoryService] Migration overflow: %s dropped for user %d", expand.itemId, userId))
					break
				end
			end
		end
	end

	-- 새 인벤토리 객체 생성
	local inv = {
		slots = normalizedSlots,
		equipment = _normalizeEquipmentSlots(savedEquip)
	}
	
	playerInventories[userId] = inv
	return inv
end

--- ?�레?�어 ?�벤?�리 가?�오�?
function InventoryService.getInventory(userId: number): any?
	return playerInventories[userId]
end

--- ?�레?�어 ?�벤?�리 ??�� (PlayerRemoving ??
function InventoryService.removeInventory(userId: number)
	playerInventories[userId] = nil
	playerActiveSlots[userId] = nil
end

--- ?�성 ?�롯 ?�정
function InventoryService.setActiveSlot(userId: number, slot: number)
	if slot < 1 or slot > 8 then return end -- ?�바 범위�?
	if playerActiveSlots[userId] == slot then return end -- ?��? ?�성 ?�롯?�면 무시
	
	playerActiveSlots[userId] = slot
	print(string.format("[InventoryService] Player %d active slot set to %d", userId, slot))
	
	-- ?�각???�착 ?�데?�트
	if EquipService then
		local player = Players:GetPlayerByUserId(userId)
		if player then
			local item = InventoryService.getSlot(userId, slot)
			EquipService.equipItem(player, item and item.itemId)
		end
	end
	
	-- ?�라?�언?�에 ?�림
	local player = Players:GetPlayerByUserId(userId)
	if player then
		NetController.FireClient(player, "Inventory.ActiveSlot.Changed", { slot = slot })
	end
end

--- ?�성 ?�롯 조회
function InventoryService.getActiveSlot(userId: number): number
	return playerActiveSlots[userId] or 1
end

--========================================
-- Public API: Move
--========================================

--- ?�이???�동 (fromSlot -> toSlot)
--- count가 nil?�면 ?�체 ?�동
function InventoryService.move(player: Player, fromSlot: number, toSlot: number, count: number?): (boolean, string?, any?)
	local userId = player.UserId
	local inv = playerInventories[userId]
	
	if not inv then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- ?�롯 범위 검�?(먼�?!)
	local ok, err = _validateSlotRange(fromSlot)
	if not ok then return false, err, nil end
	
	ok, err = _validateSlotRange(toSlot)
	if not ok then return false, err, nil end
	
	-- 같�? ?�롯?�면 무시
	if fromSlot == toSlot then
		return true, nil, nil
	end
	
	-- 출발 ?�롯???�이?�이 ?�는지
	ok, err = _validateHasItem(inv, fromSlot)
	if not ok then return false, err, nil end
	
	-- ?�량 검�?
	ok, err = _validateCount(count)
	if not ok then return false, err, nil end
	
	local fromData = inv.slots[fromSlot]
	local moveCount = count or fromData.count  -- nil?�면 ?�체

	-- 방어구는 ?�바(1~8) ?�롯?�로 ?�동 금�?
	if _isArmorItemId(fromData.itemId) and toSlot <= HOTBAR_SLOT_MAX then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end
	
	-- ?�동 ?�량 검�?
	ok, err = _validateCountAvailable(inv, fromSlot, moveCount)
	if not ok then return false, err, nil end
	
	local toData = inv.slots[toSlot]
	local changes = {}
	
	if toData == nil then
		-- ?�???�롯??비어?�으�? ?�순 ?�동
		_increaseSlot(inv, toSlot, fromData.itemId, moveCount, fromData.durability, fromData.attributes)
		_decreaseSlot(inv, fromSlot, moveCount)
		
		table.insert(changes, _makeChange(inv, fromSlot))
		table.insert(changes, _makeChange(inv, toSlot))
		
	elseif toData.itemId == fromData.itemId then
		if _isStackable(fromData.itemId) then
			-- 스택 가능 아이템(화살류): 스택 병합
			local itemMaxStack = _getMaxStack(fromData.itemId)
			local canAdd = math.max(0, itemMaxStack - toData.count)
			local actualMove = math.min(moveCount, canAdd)
			
			if actualMove > 0 then
				_increaseSlot(inv, toSlot, fromData.itemId, actualMove, fromData.durability, fromData.attributes)
				_decreaseSlot(inv, fromSlot, actualMove)
				
				table.insert(changes, _makeChange(inv, fromSlot))
				table.insert(changes, _makeChange(inv, toSlot))
			else
				return false, Enums.ErrorCode.STACK_OVERFLOW, nil
			end
		else
			-- 비스택 아이템: 같은 아이템이어도 스왑
			if count ~= nil then
				return false, Enums.ErrorCode.ITEM_MISMATCH, nil
			end
			inv.slots[fromSlot] = toData
			inv.slots[toSlot] = fromData
			table.insert(changes, _makeChange(inv, fromSlot))
			table.insert(changes, _makeChange(inv, toSlot))
		end
		
	else
		-- ?�른 ?�이?�이�? ?�왑 (?�체 ?�동???�만)
		if count ~= nil then
			-- 부�??�동?� ?�른 ?�이?�과 불�?
			return false, Enums.ErrorCode.ITEM_MISMATCH, nil
		end
		
		-- ?�왑
		inv.slots[fromSlot] = toData
		inv.slots[toSlot] = fromData
		
		table.insert(changes, _makeChange(inv, fromSlot))
		table.insert(changes, _makeChange(inv, toSlot))
	end
	
	-- ?�벤??발생
	_emitChanged(player, changes)
	
	return true, nil, { changes = changes }
end

--========================================
-- Public API: Split
--========================================

--- ?�택 분할 (fromSlot?�서 count만큼 ?�서 toSlot?????�택)
--- toSlot?� 반드??비어?�어????
function InventoryService.split(player: Player, fromSlot: number, toSlot: number, count: number): (boolean, string?, any?)
	local userId = player.UserId
	local inv = playerInventories[userId]
	
	if not inv then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- ?�롯 범위 검�?(먼�?!)
	local ok, err = _validateSlotRange(fromSlot)
	if not ok then return false, err, nil end
	
	ok, err = _validateSlotRange(toSlot)
	if not ok then return false, err, nil end
	
	-- 같�? ?�롯?�면 불�?
	if fromSlot == toSlot then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end
	
	-- 출발 ?�롯???�이?�이 ?�는지
	ok, err = _validateHasItem(inv, fromSlot)
	if not ok then return false, err, nil end
	
	-- ?�???�롯??비어?�는지
	ok, err = _validateSlotEmpty(inv, toSlot)
	if not ok then return false, err, nil end
	
	-- ?�량 검�?(split?� count ?�수)
	if count == nil then
		return false, Enums.ErrorCode.INVALID_COUNT, nil
	end
	
	ok, err = _validateCount(count)
	if not ok then return false, err, nil end
	
	-- ?�동 ?�량 검�?
	ok, err = _validateCountAvailable(inv, fromSlot, count)
	if not ok then return false, err, nil end
	
	local fromData = inv.slots[fromSlot]
	
	-- 분할 ?�용
	_setSlot(inv, toSlot, fromData.itemId, count, fromData.durability, fromData.attributes)
	_decreaseSlot(inv, fromSlot, count)
	
	local changes = {
		_makeChange(inv, fromSlot),
		_makeChange(inv, toSlot),
	}
	
	-- ?�벤??발생
	_emitChanged(player, changes)
	
	return true, nil, { changes = changes }
end

--========================================
-- Public API: Drop
--========================================

--- ?�이???�롭 (?�벤?�서 감소�? ?�드 ?�롭?� ?�중??
--- count가 nil?�면 ?�체 ?�롭
function InventoryService.drop(player: Player, slot: number, count: number?): (boolean, string?, any?)
	local userId = player.UserId
	local inv = playerInventories[userId]
	
	if not inv then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- ?�롯 범위 검�?
	local ok, err = _validateSlotRange(slot)
	if not ok then return false, err, nil end
	
	-- ?�롯???�이?�이 ?�는지
	ok, err = _validateHasItem(inv, slot)
	if not ok then return false, err, nil end
	
	-- ?�량 검�?
	ok, err = _validateCount(count)
	if not ok then return false, err, nil end
	
	local slotData = inv.slots[slot]
	local dropCount = count or slotData.count  -- nil?�면 ?�체
	
	-- ?�롭 ?�량 검�?
	ok, err = _validateCountAvailable(inv, slot, dropCount)
	if not ok then return false, err, nil end
	
	local droppedItem = {
		itemId = slotData.itemId,
		count = dropCount,
		durability = slotData.durability, -- ?�구??보존
	}
	
	-- ?�벤?�서 감소
	_decreaseSlot(inv, slot, dropCount)
	
	local changes = {
		_makeChange(inv, slot),
	}
	
	-- ?�벤??발생
	_emitChanged(player, changes)
	
	return true, nil, {
		dropped = droppedItem,
		changes = changes,
	}
end

--========================================
-- Public API: MoveInternal (범용 컨테?�너 �??�동)
-- StorageService ?�에???�사??
--========================================

--- ?�롯 범위 검�?(커스?� maxSlots)
local function _validateSlotRangeCustom(slot: number, maxSlots: number, allowZero: boolean?): (boolean, string?)
	if type(slot) ~= "number" then
		return false, Enums.ErrorCode.INVALID_SLOT
	end
	if allowZero and slot == 0 then return true, nil end
	if slot < 1 or slot > maxSlots or slot ~= math.floor(slot) then
		return false, Enums.ErrorCode.INVALID_SLOT
	end
	return true, nil
end

--- 범용 컨테?�너 �??�이???�동
--- sourceContainer, targetContainer: { slots = { [slot] = {itemId, count} } }
--- maxSlots: ?�롯 최�? ??
--- ?�벤??발행?� ?�출??책임
function InventoryService.MoveInternal(
	sourceContainer: any,
	sourceSlot: number,
	sourceMaxSlots: number,
	targetContainer: any,
	targetSlot: number,
	targetMaxSlots: number,
	count: number?
): (boolean, string?, any?)
	
	-- ?�스/?��?검�?
	if not sourceContainer or not sourceContainer.slots then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	if not targetContainer or not targetContainer.slots then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- ?�롯 범위 검�?
	local ok, err = _validateSlotRangeCustom(sourceSlot, sourceMaxSlots)
	if not ok then return false, err, nil end
	
	ok, err = _validateSlotRangeCustom(targetSlot, targetMaxSlots, true)
	if not ok then return false, err, nil end
	
	-- ?�물 ?�이???�보 ?�인
	ok, err = _validateHasItem(sourceContainer, sourceSlot)
	if not ok then return false, err, nil end
	
	local sourceData = sourceContainer.slots[sourceSlot]

	-- 자동 슬롯 이동 선택 (targetSlot == 0)
	if targetSlot == 0 then
		-- 1. 스택 가능 아이템만: 같은 아이템 스택 가능 슬롯 찾기
		if _isStackable(sourceData.itemId) then
			local itemMaxStack = _getMaxStack(sourceData.itemId)
			for i = 1, targetMaxSlots do
				local ts = targetContainer.slots[i]
				if ts and ts.itemId == sourceData.itemId and ts.count < itemMaxStack then
					targetSlot = i
					break
				end
			end
		end
		-- 2. 빈 슬롯 찾기
		if targetSlot == 0 then
			for i = 1, targetMaxSlots do
				if targetContainer.slots[i] == nil then
					targetSlot = i
					break
				end
			end
		end
		-- 여전히 0이면 공간 없음
		if targetSlot == 0 then
			return false, Enums.ErrorCode.INV_FULL, nil
		end
	end

	-- 같�? 컨테?�너 + 같�? ?�롯?�면 무시
	if sourceContainer == targetContainer and sourceSlot == targetSlot then
		return true, nil, nil
	end
	
	-- ?�량 검�?
	ok, err = _validateCount(count)
	if not ok then return false, err, nil end
	
	local sourceData = sourceContainer.slots[sourceSlot]
	local moveCount = count or sourceData.count  -- nil?�면 ?�체
	
	-- ?�동 ?�량 검�?
	ok, err = _validateCountAvailable(sourceContainer, sourceSlot, moveCount)
	if not ok then return false, err, nil end
	
	local targetData = targetContainer.slots[targetSlot]
	
	local sourceChanges = {}
	local targetChanges = {}
	
	if targetData == nil then
		-- ?��??�롯??비어?�으�? ?�순 ?�동
		_increaseSlot(targetContainer, targetSlot, sourceData.itemId, moveCount, sourceData.durability, sourceData.attributes)
		_decreaseSlot(sourceContainer, sourceSlot, moveCount)
		
		table.insert(sourceChanges, _makeChange(sourceContainer, sourceSlot))
		table.insert(targetChanges, _makeChange(targetContainer, targetSlot))
		
	elseif targetData.itemId == sourceData.itemId then
		if _isStackable(sourceData.itemId) then
			-- 스택 가능 아이템(화살류): 스택 병합
			local itemMaxStack = _getMaxStack(sourceData.itemId)
			local canAdd = math.max(0, itemMaxStack - targetData.count)
			local actualMove = math.min(moveCount, canAdd)
			
			if actualMove > 0 then
				_increaseSlot(targetContainer, targetSlot, sourceData.itemId, actualMove, sourceData.durability, sourceData.attributes)
				_decreaseSlot(sourceContainer, sourceSlot, actualMove)
				
				table.insert(sourceChanges, _makeChange(sourceContainer, sourceSlot))
				table.insert(targetChanges, _makeChange(targetContainer, targetSlot))
			else
				return false, Enums.ErrorCode.STACK_OVERFLOW, nil
			end
		else
			-- 비스택 아이템: 같은 아이템이어도 스왑
			if count ~= nil then
				return false, Enums.ErrorCode.ITEM_MISMATCH, nil
			end
			if sourceContainer ~= targetContainer then
				return false, Enums.ErrorCode.ITEM_MISMATCH, nil
			end
			sourceContainer.slots[sourceSlot] = targetData
			sourceContainer.slots[targetSlot] = sourceData
			table.insert(sourceChanges, _makeChange(sourceContainer, sourceSlot))
			table.insert(targetChanges, _makeChange(sourceContainer, targetSlot))
		end
		
	else
		-- ?�른 ?�이?�이�? ?�왑 (?�체 ?�동???�만, 같�? 컨테?�너 ?�에?�만)
		if count ~= nil then
			return false, Enums.ErrorCode.ITEM_MISMATCH, nil
		end
		
		if sourceContainer ~= targetContainer then
			-- ?�른 컨테?�너 �??�왑?� 복잡?��?�?금�?
			return false, Enums.ErrorCode.ITEM_MISMATCH, nil
		end
		
		-- ?�왑
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

--- ?�이??추�? (�??�롯 ?�는 기존 ?�택??
--- 반환: 추�????�량, ?��? ?�량
function InventoryService.addItem(userId: number, itemId: string, count: number, durability: number?, attributes: any?): (number, number)
	local inv = playerInventories[userId]
	if not inv then
		return 0, count
	end
	
	local player = Players:GetPlayerByUserId(userId)
	
	local remaining = count
	local added = 0
	local changedSlots = {}
	
	-- ?�롯 ??체크
	local maxSlots = _getMaxSlots(userId)

	-- ?�구???�보 조회 (???�택 ?�성 ???�용)
	local maxDurability = durability -- ?�달받�? ?�구???�선
	if not maxDurability and DataService then
		local itemData = DataService.getItem(itemId)
		if itemData then maxDurability = itemData.durability end
	end
	
	-- 스택 가능 여부 / 아이템별 최대 스택
	local stackable = _isStackable(itemId)
	local itemMaxStack = _getMaxStack(itemId)
	
	-- 1. 기존 스택에 병합 (스택 가능 아이템(화살류)만, 내구도 없는 경우)
	if stackable and not maxDurability then
		for slot = 1, maxSlots do
			if remaining <= 0 then break end
			
			local slotData = inv.slots[slot]
			if slotData and slotData.itemId == itemId and slotData.count < itemMaxStack and not slotData.durability then
				local canAddByStack = itemMaxStack - slotData.count
				
				local canAdd = math.min(remaining, canAddByStack)
				if canAdd <= 0 then break end

				slotData.count = slotData.count + canAdd
				remaining = remaining - canAdd
				added = added + canAdd
				changedSlots[slot] = true
			end
		end
	end
	
	-- 2. 빈 슬롯에 새 아이템 배치
	-- 방어구는 핫바(1~8) 자동 이동을 방지하기 위해 9번 이후 슬롯을 우선 사용
	local slotOrder = {}
	local curItemData = DataService and DataService.getItem(itemId)
	local isArmor = curItemData and curItemData.type == "ARMOR"
	if isArmor then
		for slot = HOTBAR_SLOT_MAX + 1, maxSlots do
			table.insert(slotOrder, slot)
		end
		for slot = 1, HOTBAR_SLOT_MAX do
			table.insert(slotOrder, slot)
		end
	else
		for slot = 1, maxSlots do
			table.insert(slotOrder, slot)
		end
	end

	for _, slot in ipairs(slotOrder) do
		if remaining <= 0 then break end
		
		if inv.slots[slot] == nil then
			-- 스택 가능: 최대 itemMaxStack, 비스택: 항상 1
			local canAdd = stackable and math.min(remaining, itemMaxStack) or 1
			if canAdd <= 0 then break end

			inv.slots[slot] = {
				itemId = itemId,
				count = canAdd,
				durability = maxDurability,
				attributes = attributes,
			}
			remaining = remaining - canAdd
			added = added + canAdd
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

	if added > 0 and questItemCallback then
		task.spawn(function()
			questItemCallback(userId, itemId, added)
		end)
	end
	
	-- [FIX] Ensure items are packed during sort request only, not every add (Performance optimization)
	-- InventoryService.sort(userId)
	
	return added, remaining
end

--- ?�벤?�리 ?�렬 (�??�롯 채우�?
function InventoryService.sort(userId: number)
	local inv = playerInventories[userId]
	if not inv then return end
	
	local items = {}
	for slot = 1, Balance.MAX_INV_SLOTS do
		if inv.slots[slot] then
			table.insert(items, inv.slots[slot])
			inv.slots[slot] = nil
		end
	end
	
	-- 아이템 압축 (스택 가능 아이템만 병합, 비스택은 개별 유지)
	local compressed = {}
	for _, item in ipairs(items) do
		local remaining = item.count or 1
		local isItemStackable = _isStackable(item.itemId)
		local itemMaxStack = _getMaxStack(item.itemId)
		
		if isItemStackable then
			for _, comp in ipairs(compressed) do
				if remaining <= 0 then break end
				if comp.itemId == item.itemId and comp.count < itemMaxStack and not comp.durability and not item.durability then
					local space = itemMaxStack - comp.count
					local amount = math.min(remaining, space)
					comp.count = comp.count + amount
					remaining = remaining - amount
				end
			end
		end
		
		-- 비스택 아이템은 1개씩 개별 슬롯으로 배치
		if not isItemStackable then
			for i = 1, remaining do
				table.insert(compressed, {
					itemId = item.itemId,
					count = 1,
					durability = item.durability,
					attributes = item.attributes,
				})
			end
		elseif remaining > 0 then
			table.insert(compressed, {
				itemId = item.itemId,
				count = remaining,
				durability = item.durability,
				attributes = item.attributes,
			})
		end
	end

	inv.slots = {}
	for index, item in ipairs(compressed) do
		if index > Balance.MAX_INV_SLOTS then
			break
		end
		inv.slots[index] = {
			itemId = item.itemId,
			count = item.count,
			durability = item.durability,
			attributes = item.attributes,
		}
	end
	
	local player = Players:GetPlayerByUserId(userId)
	
	if player then
		-- [최적?? 모든 ?�롯 ?��? ?�??FullStack ?�송 (?�덱???�실 방�?�??�해 getFullInventory 배열 ?�용)
		_emitChanged(player, {}, InventoryService.getFullInventory(userId))
		
		-- [추�? FIX] ?�렬 ???�재 ?�성 ?�롯(1~8)???�???�각???�착 갱신 강제 ?�행
		local active = playerActiveSlots[userId] or 1
		local item = inv.slots[active]
		if EquipService then
			EquipService.equipItem(player, item and item.itemId)
		end
		
		-- 클라이언트에 핫바 동기화 알림
		if NetController then
			NetController.FireClient(player, "Inventory.ActiveSlot.Changed", { slot = active })
		end
	end
end

--- �??�롯 개수
function InventoryService.getEmptySlotCount(userId: number): number
	local inv = playerInventories[userId]
	if not inv then return 0 end
	
	local count = 0
	for slot = 1, Balance.MAX_INV_SLOTS do
		if inv.slots[slot] == nil then
			count = count + 1
		end
	end
	return count
end

--- ?�량 ?�용 가???��? 검�?(?�수 ?�수, ?�태 변�??�음)
--- Loot ?�자???�보??
function InventoryService.canAdd(userId: number, itemId: string, count: number): boolean
	local inv = playerInventories[userId]
	if not inv then return false end
	
	local remaining = count
	local stackable = _isStackable(itemId)
	local itemMaxStack = _getMaxStack(itemId)
	
	-- 1. 스택 가능 아이템만: 기존 스택 여유분 계산
	if stackable then
		for slot = 1, Balance.MAX_INV_SLOTS do
			if remaining <= 0 then break end
			
			local slotData = inv.slots[slot]
			if slotData and slotData.itemId == itemId and slotData.count < itemMaxStack then
				remaining = remaining - (itemMaxStack - slotData.count)
			end
		end
	end
	
	-- 2. 빈 슬롯 개수 계산 (스택 가능: itemMaxStack씩, 비스택: 1씩)
	for slot = 1, Balance.MAX_INV_SLOTS do
		if remaining <= 0 then break end
		
		if inv.slots[slot] == nil then
			remaining = remaining - itemMaxStack
		end
	end
	
	return remaining <= 0
end

--- ?�이??보유 ?��? ?�인 (?�수 ?�수)
function InventoryService.hasItem(userId: number, itemId: string, count: number): boolean
	local inv = playerInventories[userId]
	if not inv then return false end
	
	local total = 0
	for slot = 1, Balance.MAX_INV_SLOTS do
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

--- ?�이???�거 (?�러 ?�롯?�서 분산 ?�거)
--- 반환: ?�거???�량
function InventoryService.removeItem(userId: number, itemId: string, count: number): number
	local inv = playerInventories[userId]
	if not inv then return 0 end
	
	local remaining = count
	local removed = 0
	local changedSlots = {}
	
	-- ?�롯 ?�회?�며 ?�거
	for slot = 1, Balance.MAX_INV_SLOTS do
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
	
	-- ?�벤??발생
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

--- ?�정 ?�롯?�서 ?�이???�거
function InventoryService.removeItemFromSlot(userId: number, slot: number, count: number): number
	local inv = playerInventories[userId]
	if not inv then return 0 end
	
	local ok, err = _validateSlotRange(slot)
	if not ok then return 0 end
	
	local slotData = inv.slots[slot]
	if not slotData then return 0 end
	
	local toRemove = math.min(count, slotData.count)
	_decreaseSlot(inv, slot, toRemove)
	
	-- ?�벤??발생
	local player = Players:GetPlayerByUserId(userId)
	if player then
		_emitChanged(player, { _makeChange(inv, slot) })
	end
	
	return toRemove
end

--- ?�체 ?�벤?�리 ?�이??반환 (?�라?�언???�기?�용)
function InventoryService.getFullInventory(userId: number): {{slot: number, itemId: string?, count: number?}}
	local inv = playerInventories[userId]
	if not inv then return {} end
	
	local result = {}
	for slot = 1, Balance.MAX_INV_SLOTS do
		local slotData = inv.slots[slot]
		if slotData then
			table.insert(result, {
				slot = slot,
				itemId = slotData.itemId,
				count = slotData.count,
				durability = slotData.durability,
				attributes = slotData.attributes,
			})
		end
	end
	return result
end

--- ?�구??감소 (0 ?�하 ?�괴)
--- 반환: success, errorCode, currentDurability(or 0)
function InventoryService.decreaseDurability(userId: number, slot: number, amount: number)
	local inv = playerInventories[userId]
	if not inv then return false, Enums.ErrorCode.NOT_FOUND end
	
	local slotData = inv.slots[slot]
	
	-- ?�이?�이 ?�거???�구?��? ?�는 ?�이?�이�?무시 (?�는 ?�러)
	if not slotData then return false, Enums.ErrorCode.SLOT_EMPTY end
	if not slotData.durability then return false, Enums.ErrorCode.INVALID_ITEM end
	
	slotData.durability = slotData.durability - amount
	local current = slotData.durability
	
	if current <= 0 then
		-- ?�괴
		inv.slots[slot] = nil
	end
	
	-- ?�벤??
	local player = Players:GetPlayerByUserId(userId)
	if player then
		_emitChanged(player, {_makeChange(inv, slot)})
	end
	
	return true, nil, math.max(0, current)
end

--- ?�비 ?�롯 ?�구??감소
function InventoryService.decreaseEquipmentDurability(userId: number, equipmentSlotName: string, amount: number)
	local inv = playerInventories[userId]
	if not inv or not inv.equipment then return false, Enums.ErrorCode.NOT_FOUND end
	
	local slotData = inv.equipment[equipmentSlotName]
	if not slotData then return false, Enums.ErrorCode.SLOT_EMPTY end
	if not slotData.durability then return false, Enums.ErrorCode.INVALID_ITEM end
	
	slotData.durability = math.max(0, slotData.durability - amount)
	local current = slotData.durability
	
	if current <= 0 then
		-- 장비 파괴 (장착 제거)
		print(string.format("[InventoryService] Equipment %s destroyed for user %d", equipmentSlotName, userId))
		inv.equipment[equipmentSlotName] = nil
	end
	
	-- SaveService에 장비 상태 동기화 (내구도 변동 및 파괴 반영)
	if SaveService then
		SaveService.updatePlayerState(userId, function(state)
			state.equipment = inv.equipment
			return state
		end)
	end
	
	-- 이벤트 발생
	local player = game:GetService("Players"):GetPlayerByUserId(userId)
	if player then
		NetController.FireClient(player, "Inventory.Equipment.Changed", { equipment = inv.equipment })
		
		-- ?�드 ?�롯 ?�괴 ???�각???�데?�트
		if equipmentSlotName == "HAND" and current <= 0 then
			if EquipService then
				EquipService.equipItem(player, nil)
			end
		end
		
		-- ?�탯 ?�계??(방어??공격????변�??�??
		if PlayerStatService then
			PlayerStatService.recalculateStats(userId)
		end
	end
	
	return true, nil, current
end

--- ?�구???�정 (?�리 ?�에 ?�용)
function InventoryService.setDurability(userId: number, slot: number, amount: number)
	local inv = playerInventories[userId]
	if not inv then return false, Enums.ErrorCode.NOT_FOUND end
	
	local slotData = inv.slots[slot]
	if not slotData then return false, Enums.ErrorCode.SLOT_EMPTY end
	
	slotData.durability = amount
	
	-- ?�벤??
	local player = Players:GetPlayerByUserId(userId)
	if player then
		_emitChanged(player, {_makeChange(inv, slot)})
	end
	
	return true
end

--- ?�재 ?�착 중인(?�택???�바) ?�이??조회
function InventoryService.getEquippedItem(userId: number): any?
	local inv = playerInventories[userId]
	if not inv then return nil end
	
	-- ?�버 권위(Active Slot) 기반?�로 ?�재 ?�착 ?�이??조회
	local active = InventoryService.getActiveSlot(userId)
	return InventoryService.getSlot(userId, active)
end

--- 특정 슬롯 아이템 조회
function InventoryService.getSlot(userId: number, slot: number): any?
	local inv = playerInventories[userId]
	if not inv then return nil end
	return inv.slots[slot]
end

--- 아이템 스택 가능 여부 조회 (외부 서비스용)
function InventoryService.isStackable(itemId: string): boolean
	return _isStackable(itemId)
end

--- 아이템별 최대 스택 수량 조회 (외부 서비스용)
function InventoryService.getMaxStackForItem(itemId: string): number
	return _getMaxStack(itemId)
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
	return { success = true, data = data }  -- data.dropped ?�함
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
	
	-- 1. ?�착 가???�이??(무기, ?�구 ??
	if itemData.type == Enums.ItemType.WEAPON or itemData.type == Enums.ItemType.TOOL or itemData.type == Enums.ItemType.ARMOR then
		-- ?��? ?�바(1-8)???�는 경우 -> ?�성 ?�롯?�로 ?�정
		if slot >= 1 and slot <= 8 then
			InventoryService.setActiveSlot(userId, slot)
			NetController.FireClient(player, "Inventory.ActiveSlot.Changed", { slot = slot })
			return { success = true, data = { action = "SELECT", slot = slot } }
		else
			-- 가방에 ?�는 경우
			
			-- [추�?] 방어�??�?�이�??�용 ?�롯(BODY ?? ?�보가 ?�는 경우 바로 ?�착
			if itemData.type == Enums.ItemType.ARMOR and itemData.slot then
				local success, err = InventoryService.equipItem(player, slot, itemData.slot:upper())
				if success then
					return { success = true, data = { action = "EQUIP_ARMOR", slot = itemData.slot } }
				end
				-- ?�패 ???�롯 꽉참 ?? ?�반 Swap 로직?�로 ?�오버하거나 ?�러 반환
				if err then return { success = false, errorCode = err } end
			end

			-- 무기/?�구 ?��? ?�롯 ?�보 ?�는 방어�?-> ?�재 ?�성 ?�바 ?�롯�?교체(Swap)
			local activeSlot = InventoryService.getActiveSlot(userId)
			local success, err = InventoryService.move(player, slot, activeSlot, nil)
			if success then
				-- ?�동 ?�공 ???�성 ?�롯???�???�착 ?�데?�트
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
	
	-- 2. DNA ?�이??(?�용 ???�감 ?�록)
	if itemData.type == "DNA" then
		local creatureId = itemData.creatureId
		if not creatureId then
			return { success = false, errorCode = Enums.ErrorCode.INVALID_ITEM }
		end
		
		-- ?�감??DNA ?�록
		if PlayerStatService and PlayerStatService.addCollectionDna then
			PlayerStatService.addCollectionDna(userId, creatureId, 1)
		end
		
		-- ?�벤?�리?�서 1�??�모 (?�롯 기반 ?�거)
		InventoryService.removeItemFromSlot(userId, slot, 1)
		
		-- ?�라?�언?�에 ?�감 ?�록 ?�공 ?�림
		if NetController then
			NetController.FireClient(player, "DNA.Registered", {
				creatureId = creatureId,
				itemId = slotData.itemId,
			})
		end

		return { success = true, data = { action = "DNA_REGISTER", creatureId = creatureId, itemId = slotData.itemId } }
	end
	
	-- 3. ?�모???�이??
	if itemData.type == Enums.ItemType.CONSUMABLE then
		-- ?�시: ?�용 ?�림�?
		print(string.format("[InventoryService] User %d used %s", userId, slotData.itemId))
		return { success = true, data = { action = "USE", itemId = slotData.itemId } }
	end
	
	-- 3. ?�식 (Phase 11 ?�동)
	if itemData.type == Enums.ItemType.FOOD or itemData.foodValue then
		local HungerService = require(game:GetService("ServerScriptService").Server.Services.HungerService)
		local current, max = HungerService.getHunger(userId)
		if current >= max and not itemData.healingValue then
			-- 배�? 가??차있�?치유 ?�과???�는 ?�식?�면 ??먹어�?
			return { success = false, errorCode = "HUNGER_FULL" }
		end
		
		-- 배고???�복
		if itemData.foodValue then
			HungerService.eatFood(userId, itemData.foodValue)
		end
		
		-- 체력 ?�복
		if itemData.healingValue then
			local character = player.Character
			local humanoid = character and character:FindFirstChild("Humanoid")
			if humanoid then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + itemData.healingValue)
			end
		end
		
		-- ?�이??1�??�모
		InventoryService.removeItemFromSlot(userId, slot, 1)

		-- ?�스??콜백 (?�식 ??��)
		if questFoodEatenCallback then
			task.spawn(questFoodEatenCallback, userId, slotData.itemId)
		end
		
		return { success = true, data = { action = "EAT", itemId = slotData.itemId, foodValue = itemData.foodValue } }
	end
	
	return { success = false, errorCode = Enums.ErrorCode.NOT_SUPPORTED }
end

local function handleGetInventory(player: Player, payload: any)
	local userId = player.UserId
	-- [중요] ?�라?�언?��? ?�이?��? ?�청?????�버 로드가 ?�나지 ?�았?????�으므�??��?(Race Condition ?�결)
	local inv = InventoryService.getOrCreateInventory(userId)
	local slots = InventoryService.getFullInventory(userId)
	
	return {
		success = true,
		data = {
			inventory = slots, -- Client expects 'inventory'
			equipment = inv and inv.equipment or {},
			usedSlots = inv and _getUsedSlots(inv) or 0,
			maxSlots = _getMaxSlots(userId),
			maxStack = Balance.MAX_STACK,
		}
	}
end

--- ?�버�? ?�이??지�?
local function handleGiveItem(player: Player, payload: any)
	if not _canUseDebugGrant(player) then
		return {
			success = false,
			errorCode = Enums.ErrorCode.NO_PERMISSION,
		}
	end

	local body = type(payload) == "table" and payload or {}
	local itemId = type(body.itemId) == "string" and body.itemId or "STONE"
	local count = tonumber(body.count) or 30
	count = math.floor(count)
	count = math.clamp(count, 1, Balance.MAX_STACK)

	if DataService and not DataService.getItem(itemId) then
		return {
			success = false,
			errorCode = Enums.ErrorCode.NOT_FOUND,
		}
	end
	
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
	InventoryService.setActiveSlot(userId, 1) -- 초기 ?�성 ?�롯 1�?
	
	-- [FIX] 리스?????�비 ?�형 �??�구 ?�동 복구
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then return end
		
		-- 캐릭???�업(?��????????�료???�까지 ?�간??지??(Race Condition 방�?)
		task.delay(0.1, function()
			if EquipService then
				EquipService.updateAppearance(player)
				
				-- ?�에 ?�고 ?�던 ?�이???�착 (?�성 ?�롯 기�?)
				local activeSlot = InventoryService.getActiveSlot(userId)
				local inv = playerInventories[userId]
				if inv and inv.slots[activeSlot] then
					EquipService.equipItem(player, inv.slots[activeSlot].itemId)
				end
			end
		end)
	end)
	
end

-- onPlayerRemoving moved to SaveService to prevent Race Condition

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
	
	-- ?�레?�어 ?�벤???�결
	Players.PlayerAdded:Connect(onPlayerAdded)
	-- Players.PlayerRemoving:Connect(onPlayerRemoving) -- Moved to SaveService
	
	-- ?��? ?�속???�레?�어 처리
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	
	initialized = true
	print(string.format("[InventoryService] Initialized - Slots: %d, MaxStack: %d", 
		Balance.MAX_INV_SLOTS, Balance.MAX_STACK))
end

--========================================
-- Public API: Drop Excess Items (스탯 초기화 시)
--========================================

--- newMaxSlots를 초과하는 슬롯의 아이템을 월드에 드랍하고 인벤에서 제거
--- @return table 드랍된 아이템 목록 {{itemId, count, durability}}
function InventoryService.dropExcessItems(player: Player, newMaxSlots: number): {{itemId: string, count: number, durability: number?}}
	local userId = player.UserId
	local inv = playerInventories[userId]
	if not inv then return {} end
	
	local droppedItems = {}
	local changedSlots = {}
	
	-- newMaxSlots+1 ~ MAX_INV_SLOTS 범위의 아이템 수집 및 제거
	for slot = newMaxSlots + 1, Balance.MAX_INV_SLOTS do
		local slotData = inv.slots[slot]
		if slotData then
			table.insert(droppedItems, {
				itemId = slotData.itemId,
				count = slotData.count,
				durability = slotData.durability,
			})
			inv.slots[slot] = nil
			changedSlots[slot] = true
		end
	end
	
	if #droppedItems <= 0 then return droppedItems end
	
	-- WorldDropService 지연 로딩으로 월드에 드랍
	local wdOk, WorldDropService = pcall(function()
		return require(game:GetService("ServerScriptService").Server.Services.WorldDropService)
	end)
	
	if wdOk and WorldDropService and WorldDropService.spawnDrop then
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local basePos = hrp.Position + Vector3.new(0, -1, 0)
			for i, item in ipairs(droppedItems) do
				-- 아이템별로 약간 다른 위치에 드랍 (원형 배치)
				local angle = (i - 1) * (2 * math.pi / math.max(#droppedItems, 1))
				local offset = Vector3.new(math.cos(angle) * 3, 0, math.sin(angle) * 3)
				WorldDropService.spawnDrop(basePos + offset, item.itemId, item.count, item.durability)
			end
		end
	end
	
	-- 클라이언트에 변경 알림
	local changes = {}
	for slot, _ in pairs(changedSlots) do
		table.insert(changes, _makeChange(inv, slot))
	end
	_emitChanged(player, changes)
	
	return droppedItems
end

function InventoryService.GetHandlers()
	local handlers = {
		["Inventory.Move.Request"] = handleMove,
		["Inventory.Split.Request"] = handleSplit,
		["Inventory.Drop.Request"] = handleDrop,
		["Inventory.Get.Request"] = handleGetInventory,
		["Inventory.ActiveSlot.Request"] = handleActiveSlot,
		["Inventory.Use.Request"] = handleUse,
		["Inventory.Equip.Request"] = function(player, payload)
			local success, err = InventoryService.equipItem(player, payload.fromSlot, payload.toSlot)
			return { success = success, errorCode = err }
		end,
		["Inventory.Unequip.Request"] = function(player, payload)
			local success, err = InventoryService.unequipItem(player, payload.slot)
			return { success = success, errorCode = err }
		end,
		["Inventory.Sort.Request"] = function(player, payload)
			InventoryService.sort(player.UserId)
			return { success = true }
		end,
	}

	if RunService:IsStudio() then
		handlers["Inventory.GiveItem"] = handleGiveItem
	end

	return handlers
end

function InventoryService.SetQuestItemCallback(callback)
	questItemCallback = callback
end

function InventoryService.SetQuestFoodEatenCallback(callback)
	questFoodEatenCallback = callback
end

return InventoryService
