extends SceneTree
## Run: godot --headless --path . --script res://tests/test_combat.gd

const Hex = preload("res://scripts/hex_math.gd")
const Board = preload("res://scripts/battle_board.gd")
const Unit = preload("res://scripts/battle_unit.gd")
const Combat = preload("res://scripts/battle_combat.gd")
const Turns = preload("res://scripts/battle_turns.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    test_damage()
    test_range_and_allies()
    test_death_and_occupancy()
    test_turn_removal()
    if failures == 0:
        print("SULEYN Stage 3: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN Stage 3: %d failures of %d checks." % [failures, checks])
        quit(1)


func check(ok: bool, description: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED: " + description)


func test_damage() -> void:
    var unit = Unit.new("test", "blue", 20, 5)
    check(unit.hp == 20, "HP starts full")
    check(unit.receive_damage(-8) == 0, "negative damage cannot heal")
    check(unit.receive_damage(7) == 7, "damage applied")
    check(unit.hp == 13, "HP lowered")
    check(unit.receive_damage(100) == 13, "overkill capped at remaining HP")
    check(unit.hp == 0 and not unit.is_alive(), "HP zero means defeated")
    check(unit.receive_damage(1) == 0, "dead unit ignores damage")


func test_range_and_allies() -> void:
    var board = Board.new(6, 6)
    board.add_unit("A", Vector2i(1, 1))
    board.add_unit("E", Vector2i(3, 1))
    board.add_unit("B", Vector2i(1, 2))
    var units: Dictionary = {
        "A": Unit.new("A", "blue", 20, 5),
        "E": Unit.new("E", "red", 20, 5),
        "B": Unit.new("B", "blue", 20, 5),
    }
    check(not Combat.can_melee(board, units, "A", "E"), "cannot attack at range 2")
    check(not Combat.can_melee(board, units, "A", "B"), "cannot attack ally")
    check(not Combat.can_melee(board, units, "A", "A"), "cannot attack self")
    check(not Combat.can_melee(board, units, "missing", "E"), "unknown attacker rejected")
    check(not Combat.melee_attack(board, units, "A", "E", 99.0, 99.0)["ok"], "out-of-range hit rejected")
    check(units["E"].hp == 20, "invalid attack deals zero damage")
    check(board.move_unit("E", Vector2i(2, 1)), "enemy moved into adjacency")
    check(Hex.hex_distance(board.position_of("A"), board.position_of("E")) == 1, "hex neighbor")
    check(Combat.can_melee(board, units, "A", "E"), "adjacent enemy can be attacked")
    var result: Dictionary = Combat.melee_attack(board, units, "A", "E", 99.0, 99.0)
    check(result["ok"] and result["damage"] == 5, "physical demo hit applies 5 damage")
    check(result["remaining_hp"] == 15 and not result["defeated"], "enemy survives hit")


func test_death_and_occupancy() -> void:
    var board = Board.new(4, 4)
    board.add_unit("A", Vector2i(1, 1))
    board.add_unit("E", Vector2i(2, 1))
    var units: Dictionary = {
        "A": Unit.new("A", "blue", 10, 5),
        "E": Unit.new("E", "red", 5, 5),
    }
    var result: Dictionary = Combat.melee_attack(board, units, "A", "E", 99.0, 99.0)
    check(result["ok"] and result["defeated"], "lethal strike defeats target")
    check(units["E"].hp == 0, "target HP is zero")
    check(board.unit_at(Vector2i(2, 1)).is_empty(), "dead enemy frees hex")
    check(not board.unit_positions.has("E"), "dead unit removed from board")
    check(not Combat.can_melee(board, units, "A", "E"), "cannot hit defeated enemy")
    check(board.move_unit("A", Vector2i(2, 1)), "freed hex can be occupied")
    check(not board.remove_unit("E"), "cannot remove removed unit twice")


func test_turn_removal() -> void:
    var turns = Turns.new(["A", "E"])
    check(turns.remove_unit("E"), "remove defeated enemy from queue")
    check(turns.active_unit_id() == "A", "attacker remains active")
    check(turns.next_turn("A"), "one surviving unit can advance round")
    check(turns.round_number == 2, "round advances with one participant")
    check(not turns.remove_unit("E"), "no duplicate removal")
    check(turns.remove_unit("A"), "remove final unit")
    check(turns.active_unit_id().is_empty(), "empty turn queue")
    var another = Turns.new(["A", "E", "B"])
    another.next_turn("A")
    another.spend_action("E")
    check(another.remove_unit("A"), "remove unit before active index")
    check(another.active_unit_id() == "E", "current active preserved")
    check(not another.can_act("E"), "removal of earlier participant does not refund action")
