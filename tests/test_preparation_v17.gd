extends SceneTree
## Preparation -> deployment -> battle through the real v1.7 demo lifecycle.
## Run: godot --headless --path . --script res://tests/test_preparation_v17.gd

const Demo = preload("res://scripts/battle_demo.gd")
const Scene = preload("res://scenes/battle_demo.tscn")
const ORDER: Array[String] = ["ally_1", "enemy_1", "ally_2", "enemy_2", "ally_3", "enemy_3"]

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    call_deferred("run_checks")


func check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAILED preparation v1.7: " + description)


func new_demo():
    var demo = Demo.new()
    demo.reset_demo()
    return demo


func deploy(demo) -> void:
    demo.preparation_ui.show_deployment()
    demo.preview_preparation()


func snapshot(demo) -> Dictionary:
    var resources: Dictionary = {}
    for unit_id in demo.units:
        var unit = demo.units[unit_id]
        resources[unit_id] = [unit.hp, unit.mp, unit.concussion_turns_remaining]
    return {
        "resources": resources,
        "positions": demo.board.unit_positions.duplicate(),
        "active": demo.turns.active_unit_id(),
        "round": demo.turns.round_number,
        "animation": demo.animation_time,
        "casting": demo.casting_mode,
        "special": demo.special_mode,
        "encounter": demo.encounter_index,
    }


func send_key(demo, keycode: int) -> void:
    var event := InputEventKey.new()
    event.pressed = true
    event.keycode = keycode
    demo._unhandled_input(event)


func test_entry_and_flow() -> void:
    var demo = new_demo()
    check(not demo.start_in_preparation and not demo.preparing,
        "direct Demo.new keeps legacy battle fixture behavior")
    demo.open_preparation()
    check(demo.preparing and demo.preparation_ui != null, "new battle opens preparation")
    check(demo.preparation_ui.stage == "roster", "preparation begins with roster stage")
    check(demo.preparation_ui.setup.is_valid(), "initial preparation has complete valid teams")
    check(not demo.start_prepared_battle(), "battle cannot bypass roster stage")
    check(demo.preparing, "failed early start stays in preparation")
    demo.open_preparation()
    check(demo.preparing and demo.preparation_ui.setup.is_valid(),
        "opening preparation again leaves one valid editable draft")
    # No queued callbacks from a previous view are needed to start the battle.
    check(demo.preparation_ui != null, "reopened preparation owns a current view")
    deploy(demo)
    check(demo.preparation_ui.stage == "deployment", "next step exposes deployment")
    check(demo.board.unit_positions.size() == 6 and demo.units.size() == 6,
        "deployment materializes six preview units")
    check(demo.start_prepared_battle(), "valid deployment starts battle")
    check(not demo.preparing and demo.team_setup != null, "battle owns a committed setup")
    check(demo.turns.turn_order == ORDER and demo.turns.active_unit_id() == "ally_1"
        and demo.turns.round_number == 1, "new battle starts at the original interleaved queue")
    check(demo.selected_unit_id.is_empty() and not demo.battle_over and demo.winner_side.is_empty(),
        "new battle clears selection and outcome")
    send_key(demo, KEY_P)
    check(demo.preparing and demo.preparation_ui.stage == "roster", "P opens next battle preparation")
    demo.free()


