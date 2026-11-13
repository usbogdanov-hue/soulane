extends Control
## Read-only attack information; buttons choose a mode but never spend a turn.
signal mode_requested(mode: String)

var body: RichTextLabel
var mode_buttons: Dictionary = {}


func _init() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    size = Vector2(1440, 900)
    for index in range(3):
        var mode: String = ["basic", "special", "magic"][index]
        var button := Button.new()
        button.text = ["1 · Обычный удар", "2 · Умение", "F · Магия"][index]
        button.position = Vector2(44 + index * 262, 548)
        button.size = Vector2(250, 36)
        button.focus_mode = Control.FOCUS_NONE
        button.toggle_mode = true
        button.add_theme_font_size_override("font_size", 16)
        button.pressed.connect(func(): mode_requested.emit(mode))
        add_child(button)
        mode_buttons[mode] = button
    var panel := Panel.new()
    panel.position = Vector2(44, 594)
    panel.size = Vector2(774, 166)
    var box := StyleBoxFlat.new()
    box.bg_color = Color(0.055, 0.09, 0.13)
    box.border_color = Color(0.28, 0.41, 0.47)
    box.set_border_width_all(1)
    box.set_corner_radius_all(6)
    panel.add_theme_stylebox_override("panel", box)
    add_child(panel)
    body = RichTextLabel.new()
    body.position = Vector2(14, 10)
    body.size = Vector2(746, 146)
    body.bbcode_enabled = true
    body.scroll_active = false
    body.mouse_filter = Control.MOUSE_FILTER_IGNORE
    body.add_theme_font_size_override("normal_font_size", 14)
    body.add_theme_font_size_override("bold_font_size", 15)
    body.add_theme_color_override("default_color", Color(0.9, 0.94, 0.96))
    panel.add_child(body)


func present(text: String, mode: String, can_choose: bool) -> void:
    if body.text != text:
        body.text = text
    for key in mode_buttons:
        mode_buttons[key].set_pressed_no_signal(key == mode)
        mode_buttons[key].disabled = not can_choose
