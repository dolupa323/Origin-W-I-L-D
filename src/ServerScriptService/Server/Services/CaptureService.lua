-- CaptureService.lua
-- Phase 5-2: 포획 시스템 (Server-Authoritative)
-- 약해진 크리처에게 포획구를 던져 팰로 포획

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)
local Balance = require(Shared.Config.Balance)

local CaptureService = {}

-- Dependencies
local NetController
local DataService
local CreatureService
local InventoryService
local PalboxService
local PlayerStatService  -- Phase 6: 포획 성공 시 XP 지급

-- Data
local PalData
local CaptureItemData

-- Quest callback (Phase 8)
local questCallback = nil

--========================================
-- Internal Helpers
--========================================

--- 포획 확률 계산
--- finalRate = baseRate × (1 + (1 - currentHP/maxHP) × 2) × captureMultiplier
--- HP가 낮을수록 포획률이 높아짐
local function calculateCaptureRate(palDef, creature, captureMultiplier: number): number
	local hpRatio = math.clamp(creature.currentHealth / creature.maxHealth, 0, 1)
	local hpBonus = 1 + (1 - hpRatio) * 2 -- HP 0%일 때 3배, HP 100%일 때 1배
	
	local rate = palDef.captureRate * hpBonus * captureMultiplier
	
	-- 최대 95%로 제한 (100%는 없음)
	return math.clamp(rate, 0, 0.95)
end

--========================================
-- Public API
--========================================

function CaptureService.Init(_NetController, _DataService, _CreatureService, _InventoryService, _PalboxService, _PlayerStatService)
	NetController = _NetController
	DataService = _DataService
	CreatureService = _CreatureService
	InventoryService = _InventoryService
	PalboxService = _PalboxService
	PlayerStatService = _PlayerStatService
	
	-- 데이터 로드
	PalData = require(ReplicatedStorage.Data.PalData)
	CaptureItemData = require(ReplicatedStorage.Data.CaptureItemData)
	
	print("[CaptureService] Initialized")
end

