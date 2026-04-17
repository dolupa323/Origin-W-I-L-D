-- PortalService.lua
-- 고대 포탈 시스템 (Ancient Portal) — 허브-스포크 모델
-- 초원섬(허브)에 섬별 고대포탈, 각 섬에 귀환 포탈
-- 이동 경로: 초원섬 ↔ 개별 섬 (섬끼리 직접 이동 불가)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local SpawnConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("SpawnConfig"))
local Balance = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Balance"))

local PortalService = {}
local initialized = false

-- Dependencies (injected via Init)
local NetController
local NPCShopService
local SaveService
local InventoryService
local HarvestService
local CreatureService

--========================================
-- Configuration
--========================================
local HUB_ZONE = SpawnConfig.HUB_ZONE or "GRASSLAND"

-- 포탈 정의 (섬 추가 시 여기에 항목 추가)
local PORTAL_DEFINITIONS = {
	{
		id = "TROPICAL",                            -- 고유 ID (저장 키)
		displayName = "열대섬 고대 포탈",            -- UI 표시명
		destinationName = "열대섬",                  -- 이동 목적지 이름
		portalName = "Portal_Tropical",             -- 초원섬의 출발 포탈 (workspace 오브젝트명)
		returnPortalName = "Portal_Return_Tropical",-- 열대섬의 귀환 포탈 (workspace 오브젝트명)
		targetZone = "TROPICAL",                    -- 이동 대상 Zone
		repairGold = 30,                            -- [수정] 열대섬 30골드로 변경
	},
	{
		id = "DESERT",
		displayName = "사막섬 고대 포탈",
		destinationName = "사막섬",
		portalName = "Portal_Desert",
		returnPortalName = "Portal_Return_Desert",
		targetZone = "DESERT",
		repairGold = 2500,
	},
	{
		id = "SNOWY",
		displayName = "설원섬 고대 포탈",
		destinationName = "설원섬",
		portalName = "Portal_Snowy",
		returnPortalName = "Portal_Return_Snowy",
		targetZone = "SNOWY",
		repairGold = 10000,
	},
}

local PROMPT_DISTANCE = 14
local PORTAL_USE_DISTANCE = 26
local DEBOUNCE_COOLDOWN = 3

local debounces = {}             -- [userId] = tick()
local portalLookup = {}          -- [portalId] = definition
local activeInteractions = {}    -- [userId] = { portalId, isReturn }

-- 포탈 정의 룩업 테이블 구축
for _, def in ipairs(PORTAL_DEFINITIONS) do
	portalLookup[def.id] = def
end

--========================================
-- Save State Helpers (per-portal)
--========================================

--- 레거시 저장 데이터 마이그레이션 (portalRepaired → portals.TROPICAL)
local function _migrateOldPortalState(state)
	if state.portalRepaired ~= nil and not state.portals then
		state.portals = {
			TROPICAL = {
				repaired = state.portalRepaired == true,
				currentGold = type(state.portalProgress) == "table" and state.portalProgress.GOLD or 0,
			},
		}
		state.portalRepaired = nil
		state.portalProgress = nil
	end
	if not state.portals then
		state.portals = {}
	end
	return state.portals
end

local function _getPortalState(userId, portalId)
	local state = SaveService and SaveService.getPlayerState(userId)
	if not state then return { repaired = false, currentGold = 0 } end
	local portals = _migrateOldPortalState(state)
	if not portals[portalId] then
		portals[portalId] = { repaired = false, currentGold = 0 }
	end
	return portals[portalId]
end

local function _isPortalRepaired(userId, portalId)
	return _getPortalState(userId, portalId).repaired == true
end

local function _markPortalRepaired(userId, portalId)
	if not SaveService then return end
	local def = portalLookup[portalId]
	if not def then return end
	SaveService.updatePlayerState(userId, function(state)
		local portals = _migrateOldPortalState(state)
		if not portals[portalId] then portals[portalId] = {} end
		portals[portalId].repaired = true
		portals[portalId].currentGold = def.repairGold
		return state
	end)
end

