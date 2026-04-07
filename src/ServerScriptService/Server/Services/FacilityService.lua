-- FacilityService.lua
-- 시설 상태 관리 서비스 (Server-Authoritative)
-- 연료 기반 시설(화로 등)의 상태머신 + Lazy Update

local Players = game:GetService("Players")

local FacilityService = {}

--========================================
-- Dependencies (Init에서 주입)
--========================================
local NetController
local DataService
local InventoryService
local BuildService
local Balance
local RecipeService
local WorldDropService
local TechService    -- Phase 6: 기술 해금 검증 (Relinquish 어뷰징 방지)
local PalboxService  -- Phase 5-5: 팰 작업 배치
local PalAIService   -- Phase 7-5: 팰 AI 및 비주얼
local TotemService   -- Totem 유지비 만료 시 약탈 권한 판정

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)

--========================================
-- Private State
--========================================

-- [structureId] = FacilityRuntime
-- FacilityRuntime = {
--   structureId: string,
--   facilityId: string,     -- FacilityData 참조 ID
--   ownerId: number,
--   state: Enums.FacilityState,
--   inputSlot: { itemId: string, count: number }?,
--   fuelSlot: { itemId: string, count: number }?,
--   outputSlot: { [itemId: string]: number }?, -- 다중 결과물 지원을 위한 테이블 { itemId = count }
--   currentFuel: number,    -- 남은 가동 시간(초)
--   lastUpdateAt: number,   -- 마지막 Lazy Update 시각 (os.time())
--   processProgress: number, -- 현재 제작 진행률(초)
--   currentRecipeId: string?, -- 현재 처리 중인 레시피
-- }
local facilityStates = {}
local sleepCooldownByUser = {} -- [userId] = nextAllowedUnix

--========================================
-- Internal Helpers
--========================================

--- 플레이어 캐릭터 위치 (월드 드롭용)
local function getPlayerPosition(player: Player): Vector3?
	local character = player.Character
	if not character then return nil end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	return hrp.Position
end

--- 시설 런타임 초기화
local function createFacilityRuntime(structureId: string, facilityId: string, ownerId: number)
	return {
		structureId = structureId,
		facilityId = facilityId,
		ownerId = ownerId,
		state = Enums.FacilityState.IDLE,
		inputSlot = nil,
		fuelSlot = nil,
		outputSlot = {}, -- 다중 결과물 수용을 위한 빈 테이블 초기화
		currentFuel = 0,
		lastUpdateAt = os.time(),
		processProgress = 0,
		currentRecipeId = nil,
		-- Phase 5-5: 팰 작업 배치
		assignedPalUID = nil,     -- 배치된 팰 UID
		assignedPalOwnerId = nil, -- 팰 소유자 userId
	}
end

--- FacilityData에서 시설의 레시피 찾기 (Input ItemId → RecipeData)
local function findRecipeForInput(facilityId: string, inputItemId: string): any?
	local allRecipes = DataService.get("RecipeData")
	if not allRecipes then return nil end
	
	local facilityData = DataService.getFacility(facilityId)
	if not facilityData then return nil end
	
	for recipeId, recipe in pairs(allRecipes) do
		-- 레시피의 requiredFacility가 이 시설의 functionType과 일치하고
		-- inputs에 해당 아이템이 포함되어 있으면 매칭
		if recipe.requiredFacility == facilityData.functionType then
			for _, input in ipairs(recipe.inputs) do
				if input.itemId == inputItemId then
					return recipe, recipeId
				end
			end
		end
	end
	return nil, nil
end

--- 상태 전이 판정
local function determineState(runtime: any): string
	local facilityData = DataService.getFacility(runtime.facilityId)
	if not facilityData then return Enums.FacilityState.IDLE end
	local fuelConsumption = tonumber(facilityData.fuelConsumption) or 0

	-- Output 슬롯이 꽉 찼으면 → FULL (총 아이템 개수가 한도를 넘으면)
	if facilityData.hasOutputSlot and runtime.outputSlot then
		local totalOutput = 0
		for _, count in pairs(runtime.outputSlot) do
			totalOutput = totalOutput + count
		end
		if totalOutput >= (Balance.MAX_FACILITY_OUTPUT or 1000) then
			return Enums.FacilityState.FULL
		end
	end
	
	-- 작업 가능 조건: Input + Fuel
	local hasInput = (runtime.inputSlot ~= nil and runtime.inputSlot.count > 0)
	local hasFuel = (runtime.currentFuel > 0)
	
	-- 연료 필요한 시설
	if fuelConsumption > 0 then
		-- 연료 슬롯에 뭔가 있거나 현재 연소 중인 연료가 있거나
		local hasAnyFuel = (runtime.currentFuel > 0 or (runtime.fuelSlot ~= nil and runtime.fuelSlot.count > 0))
		
		if hasInput and hasAnyFuel then
			return Enums.FacilityState.ACTIVE
		elseif hasInput and not hasAnyFuel then
			return Enums.FacilityState.NO_POWER
		end
	else
		-- 연료 불필요 시설 (작업대 등)
		if hasInput then
			return Enums.FacilityState.ACTIVE
		end
	end
	
	return Enums.FacilityState.IDLE
end

