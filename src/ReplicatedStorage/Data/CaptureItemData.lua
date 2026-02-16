-- CaptureItemData.lua
-- Phase 5-1: 포획 도구 데이터 정의

local CaptureItemData = {
	CAPTURE_SPHERE_BASIC = {
		id = "CAPTURE_SPHERE_BASIC",
		name = "기본 포획구",
		description = "약해진 크리처를 포획할 수 있는 기본 도구",
		captureMultiplier = 1.0,   -- 포획률 배율
		maxRange = 30,             -- 투척 사거리 (스터드)
		rarity = "COMMON",
	},
	CAPTURE_SPHERE_MEGA = {
		id = "CAPTURE_SPHERE_MEGA",
		name = "고급 포획구",
		description = "더 높은 포획률을 가진 개량형 포획구",
		captureMultiplier = 1.5,   -- 1.5배 포획률
		maxRange = 35,
		rarity = "UNCOMMON",
	},
	CAPTURE_SPHERE_ULTRA = {
		id = "CAPTURE_SPHERE_ULTRA",
		name = "마스터 포획구",
		description = "최고급 포획구. 거의 확실한 포획이 가능",
		captureMultiplier = 2.5,   -- 2.5배 포획률
		maxRange = 40,
		rarity = "RARE",
	},
}

return CaptureItemData
