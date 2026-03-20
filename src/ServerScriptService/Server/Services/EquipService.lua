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
local TechService = nil -- Phase 6: 기술 해금 검증 (Relinquish 어뷰징 방지)

-- 모델 캐시 (O(1) 조회를 위한 인덱스)
local modelCache = {} 
local armorCache = {}

--========================================
-- Public API
--========================================

--- 모델 인덱싱 (서버 부팅 시 1회 실행)
local function indexAssets()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return end
	
	-- 1. 아이템 모델 인덱싱 (ItemModels, LootModels, Models 폴더 및 하위 모든 모델)
	local folders = {assets:FindFirstChild("ItemModels"), assets:FindFirstChild("LootModels"), assets:FindFirstChild("Models"), assets}
	for _, folder in ipairs(folders) do
		if not folder then continue end
		for _, child in ipairs(folder:GetDescendants()) do -- GetDescendants()로 변경하여 하위 폴더 대응
			if child:IsA("Model") or child:IsA("BasePart") or child:IsA("MeshPart") or child:IsA("Tool") then
				-- 원본 이름 저장
				if not modelCache[child.Name] then
					modelCache[child.Name] = child
				end
				-- 정규화된 이름 저장 (검색용)
				local norm = child.Name:lower():gsub("_", "")
				if not modelCache[norm] then
					modelCache[norm] = child
				end
			end
		end
	end
	
	-- 2. 아머 모델 인덱싱 (ArmorModels, Models 폴더 및 하위 모든 액세서리)
	local armorFolders = {assets:FindFirstChild("ArmorModels"), assets:FindFirstChild("Models")}
	for _, folder in ipairs(armorFolders) do
		if not folder then continue end
		for _, child in ipairs(folder:GetDescendants()) do -- GetDescendants()로 변경
			if child:IsA("Accessory") or child:IsA("Model") then
				armorCache[child.Name] = child
			end
		end
	end
	
	print(string.format("[EquipService] Indexed %d models and %d armor sets (including subfolders)", 
		table.count and table.count(modelCache) or 0, 
		table.count and table.count(armorCache) or 0))
end

