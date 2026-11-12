extends SceneTree
## Behavioral integration tests for the playable multiunit demo.
## Run: godot --headless --path . --script res://tests/test_teams_v15.gd

const Demo = preload("res://scripts/battle_demo.gd")
const Board = preload("res://scripts/battle_board.gd")
const EXPECTED_ORDER: Array[String] = [
    "ally_1", "enemy_1", "ally_2", "enemy_2", "ally_3", "enemy_3"]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    test_setup_and_rounds()
    test_action_guards_and_movement()
    test_occupied_passage()
    test_mana_and_animation()
    test_magic_team_kill()
    test_team_victory("blue")
    test_team_victory("red")
    test_concussion_in_full_queue()
    test_reset_and_encounters()
    if failures == 0:
        print("SULEYN teams v1.5: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN teams v1.5: %d / %d checks FAILED." % [failures, checks])
        quit(1)


func check(ok: bool, description: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED teams v1.5: " + description)


func new_demo():
    var demo = Demo.new()
    demo.reset_demo()
    return demo


func finish_animation(demo) -> void:
    demo.animation_time = demo.ANIMATION_DURATION


func move_for_attack(demo, attacker_id: String, defender_id: String) -> void:
    # Arrange adjacent positions through the same occupancy-aware board API.
    check(demo.board.move_unit(attacker_id, Vector2i(3, 3)), "arrange attacker")
    check(demo.board.move_unit(defender_id, Vector2i(4, 3)), "arrange defender")


func pass_until(demo, wanted: String) -> void:
    for _attempt in range(12):
        if demo.battle_over or demo.turns.active_unit_id() == wanted:
            break
        finish_animation(demo)
        if demo.concussion_skip_pending:
            demo.resolve_one_concussion_skip()
        else:
            demo.pass_turn()
    check(demo.turns.active_unit_id() == wanted, "requested living actor gets a turn")


func test_setup_and_rounds() -> void:
    var demo = new_demo()
    check(demo.encounter_index == 4, "default is team battle")
    check(demo.units.size() == 6 and demo.board.unit_positions.size() == 6,
        "six units placed on six occupied hexes")
    check(demo.turns.turn_order == EXPECTED_ORDER, "stable interleaved team order")
    var blue: int = 0
    var red: int = 0
    var occupied_cells: Dictionary = {}
    for unit_id in demo.units:
        var unit = demo.units[unit_id]
        var cell: Vector2i = demo.board.position_of(unit_id)
        check(unit.id == unit_id and unit.is_alive(), "unique living runtime unit " + unit_id)
        check(demo.board.contains(cell) and not occupied_cells.has(cell),
            "in-bounds distinct placement " + unit_id)
        occupied_cells[cell] = true
        check(demo.board.unit_at(cell) == unit_id, "occupancy links back to " + unit_id)
        if unit.side == "blue":
            blue += 1
        elif unit.side == "red":
            red += 1
    check(blue == 3 and red == 3, "three combatants per side")
    check(demo.units["ally_2"].level == 25 and demo.units["ally_3"].is_monster,
        "blue has second commander and test monster")
    check(demo.units["enemy_1"].is_monster and demo.units["enemy_2"].is_monster
        and demo.units["enemy_3"].is_monster, "red uses three v1.4 monsters")
    for expected in EXPECTED_ORDER:
        check(demo.turns.active_unit_id() == expected and demo.turns.round_number == 1,
            "one opportunity per unit during round one: " + expected)
        demo.pass_turn()
    check(demo.turns.active_unit_id() == "ally_1" and demo.turns.round_number == 2,
        "round increments after all six slots")
    demo.free()


func test_action_guards_and_movement() -> void:
    var demo = new_demo()
    move_for_attack(demo, "ally_2", "enemy_1")
    var foe_hp: int = demo.units["enemy_1"].hp
    var friend_hp: int = demo.units["ally_1"].hp
    demo.attack_enemy("ally_2", "enemy_1", 99.0, 99.0)
    check(demo.units["enemy_1"].hp == foe_hp and demo.turns.active_unit_id() == "ally_1",
        "inactive ally cannot attack even while adjacent")
    check(demo.board.move_unit("ally_1", Vector2i(3, 2)), "active ally beside friendly unit")
    demo.attack_enemy("ally_1", "ally_2", 99.0, 99.0)
    check(demo.units["ally_1"].hp == friend_hp and demo.units["ally_2"].hp == demo.units["ally_2"].max_hp,
        "friendly fire cannot damage either ally")
    check(demo.turns.active_unit_id() == "ally_1", "invalid friendly attack preserves action")
    demo.click_cell(demo.board.position_of("ally_1"))
    check(demo.selected_unit_id == "ally_1", "active unit can be selected")
    for cell in demo.reachable:
        check(demo.board.unit_at(cell).is_empty() or demo.board.unit_at(cell) == "ally_1",
            "movement never includes another occupied cell")
    var friend_cell: Vector2i = demo.board.position_of("ally_2")
    demo.click_cell(friend_cell)
    check(demo.board.position_of("ally_1") == Vector2i(3, 2)
        and demo.turns.active_unit_id() == "ally_1", "clicking ally cannot move or spend action")
    var destination: Vector2i = Vector2i(2, 2)
    demo.click_cell(destination)
    check(demo.board.position_of("ally_1") == destination, "valid empty-hex movement succeeds")
    check(demo.turns.active_unit_id() == "enemy_1", "movement consumes entire turn")
    var old_position: Vector2i = demo.board.position_of("ally_1")
    demo.click_cell(old_position)
    demo.click_cell(Vector2i(2, 1))
    check(demo.board.position_of("ally_1") == old_position,
        "previous actor cannot move again during another unit's turn")
    demo.free()


func test_mana_and_animation() -> void:
    var demo = new_demo()
    move_for_attack(demo, "ally_1", "enemy_1")
    var man = demo.units["ally_1"]
    var foe = demo.units["enemy_1"]
    man.mp = 29
    demo.special_mode = true
    var foe_hp: int = foe.hp
    demo.attack_enemy("ally_1", "enemy_1", 99.0, 99.0, 99.0)
    check(man.mp == 29 and foe.hp == foe_hp and demo.turns.active_unit_id() == "ally_1",
        "failed insufficient-MP attack changes neither resources nor turn")
    man.mp = man.max_mp
    var initial_mp: int = man.mp
    demo.attack_enemy("ally_1", "enemy_1", 0.0, 99.0, 99.0)
    var expected_regen: int = int(floor(float(man.max_mp) * man.mana_regen_pct / 100.0 + 0.000001))
    check(foe.hp == foe_hp, "injected dodge prevents special damage")
    check(man.mp == initial_mp - 30 + expected_regen,
        "dodged special spends MP and regenerates exactly once")
    check(demo.turns.active_unit_id() == "enemy_1", "dodge still consumes attacking turn")
    var active_before: String = demo.turns.active_unit_id()
    var man_hp: int = man.hp
    demo.special_mode = false
    demo.attack_enemy("enemy_1", "ally_1", 99.0, 99.0)
    demo.pass_turn()
    check(demo.turns.active_unit_id() == active_before and man.hp == man_hp,
        "attack animation prevents next actor attacking or passing early")
    finish_animation(demo)
    demo.pass_turn()
    check(demo.turns.active_unit_id() == "ally_2", "input resumes after animation")
    demo.free()


func test_occupied_passage() -> void:
    var demo = new_demo()
    # A one-hex-wide passage makes walking through an occupant observable,
    # rather than permitting BFS to find an alternate route around it.
    demo.board = Board.new(6, 1)
    demo.board.add_unit("ally_1", Vector2i(0, 0))
    demo.board.add_unit("ally_2", Vector2i(1, 0))
    demo.board.add_unit("enemy_1", Vector2i(5, 0))
    demo.units["ally_1"].movement = 5
    demo.click_cell(Vector2i(0, 0))
    check(not demo.reachable.has(Vector2i(1, 0)) and not demo.reachable.has(Vector2i(2, 0)),
        "friendly occupant blocks entry and movement through narrow passage")
    demo.click_cell(Vector2i(2, 0))
    check(demo.board.position_of("ally_1") == Vector2i(0, 0)
        and demo.turns.active_unit_id() == "ally_1", "unreachable destination does not spend turn")
    demo.board.move_unit("ally_2", Vector2i(4, 0))
    demo.board.move_unit("enemy_1", Vector2i(1, 0))
    demo.refresh_reachable()
    check(not demo.reachable.has(Vector2i(2, 0)), "hostile occupant also blocks traversal")
    demo.free()


func test_magic_team_kill() -> void:
    var demo = new_demo()
    move_for_attack(demo, "ally_1", "enemy_2")
    demo.units["enemy_2"].hp = 1
    var attacker = demo.units["ally_1"]
    var mp_before: int = attacker.mp
    var expected_regen: int = int(floor(float(attacker.max_mp) * attacker.mana_regen_pct / 100.0 + 0.000001))
    demo.casting_mode = true
    demo.attack_enemy("ally_1", "enemy_2")
    check(not demo.units["enemy_2"].is_alive() and not demo.turns.turn_order.has("enemy_2"),
        "magic kill removes a later enemy from team queue")
    check(demo.board.is_free(Vector2i(4, 3)), "magic defeat frees target hex")
    check(not demo.battle_over and demo.turns.active_unit_id() == "enemy_1"
        and demo.turns.round_number == 1, "magic kill preserves next survivor and current round")
    check(attacker.mp == mini(attacker.max_mp, mp_before - attacker.spell_mana_cost + expected_regen),
        "magic kill spends spell cost and regenerates once")
    demo.free()


func test_team_victory(winning_side: String) -> void:
    var demo = new_demo()
    var attacker_id: String = "ally_1" if winning_side == "blue" else "enemy_1"
    var targets: Array[String] = ["enemy_1", "enemy_2", "enemy_3"]
    if winning_side == "red":
        targets.assign(["ally_1", "ally_2", "ally_3"])
    for index in range(targets.size()):
        var defender_id: String = targets[index]
        pass_until(demo, attacker_id)
        move_for_attack(demo, attacker_id, defender_id)
        demo.units[defender_id].hp = 1
        var defender_cell: Vector2i = demo.board.position_of(defender_id)
        demo.attack_enemy(attacker_id, defender_id, 99.0, 99.0)
        check(not demo.units[defender_id].is_alive(), "lethal attack defeats " + defender_id)
        check(demo.board.is_free(defender_cell) and not demo.board.unit_positions.has(defender_id),
            "defeat releases occupied hex " + defender_id)
        check(not demo.turns.turn_order.has(defender_id), "defeated unit removed from queue " + defender_id)
        if index < targets.size() - 1:
            check(not demo.battle_over and demo.winner_side.is_empty(),
                "remaining teammate prevents premature victory")
            check(demo.turns.active_unit_id() != attacker_id,
                "nonfinal kill advances to a surviving unit")
        else:
            check(demo.battle_over and demo.winner_side == winning_side,
                "last opponent defeat awards victory to entire " + winning_side + " team")
    var final_round: int = demo.turns.round_number
    var final_active: String = demo.turns.active_unit_id()
    var final_mp: int = demo.units[attacker_id].mp
    var final_position: Vector2i = demo.board.position_of(attacker_id)
    finish_animation(demo)
    demo.pass_turn()
    demo.click_cell(final_position)
    demo.click_cell(Vector2i(2, 3))
    demo.attack_enemy(attacker_id, targets[0], 99.0, 99.0)
    demo.debug_spend_mana()
    check(demo.turns.round_number == final_round and demo.turns.active_unit_id() == final_active,
        "victory blocks all further turn advancement")
    check(demo.units[attacker_id].mp == final_mp and demo.board.position_of(attacker_id) == final_position,
        "victory blocks resource changes and movement")
    demo.reset_demo()
    check(not demo.battle_over and demo.winner_side.is_empty() and demo.turns.round_number == 1,
        "restart clears team victory state")
    check(demo.turns.turn_order == EXPECTED_ORDER and demo.board.unit_positions.size() == 6,
        "restart restores fallen units and queue")
    demo.free()


func test_concussion_in_full_queue() -> void:
    var demo = new_demo()
    demo.create_journal()
    move_for_attack(demo, "ally_1", "enemy_1")
    demo.special_mode = true
    demo.attack_enemy("ally_1", "enemy_1", 99.0, 99.0, 0.0)
    var target = demo.units["enemy_1"]
    check(target.concussion_turns_remaining == 2 and demo.concussion_skip_pending,
        "real special schedules both upcoming own-turn skips")
    check(demo.turns.active_unit_id() == "enemy_1", "stunned unit retains visible turn opportunity")
    demo.pass_turn()
    check(target.concussion_turns_remaining == 2 and demo.turns.active_unit_id() == "enemy_1",
        "ordinary pass cannot bypass scheduled concussion")
    finish_animation(demo)
    demo.resolve_one_concussion_skip()
    check(target.concussion_turns_remaining == 1 and demo.turns.active_unit_id() == "ally_2",
        "first skip consumes one own opportunity and advances")
    for expected in ["ally_2", "enemy_2", "ally_3", "enemy_3", "ally_1"]:
        check(demo.turns.active_unit_id() == expected, "other unit keeps turn between skips: " + expected)
        check(target.concussion_turns_remaining == 1, "other unit turn does not decrement concussion")
        demo.pass_turn()
    check(demo.turns.round_number == 2 and demo.turns.active_unit_id() == "enemy_1"
        and demo.concussion_skip_pending, "second skip waits until next round own turn")
    demo.resolve_one_concussion_skip()
    check(target.concussion_turns_remaining == 0 and demo.turns.active_unit_id() == "ally_2",
        "second skip exhausts concussion")
    pass_until(demo, "enemy_1")
    check(not demo.concussion_skip_pending and demo.turns.can_act("enemy_1"),
        "third own turn is actionable")
    var log_text: String = demo.journal.get_parsed_text()
    check(log_text.contains("ПРОПУСК 1 из 2") and log_text.contains("ПРОПУСК 2 из 2"),
        "combat journal records each individual concussion skip")
    demo.free()


func test_reset_and_encounters() -> void:
    var demo = new_demo()
    for expected in range(5):
        demo.switch_encounter()
        check(demo.encounter_index == expected, "T advances and wraps scenario " + str(expected))
        var expected_count: int = 6 if expected == 4 else 2
        check(demo.units.size() == expected_count and demo.turns.turn_order.size() == expected_count,
            "switch rebuilds matching roster and queue")
        check(demo.turns.active_unit_id() == "ally_1" and demo.turns.round_number == 1,
            "switch restarts at first actor and first round")
        if expected < 4:
            check(demo.units["enemy_1"].is_monster == (expected > 0),
                "original duel and three monster encounters remain available")
        demo.casting_mode = true
        demo.special_mode = true
        demo.selected_unit_id = "ally_1"
        demo.units["ally_1"].apply_concussion(2)
        demo.reset_demo()
        check(not demo.casting_mode and not demo.special_mode and demo.selected_unit_id.is_empty(),
            "reset clears selection and attack modes")
        check(demo.units["ally_1"].concussion_turns_remaining == 0 and not demo.concussion_skip_pending,
            "reset clears status scheduling")
    demo.demo_columns = 4
    demo.demo_rows = 3
    demo.reset_demo()
    check(demo.units.size() == 6 and demo.board.unit_positions.size() == 6,
        "team placement supports minimum exported board dimensions")
    for unit_id in demo.units:
        check(demo.board.contains(demo.board.position_of(unit_id)), "minimum board contains " + unit_id)
    demo.free()
