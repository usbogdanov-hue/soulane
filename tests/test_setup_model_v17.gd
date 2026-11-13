extends SceneTree
## Data-only preparation validation, independent draft copies and deployment zones.
## Run: godot --headless --path . --script res://tests/test_setup_model_v17.gd

const Setup = preload("res://scripts/battle_setup.gd")
const Board = preload("res://scripts/battle_board.gd")
const EXPECTED_IDS: Array[String] = ["ally_1", "enemy_1", "ally_2", "enemy_2", "ally_3", "enemy_3"]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    test_defaults_and_catalog()
    test_roster_edits()
    test_deployment()
    test_map_sizes()
    test_copy_is_independent()
    test_corrupt_drafts()
    test_resets()
    if failures == 0:
        print("SULEYN setup model v1.7: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN setup model v1.7: %d / %d checks FAILED." % [failures, checks])
        quit(1)


func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED setup model: " + label)


func test_defaults_and_catalog() -> void:
    var setup = Setup.new()
    check(setup.columns == 9 and setup.rows == 7, "standard map dimensions")
    check(setup.unit_ids() == EXPECTED_IDS, "stable interleaved IDs")
    check(setup.is_valid() and setup.validation_errors().is_empty(), "default draft is valid")
    check(setup.enemy_ai_enabled, "red AI is enabled by default")
    var order: Array[String] = setup.unit_ids()
    order.clear()
    check(setup.unit_ids() == EXPECTED_IDS, "returned order cannot mutate fixed slots")
    var expected: Dictionary = {"ally_1": "male", "ally_2": "female", "ally_3": "falcon",
        "enemy_1": "hellhound", "enemy_2": "falcon", "enemy_3": "lich"}
    for id in EXPECTED_IDS:
        check(setup.profile_key(id) == expected[id], "default resource key " + id)
        check(setup.profile_stats(id) == Setup.catalog_entry(expected[id]), "existing resource reused " + id)
        check(setup.unit_at(setup.positions[id]) == id, "position maps back to " + id)
        check(setup.team_for(id) == ("blue" if id.begins_with("ally_") else "red"), "team for " + id)
    for key in Setup.PROFILE_KEYS:
        check(Setup.catalog_entry(key) != null and not Setup.profile_label(key).is_empty(), "catalog resource and label " + key)
    check(Setup.PROFILE_KEYS == ["male", "female", "falcon", "hellhound", "lich"], "fixed catalog order")
    check(Setup.catalog_entry("unknown") == null and Setup.profile_label("unknown").is_empty(), "unknown catalog value is not usable")
    check(setup.profile_stats("unknown") == null and setup.profile_key("unknown").is_empty(), "unknown actor has no profile")
    check(setup.team_for("ally_9").is_empty() and setup.team_for("enemy_0").is_empty(), "prefix is not a valid slot")


func test_roster_edits() -> void:
    var setup = Setup.new()
    var positions: Dictionary = setup.positions.duplicate(true)
    for id in EXPECTED_IDS:
        check(setup.set_profile(id, "lich"), "duplicates are legal in any team slot " + id)
    check(setup.is_valid(), "six same profiles form a valid test composition")
    check(setup.positions == positions, "composition changes preserve placement")
    var before: Dictionary = setup.profile_keys.duplicate(true)
    check(not setup.set_profile("ally_9", "male"), "unknown slot rejected")
    check(not setup.set_profile("", "male"), "empty slot rejected")
    check(not setup.set_profile("ally_1", "unknown"), "unknown profile rejected")
    check(setup.profile_keys == before, "invalid composition edits do not mutate state")
    check(setup.profile_stats("ally_1") == setup.profile_stats("enemy_1"), "catalog resources stay read-only/shared")


func test_deployment() -> void:
    var setup = Setup.new()
    check(setup.cell_is_deployment("blue", Vector2i(0, 0)), "blue first column")
    check(setup.cell_is_deployment("blue", Vector2i(1, 6)), "blue second column and final row")
    check(setup.cell_is_deployment("red", Vector2i(7, 0)), "red penultimate column")
    check(setup.cell_is_deployment("red", Vector2i(8, 6)), "red final column")
    for cell in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(9, 0), Vector2i(0, 7), Vector2i(4, 3)]:
        check(not setup.cell_is_deployment("blue", cell) and not setup.cell_is_deployment("red", cell),
            "outside field or neutral columns rejected " + str(cell))
    check(not setup.cell_is_deployment("unknown", Vector2i(0, 0)), "unknown team has no deployment zone")
    check(not setup.cell_is_deployment("blue", Vector2i(8, 0)) and not setup.cell_is_deployment("red", Vector2i(0, 0)), "teams cannot use each other's zone")
    check(setup.place_unit("ally_1", Vector2i(0, 0)), "move draft ally to free friendly hex")
    check(setup.positions["ally_1"] == Vector2i(0, 0) and setup.unit_at(Vector2i(1, 1)).is_empty(), "old draft hex is freed")
    check(setup.place_unit("ally_1", Vector2i(0, 0)), "placing on own position is an allowed no-op")
    check(setup.place_unit("enemy_3", Vector2i(8, 6)), "move red to free red hex")
    var before: Dictionary = setup.positions.duplicate(true)
    check(not setup.place_unit("ally_1", setup.positions["ally_2"]), "occupied friendly hex rejected without swapping")
    check(not setup.place_unit("ally_1", setup.positions["enemy_1"]), "occupied enemy hex rejected")
    check(not setup.place_unit("ally_1", Vector2i(3, 0)), "neutral zone rejected")
    check(not setup.place_unit("enemy_1", Vector2i(0, 0)), "opposite zone rejected")
    check(not setup.place_unit("missing", Vector2i(0, 1)), "unknown actor placement rejected")
    check(setup.positions == before, "all invalid placements preserve draft")
    check(setup.is_valid(), "legal edits retain a startable draft")


