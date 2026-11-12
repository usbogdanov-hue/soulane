class_name SuleynMonsterProfile
extends Resource
## Monsters have NO commander armor. Percentages are editable by race/class.
@export var display_name: String = "Монстр"
@export var base_pdef_pct: float = 0.0
@export var base_mdef_pct: float = 0.0
## Test encounters can tune avoidance and damage independently of commander attributes.
@export var evasion_pct: float = 5.0
@export var physical_damage_bonus_pct: float = 0.0
@export var crit_chance_pct: float = 0.0
@export var max_mp: int = 0
@export_flags("Летающий", "Наземный", "Магический/неживой") var categories: int = 0
## Monster matter is part of its nature/race, NOT commander armor.
@export_enum("Нейтральная", "Огонь", "Воздух", "Вода", "Свет", "Тьма") var matter: int = 0
@export var critical_passive: SuleynCriticalPassive
