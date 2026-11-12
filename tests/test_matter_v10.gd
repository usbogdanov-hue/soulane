extends SceneTree
## Run: godot --headless --path . --script res://tests/test_matter_v10.gd
const Matter = preload("res://scripts/matter_rules.gd")
const Profile = preload("res://scripts/commander_profile.gd")
const Passive = preload("res://scripts/critical_passive.gd")
const Item = preload("res://scripts/matter_item.gd")
const Demo = preload("res://scripts/battle_demo.gd")
const Damage = preload("res://scripts/damage_calculator.gd")
const Board = preload("res://scripts/battle_board.gd")
const Unit = preload("res://scripts/battle_unit.gd")
const Combat = preload("res://scripts/battle_combat.gd")
const Ally = preload("res://data/demo_ally.tres")
const Enemy = preload("res://data/demo_enemy.tres")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
    test_majority()
    test_profiles()
    test_hard_caps()
    test_matter_damage()
    test_combat_and_magic()
    if failures == 0:
        print("SULEYN v1.0: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN v1.0: %d FAILURES of %d checks." % [failures, checks])
        quit(1)

func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED: " + label)

func near(a: float, b: float) -> bool:
    return absf(a - b) < 0.001

func test_majority() -> void:
    check(Matter.resolve([]) == Matter.NEUTRAL, "no matter is neutral")
    check(Matter.resolve([Matter.FIRE]) == Matter.FIRE, "one matter changes neutral to fire")
    check(Matter.resolve([Matter.FIRE, Matter.WATER]) == Matter.NEUTRAL, "fire + water tie -> neutral")
    check(Matter.resolve([Matter.FIRE, Matter.WATER, Matter.WATER]) == Matter.WATER,
        "fire + water sword + water shield -> water")
    check(Matter.resolve([Matter.FIRE, Matter.WATER, Matter.WIND]) == Matter.NEUTRAL,
        "three-way tie -> neutral")
    check(Matter.resolve([Matter.FIRE, Matter.NEUTRAL, Matter.FIRE]) == Matter.FIRE,
        "neutral items don't vote")
    check(Matter.is_strong_against(Matter.FIRE, Matter.WIND), "fire > wind")
    check(Matter.is_strong_against(Matter.WIND, Matter.WATER), "wind > water")
    check(Matter.is_strong_against(Matter.WATER, Matter.FIRE), "water > fire")
    check(Matter.is_strong_against(Matter.LIGHT, Matter.DARK), "light > dark")
    check(Matter.is_strong_against(Matter.DARK, Matter.LIGHT), "dark > light")
    check(not Matter.is_strong_against(Matter.FIRE, Matter.WATER), "fire isn't strong vs water")
    check(near(Matter.attack_penalty_pct(Matter.FIRE, Matter.FIRE), -15.0), "same matter attack -15")
    check(near(Matter.defense_penalty_pp(Matter.WATER, Matter.FIRE), -15.0), "water vs fire defense -15pp")
    check(near(Matter.attack_penalty_pct(Matter.NEUTRAL, Matter.FIRE), 0.0), "neutral attack no matter effects")
    check(near(Matter.defense_penalty_pp(Matter.FIRE, Matter.NEUTRAL), 0.0), "neutral target no matter effects")

func test_profiles() -> void:
    var fire = Item.new()
    fire.matter = Matter.FIRE
    var water = Item.new()
    water.matter = Matter.WATER
    var p = Profile.new()
    p.archetype = 1
    check(p.resolved_matter() == Matter.NEUTRAL, "no class matter or items")
    var one_water: Array[Resource] = [water]
    p.matter_equipment = one_water
    check(p.resolved_matter() == Matter.WATER, "neutral commander inherits water item")
    p.class_matter = Matter.FIRE
    check(p.resolved_matter() == Matter.NEUTRAL, "fire class + water item is tie")
    var two_water: Array[Resource] = [water, water]
    p.matter_equipment = two_water
    check(p.resolved_matter() == Matter.WATER, "two water items outnumber fire class")
    var mixed: Array[Resource] = [water, fire]
    p.matter_equipment = mixed
    check(p.resolved_matter() == Matter.FIRE, "fire class + fire item > water")
    var passive = Passive.new()
    passive.crit_multiplier = 2.2
    p.critical_passive = passive
    check(near(p.critical_multiplier(), 2.2), "a dedicated passive determines crit coefficient")
    p.critical_passive = null
    check(near(p.critical_multiplier(), 1.5), "default crit x1.5")
    check(Ally.commander.resolved_matter() == Matter.WATER, "demo female fire+2 water resolved water")
    check(Enemy.commander.resolved_matter() == Matter.FIRE, "neutral male + fire item resolved fire")

