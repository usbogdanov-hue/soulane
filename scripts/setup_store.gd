extends RefCounted
## Validated, local preparation library. Runtime HP, turns and RNG are never saved.
const Codec = preload("res://scripts/setup_codec.gd")
const FORMAT: String = "suleyn.library"
const VERSION: int = 1
const SLOT_COUNT: int = 3
const MAX_FILE_BYTES: int = 256 * 1024
const MAX_NAME_LENGTH: int = 32

var storage_path: String
var _data: Dictionary = _empty_data()
var _loaded: bool = false
var _read_locked: bool = false
var _main_valid: bool = false
var _read_reason: String = ""


func _init(path: String = "user://battle_setups.json") -> void:
    storage_path = path


static func _empty_data() -> Dictionary:
    return {"format": FORMAT, "version": VERSION, "last_setup": null,
        "slots": [null, null, null]}


func load_library() -> Dictionary:
    var has_main: bool = FileAccess.file_exists(storage_path)
    var has_backup: bool = FileAccess.file_exists(storage_path + ".bak")
    if not has_main and not has_backup:
        _data = _empty_data()
        _loaded = true
        _read_locked = false
        _main_valid = false
        _read_reason = ""
        return _result(true)
    var current: Dictionary = _read_file(storage_path) if has_main else _result(false, "Файл сохранений отсутствует.")
    if current.ok:
        _data = current.data
        _loaded = true
        _read_locked = false
        _main_valid = true
        _read_reason = ""
        return _result(true)
    if has_backup:
        var backup: Dictionary = _read_file(storage_path + ".bak")
        if backup.ok:
            _data = backup.data
            _loaded = true
            _read_locked = false
            _main_valid = false
            _read_reason = "Основной файл не прочитан. Восстановлена резервная копия составов."
            return _result(true, _read_reason, true)
    _loaded = true
    _read_locked = true
    _main_valid = false
    _read_reason = "Не удалось прочитать сохранения. Файлы сохранены; используйте перенос кодом. " + str(current.reason)
    return _result(false, _read_reason)


func list_slots() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for slot in _data.slots:
        result.append({"occupied": slot != null, "name": str(slot.name) if slot != null else ""})
    return result


func slot_setup(index: int):
    if index < 0 or index >= SLOT_COUNT or _data.slots[index] == null:
        return null
    return Codec.from_data(_data.slots[index].setup).setup


func last_setup():
    return null if _data.last_setup == null else Codec.from_data(_data.last_setup).setup


func save_slot(index: int, name: String, setup) -> Dictionary:
    if index < 0 or index >= SLOT_COUNT:
        return _result(false, "Выберите один из трёх слотов.")
    var checked_name: Dictionary = _checked_name(name)
    if not checked_name.ok:
        return checked_name
    var encoded: Dictionary = Codec.encode(setup)
    if not encoded.ok:
        return _result(false, str(encoded.reason))
    var ready: Dictionary = _ensure_loaded()
    if not ready.ok:
        return ready
    var candidate: Dictionary = _data.duplicate(true)
    candidate.slots[index] = {"name": checked_name.name, "setup": encoded.data}
    return _commit(candidate)


func delete_slot(index: int) -> Dictionary:
    if index < 0 or index >= SLOT_COUNT:
        return _result(false, "Выберите один из трёх слотов.")
    var ready: Dictionary = _ensure_loaded()
    if not ready.ok:
        return ready
    if _data.slots[index] == null:
        return _result(false, "Этот слот уже пуст.")
    var candidate: Dictionary = _data.duplicate(true)
    candidate.slots[index] = null
    return _commit(candidate)


func save_last(setup) -> Dictionary:
    var encoded: Dictionary = Codec.encode(setup)
    if not encoded.ok:
        return _result(false, str(encoded.reason))
    var ready: Dictionary = _ensure_loaded()
    if not ready.ok:
        return ready
    var candidate: Dictionary = _data.duplicate(true)
    candidate.last_setup = encoded.data
    return _commit(candidate)


func _ensure_loaded() -> Dictionary:
    if not _loaded:
        var loaded: Dictionary = load_library()
        if not loaded.ok:
            return loaded
    return _result(not _read_locked, _read_reason if _read_locked else "")


