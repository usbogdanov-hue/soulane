extends Control
## Read-only battle summary, event statistics and a selectable text report. The demo owns replay, preparation and review actions.

signal repeat_requested
signal preparation_requested
signal review_requested

const BLUE = Color(0.36, 0.63, 0.97)
const RED = Color(0.93, 0.47, 0.52)
const TEXT = Color(0.94, 0.96, 0.97)
const MUTED = Color(0.67, 0.76, 0.80)
const GOLD = Color(0.99, 0.83, 0.44)

const Statistics = preload("res://scripts/battle_statistics.gd")

var tab_buttons: Dictionary = {}
var tab_views: Dictionary = {}
var active_tab: String = "overview"
var stats_rows: Array[Button] = []
var stats_team_labels: Dictionary = {}
var stats_detail_label: Label
var selected_unit_id: String = ""
var report_edit: TextEdit
var select_report_button: Button
var report_status_label: Label
var summary: Dictionary = {}
var title_label: Label
var rounds_label: Label
var team_labels: Dictionary = {}
var unit_rows: Array[Control] = []
var repeat_button: Button
var preparation_button: Button
var review_button: Button


func configure(result: Dictionary) -> void:
    summary = result.duplicate(true)
    for child in get_children():
        remove_child(child)
        child.free()
    team_labels.clear()
    unit_rows.clear()
    stats_rows.clear()
    stats_team_labels.clear()
    tab_buttons.clear()
    tab_views.clear()
    selected_unit_id = ""
    position = Vector2.ZERO
    size = Vector2(1440, 900)
    mouse_filter = Control.MOUSE_FILTER_STOP
    theme = _make_theme()

    var shade := ColorRect.new()
    shade.color = Color(0.025, 0.045, 0.065, 0.90)
    shade.size = size
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(shade)
    var card := Panel.new()
    card.name = "ResultCard"
    card.position = Vector2(160, 60)
    card.size = Vector2(1120, 780)
    card.mouse_filter = Control.MOUSE_FILTER_STOP
    card.add_theme_stylebox_override("panel", _box(Color(0.085, 0.14, 0.19), Color(0.32, 0.45, 0.51)))
    add_child(card)

    _label(card, "СУЛЭЙН / ИТОГИ БОЯ", Vector2(32, 22), Vector2(880, 28), 16, MUTED)
    var winner: String = str(summary.get("winner_side", ""))
    var heading: String = "Синие победили" if winner == "blue" else ("Красные победили" if winner == "red" else "Бой завершён")
    title_label = _label(card, heading, Vector2(32, 53), Vector2(630, 44), 31, GOLD)
    title_label.name = "Winner"
    rounds_label = _label(card, "Раунд: %d" % maxi(1, int(summary.get("rounds", 1))), Vector2(688, 61), Vector2(224, 32), 19, MUTED)
    rounds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

    for index in range(3):
        var key: String = ["overview", "statistics", "report"][index]
        var tab := _button(card, ["Состояние", "Статистика", "Отчёт"][index], Vector2(32 + index * 254, 110), Vector2(244, 36), show_tab.bind(key))
        tab.toggle_mode = true
        tab_buttons[key] = tab
        var view := Control.new()
        view.position = Vector2(32, 162)
        view.size = Vector2(1056, 438)
        view.mouse_filter = Control.MOUSE_FILTER_IGNORE
        card.add_child(view)
        tab_views[key] = view

    for side in ["blue", "red"]:
        var x: float = 0.0 if side == "blue" else 540.0
        var panel := Panel.new()
        panel.position = Vector2(x, 0)
        panel.size = Vector2(516, 84)
        panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        panel.add_theme_stylebox_override("panel", _box(Color(0.12, 0.20, 0.25), Color(0.25, 0.37, 0.43)))
        tab_views.overview.add_child(panel)
        var totals: Dictionary = summary.get("teams", {}).get(side, {})
        var side_name: String = "СИНЯЯ КОМАНДА" if side == "blue" else "КРАСНАЯ КОМАНДА"
        _label(panel, side_name, Vector2(16, 10), Vector2(484, 26), 17, BLUE if side == "blue" else RED)
        team_labels[side] = _label(panel, "В строю: %d из %d   ·   Потери: %d" % [int(totals.get("alive", 0)), int(totals.get("total", 0)), int(totals.get("fallen", 0))], Vector2(16, 43), Vector2(484, 27), 16, TEXT)

    _label(tab_views.overview, "БОЙЦЫ", Vector2(0, 100), Vector2(460, 27), 15, MUTED)
    _label(tab_views.overview, "СОСТОЯНИЕ ПОСЛЕ БОЯ", Vector2(612, 100), Vector2(356, 27), 15, MUTED)
    var row_index: int = 0
    for raw_unit in summary.get("units", []):
        if not raw_unit is Dictionary or row_index >= 6:
            continue
        var unit: Dictionary = raw_unit
        var row := Panel.new()
        row.position = Vector2(0, 132 + row_index * 49)
        row.size = Vector2(1056, 43)
        row.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_theme_stylebox_override("panel", _box(Color(0.11, 0.18, 0.23), Color(0.19, 0.29, 0.35)))
        tab_views.overview.add_child(row)
        var side: String = str(unit.get("side", ""))
        var color: Color = BLUE if side == "blue" else RED
        _label(row, str(unit.get("label", "Боец")), Vector2(14, 6), Vector2(584, 31), 16, color)
        var alive: bool = bool(unit.get("alive", false))
        var state_text: String = "В строю · HP %d/%d" % [maxi(0, int(unit.get("hp", 0))), maxi(1, int(unit.get("max_hp", 1)))] if alive else "Повержен · HP 0"
        _label(row, state_text, Vector2(612, 6), Vector2(430, 31), 16, TEXT if alive else MUTED)
        unit_rows.append(row)
        row_index += 1

    _build_statistics(tab_views.statistics)
    _build_report(tab_views.report)

    repeat_button = _button(card, "Повторить бой", Vector2(32, 620), Vector2(516, 48), func(): repeat_requested.emit())
    repeat_button.name = "RepeatBattle"
    preparation_button = _button(card, "Изменить составы", Vector2(572, 620), Vector2(516, 48), func(): preparation_requested.emit())
    preparation_button.name = "ChangeTeams"
    review_button = _button(card, "Вернуться на поле и посмотреть журнал", Vector2(32, 689), Vector2(1056, 43), func(): review_requested.emit())
    review_button.name = "ReviewBattle"
    show_tab("overview")


