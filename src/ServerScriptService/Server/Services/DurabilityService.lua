-- DurabilityService.lua
-- 아이템 내구도 관리 서비스 (Phase 2-4)
-- 내구도 감소 및 수리(Repair) 담당

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums.Enums)

local DurabilityService = {}

-- Dependencies
local NetController
local InventoryService

--========================================
-- Public API
--========================================

function DurabilityService.Init(_NetController, _InventoryService)
	NetController = _NetController
	InventoryService = _InventoryService
	print("[DurabilityService] Initialized")
end

--- 내구도 감소 요청 (채집, 공격 등에서 호출)
--- @param player Player
--- @param slot number 인벤토리 슬롯
--- @param amount number 감소량 (양수)
--- @return boolean success
function DurabilityService.reduceDurability(player: Player, slot: number, amount: number): boolean
	if not player or not slot or not amount then return false end
	if amount <= 0 then return false end -- 감소량은 양수여야 함
	
	local userId = player.UserId
	
	-- InventoryService에 위임
	local success, errorCode, current = InventoryService.decreaseDurability(userId, slot, amount)
	
	if not success then
		warn(string.format("[DurabilityService] Failed to reduce durability for player %d slot %d: %s", 
			userId, slot, tostring(errorCode)))
		return false
	end
	
	-- 0 이하 파괴 알림은 InventoryService가 이벤트를 보내므로 여기선 추가 처리 불필요
	-- 필요시 파괴 효과음 등을 위한 별도 패킷 전송 가능
	if current <= 0 then
		-- e.g. NetController.FireClient(player, "Effect.ItemBreak", { slot = slot })
	end
	
	return true
end

--========================================
-- Network Handlers
--========================================

function DurabilityService.GetHandlers()
	return {
		-- 추후 Repair 관련 핸들러 추가
	}
end

return DurabilityService
