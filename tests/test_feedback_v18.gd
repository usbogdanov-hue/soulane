extends SceneTree
## Exercise preview gates and results through the real demo and control signals.
const Demo = preload("res://scripts/battle_demo.gd")
const Scene = preload("res://scenes/battle_demo.tscn")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    call_deferred("run_checks")


func check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAILED feedback v1.8: " + description)


func fixture():
    var demo = Demo.new()
    demo.reset_demo()
    demo.enemy_ai_enabled = false
    check(demo.board.move_unit("enemy_1", Vector2i(2, 1)), "fixture positions adjacent enemy")
    demo.selected_unit_id = "ally_1"
    demo.hovered_cell = Vector2i(2, 1)
    return demo


func state(demo) -> Dictionary:
    var resources: Dictionary = {}
    for unit_id in demo.units:
        var unit = demo.units[unit_id]
        resources[unit_id] = [unit.hp, unit.mp, unit.concussion_turns_remaining]
    return {"units": resources, "positions": demo.board.unit_positions.duplicate(true),
        "active": demo.turns.active_unit_id(), "round": demo.turns.round_number,
        "spent": demo.turns.action_spent, "battle_over": demo.battle_over,
        "winner": demo.winner_side, "mode": demo.current_attack_mode()}


func key(demo, code: int) -> void:
    var event := InputEventKey.new()
    event.pressed = true
    event.keycode = code
    demo._unhandled_input(event)


func test_runtime_preview() -> void:
    var demo = fixture()
    var preview: Dictionary = demo.attack_preview_for("enemy_1")
    check(preview.available and preview.distance == 1, "selected current actor can preview legal attack")
    check(demo.can_target_with_mode("ally_1", "enemy_1"), "target availability matches legal preview")
    check(demo.feedback_text().contains("Доступно:") and demo.feedback_text().contains("HP"),
        "hover gives action availability and damage information")
    demo.selected_unit_id = ""
    preview = demo.attack_preview_for("enemy_1")
    check(not preview.available and preview.reason.contains("выберите"), "preview explains missing active selection")
    demo.selected_unit_id = "ally_1"
    demo.animation_time = 0.1
    preview = demo.attack_preview_for("enemy_1")
    check(not preview.available and preview.reason.contains("анимации"), "preview blocks during hit animation")
    demo.animation_time = demo.ANIMATION_DURATION
    demo.units["ally_1"].apply_concussion(2)
    preview = demo.attack_preview_for("enemy_1")
    check(not preview.available and preview.reason.contains("Контузия"), "preview blocks stunned actor")
    check(demo.unit_status("ally_1").contains("2") and demo.unit_status("ally_1").contains("собственных"),
        "status specifies remaining own skipped turns")
    demo.units["ally_1"].concussion_turns_remaining = 0
    demo.concussion_skip_pending = true
    check(not demo.attack_preview_for("enemy_1").available, "preview blocks pending concussion skip")
    demo.concussion_skip_pending = false
    demo.turns.action_spent = true
    preview = demo.attack_preview_for("enemy_1")
    check(not preview.available and preview.reason.contains("потрачено"), "preview rejects spent action")
    demo.turns.action_spent = false
    demo.set_attack_mode("special")
    demo.units["ally_1"].mp = 0
    preview = demo.attack_preview_for("enemy_1")
    check(not preview.available and preview.reason.contains("MP"), "preview explains low MP")
    check(not demo.can_target_with_mode("ally_1", "enemy_1"), "low-MP target is not highlighted as available")
    check(preview.normal_damage > 0, "unaffordable attack retains informational damage estimate")
    demo.units["ally_1"].mp = demo.units["ally_1"].max_mp
    demo.set_attack_mode("basic")
    demo.board.move_unit("enemy_1", Vector2i(6, 1))
    preview = demo.attack_preview_for("enemy_1")
    check(not preview.available and preview.reason.contains("дальности"), "range rejection gives actionable explanation")
    demo.board.move_unit("enemy_1", Vector2i(2, 1))
    var before: Dictionary = state(demo)
    seed(8111)
    var expected_random: float = randf()
    seed(8111)
    for _iteration in range(20):
        demo.attack_preview_for("enemy_1")
        demo.feedback_text()
        demo.battle_summary()
    check(randf() == expected_random, "reading runtime feedback does not consume combat RNG")
    check(state(demo) == before, "repeated feedback reads preserve resources, positions and queue")
    demo.enemy_ai_enabled = true
    demo.turns.turn_index = 1
    demo.selected_unit_id = "enemy_1"
    preview = demo.attack_preview_for("ally_1")
    check(not preview.available and preview.reason.contains("ИИ"), "preview explains AI ownership")
    var ai_before: Dictionary = state(demo)
    demo.set_attack_mode("magic")
    check(state(demo) == ai_before, "manual mode choice cannot alter automated turn")
    demo.enemy_ai_enabled = false
    demo.battle_over = true
    preview = demo.attack_preview_for("ally_1")
    check(not preview.available and preview.reason.contains("завершён"), "preview blocks completed battle")
    demo.battle_over = false
    demo.open_preparation()
    preview = demo.attack_preview_for("ally_1")
    check(not preview.available and preview.reason.contains("подготовку"), "preview blocks deployment and roster editing")
    demo.free()


