extends SceneTree
## Commander edits through the actual preparation controls and battle lifecycle.
const Scene = preload("res://scenes/battle_demo.tscn")
const Setup = preload("res://scripts/battle_setup.gd")
const Build = preload("res://scripts/commander_build.gd")
const Codec = preload("res://scripts/setup_codec.gd")
const Store = preload("res://scripts/setup_store.gd")

var checks: int = 0
var failures: int = 0
var paths: Array[String] = []
var prefix: String = "user://test_commander_editor_v112_%d_" % Time.get_ticks_usec()


func _initialize() -> void:
    call_deferred("run_checks")


func check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAILED commander editor v1.12: " + description)


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
    paths.append(path)
    return path


func code_of(configuration) -> String:
    return "" if configuration == null else str(Codec.encode(configuration).code)


func start(demo) -> void:
    demo.preparation_ui.next_button.pressed.emit()
    demo.preparation_ui.start_button.pressed.emit()


func key(demo, keycode: int) -> void:
    var event := InputEventKey.new()
    event.pressed = true
    event.keycode = keycode
    demo._unhandled_input(event)


func choose_profile(demo, unit_id: String, index: int) -> void:
    var option: OptionButton = demo.preparation_ui.profile_options[unit_id]
    option.select(index)
    option.item_selected.emit(index)


func snapshot(demo) -> Dictionary:
    var resources: Dictionary = {}
    for unit_id in demo.units:
        var unit = demo.units[unit_id]
        resources[unit_id] = [unit.hp, unit.mp, unit.concussion_turns_remaining,
            unit.max_hp, unit.max_mp, unit.attributes.duplicate(true)]
    return {"accepted": code_of(demo.team_setup), "resources": resources,
        "positions": demo.board.unit_positions.duplicate(true),
        "blocked": demo.board.blocked.duplicate(true), "order": demo.turns.turn_order.duplicate(),
        "active": demo.turns.active_unit_id(), "round": demo.turns.round_number,
        "spent": demo.turns.action_spent, "ai": demo.enemy_ai_enabled,
        "casting": demo.casting_mode, "special": demo.special_mode}


func configured_options() -> Dictionary:
    var options: Dictionary = Build.defaults(Setup.catalog_entry("male"))
    options.merge({"level": 10, "armor": 0, "STR": 10, "AGI": 5, "WIS": 5, "INT": 7}, true)
    return options


func apply_options(demo, unit_id: String, options: Dictionary) -> void:
    demo.preparation_ui.configure_buttons[unit_id].pressed.emit()
    demo.commander_editor.applied.emit(options.duplicate(true))


func check_runtime_matches(unit, preview: Dictionary, description: String) -> void:
    check(unit.max_hp == preview.hp and unit.max_mp == preview.mp,
        description + " HP/MP match commander preview")
    check(unit.attributes == preview.stats,
        description + " primary stats match commander preview")
    check(is_equal_approx(unit.physical_damage_bonus_pct, preview.physical_bonus)
        and is_equal_approx(unit.magic_power_pct, preview.magic_bonus),
        description + " physical/magic bonuses use edited STR/INT")
    check(is_equal_approx(unit.physical_defense_pct(unit.melee_damage_type), preview.pdef)
        and is_equal_approx(unit.magic_defense_pct(), preview.mdef),
        description + " physical/magic defense match edited armor and WIS")
    check(is_equal_approx(unit.final_evasion_pct(), preview.evasion)
        and is_equal_approx(unit.crit_chance_pct, preview.crit),
        description + " evasion and crit match edited AGI and armor")