local function _getPortalStatus(userId, portalId)
	local def = portalLookup[portalId]
	if not def then return { repaired = false, currentGold = 0, requiredGold = 0 } end

	local portalState = _getPortalState(userId, portalId)
	local repaired = portalState.repaired == true -- [중요] repaired 상태 체크
	local currentGold = tonumber(portalState.currentGold) or 0
	local requiredGold = def.repairGold

	if currentGold >= requiredGold and not repaired then
		_markPortalRepaired(userId, portalId)
		repaired = true
	end

	return {
		portalId = portalId,
		displayName = def.displayName,
		destinationName = def.destinationName,
		portalName = def.portalName,
		returnPortalName = def.returnPortalName,
		repaired = repaired,
		currentGold = currentGold,
		requiredGold = requiredGold,
		isReturn = false,
	}
end

--========================================
-- Portal Object Helpers
--========================================

local function _getPortalObject(objectName)
	if not objectName or objectName == "" then return nil end
	-- 1. 최상위 Workspace 우선 검색
	local obj = workspace:FindFirstChild(objectName)
	if obj then return obj end

	-- 2. 하위 폴더/모델 내 재귀 검색 (StreamingEnabled 환경 대응)
	for _, folder in ipairs(workspace:GetChildren()) do
		if folder:IsA("Folder") or folder:IsA("Model") then
			local sub = folder:FindFirstChild(objectName, true)
			if sub then return sub end
		end
	end
	return nil
end

local function _getArrivalPortalBasePart(portalObject)
	if not portalObject then
		return nil
	end

	if portalObject:IsA("BasePart") then
		return portalObject
	end

	if portalObject:IsA("Model") then
		local preferred = portalObject:FindFirstChild("TeleportAnchor", true)
			or portalObject:FindFirstChild("TeleportPoint", true)
			or portalObject.PrimaryPart
		if preferred and preferred:IsA("BasePart") then
			return preferred
		end
		return portalObject:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

local function _resolveArrivalPosition(zoneInfo, arrivalPortal, character)
	local defaultArrival = zoneInfo.spawnPoint + Vector3.new(0, 5, 0)
	local excludeList = { character }
	local zoneCenter = zoneInfo.center or zoneInfo.spawnPoint
	local zoneRadius = tonumber(zoneInfo.radius) or 0

	if arrivalPortal then
		table.insert(excludeList, arrivalPortal)
	end

	local function projectToSafeGround(candidatePos)
		local rayParams = RaycastParams.new()
		local includeList = { workspace.Terrain }
		local map = workspace:FindFirstChild("Map")
		if map then
			table.insert(includeList, map)
		end
		rayParams.FilterDescendantsInstances = includeList
		rayParams.FilterType = Enum.RaycastFilterType.Include

		local rayOrigin = candidatePos + Vector3.new(0, 80, 0)
		local rayDir = Vector3.new(0, -500, 0)
		local rayResult = workspace:Raycast(rayOrigin, rayDir, rayParams)
		if rayResult and rayResult.Material ~= Enum.Material.Water then
			local minSafeY = math.min(defaultArrival.Y, zoneCenter.Y + 5) - 40
			if rayResult.Position.Y >= minSafeY then
				return rayResult.Position + Vector3.new(0, 8, 0), true
			end
		end
		return candidatePos, false
	end

	local function scanSafeGround(originPos)
		local radialSamples = {
			Vector3.new(0, 0, 0),
			Vector3.new(10, 0, 0),
			Vector3.new(-10, 0, 0),
			Vector3.new(0, 0, 10),
			Vector3.new(0, 0, -10),
			Vector3.new(18, 0, 18),
			Vector3.new(-18, 0, 18),
			Vector3.new(18, 0, -18),
			Vector3.new(-18, 0, -18),
			Vector3.new(28, 0, 0),
			Vector3.new(-28, 0, 0),
			Vector3.new(0, 0, 28),
			Vector3.new(0, 0, -28),
		}

		for _, offset in ipairs(radialSamples) do
			local samplePos = originPos + offset
			local flatDistance = (Vector2.new(samplePos.X, samplePos.Z) - Vector2.new(zoneCenter.X, zoneCenter.Z)).Magnitude
			if zoneRadius <= 0 or flatDistance <= zoneRadius + 120 then
				local groundedPos, ok = projectToSafeGround(samplePos)
				if ok then
					return groundedPos, true
				end
			end
		end

		return originPos, false
	end

		local portalBasePart = _getArrivalPortalBasePart(arrivalPortal)
	if portalBasePart then
		local candidatePos = portalBasePart.Position + portalBasePart.CFrame.LookVector * 14 + Vector3.new(0, math.max(8, portalBasePart.Size.Y * 0.5 + 6), 0)
		local flatDistance = (Vector2.new(candidatePos.X, candidatePos.Z) - Vector2.new(zoneCenter.X, zoneCenter.Z)).Magnitude
		local minSafeY = (Balance.SEA_LEVEL or 0) - 5
		if (zoneRadius <= 0 or flatDistance <= zoneRadius + 120) and candidatePos.Y >= minSafeY then
			local groundedPos, ok = scanSafeGround(candidatePos)
			if ok then
				return groundedPos
			end
		else
			warn(string.format("[PortalService] Arrival portal '%s' base position rejected, fallback to spawnPoint", tostring(arrivalPortal.Name)))
		end
	end

	local groundedDefault, ok = scanSafeGround(defaultArrival)
	if ok then
		return groundedDefault
	end

	return defaultArrival
