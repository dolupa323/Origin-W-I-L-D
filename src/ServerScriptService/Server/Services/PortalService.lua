-- PortalService.lua
-- 고대 포탈 시스템 (Ancient Portal)
-- 수리 재료 투입 → 강제 저장 → 열대섬 텔레포트

local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local PortalService = {}
local initialized = false

-- Dependencies (injected via Init)
local NetController
local SaveService
local InventoryService

--========================================
-- Configuration
--========================================
local PORTAL_NAME = "Portal_Tropical"
local TARGET_PLACE_ID = 107341024431610

-- 포탈 수리 비용 (grassland_ecosystem_design.md 섹션 9)
local REPAIR_COST = {
	{ itemId = "LOG", amount = 10, name = "통나무" },
	{ itemId = "STONE", amount = 10, name = "돌" },
}

local DEBOUNCE_COOLDOWN = 3
local debounces = {} -- userId → tick()

--========================================
-- Internal: Player State
--========================================

--- 포탈 수리 여부 확인
local function _isPortalRepaired(userId)
	if not SaveService then return false end
	local state = SaveService.getPlayerState(userId)
	return state and state.portalRepaired == true
end

--- 포탈 수리 완료 마킹
local function _markPortalRepaired(userId)
	if not SaveService then return end
	SaveService.updatePlayerState(userId, function(state)
		state.portalRepaired = true
		return state
	end)
end

--========================================
-- Internal: Material Check
--========================================

--- 재료 보유 상태 확인 (부족한 항목 반환)
local function _checkMaterials(userId)
	local status = {}
	local allMet = true
	for _, req in ipairs(REPAIR_COST) do
		local has = InventoryService.hasItem(userId, req.itemId, req.amount)
		table.insert(status, {
			itemId = req.itemId,
			name = req.name,
			required = req.amount,
			met = has,
		})
		if not has then
			allMet = false
		end
	end
	return allMet, status
end

--- 수리 재료 소모
local function _consumeMaterials(userId)
	-- 사전 체크: 모든 재료 보유 확인
	for _, req in ipairs(REPAIR_COST) do
		if not InventoryService.hasItem(userId, req.itemId, req.amount) then
			return false
		end
	end

	-- 실제 소모
	local consumed = {}
	for _, req in ipairs(REPAIR_COST) do
		local removed = InventoryService.removeItem(userId, req.itemId, req.amount)
		table.insert(consumed, { itemId = req.itemId, count = removed })
		if removed < req.amount then
			-- 롤백
			for _, c in ipairs(consumed) do
				if c.count > 0 then
					InventoryService.addItem(userId, c.itemId, c.count)
				end
			end
			warn(string.format("[PortalService] Material consumption failed: %s (%d/%d)", req.itemId, removed, req.amount))
			return false
		end
	end
	return true
end

--========================================
-- Internal: Portal Interaction
--========================================

local function _onPortalTriggered(player)
	local userId = player.UserId

	-- 디바운스
	if debounces[userId] and (tick() - debounces[userId]) < DEBOUNCE_COOLDOWN then
		return
	end
	debounces[userId] = tick()

	-- ① 이미 수리됨 → 강제 저장 후 텔레포트
	if _isPortalRepaired(userId) then
		if TARGET_PLACE_ID == 0 then
			NetController.FireClient(player, "Portal.Error", { message = "목적지 PlaceId가 설정되지 않았습니다." })
			return
		end

		NetController.FireClient(player, "Portal.Teleporting", {})

		-- 강제 저장
		local saveOk = SaveService.savePlayer(userId)
		if not saveOk then
			warn("[PortalService] Save failed for", player.Name)
			NetController.FireClient(player, "Portal.Error", { message = "저장 실패. 다시 시도해주세요." })
			return
		end

		-- 텔레포트
		print(string.format("[PortalService] Teleporting %s to PlaceId %d", player.Name, TARGET_PLACE_ID))
		local success, err = pcall(function()
			TeleportService:TeleportAsync(TARGET_PLACE_ID, {player})
		end)
		if not success then
			warn("[PortalService] Teleport failed:", err)
			NetController.FireClient(player, "Portal.Error", { message = "텔레포트 실패. 다시 시도해주세요." })
		end
		return
	end

	-- ② 미수리 → 재료 확인
	local allMet, status = _checkMaterials(userId)

	if not allMet then
		-- 부족한 재료 알림
		NetController.FireClient(player, "Portal.MissingMaterials", { cost = status })
		return
	end

	-- ③ 재료 충분 → 소모 + 수리 완료
	if not _consumeMaterials(userId) then
		NetController.FireClient(player, "Portal.Error", { message = "재료 소모 중 오류가 발생했습니다." })
		return
	end

	_markPortalRepaired(userId)
	NetController.FireClient(player, "Portal.Repaired", {})
	print(string.format("[PortalService] Portal repaired by %s", player.Name))
end

--========================================
-- Public API
--========================================

function PortalService.Init(_NetController, _SaveService, _InventoryService)
	if initialized then return end

	NetController = _NetController
	SaveService = _SaveService
	InventoryService = _InventoryService

	-- 포탈 오브젝트에 ProximityPrompt 설정
	task.spawn(function()
		local portalObject = workspace:WaitForChild(PORTAL_NAME, 30)
		if not portalObject then
			warn("[PortalService] Portal object not found:", PORTAL_NAME)
			return
		end

		-- 프롬프트를 붙일 파트 결정
		local promptPart = portalObject
		if portalObject:IsA("Model") then
			promptPart = portalObject:FindFirstChild("PromptPart")
				or portalObject.PrimaryPart
				or portalObject:FindFirstChildWhichIsA("BasePart")
		end

		if not promptPart or not promptPart:IsA("BasePart") then
			warn("[PortalService] No valid BasePart found for ProximityPrompt in", PORTAL_NAME)
			return
		end

		-- ProximityPrompt 생성
		local prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = "고대 포탈"
		prompt.ActionText = "상호작용"
		prompt.MaxActivationDistance = 10
		prompt.HoldDuration = 0.5
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.RequiresLineOfSight = false
		prompt.Parent = promptPart

		prompt.Triggered:Connect(function(player)
			_onPortalTriggered(player)
		end)

		print("[PortalService] Portal prompt initialized:", PORTAL_NAME)
	end)

	-- 플레이어 퇴장 시 디바운스 정리
	Players.PlayerRemoving:Connect(function(player)
		debounces[player.UserId] = nil
	end)

	initialized = true
	print("[PortalService] Initialized")
end

--- 네트워크 핸들러
function PortalService.GetHandlers()
	return {
		["Portal.GetStatus.Request"] = function(player, _payload)
			local userId = player.UserId
			local repaired = _isPortalRepaired(userId)
			local _, status = _checkMaterials(userId)
			return {
				success = true,
				data = {
					repaired = repaired,
					cost = status,
				},
			}
		end,
	}
end

return PortalService