--- 💡 핵심: Lazy Update
--- lastUpdateAt 이래로 경과한 시간만큼 연료 소모 + 제작 진행을 한번에 계산
local function lazyUpdate(runtime)
	local now = os.time()
	local deltaTime = now - runtime.lastUpdateAt
	if deltaTime <= 0 then
		runtime.lastUpdateAt = now
		return
	end
	
	-- [보안/기획] 기술 해금 검증 (장기적 리뉴얼을 위해 일체 제거)
	-- if TechService and not TechService.isFacilityUnlocked(runtime.ownerId, runtime.facilityId) then
	-- 	runtime.state = Enums.FacilityState.IDLE
	-- 	runtime.lastUpdateAt = now
	-- 	return
	-- end

	local facilityData = DataService.getFacility(runtime.facilityId)
	if not facilityData then
		runtime.lastUpdateAt = now
		return
	end
	local fuelConsumption = tonumber(facilityData.fuelConsumption) or 0
	
	-- 연료가 필요 없거나 Input이 없으면 skip
	local hasInput = (runtime.inputSlot ~= nil and runtime.inputSlot.count > 0)
	if not hasInput then
		runtime.lastUpdateAt = now
		runtime.state = determineState(runtime)
		return
	end
	
	-- [수정] 연료 차감 로직을 생산 로직과 통합 (아이템 생산 시간만큼만 연료 차감)
	local recipe = runtime.currentRecipeId and DataService.getRecipe(runtime.currentRecipeId)
	local effectiveCraftTime = 1
	if recipe then
		local creatureBonus = 0
		if runtime.assignedPalUID and runtime.assignedPalOwnerId and PalboxService then
			local pal = PalboxService.getPal(runtime.assignedPalOwnerId, runtime.assignedPalUID)
			if pal and pal.stats then
				local minHunger = Balance.PAL_MIN_WORK_HUNGER or 15
				local minSan = Balance.PAL_MIN_WORK_SAN or 20
				if (pal.stats.hunger or 0) >= minHunger and (pal.stats.san or 0) >= minSan then
					creatureBonus = ((pal.workPower or 1) - 1) * 0.5
				end
			elseif pal and pal.workPower then
				creatureBonus = (pal.workPower - 1) * 0.5
			end
		end
		local context = { facilityId = runtime.facilityId, creatureBonus = creatureBonus }
		effectiveCraftTime = math.max(0.1, RecipeService.calculateCraftTime(runtime.currentRecipeId, context))
	end

	-- 생산 가능한 최대 개수 (재료 및 슬롯 제한 기준)
	local maxCanProduceByInput = (runtime.inputSlot and runtime.inputSlot.count or 0)
	if maxCanProduceByInput > 0 and recipe and facilityData.hasOutputSlot then
		local totalOutput = 0
		for _, count in pairs(runtime.outputSlot) do totalOutput = totalOutput + count end
		local remainingOutputCap = (Balance.MAX_FACILITY_OUTPUT or 1000) - totalOutput
		
		local recipeOutputSum = 0
		for _, out in ipairs(recipe.outputs) do recipeOutputSum = recipeOutputSum + (out.count or 1) end
		
		if recipeOutputSum > 0 then
			local maxProduceByCap = math.floor(remainingOutputCap / recipeOutputSum)
			maxCanProduceByInput = math.min(maxCanProduceByInput, maxProduceByCap)
		end
	end

	-- 작업을 지속할 수 있는 최대 시간 (초)
	local timeNeededForFullWork = (maxCanProduceByInput * effectiveCraftTime) - runtime.processProgress
	if maxCanProduceByInput <= 0 then timeNeededForFullWork = 0 end
	
	-- 연료 보충 (연료가 필요한데 부족한 경우)
	if fuelConsumption > 0 and runtime.currentFuel < math.min(deltaTime, timeNeededForFullWork) * fuelConsumption then
		while runtime.fuelSlot and runtime.fuelSlot.count > 0 and runtime.currentFuel < deltaTime * fuelConsumption do
			local itemData = DataService.getItem(runtime.fuelSlot.itemId)
			if itemData and itemData.fuelValue then
				runtime.currentFuel = runtime.currentFuel + itemData.fuelValue
				runtime.fuelSlot.count = runtime.fuelSlot.count - 1
				if runtime.fuelSlot.count <= 0 then runtime.fuelSlot = nil end
			else break end
		end
	end

	-- 실제 가동 시간 (델타타임, 연료 한트, 작업 가능 시간 중 최소값)
	local fuelCapTime = (fuelConsumption > 0) and (runtime.currentFuel / fuelConsumption) or deltaTime
	local workTime = math.max(0, math.min(deltaTime, fuelCapTime, timeNeededForFullWork))
	
	-- 연료 차감 (실제 한 일만큼만)
	if fuelConsumption > 0 then
		runtime.currentFuel = math.max(0, runtime.currentFuel - workTime * fuelConsumption)
	end
	
	-- 생산 결과 적용
	if recipe and workTime >= 0 then
		local totalTime = workTime + runtime.processProgress
		local producedCount = math.floor(totalTime / effectiveCraftTime)
		
		if producedCount > 0 then
			-- 재료 차감
			runtime.inputSlot.count = runtime.inputSlot.count - producedCount
			if runtime.inputSlot.count <= 0 then runtime.inputSlot = nil end
			
			-- 산출물 추가
			if facilityData.hasOutputSlot then
				runtime.outputSlot = runtime.outputSlot or {}
				for _, out in ipairs(recipe.outputs) do
					runtime.outputSlot[out.itemId] = (runtime.outputSlot[out.itemId] or 0) + (out.count or 1) * producedCount
				end
			end
			
			runtime.processProgress = totalTime - (producedCount * effectiveCraftTime)
			
			-- [추가] 시설 내구도 소모
			if BuildService and BuildService.takeDamage then
				BuildService.takeDamage(structureId, (Balance.FACILITY_WORK_HP_LOSS or 0.1) * producedCount)
			end
		else
			runtime.processProgress = totalTime
		end
		
		-- [추가] 배정된 팰 유지비 소모 (일한 시간만큼)
		if runtime.assignedPalUID and runtime.assignedPalOwnerId and PalboxService and workTime > 0 then
			PalboxService.modifyPalStats(runtime.assignedPalOwnerId, runtime.assignedPalUID, {
				hunger = -(workTime * (Balance.PAL_WORK_HUNGER_COST or 2) / 10), -- 초당 소모량 평준화 (10초 작업 기준)
				san = -(workTime * (Balance.PAL_WORK_SAN_COST or 1) / 10)
			})
		end
	end
	
	-- 상태 재판정
	runtime.state = determineState(runtime)
	runtime.lastUpdateAt = now
