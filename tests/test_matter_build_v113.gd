extends SceneTree
## Matter choices remain plain data until a validated private kit is built.
const Build = preload("res://scripts/commander_build.gd")
const Matter = preload("res://scripts/matter_rules.gd")
const MALE = preload("res://data/demo_male_lv25.tres")
const FEMALE = preload("res://data/demo_female_lv25.tres")
const FALCON = preload("res://data/monsters/falcon_unit_v14.tres")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    test_defaults_and_catalogs()
    test_sources_and_resolution()
    test_books_and_private_kits()
    test_strict_descriptors()
    test_legacy_upgrade()
    test_purity()
    if failures == 0:
        print("SULEYN matter build v1.13: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN matter build v1.13: %d / %d checks FAILED." % [failures, checks])
        quit(1)


func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED matter build v1.13: " + label)


func choices(class_matter: int = Matter.NEUTRAL, equipment: Array = [], book: String = "fire") -> Dictionary:
    var result: Dictionary = Build.defaults(MALE)
    result.class_matter = class_matter
    result.equipment = equipment.duplicate(true)
    result.book = book
    return result


func legacy(base_stats = MALE) -> Dictionary:
    var result: Dictionary = {}
    var options: Dictionary = Build.defaults(base_stats)
    for key in Build.LEGACY_KEYS:
        result[key] = options[key]
    return result


func numeric_preview(preview: Dictionary) -> Dictionary:
    var result: Dictionary = preview.duplicate(true)
    for key in ["body_matter", "spell_matter", "source_counts", "source_text", "book_name", "spell_name"]:
        result.erase(key)
    return result


func snapshot(stats) -> Dictionary:
    return {"options": Build.defaults(stats), "sources": stats.commander.matter_sources(),
        "attributes": stats.commander.primary_stats(), "hp": stats.commander.max_hp(),
        "mp": stats.commander.max_mp(), "move": stats.movement,
        "spell": stats.magic_spell, "spell_name": stats.magic_spell.display_name,
        "book": stats.magic_spell.magic_book, "power": stats.magic_spell.spell_power,
        "cost": stats.magic_spell.mana_cost, "melee": stats.melee_skill,
        "special": stats.special_skill, "critical": stats.commander.critical_multiplier()}


func test_defaults_and_catalogs() -> void:
    check(Build.KEYS.size() == 9 and Build.LEGACY_KEYS.size() == 6, "descriptor has exactly six numeric build fields and three matter choices")
    check(Build.ITEM_KEYS.size() == 4 and Build.BOOK_KEYS.size() == 7, "only the existing four test items and seven books are offered")
    for key in Build.ITEM_KEYS:
        check(Build.ITEMS[key] is SuleynMatterItem and Build.item_label(key) == Build.ITEMS[key].display_name, "item ID maps to the existing named resource: " + key)
    for key in Build.BOOK_KEYS:
        check(Build.BOOKS[key] is SuleynMagicBook and Build.book_label(key) == Build.BOOKS[key].display_name, "book ID maps to the existing named resource: " + key)
    check(Build.item_label("res:" + "//outside.tres").is_empty() and Build.book_label("unknown").is_empty(), "unknown labels do not load arbitrary resources")
    check(Build.BOOKS.novice.matter == Matter.NEUTRAL and Build.BOOKS.forest_talmud.matter == Matter.NEUTRAL, "both existing neutral books remain neutral")
    for original in [MALE, FEMALE]:
        var defaults: Dictionary = Build.defaults(original)
        check(defaults.class_matter == Matter.NEUTRAL and defaults.equipment.is_empty(), "current warrior starts with original neutral class and no items")
        check(defaults.book == ("fire" if original == MALE else "dark"), "default book is derived from each original spell")
        check(Build.validate(original, defaults).ok and Build.materialize(original, defaults).magic_spell == original.magic_spell, "unchanged spell keeps catalog identity")
    var custom: SuleynUnitStats = MALE.duplicate(false) as SuleynUnitStats
    custom.commander = MALE.commander.duplicate(false) as SuleynCommanderProfile
    custom.commander.class_matter = Matter.LIGHT
    var items: Array[Resource] = [Build.ITEMS.water_shield, Build.ITEMS.plain_sword]
    custom.commander.matter_equipment = items
    custom.magic_spell = MALE.magic_spell.duplicate(false) as SuleynMagicSpell
    custom.magic_spell.magic_book = Build.BOOKS.wind
    var derived: Dictionary = Build.defaults(custom)
    check(derived.class_matter == Matter.LIGHT and derived.equipment == ["plain_sword", "water_shield"] and derived.book == "wind", "defaults read original class, canonical equipment IDs and book ID")
    derived.equipment.clear()
    check(custom.commander.matter_equipment.size() == 2, "default descriptor owns its item array")


