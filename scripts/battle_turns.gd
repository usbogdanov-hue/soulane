extends RefCounted
## Demo turn manager: each participating unit gets one move, melee attack or pass.
## Turn order is provided externally. This file DOES NOT define GDD initiative rules.

var turn_order: Array[String] = []
var turn_index: int = 0
var round_number: int = 1
var action_spent: bool = false


func _init(unit_ids: Array[String]) -> void:
    # A runtime unit has exactly one slot; empty IDs never represent a turn.
    # Keep first occurrence order rather than guessing initiative from stats.
    for unit_id in unit_ids:
        if not unit_id.is_empty() and not turn_order.has(unit_id):
            turn_order.append(unit_id)


func active_unit_id() -> String:
    if turn_order.is_empty():
        return ""
    return turn_order[turn_index]


func can_act(unit_id: String) -> bool:
    return not unit_id.is_empty() and unit_id == active_unit_id() and not action_spent


func spend_action(unit_id: String) -> bool:
    if not can_act(unit_id):
        return false
    action_spent = true
    return true


func next_turn(unit_id: String) -> bool:
    if turn_order.is_empty() or unit_id != active_unit_id():
        return false
    turn_index += 1
    if turn_index >= turn_order.size():
        turn_index = 0
        round_number += 1
    action_spent = false
    return true


func remove_unit(unit_id: String) -> bool:
    var index: int = turn_order.find(unit_id)
    if index < 0:
        return false
    var was_active: bool = index == turn_index
    turn_order.remove_at(index)
    if turn_order.is_empty():
        turn_index = 0
        action_spent = false
    elif index < turn_index:
        turn_index -= 1
    elif turn_index >= turn_order.size():
        turn_index = 0
        round_number += 1
    if was_active:
        action_spent = false
    return true