end

local function _distanceToPortalSurface(player, portalObject)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not portalObject then return math.huge end

	if portalObject:IsA("BasePart") then
		local p = hrp.Position
		local localPos = portalObject.CFrame:PointToObjectSpace(p)
		local half = portalObject.Size * 0.5
		local clamped = Vector3.new(
			math.clamp(localPos.X, -half.X, half.X),
			math.clamp(localPos.Y, -half.Y, half.Y),
			math.clamp(localPos.Z, -half.Z, half.Z)
		)
		local worldClosest = portalObject.CFrame:PointToWorldSpace(clamped)
		return (p - worldClosest).Magnitude
	end

	if portalObject:IsA("Model") then
		local p = hrp.Position
		local minDist = math.huge
		for _, d in ipairs(portalObject:GetDescendants()) do
			if d:IsA("BasePart") then
				local localPos = d.CFrame:PointToObjectSpace(p)
				local half = d.Size * 0.5
				local clamped = Vector3.new(
					math.clamp(localPos.X, -half.X, half.X),
					math.clamp(localPos.Y, -half.Y, half.Y),
					math.clamp(localPos.Z, -half.Z, half.Z)
				)
				local worldClosest = d.CFrame:PointToWorldSpace(clamped)
				local dist = (p - worldClosest).Magnitude
				if dist < minDist then
					minDist = dist
				end
			end
		end
		return minDist
	end

	return math.huge
end

local function _isPlayerNearPortal(player, objectName)
	local portalObject = _getPortalObject(objectName)
	if not portalObject then return false end
	return _distanceToPortalSurface(player, portalObject) <= PORTAL_USE_DISTANCE
end

--========================================
-- Deposit Material (per-portal)
--========================================

local function _depositPortalMaterial(player, payload)
	local userId = player.UserId
	local interaction = activeInteractions[userId]
	local portalId = (payload and payload.portalId) or (interaction and interaction.portalId)
	if not portalId then
		return { success = false, errorCode = "BAD_REQUEST" }
	end

	local def = portalLookup[portalId]
	if not def then
		return { success = false, errorCode = "BAD_REQUEST" }
	end

	if not _isPlayerNearPortal(player, def.portalName) then
		return { success = false, errorCode = "OUT_OF_RANGE" }
	end

	if _isPortalRepaired(userId, portalId) then
		return { success = true, data = _getPortalStatus(userId, portalId) }
	end

	return { success = false, errorCode = "RETIRED_METHOD" } -- 구식 재료 투입 방식은 비활성화
end

	--========================================
-- Deposit Gold (per-portal)
--========================================

