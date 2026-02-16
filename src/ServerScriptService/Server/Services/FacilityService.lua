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
local PalboxService  -- Phase 5-5: 팰 작업 배치

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
--   outputSlot: { itemId: string, count: number }?,
--   currentFuel: number,    -- 남은 가동 시간(초)
--   lastUpdateAt: number,   -- 마지막 Lazy Update 시각 (os.time())
--   processProgress: number, -- 현재 제작 진행률(초)
--   currentRecipeId: string?, -- 현재 처리 중인 레시피
-- }
local facilityStates = {}

--========================================
-- Internal Helpers
--========================================

--- 시설 런타임 초기화
local function createFacilityRuntime(structureId: string, facilityId: string, ownerId: number)
	return {
		structureId = structureId,
		facilityId = facilityId,
		ownerId = ownerId,
		state = Enums.FacilityState.IDLE,
		inputSlot = nil,
		fuelSlot = nil,
		outputSlot = nil,
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
local function determineState(runtime): string
	local facilityData = DataService.getFacility(runtime.facilityId)
	if not facilityData then return Enums.FacilityState.IDLE end
	
	-- Output 슬롯이 꽉 찼으면 → FULL (더 이상 사용하지 않음, 즉시 드롭하므로)
	-- if facilityData.hasOutputSlot and runtime.outputSlot ...
	
	-- 작업 가능 조건: Input + Fuel
	local hasInput = (runtime.inputSlot ~= nil and runtime.inputSlot.count > 0)
	local hasFuel = (runtime.currentFuel > 0)
	
	-- 연료 필요한 시설
	if facilityData.fuelConsumption > 0 then
		if hasInput and hasFuel then
			return Enums.FacilityState.ACTIVE
		elseif hasInput and not hasFuel then
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
	
	local facilityData = DataService.getFacility(runtime.facilityId)
	if not facilityData then
		runtime.lastUpdateAt = now
		return
	end
	
	-- 연료가 필요 없거나 Input이 없으면 skip
	local hasInput = (runtime.inputSlot ~= nil and runtime.inputSlot.count > 0)
	if not hasInput then
		runtime.lastUpdateAt = now
		runtime.state = determineState(runtime)
		return
	end
	
	-- 연료 기반 시설: 가동 가능한 시간 계산
	local activeTime = deltaTime
	if facilityData.fuelConsumption > 0 then
		-- 연료로 버틸 수 있는 시간
		local fuelTime = runtime.currentFuel / facilityData.fuelConsumption
		activeTime = math.min(deltaTime, fuelTime)
		
		-- 연료 차감
		runtime.currentFuel = math.max(0, runtime.currentFuel - activeTime * facilityData.fuelConsumption)
	end
	
	-- 제작 진행 계산
	if activeTime > 0 and runtime.currentRecipeId then
		local recipe = DataService.getRecipe(runtime.currentRecipeId)
		if recipe then
			-- [Phase 5-5] 팰 workPower 보너스 계산
			local creatureBonus = 0
			if runtime.assignedPalUID and runtime.assignedPalOwnerId and PalboxService then
				local pal = PalboxService.getPal(runtime.assignedPalOwnerId, runtime.assignedPalUID)
				if pal and pal.workPower then
					-- workPower 2 = 50% 속도 증가 (0.5 보너스)
					creatureBonus = (pal.workPower - 1) * 0.5
				end
			end
			
			local context = { facilityId = runtime.facilityId, creatureBonus = creatureBonus }
			local effectiveCraftTime = RecipeService.calculateCraftTime(runtime.currentRecipeId, context)
            
			local remainingTime = activeTime
			
			while remainingTime > 0 and runtime.inputSlot and runtime.inputSlot.count > 0 do
				-- 현재 아이템의 남은 제작 시간
				local timeNeeded = effectiveCraftTime - runtime.processProgress
				
				if remainingTime >= timeNeeded then
					-- 제작 완료!
					remainingTime = remainingTime - timeNeeded
					runtime.processProgress = 0
					
					-- Input 소모
					runtime.inputSlot.count = runtime.inputSlot.count - 1
					if runtime.inputSlot.count <= 0 then
						runtime.inputSlot = nil
					end
					
					-- Output 처리: 즉시 월드 드롭 (NotebookLM 요구사항)
					if facilityData.hasOutputSlot then
						if recipe.outputs and #recipe.outputs > 0 then
							local outputItem = recipe.outputs[1]
							local count = outputItem.count or 1
							
							-- 구조물 위치 조회
							local structure = BuildService.get(runtime.structureId)
							if structure and structure.position and WorldDropService then
								-- 구조물 위로 드롭
								local dropPos = structure.position + Vector3.new(0, 3, 0)
								WorldDropService.spawnDrop(dropPos, outputItem.itemId, count)
							end
						end
					end
					
					-- Output이 꽉 차서 멈추는 로직 제거 (계속 생산)
					-- if runtime.outputSlot and runtime.outputSlot.count >= (Balance.MAX_STACK or 99) then
					-- 	break
					-- end
				else
					-- 시간 부족 → 진행률만 갱신
					runtime.processProgress = runtime.processProgress + remainingTime
					remainingTime = 0
				end
			end
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

--========================================
-- Public API
--========================================

--- 시설 등록 (BuildService에서 배치 시 호출)
function FacilityService.register(structureId: string, facilityId: string, ownerId: number)
	local facilityData = DataService.getFacility(facilityId)
	if not facilityData then return end
	
	-- Input/Fuel/Output 슬롯이 있는 시설만 등록
	if facilityData.hasInputSlot or facilityData.hasFuelSlot or facilityData.hasOutputSlot then
		facilityStates[structureId] = createFacilityRuntime(structureId, facilityId, ownerId)
		print(string.format("[FacilityService] Registered facility: %s (%s)", structureId, facilityId))
	end
end

--- 시설 제거 (BuildService에서 해체 시 호출)
function FacilityService.unregister(structureId: string)
	facilityStates[structureId] = nil
	print(string.format("[FacilityService] Unregistered facility: %s", structureId))
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
	
	-- 🔥 Lazy Update 실행
	lazyUpdate(runtime)
	
	-- 레시피 정보 (팰 workPower 보너스 포함)
	local effectiveCraftTime = 0
	if runtime.currentRecipeId then
		-- [Phase 5-5] 팰 workPower 보너스 계산
		local creatureBonus = 0
		if runtime.assignedPalUID and runtime.assignedPalOwnerId and PalboxService then
			local pal = PalboxService.getPal(runtime.assignedPalOwnerId, runtime.assignedPalUID)
			if pal and pal.workPower then
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
		-- Phase 5-5: 팰 배치 정보
		assignedPalUID = runtime.assignedPalUID,
		assignedPalOwnerId = runtime.assignedPalOwnerId,
	}
