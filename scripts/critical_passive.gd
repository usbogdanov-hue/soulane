class_name SuleynCriticalPassive
extends Resource
## A class/monster passive overrides the standard x1.5 physical crit.
## Only one assigned passive is applied: no stackable crit-power bonuses.
@export var display_name: String = "Пассивный навык критического урона"
@export_range(1.5, 10.0, 0.05) var crit_multiplier: float = 1.5
