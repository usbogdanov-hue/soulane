extends SceneTree
## Flexible teams through the real scene, native controls and saved-library path.
const Scene = preload("res://scenes/battle_demo.tscn")
const Setup = preload("res://scripts/battle_setup.gd")
const Codec = preload("res://scripts/setup_codec.gd")
const Store = preload("res://scripts/setup_store.gd")

var checks: int = 0
var failures: int = 0
var owned_paths: Array[String] = []
var prefix: String = "user://test_partial_battle_v111_%d_" % Time.get_ticks_usec()


func _initialize() -> void:
    call_deferred("run_checks")


func check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAILED partial battle v1.11: " + description)


func new_scene(path: String = ""):
    var demo = Scene.instantiate()
    demo.persist_setups = not path.is_empty()
    if not path.is_empty():
        demo.setup_store_path = path
    root.add_child(demo)
    demo.set_process(false)
    return demo


func path_for(label: String) -> String:
    var path: String = prefix + label + ".json"
    owned_paths.append(path)
    return path


func choose_empty(demo, id: String) -> void:
    var option: OptionButton = demo.preparation_ui.profile_options[id]
    option.select(5)
    option.item_selected.emit(5)


func choose_counts(demo, blue: int, red: int) -> void:
    for slot in range(1, 4):
        if slot > blue:
            choose_empty(demo, "ally_%d" % slot)
        if slot > red:
            choose_empty(demo, "enemy_%d" % slot)


func start(demo) -> void:
    demo.preparation_ui.next_button.pressed.emit()
    demo.preparation_ui.start_button.pressed.emit()


func code_of(configuration) -> String:
    return "" if configuration == null else str(Codec.encode(configuration).code)


func snapshot(demo) -> Dictionary:
    var resources: Dictionary = {}
    for id in demo.units:
        resources[id] = [demo.units[id].hp, demo.units[id].mp, demo.units[id].concussion_turns_remaining]
    return {"accepted": code_of(demo.team_setup), "resources": resources,
        "positions": demo.board.unit_positions.duplicate(true),
        "order": demo.turns.turn_order.duplicate(), "active": demo.turns.active_unit_id(),
        "round": demo.turns.round_number, "spent": demo.turns.action_spent}


func test_every_size_and_selection() -> void:
    for blue in range(1, 4):
        for red in range(1, 4):
            var demo = new_scene()
            choose_counts(demo, blue, red)
            var ui = demo.preparation_ui
            var expected: Array[String] = ui.setup.unit_ids()
            var tag: String = "%d×%d" % [blue, red]
            check(not ui.next_button.disabled and ui.setup.is_valid(), "native roster accepts " + tag)
            ui.next_button.pressed.emit()
            var visible: int = 0
            for id in ui.unit_buttons:
                if ui.unit_buttons[id].visible:
                    visible += 1
            check(ui.stage == "deployment" and visible == blue + red,
                "deployment exposes only chosen combatants " + tag)
            ui.start_button.pressed.emit()
            check(not demo.preparing and demo.units.size() == blue + red
                and demo.board.unit_positions.size() == blue + red, "runtime has no empty-slot actors " + tag)
            check(demo.turns.turn_order == expected and demo.roster_order == expected
                and demo.turns.active_unit_id() == expected[0], "runtime queue uses chosen blue-first order " + tag)
            check(demo.team_size_caption() == "%d НА %d" % [blue, red], "battle caption matches " + tag)
            var summary: Dictionary = demo.battle_summary()
            check(summary.teams.blue.total == blue and summary.teams.red.total == red
                and summary.units.size() == blue + red, "summary totals use participants " + tag)
            demo.free()

    var gaps = new_scene()
    for id in ["ally_1", "ally_2", "enemy_2"]:
        choose_empty(gaps, id)
    check(gaps.preparation_ui.selected_unit_id == "ally_3", "disabling selected early slots repairs selection")
    start(gaps)
    check(gaps.turns.turn_order == ["ally_3", "enemy_1", "enemy_3"]
        and gaps.turns.active_unit_id() == "ally_3", "gapped slots still start blue and contain no ghosts")
    check(not gaps.units.has("ally_1") and not gaps.units.has("enemy_2")
        and gaps.setup_description(gaps.team_setup).contains("Синие (1):"), "descriptions and runtime omit inactive profiles")
    gaps.free()