end

--- 연료 투입
function FacilityService.addFuel(player: Player, structureId: string, invSlot: number)
	local runtime = facilityStates[structureId]
	if not runtime then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	local facilityData = DataService.getFacility(runtime.facilityId)
	if not facilityData or not facilityData.hasFuelSlot then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end
	
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
	
	-- 연료 슬롯에 같은 아이템이면 추가, 다르면 교체(기존 제거)
	if runtime.fuelSlot and runtime.fuelSlot.itemId ~= slotData.itemId then
		-- 기존 연료를 인벤으로 반환
		InventoryService.addItem(userId, runtime.fuelSlot.itemId, runtime.fuelSlot.count)
		runtime.fuelSlot = nil
	end
	
	-- 인벤에서 1개 제거 → 연료값 충전
	InventoryService.removeItem(userId, slotData.itemId, 1)
	runtime.currentFuel = runtime.currentFuel + itemData.fuelValue
	
	-- 연료 슬롯 기록
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
	})
	
	print(string.format("[FacilityService] Added fuel to %s: +%d (total: %.0f)",
		structureId, itemData.fuelValue, runtime.currentFuel))
	return true, nil, { currentFuel = runtime.currentFuel, state = runtime.state }
end

--- 재료 투입 (Input 슬롯)
function FacilityService.addInput(player: Player, structureId: string, invSlot: number, count: number?)
	local runtime = facilityStates[structureId]
	if not runtime then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	local facilityData = DataService.getFacility(runtime.facilityId)
	if not facilityData or not facilityData.hasInputSlot then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end
	
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
		InventoryService.addItem(userId, runtime.inputSlot.itemId, runtime.inputSlot.count)
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
	})
	
	print(string.format("[FacilityService] Added input to %s: %s x%d",
		structureId, slotData.itemId, addCount))
	return true, nil, { inputSlot = runtime.inputSlot, state = runtime.state }
end

--- 산출물 수거 (Output 슬롯)
--- 현재 미지원: Output은 즉시 월드 드롭으로 전환됨
function FacilityService.collectOutput(player: Player, structureId: string)
	return false, Enums.ErrorCode.NOT_SUPPORTED, nil
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

--========================================
-- Initialization
--========================================

function FacilityService.Init(_NetController, _DataService, _InventoryService, _BuildService, _Balance, _RecipeService, _WorldDropService)
	NetController = _NetController
	DataService = _DataService
	InventoryService = _InventoryService
	BuildService = _BuildService
	Balance = _Balance
	RecipeService = _RecipeService
	WorldDropService = _WorldDropService
	
	-- PlayerRemoving: 별도 정리 불필요 (시설 상태는 structureId 기반)
	
	print("[FacilityService] Initialized")
end

--- PalboxService 주입 (Phase 5-5) - ServerInit에서 PalboxService 초기화 후 호출
function FacilityService.SetPalboxService(_PalboxService)
	PalboxService = _PalboxService
	print("[FacilityService] PalboxService injected")
end

--- 핸들러 맵 반환 (ServerInit에서 NetController에 등록)
function FacilityService.GetHandlers()
	return {
		["Facility.GetInfo.Request"] = handleGetInfo,
		["Facility.AddFuel.Request"] = handleAddFuel,
		["Facility.AddInput.Request"] = handleAddInput,
		["Facility.CollectOutput.Request"] = handleCollectOutput,
		-- Phase 5-5: 팰 작업 배치
		["Facility.AssignPal.Request"] = handleAssignPal,
		["Facility.UnassignPal.Request"] = handleUnassignPal,
	}
end

return FacilityService
