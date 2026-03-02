-- FacilityController.lua
-- 클라이언트 시설 이벤트 수신 컨트롤러
-- 서버에서 오는 Facility.* 이벤트를 수신하여 UI에 전달

local NetClient = require(script.Parent.Parent.NetClient)
local UIManager = require(script.Parent.Parent.UIManager)

local FacilityController = {}

local initialized = false

--========================================
-- Event Handlers
--========================================

local function onStateChanged(data)
	if not data then return end
	
	-- 시설 상태 변경 알림
	local structureId = data.structureId or "?"
	local state = data.state or "?"
	UIManager.notify(string.format("시설 상태 변경: %s -> %s", structureId, state), Color3.fromRGB(200, 200, 200))
end

--========================================
-- Initialization
--========================================

function FacilityController.Init()
	if initialized then return end
	
	NetClient.On("Facility.StateChanged", onStateChanged)
	
	initialized = true
	print("[FacilityController] Initialized")
end

return FacilityController
