-- AutoHarvestService.lua
-- 팰 자동 수확 시스템 (Phase 7-3)
-- 배치된 팰이 베이스 내 자원 노드를 자동 수확

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

local AutoHarvestService = {}

--========================================
-- Dependencies (Init에서 주입)
--========================================
local initialized = false
local HarvestService = nil
local FacilityService = nil
local BaseClaimService = nil
local PalboxService = nil
local DataService = nil

--========================================
-- Internal State
--========================================
-- 자동 수확 타이머 { [structureId] = lastHarvestTime }
local harvestTimers = {}

-- tick 누적 시간
local tickAccumulator = 0
local TICK_INTERVAL = 1  -- 1초마다 체크

--========================================
-- Internal Functions
--========================================

--- 팰의 workTypes와 노드의 nodeType 매칭 확인
local function canPalHarvestNode(palData: any, nodeData: any): boolean
	if not palData or not palData.workTypes then return false end
	if not nodeData or not nodeData.nodeType then return false end
	
	-- GATHERING workType이 있으면 모든 노드 수확 가능
	for _, workType in ipairs(palData.workTypes) do
		if workType == "GATHERING" then
			return true
		end
		-- 특정 매칭 (예: WOODCUTTING → TREE)
		if workType == "WOODCUTTING" and nodeData.nodeType == "TREE" then
			return true
		end
		if workType == "MINING" and (nodeData.nodeType == "ROCK" or nodeData.nodeType == "ORE") then
			return true
		end
	end
	
	return false
end

--- 노드에서 아이템 드롭 계산
local function calculateDrops(nodeData: any): {any}
	local drops = {}
	
	for _, resource in ipairs(nodeData.resources) do
		if math.random() <= resource.weight then
			local count = math.random(resource.min, resource.max)
			if count > 0 then
				table.insert(drops, {
					itemId = resource.itemId,
					count = count,
				})
			end
		end
	end
	
	return drops
end

--- 시설 Output에 아이템 추가
local function addToOutput(structureId: string, itemId: string, count: number): number
	if not FacilityService then return count end
	
	-- FacilityService의 runtime 정보 가져오기
	local runtime = FacilityService.getRuntime(structureId)
	if not runtime then return count end
	
	-- outputSlot에 추가
	if not runtime.outputSlot then
		runtime.outputSlot = { itemId = itemId, count = 0 }
	end
	
	-- 같은 아이템이면 스택
	if runtime.outputSlot.itemId == itemId or runtime.outputSlot.count == 0 then
		runtime.outputSlot.itemId = itemId
		local maxStack = Balance.MAX_STACK or 99
		local space = maxStack - runtime.outputSlot.count
		local toAdd = math.min(count, space)
		runtime.outputSlot.count = runtime.outputSlot.count + toAdd
		return count - toAdd  -- 남은 수량 반환
	end
	
	return count  -- 다른 아이템이면 추가 못함
end

