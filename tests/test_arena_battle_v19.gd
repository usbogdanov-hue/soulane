extends SceneTree
## Arenas through the real preparation, movement and AI lifecycle.
const Demo = preload("res://scripts/battle_demo.gd")
const Scene = preload("res://scenes/battle_demo.tscn")
const Arena = preload("res://scripts/battle_arena.gd")
const Turns = preload("res://scripts/battle_turns.gd")
const Hex = preload("res://scripts/hex_math.gd")
const Rules = preload("res://scripts/combat_rules.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    call_deferred("run_checks")


func check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAILED arena battle v1.9: " + description)


func choose_arena(ui, arena_key: String) -> void:
    var index: int = Arena.keys().find(arena_key)
    ui.arena_option.select(index)
    ui.arena_option.item_selected.emit(index)


func fixture(profile: String = "male", ai: bool = false):
    var demo = Demo.new()
    demo.reset_demo()
    demo.enemy_ai_enabled = ai
    demo.open_preparation()
    demo.preparation_ui.setup.set_profile("ally_1", profile)
    choose_arena(demo.preparation_ui, "gates")
    demo.preparation_ui.next_button.pressed.emit()
    demo.preparation_ui.start_button.pressed.emit()
    check(demo.board.move_unit("ally_1", Vector2i(3, 3)), "fixture places actor beside central barrier")
    demo.selected_unit_id = "ally_1"
    demo.refresh_reachable()
    return demo


func state(demo) -> Dictionary:
    var resources: Dictionary = {}
    for unit_id in demo.units:
        var unit = demo.units[unit_id]
        resources[unit_id] = [unit.hp, unit.mp, unit.concussion_turns_remaining]
    return {"resources": resources, "positions": demo.board.unit_positions.duplicate(true),
        "blocked": demo.board.blocked.duplicate(true), "active": demo.turns.active_unit_id(),
        "round": demo.turns.round_number, "spent": demo.turns.action_spent,
        "winner": demo.winner_side, "over": demo.battle_over,
        "arena": demo.team_setup.arena_key if demo.team_setup != null else "open"}


func test_preparation_and_replay() -> void:
    var demo = Scene.instantiate()
    demo.persist_setups = false
    root.add_child(demo)
    demo.set_process(false)
    check(demo.preparing and demo.preparation_ui.setup.arena_key == "open"
        and demo.board.blocked.is_empty(), "real scene starts with open arena preparation")
    var ui = demo.preparation_ui
    var positions: Dictionary = ui.setup.positions.duplicate(true)
    var profiles: Dictionary = ui.setup.profile_keys.duplicate(true)
    choose_arena(ui, "gates")
    check(ui.setup.arena_key == "gates" and ui.setup.positions == positions
        and ui.setup.profile_keys == profiles, "arena selector changes draft without changing combatants or placement")
    check(demo.team_setup == null and demo.board.blocked.is_empty(), "roster selection does not apply an unaccepted arena to battle")
    check(ui.roster_status_label.text.contains("непроходим"), "roster explains closed hex movement restriction")
    ui.next_button.pressed.emit()
    check(demo.preparing and ui.stage == "deployment" and demo.board.blocked.size() == 5,
        "deployment preview constructs chosen arena before placing units")
    check(ui.deployment_hint.text.contains("Два прохода"), "deployment identifies selected arena")
    ui.handle_board_click(Vector2i(4, 3))
    check(ui.setup.positions == positions and ui.status_label.text.contains("закрыт"),
        "closed-hex deployment click leaves placements unchanged and explains rejection")
    ui.start_button.pressed.emit()
    check(not demo.preparing and demo.team_setup.arena_key == "gates"
        and demo.board.blocked.has(Vector2i(4, 3)), "start accepts chosen arena and constructs blocked board")
    var blocked: Dictionary = demo.board.blocked.duplicate(true)
    demo.units["ally_1"].receive_damage(20)
    demo.reset_demo()
    check(demo.board.blocked == blocked and demo.board.unit_positions == positions
        and demo.units["ally_1"].hp == demo.units["ally_1"].max_hp,
        "R repeats accepted arena, positions and fresh unit state")
    for index in range(4):
        demo.switch_encounter()
        check(demo.encounter_index == index and demo.board.blocked.is_empty()
            and demo.team_setup.arena_key == "gates", "legacy duel remains open without losing arena preference %d" % index)
    demo.switch_encounter()
    check(demo.encounter_index == demo.TEAM_ENCOUNTER and demo.board.blocked == blocked,
        "T returns to accepted team arena")
    demo.open_preparation()
    ui = demo.preparation_ui
    check(ui.setup.arena_key == "gates", "P opens draft of accepted arena")
    choose_arena(ui, "pillars")
    check(ui.setup.arena_key == "pillars" and demo.team_setup.arena_key == "gates",
        "new arena draft is independent of accepted battle")
    ui._on_positions_reset()
    check(ui.setup.arena_key == "pillars", "position reset retains selected arena")
    ui._on_defaults_pressed()
    check(ui.setup.arena_key == "open" and demo.team_setup.arena_key == "gates"
        and ui.arena_option.selected == 0, "default example resets draft arena and selector only")
    choose_arena(ui, "pillars")
    ui.next_button.pressed.emit()
    check(demo.board.blocked.size() == 4 and demo.team_setup.arena_key == "gates",
        "new deployment preview does not overwrite accepted setup")
    ui.start_button.pressed.emit()
    check(demo.team_setup.arena_key == "pillars" and demo.board.blocked.size() == 4,
        "start applies changed arena")
    demo.free()


func test_route_preview_and_action() -> void:
    var demo = fixture()
    var target := Vector2i(5, 3)
    var preview: Dictionary = demo.movement_preview_for(target)
    check(preview.available and preview.steps == 3 and preview.budget == 3,
        "route takes three legal steps around barrier instead of geometric distance two")
    check(preview.steps > Hex.hex_distance(Vector2i(3, 3), target), "movement count uses actual route around closed hex")
    check(preview.path.front() == Vector2i(3, 3) and preview.path.back() == target,
        "preview route joins current actor position and requested destination")
    for index in range(1, preview.path.size()):
        check(Hex.hex_distance(preview.path[index - 1], preview.path[index]) == 1
            and not demo.board.blocked.has(preview.path[index])
            and demo.board.unit_at(preview.path[index]).is_empty(), "every preview step is adjacent, free and not blocked")
    demo.hovered_cell = target
    check(demo.feedback_text().contains("Маршрут") and demo.feedback_text().contains("3 из 3"),
        "movement panel shows route and real step budget")
    var before: Dictionary = state(demo)
    seed(19003)
    var expected: float = randf()
    seed(19003)
    for _iteration in range(12):
        demo.movement_preview_for(target)
        demo.feedback_text()
    check(randf() == expected and state(demo) == before,
        "repeated movement preview preserves RNG, resources, board, arena and turn")
    var blocked_preview: Dictionary = demo.movement_preview_for(Vector2i(4, 3))
    check(not blocked_preview.available and blocked_preview.path.is_empty()
        and blocked_preview.reason.contains("препятств"), "closed target gives specific rejection without path")
    demo.click_cell(Vector2i(4, 3))
    check(state(demo) == before and demo.message.contains("препятств"), "closed target click spends no turn or resources")
    check(not demo.move_active_unit("ally_1", Vector2i(4, 3)), "direct movement action also rejects a closed target")
    var distant: Dictionary = demo.movement_preview_for(Vector2i(6, 5))
    check(not distant.available and distant.steps > distant.budget
        and distant.path.size() == distant.steps + 1 and distant.reason.contains("шагов"),
        "distant destination explains full route cost beyond turn budget")
    demo.click_cell(Vector2i(6, 5))
    check(state(demo) == before, "out-of-budget click leaves battle unchanged")
    demo.click_cell(target)
    check(demo.board.position_of("ally_1") == target and demo.turns.active_unit_id() == "enemy_1",
        "legal detour moves actor and ends exactly one turn")
    var after: Dictionary = state(demo)
    check(not demo.move_active_unit("ally_1", Vector2i(6, 3)) and state(demo) == after,
        "moving actor cannot immediately spend a second action")
    demo.free()


func test_route_gates() -> void:
    var demo = fixture()
    var target := Vector2i(5, 3)
    demo.selected_unit_id = ""
    check(not demo.movement_preview_for(target).available
        and demo.movement_preview_for(target).reason.contains("выберите"), "route requires active selection")
    demo.selected_unit_id = "ally_1"
    demo.animation_time = 0.1
    check(demo.movement_preview_for(target).reason.contains("анимации"), "route unavailable during animation")
    demo.animation_time = demo.ANIMATION_DURATION
    demo.units["ally_1"].apply_concussion(2)
    check(demo.movement_preview_for(target).reason.contains("Контузия"), "stunned actor cannot route")
    demo.units["ally_1"].concussion_turns_remaining = 0
    demo.concussion_skip_pending = true
    check(not demo.movement_preview_for(target).available, "pending own-turn skip blocks routing")
    demo.concussion_skip_pending = false
    demo.turns.action_spent = true
    check(demo.movement_preview_for(target).reason.contains("потрачено"), "spent turn cannot route")
    demo.turns.action_spent = false
    demo.enemy_ai_enabled = true
    demo.turns.turn_index = 1
    demo.selected_unit_id = "enemy_1"
    check(demo.movement_preview_for(target).reason.contains("ИИ"), "route explains AI ownership")
    demo.turns.turn_index = 0
    demo.enemy_ai_enabled = false
    demo.selected_unit_id = "ally_1"
    demo.battle_over = true
    check(demo.movement_preview_for(target).reason.contains("завершён"), "completed battle cannot route")
    demo.battle_over = false
    demo.preparing = true
    check(demo.movement_preview_for(target).reason.contains("подготовку"), "preparation cannot execute movement")
    demo.preparing = false
    check(demo.movement_preview_for(Vector2i(-1, 0)).reason.contains("пределами"), "out-of-bounds target explained")
    check(demo.movement_preview_for(Vector2i(7, 1)).reason.contains("занят"), "occupied destination explained")
    var current: Dictionary = demo.movement_preview_for(Vector2i(3, 3))
    check(not current.available and current.steps == 0, "current hex is not a movement action")
    for direction in Hex.DIRECTIONS:
        demo.board.set_blocked(Vector2i(3, 3) + direction, true)
    var isolated: Dictionary = demo.movement_preview_for(target)
    check(not isolated.available and isolated.path.is_empty() and isolated.reason.contains("пути"),
        "isolated actor gets no-route explanation")
    demo.free()


func test_existing_flight_and_attack_rules() -> void:
    var demo = fixture("falcon")
    check((demo.units["ally_1"].monster_categories & Rules.FLYING) != 0, "fixture uses real flying category Falcon")
    check(not demo.movement_preview_for(Vector2i(4, 3)).available
        and not demo.move_active_unit("ally_1", Vector2i(4, 3)), "flying category retains existing closed-hex movement restriction")
    demo.free()
    demo = fixture("female")
    check(demo.board.move_unit("enemy_1", Vector2i(5, 3)), "place target behind blocked center hex")
    demo.set_attack_mode("special")
    var preview: Dictionary = demo.attack_preview_for("enemy_1")
    check(preview.available and preview.distance == 2 and demo.board.blocked.has(Vector2i(4, 3)),
        "existing range-two skill remains legal across closed hex without a new line-of-sight rule")
    var hp: int = demo.units["enemy_1"].hp
    demo.attack_enemy("ally_1", "enemy_1", 99.0, 99.0, 99.0)
    check(hp - demo.units["enemy_1"].hp == preview.normal_damage
        and demo.turns.active_unit_id() == "enemy_1", "real attack across closed hex matches preview and spends one action")
    demo.free()


func test_ai_detour() -> void:
    var demo = fixture("male", true)
    for unit_id in demo.units.keys():
        if unit_id != "ally_1" and unit_id != "enemy_1":
            demo.board.remove_unit(unit_id)
            demo.units.erase(unit_id)
    demo.roster_order.assign(["ally_1", "enemy_1"])
    demo.turns = Turns.new(["ally_1", "enemy_1"])
    demo.turns.turn_index = 1
    check(demo.board.move_unit("enemy_1", Vector2i(5, 3)), "place red beside other side of gate wall")
    var start: Vector2i = demo.board.position_of("enemy_1")
    var hp: int = demo.units["ally_1"].hp
    var old_board = demo.board
    var decision: Dictionary = demo.BattleAI.choose_action(demo.board, demo.units, "enemy_1")
    check(decision.kind == "move", "red AI chooses approach instead of attacking through excessive melee distance")
    var route: Array[Vector2i] = old_board.shortest_path(start, decision.cell, "enemy_1")
    check(route.size() > 1 and route.size() - 1 <= demo.units["enemy_1"].movement,
        "chosen red approach respects actual path budget")
    for cell in route:
        check(not old_board.blocked.has(cell), "AI approach avoids every blocked cell")
    demo.perform_ai_turn()
    check(demo.board.position_of("enemy_1") == decision.cell and demo.board.position_of("enemy_1") != start,
        "AI executor performs legal gate detour")
    check(demo.units["ally_1"].hp == hp and demo.turns.active_unit_id() == "ally_1",
        "red movement does not add an attack and hands turn back to blue")
    var after: Dictionary = state(demo)
    demo.perform_ai_turn()
    check(state(demo) == after, "AI cannot act twice after detour ends turn")
    demo.free()


func run_checks() -> void:
    test_preparation_and_replay()
    test_route_preview_and_action()
    test_route_gates()
    test_existing_flight_and_attack_rules()
    test_ai_detour()
    if failures == 0:
        print("SULEYN arena battle v1.9: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN arena battle v1.9: %d/%d checks FAILED." % [failures, checks])
        quit(1)
