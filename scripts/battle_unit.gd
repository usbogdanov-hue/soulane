extends RefCounted
const Rules = preload("res://scripts/combat_rules.gd")
const Matter = preload("res://scripts/matter_rules.gd")
## Runtime unit. HP/MP, armor and attributes are resolved from commander data when present.
## Existing v0.4 constructor retained for backward compatibility.

var id: String
var side: String
var display_name: String
var max_hp: int
var hp: int
var max_mp: int = 0
var mp: int = 0
var attack: int
var defense: int
var movement: int
var level: int = 0
var armor: String = ""
var attributes: Dictionary = {}
var unspent_points: int = 0
# GDD-driven combat attributes. Percent values are percentage points.
# Negative defensive values are allowed. All final defensive values cap at +90.
var physical_damage_bonus_pct: float = 0.0
var evasion_pct: float = Rules.EVASION_FLOOR
var crit_chance_pct: float = 0.0
var physical_resistance_pct: float = 0.0  # deprecated; AGI provides NO PDEF
var armor_pdef_pct: float = 0.0
var armor_mdef_pct: float = 0.0
var base_pdef_pct: float = 0.0
var base_mdef_pct: float = 0.0
var is_monster: bool = false
var monster_categories: int = 0
var melee_skill_power: int = 0
var special_skill: SuleynAttackSkill
var concussion_turns_remaining: int = 0  # Exactly this many upcoming turns are skipped.
var concussion_total_turns: int = 0  # For explicit 1/2 and 2/2 turn notifications.
var melee_damage_type: int = Rules.SLASHING
var matter: int = Matter.NEUTRAL  # Effective matter; resolved once from equipment/class.
var critical_multiplier: float = 1.5  # Only dedicated class/monster passive may override.
var spell_power: int = 0
var spell_mana_cost: int = 0
var spell_matter: int = Matter.NEUTRAL
var armor_weapon_bonuses: Dictionary = {}
var defense_effects_pct: float = 0.0
var mdef_effects_pct: float = 0.0
var weapon_defense_effects: Dictionary = {}
var magic_power_pct: float = 0.0
var mana_regen_pct: float = 0.0
var magic_resistance_pct: float = 0.0
var mana_regen_fraction: float = 0.0

func _init(unit_id: String, unit_side: String, health: int, attack_value: int,
        defense_value: int = 0, movement_value: int = 3, name_value: String = "") -> void:
    id = unit_id
    side = unit_side
    display_name = name_value if not name_value.is_empty() else unit_id
    max_hp = maxi(health, 1)
    hp = max_hp
    attack = maxi(attack_value, 0)
    defense = maxi(defense_value, 0)
    movement = maxi(movement_value, 0)

func final_evasion_pct() -> float:
    # Clamp on use as well: debuffs, equipment and future monster stats cannot
    # override the universal 5% floor or the 90% upper bound.
    return Rules.final_evasion(evasion_pct)


func physical_defense_pct(damage_type: int, extra_matter_penalty_pp: float = 0.0) -> float:
    var armor_weapon: float = float(armor_weapon_bonuses.get(damage_type, 0.0)) if not is_monster else 0.0
    var armor_base: float = armor_pdef_pct if not is_monster else 0.0
    var vulnerability: float = Rules.monster_vulnerability(is_monster, monster_categories, damage_type)
    return Rules.cap_percent(base_pdef_pct + armor_base + armor_weapon +
        defense_effects_pct + float(weapon_defense_effects.get(damage_type, 0.0)) - vulnerability + extra_matter_penalty_pp)


func magic_defense_pct(extra_matter_penalty_pp: float = 0.0) -> float:
    var armor_magic: float = armor_mdef_pct if not is_monster else 0.0
    return Rules.cap_percent(base_mdef_pct + armor_magic + magic_resistance_pct + mdef_effects_pct + extra_matter_penalty_pp)


func is_alive() -> bool:
    return hp > 0

func receive_damage(amount: int) -> int:
    if not is_alive():
        return 0
    var dealt: int = mini(hp, maxi(0, amount))
    hp -= dealt
    return dealt


func apply_concussion(turns_to_skip: int) -> void:
    # Reapplying concussion refreshes the duration, never stacks it indefinitely.
    var valid_duration: int = maxi(0, turns_to_skip)
    concussion_turns_remaining = maxi(concussion_turns_remaining, valid_duration)
    concussion_total_turns = concussion_turns_remaining  # A fresh application starts a fresh skip sequence.


func skip_concussed_turn() -> bool:
    if concussion_turns_remaining <= 0 or not is_alive():
        return false
    concussion_turns_remaining -= 1
    return true


func spend_mana(amount: int) -> bool:
    if amount < 0 or mp < amount:
        return false
    mp -= amount
    return true


func regenerate_mana_end_turn() -> int:
    # Preserve fractional MP across turns, no guessed rounding bonus.
    if not is_alive() or max_mp <= 0:
        return 0
    if mp >= max_mp:
        mana_regen_fraction = 0.0
        return 0
    var regen_pool: float = mana_regen_fraction + float(max_mp) * Rules.cap_chance(mana_regen_pct) / 100.0
    var whole: int = int(floor(regen_pool + 0.000001))
    var restored: int = mini(whole, max_mp - mp)
    mp += restored
    mana_regen_fraction = regen_pool - float(whole)
    if mp >= max_mp:
        mana_regen_fraction = 0.0
    return restored
