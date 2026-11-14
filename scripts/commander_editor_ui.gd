extends Control
## Local commander draft. The demo owns applying the result to preparation.

signal applied(options: Dictionary)
signal cancelled

const Build = preload("res://scripts/commander_build.gd")
const POINT_KEYS: Array[String] = ["STR", "AGI", "WIS", "INT"]
const POINT_NAMES: Dictionary = {"STR": "Сила", "AGI": "Ловкость", "WIS": "Мудрость", "INT": "Интеллект"}
const ARMOR_NAMES: Array[String] = ["Без брони", "Лёгкая броня", "Средняя броня", "Тяжёлая броня"]
const TEXT = Color(0.94, 0.96, 0.97)
const MUTED = Color(0.67, 0.76, 0.80)
const GOLD = Color(0.99, 0.83, 0.44)
const ERROR = Color(1.0, 0.57, 0.54)

var base_stats
var options: Dictionary = {}
var level_spin: SpinBox
var armor_option: OptionButton
var point_spins: Dictionary = {}
var remaining_label: Label
var preview_label: Label
var apply_button: Button
var cancel_button: Button
var reset_button: Button
var status_label: Label
var _ability_label: Label
var _refreshing: bool = false
var _notice: String = ""


func configure(unit_label: String, stats, initial_options: Dictionary) -> void:
    base_stats = stats
    options = initial_options.duplicate(true)
    _notice = ""
    for child in get_children():
        remove_child(child)
        child.free()
    point_spins.clear()
    position = Vector2.ZERO
    size = Vector2(1440, 900)
    mouse_filter = Control.MOUSE_FILTER_STOP
    theme = _make_theme()
    var shade := ColorRect.new()
    shade.color = Color(0.025, 0.045, 0.065, 0.93)
    shade.size = size
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(shade)
    var card := _panel(self, Vector2(200, 70), Vector2(1040, 760), Color(0.085, 0.14, 0.19))
    _label(card, "НАСТРОЙКА КОМАНДИРА · " + unit_label, Vector2(28, 19), Vector2(925, 42), 25, GOLD)
    _button(card, "×", Vector2(966, 20), Vector2(46, 38), _on_cancel_pressed)
    _label(card, "Настройки применятся после «Начать бой». Умения, материя, пассивная способность\nи движение остаются как в выбранном профиле.", Vector2(28, 70), Vector2(984, 49), 15, MUTED)

    var controls := _panel(card, Vector2(28, 136), Vector2(446, 450), Color(0.11, 0.18, 0.23))
    _label(controls, "Уровень", Vector2(18, 17), Vector2(180, 30), 18)
    level_spin = _spin(controls, "CommanderLevel", Vector2(250, 13), Vector2(168, 42), 1, 999)
    level_spin.value_changed.connect(_on_level_changed)
    _label(controls, "Броня", Vector2(18, 72), Vector2(170, 30), 18)
    armor_option = OptionButton.new()
    armor_option.name = "CommanderArmor"
    armor_option.position = Vector2(200, 66)
    for name in ARMOR_NAMES:
        armor_option.add_item(name)
    controls.add_child(armor_option)
    armor_option.size = Vector2(218, 42)
    armor_option.item_selected.connect(_on_armor_selected)
    _label(controls, "ОЧКИ ЗА УРОВНИ", Vector2(18, 126), Vector2(400, 27), 16, MUTED)
    for index in range(POINT_KEYS.size()):
        var key: String = POINT_KEYS[index]
        var y: float = 165 + index * 51
        _label(controls, key + " · " + POINT_NAMES[key], Vector2(18, y + 4), Vector2(248, 32), 17)
        var spin := _spin(controls, "Points_" + key, Vector2(282, y), Vector2(136, 40), 0, 2994)
        if key == "WIS":
            spin.tooltip_text = "WIS повышает магическую защиту (MDEF) и регенерацию MP в конце собственного хода."
        spin.value_changed.connect(_on_points_changed.bind(key))
        point_spins[key] = spin
    remaining_label = _label(controls, "", Vector2(18, 380), Vector2(400, 60), 18, GOLD)
    remaining_label.name = "RemainingPoints"

    var preview := _panel(card, Vector2(498, 136), Vector2(514, 450), Color(0.11, 0.18, 0.23))
    _label(preview, "ИТОГОВЫЕ ПАРАМЕТРЫ", Vector2(18, 16), Vector2(478, 28), 17, GOLD)
    preview_label = _label(preview, "", Vector2(18, 54), Vector2(478, 248), 17)
    preview_label.name = "CommanderPreview"
    _ability_label = _label(preview, "", Vector2(18, 310), Vector2(478, 122), 14, MUTED)
    _ability_label.name = "CommanderAbilities"

    status_label = _label(card, "", Vector2(28, 606), Vector2(984, 63), 15, MUTED)
    status_label.name = "CommanderStatus"
    reset_button = _button(card, "Как в исходном профиле", Vector2(28, 690), Vector2(296, 46), _on_reset_pressed)
    reset_button.name = "ResetCommander"
    cancel_button = _button(card, "Отмена", Vector2(520, 690), Vector2(218, 46), _on_cancel_pressed)
    cancel_button.name = "CancelCommander"
    apply_button = _button(card, "Применить к бойцу", Vector2(760, 690), Vector2(252, 46), _on_apply_pressed)
    apply_button.name = "ApplyCommander"
    _refresh()


