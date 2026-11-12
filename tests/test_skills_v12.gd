extends SceneTree
## Run: godot --headless --path . --script res://tests/test_skills_v12.gd
## Deterministic skill, passive critical and two-turn concussion checks.

const Demo = preload("res://scripts/battle_demo.gd")
const Board = preload("res://scripts/battle_board.gd")
const Combat = preload("res://scripts/battle_combat.gd")
const MaleStats = preload("res://data/demo_male_lv25.tres")
const FemaleStats = preload("res://data/demo_female_lv25.tres")

var checks: int = 0
var failures: int = 0


func check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAIL v1.2: " + description)


func _initialize() -> void:
    run_checks()
    if failures == 0:
        print("SULEYN v1.2: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN v1.2: %d / %d checks FAILED." % [failures, checks])
        quit(1)


func make_duel(distance: int = 1) -> Dictionary:
    var demo = Demo.new()
    var man = demo.make_unit("man", "blue", MaleStats)
    var woman = demo.make_unit("woman", "red", FemaleStats)
    demo.free()
    var board = Board.new(7, 5)
    board.add_unit("man", Vector2i(1, 2))
    board.add_unit("woman", Vector2i(1 + distance, 2))
    return {"man": man, "woman": woman, "board": board,
        "units": {"man": man, "woman": woman}}


