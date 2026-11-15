extends SceneTree
## Approved growth reaches runtime, current preparation and four-class formulas.
## Mage resources below are formula fixtures, not new playable spell/weapon kits.
const Profile = preload("res://scripts/commander_profile.gd")
const Build = preload("res://scripts/commander_build.gd")
const Growth = preload("res://scripts/commander_growth.gd")
const Demo = preload("res://scripts/battle_demo.gd")
const Scene = preload("res://scenes/battle_demo.tscn")
const Setup = preload("res://scripts/battle_setup.gd")
const Codec = preload("res://scripts/setup_codec.gd")
const Matter = preload("res://scripts/matter_rules.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
    call_deferred("run_checks")

func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED auto growth battle v1.15: " + label)

func stats_for(archetype: int, level: int, armor: int):
    var stats = Setup.catalog_entry("female" if archetype == 1 else "male").duplicate(false)
    var profile = Profile.new()
    profile.archetype = archetype
    profile.level = level
    profile.armor_type = armor
    stats.commander = profile
    stats.melee_skill = null
    stats.special_skill = null
    stats.magic_spell = null
    return stats

func test_four_level30_profiles() -> void:
    var cases: Array[Dictionary] = [
        {"archetype":0,"armor":3,"attributes":{"STR":53,"AGI":34,"WIS":13,"INT":15},
            "hp":975,"mp":183,"pdef":[40.0,30.0,20.0],"mdef":13.0,"evade":7.0,"crit":17.0,"mult":1.5,"regen":3.9,"first":7},
        {"archetype":1,"armor":2,"attributes":{"STR":34,"AGI":45,"WIS":23,"INT":13},
            "hp":755,"mp":178,"pdef":[20.0,10.0,20.0],"mdef":33.0,"evade":22.5,"crit":22.5,"mult":1.5,"regen":6.9,"first":12},
        {"archetype":4,"armor":1,"attributes":{"STR":14,"AGI":14,"WIS":34,"INT":53},
            "hp":435,"mp":423,"pdef":[0.0,0.0,0.0],"mdef":54.0,"evade":17.0,"crit":7.0,"mult":1.5,"regen":10.2,"first":43},
        {"archetype":5,"armor":1,"attributes":{"STR":13,"AGI":15,"WIS":53,"INT":34},
            "hp":410,"mp":333,"pdef":[0.0,0.0,0.0],"mdef":73.0,"evade":17.5,"crit":7.5,"mult":1.5,"regen":15.9,"first":52},
    ]
    var demo = Demo.new()
    for row in cases:
        var stats = stats_for(row.archetype, 30, row.armor)
        var descriptor: Dictionary = Build.defaults(stats)
        var preview: Dictionary = Build.preview(stats, descriptor)
        var unit = demo.make_unit("fixture", "blue", Build.materialize(stats, descriptor))
        var profile = stats.commander
        var label: String = "archetype " + str(row.archetype)
        check(profile.critical_passive == null and stats.melee_skill == null
            and stats.special_skill == null and stats.magic_spell == null
            and unit.special_skill == null and unit.spell_power == 0,
            "baseline comparison contains no active skills or passives: " + label)
        check(profile.primary_stats() == row.attributes and unit.attributes == row.attributes and preview.stats == row.attributes,
            "level30 attributes agree across profile, preview and runtime: " + label)
        check(profile.points_earned() == 87 and profile.points_spent() == 87 and profile.points_unspent() == 0,
            "all 87 earned points are distributed above the base: " + label)
        check(unit.max_hp == row.hp and profile.max_hp() == row.hp and preview.hp == row.hp,
            "HP retains base +5 per level and +10 per total STR: " + label)
        check(unit.max_mp == row.mp and profile.max_mp() == row.mp and preview.mp == row.mp,
            "MP retains base +2 per level and +5 per total INT: " + label)
        check(unit.physical_damage_bonus_pct == row.attributes.STR and preview.physical_bonus == row.attributes.STR,
            "physical damage bonus is one percent per STR: " + label)
        check(unit.magic_power_pct == row.attributes.INT and preview.magic_bonus == row.attributes.INT,
            "magic damage bonus is one percent per INT: " + label)
        check(is_equal_approx(unit.final_evasion_pct(), row.evade) and is_equal_approx(preview.evasion, row.evade),
            "armor modifies the existing AGI evasion formula: " + label)
        check(unit.crit_chance_pct == row.crit and unit.critical_multiplier == row.mult,
            "physical crit uses AGI chance and universal baseline multiplier without passives: " + label)
        check(unit.physical_defense_pct(0) == row.pdef[0] and unit.physical_defense_pct(1) == row.pdef[1]
            and unit.physical_defense_pct(2) == row.pdef[2], "armor defenses remain type specific: " + label)
        check(unit.physical_resistance_pct == 0.0 and unit.base_pdef_pct == 0.0 and unit.base_mdef_pct == 0.0,
            "AGI adds no physical resistance and commander base defenses remain zero: " + label)
        check(unit.magic_resistance_pct == row.attributes.WIS and profile.get("magic_resistance_percent") == row.attributes.WIS,
            "WIS contributes one raw MDEF point without a premature cap: " + label)
        check(unit.magic_defense_pct() == row.mdef and profile.magic_defense_pct() == row.mdef and preview.mdef == row.mdef,
            "WIS and armor produce the same final MDEF everywhere: " + label)
        check(is_equal_approx(unit.mana_regen_pct, row.regen), "WIS still supplies 0.3 percent MP regeneration: " + label)
        unit.mp = 0
        var first: int = unit.regenerate_mana_end_turn()
        var second: int = unit.regenerate_mana_end_turn()
        check(first == row.first and first + second == int(floor(2.0 * row.mp * row.regen / 100.0 + 0.000001)),
            "whole MP regeneration carries fractional remainder between own turns: " + label)
        unit.mp = unit.max_mp - 1
        unit.mana_regen_fraction = 0.0
        check(unit.regenerate_mana_end_turn() == 1 and unit.mp == unit.max_mp and unit.mana_regen_fraction == 0.0,
            "actual regeneration stops at max MP and clears the remainder: " + label)
    demo.free()

func test_high_stats_and_defense_order() -> void:
    var demo = Demo.new()
    var stats = stats_for(5, 101, 3)
    var profile = stats.commander
    var unit = demo.make_unit("high_wis", "blue", stats)
    check(unit.attributes.WIS == 160 and unit.magic_resistance_pct == 160.0,
        "high WIS survives as a raw component above the final defense cap")
    check(unit.magic_defense_pct(-15.0) == 90.0 and profile.magic_defense_pct(-15.0) == 90.0,
        "matter advantage is subtracted before the final ninety percent cap")
    unit.mdef_effects_pct = -80.0
    check(unit.magic_defense_pct(-15.0) == 65.0 and profile.magic_defense_pct(-95.0) == 65.0,
        "negative effects and matter combine with uncapped WIS before final protection")
    unit.mdef_effects_pct = -190.0
    check(unit.magic_defense_pct(-15.0) == -45.0 and profile.magic_defense_pct(-205.0) == -45.0,
        "final magic defense may remain negative")
    var high = stats_for(0, 999, 3)
    var descriptor: Dictionary = Build.defaults(high)
    var actor = demo.make_unit("high_str", "blue", Build.materialize(high, descriptor))
    check(actor.attributes.STR > 45 and actor.physical_damage_bonus_pct == 90.0,
        "STR itself is uncapped while its damage bonus retains the ninety percent ceiling")
    var high_mage = stats_for(4, 999, 1)
    actor = demo.make_unit("high_int", "blue", high_mage)
    check(actor.attributes.INT > 45 and actor.magic_power_pct == 90.0,
        "INT itself is uncapped while its damage bonus retains the ninety percent ceiling")
    demo.free()

func battle_fixture():
    var setup = Setup.new()
    setup.enemy_ai_enabled = false
    var stats = Setup.catalog_entry("male")
    var options: Dictionary = Build.resize(stats, Build.defaults(stats), 30)
    options.armor = 3
    options.book = "novice"
    setup.set_commander_options("ally_1", options)
    var demo = Demo.new()
    demo.team_setup = setup
    demo.reset_demo()
    demo.enemy_ai_enabled = false
    demo.board.move_unit("enemy_1", Vector2i(2, 1))
    demo.selected_unit_id = "ally_1"
    demo.hovered_cell = Vector2i(2, 1)
    return demo

func test_actual_damage() -> void:
    for mode in ["basic", "magic"]:
        var demo = battle_fixture()
        demo.set_attack_mode(mode)
        var preview: Dictionary = demo.attack_preview_for("enemy_1")
        var before_hp: int = demo.units.enemy_1.hp
        check(preview.available and preview.normal_damage == (107 if mode == "basic" else 22),
            "one-percent stat bonus gives an independently calculated damage outcome: " + mode)
        demo.attack_enemy("ally_1", "enemy_1", 99.0, 99.0, 99.0)
        check(before_hp - demo.units.enemy_1.hp == preview.normal_damage and demo.animation_damage == preview.normal_damage,
            "real damage equals the read-only one-percent preview: " + mode)
        check(not demo.animation_crit, "normal physical fixture and all magic remain noncritical: " + mode)
        if mode == "magic":
            check(preview.crit_chance_pct == 0.0 and preview.hit_chance_pct == 100.0,
                "new growth does not grant magic critical hits or evasion")
        demo.free()

func test_preparation_ui() -> void:
    var scene = Scene.instantiate()
    scene.persist_setups = false
    root.add_child(scene)
    scene.set_process(false)
    var catalog = Setup.catalog_entry("male")
    var original: Dictionary = Build.defaults(catalog)
    scene.open_commander_editor("ally_1")
    var editor = scene.commander_editor
    editor.level_spin.value = 30
    check(editor.options.STR == 43 and editor.options.AGI == 26 and editor.options.WIS == 9 and editor.options.INT == 9,
        "level selection exposes automatic level30 allocations")
    for key in ["STR", "AGI", "WIS", "INT"]:
        check(not editor.point_spins[key].editable, "earned point field is read-only: " + key)
    var before: Dictionary = editor.options.duplicate(true)
    editor._on_points_changed(0.0, "STR")
    check(editor.options == before, "legacy manual change entry point cannot edit automatic growth")
    editor.tab_buttons.matter.pressed.emit()
    editor.equipment_checks.water_sword.button_pressed = true
    editor.equipment_checks.water_shield.button_pressed = true
    editor.book_option.item_selected.emit(Build.BOOK_KEYS.find("wind"))
    editor.level_spin.value = 31
    check(editor.options.equipment == ["water_sword", "water_shield"] and editor.options.book == "wind",
        "changing level preserves selected matter sources and independent book")
    editor.apply_button.pressed.emit()
    scene.preparation_ui.setup.set_enabled("ally_3", false)
    scene.preparation_ui.next_button.pressed.emit()
    scene.preparation_ui.start_button.pressed.emit()
    check(scene.units.size() == 5 and scene.units.ally_1.level == 31 and scene.units.ally_1.matter == Matter.WATER
        and scene.units.ally_1.spell_matter == Matter.WIND, "accepted partial battle materializes auto growth with chosen matter and book")
    check(scene.units.ally_1.physical_damage_bonus_pct == scene.units.ally_1.attributes.STR,
        "accepted warrior runtime uses the same one-percent growth values as preparation")
    var encoded: Dictionary = Codec.encode(scene.team_setup)
    var restored: Dictionary = Codec.decode(encoded.code)
    check(encoded.ok and encoded.data.version == 5 and restored.ok
        and restored.setup.current_commander_options("ally_1") == scene.team_setup.current_commander_options("ally_1"),
        "partial current setup round-trips derived growth and selected equipment")
    var replay_before: Dictionary = scene.team_setup.current_commander_options("ally_1")
    scene.reset_demo()
    check(scene.team_setup.current_commander_options("ally_1") == replay_before and scene.units.ally_1.level == 31,
        "repeat retains chosen level and deterministically rebuilds the same automatic allocation")
    check(Build.defaults(catalog) == original, "editing and starting the private growth never mutate the source catalog")
    scene.free()

func run_checks() -> void:
    test_four_level30_profiles()
    test_high_stats_and_defense_order()
    test_actual_damage()
    test_preparation_ui()
    if failures == 0:
        print("SULEYN auto growth battle v1.15: %d checks passed." % checks)
    quit(0 if failures == 0 else 1)
