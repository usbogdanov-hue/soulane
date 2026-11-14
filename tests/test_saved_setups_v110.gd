extends SceneTree
## Saved preparation through the actual scene, controls and fresh storage reads.
const Scene = preload("res://scenes/battle_demo.tscn")
const Setup = preload("res://scripts/battle_setup.gd")
const Codec = preload("res://scripts/setup_codec.gd")
const Store = preload("res://scripts/setup_store.gd")

var checks: int = 0
var failures: int = 0
var owned_paths: Array[String] = []
var prefix: String = "user://test_saved_setups_v110_%d_" % Time.get_ticks_usec()


func _initialize() -> void:
    call_deferred("run_checks")


func check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAILED saved setups v1.10: " + description)


func path_for(label: String) -> String:
    var path: String = prefix + label + ".json"
    owned_paths.append(path)
    return path


func new_scene(path: String):
    var demo = Scene.instantiate()
    demo.setup_store_path = path
    demo.persist_setups = true
    root.add_child(demo)
    demo.set_process(false)
    return demo


func custom_draft(demo) -> void:
    var draft = demo.preparation_ui.setup
    draft.set_arena("gates")
    draft.set_profile("ally_1", "lich")
    draft.set_profile("enemy_3", "female")
    draft.enemy_ai_enabled = false
    draft.place_unit("ally_1", Vector2i(0, 0))
    draft.place_unit("enemy_3", Vector2i(8, 6))


func start(demo) -> void:
    demo.preparation_ui.next_button.pressed.emit()
    demo.preparation_ui.start_button.pressed.emit()


func code_of(configuration) -> String:
    return "" if configuration == null else str(Codec.encode(configuration).code)


func runtime_state(demo) -> Dictionary:
    var resources: Dictionary = {}
    for unit_id in demo.units:
        var unit = demo.units[unit_id]
        resources[unit_id] = [unit.hp, unit.mp, unit.concussion_turns_remaining]
    return {"accepted": code_of(demo.team_setup), "resources": resources,
        "positions": demo.board.unit_positions.duplicate(true),
        "blocked": demo.board.blocked.duplicate(true), "active": demo.turns.active_unit_id(),
        "round": demo.turns.round_number, "spent": demo.turns.action_spent,
        "over": demo.battle_over, "winner": demo.winner_side,
        "encounter": demo.encounter_index, "ai": demo.enemy_ai_enabled}


func key(demo, keycode: int) -> void:
    var event := InputEventKey.new()
    event.pressed = true
    event.keycode = keycode
    demo._unhandled_input(event)


