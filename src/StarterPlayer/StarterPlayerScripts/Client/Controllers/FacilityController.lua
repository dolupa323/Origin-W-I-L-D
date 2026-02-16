-- FacilityController.lua
-- 클라이언트 시설 이벤트 수신 컨트롤러
-- 서버에서 오는 Facility.* 이벤트를 수신하여 UI에 전달

local NetClient = require(script.Parent.Parent.NetClient)

local FacilityController = {}

--========================================
-- Event Handlers
--========================================

local function onStateChanged(data)
	print(string.format("[FacilityController] Facility %s state changed: %s",
		data.structureId or "?", data.state or "?"))
	-- TODO: UI에 시설 상태 변경 반영
end

--========================================
-- Initialization
--========================================

function FacilityController.Init()
	NetClient.On("Facility.StateChanged", onStateChanged)
	print("[FacilityController] Initialized")
end

return FacilityController
