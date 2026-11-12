@tool
class_name SuleynCommanderBaseStats
extends Resource
## Базовые характеристики архетипа на 1 уровне, редактируются в Inspector.
## За уровни отвечает commander_profile.gd, броня и боевые формулы здесь не участвуют.

@export var display_name: String = "Новый командир":
    set(value):
        display_name = value
        emit_changed()
@export_range(0, 45, 1) var base_str: int = 0:
    set(value):
        base_str = clampi(value, 0, 45)
        emit_changed()
@export_range(0, 9999, 1) var base_agi: int = 0:
    set(value):
        base_agi = value
        emit_changed()
@export_range(0, 9999, 1) var base_wis: int = 0:
    set(value):
        base_wis = value
        emit_changed()
@export_range(0, 45, 1) var base_int: int = 0:
    set(value):
        base_int = clampi(value, 0, 45)
        emit_changed()
@export_range(1, 999999, 1) var base_hp: int = 1:
    set(value):
        base_hp = value
        emit_changed()
@export_range(0, 999999, 1) var base_mp: int = 0:
    set(value):
        base_mp = value
        emit_changed()


func to_record() -> Dictionary:
    return {
        "name": display_name,
        "str": base_str,
        "agi": base_agi,
        "wis": base_wis,
        "int": base_int,
        "hp": base_hp,
        "mp": base_mp,
    }
