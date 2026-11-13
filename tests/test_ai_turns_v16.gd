extends SceneTree
## Behavior of the v1.6 red-team controller through the real demo lifecycle.
## Run: godot --headless --path . --script res://tests/test_ai_turns_v16.gd

const Demo = preload("res://scripts/battle_demo.gd")
const Board = preload("res://scripts/battle_board.gd")
const Turns = preload("res://scripts/battle_turns.gd")
const Hex = preload("res://scripts/hex_math.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    test_ownership_and_manual_duels()
    test_delayed_movement_and_one_action()
    test_red_input_and_manual_toggle()
    test_physical_attack_consumes_one_turn()
    test_magic_execution_and_mode_restoration()
    test_no_path_passes_and_regenerates()
    test_animation_and_frame_boundaries()
    test_concussion_two_own_turns()
    test_concussion_frame_boundary()
    test_reset_and_switch_clear_old_wait()
    test_victory_stops_ai()
    test_consecutive_ai_turns()
    test_blue_victory_stops_ai()
    if failures == 0:
        print("SULEYN AI turns v1.6: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN AI turns v1.6: %d / %d checks FAILED." % [failures, checks])
        quit(1)


func check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAILED AI turns v1.6: " + description)


func new_demo():
    var demo = Demo.new()
    demo.reset_demo()
    return demo


func small_demo(red_id: String = "enemy_1"):
    var demo = new_demo()
    for unit_id in demo.units.keys():
        if unit_id != "ally_1" and unit_id != red_id:
            demo.units.erase(unit_id)
    demo.roster_order.assign(["ally_1", red_id])
    demo.turns = Turns.new(["ally_1", red_id])
    demo.board = Board.new(7, 5)
    check(demo.board.add_unit("ally_1", Vector2i(1, 2)), "place small-fixture blue")
    check(demo.board.add_unit(red_id, Vector2i(5, 2)), "place small-fixture red")
    return demo


func finish_animation(demo) -> void:
    demo.animation_time = demo.ANIMATION_DURATION


func ready_ai(demo) -> void:
    # A zero-time call establishes the current turn without spending think time.
    demo.update_ai(0.0)


func let_ai_act(demo) -> void:
    ready_ai(demo)
    demo.update_ai(demo.AI_THINK_SECONDS + 0.01)


func test_ownership_and_manual_duels() -> void:
    var demo = new_demo()
    check(demo.enemy_ai_enabled, "red AI is enabled by default")
    check(not demo.is_ai_turn() and not demo.ai_controls_unit("ally_1"), "blue starts under manual control")
    check(demo.ai_controls_unit("enemy_1") and demo.ai_controls_unit("enemy_2")
        and demo.ai_controls_unit("enemy_3"), "all three red combatants are AI controlled")
    check(not demo.ai_controls_unit("missing"), "unknown unit is not AI controlled")
    var initial: Vector2i = demo.board.position_of("enemy_1")
    demo.update_ai(100.0)
    demo.perform_ai_turn()
    check(demo.turns.active_unit_id() == "ally_1" and demo.board.position_of("enemy_1") == initial,
        "AI cannot spend a blue turn, even with a large elapsed interval")
    for encounter in range(4):
        demo.encounter_index = encounter
        demo.reset_demo()
        check(demo.enemy_ai_enabled and not demo.ai_controls_unit("enemy_1"),
            "legacy duel remains manual with AI preference enabled: " + str(encounter))
        demo.pass_turn()
        check(demo.turns.active_unit_id() == "enemy_1" and not demo.is_ai_turn(),
            "legacy red opportunity is manual: " + str(encounter))
        var old_position: Vector2i = demo.board.position_of("enemy_1")
        demo.update_ai(10.0)
        check(demo.board.position_of("enemy_1") == old_position and demo.turns.active_unit_id() == "enemy_1",
            "AI scheduler does nothing in legacy duel: " + str(encounter))
        demo.toggle_enemy_ai()
        check(demo.enemy_ai_enabled, "A does not change AI preference in manual duels")
        demo.pass_turn()
        check(demo.turns.active_unit_id() == "ally_1", "legacy red can still pass manually")
    demo.free()


func test_delayed_movement_and_one_action() -> void:
    var demo = small_demo()
    demo.pass_turn()
    check(demo.is_ai_turn() and demo.turns.active_unit_id() == "enemy_1", "manual blue pass schedules red")
    var initial: Vector2i = demo.board.position_of("enemy_1")
    var blue_hp: int = demo.units["ally_1"].hp
    ready_ai(demo)
    demo.update_ai(demo.AI_THINK_SECONDS - 0.01)
    check(demo.board.position_of("enemy_1") == initial and demo.is_ai_turn(),
        "red waits through its visible thinking pause")
    demo.update_ai(0.02)
    var destination: Vector2i = demo.board.position_of("enemy_1")
    var path: Array[Vector2i] = demo.board.shortest_path(destination, initial, "enemy_1")
    check(destination != initial and demo.board.contains(destination), "red moves when no enemy is in range")
    check(Hex.hex_distance(initial, destination) <= demo.units["enemy_1"].movement,
        "AI move stays within the existing movement allowance")
    check(demo.turns.active_unit_id() == "ally_1" and demo.turns.round_number == 2,
        "one AI move finishes one turn and wraps the two-unit round")
    check(demo.units["ally_1"].hp == blue_hp, "AI cannot attack after moving on the same turn")
    demo.update_ai(100.0)
    demo.perform_ai_turn()
    check(demo.turns.active_unit_id() == "ally_1" and demo.board.position_of("enemy_1") == destination,
        "large delta or repeated execution cannot act during following blue turn")
    check(not path.is_empty(), "AI destination retains a traversable path back to its start")
    demo.free()


func test_red_input_and_manual_toggle() -> void:
    var demo = small_demo()
    check(demo.board.move_unit("enemy_1", Vector2i(2, 2)), "place red adjacent for input guards")
    demo.pass_turn()
    var red = demo.units["enemy_1"]
    red.max_mp = 40
    red.mp = 30
    var old_red_cell: Vector2i = demo.board.position_of("enemy_1")
    var old_blue_hp: int = demo.units["ally_1"].hp
    demo.click_cell(old_red_cell)
    check(demo.inspected_unit_id == "enemy_1", "red remains inspectable during its automated turn")
    demo.click_cell(demo.board.position_of("ally_1"))
    check(demo.inspected_unit_id == "ally_1", "blue remains inspectable during a red AI turn")
    demo.click_cell(Vector2i(3, 2))
    demo.attack_enemy("enemy_1", "ally_1", 99.0, 99.0)
    demo.pass_turn()
    demo.debug_spend_mana()
    check(demo.turns.active_unit_id() == "enemy_1" and demo.board.position_of("enemy_1") == old_red_cell,
        "manual movement and pass cannot consume an AI turn")
    check(demo.units["ally_1"].hp == old_blue_hp and red.mp == 30,
        "manual attack and debug mana command cannot change resources during an AI turn")
    for key in [KEY_1, KEY_2, KEY_F]:
        var event := InputEventKey.new()
        event.pressed = true
        event.keycode = key
        var old_magic: bool = demo.casting_mode
        var old_special: bool = demo.special_mode
        demo._unhandled_input(event)
        check(demo.casting_mode == old_magic and demo.special_mode == old_special,
            "manual mode key ignored during AI turn: " + str(key))
    ready_ai(demo)
    demo.update_ai(demo.AI_THINK_SECONDS * 0.75)
    demo.toggle_enemy_ai()
    check(not demo.enemy_ai_enabled and not demo.is_ai_turn(), "toggle returns red control to user without restarting")
    check(demo.turns.active_unit_id() == "enemy_1" and red.mp == 30,
        "toggle preserves active turn and unit resources")
    demo.pass_turn()
    check(demo.turns.active_unit_id() == "ally_1", "manual red pass works after disabling AI")
    demo.toggle_enemy_ai()
    demo.pass_turn()
    ready_ai(demo)
    demo.update_ai(demo.AI_THINK_SECONDS * 0.5)
    check(demo.turns.active_unit_id() == "enemy_1", "reenabled AI does not inherit the old partial wait")
    demo.free()


func test_physical_attack_consumes_one_turn() -> void:
    var demo = small_demo()
    check(demo.board.move_unit("enemy_1", Vector2i(2, 2)), "place adjacent physical AI attacker")
    demo.create_journal()
    demo.pass_turn()
    var position_before: Vector2i = demo.board.position_of("enemy_1")
    var hp_before: int = demo.units["ally_1"].hp
    demo.perform_ai_turn()
    check(demo.turns.active_unit_id() == "ally_1", "physical attempt completes red turn even on random evade")
    check(demo.board.position_of("enemy_1") == position_before, "adjacent physical AI attacks without moving")
    check(demo.units["ally_1"].hp <= hp_before and demo.units["ally_1"].is_alive(),
        "physical AI uses normal bounded combat damage")
    check(demo.animation_time == 0.0 and demo.animation_attacker == "enemy_1"
        and demo.animation_defender == "ally_1", "physical AI passes through existing attack animation")
    check(demo.journal.get_parsed_text().contains("→"), "AI attack is recorded in the normal battle journal")
    var hp_after: int = demo.units["ally_1"].hp
    demo.perform_ai_turn()
    check(demo.units["ally_1"].hp == hp_after, "physical AI cannot take a second action")
    demo.free()


func test_magic_execution_and_mode_restoration() -> void:
    var demo = small_demo("enemy_3")
    check(demo.board.move_unit("enemy_3", Vector2i(2, 2)), "place adjacent magic AI attacker")
    var lich = demo.units["enemy_3"]
    lich.spell_power = 300
    lich.melee_skill_power = 1
    lich.magic_power_pct = 0.0
    lich.mana_regen_pct = 0.0
    lich.mp = lich.max_mp
    var old_mp: int = lich.mp
    var hp_before: int = demo.units["ally_1"].hp
    # Preserve a user's special mode across an AI-selected spell.
    demo.casting_mode = false
    demo.special_mode = true
    demo.pass_turn()
    demo.perform_ai_turn()
    check(lich.mp == old_mp - lich.spell_mana_cost, "Lich spends the actual spell mana cost")
    check(demo.units["ally_1"].hp < hp_before and not demo.animation_crit and not demo.animation_evaded,
        "selected magic uses normal noncritical, nonevading combat path")
    check(not demo.casting_mode and demo.special_mode,
        "AI spell execution restores the user's previous attack mode")
    check(demo.turns.active_unit_id() == "ally_1", "magic completes exactly one red turn")
    demo.free()


func test_no_path_passes_and_regenerates() -> void:
    var demo = small_demo()
    var red = demo.units["enemy_1"]
    red.movement = 0
    red.max_mp = 20
    red.mp = 10
    red.mana_regen_pct = 10.0
    var initial: Vector2i = demo.board.position_of("enemy_1")
    demo.pass_turn()
    demo.perform_ai_turn()
    check(demo.turns.active_unit_id() == "ally_1" and demo.board.position_of("enemy_1") == initial,
        "no movement and no target causes one normal pass")
    check(red.mp == 12, "AI pass regenerates mana exactly once")
    demo.perform_ai_turn()
    check(red.mp == 12, "repeated executor cannot regenerate outside its turn")
    demo.free()


func test_animation_and_frame_boundaries() -> void:
    var demo = small_demo()
    check(demo.board.move_unit("enemy_1", Vector2i(2, 2)), "place red beside blue for animation test")
    demo.attack_enemy("ally_1", "enemy_1", 99.0, 99.0)
    check(demo.turns.active_unit_id() == "enemy_1" and demo.animation_time == 0.0,
        "blue hit advances red while animation is still visible")
    var red_cell: Vector2i = demo.board.position_of("enemy_1")
    var blue_hp: int = demo.units["ally_1"].hp
    demo.update_ai(100.0)
    demo.perform_ai_turn()
    check(demo.turns.active_unit_id() == "enemy_1" and demo.units["ally_1"].hp == blue_hp,
        "scheduler and direct executor both wait for attack animation")
    demo._process(demo.ANIMATION_DURATION + demo.AI_THINK_SECONDS + 1.0)
    check(demo.turns.active_unit_id() == "enemy_1" and demo.board.position_of("enemy_1") == red_cell,
        "frame finishing hit animation cannot also execute red AI")
    ready_ai(demo)
    demo.update_ai(demo.AI_THINK_SECONDS - 0.01)
    check(demo.turns.active_unit_id() == "enemy_1", "thinking starts after animation, not during it")
    demo.update_ai(0.02)
    check(demo.turns.active_unit_id() == "ally_1", "AI responds after its entire postanimation pause")
    demo.free()


func test_concussion_two_own_turns() -> void:
    var demo = small_demo()
    demo.create_journal()
    var red = demo.units["enemy_1"]
    red.apply_concussion(2)
    red.max_mp = 20
    red.mp = 10
    red.mana_regen_pct = 10.0
    var initial: Vector2i = demo.board.position_of("enemy_1")
    for skip_number in range(1, 3):
        demo.pass_turn()
        check(demo.turns.active_unit_id() == "enemy_1" and demo.concussion_skip_pending,
            "stunned AI owns its visible skip opportunity " + str(skip_number))
        var remaining_before: int = red.concussion_turns_remaining
        demo.update_ai(100.0)
        demo.perform_ai_turn()
        check(red.concussion_turns_remaining == remaining_before and demo.turns.active_unit_id() == "enemy_1",
            "AI cannot replace the scheduled concussion skip with an action")
        demo._process(demo.CONCUSSION_PREVIEW_SECONDS + 0.01)
        check(red.concussion_turns_remaining == 2 - skip_number and demo.turns.active_unit_id() == "ally_1",
            "one own turn consumes one concussion skip")
        check(red.mp == 10 + 2 * skip_number and demo.board.position_of("enemy_1") == initial,
            "concussion skip regenerates once without AI movement")
        demo.update_ai(10.0)
        check(red.concussion_turns_remaining == 2 - skip_number,
            "blue turn cannot decrement red concussion")
    demo.pass_turn()
    check(not demo.concussion_skip_pending and demo.is_ai_turn(), "third own opportunity is actionable AI turn")
    let_ai_act(demo)
    check(demo.turns.active_unit_id() == "ally_1" and demo.board.position_of("enemy_1") != initial,
        "AI acts after exactly two own skips")
    var text: String = demo.journal.get_parsed_text()
    check(text.contains("ПРОПУСК 1 из 2") and text.contains("ПРОПУСК 2 из 2"),
        "both numbered skips remain visible in the normal journal")
    demo.free()


func test_concussion_frame_boundary() -> void:
    var demo = new_demo()
    # Keep a third combatant so a skipped red turn is followed by another AI turn.
    for unit_id in demo.units.keys():
        if unit_id not in ["ally_1", "enemy_1", "enemy_2"]:
            demo.units.erase(unit_id)
    demo.roster_order.assign(["ally_1", "enemy_1", "enemy_2"])
    demo.turns = Turns.new(["ally_1", "enemy_1", "enemy_2"])
    demo.board = Board.new(7, 5)
    demo.board.add_unit("ally_1", Vector2i(0, 2))
    demo.board.add_unit("enemy_1", Vector2i(5, 1))
    demo.board.add_unit("enemy_2", Vector2i(5, 3))
    demo.units["enemy_1"].apply_concussion(2)
    demo.pass_turn()
    var next_red_cell: Vector2i = demo.board.position_of("enemy_2")
    demo._process(demo.CONCUSSION_PREVIEW_SECONDS + demo.AI_THINK_SECONDS + 1.0)
    check(demo.turns.active_unit_id() == "enemy_2" and demo.board.position_of("enemy_2") == next_red_cell,
        "frame resolving concussion cannot also spend following AI unit's turn")
    let_ai_act(demo)
    check(demo.turns.active_unit_id() == "ally_1", "following AI turn runs on a later scheduler call")
    demo.free()


func test_reset_and_switch_clear_old_wait() -> void:
    var demo = small_demo()
    demo.pass_turn()
    ready_ai(demo)
    demo.update_ai(demo.AI_THINK_SECONDS * 0.75)
    demo.reset_demo()
    var old_red_cell: Vector2i = demo.board.position_of("enemy_1")
    demo.update_ai(10.0)
    check(demo.turns.active_unit_id() == "ally_1" and demo.board.position_of("enemy_1") == old_red_cell,
        "R cancels pending red work and restarts at blue")
    demo.pass_turn()
    ready_ai(demo)
    demo.update_ai(demo.AI_THINK_SECONDS * 0.5)
    check(demo.turns.active_unit_id() == "enemy_1", "R clears previous partial thinking time")
    demo.switch_encounter()
    demo.pass_turn()
    var duel_red_cell: Vector2i = demo.board.position_of("enemy_1")
    demo.update_ai(10.0)
    check(demo.encounter_index == 0 and not demo.is_ai_turn()
        and demo.turns.active_unit_id() == "enemy_1" and demo.board.position_of("enemy_1") == duel_red_cell,
        "T cancels old team AI work and leaves legacy duel manual")
    demo.free()


func test_victory_stops_ai() -> void:
    var demo = small_demo("enemy_3")
    check(demo.board.move_unit("enemy_3", Vector2i(2, 2)), "place Lich for deterministic final spell")
    var lich = demo.units["enemy_3"]
    lich.spell_power = 300
    lich.melee_skill_power = 1
    lich.mana_regen_pct = 0.0
    demo.units["ally_1"].hp = 1
    demo.pass_turn()
    let_ai_act(demo)
    check(demo.battle_over and demo.winner_side == "red", "AI can finish the last opponent and win for red")
    check(not demo.board.unit_positions.has("ally_1") and not demo.turns.turn_order.has("ally_1"),
        "AI lethal spell removes defeated target from board and queue")
    var mp_after: int = lich.mp
    var active_after: String = demo.turns.active_unit_id()
    finish_animation(demo)
    demo.update_ai(100.0)
    demo.perform_ai_turn()
    demo.pass_turn(true)
    check(lich.mp == mp_after and demo.turns.active_unit_id() == active_after,
        "victory blocks scheduled or direct AI execution and further turns")
    demo.reset_demo()
    check(not demo.battle_over and demo.turns.active_unit_id() == "ally_1", "restart clears AI victory")
    demo.free()


func test_consecutive_ai_turns() -> void:
    var demo = new_demo()
    for unit_id in demo.units.keys():
        if unit_id not in ["ally_1", "enemy_1", "enemy_2"]:
            demo.units.erase(unit_id)
    demo.roster_order.assign(["ally_1", "enemy_1", "enemy_2"])
    demo.turns = Turns.new(["ally_1", "enemy_1", "enemy_2"])
    demo.board = Board.new(9, 7)
    demo.board.add_unit("ally_1", Vector2i(0, 3))
    demo.board.add_unit("enemy_1", Vector2i(7, 1))
    demo.board.add_unit("enemy_2", Vector2i(7, 5))
    var second_red_cell: Vector2i = demo.board.position_of("enemy_2")
    demo.pass_turn()
    demo.update_ai(100.0)
    check(demo.turns.active_unit_id() == "enemy_2"
        and demo.board.position_of("enemy_2") == second_red_cell,
        "one large scheduler delta executes at most one of consecutive AI actors")
    ready_ai(demo)
    demo.update_ai(demo.AI_THINK_SECONDS - 0.01)
    check(demo.turns.active_unit_id() == "enemy_2"
        and demo.board.position_of("enemy_2") == second_red_cell,
        "next consecutive AI actor receives a fresh entire thinking pause")
    demo.update_ai(0.02)
    check(demo.turns.active_unit_id() == "ally_1", "second AI completes only its own scheduled turn")
    demo.free()


func test_blue_victory_stops_ai() -> void:
    var demo = small_demo()
    check(demo.board.move_unit("enemy_1", Vector2i(2, 2)), "place final red target beside blue")
    demo.units["enemy_1"].hp = 1
    demo.casting_mode = true
    demo.attack_enemy("ally_1", "enemy_1")
    check(demo.battle_over and demo.winner_side == "blue", "manual blue can defeat the last AI opponent")
    var blue_hp: int = demo.units["ally_1"].hp
    var blue_mp: int = demo.units["ally_1"].mp
    var active: String = demo.turns.active_unit_id()
    finish_animation(demo)
    demo.update_ai(100.0)
    demo.perform_ai_turn()
    check(demo.units["ally_1"].hp == blue_hp and demo.units["ally_1"].mp == blue_mp
        and demo.turns.active_unit_id() == active and not demo.is_ai_turn(),
        "blue victory prevents any further AI turn or resource change")
    demo.free()
