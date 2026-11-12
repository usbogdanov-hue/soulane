@tool
class_name SuleynCommanderProfile
extends Resource
## SULEYN v1.0 — профиль, редактируемый в одном Inspector.
## Базовые данные остаются общими ресурсами archetype (как в v0.6),
## а вложенный Base Stats можно развернуть и изменить прямо здесь.
## Итоги в Inspector рассчитываются, НЕ сохраняются и не редактируются.

const Rules = preload("res://scripts/combat_rules.gd")
const Matter = preload("res://scripts/matter_rules.gd")

const BASES = [
    preload("res://data/commander_bases/male_warrior.tres"),
    preload("res://data/commander_bases/female_warrior.tres"),
    preload("res://data/commander_bases/male_hybrid.tres"),
    preload("res://data/commander_bases/female_hybrid.tres"),
    preload("res://data/commander_bases/male_mage.tres"),
    preload("res://data/commander_bases/female_mage.tres"),
]

@export_category("Командир")
@export_enum("Воин-мужчина", "Воин-женщина", "Гибрид-мужчина", "Гибрид-женщина", "Маг-мужчина", "Маг-женщина") var archetype: int = 0:
    set(value):
        archetype = clampi(value, 0, BASES.size() - 1)
        # Для штатных архетипов ссылка следует за сменой типа командира.
        # Пользовательский (неизвестный BASES) ресурс не перезаписываем.
        if base_stats == null or BASES.has(base_stats):
            base_stats = BASES[archetype]
        _refresh_preview()

@export_range(1, 999, 1) var level: int = 1:
    set(value):
        level = clampi(value, 1, 999)
        _trim_points_to_budget()
        _refresh_preview()

@export_enum("Без брони", "Лёгкая броня", "Средняя броня", "Тяжёлая броня") var armor_type: int = 0:
    set(value):
        armor_type = clampi(value, 0, 3)
        _refresh_preview()

@export_group("Материя и пассивные способности")
@export_enum("Нейтральная", "Огонь", "Воздух", "Вода", "Свет", "Тьма") var class_matter: int = 0:
    set(value):
        class_matter = clampi(value, 0, 5)
        _refresh_preview()
@export var matter_equipment: Array[Resource] = []:
    set(value):
        matter_equipment = value
        _refresh_preview()
@export var critical_passive: SuleynCriticalPassive

@export_group("База 1-го уровня (развернуть)")
@export var base_stats: SuleynCommanderBaseStats:
    set(value):
        if base_stats != null and base_stats.changed.is_connected(_on_base_stats_changed):
            base_stats.changed.disconnect(_on_base_stats_changed)
        base_stats = value
        if base_stats != null and not base_stats.changed.is_connected(_on_base_stats_changed):
            base_stats.changed.connect(_on_base_stats_changed)
        _refresh_preview()

@export_group("Очки, полученные за уровни")
@export_range(0, 2994, 1) var points_str: int = 0:
    set(value):
        points_str = clampi(value, 0, maxi(0, mini(45 - int(base_record()["str"]), points_earned() - points_agi - points_wis - points_int)))
        _refresh_preview()

@export_range(0, 2994, 1) var points_agi: int = 0:
    set(value):
        points_agi = clampi(value, 0, maxi(0, points_earned() - points_str - points_wis - points_int))
        _refresh_preview()

@export_range(0, 2994, 1) var points_wis: int = 0:
    set(value):
        points_wis = clampi(value, 0, maxi(0, points_earned() - points_str - points_agi - points_int))
        _refresh_preview()

@export_range(0, 2994, 1) var points_int: int = 0:
    set(value):
        points_int = clampi(value, 0, maxi(0, mini(45 - int(base_record()["int"]), points_earned() - points_str - points_agi - points_wis)))
        _refresh_preview()


func _on_base_stats_changed() -> void:
    _trim_points_to_budget()
    _refresh_preview()


func _refresh_preview() -> void:
    # Editor-only обновление вычисляемых полей, без записи этих полей в .tres.
    if Engine.is_editor_hint():
        notify_property_list_changed()


func _trim_points_to_budget() -> void:
    var old_str: int = points_str
    var old_agi: int = points_agi
    var old_wis: int = points_wis
    var old_int: int = points_int
    # Setters учитывают остальные очки: сначала освобождаем весь бюджет,
    # затем возвращаем распределение с приоритетом STR > AGI > WIS > INT.
    # Те же setters сохраняют ограничения STR/INT при изменении базы.
    points_str = 0
    points_agi = 0
    points_wis = 0
    points_int = 0
    points_str = old_str
    points_agi = old_agi
    points_wis = old_wis
    points_int = old_int


func _get_property_list() -> Array[Dictionary]:
    var p: Array[Dictionary] = []
    p.append({"name": "Расчёт по GDD (только чтение)", "type": TYPE_NIL, "usage": PROPERTY_USAGE_GROUP})
    var names: Array[String] = [
        "final_str", "final_agi", "final_wis", "final_int",
        "final_max_hp", "final_max_mp", "earned_points", "spent_points", "remaining_points", "allocation_state",
        "physical_damage_bonus_percent", "evasion_percent", "crit_chance_percent",
        "armor_pdef_percent", "armor_mdef_percent", "magic_power_percent",
        "mana_regen_percent", "magic_resistance_percent", "final_mdef_percent",
        "pdef_piercing_percent", "pdef_slashing_percent", "pdef_blunt_percent",
        "resolved_matter", "resolved_matter_name", "physical_critical_multiplier"
    ]
    for name in names:
        p.append({
            "name": name,
            "type": TYPE_STRING if name in ["allocation_state", "resolved_matter_name"] else (TYPE_INT if name in ["final_str", "final_agi", "final_wis", "final_int", "final_max_hp", "final_max_mp", "earned_points", "spent_points", "remaining_points", "resolved_matter"] else TYPE_FLOAT),
            "usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
        })
    return p