end

--- 이벤트 발행
local function emitFacilityEvent(eventName: string, player: Player, data: any)
	if NetController then
		NetController.FireClient(player, eventName, data)
	end
end

local function canAccessFacility(userId: number, runtime: any, structure: any): boolean
	if runtime and runtime.ownerId == userId then
		return true
	end

	if TotemService and TotemService.canRaidStructure then
		return TotemService.canRaidStructure(userId, structure)
	end

	return false
end

--========================================
-- Public API
--========================================

--- 시설 등록 (BuildService에서 배치 시 호출)
function FacilityService.register(structureId: string, facilityId: string, ownerId: number)
	local facilityData = DataService.getFacility(facilityId)
	if not facilityData then return end
	
	-- Input/Fuel/Output 슬롯이 있는 시설만 등록
	if facilityData.hasInputSlot or facilityData.hasFuelSlot or facilityData.hasOutputSlot or facilityData.functionType == "CRAFTING_T1" then
		facilityStates[structureId] = createFacilityRuntime(structureId, facilityId, ownerId)
		print(string.format("[FacilityService] Registered facility: %s (%s)", structureId, facilityId))
	end
end

--- 시설 제거 (BuildService에서 해체 시 호출)
function FacilityService.unregister(structureId: string)
	facilityStates[structureId] = nil
	print(string.format("[FacilityService] Unregistered facility: %s", structureId))
end

--- 시설 런타임 정보 조회 (내부 상태 확인용)
function FacilityService.getRuntime(structureId: string)
	return facilityStates[structureId]
end

--- 시설 정보 조회 (Lazy Update 트리거)
function FacilityService.getInfo(player: Player, structureId: string)
	local runtime = facilityStates[structureId]
	if not runtime then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- 거리 검증
	local structure = BuildService.get(structureId)
	if not structure then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	local facilityData = DataService.getFacility(runtime.facilityId)
	if not facilityData then
		return false, Enums.ErrorCode.INTERNAL_ERROR, nil
	end

	if not canAccessFacility(player.UserId, runtime, structure) then
		return false, Enums.ErrorCode.NO_PERMISSION, nil
	end
	
	local character = player.Character
	if character then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp and structure.position then
			local dist = (hrp.Position - structure.position).Magnitude
			if dist > (facilityData.interactRange or 10) then
				return false, Enums.ErrorCode.OUT_OF_RANGE, nil
			end
		end
	end
	
	-- [보안/기획] 기술 해금 검증 (장기적 리뉴얼을 위해 일체 제거)
	-- if TechService and not TechService.isFacilityUnlocked(player.UserId, runtime.facilityId) then
	-- 	return false, Enums.ErrorCode.RECIPE_LOCKED, nil
	-- end

	-- 🔥 Lazy Update 실행
	lazyUpdate(runtime)
	
	-- 레시피 정보 (팰 workPower 보너스 포함)
	local effectiveCraftTime = 0
	if runtime.currentRecipeId then
		-- [Phase 5-5] 팰 workPower 보너스 계산
		local creatureBonus = 0
		if runtime.assignedPalUID and runtime.assignedPalOwnerId and PalboxService then
			local pal = PalboxService.getPal(runtime.assignedPalOwnerId, runtime.assignedPalUID)
			if pal and pal.stats then
				local minHunger = Balance.PAL_MIN_WORK_HUNGER or 15
				local minSan = Balance.PAL_MIN_WORK_SAN or 20
				if (pal.stats.hunger or 0) >= minHunger and (pal.stats.san or 0) >= minSan then
					creatureBonus = ((pal.workPower or 1) - 1) * 0.5
				end
			elseif pal and pal.workPower then
				creatureBonus = (pal.workPower - 1) * 0.5
			end
		end
		local context = { facilityId = runtime.facilityId, creatureBonus = creatureBonus }
		effectiveCraftTime = RecipeService.calculateCraftTime(runtime.currentRecipeId, context)
	end
	
	return true, nil, {
		structureId = structureId,
		facilityId = runtime.facilityId,
		state = runtime.state,
		inputSlot = runtime.inputSlot,
		fuelSlot = runtime.fuelSlot,
		outputSlot = runtime.outputSlot,
		currentFuel = runtime.currentFuel,
		processProgress = runtime.processProgress,
		currentRecipeId = runtime.currentRecipeId,
		effectiveCraftTime = effectiveCraftTime,
		lastUpdateAt = runtime.lastUpdateAt,
		-- Phase 5-5: 팰 배치 정보
		assignedPalUID = runtime.assignedPalUID,
		assignedPalOwnerId = runtime.assignedPalOwnerId,
		-- [추가] 내구도 정보
		health = structure.health,
		maxHealth = facilityData.maxHealth,
	}
