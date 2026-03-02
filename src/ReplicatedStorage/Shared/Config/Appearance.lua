-- Appearance.lua
-- 캐릭터 외형 및 디자인 리소스 관련 하드코딩 상수 중앙 관리소

local Appearance = {
	-- 피부 톤 (황갈색 계열)
	SKIN_TONES = {
		Color3.fromRGB(180, 140, 100),  -- 황갈색
		Color3.fromRGB(160, 120, 85),   -- 진한 황갈색
		Color3.fromRGB(200, 160, 120),  -- 밝은 황갈색
		Color3.fromRGB(140, 100, 70),   -- 어두운 갈색
	},
	
	-- 머리카락 색상 (짙은 갈색/검정)
	HAIR_COLORS = {
		Color3.fromRGB(35, 25, 20),   -- 검정
		Color3.fromRGB(60, 40, 30),   -- 짙은 갈색
		Color3.fromRGB(80, 55, 40),   -- 갈색
	},
	
	-- 원시 의상 색상 (가죽/모피)
	CLOTHING_COLORS = {
		Color3.fromRGB(101, 67, 33),   -- 가죽 갈색
		Color3.fromRGB(85, 60, 42),    -- 어두운 가죽
		Color3.fromRGB(139, 90, 43),   -- 밝은 가죽
		Color3.fromRGB(110, 80, 50),   -- 모피 색
	},

	-- 의상 에셋 ID (기본 가죽 셔츠/바지)
	CLOTHING_IDS = {
		DEFAULT_SHIRT = "rbxassetid://398633812", 
		DEFAULT_PANTS = "rbxassetid://398633812"
	}
}

return Appearance
