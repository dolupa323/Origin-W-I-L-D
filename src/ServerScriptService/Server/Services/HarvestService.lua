-- HarvestService.lua
-- 자원 수확 시스템 (Phase 7-1)
-- 플레이어가 자원 노드(나무, 돌, 풀)에서 아이템 획득

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

local HarvestService = {}

--========================================
-- Dependencies (Init에서 주입)
--========================================
local initialized = false
local NetController = nil
local DataService = nil
local InventoryService = nil
local PlayerStatService = nil
local DurabilityService = nil
local WorldDropService = nil

--========================================
-- Internal State
--========================================
-- 활성 노드 상태 { [nodeUID] = { nodeId, remainingHits, depletedAt, position } }
local activeNodes = {}
local nodeCount = 0

-- 플레이어 쿨다운 { [userId] = lastHitTime }
local playerCooldowns = {}

-- 퀘스트 콜백 (Phase 8)
local questCallback = nil

--========================================
-- Internal Functions
--========================================

--- 고유 노드 ID 생성
local function generateNodeUID(): string
	nodeCount = nodeCount + 1
	return string.format("node_%d_%d", os.time(), nodeCount)
end

--- 도구 타입 검증
local function validateTool(player: Player, requiredTool: string?): (boolean, string?)
	if not requiredTool then
		-- 맨손 채집 가능
		return true, nil
	end
	
	-- TODO: EquipService에서 현재 장착 도구 확인
	-- 현재는 인벤토리에 해당 도구가 있으면 허용
	local userId = player.UserId
	
	-- 임시: 도구 타입 검증 스킵 (Phase 7-1 기본 구현)
	-- 실제 구현 시 EquipService.getEquippedItem() 연동 필요
	return true, nil
end

--- 드롭 아이템 계산
local function calculateDrops(nodeData: any): { {itemId: string, count: number} }
	local drops = {}
	
	for _, resource in ipairs(nodeData.resources) do
		-- weight 확률로 드롭 결정
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

--========================================
-- Public API: Node Management
--========================================

--- 자원 노드 등록 (맵 로드 시 호출)
function HarvestService.registerNode(nodeId: string, position: Vector3): string
	local nodeUID = generateNodeUID()
	local nodeData = DataService.getResourceNode(nodeId)
	
	if not nodeData then
		warn(string.format("[HarvestService] Unknown node: %s", nodeId))
		return nodeUID
	end
	
	activeNodes[nodeUID] = {
		nodeId = nodeId,
		remainingHits = nodeData.maxHits,
		depletedAt = nil,
		position = position,
	}
	
	-- 클라이언트에 노드 스폰 알림
	if NetController then
		NetController.FireAllClients("Harvest.Node.Spawned", {
			nodeUID = nodeUID,
			nodeId = nodeId,
			position = position,
		})
	end
	
	return nodeUID
end

--- 노드 상태 조회
function HarvestService.getNodeState(nodeUID: string): any?
	local state = activeNodes[nodeUID]
	if not state then return nil end
	
	return {
		nodeId = state.nodeId,
		remainingHits = state.remainingHits,
		isActive = state.depletedAt == nil,
		position = state.position,
	}
end

--- 모든 활성 노드 조회
function HarvestService.getAllNodes(): {any}
	local result = {}
	for nodeUID, state in pairs(activeNodes) do
		if state.depletedAt == nil then
			table.insert(result, {
				nodeUID = nodeUID,
				nodeId = state.nodeId,
				position = state.position,
				remainingHits = state.remainingHits,
			})
		end
	end
	return result
end

--========================================
-- Public API: Harvesting
--========================================

