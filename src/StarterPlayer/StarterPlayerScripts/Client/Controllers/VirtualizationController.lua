-- VirtualizationController.lua
-- 클라이언트 사이드 가상화 (Entity Virtualization)
-- [FIX] Parent 변경 방식의 가상화는 리플리케이션 끊김(Ghost Object)을 유발하므로
-- Transparency 및 Collision 제어 방식으로 변경하였습니다.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local VirtualizationController = {}

--========================================
-- Constants
--========================================
local RENDER_DISTANCE = 400 -- 렌더링 거리 (스터드)
local UPDATE_INTERVAL = 0.3 -- 업데이트 주기 (초)

-- 가상화 대상 폴더
local TARGET_FOLDERS = {
	"ResourceNodes",
	"Facilities",
	"WorldDrops",
	"Creatures"
}

--========================================
-- Internal State
--========================================
local initialized = false
local player = Players.LocalPlayer
local virtualizedMetadata = {} -- [instance] = { originalState }

--========================================
-- Private Functions
--========================================

--- 엔티티의 가시성 및 물리 속성 설정
local function _setEntityVisible(entity: Instance, visible: boolean)
	if visible then
		local metadata = virtualizedMetadata[entity]
		if not metadata then return end
		
		-- 원본 상태 복원
		for part, state in pairs(metadata.parts) do
			if part.Parent then
				part.Transparency = state.Transparency
				part.CanCollide = state.CanCollide
				part.CanQuery = state.CanQuery
				part.CanTouch = state.CanTouch
			end
		end
		
		-- UI 복원
		for gui, state in pairs(metadata.guis) do
			if gui.Parent then
				gui.Enabled = state.Enabled
			end
		end
		
		virtualizedMetadata[entity] = nil
	else
		-- 이미 숨겨진 상태면 무시
		if virtualizedMetadata[entity] then return end
		
		local metadata = {
			parts = {},
			guis = {}
		}
		
		-- 모든 파트 숨기기 및 물리 비활성화
		for _, descendant in ipairs(entity:GetDescendants()) do
			if descendant:IsA("BasePart") then
				metadata.parts[descendant] = {
					Transparency = descendant.Transparency,
					CanCollide = descendant.CanCollide,
					CanQuery = descendant.CanQuery,
					CanTouch = descendant.CanTouch
				}
				descendant.Transparency = 1
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
			elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
				-- Decal 등은 별도 Transparency만 저장 (Part의 Transparency에 영향받지 않는 경우 대비)
				metadata.parts[descendant] = { Transparency = descendant.Transparency }
				descendant.Transparency = 1
			elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") then
				metadata.guis[descendant] = { Enabled = descendant.Enabled }
				descendant.Enabled = false
			end
		end
		
		virtualizedMetadata[entity] = metadata
	end
end

--- 가상화 레이어 업데이트
local function updateVirtualization()
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	local playerPos = hrp.Position
	
	for _, folderName in ipairs(TARGET_FOLDERS) do
		local folder = Workspace:FindFirstChild(folderName)
		if not folder then continue end
		
		for _, entity in ipairs(folder:GetChildren()) do
			local primary = (entity:IsA("BasePart") and entity) or entity.PrimaryPart or entity:FindFirstChildWhichIsA("BasePart")
			if not primary then continue end
			
			local dist = (primary.Position - playerPos).Magnitude
			local shouldHide = dist > RENDER_DISTANCE
			local isCurrentlyHidden = virtualizedMetadata[entity] ~= nil
			
			if shouldHide and not isCurrentlyHidden then
				_setEntityVisible(entity, false)
			elseif not shouldHide and isCurrentlyHidden then
				_setEntityVisible(entity, true)
			end
		end
	end
end

--========================================
-- Public API
--========================================

function VirtualizationController.Init()
	print("[VirtualizationController] Deactivated. Using native StreamingEnabled instead.")
end

return VirtualizationController