end

--- 연료 투입
function FacilityService.addFuel(player: Player, structureId: string, invSlot: number)
	local runtime = facilityStates[structureId]
	if not runtime then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end

	local structure = BuildService.get and BuildService.get(structureId)
	if not structure then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	if not canAccessFacility(player.UserId, runtime, structure) then
		return false, Enums.ErrorCode.NO_PERMISSION, nil
	end
	
	local facilityData = DataService.getFacility(runtime.facilityId)
	-- [보안/기획] 기술 해금 검증 (일체 제거)
	-- if TechService and not TechService.isFacilityUnlocked(player.UserId, runtime.facilityId) then
	-- 	return false, Enums.ErrorCode.RECIPE_LOCKED, nil
	-- end

	-- Lazy Update 선행
	lazyUpdate(runtime)
	
	local userId = player.UserId
	
	-- 인벤토리 슬롯 검증
	local inv = InventoryService.getOrCreateInventory(userId)
	if not inv then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	local slotData = inv.slots[invSlot]
	if not slotData then
		return false, Enums.ErrorCode.SLOT_EMPTY, nil
	end
	
	-- 아이템이 연료인지 (fuelValue 확인)
	local itemData = DataService.getItem(slotData.itemId)
	if not itemData or not itemData.fuelValue or itemData.fuelValue <= 0 then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end
	
	--燃料 슬롯에 같은 아이템이면 추가, 다르면 교체(기존 제거)
	if runtime.fuelSlot and runtime.fuelSlot.itemId ~= slotData.itemId then
		-- 기존 연료를 인벤으로 반환
		local added, remaining = InventoryService.addItem(userId, runtime.fuelSlot.itemId, runtime.fuelSlot.count)
		
		-- 인벤토리 가득 참 시 월드 드롭 (아이템 증발 방지)
		if remaining > 0 and WorldDropService then
			local pPos = getPlayerPosition(player)
			if pPos then
				WorldDropService.spawnDrop(pPos + Vector3.new(0, 2, 0), runtime.fuelSlot.itemId, remaining)
			end
		end
		
		runtime.fuelSlot = nil
	end
	
	-- 인벤에서 1개 제거 -> 연료 슬롯에 추가
	InventoryService.removeItem(userId, slotData.itemId, 1)
	
	-- 연료 슬롯 기록 (충전은 연소 시점에 lazyUpdate에서 수행됨)
	if runtime.fuelSlot then
		runtime.fuelSlot.count = runtime.fuelSlot.count + 1
	else
		runtime.fuelSlot = { itemId = slotData.itemId, count = 1 }
	end
	
	-- 상태 재판정
	runtime.state = determineState(runtime)
	
	emitFacilityEvent("Facility.StateChanged", player, {
		structureId = structureId,
		state = runtime.state,
		currentFuel = runtime.currentFuel,
		fuelSlot = runtime.fuelSlot,
		lastUpdateAt = runtime.lastUpdateAt,
	})
	
	print(string.format("[FacilityService] Added fuel to %s: %s (Queued)",
		structureId, slotData.itemId))
	return true, nil, { currentFuel = runtime.currentFuel, state = runtime.state, fuelSlot = runtime.fuelSlot }
end

