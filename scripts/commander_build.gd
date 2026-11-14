extends RefCounted
## Plain-data overrides for the existing warrior commander kits. Validation
## precedes all Resource setters, which otherwise clamp invalid imported input.

const Rules = preload("res://scripts/combat_rules.gd")
const KEYS: Array[String] = ["level", "armor", "STR", "AGI", "WIS", "INT"]
const ATTRIBUTES: Array[String] = ["STR", "AGI", "WIS", "INT"]
const MAX_POINTS: int = 2994


static func defaults(base_stats) -> Dictionary:
    if not _supports(base_stats):
        return {}
    var profile: SuleynCommanderProfile = base_stats.commander
    return {"level": profile.level, "armor": profile.armor_type,
        "STR": profile.points_str, "AGI": profile.points_agi,
        "WIS": profile.points_wis, "INT": profile.points_int}


static func validate(base_stats, options: Variant) -> Dictionary:
    if not _supports(base_stats):
        return _failure("Настройка доступна только выбранному командиру.")
    if not options is Dictionary or options.size() != KEYS.size():
        return _failure("Неверные параметры командира.")
    for key in KEYS:
        if not options.has(key):
            return _failure("Неверные параметры командира.")
    if not _integer(options.level, 1, 999) or not _integer(options.armor, 0, 3):
        return _failure("Уровень должен быть от 1 до 999, броня — из списка.")
    var spent: int = 0
    for key in ATTRIBUTES:
        if not _integer(options[key], 0, MAX_POINTS):
            return _failure("Очки характеристик должны быть целыми и неотрицательными.")
        spent += int(options[key])
    if spent > (int(options.level) - 1) * 3:
        return _failure("Распределено больше очков, чем доступно на этом уровне.")
    var base: Dictionary = base_stats.commander.base_record()
    if int(base["str"]) + int(options.STR) > 45 or int(base["int"]) + int(options.INT) > 45:
        return _failure("Итоговые STR и INT не могут превышать 45.")
    return {"ok": true, "reason": ""}


static func resize(base_stats, options: Variant, new_level: Variant) -> Dictionary:
    if not validate(base_stats, options).ok or not _integer(new_level, 1, 999):
        return {}
    var result: Dictionary = _canonical(options)
    result.level = int(new_level)
    var remaining: int = (result.level - 1) * 3
    var base: Dictionary = base_stats.commander.base_record()
    for key in ATTRIBUTES:
        var cap: int = MAX_POINTS
        if key == "STR" or key == "INT":
            cap = maxi(0, 45 - int(base[key.to_lower()]))
        result[key] = mini(int(result[key]), mini(cap, remaining))
        remaining -= int(result[key])
    return result


static func materialize(base_stats, options: Variant) -> SuleynUnitStats:
    if not validate(base_stats, options).ok:
        return null
    var result: SuleynUnitStats = base_stats.duplicate(false) as SuleynUnitStats
    var profile: SuleynCommanderProfile = base_stats.commander.duplicate(false) as SuleynCommanderProfile
    # Arrays are private; the referenced matter items, base, passive and attack
    # resources remain shared read-only, exactly as in the original catalog.
    profile.matter_equipment = base_stats.commander.matter_equipment.duplicate()
    profile.points_str = 0
    profile.points_agi = 0
    profile.points_wis = 0
    profile.points_int = 0
    profile.level = int(options.level)
    profile.armor_type = int(options.armor)
    profile.points_str = int(options.STR)
    profile.points_agi = int(options.AGI)
    profile.points_wis = int(options.WIS)
    profile.points_int = int(options.INT)
    result.commander = profile
    return result


static func preview(base_stats, options: Variant) -> Dictionary:
    var stats: SuleynUnitStats = materialize(base_stats, options)
    if stats == null:
        return {}
    var profile: SuleynCommanderProfile = stats.commander
    var attributes: Dictionary = profile.primary_stats()
    var damage_type: int = stats.melee_skill.damage_type if stats.melee_skill != null else Rules.BLUNT
    return {"hp": profile.max_hp(), "mp": profile.max_mp(),
        "stats": attributes, "unspent": profile.points_unspent(),
        "level": profile.level, "armor": profile.armor_name(),
        "pdef": profile.physical_defense_pct(damage_type),
        "damage_type": damage_type,
        "pdef_by_type": {Rules.PIERCING: profile.physical_defense_pct(Rules.PIERCING),
            Rules.SLASHING: profile.physical_defense_pct(Rules.SLASHING),
            Rules.BLUNT: profile.physical_defense_pct(Rules.BLUNT)},
        "mdef": profile.magic_defense_pct(),
        "evasion": Rules.final_evasion(float(attributes.AGI) * 0.5 + profile.armor_evasion_bonus()),
        "crit": clampf(float(attributes.AGI) * 0.5, 0.0, 90.0),
        "physical_bonus": minf(90.0, float(attributes.STR) * 2.0),
        "magic_bonus": minf(90.0, float(attributes.INT) * 2.0)}


static func _supports(base_stats) -> bool:
    return (typeof(base_stats) == TYPE_OBJECT and is_instance_valid(base_stats)
        and base_stats is SuleynUnitStats and base_stats.commander != null
        and base_stats.commander.archetype in [0, 1])


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
    return ((typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
        and is_finite(float(value)) and float(value) == floor(float(value))
        and float(value) >= minimum and float(value) <= maximum)


static func _canonical(options: Dictionary) -> Dictionary:
    var result: Dictionary = {}
    for key in KEYS:
        result[key] = int(options[key])
    return result


static func _failure(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
