extends SceneTree
## Strict commander configuration wire records and previous-version readers.
const Setup = preload("res://scripts/battle_setup.gd")
const Codec = preload("res://scripts/setup_codec.gd")
const Build = preload("res://scripts/commander_build.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    test_defaults_and_legacy()
    test_configured_roundtrips()
    test_schema_and_ranges()
    test_purity_and_failed_encoding()
    if failures == 0:
        print("SULEYN build codec v1.12: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN build codec v1.12: %d / %d checks FAILED." % [failures, checks])
        quit(1)


func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED build codec v1.12: " + label)


func configured():
    var setup = Setup.new()
    setup.set_arena("gates")
    setup.enemy_ai_enabled = false
    setup.set_commander_options("ally_1", options_for("male", {"level": 10, "armor": 0, "STR": 6, "AGI": 4, "WIS": 7, "INT": 3}))
    setup.set_commander_options("ally_2", options_for("female", {"level": 20, "armor": 2, "STR": 10, "AGI": 20, "WIS": 12, "INT": 15}))
    return setup


func options_for(profile: String, stats: Dictionary) -> Dictionary:
    var result: Dictionary = Build.defaults(Setup.catalog_entry(profile))
    result.merge(stats, true)
    return result


func wire() -> Dictionary:
    return Codec.encode(configured()).data


func reject(data: Variant, label: String) -> void:
    var result: Dictionary = Codec.from_data(data)
    check(not result.ok and result.setup == null and not result.reason.is_empty(), label)


func legacy(data: Dictionary, version: int) -> Dictionary:
    var copy: Dictionary = data.duplicate(true)
    copy.version = version
    for row in copy.units:
        row.erase("commander")
    return copy


func test_defaults_and_legacy() -> void:
    var setup = Setup.new()
    var encoded: Dictionary = Codec.encode(setup)
    check(encoded.ok and encoded.data.version == 4 and encoded.data.units.size() == 6, "v4 is written for default full setup")
    for row in encoded.data.units:
        check(row.has("commander") and row.commander == null, "unchanged kit has explicit null configuration")
    for version in [1, 2]:
        var data: Dictionary = legacy(encoded.data, version)
        var restored: Dictionary = Codec.from_data(data)
        check(restored.ok and restored.setup.commander_options.is_empty(), "legacy readers retain catalog defaults")
        if restored.ok:
            check(restored.setup.profile_stats("ally_1") == Setup.CATALOG.male, "legacy male resource identity retained")
            check(restored.setup.profile_stats("ally_2") == Setup.CATALOG.female, "legacy female resource identity retained")
            check(restored.setup.unit_ids() == Setup.UNIT_IDS, "legacy full selection remains unchanged")
        data.units[0]["commander"] = null
        reject(data, "legacy schema cannot conceal new fields")
    setup.set_enabled("ally_1", false)
    setup.set_enabled("ally_3", false)
    setup.set_enabled("enemy_2", false)
    var partial: Dictionary = Codec.encode(setup).data
    var old_partial: Dictionary = Codec.from_data(legacy(partial, 2))
    check(old_partial.ok and old_partial.setup.unit_ids() == setup.unit_ids(), "v2 reads partial active slots and their compact order")
    reject(legacy(partial, 1), "v1 continues requiring a full team record")
    var future: Dictionary = partial.duplicate(true)
    future.version = 5
    reject(future, "future versions remain rejected")


func test_configured_roundtrips() -> void:
    for arena in ["open", "gates", "pillars"]:
        var setup = configured()
        setup.set_arena(arena)
        for unit_id in ["ally_3", "enemy_2", "enemy_3"]:
            setup.set_enabled(unit_id, false)
        var encoded: Dictionary = Codec.encode(setup)
        check(encoded.ok and encoded.data.units.size() == 3, "configured partial wire has only selected fighters")
        var restored: Dictionary = Codec.decode(encoded.code)
        check(restored.ok, "configured code imports " + arena)
        if not restored.ok:
            continue
        var copy = restored.setup
        check(copy.commander_options == setup.commander_options, "all per-slot choices round-trip")
        check(copy.enabled_slots == setup.enabled_slots and copy.arena_key == arena and not copy.enemy_ai_enabled, "selection, map and controller survive")
        check(copy.positions == setup.positions, "deployment survives with current active slots")
        for unit_id in ["ally_1", "ally_2"]:
            var original = setup.profile_stats(unit_id)
            var stats = copy.profile_stats(unit_id)
            check(stats != Setup.catalog_entry(copy.profile_key(unit_id)) and stats.commander != original.commander, "decoded options materialize private resources")
            check(stats.commander.primary_stats() == original.commander.primary_stats(), "allocated final stats agree")
            check(stats.commander.max_hp() == original.commander.max_hp() and stats.commander.max_mp() == original.commander.max_mp(), "derived health and mana agree")
            check(stats.commander.armor_type == original.commander.armor_type, "chosen armor agrees")
            check(stats.special_skill == original.special_skill and stats.magic_spell == original.magic_spell, "configuration does not replace ability or spell")
        check(copy.profile_stats("ally_2").commander.critical_multiplier() == 2.0, "female critical passive is preserved")
        check(Codec.encode(copy).code == encoded.code, "v4 code remains canonical after JSON parse")
        copy.commander_options.ally_1.STR = 0
        check(setup.commander_options.ally_1.STR == 6, "decoded option dictionary does not alias source")
    var highest = Setup.new()
    check(highest.set_commander_options("ally_1", options_for("male", {"level": 999, "armor": 3, "STR": 35, "AGI": 2000, "WIS": 920, "INT": 39})), "highest level supports full legal allocation")
    var upper: Dictionary = Codec.decode(Codec.encode(highest).code)
    check(upper.ok and upper.setup.profile_stats("ally_1").commander.level == 999, "upper legal level survives portable code")
    var integral: Dictionary = wire()
    for key in ["level", "armor", "STR", "AGI", "WIS", "INT", "class_matter"]:
        integral.units[0].commander[key] = float(integral.units[0].commander[key])
    var floats: Dictionary = Codec.from_data(integral)
    check(floats.ok and Codec.encode(floats.setup).code == Codec.encode(configured()).code, "integral JSON floats normalize to canonical integers")


func test_schema_and_ranges() -> void:
    var data: Dictionary = wire()
    data.units[0].erase("commander")
    reject(data, "v4 requires the commander member even for unchanged kits")
    for value in [true, 4, "res://data/male_warrior_lv25.tres", [], {}]:
        data = wire()
        data.units[0].commander = value
        reject(data, "configuration must be a complete plain dictionary")
    for key in ["level", "armor", "STR", "AGI", "WIS", "INT"]:
        data = wire()
        data.units[0].commander.erase(key)
        reject(data, "missing configuration field rejected " + key)
        for value in [null, true, "3", -1, 1.5, NAN, INF, []]:
            data = wire()
            data.units[0].commander[key] = value
            reject(data, "strict numeric configuration field " + key)
    data = wire()
    data.units[0].commander["resource"] = "res://scripts/battle_demo.gd"
    reject(data, "configuration cannot hide a resource or extra field")
    for level in [0, 1000]:
        data = wire()
        data.units[0].commander.level = level
        reject(data, "out-of-range levels rejected before setters clamp")
    data = wire()
    data.units[0].commander.armor = 4
    reject(data, "out-of-range armor rejected before setter clamps")
    data = wire()
    data.units[0].commander.level = 1
    reject(data, "point budget is checked against level")
    for stat in ["STR", "INT"]:
        data = wire()
        data.units[0].commander.level = 999
        data.units[0].commander[stat] = 45
        reject(data, "base plus allocation caps " + stat)
    for stat in ["AGI", "WIS"]:
        data = wire()
        data.units[0].commander.level = 999
        data.units[0].commander[stat] = 2995
        reject(data, "allocation bound checked " + stat)
    data = wire()
    data.units[1].commander = data.units[0].commander.duplicate(true)
    reject(data, "monster cannot import commander fields")
    data = wire()
    data.units[0].commander = null
    check(Codec.from_data(data).ok and not Codec.from_data(data).setup.commander_options.has("ally_1"), "null keeps unchanged commander defaults")


func test_purity_and_failed_encoding() -> void:
    var setup = configured()
    var encoded: Dictionary = Codec.encode(setup)
    var before: String = encoded.code
    var input: Dictionary = encoded.data.duplicate(true)
    var input_before: Dictionary = input.duplicate(true)
    seed(112789)
    var expected: int = randi()
    seed(112789)
    for index in range(5):
        Codec.encode(setup)
        Codec.decode(before)
        Codec.from_data(input)
    check(randi() == expected and input == input_before and Codec.encode(setup).code == before, "codec preserves RNG, input and draft")
    var malformed: Dictionary = input.duplicate(true)
    malformed.units[2].commander.INT = 4000
    var rejected: Dictionary = Codec.from_data(malformed)
    check(not rejected.ok and rejected.setup == null and Codec.encode(setup).code == before, "late invalid configuration cannot leak a partially applied setup")
    encoded.data.units[0].commander.STR = 0
    check(setup.commander_options.ally_1.STR == 6, "exported option data is independent")
    var invalid = configured()
    invalid.commander_options.enemy_1 = Build.defaults(Setup.CATALOG.male)
    check(not Codec.encode(invalid).ok, "encoding refuses manually corrupted monster options")
    invalid = configured()
    invalid.commander_options.ally_1.level = 1
    check(not Codec.encode(invalid).ok, "encoding cannot hide a point-budget violation")
    invalid = configured()
    invalid.commander_options.extra = Build.defaults(Setup.CATALOG.male)
    check(not Codec.encode(invalid).ok, "encoding rejects an unknown options slot")
    var original = Setup.CATALOG.male.commander
    check(original.level == 25 and original.points_str == 35 and original.armor_type == 3, "portable reads never modify original catalog commander")
    var code: String = Codec.encode(setup).code
    var padding: int = Codec.MAX_BYTES - code.to_utf8_buffer().size()
    check(Codec.decode(code + " ".repeat(padding)).ok, "configured setup retains exact byte-boundary support")
    check(not Codec.decode(code + " ".repeat(padding + 1)).ok, "configured setup still rejects byte beyond limit")
