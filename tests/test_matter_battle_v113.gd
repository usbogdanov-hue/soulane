extends SceneTree
## Selected matter sources and books reach native preparation, battle and storage.
const Demo = preload("res://scripts/battle_demo.gd")
const Scene = preload("res://scenes/battle_demo.tscn")
const Setup = preload("res://scripts/battle_setup.gd")
const Build = preload("res://scripts/commander_build.gd")
const Codec = preload("res://scripts/setup_codec.gd")
const Store = preload("res://scripts/setup_store.gd")
const Matter = preload("res://scripts/matter_rules.gd")
const Preview = preload("res://scripts/attack_preview.gd")
const AI = preload("res://scripts/battle_ai.gd")

var checks: int = 0
var failures: int = 0
var paths: Array[String] = []
var prefix: String = "user://test_matter_battle_v113_%d_" % Time.get_ticks_usec()


func _initialize() -> void:
    call_deferred("run_checks")


func check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAILED matter battle v1.13: " + description)


func new_scene(path: String = ""):
    var demo = Scene.instantiate()
    demo.persist_setups = not path.is_empty()
    if not path.is_empty():
        demo.setup_store_path = path
    root.add_child(demo)
    demo.set_process(false)
    return demo


func options(profile: String, nature: int, equipment: Array, book: String) -> Dictionary:
    var result: Dictionary = Build.defaults(Setup.catalog_entry(profile))
    result.class_matter = nature
    result.equipment = equipment.duplicate(true)
    result.book = book
    return result


func select(option: OptionButton, index: int) -> void:
    option.select(index)
    option.item_selected.emit(index)


func start(demo) -> void:
    demo.preparation_ui.next_button.pressed.emit()
    demo.preparation_ui.start_button.pressed.emit()


func code(configuration) -> String:
    return str(Codec.encode(configuration).code)


func battle_state(demo) -> Dictionary:
    var resources: Dictionary = {}
    for unit_id in demo.units:
        var unit = demo.units[unit_id]
        resources[unit_id] = [unit.hp, unit.mp, unit.matter, unit.spell_matter,
            unit.concussion_turns_remaining, unit.mana_regen_fraction]
    return {"accepted": code(demo.team_setup), "units": resources,
        "positions": demo.board.unit_positions.duplicate(true),
        "order": demo.turns.turn_order.duplicate(), "active": demo.turns.active_unit_id(),
        "round": demo.turns.round_number, "spent": demo.turns.action_spent}