func test_custom_roster_and_independence() -> void:
    var demo = new_demo()
    demo.open_preparation()
    var draft = demo.preparation_ui.setup
    var choices: Dictionary = {
        "ally_1": "lich", "ally_2": "lich", "ally_3": "female",
        "enemy_1": "male", "enemy_2": "falcon", "enemy_3": "hellhound",
    }
    for unit_id in choices:
        check(draft.set_profile(unit_id, choices[unit_id]), "choose profile for " + unit_id)
    draft.enemy_ai_enabled = false
    deploy(demo)
    check(demo.units["ally_1"].is_monster and demo.units["ally_1"].spell_power > 0,
        "selected blue Lich has its actual spell")
    check(demo.units["enemy_1"].level == 25 and not demo.units["enemy_1"].is_monster,
        "selected red commander uses actual commander data")
    check(demo.units["ally_3"].critical_multiplier == 2.0,
        "selected blue woman retains physical critical passive")
    for unit_id in ORDER:
        check(demo.board.position_of(unit_id) == draft.positions[unit_id],
            "preview position follows draft for " + unit_id)
    check(demo.start_prepared_battle(), "custom roster starts")
    check(not demo.enemy_ai_enabled, "chosen manual red control carries into battle")
    check(demo.units["ally_1"] != demo.units["ally_2"], "duplicate profiles have distinct runtime objects")
    var second_hp: int = demo.units["ally_2"].hp
    var second_mp: int = demo.units["ally_2"].mp
    demo.units["ally_1"].receive_damage(35)
    demo.units["ally_1"].spend_mana(10)
    demo.units["ally_1"].apply_concussion(2)
    check(demo.units["ally_2"].hp == second_hp and demo.units["ally_2"].mp == second_mp
        and demo.units["ally_2"].concussion_turns_remaining == 0,
        "damage, MP and status never leak between identical chosen profiles")
    check(draft.set_profile("ally_1", "male"), "old draft remains independently editable")
    check(demo.team_setup.profile_key("ally_1") == "lich" and demo.units["ally_1"].is_monster,
        "editing old draft cannot mutate accepted roster or running battle")
    check(draft.place_unit("ally_1", Vector2i(0, 0)), "old draft position can be changed")
    check(demo.board.position_of("ally_1") == demo.team_setup.positions["ally_1"]
        and demo.team_setup.positions["ally_1"] != Vector2i(0, 0),
        "accepted positions are copied instead of aliased")
    demo.free()


func test_deployment_board_interaction() -> void:
    var demo = new_demo()
    demo.open_preparation()
    deploy(demo)
    var ui = demo.preparation_ui
    var draft = ui.setup
    var ally_origin: Vector2i = draft.positions["ally_1"]
    var ally_target: Vector2i = Vector2i(0, 0)
    ui.handle_board_click(ally_origin)
    check(ui.selected_unit_id == "ally_1", "clicking preview unit selects it")
    ui.handle_board_click(ally_target)
    check(draft.positions["ally_1"] == ally_target and demo.board.position_of("ally_1") == ally_target,
        "free blue-zone click updates draft and real board preview")
    check(demo.turns.round_number == 1 and demo.turns.active_unit_id() == "ally_1",
        "deployment moves do not consume turns")
    var hp_before: int = demo.units["enemy_1"].hp
    var enemy_origin: Vector2i = draft.positions["enemy_1"]
    ui.handle_board_click(enemy_origin)
    check(ui.selected_unit_id == "enemy_1" and demo.units["enemy_1"].hp == hp_before,
        "clicking opposing preview selects it without attacking")
    ui.handle_board_click(Vector2i(demo.demo_columns - 1, 0))
    check(demo.board.position_of("enemy_1") == Vector2i(demo.demo_columns - 1, 0),
        "red can be deployed to its own edge")
    var red_position: Vector2i = draft.positions["enemy_1"]
    ui.handle_board_click(Vector2i(2, 0))
    check(draft.positions["enemy_1"] == red_position, "middle neutral cell cannot accept a red deployment")
    ui.handle_board_click(Vector2i(1, 0))
    check(draft.positions["enemy_1"] == red_position, "opposing zone cannot accept a red deployment")
    check(not draft.place_unit("enemy_2", red_position), "occupied deployment cell rejects another unit")
    check(draft.is_valid() and demo.board.unit_positions.size() == 6, "invalid moves preserve valid six-unit setup")
    ui.show_roster()
    check(ui.stage == "roster" and draft.positions["ally_1"] == ally_target,
        "back to compositions preserves drafted placement")
    deploy(demo)
    check(demo.start_prepared_battle(), "edited placement starts battle")
    check(demo.board.position_of("ally_1") == ally_target
        and demo.board.position_of("enemy_1") == red_position,
        "battle starts at explicitly chosen deployment cells")
    demo.free()


