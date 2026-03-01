-- BaseClaimService.lua
-- 베이스 영역 관리 시스템 (Phase 7-2)
-- 플레이어 베이스 영역 설정 및 자동화 범위 관리

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

local BaseClaimService = {}

--========================================
-- Dependencies (Init에서 주입)
--========================================
local initialized = false
local NetController = nil
local SaveService = nil
local BuildService = nil

--========================================
-- Internal State
--========================================
-- 베이스 영역 { [userId] = BaseClaim }
local bases = {}

-- BaseClaim 구조
-- {
--   id = "base_12345",
--   ownerId = userId,
--   centerPosition = Vector3,
--   radius = 30,
--   level = 1,
--   createdAt = timestamp,
-- }

--========================================
-- Internal Functions
--========================================

--- 고유 베이스 ID 생성
local function generateBaseId(userId: number): string
	return string.format("base_%d_%d", userId, os.time())
end

--- 월드 상태에서 베이스 로드
local function loadBases()
	if not SaveService then return end
	
	local worldState = SaveService.getWorldState()
	if worldState and worldState.bases then
		local loadedCount = 0
		for baseId, baseData in pairs(worldState.bases) do
			-- Vector3 복원
			if baseData.centerPosition then
				local pos = baseData.centerPosition
				baseData.centerPosition = Vector3.new(pos.X or pos.x or 0, pos.Y or pos.y or 0, pos.Z or pos.z or 0)
			end
			bases[baseData.ownerId] = baseData
			loadedCount = loadedCount + 1
		end
		print(string.format("[BaseClaimService] Loaded %d bases from world state", loadedCount))
	end
end

--- 베이스 저장
local function saveBase(baseClaim: any)
	if not SaveService or not SaveService.updateWorldState then return end
	
	SaveService.updateWorldState(function(state)
		if not state.bases then
			state.bases = {}
		end
		-- Vector3를 일반 테이블로 변환 (저장용)
		local saveData = {
			id = baseClaim.id,
			ownerId = baseClaim.ownerId,
			centerPosition = {
				X = baseClaim.centerPosition.X,
				Y = baseClaim.centerPosition.Y,
				Z = baseClaim.centerPosition.Z,
			},
			radius = baseClaim.radius,
			level = baseClaim.level,
			createdAt = baseClaim.createdAt,
		}
		state.bases[baseClaim.id] = saveData
		return state
	end)
end

--========================================
-- Public API
--========================================

--- 베이스 생성 (첫 건물 설치 시 자동 호출)
function BaseClaimService.create(userId: number, position: Vector3): (boolean, string?, string?)
	-- 이미 베이스 있는지 확인
	if bases[userId] then
		return false, Enums.ErrorCode.BAD_REQUEST, nil
	end
	
	-- 플레이어당 최대 베이스 수 확인
	local maxBases = Balance.BASE_MAX_PER_PLAYER or 1
	if maxBases <= 0 then
		return false, Enums.ErrorCode.NOT_SUPPORTED, nil
	end
	
	-- 중첩 검사 (Overlap Protection: (NewRadius + OtherRadius) < Distance)
	local newRadius = Balance.BASE_DEFAULT_RADIUS or 30
	for _, otherBase in pairs(bases) do
		local dx = position.X - otherBase.centerPosition.X
		local dz = position.Z - otherBase.centerPosition.Z
		local dist = math.sqrt(dx * dx + dz * dz)
		
		-- 안전 마진 포함 (중첩 원천 차단)
		local minSafeDist = newRadius + otherBase.radius
		if dist < minSafeDist then
			print(string.format("[BaseClaimService] Create failed: Overlap with player %d's base", otherBase.ownerId))
			return false, Enums.ErrorCode.COLLISION, nil
		end
	end
	
	-- 베이스 생성
	local baseId = generateBaseId(userId)
	local baseClaim = {
		id = baseId,
		ownerId = userId,
		centerPosition = position,
		radius = newRadius,
		level = 1,
		createdAt = os.time(),
	}
	
	bases[userId] = baseClaim
	saveBase(baseClaim)
	
	-- 클라이언트 알림
	if NetController then
		local player = game:GetService("Players"):GetPlayerByUserId(userId)
		if player then
			NetController.FireClient(player, "Base.Created", {
				baseId = baseId,
				centerPosition = position,
				radius = baseClaim.radius,
			})
		end
	end
	
	print(string.format("[BaseClaimService] Created base %s for player %d at (%.1f, %.1f, %.1f)",
		baseId, userId, position.X, position.Y, position.Z))
	
	return true, nil, baseId
end

--- 베이스 조회
function BaseClaimService.getBase(userId: number): any?
	return bases[userId]
end

