extends RefCounted
## Plain-data overrides for the existing warrior commander kits. Validation
## precedes all Resource setters, which otherwise clamp invalid imported input.

const Rules = preload("res://scripts/combat_rules.gd")
const Matter = preload("res://scripts/matter_rules.gd")
const LEGACY_KEYS: Array[String] = ["level", "armor", "STR", "AGI", "WIS", "INT"]
const KEYS: Array[String] = ["level", "armor", "STR", "AGI", "WIS", "INT", "class_matter", "equipment", "book"]
const ATTRIBUTES: Array[String] = ["STR", "AGI", "WIS", "INT"]
const MAX_POINTS: int = 2994
const ITEM_KEYS: Array[String] = ["plain_sword", "fire_sword", "water_sword", "water_shield"]
const ITEMS: Dictionary = {
    "plain_sword": preload("res://data/equipment/plain_sword.tres"),
    "fire_sword": preload("res://data/equipment/fire_sword.tres"),
    "water_sword": preload("res://data/equipment/water_sword.tres"),
    "water_shield": preload("res://data/equipment/water_shield.tres"),
}
const BOOK_KEYS: Array[String] = ["novice", "forest_talmud", "fire", "wind", "water", "light", "dark"]
const BOOKS: Dictionary = {
    "novice": preload("res://data/magic_books/novice.tres"),
    "forest_talmud": preload("res://data/magic_books/forest_talmud.tres"),
    "fire": preload("res://data/magic_books/fire.tres"),
    "wind": preload("res://data/magic_books/wind.tres"),
    "water": preload("res://data/magic_books/water.tres"),
    "light": preload("res://data/magic_books/light.tres"),
    "dark": preload("res://data/magic_books/dark.tres"),
}


static func defaults(base_stats) -> Dictionary:
    if not _supports(base_stats):
        return {}
    var profile: SuleynCommanderProfile = base_stats.commander
    var equipment: Array[String] = []
    for key in ITEM_KEYS:
        if profile.matter_equipment.has(ITEMS[key]):
            equipment.append(key)
    var book: String = "novice"
    if base_stats.magic_spell != null:
        for key in BOOK_KEYS:
            if base_stats.magic_spell.magic_book == BOOKS[key]:
                book = key
                break
    return {"level": profile.level, "armor": profile.armor_type,
        "STR": profile.points_str, "AGI": profile.points_agi,
        "WIS": profile.points_wis, "INT": profile.points_int,
        "class_matter": profile.class_matter, "equipment": equipment, "book": book}


static func item_label(key: String) -> String:
    return ITEMS[key].display_name if ITEMS.has(key) else ""


static func book_label(key: String) -> String:
    return BOOKS[key].display_name if BOOKS.has(key) else ""


static func validate(base_stats, options: Variant) -> Dictionary:
    if not _supports(base_stats):
        return _failure("Настройка доступна только выбранному командиру.")
    if not _has_keys(options, KEYS):
        return _failure("Неверные параметры командира.")
    var numeric_validation: Dictionary = _validate_numeric(base_stats, options)
    if not numeric_validation.ok:
        return numeric_validation
    if not _integer(options.class_matter, Matter.NEUTRAL, Matter.DARK):
        return _failure("Материя класса должна быть выбрана из списка.")
    if not options.equipment is Array or options.equipment.size() > ITEM_KEYS.size():
        return _failure("Тестовые источники материи должны быть списком известных предметов.")
    var seen: Dictionary = {}
    for item in options.equipment:
        if typeof(item) != TYPE_STRING or not ITEMS.has(item) or seen.has(item):
            return _failure("В источниках материи допустимы только разные предметы из списка.")
        seen[item] = true
    if typeof(options.book) != TYPE_STRING or not BOOKS.has(options.book):
        return _failure("Книга заклинаний должна быть выбрана из списка.")
    return {"ok": true, "reason": ""}


