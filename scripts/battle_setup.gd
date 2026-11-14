extends RefCounted
## Data-only draft with up to three enabled fighters per team.
## Deployment rules belong to preparation, not combat movement or initiative.

const Arena = preload("res://scripts/battle_arena.gd")
const CommanderBuild = preload("res://scripts/commander_build.gd")

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
var enabled_slots: Dictionary = {}
var commander_options: Dictionary = {}
var enemy_ai_enabled: bool = true
var arena_key: String = "open"


func _init(width: int = 9, height: int = 7) -> void:
    columns = maxi(4, width)
    rows = maxi(3, height)
    reset_defaults()


func unit_ids() -> Array[String]:
    # Compact the active slots before interleaving so blue always starts, even
    # when its first or second UI slot is empty. Full teams retain the old order.
    var blue: Array[String] = []
    var red: Array[String] = []
    for unit_id in UNIT_IDS:
        if is_enabled(unit_id):
            if team_for(unit_id) == "blue":
                blue.append(unit_id)
            else:
                red.append(unit_id)
    var result: Array[String] = []
    for index in range(maxi(blue.size(), red.size())):
        if index < blue.size():
            result.append(blue[index])
        if index < red.size():
            result.append(red[index])
    return result


func is_enabled(unit_id: String) -> bool:
    return UNIT_IDS.has(unit_id) and typeof(enabled_slots.get(unit_id)) == TYPE_BOOL and enabled_slots[unit_id]


func side_count(side: String) -> int:
    var count: int = 0
    for unit_id in UNIT_IDS:
        if team_for(unit_id) == side and is_enabled(unit_id):
            count += 1
    return count


func set_enabled(unit_id: String, enabled: bool) -> bool:
    if not UNIT_IDS.has(unit_id):
        return false
    if enabled and not is_enabled(unit_id):
        var activation_cell: Variant = _activation_cell(unit_id)
        if activation_cell == null:
            return false
        positions[unit_id] = activation_cell
    enabled_slots[unit_id] = enabled
    return true


func _activation_cell(unit_id: String) -> Variant:
    var side: String = team_for(unit_id)
    var previous: Variant = positions.get(unit_id)
    if typeof(previous) == TYPE_VECTOR2I and can_deploy(side, previous) and unit_at(previous).is_empty():
        return previous
    for row in range(rows):
        for column in range(columns):
            var cell := Vector2i(column, row)
            if can_deploy(side, cell) and unit_at(cell).is_empty():
                return cell
    return null


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
    var original: SuleynUnitStats = catalog_entry(profile_key(unit_id))
    if commander_options.has(unit_id):
        return CommanderBuild.materialize(original, commander_options[unit_id])
    return original


func current_commander_options(unit_id: String) -> Dictionary:
    if not UNIT_IDS.has(unit_id):
        return {}
    if commander_options.has(unit_id):
        return commander_options[unit_id].duplicate(true) if commander_options[unit_id] is Dictionary else {}
    return CommanderBuild.defaults(catalog_entry(profile_key(unit_id)))


func set_commander_options(unit_id: String, options: Variant) -> bool:
    if not UNIT_IDS.has(unit_id) or not CommanderBuild.validate(catalog_entry(profile_key(unit_id)), options).ok:
        return false
    var accepted: Dictionary = {}
    for key in CommanderBuild.KEYS:
        accepted[key] = int(options[key])
    commander_options[unit_id] = accepted
    return true


func reset_commander_options(unit_id: String) -> void:
    commander_options.erase(unit_id)


static func catalog_entry(key: String) -> SuleynUnitStats:
    return CATALOG.get(key) as SuleynUnitStats


static func profile_label(key: String) -> String:
    var stats: SuleynUnitStats = catalog_entry(key)
    return stats.display_name if stats != null else ""


func set_profile(unit_id: String, key: String) -> bool:
    if not UNIT_IDS.has(unit_id) or not CATALOG.has(key):
        return false
    if not is_enabled(unit_id) and not set_enabled(unit_id, true):
        return false
    if profile_key(unit_id) != key:
        commander_options.erase(unit_id)
    profile_keys[unit_id] = key
    return true


func unit_at(cell: Vector2i) -> String:
    # Only known slots can represent draft occupants; corrupted extra keys
    # are rejected by validation_errors rather than becoming playable units.
    for unit_id in unit_ids():
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


