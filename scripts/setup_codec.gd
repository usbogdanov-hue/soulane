extends RefCounted
## Portable plain-data setup format. Parsing never loads resources or executes
## objects, and no existing preparation or runtime state is modified.

const Setup = preload("res://scripts/battle_setup.gd")
const Arena = preload("res://scripts/battle_arena.gd")
const FORMAT: String = "suleyn.setup"
const VERSION: int = 2
const MAX_BYTES: int = 65536
const TOP_KEYS: Array[String] = ["format", "version", "columns", "rows", "arena", "enemy_ai", "units"]
const UNIT_KEYS: Array[String] = ["id", "profile", "x", "y"]


static func encode(setup) -> Dictionary:
    var failure: Dictionary = {"ok": false, "reason": "Нужна корректная подготовка боя.", "data": {}, "code": ""}
    if typeof(setup) != TYPE_OBJECT or not is_instance_valid(setup) or setup.get_script() != Setup:
        return failure
    if not _integer_in_range(setup.columns, 4, 20) or not _integer_in_range(setup.rows, 3, 14):
        failure.reason = "Размер поля должен быть от 4×3 до 20×14."
        return failure
    if not setup.is_valid():
        failure.reason = "Проверьте составы, арену и расстановку перед переносом."
        return failure
    var units: Array[Dictionary] = []
    for unit_id in Setup.UNIT_IDS:
        if not setup.is_enabled(unit_id):
            continue
        var cell: Vector2i = setup.positions[unit_id]
        units.append({"id": unit_id, "profile": setup.profile_key(unit_id), "x": cell.x, "y": cell.y})
    var data: Dictionary = {
        "format": FORMAT, "version": VERSION,
        "columns": setup.columns, "rows": setup.rows,
        "arena": setup.arena_key, "enemy_ai": setup.enemy_ai_enabled, "units": units,
    }
    return {"ok": true, "reason": "", "data": data, "code": JSON.stringify(data, "", true)}


static func decode(code: String) -> Dictionary:
    if code.to_utf8_buffer().size() > MAX_BYTES:
        return _failure("Код состава слишком длинный: максимум 64 КиБ.")
    if code.strip_edges().is_empty():
        return _failure("Вставьте код состава.")
    var parser := JSON.new()
    if parser.parse(code) != OK:
        return _failure("Код состава повреждён. Скопируйте его целиком.")
    return from_data(parser.data)


static func from_data(data: Variant) -> Dictionary:
    if not data is Dictionary or not _has_exact_keys(data, TOP_KEYS):
        return _failure("Неверная структура кода состава.")
    if typeof(data.format) != TYPE_STRING or data.format != FORMAT:
        return _failure("Этот код не является подготовкой Сулэйна.")
    if not _integer_in_range(data.version, 1, VERSION):
        return _failure("Версия кода состава не поддерживается.")
    if not _integer_in_range(data.columns, 4, 20) or not _integer_in_range(data.rows, 3, 14):
        return _failure("Размер поля должен быть от 4×3 до 20×14.")
    var columns: int = int(data.columns)
    var rows: int = int(data.rows)
    if typeof(data.arena) != TYPE_STRING or not Arena.is_supported(data.arena, columns, rows):
        return _failure("Арена неизвестна или недоступна для этого размера поля.")
    if typeof(data.enemy_ai) != TYPE_BOOL:
        return _failure("Неверная настройка управления красной командой.")
    if not data.units is Array or data.units.size() < 2 or data.units.size() > Setup.UNIT_IDS.size():
        return _failure("В коде нужны от одного до трёх бойцов каждой команды.")
    if int(data.version) == 1 and data.units.size() != Setup.UNIT_IDS.size():
        return _failure("В старом коде состава должны быть все шесть бойцов.")
    var profiles: Dictionary = {}
    var positions: Dictionary = {}
    for row in data.units:
        if not row is Dictionary or not _has_exact_keys(row, UNIT_KEYS):
            return _failure("Неверные данные бойца в коде состава.")
        if typeof(row.id) != TYPE_STRING or not Setup.UNIT_IDS.has(row.id) or profiles.has(row.id):
            return _failure("В коде есть неизвестный или повторяющийся боец.")
        if typeof(row.profile) != TYPE_STRING or not Setup.PROFILE_KEYS.has(row.profile):
            return _failure("В коде есть неизвестный профиль бойца.")
        if not _integer_in_range(row.x, 0, columns - 1) or not _integer_in_range(row.y, 0, rows - 1):
            return _failure("Координаты бойца должны быть целыми гексами внутри поля.")
        profiles[row.id] = row.profile
        positions[row.id] = Vector2i(int(row.x), int(row.y))
    var setup = Setup.new(columns, rows)
    for unit_id in Setup.UNIT_IDS:
        setup.enabled_slots[unit_id] = profiles.has(unit_id)
        if profiles.has(unit_id):
            setup.profile_keys[unit_id] = profiles[unit_id]
            setup.positions[unit_id] = positions[unit_id]
    setup.arena_key = data.arena
    setup.enemy_ai_enabled = data.enemy_ai
    if not setup.is_valid():
        return _failure("В каждой команде нужен боец, а выбранные бойцы должны стоять на свободных гексах своей зоны.")
    return {"ok": true, "reason": "", "setup": setup}


static func _integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
    if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
        return false
    var number: float = float(value)
    return is_finite(number) and number == floor(number) and number >= minimum and number <= maximum


static func _has_exact_keys(data: Dictionary, keys: Array[String]) -> bool:
    if data.size() != keys.size():
        return false
    for key in keys:
        if not data.has(key):
            return false
    return true


static func _failure(reason: String) -> Dictionary:
    return {"ok": false, "reason": reason, "setup": null}
