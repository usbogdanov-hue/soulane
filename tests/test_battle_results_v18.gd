extends SceneTree
## Result view lifecycle: immutable snapshots and one event per active button.

const Results = preload("res://scripts/battle_results_ui.gd")
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    call_deferred("run_checks")


func check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAILED battle results v1.8: " + description)


func fixture(count_per_side: int = 3) -> Dictionary:
    var units: Array[Dictionary] = []
    for side in ["blue", "red"]:
        for slot in range(count_per_side):
            units.append({"label": ("С" if side == "blue" else "К") + str(slot + 1) + " · Адская гончая (тест)",
                "side": side, "alive": side == "blue", "hp": 177 if side == "blue" else 0, "max_hp": 650})
    return {"winner_side": "blue", "rounds": 17,
        "teams": {"blue": {"total": count_per_side, "alive": count_per_side, "fallen": 0},
            "red": {"total": count_per_side, "alive": 0, "fallen": count_per_side}}, "units": units}


func run_checks() -> void:
    var source: Dictionary = fixture()
    var before: Dictionary = source.duplicate(true)
    var view = Results.new()
    var events: Dictionary = {"repeat": 0, "preparation": 0, "review": 0}
    view.repeat_requested.connect(func(): events.repeat += 1)
    view.preparation_requested.connect(func(): events.preparation += 1)
    view.review_requested.connect(func(): events.review += 1)
    view.configure(source)
    root.add_child(view)
    await process_frame
    check(source == before, "configuration does not mutate the battle snapshot")
    check(view.title_label.text == "Синие победили", "blue outcome is presented")
    check(view.rounds_label.text == "Раунд: 17", "finishing round is preserved")
    check(view.unit_rows.size() == 6, "team result includes all six combatants")
    check("Потери: 3" in view.team_labels.red.text and "Потери: 0" in view.team_labels.blue.text,
        "team losses are retained")
    check(view.mouse_filter == Control.MOUSE_FILTER_STOP, "result screen blocks board mouse input")
    check(view.unit_rows[0].get_child(1).text == "В строю · HP 177/650", "survivor HP is visible")
    check(view.unit_rows[3].get_child(1).text == "Повержен · HP 0", "fallen fighter is explicit")
    source.units[0].hp = 1
    check(view.summary.units[0].hp == 177, "result owns an independent snapshot")
    view.repeat_button.pressed.emit()
    view.preparation_button.pressed.emit()
    view.review_button.pressed.emit()
    check(events == {"repeat": 1, "preparation": 1, "review": 1}, "each button routes one distinct action")
    var duel: Dictionary = fixture(1)
    duel.winner_side = "red"
    duel.rounds = 4
    view.configure(duel)
    await process_frame
    check(view.unit_rows.size() == 2, "reconfiguration replaces team rows with a two-unit duel")
    check(view.get_child_count() == 2, "reconfiguration does not accumulate old panels")
    check(view.title_label.text == "Красные победили", "red outcome replaces previous winner")
    check(view.rounds_label.text == "Раунд: 4", "new result replaces previous round")
    view.repeat_button.pressed.emit()
    view.preparation_button.pressed.emit()
    view.review_button.pressed.emit()
    check(events == {"repeat": 2, "preparation": 2, "review": 2}, "reconfiguration does not duplicate event bindings")
    var card: Control = view.get_node("ResultCard")
    for button in [view.repeat_button, view.preparation_button, view.review_button]:
        check(Rect2(Vector2.ZERO, card.size).encloses(button.get_rect()), "action button stays within the result card")
    view.queue_free()
    await process_frame
    if failures == 0:
        print("SULEYN battle results v1.8: %d checks passed." % checks)
    quit(0 if failures == 0 else 1)