func test_native_matter_controls() -> void:
    var demo = new_scene()
    select(demo.preparation_ui.profile_options.ally_3, 5)
    demo.preparation_ui.setup.enemy_ai_enabled = false
    start(demo)
    demo.units.ally_1.receive_damage(19)
    demo.units.ally_1.spend_mana(10)
    demo.open_preparation()
    var before: Dictionary = battle_state(demo)
    var draft: String = code(demo.preparation_ui.setup)
    var original = Setup.catalog_entry("male")
    var defaults: Dictionary = Build.defaults(original)
    seed(113031)
    var expected_random: int = randi()
    seed(113031)
    demo.preparation_ui.configure_buttons.ally_1.pressed.emit()
    var editor = demo.commander_editor
    check(editor.active_tab == "stats" and editor.tab_views.stats.visible
        and not editor.tab_views.matter.visible, "editor opens on the existing stats tab")
    editor.tab_buttons.matter.pressed.emit()
    check(editor.active_tab == "matter" and editor.tab_views.matter.visible
        and not editor.tab_views.stats.visible, "matter tab switches the visible controls")
    check(editor.equipment_checks.size() == 4 and editor.book_option.item_count == 7
        and editor.class_matter_option.item_count == 6, "native selectors offer only existing matter choices")
    select(editor.class_matter_option, Matter.FIRE)
    editor.equipment_checks.water_sword.button_pressed = true
    check(editor.matter_preview_label.text.contains("Ничья")
        and Build.preview(original, editor.options).body_matter == Matter.NEUTRAL,
        "visible equal source counts explain neutral body matter")
    editor.equipment_checks.water_shield.button_pressed = true
    select(editor.book_option, Build.BOOK_KEYS.find("wind"))
    var chosen: Dictionary = options("male", Matter.FIRE, ["water_sword", "water_shield"], "wind")
    check(editor.options == chosen, "native class, item and book signals update the same local descriptor")
    check(editor.matter_preview_label.text.contains("Вода ×2")
        and editor.matter_preview_label.text.contains("Огонь ×1")
        and editor.matter_preview_label.text.contains("Воздух · Книга Ветра"),
        "preview distinguishes body source majority from the independent book")
    editor.tab_buttons.stats.pressed.emit()
    check(editor._ability_label.text.contains("Удар · Книга Ветра")
        and not editor._ability_label.text.contains(original.magic_spell.display_name),
        "ability description follows changed book without retaining the old elemental name")
    check(editor.status_label.text.contains("WIS") and editor.status_label.text.contains("MDEF")
        and editor.status_label.text.contains("регенерацию MP"), "WIS help retains defense and MP regeneration")
    editor.level_spin.value = 1
    check(editor.options.class_matter == Matter.FIRE and editor.options.book == "wind"
        and editor.options.equipment == chosen.equipment, "changing level preserves all matter controls")
    editor.tab_buttons.matter.pressed.emit()
    check(editor.equipment_checks.water_sword.button_pressed
        and editor.equipment_checks.water_shield.button_pressed
        and editor.book_option.selected == Build.BOOK_KEYS.find("wind"),
        "tab switch retains selected sources and book after stats refresh")
    check(code(demo.preparation_ui.setup) == draft and battle_state(demo) == before,
        "editing matter controls changes neither paused battle nor preparation draft")
    check(randi() == expected_random, "tab previews and native matter changes consume no combat RNG")
    editor.cancel_button.pressed.emit()
    demo.open_commander_editor("ally_1")
    check(editor.options == defaults and code(demo.preparation_ui.setup) == draft,
        "Cancel discards every matter choice and reopening starts from the draft")
    editor.tab_buttons.matter.pressed.emit()
    select(editor.class_matter_option, Matter.FIRE)
    editor.equipment_checks.water_sword.button_pressed = true
    editor.equipment_checks.water_shield.button_pressed = true
    select(editor.book_option, Build.BOOK_KEYS.find("wind"))
    editor.apply_button.pressed.emit()
    check(not editor.visible and demo.preparation_ui.setup.current_commander_options("ally_1") == chosen,
        "Apply transfers selected sources and book into only the edited preparation slot")
    check(battle_state(demo) == before, "Apply leaves accepted damaged battle and its queue intact")
    check(demo.preparation_ui.profile_summaries.ally_1.text.contains("Вода")
        and demo.preparation_ui.profile_summaries.ally_1.text.contains("Книга Ветра"),
        "roster summary immediately reports chosen body matter and book")
    start(demo)
    check(demo.units.size() == 5 and demo.units.ally_1.matter == Matter.WATER
        and demo.units.ally_1.spell_matter == Matter.WIND,
        "Start materializes a partial team with independent physical and magic matter")
    check(demo.units.ally_1.spell_power == original.magic_spell.spell_power
        and demo.units.ally_1.spell_mana_cost == original.magic_spell.mana_cost
        and demo.units.ally_1.special_skill == original.special_skill
        and demo.units.ally_1.movement == original.movement,
        "matter controls preserve existing spell cost, power, special and movement")
    demo.reset_demo()
    check(demo.units.ally_1.matter == Matter.WATER and demo.units.ally_1.spell_matter == Matter.WIND
        and demo.units.ally_1.hp == demo.units.ally_1.max_hp, "R repeats chosen matters with fresh HP")
    check(Build.defaults(original) == defaults and original.magic_spell.magic_book == Build.BOOKS.fire,
        "native lifecycle does not mutate the catalog commander or its original book")
    demo.free()


