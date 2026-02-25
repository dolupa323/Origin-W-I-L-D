-- EquipService.lua
-- 플레이어 장비 시각화 및 도구(Tool) 스폰 관리
-- ReplicatedStorage.Assets.ItemModels 폴더에서 모델을 찾아 장착

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local EquipService = {}

--========================================
-- Private State
--========================================
local initialized = false
local DataService = nil

--========================================
-- Public API
--========================================

function EquipService.Init(_DataService)
	if initialized then return end
	DataService = _DataService
	initialized = true
	print("[EquipService] Initialized")
end

--- 플레이어의 모든 도구 제거
function EquipService.unequipAll(player: Player)
	if not player or not player.Character then return end
	
	-- Backpack 내부 도구 제거
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") then item:Destroy() end
		end
	end
	
	-- 캐릭터가 현재 들고 있는 도구 제거
	for _, item in ipairs(player.Character:GetChildren()) do
		if item:IsA("Tool") then item:Destroy() end
	end
end

--- 특정 아이템을 플레이어에게 장착 (시각화)
function EquipService.equipItem(player: Player, itemId: string?)
	-- 1. 기존 장비 모두 해제
	EquipService.unequipAll(player)
	
	if not itemId or itemId == "" then return end
	
	-- 2. 아이템 데이터 확인 (장착 가능한 타입인지)
	local itemData = DataService.getItem(itemId)
	if not itemData then return end
	
	-- 장착 가능한 타입: TOOL, WEAPON
	local equippableTypes = { ["TOOL"] = true, ["WEAPON"] = true }
	if not equippableTypes[itemData.type] then return end
	
	-- 3. Assets/ItemModels 폴더에서 템플릿 찾기
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local modelsFolder = assets and assets:FindFirstChild("ItemModels")
	
	if not modelsFolder then
		warn("[EquipService] Assets/ItemModels folder not found!")
		return
	end
	
	local template = modelsFolder:FindFirstChild(itemId)
	if not template then
		warn(string.format("[EquipService] No model template found for itemId: %s", itemId))
		return
	end
	
	-- 4. 도구 복제 및 지급
	local tool = template:Clone()
	tool.Name = itemId
	
	-- 속성 주입 (HarvestService 등에서 참조)
	tool:SetAttribute("ToolType", itemData.optimalTool or itemId:upper())
	tool:SetAttribute("Damage", itemData.damage or 0)
	
	-- 인벤토리의 Backpack에 넣으면 자동으로 장착 가능한 상태가 됨
	-- 하지만 우리는 항상 핫바 선택 시 즉시 '장착' 상태로 만들고 싶으므로 Character에 직접 넣음
	if player.Character then
		tool.Parent = player.Character
	else
		local backpack = player:WaitForChild("Backpack", 5)
		if backpack then tool.Parent = backpack end
	end
	
	print(string.format("[EquipService] Equipped %s to %s", itemId, player.Name))
end

return EquipService