--- 재료 투입 (Input 슬롯)
function FacilityService.addInput(player: Player, structureId: string, invSlot: number, count: number?)
	local runtime = facilityStates[structureId]
	if not runtime then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end

	local structure = BuildService.get and BuildService.get(structureId)
	if not structure then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	if not canAccessFacility(player.UserId, runtime, structure) then
		return false, Enums.ErrorCode.NO_PERMISSION, nil
	end
	
	local facilityData = DataService.getFacility(runtime.facilityId)
	if not facilityData or not facilityData.hasInputSlot then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end
	
	-- [보안/기획] 기술 해금 검증 (일체 제거)
	-- if TechService and not TechService.isFacilityUnlocked(player.UserId, runtime.facilityId) then
	-- 	return false, Enums.ErrorCode.RECIPE_LOCKED, nil
	-- end

	-- Lazy Update 선행
	lazyUpdate(runtime)
	
	local userId = player.UserId
	
	-- 인벤 슬롯 확인
	local inv = InventoryService.getOrCreateInventory(userId)
	if not inv then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	local slotData = inv.slots[invSlot]
	if not slotData then
		return false, Enums.ErrorCode.SLOT_EMPTY, nil
	end
	
	local addCount = count or slotData.count
	addCount = math.min(addCount, slotData.count)
	
	-- Input 슬롯에 같은 아이템인지 확인
	if runtime.inputSlot and runtime.inputSlot.itemId ~= slotData.itemId then
		-- 기존 Input을 인벤으로 반환
		local added, remaining = InventoryService.addItem(userId, runtime.inputSlot.itemId, runtime.inputSlot.count)
		
		-- 인벤토리 가득 참 시 월드 드롭 (아이템 증발 방지)
		if remaining > 0 and WorldDropService then
			local pPos = getPlayerPosition(player)
			if pPos then
				WorldDropService.spawnDrop(pPos + Vector3.new(0, 2, 0), runtime.inputSlot.itemId, remaining)
			end
		end
		
		runtime.inputSlot = nil
		runtime.currentRecipeId = nil
		runtime.processProgress = 0
	end
	
	-- 레시피 매칭 확인
	local recipe, recipeId = findRecipeForInput(runtime.facilityId, slotData.itemId)
	if not recipe then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- 인벤에서 제거 → Input 슬롯에 추가
	local removed = InventoryService.removeItem(userId, slotData.itemId, addCount)
	if removed < addCount then
		warn("[FacilityService] Failed to remove input items from inventory")
		return false, Enums.ErrorCode.INTERNAL_ERROR, nil
	end
	
	if runtime.inputSlot then
		runtime.inputSlot.count = runtime.inputSlot.count + addCount
	else
		runtime.inputSlot = { itemId = slotData.itemId, count = addCount }
	end
	
	-- 레시피 설정
	runtime.currentRecipeId = recipeId
	
	-- 상태 재판정
	runtime.state = determineState(runtime)
	
	emitFacilityEvent("Facility.StateChanged", player, {
		structureId = structureId,
		state = runtime.state,
		inputSlot = runtime.inputSlot,
		currentRecipeId = runtime.currentRecipeId,
		lastUpdateAt = runtime.lastUpdateAt,
	})
	
	print(string.format("[FacilityService] Added input to %s: %s x%d",
		structureId, slotData.itemId, addCount))
	return true, nil, { inputSlot = runtime.inputSlot, state = runtime.state }
end

--- 산출물 수거 (Output 슬롯)
function FacilityService.collectOutput(player: Player, structureId: string)
	local runtime = facilityStates[structureId]
	if not runtime then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end

	local structure = BuildService.get and BuildService.get(structureId)
	if not structure then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	if not canAccessFacility(player.UserId, runtime, structure) then
		return false, Enums.ErrorCode.NO_PERMISSION, nil
	end
	
	-- [보안/기획] 기술 해금 검증 (일체 제거)
	-- if TechService and not TechService.isFacilityUnlocked(player.UserId, runtime.facilityId) then
	-- 	return false, Enums.ErrorCode.RECIPE_LOCKED, nil
	-- end

	-- Lazy Update 선행
	lazyUpdate(runtime)
	
	-- 다중 아이템 수거 처리
	local anyCollected = false
	local firstError = nil
	local totalAdded = 0
	local userId = player.UserId
	
	-- 복사본을 만들어 순회 (수집 중 테이블 변경 방지)
	local currentOutputs = {}
	for id, count in pairs(runtime.outputSlot) do currentOutputs[id] = count end
	
	for itemId, totalToCollect in pairs(currentOutputs) do
		if totalToCollect > 0 then
			local added, remaining = InventoryService.addItem(userId, itemId, totalToCollect)
			
			if added > 0 then
				anyCollected = true
				totalAdded = totalAdded + added
				if remaining <= 0 then
					runtime.outputSlot[itemId] = nil
				else
					runtime.outputSlot[itemId] = remaining
				end
			else
				firstError = Enums.ErrorCode.INV_FULL
			end
		end
	end
	
	if anyCollected then
		-- 상태 재판정
		runtime.state = determineState(runtime)
		
		emitFacilityEvent("Facility.StateChanged", player, {
			structureId = structureId,
			state = runtime.state,
			outputSlot = runtime.outputSlot,
			lastUpdateAt = runtime.lastUpdateAt,
		})
		
		return true, nil, { added = totalAdded }
	else
		return false, firstError or Enums.ErrorCode.SLOT_EMPTY, nil
	end
end

--- 재료 회수 (Input 슬롯)
function FacilityService.removeInput(player: Player, structureId: string)
	local runtime = facilityStates[structureId]
	if not runtime or not runtime.inputSlot then
		return false, Enums.ErrorCode.SLOT_EMPTY, nil
	end

	local structure = BuildService.get and BuildService.get(structureId)
	if not structure then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	if not canAccessFacility(player.UserId, runtime, structure) then
		return false, Enums.ErrorCode.NO_PERMISSION, nil
	end
	
	-- [보안/기획] 기술 해금 검증 (일체 제거)
	-- if TechService and not TechService.isFacilityUnlocked(player.UserId, runtime.facilityId) then
	-- 	return false, Enums.ErrorCode.RECIPE_LOCKED, nil
	-- end

	-- Lazy Update 선행 (중도 포기 시 진행률 초기화)
	lazyUpdate(runtime)
	
	local itemId = runtime.inputSlot.itemId
	local count = runtime.inputSlot.count
	
	local added, remaining = InventoryService.addItem(player.UserId, itemId, count)
	
	if added > 0 then
		if remaining <= 0 then
			runtime.inputSlot = nil
			runtime.currentRecipeId = nil
			runtime.processProgress = 0
		else
			runtime.inputSlot.count = remaining
		end
		
		runtime.state = determineState(runtime)
		emitFacilityEvent("Facility.StateChanged", player, {
			structureId = structureId,
			state = runtime.state,
			inputSlot = runtime.inputSlot,
			lastUpdateAt = runtime.lastUpdateAt,
		})
		
		return true, nil, { added = added }
	else
		return false, Enums.ErrorCode.INV_FULL, nil
	end
