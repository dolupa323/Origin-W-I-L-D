-- CraftController.lua
-- 클라이언트 제작 이벤트 수신 컨트롤러
-- 서버에서 오는 Craft.* 이벤트를 수신하여 UI에 전달

local CraftController = {}

local NetClient = require(script.Parent.Parent.NetClient)
local UIManager = require(script.Parent.Parent.UIManager)
local DataHelper = require(game.ReplicatedStorage.Shared.Util.DataHelper)

local initialized = false

--========================================
-- Event Handlers
--========================================

local function onCraftStarted(data)
	if data and data.craftTime and data.craftTime > 0 then
		UIManager.showCraftingProgress(data.craftTime)
	end
end

local function onCraftCompleted(data)
	UIManager.stopCraftingProgress()
	
	local name = "아이템"
	local icon = ""
	if data and data.recipeId then
		local recipe = DataHelper.GetData("RecipeData", data.recipeId)
		if recipe then 
			name = recipe.name 
			-- 아이콘 정보 (DataHelper나 UIManager에서 가져와야 함)
			-- UIManager.getItemIcon은 export되어 있지 않으므로 
			-- 여기서는 이름 위주로 표시하거나 UIManager 내부에 아이콘 처리 로직을 넣는 것이 좋음.
			-- 일단 이름과 색상으로 처리
		end
	end
	
	UIManager.sideNotify("🛠️ 제작 완료: " .. name, Color3.fromRGB(100, 255, 100))
	UIManager.refreshInventory()
	
	if UIManager.refreshPersonalCrafting then
		UIManager.refreshPersonalCrafting(true)
	end
end

local function onCraftReady(data)
	-- 수거 가능 알림 (시설 제작 등의 경우)
	UIManager.sideNotify("📦 제작 완료: 수거 가능", Color3.fromRGB(255, 215, 0))
end

local function onCraftCancelled(data)
	UIManager.stopCraftingProgress()
	UIManager.notify("제작 취소됨", Color3.fromRGB(150, 150, 150)) -- GRAY
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