func test_native_edit_apply_and_independence() -> void:
    var demo = new_scene()
    check(not demo.preparation_ui.configure_buttons["ally_1"].disabled
        and not demo.preparation_ui.configure_buttons["ally_2"].disabled,
        "both warrior profiles expose native configure controls")
    check(demo.preparation_ui.configure_buttons["ally_3"].disabled
        and demo.preparation_ui.configure_buttons["enemy_1"].disabled,
        "monster profiles do not expose editable commander settings")
    choose_profile(demo, "ally_2", 0)
    choose_profile(demo, "ally_3", 5)
    demo.preparation_ui.setup.enemy_ai_enabled = false
    start(demo)
    demo.units["ally_1"].receive_damage(23)
    demo.units["ally_1"].spend_mana(10)
    demo.open_preparation()
    var before: Dictionary = snapshot(demo)
    var draft_before: String = code_of(demo.preparation_ui.setup)
    var original = Setup.catalog_entry("male")
    var catalog_before: Dictionary = Build.defaults(original)
    seed(121201)
    var next_random: int = randi()
    seed(121201)
    demo.preparation_ui.configure_buttons["ally_1"].pressed.emit()
    var editor = demo.commander_editor
    check(editor.visible and demo.editing_commander_id == "ally_1",
        "native configure signal opens the selected warrior editor")
    editor.level_spin.value = 10
    editor.armor_option.select(0)
    editor.armor_option.item_selected.emit(0)
    editor.point_spins.STR.value = 10
    editor.point_spins.AGI.value = 5
    editor.point_spins.WIS.value = 5
    editor.point_spins.INT.value = 7
    var expected: Dictionary = configured_options()
    check(editor.options == expected and not editor.apply_button.disabled,
        "level, armor and point control signals create the requested valid build")
    var preview: Dictionary = Build.preview(original, expected)
    check(editor.preview_label.text.contains("HP %d" % preview.hp)
        and editor.preview_label.text.contains("MP %d" % preview.mp),
        "visible preview reports derived edited HP and MP")
    check(editor.remaining_label.text.contains("0")
        and editor.point_spins.AGI.max_value == expected.AGI,
        "fully allocated budget has no additional AGI available")
    check(code_of(demo.preparation_ui.setup) == draft_before and snapshot(demo) == before,
        "editing controls changes neither preparation nor paused accepted battle")
    check(randi() == next_random, "editor preview and controls consume no combat RNG")
    editor.apply_button.pressed.emit()
    check(not editor.visible and demo.preparation_ui.setup.current_commander_options("ally_1") == expected,
        "Apply transfers the editor-local copy into its preparation slot")
    check(snapshot(demo) == before,
        "Apply leaves accepted setup, damaged runtime, queue and modes untouched")
    check(demo.preparation_ui.setup.profile_stats("ally_2") == original
        and not demo.preparation_ui.setup.commander_options.has("ally_2"),
        "a second identical warrior slot retains the original independent preset")
    check(Build.defaults(original) == catalog_before,
        "catalog commander resource remains unchanged after edit and Apply")
    check(demo.preparation_ui.profile_summaries["ally_1"].text.contains(str(preview.hp)),
        "roster summary refreshes to the edited commander's derived HP")
    demo.preparation_ui.next_button.pressed.emit()
    check(code_of(demo.team_setup) == before.accepted,
        "deployment preview still does not commit the edited preparation")
    demo.preparation_ui.start_button.pressed.emit()
    check_runtime_matches(demo.units["ally_1"], preview, "configured male")
    check(demo.units["ally_2"].max_hp == original.commander.max_hp()
        and demo.units["ally_2"].max_hp != demo.units["ally_1"].max_hp,
        "fresh battle creates different independent runtime states for duplicate profiles")
    check(demo.units["ally_1"].movement == original.movement
        and demo.units["ally_1"].melee_skill_power == original.melee_skill.skill_power
        and demo.units["ally_1"].special_skill == original.special_skill
        and demo.units["ally_1"].spell_power == original.magic_spell.spell_power,
        "level and armor edits grant no movement, weapon, special or spell changes")
    check(demo.units["ally_1"].matter == original.commander.resolved_matter()
        and demo.units["ally_1"].spell_matter == original.magic_spell.magic_book.matter,
        "physical matter and spell-book matter stay independent and unchanged")
    demo.free()