func fixture(actor_options: Dictionary, target_matter: int):
    var setup = Setup.new()
    setup.enemy_ai_enabled = false
    setup.set_profile("enemy_1", "male")
    setup.set_commander_options("ally_1", actor_options)
    setup.set_commander_options("enemy_1", options("male", target_matter, [], "dark"))
    var demo = Demo.new()
    demo.team_setup = setup
    demo.reset_demo()
    demo.enemy_ai_enabled = false
    demo.board.move_unit("enemy_1", Vector2i(2, 1))
    demo.selected_unit_id = "ally_1"
    demo.hovered_cell = Vector2i(2, 1)
    return demo


func test_runtime_interactions() -> void:
    var cases: Array[Dictionary] = [
        {"nature": Matter.FIRE, "items": ["water_sword", "water_shield"], "book": "wind", "target": Matter.WATER,
            "body": Matter.WATER, "pa": -15.0, "pd": 0.0, "ma": 0.0, "md": -15.0},
        {"nature": Matter.FIRE, "items": ["water_sword", "water_shield"], "book": "fire", "target": Matter.FIRE,
            "body": Matter.WATER, "pa": 0.0, "pd": -15.0, "ma": -15.0, "md": 0.0},
        {"nature": Matter.FIRE, "items": ["water_sword"], "book": "water", "target": Matter.FIRE,
            "body": Matter.NEUTRAL, "pa": 0.0, "pd": 0.0, "ma": 0.0, "md": -15.0},
        {"nature": Matter.LIGHT, "items": [], "book": "novice", "target": Matter.DARK,
            "body": Matter.LIGHT, "pa": 0.0, "pd": -15.0, "ma": 0.0, "md": 0.0},
        {"nature": Matter.FIRE, "items": ["fire_sword"], "book": "water", "target": Matter.NEUTRAL,
            "body": Matter.FIRE, "pa": 0.0, "pd": 0.0, "ma": 0.0, "md": 0.0},
    ]
    for row in cases:
        var chosen: Dictionary = options("male", row.nature, row.items, row.book)
        for mode in ["basic", "special", "magic"]:
            var demo = fixture(chosen, row.target)
            demo.set_attack_mode(mode)
            var actor = demo.units.ally_1
            var target = demo.units.enemy_1
            var p: Dictionary = demo.attack_preview_for("enemy_1")
            var magic: bool = mode == "magic"
            check(p.available and actor.matter == row.body
                and p.attack_matter == (Build.BOOKS[row.book].matter if magic else row.body),
                "runtime attack uses selected body or independent book: " + mode)
            check(p.matter_attack_penalty_pct == (row.ma if magic else row.pa)
                and p.matter_defense_penalty_pp == (row.md if magic else row.pd),
                "selected materials reach the existing same/advantage/neutral rules: " + mode)
            var expected_defense: float = target.magic_defense_pct() if magic else target.physical_defense_pct(
                actor.special_skill.damage_type if mode == "special" else actor.melee_damage_type)
            check(is_equal_approx(p.defense_pct, expected_defense + (row.md if magic else row.pd)),
                "advantage changes defense by percentage points only: " + mode)
            var old_hp: int = target.hp
            demo.attack_enemy("ally_1", "enemy_1", 99.0, 99.0, 99.0)
            check(old_hp - target.hp == p.normal_damage and demo.animation_damage == p.normal_damage,
                "real native battle damage matches selected matter preview: " + mode)
            if magic:
                check(not demo.animation_crit and not demo.animation_evaded
                    and p.crit_chance_pct == 0.0 and p.hit_chance_pct == 100.0,
                    "changed book does not introduce magic evasion or critical hits")
                check(p.cost == 10 and p.min_range == 1 and p.max_range == 1
                    and actor.spell_power == 20, "changed book keeps spell power, MP cost and adjacent range")
            demo.free()


