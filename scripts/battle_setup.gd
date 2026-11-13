extends RefCounted
## Data-only draft for the three-versus-three preparation screen.
## Deployment rules belong to preparation, not combat movement or initiative.

const PROFILE_KEYS: Array[String] = ["male", "female", "falcon", "hellhound", "lich"]
const UNIT_IDS: Array[String] = ["ally_1", "enemy_1", "ally_2", "enemy_2", "ally_3", "enemy_3"]
const CATALOG: Dictionary = {
    "male": preload("res://data/demo_male_lv25.tres"),
    "female": preload("res://data/demo_female_lv25.tres"),
    "falcon": preload("res://data/monsters/falcon_unit_v14.tres"),
    "hellhound": preload("res://data/monsters/hellhound_unit_v14.tres"),
    "lich": preload("res://data/monsters/lich_unit_v14.tres"),
}

var columns: int
var rows: int
var profile_keys: Dictionary = {}
var positions: Dictionary = {}
var enemy_ai_enabled: bool = true


func _init(width: int = 9, height: int = 7) -> void:
    columns = maxi(4, width)
    rows = maxi(3, height)
    reset_defaults()


func unit_ids() -> Array[String]:
    return UNIT_IDS.duplicate()


func team_for(unit_id: String) -> String:
    if not UNIT_IDS.has(unit_id):
        return ""
    return "blue" if unit_id.begins_with("ally_") else "red"


func profile_key(unit_id: String) -> String:
    if not UNIT_IDS.has(unit_id):
        return ""
    var value = profile_keys.get(unit_id, "")
    return value if value is String else ""


func profile_stats(unit_id: String) -> SuleynUnitStats:
    return catalog_entry(profile_key(unit_id))


static func catalog_entry(key: String) -> SuleynUnitStats:
    return CATALOG.get(key) as SuleynUnitStats


static func profile_label(key: String) -> String:
    var stats: SuleynUnitStats = catalog_entry(key)
    return stats.display_name if stats != null else ""


func set_profile(unit_id: String, key: String) -> bool:
    if not UNIT_IDS.has(unit_id) or not CATALOG.has(key):
        return false
    profile_keys[unit_id] = key
    return true


func unit_at(cell: Vector2i) -> String:
    # Only known slots can represent draft occupants; corrupted extra keys
    # are rejected by validation_errors rather than becoming playable units.
    for unit_id in UNIT_IDS:
        var location = positions.get(unit_id)
        if typeof(location) == TYPE_VECTOR2I and location == cell:
            return unit_id
    return ""


func cell_is_deployment(side: String, cell: Vector2i) -> bool:
    if cell.x < 0 or cell.x >= columns or cell.y < 0 or cell.y >= rows:
        return false
    if side == "blue":
        return cell.x <= 1
    if side == "red":
        return cell.x >= columns - 2
    return false


func place_unit(unit_id: String, cell: Vector2i) -> bool:
    var side: String = team_for(unit_id)
    if side.is_empty() or not cell_is_deployment(side, cell):
        return false
    # The chosen slot must exist before a placement can edit it.
    if not positions.has(unit_id):
        return false
    for other_id in positions:
        var location = positions[other_id]
        if other_id != unit_id and typeof(location) == TYPE_VECTOR2I and location == cell:
            return false
    positions[unit_id] = cell
    return true


func reset_positions() -> void:
    positions.clear()
    var center_row: int = rows / 2
    var spacing: int = maxi(1, (rows - 1) / 3)
    for slot in range(3):
        var row: int = center_row + (slot - 1) * spacing
        positions["ally_%d" % (slot + 1)] = Vector2i(1, row)
        positions["enemy_%d" % (slot + 1)] = Vector2i(columns - 2, row)


func reset_defaults() -> void:
    profile_keys = {
        "ally_1": "male", "enemy_1": "hellhound",
        "ally_2": "female", "enemy_2": "falcon",
        "ally_3": "falcon", "enemy_3": "lich",
    }
    enemy_ai_enabled = true
    reset_positions()


func validation_errors() -> PackedStringArray:
    var errors: PackedStringArray = []
    if columns < 4 or rows < 3:
        errors.append("Поле подготовки должно быть не меньше 4×3.")
    if profile_keys.size() != UNIT_IDS.size():
        errors.append("В составе должны быть ровно три бойца каждой команды.")
    if positions.size() != UNIT_IDS.size():
        errors.append("Для каждого бойца требуется стартовый гекс.")
    for key in profile_keys:
        if not UNIT_IDS.has(key):
            errors.append("Неизвестный боец в составе: %s." % str(key))
    for key in positions:
        if not UNIT_IDS.has(key):
            errors.append("Неизвестный боец в расстановке: %s." % str(key))
    var occupied: Dictionary = {}
    for unit_id in UNIT_IDS:
        if not profile_keys.has(unit_id) or catalog_entry(profile_key(unit_id)) == null:
            errors.append("Для %s выберите доступного бойца." % unit_id)
        if not positions.has(unit_id) or typeof(positions[unit_id]) != TYPE_VECTOR2I:
            errors.append("Для %s нужен корректный стартовый гекс." % unit_id)
            continue
        var cell: Vector2i = positions[unit_id]
        if not cell_is_deployment(team_for(unit_id), cell):
            errors.append("Боец %s находится вне зоны своей команды." % unit_id)
        if occupied.has(cell):
            errors.append("Гекс занят сразу несколькими бойцами.")
        occupied[cell] = unit_id
    return errors


func is_valid() -> bool:
    return validation_errors().is_empty()


func copy():
    var draft = get_script().new(columns, rows)
    # A copy preserves even a corrupted draft so validation cannot be bypassed
    # by constructor clamping when the caller snapshots it.
    draft.columns = columns
    draft.rows = rows
    draft.profile_keys = profile_keys.duplicate(true)
    draft.positions = positions.duplicate(true)
    draft.enemy_ai_enabled = enemy_ai_enabled
    return draft
