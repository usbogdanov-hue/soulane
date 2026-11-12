extends SceneTree
## Run: godot --headless --path . --script res://tests/test_board.gd

const Hex = preload("res://scripts/hex_math.gd")
const Board = preload("res://scripts/battle_board.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    test_geometry()
    test_occupancy()
    test_paths()
    if failures == 0:
        print("SULEYN Stage 1: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN Stage 1: %d failures of %d checks." % [failures, checks])
        quit(1)


func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED: " + message)


func test_geometry() -> void:
    for q in range(-3, 10):
        for r in range(-3, 10):
            var cell := Vector2i(q, r)
            check(Hex.pixel_to_axial(Hex.axial_to_pixel(cell, 35.0), 35.0) == cell,
                "roundtrip %s" % cell)
    var origin := Vector2i(2, 2)
    for direction in Hex.DIRECTIONS:
        check(Hex.hex_distance(origin, origin + direction) == 1,
            "adjacent hex distance equals 1")
    check(Hex.point_in_hex(Vector2.ZERO, Vector2.ZERO, 35.0), "inside center")
    check(not Hex.point_in_hex(Vector2(50, 50), Vector2.ZERO, 35.0), "outside radius")


func test_occupancy() -> void:
    var board = Board.new(5, 5)
    check(board.add_unit("ally", Vector2i(1, 2)), "add ally")
    check(board.add_unit("enemy", Vector2i(3, 2)), "add enemy")
    check(not board.add_unit("clone", Vector2i(1, 2)), "reject occupied hex")
    check(not board.set_blocked(Vector2i(1, 2), true), "reject blocking occupied hex")
    check(board.set_blocked(Vector2i(2, 2), true), "set terrain blocker")
    check(not board.move_unit("ally", Vector2i(2, 2)), "blocked destination")
    check(not board.move_unit("ally", Vector2i(3, 2)), "enemy destination")
    check(not board.move_unit("missing", Vector2i(1, 1)), "unknown unit")
    check(board.move_unit("ally", Vector2i(1, 3)), "move valid")
    check(board.unit_at(Vector2i(1, 2)).is_empty(), "old position vacated")
    check(board.unit_at(Vector2i(1, 3)) == "ally", "new position occupied")


func test_paths() -> void:
    var board = Board.new(5, 5)
    board.add_unit("ally", Vector2i(0, 2))
    board.add_unit("enemy", Vector2i(2, 2))
    var reachable: Dictionary = board.reachable_from(Vector2i(0, 2), 2, "ally")
    check(reachable[Vector2i(0, 2)] == 0, "start cost is zero")
    check(reachable.has(Vector2i(1, 2)), "neighbor is reachable")
    check(not reachable.has(Vector2i(2, 2)), "enemy hex is not reachable")
    check(not reachable.has(Vector2i(4, 2)), "beyond move range")
    var path: Array[Vector2i] = board.shortest_path(Vector2i(0, 2), Vector2i(3, 2), "ally")
    check(path.size() > 0, "detour exists")
    check(path[0] == Vector2i(0, 2), "path begins at ally")
    check(path[path.size() - 1] == Vector2i(3, 2), "path ends at target")
    for cell in path:
        check(cell != Vector2i(2, 2), "path avoids occupied enemy cell")
    check(board.shortest_path(Vector2i(0, 2), Vector2i(2, 2), "ally").is_empty(),
        "no path onto occupied enemy cell")