func show_tab(key: String) -> void:
    if not tab_views.has(key):
        return
    active_tab = key
    for tab_key in tab_views:
        tab_views[tab_key].visible = tab_key == key
        tab_buttons[tab_key].set_pressed_no_signal(tab_key == key)


func _build_statistics(view: Control) -> void:
    var statistics: Dictionary = summary.get("statistics", {})
    var teams: Dictionary = statistics.get("teams", {})
    for side in ["blue", "red"]:
        var totals: Dictionary = teams.get(side, {})
        stats_team_labels[side] = _label(view,
            "%s: урон %d HP · получено %d HP\nПопадания %d/%d · MP −%d / +%d" % [
                "СИНИЕ" if side == "blue" else "КРАСНЫЕ", totals.get("damage_dealt", 0),
                totals.get("damage_received", 0), totals.get("hits", 0), totals.get("attacks", 0),
                totals.get("mp_spent", 0), totals.get("mp_regenerated", 0)],
            Vector2(0 if side == "blue" else 540, 0), Vector2(516, 54), 15, BLUE if side == "blue" else RED)
    var columns: Array = [["Боец", 12, 300], ["Урон", 320, 80], ["Получено", 410, 90],
        ["Попад./атак", 510, 100], ["Крит", 620, 60], ["Добив.", 690, 65], ["MP −/+", 785, 250]]
    for column in columns:
        _label(view, column[0], Vector2(column[1], 65), Vector2(column[2], 24), 13, MUTED)
    var index: int = 0
    for unit in summary.get("units", []):
        if not unit is Dictionary or index >= 6:
            continue
        var unit_id: String = str(unit.get("id", "legacy_%d" % index))
        var counters: Dictionary = statistics.get("units", {}).get(unit_id, {})
        var row := _button(view, "", Vector2(0, 95 + index * 36), Vector2(1056, 32), select_stats_unit.bind(unit_id))
        row.toggle_mode = true
        row.set_meta("unit_id", unit_id)
        var values: Array = [unit.get("label", "Боец"), str(counters.get("damage_dealt", 0)),
            str(counters.get("damage_received", 0)), "%d/%d" % [counters.get("hits", 0), counters.get("attacks", 0)],
            str(counters.get("criticals", 0)), str(counters.get("kills", 0)),
            "%d / %d" % [counters.get("mp_spent", 0), counters.get("mp_regenerated", 0)]]
        for col in range(columns.size()):
            _label(row, str(values[col]), Vector2(columns[col][1], 4), Vector2(columns[col][2], 24), 14,
                (BLUE if unit.get("side", "") == "blue" else RED) if col == 0 else TEXT)
        stats_rows.append(row)
        index += 1
    stats_detail_label = _label(view, "", Vector2(0, 320), Vector2(1056, 112), 14, TEXT)
    if not stats_rows.is_empty():
        select_stats_unit(str(stats_rows[0].get_meta("unit_id")))


