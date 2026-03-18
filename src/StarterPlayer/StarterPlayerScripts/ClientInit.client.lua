-- ClientInit.client.lua
-- 클라이언트 초기화 스크립트

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayerScripts = script.Parent

local Client = StarterPlayerScripts:WaitForChild("Client")
local Controllers = Client:WaitForChild("Controllers")

local NetClient = require(Client.NetClient)
local InputManager = require(Client.InputManager)
local UIManager = require(Client.UIManager)

-- NetClient 초기화
local success = NetClient.Init()

if success then
	-- InputManager 초기화 (키 바인딩)
	InputManager.Init()
	
	-- WorldDropController 초기화 (이벤트 소비자)
	local WorldDropController = require(Controllers.WorldDropController)
	WorldDropController.Init()
	
	-- InventoryController 초기화 (이벤트 소비자)
	local InventoryController = require(Controllers.InventoryController)
	InventoryController.Init()
	
	-- TimeController 초기화 (이벤트 소비자)
	local TimeController = require(Controllers.TimeController)
	TimeController.Init()
	
	-- StorageController 초기화 (이벤트 소비자)
	local StorageController = require(Controllers.StorageController)
	StorageController.Init()
	
	-- BuildController 초기화 (이벤트 소비자)
	local BuildController = require(Controllers.BuildController)
	BuildController.Init()
	
	-- CraftController 초기화 (이벤트 소비자)
	local CraftController = require(Controllers.CraftController)
	CraftController.Init()
	
	-- FacilityController 초기화 (이벤트 소비자)
	local FacilityController = require(Controllers.FacilityController)
	FacilityController.Init()

	-- ShopController 초기화 (Phase 9)
	local ShopController = require(Controllers.ShopController)
	ShopController.Init()
	
	
	-- CombatController 초기화 (공격 시스템)
	local CombatController = require(Controllers.CombatController)
	CombatController.Init()
	
	-- InteractController 초기화 (채집/상호작용)
	local InteractController = require(Controllers.InteractController)
	InteractController.Init()
	
	-- MovementController 초기화 (스프린트/구르기)
	local MovementController = require(Controllers.MovementController)
	MovementController.Init()
	
	-- ResourceUIController 초기화 (노드 HP 바)
	local ResourceUIController = require(Controllers.ResourceUIController)
	ResourceUIController.Init()
	
	-- VirtualizationController 초기화 (성능 최적화: 가상화)
	local VirtualizationController = require(Controllers.VirtualizationController)
	VirtualizationController.Init()

	-- CreatureAnimationController 초기화 (공룡 애니메이션)
	local CreatureAnimationController = require(Controllers.CreatureAnimationController)
	CreatureAnimationController.Init()
	
	-- [추가] HitFeedbackController 초기화 (피격 연출 및 물리 보정)
	local HitFeedbackController = require(Controllers.HitFeedbackController)
	HitFeedbackController.Init()
	
	-- [추가] PromptUI 초기화 (커스텀 ProximityPrompt)
	local PromptUI = require(Client:WaitForChild("UI"):WaitForChild("PromptUI"))
	PromptUI.Init()
	
	-- UIManager 초기화 (UI 생성 - 컨트롤러들 초기화 후)
	UIManager.Init()

	-- TutorialController 초기화 (첫 진입 튜토리얼)
	local TutorialController = require(Controllers.TutorialController)
	TutorialController.Init()

	-- TotemController 초기화 (거점 토템 유지비/범위 프리뷰)
	local TotemController = require(Controllers.TotemController)
	TotemController.Init()
	
	-- MovementController 스태미나 → UIManager 연동
	MovementController.onStaminaChanged(function(current, max)
		UIManager.updateStamina(current, max)
	end)
	
	-- 배고픔 → UIManager 연동 (Phase 11)
	NetClient.On("Hunger.Update", function(data)
		UIManager.updateHunger(data.current, data.max)
	end)
	
	-- 키 바인딩 설정
	-- [Key Bindings] B = 인벤토리, C = 건축, E = 장비창, P = 도감
	InputManager.bindKey(Enum.KeyCode.B, "ToggleInventory", function() UIManager.toggleInventory() end)
	InputManager.bindKey(Enum.KeyCode.C, "ToggleBuilding", function() UIManager.toggleBuild() end)
	InputManager.bindKey(Enum.KeyCode.E, "ToggleEquipment", function() UIManager.toggleEquipment() end)
	InputManager.bindKey(Enum.KeyCode.P, "ToggleCollection", function() UIManager.toggleCollection() end)
	InputManager.bindKey(Enum.KeyCode.Tab, "ToggleInventory_Tab", function() UIManager.toggleInventory() end)
	
	-- Z = 상호작용 (줍기, NPC 등)
	InputManager.bindKey(Enum.KeyCode.Z, "InteractZ", function()
		InteractController.onInteractPress()
	end)

	-- R = 건물/시설 상호작용 (Z 줍기 프롬프트와 충돌 방지)
	InputManager.bindKey(Enum.KeyCode.R, "InteractFacilityR", function()
		if InteractController.onFacilityInteractPress then
			InteractController.onFacilityInteractPress()
		end
	end)

	-- T = 건물 해체
	InputManager.bindKey(Enum.KeyCode.T, "InteractFacilityRemoveT", function()
		if InteractController.onFacilityRemovePress then
			InteractController.onFacilityRemovePress()
		end
	end)
	
	InputManager.bindKey(Enum.KeyCode.Escape, "CloseUI", function()
		UIManager.closeInventory()
		UIManager.closeCrafting()
		UIManager.closeEquipment()
		UIManager.closeBuild()
		UIManager.closeCollection()
		UIManager.closeShop()
		if UIManager.closeTotem then
			UIManager.closeTotem()
		end
	end)
end

print("[ClientInit] Client initialized")