local function _depositPortalGold(player, payload)
	local userId = player.UserId
	local interaction = activeInteractions[userId]
	local portalId = (payload and payload.portalId) or (interaction and interaction.portalId)
	if not portalId then
		return { success = false, errorCode = "BAD_REQUEST" }
	end

	local def = portalLookup[portalId]
	if not def then
		return { success = false, errorCode = "BAD_REQUEST" }
	end

	if not _isPlayerNearPortal(player, def.portalName) then
		return { success = false, errorCode = "OUT_OF_RANGE" }
	end

	if _isPortalRepaired(userId, portalId) then
		return { success = true, data = _getPortalStatus(userId, portalId) }
	end

	local amount = tonumber(payload and payload.amount) or 0
	if amount <= 0 then
		return { success = false, errorCode = "BAD_REQUEST" }
	end

	local portalState = _getPortalState(userId, portalId)
	local currentGold = tonumber(portalState.currentGold) or 0
	local need = def.repairGold - currentGold

	if need <= 0 then
		return { success = true, data = _getPortalStatus(userId, portalId) }
	end

	local depositAmount = math.min(need, amount)

	-- NPCShopService를 통한 골드 차감
	local ok, err = NPCShopService.removeGold(userId, depositAmount)
	if not ok then
		return { success = false, errorCode = "INSUFFICIENT_GOLD", data = _getPortalStatus(userId, portalId) }
	end

	SaveService.updatePlayerState(userId, function(s)
		local p = _migrateOldPortalState(s)
		if not p[portalId] then p[portalId] = { repaired = false, currentGold = 0 } end
		p[portalId].currentGold = (tonumber(p[portalId].currentGold) or 0) + depositAmount
		if p[portalId].currentGold >= def.repairGold then
			p[portalId].repaired = true
		end
		return s
	end)

	if SaveService and SaveService.savePlayer then
		SaveService.savePlayer(userId)
	end

	local status = _getPortalStatus(userId, portalId)
	if status.repaired then
		NetController.FireClient(player, "Portal.Repaired", { portalId = portalId })
	end

	return { success = true, data = status }
end

--========================================
-- Teleportation
--========================================