func test_sources_and_resolution() -> void:
    for class_matter in range(6):
        var options: Dictionary = choices(class_matter)
        var preview: Dictionary = Build.preview(MALE, options)
        var stats = Build.materialize(MALE, options)
        check(Build.validate(MALE, options).ok and preview.body_matter == class_matter, "each allowed class matter resolves without equipment")
        check(stats.commander.resolved_matter() == class_matter and preview.spell_matter == Matter.FIRE, "body source does not replace original book matter")
        check(preview.source_counts == ({} if class_matter == 0 else {class_matter: 1}), "source counts include one non-neutral class vote")
    var neutral: Dictionary = Build.preview(MALE, choices(0, ["plain_sword"]))
    check(neutral.body_matter == 0 and neutral.source_counts.is_empty() and neutral.source_text.contains("Нет активных"), "plain sword contributes no active matter source")
    var lone: Dictionary = Build.preview(MALE, choices(Matter.WATER, ["plain_sword"]))
    check(lone.body_matter == Matter.WATER and lone.source_counts == {Matter.WATER: 1}, "neutral item does not compete with class vote")
    var tie: Dictionary = Build.preview(MALE, choices(Matter.FIRE, ["water_sword", "plain_sword"]))
    check(tie.body_matter == Matter.NEUTRAL and tie.source_counts == {Matter.FIRE: 1, Matter.WATER: 1}, "equal fire and water votes resolve neutral")
    check(tie.source_text.contains("Ничья") and tie.source_text.contains("Огонь ×1") and tie.source_text.contains("Вода ×1"), "tie explanation includes counts and neutral result")
    var two_water: Dictionary = Build.preview(MALE, choices(Matter.FIRE, ["water_sword", "water_shield"]))
    check(two_water.body_matter == Matter.WATER and two_water.source_counts == {Matter.FIRE: 1, Matter.WATER: 2}, "two separate water items outweigh one class fire source")
    var all_items: Array = ["water_shield", "fire_sword", "plain_sword", "water_sword"]
    var all: Dictionary = Build.preview(MALE, choices(Matter.NEUTRAL, all_items))
    check(all.body_matter == Matter.WATER and all.source_counts == {Matter.FIRE: 1, Matter.WATER: 2}, "all four allowed items are usable together and neutral is ignored")
    var even: Dictionary = Build.preview(MALE, choices(Matter.FIRE, all_items))
    check(even.body_matter == Matter.NEUTRAL and even.source_counts == {Matter.FIRE: 2, Matter.WATER: 2}, "class vote plus four items can create a two-to-two tie")
    var three_types: Dictionary = Build.preview(MALE, choices(Matter.WIND, all_items))
    check(three_types.body_matter == Matter.WATER and three_types.source_counts == {Matter.FIRE: 1, Matter.WIND: 1, Matter.WATER: 2}, "lower-count ties do not defeat a unique leading matter")
    var reversed: Array = all_items.duplicate()
    reversed.reverse()
    check(Build.preview(MALE, choices(Matter.WIND, reversed)) == three_types, "resolution and explanation are independent of incoming equipment order")
    var floats: Dictionary = choices()
    floats.class_matter = 3.0
    check(Build.validate(MALE, floats).ok and typeof(Build.canonical(floats).class_matter) == TYPE_INT, "integral JSON matter value is accepted and canonicalized")


