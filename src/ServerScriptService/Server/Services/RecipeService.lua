-- RecipeService.lua
-- 레시피 효율 계산 서비스 (Phase 2-3)
-- 제작 시간 보정: 시설 속도 + 크리처/Bond/Traits (확장점)
-- CraftingService/FacilityService가 제작 전 호출하여 보정된 시간을 받음

local RecipeService = {}

--========================================
-- Dependencies (Init에서 주입)
--========================================
local DataService

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)

--========================================
-- Efficiency Context
--========================================
-- CraftContext = {
--   facilityId: string?,        -- 사용 중인 시설 ID (FacilityData 키)
--   creatureBonus: number?,     -- 활성 크리처 효율 보너스 (Phase 3에서 주입)
--   bondMultiplier: number?,    -- Bond 배율 (Phase 3에서 주입)
--   traitBonus: number?,        -- 특성 보너스 (Phase 3에서 주입)
--   playerStatBonus: number?,   -- 플레이어 스탯 보너스 (Phase 6에서 주입)
-- }

--========================================
-- Core: Efficiency Calculation
--========================================

--- 효율 배율 계산
--- 공식: totalMultiplier = facilitySpeed * (1 + creatureBonus + bondMultiplier + traitBonus + playerStatBonus)
--- 반환: 0보다 큰 숫자 (높을수록 빠름)
function RecipeService.calculateEfficiency(context: {[string]: any}?): number
	context = context or {}
	
	-- 1. 시설 속도 배율 (FacilityData.craftSpeed)
	local facilitySpeed = 1.0
	if context.facilityId then
		local facilityData = DataService.getFacility(context.facilityId)
		if facilityData and facilityData.craftSpeed then
			facilitySpeed = facilityData.craftSpeed
		end
	end
	
	-- 2. 크리처 보너스 (Phase 3 확장점 — 현재 기본값 0)
	local creatureBonus = context.creatureBonus or 0
	
	-- 3. Bond 배율 (Phase 3 확장점 — 현재 기본값 0)
	local bondMultiplier = context.bondMultiplier or 0
	
	-- 4. Traits 보너스 (Phase 3 확장점 — 현재 기본값 0)
	local traitBonus = context.traitBonus or 0
	
	-- 5. 플레이어 스탯 보너스 (Phase 6 확장점 — 현재 기본값 0)
	local playerStatBonus = context.playerStatBonus or 0
	
	-- 최종 배율 계산
	-- facilitySpeed는 기본 배율, 나머지는 가산
	local totalMultiplier = facilitySpeed * (1 + creatureBonus + bondMultiplier + traitBonus + playerStatBonus)
	
	-- 최소값 보장 (0 이하 방지)
	return math.max(0.1, totalMultiplier)
end

--- 레시피의 실제 제작 시간 계산
--- @param recipeId string 레시피 ID
--- @param context table? CraftContext (효율 변수들)
--- @return number realCraftTime (초)
function RecipeService.calculateCraftTime(recipeId: string, context: {[string]: any}?): number
	local recipe = DataService.getRecipe(recipeId)
	if not recipe then
		warn("[RecipeService] Recipe not found:", recipeId)
		return 0
	end
	
	local baseCraftTime = recipe.craftTime or 0
	if baseCraftTime <= 0 then
		return 0  -- 즉시 제작은 보정 없이 0
	end
	
	local efficiency = RecipeService.calculateEfficiency(context)
	
	-- 실제 시간 = 기본 시간 / 효율
	local realTime = baseCraftTime / efficiency
	
	-- 최소 1초 보장 (0초 미만 방지)
	return math.max(1, math.floor(realTime + 0.5))
end

--- 레시피의 기본 정보 + 효율 보정 정보 반환
function RecipeService.getRecipeInfo(recipeId: string, context: {[string]: any}?)
	local recipe = DataService.getRecipe(recipeId)
	if not recipe then
		return nil
	end
	
	local efficiency = RecipeService.calculateEfficiency(context)
	local realCraftTime = RecipeService.calculateCraftTime(recipeId, context)
	
	return {
		recipeId = recipeId,
		name = recipe.name,
		category = recipe.category,
		techLevel = recipe.techLevel or 0,
		requiredFacility = recipe.requiredFacility,
		baseCraftTime = recipe.craftTime or 0,
		realCraftTime = realCraftTime,
		efficiency = efficiency,
		inputs = recipe.inputs,
		outputs = recipe.outputs,
	}
end