func test_preparation_blocks_combat() -> void:
    var demo = new_demo()
    demo.pass_turn()
    demo.update_ai(demo.AI_THINK_SECONDS * 0.5)
    check(demo.turns.active_unit_id() == "enemy_1", "arrange pending red AI turn")
    demo.open_preparation()
    check(demo.ai_waiting_unit_id.is_empty(), "opening preparation clears pending AI actor")
    demo.units["enemy_1"].apply_concussion(2)
    demo.concussion_skip_pending = true
    demo.animation_time = 0.0
    demo.casting_mode = true
    demo.special_mode = false
    var before: Dictionary = snapshot(demo)
    var red_position: Vector2i = demo.board.position_of("enemy_1")
    demo._process(100.0)
    demo.update_ai(100.0)
    demo.perform_ai_turn()
    demo.pass_turn()
    demo.pass_turn(true)
    demo.debug_spend_mana()
    demo.attack_enemy("enemy_1", "ally_1", 99.0, 99.0, 0.0, true)
    demo.move_active_unit("enemy_1", Vector2i(4, 1), true)
    demo.resolve_one_concussion_skip()
    demo.advance_turn("enemy_1")
    for keycode in [KEY_1, KEY_2, KEY_F, KEY_SPACE, KEY_A, KEY_R, KEY_T, KEY_M]:
        send_key(demo, keycode)
    check(snapshot(demo) == before, "preparation blocks combat, timers, status skips and battle hotkeys")
    check(not demo.can_perform_action(demo.turns.active_unit_id()), "no actor can perform a combat action in preparation")
    check(demo.board.position_of("enemy_1") == red_position, "pending AI never moves preview units")
    deploy(demo)
    check(demo.start_prepared_battle(), "valid preparation restarts after an interrupted battle")
    check(demo.animation_time == demo.ANIMATION_DURATION and not demo.concussion_skip_pending,
        "start removes stale hit animation and pending concussion")
    check(demo.ai_waiting_unit_id.is_empty() and demo.ai_delay_remaining == demo.AI_THINK_SECONDS,
        "fresh battle cannot inherit an old AI delay")
    for unit_id in ORDER:
        check(demo.units[unit_id].concussion_turns_remaining == 0,
            "new runtime unit has no old status: " + unit_id)
    demo.free()


func test_restart_and_legacy_cycle() -> void:
    var demo = new_demo()
    demo.open_preparation()
    var draft = demo.preparation_ui.setup
    draft.set_profile("ally_1", "falcon")
    draft.set_profile("enemy_1", "female")
    draft.enemy_ai_enabled = false
    draft.place_unit("ally_1", Vector2i(0, 0))
    draft.place_unit("enemy_1", Vector2i(demo.demo_columns - 1, demo.demo_rows - 1))
    deploy(demo)
    check(demo.start_prepared_battle(), "restart fixture starts chosen battle")
    var chosen_positions: Dictionary = demo.board.unit_positions.duplicate()
    demo.units["ally_1"].receive_damage(55)
    demo.units["ally_1"].apply_concussion(2)
    demo.units["enemy_1"].mp = 0
    demo.battle_over = true
    demo.winner_side = "red"
    demo.reset_demo()
    check(demo.board.unit_positions == chosen_positions and demo.turns.turn_order == ORDER,
        "R restores chosen cells and queue")
    check(demo.units["ally_1"].is_monster and not demo.units["enemy_1"].is_monster,
        "R retains the chosen composition")
    check(not demo.battle_over and demo.winner_side.is_empty() and demo.turns.round_number == 1,
        "R clears prior outcome and round")
    for unit_id in ORDER:
        var unit = demo.units[unit_id]
        check(unit.hp == unit.max_hp and unit.mp == unit.max_mp and unit.concussion_turns_remaining == 0,
            "R creates fresh resources and statuses: " + unit_id)
    demo.toggle_enemy_ai()
    check(demo.enemy_ai_enabled, "A can change control preference after custom start")
    demo.reset_demo()
    check(demo.enemy_ai_enabled, "R preserves changed AI preference")
    demo.switch_encounter()
    check(demo.encounter_index == 0 and demo.units.size() == 2,
        "T still enters original duel after a custom team fight")
    check(not demo.units["ally_1"].is_monster and not demo.units["enemy_1"].is_monster,
        "legacy duel retains original commander profiles")
    check(not demo.ai_controls_unit("enemy_1"), "legacy duel remains manual")
    for _step in range(4):
        demo.switch_encounter()
    check(demo.encounter_index == demo.TEAM_ENCOUNTER and demo.units.size() == 6,
        "T cycle returns to six-unit team battle")
    check(demo.board.unit_positions == chosen_positions and demo.units["ally_1"].is_monster,
        "returning team encounter restores custom roster and placement")
    check(demo.enemy_ai_enabled, "legacy cycle does not discard AI preference")
    demo.open_preparation()
    check(demo.preparation_ui.setup.profile_key("ally_1") == "falcon"
        and demo.preparation_ui.setup.enemy_ai_enabled,
        "next preparation starts from accepted roster and current AI preference")
    demo.free()


