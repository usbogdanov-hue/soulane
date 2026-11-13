extends RefCounted
## Read-only projection of existing combat outcomes. Does not roll, spend MP,
## change HP or advance turns; the caller adds turn and input ownership checks.
const Combat = preload("res://scripts/battle_combat.gd")
const Damage = preload("res://scripts/damage_calculator.gd")
const Hex = preload("res://scripts/hex_math.gd")
const Matter = preload("res://scripts/matter_rules.gd")
const Rules = preload("res://scripts/combat_rules.gd")


static func evaluate(board, units: Dictionary, attacker_id: String,
        defender_id: String, mode: String = "basic") -> Dictionary:
    var result: Dictionary = {
        "available": false, "reason": "", "mode": mode, "name": "Атака",
        "cost": 0, "min_range": 1, "max_range": 1, "distance": -1,
        "hit_chance_pct": 0.0, "crit_chance_pct": 0.0,
        "normal_damage": 0, "critical_damage": 0, "expected_damage": 0.0,
        "defense_pct": 0.0, "attack_matter": Matter.NEUTRAL,
        "defender_matter": Matter.NEUTRAL, "matter_attack_penalty_pct": 0.0,
        "matter_defense_penalty_pp": 0.0, "concussion_chance_pct": 0.0,
        "concussion_turns": 0,
    }
    if not units.has(attacker_id) or units[attacker_id] == null:
        return _unavailable(result, "Выберите бойца для атаки.")
    if not units.has(defender_id) or units[defender_id] == null:
        return _unavailable(result, "Наведите курсор на противника.")
    var actor = units[attacker_id]
    var target = units[defender_id]
    if not actor.is_alive():
        return _unavailable(result, "Поверженный боец не может атаковать.")
    if not target.is_alive():
        return _unavailable(result, "Этот противник уже повержен.")
    if attacker_id == defender_id or actor.side == target.side:
        return _unavailable(result, "Выберите противника: своих бойцов атаковать нельзя.")
    if board == null or not board.contains(board.position_of(attacker_id)) or not board.contains(board.position_of(defender_id)):
        return _unavailable(result, "Атакующий и цель должны находиться на поле.")
    result.distance = Hex.hex_distance(board.position_of(attacker_id), board.position_of(defender_id))
    if mode != "basic" and mode != "special" and mode != "magic":
        return _unavailable(result, "Выберите обычный удар, умение или магию.")

    var magic: bool = mode == "magic"
    var skill: SuleynAttackSkill = actor.special_skill if mode == "special" else null
    if mode == "special" and skill == null:
        return _unavailable(result, "У бойца нет дополнительного умения. Нажмите 1 для обычного удара.")
    if magic and actor.spell_power <= 0:
        return _unavailable(result, "У бойца нет атакующего заклинания. Нажмите 1 для обычного удара.")
    result.name = "Магия" if magic else (skill.display_name if skill != null else "Обычный удар")
    result.cost = actor.spell_mana_cost if magic else (skill.mana_cost if skill != null else 0)
    if skill != null:
        result.min_range = maxi(1, skill.min_range)
        result.max_range = maxi(result.min_range, skill.max_range)
        result.concussion_chance_pct = Rules.cap_chance(skill.concussion_chance_pct)
        result.concussion_turns = maxi(0, skill.concussion_skipped_turns)
    result.attack_matter = actor.spell_matter if magic else actor.matter
    result.defender_matter = target.matter
    result.matter_attack_penalty_pct = Matter.attack_penalty_pct(result.attack_matter, target.matter)
    result.matter_defense_penalty_pp = Matter.defense_penalty_pp(result.attack_matter, target.matter)
    var ordinary: int
    var critical: int
    if magic:
        result.hit_chance_pct = 100.0
        result.defense_pct = target.magic_defense_pct(result.matter_defense_penalty_pp)
        ordinary = Damage.magical_damage(actor.spell_power, actor.magic_power_pct,
            result.defense_pct, result.matter_attack_penalty_pct)
        critical = ordinary  # Magic has one damage outcome and never critical-hits.
    else:
        result.hit_chance_pct = 100.0 - target.final_evasion_pct()
        result.crit_chance_pct = Rules.cap_chance(actor.crit_chance_pct)
        var power: int = skill.skill_power if skill != null else (
            actor.melee_skill_power if actor.melee_skill_power > 0 else actor.attack)
        var damage_type: int = skill.damage_type if skill != null else actor.melee_damage_type
        result.defense_pct = target.physical_defense_pct(damage_type, result.matter_defense_penalty_pp)
        ordinary = Damage.physical_damage(power, actor.physical_damage_bonus_pct,
            result.defense_pct, 1.0, result.matter_attack_penalty_pct)
        critical = Damage.physical_damage(power, actor.physical_damage_bonus_pct,
            result.defense_pct, maxf(1.5, actor.critical_multiplier), result.matter_attack_penalty_pct)
    result.normal_damage = mini(target.hp, ordinary)
    result.critical_damage = mini(target.hp, critical)
    var critical_probability: float = result.crit_chance_pct / 100.0
    result.expected_damage = (float(result.normal_damage) * (1.0 - critical_probability)
        + float(result.critical_damage) * critical_probability) * result.hit_chance_pct / 100.0

    if actor.concussion_turns_remaining > 0:
        return _unavailable(result, "Контузия: осталось пропустить собственных ходов — %d." % actor.concussion_turns_remaining)
    if result.cost < 0:
        return _unavailable(result, "У выбранной атаки некорректная стоимость MP.")
    if actor.mp < result.cost:
        return _unavailable(result, "Недостаточно MP: нужно %d, доступно %d. Выберите другое действие." % [result.cost, actor.mp])
    if not Combat.can_physical(board, units, attacker_id, defender_id, skill):
        var range_text: String = str(result.min_range) if result.min_range == result.max_range else "%d–%d" % [result.min_range, result.max_range]
        return _unavailable(result, "Цель вне дальности: нужно %s гекс., сейчас %d. Измените позицию." % [range_text, result.distance])
    result.available = true
    return result


static func _unavailable(result: Dictionary, reason: String) -> Dictionary:
    result.reason = reason
    return result
