-- AutoDepositService.lua
-- 자동 저장 시스템 (Phase 7-4)
-- 시설 Output이 가득 차면 근처 Storage로 자동 이동

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

local AutoDepositService = {}

--========================================
-- Dependencies (Init에서 주입)
--========================================
local initialized = false
local FacilityService = nil
local StorageService = nil
local BaseClaimService = nil
local BuildService = nil
local DataService = nil
local PalboxService = nil -- Phase 5-5
local PalAIService = nil -- Phase 7-5: 팰 AI 및 비주얼
local InventoryService = nil -- 스택 규칙 조회용 (지연 로딩)

--========================================
-- Internal State
--========================================
-- tick 누적 시간
local tickAccumulator = 0
local TICK_INTERVAL = Balance.AUTO_DEPOSIT_INTERVAL or 5

--========================================
-- Internal Functions
--========================================

--- 시설에서 가장 가까운 Storage 찾기
local function findNearestStorage(facilityPosition: Vector3, ownerId: number, itemId: string): (string?, any?)
	if not BuildService or not StorageService then return nil, nil end
	
	-- InventoryService 지연 로딩 (스택 규칙 조회용)
	if not InventoryService then
		local ok, svc = pcall(function()
			return require(game:GetService("ServerScriptService").Server.Services.InventoryService)
		end)
		if ok then InventoryService = svc end
	end
	
	local searchRange = Balance.AUTO_DEPOSIT_RANGE or 30
	local ownerStructures = BuildService.getStructuresByOwner(ownerId) or {}
	
	local priority1_Id = nil
	local priority1_Dist = math.huge
	
	local priority2_Id = nil
	local priority2_Dist = math.huge
	
	for _, structure in ipairs(ownerStructures) do
		local facilityData = DataService and DataService.getFacility(structure.facilityId)
		if facilityData and facilityData.functionType == "STORAGE" then
			local dist = (structure.position - facilityPosition).Magnitude
			if dist <= searchRange then
				-- 창고 내용물 확인
				local storage = StorageService.getStorageInfo(structure.id)
				if not storage then continue end
				
				local hasItem = false
				local hasSpace = false
				local stackable = InventoryService and InventoryService.isStackable(itemId)
				local maxStack = InventoryService and InventoryService.getMaxStackForItem(itemId) or 1
				
				for slot = 1, (Balance.STORAGE_SLOTS or 20) do
					local slotData = storage.slots[slot]
					if slotData then
						if stackable and slotData.itemId == itemId and slotData.count < maxStack then
							hasItem = true
							hasSpace = true
							break
						end
					else
						hasSpace = true
					end
				end
				
				if hasItem and hasSpace then
					-- 우선순위 1: 같은 아이템이 이미 있고 공간도 있는 경우
					if dist < priority1_Dist then
						priority1_Id = structure.id
						priority1_Dist = dist
					end
				elseif hasSpace then
					-- 우선순위 2: 아이템은 없지만 비어있는 슬롯이 있는 경우
					if dist < priority2_Dist then
						priority2_Id = structure.id
						priority2_Dist = dist
					end
				end
			end
		end
	end
	
	if priority1_Id then
		return priority1_Id, BuildService.get(priority1_Id)
	end
	
	return priority2_Id, BuildService.get(priority2_Id)
end

--- Storage에 아이템 추가
local function addToStorage(storageId: string, itemId: string, count: number): number
	if not StorageService then return count end
	
	-- StorageService의 내부 API 사용
	if StorageService.addItemInternal then
		return StorageService.addItemInternal(storageId, itemId, count)
	end
	
	-- fallback: 추가 못함
	return count
end

