-- CraftController.lua
-- 클라이언트 제작 이벤트 수신 컨트롤러
-- 서버에서 오는 Craft.* 이벤트를 수신하여 UI에 전달

local CraftController = {}

local NetClient = require(script.Parent.Parent.NetClient)

local initialized = false

--========================================
-- Event Handlers
--========================================

local function onCraftStarted(data)
	print(string.format("[CraftController] Craft started: %s (recipe: %s, time: %ds)",
		data.craftId or "instant", data.recipeId, data.craftTime or 0))
	-- TODO: UI에 제작 진행 표시 (프로그레스바 시작)
end

local function onCraftCompleted(data)
	print(string.format("[CraftController] Craft completed: recipe %s", data.recipeId))
	if data.outputs then
		for _, output in ipairs(data.outputs) do
			print(string.format("  -> Received: %s x%d", output.itemId, output.count))
		end
	end
	-- TODO: UI에 제작 완료 알림 + 인벤토리 갱신
end

local function onCraftReady(data)
	print(string.format("[CraftController] Craft ready to collect: %s (recipe: %s)",
		data.craftId, data.recipeId))
	-- TODO: UI에 "수거 가능" 알림 표시
end

local function onCraftCancelled(data)
	print(string.format("[CraftController] Craft cancelled: %s (recipe: %s)",
		data.craftId, data.recipeId))
	-- TODO: UI에서 제작 항목 제거
end

--========================================
-- Initialization
--========================================
function CraftController.Init()
	if initialized then return end
	
	-- 서버 이벤트 구독
	NetClient.On("Craft.Started", onCraftStarted)
	NetClient.On("Craft.Completed", onCraftCompleted)
	NetClient.On("Craft.Ready", onCraftReady)
	NetClient.On("Craft.Cancelled", onCraftCancelled)
	
	initialized = true
	print("[CraftController] Initialized")
end

return CraftController
