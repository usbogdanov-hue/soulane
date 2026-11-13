extends RefCounted
## Deterministic demo policy. Choosing an action never executes combat, rolls RNG,
## spends resources or mutates the board. Runtime validates the returned action.
const Combat = preload("res://scripts/battle_combat.gd")
const Damage = preload("res://scripts/damage_calculator.gd")
const Hex = preload("res://scripts/hex_math.gd")
const Matter = preload("res://scripts/matter_rules.gd")
const Rules = preload("res://scripts/combat_rules.gd")


static func choose_action(board, units: Dictionary, actor_id: String) -> Dictionary:
    if not units.has(actor_id):
        return {"kind": "pass"}
    var actor = units[actor_id]
    if actor == null or not actor.is_alive() or actor.concussion_turns_remaining > 0:
        return {"kind": "pass"}
    var start: Vector2i = board.position_of(actor_id)
    if not board.contains(start):
        return {"kind": "pass"}
    var targets: Array[String] = []
    for unit_id in units:
        var target = units[unit_id]
        if target != null and target.is_alive() and target.side != actor.side:
            if board.contains(board.position_of(unit_id)):
                targets.append(unit_id)
    targets.sort()
    var options: Array[Dictionary] = _attack_options(actor)
    var best_attack: Dictionary = {}
    for target_id in targets:
        for option in options:
            if _can_attack(board, units, actor_id, target_id, option):
                var candidate: Dictionary = {
                    "target_id": target_id, "mode": option.mode, "cost": option.cost,
                    "score": _expected_damage(actor, units[target_id], option)}
                if _better_attack(candidate, best_attack):
                    best_attack = candidate
    if not best_attack.is_empty():
        return {"kind": "attack", "target_id": best_attack.target_id, "mode": best_attack.mode}
    if actor.movement <= 0 or targets.is_empty():
        return {"kind": "pass"}

    # Search the full free component first, not just this turn's movement radius.
    # A shortest valid route can initially lead away from the enemy.
    var distances: Dictionary = board.reachable_from(start, board.columns * board.rows, actor_id)
    var best_goal: Dictionary = {}
    for target_id in targets:
        var target_cell: Vector2i = board.position_of(target_id)
        for option in options:
            var expected: float = _expected_damage(actor, units[target_id], option)
            for x in range(board.columns):
                for y in range(board.rows):
                    var goal: Vector2i = Vector2i(x, y)
                    if not board.is_free(goal) or not distances.has(goal):
                        continue
                    var distance_to_target: int = Hex.hex_distance(goal, target_cell)
                    if distance_to_target < option.min_range or distance_to_target > option.max_range:
                        continue
                    var candidate: Dictionary = {
                        "cell": goal, "steps": int(distances[goal]), "target_id": target_id,
                        "mode": option.mode, "cost": option.cost,
                        "score": expected}
                    if _better_goal(candidate, best_goal):
                        best_goal = candidate
    if best_goal.is_empty():
        return {"kind": "pass"}
    var path: Array[Vector2i] = board.shortest_path(start, best_goal.cell, actor_id)
    if path.size() < 2:
        return {"kind": "pass"}
    var step: int = mini(actor.movement, path.size() - 1)
    return {"kind": "move", "cell": path[step]}


static func _attack_options(actor) -> Array[Dictionary]:
    var result: Array[Dictionary] = [{
        "mode": "basic", "cost": 0, "min_range": 1, "max_range": 1,
        "power": actor.melee_skill_power if actor.melee_skill_power > 0 else actor.attack,
        "damage_type": actor.melee_damage_type}]
    var skill: SuleynAttackSkill = actor.special_skill
    if skill != null and skill.mana_cost >= 0 and actor.mp >= skill.mana_cost:
        var minimum: int = maxi(1, skill.min_range)
        result.append({"mode": "special", "cost": skill.mana_cost,
            "min_range": minimum, "max_range": maxi(minimum, skill.max_range),
            "power": skill.skill_power, "damage_type": skill.damage_type})
    if actor.spell_power > 0 and actor.spell_mana_cost >= 0 and actor.mp >= actor.spell_mana_cost:
        # Existing demo magic targets adjacent hexes; no new spell-range rule.
        result.append({"mode": "magic", "cost": actor.spell_mana_cost,
            "min_range": 1, "max_range": 1, "power": actor.spell_power})
    return result


static func _can_attack(board, units: Dictionary, actor_id: String,
        target_id: String, option: Dictionary) -> bool:
    if option.mode == "special":
        return Combat.can_physical(board, units, actor_id, target_id, units[actor_id].special_skill)
    return Combat.can_melee(board, units, actor_id, target_id)


static func _expected_damage(actor, target, option: Dictionary) -> float:
    var magic: bool = option.mode == "magic"
    var attack_matter: int = actor.spell_matter if magic else actor.matter
    var defense_penalty: float = Matter.defense_penalty_pp(attack_matter, target.matter)
    var attack_penalty: float = Matter.attack_penalty_pct(attack_matter, target.matter)
    if magic:
        var magical: int = Damage.magical_damage(option.power, actor.magic_power_pct,
            target.magic_defense_pct(defense_penalty), attack_penalty)
        return float(mini(target.hp, magical))
    var defense: float = target.physical_defense_pct(option.damage_type, defense_penalty)
    var ordinary: int = Damage.physical_damage(option.power, actor.physical_damage_bonus_pct,
        defense, 1.0, attack_penalty)
    var critical: int = Damage.physical_damage(option.power, actor.physical_damage_bonus_pct,
        defense, maxf(1.5, actor.critical_multiplier), attack_penalty)
    var critical_chance: float = Rules.cap_chance(actor.crit_chance_pct) / 100.0
    # Clamp each outcome to current HP: overkill is not additional actual damage.
    var on_hit: float = (float(mini(target.hp, ordinary)) * (1.0 - critical_chance)
        + float(mini(target.hp, critical)) * critical_chance)
    return on_hit * (1.0 - target.final_evasion_pct() / 100.0)


static func _better_attack(candidate: Dictionary, best: Dictionary) -> bool:
    if best.is_empty():
        return true
    if candidate.score != best.score:
        return candidate.score > best.score
    if candidate.cost != best.cost:
        return candidate.cost < best.cost
    if candidate.target_id != best.target_id:
        return candidate.target_id < best.target_id
    return _mode_rank(candidate.mode) < _mode_rank(best.mode)


static func _better_goal(candidate: Dictionary, best: Dictionary) -> bool:
    if best.is_empty():
        return true
    if candidate.steps != best.steps:
        return candidate.steps < best.steps
    if _better_attack(candidate, best):
        return true
    if _better_attack(best, candidate):
        return false
    if candidate.cell.x != best.cell.x:
        return candidate.cell.x < best.cell.x
    return candidate.cell.y < best.cell.y


static func _mode_rank(mode: String) -> int:
    return 0 if mode == "basic" else (1 if mode == "special" else 2)
