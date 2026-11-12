extends RefCounted
## Data-only battle board: bounds, blocked hexes, occupied hexes, BFS.
## No movement cost, initiative or magic rules are assumed.

const Hex = preload("res://scripts/hex_math.gd")

var columns: int
var rows: int
var blocked: Dictionary = {}           # Vector2i -> true
var occupied: Dictionary = {}          # Vector2i -> String (unit_id)
var unit_positions: Dictionary = {}    # String (unit_id) -> Vector2i


func _init(width: int = 9, height: int = 7) -> void:
    columns = maxi(width, 1)
    rows = maxi(height, 1)


func contains(cell: Vector2i) -> bool:
    return cell.x >= 0 and cell.x < columns and cell.y >= 0 and cell.y < rows


func is_free(cell: Vector2i) -> bool:
    return contains(cell) and not blocked.has(cell) and not occupied.has(cell)


func can_enter(cell: Vector2i, moving_unit_id: String = "") -> bool:
    if not contains(cell) or blocked.has(cell):
        return false
    return not occupied.has(cell) or occupied[cell] == moving_unit_id


func set_blocked(cell: Vector2i, value: bool) -> bool:
    if not contains(cell):
        return false
    if value:
        if occupied.has(cell):
            return false
        blocked[cell] = true
    else:
        blocked.erase(cell)
    return true


func add_unit(unit_id: String, cell: Vector2i) -> bool:
    if unit_id.is_empty() or unit_positions.has(unit_id) or not is_free(cell):
        return false
    occupied[cell] = unit_id
    unit_positions[unit_id] = cell
    return true


func remove_unit(unit_id: String) -> bool:
    if not unit_positions.has(unit_id):
        return false
    var cell: Vector2i = unit_positions[unit_id]
    occupied.erase(cell)
    unit_positions.erase(unit_id)
    return true


func unit_at(cell: Vector2i) -> String:
    return str(occupied.get(cell, ""))


func position_of(unit_id: String) -> Vector2i:
    return unit_positions.get(unit_id, Vector2i(-1, -1))


func move_unit(unit_id: String, target: Vector2i) -> bool:
    if not unit_positions.has(unit_id) or not can_enter(target, unit_id):
        return false
    var current: Vector2i = unit_positions[unit_id]
    if current == target:
        return true
    occupied.erase(current)
    occupied[target] = unit_id
    unit_positions[unit_id] = target
    return true


func reachable_from(start: Vector2i, max_steps: int, moving_unit_id: String = "") -> Dictionary:
    # Returns { cell: minimal number of steps }. Start always costs 0.
    var distances: Dictionary = {}
    if max_steps < 0 or not contains(start) or not can_enter(start, moving_unit_id):
        return distances

    var frontier: Array[Vector2i] = [start]
    var cursor: int = 0
    distances[start] = 0

    while cursor < frontier.size():
        var current: Vector2i = frontier[cursor]
        cursor += 1
        var cost: int = distances[current]
        if cost >= max_steps:
            continue
        for direction in Hex.DIRECTIONS:
            var next_cell: Vector2i = current + direction
            if distances.has(next_cell) or not can_enter(next_cell, moving_unit_id):
                continue
            distances[next_cell] = cost + 1
            frontier.append(next_cell)
    return distances


func shortest_path(start: Vector2i, target: Vector2i, moving_unit_id: String = "") -> Array[Vector2i]:
    # BFS works because each ordinary hex currently costs one step.
    var empty_path: Array[Vector2i] = []
    if not can_enter(start, moving_unit_id) or not can_enter(target, moving_unit_id):
        return empty_path
    if start == target:
        var stay_put: Array[Vector2i] = [start]
        return stay_put

    var frontier: Array[Vector2i] = [start]
    var parent: Dictionary = {start: start}
    var cursor: int = 0
    while cursor < frontier.size() and not parent.has(target):
        var current: Vector2i = frontier[cursor]
        cursor += 1
        for direction in Hex.DIRECTIONS:
            var next_cell: Vector2i = current + direction
            if parent.has(next_cell) or not can_enter(next_cell, moving_unit_id):
                continue
            parent[next_cell] = current
            frontier.append(next_cell)

    if not parent.has(target):
        return empty_path
    var result: Array[Vector2i] = []
    var step: Vector2i = target
    while step != start:
        result.push_front(step)
        step = parent[step]
    result.push_front(start)
    return result
