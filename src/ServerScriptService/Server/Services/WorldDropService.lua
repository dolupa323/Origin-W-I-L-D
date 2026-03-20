-- WorldDropService.lua
-- 월드 드롭 서비스 (서버 권위, SSOT)
-- Cap: Balance.DROP_CAP (400)
-- Merge: Balance.DROP_MERGE_RADIUS (5m)
-- Despawn: DEFAULT 300s, GATHER 600s
-- Inactive: Balance.DROP_INACTIVE_DIST (150m)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Enums = require(Shared.Enums.Enums)

local Server = ServerScriptService:WaitForChild("Server")
local Services = Server:WaitForChild("Services")

local WorldDropService = {}

--========================================
-- 4.1 Dependencies
--========================================
local initialized = false
local NetController = nil
local DataService = nil
local InventoryService = nil
local TimeService = nil
local PlayerStatService = nil -- DNA 수집을 위해 추가

--========================================
-- Private State
--========================================
-- drops[dropId] = { dropId, pos, itemId, count, spawnedAt, despawnAt, inactive }
local drops = {}
local dropCount = 0
local mergeGrid = {} -- ["gx_gz"] = { [dropId] = true }

-- Tick 누적
local tickAccumulator = 0
local TICK_INTERVAL = 1  -- 1초 주기

-- Merge grid helper forward declarations (Lua local scope ordering)
local GRID_SIZE = Balance.DROP_INACTIVE_DIST or 150
local getGridKey
local makeGridBucketKey
local indexDropForMerge
local unindexDropForMerge

--========================================
-- Internal: ID 생성
--========================================
local function generateDropId(): string
	return "drop_" .. HttpService:GenerateGUID(false)
end

--========================================
-- Internal: Despawn 시간 계산
--========================================
local function getDespawnSeconds(itemId: string): number
	local itemData = DataService.getItem(itemId)
	if itemData and itemData.dropDespawn == "GATHER" then
		return Balance.DROP_DESPAWN_GATHER
	end
	return Balance.DROP_DESPAWN_DEFAULT
end

--========================================
-- Internal: 이벤트 발행 (브로드캐스트)
--========================================
local function emitSpawned(drop: any)
	if NetController then
		-- 네트워크 최적화: 400 스터드 내 플레이어에게만 전송
		NetController.FireClientsInRange(drop.pos, 400, "WorldDrop.Spawned", {
			dropId = drop.dropId,
			pos = drop.pos,
			itemId = drop.itemId,
			count = drop.count,
			despawnAt = drop.despawnAt,
			inactive = drop.inactive,
		})
	end
end

local function emitChanged(dropId: string, count: number)
	if NetController then
		local drop = drops[dropId]
		if drop then
			NetController.FireClientsInRange(drop.pos, 400, "WorldDrop.Changed", {
				dropId = dropId,
				count = count,
			})
		end
	end
end

local function emitDespawned(dropId: string, reason: string)
	if NetController then
		local drop = drops[dropId]
		if drop then
			NetController.FireClientsInRange(drop.pos, 400, "WorldDrop.Despawned", {
				dropId = dropId,
				reason = reason,
			})
		end
	end
end

--========================================
-- Internal: 거리 계산
--========================================
local function distanceBetween(pos1: Vector3, pos2: Vector3): number
	return (pos1 - pos2).Magnitude
end

--========================================
-- Internal: 가장 가까운 플레이어 거리
--========================================
local function getNearestPlayerDistance(pos: Vector3): number
	local minDist = math.huge
	
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
			if humanoidRootPart then
				local dist = distanceBetween(pos, humanoidRootPart.Position)
				if dist < minDist then
					minDist = dist
				end
			end
		end
	end
	
	return minDist
end

--========================================
-- Internal: 병합 대상 찾기
--========================================
local function findMergeTarget(pos: Vector3, itemId: string): any?
	local radius = Balance.DROP_MERGE_RADIUS
	local baseGx, baseGz = getGridKey(pos)
	local gridRange = math.max(1, math.ceil(radius / GRID_SIZE))

	for x = -gridRange, gridRange do
		for z = -gridRange, gridRange do
			local key = makeGridBucketKey(baseGx + x, baseGz + z)
			local bucket = mergeGrid[key]
			if bucket then
				for dropId, _ in pairs(bucket) do
					local drop = drops[dropId]
					if drop and drop.itemId == itemId then
						local dist = distanceBetween(pos, drop.pos)
						if dist <= radius then
							return drop
						end
					end
				end
			end
		end
	end
	return nil
end

--========================================
-- Internal: Cap Prune (오래된 순 제거)
--========================================
local function pruneOldestDrops()
	while dropCount > Balance.DROP_CAP do
		-- spawnedAt 가장 오래된 것 찾기
		local oldest = nil
		local oldestTime = math.huge
		
		for _, drop in pairs(drops) do
			if drop.spawnedAt < oldestTime then
				oldestTime = drop.spawnedAt
				oldest = drop
			end
		end
		
		if oldest then
			emitDespawned(oldest.dropId, "CAP_PRUNE")
			unindexDropForMerge(oldest)
			drops[oldest.dropId] = nil
			dropCount = dropCount - 1
		else
			break
		end
	end
