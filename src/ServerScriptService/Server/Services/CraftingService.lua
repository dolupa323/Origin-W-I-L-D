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
	for _, input in ipairs(inputs) do
		local removed = InventoryService.removeItem(userId, input.itemId, input.count)
		if removed < input.count then
			warn(string.format("[CraftingService] Failed to consume %s x%d for userId %d (only removed %d)",
				input.itemId, input.count, userId, removed))
			return false
		end
	end
	return true
end

--========================================
-- Internal: 이벤트 발행
--========================================
local function emitCraftEvent(eventName: string, player: Player, data: any)
	if NetController then
		NetController.FireClient(player, eventName, data)
	end
end

local function emitCraftEventToAll(eventName: string, data: any)
	if NetController then
		NetController.FireAllClients(eventName, data)
	end
end

--========================================
-- Public API
--========================================

function CraftingService.Init(_NetController, _DataService, _InventoryService, _BuildService, _RecipeService, _TechService, _PlayerStatService)
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
	
	-- Heartbeat 연결 (Lazy tick)
	RunService.Heartbeat:Connect(processTick)
	
	-- 플레이어 퇴장 이벤트
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
	initialized = true
	print("[CraftingService] Initialized with Tech & Stat injection")
end

--========================================
-- Public API: 제작 시작
--========================================
function CraftingService.start(player: Player, recipeId: string, structureId: string?)
	local userId = player.UserId
	
	-- 1. 레시피 존재 여부
	local recipe = DataService.getRecipe(recipeId)
	if not recipe then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end

	-- 1a. 기술 해금 검증 (Phase 6)
	if TechService and not TechService.isRecipeUnlocked(userId, recipeId) then
		return false, Enums.ErrorCode.RECIPE_LOCKED, nil
	end
	
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
	local matOk, matErr = validateMaterials(player, recipe.inputs)
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
	local realCraftTime = RecipeService.calculateCraftTime(recipeId, context)
	
	-- 5. 인벤토리 여유 검증 (즉시제작일 때만 사전 체크)
	if realCraftTime == 0 then
		for _, output in ipairs(recipe.outputs) do
			local canAdd = InventoryService.canAdd(userId, output.itemId, output.count)
			if not canAdd then
				return false, Enums.ErrorCode.INV_FULL, nil
			end
		end
	end
	
	-- === 실행 단계 ===
	
	-- 6. 재료 차감
	local consumed = consumeMaterials(userId, recipe.inputs)
	if not consumed then
		return false, Enums.ErrorCode.INTERNAL_ERROR, nil
	end
	
	-- 7. 즉시 제작
	if realCraftTime <= 0 then -- Changed from == 0 to <= 0
		for _, output in ipairs(recipe.outputs) do
			InventoryService.addItem(userId, output.itemId, output.count)
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
		completesAt = now + realCraftTime,
		state = Enums.CraftState.CRAFTING,
	}
	
	local queue = getQueue(userId)
	queue[craftId] = craftEntry
	
	local startData = {
		craftId = craftId,
		recipeId = recipeId,
		craftTime = realCraftTime,
		completesAt = craftEntry.completesAt,
	}
	
	emitCraftEvent("Craft.Started", player, startData)
	
	print(string.format("[CraftingService] Queued craft %s (%s) for player %d, completes in %ds",
		craftId, recipeId, userId, realCraftTime))
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
	
	-- 이미 완료된 항목은 취소 불가
	if entry.state == Enums.CraftState.COMPLETED then
		return false, Enums.ErrorCode.INVALID_STATE, nil
	end
	
	-- 재료 환불
	local recipe = DataService.getRecipe(entry.recipeId)
	if recipe and Balance.CRAFT_CANCEL_REFUND > 0 then
		for _, input in ipairs(recipe.inputs) do
			local refundCount = math.floor(input.count * Balance.CRAFT_CANCEL_REFUND)
			if refundCount > 0 then
				InventoryService.addItem(userId, input.itemId, refundCount)
			end
		end
	end
	
	-- 큐에서 제거
	queue[craftId] = nil
	
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
function CraftingService.collect(player: Player, craftId: string)
	local userId = player.UserId
	local queue = craftQueues[userId]
	
	if not queue or not queue[craftId] then
		return false, Enums.ErrorCode.CRAFT_NOT_FOUND, nil
	end
	
	local entry = queue[craftId]
	
	-- Lazy Update: 완료 시간 확인
	local now = os.time()
	if entry.state == Enums.CraftState.CRAFTING and now >= entry.completesAt then
		entry.state = Enums.CraftState.COMPLETED
	end
	
	-- 아직 제작 중이면 수거 불가
	if entry.state ~= Enums.CraftState.COMPLETED then
		return false, Enums.ErrorCode.INVALID_STATE, nil
	end
	
	-- 결과물 인벤토리 추가
	local recipe = DataService.getRecipe(entry.recipeId)
	if not recipe then
		return false, Enums.ErrorCode.INTERNAL_ERROR, nil
	end
	
	-- 인벤토리 여유 사전 체크
	for _, output in ipairs(recipe.outputs) do
		local canAdd = InventoryService.canAdd(userId, output.itemId, output.count)
		if not canAdd then
			return false, Enums.ErrorCode.INV_FULL, nil
		end
	end
	
	-- 결과물 추가
	for _, output in ipairs(recipe.outputs) do
		InventoryService.addItem(userId, output.itemId, output.count)
	end
	
	-- 3a. 경험치 보상 (Phase 6)
	if PlayerStatService then
		PlayerStatService.addXP(userId, (Balance.XP_CRAFT_ITEM or 5) * (recipe.xpMultiplier or 1), Enums.XPSource.CRAFT_ITEM)
	end
	
	-- 3b. 퀘스트 콜백 (Phase 8)
	if questCallback then
		questCallback(userId, entry.recipeId)
	end
	
	-- 큐에서 제거
	queue[craftId] = nil
	
	local collectData = {
		craftId = craftId,
		recipeId = entry.recipeId,
		outputs = recipe.outputs,
	}
	
	emitCraftEvent("Craft.Completed", player, collectData)
	
	print(string.format("[CraftingService] Collected craft %s for player %d", craftId, userId))
	return true, nil, collectData
