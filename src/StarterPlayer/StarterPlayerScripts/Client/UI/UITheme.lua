-- UITheme.lua
-- UI 컬러 및 폰트 테마 정의 (Original Durango Style)

local UITheme = {
	Colors = {
		-- Overlays & Panels
		BG_OVERLAY    = Color3.fromRGB(0, 0, 0),
		BG_PANEL      = Color3.fromRGB(15, 15, 15), -- 진한 블랙
		BG_PANEL_L    = Color3.fromRGB(30, 30, 35),
		BG_SLOT       = Color3.fromRGB(10, 10, 10), -- 슬롯은 거의 검은색
		BG_SLOT_HOVER = Color3.fromRGB(40, 40, 45),
		BG_SLOT_SEL   = Color3.fromRGB(255, 210, 80), -- 밝은 골드
		GOLD_SEL      = Color3.fromRGB(245, 185, 45),
		BG_BAR        = Color3.fromRGB(20, 20, 25),

		-- Borders
		BORDER        = Color3.fromRGB(200, 200, 200),
		BORDER_DIM    = Color3.fromRGB(60, 60, 65),
		BORDER_SEL    = Color3.fromRGB(255, 210, 80),

		-- Bars (HUD) - Screen 2 참고
		HP            = Color3.fromRGB(220, 60, 60),
		HP_BG         = Color3.fromRGB(60, 20, 20),
		STA           = Color3.fromRGB(245, 185, 45), -- Durango 스타일 노란색/골드
		STA_BG        = Color3.fromRGB(60, 45, 10),
		HARVEST       = Color3.fromRGB(255, 255, 255),
		HARVEST_BG    = Color3.fromRGB(40, 40, 40),
		XP            = Color3.fromRGB(180, 220, 100), -- 연두색 XP
		XP_BG         = Color3.fromRGB(25, 35, 15),

		-- Text
		WHITE         = Color3.fromRGB(245, 245, 245),
		GRAY          = Color3.fromRGB(160, 160, 165),
		DIM           = Color3.fromRGB(90, 90, 100),
		GOLD          = Color3.fromRGB(255, 210, 80),
		GREEN         = Color3.fromRGB(140, 220, 100),
		RED           = Color3.fromRGB(255, 70, 70),

		-- Buttons
		BTN           = Color3.fromRGB(35, 35, 40),
		BTN_H         = Color3.fromRGB(55, 55, 65),
		BTN_CRAFT     = Color3.fromRGB(245, 185, 45),
		BTN_CRAFT_H   = Color3.fromRGB(255, 210, 80),
		BTN_CLOSE     = Color3.fromRGB(255, 255, 255),
		BTN_DIS       = Color3.fromRGB(30, 30, 30),

		-- Tech Tree
		NODE          = Color3.fromRGB(10, 10, 15),
		NODE_BD       = Color3.fromRGB(180, 180, 185),
		NODE_SEL      = Color3.fromRGB(245, 185, 45),
		LOCK          = Color3.fromRGB(50, 50, 55),
	},
	
	Fonts = {
		TITLE  = Enum.Font.GothamBold,
		NORMAL = Enum.Font.Gotham,
		NUM    = Enum.Font.GothamMedium,
	},

	Transp = {
		PANEL = 0.65,
		SLOT  = 0.4,
		BG    = 0.5,
	}
}

return UITheme
