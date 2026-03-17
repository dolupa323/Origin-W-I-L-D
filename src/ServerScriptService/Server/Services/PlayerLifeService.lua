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
local playerDeathState = {} -- [userId] = { isDead, deathTime, respawnPoint, respawnPart }
local playerRespawnPreference = {} -- [userId] = { structureId = string }

--========================================
-- Internal Helpers
--========================================

local function toVector3(pos): Vector3?
	if typeof(pos) == "Vector3" then
		return pos
	end
	if type(pos) == "table" then
		return Vector3.new(pos.X or pos.x or 0, pos.Y or pos.y or 0, pos.Z or pos.z or 0)
	end
	return nil
end

local function loadRespawnPreferenceFromSave(userId: number)
	local ok, SaveService = pcall(function()
		return require(game:GetService("ServerScriptService").Server.Services.SaveService)
	end)
	if not ok or not SaveService or not SaveService.getPlayerState then
		return
	end

	for _ = 1, 10 do
		local state = SaveService.getPlayerState(userId)
		if state then
			if state.respawnStructureId then
				playerRespawnPreference[userId] = { structureId = state.respawnStructureId }
			end
			return
		end
		task.wait(0.5)
	end
end

--- 침대/침낭 리스폰 위치 찾기
local function findBedRespawnPoint(userId: number): Vector3?
	if not BuildService or not DataService then
		return nil
	end

	local function isRespawnFacility(facilityId: string?): boolean
		if not facilityId then
			return false
		end
		local facilityData = DataService.getFacility(facilityId)
		return facilityData and facilityData.functionType == "RESPAWN" or false
	end

	local preferred = playerRespawnPreference[userId]
	if preferred and preferred.structureId and BuildService.get then
		local struct = BuildService.get(preferred.structureId)
		if struct and struct.ownerId == userId and isRespawnFacility(struct.facilityId) then
			return toVector3(struct.position)
		end
	end

	-- 구조물 매칭 실패 시, 마지막 수면 좌표(lastPosition)를 우선 리스폰 기준점으로 사용.
	do
		local ok, SaveService = pcall(function()
			return require(game:GetService("ServerScriptService").Server.Services.SaveService)
		end)
		if ok and SaveService and SaveService.getPlayerState then
			local state = SaveService.getPlayerState(userId)
			if state and state.lastPosition then
				local pos = toVector3(state.lastPosition)
				if pos then
					return pos
				end
			end
		end
	end

	if BuildService.getStructuresByOwner then
		local owned = BuildService.getStructuresByOwner(userId)
		local latest = nil
		for _, struct in ipairs(owned) do
			if isRespawnFacility(struct.facilityId) then
				if (not latest) or ((struct.placedAt or 0) > (latest.placedAt or 0)) then
					latest = struct
				end
			end
		end
		if latest then
			return toVector3(latest.position)
		end
	end

	return nil
end

