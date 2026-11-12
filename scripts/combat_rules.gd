class_name SuleynCombatRules
extends RefCounted
## Combat Core Update v0.2. Percentages are percentage points (not multipliers).
## No commander category vulnerabilities. Monster armor is never applied.

const PIERCING: int = 0
const SLASHING: int = 1
const BLUNT: int = 2

const FLYING: int = 1
const GROUND: int = 2
const MAGICAL_UNDEAD: int = 4

const PERCENT_CAP: float = 90.0
const EVASION_FLOOR: float = 5.0  # All combat units, commanders and monsters.
const MONSTER_VULNERABILITY: float = 15.0


static func cap_percent(value: float) -> float:
    # Negative armor/resistance remains valid and increases incoming damage.
    return minf(PERCENT_CAP, value)


static func cap_chance(value: float, guaranteed: bool = false) -> float:
    if guaranteed:
        return 100.0
    return clampf(value, 0.0, PERCENT_CAP)


static func final_evasion(value: float) -> float:
    # Universal 5..90% dodge chance; no separate accuracy stat.
    return clampf(value, EVASION_FLOOR, PERCENT_CAP)


static func armor_pdef(armor_type: int) -> float:
    match armor_type:
        2: return 10.0
        3: return 20.0
    return 0.0


static func armor_mdef(armor_type: int) -> float:
    match armor_type:
        1: return 20.0
        2: return 10.0
    return 0.0


static func armor_weapon_defense(armor_type: int, damage_type: int) -> float:
    if armor_type == 2 and (damage_type == PIERCING or damage_type == BLUNT):
        return 10.0
    if armor_type == 3:
        if damage_type == PIERCING:
            return 20.0
        if damage_type == SLASHING:
            return 10.0
    return 0.0


static func armor_evasion(armor_type: int) -> float:
    match armor_type:
        1: return 10.0
        3: return -10.0
    return 0.0


static func monster_vulnerability(is_monster: bool, categories: int, damage_type: int) -> float:
    if not is_monster:
        return 0.0
    if damage_type == PIERCING and (categories & FLYING) != 0:
        return MONSTER_VULNERABILITY
    if damage_type == SLASHING and (categories & GROUND) != 0:
        return MONSTER_VULNERABILITY
    if damage_type == BLUNT and (categories & MAGICAL_UNDEAD) != 0:
        return MONSTER_VULNERABILITY
    return 0.0


static func damage_type_name(damage_type: int) -> String:
    match damage_type:
        PIERCING: return "Колющее"
        SLASHING: return "Рубящее"
        BLUNT: return "Дробящее"
    return "Неизвестный тип"
