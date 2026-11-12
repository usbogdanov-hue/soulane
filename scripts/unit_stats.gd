class_name SuleynUnitStats
extends Resource
## Battle settings. Actual commander HP is taken from commander when assigned.
## ATK, DEF and MOVE are separate TEMPORARY demo knobs, NOT functions of STR/AGI.

@export var display_name: String = "Тестовый отряд"
@export var commander: SuleynCommanderProfile
@export var monster: SuleynMonsterProfile
@export var melee_skill: SuleynAttackSkill
@export var special_skill: SuleynAttackSkill  # Optional additional physical skill
@export var magic_spell: SuleynMagicSpell
@export_range(1, 99999, 1) var max_hp: int = 20  # fallback for non-commander units
@export_range(0, 9999, 1) var attack: int = 5    # legacy fallback skill power
@export_range(0, 9999, 1) var defense: int = 0   # legacy field; NOT a defense percentage
@export_range(0, 99, 1) var movement: int = 3   # demo only
