-- AnimationManager.lua
-- 자산(Assets) 폴더의 애니메이션 개체를 관리하는 중앙 관리자
-- 하드코딩된 ID 대신 애니메이션 이름을 사용하여 재생

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationManager = {}

--========================================
-- Constants
--========================================
local ASSETS_PATH = "Assets/Animations"

--========================================
-- Internal Helpers
--========================================

--- 애니메이션 개체 찾기
local function findAnimation(animName: string): Animation?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return nil end
	
	local animFolder = assets:FindFirstChild("Animations")
	if not animFolder then return nil end
	
	return animFolder:FindFirstChild(animName, true) -- 재귀적으로 찾기
end

--========================================
-- Public API
--========================================

--- 애니메이션 로드 및 트랙 반환
function AnimationManager.load(humanoid: Humanoid, animName: string): AnimationTrack?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	
	local animObject = findAnimation(animName)
	if not animObject then
		warn(string.format("[AnimationManager] Animation '%s' not found in ReplicatedStorage.Assets.Animations", animName))
		
		-- 폴백: 만약 에셋에 없다면 임시로라도 생성해야 할 수도 있지만, 
		-- 사용자 요청은 "하드코딩 제거"이므로 에셋 폴더를 정적으로 사용하는 것을 원칙으로 함.
		return nil
	end
	
	return animator:LoadAnimation(animObject)
end

--- 애니메이션 즉시 재생
function AnimationManager.play(humanoid: Humanoid, animName: string, fadeTime: number?, weight: number?, speed: number?): AnimationTrack?
	local track = AnimationManager.load(humanoid, animName)
	if track then
		track:Play(fadeTime or 0.1, weight, speed)
		return track
	end
	return nil
end

return AnimationManager
