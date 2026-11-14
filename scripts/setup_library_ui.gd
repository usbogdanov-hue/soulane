extends Control
## Slot and transfer controls. Validation and persistence belong to the demo.

signal save_requested(slot: int, name: String)
signal load_requested(slot: int)
signal delete_requested(slot: int)
signal export_requested
signal import_requested(code: String)
signal close_requested

const TEXT = Color(0.94, 0.96, 0.97)
const MUTED = Color(0.67, 0.76, 0.80)
const GOLD = Color(0.99, 0.83, 0.44)
const ERROR = Color(1.0, 0.57, 0.54)

var selected_slot: int = 0
var slot_buttons: Array[Button] = []
var name_edit: LineEdit
var code_edit: TextEdit
var save_button: Button
var load_button: Button
var delete_button: Button
var export_button: Button
var import_button: Button
var close_button: Button
var status_label: Label
var _slots: Array[Dictionary] = []
var _delete_confirmation: int = -1


func configure(slots: Array[Dictionary], draft_summary: String) -> void:
    for child in get_children():
        remove_child(child)
        child.free()
    slot_buttons.clear()
    selected_slot = 0
    _delete_confirmation = -1
    position = Vector2.ZERO
    size = Vector2(1440, 900)
    mouse_filter = Control.MOUSE_FILTER_STOP
    theme = _make_theme()
    var shade := ColorRect.new()
    shade.color = Color(0.025, 0.045, 0.065, 0.93)
    shade.size = size
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(shade)
    var card := Panel.new()
    card.position = Vector2(160, 60)
    card.size = Vector2(1120, 780)
    card.mouse_filter = Control.MOUSE_FILTER_STOP
    card.add_theme_stylebox_override("panel", _box(Color(0.085, 0.14, 0.19), Color(0.32, 0.45, 0.51)))
    add_child(card)

    _label(card, "СОХРАНЁННЫЕ СОСТАВЫ", Vector2(28, 20), Vector2(860, 39), 26, GOLD)
    close_button = _button(card, "Закрыть", Vector2(910, 20), Vector2(182, 38), func(): close_requested.emit())
    close_button.name = "CloseLibrary"
    _label(card, "Сохраняются составы, позиции, арена и управление красными. Загрузка заменит черновик; бой начнётся после «Начать бой».", Vector2(28, 69), Vector2(1064, 43), 15, MUTED)
    _label(card, "ВЫБЕРИТЕ СЛОТ", Vector2(28, 115), Vector2(350, 25), 15, MUTED)
    _label(card, "ТЕКУЩИЙ ЧЕРНОВИК", Vector2(406, 115), Vector2(686, 25), 15, MUTED)
    for index in range(3):
        var button := _button(card, "", Vector2(28, 151 + index * 74), Vector2(350, 60), _select_slot.bind(index))
        button.name = "SetupSlot%d" % (index + 1)
        button.toggle_mode = true
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.add_theme_font_size_override("font_size", 16)
        button.clip_text = true
        button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        slot_buttons.append(button)
    _label(card, draft_summary, Vector2(406, 151), Vector2(686, 151), 16, TEXT)
    save_button = _button(card, "Сохранить в слот", Vector2(406, 322), Vector2(214, 46), _on_save_pressed)
    save_button.name = "SaveSetup"
    load_button = _button(card, "Загрузить", Vector2(642, 322), Vector2(214, 46), _on_load_pressed)
    load_button.name = "LoadSetup"
    delete_button = _button(card, "Удалить", Vector2(878, 322), Vector2(214, 46), _on_delete_pressed)
    delete_button.name = "DeleteSetup"
    _label(card, "Название для сохранения", Vector2(28, 382), Vector2(350, 27), 16, MUTED)
    name_edit = LineEdit.new()
    name_edit.name = "SetupName"
    name_edit.position = Vector2(28, 416)
    name_edit.size = Vector2(350, 42)
    name_edit.max_length = 32
    name_edit.placeholder_text = "Например: Колонны с личом"
    card.add_child(name_edit)
    _label(card, "Выберите слот и задайте название.\n«Сохранить в слот» заменит прежний состав в этом слоте.", Vector2(406, 386), Vector2(686, 69), 15, MUTED)

    _label(card, "ПЕРЕНОС СОСТАВА", Vector2(28, 484), Vector2(1064, 28), 19, GOLD)
    _label(card, "Создайте код и скопируйте его себе. Для загрузки вставьте код в поле и нажмите «Применить код».", Vector2(28, 518), Vector2(1064, 25), 14, MUTED)
    code_edit = TextEdit.new()
    code_edit.name = "SetupCode"
    code_edit.position = Vector2(28, 552)
    code_edit.size = Vector2(1064, 110)
    code_edit.placeholder_text = "Код можно скопировать отсюда или вставить сюда. Ctrl+A — выделить, Ctrl+C / Ctrl+V — копировать / вставить."
    code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    code_edit.add_theme_font_size_override("font_size", 14)
    card.add_child(code_edit)
    export_button = _button(card, "Создать код черновика", Vector2(28, 682), Vector2(270, 43), _on_export_pressed)
    export_button.name = "ExportSetup"
    import_button = _button(card, "Применить код", Vector2(314, 682), Vector2(270, 43), _on_import_pressed)
    import_button.name = "ImportSetup"
    status_label = _label(card, "", Vector2(608, 680), Vector2(484, 75), 15, GOLD)
    status_label.name = "LibraryStatus"
    _label(card, "Составы хранятся на этом устройстве; код можно перенести.", Vector2(28, 742), Vector2(550, 25), 14, MUTED)
    refresh_slots(slots)
    _select_slot(0)