func test_books_and_private_kits() -> void:
    for original in [MALE, FEMALE]:
        var original_preview: Dictionary = Build.preview(original, Build.defaults(original))
        for book in Build.BOOK_KEYS:
            var options: Dictionary = Build.defaults(original)
            options.class_matter = Matter.WATER
            options.equipment = ["plain_sword", "fire_sword", "water_shield"]
            options.book = book
            var stats = Build.materialize(original, options)
            var preview: Dictionary = Build.preview(original, options)
            check(stats.commander.resolved_matter() == Matter.WATER and preview.spell_matter == Build.BOOKS[book].matter, "book changes only spell matter while class and equipment determine body")
            check(stats.magic_spell.magic_book == Build.BOOKS[book] and preview.book_name == Build.book_label(book), "selected book is the allowlisted read-only resource")
            check(stats.magic_spell.spell_power == original.magic_spell.spell_power and stats.magic_spell.mana_cost == original.magic_spell.mana_cost, "book keeps existing spell power and MP cost")
            check(stats.melee_skill == original.melee_skill and stats.special_skill == original.special_skill and stats.movement == original.movement, "matter sources do not replace physical attacks or movement")
            check(numeric_preview(preview) == numeric_preview(original_preview), "matter sources and books add no numeric stats, armor or damage bonuses")
            check(stats.commander.critical_multiplier() == (2.0 if original == FEMALE else 1.5), "existing physical critical passive remains unchanged")
            if stats.magic_spell.magic_book != original.magic_spell.magic_book:
                check(stats.magic_spell != original.magic_spell and stats.magic_spell.display_name == "Удар · " + Build.book_label(book), "changed book gets a private spell with a matching display name")
            else:
                check(stats.magic_spell == original.magic_spell and preview.spell_name == original.magic_spell.display_name, "default book keeps original spell resource and display name")
    var incoming: Dictionary = choices(Matter.FIRE, ["water_shield", "plain_sword"], "water")
    var first = Build.materialize(MALE, incoming)
    var second = Build.materialize(MALE, incoming)
    check(first != second and first.commander != second.commander and first.magic_spell != second.magic_spell, "repeated changed builds own independent unit, commander and spell resources")
    first.commander.matter_equipment.clear()
    first.magic_spell.spell_power = 777
    first.magic_spell.mana_cost = 888
    first.magic_spell.display_name = "private"
    check(second.commander.matter_equipment.size() == 2 and second.magic_spell.spell_power == 20 and second.magic_spell.mana_cost == 10 and second.magic_spell.display_name == "Удар · Книга Воды", "editing one private array and spell does not alter another build")
    check(incoming.equipment == ["water_shield", "plain_sword"] and MALE.commander.matter_equipment.is_empty() and MALE.magic_spell.spell_power == 20, "materialization and private edits do not mutate input or catalog")
    var ordered: Dictionary = Build.canonical(incoming)
    check(ordered.equipment == ["plain_sword", "water_shield"] and incoming.equipment == ["water_shield", "plain_sword"], "canonical item order is deterministic and leaves input unchanged")
    ordered.equipment.append("fire_sword")
    check(incoming.equipment.size() == 2, "canonical array is not aliased to input")
    var resized: Dictionary = Build.resize(MALE, incoming, 1)
    check(resized.class_matter == Matter.FIRE and resized.book == "water" and resized.equipment == ["plain_sword", "water_shield"], "level reduction preserves all three matter choices")
    resized.equipment.clear()
    check(incoming.equipment.size() == 2, "resizing owns its equipment array")


func test_strict_descriptors() -> void:
    for key in ["class_matter", "equipment", "book"]:
        var missing: Dictionary = choices()
        missing.erase(key)
        check(not Build.validate(MALE, missing).ok, "missing new field is rejected: " + key)
    for invalid in [false, "1", -1, 6, 0.5, NAN, INF, null, [], {}]:
        var options: Dictionary = choices()
        options.class_matter = invalid
        check(not Build.validate(MALE, options).ok and Build.materialize(MALE, options) == null, "invalid class matter is rejected before setters")
    for invalid in [null, false, "fire_sword", {}, PackedStringArray(["fire_sword"]), [StringName("fire_sword")], ["unknown"], ["res://data/equipment/fire_sword.tres"], ["../fire_sword"], [Build.ITEMS.fire_sword], [1], [null], [["fire_sword"]], ["fire_sword", "fire_sword"], ["plain_sword", "fire_sword", "water_sword", "water_shield", "plain_sword"]]:
        var options: Dictionary = choices()
        options.equipment = invalid
        var validation: Dictionary = Build.validate(MALE, options)
        check(not validation.ok and not validation.reason.is_empty() and Build.materialize(MALE, options) == null, "malformed, duplicate or external equipment is rejected")
    for invalid in [null, false, 1, [], {}, StringName("water"), "unknown", "res://data/magic_books/water.tres", "../water", Build.BOOKS.water]:
        var options: Dictionary = choices()
        options.book = invalid
        check(not Build.validate(MALE, options).ok and Build.preview(MALE, options).is_empty(), "only a known plain book ID is accepted")
    var extra: Dictionary = choices()
    extra.spell_power = 999
    check(not Build.validate(MALE, extra).ok, "unrecognized ninth-plus field cannot override attack values")
    check(not Build.validate(FALCON, choices()).ok and not Build.validate(MALE, legacy()).ok, "monsters and unupgraded six-field descriptors cannot use current build API")


