extends SceneTree
## Arena invariants, connectivity and independent preparation drafts.

const Arena = preload("res://scripts/battle_arena.gd")
const Setup = preload("res://scripts/battle_setup.gd")
const Board = preload("res://scripts/battle_board.gd")
const Hex = preload("res://scripts/hex_math.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    test_catalog()
    for dimensions in [Vector2i(9, 7), Vector2i(7, 5), Vector2i(20, 14)]:
        for key in Arena.keys():
            test_layout(key, dimensions)
    test_small_and_invalid_maps()
    test_copy_and_reset()
    if failures == 0:
        print("SULEYN arenas v1.9: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN arenas v1.9: %d / %d checks FAILED." % [failures, checks])
        quit(1)


func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED arenas v1.9: " + label)


func test_catalog() -> void:
    check(Arena.keys() == ["open", "gates", "pillars"], "three stable arena choices")
    var keys: Array[String] = Arena.keys()
    keys.clear()
    check(Arena.keys().size() == 3, "catalog callers cannot mutate keys")
    for key in Arena.keys():
        check(not Arena.label(key).is_empty() and not Arena.description(key).is_empty(), "each arena has user-facing information " + key)
    check(Arena.label("missing").is_empty() and Arena.description("missing").is_empty(), "unknown arena has no invented metadata")
    check(not Arena.is_supported("missing", 9, 7), "unknown arena is unavailable")
    check(Arena.blocked_cells("missing", 9, 7).is_empty(), "unknown arena returns no generated geometry")


func test_layout(key: String, dimensions: Vector2i) -> void:
    var setup = Setup.new(dimensions.x, dimensions.y)
    var tag: String = "%s %s" % [key, dimensions]
    check(setup.set_arena(key) and setup.is_valid(), "layout supports intact draft " + tag)
    check(setup.arena_label() == Arena.label(key) and setup.arena_description() == Arena.description(key), "draft metadata matches selected arena " + tag)
    var board = Board.new(dimensions.x, dimensions.y)
    var cells: Array[Vector2i] = setup.blocked_cells()
    var unique: Dictionary = {}
    var valid_geometry: bool = true
    for cell in cells:
        valid_geometry = valid_geometry and board.contains(cell) and not unique.has(cell)
        valid_geometry = valid_geometry and not setup.cell_is_deployment("blue", cell) and not setup.cell_is_deployment("red", cell)
        valid_geometry = valid_geometry and setup.is_blocked(cell)
        unique[cell] = true
        board.set_blocked(cell, true)
    check(valid_geometry, "obstacles unique, in bounds and outside both deployment zones " + tag)
    var expected_count: int = 0 if key == "open" else (dimensions.y - 2 if key == "gates" else 4)
    check(cells.size() == expected_count, "expected obstacle count " + tag)
    var reachable: Dictionary = board.reachable_from(Vector2i.ZERO, dimensions.x * dimensions.y)
    check(reachable.size() == dimensions.x * dimensions.y - cells.size(), "all free cells connected without isolated pockets " + tag)
    var left: Vector2i = Vector2i(0, dimensions.y / 2)
    var right: Vector2i = Vector2i(dimensions.x - 1, dimensions.y / 2)
    var path: Array[Vector2i] = board.shortest_path(left, right)
    check(path.size() > 1 and path[0] == left and path[-1] == right, "opposite teams have a route " + tag)
    var legal_route: bool = true
    for index in range(path.size()):
        legal_route = legal_route and board.is_free(path[index])
        if index > 0:
            legal_route = legal_route and Hex.hex_distance(path[index - 1], path[index]) == 1
    check(legal_route, "BFS route takes adjacent free hexes " + tag)
    if key == "gates":
        check(path.size() - 1 > Hex.hex_distance(left, right), "central obstacle causes a real detour " + tag)
        var gate_count: int = 0
        for row in range(dimensions.y):
            if not board.blocked.has(Vector2i(dimensions.x / 2, row)):
                gate_count += 1
        check(gate_count == 2, "wall retains two independent gate hexes " + tag)
    var both_zones_free: bool = true
    for row in range(dimensions.y):
        for column in [0, 1]:
            both_zones_free = both_zones_free and setup.can_deploy("blue", Vector2i(column, row))
            both_zones_free = both_zones_free and setup.can_deploy("red", Vector2i(dimensions.x - 1 - column, row))
    check(both_zones_free, "all deployment hexes remain available " + tag)
    var all_placed: bool = true
    for unit_id in setup.unit_ids():
        all_placed = all_placed and board.add_unit(unit_id, setup.positions[unit_id])
    check(all_placed and board.unit_positions.size() == 6, "original six fighters fit after terrain application " + tag)
    cells.clear()
    check(setup.blocked_cells().size() == expected_count, "caller cannot mutate generated arena cells " + tag)
    if key != "open":
        var obstacle: Vector2i = setup.blocked_cells()[0]
        var positions_before: Dictionary = setup.positions.duplicate(true)
        check(not setup.can_deploy("blue", obstacle) and not setup.can_deploy("red", obstacle), "obstacles cannot be deployment cells " + tag)
        check(not setup.place_unit("ally_1", obstacle) and setup.positions == positions_before, "failed blocked placement leaves positions untouched " + tag)
        check(not board.move_unit("ally_1", obstacle), "runtime board rejects obstacle destination " + tag)
        setup.positions["ally_1"] = obstacle
        check(not setup.is_valid() and "; ".join(setup.validation_errors()).contains("препятствии"), "corrupt draft on obstacle has explicit validation error " + tag)


func test_small_and_invalid_maps() -> void:
    for dimensions in [Vector2i(4, 3), Vector2i(6, 7), Vector2i(9, 4)]:
        var setup = Setup.new(dimensions.x, dimensions.y)
        check(setup.is_valid() and setup.arena_key == "open", "small boards retain supported open default " + str(dimensions))
        for key in ["gates", "pillars", "missing"]:
            check(not setup.set_arena(key) and setup.arena_key == "open", "unsupported choice rejected without fallback mutation " + str(dimensions) + key)
        setup.arena_key = "gates"
        check(not setup.is_valid(), "direct unsupported arena assignment cannot pass validation " + str(dimensions))
        check(not setup.can_deploy("blue", Vector2i.ZERO), "unsupported draft cannot accept placement " + str(dimensions))
    for dimensions in [Vector2i(0, 7), Vector2i(9, 0), Vector2i(-1, -3), Vector2i(3, 3), Vector2i(4, 2)]:
        check(not Arena.is_supported("open", dimensions.x, dimensions.y), "raw invalid dimensions rejected " + str(dimensions))
        check(Arena.blocked_cells("gates", dimensions.x, dimensions.y).is_empty(), "invalid dimensions do not generate geometry " + str(dimensions))
    var broken = Setup.new()
    broken.arena_key = "missing"
    check(not broken.is_valid(), "unknown arena cannot start")
    check(not broken.set_arena("missing") and broken.arena_key == "missing", "invalid setter is transactional even on broken draft")
    var clone = broken.copy()
    check(clone.arena_key == "missing" and not clone.is_valid(), "copy cannot mask invalid arena")
    broken.arena_key = "gates"
    broken.columns = 3
    clone = broken.copy()
    check(clone.columns == 3 and clone.arena_key == "gates" and not clone.is_valid(), "copy cannot clamp away unsupported dimensions")


func test_copy_and_reset() -> void:
    var setup = Setup.new()
    setup.enemy_ai_enabled = false
    setup.set_profile("ally_1", "lich")
    setup.place_unit("ally_1", Vector2i.ZERO)
    var profiles_before: Dictionary = setup.profile_keys.duplicate(true)
    var positions_before: Dictionary = setup.positions.duplicate(true)
    check(setup.set_arena("gates"), "choose gates for edited roster")
    check(setup.profile_keys == profiles_before and setup.positions == positions_before and not setup.enemy_ai_enabled, "arena selection preserves all unrelated choices")
    var clone = setup.copy()
    check(clone.arena_key == "gates" and clone.is_valid(), "copy retains selected arena")
    clone.set_arena("pillars")
    clone.set_profile("ally_2", "lich")
    clone.place_unit("enemy_1", Vector2i(8, 0))
    check(setup.arena_key == "gates" and setup.profile_keys == profiles_before and setup.positions == positions_before, "draft edits never mutate original accepted state")
    setup.reset_positions()
    check(setup.arena_key == "gates" and setup.profile_keys == profiles_before and not setup.enemy_ai_enabled and setup.is_valid(), "reset positions retains arena and roster/AI")
    setup.reset_defaults()
    check(setup.arena_key == "open" and setup.blocked_cells().is_empty() and setup.enemy_ai_enabled and setup.profile_key("ally_1") == "male" and setup.is_valid(), "reset all restores complete open default")