func test_ai_scores_and_feedback() -> void:
    var chosen: Dictionary = options("male", Matter.FIRE, ["water_sword", "water_shield"], "wind")
    var demo = fixture(chosen, Matter.WATER)
    var actor = demo.units.ally_1
    var before: Dictionary = battle_state(demo)
    seed(113099)
    var next_random: int = randi()
    seed(113099)
    for attack in AI._attack_options(actor):
        var p: Dictionary = Preview.evaluate(demo.board, demo.units, "ally_1", "enemy_1", attack.mode)
        check(is_equal_approx(AI._expected_damage(actor, demo.units.enemy_1, attack), p.expected_damage),
            "AI scores a materialized selected kit using the same matter outcome as preview: " + attack.mode)
    var first: Dictionary = AI.choose_action(demo.board, demo.units, "ally_1")
    check(first.kind == "attack" and first.target_id == "enemy_1", "AI uses legal adjacent opponent for selected matter kit")
    check(AI.choose_action(demo.board, demo.units, "ally_1") == first,
        "selected sources and book retain deterministic AI choice")
    demo.set_attack_mode("special")
    var text: String = demo.feedback_text()
    check(text.contains("Вода → Вода: −15% к атаке") and text.contains("Контузия"),
        "special feedback includes both same-matter penalty and existing concussion chance")
    check(not text.contains("−-") and not text.contains("−−"), "negative matter penalty is displayed once")
    demo.set_attack_mode("magic")
    text = demo.feedback_text()
    check(text.contains("Воздух → Вода: −15 п.п. защиты цели") and text.contains("Без критов"),
        "magic feedback reports selected book advantage and no critical hits")
    check(randi() == next_random and battle_state(demo) == before,
        "AI and repeated matter feedback remain read-only and RNG-free")
    demo.free()


func test_partial_save_import_restart() -> void:
    var path: String = prefix + "save.json"
    paths.append(path)
    var demo = new_scene(path)
    select(demo.preparation_ui.profile_options.ally_3, 5)
    var male: Dictionary = options("male", Matter.FIRE, ["water_sword", "water_shield"], "light")
    var female: Dictionary = options("female", Matter.DARK, ["fire_sword"], "water")
    for unit_id in ["ally_1", "ally_2"]:
        demo.open_commander_editor(unit_id)
        demo.commander_editor.applied.emit(male if unit_id == "ally_1" else female)
    var chosen: String = code(demo.preparation_ui.setup)
    demo.open_setup_library()
    demo.library_ui.slot_buttons[1].pressed.emit()
    demo.library_ui.name_edit.text = "Материи 2×3"
    demo.library_ui.save_button.pressed.emit()
    demo.library_ui.export_button.pressed.emit()
    var exported: String = demo.library_ui.code_edit.text
    check(exported == chosen and JSON.parse_string(exported).version == 4,
        "native export writes v4 selected matter and books for a partial team")
    demo.close_setup_library()
    start(demo)
    check(demo.units.size() == 5 and demo.units.ally_1.matter == Matter.WATER
        and demo.units.ally_1.spell_matter == Matter.LIGHT
        and demo.units.ally_2.matter == Matter.NEUTRAL and demo.units.ally_2.spell_matter == Matter.WATER,
        "accepted partial battle applies two different independent source/book combinations")
    demo.open_preparation()
    demo.preparation_ui.setup.reset_commander_options("ally_1")
    check(demo.import_setup_code(exported) and code(demo.preparation_ui.setup) == chosen
        and code(demo.team_setup) == chosen, "v4 import restores selected choices into the draft")
    demo.free()
    var restored = new_scene(path)
    check(restored.preparing and code(restored.team_setup) == chosen
        and restored.units.size() == 5 and restored.units.ally_1.spell_matter == Matter.LIGHT,
        "new scene restores last accepted v4 partial composition with selected book")
    restored.open_setup_library()
    check(restored.load_library_slot(1) and code(restored.preparation_ui.setup) == chosen
        and restored.setup_store.list_slots()[1].name == "Материи 2×3",
        "named slot survives fresh store and scene with selected materials intact")
    restored.free()


