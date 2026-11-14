extends SceneTree
## Portable matter loadouts, strict v3 migration and nested-data isolation.
const Setup = preload("res://scripts/battle_setup.gd")
const Codec = preload("res://scripts/setup_codec.gd")
const Build = preload("res://scripts/commander_build.gd")
const Matter = preload("res://scripts/matter_rules.gd")
const Store = preload("res://scripts/setup_store.gd")
const LEGACY_KEYS: Array[String] = ["level", "armor", "STR", "AGI", "WIS", "INT"]
const NEW_KEYS: Array[String] = ["class_matter", "equipment", "book"]
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    test_v3_migration()
    test_v4_roundtrips()
    test_strict_versions_and_loadouts()
    test_purity_and_transaction()
    if failures == 0:
        print("SULEYN matter codec v1.13: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN matter codec v1.13: %d / %d checks FAILED." % [failures, checks])
        quit(1)


func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED matter codec v1.13: " + label)


func options_for(profile: String, changes: Dictionary) -> Dictionary:
    var result: Dictionary = Build.defaults(Setup.catalog_entry(profile))
    result.merge(changes, true)
    return result


func configured():
    var setup = Setup.new()
    setup.set_arena("pillars")
    setup.enemy_ai_enabled = false
    setup.set_commander_options("ally_1", options_for("male", {
        "level": 10, "armor": 1, "STR": 6, "AGI": 4, "WIS": 7, "INT": 3,
        "class_matter": Matter.FIRE, "equipment": ["water_shield", "plain_sword", "water_sword"], "book": "wind"}))
    setup.set_commander_options("ally_2", options_for("female", {
        "level": 20, "armor": 2, "STR": 10, "AGI": 20, "WIS": 12, "INT": 15,
        "class_matter": Matter.LIGHT, "equipment": ["fire_sword"], "book": "water"}))
    return setup


func wire() -> Dictionary:
    return Codec.encode(configured()).data


func v3_data(data: Dictionary) -> Dictionary:
    var result: Dictionary = data.duplicate(true)
    result.version = 3
    for row in result.units:
        if row.commander is Dictionary:
            for key in NEW_KEYS:
                row.commander.erase(key)
    return result


func reject(data: Variant, label: String) -> void:
    var result: Dictionary = Codec.from_data(data)
    check(not result.ok and result.setup == null and not result.reason.is_empty(), label)


func test_v3_migration() -> void:
    for partial in [false, true]:
        var setup = configured()
        if partial:
            for id in ["ally_3", "enemy_2", "enemy_3"]:
                setup.set_enabled(id, false)
        var data: Dictionary = v3_data(Codec.encode(setup).data)
        var before: Dictionary = data.duplicate(true)
        var decoded: Dictionary = Codec.from_data(data)
        check(decoded.ok, "genuine v3 custom stats import, partial=" + str(partial))
        check(data == before, "migration leaves legacy input unchanged")
        if not decoded.ok:
            continue
        var copy = decoded.setup
        check(copy.unit_ids() == setup.unit_ids() and copy.arena_key == "pillars" and not copy.enemy_ai_enabled,
            "migration preserves selection, arena and controller")
        for id in ["ally_1", "ally_2"]:
            var options: Dictionary = copy.commander_options[id]
            var old: Dictionary = setup.commander_options[id]
            check(options.size() == 9, "v3 commander gains exactly the new fields " + id)
            for key in LEGACY_KEYS:
                check(options[key] == old[key], "v3 scalar is preserved " + id + " " + key)
            check(options.class_matter == Matter.NEUTRAL and options.equipment.is_empty(),
                "v3 restores existing neutral class and empty equipment " + id)
            check(options.book == ("fire" if id == "ally_1" else "dark"), "v3 restores original profile book " + id)
            var base = Setup.catalog_entry(copy.profile_key(id))
            var stats = copy.profile_stats(id)
            check(stats.magic_spell == base.magic_spell and stats.special_skill == base.special_skill,
                "legacy spells and abilities retain resource identity " + id)
            var expected: Dictionary = {"STR": 16, "AGI": 12, "WIS": 11, "INT": 9} if id == "ally_1" else {"STR": 18, "AGI": 30, "WIS": 18, "INT": 19}
            check(stats.commander.primary_stats() == expected, "v3 final attributes do not lose allocations " + id)
            check(stats.commander.max_hp() == (505 if id == "ally_1" else 545)
                and stats.commander.max_mp() == (113 if id == "ally_1" else 188), "v3 health and mana are preserved " + id)
        var rewritten: Dictionary = Codec.encode(copy)
        check(rewritten.ok and rewritten.data.version == 4, "legacy record rewrites as v4")
        check(Codec.encode(Codec.decode(rewritten.code).setup).code == rewritten.code, "migration has a stable canonical v4 rewrite")
    var unchanged: Dictionary = Codec.encode(Setup.new()).data
    unchanged.version = 3
    var defaults: Dictionary = Codec.from_data(unchanged)
    check(defaults.ok and defaults.setup.commander_options.is_empty()
        and defaults.setup.profile_stats("ally_1") == Setup.CATALOG.male,
        "v3 null overrides preserve unchanged catalog resources")


