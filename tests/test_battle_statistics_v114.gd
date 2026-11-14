extends SceneTree
## Actual outcomes, lifecycle and real GUI input for battle reports.
const Stats = preload("res://scripts/battle_statistics.gd")
const Demo = preload("res://scripts/battle_demo.gd")
const Scene = preload("res://scenes/battle_demo.tscn")
const Setup = preload("res://scripts/battle_setup.gd")
const Codec = preload("res://scripts/setup_codec.gd")
const AI = preload("res://scripts/battle_ai.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
    call_deferred("run_checks")

func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED battle statistics v1.14: " + label)

func test_counters() -> void:
    var stats = Stats.new()
    var roster: Array[Dictionary] = [{"id": "a", "side": "blue"}, {"id": "b", "side": "red"}, {"id": "c", "side": "blue"}]
    stats.reset(roster)
    var initial: Dictionary = stats.snapshot()
    for key in Stats.COUNTERS:
        check(initial.totals[key] == 0, "new battle starts at zero: " + key)
    stats.record_attack("a", "b", "special", {"ok": true, "evaded": true, "damage": 0, "skill_cost": 30})
    stats.record_attack("a", "b", "basic", {"ok": true, "damage": 12, "calculated_damage": 1200, "critical": true, "defeated": true})
    stats.record_attack("b", "a", "magic", {"ok": true, "damage": 9, "critical": true, "spell_cost": 10})
    stats.record_attack("c", "b", "special", {"ok": true, "damage": 0, "concussion_applied": true, "skill_cost": 30})
    stats.record_move("a", 3)
    stats.record_pass("c")
    stats.record_concussion_skip("b")
    stats.record_concussion_skip("b")
    stats.record_regeneration("a", 2)
    stats.record_test_spend("a", 20)
    var snapshot: Dictionary = stats.snapshot()
    var a: Dictionary = snapshot.units.a
    check(a.attacks == 2 and a.hits == 1 and a.misses == 1, "paid miss is one attack, not a hit")
    check(a.damage_dealt == 12 and a.physical_damage == 12 and a.kills == 1, "damage uses actual HP rather than overkill")
    check(a.criticals == 1 and snapshot.units.b.criticals == 0 and snapshot.units.b.magic_damage == 9, "magic cannot add physical crits")
    check(a.mp_spent == 50 and a.mp_test_spent == 20 and a.mp_regenerated == 2, "miss cost, explicit test spend and actual regeneration remain distinct")
    check(snapshot.units.c.hits == 1 and snapshot.units.c.concussions == 1, "zero damage hit and successful concussion are counted")
    check(snapshot.units.b.concussion_skips == 2 and snapshot.units.b.passes == 0, "two own concussion skips are not voluntary passes")
    check(a.moves == 1 and a.steps == 3 and snapshot.units.c.passes == 1, "movement steps and passes are separate events")
    for key in Stats.COUNTERS:
        check(snapshot.teams.blue[key] + snapshot.teams.red[key] == snapshot.totals[key], "team totals reconcile: " + key)
    check(snapshot.totals.damage_dealt == snapshot.totals.damage_received, "damage dealt equals received across the battle")
    var before: Dictionary = snapshot.duplicate(true)
    for bad in [{"ok": false}, {"ok": true, "damage": -1}, {"ok": true, "damage": false}, {"ok": true, "damage": 1.5}, {"ok": true, "damage": 8, "evaded": true}]:
        stats.record_attack("a", "b", "basic", bad)
    stats.record_attack("a", "c", "basic", {"ok": true, "damage": 7})
    stats.record_attack("a", "unknown", "basic", {"ok": true, "damage": 7})
    stats.record_attack("a", "b", "unknown", {"ok": true, "damage": 7})
    for invalid in [-1, 0, false, 1.5]:
        stats.record_move("a", invalid)
        stats.record_regeneration("a", invalid)
        stats.record_test_spend("a", invalid)
    check(stats.snapshot() == before, "invalid events do not partially update counters")
    snapshot.units.a.damage_dealt = 999
    snapshot.teams.blue.damage_dealt = 999
    check(stats.snapshot() == before, "snapshots own all nested dictionaries")
    seed(114)
    var next_random: int = randi()
    seed(114)
    stats.snapshot()
    var report: String = Stats.report({"statistics": before, "winner_side": "blue", "rounds": 4, "arena": "Колонны", "setup_code": "test-code"})
    check(report.contains("нанесено 12 HP") and report.contains("из них тест M: 20") and report.contains("не сохранение"), "report includes concrete counters and setup-code limits")
    check(randi() == next_random and stats.snapshot() == before, "report reads preserve RNG and counters")
    stats.reset([{"id": "duel_blue", "side": "blue"}, {"id": "duel_red", "side": "red"}])
    check(stats.snapshot().units.keys() == ["duel_blue", "duel_red"] and stats.snapshot().totals.attacks == 0, "new roster replaces participants and all counters")

func fixture():
    var demo = Demo.new()
    demo.reset_demo()
    demo.enemy_ai_enabled = false
    demo.board.move_unit("enemy_1", Vector2i(2, 1))
    return demo

func counts(demo, unit_id: String) -> Dictionary:
    return demo.battle_statistics.snapshot().units[unit_id]

func next_blue(demo) -> void:
    demo.animation_time = demo.ANIMATION_DURATION
    for _turn in range(6):
        if demo.turns.active_unit_id() == "ally_1":
            break
        if demo.concussion_skip_pending:
            demo.resolve_one_concussion_skip()
        else:
            demo.pass_turn()

func test_native_events() -> void:
    var demo = fixture()
    demo.set_attack_mode("special")
    var mp: int = demo.units.ally_1.mp
    demo.attack_enemy("ally_1", "enemy_1", 0.0, 99.0, 99.0)
    var a: Dictionary = counts(demo, "ally_1")
    check(a.attacks == 1 and a.misses == 1 and a.mp_spent == 30, "real missed skill consumes and records MP once")
    check(demo.units.ally_1.mp == mp - a.mp_spent + a.mp_regenerated, "actual attack MP reconciles with regeneration")
    next_blue(demo)
    demo.set_attack_mode("magic")
    var hp: int = demo.units.enemy_1.hp
    demo.attack_enemy("ally_1", "enemy_1")
    a = counts(demo, "ally_1")
    check(a.attacks == 2 and a.hits == 1 and a.magic_damage == hp - demo.units.enemy_1.hp and a.criticals == 0, "real magic records actual damage without a crit")
    next_blue(demo)
    demo.set_attack_mode("basic")
    demo.units.enemy_1.hp = 7
    demo.attack_enemy("ally_1", "enemy_1", 99.0, 0.0)
    a = counts(demo, "ally_1")
    check(a.physical_damage == 7 and a.kills == 1 and a.criticals == 1, "real critical finisher records only seven remaining HP")
    check(counts(demo, "enemy_1").damage_received == a.damage_dealt, "fallen defender remains in statistics")
    check(not demo.battle_statistics.snapshot().units.has("unknown"), "only original combatants are registered")
    demo.reset_demo()
    check(counts(demo, "ally_1").attacks == 0 and counts(demo, "enemy_1").damage_received == 0, "R clears counters and restores fallen units")
    demo.units.ally_1.mp = demo.units.ally_1.max_mp - 1
    demo.units.ally_1.mana_regen_pct = 90.0
    demo.pass_turn()
    check(counts(demo, "ally_1").mp_regenerated == 1 and counts(demo, "ally_1").passes == 1, "regen counts only one MP actually restored at cap")
    demo.reset_demo()
    demo.debug_spend_mana()
    check(counts(demo, "ally_1").mp_spent == 20 and counts(demo, "ally_1").mp_test_spent == 20 and counts(demo, "ally_1").attacks == 0, "test M is a labelled resource expense, not an attack")
    check(demo.move_active_unit("ally_1", Vector2i(2, 1)), "legal real movement succeeds")
    check(counts(demo, "ally_1").moves == 1 and counts(demo, "ally_1").steps == 1, "successful movement records exact path length")
    var before: Dictionary = demo.battle_statistics.snapshot()
    check(not demo.move_active_unit("ally_1", Vector2i(4, 1)) and demo.battle_statistics.snapshot() == before, "rejected out-of-turn movement adds no event")
    demo.reset_demo()
    demo.board.move_unit("enemy_1", Vector2i(2, 1))
    demo.set_attack_mode("special")
    demo.attack_enemy("ally_1", "enemy_1", 99.0, 99.0, 0.0)
    check(counts(demo, "ally_1").concussions == 1 and counts(demo, "enemy_1").concussion_skips == 0, "concussion application is recorded before own skips occur")
    demo.animation_time = demo.ANIMATION_DURATION
    demo.resolve_one_concussion_skip()
    next_blue(demo)
    demo.pass_turn()
    demo.resolve_one_concussion_skip()
    var target: Dictionary = counts(demo, "enemy_1")
    check(target.concussion_skips == 2 and target.passes == 0 and demo.units.enemy_1.concussion_turns_remaining == 0, "two real own skips count exactly once each")
    var stable: Dictionary = demo.battle_statistics.snapshot()
    demo.resolve_one_concussion_skip()
    check(demo.battle_statistics.snapshot() == stable, "calling skip resolution again cannot double count")
    demo.reset_demo()
    demo.board.move_unit("enemy_1", Vector2i(2, 1))
    demo.selected_unit_id = "ally_1"
    demo.hovered_cell = Vector2i(2, 1)
    before = demo.battle_statistics.snapshot()
    seed(114009)
    var next_random: int = randi()
    seed(114009)
    for _i in range(3):
        demo.attack_preview_for("enemy_1")
        AI.choose_action(demo.board, demo.units, "enemy_1")
        demo.battle_summary()
    check(randi() == next_random and demo.battle_statistics.snapshot() == before, "previews, AI planning and report reads add no events or RNG")
    demo.pass_turn()
    demo.enemy_ai_enabled = true
    demo.perform_ai_turn()
    target = counts(demo, "enemy_1")
    check(target.attacks + target.moves + target.passes == 1, "AI execution records exactly one real action")
    demo.switch_encounter()
    check(demo.battle_statistics.snapshot().units.size() == 2 and demo.battle_statistics.snapshot().totals.attacks == 0, "T registers a fresh two-unit duel")
    check(demo.battle_summary().setup_code.is_empty(), "duel report does not claim a team setup code")
    demo.free()

func mouse_click(control: Control) -> void:
    var at: Vector2 = control.get_global_rect().get_center()
    var motion := InputEventMouseMotion.new()
    motion.position = at
    root.push_input(motion, true)
    await process_frame
    for pressed in [true, false]:
        var event := InputEventMouseButton.new()
        event.position = at
        event.button_index = MOUSE_BUTTON_LEFT
        event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
        event.pressed = pressed
        root.push_input(event, true)
    await process_frame

func test_scene_and_results() -> void:
    var demo = Scene.instantiate()
    demo.persist_setups = false
    root.add_child(demo)
    demo.set_process(false)
    demo.preparation_ui.setup.set_enabled("ally_3", false)
    demo.preparation_ui.setup.enemy_ai_enabled = false
    demo.preparation_ui.next_button.pressed.emit()
    demo.preparation_ui.start_button.pressed.emit()
    check(demo.battle_statistics.snapshot().units.size() == 5, "2x3 roster excludes inactive slot")
    demo.pass_turn()
    var snapshot: Dictionary = demo.battle_statistics.snapshot()
    demo.open_preparation()
    demo.preview_preparation()
    check(demo.battle_statistics.snapshot() == snapshot, "P and deployment preview do not reset recorded battle statistics")
    var code: Dictionary = Codec.encode(demo.team_setup).data
    check(code.version == 4 and not str(code).contains("statistics"), "portable setup schema remains v4 without runtime counters")
    demo.preparation_ui.next_button.pressed.emit()
    demo.preparation_ui.start_button.pressed.emit()
    check(demo.battle_statistics.snapshot().totals.passes == 0, "new accepted battle clears prior events")
    # Use a real one-versus-one accepted setup for a deterministic final blow.
    demo.open_preparation()
    for unit_id in ["ally_2", "ally_3", "enemy_2", "enemy_3"]:
        demo.preparation_ui.setup.set_enabled(unit_id, false)
    demo.preparation_ui.next_button.pressed.emit()
    demo.preparation_ui.start_button.pressed.emit()
    demo.board.move_unit("enemy_1", Vector2i(2, 1))
    demo.units.enemy_1.hp = 3
    demo.attack_enemy("ally_1", "enemy_1", 99.0, 99.0)
    check(demo.battle_over and demo.results_pending, "real final attack schedules results")
    demo.show_battle_results()
    check(not is_instance_valid(demo.results_ui), "results wait for final animation")
    demo.animation_time = demo.ANIMATION_DURATION
    demo.show_battle_results()
    var view = demo.results_ui
    await process_frame
    check(view.visible and view.active_tab == "overview" and view.unit_rows.size() == 2, "completed partial battle opens compatible overview")
    await mouse_click(view.tab_buttons.statistics)
    check(view.active_tab == "statistics" and view.stats_rows.size() == 2, "real mouse input opens statistics including fallen fighter")
    check(view.stats_team_labels.blue.text.contains("урон 3 HP"), "visible team damage is capped actual HP")
    await mouse_click(view.stats_rows[1])
    check(view.selected_unit_id == "enemy_1" and view.stats_detail_label.text.contains("магический 0"), "real row selection changes the detailed counters")
    await mouse_click(view.tab_buttons.report)
    check(view.active_tab == "report" and not view.report_edit.editable, "report tab is readable without editing the source report")
    await mouse_click(view.select_report_button)
    check(view.report_edit.get_selected_text() == view.report_edit.text and root.gui_get_focus_owner() == view.report_edit, "select report selects the full copyable text and gives it focus")
    var report: String = view.report_edit.text
    check(report.contains("v1.14") and report.contains("КОД НАЧАЛЬНОЙ ПОДГОТОВКИ") and report.contains("Добивания 1"), "standalone report includes version, setup and actual final blow")
    snapshot = demo.battle_statistics.snapshot()
    demo.review_battle()
    demo.show_battle_results()
    check(demo.results_ui.report_edit.text == report and demo.battle_statistics.snapshot() == snapshot, "review and reopening results do not duplicate statistics")
    var summary: Dictionary = demo.battle_summary()
    summary.statistics.units.ally_1.damage_dealt = 999
    check(demo.battle_statistics.snapshot() == snapshot, "result snapshot cannot mutate tracker")
    demo.results_ui.repeat_button.pressed.emit()
    check(not demo.battle_over and demo.units.size() == 2 and demo.battle_statistics.snapshot().totals.damage_dealt == 0, "repeat button starts same composition with zero counters")
    demo.free()

func run_checks() -> void:
    test_counters()
    test_native_events()
    await test_scene_and_results()
    if failures == 0:
        print("SULEYN battle statistics v1.14: %d checks passed." % checks)
    quit(0 if failures == 0 else 1)