local function _requestPortalTeleport(player, payload)
	local userId = player.UserId
	local interaction = activeInteractions[userId]
	local portalId = (payload and payload.portalId) or (interaction and interaction.portalId)
	local isReturn = interaction and interaction.isReturn or false

	if not portalId then
		return { success = false, errorCode = "BAD_REQUEST" }
	end

	local def = portalLookup[portalId]
	if not def then
		return { success = false, errorCode = "BAD_REQUEST" }
	end

	-- 근접 체크 (출발/귀환 여부에 따라 다른 오브젝트)
	local portalObjectName = isReturn and def.returnPortalName or def.portalName
	if not _isPlayerNearPortal(player, portalObjectName) then
		return { success = false, errorCode = "OUT_OF_RANGE" }
	end

	-- 출발 포탈은 수리 필요, 귀환 포탈은 수리 불필요
	if not isReturn and not _isPortalRepaired(userId, portalId) then
		return { success = false, errorCode = "INVALID_STATE" }
	end

	-- 목적지 Zone 결정: 출발=대상섬, 귀환=초원섬
	local targetZoneName = isReturn and HUB_ZONE or def.targetZone
	local zoneInfo = SpawnConfig.GetZoneInfo(targetZoneName)
	if not zoneInfo or not zoneInfo.spawnPoint then
		warn("[PortalService] Zone not found:", targetZoneName)
		return { success = false, errorCode = "INVALID_STATE" }
	end

	-- 도착 포탈 이름 (실제 좌표는 SpawnZone 완료 후 계산)
	local arrivalPortalName = isReturn and def.portalName or def.returnPortalName

	local destName = isReturn and "초원섬" or def.destinationName
	NetController.FireClient(player, "Portal.Teleporting", {
		portalId = portalId,
		destination = destName,
	})

	-- 비동기로 SpawnZone + 텔레포트 처리 (RemoteFunction 블로킹 방지)
	-- ★ task.defer: 호출자(handler)가 먼저 return한 뒤 다음 프레임에 실행
	-- task.spawn은 내부가 yield하기 전까지 호출자를 블로킹하므로 사용 금지
	task.defer(function()
		if HarvestService and HarvestService.SpawnZone then
			HarvestService.SpawnZone(targetZoneName)
		end
		if CreatureService and CreatureService.SpawnZone then
			CreatureService.SpawnZone(targetZoneName)
		end
		task.wait(1.5) -- 클라이언트 페이드 완료 대기

		local okParty, PartyService = pcall(function()
			return require(game:GetService("ServerScriptService").Server.Services.PartyService)
		end)
		local okDebuff, DebuffService = pcall(function()
			return require(game:GetService("ServerScriptService").Server.Services.DebuffService)
		end)
		if okParty and PartyService and PartyService.getSummon then
			local summon = PartyService.getSummon(userId)
			if summon then
				if summon.isMounted and PartyService.dismount then
					pcall(function()
						PartyService.dismount(userId, false)
					end)
				end
				if PartyService._recallPal then
					pcall(function()
						PartyService._recallPal(userId)
					end)
				end
			end
		end

		local saveOk = SaveService.savePlayer(userId)
		if not saveOk then
			NetController.FireClient(player, "Portal.Error", { message = "데이터 저장 실패" })
			return
		end

		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not hrp then
			NetController.FireClient(player, "Portal.Error", { message = "캐릭터를 찾을 수 없습니다" })
			return
		end

		local arrivalPortal = _getPortalObject(arrivalPortalName)
		local arrivalPos = _resolveArrivalPosition(zoneInfo, arrivalPortal, character)

		if okDebuff and DebuffService and DebuffService.removeDebuff then
			pcall(function()
				DebuffService.removeDebuff(userId, "CHILLY")
				DebuffService.removeDebuff(userId, "FREEZING")
				DebuffService.removeDebuff(userId, "WARMTH")
			end)
		end
		player:SetAttribute("PortalSafeUntil", os.clock() + 12)
		player:SetAttribute("SpawnPosX", arrivalPos.X)
		player:SetAttribute("SpawnPosY", arrivalPos.Y)
		player:SetAttribute("SpawnPosZ", arrivalPos.Z)
		player:SetAttribute("DataLoaded", true)

		-- 포탈 이동은 기존 캐릭터를 직접 순간이동하지 않고,
		-- 접속/리스폰과 동일한 SpawnPos + LoadCharacter 파이프라인을 사용한다.
		pcall(function()
			player:RequestStreamAroundAsync(arrivalPos, 5)
		end)

		player:LoadCharacter()

		local charStart = tick()
		while player.Parent and (tick() - charStart) < 10 do
			local newCharacter = player.Character
			local newRoot = newCharacter and newCharacter:FindFirstChild("HumanoidRootPart")
			if newCharacter and newRoot then
				local ff = Instance.new("ForceField")
				ff.Visible = false
				ff.Parent = newCharacter
				task.delay(12, function()
					if ff and ff.Parent then ff:Destroy() end
					if player.Parent then
						local safeUntil = tonumber(player:GetAttribute("PortalSafeUntil"))
						if safeUntil and safeUntil <= os.clock() then
							player:SetAttribute("PortalSafeUntil", nil)
						end
					end
				end)
				break
			end
			task.wait(0.05)
		end

		NetController.FireClient(player, "Portal.Arrived", { zone = targetZoneName, portalId = portalId })
		print(string.format("[PortalService] %s warped to '%s' via portal '%s'%s (pos=%.0f,%.0f,%.0f)",
			player.Name, targetZoneName, portalId, isReturn and " (return)" or "",
			arrivalPos.X, arrivalPos.Y, arrivalPos.Z))
	end)

	return { success = true, data = { teleporting = true, zone = targetZoneName } }
end

--========================================
-- Portal Interaction (Triggered)
--========================================

local function _onPortalTriggered(player, portalId, isReturn)
	local userId = player.UserId

	if debounces[userId] and (tick() - debounces[userId]) < DEBOUNCE_COOLDOWN then
		return
	end
	debounces[userId] = tick()

	local def = portalLookup[portalId]
	if not def then return end

	local portalObjectName = isReturn and def.returnPortalName or def.portalName
	if not _isPlayerNearPortal(player, portalObjectName) then
		return
	end

	-- 현재 상호작용 중인 포탈 기록
	activeInteractions[userId] = { portalId = portalId, isReturn = isReturn }

	if isReturn then
		-- 귀환 포탈: 즉시 이동 UI (재료 불필요)
		NetController.FireClient(player, "Portal.UI.Open", {
			portalId = portalId,
			repaired = true,
			displayName = "초원섬 귀환",
			destinationName = "초원섬",
			portalName = def.portalName,
			returnPortalName = def.returnPortalName,
			isReturn = true,
		})
	else
		-- 출발 포탈: 수리 상태 반영
		local status = _getPortalStatus(userId, portalId)
		NetController.FireClient(player, "Portal.UI.Open", status)
	end