func arena_label() -> String:
    return Arena.label(arena_key)


func arena_description() -> String:
    return Arena.description(arena_key)


func blocked_cells() -> Array[Vector2i]:
    return Arena.blocked_cells(arena_key, columns, rows)


func is_blocked(cell: Vector2i) -> bool:
    return blocked_cells().has(cell)


func can_deploy(side: String, cell: Vector2i) -> bool:
    return Arena.is_supported(arena_key, columns, rows) and cell_is_deployment(side, cell) and not is_blocked(cell)


func set_arena(key: String) -> bool:
    if not Arena.is_supported(key, columns, rows):
        return false
    arena_key = key
    return true


func place_unit(unit_id: String, cell: Vector2i) -> bool:
    var side: String = team_for(unit_id)
    if side.is_empty() or not is_enabled(unit_id) or not can_deploy(side, cell):
        return false
    # The chosen slot must exist before a placement can edit it.
    if not positions.has(unit_id):
        return false
    for other_id in positions:
        var location = positions[other_id]
        if other_id != unit_id and typeof(other_id) == TYPE_STRING and is_enabled(other_id) and typeof(location) == TYPE_VECTOR2I and location == cell:
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
    commander_options.clear()
    arena_key = "open"
    enabled_slots.clear()
    for unit_id in UNIT_IDS:
        enabled_slots[unit_id] = true
    profile_keys = {
        "ally_1": "male", "enemy_1": "hellhound",
        "ally_2": "female", "enemy_2": "falcon",
        "ally_3": "falcon", "enemy_3": "lich",
    }
    enemy_ai_enabled = true
    reset_positions()


func validation_errors() -> PackedStringArray:
    var errors: PackedStringArray = []
    for unit_id in commander_options:
        if not UNIT_IDS.has(unit_id):
            errors.append("Неизвестный слот настроек командира.")
        elif not CommanderBuild.validate(catalog_entry(profile_key(unit_id)), commander_options[unit_id]).ok:
            errors.append("Проверьте настройки командира %s." % unit_id)
    if columns < 4 or rows < 3:
        errors.append("Поле подготовки должно быть не меньше 4×3.")
    if not Arena.is_supported(arena_key, columns, rows):
        errors.append("Выберите доступную арену: арены с препятствиями требуют поле не меньше 7×5.")
    if profile_keys.size() != UNIT_IDS.size():
        errors.append("В составе должны быть все шесть доступных слотов.")
    if positions.size() != UNIT_IDS.size():
        errors.append("Для каждого бойца требуется стартовый гекс.")
    if enabled_slots.size() != UNIT_IDS.size():
        errors.append("Для каждого слота требуется признак выбора бойца.")
    for key in enabled_slots:
        if not UNIT_IDS.has(key):
            errors.append("Неизвестный слот выбора: %s." % str(key))
    for side in ["blue", "red"]:
        if side_count(side) < 1:
            errors.append("В каждой команде нужен хотя бы один боец.")
    for key in profile_keys:
        if not UNIT_IDS.has(key):
            errors.append("Неизвестный боец в составе: %s." % str(key))
    for key in positions:
        if not UNIT_IDS.has(key):
            errors.append("Неизвестный боец в расстановке: %s." % str(key))
    var occupied: Dictionary = {}
    for unit_id in UNIT_IDS:
        if not enabled_slots.has(unit_id) or typeof(enabled_slots[unit_id]) != TYPE_BOOL:
            errors.append("Для %s нужен корректный признак выбора." % unit_id)
        if not profile_keys.has(unit_id) or catalog_entry(profile_key(unit_id)) == null:
            errors.append("Для %s выберите доступного бойца." % unit_id)
        if not positions.has(unit_id) or typeof(positions[unit_id]) != TYPE_VECTOR2I:
            errors.append("Для %s нужен корректный стартовый гекс." % unit_id)
            continue
        if not is_enabled(unit_id):
            continue
        var cell: Vector2i = positions[unit_id]
        if is_blocked(cell):
            errors.append("Боец %s размещён на препятствии." % unit_id)
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
    draft.enabled_slots = enabled_slots.duplicate(true)
    draft.commander_options = commander_options.duplicate(true)
    draft.enemy_ai_enabled = enemy_ai_enabled
    draft.arena_key = arena_key
    return draft
