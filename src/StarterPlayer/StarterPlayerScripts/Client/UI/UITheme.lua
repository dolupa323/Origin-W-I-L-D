-- UITheme.lua
-- UI 컬러 및 폰트 테마 정의 (Durango Style)

local UITheme = {
	Colors = {
		-- Overlays & Panels
		BG_OVERLAY    = Color3.fromRGB(0, 0, 0),
		BG_PANEL      = Color3.fromRGB(15, 17, 15), -- 살짝 탁한 어두운 색
		BG_PANEL_L    = Color3.fromRGB(28, 30, 28),
		BG_SLOT       = Color3.fromRGB(18, 20, 18), -- 빈 슬롯
		BG_SLOT_SEL   = Color3.fromRGB(40, 42, 40),
		GOLD_SEL      = Color3.fromRGB(250, 210, 74), -- 듀랑고 특유의 골드/옐로우
		
		-- Borders
		BORDER        = Color3.fromRGB(180, 180, 180),
		BORDER_DIM    = Color3.fromRGB(45, 50, 45),
		BORDER_SEL    = Color3.fromRGB(250, 210, 74),

		-- Bars
		HP            = Color3.fromRGB(210, 40, 40),
		HP_BG         = Color3.fromRGB(50, 15, 15),
		STA           = Color3.fromRGB(40, 150, 220), -- 스태미너 블루
		STA_BG        = Color3.fromRGB(10, 35, 55),
		HUNGER        = Color3.fromRGB(220, 110, 40), -- 배고픔 오렌지
		XP            = Color3.fromRGB(140, 200, 80),

		-- Text
		WHITE         = Color3.fromRGB(240, 240, 240),
		GRAY          = Color3.fromRGB(150, 150, 150),
		DIM           = Color3.fromRGB(100, 100, 100),
		GOLD          = Color3.fromRGB(250, 210, 74),
		GREEN         = Color3.fromRGB(120, 200, 80),
		RED           = Color3.fromRGB(230, 50, 50),

		-- Buttons
		BTN           = Color3.fromRGB(35, 38, 35),
		BTN_H         = Color3.fromRGB(50, 55, 50),
		BTN_DIS       = Color3.fromRGB(25, 27, 25),
		
		-- Crafting/Tech States
		LOCK          = Color3.fromRGB(40, 40, 40),
		SUCCESS       = Color3.fromRGB(60, 90, 60),
	},
	
	Fonts = {
		TITLE  = Enum.Font.GothamBold,
		NORMAL = Enum.Font.Gotham,
		NUM    = Enum.Font.GothamMedium,
	},

	Transp = {
		PANEL = 0.85, -- 듀랑고 레이아웃은 반투명함
		SLOT  = 0.4,
		BG    = 0.5,
	}
}

return UITheme