## The codec invokes this only for a v3 descriptor, before accepting new fields.
static func migrate_v3(base_stats, legacy_options: Variant) -> Dictionary:
    if not _supports(base_stats) or not _has_keys(legacy_options, LEGACY_KEYS):
        return {"ok": false, "reason": "Неверные прежние параметры командира.", "options": {}}
    var validation: Dictionary = _validate_numeric(base_stats, legacy_options)
    if not validation.ok:
        return {"ok": false, "reason": validation.reason, "options": {}}
    var result: Dictionary = defaults(base_stats)
    for key in LEGACY_KEYS:
        result[key] = int(legacy_options[key])
    return {"ok": true, "reason": "", "options": canonical(result)}


## Call after validation. Each result owns its plain equipment array, and item
## order follows the catalog so equivalent selections produce identical codes.
static func canonical(options: Dictionary) -> Dictionary:
    var result: Dictionary = {}
    for key in LEGACY_KEYS:
        result[key] = int(options[key])
    result.class_matter = int(options.class_matter)
    var equipment: Array[String] = []
    for key in ITEM_KEYS:
        if options.equipment.has(key):
            equipment.append(key)
    result.equipment = equipment
    result.book = options.book
    return result


static func _validate_numeric(base_stats, options: Dictionary) -> Dictionary:
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
    var result: Dictionary = canonical(options)
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
    # Each selected ID maps to a fixed read-only resource, never a loaded path.
    # Every slot owns its array and its mutable commander / spell resources.
    var equipment: Array[Resource] = []
    for key in ITEM_KEYS:
        if options.equipment.has(key):
            equipment.append(ITEMS[key])
    profile.matter_equipment = equipment
    profile.class_matter = int(options.class_matter)
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
    if result.magic_spell != null and result.magic_spell.magic_book != BOOKS[options.book]:
        result.magic_spell = result.magic_spell.duplicate(false) as SuleynMagicSpell
        result.magic_spell.magic_book = BOOKS[options.book]
        result.magic_spell.display_name = "Удар · " + book_label(options.book)
    return result


static func preview(base_stats, options: Variant) -> Dictionary:
    var stats: SuleynUnitStats = materialize(base_stats, options)
    if stats == null:
        return {}
    var profile: SuleynCommanderProfile = stats.commander
    var attributes: Dictionary = profile.primary_stats()
    var damage_type: int = stats.melee_skill.damage_type if stats.melee_skill != null else Rules.BLUNT
    var counts: Dictionary = _source_counts(profile.matter_sources())
    var body_matter: int = profile.resolved_matter()
    var spell_matter: int = Matter.NEUTRAL
    if stats.magic_spell != null and stats.magic_spell.magic_book != null:
        spell_matter = stats.magic_spell.magic_book.matter
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
        "magic_bonus": minf(90.0, float(attributes.INT) * 2.0),
        "body_matter": body_matter, "spell_matter": spell_matter,
        "source_counts": counts, "source_text": _source_text(counts, body_matter),
        "book_name": book_label(options.book),
        "spell_name": stats.magic_spell.display_name if stats.magic_spell != null else ""}


static func _supports(base_stats) -> bool:
    return (typeof(base_stats) == TYPE_OBJECT and is_instance_valid(base_stats)
        and base_stats is SuleynUnitStats and base_stats.commander != null
        and base_stats.commander.archetype in [0, 1])


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
    return ((typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
        and is_finite(float(value)) and float(value) == floor(float(value))
        and float(value) >= minimum and float(value) <= maximum)


static func _source_counts(sources: Array) -> Dictionary:
    var result: Dictionary = {}
    for matter in range(Matter.FIRE, Matter.DARK + 1):
        var count: int = sources.count(matter)
        if count > 0:
            result[matter] = count
    return result


static func _source_text(counts: Dictionary, body_matter: int) -> String:
    if counts.is_empty():
        return "Нет активных источников."
    var parts: PackedStringArray = []
    for matter in counts:
        parts.append("%s ×%d" % [Matter.matter_name(matter), counts[matter]])
    var explanation: String = "Больше: %s." % Matter.matter_name(body_matter)
    if body_matter == Matter.NEUTRAL:
        explanation = "Ничья → нейтральная."
    return "%s. %s" % [" · ".join(parts), explanation]


static func _has_keys(options: Variant, keys: Array[String]) -> bool:
    if not options is Dictionary or options.size() != keys.size():
        return false
    for key in keys:
        if not options.has(key):
            return false
    return true


static func _failure(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason}
