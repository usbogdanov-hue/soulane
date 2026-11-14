extends SceneTree
## Optional setup slots and backward-compatible portable codes.
const Setup = preload("res://scripts/battle_setup.gd")
const Codec = preload("res://scripts/setup_codec.gd")
const Board = preload("res://scripts/battle_board.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    test_sizes_and_roundtrips()
    test_gaps_and_occupancy()
    test_activation_and_resets()
    test_corruption()
    test_legacy_and_versions()
    test_purity()
    if failures == 0:
        print("SULEYN partial model v1.11: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN partial model v1.11: %d / %d checks FAILED." % [failures, checks])
        quit(1)


func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED partial model v1.11: " + label)


func sized(blue: int, red: int):
    var setup = Setup.new()
    for slot in range(1, 4):
        setup.set_enabled("ally_%d" % slot, slot <= blue)
        setup.set_enabled("enemy_%d" % slot, slot <= red)
    return setup


func test_sizes_and_roundtrips() -> void:
    for blue in range(1, 4):
        for red in range(1, 4):
            var setup = sized(blue, red)
            setup.set_arena("gates")
            setup.enemy_ai_enabled = false
            setup.set_profile("ally_1", "lich")
            setup.place_unit("ally_1", Vector2i(0, 0))
            var tag: String = "%d vs %d" % [blue, red]
            check(setup.is_valid(), "valid partial team " + tag)
            check(setup.side_count("blue") == blue and setup.side_count("red") == red, "counts selected units " + tag)
            check(setup.unit_ids().size() == blue + red and setup.unit_ids()[0] == "ally_1", "active-only order starts blue " + tag)
            var board = Board.new(setup.columns, setup.rows)
            for cell in setup.blocked_cells():
                board.set_blocked(cell, true)
            for unit_id in setup.unit_ids():
                check(board.add_unit(unit_id, setup.positions[unit_id]), "selected fighters can be placed " + tag)
            check(board.unit_positions.size() == blue + red, "no empty units spawned " + tag)
            var encoded: Dictionary = Codec.encode(setup)
            check(encoded.ok and encoded.data.version == Codec.VERSION and encoded.data.units.size() == blue + red, "current format contains selected rows only " + tag)
            var decoded: Dictionary = Codec.decode(encoded.code)
            check(decoded.ok and decoded.setup.unit_ids() == setup.unit_ids(), "partial order round-trips " + tag)
            if decoded.ok:
                check(decoded.setup.enabled_slots == setup.enabled_slots, "selected flags round-trip " + tag)
                check(decoded.setup.arena_key == "gates" and not decoded.setup.enemy_ai_enabled, "arena and control round-trip " + tag)
                check(decoded.setup.profile_key("ally_1") == "lich" and decoded.setup.positions.ally_1 == Vector2i(0, 0), "chosen fighter and position round-trip " + tag)
                check(Codec.encode(decoded.setup).code == encoded.code, "portable code remains canonical " + tag)


func test_gaps_and_occupancy() -> void:
    var setup = Setup.new()
    setup.set_enabled("ally_1", false)
    setup.set_enabled("ally_2", false)
    setup.set_enabled("enemy_2", false)
    check(setup.unit_ids() == ["ally_3", "enemy_1", "enemy_3"], "gaps compact before interleaving and blue still starts")
    var returned: Array[String] = setup.unit_ids()
    returned.clear()
    check(setup.unit_ids().size() == 3, "returned active list cannot mutate slots")
    var vacancy: Vector2i = setup.positions.ally_1
    check(setup.unit_at(vacancy).is_empty(), "inactive position is not occupied")
    check(not setup.place_unit("ally_1", Vector2i(0, 0)), "inactive slot cannot be moved")
    check(setup.place_unit("ally_3", vacancy), "active fighter may use inactive fighter's former cell")
    check(setup.unit_at(vacancy) == "ally_3" and setup.is_valid(), "inactive overlaps do not invalidate placement")
    setup.positions.ally_1 = Vector2i(-200, 800)
    check(setup.is_valid(), "inactive geometry is ignored")
    check(setup.side_count("missing") == 0 and not setup.is_enabled("unknown"), "unknown side and slot are safe")
    var encoded: Dictionary = Codec.encode(setup)
    check(encoded.ok and encoded.data.units.map(func(row): return row.id) == ["enemy_1", "ally_3", "enemy_3"], "wire rows retain canonical known-slot order independently of turn order")


func test_activation_and_resets() -> void:
    var setup = Setup.new()
    setup.set_enabled("ally_1", false)
    var old_cell: Vector2i = setup.positions.ally_1
    setup.place_unit("ally_2", old_cell)
    check(setup.set_enabled("ally_1", true), "re-enable succeeds when former cell is occupied")
    check(setup.positions.ally_1 != old_cell and setup.unit_at(setup.positions.ally_1) == "ally_1", "re-enable assigns a free own-zone cell")
    check(setup.is_valid(), "re-enable avoids blocked-next dead end")
    setup.set_enabled("enemy_1", false)
    var previous: Vector2i = setup.positions.enemy_1
    check(setup.set_profile("enemy_1", "lich") and setup.is_enabled("enemy_1"), "choosing a real profile activates its slot")
    check(setup.positions.enemy_1 == previous, "re-enable preserves a still-free position")
    setup.set_enabled("ally_2", false)
    setup.set_arena("pillars")
    setup.enemy_ai_enabled = false
    var copy = setup.copy()
    setup.enabled_slots.ally_2 = true
    check(not copy.is_enabled("ally_2"), "enabled dictionary is independently copied")
    copy.set_profile("enemy_3", "male")
    check(setup.profile_key("enemy_3") == "lich", "profile data remains independent")
    copy.reset_positions()
    check(not copy.is_enabled("ally_2") and copy.arena_key == "pillars" and not copy.enemy_ai_enabled, "position reset keeps selected slots, map and control")
    copy.reset_defaults()
    check(copy.unit_ids() == Setup.UNIT_IDS and copy.is_valid(), "default reset restores six active fighters")
    var before: Dictionary = setup.enabled_slots.duplicate()
    check(not setup.set_enabled("unknown", true) and setup.enabled_slots == before, "invalid enable is transactional")
    setup.set_enabled("ally_1", false)
    var profiles: Dictionary = setup.profile_keys.duplicate()
    check(not setup.set_profile("ally_1", "") and not setup.is_enabled("ally_1") and setup.profile_keys == profiles, "empty is not an arbitrary catalog profile")
    setup.columns = 3
    before = setup.enabled_slots.duplicate()
    var cells: Dictionary = setup.positions.duplicate()
    check(not setup.set_enabled("ally_1", true) and setup.enabled_slots == before and setup.positions == cells, "failed activation does not mutate selection or cell")


func test_corruption() -> void:
    var setup = sized(1, 1)
    setup.set_enabled("ally_1", false)
    check(not setup.is_valid(), "empty blue team invalidates start")
    setup = sized(1, 1)
    setup.set_enabled("enemy_1", false)
    check(not setup.is_valid(), "empty red team invalidates start")
    setup = sized(1, 1)
    setup.enabled_slots.extra = true
    check(not setup.is_valid(), "unknown selection key invalidates model")
    setup = sized(1, 1)
    setup.enabled_slots.erase("ally_2")
    check(not setup.is_valid(), "missing inactive selection flag is rejected")
    setup = sized(1, 1)
    setup.enabled_slots.ally_2 = 1
    check(not setup.is_enabled("ally_2") and not setup.is_valid(), "nonboolean flag cannot silently enable a fighter")
    setup = sized(1, 1)
    setup.positions.ally_2 = "bad"
    check(not setup.is_valid(), "inactive position still needs its declared value type")
    setup = sized(1, 1)
    setup.profile_keys.ally_2 = "missing"
    check(not setup.is_valid(), "inactive cached profile cannot bypass allowlist")


func legacy_data(setup, version: int) -> Dictionary:
    var data: Dictionary = Codec.encode(setup).data
    data.version = version
    for row in data.units:
        row.erase("commander")
    return data


func test_legacy_and_versions() -> void:
    var complete = Setup.new()
    complete.set_arena("pillars")
    var legacy: Dictionary = legacy_data(complete, 1)
    legacy.version = 1.0
    var decoded: Dictionary = Codec.from_data(legacy)
    check(decoded.ok and decoded.setup.unit_ids() == Setup.UNIT_IDS, "v1 full team still loads with every slot active")
    check(decoded.ok and decoded.setup.arena_key == "pillars", "v1 arena preserved")
    var partial_data: Dictionary = legacy_data(sized(1, 2), 1)
    check(not Codec.from_data(partial_data).ok, "v1 partial wire records cannot be misread as legacy full team")
    partial_data.version = Codec.VERSION + 1
    check(not Codec.from_data(partial_data).ok, "unknown future version remains rejected")
    partial_data = legacy_data(sized(1, 2), 2)
    partial_data.units = partial_data.units.filter(func(row): return row.id.begins_with("enemy_"))
    check(not Codec.from_data(partial_data).ok, "v2 with two red fighters and no blue is rejected")
    partial_data = legacy_data(sized(1, 1), 2)
    partial_data.units[1] = partial_data.units[0].duplicate()
    check(not Codec.from_data(partial_data).ok, "duplicate v2 slots rejected")
    partial_data = legacy_data(sized(1, 1), 2)
    partial_data.units[1].id = "enemy_4"
    check(not Codec.from_data(partial_data).ok, "unknown v2 slot rejected")
    partial_data = legacy_data(sized(1, 1), 2)
    partial_data.units[0].x = -1
    check(not Codec.from_data(partial_data).ok, "active partial coordinates still validated")


func test_purity() -> void:
    var setup = sized(2, 3)
    var flags: Dictionary = setup.enabled_slots.duplicate()
    var cells: Dictionary = setup.positions.duplicate()
    var code: String = Codec.encode(setup).code
    seed(81113)
    var expected: int = randi()
    seed(81113)
    for index in range(10):
        setup.unit_ids()
        setup.unit_at(Vector2i(1, 1))
        setup.side_count("blue")
        Codec.encode(setup)
        Codec.decode(code)
        setup.copy()
    check(randi() == expected, "reading and transferring partial setup never consumes RNG")
    check(setup.enabled_slots == flags and setup.positions == cells and Codec.encode(setup).code == code, "reads leave flags, positions and wire representation unchanged")