func test_v4_roundtrips() -> void:
    check(Codec.VERSION == 4 and Store.VERSION == 1, "portable format advances while the outer library remains v1")
    for partial in [false, true]:
        var setup = configured()
        if partial:
            for id in ["ally_3", "enemy_2", "enemy_3"]:
                setup.set_enabled(id, false)
        var encoded: Dictionary = Codec.encode(setup)
        check(encoded.ok and encoded.data.version == 4 and encoded.data.units.size() == (3 if partial else 6), "v4 writes only active rows")
        var decoded: Dictionary = Codec.decode(encoded.code)
        check(decoded.ok, "v4 active matter loadouts import")
        if not decoded.ok:
            continue
        var copy = decoded.setup
        check(copy.commander_options == setup.commander_options and copy.enabled_slots == setup.enabled_slots,
            "all active configuration and selection choices survive")
        check(copy.positions == setup.positions and copy.arena_key == setup.arena_key
            and copy.enemy_ai_enabled == setup.enemy_ai_enabled, "loadouts preserve placement and battle settings")
        check(copy.commander_options.ally_1.equipment == ["plain_sword", "water_sword", "water_shield"], "equipment uses stable catalog order")
        var male = copy.profile_stats("ally_1")
        var female = copy.profile_stats("ally_2")
        check(male.commander.resolved_matter() == Matter.WATER and male.magic_spell.magic_book.matter == Matter.WIND,
            "water majority and wind book survive independently")
        check(female.commander.resolved_matter() == Matter.NEUTRAL and female.magic_spell.magic_book.matter == Matter.WATER,
            "tie remains neutral without cancelling selected spell matter")
        check(male.magic_spell.spell_power == 20 and male.magic_spell.mana_cost == 10
            and female.magic_spell.spell_power == 20 and female.magic_spell.mana_cost == 10,
            "book portability does not alter spell power or cost")
        check(Codec.encode(copy).code == encoded.code, "v4 JSON parse rewrites byte-for-byte canonically")
        copy.commander_options.ally_1.equipment.clear()
        check(setup.commander_options.ally_1.equipment.size() == 3, "decoded equipment does not alias the source draft")
    for book in ["novice", "forest_talmud", "fire", "wind", "water", "light", "dark"]:
        var setup = Setup.new()
        check(setup.set_commander_options("ally_1", options_for("male", {"book": book})), "known book accepted " + book)
        var decoded: Dictionary = Codec.decode(Codec.encode(setup).code)
        check(decoded.ok and decoded.setup.commander_options.ally_1.book == book, "book ID round-trips without collapsing equal matter " + book)
    var setup = configured()
    setup.set_enabled("ally_1", false)
    var decoded: Dictionary = Codec.decode(Codec.encode(setup).code)
    check(decoded.ok and not decoded.setup.commander_options.has("ally_1")
        and decoded.setup.commander_options.has("ally_2"), "disabled cached loadouts are omitted just like earlier commander overrides")
    var unordered: Dictionary = wire()
    unordered.units[0].commander.equipment.reverse()
    var floats: Dictionary = unordered.duplicate(true)
    for key in LEGACY_KEYS + ["class_matter"]:
        floats.units[0].commander[key] = float(floats.units[0].commander[key])
    check(Codec.encode(Codec.from_data(floats).setup).code == Codec.encode(configured()).code,
        "integral numbers and unordered unique IDs canonicalize without converting strings or arrays")