func test_cancel_modal_limits_and_profile_changes() -> void:
    var demo = new_scene()
    var draft = demo.preparation_ui.setup
    var before: Dictionary = snapshot(demo)
    var untouched: String = code_of(draft)
    demo.open_commander_editor("ally_3")
    check(not is_instance_valid(demo.commander_editor), "monster cannot open commander editor through root API")
    choose_profile(demo, "ally_1", 5)
    check(demo.preparation_ui.configure_buttons["ally_1"].disabled,
        "empty slot has a disabled configure control")
    demo.open_commander_editor("ally_1")
    check(not is_instance_valid(demo.commander_editor), "empty slot cannot open editor through root API")
    choose_profile(demo, "ally_1", 0)
    untouched = code_of(draft)
    demo.open_commander_editor("ally_1")
    var editor = demo.commander_editor
    for keycode in [KEY_R, KEY_T, KEY_P, KEY_1, KEY_2, KEY_F, KEY_A, KEY_SPACE]:
        key(demo, keycode)
    check(editor.visible and code_of(draft) == untouched and snapshot(demo) == before,
        "editor modal blocks battle and preparation hotkeys without spending state")
    demo.open_setup_library()
    check(not is_instance_valid(demo.library_ui), "editor prevents opening a nested library")
    demo.preparation_ui.show_deployment()
    check(not demo.start_prepared_battle() and demo.preparing and editor.visible,
        "direct battle start is rejected while commander editor is open")
    demo.preparation_ui.show_roster()
    editor.level_spin.value = 1
    check(editor.options.level == 1 and editor.options.STR == 0 and editor.options.AGI == 0
        and editor.options.WIS == 0 and editor.options.INT == 0,
        "lowering level trims all earned allocation at level one")
    check(editor.point_spins.STR.max_value == 0 and editor.point_spins.INT.max_value == 0,
        "no earned attribute points can be allocated at level one")
    editor.level_spin.value = 999
    editor.point_spins.STR.value = 99999
    editor.point_spins.INT.value = 99999
    var cap_preview: Dictionary = Build.preview(Setup.catalog_entry("male"), editor.options)
    check(cap_preview.stats.STR == 45 and cap_preview.stats.INT == 45
        and Build.validate(Setup.catalog_entry("male"), editor.options).ok,
        "native spin controls enforce STR/INT caps even with a large level budget")
    editor.reset_button.pressed.emit()
    check(editor.options == Build.defaults(Setup.catalog_entry("male"))
        and code_of(draft) == untouched,
        "reset restores the editor-local preset without applying it to preparation")
    editor.level_spin.value = 1
    editor.cancel_button.pressed.emit()
    check(not editor.visible and code_of(draft) == untouched,
        "Cancel discards local level and allocation edits")
    demo.open_commander_editor("ally_1")
    editor.level_spin.value = 1
    key(demo, KEY_ESCAPE)
    check(not editor.visible and code_of(draft) == untouched,
        "Escape also discards editor edits")
    apply_options(demo, "ally_1", configured_options())
    choose_profile(demo, "ally_1", 5)
    check(draft.commander_options.has("ally_1"),
        "temporarily disabling a slot keeps its edited build in this draft")
    choose_profile(demo, "ally_1", 0)
    check(draft.current_commander_options("ally_1") == configured_options(),
        "re-enabling the same profile restores that slot's build")
    choose_profile(demo, "ally_1", 1)
    check(not draft.commander_options.has("ally_1")
        and draft.profile_stats("ally_1") == Setup.catalog_entry("female"),
        "choosing a different profile clears the previous warrior override")
    demo.open_setup_library()
    demo.open_commander_editor("ally_1")
    check(not editor.visible and demo.library_ui.visible,
        "library modal also prevents opening a nested commander editor")
    demo.close_setup_library()
    demo.free()


