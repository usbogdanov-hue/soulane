extends SceneTree
## Portable setup round-trips and rejects malformed data without changing state.

const Setup = preload("res://scripts/battle_setup.gd")
const Arena = preload("res://scripts/battle_arena.gd")
const Codec = preload("res://scripts/setup_codec.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    test_round_trip(4, 3, "open")
    for dimensions in [Vector2i(7, 5), Vector2i(9, 7), Vector2i(20, 14)]:
        for arena in Arena.keys():
            test_round_trip(dimensions.x, dimensions.y, arena)
    test_bad_encoding()
    test_text_boundary()
    test_schema_and_types()
    test_units_and_positions()
    test_transaction_and_rng()
    if failures == 0:
        print("SULEYN setup codec v1.10: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN setup codec v1.10: %d / %d checks FAILED." % [failures, checks])
        quit(1)


func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED setup codec v1.10: " + label)


func base_data() -> Dictionary:
    return Codec.encode(Setup.new()).data


func reject(data: Variant, label: String) -> void:
    var result: Dictionary = Codec.from_data(data)
    check(not result.ok and result.setup == null and not result.reason.is_empty(), label)


func test_round_trip(columns: int, rows: int, arena: String) -> void:
    var setup = Setup.new(columns, rows)
    setup.set_arena(arena)
    setup.enemy_ai_enabled = false
    var profiles: Array[String] = ["lich", "female", "lich", "male", "hellhound", "falcon"]
    for index in range(Setup.UNIT_IDS.size()):
        var id: String = Setup.UNIT_IDS[index]
        setup.set_profile(id, profiles[index])
        var slot: int = index / 2
        setup.positions[id] = Vector2i(0, slot) if setup.team_for(id) == "blue" else Vector2i(columns - 1, rows - 1 - slot)
    var snapshot_profiles: Dictionary = setup.profile_keys.duplicate()
    var snapshot_positions: Dictionary = setup.positions.duplicate()
    var encoded: Dictionary = Codec.encode(setup)
    var tag: String = "%s %dx%d" % [arena, columns, rows]
    check(encoded.ok and encoded.reason.is_empty(), "valid custom setup encodes " + tag)
    check(encoded.code == Codec.encode(setup).code, "code is deterministic " + tag)
    check(encoded.data.units.map(func(row): return row.id) == Setup.UNIT_IDS, "canonical slot order " + tag)
    var decoded: Dictionary = Codec.decode(encoded.code)
    check(decoded.ok and decoded.reason.is_empty(), "JSON round-trip succeeds " + tag)
    if not decoded.ok:
        return
    var copy = decoded.setup
    check(copy != setup and copy.columns == columns and copy.rows == rows, "fresh model with exact dimensions " + tag)
    check(copy.profile_keys == snapshot_profiles and copy.positions == snapshot_positions, "profiles and cells preserved " + tag)
    check(copy.arena_key == arena and not copy.enemy_ai_enabled, "arena and manual setting preserved " + tag)
    check(Codec.encode(copy).code == encoded.code, "round-trip remains canonical " + tag)
    copy.set_profile("ally_1", "male")
    copy.positions["ally_1"] = Vector2i(1, 0)
    encoded.data.units[0].profile = "falcon"
    check(setup.profile_keys == snapshot_profiles and setup.positions == snapshot_positions, "copies and output data do not alias source " + tag)


func test_bad_encoding() -> void:
    for value in [null, 7, "res://data/demo_male_lv25.tres", {}, []]:
        var result: Dictionary = Codec.encode(value)
        check(not result.ok and result.data.is_empty() and result.code.is_empty() and not result.reason.is_empty(), "non-setup encoding fails safely")
    var setup = Setup.new()
    setup.columns = 21
    check(not Codec.encode(setup).ok, "encoding refuses oversized dimensions")
    setup.columns = 9
    setup.rows = 15
    check(not Codec.encode(setup).ok, "encoding refuses excessive rows")
    setup.rows = 7
    setup.arena_key = "missing"
    check(not Codec.encode(setup).ok, "encoding refuses unknown arena")
    setup.arena_key = "open"
    setup.positions["ally_1"] = setup.positions["ally_2"]
    check(not Codec.encode(setup).ok, "encoding refuses occupied placement")


func test_text_boundary() -> void:
    for code in ["", " \n\t ", "{", "[]", "null", "7", '"hello"']:
        var result: Dictionary = Codec.decode(code)
        check(not result.ok and result.setup == null and not result.reason.is_empty(), "malformed text is rejected")
    var code: String = Codec.encode(Setup.new()).code
    var padding: int = Codec.MAX_BYTES - code.to_utf8_buffer().size()
    check(Codec.decode(code + " ".repeat(padding)).ok, "exactly64KiB valid text is accepted")
    var too_long: Dictionary = Codec.decode(code + " ".repeat(padding + 1))
    check(not too_long.ok and too_long.reason.contains("64"), "byte beyond limit rejected before parsing")
    var unicode: Dictionary = Codec.decode("я".repeat(33000))
    check(not unicode.ok and unicode.reason.contains("64"), "limit counts UTF8 bytes instead of characters")


func test_schema_and_types() -> void:
    reject(null, "null root rejected")
    reject([], "array root rejected")
    for key in base_data().keys():
        var missing: Dictionary = base_data()
        missing.erase(key)
        reject(missing, "missing root field rejected " + str(key))
    var data: Dictionary = base_data()
    data["resource_path"] = "res://scripts/battle_demo.gd"
    reject(data, "unknown root fields rejected")
    for value in [null, 1, true, "other.game", ""]:
        data = base_data()
        data.format = value
        reject(data, "invalid format rejected")
    for value in [null, "1", true, 0, 2, 1.1, NAN, INF]:
        data = base_data()
        data.version = value
        reject(data, "unsupported or nonintegral version rejected")
    for value in [3, 21, -1, 8.5, "9", true, NAN, INF]:
        data = base_data()
        data.columns = value
        reject(data, "invalid columns rejected")
    for value in [2, 15, -1, 6.5, "7", false, NAN, -INF]:
        data = base_data()
        data.rows = value
        reject(data, "invalid rows rejected")
    for value in [null, "yes", 0, 1, [], {}]:
        data = base_data()
        data.enemy_ai = value
        reject(data, "AI setting must be a boolean")
    for value in [null, true, 1, "missing", "res://scripts/battle_demo.gd"]:
        data = base_data()
        data.arena = value
        reject(data, "unknown arena or path rejected")
    data = base_data()
    data.columns = 4
    data.rows = 3
    data.arena = "gates"
    reject(data, "small arena cannot import obstacles")
    data = base_data()
    data.version = 1.0
    data.columns = 9.0
    data.rows = 7.0
    for row in data.units:
        row.x = float(row.x)
        row.y = float(row.y)
    check(Codec.from_data(data).ok, "integral JSON floats are accepted")


func test_units_and_positions() -> void:
    var data: Dictionary = base_data()
    for value in [null, {}, "units", [], [1, 2, 3, 4, 5, 6]]:
        data = base_data()
        data.units = value
        reject(data, "units must be six structured records")
    data = base_data()
    data.units.pop_back()
    reject(data, "missing sixth unit rejected")
    data = base_data()
    data.units.append(data.units[0].duplicate())
    reject(data, "seventh unit rejected")
    for key in ["id", "profile", "x", "y"]:
        data = base_data()
        data.units[0].erase(key)
        reject(data, "missing unit field rejected " + key)
    data = base_data()
    data.units[0]["resource"] = "res://data/demo_male_lv25.tres"
    reject(data, "extra unit field rejected")
    for value in [null, 1, true, "missing", "enemy_4", "res://scripts/battle_demo.gd"]:
        data = base_data()
        data.units[0].id = value
        reject(data, "unknown unit identifier rejected")
    data = base_data()
    data.units[0].id = data.units[1].id
    reject(data, "duplicate identifier rejected")
    for value in [null, true, 1, "missing", "res://data/demo_male_lv25.tres", Setup.CATALOG.male]:
        data = base_data()
        data.units[0].profile = value
        reject(data, "profile allowlist prevents arbitrary resources")
    for key in ["x", "y"]:
        for value in [null, true, "1", -1, 100, 1.25, NAN, INF]:
            data = base_data()
            data.units[0][key] = value
            reject(data, "invalid coordinate rejected " + key)
    data = base_data()
    data.units[0].x = 9
    reject(data, "right boundary excluded")
    data = base_data()
    data.units[0].y = 7
    reject(data, "bottom boundary excluded")
    data = base_data()
    data.units[0].x = 4
    reject(data, "placement outside side zone rejected")
    data = base_data()
    data.units[0].x = data.units[2].x
    data.units[0].y = data.units[2].y
    reject(data, "overlapping deployment rejected")
    data = base_data()
    data.units.reverse()
    check(Codec.from_data(data).ok, "known identifiers may arrive in another order")


func test_transaction_and_rng() -> void:
    var setup = Setup.new()
    setup.set_arena("pillars")
    setup.set_profile("ally_1", "lich")
    var code: String = Codec.encode(setup).code
    var valid_data: Dictionary = Codec.encode(setup).data
    var snapshot: Dictionary = valid_data.duplicate(true)
    seed(39017)
    var expected_random: int = randi()
    seed(39017)
    for index in range(10):
        Codec.encode(setup)
        Codec.decode(code)
        Codec.from_data(valid_data)
    check(randi() == expected_random, "encoding and decoding never consume RNG")
    check(valid_data == snapshot and Codec.encode(setup).code == code, "successful reads leave source data and setup unchanged")
    var invalid_data: Dictionary = valid_data.duplicate(true)
    invalid_data.units[5].x = -1
    var invalid_before: Dictionary = invalid_data.duplicate(true)
    var failure: Dictionary = Codec.from_data(invalid_data)
    check(not failure.ok and failure.setup == null, "late invalid row does not leak a partial model")
    check(invalid_data == invalid_before and Codec.encode(setup).code == code, "failed import changes neither input nor accepted source")
    var decoded = Codec.from_data(valid_data).setup
    valid_data.units[0].x = 0
    check(decoded.positions["ally_1"] != Vector2i(0, int(valid_data.units[0].y)), "decoded model does not alias input records")