func run_checks() -> void:
    var duel = make_duel()
    var man = duel["man"]
    var woman = duel["woman"]
    var board = duel["board"]
    var units: Dictionary = duel["units"]
    check(man.special_skill != null and woman.special_skill != null, "each hero has one extra skill")
    check(man.special_skill.skill_power == 120 and man.special_skill.mana_cost == 30,
        "male bonus skill has editable power and MP cost")
    check(woman.special_skill.skill_power == 110 and woman.special_skill.mana_cost == 25,
        "female bonus skill has editable power and MP cost")
    check(man.melee_skill_power == 100 and woman.melee_skill_power == 100,
        "both basic attacks remain at 100")
    check(absf(woman.critical_multiplier - 2.0) < 0.001, "female passive critical x2")
    check(absf(man.critical_multiplier - 1.5) < 0.001, "male critical still x1.5")
    check(man.special_skill.concussion_chance_pct == 33.0,
        "male additional skill concussion chance 33%")
    check(man.special_skill.concussion_skipped_turns == 2,
        "male additional skill concussion lasts two skipped turns")

    var evade = Combat.skill_attack(board, units, "man", "woman",
        man.special_skill, 0.0, 0.0, 0.0)
    check(bool(evade["ok"]) and bool(evade["evaded"]), "dodge works against extra physical skill")
    check(woman.hp == 590 and woman.concussion_turns_remaining == 0,
        "dodged additional skill does no damage or concussion")
    check(man.mp == 133, "failed-to-hit special attack still consumes 30 MP")
    check(float(evade["concussion_roll"]) == -1.0, "concussion roll skipped on evade")

    var stun = Combat.skill_attack(board, units, "man", "woman",
        man.special_skill, 99.0, 99.0, 32.9)
    check(bool(stun["ok"]) and bool(stun["concussion_applied"]),
        "32.9 roll applies 33% concussion")
    check(int(stun["damage"]) == 228, "male special damage 120*1.9=228")
    check(woman.concussion_turns_remaining == 2, "two future turns pending")
    check(man.mp == 103, "two special attacks consume 60 MP")

    var high_roll = Combat.skill_attack(board, units, "man", "woman",
        man.special_skill, 99.0, 99.0, 33.0)
    check(not bool(high_roll["concussion_applied"]), "33.0 roll does not apply 33% stun")
    check(woman.concussion_turns_remaining == 2,
        "failed proc does not remove an existing concussion")

    var woman_duel = make_duel()
    var w = woman_duel["woman"]
    var b = woman_duel["board"]
    var u: Dictionary = woman_duel["units"]
    var regular_crit = Combat.melee_attack(b, u, "woman", "man", 99.0, 0.0)
    check(bool(regular_crit["critical"]) and int(regular_crit["damage"]) == 168,
        "female passive x2 on basic attack: 84*2 = 168")
    var ranged = make_duel(2)
    var ranged_woman = ranged["woman"]
    var ranged_units: Dictionary = ranged["units"]
    var ranged_board = ranged["board"]
    check(not Combat.can_melee(ranged_board, ranged_units, "woman", "man"),
        "normal melee cannot reach 2 hexes")
    check(Combat.can_physical(ranged_board, ranged_units, "woman", "man",
        ranged_woman.special_skill), "female additional skill reaches 2 hexes")
    check(not Combat.can_physical(ranged_board, ranged_units, "man", "woman",
        ranged["man"].special_skill), "male stun skill remains melee only")
    var spear = Combat.skill_attack(ranged_board, ranged_units, "woman", "man",
        ranged_woman.special_skill, 99.0, 0.0)
    check(bool(spear["ok"]) and bool(spear["critical"]), "ranged special can critically hit")
    check(int(spear["damage"]) == 185,
        "female ranged crit x2: round(110 * 1.4 * 0.6 * 2) = 185")
    check(ranged_woman.mp == 123, "ranged spear special consumes 25 MP")
    ranged_woman.mp = 0
    var hp_before: int = ranged["man"].hp
    var empty_mana = Combat.skill_attack(ranged_board, ranged_units, "woman", "man",
        ranged_woman.special_skill, 99.0, 99.0)
    check(not bool(empty_mana["ok"]), "extra skill rejected with insufficient mana")
    check(ranged["man"].hp == hp_before, "insufficient mana does not deal damage")

    var skip_demo = Demo.new()
    skip_demo.encounter_index = 0  # This regression specifically tests the legacy duel.
    skip_demo.reset_demo()
    var target = skip_demo.units[Demo.ENEMY_ID]
    target.apply_concussion(2)
    var turn_before: int = skip_demo.turns.round_number
    skip_demo.advance_turn(Demo.ALLY_ID)
    check(skip_demo.concussion_skip_pending, "first skip is explicitly scheduled")
    check(skip_demo.turns.active_unit_id() == Demo.ENEMY_ID,
        "woman visibly owns first stunned turn before being skipped")
    check(target.concussion_turns_remaining == 2,
        "first skip is NOT silently consumed during man's attack")
    skip_demo.animation_time = Demo.ANIMATION_DURATION
    skip_demo._process(Demo.CONCUSSION_PREVIEW_SECONDS + 0.01)
    check(target.concussion_turns_remaining == 1,
        "first enemy turn is skipped after visible preview")
    check(not skip_demo.concussion_skip_pending,
        "no second skip triggered on the same turn")
    check(skip_demo.turns.active_unit_id() == Demo.ALLY_ID,
        "active hero returns to man after first skipped turn")
    check(skip_demo.concussion_notice_text.contains("1 из 2"),
        "first skipped turn is numbered 1/2 for the player")
    skip_demo.advance_turn(Demo.ALLY_ID)
    check(skip_demo.concussion_skip_pending and target.concussion_turns_remaining == 1,
        "second stunned turn is queued, not consumed prematurely")
    check(skip_demo.turns.active_unit_id() == Demo.ENEMY_ID,
        "woman visibly owns second stunned turn")
    skip_demo._process(Demo.CONCUSSION_PREVIEW_SECONDS + 0.01)
    check(target.concussion_turns_remaining == 0, "second enemy turn is skipped")
    check(skip_demo.concussion_notice_text.contains("2 из 2"),
        "second skipped turn is numbered 2/2 for the player")
    check(skip_demo.turns.active_unit_id() == Demo.ALLY_ID,
        "control returns to man after second skipped turn")
    check(skip_demo.turns.round_number == turn_before + 2,
        "two skipped turns are counted in combat rounds")
    skip_demo.advance_turn(Demo.ALLY_ID)
    check(not skip_demo.concussion_skip_pending and
        skip_demo.turns.active_unit_id() == Demo.ENEMY_ID,
        "woman can act normally on her third turn opportunity")
    skip_demo.free()