func test_partial_save_restore_and_female_kit() -> void:
    var path: String = path_for("roundtrip")
    var demo = new_scene(path)
    choose_profile(demo, "ally_3", 5)
    demo.preparation_ui.setup.set_arena("gates")
    demo.preparation_ui.setup.place_unit("ally_1", Vector2i(0, 0))
    var male: Dictionary = configured_options()
    var female: Dictionary = Build.defaults(Setup.catalog_entry("female"))
    female.merge({"level": 10, "armor": 2, "STR": 5, "AGI": 10, "WIS": 6, "INT": 6}, true)
    apply_options(demo, "ally_1", male)
    apply_options(demo, "ally_2", female)
    var chosen: String = code_of(demo.preparation_ui.setup)
    demo.open_setup_library()
    demo.library_ui.slot_buttons[2].pressed.emit()
    demo.library_ui.name_edit.text = "Настроенные 2×3"
    demo.library_ui.save_button.pressed.emit()
    var stored = demo.setup_store.slot_setup(2)
    check(stored != null and stored.unit_ids().size() == 5
        and stored.current_commander_options("ally_1") == male
        and stored.current_commander_options("ally_2") == female,
        "native Save stores both private commander builds in a partial named composition")
    demo.library_ui.export_button.pressed.emit()
    var exported: String = demo.library_ui.code_edit.text
    check(Codec.decode(exported).ok and exported == chosen,
        "native export includes both edited builds in the current partial draft")
    demo.close_setup_library()
    start(demo)
    var female_base = Setup.catalog_entry("female")
    check_runtime_matches(demo.units["ally_2"], Build.preview(female_base, female), "configured female")
    check(demo.units["ally_2"].critical_multiplier == 2.0
        and demo.units["ally_2"].special_skill == female_base.special_skill
        and demo.units["ally_2"].spell_matter == female_base.magic_spell.magic_book.matter
        and demo.units["ally_2"].spell_power == female_base.magic_spell.spell_power,
        "edited female keeps x2 physical critical passive, special and original spell book")
    check(demo.units.size() == 5 and code_of(demo.team_setup) == chosen,
        "Start commits both edited builds and only selected combatants")
    demo.units["ally_1"].receive_damage(100)
    demo.reset_demo()
    check(demo.units["ally_1"].hp == demo.units["ally_1"].max_hp
        and demo.units["ally_1"].max_hp == Build.preview(Setup.catalog_entry("male"), male).hp,
        "R restores full runtime HP while preserving the edited build")
    for index in range(demo.ENCOUNTER_COUNT):
        demo.switch_encounter()
    check(demo.encounter_index == demo.TEAM_ENCOUNTER and demo.units.size() == 5
        and code_of(demo.team_setup) == chosen,
        "T through every legacy duel returns the same edited partial team")
    demo.open_preparation()
    check(code_of(demo.preparation_ui.setup) == chosen,
        "P copies edited builds into a new independent preparation draft")
    var accepted: String = code_of(demo.team_setup)
    demo.preparation_ui.setup.reset_commander_options("ally_1")
    check(demo.import_setup_code(exported) and code_of(demo.preparation_ui.setup) == chosen
        and code_of(demo.team_setup) == accepted,
        "portable import restores custom options in the draft without replacing accepted configuration")
    demo.free()
    var restored = new_scene(path)
    check(restored.preparing and code_of(restored.team_setup) == chosen
        and restored.preparation_ui.setup.current_commander_options("ally_1") == male,
        "new actual scene restores last accepted edited setup from isolated disk storage")
    check_runtime_matches(restored.units["ally_2"], Build.preview(female_base, female), "restored female")
    restored.open_setup_library()
    check(restored.load_library_slot(2)
        and code_of(restored.preparation_ui.setup) == chosen,
        "named edited partial slot survives a new store and scene instance")
    var returned: Dictionary = restored.preparation_ui.setup.current_commander_options("ally_2")
    returned.armor = 0
    check(restored.team_setup.current_commander_options("ally_2").armor == 2,
        "editing a returned draft dictionary cannot mutate the accepted female build")
    restored.free()


func test_legacy_library_migration() -> void:
    var path: String = path_for("legacy")
    var legacy: Dictionary = Codec.encode(Setup.new()).data
    legacy.version = 2
    for row in legacy.units:
        row.erase("commander")
    var original_code: String = JSON.stringify(legacy)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(JSON.stringify({"format": "suleyn.library", "version": 1,
        "last_setup": legacy, "slots": [{"name": "До редактора", "setup": legacy}, null, null]}))
    file.close()
    var demo = new_scene(path)
    check(demo.team_setup.commander_options.is_empty()
        and demo.setup_store.slot_setup(0).commander_options.is_empty()
        and demo.team_setup.profile_stats("ally_1") == Setup.catalog_entry("male"),
        "legacy v2 preparation and slot retain unchanged catalog presets")
    apply_options(demo, "ally_1", configured_options())
    start(demo)
    var reader = Store.new(path)
    check(reader.load_library().ok
        and reader.last_setup().current_commander_options("ally_1") == configured_options(),
        "a new last setup is readable after updating a legacy library")
    check(reader.slot_setup(0).commander_options.is_empty()
        and reader.slot_setup(0).profile_stats("ally_1") == Setup.catalog_entry("male")
        and Codec.decode(original_code).ok,
        "saving edited last setup preserves old named presets and old portable codes")
    demo.free()


func cleanup() -> void:
    for path in paths:
        for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
            if FileAccess.file_exists(path + suffix):
                DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func run_checks() -> void:
    test_native_edit_apply_and_independence()
    test_cancel_modal_limits_and_profile_changes()
    test_partial_save_restore_and_female_kit()
    test_legacy_library_migration()
    cleanup()
    if failures == 0:
        print("SULEYN commander editor v1.12: %d checks passed." % checks)
    else:
        printerr("SULEYN commander editor v1.12: %d / %d checks FAILED." % [failures, checks])
    quit(1 if failures else 0)
