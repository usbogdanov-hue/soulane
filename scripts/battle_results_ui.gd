extends Control
## Read-only battle summary. The demo owns replay, preparation and review actions.

signal repeat_requested
signal preparation_requested
signal review_requested

const BLUE = Color(0.36, 0.63, 0.97)
const RED = Color(0.93, 0.47, 0.52)
const TEXT = Color(0.94, 0.96, 0.97)
const MUTED = Color(0.67, 0.76, 0.80)
const GOLD = Color(0.99, 0.83, 0.44)

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
    card.position = Vector2(248, 96)
    card.size = Vector2(944, 708)
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

    for side in ["blue", "red"]:
        var x: float = 32.0 if side == "blue" else 484.0
        var panel := Panel.new()
        panel.position = Vector2(x, 111)
        panel.size = Vector2(428, 84)
        panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        panel.add_theme_stylebox_override("panel", _box(Color(0.12, 0.20, 0.25), Color(0.25, 0.37, 0.43)))
        card.add_child(panel)
        var totals: Dictionary = summary.get("teams", {}).get(side, {})
        var side_name: String = "СИНЯЯ КОМАНДА" if side == "blue" else "КРАСНАЯ КОМАНДА"
        _label(panel, side_name, Vector2(16, 10), Vector2(396, 26), 17, BLUE if side == "blue" else RED)
        team_labels[side] = _label(panel, "В строю: %d из %d   ·   Потери: %d" % [int(totals.get("alive", 0)), int(totals.get("total", 0)), int(totals.get("fallen", 0))], Vector2(16, 43), Vector2(396, 27), 16, TEXT)

    _label(card, "БОЙЦЫ", Vector2(32, 211), Vector2(460, 27), 15, MUTED)
    _label(card, "СОСТОЯНИЕ ПОСЛЕ БОЯ", Vector2(556, 211), Vector2(356, 27), 15, MUTED)
    var row_index: int = 0
    for raw_unit in summary.get("units", []):
        if not raw_unit is Dictionary or row_index >= 6:
            continue
        var unit: Dictionary = raw_unit
        var row := Panel.new()
        row.position = Vector2(32, 245 + row_index * 49)
        row.size = Vector2(880, 43)
        row.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_theme_stylebox_override("panel", _box(Color(0.11, 0.18, 0.23), Color(0.19, 0.29, 0.35)))
        card.add_child(row)
        var side: String = str(unit.get("side", ""))
        var color: Color = BLUE if side == "blue" else RED
        _label(row, str(unit.get("label", "Боец")), Vector2(14, 6), Vector2(498, 31), 16, color)
        var alive: bool = bool(unit.get("alive", false))
        var state_text: String = "В строю · HP %d/%d" % [maxi(0, int(unit.get("hp", 0))), maxi(1, int(unit.get("max_hp", 1)))] if alive else "Повержен · HP 0"
        _label(row, state_text, Vector2(524, 6), Vector2(342, 31), 16, TEXT if alive else MUTED)
        unit_rows.append(row)
        row_index += 1

    repeat_button = _button(card, "Повторить бой", Vector2(32, 572), Vector2(428, 48), func(): repeat_requested.emit())
    repeat_button.name = "RepeatBattle"
    preparation_button = _button(card, "Изменить составы", Vector2(484, 572), Vector2(428, 48), func(): preparation_requested.emit())
    preparation_button.name = "ChangeTeams"
    review_button = _button(card, "Вернуться на поле и посмотреть журнал", Vector2(32, 637), Vector2(880, 43), func(): review_requested.emit())
    review_button.name = "ReviewBattle"


func _make_theme() -> Theme:
    var result := Theme.new()
    result.default_font = ThemeDB.fallback_font
    result.default_font_size = 17
    for type_name in ["Label", "Button"]:
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
    label.text = text
    label.position = at
    label.size = dimensions
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    parent.add_child(label)
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