--- 해당 위치를 소유한 베이스 주인 ID 반환
function BaseClaimService.getOwnerAt(position: Vector3): number?
	for userId, baseClaim in pairs(bases) do
		local dx = position.X - baseClaim.centerPosition.X
		local dz = position.Z - baseClaim.centerPosition.Z
		local dist = math.sqrt(dx * dx + dz * dz)
		
		if dist <= baseClaim.radius then
			return userId
		end
	end
	return nil
end

--- 위치가 베이스 안인지 확인
function BaseClaimService.isInBase(userId: number, position: Vector3): boolean
	local baseClaim = bases[userId]
	if not baseClaim then return false end
	
	-- XZ 평면에서 거리 계산 (높이 무시)
	local dx = position.X - baseClaim.centerPosition.X
	local dz = position.Z - baseClaim.centerPosition.Z
	local distance = math.sqrt(dx * dx + dz * dz)
	
	return distance <= baseClaim.radius
end

--- 베이스 반경 확장
function BaseClaimService.expand(userId: number): (boolean, string?)
	local baseClaim = bases[userId]
	if not baseClaim then
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	local maxRadius = Balance.BASE_MAX_RADIUS or 100
	local radiusIncrease = Balance.BASE_RADIUS_PER_LEVEL or 10
	
	if baseClaim.radius >= maxRadius then
		return false, Enums.ErrorCode.INVALID_STATE
	end
	
	baseClaim.radius = math.min(baseClaim.radius + radiusIncrease, maxRadius)
	baseClaim.level = baseClaim.level + 1
	saveBase(baseClaim)
	
	-- 클라이언트 알림
	if NetController then
		local player = game:GetService("Players"):GetPlayerByUserId(userId)
		if player then
			NetController.FireClient(player, "Base.Expanded", {
				baseId = baseClaim.id,
				radius = baseClaim.radius,
				level = baseClaim.level,
			})
		end
	end
	
	return true, nil
end

--- 베이스 내 시설 목록 조회
function BaseClaimService.getStructuresInBase(userId: number): {string}
	local baseClaim = bases[userId]
	if not baseClaim then return {} end
	if not BuildService then return {} end
	
	local result = {}
	local allStructures = BuildService.getAll()
	
	for _, structure in ipairs(allStructures) do
		if BaseClaimService.isInBase(userId, structure.position) then
			table.insert(result, structure.id)
		end
	end
	
	return result
end

--- 베이스 삭제 (디버그/어드민용)
function BaseClaimService.delete(userId: number): boolean
	local baseClaim = bases[userId]
	if not baseClaim then return false end
	
	-- SaveService에서 제거
	if SaveService and SaveService.updateWorldState then
		SaveService.updateWorldState(function(state)
			if state.bases then
				state.bases[baseClaim.id] = nil
			end
			return state
		end)
	end
	
	bases[userId] = nil
	return true
end

--- 모든 베이스 조회 (디버그용)
function BaseClaimService.getAllBases(): {any}
	local result = {}
	for _, baseClaim in pairs(bases) do
		table.insert(result, {
			id = baseClaim.id,
			ownerId = baseClaim.ownerId,
			centerPosition = baseClaim.centerPosition,
			radius = baseClaim.radius,
			level = baseClaim.level,
		})
	end
	return result
end

--========================================
-- BuildService 연동: 첫 건물 설치 시 베이스 자동 생성
--========================================
function BaseClaimService.onStructurePlaced(userId: number, position: Vector3)
	-- 이미 베이스가 있으면 무시
	if bases[userId] then return end
	
	-- 베이스 자동 생성
	BaseClaimService.create(userId, position)
end

--========================================
-- Network Handlers
--========================================

local function handleGetBase(player: Player, payload: any)
	local baseClaim = BaseClaimService.getBase(player.UserId)
	
	if baseClaim then
		return {
			success = true,
			data = {
				id = baseClaim.id,
				centerPosition = baseClaim.centerPosition,
				radius = baseClaim.radius,
				level = baseClaim.level,
			}
		}
	else
		return { success = false, errorCode = Enums.ErrorCode.NOT_FOUND }
	end
end

local function handleExpand(player: Player, payload: any)
	local success, errorCode = BaseClaimService.expand(player.UserId)
	
	if success then
		return { success = true }
	else
		return { success = false, errorCode = errorCode }
	end
end

--========================================
-- Initialization
--========================================

function BaseClaimService.Init(netController: any, saveService: any, buildService: any)
	if initialized then return end
	
	NetController = netController
	SaveService = saveService
	BuildService = buildService
	
	-- 저장된 베이스 로드
	loadBases()
	
	initialized = true
	print("[BaseClaimService] Initialized")
end

function BaseClaimService.GetHandlers()
	return {
		["Base.Get.Request"] = handleGetBase,
		["Base.Expand.Request"] = handleExpand,
	}
end

return BaseClaimService
