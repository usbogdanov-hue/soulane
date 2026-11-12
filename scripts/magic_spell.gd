class_name SuleynMagicSpell
extends Resource
## Attack matter is ALWAYS supplied by the magic book, never by caster.
@export var display_name: String = "Атакующее заклинание"
@export_range(0, 999999, 1) var spell_power: int = 20
@export_range(0, 999999, 1) var mana_cost: int = 10
@export var magic_book: SuleynMagicBook