func read_text(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    var text: String = file.get_as_text()
    file.close()
    return text


func test_autosave_and_restart() -> void:
    var path: String = path_for("restart")
    var demo = new_scene(path)
    check(demo.persist_setups and demo.preparing and demo.storage_ready,
        "actual scene enables persistence and loads a missing library as empty")
    check(demo.team_setup == null and not FileAccess.file_exists(path),
        "opening preparation does not save an unaccepted draft")
    custom_draft(demo)
    var expected: String = code_of(demo.preparation_ui.setup)
    start(demo)
    check(not demo.preparing and code_of(demo.team_setup) == expected,
        "start accepts custom team, arena, control preference and positions")
    check(FileAccess.file_exists(path) and demo.setup_store.last_setup() != null,
        "successful start persists accepted setup")
    var reader = Store.new(path)
    check(reader.load_library().ok and code_of(reader.last_setup()) == expected,
        "fresh storage instance reads exact accepted setup from disk")
    demo.units["ally_1"].receive_damage(80)
    demo.units["ally_1"].spend_mana(20)
    demo.units["ally_1"].apply_concussion(2)
    demo.board.move_unit("ally_1", Vector2i(1, 0))
    demo.free()
    var restored = new_scene(path)
    check(restored.preparing and code_of(restored.preparation_ui.setup) == expected,
        "fresh actual scene restores last accepted setup into preparation")
    check(code_of(restored.team_setup) == expected and not restored.enemy_ai_enabled,
        "restored accepted setup and red control preference match the saved selection")
    check(restored.board.position_of("ally_1") == Vector2i(0, 0)
        and restored.units["ally_1"].hp == restored.units["ally_1"].max_hp
        and restored.units["ally_1"].mp == restored.units["ally_1"].max_mp
        and restored.units["ally_1"].concussion_turns_remaining == 0,
        "restore starts fresh units and deployment, never live battle HP, MP or concussion")
    check(restored.preparation_ui.roster_status_label.text.contains("Восстановлен"),
        "startup visibly explains restored accepted configuration")
    restored.preparation_ui.setup.set_arena("pillars")
    restored.free()
    var unaccepted = new_scene(path)
    check(unaccepted.preparation_ui.setup.arena_key == "gates",
        "closing with an unaccepted draft does not replace the last accepted setup")
    unaccepted.free()


func test_native_library_and_draft_only_load() -> void:
    var path: String = path_for("slots")
    var demo = new_scene(path)
    custom_draft(demo)
    start(demo)
    demo.units["ally_1"].receive_damage(17)
    demo.open_preparation()
    var accepted_before: Dictionary = runtime_state(demo)
    var draft = demo.preparation_ui.setup
    draft.set_arena("pillars")
    draft.set_profile("ally_2", "hellhound")
    var saved_code: String = code_of(draft)
    demo.preparation_ui.library_requested.emit()
    var ui = demo.library_ui
    check(ui.visible and ui.slot_buttons.size() == 3 and ui.load_button.disabled,
        "preparation signal opens three slots and disables loading an empty slot")
    ui.name_edit.text = "Колонны с гончей"
    ui.save_button.pressed.emit()
    check(ui.slot_buttons[0].text.contains("Колонны с гончей") and not ui.load_button.disabled,
        "save control refreshes selected named slot and available load action")
    check(demo.setup_store.list_slots()[0].name == "Колонны с гончей"
        and code_of(demo.setup_store.slot_setup(0)) == saved_code,
        "slot save stores an independent exact draft")
    check(runtime_state(demo) == accepted_before,
        "saving a draft does not change accepted setup or paused battle state")
    var reader = Store.new(path)
    check(reader.load_library().ok and code_of(reader.slot_setup(0)) == saved_code,
        "named slot survives a separate disk read")
    var file_before: String = read_text(path)
    ui.name_edit.text = ""
    ui.save_button.pressed.emit()
    check(read_text(path) == file_before and ui.status_label.text.contains("Название"),
        "invalid slot name reports failure and preserves stored bytes")
    ui.slot_buttons[2].pressed.emit()
    ui.name_edit.text = "Третий слот"
    ui.save_button.pressed.emit()
    check(demo.setup_store.list_slots()[2].name == "Третий слот"
        and demo.setup_store.list_slots()[1].occupied == false,
        "slot button selects the requested slot without changing other slots")
    ui.delete_button.pressed.emit()
    check(demo.setup_store.list_slots()[2].occupied and ui.delete_button.text.contains("Подтвердить"),
        "first delete click requires confirmation and preserves data")
    ui.slot_buttons[0].pressed.emit()
    ui.slot_buttons[2].pressed.emit()
    ui.delete_button.pressed.emit()
    check(demo.setup_store.list_slots()[2].occupied,
        "changing selected slot cancels an earlier delete confirmation")
    ui.delete_button.pressed.emit()
    check(not demo.setup_store.list_slots()[2].occupied and ui.load_button.disabled,
        "confirmed delete clears only the selected slot and refreshes actions")
    demo.close_setup_library()
    draft.set_arena("open")
    draft.set_profile("ally_2", "female")
    demo.open_setup_library()
    demo.library_ui.load_button.pressed.emit()
    check(not demo.library_ui.visible and demo.preparation_ui.stage == "roster"
        and code_of(demo.preparation_ui.setup) == saved_code,
        "load button closes modal and replaces only the editable roster draft")
    check(runtime_state(demo) == accepted_before,
        "loading a named slot leaves accepted setup and paused runtime untouched")
    demo.preparation_ui.next_button.pressed.emit()
    check(code_of(demo.team_setup) == accepted_before.accepted
        and demo.preparation_ui.setup.arena_key == "pillars",
        "deployment preview of loaded draft still does not replace accepted setup")
    demo.preparation_ui.start_button.pressed.emit()
    check(code_of(demo.team_setup) == saved_code and demo.board.blocked.size() == 4
        and demo.units["ally_2"].is_monster,
        "Start applies loaded arena and combatants to a fresh battle")
    demo.free()


func test_code_and_modal_guards() -> void:
    var path: String = path_for("code")
    var demo = new_scene(path)
    custom_draft(demo)
    start(demo)
    demo.open_preparation()
    demo.preparation_ui.setup.set_arena("pillars")
    demo.open_setup_library()
    var ui = demo.library_ui
    var before: Dictionary = runtime_state(demo)
    var draft_before: String = code_of(demo.preparation_ui.setup)
    var rng_before: int = seed_snapshot()
    ui.export_button.pressed.emit()
    var exported: String = ui.code_edit.text
    check(Codec.decode(exported).ok and exported == draft_before,
        "export control places a complete portable code for the current draft")
    check(runtime_state(demo) == before and code_of(demo.preparation_ui.setup) == draft_before,
        "export does not mutate accepted battle or draft")
    check(randi() == rng_before, "export does not consume combat RNG")
    for keycode in [KEY_R, KEY_T, KEY_P, KEY_1, KEY_SPACE, KEY_A]:
        key(demo, keycode)
    check(runtime_state(demo) == before and ui.visible
        and code_of(demo.preparation_ui.setup) == draft_before,
        "modal blocks battle and preparation hotkeys without changing state")
    demo.preparation_ui.show_deployment()
    check(not demo.start_prepared_battle() and demo.preparing and ui.visible,
        "even deployment cannot start a battle while library modal is open")
    ui.code_edit.text = "{неполный код"
    ui.import_button.pressed.emit()
    check(ui.visible and runtime_state(demo) == before
        and code_of(demo.preparation_ui.setup) == draft_before,
        "invalid imported text leaves draft and accepted battle unchanged")
    check(ui.status_label.text.contains("повреждён"),
        "invalid imported text produces a visible validation reason")
    var mismatched = Setup.new(7, 5)
    var other_code: String = code_of(mismatched)
    check(not other_code.is_empty() and not demo.import_setup_code(other_code),
        "valid portable setup for a different field is rejected by scene")
    check(code_of(demo.preparation_ui.setup) == draft_before and ui.visible
        and ui.status_label.text.contains("Размер поля"),
        "different field rejection preserves draft and explains scene size")
    key(demo, KEY_ESCAPE)
    check(not ui.visible and demo.preparing, "Escape closes library without starting or changing battle")
    demo.preparation_ui.show_roster()
    demo.preparation_ui.setup.set_arena("open")
    demo.open_setup_library()
    demo.library_ui.code_edit.text = exported
    demo.library_ui.import_button.pressed.emit()
    check(not demo.library_ui.visible and demo.preparation_ui.stage == "roster"
        and code_of(demo.preparation_ui.setup) == draft_before,
        "valid import control replaces draft and returns to roster")
    check(runtime_state(demo) == before, "valid import still leaves accepted battle and resources unchanged")
    demo.preparation_ui.next_button.pressed.emit()
    demo.preparation_ui.start_button.pressed.emit()
    check(demo.team_setup.arena_key == "pillars" and not demo.preparing,
        "Start separately accepts valid imported draft")
    check(demo.export_setup_code().is_empty() and not demo.import_setup_code(exported),
        "code transfer APIs do not alter an active battle")
    demo.reset_demo()
    check(demo.team_setup.arena_key == "pillars"
        and demo.board.position_of("ally_1") == Vector2i(0, 0),
        "usual repeat retains imported accepted configuration")
    demo.free()


func seed_snapshot() -> int:
    seed(55110)
    var expected: int = randi()
    seed(55110)
    return expected


func test_unavailable_storage_and_corruption() -> void:
    var missing_parent: String = prefix + "missing_parent/library.json"
    var demo = new_scene(missing_parent)
    custom_draft(demo)
    start(demo)
    check(not demo.preparing and demo.units.size() == 6 and demo.team_setup.arena_key == "gates",
        "a write failure does not prevent playing the accepted setup")
    check(demo.storage_notice.contains("не сохранён") and demo.message == demo.storage_notice,
        "write failure is reported rather than claiming successful persistence")
    check(not FileAccess.file_exists(missing_parent), "failed write does not create a partial accepted save")
    demo.open_preparation()
    demo.open_setup_library()
    demo.library_ui.name_edit.text = "Не записывается"
    demo.library_ui.save_button.pressed.emit()
    check(not demo.setup_store.list_slots()[0].occupied
        and demo.library_ui.status_label.text.contains("Не удалось"),
        "named slot failure keeps library empty and reports error")
    check(not demo.export_setup_code().is_empty(), "portable transfer remains available when disk writes fail")
    demo.free()
    var path: String = path_for("corrupt")
    var corrupt: String = "{damaged-library"
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(corrupt)
    file.close()
    var broken = new_scene(path)
    check(broken.preparing and not broken.storage_ready and broken.team_setup == null,
        "corrupt library starts a usable default draft without false restoration")
    check(broken.preparation_ui.roster_status_label.text.contains("Не удалось"),
        "startup read failure is visible in preparation")
    broken.open_setup_library()
    broken.library_ui.name_edit.text = "Новый черновик"
    broken.library_ui.save_button.pressed.emit()
    check(read_text(path) == corrupt and not broken.setup_store.list_slots()[0].occupied,
        "saving after a corrupt read cannot silently overwrite unknown stored data")
    var code: String = broken.export_setup_code()
    check(Codec.decode(code).ok, "corrupt storage still permits exporting valid current draft")
    broken.close_setup_library()
    start(broken)
    check(not broken.preparing and read_text(path) == corrupt
        and broken.storage_notice.contains("не сохранён"),
        "accepted battle can start while corrupt persisted bytes remain protected")
    broken.free()


func cleanup() -> void:
    for path in owned_paths:
        for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
            var full_path: String = path + suffix
            if FileAccess.file_exists(full_path):
                DirAccess.remove_absolute(ProjectSettings.globalize_path(full_path))


func run_checks() -> void:
    test_autosave_and_restart()
    test_native_library_and_draft_only_load()
    test_code_and_modal_guards()
    test_unavailable_storage_and_corruption()
    cleanup()
    if failures == 0:
        print("SULEYN saved setups v1.10: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN saved setups v1.10: %d/%d checks FAILED." % [failures, checks])
        quit(1)
