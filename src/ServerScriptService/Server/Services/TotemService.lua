-- TotemService.lua
-- 거점 토템 유지비/보호효과 서비스

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)
local SpawnConfig = require(Shared.Config.SpawnConfig)

local TotemService = {}

local initialized = false
local NetController = nil
local SaveService = nil
local BaseClaimService = nil
local BuildService = nil
local NPCShopService = nil
local upkeepCache = {} -- [userId] = expiresAt (state 로드 지연 대비 런타임 캐시)
local expiryNotifiedAt = {} -- [ownerId] = expiresAt (같은 만료 시각 중복 알림 방지)

local ALLOWED_DURATIONS = {
	[1] = Balance.TOTEM_UPKEEP_COST_1D or 100,
	[3] = Balance.TOTEM_UPKEEP_COST_3D or 280,
	[7] = Balance.TOTEM_UPKEEP_COST_7D or 630,
}

local function getStarterZoneCenter(): Vector3?
	local spawnPart = workspace:FindFirstChild("SpawnLocation", true)
	if spawnPart then
		if spawnPart:IsA("BasePart") then
			return spawnPart.Position
		end
		if spawnPart:IsA("Model") then
			local ok, pivot = pcall(function()
				return spawnPart:GetPivot()
			end)
			if ok and pivot then
				return pivot.Position
			end
			if spawnPart.PrimaryPart then
				return spawnPart.PrimaryPart.Position
			end
		end
	end

	local configured = SpawnConfig and SpawnConfig.DEFAULT_START_SPAWN
	if typeof(configured) == "Vector3" then
		return configured
	end

	return nil
end

local function isInStarterProtectionZone(position: Vector3): boolean
	if typeof(position) ~= "Vector3" then
		return false
	end

	local center = getStarterZoneCenter()
	if not center then
		return false
	end

	local radius = Balance.STARTER_PROTECTION_RADIUS or 45
	local dx = position.X - center.X
	local dz = position.Z - center.Z
	return (dx * dx + dz * dz) <= (radius * radius)
end

local function getState(userId)
	local state = SaveService and SaveService.getPlayerState(userId)
	if type(state) ~= "table" then
		return nil
	end
	if type(state.totemUpkeep) ~= "table" then
		state.totemUpkeep = {
			expiresAt = 0,
			lastPaidAt = 0,
		}
	end
	state.totemUpkeep.expiresAt = tonumber(state.totemUpkeep.expiresAt) or 0
	state.totemUpkeep.lastPaidAt = tonumber(state.totemUpkeep.lastPaidAt) or 0
	upkeepCache[userId] = math.max(upkeepCache[userId] or 0, state.totemUpkeep.expiresAt)
	return state
end

local function getOwnerTotems(ownerId)
	if not BuildService or not BuildService.getAll then
		return {}
	end

	local result = {}
	local all = BuildService.getAll()
	for _, structure in ipairs(all) do
		if structure.ownerId == ownerId and structure.facilityId == "CAMP_TOTEM" then
			table.insert(result, structure)
		end
	end
	return result
end

local function getOwnerTotemStructure(ownerId)
	local totems = getOwnerTotems(ownerId)
	if #totems == 0 then
		return nil
	end
	if #totems == 1 then
		return totems[1]
	end

	local base = BaseClaimService and BaseClaimService.getBase and BaseClaimService.getBase(ownerId)
	if base and base.centerPosition then
		local best, bestScore = nil, math.huge
		for _, structure in ipairs(totems) do
			local pos = structure.position
			if typeof(pos) == "Vector3" then
				local dx = pos.X - base.centerPosition.X
				local dz = pos.Z - base.centerPosition.Z
				local score = (dx * dx) + (dz * dz)
				if score < bestScore then
					bestScore = score
					best = structure
				elseif score == bestScore and (tonumber(structure.placedAt) or 0) > (tonumber(best and best.placedAt) or 0) then
					best = structure
				end
			end
		end
		if best then
			return best
		end
	end

	table.sort(totems, function(a, b)
		return (tonumber(a.placedAt) or 0) > (tonumber(b.placedAt) or 0)
	end)
	return totems[1]
end

local function hasBase(userId)
	if not BaseClaimService or not BaseClaimService.getBase then
		return false
	end
	return BaseClaimService.getBase(userId) ~= nil
end

local function getExpiresAt(ownerId)
	local state = getState(ownerId)
	if state then
		return tonumber(state.totemUpkeep.expiresAt) or 0
	end
	return tonumber(upkeepCache[ownerId]) or 0
end