func test_strict_versions_and_loadouts() -> void:
    for version in [0, 5, 99, true, "4", 3.5]:
        var data: Dictionary = wire()
        data.version = version
        reject(data, "unsupported version is rejected " + str(version))
    for version in [1, 2]:
        var data: Dictionary = wire()
        data.version = version
        reject(data, "legacy row schema rejects commander member v" + str(version))
    var masquerade: Dictionary = wire()
    masquerade.version = 3
    reject(masquerade, "v4 descriptor cannot masquerade as a v3 record")
    var stripped: Dictionary = v3_data(wire())
    stripped.version = 4
    reject(stripped, "v4 requires explicit matter, equipment and book members")
    for key in NEW_KEYS:
        var data: Dictionary = wire()
        data.units[0].commander.erase(key)
        reject(data, "v4 requires new descriptor member " + key)
        data = v3_data(wire())
        data.units[0].commander[key] = wire().units[0].commander[key]
        reject(data, "v3 cannot hide any new descriptor member " + key)
    for value in [null, true, -1, 6, 1.5, NAN, INF, "1", [], {}]:
        var data: Dictionary = wire()
        data.units[0].commander.class_matter = value
        reject(data, "class matter needs a finite integer from its allowlist")
    for value in [null, true, 0, "water_sword", {}, ["unknown"], ["res:" + "//data/items/water_sword.tres"],
            ["water_sword", "water_sword"], [null], [1], [true], [["fire_sword"]],
            [Setup.CATALOG.male], ["plain_sword", "fire_sword", "water_sword", "water_shield", "fire_sword"]]:
        var data: Dictionary = wire()
        data.units[0].commander.equipment = value
        reject(data, "equipment must contain only unique known plain IDs, maximum four")
    for value in [null, true, 0, [], {}, "", "unknown", "res:" + "//data/books/fire_book.tres", Setup.CATALOG.male]:
        var data: Dictionary = wire()
        data.units[0].commander.book = value
        reject(data, "book allowlist refuses objects, paths and unknown IDs")
    var monster: Dictionary = wire()
    monster.units[1].commander = monster.units[0].commander.duplicate(true)
    reject(monster, "monster records cannot gain matter loadout descriptors")
    for key in LEGACY_KEYS:
        var data: Dictionary = v3_data(wire())
        data.units[0].commander[key] = true
        reject(data, "migration validates legacy numeric type before any conversion " + key)
    for value in [null, {}, true, "res://scripts/battle_demo.gd"]:
        var data: Dictionary = v3_data(wire())
        data.units[0].commander = value
        if value == null:
            check(Codec.from_data(data).ok, "v3 null override remains valid")
        else:
            reject(data, "legacy migration accepts only exact six-field dictionaries")


func test_purity_and_transaction() -> void:
    var setup = configured()
    var before: String = Codec.encode(setup).code
    var data: Dictionary = wire()
    var data_before: Dictionary = data.duplicate(true)
    var legacy: Dictionary = v3_data(data)
    var legacy_before: Dictionary = legacy.duplicate(true)
    var original_equipment: Array = Setup.CATALOG.male.commander.matter_equipment.duplicate()
    var original_spell = Setup.CATALOG.male.magic_spell
    seed(113733)
    var expected: int = randi()
    seed(113733)
    for index in range(5):
        Codec.encode(setup)
        Codec.decode(before)
        Codec.from_data(data)
        Codec.from_data(legacy)
    check(randi() == expected, "encoding, decoding and legacy migration never consume RNG")
    check(data == data_before and legacy == legacy_before and Codec.encode(setup).code == before,
        "successful reads leave nested source and draft dictionaries unchanged")
    var decoded: Dictionary = Codec.from_data(data)
    data.units[0].commander.equipment.clear()
    data.units[0].commander.book = "dark"
    check(decoded.setup.commander_options.ally_1.equipment.size() == 3
        and decoded.setup.commander_options.ally_1.book == "wind", "decoded nested fields do not alias input dictionaries")
    var exported: Dictionary = Codec.encode(setup)
    exported.data.units[0].commander.equipment.clear()
    check(Codec.encode(setup).code == before, "encoded equipment array does not alias source draft")
    var malformed: Dictionary = wire()
    malformed.units[2].commander.equipment.append("res://scripts/battle_demo.gd")
    var malformed_before: Dictionary = malformed.duplicate(true)
    var result: Dictionary = Codec.from_data(malformed)
    check(not result.ok and result.setup == null and malformed == malformed_before
        and Codec.encode(setup).code == before, "late bad loadout cannot leak a partial model or mutate input")
    check(Setup.CATALOG.male.commander.class_matter == Matter.NEUTRAL
        and Setup.CATALOG.male.commander.matter_equipment == original_equipment
        and Setup.CATALOG.male.magic_spell == original_spell
        and original_spell.magic_book.matter == Matter.FIRE, "portable operations leave catalog resources untouched")
    var padding: int = Codec.MAX_BYTES - before.to_utf8_buffer().size()
    check(Codec.decode(before + " ".repeat(padding)).ok
        and not Codec.decode(before + " ".repeat(padding + 1)).ok, "new nested descriptors preserve the exact 64 KiB wire boundary")