func eliminate(demo, unit_id: String) -> void:
    demo.units[unit_id].receive_damage(99999)
    demo.board.remove_unit(unit_id)
    demo.turns.remove_unit(unit_id)


func win_team_battle(demo) -> void:
    eliminate(demo, "enemy_2")
    eliminate(demo, "enemy_3")
    eliminate(demo, "ally_3")
    demo.board.move_unit("enemy_1", Vector2i(2, 1))
    demo.units["enemy_1"].hp = 1
    demo.turns.round_number = 3
    demo.selected_unit_id = "ally_1"
    demo.casting_mode = false
    demo.special_mode = false
    demo.attack_enemy("ally_1", "enemy_1", 99.0, 99.0, 99.0)


func test_results_lifecycle() -> void:
    var demo = fixture()
    demo.create_battle_feedback()
    win_team_battle(demo)
    check(demo.battle_over and demo.winner_side == "blue" and demo.results_pending,
        "last enemy kill schedules results for correct winner")
    check(demo.animation_time == 0.0 and demo.results_ui == null, "last hit animation remains visible before result modal")
    demo.show_battle_results()
    check(demo.results_ui == null and demo.results_pending, "opening results directly cannot skip final animation")
    var summary: Dictionary = demo.battle_summary()
    check(summary.rounds == 3 and summary.units.size() == 6, "summary retains final round and all participants")
    check(summary.teams.blue == {"total": 3, "alive": 2, "fallen": 1}, "summary counts blue survivors and losses")
    check(summary.teams.red == {"total": 3, "alive": 0, "fallen": 3}, "summary includes all fallen enemies")
    var frozen: Dictionary = state(demo)
    demo._process(demo.ANIMATION_DURATION)
    check(demo.results_ui != null and demo.results_ui.visible and not demo.results_pending,
        "results open automatically after last animation")
    check(not demo.feedback_ui.visible and demo.results_button.visible, "results hide live preview and enable reopening")
    demo._process(100.0)
    demo.update_ai(100.0)
    demo.perform_ai_turn()
    check(state(demo) == frozen, "victory stops further AI and combat state transitions")
    for code in [KEY_1, KEY_2, KEY_F, KEY_M, KEY_SPACE, KEY_A]:
        key(demo, code)
    check(state(demo) == frozen, "result modal blocks combat and attack-mode hotkeys")
    demo.results_ui.review_button.pressed.emit()
    check(not demo.results_ui.visible and demo.feedback_ui.visible and demo.battle_over,
        "review signal returns to finished field without restarting")
    demo.results_button.pressed.emit()
    check(demo.results_ui.visible and demo.results_ui.summary.teams.blue.fallen == 1,
        "results button reopens same final outcome")
    demo.results_ui.repeat_button.pressed.emit()
    check(not demo.battle_over and not demo.results_ui.visible and not demo.results_button.visible,
        "repeat signal resets outcome and hides completed summary")
    check(demo.turns.round_number == 1 and demo.units["ally_3"].is_alive()
        and demo.units["enemy_3"].is_alive(), "repeat creates fresh units and queue")
    check(demo.feedback_ui.visible, "repeat restores live preview controls")
    win_team_battle(demo)
    demo._process(demo.ANIMATION_DURATION)
    demo.results_ui.preparation_button.pressed.emit()
    check(demo.preparing and demo.preparation_ui.stage == "roster" and not demo.results_ui.visible,
        "change-compositions signal opens preparation and hides results")
    check(not demo.feedback_ui.visible and not demo.results_button.visible,
        "preparation cannot expose stale live controls or result button")
    demo.free()