local function updateExpiresAt(ownerId, newExpiresAt)
	upkeepCache[ownerId] = tonumber(newExpiresAt) or 0

	if SaveService and SaveService.updatePlayerState then
		SaveService.updatePlayerState(ownerId, function(state)
			if type(state.totemUpkeep) ~= "table" then
				state.totemUpkeep = {}
			end
			state.totemUpkeep.expiresAt = newExpiresAt
			state.totemUpkeep.lastPaidAt = os.time()
			return state
		end)
	end
end

local function notifyUpkeepExpired(ownerId, expiresAt)
	if not NetController then
		return
	end

	local player = Players:GetPlayerByUserId(ownerId)
	if not player then
		return
	end

	local structure = getOwnerTotemStructure(ownerId)
	local structureId = structure and structure.id or nil

	NetController.FireClient(player, "Totem.Upkeep.Expired", {
		ownerId = ownerId,
		structureId = structureId,
		expiresAt = expiresAt,
		raidOpen = true,
	})

	if structure then
		local info = buildInfoPayload(ownerId, structure)
		if info then
			NetController.FireClient(player, "Totem.Upkeep.Changed", info)
		end
	end
end

local function runUpkeepWatcher()
	task.spawn(function()
		while initialized do
			if BaseClaimService and BaseClaimService.getAllBases then
				for _, base in ipairs(BaseClaimService.getAllBases()) do
					local ownerId = tonumber(base and base.ownerId)
					if ownerId then
						local totem = getOwnerTotemStructure(ownerId)
						if totem then
							local expiresAt = getExpiresAt(ownerId)
							local active = TotemService.isProtectionActiveForOwner(ownerId)

							if active then
								expiryNotifiedAt[ownerId] = nil
							elseif expiresAt > 0 and expiryNotifiedAt[ownerId] ~= expiresAt then
								expiryNotifiedAt[ownerId] = expiresAt
								notifyUpkeepExpired(ownerId, expiresAt)
							end
						end
					end
				end
			end

			task.wait(1)
		end
	end)
end

local function buildInfoPayload(requesterId, structure)
	local ownerId = structure and structure.ownerId
	if not ownerId then
		return nil
	end

	local base = BaseClaimService and BaseClaimService.getBase and BaseClaimService.getBase(ownerId)
	local expiresAt = getExpiresAt(ownerId)
	local now = os.time()
	local remaining = math.max(0, expiresAt - now)
	local active = remaining > 0

	return {
		structureId = structure.id,
		ownerId = ownerId,
		canManage = requesterId == ownerId,
		radius = (base and base.radius) or (Balance.BASE_DEFAULT_RADIUS or 30),
		centerPosition = base and base.centerPosition or structure.position,
		upkeep = {
			active = active,
			expiresAt = expiresAt,
			remainingSeconds = remaining,
			options = {
				{ days = 1, cost = ALLOWED_DURATIONS[1] },
				{ days = 3, cost = ALLOWED_DURATIONS[3] },
				{ days = 7, cost = ALLOWED_DURATIONS[7] },
			},
		},
		gold = NPCShopService and NPCShopService.getGold and NPCShopService.getGold(requesterId) or 0,
	}
end

function TotemService.isProtectionActiveForOwner(ownerId)
	if not ownerId then
		return false
	end
	if not hasBase(ownerId) then
		return false
	end
	if not getOwnerTotemStructure(ownerId) then
		return false
	end
	return getExpiresAt(ownerId) > os.time()
end

function TotemService.isProtectionActiveAt(position)
	return TotemService.getProtectionInfoAt(position) ~= nil
end

function TotemService.getProtectionInfoAt(position)
	if isInStarterProtectionZone(position) then
		local center = getStarterZoneCenter()
		if center then
			return {
				active = true,
				ownerId = 0,
				centerPosition = center,
				radius = Balance.STARTER_PROTECTION_RADIUS or 45,
			}
		end
	end

	if not BaseClaimService or not BaseClaimService.getOwnerAt then
		return nil
	end
	local ownerId = BaseClaimService.getOwnerAt(position)
	if not ownerId then
		return nil
	end
	if not TotemService.isProtectionActiveForOwner(ownerId) then
		return nil
	end
	local base = BaseClaimService.getBase and BaseClaimService.getBase(ownerId)
	if not base then
		return nil
	end
	return {
		active = true,
		ownerId = ownerId,
		centerPosition = base.centerPosition,
		radius = base.radius,
	}
end

function TotemService.isRaidOpenAt(position)
	if typeof(position) ~= "Vector3" then
		return false
	end
	if isInStarterProtectionZone(position) then
		return false
	end
	if not BaseClaimService or not BaseClaimService.getOwnerAt then
		return false
	end

	local zoneOwnerId = BaseClaimService.getOwnerAt(position)
	if not zoneOwnerId then
		return false
	end

	return not TotemService.isProtectionActiveForOwner(zoneOwnerId)
end