func _commit(candidate: Dictionary) -> Dictionary:
    if OS.has_feature("web") and not OS.is_userfs_persistent():
        return _result(false, "Браузер не разрешил постоянное хранилище. Используйте код состава для переноса.")
    if _main_valid and not _read_file(storage_path).ok:
        _read_locked = true
        _main_valid = false
        _read_reason = "Файл сохранений изменён или повреждён. Прежние данные оставлены; используйте перенос кодом."
        return _result(false, _read_reason)
    var text: String = JSON.stringify(candidate)
    if text.to_utf8_buffer().size() > MAX_FILE_BYTES:
        return _result(false, "Сохранение слишком большое.")
    var temporary: String = storage_path + ".tmp"
    var file := FileAccess.open(temporary, FileAccess.WRITE)
    if file == null:
        return _result(false, "Не удалось записать сохранения: " + error_string(FileAccess.get_open_error()))
    file.store_string(text)
    file.flush()
    var write_error: Error = file.get_error()
    file.close()
    if write_error != OK:
        _remove_file(temporary)
        return _result(false, "Запись сохранений не завершена: " + error_string(write_error))
    if _main_valid:
        var backup_temporary: String = storage_path + ".bak.tmp"
        var copy_error: Error = DirAccess.copy_absolute(_absolute(storage_path), _absolute(backup_temporary))
        if copy_error != OK:
            _remove_file(temporary)
            _remove_file(backup_temporary)
            return _result(false, "Не удалось создать резервную копию. Прежнее сохранение оставлено.")
        var backup_error: Error = DirAccess.rename_absolute(_absolute(backup_temporary), _absolute(storage_path + ".bak"))
        if backup_error != OK:
            _remove_file(temporary)
            _remove_file(backup_temporary)
            return _result(false, "Не удалось обновить резервную копию. Прежнее сохранение оставлено.")
    var rename_error: Error = DirAccess.rename_absolute(_absolute(temporary), _absolute(storage_path))
    if rename_error != OK:
        _remove_file(temporary)
        return _result(false, "Не удалось применить сохранение. Прежние данные оставлены.")
    _data = candidate
    _main_valid = true
    _read_reason = ""
    if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
        var bridge = Engine.get_singleton("JavaScriptBridge")
        if bridge.has_method("force_fs_sync"):
            bridge.call("force_fs_sync")
    return _result(true)


func _read_file(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return _result(false, "Файл недоступен для чтения.")
    if file.get_length() > MAX_FILE_BYTES:
        file.close()
        return _result(false, "Файл сохранений слишком большой.")
    var text: String = file.get_as_text()
    var read_error: Error = file.get_error()
    file.close()
    if read_error != OK and read_error != ERR_FILE_EOF:
        return _result(false, "Ошибка чтения файла сохранений.")
    var parser := JSON.new()
    if parser.parse(text) != OK:
        return _result(false, "Некорректный файл составов.")
    return _validated_library(parser.data)


static func _validated_library(value: Variant) -> Dictionary:
    if not value is Dictionary or not _has_keys(value, ["format", "version", "last_setup", "slots"]):
        return _result(false, "Некорректная структура библиотеки.")
    if not value.format is String or value.format != FORMAT or not _is_version(value.version):
        return _result(false, "Версия библиотеки не поддерживается.")
    if not value.slots is Array or value.slots.size() != SLOT_COUNT:
        return _result(false, "В библиотеке должны быть три слота.")
    var canonical: Dictionary = _empty_data()
    if value.last_setup != null:
        var last: Dictionary = Codec.from_data(value.last_setup)
        if not last.ok:
            return _result(false, "Последний состав повреждён: " + str(last.reason))
        canonical.last_setup = Codec.encode(last.setup).data
    for index in range(SLOT_COUNT):
        var slot: Variant = value.slots[index]
        if slot == null:
            continue
        if not slot is Dictionary or not _has_keys(slot, ["name", "setup"]) or not slot.name is String:
            return _result(false, "Некорректный слот составов.")
        var name_result: Dictionary = _checked_name(slot.name)
        if not name_result.ok:
            return name_result
        var setup_result: Dictionary = Codec.from_data(slot.setup)
        if not setup_result.ok:
            return _result(false, "Сохранённый состав повреждён: " + str(setup_result.reason))
        canonical.slots[index] = {"name": name_result.name, "setup": Codec.encode(setup_result.setup).data}
    return {"ok": true, "reason": "", "data": canonical}


static func _checked_name(value: String) -> Dictionary:
    var name: String = value.strip_edges()
    if name.is_empty() or name.length() > MAX_NAME_LENGTH:
        return _result(false, "Название должно содержать от 1 до 32 символов.")
    for index in range(name.length()):
        var codepoint: int = name.unicode_at(index)
        if codepoint < 32 or codepoint == 127:
            return _result(false, "В названии нельзя использовать управляющие символы.")
    return {"ok": true, "reason": "", "name": name}


static func _has_keys(value: Dictionary, expected: Array) -> bool:
    if value.size() != expected.size():
        return false
    for key in expected:
        if not value.has(key):
            return false
    return true


static func _is_version(value: Variant) -> bool:
    return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) == VERSION


static func _absolute(path: String) -> String:
    return ProjectSettings.globalize_path(path)


static func _remove_file(path: String) -> void:
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(_absolute(path))


static func _result(ok: bool, reason: String = "", recovered: bool = false) -> Dictionary:
    return {"ok": ok, "reason": reason, "recovered": recovered}