func test_invalid_start_preserves_draft() -> void:
    var demo = new_demo()
    demo.open_preparation()
    deploy(demo)
    var draft = demo.preparation_ui.setup
    draft.positions["enemy_1"] = draft.positions["ally_1"]
    check(not draft.is_valid(), "arrange illegal overlapping deployment")
    check(not demo.start_prepared_battle() and demo.preparing,
        "invalid deployment cannot close preparation or start combat")
    check(demo.team_setup == null, "invalid first draft never becomes accepted configuration")
    draft.reset_positions()
    check(demo.start_prepared_battle(), "repairing draft allows start")
    var committed_key: String = demo.team_setup.profile_key("ally_1")
    demo.open_preparation()
    deploy(demo)
    demo.preparation_ui.setup.profile_keys["ally_1"] = "unknown"
    check(not demo.start_prepared_battle() and demo.preparing,
        "unknown roster entry prevents starting a later battle")
    check(demo.team_setup.profile_key("ally_1") == committed_key,
        "invalid later draft preserves previous committed configuration")
    demo.free()


func test_actual_scene_starts_in_preparation() -> void:
    var scene = Scene.instantiate()
    check(scene.start_in_preparation, "main scene opts into v1.7 preparation on launch")
    get_root().add_child(scene)
    scene.process_mode = Node.PROCESS_MODE_DISABLED
    check(scene.preparing and scene.preparation_ui != null
        and scene.preparation_ui.stage == "roster", "scene ready opens roster instead of starting AI battle")
    var options: Array[Node] = scene.preparation_ui.find_children("*", "OptionButton", true, false)
    check(options.size() == 6, "roster screen exposes six native profile selectors")
    for option in options:
        check(option.item_count == 5, "every slot exposes all five existing profiles")
    scene.free()


func test_native_control_flow() -> void:
    var scene = Scene.instantiate()
    get_root().add_child(scene)
    scene.process_mode = Node.PROCESS_MODE_DISABLED
    var ui = scene.preparation_ui
    var first_option: OptionButton = ui.profile_options["ally_1"]
    first_option.select(4)
    first_option.item_selected.emit(4)
    check(ui.setup.profile_key("ally_1") == "lich", "profile selector signal edits actual draft")
    check(ui.profile_summaries["ally_1"].text.contains("HP 500")
        and ui.profile_summaries["ally_1"].text.contains("F:"),
        "profile selector refreshes HP and spell summary")
    ui.ai_checkbox.button_pressed = false
    check(not ui.setup.enemy_ai_enabled, "checkbox edits the draft control choice")
    check(not ui.next_button.disabled, "complete chosen rosters enable next step")
    ui.next_button.pressed.emit()
    check(ui.stage == "deployment" and scene.units["ally_1"].is_monster
        and scene.units["ally_1"].spell_power > 0,
        "next button signal materializes selected unit through root preview")
    ui.unit_buttons["enemy_2"].pressed.emit()
    check(ui.selected_unit_id == "enemy_2" and scene.selected_unit_id == "enemy_2",
        "deployment roster button synchronizes board selection")
    var chosen: Vector2i = Vector2i(scene.demo_columns - 1, 0)
    ui.handle_board_click(chosen)
    check(scene.board.position_of("enemy_2") == chosen, "selected roster button controls the next placement")
    check(not ui.start_button.disabled, "valid six-unit deployment enables battle button")
    ui.start_button.pressed.emit()
    check(not scene.preparing and scene.team_setup.profile_key("ally_1") == "lich"
        and not scene.enemy_ai_enabled,
        "start button signal commits choices and starts actual battle")
    check(scene.board.position_of("enemy_2") == chosen and scene.turns.active_unit_id() == "ally_1",
        "native control flow preserves placement and original first turn")
    check(scene.new_battle_button.visible, "running battle exposes new battle control")
    scene.new_battle_button.pressed.emit()
    check(scene.preparing and scene.preparation_ui.stage == "roster"
        and scene.preparation_ui.setup.profile_key("ally_1") == "lich",
        "new battle button starts an editable copy of the accepted composition")
    scene.free()


func run_checks() -> void:
    test_entry_and_flow()
    test_custom_roster_and_independence()
    test_deployment_board_interaction()
    test_preparation_blocks_combat()
    test_restart_and_legacy_cycle()
    test_invalid_start_preserves_draft()
    test_actual_scene_starts_in_preparation()
    test_native_control_flow()
    if failures == 0:
        print("SULEYN preparation v1.7: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN preparation v1.7: %d / %d checks FAILED." % [failures, checks])
        quit(1)