--- 시설의 자동 수확 처리
local function processGatheringFacility(structureId: string, facilityData: any, ownerId: number)
	local now = os.time()
	local interval = facilityData.gatherInterval or Balance.AUTO_HARVEST_INTERVAL or 10
	
	-- 쿨다운 체크
	if harvestTimers[structureId] and (now - harvestTimers[structureId]) < interval then
		return
	end
	
	-- 배치된 팰 확인
	local assignedPalUID = FacilityService.getAssignedPal(structureId)
	if not assignedPalUID then return end
	
	-- 팰 데이터 조회
	local palInstance = PalboxService and PalboxService.getPal(ownerId, assignedPalUID)
	if not palInstance then return end
	
	local palData = DataService and DataService.getById("PalData", palInstance.palId)
	if not palData then return end
	
	-- 시설 위치 (근사값 - BuildService에서 가져와야 함)
	-- FacilityService에서 시설 런타임 조회
	local facilityInfo = FacilityService.getRuntime(structureId)
	if not facilityInfo then return end
	
	-- 베이스 내 자원 노드 검색
	local gatherRadius = facilityData.gatherRadius or 30
	local allNodes = HarvestService and HarvestService.getAllNodes() or {}
	
	local harvestedCount = 0
	local workPowerBonus = (palInstance.workPower or 1) * 0.5  -- workPower에 따른 수확량 보너스
	
	for _, node in ipairs(allNodes) do
		-- 노드 데이터 조회
		local nodeData = DataService and DataService.getResourceNode(node.nodeId)
		if not nodeData then continue end
		
		-- 팰이 해당 노드 수확 가능한지 확인
		if not canPalHarvestNode(palData, nodeData) then continue end
		
		-- 베이스 내 노드인지 확인
		if BaseClaimService and not BaseClaimService.isInBase(ownerId, node.position) then
			continue
		end
		
		-- [FIX] 노드 데미지 적용하여 고갈 처리 (무한 자원 복사 방지)
		local palDamage = 1 -- 팰의 기본 타격 데미지
		local eff = (palInstance.workPower or 1) * 0.5 -- 팰의 효율
		
		local success, _, drops = HarvestService.damageNode(node.nodeUID, palDamage, eff, ownerId)
		if not success then continue end
		
		for _, drop in ipairs(drops) do
			-- Output 슬롯에 추가
			local remaining = addToOutput(structureId, drop.itemId, drop.count)
			
			if remaining > 0 then
				-- Output 가득 참 - 수확 중단
				print(string.format("[AutoHarvestService] Output full for %s, stopping harvest", structureId))
				harvestTimers[structureId] = now
				return
			end
			
			harvestedCount = harvestedCount + drop.count
		end
	end
	
	if harvestedCount > 0 then
		print(string.format("[AutoHarvestService] Facility %s harvested %d items", structureId, harvestedCount))
	end
	
	harvestTimers[structureId] = now
end

--========================================
-- Public API
--========================================

--- 틱 처리 (Heartbeat에서 호출)
function AutoHarvestService.tick(deltaTime: number)
	if not initialized then return end
	
	tickAccumulator = tickAccumulator + deltaTime
	if tickAccumulator < TICK_INTERVAL then return end
	tickAccumulator = 0
	
	-- 모든 GATHERING 타입 시설 처리
	if not FacilityService then return end
	
	local allRuntimes = FacilityService.getAllRuntimes and FacilityService.getAllRuntimes() or {}
	
	for structureId, runtime in pairs(allRuntimes) do
		local facilityData = DataService and DataService.getFacility(runtime.facilityId)
		if facilityData and facilityData.functionType == "GATHERING" then
			processGatheringFacility(structureId, facilityData, runtime.ownerId)
		end
	end
end

--- 특정 시설의 자동 수확 강제 실행
function AutoHarvestService.forceGather(structureId: string): {any}
	local runtime = FacilityService and FacilityService.getRuntime(structureId)
	if not runtime then return {} end
	
	local facilityData = DataService and DataService.getFacility(runtime.facilityId)
	if not facilityData then return {} end
	
	-- 강제 수확을 위해 타이머 초기화
	harvestTimers[structureId] = nil
	processGatheringFacility(structureId, facilityData, runtime.ownerId)
	
	return runtime.outputSlot and { runtime.outputSlot } or {}
end

--========================================
-- Heartbeat 연결
--========================================

local heartbeatConnection = nil

local function startHeartbeat()
	if heartbeatConnection then return end
	
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		AutoHarvestService.tick(dt)
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

function AutoHarvestService.Init(
	harvestService: any,
	facilityService: any,
	baseClaimService: any,
	palboxService: any,
	dataService: any
)
	if initialized then return end
	
	HarvestService = harvestService
	FacilityService = facilityService
	BaseClaimService = baseClaimService
	PalboxService = palboxService
	DataService = dataService
	
	-- Heartbeat 시작
	startHeartbeat()
	
	initialized = true
	print("[AutoHarvestService] Initialized")
end

function AutoHarvestService.GetHandlers()
	return {}  -- 네트워크 핸들러 없음 (자동 처리)
end

return AutoHarvestService
