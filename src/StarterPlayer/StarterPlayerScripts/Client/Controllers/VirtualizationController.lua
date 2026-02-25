-- VirtualizationController.lua
-- 클라이언트 사이드 가상화 (Entity Virtualization)
-- 플레이어와의 거리에 따라 가상 객체(노드, 구조물, 드롭)의 가시성 및 렌더링을 제어하여 성능 최적화

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local VirtualizationController = {}

--========================================
-- Constants
--========================================
local RENDER_DISTANCE = 400 -- 렌더링 거리 (스터드)
local UPDATE_INTERVAL = 0.3 -- 업데이트 주기 (초) - 더 빠르게 반응하도록 상향 (1.0 -> 0.3)

-- 가상화 대상 폴더 및 매핑
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
local storageFolder = nil -- 비활성 객체 임시 저장소
local originalParents = {} -- [instance] = originalParentFolder

--========================================
-- Private Functions
--========================================

--- 가상화 레이어 업데이트
local function updateVirtualization()
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	local playerPos = hrp.Position
	
	-- 1. 현재 Workspace에 있는 대상 체크 -> 멀면 숨기기
	for _, folderName in ipairs(TARGET_FOLDERS) do
		local folder = Workspace:FindFirstChild(folderName)
		if not folder then continue end
		
		for _, entity in ipairs(folder:GetChildren()) do
			-- 이미 숨겨진 대상(Attribute 등)은 스킵하거나 검증
			local primary = entity.PrimaryPart or entity:FindFirstChildWhichIsA("BasePart")
			if not primary then continue end
			
			local dist = (primary.Position - playerPos).Magnitude
			if dist > RENDER_DISTANCE then
				-- 숨기기 (원래 폴더 기록)
				originalParents[entity] = folder
				entity.Parent = storageFolder
				-- print("[Virtualization] Hidden:", entity.Name)
			end
		end
	end
	
	-- 2. Storage에 있는 대상 체크 -> 가까우면 다시 표시
	if storageFolder then
		for _, entity in ipairs(storageFolder:GetChildren()) do
			-- PrimaryPart 위치가 업데이트되지 않을 수 있으므로 (Creatures의 경우)
			-- 하지만 서버에서 물리 연산을 하므로 위치는 동기화됨
			local primary = entity.PrimaryPart or entity:FindFirstChildWhichIsA("BasePart")
			if not primary then continue end
			
			local dist = (primary.Position - playerPos).Magnitude
			if dist <= RENDER_DISTANCE then
				-- 다시 표시
				local originalParent = originalParents[entity]
				if originalParent and originalParent.Parent == Workspace then
					entity.Parent = originalParent
				else
					-- 원본 폴더가 유효하지 않으면 이름으로 찾기 시도
					-- Note: 보통 originalParent가 유지되어야 함
					originalParents[entity] = nil -- 초기화
				end
				-- print("[Virtualization] Restored:", entity.Name)
			end
		end
	end
end

--========================================
-- Public API
--========================================

function VirtualizationController.Init()
	if initialized then return end
	
	-- 비활성 저장소 폴더 생성 (서버 ReplicatedStorage와 혼동되지 않게 Client 전용)
	storageFolder = Instance.new("Folder")
	storageFolder.Name = "ClientVirtualizationStorage"
	-- Workspace에 두되, Physics와 Rendering이 최소화되는 곳은 Parent=nil 또는 전용 폴더
	-- ReplicatedStorage는 클라이언트 생성 인스턴스 보관 시 유용
	storageFolder.Parent = ReplicatedStorage
	
	-- 주기적 업데이트
	task.spawn(function()
		while true do
			task.wait(UPDATE_INTERVAL)
			-- 에러 방지를 위해 pcall 사용 (삭제된 객체 등)
			local success, err = pcall(updateVirtualization)
			if not success then
				-- warn("[VirtualizationController] Update error:", err)
			end
		end
	end)
	
	-- 엔티티가 디스트로이될 때 캐시 정리
	-- DescendantRemoving은 Workspace에서만 동작하므로 storageFolder도 같이 감시
	local function onRemoving(item)
		originalParents[item] = nil
	end
	
	Workspace.DescendantRemoving:Connect(onRemoving)
	storageFolder.DescendantRemoving:Connect(onRemoving)
	
	initialized = true
	print("[VirtualizationController] Initialized (Distance: " .. RENDER_DISTANCE .. ")")
end

return VirtualizationController