func test_map_sizes() -> void:
    for dimensions in [Vector2i(-2, -5), Vector2i(0, 0), Vector2i(4, 3), Vector2i(5, 4), Vector2i(9, 7), Vector2i(20, 14)]:
        var setup = Setup.new(dimensions.x, dimensions.y)
        check(setup.columns == maxi(4, dimensions.x) and setup.rows == maxi(3, dimensions.y), "dimensions clamp to usable board " + str(dimensions))
        check(setup.is_valid(), "all six fit a valid sized map " + str(dimensions))
        var board = Board.new(setup.columns, setup.rows)
        for id in setup.unit_ids():
            check(board.add_unit(id, setup.positions[id]), "default placement has unique in-bounds cell " + str(dimensions) + " " + id)
        check(board.unit_positions.size() == 6, "minimum map also fits six separate fighters")
    var narrow = Setup.new(4, 3)
    for y in range(3):
        for x in range(4):
            var cell := Vector2i(x, y)
            check(narrow.cell_is_deployment("blue", cell) != narrow.cell_is_deployment("red", cell), "minimum board zones never overlap " + str(cell))


func test_copy_is_independent() -> void:
    var setup = Setup.new()
    setup.set_profile("ally_1", "lich")
    setup.place_unit("ally_1", Vector2i(0, 0))
    setup.enemy_ai_enabled = false
    var accepted = setup.copy()
    check(accepted != setup and accepted.is_valid(), "copy is a separate valid draft")
    check(accepted.columns == setup.columns and accepted.rows == setup.rows, "copy keeps dimensions")
    check(not accepted.enemy_ai_enabled and accepted.profile_key("ally_1") == "lich", "copy keeps selected profile and AI preference")
    setup.set_profile("ally_1", "female")
    setup.place_unit("ally_1", Vector2i(0, 1))
    setup.enemy_ai_enabled = true
    check(accepted.profile_key("ally_1") == "lich" and accepted.positions["ally_1"] == Vector2i(0, 0), "editing draft cannot alter accepted configuration")
    check(not accepted.enemy_ai_enabled, "editing draft AI flag cannot alter accepted configuration")
    accepted.positions["enemy_1"] = Vector2i(8, 1)
    check(setup.positions["enemy_1"] != Vector2i(8, 1), "copy positions do not share dictionary mutations")
    accepted.profile_keys["enemy_1"] = "male"
    check(setup.profile_key("enemy_1") == "hellhound", "copy profiles do not share dictionary mutations")


func test_corrupt_drafts() -> void:
    var setup = Setup.new()
    setup.profile_keys.erase("ally_1")
    check(not setup.is_valid(), "missing profile invalidates draft")
    setup.reset_defaults()
    setup.profile_keys["ally_1"] = "unlisted"
    check(not setup.is_valid(), "unlisted profile invalidates draft")
    setup.profile_keys["ally_1"] = 42
    check(not setup.is_valid(), "wrong profile value type invalidates safely")
    setup.reset_defaults()
    setup.profile_keys["extra"] = "male"
    check(not setup.is_valid(), "additional profile slot invalidates draft")
    setup.reset_defaults()
    setup.positions.erase("ally_1")
    check(not setup.is_valid(), "missing position invalidates draft")
    check(setup.unit_at(Vector2i(1, 1)).is_empty(), "missing position cannot create an occupant")
    check(not setup.place_unit("ally_1", Vector2i(0, 0)), "placement cannot silently recreate missing slot")
    setup.reset_defaults()
    setup.positions["ally_1"] = Vector2(0, 0)
    check(not setup.is_valid(), "fractional-coordinate type rejected")
    setup.positions["ally_1"] = "bad"
    check(not setup.is_valid(), "wrong coordinate type rejected safely")
    check(setup.unit_at(Vector2i(0, 0)).is_empty(), "malformed position does not crash occupancy lookup")
    check(setup.place_unit("ally_2", Vector2i(0, 0)), "well-typed placement safely ignores malformed coordinate values")
    setup.reset_defaults()
    setup.positions["ally_1"] = setup.positions["ally_2"]
    check(not setup.is_valid(), "duplicated cell invalidates start")
    setup.reset_defaults()
    setup.positions["ally_1"] = Vector2i(8, 0)
    check(not setup.is_valid(), "opposite-side deployment invalidates start")
    setup.reset_defaults()
    setup.positions["extra"] = Vector2i(0, 0)
    check(not setup.is_valid(), "extra placement invalidates draft")
    setup.reset_defaults()
    setup.columns = 3
    check(not setup.is_valid(), "mutated too-small dimensions invalidated")
    var invalid_copy = setup.copy()
    check(invalid_copy.columns == 3 and not invalid_copy.is_valid(), "copy cannot silently repair invalid dimensions")


func test_resets() -> void:
    var setup = Setup.new()
    setup.set_profile("ally_1", "lich")
    setup.place_unit("ally_1", Vector2i(0, 0))
    setup.enemy_ai_enabled = false
    setup.reset_positions()
    check(setup.positions["ally_1"] == Vector2i(1, 1), "position reset restores original layout")
    check(setup.profile_key("ally_1") == "lich" and not setup.enemy_ai_enabled, "position reset preserves selected composition and controller")
    setup.reset_defaults()
    check(setup.is_valid() and setup.profile_key("ally_1") == "male" and setup.enemy_ai_enabled, "full defaults reset returns standard example")
    check(setup.unit_at(Vector2i(0, 0)).is_empty(), "unit_at returns empty on free deployment hex")