end

--========================================
-- Public API: 제작 큐 조회
--========================================
function CraftingService.getQueue(player: Player)
	local userId = player.UserId
	local queue = craftQueues[userId] or {}
	local now = os.time()
	
	-- Lazy Update: 완료된 항목 상태 갱신
	local result = {}
	for craftId, entry in pairs(queue) do
		if entry.state == Enums.CraftState.CRAFTING and now >= entry.completesAt then
			entry.state = Enums.CraftState.COMPLETED
		end
		table.insert(result, {
			craftId = craftId,
			recipeId = entry.recipeId,
			state = entry.state,
			startedAt = entry.startedAt,
			completesAt = entry.completesAt,
			remaining = math.max(0, entry.completesAt - now),
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
			if entry.state == Enums.CraftState.CRAFTING and now >= entry.completesAt then
				entry.state = Enums.CraftState.COMPLETED
				
				-- 플레이어에게 완료 알림
				local player = Players:GetPlayerByUserId(userId)
				if player then
					emitCraftEvent("Craft.Ready", player, {
						craftId = craftId,
						recipeId = entry.recipeId,
					})
				end
				
				print(string.format("[CraftingService] Craft %s completed for userId %d", craftId, userId))
			end
		end
	end
end

--========================================
-- Player 퇴장 시 큐 정리
--========================================
onPlayerRemoving = function(player: Player)
	-- 진행 중인 제작은 다음 접속 시 복원하지 않음 (비영속)
	-- 재료는 이미 차감되었으므로, 재접속 시 사라짐 (의도된 설계)
	craftQueues[player.UserId] = nil
end

--========================================
-- Network Handlers
--========================================
function CraftingService.GetHandlers()
	return {
		["Craft.Start.Request"] = function(player, payload)
			local recipeId = payload.recipeId
			local structureId = payload.structureId  -- optional
			
			if not recipeId or type(recipeId) ~= "string" then
				return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
			end
			
			local success, errorCode, data = CraftingService.start(player, recipeId, structureId)
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
			
			if not craftId or type(craftId) ~= "string" then
				return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
			end
			
			local success, errorCode, data = CraftingService.collect(player, craftId)
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