func test_legacy_upgrade() -> void:
    for original in [MALE, FEMALE]:
        var old: Dictionary = legacy(original)
        var before: Dictionary = old.duplicate(true)
        var migrated: Dictionary = Build.migrate_v3(original, old)
        check(migrated.ok and migrated.options == Build.defaults(original), "v3 upgrade fills original matter and book defaults for each commander")
        check(old == before and Build.validate(original, migrated.options).ok, "legacy upgrade validates without mutating original six fields")
        var floats: Dictionary = old.duplicate(true)
        for key in floats:
            floats[key] = float(floats[key])
        var integral: Dictionary = Build.migrate_v3(original, floats)
        check(integral.ok and typeof(integral.options.level) == TYPE_INT and typeof(integral.options.STR) == TYPE_INT, "legacy JSON integral floats are canonicalized")
    for invalid in [null, false, [], choices(), {}, {"level": 25}, {"level": 25, "armor": 0, "STR": 0, "AGI": 0, "WIS": 0, "resource": "fire"}]:
        var result: Dictionary = Build.migrate_v3(MALE, invalid)
        check(not result.ok and result.options.is_empty() and not result.reason.is_empty(), "legacy upgrade requires exactly the former six known fields")
    for change in [{"level": 0}, {"level": 1000}, {"armor": 4}, {"STR": 36}, {"INT": 40}, {"AGI": 2995}, {"AGI": 0.5}, {"WIS": false}, {"level": 2, "STR": 0, "AGI": 4, "WIS": 0, "INT": 0}]:
        var old: Dictionary = legacy()
        old.merge(change, true)
        check(not Build.migrate_v3(MALE, old).ok, "legacy migration keeps existing numeric bounds, caps and budget")
    check(not Build.migrate_v3(FALCON, legacy()).ok, "legacy migration never turns a monster into a commander")


func test_purity() -> void:
    var before_male: Dictionary = snapshot(MALE)
    var before_female: Dictionary = snapshot(FEMALE)
    var item_state: Dictionary = {}
    var book_state: Dictionary = {}
    for key in Build.ITEM_KEYS:
        item_state[key] = [Build.ITEMS[key].display_name, Build.ITEMS[key].matter]
    for key in Build.BOOK_KEYS:
        book_state[key] = [Build.BOOKS[key].display_name, Build.BOOKS[key].matter]
    seed(113741)
    var expected: float = randf()
    seed(113741)
    for class_matter in range(6):
        for book in Build.BOOK_KEYS:
            var options: Dictionary = choices(class_matter, ["water_shield", "fire_sword"], book)
            Build.validate(MALE, options)
            Build.canonical(options)
            Build.preview(MALE, options)
            Build.materialize(MALE, options)
            Build.resize(MALE, options, 12)
            Build.migrate_v3(FEMALE, legacy(FEMALE))
    check(randf() == expected, "validation, migration, preview and private building do not consume battle RNG")
    check(snapshot(MALE) == before_male and snapshot(FEMALE) == before_female, "catalog commanders, spells and numeric data stay unchanged after all selections")
    for key in Build.ITEM_KEYS:
        check(item_state[key] == [Build.ITEMS[key].display_name, Build.ITEMS[key].matter], "selected shared equipment remains read-only: " + key)
    for key in Build.BOOK_KEYS:
        check(book_state[key] == [Build.BOOKS[key].display_name, Build.BOOKS[key].matter], "selected shared books remain read-only: " + key)