end

--- 연료 회수 (Fuel 슬롯)
--- 주의: currentFuel은 남겨두고 fuelSlot에 기록된 아이템만 회수 (이미 연소 중인 것은 회수 불가)
function FacilityService.removeFuel(player: Player, structureId: string)
	local runtime = facilityStates[structureId]
	if not runtime or not runtime.fuelSlot then
		return false, Enums.ErrorCode.SLOT_EMPTY, nil
	end

	local structure = BuildService.get and BuildService.get(structureId)
	if not structure then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	if not canAccessFacility(player.UserId, runtime, structure) then
		return false, Enums.ErrorCode.NO_PERMISSION, nil
	end
	
	-- [보안/기획] 기술 해금 검증 (일체 제거)
	-- if TechService and not TechService.isFacilityUnlocked(player.UserId, runtime.facilityId) then
	-- 	return false, Enums.ErrorCode.RECIPE_LOCKED, nil
	-- end

	lazyUpdate(runtime)
	
	local itemId = runtime.fuelSlot.itemId
	local count = runtime.fuelSlot.count
	
	local added, remaining = InventoryService.addItem(player.UserId, itemId, count)
	
	if added > 0 then
		if remaining <= 0 then
			runtime.fuelSlot = nil
		else
			runtime.fuelSlot.count = remaining
		end
		
		-- currentFuel은 그대로 둠 (이미 충전된 시간은 취소 불가)
		
		runtime.state = determineState(runtime)
		emitFacilityEvent("Facility.StateChanged", player, {
			structureId = structureId,
			state = runtime.state,
			fuelSlot = runtime.fuelSlot,
			lastUpdateAt = runtime.lastUpdateAt,
		})
		
		return true, nil, { added = added }
	else
		return false, Enums.ErrorCode.INV_FULL, nil
	end
end

--- 시설 런타임 존재 여부
function FacilityService.has(structureId: string): boolean
	return facilityStates[structureId] ~= nil
end

--- 시설 런타임 직접 접근 (내부용)
function FacilityService.getRuntime(structureId: string)
	return facilityStates[structureId]
end

--- 모든 시설 런타임 반환 (자동화 서비스용)
function FacilityService.getAllRuntimes(): {[string]: any}
	return facilityStates
end

--========================================
-- Phase 5-5: 팰 작업 배치 API
--========================================

--- 팰을 시설에 배치
function FacilityService.assignPal(userId: number, structureId: string, palUID: string): (boolean, string?)
	local runtime = facilityStates[structureId]
	if not runtime then
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	-- 권한 확인: 시설 소유자만 팰 배치 가능
	if runtime.ownerId ~= userId then
		return false, Enums.ErrorCode.NO_PERMISSION
	end
	
	-- 이미 다른 팰이 배치되어 있으면 실패
	if runtime.assignedPalUID then
		return false, Enums.ErrorCode.PAL_ALREADY_ASSIGNED
	end
	
	-- PalboxService 없으면 실패
	if not PalboxService then
		return false, Enums.ErrorCode.INTERNAL_ERROR
	end
	
	-- 팰 존재 확인
	local pal = PalboxService.getPal(userId, palUID)
	if not pal then
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	-- 팰 상태 확인: STORED 또는 IN_PARTY만 배치 가능
	if pal.state == Enums.PalState.SUMMONED then
		return false, Enums.ErrorCode.PAL_IN_PARTY -- 소환 중 배치 불가
	end
	if pal.state == Enums.PalState.WORKING then
		return false, Enums.ErrorCode.PAL_ALREADY_ASSIGNED -- 이미 다른 시설에 배치됨
	end
	
	-- 시설 functionType과 팰 workTypes 매칭 확인
	local facilityData = DataService.getFacility(runtime.facilityId)
	if facilityData and pal.workTypes then
		local matchFound = false
		for _, workType in ipairs(pal.workTypes) do
			-- workType과 facilityData.functionType 매칭
			-- 예: workType="COOKING", functionType="COOKING"
			if workType == facilityData.functionType then
				matchFound = true
				break
			end
		end
		if not matchFound then
			return false, Enums.ErrorCode.BAD_REQUEST -- workType 불일치
		end
	end
	
	-- 배치 실행
	runtime.assignedPalUID = palUID
	runtime.assignedPalOwnerId = userId
	
	-- PalboxService에 상태 업데이트
	PalboxService.setAssignedFacility(userId, palUID, structureId)
	
	-- [추가] 팰 모델 스폰 (시각화)
	if PalAIService then
		PalAIService.onPalAssigned(userId, palUID, structureId)
	end
	
	print(string.format("[FacilityService] Pal %s assigned to facility %s by user %d", palUID, structureId, userId))
	return true, nil
end

