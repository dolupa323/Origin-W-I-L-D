-- AnimationIds.lua
-- 게임에서 사용하는 애니메이션 논리적 이름 (ID 제거됨)
-- 실제 ID는 ReplicatedStorage.Assets.Animations의 Animation 개체에 설정되어야 함

local AnimationIds = {}

--========================================
-- 이동 애니메이션
--========================================
AnimationIds.ROLL = {
	FORWARD = "RollForward",
	BACKWARD = "RollBackward",
	LEFT = "RollLeft",
	RIGHT = "RollRight",
}

--========================================
-- 전투 애니메이션 (맨손)
--========================================
AnimationIds.ATTACK_UNARMED = {
	SWING_1 = "AttackUnarmed_1",
	SWING_2 = "AttackUnarmed_2",
	SWING_3 = "AttackUnarmed_3",
}

--========================================
-- 전투 애니메이션 (도구/무기)
--========================================
AnimationIds.ATTACK_TOOL = {
	SWING = "AttackTool_Swing",
	OVERHEAD = "AttackTool_Overhead",
}

AnimationIds.ATTACK_SWORD = {
	SLASH = "AttackSword_Slash",
	SWING = "AttackSword_Swing",
}

AnimationIds.ATTACK_CLUB = {
	SMASH = "AttackClub_Smash",
	SWING = "AttackClub_Swing",
}

AnimationIds.BOLA = {
	THROW = "AttackBola_Throw",
}

AnimationIds.ATTACK_BOW = {
	DRAW = "AttackBow_Draw",
}

--========================================
-- 채집 애니메이션
--========================================
AnimationIds.HARVEST = {
	GATHER = "HarvestGather",
	CHOP = "HarvestChop",
	MINE = "HarvestMine",
}

--========================================
-- 기타 애니메이션
--========================================
AnimationIds.MISC = {
	HIT = "InteractHit",
	DEATH = "InteractDeath",
	JUMP = "MovementJump",
	REST = "InteractRest",
}

--========================================
-- 소모/섭취 애니메이션
--========================================
AnimationIds.CONSUME = {
	EAT = "ConsumeEat",
}

--========================================
-- 연속 콤보 배열
--========================================

--========================================
-- 액티브 스킬 애니메이션 (플레이스홀더 — 추후 실제 애니메이션 연결)
--========================================
AnimationIds.SKILL_SWORD = {
	STRIKE = "SkillSword_Strike",       -- 강타
	CHARGE = "SkillSword_Charge",       -- 돌진
	FLURRY = "SkillSword_Flurry",       -- 난무
}

AnimationIds.SKILL_BOW = {
	POWER = "SkillBow_Power",           -- 강사
	RAPID = "SkillBow_Rapid",           -- 속사
	EXPLOSIVE = "SkillBow_Explosive",   -- 폭렬 사격
}

AnimationIds.SKILL_AXE = {
	SLAM = "SkillAxe_Slam",             -- 내려찍기
	SPIN = "SkillAxe_Spin",             -- 회전 베기
	STORM = "SkillAxe_Storm",           -- 도끼 폭풍
}

-- 스킬ID → 애니메이션 논리이름 매핑
AnimationIds.SKILL_ANIM_MAP = {
	SWORD_A1 = "SkillSword_Strike",
	SWORD_A2 = "SkillSword_Charge",
	SWORD_A3 = "SkillSword_Flurry",
	BOW_A1   = "AttackBow_Draw",
	BOW_A2   = "AttackBow_Draw",
	BOW_A3   = "AttackBow_Draw",
	AXE_A1   = "SkillAxe_Slam",
	AXE_A2   = "SkillAxe_Spin",
	AXE_A3   = "SkillAxe_Spin",   -- Storm: Spin→Slam 순차 (전용 애니 없음)
}

-- 스킬ID → VFX/사운드 에셋 이름 매핑 (애니메이션과 다른 경우)
AnimationIds.SKILL_ASSET_MAP = {
	BOW_A1 = "SkillBow_Power",
	BOW_A2 = "SkillBow_Rapid",
	BOW_A3 = "SkillBow_Explosive",
	AXE_A3 = "SkillAxe_Storm",    -- VFX/사운드는 Storm 에셋 사용
}

AnimationIds.COMBO_UNARMED = {
	"AttackUnarmed_1",
	"AttackUnarmed_2",
	"AttackUnarmed_3",
}

AnimationIds.COMBO_TOOL = {
	"AttackTool_Swing",
	"AttackTool_Overhead",
}

return AnimationIds
