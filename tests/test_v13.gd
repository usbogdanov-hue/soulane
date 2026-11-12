extends SceneTree
## Run: godot --headless --path . --script res://tests/test_v13.gd
## Regression: universal evasion floor/ceiling, existing stun/MP/critical paths.

const Rules = preload("res://scripts/combat_rules.gd")
const Unit = preload("res://scripts/battle_unit.gd")
const Demo = preload("res://scripts/battle_demo.gd")
const Board = preload("res://scripts/battle_board.gd")
const Combat = preload("res://scripts/battle_combat.gd")
const Male = preload("res://data/demo_male_lv25.tres")
const Female = preload("res://data/demo_female_lv25.tres")

var checks: int = 0
var failures: int = 0

func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED v1.3: " + label)

func near(a: float, b: float) -> bool:
    return absf(a - b) < 0.001

func _initialize() -> void:
    run_tests()
    if failures == 0:
        print("SULEYN v1.3: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN v1.3: %d / %d checks FAILED." % [failures, checks])
        quit(1)

func run_tests() -> void:
    check(near(Rules.final_evasion(-100.0), 5.0), "deeply negative evasion floors at 5%")
    check(near(Rules.final_evasion(0.0), 5.0), "zero evasion floors at 5%")
    check(near(Rules.final_evasion(4.99), 5.0), "4.99% floors at 5%")
    check(near(Rules.final_evasion(5.0), 5.0), "5% stays 5%")
    check(near(Rules.final_evasion(37.5), 37.5), "normal evasion unchanged")
    check(near(Rules.final_evasion(90.0), 90.0), "90% stays 90%")
    check(near(Rules.final_evasion(250.0), 90.0), "extreme positive evasion caps at 90%")
    check(near(Rules.cap_chance(0.0), 0.0), "critical chance still can be 0%")
    check(near(Rules.cap_chance(100.0, true), 100.0), "guaranteed effects still 100%")

    var demo = Demo.new()
    var man = demo.make_unit("man", "blue", Male)
    var woman = demo.make_unit("woman", "red", Female)
    check(near(float(Male.commander.get("evasion_percent")), 5.0), "male Inspector has 5% floor")
    check(near(float(Female.commander.get("evasion_percent")), 37.5), "female Inspector remains 37.5%")
    check(near(man.evasion_pct, 5.0) and near(man.final_evasion_pct(), 5.0),
        "male runtime 18 AGI minus heavy armor = 5%, not 0%")
    check(near(woman.evasion_pct, 37.5), "woman runtime 55 AGI plus light armor = 37.5%")
    check(near(man.crit_chance_pct, 9.0) and near(woman.crit_chance_pct, 27.5),
        "evasion floor does not change physical crit chances")
    check(near(woman.critical_multiplier, 2.0), "female passive x2 critical remains active")

    var monster = Unit.new("monster", "red", 5000, 100)
    monster.is_monster = true
    check(near(monster.final_evasion_pct(), 5.0), "new monster starts at 5% dodge")
    monster.evasion_pct = -35.0
    check(near(monster.final_evasion_pct(), 5.0), "monster severe evasion debuff floors at 5%")

    var board = Board.new(5, 5)
    check(board.add_unit("man", Vector2i(1, 2)), "man placed")
    check(board.add_unit("monster", Vector2i(2, 2)), "monster placed")
    var units: Dictionary = {"man": man, "monster": monster}
    var dodge = Combat.melee_attack(board, units, "man", "monster", 4.99, 99.0)
    check(bool(dodge.get("ok", false)) and bool(dodge.get("evaded", false)),
        "roll 4.99 dodges against even negative base evasion")
    check(near(float(dodge.get("evasion_percent", -1.0)), 5.0),
        "combat log reports clamped 5% evasion")
    var hit = Combat.melee_attack(board, units, "man", "monster", 5.0, 99.0)
    check(bool(hit.get("ok", false)) and not bool(hit.get("evaded", true)),
        "roll 5.0 hits: maximum physical hit chance is 95%")
    monster.evasion_pct = 250.0
    var upper_dodge = Combat.melee_attack(board, units, "man", "monster", 89.99, 99.0)
    check(bool(upper_dodge.get("evaded", false)) and near(float(upper_dodge.get("evasion_percent", -1)), 90.0),
        "90% evasion ceiling used by combat")
    var upper_hit = Combat.melee_attack(board, units, "man", "monster", 90.0, 99.0)
    check(bool(upper_hit.get("ok", false)) and not bool(upper_hit.get("evaded", true)),
        "90.0 roll hits against 90% dodge: minimum hit chance 10%")

    var board2 = Board.new(5, 5)
    check(board2.add_unit("woman", Vector2i(1, 2)), "woman placed")
    check(board2.add_unit("man", Vector2i(2, 2)), "man placed for critical checks")
    var heroes: Dictionary = {"man": man, "woman": woman}
    var man_hp_before: int = man.hp
    var passive_crit = Combat.melee_attack(board2, heroes, "woman", "man", 99.0, 0.0)
    check(bool(passive_crit.get("critical", false)) and int(passive_crit.get("damage", -1)) == 168,
        "female 27.5% physical crit chance, x2 passive damage unchanged")
    check(man.hp == man_hp_before - 168, "critical damage applies correctly")

    var board3 = Board.new(5, 5)
    var another_man = demo.make_unit("m2", "blue", Male)
    var another_woman = demo.make_unit("w2", "red", Female)
    board3.add_unit("m2", Vector2i(1, 2))
    board3.add_unit("w2", Vector2i(2, 2))
    var duel_units: Dictionary = {"m2": another_man, "w2": another_woman}
    var old_mp: int = another_man.mp
    var stunned = Combat.skill_attack(board3, duel_units, "m2", "w2",
        another_man.special_skill, 99.0, 99.0, 0.0)
    check(bool(stunned.get("ok", false)) and bool(stunned.get("concussion_applied", false)),
        "special still applies 33% concussion with roll 0")
    check(another_woman.concussion_turns_remaining == 2, "concussion holds two upcoming turns")
    check(another_man.mp == old_mp - 30, "special still costs 30 MP")
    check(another_woman.skip_concussed_turn(), "concussed defender skips first turn")
    check(another_woman.skip_concussed_turn(), "concussed defender skips second turn")
    check(not another_woman.skip_concussed_turn(), "concussion does not skip third turn")
    check(another_woman.concussion_turns_remaining == 0, "concussion counter returns to zero")
    var regen: int = another_man.regenerate_mana_end_turn()
    check(regen > 0 and another_man.mp == old_mp - 30 + regen,
        "end-of-turn mana regeneration still works")
