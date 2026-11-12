extends SceneTree
## Deterministic multi-unit queue checks, including deaths at round boundaries.
## Run: godot --headless --path . --script res://tests/test_turns_v15.gd
const Turns = preload("res://scripts/battle_turns.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    check_unique_slots()
    check_full_rounds()
    check_remove_future_and_previous()
    check_remove_active()
    check_round_boundary_deaths()
    if failures == 0:
        print("SULEYN v1.5 turn queue: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN v1.5 turn queue: %d / %d checks FAILED." % [failures, checks])
        quit(1)


func check_unique_slots() -> void:
    var supplied: Array[String] = ["", "blue_a", "red_a", "blue_a", "", "red_b"]
    var turns = Turns.new(supplied)
    check(turns.turn_order == ["blue_a", "red_a", "red_b"],
        "one slot per nonempty unit ID, in supplied order")
    supplied.clear()
    check(turns.active_unit_id() == "blue_a", "queue owns its data")
    var empty = Turns.new(["", ""])
    check(empty.active_unit_id().is_empty(), "all-empty IDs produce no active unit")
    check(not empty.can_act(""), "empty queue cannot act")
    check(not empty.next_turn(""), "empty queue cannot advance")
    check(not empty.remove_unit(""), "empty ID is never a queued unit")


func check_full_rounds() -> void:
    var turns = Turns.new(["blue_a", "red_a", "blue_b", "red_b", "red_c"])
    var observed: Array[String] = []
    for round_index in range(2):
        for expected in ["blue_a", "red_a", "blue_b", "red_b", "red_c"]:
            observed.append(turns.active_unit_id())
            check(turns.active_unit_id() == expected, "all living units retain supplied order")
            check(turns.round_number == round_index + 1, "round changes only after final slot")
            check(turns.spend_action(expected), "active unit has one action")
            check(not turns.can_act(expected), "spent action cannot be reused")
            check(not turns.spend_action(expected), "second action is rejected")
            check(not turns.next_turn("outsider"), "nonparticipant cannot advance queue")
            check(turns.next_turn(expected), "active unit completes its turn")
    check(observed == ["blue_a", "red_a", "blue_b", "red_b", "red_c",
        "blue_a", "red_a", "blue_b", "red_b", "red_c"], "two complete five-unit rounds")
    check(turns.round_number == 3 and turns.can_act("blue_a"), "new round resets first action")


func check_remove_future_and_previous() -> void:
    var turns = Turns.new(["blue_a", "red_a", "blue_b", "red_b", "red_c"])
    turns.spend_action("blue_a")
    check(turns.remove_unit("red_a"), "defeated upcoming unit removed")
    check(turns.active_unit_id() == "blue_a" and not turns.can_act("blue_a"),
        "future death preserves current actor and spent action")
    check(turns.round_number == 1, "future death does not advance round")
    turns.next_turn("blue_a")
    check(turns.active_unit_id() == "blue_b", "next turn skips defeated upcoming unit")
    turns.spend_action("blue_b")
    check(turns.remove_unit("blue_a"), "earlier slot can be removed")
    check(turns.active_unit_id() == "blue_b" and not turns.can_act("blue_b"),
        "earlier death preserves current actor and spent action")
    check(not turns.remove_unit("missing"), "unknown death is rejected")
    check(not turns.remove_unit("blue_a"), "repeated removal has no effect")
    turns.next_turn("blue_b")
    check(turns.active_unit_id() == "red_b" and turns.round_number == 1,
        "earlier removal does not skip next survivor")
    turns.next_turn("red_b")
    turns.next_turn("red_c")
    check(turns.active_unit_id() == "blue_b" and turns.round_number == 2,
        "next round begins with first surviving slot")


func check_remove_active() -> void:
    var turns = Turns.new(["a", "b", "c", "d"])
    turns.spend_action("a")
    check(turns.remove_unit("a"), "active first slot removed")
    check(turns.active_unit_id() == "b" and turns.can_act("b") and turns.round_number == 1,
        "successor of dead active first unit receives fresh action in same round")
    turns.next_turn("b")
    turns.spend_action("c")
    check(turns.remove_unit("c"), "active middle slot removed")
    check(turns.active_unit_id() == "d" and turns.can_act("d") and turns.round_number == 1,
        "successor of dead active middle unit receives fresh action")
    turns.spend_action("d")
    check(turns.remove_unit("d"), "active final slot removed")
    check(turns.active_unit_id() == "b" and turns.can_act("b") and turns.round_number == 2,
        "dead active final unit wraps exactly once")
    check(turns.remove_unit("b"), "final remaining unit removed")
    check(turns.active_unit_id().is_empty() and turns.turn_index == 0,
        "no active unit or stale index after final death")
    check(not turns.can_act("b") and not turns.spend_action("b") and not turns.next_turn("b"),
        "empty battle rejects actions and advancement")
    check(turns.round_number == 2, "final death does not invent another round")


func check_round_boundary_deaths() -> void:
    var turns = Turns.new(["a", "b", "c", "d"])
    turns.next_turn("a")
    turns.next_turn("b")
    check(turns.remove_unit("d"), "future final slot removed before its turn")
    check(turns.active_unit_id() == "c" and turns.round_number == 1,
        "removing future last slot keeps current round")
    turns.next_turn("c")
    check(turns.active_unit_id() == "a" and turns.round_number == 2,
        "last surviving slot ends the round")
    turns.next_turn("a")
    turns.next_turn("b")
    turns.spend_action("c")
    check(turns.remove_unit("a") and turns.remove_unit("b"), "remove both earlier slots")
    check(turns.active_unit_id() == "c" and not turns.can_act("c") and turns.round_number == 2,
        "deaths before current final slot neither reset action nor advance round")
    turns.next_turn("c")
    check(turns.active_unit_id() == "c" and turns.can_act("c") and turns.round_number == 3,
        "single survivor advances one round per own turn")


func check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAILED: " + description)