func _get(property: StringName) -> Variant:
    match str(property):
        "resolved_matter":
            return resolved_matter()
        "resolved_matter_name":
            return Matter.matter_name(resolved_matter())
        "physical_critical_multiplier":
            return critical_multiplier()
        "final_str":
            return primary_stats()["STR"]
        "final_agi":
            return primary_stats()["AGI"]
        "final_wis":
            return primary_stats()["WIS"]
        "final_int":
            return primary_stats()["INT"]
        "final_max_hp":
            return max_hp()
        "final_max_mp":
            return max_mp()
        "earned_points":
            return points_earned()
        "spent_points":
            return points_spent()
        "remaining_points":
            return points_unspent()
        "allocation_state":
            return "OK (очки в пределах бюджета)" if valid_allocation() else "Ошибка распределения"
        "physical_damage_bonus_percent":
            return minf(90.0, float(primary_stats()["STR"]) * 2.0)
        "evasion_percent":
            return Rules.final_evasion(float(primary_stats()["AGI"]) * 0.5 + armor_evasion_bonus())
        "crit_chance_percent":
            return Rules.cap_chance(float(primary_stats()["AGI"]) * 0.5)
        "armor_pdef_percent":
            return float(armor_pdef_bonus())
        "armor_mdef_percent":
            return float(armor_mdef_bonus())
        "magic_power_percent":
            return minf(90.0, float(primary_stats()["INT"]) * 2.0)
        "mana_regen_percent":
            return Rules.cap_chance(float(primary_stats()["WIS"]) * 0.3)
        "magic_resistance_percent":
            return minf(90.0, float(primary_stats()["WIS"]) * 2.0)
        "final_mdef_percent":
            return magic_defense_pct()
        "pdef_piercing_percent":
            return physical_defense_pct(Rules.PIERCING)
        "pdef_slashing_percent":
            return physical_defense_pct(Rules.SLASHING)
        "pdef_blunt_percent":
            return physical_defense_pct(Rules.BLUNT)
    return null


func base_record() -> Dictionary:
    var source: SuleynCommanderBaseStats = base_stats
    if source == null:
        source = BASES[clampi(archetype, 0, BASES.size() - 1)]
    return source.to_record()


func archetype_name() -> String:
    return str(base_record()["name"])


func armor_name() -> String:
    match armor_type:
        1:
            return "Лёгкая"
        2:
            return "Средняя"
        3:
            return "Тяжёлая"
        _:
            return "Без брони"


func level_ups() -> int:
    return maxi(level - 1, 0)


func points_earned() -> int:
    return level_ups() * 3


func points_spent() -> int:
    return points_str + points_agi + points_wis + points_int


func points_unspent() -> int:
    return points_earned() - points_spent()


func valid_allocation() -> bool:
    return points_str >= 0 and points_agi >= 0 and points_wis >= 0 and points_int >= 0 and points_unspent() >= 0 and int(base_record()["str"]) + points_str <= 45 and int(base_record()["int"]) + points_int <= 45


func primary_stats() -> Dictionary:
    var base: Dictionary = base_record()
    return {
        "STR": mini(45, int(base["str"]) + points_str),
        "AGI": int(base["agi"]) + points_agi,
        "WIS": int(base["wis"]) + points_wis,
        "INT": mini(45, int(base["int"]) + points_int),
    }


func matter_sources() -> Array:
    var sources: Array = [class_matter]
    for item in matter_equipment:
        if item is SuleynMatterItem:
            sources.append(item.matter)
    return sources


func resolved_matter() -> int:
    return Matter.resolve(matter_sources())


func critical_multiplier() -> float:
    return maxf(1.5, critical_passive.crit_multiplier) if critical_passive != null else 1.5


func armor_pdef_bonus() -> int:
    return int(Rules.armor_pdef(armor_type))


func armor_mdef_bonus() -> int:
    return int(Rules.armor_mdef(armor_type))


func armor_weapon_bonus(damage_type: int) -> int:
    return int(Rules.armor_weapon_defense(armor_type, damage_type))


func armor_evasion_bonus() -> int:
    return int(Rules.armor_evasion(armor_type))


func physical_defense_pct(damage_type: int, effects_pct: float = 0.0) -> float:
    # Commander base PDEF = 0, NO vulnerability from monster matter categories.
    return Rules.cap_percent(float(armor_pdef_bonus() + armor_weapon_bonus(damage_type)) + effects_pct)


func magic_defense_pct(effects_pct: float = 0.0) -> float:
    # Commander base MDEF = 0; WIS protection stacks additively with armor.
    return Rules.cap_percent(float(armor_mdef_bonus()) + float(primary_stats()["WIS"]) * 2.0 + effects_pct)


func max_hp() -> int:
    # +5 HP per level-up and +10 HP per TOTAL STR point.
    return int(base_record()["hp"]) + level_ups() * 5 + int(primary_stats()["STR"]) * 10


func max_mp() -> int:
    # +2 MP per level-up and +5 MP per TOTAL INT point.
    return int(base_record()["mp"]) + level_ups() * 2 + int(primary_stats()["INT"]) * 5
