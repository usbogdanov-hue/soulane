extends SceneTree
## Versioned automatic allocations and migration of genuine manual saves.
const Setup = preload("res://scripts/battle_setup.gd")
const Codec = preload("res://scripts/setup_codec.gd")
const Build = preload("res://scripts/commander_build.gd")
const Growth = preload("res://scripts/commander_growth.gd")
const Store = preload("res://scripts/setup_store.gd")
const LEGACY_KEYS: Array[String] = ["level", "armor", "STR", "AGI", "WIS", "INT"]
var checks: int = 0
var failures: int = 0
var paths: Array[String] = []

func _initialize() -> void:
    test_current_codes()
    test_manual_migration()
    test_strict_versions()
    test_library_migration()
    cleanup()
    if failures == 0:
        print("SULEYN automatic growth codec v1.15: %d checks passed." % checks)
    else:
        printerr("SULEYN automatic growth codec v1.15: %d / %d checks FAILED." % [failures, checks])
    quit(0 if failures == 0 else 1)

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED automatic growth codec v1.15: " + message)

func configured(level: int = 25):
    var setup = Setup.new()
    setup.set_arena("pillars")
    setup.enemy_ai_enabled = false
    setup.set_enabled("ally_3", false)
    var male: Dictionary = Build.resize(Setup.CATALOG.male, Build.defaults(Setup.CATALOG.male), level)
    male.class_matter = 1
    male.equipment = ["water_shield", "plain_sword", "water_sword"]
    male.book = "wind"
    setup.set_commander_options("ally_1", male)
    var female: Dictionary = Build.resize(Setup.CATALOG.female, Build.defaults(Setup.CATALOG.female), 20)
    female.armor = 1
    female.book = "water"
    setup.set_commander_options("ally_2", female)
    return setup

func legacy(version: int) -> Dictionary:
    var data: Dictionary = Codec.encode(configured()).data
    data.version = version
    for row in data.units:
        if row.commander == null:
            continue
        var old: Dictionary = {"level": 10, "armor": 0, "STR": 25, "AGI": 0, "WIS": 2, "INT": 0} if row.id == "ally_1" else {"level": 20, "armor": 2, "STR": 10, "AGI": 20, "WIS": 12, "INT": 15}
        if version == 4:
            old.class_matter = row.commander.class_matter
            old.equipment = row.commander.equipment.duplicate()
            old.book = row.commander.book
        row.commander = old
    return data

func reject(data: Variant, message: String) -> void:
    var decoded: Dictionary = Codec.from_data(data)
    check(not decoded.ok and decoded.setup == null and not decoded.reason.is_empty(), message)

func test_current_codes() -> void:
    check(Codec.VERSION == 5 and Store.VERSION == 1, "new preparation version keeps the outer library format")
    for level in [1, 10, 25, 31, 999]:
        var setup = configured(level)
        var encoded: Dictionary = Codec.encode(setup)
        check(encoded.ok and encoded.data.version == 5 and encoded.data.units.size() == 5, "v5 writes only selected fighters at level " + str(level))
        var decoded: Dictionary = Codec.decode(encoded.code)
        check(decoded.ok, "v5 automatic setup imports at level " + str(level))
        if not decoded.ok:
            continue
        var copy = decoded.setup
        var options: Dictionary = copy.commander_options.ally_1
        var expected: Dictionary = Growth.points(0, level)
        for key in Growth.KEYS:
            check(options[key] == expected[key], "derived allocation survives current code " + key)
        check(copy.unit_ids() == setup.unit_ids() and copy.positions == setup.positions
            and copy.arena_key == "pillars" and not copy.enemy_ai_enabled, "current code preserves battle preparation")
        check(options.class_matter == 1 and options.equipment == ["plain_sword", "water_sword", "water_shield"]
            and options.book == "wind", "current code preserves independent matter choices")
        check(Codec.encode(copy).code == encoded.code, "automatic code is canonical after JSON parsing")
        var stats = copy.profile_stats("ally_1")
        check(stats.commander.points_unspent() == 0 and stats.commander.auto_allocate,
            "imported current commander uses every earned point automatically")
        if level >= 25:
            check(stats.commander.primary_stats().STR > 45, "current import accepts STR above the removed cap")
        options.equipment.clear()
        check(setup.commander_options.ally_1.equipment.size() == 3, "current nested arrays are independent from the original setup")
    var high = configured(999)
    var preview: Dictionary = Build.preview(Setup.CATALOG.male, high.commander_options.ally_1)
    check(preview.physical_bonus == 90.0 and preview.magic_bonus == 90.0,
        "high imported attributes retain only the existing damage bonus ceiling")