func test_hard_caps() -> void:
    var p = Profile.new()
    p.archetype = 1
    p.level = 30
    p.points_str = 100
    check(p.primary_stats()["STR"] == 45 and p.points_str == 37, "STR can't exceed 45")
    p.points_int = 100
    check(p.primary_stats()["INT"] == 45 and p.points_int == 41, "INT can't exceed 45")
    check(p.valid_allocation() and p.points_unspent() == 9, "remaining points aren't silently discarded")
    check(p.max_hp() == 270 + 145 + 45 * 10, "HP computed from capped STR")
    check(p.max_mp() == 55 + 58 + 45 * 5, "MP computed from capped INT")

func test_matter_damage() -> void:
    check(Damage.physical_damage(100, 40.0, 20.0, 1.0, -15.0) == 100,
        "same matter subtracts 15 pp attack before defense")
    check(Damage.physical_damage(100, 40.0, 5.0) == 133,
        "fire beats wind: PDEF 20 -> 5")
    check(Damage.physical_damage(100, 40.0, 20.0) == 112,
        "neutral target or attack has no matter interaction")
    check(Damage.physical_damage(100, 0.0, -20.0, 1.5) == 180,
        "negative PDEF magnifies physical critical damage")
    check(Damage.magical_damage(100, 40.0, 20.0, -15.0) == 100,
        "magic same matter -15 pp attack; never critical")
    check(Damage.magical_damage(100, 0.0, 85.0) == 15, "defense cap applied after advantage")
    var u = Unit.new("D", "red", 400, 5)
    u.base_pdef_pct = 100.0
    check(near(u.physical_defense_pct(0, -15.0), 85.0),
        "matter adjustment applied before PDEF +90 cap")
    u.base_mdef_pct = 100.0
    check(near(u.magic_defense_pct(-15.0), 85.0),
        "matter adjustment applied before MDEF +90 cap")

func test_combat_and_magic() -> void:
    var demo = Demo.new()
    var f = demo.make_unit("A", "blue", Ally)
    var m = demo.make_unit("E", "red", Enemy)
    check(f.matter == Matter.WATER and m.matter == Matter.FIRE, "runtime uses resolved commander matter")
    check(f.spell_matter == Matter.DARK and m.spell_matter == Matter.FIRE,
        "magic matter comes from book and ignores commander/equipment")
    check(f.spell_power == 20 and f.spell_mana_cost == 10, "resource spell fields loaded")
    var board = Board.new(4, 4)
    board.add_unit("A", Vector2i(1, 1))
    board.add_unit("E", Vector2i(2, 1))
    var units: Dictionary = {"A":f,"E":m}
    var hit: Dictionary = Combat.melee_attack(board, units, "A", "E", 99.0, 0.0)
    check(hit.get("critical", false), "forced physical crit")
    check(near(hit.get("critical_multiplier", 0.0), 1.5), "physical critical coefficient 1.5")
    check(near(hit.get("pdef_percent", 0.0), -5.0), "water attack reduces fire PDEF by 15pp")
    check(hit.get("damage", 0) == 15, "skill8, STR8, PDEF-5, crit1.5 => 15")
    var hp_before: int = m.hp
    var mana_before: int = f.mp
    var magic: Dictionary = Combat.magic_attack(board, units, "A", "E")
    check(magic.get("ok", false) and not magic.get("critical", true), "magic never critical")
    check(magic.get("attack_matter", -1) == Matter.DARK, "dark book defines attack matter")
    check(magic.get("damage", 0) == 18 and m.hp == hp_before - 18,
        "magic power20, INT4, target MDEF18 => 18 damage")
    check(f.mp == mana_before - 10, "spell spends exactly 10 MP")
    f.mp = 0
    var fail: Dictionary = Combat.magic_attack(board, units, "A", "E")
    check(not fail.get("ok", true), "cannot cast without MP")
