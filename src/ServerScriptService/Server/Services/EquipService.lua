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
local isEquipping = {}

function EquipService.equipItem(player: Player, itemId: string?)
	local char = player.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if not char or not hum then return end
	
	-- 0. 장착 해제 처리
	if not itemId or itemId == "" then
		EquipService.unequipAll(player)
		return
	end

	-- 1. 중복 장착 체크
	local current = char:FindFirstChildWhichIsA("Tool")
	if current and current.Name == itemId then return end
	
	if isEquipping[player.UserId] then return end
	isEquipping[player.UserId] = true
	
	local success, err = pcall(function()
		-- 2. 기존 도구 청소
		EquipService.unequipAll(player)
		
		local itemData = DataService.getItem(itemId)
		if not itemData then 
			isEquipping[player.UserId] = nil
			return 
		end
		
		-- 3. 에셋 탐색
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local modelsFolder = assets and (assets:FindFirstChild("ItemModels") or assets:FindFirstChild("Models"))
		
		if modelsFolder then
			local allNames = {}
			for _, child in ipairs(modelsFolder:GetChildren()) do table.insert(allNames, child.Name) end
			print(string.format("[EquipService] ItemModels contents: [%s]", table.concat(allNames, ", ")))
		end

		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local searchRoot = (assets and (assets:FindFirstChild("ItemModels") or assets:FindFirstChild("Models") or assets)) or ReplicatedStorage
		
		local template = nil
		-- [설계] 볼라(BOLA) 아이템만 손에 들었을 때 "POUCH" 모델로 표시
		local isBola = itemId:upper():match("BOLA$") or (itemData.optimalTool == "BOLA")
		
		if isBola then
			template = searchRoot:FindFirstChild("POUCH") or searchRoot:FindFirstChild("Pouch")
			-- 못 찾으면 하위 폴더까지 깊이 탐색
			if not template then
				for _, child in ipairs(searchRoot:GetDescendants()) do
					if child.Name:upper() == "POUCH" then
						template = child
						break
					end
				end
			end
		end
		
		-- 기본 탐색 (POUCH가 아니거나 못 찾은 경우 각 아이템 고유 모델 사용)
		if not template then
			template = searchRoot:FindFirstChild(itemId)
			if not template then
				local searchTarget = itemId:lower():gsub("_", "")
				for _, child in ipairs(searchRoot:GetChildren()) do
					if child.Name:lower():gsub("_", "") == searchTarget then 
						template = child 
						break 
					end
				end
			end
		end

		-- 4. 도구 조립
		local tool = Instance.new("Tool")
		tool.Name = itemId
		tool.RequiresHandle = false
		tool.CanBeDropped = false
		
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.5, 0.5, 0.5)
		handle.Transparency = 1
		handle.CanCollide = false
		handle.Massless = true
		handle.Parent = tool
		
		if template then
			local visual = template:Clone()
			
			-- [중요] 아이템 내 모든 스크립트 비활성화 및 핸들 이름 변경
			for _, d in ipairs(visual:GetDescendants()) do
				if d:IsA("Script") or d:IsA("LocalScript") then 
					d.Disabled = true 
				end
				if d:IsA("BasePart") and d.Name == "Handle" then
					d.Name = "ModelPart"
				end
			end

			-- 규격화를 위해 임시 모델에 담기
			local assemblyModel = Instance.new("Model")
			assemblyModel.Name = "VisualContent"
			
			if visual:IsA("Tool") then
				for _, child in ipairs(visual:GetChildren()) do
					if child:IsA("BasePart") or child:IsA("Model") then
						child.Parent = assemblyModel
					end
				end
				visual:Destroy()
			else
				visual.Parent = assemblyModel
			end
			
			assemblyModel.Parent = tool
			
			-- 타입별 크기 최적화
			local targetSize = 1.2 -- 기본 (RESOURCE 등)
			local itemType = itemData.type or ""
			
			if itemType == "TOOL" then
				targetSize = 2.8 -- 곡괭이/도끼 등
			elseif itemType == "WEAPON" then
				-- 창은 훨씬 더 거대하게 (11.0)
				if itemData.optimalTool == "SPEAR" then
					targetSize = 11.0
				else
					targetSize = 4.0
				end
			elseif itemType == "EQUIPMENT" or itemType == "ARMOR" then
				targetSize = 1.5
			elseif itemType == "CONSUMABLE" and itemData.optimalTool then
				targetSize = 2.0 -- 볼라 등 던지는 아이템
			end

			local cf, size = assemblyModel:GetBoundingBox()
			local maxDim = math.max(size.X, size.Y, size.Z)
			if maxDim > 0 then
				local scale = targetSize / maxDim
				assemblyModel:ScaleTo(scale)
				cf, size = assemblyModel:GetBoundingBox() -- 재계산
				assemblyModel:PivotTo(assemblyModel:GetPivot() * cf:Inverse())
				
				-- 볼라: 왼손 위치로 조기 배치
				local isBola = (itemData.optimalTool == "BOLA") or (itemId and itemId:upper():find("BOLA"))
				if isBola then
					local leftHand = char:FindFirstChild("LeftHand") or char:FindFirstChild("Left Arm")
					if leftHand then
						assemblyModel:PivotTo(leftHand.CFrame * CFrame.Angles(math.rad(-90), 0, 0))
					end
				end
			end

			handle.CFrame = CFrame.new(0, 0, 0)
			
			-- 모든 파트 물리 해제 및 용접
			for _, p in ipairs(tool:GetDescendants()) do
				if p:IsA("BasePart") then
					p.CanCollide = false
					p.CanTouch = false
					p.CanQuery = false
					p.Massless = true
					p.Anchored = false
					
					-- 투명한 파트(히트박스 등)는 그대로 투명하게 유지
					if p == handle or p.Transparency > 0.95 then
						p.Transparency = 1
						p.CanCollide = false
						p.CanTouch = false
						p.CanQuery = false
					end
					
					if p ~= handle then
						local w = Instance.new("WeldConstraint")
						
						-- 볼라인 경우 왼손에 용접, 그 외에는 핸들(오른손)에 용접
						local isBola = (itemData.optimalTool == "BOLA") or (itemId and itemId:upper():find("BOLA"))
						local leftHand = char:FindFirstChild("LeftHand") or char:FindFirstChild("Left Arm")
						
						if isBola and leftHand then
							w.Part0 = leftHand
						else
							w.Part0 = handle
						end
						
						w.Part1 = p
						w.Parent = p
					end
				end
			end
		else
			warn("[EquipService] Missing template for:", itemId)
			handle.Transparency = 0
			handle.Material = Enum.Material.Neon
			handle.Color = Color3.fromRGB(255, 255, 0)
		end

		-- 5. 최종 장착
		tool:SetAttribute("ToolType", itemData.optimalTool or itemId:upper())
		
		-- [추가] 타입별 Grip 설정 (쥐는 각도 및 위치 조정)
		if itemData.optimalTool == "PICKAXE" then
			-- 곡괭이: 뾰족한 부분이 정면을 보게 하고 똑바로 쥐도록 수정
			tool.Grip = CFrame.new(0, 0, 1.2) * CFrame.Angles(math.rad(-90), 0, 0)
		elseif itemType == "TOOL" or itemType == "WEAPON" or (itemData.optimalTool == "BOLA") or (itemId and itemId:upper():find("BOLA")) then
			-- 기타 도구/무기/볼라: 손잡이가 손바닥에 밀착되고 날이 정면을 향하도록 90도 회전
			tool.Grip = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(-90), 0, 0)
		else
			-- 자원: 손바닥 위에 오프셋 적용
			tool.Grip = CFrame.new(0, -0.3, 0.2) 
		end
		
		hum:EquipTool(tool)
		
		-- [PHYSICS REFACTOR] 고성능 물리 처리 (루프 탈피)
		task.spawn(function()
			-- 도구가 캐릭터에 부모화될 때까지 대기
			local toolAtChar = tool.Parent == char or tool:GetPropertyChangedSignal("Parent"):Wait()
			if not toolAtChar or not tool.Parent then return end
			
			local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
			if hand then
				-- 1. Motor6D 연결 (순수 물리 배제용)
				local joint = hand:FindFirstChild("RightGripJoint") or Instance.new("Motor6D")
				joint.Name = "RightGripJoint"
				joint.Part0 = hand
				joint.Part1 = handle
				-- Tool.Grip은 Handle 기준이므로 역행렬을 C0에 적용하여 동일 효과 구현
				joint.C0 = tool.Grip:Inverse()
				joint.Parent = hand
				
				-- 2. NoCollisionConstraint 적용 (팔과 도구 사이 충돌 방지)
				for _, p in ipairs(tool:GetDescendants()) do
					if p:IsA("BasePart") then
						local ncc = Instance.new("NoCollisionConstraint")
						ncc.Part0 = p
						ncc.Part1 = hand
						ncc.Parent = p
						
						-- 몸체 충돌도 추가 방지
						local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
						if torso then
							local ncc2 = Instance.new("NoCollisionConstraint")
							ncc2.Part0 = p
							ncc2.Part1 = torso
							ncc2.Parent = p
						end
					end
				end
			end
		end)
	end)
	
	if not success then warn("[EquipService] Critical Error:", err) end
	isEquipping[player.UserId] = nil