end

--========================================
-- Portal Prompt Setup
--========================================

local function _attachPrompt(part, objectText, actionText, callback)
	if not part or not part:IsA("BasePart") then return end
	local existing = part:FindFirstChild("PortalPrompt")
	if existing then existing:Destroy() end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PortalPrompt"
	prompt.ObjectText = objectText
	prompt.ActionText = actionText
	prompt.KeyboardKeyCode = Enum.KeyCode.R
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.HoldDuration = 0
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(callback)
end

local function _setupPortalObject(objectName, objectText, actionText, callback)
	task.spawn(function()
		local portalObj = nil
		local deadline = os.clock() + 30
		repeat
			portalObj = _getPortalObject(objectName)
			if portalObj then
				break
			end
			task.wait(0.5)
		until os.clock() >= deadline

		if not portalObj then
			warn("[PortalService] Portal object not found:", objectName)
			return
		end

		if portalObj:IsA("Model") then
			local found = 0
			for _, d in ipairs(portalObj:GetDescendants()) do
				if d:IsA("BasePart") then
					_attachPrompt(d, objectText, actionText, callback)
					found += 1
				end
			end
			if found == 0 then
				_attachPrompt(
					portalObj.PrimaryPart or portalObj:FindFirstChildWhichIsA("BasePart"),
					objectText, actionText, callback
				)
			end
		elseif portalObj:IsA("BasePart") then
			_attachPrompt(portalObj, objectText, actionText, callback)
		end

		print("[PortalService] Portal ready:", objectName)
	end)
end

local function _setupPortalPair(def)
	-- 출발 포탈 (초원섬 → 대상 섬)
	_setupPortalObject(def.portalName, def.displayName, "상호작용", function(player)
		_onPortalTriggered(player, def.id, false)
	end)

	-- 귀환 포탈 (대상 섬 → 초원섬)
	_setupPortalObject(def.returnPortalName, "초원섬 귀환 포탈", "돌아가기", function(player)
		_onPortalTriggered(player, def.id, true)
	end)
end

--========================================
-- Public API
--========================================

function PortalService.Init(_NetController, _SaveService, _InventoryService, _HarvestService, _CreatureService, _NPCShopService)
	if initialized then return end

	NetController = _NetController
	SaveService = _SaveService
	InventoryService = _InventoryService
	HarvestService = _HarvestService
	CreatureService = _CreatureService
	NPCShopService = _NPCShopService

	-- 모든 포탈 정의에 대해 프롬프트 설정
	for _, def in ipairs(PORTAL_DEFINITIONS) do
		_setupPortalPair(def)
	end

	Players.PlayerRemoving:Connect(function(player)
		debounces[player.UserId] = nil
		activeInteractions[player.UserId] = nil
	end)

	initialized = true
	print("[PortalService] Initialized with", #PORTAL_DEFINITIONS, "portal(s)")
end

--- 네트워크 핸들러
function PortalService.GetHandlers()
	return {
		["Portal.GetStatus.Request"] = function(player, payload)
			local interaction = activeInteractions[player.UserId]
			local portalId = (payload and payload.portalId) or (interaction and interaction.portalId)
			if not portalId then
				return { success = false, errorCode = "BAD_REQUEST" }
			end
			return { success = true, data = _getPortalStatus(player.UserId, portalId) }
		end,
		["Portal.Deposit.Request"] = function(player, payload)
			return _depositPortalGold(player, payload or {})
		end,
		["Portal.Teleport.Request"] = function(player, payload)
			return _requestPortalTeleport(player, payload or {})
		end,
	}
end

return PortalService