function EquipService.Init(_DataService, _TechService)
	if initialized then return end
	DataService = _DataService
	TechService = _TechService
	
	indexAssets()
	
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
		local itemType = itemData.type or ""
		
		-- [보안/기획] 기술 해금 체크 (Relinquish 어뷰징 방지)
		if TechService and not TechService.isRecipeUnlocked(player.UserId, itemId) then
			warn(string.format("[EquipService] Item %s is locked for player %d", itemId, player.UserId))
			EquipService.unequipAll(player)
			isEquipping[player.UserId] = nil
			return
		end
		
		-- 3. 에셋 탐색 (모델명 매핑 우선 순위 적용)
		local modelName = itemData.modelName or itemId
		local template = modelCache[modelName] or modelCache[modelName:lower():gsub("_", "")]
		
		-- [추가] modelName으로 실패 시 itemId로 재시도
		if not template and modelName ~= itemId then
			template = modelCache[itemId] or modelCache[itemId:lower():gsub("_", "")]
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
			
			if itemType == "TOOL" then
				targetSize = 2.8 -- 곡괭이/도끼 등
			elseif itemType == "WEAPON" then
				-- 창은 훨씬 더 거대하게 (11.0)
				if itemData.optimalTool == "SPEAR" then
					targetSize = 9.0 -- 10.0도 길 수 있으니 조금 더 줄임
				else
					targetSize = 4.0
				end
			elseif itemType == "EQUIPMENT" or itemType == "ARMOR" then
				targetSize = 1.5
			elseif itemType == "CONSUMABLE" and itemData.optimalTool then
				targetSize = 2.0 -- 소모품 등
			elseif itemType == "DNA" then
				targetSize = 0.8 -- DNA 샘플
			elseif itemId == "LOG" or itemId == "WOOD" then
				-- [UX 개선] 통나무와 나무는 자원이지만 적당히 큼직하게 (스틱 현상 방지)
				targetSize = 3.5
			end

			local cf, size = assemblyModel:GetBoundingBox()
			local maxDim = math.max(size.X, size.Y, size.Z)
			if maxDim > 0 then
				local scale = targetSize / maxDim
				assemblyModel:ScaleTo(scale)
				cf, size = assemblyModel:GetBoundingBox() -- 재계산
				assemblyModel:PivotTo(assemblyModel:GetPivot() * cf:Inverse())
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
						w.Part0 = handle
						w.Part1 = p
						w.Parent = p
					end
				end
			end
		else
			if itemType ~= "RESOURCE" then
				warn("[EquipService] Missing template for:", itemId)
			end
			handle.Transparency = 0
			handle.Material = Enum.Material.Neon
			handle.Color = Color3.fromRGB(255, 255, 0)
		end

		-- 5. 최종 장착
		tool.Name = itemId
		-- [핵심 해결] 창이 땅에 떨어지는 원인이었던 모든 커스텀 물리 관절 의존성을 버리고 로블록스 기본 엔진 사용
		tool.RequiresHandle = true 
		tool:SetAttribute("ItemId", itemId)
		tool:SetAttribute("ToolType", itemData.optimalTool or itemId:upper())
		
		-- [추가] 타입별 Grip 설정 (쥐는 각도 및 위치 조정)
		if itemData.optimalTool == "PICKAXE" then
			tool.Grip = CFrame.new(0, 0, 1.2) * CFrame.Angles(math.rad(-90), 0, 0)
		elseif itemData.optimalTool == "AXE" then
			-- 도끼: 손잡이를 수직으로 쥐도록 각도 초기화 및 오프셋 조정
			tool.Grip = CFrame.new(0, -0.8, 0) * CFrame.Angles(0, 0, 0)
		elseif itemData.optimalTool == "SPEAR" then
			-- 창: Z축(가로) 오프셋을 0으로 만들어 손에 딱 붙이고, Y축(세로)를 -1.5로 내려 아래쪽을 쥐게 함
			tool.Grip = CFrame.new(0, -1.5, 0) * CFrame.Angles(0, 0, 0)
		elseif itemData.optimalTool == "BOW" then
			-- 활대를 세로로 세우고, 활줄이 몸쪽을 향하도록 축을 뒤집어 정렬.
			tool.Grip = CFrame.new(0.05, -0.24, -0.40) * CFrame.Angles(math.rad(-88), math.rad(180), math.rad(90))
		elseif itemData.optimalTool == "CROSSBOW" then
			-- 석궁은 활보다 약간 낮고 전방을 향하도록 분리 세팅.
			tool.Grip = CFrame.new(0.14, -0.30, -0.56) * CFrame.Angles(math.rad(2), math.rad(90), math.rad(86))
		elseif itemType == "TOOL" or itemType == "WEAPON" then
			tool.Grip = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(-90), 0, 0)
		else
			tool.Grip = CFrame.new(0, -0.3, 0.2) 
		end
		
		hum:EquipTool(tool)
		
		-- [PHYSICS REFACTOR] 고성능 물리 처리 (루프 탈피)
		task.spawn(function()
			-- [수정] Wait()의 반환값은 불리언이 아니므로 명시적으로 분리하여 대기
			if tool.Parent ~= char then
				tool:GetPropertyChangedSignal("Parent"):Wait()
			end
			-- 대기 후 부모가 정확히 캐릭터인지 한 번 더 확인
			if not tool.Parent or tool.Parent ~= char then return end
			
			local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
			if hand then
				-- [안정성 보장] 튕김, 땅에 떨어짐 버그 유발 요소였던 Motor6D 생성코드 완전 제거.
				-- tool.RequiresHandle = true에 의해엔진이 RightGrip(Weld)을 완벽히 생성함.
				
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

local function _formatAssetId(id, fallback)
	if not id or id == "" or id == 0 then return fallback or "" end
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
	
	-- 1. 한벌옷 텍스처 적용 (상의/하의 슬롯은 제거됨)
	local suitItem = equip.SUIT and DataService.getItem(equip.SUIT.itemId)
	
	-- [FIX] 장비가 없는 경우 기본 원시인 의상 유지
	local Appearance = require(ReplicatedStorage.Shared.Config.Appearance)
	local defaultShirt = Appearance.CLOTHING_IDS.DEFAULT_SHIRT
	local defaultPants = Appearance.CLOTHING_IDS.DEFAULT_PANTS
	
	if suitItem then
		shirt.ShirtTemplate = _formatAssetId(suitItem.shirtId)
		pants.PantsTemplate = _formatAssetId(suitItem.pantsId)
		-- 3D 모델이 있다면 적용
		if suitItem.modelId then
			EquipService._applyArmorModel(char, suitItem.modelId)
		end
	else
		shirt.ShirtTemplate = _formatAssetId(nil, defaultShirt)
		pants.PantsTemplate = _formatAssetId(nil, defaultPants)
	end
	
	-- 2. 투구(HEAD) 적용
	local headItem = equip.HEAD and DataService.getItem(equip.HEAD.itemId)
	if headItem and headItem.modelId then
		EquipService._applyArmorModel(char, headItem.modelId)
	end
end

--- 3D 아머 모델 적용 내부 함수 (Accessory 방식)
function EquipService._applyArmorModel(char, modelId)
	local template = armorCache[modelId]
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
