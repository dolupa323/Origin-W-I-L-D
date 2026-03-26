-- CraftingService.lua
-- Phase 2-2: 제작 시스템
-- Server-Authoritative: 모든 검증/실행은 서버에서 수행
-- Timestamp 기반 Lazy Update: craftTime > 0이면 완료 시각 기록, 완료 시점에 결과물 생성

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)

local Data = ReplicatedStorage:WaitForChild("Data")
local MaterialAttributeData = require(Data.MaterialAttributeData)

local CraftingService = {}

--========================================
-- Dependencies (Init에서 주입)
--========================================
local NetController = nil
local DataService = nil
local InventoryService = nil
local BuildService = nil
local RecipeService = nil
local TechService = nil        -- Phase 6: 기술 해금 검증
local PlayerStatService = nil  -- Phase 6: XP 지급
local WorldDropService = nil   -- Phase 2-2: 인벤토리 풀 시 월드 드롭용
local TimeService = nil

--========================================
-- State
--========================================
-- craftQueues[userId] = { [craftId] = { recipeId, structureId, startedAt, completesAt, state } }
local craftQueues = {}
local initialized = false

-- Quest callback (Phase 8)
local questCallback = nil

-- Forward declarations (Init에서 사용)
local processTick
local onPlayerRemoving

--========================================
-- Internal: ID 생성
--========================================
local function generateCraftId(): string
	return "craft_" .. HttpService:GenerateGUID(false):sub(1, 8)
end

--========================================
-- Internal: 플레이어 큐 가져오기
--========================================
local function getQueue(userId: number): { [string]: any }
	if not craftQueues[userId] then
		craftQueues[userId] = {}
	end
	return craftQueues[userId]
end

--========================================
-- Internal: 큐 크기 카운트
--========================================
local function getQueueSize(userId: number): number
	local queue = craftQueues[userId]
	if not queue then return 0 end
	local count = 0
	for _ in pairs(queue) do
		count = count + 1
	end
	return count
end

--========================================
-- Internal: 플레이어 캐릭터 위치
--========================================
local function getPlayerPosition(player: Player): Vector3?
	local character = player.Character
	if not character then return nil end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	return hrp.Position
end

--========================================
-- Internal: 시설 거리 검증
--========================================
local function validateFacilityAccess(player: Player, structureId: string?, requiredFacility: string?): (boolean, string?)
	-- 맨손 제작 (requiredFacility == nil)
	if not requiredFacility then
		return true, nil
	end
	
	-- 시설 필요한데 structureId가 없으면 에러
	if not structureId then
		return false, Enums.ErrorCode.NO_FACILITY
	end
	
	-- BuildService에서 구조물 조회
	local structure = BuildService.get(structureId)
	if not structure then
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	-- 시설 타입 확인
	local facilityData = DataService.getFacility(structure.facilityId)
	if not facilityData then
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	if facilityData.functionType ~= requiredFacility then
		return false, Enums.ErrorCode.NO_FACILITY
	end
	
	-- 거리 검증
	local playerPos = getPlayerPosition(player)
	if not playerPos then
		return false, Enums.ErrorCode.BAD_REQUEST
	end
	
	local structurePos = structure.position
	local dist = (playerPos - structurePos).Magnitude
	if dist > Balance.CRAFT_RANGE then
		return false, Enums.ErrorCode.OUT_OF_RANGE
	end
	
	return true, nil
end

--========================================
-- Internal: 재료 보유 검증
--========================================
local function validateMaterials(player: Player, inputs: { any }): (boolean, string?)
	local userId = player.UserId
	for _, input in ipairs(inputs) do
		local has = InventoryService.hasItem(userId, input.itemId, input.count)
		if not has then
			return false, Enums.ErrorCode.MISSING_REQUIREMENTS
		end
	end
	return true, nil
end

--========================================
-- Internal: 재료 차감
--========================================
local function consumeMaterials(userId: number, inputs: { any }): boolean
	local consumedList = {} -- 롤백을 위한 임시 저장소
	
	for _, input in ipairs(inputs) do
		local removed = InventoryService.removeItem(userId, input.itemId, input.count)
		
		if removed > 0 then
			table.insert(consumedList, { itemId = input.itemId, count = removed })
		end
		
		if removed < input.count then
			warn(string.format("[CraftingService] Failed to consume %s x%d for userId %d (Rollback triggered)",
				input.itemId, input.count, userId))
			
			-- 롤백: 지금까지 차감한 재료들 다시 지급
			for _, item in ipairs(consumedList) do
				InventoryService.addItem(userId, item.itemId, item.count)
			end
			
			return false
		end
	end
	return true
