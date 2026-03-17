-- UITheme.lua
-- UI 컬러 및 폰트 테마 정의 (Durango Style)

local UITheme = {
	Colors = {
		-- Overlays & Panels (Minimalist Glass)
		BG_OVERLAY    = Color3.fromRGB(0, 0, 0),
		BG_PANEL      = Color3.fromRGB(5, 7, 10), 
		BG_PANEL_L    = Color3.fromRGB(25, 27, 30), 
		BG_DARK       = Color3.fromRGB(0, 0, 0),    
		
		BG_SLOT       = Color3.fromRGB(15, 17, 20), 
		BG_SLOT_SEL   = Color3.fromRGB(40, 45, 55), 
		GOLD_SEL      = Color3.fromRGB(255, 230, 100), 
		
		-- Borders & Strokes (Subtle)
		BORDER        = Color3.fromRGB(60, 65, 75), -- 어둡고 은은한 외곽선 (하얀색 제거)
		BORDER_DIM    = Color3.fromRGB(40, 42, 48),
		BORDER_SEL    = Color3.fromRGB(245, 215, 80),

		-- Bars (Modern & Flat)
		HP            = Color3.fromRGB(255, 60, 60),  
		HP_BG         = Color3.fromRGB(30, 10, 10),
		STA           = Color3.fromRGB(255, 225, 50), 
		STA_BG        = Color3.fromRGB(40, 35, 5),
		HUNGER        = Color3.fromRGB(100, 255, 120), 
		XP            = Color3.fromRGB(100, 255, 50), -- 연두색 (Vivid Light Green)
		XP_BG         = Color3.fromRGB(15, 30, 15),

		-- Text (Modern Clean)
		WHITE         = Color3.fromRGB(255, 255, 255),
		INK           = Color3.fromRGB(220, 220, 220),
		GRAY          = Color3.fromRGB(150, 155, 165),
		DIM           = Color3.fromRGB(90, 95, 105),
		GOLD          = Color3.fromRGB(255, 230, 100),
		GREEN         = Color3.fromRGB(100, 255, 120),
		RED           = Color3.fromRGB(255, 70, 70),
		ORANGE        = Color3.fromRGB(255, 160, 50),

		-- Buttons
		BTN           = Color3.fromRGB(20, 22, 28),
		BTN_H         = Color3.fromRGB(45, 50, 60),
		BTN_DIS       = Color3.fromRGB(15, 17, 20),
		
		-- Rarities
		COMMON        = Color3.fromRGB(160, 165, 175),
		UNCOMMON      = Color3.fromRGB(80, 230, 80),
		RARE          = Color3.fromRGB(60, 140, 255),
		EPIC          = Color3.fromRGB(170, 70, 255),
		LEGENDARY     = Color3.fromRGB(255, 160, 30),
	},
	
	Fonts = {
		-- Roblox built-in font preset tuned for a rougher survival-style tone.
		TITLE  = Enum.Font.Cartoon,
		NORMAL = Enum.Font.Gotham,
		NUM    = Enum.Font.Highway,
		CLASSIC = Enum.Font.Gotham,
	},

	Transp = {
		PANEL = 0.95, -- 거의 투명하게
		SLOT  = 0.6,
		BG    = 0.95,
	}
}

return UITheme
