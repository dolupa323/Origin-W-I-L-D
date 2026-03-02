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
	if data and data.recipeId then
		local recipe = DataHelper.GetData("RecipeData", data.recipeId)
		if recipe then name = recipe.name end
	end
	
	UIManager.notify("제작 완료: " .. name, Color3.fromRGB(100, 255, 100)) -- GREEN
	UIManager.refreshInventory()
	UIManager.refreshCrafting()
end

local function onCraftReady(data)
	-- 수거 가능 알림 (시설 제작 등의 경우)
	UIManager.notify("제작 완료: 수거 가능", Color3.fromRGB(255, 215, 0)) -- GOLD
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