--- 팰을 시설에서 해제
function FacilityService.unassignPal(userId: number, structureId: string): (boolean, string?)
	local runtime = facilityStates[structureId]
	if not runtime then
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	-- 배치된 팰이 없으면 실패
	if not runtime.assignedPalUID then
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	-- 권한 확인: 팰 소유자만 해제 가능
	if runtime.assignedPalOwnerId ~= userId then
		return false, Enums.ErrorCode.NO_PERMISSION
	end
	
	local palUID = runtime.assignedPalUID
	
	-- 해제 실행
	runtime.assignedPalUID = nil
	runtime.assignedPalOwnerId = nil
	
	-- PalboxService에 상태 업데이트
	if PalboxService then
		PalboxService.setAssignedFacility(userId, palUID, nil)
	end
	
	-- [추가] 팰 모델 제거
	if PalAIService then
		PalAIService.onPalUnassigned(palUID)
	end
	
	print(string.format("[FacilityService] Pal %s unassigned from facility %s by user %d", palUID, structureId, userId))
	return true, nil
end

--- 시설에 배치된 팰 정보 조회
function FacilityService.getAssignedPal(structureId: string): (string?, number?)
	local runtime = facilityStates[structureId]
	if runtime then
		return runtime.assignedPalUID, runtime.assignedPalOwnerId
	end
	return nil, nil
end

function FacilityService.sleep(player: Player, structureId: string): (boolean, string?, any?)
	if not player or not structureId or structureId == "" then
		return false, Enums.ErrorCode.BAD_REQUEST
	end

	if not BuildService or not DataService then
		return false, Enums.ErrorCode.INTERNAL_ERROR
	end

	local struct = BuildService.get and BuildService.get(structureId)
	if not struct then
		return false, Enums.ErrorCode.NOT_FOUND
	end

	local nowUnix = os.time()
	local nextAllowed = sleepCooldownByUser[player.UserId] or 0
	if nowUnix < nextAllowed then
		return false, "SLEEP_COOLDOWN"
	end

	if struct.ownerId ~= player.UserId then
		return false, Enums.ErrorCode.NO_PERMISSION
	end

	local facilityData = DataService.getFacility(struct.facilityId)
	if not facilityData or facilityData.functionType ~= "RESPAWN" then
		return false, Enums.ErrorCode.BAD_REQUEST
	end

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = humanoid.MaxHealth
		end
	end

	local okStamina, StaminaService = pcall(function()
		return require(game:GetService("ServerScriptService").Server.Services.StaminaService)
	end)
	if okStamina and StaminaService and StaminaService.restoreFull then
		StaminaService.restoreFull(player.UserId)
	end

	local okHunger, HungerService = pcall(function()
		return require(game:GetService("ServerScriptService").Server.Services.HungerService)
	end)
	if okHunger and HungerService and HungerService.restoreFull then
		HungerService.restoreFull(player.UserId)
	end

	local okDebuff, DebuffService = pcall(function()
		return require(game:GetService("ServerScriptService").Server.Services.DebuffService)
	end)
	if okDebuff and DebuffService and DebuffService.removeDebuff then
		DebuffService.removeDebuff(player.UserId, "CHILLY")
		DebuffService.removeDebuff(player.UserId, "FREEZING")
	end

	local okLife, PlayerLifeService = pcall(function()
		return require(game:GetService("ServerScriptService").Server.Services.PlayerLifeService)
	end)
	if okLife and PlayerLifeService and PlayerLifeService.setPreferredRespawn then
		PlayerLifeService.setPreferredRespawn(player.UserId, structureId)
		print(string.format("[FacilityService.sleep] setPreferredRespawn OK (userId=%d, structId=%s)", player.UserId, structureId))
	end

	local okSave, SaveService = pcall(function()
		return require(game:GetService("ServerScriptService").Server.Services.SaveService)
	end)
	if okSave and SaveService and SaveService.updatePlayerState then
		local pos = struct.position
		if type(pos) == "table" then
			pos = Vector3.new(pos.X or pos.x or 0, pos.Y or pos.y or 0, pos.Z or pos.z or 0)
		end
		SaveService.updatePlayerState(player.UserId, function(state)
			state.lastPosition = {
				x = pos.X,
				y = pos.Y,
				z = pos.Z,
			}
			return state
		end)
		print(string.format("[FacilityService.sleep] lastPosition saved (%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z))
	end

	local okTime, TimeService = pcall(function()
		return require(game:GetService("ServerScriptService").Server.Services.TimeService)
	end)
	if okTime and TimeService and TimeService.getTime and TimeService.warp then
		-- 기상 직후는 완전히 밝은 상태가 되도록 "정오" 시점으로 이동.
		local dayLength = math.max(1, Balance.DAY_LENGTH or 2400)
		local target = math.floor((Balance.DAY_DURATION or 1800) * 0.5)
		local cur = TimeService.getTime()
		local dayTime = (cur and cur.dayTime) or 0
		local delta = target - dayTime
		if delta < 0 then
			delta += dayLength
		end
		TimeService.warp(delta)
		if TimeService.sync then
			TimeService.sync()
		end
	end

	sleepCooldownByUser[player.UserId] = nowUnix + math.max(1, Balance.SLEEP_COOLDOWN or 20)

	return true, nil, {
		respawnSet = true,
		restored = true,
		phase = "DAY",
		nextSleepAt = sleepCooldownByUser[player.UserId],
	}
end

--========================================
-- Network Handlers
--========================================

local function handleGetInfo(player: Player, payload: any)
	local structureId = payload.structureId
	if not structureId then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local success, errorCode, data = FacilityService.getInfo(player, structureId)
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = data }
end

local function handleAddFuel(player: Player, payload: any)
	local structureId = payload.structureId
	local invSlot = payload.invSlot
	if not structureId or not invSlot then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local success, errorCode, data = FacilityService.addFuel(player, structureId, invSlot)
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = data }
end