func test_manual_migration() -> void:
    for version in [3, 4]:
        var data: Dictionary = legacy(version)
        var before: Dictionary = data.duplicate(true)
        var decoded: Dictionary = Codec.from_data(data)
        check(decoded.ok and data == before, "genuine old manual setup migrates without modifying input v" + str(version))
        if not decoded.ok:
            continue
        var setup = decoded.setup
        var male: Dictionary = setup.commander_options.ally_1
        var female: Dictionary = setup.commander_options.ally_2
        check(male.level == 10 and male.armor == 0 and female.level == 20 and female.armor == 2,
            "legacy levels and armor survive migration v" + str(version))
        check(male.STR == 13 and male.AGI == 8 and male.WIS == 3 and male.INT == 3,
            "old hand allocation becomes the approved male growth at level ten")
        check(female.STR == 17 and female.AGI == 23 and female.WIS == 11 and female.INT == 6,
            "old hand allocation becomes the approved female growth at level twenty")
        var stats = setup.profile_stats("ally_1")
        check(stats.commander.max_hp() == 575 and stats.commander.max_mp() == 113,
            "migrated health and mana derive from new growth, level and unchanged base formulas")
        if version == 3:
            check(male.class_matter == 0 and male.equipment.is_empty() and male.book == "fire"
                and female.book == "dark", "v3 adds original profile matter and books")
        else:
            check(male.class_matter == 1 and male.equipment == ["plain_sword", "water_sword", "water_shield"]
                and male.book == "wind" and female.book == "water", "v4 keeps existing source items and book IDs")
        check(setup.unit_ids().size() == 5 and setup.arena_key == "pillars" and not setup.enemy_ai_enabled,
            "legacy migration keeps partial sides and arena/controller")
        var rewritten: Dictionary = Codec.encode(setup)
        check(rewritten.ok and rewritten.data.version == 5
            and Codec.encode(Codec.decode(rewritten.code).setup).code == rewritten.code,
            "legacy setup has a stable canonical v5 rewrite")
    for version in [1, 2]:
        var data: Dictionary = Codec.encode(Setup.new()).data
        data.version = version
        for row in data.units:
            row.erase("commander")
        var decoded: Dictionary = Codec.from_data(data)
        check(decoded.ok and decoded.setup.commander_options.is_empty(), "earlier code keeps original catalog identity v" + str(version))
        check(decoded.setup.profile_stats("ally_1") == Setup.CATALOG.male
            and decoded.setup.profile_stats("ally_1").commander.points_str == 36,
            "earlier default commander resolves through current automatic growth")

func test_strict_versions() -> void:
    var valid: Dictionary = Codec.encode(configured()).data
    var changed: Dictionary = valid.duplicate(true)
    changed.units[0].commander.STR -= 1
    changed.units[0].commander.AGI += 1
    reject(changed, "same total cannot conceal a manually redistributed current allocation")
    changed = valid.duplicate(true)
    changed.units[0].commander.level = 26
    reject(changed, "changing level requires recalculating all derived current points")
    changed = valid.duplicate(true)
    changed.version = 6
    reject(changed, "future version remains unsupported")
    for version in [3, 4]:
        changed = legacy(version)
        changed.units[0].commander.STR = 36
        changed.units[0].commander.level = 25
        reject(changed, "old cap violation is rejected before automatic migration v" + str(version))
        changed = legacy(version)
        changed.units[0].commander.WIS = true
        reject(changed, "legacy numeric boolean cannot be hidden by recalculation v" + str(version))
        changed = legacy(version)
        changed.units[0].commander.level = 1
        reject(changed, "legacy over-budget points are rejected before recalculation v" + str(version))
        changed = legacy(version)
        changed.units[0].commander.extra = 0
        reject(changed, "legacy exact descriptor shape remains required v" + str(version))
    changed = legacy(3)
    changed.units[0].commander.book = "wind"
    reject(changed, "v3 cannot smuggle newer matter fields")
    changed = legacy(4)
    changed.units[0].commander.erase("book")
    reject(changed, "v4 still requires all nine historical fields")
    var setup = configured()
    var before: String = Codec.encode(setup).code
    var input: Dictionary = legacy(4)
    var input_before: Dictionary = input.duplicate(true)
    seed(115313)
    var expected: int = randi()
    seed(115313)
    for _iteration in range(5):
        Codec.encode(setup)
        Codec.decode(before)
        Codec.from_data(input)
    check(randi() == expected and input == input_before and Codec.encode(setup).code == before,
        "current encoding and migration preserve RNG, source input and draft")
    changed = valid.duplicate(true)
    changed.units[2].commander.INT += 1
    var rejected: Dictionary = Codec.from_data(changed)
    check(not rejected.ok and rejected.setup == null and Codec.encode(setup).code == before,
        "late invalid current field cannot expose a partially migrated setup")

func test_library_migration() -> void:
    var path: String = "user://test_auto_growth_codec_v115_%d.json" % Time.get_ticks_usec()
    paths.append(path)
    var library: Dictionary = {"format": Store.FORMAT, "version": 1, "last_setup": legacy(4),
        "slots": [{"name": "Прежние материи", "setup": legacy(4)}, {"name": "Прежние очки", "setup": legacy(3)}, null]}
    var file := FileAccess.open(path, FileAccess.WRITE)
    check(file != null, "isolated historical library fixture is writable")
    if file == null:
        return
    file.store_string(JSON.stringify(library))
    file.close()
    var store = Store.new(path)
    check(store.load_library().ok and store.list_slots()[0].name == "Прежние материи"
        and store.list_slots()[1].name == "Прежние очки", "outer v1 library loads both legacy descriptor generations")
    var restored = store.last_setup()
    check(restored != null and restored.commander_options.ally_1.STR == 13
        and restored.commander_options.ally_1.book == "wind", "last accepted old setup restores new growth and prior book")
    check(store.slot_setup(0).commander_options.ally_1.book == "wind"
        and store.slot_setup(1).commander_options.ally_1.book == "fire", "named old slots keep their distinct historical book choices")
    check(store.save_last(configured(999)).ok, "saving a new high-level setup preserves migrated named slots")
    var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
    check(stored.version == 1 and stored.last_setup.version == 5 and stored.slots[0].setup.version == 5
        and stored.slots[1].setup.version == 5 and stored.slots[2] == null, "next write uses current setup codes without changing library shape")
    var fresh = Store.new(path)
    check(fresh.load_library().ok and fresh.last_setup().profile_stats("ally_1").commander.primary_stats().STR > 45,
        "fresh store reopens uncapped automatic growth")
    check(fresh.list_slots()[0].name == "Прежние материи" and fresh.slot_setup(0).commander_options.ally_1.STR == 13,
        "old named slot and its migrated automatic allocation survive restart")

func cleanup() -> void:
    for path in paths:
        for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
            if FileAccess.file_exists(path + suffix):
                DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