function TotemService.canRaidStructure(requesterUserId, structure)
	if type(structure) ~= "table" then
		return false
	end
	if requesterUserId and structure.ownerId == requesterUserId then
		return true
	end
	if typeof(structure.position) ~= "Vector3" then
		return false
	end
	return TotemService.isRaidOpenAt(structure.position)
end

function TotemService.onTotemPlaced(ownerId)
	if not ownerId then
		return
	end
	local expiresAt = getExpiresAt(ownerId)
	if expiresAt > os.time() then
		return
	end
	local grace = Balance.TOTEM_INITIAL_GRACE_SECONDS or (Balance.TOTEM_UPKEEP_DAY_SECONDS or 86400)
	updateExpiresAt(ownerId, os.time() + grace)
end

function TotemService.isBuildAllowed(userId, facilityId, position)
	if position and isInStarterProtectionZone(position) then
		return false, Enums.ErrorCode.STARTER_ZONE_PROTECTED
	end

	if facilityId == "CAMPFIRE" or facilityId == "CAMP_TOTEM" then
		if facilityId == "CAMP_TOTEM" then
			local hasAny = #getOwnerTotems(userId) > 0
			if hasAny then
				return false, Enums.ErrorCode.TOTEM_ALREADY_EXISTS
			end

			if BaseClaimService and BaseClaimService.getOwnerAt and position then
				local zoneOwnerId = BaseClaimService.getOwnerAt(position)
				if zoneOwnerId and zoneOwnerId ~= userId then
					return false, Enums.ErrorCode.TOTEM_ZONE_OCCUPIED
				end
			end
		end

		return true, nil
	end

	if not hasBase(userId) then
		return false, Enums.ErrorCode.TOTEM_REQUIRED
	end

	if not getOwnerTotemStructure(userId) then
		return false, Enums.ErrorCode.TOTEM_REQUIRED
	end

	if not TotemService.isProtectionActiveForOwner(userId) then
		return false, Enums.ErrorCode.TOTEM_UPKEEP_EXPIRED
	end

	return true, nil
end

local function handleGetInfo(player, payload)
	local structureId = payload and payload.structureId
	local structure = nil

	if structureId and BuildService and BuildService.get then
		structure = BuildService.get(structureId)
	end

	if not structure then
		structure = getOwnerTotemStructure(player.UserId)
	end

	if not structure or structure.facilityId ~= "CAMP_TOTEM" then
		return { success = false, errorCode = Enums.ErrorCode.TOTEM_NOT_FOUND }
	end

	local info = buildInfoPayload(player.UserId, structure)
	if not info then
		return { success = false, errorCode = Enums.ErrorCode.TOTEM_NOT_FOUND }
	end

	return { success = true, data = info }
end

local function handlePayUpkeep(player, payload)
	local structureId = payload and payload.structureId
	local days = tonumber(payload and payload.days)
	if not structureId or not days then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end

	if not ALLOWED_DURATIONS[days] then
		return { success = false, errorCode = Enums.ErrorCode.INVALID_COUNT }
	end

	local structure = BuildService and BuildService.get and BuildService.get(structureId)
	if not structure or structure.facilityId ~= "CAMP_TOTEM" then
		return { success = false, errorCode = Enums.ErrorCode.TOTEM_NOT_FOUND }
	end

	if structure.ownerId ~= player.UserId then
		return { success = false, errorCode = Enums.ErrorCode.TOTEM_NOT_OWNER }
	end

	local cost = ALLOWED_DURATIONS[days]
	local ok, err = NPCShopService.removeGold(player.UserId, cost)
	if not ok then
		return { success = false, errorCode = err or Enums.ErrorCode.INSUFFICIENT_GOLD }
	end

	local now = os.time()
	local currentExpires = getExpiresAt(player.UserId)
	local baseAt = math.max(now, currentExpires)
	local nextExpires = baseAt + (Balance.TOTEM_UPKEEP_DAY_SECONDS or 86400) * days
	updateExpiresAt(player.UserId, nextExpires)
	expiryNotifiedAt[player.UserId] = nil

	local info = buildInfoPayload(player.UserId, structure)
	if NetController then
		NetController.FireClient(player, "Totem.Upkeep.Changed", info)
	end

	return { success = true, data = info }
end

function TotemService.Init(netController, saveService, baseClaimService, buildService, npcShopService)
	if initialized then
		return
	end

	NetController = netController
	SaveService = saveService
	BaseClaimService = baseClaimService
	BuildService = buildService
	NPCShopService = npcShopService

	initialized = true
	runUpkeepWatcher()
	print("[TotemService] Initialized")
end

function TotemService.GetHandlers()
	return {
		["Totem.GetInfo.Request"] = handleGetInfo,
		["Totem.PayUpkeep.Request"] = handlePayUpkeep,
	}
end

return TotemService