--- 특정 테크 레벨까지의 해금된 레시피 목록 (Phase 6 준비)
--- 현재는 techLevel 필터만 적용 (실제 해금 로직은 Phase 6 TechService)
function RecipeService.getRecipesForTechLevel(maxTechLevel: number): { any }
	local allRecipes = DataService.get("RecipeData")
	if not allRecipes then return {} end
	
	local result = {}
	for recipeId, recipe in pairs(allRecipes) do
		local level = recipe.techLevel or 0
		if level <= maxTechLevel then
			table.insert(result, {
				recipeId = recipeId,
				name = recipe.name,
				category = recipe.category,
				techLevel = level,
				requiredFacility = recipe.requiredFacility,
				baseCraftTime = recipe.craftTime or 0,
			})
		end
	end
	
	return result
end

--- 레시피가 특정 테크 레벨에서 해금 상태인지 확인
function RecipeService.isUnlocked(recipeId: string, playerTechLevel: number): boolean
	local recipe = DataService.getRecipe(recipeId)
	if not recipe then return false end
	
	local required = recipe.techLevel or 0
	return playerTechLevel >= required
end

--========================================
-- Debug / Test Helpers
--========================================

--- 효율 시뮬레이션 (DoD 검증용)
--- 동일 레시피가 context에 따라 시간이 달라지는지 확인
function RecipeService.debugSimulate(recipeId: string)
	local recipe = DataService.getRecipe(recipeId)
	if not recipe then
		print("[RecipeService.Debug] Recipe not found:", recipeId)
		return
	end
	
	print(string.format("\n[RecipeService.Debug] === Simulate: %s (base: %ds) ===", recipeId, recipe.craftTime or 0))
	
	-- Case 1: 기본 (보정 없음)
	local t1 = RecipeService.calculateCraftTime(recipeId, {})
	print(string.format("  [1] No bonuses:           %ds (efficiency: %.2f)", t1, RecipeService.calculateEfficiency({})))
	
	-- Case 2: 시설 craftSpeed = 2.0
	local t2 = RecipeService.calculateCraftTime(recipeId, { facilityId = "CAMPFIRE" })
	print(string.format("  [2] Facility CAMPFIRE:     %ds (efficiency: %.2f)", t2, RecipeService.calculateEfficiency({ facilityId = "CAMPFIRE" })))
	
	-- Case 3: 크리처 보너스 0.5
	local t3 = RecipeService.calculateCraftTime(recipeId, { creatureBonus = 0.5 })
	print(string.format("  [3] Creature bonus 0.5:    %ds (efficiency: %.2f)", t3, RecipeService.calculateEfficiency({ creatureBonus = 0.5 })))
	
	-- Case 4: Bond 배율 1.0
	local t4 = RecipeService.calculateCraftTime(recipeId, { bondMultiplier = 1.0 })
	print(string.format("  [4] Bond multiplier 1.0:   %ds (efficiency: %.2f)", t4, RecipeService.calculateEfficiency({ bondMultiplier = 1.0 })))
	
	-- Case 5: 전부 합산
	local ctx5 = { facilityId = "CAMPFIRE", creatureBonus = 0.5, bondMultiplier = 0.3, traitBonus = 0.2, playerStatBonus = 0.1 }
	local t5 = RecipeService.calculateCraftTime(recipeId, ctx5)
	print(string.format("  [5] All bonuses combined:  %ds (efficiency: %.2f)", t5, RecipeService.calculateEfficiency(ctx5)))
	
	print("[RecipeService.Debug] === End Simulate ===\n")
end

--========================================
-- Network Handlers
--========================================

local function handleGetRecipeInfo(player, payload)
	local recipeId = payload.recipeId
	if not recipeId then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	-- 현재 Phase에서는 context 없이 기본 정보만 반환
	local info = RecipeService.getRecipeInfo(recipeId, {})
	if not info then
		return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
	end
	
	return { success = true, data = info }
end

local function handleGetAllRecipes(player, payload)
	-- 현재 Phase에서는 techLevel 0 = 모든 레시피 해금
	local recipes = RecipeService.getRecipesForTechLevel(0)
	return { success = true, data = { recipes = recipes } }
end

--========================================
-- Initialization
--========================================

function RecipeService.Init(_DataService)
	DataService = _DataService
	
	print("[RecipeService] Initialized")
end

--- 핸들러 맵 반환
function RecipeService.GetHandlers()
	return {
		["Recipe.GetInfo.Request"] = handleGetRecipeInfo,
		["Recipe.GetAll.Request"] = handleGetAllRecipes,
	}
end

return RecipeService
