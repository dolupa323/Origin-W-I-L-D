-- PlayerLifeService.lua
-- Phase 4-2: 플레이어 생존 시스템 (사망, 리스폰, 아이템 손실)
-- Server-Authoritative

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)

local PlayerLifeService = {}

-- Dependencies
local NetController
local DataService
local InventoryService
local BuildService

-- Constants
local ITEM_LOSS_PERCENT = 0.3 -- 사망 시 인벤토리 아이템 30% 손실
local DEFAULT_RESPAWN_POS = Vector3.new(0, 50, 0) -- 기본 리스폰 위치
local RESPAWN_DELAY = 5 -- 리스폰까지 대기 시간(초)

-- Player State
local playerDeathState = {} -- [userId] = { isDead, deathTime, respawnPoint }

--========================================
-- Internal Helpers
--========================================

--- 침대/침낭 리스폰 위치 찾기
local function findBedRespawnPoint(userId: number): Vector3?
	-- BuildService에서 해당 플레이어가 소유한 RESPAWN 타입 구조물을 검색
	if not BuildService then return nil end
	
	-- BuildService.getPlayerStructures 가 있다면 사용
	-- 없으면 nil 반환 (기본 리스폰)
	-- 추후 BuildService에 getPlayerStructuresByType(userId, "RESPAWN") 추가 필요
	
	return nil -- Phase 4-2: 침대 건설 시스템 추후 구현
end

--- 인벤토리 아이템 랜덤 손실 처리
local function applyItemLoss(userId: number)
	local inv = InventoryService.getOrCreateInventory(userId)
	if not inv then return end
	
	-- 슬롯 데이터를 미리 캡처 (removeItem이 inv.slots를 변경하므로)
	local occupiedSlots = {}
	for slot, slotData in pairs(inv.slots) do
		if slotData and slotData.itemId then
			table.insert(occupiedSlots, {
				slot = slot,
				itemId = slotData.itemId,
				count = slotData.count,
			})
		end
	end
	
	if #occupiedSlots == 0 then return end
	
	-- 손실 아이템 수 계산 (최소 1개, 최대 전체의 30%)
	local lossCount = math.max(1, math.floor(#occupiedSlots * ITEM_LOSS_PERCENT))
	lossCount = math.min(lossCount, #occupiedSlots) -- 초과 방지
	
	-- 랜덤 셔플
	for i = #occupiedSlots, 2, -1 do
		local j = math.random(1, i)
		occupiedSlots[i], occupiedSlots[j] = occupiedSlots[j], occupiedSlots[i]
	end
	
	-- 앞에서부터 lossCount 만큼 제거
	for i = 1, lossCount do
		local info = occupiedSlots[i]
		if info then
			InventoryService.removeItem(userId, info.itemId, info.count)
			print(string.format("[PlayerLifeService] Death Loss: Player %d lost %s x%d from slot %d",
				userId, info.itemId, info.count, info.slot))
		end
	end
end

--========================================
-- Public API
--========================================

function PlayerLifeService.Init(_NetController, _DataService, _InventoryService, _BuildService)
	NetController = _NetController
	DataService = _DataService
	InventoryService = _InventoryService
	BuildService = _BuildService
	
	-- Humanoid.Died 이벤트 연결
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid")
			humanoid.Died:Connect(function()
				PlayerLifeService._onPlayerDied(player)
			end)
		end)
	end)
	
	-- 로그아웃 시 정리
	Players.PlayerRemoving:Connect(function(player)
		playerDeathState[player.UserId] = nil
	end)
	
	print("[PlayerLifeService] Initialized")
end

--- 플레이어 사망 처리
function PlayerLifeService._onPlayerDied(player: Player)
	local userId = player.UserId
	
	-- 중복 방지
	if playerDeathState[userId] and playerDeathState[userId].isDead then
		return
	end
	
	print(string.format("[PlayerLifeService] Player %s (%d) died!", player.Name, userId))
	
	-- 1. 아이템 손실 적용
	applyItemLoss(userId)
	
	-- 2. 사망 상태 기록
	local respawnPoint = findBedRespawnPoint(userId) or DEFAULT_RESPAWN_POS
	
	playerDeathState[userId] = {
		isDead = true,
		deathTime = os.time(),
		respawnPoint = respawnPoint,
	}
	
	-- 3. 클라이언트에 사망 알림 (UI 표시용)
	if NetController then
		NetController.FireClient(player, "Player.Died", {
			respawnDelay = RESPAWN_DELAY,
			respawnPoint = respawnPoint,
		})
	end
	
	-- 4. 일정 시간 후 리스폰
	task.delay(RESPAWN_DELAY, function()
		if player.Parent then -- 아직 접속 중인지 확인
			PlayerLifeService._respawnPlayer(player)
		end
	end)
end

--- 플레이어 리스폰
function PlayerLifeService._respawnPlayer(player: Player)
	local userId = player.UserId
	local state = playerDeathState[userId]
	
	if not state then return end
	
	local respawnPoint = state.respawnPoint or DEFAULT_RESPAWN_POS
	
	-- 캐릭터 다시 로드
	player:LoadCharacter()
	
	-- CharacterAdded를 기다려서 확실한 타이밍에 위치 설정
	task.spawn(function()
		local character = player.Character or player.CharacterAdded:Wait()
		local hrp = character:WaitForChild("HumanoidRootPart", 5)
		if hrp then
			hrp.CFrame = CFrame.new(respawnPoint)
		end
	end)
	
	-- 사망 상태 초기화
	playerDeathState[userId] = nil
	
	-- 클라이언트에 리스폰 알림
	if NetController then
		NetController.FireClient(player, "Player.Respawned", {
			position = respawnPoint,
		})
	end
	
	print(string.format("[PlayerLifeService] Player %s respawned at (%.0f, %.0f, %.0f)",
		player.Name, respawnPoint.X, respawnPoint.Y, respawnPoint.Z))
end

--- 사망 여부 확인
function PlayerLifeService.isDead(userId: number): boolean
	local state = playerDeathState[userId]
	return state ~= nil and state.isDead == true
end

--========================================
-- Network Handlers
--========================================

function PlayerLifeService.GetHandlers()
	return {
		-- 추후: 수동 리스폰 버튼, 침대 선택 등
	}
end

return PlayerLifeService
