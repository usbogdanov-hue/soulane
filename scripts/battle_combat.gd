extends RefCounted
## Physical and magic use one consistent matter comparison; no magic crits.
const Hex = preload("res://scripts/hex_math.gd")
const DamageCalculator = preload("res://scripts/damage_calculator.gd")
const Matter = preload("res://scripts/matter_rules.gd")
const Rules = preload("res://scripts/combat_rules.gd")

static func can_physical(board, units: Dictionary, attacker_id: String, defender_id: String,
        skill: SuleynAttackSkill = null) -> bool:
    if attacker_id == defender_id or not units.has(attacker_id) or not units.has(defender_id):
        return false
    var attacker = units[attacker_id]
    var defender = units[defender_id]
    if not attacker.is_alive() or not defender.is_alive() or attacker.side == defender.side:
        return false
    var from_cell: Vector2i = board.position_of(attacker_id)
    var to_cell: Vector2i = board.position_of(defender_id)
    if not board.contains(from_cell) or not board.contains(to_cell):
        return false
    var distance: int = Hex.hex_distance(from_cell, to_cell)
    var shortest: int = maxi(1, skill.min_range) if skill != null else 1
    var longest: int = maxi(shortest, skill.max_range) if skill != null else 1
    return distance >= shortest and distance <= longest


static func can_melee(board, units: Dictionary, attacker_id: String, defender_id: String) -> bool:
    return can_physical(board, units, attacker_id, defender_id)


static func melee_attack(board, units: Dictionary, attacker_id: String, defender_id: String,
        dodge_roll: float = -1.0, crit_roll: float = -1.0) -> Dictionary:
    # v1.1 public API is retained for all older tests and normal attacks.
    return physical_attack(board, units, attacker_id, defender_id, null, dodge_roll, crit_roll)


static func skill_attack(board, units: Dictionary, attacker_id: String, defender_id: String,
        skill: SuleynAttackSkill, dodge_roll: float = -1.0, crit_roll: float = -1.0,
        concussion_roll: float = -1.0) -> Dictionary:
    if skill == null:
        return {"ok": false, "reason": "Не назначено дополнительное умение."}
    return physical_attack(board, units, attacker_id, defender_id, skill,
        dodge_roll, crit_roll, concussion_roll)