end

local function _formatAssetId(id)
	if not id or id == "" or id == 0 then return "" end
	if type(id) == "number" or (type(id) == "string" and not id:find("://")) then
		return "rbxassetid://" .. tostring(id)
	end
	return id
end

--- 캐릭터 외형 업데이트 (방어구 시각화)
function EquipService.updateAppearance(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildWhichIsA("Humanoid")
	if not char or not hum then return end
	
	-- 순환 참조 방지를 위해 지연 로딩
	local InventoryService = require(game:GetService("ServerScriptService").Server.Services.InventoryService)
	local equip = InventoryService.getEquipment(player.UserId)
	if not equip then return end
	
	-- 0. 기존 장착 모델(Accessory) 제거 (ARMOR 태그가 붙은 것들)
	for _, acc in ipairs(char:GetChildren()) do
		if acc:IsA("Accessory") and acc:GetAttribute("IsArmor") then
			acc:Destroy()
		end
	end
	
	local shirt = char:FindFirstChildOfClass("Shirt") or Instance.new("Shirt", char)
	local pants = char:FindFirstChildOfClass("Pants") or Instance.new("Pants", char)
	
	-- 1. 상의/하의/한벌옷 텍스처 적용
	local suitItem = equip.SUIT and DataService.getItem(equip.SUIT.itemId)
	local topItem = equip.TOP and DataService.getItem(equip.TOP.itemId)
	local botItem = equip.BOTTOM and DataService.getItem(equip.BOTTOM.itemId)
	
	if suitItem then
		shirt.ShirtTemplate = _formatAssetId(suitItem.shirtId)
		pants.PantsTemplate = _formatAssetId(suitItem.pantsId)
		-- 3D 모델이 있다면 적용
		if suitItem.modelId then
			EquipService._applyArmorModel(char, suitItem.modelId)
		end
	else
		shirt.ShirtTemplate = _formatAssetId(topItem and topItem.shirtId)
		pants.PantsTemplate = _formatAssetId(botItem and botItem.pantsId)
		
		if topItem and topItem.modelId then
			EquipService._applyArmorModel(char, topItem.modelId)
		end
		if botItem and botItem.modelId then
			EquipService._applyArmorModel(char, botItem.modelId)
		end
	end
	
	-- 2. 투구(HEAD) 적용
	local headItem = equip.HEAD and DataService.getItem(equip.HEAD.itemId)
	if headItem and headItem.modelId then
		EquipService._applyArmorModel(char, headItem.modelId)
	end
end

--- 3D 아머 모델 적용 내부 함수 (Accessory 방식)
function EquipService._applyArmorModel(char, modelId)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local armorFolder = assets and (assets:FindFirstChild("ArmorModels") or assets:FindFirstChild("Models"))
	if not armorFolder then return end
	
	local template = armorFolder:FindFirstChild(modelId)
	if template then
		local acc = template:Clone()
		if acc:IsA("Accessory") then
			acc:SetAttribute("IsArmor", true)
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then hum:AddAccessory(acc) end
		end
	end
end

return EquipService
