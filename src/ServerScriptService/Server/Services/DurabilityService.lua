-- DurabilityService.lua
-- 아이템 내구도 관리 서비스 (Phase 2-4)
-- 내구도 감소 및 수리(Repair) 담당

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)

local DurabilityService = {}

-- Dependencies
local NetController
local InventoryService
local DataService
local BuildService
local Balance

--========================================
-- Internal Helpers
--========================================

--- 수리 시설 접근성 및 타입 검증
local function validateRepairFacility(player: Player, structureId: string?): (boolean, string?)
	if not structureId then return false, Enums.ErrorCode.NO_FACILITY end
	
	if not BuildService or not DataService then return false, Enums.ErrorCode.INTERNAL_ERROR end
	
	local structure = BuildService.get(structureId)
	if not structure then return false, Enums.ErrorCode.NOT_FOUND end
	
	local facilityData = DataService.getFacility(structure.facilityId)
	if not facilityData or facilityData.functionType ~= "REPAIR" then
		return false, Enums.ErrorCode.NO_FACILITY
	end
	
	-- 거리 검증
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false, Enums.ErrorCode.BAD_REQUEST end
	
	local dist = (hrp.Position - structure.position).Magnitude
	if dist > (Balance.CRAFT_RANGE or 20) then
		return false, Enums.ErrorCode.OUT_OF_RANGE
	end
	
	return true
end

--- 아이템 수리 비용 계산 (제작 재료의 50%)
local function calculateRepairCost(itemId: string): {any}?
	if not DataService then return nil end
	
	local allRecipes = DataService.get("RecipeData")
	if not allRecipes then return nil end
	
	-- 해당 아이템을 결과물로 가지는 레시피 찾기
	local targetRecipe
	for _, recipe in pairs(allRecipes) do
		if recipe.outputs and recipe.outputs[1] and recipe.outputs[1].itemId == itemId then
			targetRecipe = recipe
			break
		end
	end
	
	if not targetRecipe then return nil end
	
	local costs = {}
	for _, input in ipairs(targetRecipe.inputs) do
		local amount = math.ceil(input.count * 0.5) -- 50% 반올림
		if amount > 0 then
			table.insert(costs, { itemId = input.itemId, count = amount })
		end
	end
	
	return costs
end

--========================================
-- Public API
--========================================

function DurabilityService.Init(_NetController, _InventoryService, _DataService, _BuildService, _Balance)
	NetController = _NetController
	InventoryService = _InventoryService
	DataService = _DataService
	BuildService = _BuildService
	Balance = _Balance
	
	print("[DurabilityService] Initialized with Repair Logic")
	
	-- 패시브 내구도 감소 루프 (예: 횃불)
	local Players = game:GetService("Players")
	local DataHelper = require(Shared.Util.DataHelper)
	
	task.spawn(function()
		while true do
			task.wait(1) -- 매 1초마다 동기화 검사
			for _, player in ipairs(Players:GetPlayers()) do
				local userId = player.UserId
				-- 장착 중인 아이템 가져오기
				local activeSlot = InventoryService.getActiveSlot and InventoryService.getActiveSlot(userId)
				if activeSlot then
					local slotData = InventoryService.getSlot and InventoryService.getSlot(userId, activeSlot)
					if slotData and slotData.itemId and slotData.durability then
						local itemData = DataHelper.GetData("ItemData", slotData.itemId)
						if itemData and itemData.passiveDurabilityDrain and itemData.passiveDurabilityDrain > 0 then
							-- 1초마다 정해진 량만큼 내구도 자동 감소
							DurabilityService.reduceDurability(player, activeSlot, itemData.passiveDurabilityDrain)
						end
					end
				end
			end
		end
	end)
end

--- 내구도 감소 요청 (채집, 공격 등에서 호출)
--- @param player Player
--- @param slot number 인벤토리 슬롯
--- @param amount number 감소량 (양수)
--- @return boolean success
function DurabilityService.reduceDurability(player: Player, slot: number, amount: number): boolean
	if not player or not slot or not amount then return false end
	if amount <= 0 then return false end -- 감소량은 양수여야 함
	
	local userId = player.UserId
	
	-- InventoryService에 위임
	local success, errorCode, current = InventoryService.decreaseDurability(userId, slot, amount)
	
	if not success then
		if errorCode ~= Enums.ErrorCode.INVALID_ITEM then
			warn(string.format("[DurabilityService] Failed to reduce durability for player %d slot %d: %s", 
				userId, slot, tostring(errorCode)))
		end
		return false
	end
	
	return true
end

--- 아이템 수리 실행
function DurabilityService.repair(player: Player, slot: number, structureId: string?): (boolean, string?)
	local userId = player.UserId
	
	-- 1. 시설 검증
	local facilityOk, facilityErr = validateRepairFacility(player, structureId)
	if not facilityOk then return false, facilityErr end
	
	-- 2. 아이템 존재 및 내구도 확인
	local slotData = InventoryService.getSlot(userId, slot)
	if not slotData then return false, Enums.ErrorCode.SLOT_EMPTY end
	if not slotData.durability then return false, Enums.ErrorCode.INVALID_ITEM end
	
	local itemData = DataService.getItem(slotData.itemId)
	if not itemData or not itemData.durability then return false, Enums.ErrorCode.INVALID_ITEM end
	
	-- 이미 내구도가 꽉 찼으면 무시
	if slotData.durability >= itemData.durability then
		return false, Enums.ErrorCode.BAD_REQUEST -- or "ALREADY_FULL"
	end
	
	-- 3. 비용 계산
	local costs = calculateRepairCost(slotData.itemId)
	if not costs then
		-- 레시피가 없는 아이템(예: 기본 자원)은 수리 불가
		return false, Enums.ErrorCode.NOT_SUPPORTED
	end
	
	-- 4. 재료 보유 확인
	for _, cost in ipairs(costs) do
		if not InventoryService.hasItem(userId, cost.itemId, cost.count) then
			return false, Enums.ErrorCode.MISSING_REQUIREMENTS
		end
	end
	
	-- 5. 재료 소모
	for _, cost in ipairs(costs) do
		InventoryService.removeItem(userId, cost.itemId, cost.count)
	end
	
	-- 6. 내구도 복구 (100%)
	InventoryService.setDurability(userId, slot, itemData.durability)
	
	print(string.format("[DurabilityService] Player %d repaired %s in slot %d", userId, slotData.itemId, slot))
	return true, nil
end

--========================================
-- Network Handlers
--========================================

function DurabilityService.GetHandlers()
	return {
		["Durability.Repair.Request"] = function(player, payload)
			local slot = payload.slot
			local structureId = payload.structureId
			
			if not slot or type(slot) ~= "number" then
				return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
			end
			
			local success, errorCode = DurabilityService.repair(player, slot, structureId)
			return { success = success, errorCode = errorCode }
		end,
	}
end

return DurabilityService
