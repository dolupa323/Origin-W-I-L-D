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
local function findNearestStorage(facilityPosition: Vector3, ownerId: number): (string?, any?)
	if not BuildService then return nil, nil end
	
	-- [FIX] 모든 구조물이 아닌 해당 소유자의 구조물만 순회 (성능 최적화)
	local ownerStructures = BuildService.getStructuresByOwner(ownerId)
	
	for _, structure in ipairs(ownerStructures) do
		-- Storage 타입인지 확인
		local facilityData = DataService and DataService.getFacility(structure.facilityId)
		if facilityData and facilityData.functionType == "STORAGE" then
			local dist = (structure.position - facilityPosition).Magnitude
			if dist <= searchRange and dist < nearestDist then
				nearestId = structure.id
				nearestDist = dist
				nearestStorage = structure
			end
		end
	end
	
	return nearestId, nearestStorage
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
	-- Output 슬롯 확인
	if not runtime.outputSlot or runtime.outputSlot.count == 0 then
		return 0
	end
	
	local itemId = runtime.outputSlot.itemId
	local count = runtime.outputSlot.count
	
	-- 시설 위치 가져오기 (BuildService에서)
	local structure = BuildService and BuildService.get(structureId)
	if not structure then return 0 end
	
	-- 가장 가까운 Storage 찾기
	local storageId, _ = findNearestStorage(structure.position, ownerId)
	if not storageId then return 0 end
	
	-- Storage에 아이템 추가
	local remaining = addToStorage(storageId, itemId, count)
	local deposited = count - remaining
	
	if deposited > 0 then
		-- Output 슬롯 업데이트
		runtime.outputSlot.count = remaining
		if remaining == 0 then
			runtime.outputSlot = nil
		end
		
		print(string.format("[AutoDepositService] Deposited %d %s from %s to %s",
			deposited, itemId, structureId, storageId))
	end
	
	return deposited
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
		if runtime.outputSlot and runtime.outputSlot.count > 0 then
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

local function stopHeartbeat()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

--========================================
-- Initialization
--========================================

function AutoDepositService.Init(
	facilityService: any,
	storageService: any,
	baseClaimService: any,
	buildService: any,
	dataService: any
)
	if initialized then return end
	
	FacilityService = facilityService
	StorageService = storageService
	BaseClaimService = baseClaimService
	BuildService = buildService
	DataService = dataService
	
	-- Heartbeat 시작
	startHeartbeat()
	
	initialized = true
	print("[AutoDepositService] Initialized")
end

function AutoDepositService.GetHandlers()
	return {}  -- 네트워크 핸들러 없음 (자동 처리)
end

return AutoDepositService
