-- PortalService.lua
-- 고대 포탈 시스템 (Ancient Portal) — 허브-스포크 모델
-- 초원섬(허브)에 섬별 고대포탈, 각 섬에 귀환 포탈
-- 이동 경로: 초원섬 ↔ 개별 섬 (섬끼리 직접 이동 불가)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local SpawnConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("SpawnConfig"))

local PortalService = {}
local initialized = false

-- Dependencies (injected via Init)
local NetController
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
		repairCost = {
			{ itemId = "LOG", amount = 10, name = "통나무" },
			{ itemId = "STONE", amount = 10, name = "돌" },
		},
	},
	-- ★ 향후 섬 추가 예시:
	-- {
	--     id = "DESERT",
	--     displayName = "사막섬 고대 포탈",
	--     destinationName = "사막섬",
	--     portalName = "Portal_Desert",
	--     returnPortalName = "Portal_Return_Desert",
	--     targetZone = "DESERT",
	--     repairCost = {
	--         { itemId = "LOG", amount = 20, name = "통나무" },
	--         { itemId = "IRON_INGOT", amount = 5, name = "철 주괴" },
	--     },
	-- },
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
				progress = type(state.portalProgress) == "table" and state.portalProgress or {},
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
	if not state then return { repaired = false, progress = {} } end
	local portals = _migrateOldPortalState(state)
	if not portals[portalId] then
		portals[portalId] = { repaired = false, progress = {} }
	end
	return portals[portalId]
end

local function _isPortalRepaired(userId, portalId)
	return _getPortalState(userId, portalId).repaired == true
end

local function _ensurePortalProgress(portalState, repairCost)
	if type(portalState.progress) ~= "table" then
		portalState.progress = {}
	end
	for _, req in ipairs(repairCost) do
		if type(portalState.progress[req.itemId]) ~= "number" then
			portalState.progress[req.itemId] = 0
		end
	end
	return portalState.progress
end

local function _markPortalRepaired(userId, portalId)
	if not SaveService then return end
	local def = portalLookup[portalId]
	if not def then return end
	SaveService.updatePlayerState(userId, function(state)
		local portals = _migrateOldPortalState(state)
		if not portals[portalId] then portals[portalId] = {} end
		portals[portalId].repaired = true
		local progress = _ensurePortalProgress(portals[portalId], def.repairCost)
		for _, req in ipairs(def.repairCost) do
			progress[req.itemId] = req.amount
		end
		return state
	end)
end