func test_red_duel_result() -> void:
    var demo = fixture()
    demo.encounter_index = 0
    demo.reset_demo()
    demo.board.move_unit("enemy_1", Vector2i(2, 3))
    demo.units["ally_1"].hp = 1
    demo.turns.turn_index = 1
    demo.turns.round_number = 4
    demo.attack_enemy("enemy_1", "ally_1", 99.0, 99.0, 99.0)
    demo._process(demo.ANIMATION_DURATION)
    check(demo.battle_over and demo.winner_side == "red" and demo.results_ui.visible,
        "manual red commander can win original duel and open results")
    var summary: Dictionary = demo.results_ui.summary
    check(summary.rounds == 4 and summary.units.size() == 2, "duel summary uses two participants and actual round")
    check(summary.teams.blue.total == 1 and summary.teams.blue.fallen == 1
        and summary.teams.red.alive == 1, "duel losses do not assume three units per team")
    key(demo, KEY_T)
    check(not demo.results_ui.visible and not demo.battle_over and demo.encounter_index == 1,
        "T from result modal opens next legacy scenario cleanly")
    demo.free()


func test_actual_controls() -> void:
    var demo = Scene.instantiate()
    demo.persist_setups = false
    root.add_child(demo)
    demo.set_process(false)
    check(demo.preparing and demo.feedback_ui != null and not demo.feedback_ui.visible,
        "actual main scene starts with battle feedback hidden during preparation")
    var ui = demo.preparation_ui
    ui.profile_options["ally_1"].select(4)
    ui.profile_options["ally_1"].item_selected.emit(4)
    ui.ai_checkbox.button_pressed = false
    ui.handle_board_click(Vector2i(0, 0))
    ui.next_button.pressed.emit()
    ui.handle_board_click(Vector2i(0, 0))
    var accepted: Dictionary = ui.setup.positions.duplicate(true)
    ui.start_button.pressed.emit()
    check(not demo.preparing and demo.feedback_ui.visible and demo.units["ally_1"].is_monster,
        "real start control exposes battle feedback for custom chosen profile")
    var initial: Dictionary = state(demo)
    demo.feedback_ui.mode_buttons.magic.pressed.emit()
    check(demo.current_attack_mode() == "magic", "native magic button changes attack mode")
    check(demo.turns.active_unit_id() == initial.active and demo.turns.round_number == initial.round
        and not demo.turns.action_spent and demo.units["ally_1"].mp == initial.units.ally_1[1],
        "mode button never spends mana or a turn")
    key(demo, KEY_F)
    check(demo.current_attack_mode() == "basic", "F toggles selected magic back to basic")
    key(demo, KEY_F)
    check(demo.current_attack_mode() == "magic", "F toggles basic to magic")
    demo.feedback_ui.mode_buttons.special.pressed.emit()
    check(demo.current_attack_mode() == "special" and not demo.casting_mode,
        "native special button selects mutually exclusive mode")
    demo.feedback_ui.mode_buttons.basic.pressed.emit()
    check(demo.current_attack_mode() == "basic" and not demo.special_mode,
        "native basic button clears special mode")
    demo.units["ally_1"].receive_damage(19)
    demo.battle_over = true
    demo.winner_side = "red"
    demo.show_battle_results()
    demo.results_ui.repeat_button.pressed.emit()
    check(demo.board.unit_positions == accepted and demo.units["ally_1"].is_monster
        and demo.units["ally_1"].spell_power > 0, "repeat result control retains accepted custom roster and deployment")
    check(demo.units["ally_1"].hp == demo.units["ally_1"].max_hp and demo.feedback_ui.visible,
        "custom replay restores HP and feedback")
    demo.battle_over = true
    demo.winner_side = "blue"
    demo.show_battle_results()
    demo.results_ui.preparation_button.pressed.emit()
    check(demo.preparation_ui.setup.profile_key("ally_1") == "lich"
        and demo.preparation_ui.setup.positions == accepted,
        "result preparation control opens editable accepted custom configuration")
    demo.free()


func run_checks() -> void:
    test_runtime_preview()
    test_results_lifecycle()
    test_red_duel_result()
    test_actual_controls()
    if failures == 0:
        print("SULEYN feedback v1.8: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN feedback v1.8: %d/%d checks FAILED." % [failures, checks])
        quit(1)
