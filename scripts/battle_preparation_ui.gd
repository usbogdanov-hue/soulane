extends Control
## Presentation and input for the preparation draft. Runtime battle state is owned
## by battle_demo.gd; this view only changes the supplied setup model.

signal deployment_requested
signal placement_changed
signal selection_changed(unit_id: String)
signal battle_requested

const PROFILE_KEYS: Array[String] = ["male", "female", "falcon", "hellhound", "lich"]
const PROFILE_LABELS: Dictionary = {
    "male": "Мужчина · булава", "female": "Женщина · копьё", "falcon": "Сокол",
    "hellhound": "Адская гончая", "lich": "Лич",
}
const BLUE = Color(0.36, 0.63, 0.97)
const RED = Color(0.93, 0.47, 0.52)
const TEXT = Color(0.94, 0.96, 0.97)
const MUTED = Color(0.67, 0.76, 0.80)
const GOLD = Color(0.99, 0.83, 0.44)

var setup
var stage: String = "roster"
var selected_unit_id: String = "ally_1"
var status_label: Label
var roster_status_label: Label
var start_button: Button
var next_button: Button
var ai_checkbox: CheckBox
var profile_options: Dictionary = {}
var profile_summaries: Dictionary = {}
var unit_buttons: Dictionary = {}
var roster_root: Control
var deployment_root: Control
var _refreshing: bool = false
var _status_override: String = ""


func configure(model) -> void:
    setup = model
    stage = "roster"
    selected_unit_id = "ally_1"
    _status_override = ""
    for child in get_children():
        remove_child(child)
        child.free()
    profile_options.clear()
    profile_summaries.clear()
    unit_buttons.clear()
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    position = Vector2.ZERO
    size = Vector2(1440, 900)
    theme = _make_theme()
    _build_roster()
    _build_deployment()
    show_roster()


func show_roster() -> void:
    stage = "roster"
    _status_override = ""
    roster_root.show()
    deployment_root.hide()
    _refresh_roster()


func show_deployment() -> void:
    stage = "deployment"
    _status_override = ""
    roster_root.hide()
    deployment_root.show()
    _refresh_deployment()


func set_status(text: String) -> void:
    _status_override = text
    if stage == "roster":
        roster_status_label.text = text
    else:
        status_label.text = text


func handle_board_click(cell: Vector2i) -> void:
    if stage != "deployment":
        return
    var occupant: String = setup.unit_at(cell)
    if not occupant.is_empty():
        selected_unit_id = occupant
        _status_override = ""
        _refresh_deployment()
        selection_changed.emit(selected_unit_id)
        return
    if not setup.place_unit(selected_unit_id, cell):
        var zone: String = "двух левых" if setup.team_for(selected_unit_id) == "blue" else "двух правых"
        set_status("Для %s выберите свободный гекс в %s колонках поля." % [_token(selected_unit_id), zone])
        return
    _status_override = "%s размещён. Можно выбрать следующего бойца или начать бой." % _token(selected_unit_id)
    _refresh_deployment()
    placement_changed.emit()


func _make_theme() -> Theme:
    var result := Theme.new()
    result.default_font = ThemeDB.fallback_font
    result.default_font_size = 17
    for type_name in ["Label", "Button", "OptionButton", "CheckBox", "PopupMenu"]:
        result.set_color("font_color", type_name, TEXT)
        result.set_color("font_hover_color", type_name, TEXT)
        result.set_color("font_pressed_color", type_name, TEXT)
    for type_name in ["Button", "OptionButton"]:
        result.set_stylebox("normal", type_name, _box(Color(0.14, 0.23, 0.28), Color(0.29, 0.40, 0.46)))
        result.set_stylebox("hover", type_name, _box(Color(0.21, 0.33, 0.39), Color(0.48, 0.64, 0.70)))
        result.set_stylebox("pressed", type_name, _box(Color(0.19, 0.35, 0.40), GOLD))
        result.set_stylebox("disabled", type_name, _box(Color(0.11, 0.16, 0.19), Color(0.20, 0.28, 0.32)))
        result.set_stylebox("focus", type_name, _box(Color(0, 0, 0, 0), GOLD))
        result.set_color("font_disabled_color", type_name, Color(0.43, 0.53, 0.58))
    result.set_stylebox("panel", "PopupMenu", _box(Color(0.10, 0.16, 0.20), Color(0.40, 0.54, 0.61)))
    result.set_stylebox("hover", "PopupMenu", _box(Color(0.22, 0.35, 0.40), Color(0.22, 0.35, 0.40)))
    return result


func _box(fill: Color, border: Color) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = fill
    box.border_color = border
    box.set_border_width_all(1)
    box.set_corner_radius_all(7)
    box.content_margin_left = 12
    box.content_margin_right = 12
    box.content_margin_top = 7
    box.content_margin_bottom = 7
    return box


