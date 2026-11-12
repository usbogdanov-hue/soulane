extends SceneTree
## Run: godot --headless --path . --script res://tests/test_duel_v11.gd
## Deterministic combat checks: injected rolls for evade/critical.

const Demo = preload("res://scripts/battle_demo.gd")
const Board = preload("res://scripts/battle_board.gd")
const Combat = preload("res://scripts/battle_combat.gd")
const Rules = preload("res://scripts/combat_rules.gd")
const Matter = preload("res://scripts/matter_rules.gd")
const MaleStats = preload("res://data/demo_male_lv25.tres")
const FemaleStats = preload("res://data/demo_female_lv25.tres")

var checks: int = 0
var failures: int = 0

func check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAIL: " + description)

func near(a: float, b: float) -> bool:
    return absf(a - b) < 0.0001

func _initialize() -> void:
    run_checks()
    if failures == 0:
        print("SULEYN v1.1: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN v1.1: %d / %d checks FAILED." % [failures, checks])
        quit(1)

func run_checks() -> void:
    var demo = Demo.new()
    var man = demo.make_unit("man", "blue", MaleStats)
    var woman = demo.make_unit("woman", "red", FemaleStats)

    check(man.level == 25 and woman.level == 25, "both commanders level 25")
    check(MaleStats.commander.valid_allocation(), "male 72 allocation points valid")
    check(FemaleStats.commander.valid_allocation(), "female 72 allocation points valid")
    check(man.unspent_points == 0 and woman.unspent_points == 0, "all earned points allocated")
    check(int(man.attributes["STR"]) == 45, "male STR capped at 45")
    check(int(man.attributes["AGI"]) == 18, "male AGI 18")
    check(int(woman.attributes["STR"]) == 20, "female STR 20")
    check(int(woman.attributes["AGI"]) == 55, "female AGI 55")
    check(man.max_hp == 870 and man.max_mp == 163, "male HP/MP correct")
    check(woman.max_hp == 590 and woman.max_mp == 148, "female HP/MP correct")
    check(man.melee_skill_power == 100 and woman.melee_skill_power == 100, "both skills 100")
    check(man.melee_damage_type == Rules.BLUNT, "male blunt weapon")
    check(woman.melee_damage_type == Rules.PIERCING, "female piercing weapon")
    check(man.armor == "Тяжёлая" and woman.armor == "Лёгкая", "armor as requested")
    check(man.matter == Matter.NEUTRAL and woman.matter == Matter.NEUTRAL,
        "neutral matter eliminates interaction from armor calculation")
    check(near(man.physical_defense_pct(Rules.PIERCING), 40.0), "male 40% PDEF vs piercing")
    check(near(woman.physical_defense_pct(Rules.BLUNT), 0.0), "woman 0% PDEF vs blunt")
    check(near(man.final_evasion_pct(), 5.0), "v1.3 heavy male dodge floor 5%: 18 AGI * .5 - 10 = -1%")
    check(near(woman.evasion_pct, 37.5), "light female dodge 37.5%")
    check(near(man.crit_chance_pct, 9.0), "male physical crit 9%")
    check(near(woman.crit_chance_pct, 27.5), "female physical crit 27.5%")

    var board = Board.new(5, 5)
    check(board.add_unit("man", Vector2i(1, 2)), "male placed")
    check(board.add_unit("woman", Vector2i(2, 2)), "female placed adjacent")
    var units: Dictionary = {"man": man, "woman": woman}

    var dodge = Combat.melee_attack(board, units, "man", "woman", 0.0, 0.0)
    check(bool(dodge.get("evaded", false)), "0.0 dodge roll triggers female evade")
    check(int(dodge.get("damage", -1)) == 0 and woman.hp == 590, "evade prevents damage")
    check(near(float(dodge.get("dodge_roll", -1.0)), 0.0), "dodge roll returned for battle log")
    check(near(float(dodge.get("crit_roll", -1.0)), -1.0), "crit is not rolled on evade")

    var normal_male = Combat.melee_attack(board, units, "man", "woman", 99.0, 99.0)
    check(not bool(normal_male.get("critical", true)), "99 crit roll is not critical")
    check(int(normal_male.get("damage", -1)) == 190, "male normal: 100 * 1.9 * (1 - 0) = 190")
    check(woman.hp == 400, "female HP after normal male attack")
    check(near(float(normal_male.get("pdef_percent", -1)), 0.0), "physical PDEF result is logged")

    var normal_female = Combat.melee_attack(board, units, "woman", "man", 99.0, 99.0)
    check(int(normal_female.get("damage", -1)) == 84,
        "female normal: 100 * 1.4 * (1 - 0.4) = 84")
    check(man.hp == 786, "male HP after normal female attack")
    check(near(float(normal_female.get("pdef_percent", -1)), 40.0), "male PDEF 40 logged")

    var male_crit = Combat.melee_attack(board, units, "man", "woman", 99.0, 0.0)
    check(bool(male_crit.get("critical", false)), "0 roll triggers male physical critical")
    check(int(male_crit.get("damage", -1)) == 285, "male crit: 190 * 1.5 = 285")
    check(woman.hp == 115, "female HP after male critical")
    check(near(float(male_crit.get("crit_roll", -1.0)), 0.0), "crit roll returned for journal")

    var female_crit = Combat.melee_attack(board, units, "woman", "man", 99.0, 0.0)
    check(bool(female_crit.get("critical", false)), "0 roll triggers female physical critical")
    check(int(female_crit.get("damage", -1)) == 168, "v1.2 passive female crit: 84 * 2.0 = 168")
    check(man.hp == 618, "male HP after v1.2 female passive critical")

    var magic = Combat.magic_attack(board, units, "woman", "man")
    check(bool(magic.get("ok", false)) and not bool(magic.get("critical", true)),
        "optional magic remains without critical checks")