end


--================ : OPTIMIZATION : Spatial Grid ================
function getGridKey(pos: Vector3)
	return math.floor(pos.X / GRID_SIZE), math.floor(pos.Z / GRID_SIZE)
end

function makeGridBucketKey(gx: number, gz: number): string
	return string.format("%d_%d", gx, gz)
end

function indexDropForMerge(drop: any)
	local gx, gz = getGridKey(drop.pos)
	local key = makeGridBucketKey(gx, gz)
	if not mergeGrid[key] then
		mergeGrid[key] = {}
	end
	mergeGrid[key][drop.dropId] = true
	drop.gridKey = key
end

function unindexDropForMerge(drop: any)
	if not drop then
		return
	end

	local key = drop.gridKey
	if not key then
		local gx, gz = getGridKey(drop.pos)
		key = makeGridBucketKey(gx, gz)
	end

	local bucket = mergeGrid[key]
	if bucket then
		bucket[drop.dropId] = nil
		if next(bucket) == nil then
			mergeGrid[key] = nil
		end
	end
end

--========================================
-- Internal: Tick 처리 (1초마다)
--========================================
local function processTick()
	local now = tick()
	local toRemove = {}
	
	-- 1. 유저 위치 그리드 인덱싱 (O(P))
	local activeGrids = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local gx, gz = getGridKey(hrp.Position)
			-- 자신과 주변 8방향 그리드를 활성 상태로 표시
			for x = -1, 1 do
				for z = -1, 1 do
					activeGrids[string.format("%d_%d", gx + x, gz + z)] = true
				end
			end
		end
	end

	-- 2. 드롭 체크 (O(N))
	for dropId, drop in pairs(drops) do
		-- (1) Despawn 타이머 체크
		if now >= drop.despawnAt then
			table.insert(toRemove, { dropId = dropId, reason = "DESPAWN_TIMER" })
		else
			-- (2) Inactive 상태 갱신 (O(1) Grid Lookup)
			-- 유저 근처에 있으면 active, 없으면 inactive
			local gx, gz = getGridKey(drop.pos)
			local key = string.format("%d_%d", gx, gz)
			
			drop.inactive = not activeGrids[key]
		end
	end
	
	-- 제거 처리
	for _, item in ipairs(toRemove) do
		local drop = drops[item.dropId]
		if drop then
			emitDespawned(item.dropId, item.reason)
			unindexDropForMerge(drop)
			drops[item.dropId] = nil
			dropCount = dropCount - 1
		end
	end
	
	-- 3. Cap Prune (오래된 순 제거)
	if dropCount > Balance.DROP_CAP then
		pruneOldestDrops()
	end
end

--========================================
-- Heartbeat 핸들러
--========================================
local function onHeartbeat(dt: number)
	tickAccumulator = tickAccumulator + dt
	
	if tickAccumulator >= TICK_INTERVAL then
		tickAccumulator = tickAccumulator - TICK_INTERVAL
		processTick()
	end
end

--========================================
-- 4.2 Public API
--========================================

--- 드롭 생성
--- 반환: (success, errorCode?, data?)
function WorldDropService.spawnDrop(pos: Vector3, itemId: string, count: number, durability: number?): (boolean, string?, any?)
	-- 아이템 존재 검증
	local itemData = DataService.getItem(itemId)
	if not itemData then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- count 검증
	if type(count) ~= "number" or count < 1 or count ~= math.floor(count) then
		return false, Enums.ErrorCode.INVALID_COUNT, nil
	end
	
	-- 병합 대상 찾기 (내구도가 있는 아이템은 병합 제외)
	local mergeTarget = nil
	if not durability then
		mergeTarget = findMergeTarget(pos, itemId)
	end
	
	if mergeTarget then
		-- 병합
		mergeTarget.count = mergeTarget.count + count
		emitChanged(mergeTarget.dropId, mergeTarget.count)
		return true, nil, { merged = true, dropId = mergeTarget.dropId, count = mergeTarget.count }
	end
	
	-- 새 드롭 생성
	local now = tick()
	local despawnSeconds = getDespawnSeconds(itemId)
	
	local drop = {
		dropId = generateDropId(),
		pos = pos,
		itemId = itemId,
		count = count,
		durability = durability, -- 내구도 보존
		spawnedAt = now,
		despawnAt = now + despawnSeconds,
		inactive = false,
	}
	
	drops[drop.dropId] = drop
	dropCount = dropCount + 1
	indexDropForMerge(drop)
	
	-- Cap 초과 시 prune
	if dropCount > Balance.DROP_CAP then
		pruneOldestDrops()
	end
	
	emitSpawned(drop)
	
	return true, nil, { merged = false, dropId = drop.dropId, count = drop.count }
end