func test_empty_team_and_reactivation() -> void:
    var demo = new_scene()
    for id in ["ally_1", "ally_2", "ally_3"]:
        choose_empty(demo, id)
    var ui = demo.preparation_ui
    check(ui.next_button.disabled and not ui.setup.is_valid(), "zero-blue team disables next stage")
    ui.next_button.pressed.emit()
    check(ui.stage == "roster" and not demo.start_prepared_battle() and demo.preparing,
        "signal or direct call cannot start a zero-player battle")
    for id in ["enemy_1", "enemy_2", "enemy_3"]:
        choose_empty(demo, id)
    check(ui.selected_unit_id.is_empty() and ui.setup.unit_ids().is_empty(), "fully empty draft has safe empty selection")
    ui.show_deployment()
    var visible: bool = false
    for button in ui.unit_buttons.values():
        visible = visible or button.visible
    check(not visible and ui.start_button.disabled and not demo.start_prepared_battle(),
        "even forced empty deployment has no selectable ghosts or start")
    ui.show_roster()
    for id in ["ally_3", "enemy_2"]:
        ui.profile_options[id].select(4)
        ui.profile_options[id].item_selected.emit(4)
    check(ui.setup.side_count("blue") == 1 and ui.setup.side_count("red") == 1
        and not ui.next_button.disabled, "choosing a profile reactivates a slot on either side")
    start(demo)
    check(demo.units.size() == 2 and demo.units.has("ally_3") and demo.units.has("enemy_2")
        and demo.turns.active_unit_id() == "ally_3", "repaired nonleading 1×1 starts normally")
    demo.free()


func test_actions_ai_and_concussion() -> void:
    var movement = new_scene()
    choose_counts(movement, 2, 3)
    movement.preparation_ui.setup.enemy_ai_enabled = false
    start(movement)
    check(movement.move_active_unit("ally_1", Vector2i(0, 0)), "2×3 blue actor can move normally")
    check(movement.turns.active_unit_id() == "enemy_1"
        and not movement.move_active_unit("ally_1", Vector2i(0, 1)), "movement spends exactly one turn in an uneven team")
    movement.free()
    for blue in [1, 2]:
        var ai = new_scene()
        choose_counts(ai, blue, 3 if blue == 2 else 2)
        ai.preparation_ui.setup.set_arena("gates")
        start(ai)
        ai.pass_turn()
        var id: String = ai.turns.active_unit_id()
        var before: Vector2i = ai.board.position_of(id)
        var budget: int = ai.units[id].movement
        ai.perform_ai_turn()
        var after: Vector2i = ai.board.position_of(id)
        var path: Array[Vector2i] = ai.board.shortest_path(before, after, id)
        check(before != after and not path.is_empty() and path.size() - 1 <= budget
            and not ai.board.blocked.has(after), "red AI legally navigates partial-team arena " + str(blue))
        check(ai.turns.active_unit_id() != id and ai.units.size() == blue + (3 if blue == 2 else 2),
            "AI performs one action and creates no empty-slot actors " + str(blue))
        ai.free()
    var stunned = new_scene()
    choose_counts(stunned, 1, 2)
    stunned.preparation_ui.setup.enemy_ai_enabled = false
    start(stunned)
    stunned.units["ally_1"].apply_concussion(2)
    stunned.prepare_next_concussion_skip()
    stunned.resolve_one_concussion_skip()
    check(stunned.units["ally_1"].concussion_turns_remaining == 1
        and stunned.turns.active_unit_id() == "enemy_1", "first concussion skip advances to first real opponent")
    stunned.pass_turn()
    check(stunned.turns.active_unit_id() == "enemy_2", "second opponent retains a real turn between own skips")
    stunned.pass_turn()
    check(stunned.concussion_skip_pending and stunned.units["ally_1"].concussion_turns_remaining == 1,
        "return to single blue actor schedules only the second own skip")
    stunned.resolve_one_concussion_skip()
    stunned.pass_turn()
    stunned.pass_turn()
    check(stunned.units["ally_1"].concussion_turns_remaining == 0
        and stunned.can_issue_action("ally_1"), "two own skips finish without phantom queue slots")
    stunned.free()


func test_partial_victories_and_results() -> void:
    var demo = new_scene()
    choose_counts(demo, 1, 2)
    demo.preparation_ui.setup.enemy_ai_enabled = false
    start(demo)
    demo.board.move_unit("enemy_1", Vector2i(2, 1))
    demo.board.move_unit("enemy_2", Vector2i(1, 2))
    demo.units["enemy_1"].hp = 1
    demo.attack_enemy("ally_1", "enemy_1", 99.0, 99.0, 99.0)
    check(not demo.battle_over and not demo.turns.turn_order.has("enemy_1")
        and demo.turns.active_unit_id() == "enemy_2", "1×2 battle continues after only first opponent falls")
    demo.animation_time = demo.ANIMATION_DURATION
    demo.pass_turn()
    demo.units["enemy_2"].hp = 1
    demo.attack_enemy("ally_1", "enemy_2", 99.0, 99.0, 99.0)
    check(demo.battle_over and demo.winner_side == "blue" and demo.results_pending,
        "defeating last actual opponent wins uneven battle")
    var summary: Dictionary = demo.battle_summary()
    check(summary.teams.blue == {"total": 1, "alive": 1, "fallen": 0}
        and summary.teams.red == {"total": 2, "alive": 0, "fallen": 2}, "victory loss totals exclude empty slots")
    demo._process(demo.ANIMATION_DURATION)
    check(demo.results_ui.visible and demo.results_ui.unit_rows.size() == 3,
        "result modal lists exactly the three battle participants")
    demo.results_ui.repeat_button.pressed.emit()
    check(not demo.battle_over and demo.units.size() == 3 and demo.team_size_caption() == "1 НА 2",
        "result repeat preserves uneven accepted composition")
    demo.free()


