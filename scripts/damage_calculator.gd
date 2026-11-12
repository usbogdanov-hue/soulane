extends RefCounted
## SkillPower is numeric; STR/INT bonuses and matter penalties sum as percent points.
## Defensive penalties are added BEFORE the +90% defense cap.
const Rules = preload("res://scripts/combat_rules.gd")

static func physical_damage(skill_power: int, attack_bonus_pct: float = 0.0,
        final_pdef_pct: float = 0.0, crit_multiplier: float = 1.0,
        matter_attack_penalty_pct: float = 0.0) -> int:
    if skill_power <= 0:
        return 0
    var bonus: float = Rules.cap_percent(attack_bonus_pct + matter_attack_penalty_pct)
    var effective_attack: float = float(skill_power) * maxf(0.0, 1.0 + bonus / 100.0)
    var defense_pct: float = Rules.cap_percent(final_pdef_pct)
    var raw: float = effective_attack * (1.0 - defense_pct / 100.0) * maxf(1.0, crit_multiplier)
    return maxi(0, roundi(raw))

static func magical_damage(spell_power: int, attack_bonus_pct: float = 0.0,
        final_mdef_pct: float = 0.0, matter_attack_penalty_pct: float = 0.0) -> int:
    ## Magical attacks NEVER critical-hit.
    return physical_damage(spell_power, attack_bonus_pct, final_mdef_pct, 1.0, matter_attack_penalty_pct)
