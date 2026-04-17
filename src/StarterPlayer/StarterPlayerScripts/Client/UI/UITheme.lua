-- UITheme.lua
-- UI 컬러 및 폰트 테마 정의 (Dark Glass + Gold Metallic)

local UITheme = {
	Colors = {
		-- Overlays & Panels (Cool Dark Glass)
		BG_OVERLAY    = Color3.fromRGB(10, 10, 15),
		BG_PANEL      = Color3.fromRGB(20, 20, 28),
		BG_PANEL_L    = Color3.fromRGB(32, 32, 42),
		BG_DARK       = Color3.fromRGB(12, 12, 18),

		BG_SLOT       = Color3.fromRGB(28, 28, 38),
		BG_SLOT_SEL   = Color3.fromRGB(50, 48, 40),
		GOLD_SEL      = Color3.fromRGB(255, 225, 90),

		-- Borders & Strokes (Gold Metallic)
		BORDER        = Color3.fromRGB(170, 140, 60),
		BORDER_DIM    = Color3.fromRGB(65, 58, 35),
		BORDER_SEL    = Color3.fromRGB(255, 210, 60),

		-- Bars
		HP            = Color3.fromRGB(200, 50, 40),
		HP_BG         = Color3.fromRGB(40, 15, 15),
		STA           = Color3.fromRGB(230, 185, 50),
		STA_BG        = Color3.fromRGB(42, 38, 15),
		HUNGER        = Color3.fromRGB(80, 200, 90),
		XP            = Color3.fromRGB(120, 220, 60),
		XP_BG         = Color3.fromRGB(20, 30, 15),

		-- Text (Clean Modern)
		WHITE         = Color3.fromRGB(240, 238, 230),
		INK           = Color3.fromRGB(200, 198, 190),
		GRAY          = Color3.fromRGB(145, 142, 135),
		DIM           = Color3.fromRGB(95, 92, 85),
		GOLD          = Color3.fromRGB(255, 210, 60),
		GREEN         = Color3.fromRGB(90, 210, 90),
		RED           = Color3.fromRGB(220, 60, 50),
		ORANGE        = Color3.fromRGB(235, 155, 45),

		-- Buttons (Glassmorphism + Yellow Action)
		BTN           = Color3.fromRGB(255, 200, 40),  -- Primary Action (Yellow)
		BTN_H         = Color3.fromRGB(255, 225, 90),  -- Primary Action Hover
		BTN_GRAY      = Color3.fromRGB(45, 45, 52),    -- Neutral/Negative Action (Gray)
		BTN_GRAY_H    = Color3.fromRGB(65, 65, 75),
		BTN_DIS       = Color3.fromRGB(25, 25, 30),

		-- Rarities
		COMMON        = Color3.fromRGB(175, 172, 160),
		UNCOMMON      = Color3.fromRGB(80, 200, 80),
		RARE          = Color3.fromRGB(70, 150, 245),
		EPIC          = Color3.fromRGB(180, 80, 240),
		LEGENDARY     = Color3.fromRGB(255, 200, 40),

		-- Accent
		PARCHMENT     = Color3.fromRGB(180, 170, 150),
		WOOD_DARK     = Color3.fromRGB(35, 32, 28),
		WOOD_LIGHT    = Color3.fromRGB(90, 80, 60),
	},

	Fonts = {
		TITLE  = Enum.Font.GothamMedium,
		NORMAL = Enum.Font.Gotham,
		NUM    = Enum.Font.RobotoMono,
		CLASSIC = Enum.Font.Gotham,
	},

	Transp = {
		PANEL = 0.72,  -- More transparent for even cleaner Glassmorphism
		SLOT  = 0.70,  -- Lighten slots
		BG    = 0.50,
	}
}

return UITheme
