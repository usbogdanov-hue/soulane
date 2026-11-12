extends SceneTree
## Run: godot --headless --path . --script res://tests/test_turns.gd
const Turns = preload("res://scripts/battle_turns.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    var turns = Turns.new(["ally_1", "enemy_1"])
    check(turns.active_unit_id() == "ally_1", "ally starts")
    check(turns.round_number == 1, "round starts at 1")
    check(not turns.can_act("enemy_1"), "enemy cannot act outside turn")
    check(not turns.spend_action("enemy_1"), "enemy cannot spend ally action")
    check(turns.can_act("ally_1"), "ally can act")
    check(turns.spend_action("ally_1"), "ally action spent")
    check(not turns.can_act("ally_1"), "ally cannot act twice")
    check(not turns.spend_action("ally_1"), "action cannot be spent twice")
    check(not turns.next_turn("enemy_1"), "enemy cannot advance ally turn")
    check(turns.next_turn("ally_1"), "ally turn advances")
    check(turns.active_unit_id() == "enemy_1", "enemy becomes active")
    check(turns.can_act("enemy_1"), "enemy may act")
    check(turns.round_number == 1, "round is still 1")
    check(turns.next_turn("enemy_1"), "enemy may pass")
    check(turns.active_unit_id() == "ally_1", "ally active again")
    check(turns.round_number == 2, "round increments")
    check(turns.can_act("ally_1"), "ally action refreshed")
    var empty_turns = Turns.new([])
    check(empty_turns.active_unit_id() == "", "empty manager has no active unit")
    check(not empty_turns.next_turn("ally_1"), "empty manager cannot advance")
    if failures == 0:
        print("SULEYN Stage 2: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN Stage 2: %d of %d checks FAILED." % [failures, checks])
        quit(1)


func check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAILED: " + description)
