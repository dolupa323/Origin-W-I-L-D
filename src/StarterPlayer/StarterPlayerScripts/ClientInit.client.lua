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
	
	-- TechController 초기화
	local TechController = require(Controllers.TechController)
	TechController.Init()
	
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
	
	-- UIManager 초기화 (UI 생성 - 컨트롤러들 초기화 후)
	UIManager.Init()
	
	-- MovementController 스태미나 → UIManager 연동
	MovementController.onStaminaChanged(function(current, max)
		UIManager.updateStamina(current, max)
	end)
	
	-- 키 바인딩 설정
	-- E = 장비창, B = 인벤토리
	InputManager.bindKey(Enum.KeyCode.E, "ToggleEquipment", function()
		UIManager.toggleEquipment()
	end)
	InputManager.bindKey(Enum.KeyCode.B, "ToggleInventory", function()
		UIManager.toggleInventory()
	end)
	-- C = 건축 (기존 제작 벤치에서 분리)
	InputManager.bindKey(Enum.KeyCode.C, "ToggleBuilding", function()
		UIManager.toggleCrafting("BUILDING") -- BUILDING 모드로 고정 호출
	end)
	-- K = 기술 트리 (T에서 K로 변경)
	InputManager.bindKey(Enum.KeyCode.K, "ToggleTechTree", function()
		UIManager.toggleTechTree()
	end)
	-- Z = 상호작용 (줍기, NPC 등)
	InputManager.bindKey(Enum.KeyCode.Z, "InteractZ", function()
		InteractController.onInteractPress()
	end)
	
	InputManager.bindKey(Enum.KeyCode.Escape, "CloseUI", function()
		UIManager.closeInventory()
		UIManager.closeCrafting()
		UIManager.closeShop()
		UIManager.closeTechTree()
	end)
end

print("[ClientInit] Client initialized")