func test_actual_v3_library_upgrade() -> void:
    var path: String = prefix + "v3.json"
    paths.append(path)
    var setup = Setup.new()
    setup.set_enabled("ally_3", false)
    var male: Dictionary = Build.defaults(Setup.catalog_entry("male"))
    male.merge({"level": 10, "armor": 0, "STR": 10, "AGI": 5, "WIS": 5, "INT": 7}, true)
    var female: Dictionary = Build.defaults(Setup.catalog_entry("female"))
    female.merge({"level": 10, "armor": 2, "STR": 5, "AGI": 10, "WIS": 6, "INT": 6}, true)
    setup.set_commander_options("ally_1", male)
    setup.set_commander_options("ally_2", female)
    var old: Dictionary = Codec.encode(setup).data
    old.version = 3
    for row in old.units:
        if row.commander != null:
            for field in ["class_matter", "equipment", "book"]:
                row.commander.erase(field)
    var file := FileAccess.open(path, FileAccess.WRITE)
    file.store_string(JSON.stringify({"format": "suleyn.library", "version": 1,
        "last_setup": old, "slots": [{"name": "Прежние 2×3", "setup": old}, null, null]}))
    file.close()
    var demo = new_scene(path)
    check(demo.preparing and demo.units.size() == 5
        and demo.team_setup.current_commander_options("ally_1") == male
        and demo.team_setup.current_commander_options("ally_2") == female,
        "actual scene upgrades genuine v3 six-field builds in partial last setup")
    check(demo.units.ally_1.matter == Matter.NEUTRAL and demo.units.ally_1.spell_matter == Matter.FIRE
        and demo.units.ally_2.matter == Matter.NEUTRAL and demo.units.ally_2.spell_matter == Matter.DARK,
        "legacy migration preserves original body and book matter for both warriors")
    demo.open_commander_editor("ally_1")
    var editor = demo.commander_editor
    check(editor.level_spin.value == 10 and editor.options == male,
        "native editor opens migrated allocation without losing level or points")
    editor.tab_buttons.matter.pressed.emit()
    select(editor.class_matter_option, Matter.LIGHT)
    select(editor.book_option, Build.BOOK_KEYS.find("water"))
    editor.apply_button.pressed.emit()
    check(demo.units.ally_1.spell_matter == Matter.FIRE,
        "editing an upgraded v3 preparation still leaves accepted runtime untouched")
    start(demo)
    check(demo.units.ally_1.level == 10 and demo.units.ally_1.matter == Matter.LIGHT
        and demo.units.ally_1.spell_matter == Matter.WATER,
        "Start accepts new source and book while retaining migrated numeric build")
    var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
    check(raw.version == 1 and raw.last_setup.version == 4,
        "autosave upgrades setup payload to v4 inside unchanged library wrapper")
    demo.free()
    var reader = Store.new(path)
    check(reader.load_library().ok and reader.list_slots()[0].name == "Прежние 2×3"
        and reader.slot_setup(0).current_commander_options("ally_1") == male
        and reader.slot_setup(0).current_commander_options("ally_2") == female,
        "new autosave preserves previous named v3 composition and both original books")
    var restored = new_scene(path)
    check(restored.units.ally_1.matter == Matter.LIGHT and restored.units.ally_1.spell_matter == Matter.WATER
        and restored.units.ally_2.spell_matter == Matter.DARK,
        "fresh actual scene restores new v4 matter choices alongside unchanged second warrior")
    restored.free()


func mouse_click(control: Control) -> void:
    var at: Vector2 = control.get_global_rect().get_center()
    var motion := InputEventMouseMotion.new()
    motion.position = at
    motion.global_position = at
    root.push_input(motion, true)
    await process_frame
    var press := InputEventMouseButton.new()
    press.position = at
    press.global_position = at
    press.button_index = MOUSE_BUTTON_LEFT
    press.button_mask = MOUSE_BUTTON_MASK_LEFT
    press.pressed = true
    root.push_input(press, true)
    var release := InputEventMouseButton.new()
    release.position = at
    release.global_position = at
    release.button_index = MOUSE_BUTTON_LEFT
    release.button_mask = 0
    release.pressed = false
    root.push_input(release, true)
    await process_frame


func button_named(parent: Node, text: String) -> Button:
    for button in parent.find_children("*", "Button", true, false):
        if button.text == text:
            return button
    return null


func viewport_key(keycode: int) -> void:
    var press := InputEventKey.new()
    press.keycode = keycode
    press.physical_keycode = keycode
    press.pressed = true
    root.push_input(press)
    await process_frame
    var release := InputEventKey.new()
    release.keycode = keycode
    release.physical_keycode = keycode
    release.pressed = false
    root.push_input(release)
    await process_frame


