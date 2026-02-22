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

AnimationIds.ATTACK_SPEAR = {
	THRUST = "AttackSpear_Thrust",
	SWING = "AttackSpear_Swing",
}

AnimationIds.ATTACK_CLUB = {
	SMASH = "AttackClub_Smash",
	SWING = "AttackClub_Swing",
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
}

--========================================
-- 연속 콤보 배열
--========================================
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