end

local function scaleInputs(inputs: { any }, multiplier: number): { any }
	local out = {}
	for _, input in ipairs(inputs or {}) do
		table.insert(out, {
			itemId = input.itemId,
			count = (input.count or 0) * multiplier,
		})
	end
	return out
end

--========================================
-- Internal: 슬롯 지정 재료 차감 (재료 선택 UI용)
--========================================
local function consumeMaterialsBySlots(userId: number, materialSlots: { any }, recipe: any, craftCount: number): boolean
	-- 0. 중복 슬롯 검출 (클라이언트 조작 방지)
	local seenSlots = {}
	for _, entry in ipairs(materialSlots) do
		local slot = tonumber(entry.slot)
		if not slot then return false end
		if seenSlots[slot] then
			warn(string.format("[CraftingService] Duplicate slot %d in materialSlots", slot))
			return false
		end
		seenSlots[slot] = true
	end
	
	-- 1. 선택된 슬롯들이 올바른 itemId를 가지고 있는지 검증 + 속성 정보 기록
	local slotItemMap = {} -- [itemId] = { slot1, slot2, ... }
	for _, entry in ipairs(materialSlots) do
		local slot = tonumber(entry.slot)
		local itemId = entry.itemId
		if not slot or not itemId then
			warn("[CraftingService] Invalid materialSlot entry")
			return false
		end
		-- InventoryService를 통해 슬롯에 실제로 해당 아이템이 있는지 확인
		local slotData = InventoryService.getSlot(userId, slot)
		if not slotData or slotData.itemId ~= itemId then
			warn(string.format("[CraftingService] Slot %d does not contain %s", slot, itemId))
			return false
		end
		-- 속성 정보를 엔트리에 기록 (extractInheritedAttributes에서 사용)
		entry.attributes = slotData.attributes
		if not slotItemMap[itemId] then slotItemMap[itemId] = {} end
		table.insert(slotItemMap[itemId], slot)
	end
	
	-- 2. 레시피 요구량 대비 슬롯 수 검증
	local scaledInputs = scaleInputs(recipe.inputs, craftCount)
	for _, input in ipairs(scaledInputs) do
		local selected = slotItemMap[input.itemId]
		if not selected or #selected < input.count then
			warn(string.format("[CraftingService] Not enough selected slots for %s: need %d, got %d",
				input.itemId, input.count, selected and #selected or 0))
			return false
		end
	end
	
	-- 3. 슬롯별 소비 (롤백 지원)
	local consumedSlots = {} -- 롤백용
	for _, entry in ipairs(materialSlots) do
		local slot = tonumber(entry.slot)
		local removed = InventoryService.removeItemFromSlot(userId, slot, 1)
		if removed > 0 then
			table.insert(consumedSlots, { slot = slot, itemId = entry.itemId, count = removed })
		else
			warn(string.format("[CraftingService] Failed to remove from slot %d (Rollback triggered)", slot))
			-- 롤백
			for _, prev in ipairs(consumedSlots) do
				InventoryService.addItem(userId, prev.itemId, prev.count)
			end
			return false
		end
	end
	
	return true
end

--========================================
-- Internal: 속성 상속 — materialSlots에서 결과물에 전달할 속성 추출 (다중 속성)
-- 같은 속성 ID는 레벨 합산, 서로 다른 속성은 모두 보존
--========================================
local function extractInheritedAttributes(userId: number, materialSlots: {any}?, outputItemId: string): any?
	if not materialSlots or #materialSlots == 0 then return nil end
	
	local outputCategory = MaterialAttributeData.getCategory(outputItemId)
	
	-- 같은 속성 ID끼리 레벨을 합산 (중첩 시스템)
	-- 예: 가벼움 Lv1 + 가벼움 Lv1 → 가벼움 Lv2
	-- 예: 가벼움 Lv1 + 날카로운 Lv2 → { LIGHT=1, SHARP=2 }
	local attrSum = {} -- [attributeId] = 합산 레벨
	
	for _, entry in ipairs(materialSlots) do
		if entry.attributes then
			for attrId, level in pairs(entry.attributes) do
				local include = false
				if outputCategory then
					local entryCategory = MaterialAttributeData.getCategory(entry.itemId)
					if entryCategory == outputCategory then
						include = true
					end
				else
					-- 무기/도구는 모든 재료 속성 합산
					include = true
				end
				if include then
					attrSum[attrId] = (attrSum[attrId] or 0) + level
				end
			end
		end
	end
	
	if next(attrSum) then
		return attrSum
	end
	return nil
end

local function getBatchCount(entry: any): number
	return math.max(1, tonumber(entry and entry.batchCount) or 1)
end

local function getUnitDuration(entry: any): number
	local unit = tonumber(entry and entry.unitDuration)
	if unit and unit > 0 then
		return math.max(1, math.floor(unit))
	end
	local total = tonumber(entry and entry.totalDuration) or 0
	return math.max(1, math.floor(total / getBatchCount(entry)))
end

local function syncEntryProgress(entry: any, now: number?): number
	now = now or os.time()
	if not entry then return 0 end

	local batchCount = getBatchCount(entry)
	entry.completedCount = math.max(0, math.min(batchCount, tonumber(entry.completedCount) or 0))
	entry.collectedCount = math.max(0, math.min(batchCount, tonumber(entry.collectedCount) or 0))

	if entry.completedCount >= batchCount then
		entry.nextCompleteAt = nil
		entry.completesAt = entry.startedAt + (getUnitDuration(entry) * batchCount)
		if entry.collectedCount >= batchCount then
			entry.state = Enums.CraftState.COMPLETED
		else
			entry.state = Enums.CraftState.PENDING_COLLECT
		end
		return 0
	end

	local unitDuration = getUnitDuration(entry)
	entry.nextCompleteAt = tonumber(entry.nextCompleteAt) or (entry.startedAt + unitDuration)

	local produced = 0
	while entry.completedCount < batchCount and now >= entry.nextCompleteAt do
		entry.completedCount = entry.completedCount + 1
		produced = produced + 1
		entry.nextCompleteAt = entry.nextCompleteAt + unitDuration
	end

	entry.completesAt = entry.startedAt + (unitDuration * batchCount)
	if entry.completedCount >= batchCount then
		entry.nextCompleteAt = nil
		if entry.collectedCount >= batchCount then
			entry.state = Enums.CraftState.COMPLETED
		else
			entry.state = Enums.CraftState.PENDING_COLLECT
		end
	else
		entry.state = Enums.CraftState.CRAFTING
	end

	return produced
end

--========================================
-- Internal: 이벤트 발행
--========================================
local function emitCraftEvent(eventName: string, player: Player, data: any)
	if NetController then
		NetController.FireClient(player, eventName, data)
	end
end

--- SaveService에 현재 큐 상태 동기화
local function _syncToSave(userId: number)
	if not SaveService then return end
	local queue = craftQueues[userId] or {}
	SaveService.updatePlayerState(userId, function(state)
		state.craftingQueue = queue
		return state
	end)
end

local function emitCraftEventToAll(eventName: string, data: any)
	if NetController then
		NetController.FireAllClients(eventName, data)
	end
end

--========================================
-- Public API
--========================================

function CraftingService.Init(_NetController, _DataService, _InventoryService, _BuildService, _RecipeService, _TechService, _PlayerStatService, _WorldDropService, _TimeService)
	if initialized then
		warn("[CraftingService] Already initialized")
		return
	end
	
	NetController = _NetController
	DataService = _DataService
	InventoryService = _InventoryService
	BuildService = _BuildService
	RecipeService = _RecipeService
	TechService = _TechService
	PlayerStatService = _PlayerStatService
	WorldDropService = _WorldDropService
	TimeService = _TimeService
	
	-- Heartbeat 연결 (Lazy tick)
	RunService.Heartbeat:Connect(processTick)
	
	-- 플레이어 이벤트 연결
	Players.PlayerAdded:Connect(function(player)
		local userId = player.UserId
		-- SaveService에서 저장된 큐 로드
		if SaveService then
			local state = SaveService.getPlayerState(userId)
			if state and state.craftingQueue then
				-- 기존 큐가 있으면 병합 (이미 진행 중인 오프라인 작업 등)
				if not craftQueues[userId] then
					craftQueues[userId] = state.craftingQueue
				else
					for cid, entry in pairs(state.craftingQueue) do
						if not craftQueues[userId][cid] then
							craftQueues[userId][cid] = entry
						end
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
	initialized = true
	print("[CraftingService] Initialized with Tech & Stat injection")
end

--========================================
-- Public API: 제작 시작
--========================================
function CraftingService.start(player: Player, recipeId: string, structureId: string?, count: number?, materialSlots: {any}?)
	local userId = player.UserId
	local craftCount = math.max(1, math.floor(tonumber(count) or 1))
	
	-- 1. 레시피 존재 여부
	local recipe = DataService.getRecipe(recipeId)
	if not recipe then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end

	-- 1a. 기술 해금 검증 (장기적 리뉴얼을 위해 일시 제거)
	-- if TechService and not TechService.isRecipeUnlocked(userId, recipeId) then
	-- 	return false, Enums.ErrorCode.RECIPE_LOCKED, nil
	-- end
	
	-- 2. 큐 크기 검증
	if getQueueSize(userId) >= Balance.CRAFT_QUEUE_MAX then
		return false, Enums.ErrorCode.CRAFT_QUEUE_FULL, nil
	end
	
	-- 3. 시설 접근 검증
	local facilityOk, facilityErr = validateFacilityAccess(player, structureId, recipe.requiredFacility)
	if not facilityOk then
		return false, facilityErr, nil
	end
	
	-- 4. 재료 보유 검증
	local requiredInputs = scaleInputs(recipe.inputs, craftCount)
	local matOk, matErr = validateMaterials(player, requiredInputs)
	if not matOk then
		return false, matErr, nil
	end
	
	-- [NEW] 제작 시간 계산 (효율 적용)
	local context = {
		playerStatBonus = PlayerStatService and PlayerStatService.getStats(userId).craftSpeedBonus or 0
	}
	if structureId then
		local structure = BuildService.get(structureId)
		if structure then context.facilityId = structure.facilityId end
	end
	local perCraftTime = RecipeService.calculateCraftTime(recipeId, context)
	local perUnitDuration = perCraftTime

	-- 기초작업대 이상 제작물은 체감 제작 시간이 나도록 최소 시간 보장
	if recipe.requiredFacility and recipe.requiredFacility ~= "COOKING" then
		perUnitDuration = math.max(3, math.floor(perUnitDuration * 1.35 + 0.5))
	end
	perUnitDuration = math.max(0, math.floor(perUnitDuration))
	local realCraftTime = perUnitDuration * craftCount
	
	-- 5. 인벤토리 여유 검증 (즉시제작일 때만 사전 체크)
	if realCraftTime == 0 then
		for _, output in ipairs(recipe.outputs) do
			local canAdd = InventoryService.canAdd(userId, output.itemId, output.count * craftCount)
			if not canAdd then
				return false, Enums.ErrorCode.INV_FULL, nil
			end
		end
	end
	
	-- === 실행 단계 ===
	
	-- 6. 재료 차감 (슬롯 지정 vs 기존 방식)
	local consumed
	if materialSlots and type(materialSlots) == "table" and #materialSlots > 0 then
		consumed = consumeMaterialsBySlots(userId, materialSlots, recipe, craftCount)
	else
		consumed = consumeMaterials(userId, requiredInputs)
	end
	if not consumed then
		return false, Enums.ErrorCode.INTERNAL_ERROR, nil
	end
	
	-- 6a. 속성 상속 정보 추출 (소비 전에 materialSlots에 기록됨)
	local inheritedAttributes = {} -- [outputItemId] = attributes table { [attrId] = level }
	if materialSlots and type(materialSlots) == "table" and #materialSlots > 0 then
		for _, output in ipairs(recipe.outputs) do
			local attrs = extractInheritedAttributes(userId, materialSlots, output.itemId)
			if attrs then
				inheritedAttributes[output.itemId] = attrs
			end
		end
	end
	
	-- 7. 즉시 제작
	if realCraftTime <= 0 then -- Changed from == 0 to <= 0
		for _, output in ipairs(recipe.outputs) do
			local outAttrs = inheritedAttributes[output.itemId]
			-- 내구도 속성(durabilityMult) 적용: 모든 속성의 내구도 효과 합산
			local outDurability = nil
			if outAttrs then
				local totalDurMult = 0
				for attrId, level in pairs(outAttrs) do
					local fx = MaterialAttributeData.getEffectValues(attrId, level)
					if fx and fx.durabilityMult ~= 0 then
						totalDurMult = totalDurMult + fx.durabilityMult
					end
				end
				if totalDurMult ~= 0 then
					local baseItemData = DataService.getItem(output.itemId)
					if baseItemData and baseItemData.durability then
						outDurability = math.max(1, math.floor(baseItemData.durability * (1 + totalDurMult)))
					end
				end
			end
			for _ = 1, output.count * craftCount do
				InventoryService.addItem(userId, output.itemId, 1, outDurability, outAttrs)
			end
		end
		
		-- Phase 6: XP 보상
		if PlayerStatService then
			PlayerStatService.addXP(userId, (Balance.XP_CRAFT_ITEM or 5) * (recipe.xpMultiplier or 1), Enums.XPSource.CRAFT_ITEM)
		end
		
		-- Phase 8: 퀘스트 콜백
		if questCallback then
			questCallback(userId, recipeId)
		end

		local resultData = {
			recipeId = recipeId,
			outputs = recipe.outputs,
			batchCount = craftCount,
			instant = true,
		}
		
		emitCraftEvent("Craft.Completed", player, resultData)
		
		print(string.format("[CraftingService] Instant craft %s for player %d", recipeId, userId))
		return true, nil, resultData
	end
	
	-- 8. 대기 제작
	local now = os.time()
	local craftId = generateCraftId()
	
	local craftEntry = {
		craftId = craftId,
		recipeId = recipeId,
		structureId = structureId,
		userId = userId,
		startedAt = now,
		nextCompleteAt = now + math.max(1, perUnitDuration),
		completesAt = now + realCraftTime,
		batchCount = craftCount,
		completedCount = 0,
		collectedCount = 0,
		unitDuration = math.max(1, perUnitDuration),
		totalDuration = realCraftTime,
		state = Enums.CraftState.CRAFTING,
		inheritedAttributes = next(inheritedAttributes) and inheritedAttributes or nil,
	}
	
	local queue = getQueue(userId)
	queue[craftId] = craftEntry
	
	local startData = {
		craftId = craftId,
		recipeId = recipeId,
		batchCount = craftCount,
		perCraftTime = perCraftTime,
		craftTime = realCraftTime,
		completesAt = craftEntry.completesAt,
		totalDuration = realCraftTime,
		structureId = structureId,
	}
	
	_syncToSave(userId)
	
	emitCraftEvent("Craft.Started", player, startData)
	
	print(string.format("[CraftingService] Queued craft %s (%s x%d) for player %d, completes in %ds",
		craftId, recipeId, craftCount, player.UserId, realCraftTime))
	return true, nil, startData
end

--========================================
-- Public API: 제작 취소
--========================================
function CraftingService.cancel(player: Player, craftId: string)
	local userId = player.UserId
	local queue = craftQueues[userId]
	
	if not queue or not queue[craftId] then
		return false, Enums.ErrorCode.CRAFT_NOT_FOUND, nil
	end
	
	local entry = queue[craftId]
	local now = os.time()
	syncEntryProgress(entry, now)
	
	-- 이미 완료된 항목은 취소 불가
	if entry.state == Enums.CraftState.COMPLETED then
		return false, Enums.ErrorCode.INVALID_STATE, nil
	end
	
	-- 재료 환불
	local recipe = DataService.getRecipe(entry.recipeId)
	if recipe and Balance.CRAFT_CANCEL_REFUND > 0 then
		local pPos = getPlayerPosition(player)
		local batchCount = math.max(1, tonumber(entry.batchCount) or 1)
		local completedCount = math.max(0, math.min(batchCount, tonumber(entry.completedCount) or 0))
		local refundableUnits = math.max(0, batchCount - completedCount)
		for _, input in ipairs(recipe.inputs) do
			local refundCount = math.floor((input.count * refundableUnits) * Balance.CRAFT_CANCEL_REFUND)
			if refundCount > 0 then
				local added, remaining = InventoryService.addItem(userId, input.itemId, refundCount)
				
				-- 인벤토리가 가득 차서 남은 재료는 월드 드롭 처리 (데이터 유실 방지)
				if remaining > 0 and WorldDropService and pPos then
					WorldDropService.spawnDrop(pPos + Vector3.new(0, 2, 0), input.itemId, remaining)
					warn(string.format("[CraftingService] Refund overflow for %s: x%d dropped as WorldDrop for userId %d", 
						input.itemId, remaining, userId))
				end
			end
		end
	end
	
	-- 큐에서 제거
	queue[craftId] = nil
	_syncToSave(userId)
	
	local cancelData = {
		craftId = craftId,
		recipeId = entry.recipeId,
	}
	
	emitCraftEvent("Craft.Cancelled", player, cancelData)
	
	print(string.format("[CraftingService] Cancelled craft %s for player %d", craftId, userId))
	return true, nil, cancelData
end

--========================================
-- Public API: 완성품 수거
--========================================
function CraftingService.collect(player: Player, craftId: string, count: number?)
	local userId = player.UserId
	local queue = craftQueues[userId]
	
	if not queue or not queue[craftId] then
		return false, Enums.ErrorCode.CRAFT_NOT_FOUND, nil
	end
	
	local entry = queue[craftId]
	local now = os.time()
	syncEntryProgress(entry, now)
	
	-- 1. 아직 해금 상태인지 재검증 (장기적 리뉴얼을 위해 일시 제거)
	-- if TechService and not TechService.isRecipeUnlocked(userId, entry.recipeId) then
	-- 	return false, Enums.ErrorCode.RECIPE_LOCKED, nil
	-- end
	
	local batchCount = getBatchCount(entry)
	local completedCount = math.max(0, math.min(batchCount, tonumber(entry.completedCount) or 0))
	local collectedCount = math.max(0, math.min(batchCount, tonumber(entry.collectedCount) or 0))
	local readyCount = math.max(0, completedCount - collectedCount)
	if readyCount <= 0 then
		return false, Enums.ErrorCode.INVALID_STATE, nil
	end

	local collectCount = tonumber(count) and math.max(1, math.floor(tonumber(count))) or readyCount
	collectCount = math.min(collectCount, readyCount)
	
	-- 결과물 인벤토리 추가
	local recipe = DataService.getRecipe(entry.recipeId)
	if not recipe then
		return false, Enums.ErrorCode.INTERNAL_ERROR, nil
	end
	
	-- 인벤토리 여유 사전 체크
	for _, output in ipairs(recipe.outputs) do
		local totalOut = output.count * collectCount
		local canAdd = InventoryService.canAdd(userId, output.itemId, totalOut)
		if not canAdd then
			return false, Enums.ErrorCode.INV_FULL, nil
		end
	end
	
	-- 결과물 추가 (속성 상속 포함)
	for _, output in ipairs(recipe.outputs) do
		local totalOut = output.count * collectCount
		local outAttrs = entry.inheritedAttributes and entry.inheritedAttributes[output.itemId]
		-- 내구도 속성(durabilityMult) 적용: 모든 속성의 내구도 효과 합산
		local outDurability = nil
		if outAttrs then
			local totalDurMult = 0
			for attrId, level in pairs(outAttrs) do
				local fx = MaterialAttributeData.getEffectValues(attrId, level)
				if fx and fx.durabilityMult ~= 0 then
					totalDurMult = totalDurMult + fx.durabilityMult
				end
			end
			if totalDurMult ~= 0 then
				local baseItemData = DataService.getItem(output.itemId)
				if baseItemData and baseItemData.durability then
					outDurability = math.max(1, math.floor(baseItemData.durability * (1 + totalDurMult)))
				end
			end
		end
		if outAttrs then
			for _ = 1, totalOut do
				InventoryService.addItem(userId, output.itemId, 1, outDurability, outAttrs)
			end
		else
			InventoryService.addItem(userId, output.itemId, totalOut)
		end
	end
	
	-- 3a. 경험치 보상 (Phase 6)
	if PlayerStatService then
		PlayerStatService.addXP(userId, ((Balance.XP_CRAFT_ITEM or 5) * (recipe.xpMultiplier or 1)) * collectCount, Enums.XPSource.CRAFT_ITEM)
	end
	
	-- 3b. 퀘스트 콜백 (Phase 8)
	if questCallback then
		for _ = 1, collectCount do
			questCallback(userId, entry.recipeId)
		end
	end

	entry.collectedCount = math.min(batchCount, collectedCount + collectCount)
	syncEntryProgress(entry, now)

	local doneAll = entry.collectedCount >= batchCount and entry.completedCount >= batchCount
	if doneAll then
		queue[craftId] = nil
	end
	_syncToSave(userId)
	
	local collectData = {
		craftId = craftId,
		recipeId = entry.recipeId,
		batchCount = batchCount,
		collectedCount = collectCount,
		readyRemaining = math.max(0, (tonumber(entry.completedCount) or 0) - (tonumber(entry.collectedCount) or 0)),
		completedCount = tonumber(entry.completedCount) or 0,
		outputs = recipe.outputs,
	}
	
	emitCraftEvent("Craft.Completed", player, collectData)
	
	print(string.format("[CraftingService] Collected craft %s x%d for player %d", craftId, collectCount, userId))
	return true, nil, collectData
end

--========================================
-- Public API: 제작 큐 조회
--========================================
function CraftingService.getQueue(player: Player)
	local userId = player.UserId
	local queue = craftQueues[userId] or {}
	local now = os.time()
	
	-- Lazy Update: 배치 단위 진행 상태 갱신
	local result = {}
	for craftId, entry in pairs(queue) do
		syncEntryProgress(entry, now)
		local batchCount = getBatchCount(entry)
		local completedCount = math.max(0, math.min(batchCount, tonumber(entry.completedCount) or 0))
		local collectedCount = math.max(0, math.min(batchCount, tonumber(entry.collectedCount) or 0))
		local readyCount = math.max(0, completedCount - collectedCount)
		local inProgressCount = math.max(0, batchCount - completedCount)
		local unitDuration = getUnitDuration(entry)
		local totalDuration = tonumber(entry.totalDuration) or (unitDuration * batchCount)
		local remainingToNext = entry.nextCompleteAt and math.max(0, entry.nextCompleteAt - now) or 0
		local elapsedInCurrent = (inProgressCount > 0) and math.max(0, unitDuration - remainingToNext) or 0
		local elapsedTotal = math.max(0, math.min(totalDuration, (completedCount * unitDuration) + elapsedInCurrent))
		local remainingTotal = math.max(0, totalDuration - elapsedTotal)
		local progressRatio = (totalDuration > 0) and math.clamp(elapsedTotal / totalDuration, 0, 1) or 1

		table.insert(result, {
			craftId = craftId,
			recipeId = entry.recipeId,
			state = entry.state,
			startedAt = entry.startedAt,
			completesAt = entry.completesAt,
			remaining = remainingTotal,
			remainingToNext = remainingToNext,
			batchCount = batchCount,
			completedCount = completedCount,
			collectedCount = collectedCount,
			readyCount = readyCount,
			inProgressCount = inProgressCount,
			unitDuration = unitDuration,
			totalDuration = totalDuration,
			progressRatio = progressRatio,
			structureId = entry.structureId,
		})
	end
	
	return true, nil, { queue = result }
end

--========================================
-- Public API: 사용 가능 레시피 목록
--========================================
function CraftingService.getAvailableRecipes(player: Player, structureId: string?)
	local userId = player.UserId
	local available = {}
	
	local allRecipes = DataService.get("RecipeData")
	if not allRecipes then
		return true, nil, { recipes = {} }
	end
	
	-- 효율 Context 구성
	local context = {}
	if structureId then
		local structure = BuildService.get(structureId)
		if structure then
			context.facilityId = structure.facilityId
		end
	end
	
	for recipeId, recipe in pairs(allRecipes) do
		-- 시설 조건 확인
		local facilityOk = true
		if recipe.requiredFacility then
			if not structureId then
				facilityOk = false
			else
				local structure = BuildService.get(structureId)
				if structure then
					local facilityData = DataService.getFacility(structure.facilityId)
					if not facilityData or facilityData.functionType ~= recipe.requiredFacility then
						facilityOk = false
					end
				else
					facilityOk = false
				end
			end
		end
		
		-- 재료 보유 확인
		local hasAll = true
		for _, input in ipairs(recipe.inputs) do
			if not InventoryService.hasItem(userId, input.itemId, input.count) then
				hasAll = false
				break
			end
		end
		
		-- [NEW] 실수 계산
		local realCraftTime = RecipeService.calculateCraftTime(recipeId, context)
		
		table.insert(available, {
			recipeId = recipeId,
			name = recipe.name,
			category = recipe.category,
			craftTime = realCraftTime,
			baseCraftTime = recipe.craftTime,
			facilityOk = facilityOk,
			hasAllMaterials = hasAll,
			canCraft = facilityOk and hasAll,
		})
	end
	
	return true, nil, { recipes = available }
end

--========================================
-- Tick: 완료 알림 (Heartbeat - Lazy)
--========================================
local TICK_INTERVAL = 1.0  -- 1초마다 체크
local lastTickTime = 0

processTick = function()
	local now = os.time()
	if now - lastTickTime < TICK_INTERVAL then return end
	lastTickTime = now
	
	for userId, queue in pairs(craftQueues) do
		for craftId, entry in pairs(queue) do
			local producedNow = syncEntryProgress(entry, now)
			if producedNow > 0 then
				_syncToSave(userId)
				local player = Players:GetPlayerByUserId(userId)
				if player then
					if not entry.structureId then
						task.spawn(function()
							local success = CraftingService.collect(player, craftId, producedNow)
							if not success then
								local recipe = DataService.getRecipe(entry.recipeId)
								local pPos = getPlayerPosition(player)
								if recipe and pPos and WorldDropService then
									for _, output in ipairs(recipe.outputs) do
										WorldDropService.spawnDrop(pPos + Vector3.new(0, 2, 0), output.itemId, output.count * producedNow)
									end
									entry.collectedCount = math.min(getBatchCount(entry), (tonumber(entry.collectedCount) or 0) + producedNow)
									syncEntryProgress(entry, os.time())
									if entry.collectedCount >= getBatchCount(entry) and entry.completedCount >= getBatchCount(entry) then
										queue[craftId] = nil
									end
									_syncToSave(userId)
								end
							end
						end)
					else
						emitCraftEvent("Craft.Ready", player, {
							craftId = craftId,
							recipeId = entry.recipeId,
							producedCount = producedNow,
							readyCount = math.max(0, (tonumber(entry.completedCount) or 0) - (tonumber(entry.collectedCount) or 0)),
							batchCount = getBatchCount(entry),
							completedCount = tonumber(entry.completedCount) or 0,
						})
					end
				end
			end
		end
	end
end

--========================================
-- Player 퇴장 시 큐 정리
--========================================
onPlayerRemoving = function(player: Player)
	local userId = player.UserId
	local queue = craftQueues[userId]
	if not queue then return end
	
	-- 오프라인 정체 방지를 위해 완료되지 않은 '맨손 제작'만 취소 처리
	-- 시설 제작(structureId 있음)은 큐에 유지하여 오프라인 제작 지원
	for craftId, entry in pairs(queue) do
		if not entry.structureId and entry.state == Enums.CraftState.CRAFTING then
			queue[craftId] = nil
		end
	end
	
	-- 만약 큐가 완전히 비게 되었다면 메모리에서 해제, 아니면 오프라인 진행을 위해 유지
	local hasRemaining = false
	for _ in pairs(queue) do hasRemaining = true break end
	
	if not hasRemaining then
		craftQueues[userId] = nil
	end
	
	-- 최종 상태 저장
	_syncToSave(userId)
end

--========================================
-- Network Handlers
--========================================
function CraftingService.GetHandlers()
	return {
		["Craft.Start.Request"] = function(player, payload)
			local recipeId = payload.recipeId
			local structureId = payload.structureId  -- optional
			local count = payload.count
			local materialSlots = payload.materialSlots -- optional: [{slot, itemId}]
			
			if not recipeId or type(recipeId) ~= "string" then
				return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
			end
			
			-- materialSlots 데이터 검증
			if materialSlots ~= nil then
				if type(materialSlots) ~= "table" then
					return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
				end
				for _, entry in ipairs(materialSlots) do
					if type(entry) ~= "table" or not entry.slot or not entry.itemId then
						return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
					end
				end
			end
			
			local success, errorCode, data = CraftingService.start(player, recipeId, structureId, count, materialSlots)
			if not success then
				return { success = false, errorCode = errorCode }
			end
			return { success = true, data = data }
		end,
		
		["Craft.Cancel.Request"] = function(player, payload)
			local craftId = payload.craftId
			
			if not craftId or type(craftId) ~= "string" then
				return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
			end
			
			local success, errorCode, data = CraftingService.cancel(player, craftId)
			if not success then
				return { success = false, errorCode = errorCode }
			end
			return { success = true, data = data }
		end,
		
		["Craft.Collect.Request"] = function(player, payload)
			local craftId = payload.craftId
			local count = payload.count
			
			if not craftId or type(craftId) ~= "string" then
				return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
			end
			
			local success, errorCode, data = CraftingService.collect(player, craftId, count)
			if not success then
				return { success = false, errorCode = errorCode }
			end
			return { success = true, data = data }
		end,
		
		["Craft.GetQueue.Request"] = function(player, _payload)
			local success, errorCode, data = CraftingService.getQueue(player)
			return { success = true, data = data }
		end,
	}
end

--- 퀘스트 콜백 설정 (Phase 8)
function CraftingService.SetQuestCallback(callback)
	questCallback = callback
end

return CraftingService