func preparation_popup_visible(demo) -> bool:
    for option in demo.preparation_ui.profile_options.values():
        if option.get_popup().visible:
            return true
    return demo.preparation_ui.arena_option.get_popup().visible


func test_reopened_modal_mouse_delivery() -> void:
    var demo = new_scene()
    await process_frame
    await mouse_click(demo.preparation_ui.configure_buttons.ally_1)
    var editor = demo.commander_editor
    check(is_instance_valid(editor) and editor.visible,
        "viewport mouse delivery opens the initial commander editor")
    await mouse_click(editor.tab_buttons.matter)
    check(editor.active_tab == "matter", "initial matter tab accepts a real viewport mouse click")
    await mouse_click(editor.cancel_button)
    check(not editor.visible, "initial editor accepts a real Cancel click")
    await mouse_click(button_named(demo.preparation_ui, "Сохранённые составы"))
    var library = demo.library_ui
    check(is_instance_valid(library) and library.visible,
        "viewport mouse delivery opens the initial saved compositions modal")
    await mouse_click(library.close_button)
    check(not library.visible, "initial library accepts a real Close click")
    var old_preparation_id: int = demo.preparation_ui.get_instance_id()
    await mouse_click(demo.preparation_ui.next_button)
    await mouse_click(demo.preparation_ui.start_button)
    check(not demo.preparing, "real preparation button clicks start the battle")
    await viewport_key(KEY_P)
    check(demo.preparing and demo.preparation_ui.get_instance_id() != old_preparation_id,
        "P creates a fresh preparation after both modal instances already exist")
    await mouse_click(demo.preparation_ui.configure_buttons.ally_1)
    check(demo.commander_editor == editor and editor.visible and editor.active_tab == "stats",
        "rebuilt preparation reopens the existing commander modal with real input")
    check(root.gui_get_focus_owner() == editor.tab_buttons.stats,
        "reopened editor moves keyboard focus into its visible controls")
    editor.show_tab("matter")
    await viewport_key(KEY_SPACE)
    check(editor.active_tab == "stats" and not preparation_popup_visible(demo),
        "Space activates focused editor tab rather than underlying preparation controls")
    await mouse_click(editor.tab_buttons.matter)
    check(editor.active_tab == "matter" and not preparation_popup_visible(demo),
        "reopened matter tab receives mouse input without opening an underlying roster dropdown")
    await mouse_click(editor.cancel_button)
    check(not editor.visible and not preparation_popup_visible(demo),
        "reopened editor Cancel receives the click above the rebuilt preparation")
    await mouse_click(button_named(demo.preparation_ui, "Сохранённые составы"))
    check(demo.library_ui == library and library.visible,
        "rebuilt preparation reopens the existing library modal with real input")
    check(root.gui_get_focus_owner() == library.slot_buttons[0],
        "reopened library moves keyboard focus into its first slot")
    library.slot_buttons[1].pressed.emit()
    await viewport_key(KEY_SPACE)
    check(library.selected_slot == 0 and not preparation_popup_visible(demo),
        "Space activates focused library slot rather than underlying preparation controls")
    await mouse_click(library.export_button)
    check(Codec.decode(library.code_edit.text).ok and not preparation_popup_visible(demo),
        "reopened library export button receives the click and produces a valid draft code")
    await mouse_click(library.close_button)
    check(not library.visible and not preparation_popup_visible(demo),
        "reopened library Close receives mouse input above the rebuilt preparation")
    demo.free()


func cleanup() -> void:
    for path in paths:
        for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
            if FileAccess.file_exists(path + suffix):
                DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func run_checks() -> void:
    test_native_matter_controls()
    test_runtime_interactions()
    test_ai_scores_and_feedback()
    test_partial_save_import_restart()
    test_actual_v3_library_upgrade()
    await test_reopened_modal_mouse_delivery()
    cleanup()
    if failures == 0:
        print("SULEYN matter battle v1.13: %d checks passed." % checks)
    else:
        printerr("SULEYN matter battle v1.13: %d / %d checks FAILED." % [failures, checks])
    quit(1 if failures else 0)