--- 자원 노드 타격 (플레이어 수동 채집)
function HarvestService.hit(player: Player, nodeUID: string): (boolean, string?, {any}?)
	local userId = player.UserId
	
	-- 1. 쿨다운 체크
	local now = tick()
	local cooldown = Balance.HARVEST_COOLDOWN or 0.5
	if playerCooldowns[userId] and (now - playerCooldowns[userId]) < cooldown then
		return false, Enums.ErrorCode.COOLDOWN, nil
	end
	playerCooldowns[userId] = now
	
	-- 2. 노드 존재 확인
	local nodeState = activeNodes[nodeUID]
	if not nodeState then
		return false, Enums.ErrorCode.NODE_NOT_FOUND, nil
	end
	
	-- 3. 노드 고갈 확인
	if nodeState.depletedAt then
		return false, Enums.ErrorCode.NODE_DEPLETED, nil
	end
	
	-- 4. 노드 데이터 조회
	local nodeData = DataService.getResourceNode(nodeState.nodeId)
	if not nodeData then
		return false, Enums.ErrorCode.NOT_FOUND, nil
	end
	
	-- 5. 거리 검증
	local character = player.Character
	if character then
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart then
			local distance = (humanoidRootPart.Position - nodeState.position).Magnitude
			local maxRange = Balance.HARVEST_RANGE or 5
			if distance > maxRange then
				return false, Enums.ErrorCode.OUT_OF_RANGE, nil
			end
		end
	end
	
	-- 6. 도구 검증
	local toolOk, toolError = validateTool(player, nodeData.requiredTool)
	if not toolOk then
		return false, toolError or Enums.ErrorCode.WRONG_TOOL, nil
	end
	
	-- 7. 타격 처리
	nodeState.remainingHits = nodeState.remainingHits - 1
	
	-- 8. 드롭 계산
	local drops = calculateDrops(nodeData)
	
	-- 9. 인벤토리에 추가 또는 월드 드롭
	for _, drop in ipairs(drops) do
		local added, remaining = InventoryService.addItem(userId, drop.itemId, drop.count)
		if remaining and remaining > 0 then
			-- 인벤토리 가득 참 → 월드 드롭
			if WorldDropService then
				local dropPosition = nodeState.position + Vector3.new(
					math.random(-2, 2),
					1,
					math.random(-2, 2)
				)
				WorldDropService.spawnDrop(dropPosition, drop.itemId, remaining)
			end
		end
	end
	
	-- 10. XP 보상
	if PlayerStatService then
		PlayerStatService.addXP(userId, nodeData.xpPerHit or Balance.HARVEST_XP_PER_HIT or 2, Enums.XPSource.HARVEST_RESOURCE)
	end
	
	-- 10.5 퀘스트 콜백 (Phase 8)
	if questCallback then
		questCallback(userId, nodeData.nodeType or nodeData.id)
	end
	
	-- 11. 도구 내구도 감소
	if DurabilityService and nodeData.requiredTool then
		-- TODO: 장착된 도구 내구도 감소
		-- DurabilityService.damage(userId, equippedSlot, 1)
	end
	
	-- 12. 노드 고갈 처리
	if nodeState.remainingHits <= 0 then
		nodeState.depletedAt = os.time()
		nodeState.respawnAt = os.time() + (nodeData.respawnTime or 300)
		
		-- 고갈 이벤트
		if NetController then
			NetController.FireAllClients("Harvest.Node.Depleted", {
				nodeUID = nodeUID,
			})
		end
		
		-- 리스폰 예약
		task.delay(nodeData.respawnTime or 300, function()
			HarvestService._respawnNode(nodeUID)
		end)
	end
	
	return true, nil, drops
end

--- 노드 리스폰 (내부)
function HarvestService._respawnNode(nodeUID: string)
	local nodeState = activeNodes[nodeUID]
	if not nodeState then return end
	
	local nodeData = DataService.getResourceNode(nodeState.nodeId)
	if not nodeData then return end
	
	-- 상태 초기화
	nodeState.remainingHits = nodeData.maxHits
	nodeState.depletedAt = nil
	nodeState.respawnAt = nil
	
	-- 리스폰 이벤트
	if NetController then
		NetController.FireAllClients("Harvest.Node.Spawned", {
			nodeUID = nodeUID,
			nodeId = nodeState.nodeId,
			position = nodeState.position,
		})
	end
	
	print(string.format("[HarvestService] Node respawned: %s (%s)", nodeUID, nodeState.nodeId))
end

--- 맨손 타격 가능 여부
function HarvestService.canHarvestBareHanded(nodeId: string): boolean
	local nodeData = DataService.getResourceNode(nodeId)
	if not nodeData then return false end
	return nodeData.requiredTool == nil
end

--========================================
-- Network Handlers
--========================================

local function handleHitRequest(player: Player, payload: any)
	local nodeUID = payload.nodeUID
	
	if not nodeUID then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local success, errorCode, drops = HarvestService.hit(player, nodeUID)
	
	if success then
		return { success = true, data = { drops = drops } }
	else
		return { success = false, errorCode = errorCode }
	end
end

local function handleGetNodesRequest(player: Player, payload: any)
	local nodes = HarvestService.getAllNodes()
	return { success = true, data = { nodes = nodes } }
end

--========================================
-- Initialization
--========================================

function HarvestService.Init(
	netController: any,
	dataService: any,
	inventoryService: any,
	playerStatService: any,
	durabilityService: any,
	worldDropService: any
)
	if initialized then return end
	
	NetController = netController
	DataService = dataService
	InventoryService = inventoryService
	PlayerStatService = playerStatService
	DurabilityService = durabilityService
	WorldDropService = worldDropService
	
	initialized = true
	print("[HarvestService] Initialized")
end

function HarvestService.GetHandlers()
	return {
		["Harvest.Hit.Request"] = handleHitRequest,
		["Harvest.GetNodes.Request"] = handleGetNodesRequest,
	}
end

--- 퀘스트 콜백 설정 (Phase 8)
function HarvestService.SetQuestCallback(callback)
	questCallback = callback
end

return HarvestService