local function handleAddInput(player: Player, payload: any)
	local structureId = payload.structureId
	local invSlot = payload.invSlot
	local count = payload.count
	if not structureId or not invSlot then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local success, errorCode, data = FacilityService.addInput(player, structureId, invSlot, count)
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = data }
end

local function handleCollectOutput(player: Player, payload: any)
	local structureId = payload.structureId
	if not structureId then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local success, errorCode, data = FacilityService.collectOutput(player, structureId)
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = data }
end

local function handleRemoveInput(player: Player, payload: any)
	local structureId = payload.structureId
	if not structureId then return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST } end
	local success, errorCode, data = FacilityService.removeInput(player, structureId)
	if not success then return { success = false, errorCode = errorCode } end
	return { success = true, data = data }
end

local function handleRemoveFuel(player: Player, payload: any)
	local structureId = payload.structureId
	if not structureId then return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST } end
	local success, errorCode, data = FacilityService.removeFuel(player, structureId)
	if not success then return { success = false, errorCode = errorCode } end
	return { success = true, data = data }
end

local function handleAssignPal(player: Player, payload: any)
	local structureId = payload.structureId
	local palUID = payload.palUID
	if not structureId or not palUID then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local success, errorCode = FacilityService.assignPal(player.UserId, structureId, palUID)
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true }
end

local function handleUnassignPal(player: Player, payload: any)
	local structureId = payload.structureId
	if not structureId then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local success, errorCode = FacilityService.unassignPal(player.UserId, structureId)
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true }
end

local function handleSleep(player: Player, payload: any)
	local structureId = payload and payload.structureId
	if not structureId then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end

	local success, errorCode, data = FacilityService.sleep(player, structureId)
	if not success then
		return { success = false, errorCode = errorCode }
	end

	return { success = true, data = data }
end

--========================================
-- Initialization
--========================================

function FacilityService.Init(_NetController, _DataService, _InventoryService, _BuildService, _Balance, _RecipeService, _WorldDropService, _TechService)
	NetController = _NetController
	DataService = _DataService
	InventoryService = _InventoryService
	BuildService = _BuildService
	Balance = _Balance
	RecipeService = _RecipeService
	WorldDropService = _WorldDropService
	TechService = _TechService
	
	-- PlayerRemoving: 별도 정리 불필요 (시설 상태는 structureId 기반)

	-- 모닥불 등 시설 자연 내구도 감소 루프
	task.spawn(function()
		while true do
			local tickSec = Balance.FACILITY_PASSIVE_DECAY_TICK or 5
			task.wait(tickSec)

			for structureId, runtime in pairs(facilityStates) do
				local facilityData = DataService.getFacility(runtime.facilityId)
				local drainPerSec = facilityData and facilityData.passiveHealthDecayPerSec
				if drainPerSec and drainPerSec > 0 and BuildService and BuildService.takeDamage then
					BuildService.takeDamage(structureId, drainPerSec * tickSec)
				end
			end
		end
	end)
	
	print("[FacilityService] Initialized")
end

--- PalboxService 주입 (Phase 5-5) - ServerInit에서 PalboxService 초기화 후 호출
function FacilityService.SetPalboxService(_PalboxService)
	PalboxService = _PalboxService
	print("[FacilityService] PalboxService injected")
end

--- BuildService 주입 (순환 참조 방지) - ServerInit에서 BuildService 초기화 후 호출
function FacilityService.SetBuildService(_BuildService)
	BuildService = _BuildService
	print("[FacilityService] BuildService injected")
end

--- PalAIService 주입 (Phase 7-5)
function FacilityService.SetPalAIService(_PalAIService)
	PalAIService = _PalAIService
	print("[FacilityService] PalAIService injected")
end

function FacilityService.SetTotemService(_TotemService)
	TotemService = _TotemService
	print("[FacilityService] TotemService injected")
end

--- 핸들러 맵 반환 (ServerInit에서 NetController에 등록)
function FacilityService.GetHandlers()
	return {
		["Facility.GetInfo.Request"] = handleGetInfo,
		["Facility.AddFuel.Request"] = handleAddFuel,
		["Facility.AddInput.Request"] = handleAddInput,
		["Facility.CollectOutput.Request"] = handleCollectOutput,
		["Facility.RemoveInput.Request"] = handleRemoveInput,
		["Facility.RemoveFuel.Request"] = handleRemoveFuel,
		-- Phase 5-5: 팰 작업 배치
		["Facility.AssignPal.Request"] = handleAssignPal,
		["Facility.UnassignPal.Request"] = handleUnassignPal,
		["Facility.Sleep.Request"] = handleSleep,
	}
end

return FacilityService