--- 시설의 Output → Storage 이동 처리
local function processDeposit(structureId: string, runtime: any, ownerId: number)
	-- Output 슬롯 확인 (다중 아이템 맵 구조)
	if type(runtime.outputSlot) ~= "table" then
		return 0
	end
	
	-- 배치된 팰 확인 (운반꾼)
	local assignedPalUID = FacilityService and FacilityService.getAssignedPal(structureId)
	if not assignedPalUID then return 0 end

	-- 팰 데이터 및 스탯 체크
	local palInstance = PalboxService and PalboxService.getPal(ownerId, assignedPalUID)
	if not palInstance then return 0 end
	
	local palStats = palInstance.stats or {}
	local minHunger = Balance.PAL_MIN_WORK_HUNGER or 15
	local minSan = Balance.PAL_MIN_WORK_SAN or 20
	
	if (palStats.hunger or 0) < minHunger or (palStats.san or 0) < minSan then
		-- 너무 배고프거나 힘들어서 작업 거부
		return 0
	end

	local totalDeposited = 0
	
	-- 모든 아이템에 대해 처리
	for itemId, count in pairs(runtime.outputSlot) do
		if count > 0 then
			-- 시설 위치 가져오기 (BuildService에서)
			local structure = BuildService and BuildService.get(structureId)
			if not structure then continue end
			
			-- 가장 가까운 Storage 찾기 (아이템 종류 우선 순위 고려)
			local storageId, storageStruct = findNearestStorage(structure.position, ownerId, itemId)
			if not storageId or not storageStruct then continue end
			
			-- [추가] 물리적 이동 및 작업 피드백 (PalAIService 연동)
			if PalAIService then
				-- 1. 먼저 시설로 이동하여 아이템 픽업
				if not PalAIService.isPalAt(assignedPalUID, structure.position, 8) then
					PalAIService.assignTask(assignedPalUID, "TRANSPORT_PICKUP", structure.position, 1.5, function()
						-- 픽업 완료 후 다음 틱에서 창고로 출발
					end)
					return 0 -- 이동 중이므로 중단 (한 번에 하나씩)
				end
				
				-- 2. 창고로 이동하여 아이템 저장
				if not PalAIService.isPalAt(assignedPalUID, storageStruct.position, 8) then
					PalAIService.assignTask(assignedPalUID, "TRANSPORT_DROP", storageStruct.position, 1.5, function()
						-- 도착 후 저장 처리
					end)
					return 0 -- 이동 중이므로 중단
				end
			end

			-- Storage에 아이템 추가 (팰이 창고에 도착했을 때만 실행됨)
			local remaining = addToStorage(storageId, itemId, count)
			local deposited = count - remaining
			
			if deposited > 0 then
				-- Output 슬롯 업데이트
				if remaining <= 0 then
					runtime.outputSlot[itemId] = nil
				else
					runtime.outputSlot[itemId] = remaining
				end
				
				totalDeposited = totalDeposited + deposited
				print(string.format("[AutoDepositService] Deposited %d %s from %s to %s",
					deposited, itemId, structureId, storageId))
				
				-- [추가] 팰 유지비 소모 (운반은 채집의 50%만 소모)
				if PalboxService then
					PalboxService.modifyPalStats(ownerId, assignedPalUID, {
						hunger = -((Balance.PAL_WORK_HUNGER_COST or 2) * 0.5),
						san = -((Balance.PAL_WORK_SAN_COST or 1) * 0.5)
					})
				end
			end
		end
	end
	
	return totalDeposited
end

--========================================
-- Public API
--========================================

--- 틱 처리 (Heartbeat에서 호출)
function AutoDepositService.tick(deltaTime: number)
	if not initialized then return end
	
	tickAccumulator = tickAccumulator + deltaTime
	if tickAccumulator < TICK_INTERVAL then return end
	tickAccumulator = 0
	
	-- 모든 활성 시설의 Output 처리
	if not FacilityService then return end
	
	local allRuntimes = FacilityService.getAllRuntimes and FacilityService.getAllRuntimes() or {}
	
	for structureId, runtime in pairs(allRuntimes) do
		-- Output이 있는 시설만 처리
		if type(runtime.outputSlot) == "table" and next(runtime.outputSlot) ~= nil then
			processDeposit(structureId, runtime, runtime.ownerId)
		end
	end
end

--- 특정 시설의 Output을 Storage로 강제 이동
function AutoDepositService.depositFromFacility(structureId: string): (boolean, number)
	local runtime = FacilityService and FacilityService.getRuntime(structureId)
	if not runtime then return false, 0 end
	
	local deposited = processDeposit(structureId, runtime, runtime.ownerId)
	return deposited > 0, deposited
end

--========================================
-- Heartbeat 연결
--========================================

local heartbeatConnection = nil

local function startHeartbeat()
	if heartbeatConnection then return end
	
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		AutoDepositService.tick(dt)
	end)
end

--========================================
-- Initialization
--========================================

function AutoDepositService.Init(
	facilityService: any,
	storageService: any,
	baseClaimService: any,
	buildService: any,
	dataService: any,
	palboxService: any,
	palAIService: any
)
	if initialized then return end
	
	FacilityService = facilityService
	StorageService = storageService
	BaseClaimService = baseClaimService
	BuildService = buildService
	DataService = dataService
	PalboxService = palboxService
	PalAIService = palAIService
	
	-- Heartbeat 시작
	startHeartbeat()
	
	initialized = true
	print("[AutoDepositService] Initialized")
end

function AutoDepositService.GetHandlers()
	return {}  -- 네트워크 핸들러 없음 (자동 처리)
end

return AutoDepositService