func select_stats_unit(unit_id: String) -> void:
    selected_unit_id = unit_id
    for row in stats_rows:
        row.set_pressed_no_signal(row.get_meta("unit_id") == unit_id)
    var counters: Dictionary = summary.get("statistics", {}).get("units", {}).get(unit_id, {})
    stats_detail_label.text = "Фактический урон: физический %d HP · магический %d HP. Промахи: %d.\nКонтузии: применено %d · собственных пропусков %d.\nПеремещения: %d · шаги: %d · добровольные пропуски: %d. Тестовый расход M: %d MP.\nУрон без избыточного урона; крит учитывается только у физических атак. Нажмите строку бойца для подробностей." % [
        counters.get("physical_damage", 0), counters.get("magic_damage", 0), counters.get("misses", 0),
        counters.get("concussions", 0), counters.get("concussion_skips", 0), counters.get("moves", 0),
        counters.get("steps", 0), counters.get("passes", 0), counters.get("mp_test_spent", 0)]


func _build_report(view: Control) -> void:
    select_report_button = _button(view, "Выделить отчёт", Vector2(0, 0), Vector2(244, 36), _select_report)
    report_status_label = _label(view, "Выделите текст и скопируйте через Ctrl+C или меню текста.", Vector2(262, 3), Vector2(794, 32), 14, MUTED)
    report_edit = TextEdit.new()
    report_edit.name = "BattleReport"
    report_edit.editable = false
    report_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    report_edit.position = Vector2(0, 48)
    report_edit.add_theme_font_size_override("font_size", 14)
    report_edit.add_theme_color_override("font_readonly_color", TEXT)
    report_edit.add_theme_color_override("font_selected_color", TEXT)
    report_edit.add_theme_color_override("selection_color", Color(0.20, 0.37, 0.49))
    report_edit.text = str(summary.get("report", Statistics.report(summary)))
    view.add_child(report_edit)
    report_edit.size = Vector2(1056, 386)


func _select_report() -> void:
    report_edit.grab_focus()
    report_edit.select_all()
    report_status_label.text = "Отчёт выделен. Ctrl+C или меню текста → «Копировать»."


func _make_theme() -> Theme:
    var result := Theme.new()
    result.default_font = ThemeDB.fallback_font
    result.default_font_size = 17
    for type_name in ["Label", "Button", "TextEdit"]:
        result.set_color("font_color", type_name, TEXT)
        result.set_color("font_hover_color", type_name, TEXT)
        result.set_color("font_pressed_color", type_name, TEXT)
    result.set_stylebox("normal", "Button", _box(Color(0.14, 0.23, 0.28), Color(0.29, 0.40, 0.46)))
    result.set_stylebox("hover", "Button", _box(Color(0.21, 0.33, 0.39), Color(0.48, 0.64, 0.70)))
    result.set_stylebox("pressed", "Button", _box(Color(0.19, 0.35, 0.40), GOLD))
    result.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), GOLD))
    return result


func _box(fill: Color, border: Color) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = fill
    box.border_color = border
    box.set_border_width_all(1)
    box.set_corner_radius_all(7)
    return box


func _label(parent: Node, text: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.position = at
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.text = text
    label.clip_text = true
    parent.add_child(label)
    label.size = dimensions
    return label


func _button(parent: Node, text: String, at: Vector2, dimensions: Vector2, callback: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.position = at
    button.size = dimensions
    button.mouse_filter = Control.MOUSE_FILTER_STOP
    button.pressed.connect(callback)
    parent.add_child(button)
    return button