func refresh_slots(slots: Array[Dictionary]) -> void:
    _slots.clear()
    for index in range(3):
        _slots.append(slots[index].duplicate(true) if index < slots.size() else {"occupied": false, "name": ""})
        var item: Dictionary = _slots[index]
        var occupied: bool = bool(item.get("occupied", false))
        var title: String = "Слот %d · %s" % [index + 1, str(item.get("name", "")) if occupied else "Пусто"]
        var details: String = str(item.get("summary", "")) if occupied else ""
        slot_buttons[index].text = title + ("\n" + details if not details.is_empty() else "")
        slot_buttons[index].tooltip_text = title + ("\n" + details if not details.is_empty() else "")
        slot_buttons[index].set_pressed_no_signal(index == selected_slot)
    _delete_confirmation = -1
    _refresh_actions()


func set_status(text: String, error: bool = false) -> void:
    status_label.text = text
    status_label.size = Vector2(484, 75)
    status_label.add_theme_color_override("font_color", ERROR if error else GOLD)


func set_code(code: String) -> void:
    code_edit.text = code
    code_edit.grab_focus()
    code_edit.select_all()


func _select_slot(index: int) -> void:
    if index < 0 or index >= _slots.size():
        return
    selected_slot = index
    _delete_confirmation = -1
    for slot in range(slot_buttons.size()):
        slot_buttons[slot].set_pressed_no_signal(slot == index)
    name_edit.text = str(_slots[index].get("name", "")) if bool(_slots[index].get("occupied", false)) else ""
    _refresh_actions()
    set_status("Выбран слот %d." % (index + 1))


func _refresh_actions() -> void:
    var occupied: bool = selected_slot >= 0 and selected_slot < _slots.size() and bool(_slots[selected_slot].get("occupied", false))
    load_button.disabled = not occupied
    delete_button.disabled = not occupied
    delete_button.text = "Удалить"


func _on_save_pressed() -> void:
    _delete_confirmation = -1
    _refresh_actions()
    save_requested.emit(selected_slot, name_edit.text)


func _on_load_pressed() -> void:
    _delete_confirmation = -1
    _refresh_actions()
    load_requested.emit(selected_slot)


func _on_delete_pressed() -> void:
    if delete_button.disabled:
        return
    if _delete_confirmation != selected_slot:
        _delete_confirmation = selected_slot
        delete_button.text = "Подтвердить удаление"
        set_status("Повторное нажатие удалит состав из слота %d." % (selected_slot + 1))
        return
    _delete_confirmation = -1
    _refresh_actions()
    delete_requested.emit(selected_slot)


func _on_export_pressed() -> void:
    _delete_confirmation = -1
    _refresh_actions()
    export_requested.emit()


func _on_import_pressed() -> void:
    _delete_confirmation = -1
    _refresh_actions()
    import_requested.emit(code_edit.text)


func _make_theme() -> Theme:
    var result := Theme.new()
    result.default_font = ThemeDB.fallback_font
    result.default_font_size = 17
    for type_name in ["Label", "Button", "LineEdit", "TextEdit"]:
        result.set_color("font_color", type_name, TEXT)
        result.set_color("font_hover_color", type_name, TEXT)
        result.set_color("font_pressed_color", type_name, TEXT)
    for type_name in ["Button", "LineEdit", "TextEdit"]:
        result.set_stylebox("normal", type_name, _box(Color(0.12, 0.20, 0.25), Color(0.28, 0.41, 0.47)))
        result.set_stylebox("focus", type_name, _box(Color(0, 0, 0, 0), GOLD))
    result.set_stylebox("hover", "Button", _box(Color(0.21, 0.33, 0.39), Color(0.48, 0.64, 0.70)))
    result.set_stylebox("pressed", "Button", _box(Color(0.19, 0.35, 0.40), GOLD))
    result.set_stylebox("disabled", "Button", _box(Color(0.075, 0.12, 0.15), Color(0.19, 0.28, 0.32)))
    result.set_color("font_disabled_color", "Button", Color(0.45, 0.55, 0.59))
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


func _label(parent: Node, text: String, at: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
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


func _button(parent: Node, text: String, at: Vector2, dimensions: Vector2, callback: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.position = at
    button.size = dimensions
    button.mouse_filter = Control.MOUSE_FILTER_STOP
    button.pressed.connect(callback)
    parent.add_child(button)
    return button
