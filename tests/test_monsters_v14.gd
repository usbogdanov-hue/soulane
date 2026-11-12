extends SceneTree
## Godot-only integration tests, run with:
## godot --headless --path . --script res://tests/test_monsters_v14.gd

const Demo = preload("res://scripts/battle_demo.gd")
const Board = preload("res://scripts/battle_board.gd")
const Combat = preload("res://scripts/battle_combat.gd")
const Rules = preload("res://scripts/combat_rules.gd")
const Matter = preload("res://scripts/matter_rules.gd")
const Male = preload("res://data/demo_male_lv25.tres")
const Falcon = preload("res://data/monsters/falcon_unit_v14.tres")
const Hound = preload("res://data/monsters/hellhound_unit_v14.tres")
const Lich = preload("res://data/monsters/lich_unit_v14.tres")

var checks: int = 0
var failed: int = 0

func check(condition: bool, label: String) -> void:
    checks += 1
    if not condition:
        failed += 1
        printerr("v1.4 FAILURE: " + label)

func near(a: float, b: float) -> bool:
    return absf(a - b) < 0.001

func _initialize() -> void:
    run_tests()
    if failed == 0:
        print("SULEYN v1.4: %d tests passed" % checks)
        quit(0)
    else:
        printerr("SULEYN v1.4: %d / %d failed" % [failed, checks])
        quit(1)

func run_tests() -> void:
    var demo = Demo.new()
    var f = demo.make_unit("f", "red", Falcon)
    var h = demo.make_unit("h", "red", Hound)
    var l = demo.make_unit("l", "red", Lich)
    check(f.is_monster and h.is_monster and l.is_monster, "all test entities are monsters")
    check(f.monster_categories == Rules.FLYING and h.monster_categories == Rules.GROUND
        and l.monster_categories == Rules.MAGICAL_UNDEAD, "three vulnerability categories")
    check(f.matter == Matter.WIND and h.matter == Matter.FIRE and l.matter == Matter.DARK,
        "air/fire/dark matter assignments")
    check(near(f.physical_defense_pct(Rules.PIERCING), 5.0), "flying falcon -15 pp vs piercing")
    check(near(f.physical_defense_pct(Rules.SLASHING), 20.0), "falcon no slash vulnerability")
    check(near(h.physical_defense_pct(Rules.SLASHING), 15.0), "ground hound -15 pp vs slashing")
    check(near(h.physical_defense_pct(Rules.BLUNT), 30.0), "hound no blunt vulnerability")
    check(near(l.physical_defense_pct(Rules.BLUNT), -5.0), "undead lich has negative blunt PDEF")
    check(near(l.magic_defense_pct(), 40.0), "undead's base MDEF is independently tunable")
    check(near(f.final_evasion_pct(), 20.0), "monster own evasion property")
    check(near(h.final_evasion_pct(), 10.0), "second monster own evasion property")
    check(near(l.final_evasion_pct(), 5.0), "universal 5% evasion floor")

    # Armor must never affect monster defenses, even if an accidental value is assigned.
    l.armor_pdef_pct = 90.0
    l.armor_mdef_pct = 90.0
    l.armor_weapon_bonuses = {Rules.BLUNT: 50.0}
    check(near(l.physical_defense_pct(Rules.BLUNT), -5.0), "monster never gains armor")
    check(near(l.magic_defense_pct(), 40.0), "monster ignores armor MDEF")
    check(near(f.physical_defense_pct(Rules.PIERCING, -15.0), -10.0),
        "flying vulnerability stacks with fire superiority against air")
    check(near(Matter.attack_penalty_pct(Matter.FIRE, Matter.FIRE), -15.0),
        "same matter causes -15 pct to attack")
    check(near(Matter.defense_penalty_pp(Matter.WATER, Matter.FIRE), -15.0),
        "water defeats fire")
    check(near(Matter.defense_penalty_pp(Matter.NEUTRAL, Matter.FIRE), 0.0),
        "neutral has no advantage")

    var attacker = demo.make_unit("man", "blue", Male)
    var map = Board.new(5, 5)
    check(map.add_unit("man", Vector2i(1, 2)) and map.add_unit("l", Vector2i(2, 2)),
        "adjacent monster board placements")
    var combatants: Dictionary = {"man": attacker, "l": l}
    var physical = Combat.melee_attack(map, combatants, "man", "l", 99.0, 99.0)
    check(bool(physical.get("ok", false)) and not bool(physical.get("evaded", true)),
        "normal hit against undead")
    check(int(physical.get("calculated_damage", -1)) == 200,
        "190 attack into -5 percent PDEF rounds to 200")
    check(not bool(physical.get("critical", true)), "non-critical hit is still possible")

    # Monster magic uses book's matter and no critical/evasion even when high crit exists.
    var lich_magic = demo.make_unit("lm", "red", Lich)
    var victim = demo.make_unit("man2", "blue", Male)
    var magic_board = Board.new(5, 5)
    magic_board.add_unit("lm", Vector2i(1, 2))
    magic_board.add_unit("man2", Vector2i(2, 2))
    var magic_units: Dictionary = {"lm": lich_magic, "man2": victim}
    check(lich_magic.max_mp == 100 and lich_magic.mp == 100,
        "monster mana initialized from its profile")
    check(lich_magic.spell_matter == Matter.DARK, "monster spell matter from dark book")
    var magic_result = Combat.magic_attack(magic_board, magic_units, "lm", "man2")
    check(bool(magic_result.get("ok", false)), "dark spell cast from monster")
    check(not bool(magic_result.get("critical", true)) and not bool(magic_result.get("evaded", true)),
        "magic has no crit or evasion")
    check(lich_magic.mp == 90, "spell consumes 10 MP")

    # The switch resets the encounter, not the original validated two-person mechanics.
    demo.encounter_index = 0
    check(demo.encounter_enemy_stats() == demo.enemy_stats, "original duel preserved")
    demo.encounter_index = 1
    check(demo.encounter_enemy_stats() == Falcon, "first monster scenario")
    demo.encounter_index = 2
    check(demo.encounter_enemy_stats() == Hound, "second monster scenario")
    demo.encounter_index = 3
    check(demo.encounter_enemy_stats() == Lich, "third monster scenario")