func _panel(parent: Node, at: Vector2, dimensions: Vector2, fill: Color) -> Panel:
    var panel := Panel.new()
    panel.position = at
    panel.size = dimensions
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    panel.add_theme_stylebox_override("panel", _box(fill, Color(0.24, 0.34, 0.40)))
    parent.add_child(panel)
    return panel


func _label(parent: Node, text: String, at: Vector2, dimensions: Vector2,
        font_size: int = 17, color: Color = TEXT) -> Label:
    var label := Label.new()
    label.text = text
    label.position = at
    label.size = dimensions
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    parent.add_child(label)
    return label


func _button(parent: Node, text: String, at: Vector2, dimensions: Vector2,
        callback: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.position = at
    button.size = dimensions
    button.mouse_filter = Control.MOUSE_FILTER_STOP
    button.pressed.connect(callback)
    parent.add_child(button)
    return button


func _build_roster() -> void:
    roster_root = Control.new()
    roster_root.size = size
    roster_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(roster_root)
    var background := ColorRect.new()
    background.color = Color(0.055, 0.08, 0.115)
    background.size = size
    background.mouse_filter = Control.MOUSE_FILTER_STOP
    roster_root.add_child(background)
    _label(roster_root, "СУЛЭЙН / ПОДГОТОВКА БОЯ", Vector2(80, 52), Vector2(1280, 52), 32)
    _label(roster_root, "1  СОСТАВЫ    →    2  РАССТАНОВКА    →    3  БОЙ", Vector2(82, 113), Vector2(1270, 30), 17, GOLD)
    for side in ["blue", "red"]:
        var x: float = 60.0 if side == "blue" else 745.0
        var panel := _panel(roster_root, Vector2(x, 172), Vector2(635, 478), Color(0.10, 0.16, 0.21))
        var color: Color = BLUE if side == "blue" else RED
        _label(panel, "СИНЯЯ КОМАНДА" if side == "blue" else "КРАСНАЯ КОМАНДА", Vector2(22, 16), Vector2(590, 34), 23, color)
        _label(panel, "Выберите трёх бойцов. Одинаковые профили допустимы.", Vector2(22, 53), Vector2(590, 27), 14, MUTED)
        for slot in range(3):
            var unit_id: String = ("ally_" if side == "blue" else "enemy_") + str(slot + 1)
            var y: float = 91.0 + slot * 124.0
            _label(panel, _token(unit_id), Vector2(22, y + 6), Vector2(48, 30), 20, color)
            var option := OptionButton.new()
            option.name = "Profile_" + unit_id
            option.position = Vector2(78, y)
            option.size = Vector2(531, 42)
            for key in PROFILE_KEYS:
                option.add_item(PROFILE_LABELS[key])
            option.item_selected.connect(_on_profile_selected.bind(unit_id))
            panel.add_child(option)
            profile_options[unit_id] = option
            profile_summaries[unit_id] = _label(panel, "", Vector2(22, y + 48), Vector2(589, 65), 14, MUTED)
    ai_checkbox = CheckBox.new()
    ai_checkbox.name = "RedAI"
    ai_checkbox.text = "Красной командой управляет ИИ"
    ai_checkbox.position = Vector2(80, 675)
    ai_checkbox.size = Vector2(800, 42)
    ai_checkbox.toggled.connect(_on_ai_toggled)
    roster_root.add_child(ai_checkbox)
    roster_status_label = _label(roster_root, "", Vector2(80, 718), Vector2(1280, 34), 16, GOLD)
    _button(roster_root, "Вернуть пример 3 × 3", Vector2(80, 765), Vector2(300, 50), _on_defaults_pressed)
    next_button = _button(roster_root, "Далее: расстановка →", Vector2(1015, 765), Vector2(365, 50), _on_next_pressed)
    next_button.name = "NextDeployment"
    _label(roster_root, "Профили и характеристики взяты из текущего прототипа. Баланс монстров остаётся тестовым.", Vector2(80, 846), Vector2(1280, 30), 14, MUTED)


func _build_deployment() -> void:
    deployment_root = Control.new()
    deployment_root.size = size
    deployment_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(deployment_root)
    var panel := _panel(deployment_root, Vector2(879, 98), Vector2(530, 735), Color(0.085, 0.14, 0.19))
    _label(panel, "2 / РАССТАНОВКА", Vector2(22, 16), Vector2(486, 36), 23, GOLD)
    _label(panel, "Выберите бойца в списке или на поле.\nЗатем нажмите свободный гекс его зоны.", Vector2(22, 57), Vector2(486, 54), 16, MUTED)
    _label(panel, "СИНИЕ — ДВЕ ЛЕВЫЕ КОЛОНКИ · КРАСНЫЕ — ДВЕ ПРАВЫЕ", Vector2(22, 118), Vector2(486, 29), 12, MUTED)
    var slot: int = 0
    for unit_id in setup.unit_ids():
        var button := _button(panel, "", Vector2(22, 151 + slot * 62), Vector2(486, 52), _on_unit_selected.bind(unit_id))
        button.name = "Deploy_" + unit_id
        button.toggle_mode = true
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.add_theme_font_size_override("font_size", 15)
        unit_buttons[unit_id] = button
        slot += 1
    status_label = _label(panel, "", Vector2(22, 535), Vector2(486, 54), 16, GOLD)
    status_label.name = "DeploymentStatus"
    _button(panel, "← К составам", Vector2(22, 597), Vector2(234, 46), show_roster)
    _button(panel, "Сбросить позиции", Vector2(274, 597), Vector2(234, 46), _on_positions_reset)
    start_button = _button(panel, "Начать бой", Vector2(22, 660), Vector2(486, 50), _on_start_pressed)
    start_button.name = "StartBattle"


func _refresh_roster() -> void:
    _refreshing = true
    for unit_id in profile_options:
        var key: String = setup.profile_key(unit_id)
        profile_options[unit_id].select(PROFILE_KEYS.find(key))
        profile_summaries[unit_id].text = _profile_summary(key)
    ai_checkbox.set_pressed_no_signal(setup.enemy_ai_enabled)
    next_button.disabled = not setup.is_valid()
    roster_status_label.text = "Каждая команда: 3 бойца. Очерёдность и боевые правила сохраняются." if setup.is_valid() else _validation_message()
    _refreshing = false


func _refresh_deployment() -> void:
    for unit_id in unit_buttons:
        var raw_cell: Variant = setup.positions.get(unit_id, Vector2i(-1, -1))
        var cell: Vector2i = raw_cell if typeof(raw_cell) == TYPE_VECTOR2I else Vector2i(-1, -1)
        var key: String = setup.profile_key(unit_id)
        unit_buttons[unit_id].text = "%s · %s\nГекс %d, %d" % [_token(unit_id), PROFILE_LABELS.get(key, key), cell.x + 1, cell.y + 1]
        unit_buttons[unit_id].set_pressed_no_signal(unit_id == selected_unit_id)
        unit_buttons[unit_id].add_theme_color_override("font_color", BLUE if setup.team_for(unit_id) == "blue" else RED)
    start_button.disabled = not setup.is_valid()
    if not setup.is_valid():
        status_label.text = _validation_message()
    elif not _status_override.is_empty():
        status_label.text = _status_override
    else:
        status_label.text = "Выбран %s. Для смены бойцов нажмите\n«К составам»." % _token(selected_unit_id)


func _profile_summary(key: String) -> String:
    var stats = setup.catalog_entry(key)
    if stats == null:
        return "Профиль недоступен."
    var hp: int = stats.commander.max_hp() if stats.commander != null else stats.max_hp
    var mp: int = stats.commander.max_mp() if stats.commander != null else (stats.monster.max_mp if stats.monster != null else 0)
    var power: int = stats.melee_skill.skill_power if stats.melee_skill != null else stats.attack
    var abilities: PackedStringArray = []
    if stats.special_skill != null:
        abilities.append("2: %s" % stats.special_skill.display_name)
    if stats.magic_spell != null:
        abilities.append("F: %s" % stats.magic_spell.display_name)
    if abilities.is_empty():
        abilities.append("Обычная физическая атака")
    return "HP %d · MP %d · Движение %d · Сила удара %d\n%s" % [hp, mp, stats.movement, power, " · ".join(abilities)]


func _validation_message() -> String:
    return "Проверьте составы и позиции: " + "; ".join(setup.validation_errors())


func _on_profile_selected(index: int, unit_id: String) -> void:
    if _refreshing or index < 0 or index >= PROFILE_KEYS.size():
        return
    setup.set_profile(unit_id, PROFILE_KEYS[index])
    _refresh_roster()


func _on_ai_toggled(enabled: bool) -> void:
    if not _refreshing:
        setup.enemy_ai_enabled = enabled


func _on_defaults_pressed() -> void:
    setup.reset_defaults()
    selected_unit_id = "ally_1"
    _status_override = ""
    _refresh_roster()


func _on_next_pressed() -> void:
    if not setup.is_valid():
        set_status(_validation_message())
        return
    show_deployment()
    deployment_requested.emit()
    selection_changed.emit(selected_unit_id)


func _on_unit_selected(unit_id: String) -> void:
    selected_unit_id = unit_id
    _status_override = ""
    _refresh_deployment()
    selection_changed.emit(unit_id)


func _on_positions_reset() -> void:
    setup.reset_positions()
    _status_override = "Стартовые позиции восстановлены. Составы сохранены."
    _refresh_deployment()
    placement_changed.emit()
    selection_changed.emit(selected_unit_id)


func _on_start_pressed() -> void:
    if stage != "deployment":
        return
    if not setup.is_valid():
        set_status(_validation_message())
        return
    battle_requested.emit()


func _token(unit_id: String) -> String:
    return unit_id.replace("ally_", "С").replace("enemy_", "К")