static func physical_attack(board, units: Dictionary, attacker_id: String, defender_id: String,
        skill: SuleynAttackSkill = null, dodge_roll: float = -1.0,
        crit_roll: float = -1.0, concussion_roll: float = -1.0) -> Dictionary:
    if not can_physical(board, units, attacker_id, defender_id, skill):
        return {"ok": false, "reason": "Цель вне дальности выбранного умения."}
    var attacker = units[attacker_id]
    var defender = units[defender_id]
    var mana_cost: int = skill.mana_cost if skill != null else 0
    if attacker.mp < mana_cost:
        return {"ok": false, "reason": "Недостаточно MP: требуется %d." % mana_cost}
    var skill_power: int = skill.skill_power if skill != null else (
        attacker.melee_skill_power if attacker.melee_skill_power > 0 else attacker.attack)
    var damage_type: int = skill.damage_type if skill != null else attacker.melee_damage_type
    var skill_name: String = skill.display_name if skill != null else "Обычный удар"
    var stun_chance: float = Rules.cap_chance(skill.concussion_chance_pct) if skill != null else 0.0
    var stun_duration: int = skill.concussion_skipped_turns if skill != null else 0
    # MP is consumed on ATTEMPT, including when the defender successfully dodges.
    if not attacker.spend_mana(mana_cost):
        return {"ok": false, "reason": "Недостаточно MP."}
    var evasion: float = defender.final_evasion_pct()
    var dodge: float = dodge_roll if dodge_roll >= 0.0 else randf() * 100.0
    if dodge < evasion:
        return {"ok": true, "evaded": true, "critical": false, "damage": 0,
            "remaining_hp": defender.hp, "defeated": false,
            "evasion_percent": evasion, "critical_percent": attacker.crit_chance_pct,
            "dodge_roll": dodge, "crit_roll": -1.0,
            "attacker_attack": attacker.attack, "defender_defense": defender.defense,
            "skill_name": skill_name, "skill_power": skill_power,
            "damage_type": damage_type, "skill_cost": mana_cost,
            "concussion_chance_pct": stun_chance, "concussion_roll": -1.0,
            "concussion_applied": false, "concussion_remaining": defender.concussion_turns_remaining}
    var critical_chance: float = Rules.cap_chance(attacker.crit_chance_pct)
    var crit: float = crit_roll if crit_roll >= 0.0 else randf() * 100.0
    var critical: bool = crit < critical_chance
    var atk_matter: int = attacker.matter
    var target_matter: int = defender.matter
    var matter_defense: float = Matter.defense_penalty_pp(atk_matter, target_matter)
    var matter_attack: float = Matter.attack_penalty_pct(atk_matter, target_matter)
    var physical_defense: float = defender.physical_defense_pct(damage_type, matter_defense)
    var crit_coef: float = maxf(1.5, attacker.critical_multiplier) if critical else 1.0
    var calculated_damage: int = DamageCalculator.physical_damage(skill_power,
        attacker.physical_damage_bonus_pct, physical_defense, crit_coef, matter_attack)
    var dealt: int = defender.receive_damage(calculated_damage)
    var defeated: bool = not defender.is_alive()
    var stun_roll: float = -1.0
    var stun_applied: bool = false
    if not defeated and stun_chance > 0.0 and stun_duration > 0:
        stun_roll = concussion_roll if concussion_roll >= 0.0 else randf() * 100.0
        stun_applied = stun_roll < stun_chance
        if stun_applied:
            defender.apply_concussion(stun_duration)
    if defeated:
        board.remove_unit(defender_id)
    return {"ok": true, "evaded": false, "critical": critical, "damage": dealt,
        "calculated_damage": calculated_damage, "critical_multiplier": crit_coef,
        "attacker_attack": attacker.attack, "defender_defense": defender.defense,
        "evasion_percent": evasion, "critical_percent": critical_chance,
        "dodge_roll": dodge, "crit_roll": crit,
        "skill_name": skill_name, "skill_cost": mana_cost,
        "skill_power": skill_power, "damage_type": damage_type,
        "attack_matter": atk_matter, "defender_matter": target_matter,
        "matter_attack_penalty_pct": matter_attack,
        "matter_defense_penalty_pp": matter_defense,
        "pdef_percent": physical_defense,
        "concussion_chance_pct": stun_chance,
        "concussion_roll": stun_roll, "concussion_applied": stun_applied,
        "concussion_remaining": defender.concussion_turns_remaining,
        "remaining_hp": defender.hp, "defeated": defeated}


static func magic_attack(board, units: Dictionary, attacker_id: String, defender_id: String) -> Dictionary:
    ## v1.0 demo magic range: adjacent hexes, pending full spell targeting GDD.
    if not can_melee(board, units, attacker_id, defender_id):
        return {"ok": false, "reason": "В демо магия пока доступна только на соседнем гексе."}
    var attacker = units[attacker_id]
    var defender = units[defender_id]
    if attacker.spell_power <= 0:
        return {"ok": false, "reason": "Нет атакующего заклинания."}
    if attacker.mp < attacker.spell_mana_cost:
        return {"ok": false, "reason": "Недостаточно MP."}
    var atk_matter: int = attacker.spell_matter
    var target_matter: int = defender.matter
    var matter_defense: float = Matter.defense_penalty_pp(atk_matter, target_matter)
    var matter_attack: float = Matter.attack_penalty_pct(atk_matter, target_matter)
    var mdef: float = defender.magic_defense_pct(matter_defense)
    var calculated_damage: int = DamageCalculator.magical_damage(attacker.spell_power,
        attacker.magic_power_pct, mdef, matter_attack)
    if not attacker.spend_mana(attacker.spell_mana_cost):
        return {"ok": false, "reason": "Недостаточно MP."}
    var dealt: int = defender.receive_damage(calculated_damage)
    var defeated: bool = not defender.is_alive()
    if defeated:
        board.remove_unit(defender_id)
    return {"ok": true, "evaded": false, "critical": false,
        "damage": dealt, "calculated_damage": calculated_damage,
        "spell_power": attacker.spell_power, "spell_cost": attacker.spell_mana_cost,
        "attack_matter": atk_matter, "defender_matter": target_matter,
        "matter_attack_penalty_pct": matter_attack,
        "matter_defense_penalty_pp": matter_defense, "mdef_percent": mdef,
        "remaining_hp": defender.hp, "defeated": defeated}