func _refresh() -> void:
    _refreshing = true
    var validation: Dictionary = Build.validate(base_stats, options)
    apply_button.disabled = not validation.ok
    if not validation.ok:
        preview_label.text = "Проверьте настройки командира."
        status_label.text = str(validation.reason)
        status_label.add_theme_color_override("font_color", ERROR)
        _refreshing = false
        return
    var values: Dictionary = Build.preview(base_stats, options)
    var stats: Dictionary = values.stats
    var physical: Dictionary = values.get("pdef_by_type", {})
    level_spin.set_value_no_signal(int(options.level))
    armor_option.select(int(options.armor))
    var bases: Dictionary = base_stats.commander.base_record()
    var unspent: int = int(values.unspent)
    for key in POINT_KEYS:
        var spin: SpinBox = point_spins[key]
        var maximum: int = int(options[key]) + unspent
        if key == "STR" or key == "INT":
            maximum = mini(maximum, 45 - int(bases[key.to_lower()]))
        spin.max_value = maxi(0, maximum)
        spin.set_value_no_signal(int(options[key]))
    remaining_label.text = "Осталось очков: %d\nВсего за уровни: %d" % [unspent, 3 * (int(options.level) - 1)]
    preview_label.text = "HP %d     MP %d\nSTR %d   AGI %d   WIS %d   INT %d\n\nФиз. урон (STR) +%.0f%%\nМаг. урон (INT) +%.0f%%\nУклонение %.1f%% · Крит %.1f%% ×%.1f\nPDEF: кол. %.0f%% · руб. %.0f%% · дроб. %.0f%%\nMDEF (WIS + броня) %.1f%% · %s" % [
        values.hp, values.mp, stats.STR, stats.AGI, stats.WIS, stats.INT,
        values.physical_bonus, values.magic_bonus, values.evasion, values.crit,
        base_stats.commander.critical_multiplier(), physical.get(0, values.pdef),
        physical.get(1, values.pdef), physical.get(2, values.pdef),
        values.mdef, ARMOR_NAMES[int(options.armor)]]
    _ability_label.text = _ability_text()
    status_label.text = _notice if not _notice.is_empty() else "За уровень: 3 очка; STR/INT не выше 45. STR усиливает физический урон, INT — магический.\nWIS повышает магическое сопротивление (MDEF) и регенерацию MP. Очки можно оставить свободными."
    status_label.add_theme_color_override("font_color", MUTED)
    status_label.size = Vector2(984, 63)
    preview_label.size = Vector2(478, 248)
    _refreshing = false


func _ability_text() -> String:
    var lines: PackedStringArray = []
    var power: int = base_stats.melee_skill.skill_power if base_stats.melee_skill != null else base_stats.attack
    lines.append("1 · Обычный удар · сила %d · 1 гекс." % power)
    if base_stats.special_skill != null:
        var skill = base_stats.special_skill
        lines.append("2 · %s · %d MP · %d–%d гекс." % [skill.display_name, skill.mana_cost, skill.min_range, skill.max_range])
    if base_stats.magic_spell != null:
        lines.append("F · %s · %d MP" % [base_stats.magic_spell.display_name, base_stats.magic_spell.mana_cost])
    lines.append("Движение: %d. Набор умений сохраняется." % base_stats.movement)
    return "\n".join(lines)


