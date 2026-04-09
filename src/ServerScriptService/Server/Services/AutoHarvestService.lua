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
local BuildService = nil
local PalAIService = nil -- Phase 7-5: 팰 AI 및 비주얼

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
	
	-- outputSlot에 추가 (다중 아이템 맵 구조)
	if not runtime.outputSlot then
		runtime.outputSlot = {}
	end
	
	local currentCount = runtime.outputSlot[itemId] or 0
	local maxStack = Balance.MAX_STACK or 99
	local space = maxStack - currentCount
	
	if space > 0 then
		local toAdd = math.min(count, space)
		runtime.outputSlot[itemId] = currentCount + toAdd
		return count - toAdd  -- 남은 수량 반환
	end
	
	return count  -- 공간 없음
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
	
	-- CreatureData에서 크리처 정의 조회 (workTypes 등)
	local CreatureDataModule = require(game:GetService("ReplicatedStorage").Data.CreatureData)
	local palData = nil
	for _, entry in ipairs(CreatureDataModule) do
		if entry.id == palInstance.creatureId then
			palData = entry
			break
		end
	end
	-- palInstance 자체에 workTypes가 있으면 우선 사용
	if palInstance.workTypes and #palInstance.workTypes > 0 then
		palData = palData or {}
		palData.workTypes = palInstance.workTypes
	end
	if not palData then return end
	
	-- [추가] 팰 유지비 체크 (Hunger, SAN)
	local palStats = palInstance.stats or {}
	local minHunger = Balance.PAL_MIN_WORK_HUNGER or 15
	local minSan = Balance.PAL_MIN_WORK_SAN or 20
	
	if (palStats.hunger or 0) < minHunger or (palStats.san or 0) < minSan then
		warn(string.format("[AutoHarvestService] Pal %s is too hungry (%d) or tired (%d) to work. owner: %d", 
			palUID, palStats.hunger or 0, palStats.san or 0, ownerId))
		-- 상태 전파 (UI에 표시되도록 필요시 추가)
		return
	end
	
	-- 주인 베이스 정보 (베이스 밖 노드는 채집 불가)
	if not BaseClaimService then return end
	
	-- [OPTIMIZATION] 모든 노드 순회(O(N)) 대신 공간 쿼리(GetPartBoundsInRadius) 사용
	local gatherRadius = facilityData.gatherRadius or 30
	local nodeFolder = workspace:FindFirstChild("ResourceNodes")
	if not nodeFolder then return end
	
	-- 시설 위치 가져오기 (BuildService 참조)
	local struct = BuildService and BuildService.get(structureId)
	if not struct or not struct.position then return end
	
	local spatialParams = OverlapParams.new()
	spatialParams.FilterDescendantsInstances = { nodeFolder }
	spatialParams.FilterType = Enum.RaycastFilterType.Include
	
	local nearbyParts = workspace:GetPartBoundsInRadius(struct.position, gatherRadius, spatialParams)
	local processedNodes = {} -- 중복 처리 방지 (모델 내 여러 파트 감지 대응)
	
	local harvestedCount = 0
	
	for _, part in ipairs(nearbyParts) do
		local nodeModel = part:FindFirstAncestorOfClass("Model")
		if not nodeModel then continue end
		
		local nodeUID = nodeModel:GetAttribute("NodeUID")
		if not nodeUID or processedNodes[nodeUID] then continue end
		processedNodes[nodeUID] = true
		
		-- 노드 데이터 조회
		local nodeId = nodeModel:GetAttribute("NodeId")
		local nodeData = DataService and DataService.getResourceNode(nodeId)
		if not nodeData then continue end
		
		-- 팰이 해당 노드 수확 가능한지 확인
		if not canPalHarvestNode(palData, nodeData) then continue end
		
		-- 베이스 내 노드인지 확인 (다른 베이스 침범 방지)
		if not BaseClaimService.isInBase(ownerId, nodeModel:GetPivot().Position) then
			continue
		end
		
		-- [추가] 물리적 이동 및 작업 피드백 (PalAIService 연동)
		if PalAIService then
			if not PalAIService.isPalAt(assignedPalUID, nodeModel:GetPivot().Position, 8) then
				-- 노드로 이동 명령
				PalAIService.assignTask(assignedPalUID, "HARVEST", nodeModel:GetPivot().Position, 2, function()
					-- 도착 후 다음 틱에서 채집되도록 함
				end)
				continue -- 이동 중이므로 이번 틱은 스킵
			end
		end

		-- 노드 데미지 적용
		local palDamage = 1
		local eff = (palInstance.workPower or 1) * 0.5
		
		local success, _, drops = HarvestService.damageNode(nodeUID, palDamage, eff, ownerId)
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
		
		-- [추가] 팰 유지비 소모
		if PalboxService then
			PalboxService.modifyPalStats(ownerId, assignedPalUID, {
				hunger = -(Balance.PAL_WORK_HUNGER_COST or 2),
				san = -(Balance.PAL_WORK_SAN_COST or 1)
			})
		end
	end
	
	if harvestedCount > 0 then
		print(string.format("[AutoHarvestService] Facility %s harvested %d items", structureId, harvestedCount))
	end
	
		-- [추가] 시설 내구도 소모
		if BuildService and BuildService.takeDamage then
			BuildService.takeDamage(structureId, Balance.FACILITY_WORK_HP_LOSS or 0.1)
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

--========================================
-- Initialization
--========================================

function AutoHarvestService.Init(
	harvestService: any,
	facilityService: any,
	baseClaimService: any,
	palboxService: any,
	dataService: any,
	buildService: any,
	palAIService: any
)
	if initialized then return end
	
	HarvestService = harvestService
	FacilityService = facilityService
	BaseClaimService = baseClaimService
	PalboxService = palboxService
	DataService = dataService
	BuildService = buildService
	PalAIService = palAIService
	
	-- Heartbeat 시작
	startHeartbeat()
	
	initialized = true
	print("[AutoHarvestService] Initialized")
end

function AutoHarvestService.GetHandlers()
	return {}  -- 네트워크 핸들러 없음 (자동 처리)
end

return AutoHarvestService
