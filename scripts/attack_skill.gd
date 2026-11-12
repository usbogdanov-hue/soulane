class_name SuleynAttackSkill
extends Resource
## Physical skill: distance is measured in HEXES, and MP is paid when attack is attempted.
## Regular v1.1 attacks use the defaults: adjacent, zero MP, no status.
@export var display_name: String = "Атака"
@export_range(0, 999999, 1) var skill_power: int = 5
@export_enum("Колющее", "Рубящее", "Дробящее") var damage_type: int = 1
@export_range(0, 9999, 1) var mana_cost: int = 0
@export_range(1, 20, 1) var min_range: int = 1
@export_range(1, 20, 1) var max_range: int = 1
@export_range(0.0, 90.0, 0.1) var concussion_chance_pct: float = 0.0
@export_range(0, 20, 1) var concussion_skipped_turns: int = 0