local function _getPortalStatus(userId, portalId)
	local def = portalLookup[portalId]
	if not def then return { repaired = false, cost = {} } end

	local portalState = _getPortalState(userId, portalId)
	local repaired = portalState.repaired == true
	local progress = _ensurePortalProgress(portalState, def.repairCost)
	local cost = {}
	local allMet = true

	for _, req in ipairs(def.repairCost) do
		local current = math.clamp(tonumber(progress[req.itemId]) or 0, 0, req.amount)
		local met = current >= req.amount
		if not met then allMet = false end
		table.insert(cost, {
			itemId = req.itemId,
			name = req.name,
			required = req.amount,
			current = current,
			remaining = math.max(0, req.amount - current),
			met = met,
		})
	end

	if allMet and not repaired then
		_markPortalRepaired(userId, portalId)
		repaired = true
	end

	return {
		portalId = portalId,
		displayName = def.displayName,
		destinationName = def.destinationName,
		repaired = repaired,
		cost = cost,
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

	local itemId = payload and payload.itemId
	if type(itemId) ~= "string" or itemId == "" then
		return { success = false, errorCode = "BAD_REQUEST" }
	end

	local reqData = nil
	for _, req in ipairs(def.repairCost) do
		if req.itemId == itemId then
			reqData = req
			break
		end
	end
	if not reqData then
		return { success = false, errorCode = "BAD_REQUEST" }
	end

	local state = SaveService and SaveService.getPlayerState(userId)
	if not state then
		return { success = false, errorCode = "INVALID_STATE" }
	end

	local portals = _migrateOldPortalState(state)
	if not portals[portalId] then portals[portalId] = { repaired = false, progress = {} } end
	local progress = _ensurePortalProgress(portals[portalId], def.repairCost)
	local current = math.clamp(tonumber(progress[itemId]) or 0, 0, reqData.amount)
	local need = reqData.amount - current
	if need <= 0 then
		return { success = true, data = _getPortalStatus(userId, portalId) }
	end

	local requestedAmount = math.max(1, math.floor(tonumber(payload and payload.amount) or need))
	local depositAmount = math.min(need, requestedAmount)

	if not InventoryService.hasItem(userId, itemId, 1) then
		return { success = false, errorCode = "NO_ITEM", data = _getPortalStatus(userId, portalId) }
	end

	local removed = InventoryService.removeItem(userId, itemId, depositAmount)
	if removed <= 0 then
		return { success = false, errorCode = "NO_ITEM" }
	end

	SaveService.updatePlayerState(userId, function(s)
		local p = _migrateOldPortalState(s)
		if not p[portalId] then p[portalId] = { repaired = false, progress = {} } end
		local prog = _ensurePortalProgress(p[portalId], def.repairCost)
		prog[itemId] = math.min(reqData.amount, (tonumber(prog[itemId]) or 0) + removed)
		return s
	end)

	if SaveService and SaveService.savePlayer then
		local saveOk, saveErr = SaveService.savePlayer(userId)
		if not saveOk then
			warn(string.format("[PortalService] Save failed after deposit (user=%d): %s", userId, tostring(saveErr)))
		end
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

		-- ★ 도착 좌표: zone spawnPoint를 기본으로 사용 (안전 보장)
		-- 포탈 오브젝트 위치는 주변 지형(물 등)이 위험할 수 있으므로 spawnPoint 우선
		local arrivalPos = zoneInfo.spawnPoint + Vector3.new(0, 5, 0)
		local excludeList = { character }

		-- ★ 포탈 오브젝트가 발견되면 해당 위치를 정교한 이동 기준점으로 사용
		local arrivalPortal = _getPortalObject(arrivalPortalName)
		if arrivalPortal then
			table.insert(excludeList, arrivalPortal)
			arrivalPos = arrivalPortal:GetPivot().Position + Vector3.new(0, 5, 0)
		else
			-- 도착 포탈 기준점이 없는 경우에만 레이캐스트로 지면 재확인 (공중 스폰 방지)
			local rayOrigin = arrivalPos + Vector3.new(0, 50, 0)
			local rayDir = Vector3.new(0, -250, 0)
			local rayParams = RaycastParams.new()
			rayParams.FilterDescendantsInstances = excludeList
			rayParams.FilterType = Enum.RaycastFilterType.Exclude

			local rayResult = workspace:Raycast(rayOrigin, rayDir, rayParams)
			if rayResult and rayResult.Material ~= Enum.Material.Water then
				-- [안전 장치] 레이캐스트 결과 지면이 기준점보다 너무 낮다면 기본값 유지
				local hitY = rayResult.Position.Y
				if hitY > (arrivalPos.Y - 20) then
					arrivalPos = rayResult.Position + Vector3.new(0, 5, 0)
				else
					warn("[PortalService] Raycast hit too low surface (possibly underground), using default spawnPoint height.")
				end
			else
				-- 지면 없음 또는 Water → spawnPoint 높이 그대로 사용 (공중 5스터드)
				if rayResult then
					warn("[PortalService] Water detected at spawnPoint, using raw spawnPoint")
				end
			end
		end

		-- ★ [원인파악 밎 근본 해결]
		-- StreamingEnabled 환경에서는 서버가 PivotTo로 캐릭터를 순간 이동시키면,
		-- 클라이언트는 아직 해당 지역의 지형/파트를 다운로드받지 못한 상태일 수 있습니다.
		-- 이 때 클라이언트 측 물리 엔진이 빈 공간으로 인식하여 중력에 의해 캐릭터가 추락하며,
		-- 지형이 생성되기 전에 FallenPartsDestroyHeight 선(-500)에 닿아 사망하게 됩니다 (지하 리스폰 버그의 원인).

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then
			-- 텔레포트 전후로 클라이언트 물리 추락 방지를 위해 앵커링
			hrp.Anchored = true
		end

		-- 서버가 클라이언트에게 도착 위치의 맵 데이터를 최우선으로 스트리밍하도록 강제 요청 (최대 5초 대기)
		pcall(function()
			player:RequestStreamAroundAsync(arrivalPos, 5)
		end)

		character:PivotTo(CFrame.new(arrivalPos))

		-- ★ 텔레포트 직후 무적 (ForceField) — 주변 크리처 인식 시간 확보
		local ff = Instance.new("ForceField")
		ff.Visible = false
		ff.Parent = character
		task.delay(5, function()
			if ff and ff.Parent then ff:Destroy() end
		end)

		if hrp then
			-- 데이터 스트리밍(RequestStreamAroundAsync)이 완료되었더라도,
			-- 클라이언트 렌더링 프레임 및 물리 계산이 정상화되는 찰나의 순간 추락할 위험이 있으므로
			-- 서버에서 충분한 시간(2초) 동안 Anchored를 유지해 허공 추락을 근본적으로 방지합니다.
			task.delay(2.0, function()
				if hrp and character.Parent then
					hrp.Anchored = false
				end
			end)
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
		-- 귀환 포탈: 수리 불필요, 바로 이용 가능
		NetController.FireClient(player, "Portal.UI.Open", {
			portalId = portalId,
			displayName = "초원섬 귀환 포탈",
			destinationName = "초원섬",
			repaired = true,
			cost = {},
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

function PortalService.Init(_NetController, _SaveService, _InventoryService, _HarvestService, _CreatureService)
	if initialized then return end

	NetController = _NetController
	SaveService = _SaveService
	InventoryService = _InventoryService
	HarvestService = _HarvestService
	CreatureService = _CreatureService

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
			return _depositPortalMaterial(player, payload or {})
		end,
		["Portal.Teleport.Request"] = function(player, payload)
			return _requestPortalTeleport(player, payload or {})
		end,
	}
end

return PortalService