func test_library_roundtrip_and_legacy() -> void:
    var path: String = path_for("partial")
    var demo = new_scene(path)
    choose_empty(demo, "ally_1")
    demo.preparation_ui.setup.set_arena("gates")
    demo.preparation_ui.setup.enemy_ai_enabled = false
    start(demo)
    check(demo.units.size() == 5 and demo.turns.active_unit_id() == "ally_2", "saved partial setup accepts nonleading 2×3")
    demo.open_preparation()
    var before: Dictionary = snapshot(demo)
    choose_empty(demo, "enemy_2")
    demo.open_setup_library()
    demo.library_ui.name_edit.text = "Два против двух"
    demo.library_ui.save_button.pressed.emit()
    var exported: String = demo.export_setup_code()
    var decoded: Dictionary = Codec.decode(exported)
    check(decoded.ok and decoded.setup.side_count("blue") == 2 and decoded.setup.side_count("red") == 2,
        "native slot/export saves only selected partial-team fighters")
    check(demo.library_ui.slot_buttons[0].text.contains("2×2"), "slot summary displays actual team sizes")
    check(snapshot(demo) == before, "saving/exporting partial draft leaves paused accepted battle unchanged")
    demo.close_setup_library()
    choose_empty(demo, "enemy_3")
    demo.open_setup_library()
    demo.library_ui.load_button.pressed.emit()
    check(not demo.library_ui.visible and code_of(demo.preparation_ui.setup) == exported
        and snapshot(demo) == before, "loading restores partial draft only")
    check(demo.import_setup_code(exported) and snapshot(demo) == before,
        "portable partial code likewise leaves accepted state unchanged")
    start(demo)
    var accepted: String = code_of(demo.team_setup)
    demo.reset_demo()
    check(demo.units.size() == 4 and code_of(demo.team_setup) == accepted, "R keeps partial composition")
    for _index in range(demo.ENCOUNTER_COUNT):
        demo.switch_encounter()
    check(demo.units.size() == 4 and demo.turns.active_unit_id() == "ally_2", "T returns from legacy duels to partial accepted queue")
    demo.open_preparation()
    check(code_of(demo.preparation_ui.setup) == accepted, "P copies all active/empty slot choices")
    demo.free()
    var restored = new_scene(path)
    check(code_of(restored.team_setup) == accepted and restored.units.size() == 4
        and not restored.preparation_ui.setup.is_enabled("ally_1"), "new scene restores partial last setup and inactive first slot")
    check(restored.setup_store.slot_setup(0).unit_ids().size() == 4, "named partial slot survives fresh disk load")
    restored.free()

    var legacy_path: String = path_for("legacy")
    var legacy: Dictionary = Codec.encode(Setup.new()).data
    legacy.version = 1
    var legacy_text: String = JSON.stringify({"format": "suleyn.library", "version": 1,
        "last_setup": legacy, "slots": [{"name": "Старая команда", "setup": legacy}, null, null]})
    var file := FileAccess.open(legacy_path, FileAccess.WRITE)
    file.store_string(legacy_text)
    file.close()
    var migrated = new_scene(legacy_path)
    check(migrated.team_setup.unit_ids().size() == 6 and migrated.setup_store.slot_setup(0).unit_ids().size() == 6,
        "v1.10 outer library and old six-fighter v1 codes still load")
    choose_counts(migrated, 1, 2)
    start(migrated)
    var reader = Store.new(legacy_path)
    check(reader.load_library().ok and reader.last_setup().unit_ids().size() == 3
        and reader.slot_setup(0).unit_ids().size() == 6, "saving new partial last setup preserves the legacy named full-team slot")
    check(Codec.decode(JSON.stringify(legacy)).ok, "original legacy portable code remains importable after new writes")
    migrated.free()


func cleanup() -> void:
    for path in owned_paths:
        for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
            if FileAccess.file_exists(path + suffix):
                DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func run_checks() -> void:
    test_every_size_and_selection()
    test_empty_team_and_reactivation()
    test_actions_ai_and_concussion()
    test_partial_victories_and_results()
    test_library_roundtrip_and_legacy()
    cleanup()
    if failures == 0:
        print("SULEYN partial battle v1.11: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN partial battle v1.11: %d / %d checks FAILED." % [failures, checks])
        quit(1)