--- 인벤토리 아이템 랜덤 손실 처리
local function applyItemLoss(userId: number)
	local inv = InventoryService.getOrCreateInventory(userId)
	if not inv then return end

	-- [UX 개선] 1~8번 슬롯(단축키)은 보호하고 9번 이후(가방)만 손실 대상으로 분류
	local lossCandidateSlots = {}
	for slot, slotData in pairs(inv.slots) do
		if slotData and slotData.itemId and slot > 8 then
			table.insert(lossCandidateSlots, {
				slot = slot,
				itemId = slotData.itemId,
				count = slotData.count,
			})
		end
	end

	if #lossCandidateSlots == 0 then return end

	-- 손실 아이템 수 계산 (가방 아이템의 최대 30%)
	local lossCount = math.max(1, math.floor(#lossCandidateSlots * ITEM_LOSS_PERCENT))
	lossCount = math.min(lossCount, #lossCandidateSlots)

	-- 랜덤 셔플
	for i = #lossCandidateSlots, 2, -1 do
		local j = math.random(1, i)
		lossCandidateSlots[i], lossCandidateSlots[j] = lossCandidateSlots[j], lossCandidateSlots[i]
	end

	for i = 1, lossCount do
		local info = lossCandidateSlots[i]
		if info then
			InventoryService.removeItemFromSlot(userId, info.slot, info.count)
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

	Players.PlayerAdded:Connect(function(player)
		task.spawn(loadRespawnPreferenceFromSave, player.UserId)

		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid")
			humanoid.Died:Connect(function()
				PlayerLifeService._onPlayerDied(player)
			end)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(loadRespawnPreferenceFromSave, player.UserId)
		if player.Character then
			local humanoid = player.Character:FindFirstChild("Humanoid")
			if humanoid then
				humanoid.Died:Connect(function()
					PlayerLifeService._onPlayerDied(player)
				end)
			end
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		playerDeathState[player.UserId] = nil
		playerRespawnPreference[player.UserId] = nil
	end)

	print("[PlayerLifeService] Initialized")
end

--- 플레이어 사망 처리
function PlayerLifeService._onPlayerDied(player: Player)
	local userId = player.UserId

	if playerDeathState[userId] and playerDeathState[userId].isDead then
		return
	end

	print(string.format("[PlayerLifeService] Player %s (%d) died!", player.Name, userId))

	applyItemLoss(userId)

	local respawnTarget = findBedRespawnPoint(userId)
	playerDeathState[userId] = {
		isDead = true,
		deathTime = os.time(),
		respawnPoint = respawnTarget or DEFAULT_RESPAWN_POS,
		respawnPart = (typeof(respawnTarget) == "Instance") and respawnTarget or nil,
	}

	if NetController then
		NetController.FireClient(player, "Player.Died", {
			respawnDelay = RESPAWN_DELAY,
			respawnPoint = (typeof(respawnTarget) == "Instance") and respawnTarget.Position or (respawnTarget or DEFAULT_RESPAWN_POS),
		})
	end

	task.delay(RESPAWN_DELAY, function()
		if player.Parent then
			PlayerLifeService._respawnPlayer(player)
		end
	end)
end

--- 플레이어 리스폰
function PlayerLifeService._respawnPlayer(player: Player)
	local userId = player.UserId
	local state = playerDeathState[userId]
	if not state then return end

	if state.respawnPart and state.respawnPart:IsA("SpawnLocation") then
		player.RespawnLocation = state.respawnPart
	else
		player.RespawnLocation = nil
	end

	player:LoadCharacter()

	if not player.RespawnLocation then
		local respawnPoint = state.respawnPoint
		task.spawn(function()
			local character = player.Character or player.CharacterAdded:Wait()
			local hrp = character:WaitForChild("HumanoidRootPart", 5)
			if hrp then
				game:GetService("RunService").Stepped:Wait()
				character:PivotTo(CFrame.new(respawnPoint + Vector3.new(0, 3, 0)))
			end
		end)
	end

	playerDeathState[userId] = nil

	if NetController then
		NetController.FireClient(player, "Player.Respawned", {
			position = (state.respawnPart and state.respawnPart.Position) or state.respawnPoint,
		})
	end

	print(string.format("[PlayerLifeService] Player %s respawned", player.Name))
end

function PlayerLifeService.isDead(userId: number): boolean
	local state = playerDeathState[userId]
	return state ~= nil and state.isDead == true
end

function PlayerLifeService.setPreferredRespawn(userId: number, structureId: string)
	if not userId or not structureId or structureId == "" then
		return false
	end

	playerRespawnPreference[userId] = {
		structureId = structureId,
	}

	local ok, SaveService = pcall(function()
		return require(game:GetService("ServerScriptService").Server.Services.SaveService)
	end)
	if ok and SaveService and SaveService.updatePlayerState then
		SaveService.updatePlayerState(userId, function(state)
			state.respawnStructureId = structureId
			return state
		end)
	end

	return true
end

function PlayerLifeService.GetHandlers()
	return {}
end

return PlayerLifeService