--- 포획 시도 (메인 로직)
function CaptureService.attemptCapture(player: Player, targetId: string, captureItemSlot: number)
	local userId = player.UserId
	
	-- 1. 플레이어 캐릭터 검증
	local char = player.Character
	if not char then return false, Enums.ErrorCode.INTERNAL_ERROR end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false, Enums.ErrorCode.INTERNAL_ERROR end
	
	-- 2. 포획구 아이템 검증
	local slotData = InventoryService.getSlot(userId, captureItemSlot)
	if not slotData then
		return false, Enums.ErrorCode.SLOT_EMPTY
	end
	
	local itemDef = DataService.getItem(slotData.itemId)
	if not itemDef or not itemDef.captureMultiplier then
		return false, Enums.ErrorCode.NO_CAPTURE_ITEM
	end
	
	-- CaptureItemData에서 상세 정보 가져오기
	local captureItemDef = CaptureItemData[slotData.itemId]
	local captureMultiplier = (captureItemDef and captureItemDef.captureMultiplier) or itemDef.captureMultiplier or 1.0
	local maxRange = (captureItemDef and captureItemDef.maxRange) or Balance.CAPTURE_RANGE
	
	-- 3. 대상 크리처 검증
	local creature = CreatureService.getCreatureRuntime(targetId)
	if not creature or not creature.rootPart then
		return false, Enums.ErrorCode.NOT_FOUND
	end
	
	-- 3a. 거리 검증
	local dist = (hrp.Position - creature.rootPart.Position).Magnitude
	if dist > maxRange + 2 then -- 약간의 오차 허용
		return false, Enums.ErrorCode.OUT_OF_RANGE
	end
	
	-- 3b. 포획 가능 여부 (PalData에 정의된 크리처만)
	local palDef = PalData[creature.creatureId]
	if not palDef then
		return false, Enums.ErrorCode.NOT_CAPTURABLE
	end
	
	-- 3c. 보스 체크
	if palDef.isBoss then
		return false, Enums.ErrorCode.NOT_CAPTURABLE
	end
	
	-- 4. Palbox 용량 체크
	if PalboxService then
		local palCount = PalboxService.getPalCount(userId)
		if palCount >= Balance.MAX_PALBOX then
			return false, Enums.ErrorCode.PALBOX_FULL
		end
	end
	
	-- 5. 포획구 소모 (1개)
	local removed = InventoryService.removeItemFromSlot(userId, captureItemSlot, 1)
	if removed < 1 then
		return false, Enums.ErrorCode.SLOT_EMPTY
	end
	
	-- 6. 확률 판정
	local captureRate = calculateCaptureRate(palDef, creature, captureMultiplier)
	local roll = math.random()
	local success = roll <= captureRate
	
	print(string.format("[CaptureService] %s attempts capture on %s (rate: %.1f%%, roll: %.3f) → %s",
		player.Name, creature.creatureId, captureRate * 100, roll, success and "SUCCESS" or "FAIL"))
	
	if not success then
		-- 포획 실패 - 크리처 유지
		-- 클라이언트에 실패 알림
		if NetController then
			NetController.FireClient(player, "Capture.Result", {
				success = false,
				targetId = targetId,
				captureRate = captureRate,
			})
		end
		return false, Enums.ErrorCode.CAPTURE_FAILED
	end
	
	-- 7. 포획 성공!
	-- 7a. 경험치 보상 (Phase 6)
	if PlayerStatService then
		PlayerStatService.addXP(userId, Balance.XP_CAPTURE_PAL or 50, Enums.XPSource.CAPTURE_PAL)
	end
		-- 7a-2. 퀘스트 콜백 (Phase 8)
	if questCallback then
		questCallback(userId, creature.creatureId)
	end
		-- 7b. 팰 데이터 생성
	local palUID = HttpService:GenerateGUID(false)
	local newPal = {
		uid = palUID,
		creatureId = creature.creatureId,
		nickname = palDef.palName, -- 기본 닉네임
		level = 1,
		exp = 0,
		stats = {
			hp = palDef.baseStats.hp,
			attack = palDef.baseStats.attack,
			defense = palDef.baseStats.defense,
			speed = palDef.baseStats.speed,
		},
		workTypes = palDef.workTypes,
		workPower = palDef.workPower,
		combatPower = palDef.combatPower,
		passiveSkill = palDef.passiveSkill,
		capturedAt = os.time(),
		state = Enums.PalState.STORED,
		assignedFacility = nil,
	}
	
	-- 7b. PalboxService에 등록
	if PalboxService then
		local addSuccess = PalboxService.addPal(userId, newPal)
		if not addSuccess then
			warn("[CaptureService] Failed to add pal to palbox")
			return false, Enums.ErrorCode.PALBOX_FULL
		end
	end
	
	-- 7c. 크리처 제거 (월드에서 사라짐)
	-- 사망 로직과 유사하지만 드롭 없음
	if CreatureService and CreatureService.removeCreature then
		CreatureService.removeCreature(targetId)
	end
	
	-- 7d. 클라이언트에 성공 알림
	if NetController then
		NetController.FireClient(player, "Capture.Result", {
			success = true,
			targetId = targetId,
			palUID = palUID,
			palName = newPal.nickname,
			creatureId = newPal.creatureId,
			captureRate = captureRate,
		})
	end
	
	return true, nil, { palUID = palUID, palData = newPal }
end

--========================================
-- Network Handlers
--========================================

local function handleCaptureRequest(player: Player, payload)
	local targetId = payload.targetId
	local captureItemSlot = payload.captureItemSlot
	
	if not targetId or not captureItemSlot then
		return { success = false, errorCode = Enums.ErrorCode.BAD_REQUEST }
	end
	
	local success, errorCode, data = CaptureService.attemptCapture(player, targetId, captureItemSlot)
	
	if not success then
		return { success = false, errorCode = errorCode }
	end
	
	return { success = true, data = data }
end

function CaptureService.GetHandlers()
	return {
		["Capture.Attempt.Request"] = handleCaptureRequest,
	}
end

--- 퀘스트 콜백 설정 (Phase 8)
function CaptureService.SetQuestCallback(callback)
	questCallback = callback
end

return CaptureService