--- Loot (아이템 줍기)
--- 반환: (success, errorCode?, data?)
function WorldDropService.loot(player: Player, dropId: string): (boolean, string?, any?)
	local userId = player.UserId
	
	-- 드롭 존재 확인
	local drop = drops[dropId]
	if not drop then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- 거리 확인
	local character = player.Character
	if not character then
		return false, Enums.ErrorCode.INVALID_STATE, nil
	end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return false, Enums.ErrorCode.INVALID_STATE, nil
	end
	
	local dist = distanceBetween(drop.pos, humanoidRootPart.Position)
	
	if dist > Balance.DROP_LOOT_RANGE then
		return false, Enums.ErrorCode.OUT_OF_RANGE, nil
	end
	
	-- DNA 타입 아이템: 인벤토리에 추가 + 특별 알림
	local itemData = DataService.getItem(drop.itemId)
	if itemData and itemData.type == "DNA" then
		local added, remaining = InventoryService.addItem(userId, drop.itemId, drop.count, drop.durability)
		if added <= 0 then
			return false, Enums.ErrorCode.INV_FULL, nil
		end
		
		-- DNA 획득 특별 알림 (클라이언트에서 대형 연출)
		if NetController then
			NetController.FireClient(player, "DNA.Obtained", {
				itemId = drop.itemId,
				creatureId = itemData.creatureId,
				count = added,
				rarity = itemData.rarity,
			})
		end
		
		if remaining > 0 then
			drop.count = remaining
			emitChanged(dropId, remaining)
		else
			emitDespawned(dropId, "LOOTED_OUT")
			unindexDropForMerge(drop)
			drops[dropId] = nil
			dropCount = dropCount - 1
		end
		
		return true, nil, {
			dropId = dropId,
			itemId = drop.itemId,
			count = added,
			remaining = remaining or 0,
			isDna = true,
		}
	end

	-- 일반 아이템: 인벤토리에 추가
	local added, remaining = InventoryService.addItem(userId, drop.itemId, drop.count, drop.durability)
	
	if added <= 0 then
		return false, Enums.ErrorCode.INV_FULL, nil
	end

	if remaining > 0 then
		-- 부분 줍기: 드롭 잔량 업데이트
		drop.count = remaining
		emitChanged(dropId, remaining)
	else
		-- 전량 줍기: 드롭 제거
		emitDespawned(dropId, "LOOTED_OUT")
		unindexDropForMerge(drop)
		drops[dropId] = nil
		dropCount = dropCount - 1
	end
	
	return true, nil, {
		dropId = dropId,
		itemId = drop.itemId,
		count = added,
		remaining = remaining,
	}
end

--- 모든 드롭 제거 (디버그/테스트용)
function WorldDropService.clearAllDrops()
	for dropId, _ in pairs(drops) do
		emitDespawned(dropId, "CLEARED")
	end
	drops = {}
	dropCount = 0
	mergeGrid = {}
end

--- 현재 드롭 수
function WorldDropService.getDropCount(): number
	return dropCount
end

--- 드롭 가져오기 (디버그용)
function WorldDropService.getDrop(dropId: string): any?
	return drops[dropId]
end

--- 모든 드롭 가져오기 (디버그용)
function WorldDropService.getAllDrops(): {any}
	local result = {}
	for _, drop in pairs(drops) do
		table.insert(result, drop)
	end
	return result
end

--========================================
-- 4.3 Debug API (Studio Only)
--========================================

--- 대량 스폰 테스트
function WorldDropService.DebugSpawnMany(itemId: string, countPerDrop: number, numDrops: number)
	for i = 1, numDrops do
		local pos = Vector3.new(
			math.random(-100, 100),
			5,
			math.random(-100, 100)
		)
		WorldDropService.spawnDrop(pos, itemId, countPerDrop)
	end
end

--- 병합 테스트 (같은 위치에 여러 번 스폰)
function WorldDropService.DebugMergeTest(itemId: string, countPerDrop: number, numDrops: number)
	local pos = Vector3.new(0, 5, 0)  -- 고정 위치
	for i = 1, numDrops do
		WorldDropService.spawnDrop(pos, itemId, countPerDrop)
	end
end

--========================================
-- Network Handlers
--========================================

local function handleLoot(player: Player, payload: any)
	local dropId = payload.dropId
	
	if type(dropId) ~= "string" then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local success, errorCode, data = WorldDropService.loot(player, dropId)
	
	if not success then
		return { success = false, errorCode = errorCode }
	end
	return { success = true, data = data }
end

--========================================
-- Initialization
--========================================

function WorldDropService.Init(netController: any, dataService: any, inventoryService: any, timeService: any, _PlayerStatService: any)
	if initialized then
		warn("[WorldDropService] Already initialized")
		return
	end
	
	NetController = netController
	DataService = dataService
	InventoryService = inventoryService
	TimeService = timeService
	PlayerStatService = _PlayerStatService
	
	-- Heartbeat 연결
	RunService.Heartbeat:Connect(onHeartbeat)
	
	initialized = true
	print(string.format("[WorldDropService] Initialized - Cap: %d, MergeRadius: %d, InactiveDist: %d",
		Balance.DROP_CAP, Balance.DROP_MERGE_RADIUS, Balance.DROP_INACTIVE_DIST))
end

function WorldDropService.GetHandlers()
	return {
		["WorldDrop.Loot.Request"] = handleLoot,
	}
end

return WorldDropService