func _on_level_changed(value: float) -> void:
    if _refreshing:
        return
    var old: Dictionary = options.duplicate(true)
    options = Build.resize(base_stats, options, int(value))
    var trimmed: bool = false
    for key in POINT_KEYS:
        if int(options.get(key, 0)) < int(old.get(key, 0)):
            trimmed = true
    _notice = "Часть очков снята по новому бюджету. Приоритет сохранения: STR → AGI → WIS → INT." if trimmed else "Уровень изменён. Распределите оставшиеся очки."
    _refresh()


func _on_armor_selected(index: int) -> void:
    if _refreshing or index < 0 or index >= ARMOR_NAMES.size():
        return
    options.armor = index
    _notice = "Броня изменена. Итоговые защита и уклонение пересчитаны."
    _refresh()


func _on_points_changed(value: float, key: String) -> void:
    if _refreshing or not POINT_KEYS.has(key):
        return
    options[key] = int(value)
    _notice = ""
    _refresh()


func _on_reset_pressed() -> void:
    options = Build.defaults(base_stats)
    _notice = "Восстановлены настройки исходного профиля. Нажмите «Применить к бойцу», чтобы принять их."
    _refresh()


func _on_apply_pressed() -> void:
    var result: Dictionary = Build.validate(base_stats, options)
    if not result.ok:
        _refresh()
        return
    applied.emit(options.duplicate(true))


func _on_cancel_pressed() -> void:
    cancelled.emit()


func _make_theme() -> Theme:
    var result := Theme.new()
    result.default_font = ThemeDB.fallback_font
    result.default_font_size = 17
    for type_name in ["Label", "Button", "OptionButton", "PopupMenu", "LineEdit", "SpinBox"]:
        result.set_color("font_color", type_name, TEXT)
        result.set_color("font_hover_color", type_name, TEXT)
        result.set_color("font_pressed_color", type_name, TEXT)
    for type_name in ["Button", "OptionButton", "LineEdit"]:
        result.set_stylebox("normal", type_name, _box(Color(0.14, 0.23, 0.28), Color(0.29, 0.40, 0.46)))
        result.set_stylebox("hover", type_name, _box(Color(0.21, 0.33, 0.39), Color(0.48, 0.64, 0.70)))
        result.set_stylebox("pressed", type_name, _box(Color(0.19, 0.35, 0.40), GOLD))
        result.set_stylebox("disabled", type_name, _box(Color(0.075, 0.12, 0.15), Color(0.19, 0.28, 0.32)))
        result.set_stylebox("focus", type_name, _box(Color(0, 0, 0, 0), GOLD))
        result.set_color("font_disabled_color", type_name, Color(0.45, 0.55, 0.59))
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
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    panel.add_theme_stylebox_override("panel", _box(fill, Color(0.28, 0.40, 0.46)))
    parent.add_child(panel)
    panel.size = dimensions
    return panel


func _label(parent: Node, text: String, at: Vector2, dimensions: Vector2,
        font_size: int = 17, color: Color = TEXT) -> Label:
    var label := Label.new()
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.text = text
    label.position = at
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.clip_text = true
    parent.add_child(label)
    label.size = dimensions
    return label


func _button(parent: Node, text: String, at: Vector2, dimensions: Vector2,
        callback: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.position = at
    button.pressed.connect(callback)
    parent.add_child(button)
    button.size = dimensions
    return button


func _spin(parent: Node, label: String, at: Vector2, dimensions: Vector2,
        minimum: int, maximum: int) -> SpinBox:
    var spin := SpinBox.new()
    spin.name = label
    spin.position = at
    spin.min_value = minimum
    spin.max_value = maximum
    spin.step = 1
    spin.allow_lesser = false
    spin.allow_greater = false
    parent.add_child(spin)
    spin.size = dimensions
    return spin
