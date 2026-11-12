extends SceneTree
## Run: godot --headless --path . --script res://tests/test_gdd_v09.gd

const Rules = preload("res://scripts/combat_rules.gd")
const Profile = preload("res://scripts/commander_profile.gd")
const Unit = preload("res://scripts/battle_unit.gd")
const Board = preload("res://scripts/battle_board.gd")
const Combat = preload("res://scripts/battle_combat.gd")
const Damage = preload("res://scripts/damage_calculator.gd")
const Element = preload("res://scripts/element_rules.gd")
const Demo = preload("res://scripts/battle_demo.gd")
const Ally = preload("res://data/demo_ally.tres")
const Enemy = preload("res://data/demo_enemy.tres")

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
    test_growth_and_bonuses()
    test_armor_and_defense()
    test_monster_categories()
    test_limits_and_damage()
    test_runtime_combat()
    test_magic_books()
    if failures == 0:
        print("SULEYN v0.9: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN v0.9: %d failures of %d checks." % [failures, checks])
        quit(1)

func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED: " + label)

func near(a: float, b: float) -> bool:
    return absf(a - b) < 0.0001

func test_growth_and_bonuses() -> void:
    var f = Ally.commander
    var m = Enemy.commander
    check(f.max_hp() == 395 and f.max_mp() == 93, "female L10 HP 395 MP 93")
    check(m.max_hp() == 445 and m.max_mp() == 98, "male L10 HP 445 MP 98")
    check(f.points_earned() == 27 and m.points_earned() == 27, "level 10 earns 27 points")
    check(near(f.get("evasion_percent"), 5.0) and near(m.get("evasion_percent"), 5.0), "v1.3 universal dodge floor 5% after AGI and armor")
    check(near(f.get("crit_chance_percent"), 5.0) and near(m.get("crit_chance_percent"), 4.0), "AGI critical 0.5%")
    check(near(f.get("mana_regen_percent"), 1.8) and near(m.get("mana_regen_percent"), 1.2), "WIS regen 0.3%")
    check(near(f.get("magic_resistance_percent"), 12.0), "WIS magic resistance +2%")
    check(near(f.get("physical_damage_bonus_percent"), 16.0), "STR physical attack +2%")
    var woman = Profile.new()
    woman.archetype = 1
    woman.level = 30
    woman.points_str = 40
    woman.points_agi = 30
    woman.points_wis = 12
    woman.points_int = 5
    check(woman.points_unspent() == 3 and woman.points_str == 37 and woman.max_hp() == 865 and woman.max_mp() == 158,
        "female L30: STR hard-capped at 45; surplus points remain")
    check(near(woman.get("evasion_percent"), 20.0), "without armor 40 AGI=20 evade")
    woman.armor_type = 3
    check(near(woman.get("evasion_percent"), 10.0), "heavy -10 evade")
    var mage = Profile.new()
    mage.archetype = 4
    mage.level = 30
    mage.points_str = 5
    mage.points_agi = 12
    mage.points_wis = 25
    mage.points_int = 45
    mage.armor_type = 1
    check(mage.max_hp() == 395 and mage.max_mp() == 383 and mage.primary_stats()["INT"] == 45,
        "male mage L30 INT capped at 45, HP 395 MP 383")
    check(near(mage.get("mana_regen_percent"), 9.9), "33 WIS -> 9.9% mana regen")
    check(near(mage.get("magic_power_percent"), 90.0), "INT bonus limited at 90%")
    check(near(mage.magic_defense_pct(), 86.0), "mage MDEF 66 WIS + 20 armor=86")

func test_armor_and_defense() -> void:
    var p = Profile.new()
    p.archetype = 1
    for row in [[0, 0, 0, 0, 0], [1, 0, 0, 0, 20], [2, 20, 10, 20, 10], [3, 40, 30, 20, 0]]:
        p.armor_type = row[0]
        check(near(p.physical_defense_pct(Rules.PIERCING), float(row[1])), "armor piercing %d" % row[0])
        check(near(p.physical_defense_pct(Rules.SLASHING), float(row[2])), "armor slashing %d" % row[0])
        check(near(p.physical_defense_pct(Rules.BLUNT), float(row[3])), "armor blunt %d" % row[0])
        check(near(float(p.armor_mdef_bonus()), float(row[4])), "armor MDEF %d" % row[0])
    p.armor_type = 1
    check(near(p.physical_defense_pct(Rules.PIERCING, -20.0), -20.0), "negative resistance from debuff allowed")
    p.armor_type = 3
    check(near(p.magic_defense_pct(), 12.0), "female heavy adds 0 MDEF + 12 from WIS")

func test_monster_categories() -> void:
    var monster = Unit.new("monster", "red", 100, 5)
    monster.is_monster = true
    monster.base_pdef_pct = 20.0
    monster.base_mdef_pct = 10.0
    monster.monster_categories = Rules.FLYING | Rules.GROUND | Rules.MAGICAL_UNDEAD
    monster.armor_pdef_pct = 90.0
    monster.armor_mdef_pct = 90.0
    monster.armor_weapon_bonuses = {Rules.PIERCING: 90.0}
    check(near(monster.physical_defense_pct(Rules.PIERCING), 5.0), "monster flying: 20 - 15 piercing, no armor")
    check(near(monster.physical_defense_pct(Rules.SLASHING), 5.0), "monster ground: 20 - 15 slashing")
    check(near(monster.physical_defense_pct(Rules.BLUNT), 5.0), "monster magical/undead: 20 - 15 blunt")
    check(near(monster.magic_defense_pct(), 10.0), "monster has its own MDEF without armor")
    var sample = load("res://data/sample_monster_unit.tres")
    var built = Demo.new().make_unit("M", "red", sample)
    check(built.is_monster and built.base_pdef_pct == 20.0 and built.base_mdef_pct == 10.0,
        "editable monster profile loads without commander armor")
    check(near(built.physical_defense_pct(Rules.SLASHING), 5.0) and built.melee_skill_power == 10,
        "monster sample uses own skill power and -15 ground vulnerability")
    monster.is_monster = false
    monster.armor_pdef_pct = 0.0
    monster.armor_mdef_pct = 0.0
    monster.armor_weapon_bonuses.clear()
    check(near(monster.physical_defense_pct(Rules.SLASHING), 20.0), "commander never has monster category vulnerability")

func test_limits_and_damage() -> void:
    check(near(Rules.cap_percent(110.0), 90.0), "90% maximum percent")
    check(near(Rules.cap_percent(-30.0), -30.0), "negative defense unlimited below")
    check(near(Rules.cap_chance(140.0), 90.0) and near(Rules.cap_chance(-5.0), 0.0), "probabilities range 0..90")
    check(near(Rules.cap_chance(100.0, true), 100.0), "guaranteed effects remain 100%")
    check(Damage.physical_damage(100, 96.0, 0.0) == 190, "STR +96% capped at +90%")
    check(Damage.physical_damage(100, 0.0, 90.0) == 10, "defense cap leaves 10% damage")
    check(Damage.physical_damage(100, 0.0, -20.0) == 120, "-20% defense produces +20% damage")
    check(Damage.physical_damage(0, 90.0, -20.0) == 0, "zero power causes zero damage")
    var u = Unit.new("defender", "blue", 100, 5)
    u.base_pdef_pct = 80.0
    u.armor_pdef_pct = 20.0
    check(near(u.physical_defense_pct(Rules.SLASHING), 90.0), "combined defense capped at +90%")
    u.base_mdef_pct = 100.0
    check(near(u.magic_defense_pct(), 90.0), "MDEF capped at 90%")
    u.base_mdef_pct = -30.0
    check(near(u.magic_defense_pct(), -30.0), "negative MDEF allowed")

func test_runtime_combat() -> void:
    var demo = Demo.new()
    var f = demo.make_unit("A", "blue", Ally)
    var m = demo.make_unit("E", "red", Enemy)
    check(f.hp == 395 and f.mp == 93 and m.hp == 445 and m.mp == 98, "runtime uses revised HP/MP")
    check(f.melee_skill_power == 8 and m.melee_skill_power == 7, "power comes from separate skill resources")
    check(f.melee_damage_type == Rules.SLASHING, "skill type is slashing")
    check(near(m.physical_defense_pct(Rules.SLASHING), 10.0), "medium armor vs slashing only base 10%")
    check(near(f.physical_defense_pct(Rules.SLASHING), 30.0), "heavy armor vs slashing 20+10=30%")
    check(near(f.magic_defense_pct(), 12.0) and near(m.magic_defense_pct(), 18.0), "total commander MDEF")
    var board = Board.new(4, 4)
    board.add_unit("A", Vector2i(1, 1))
    board.add_unit("E", Vector2i(2, 1))
    var units: Dictionary = {"A": f, "E": m}
    var dodge: Dictionary = Combat.melee_attack(board, units, "A", "E", 0.0, 99.0)
    check(dodge.get("ok", false) and dodge.get("evaded", false) and m.hp == 445, "forced dodge")
    var hit: Dictionary = Combat.melee_attack(board, units, "A", "E", 99.0, 0.0)
    var expected: int = Damage.physical_damage(8, 16.0, m.physical_defense_pct(Rules.SLASHING, -15.0), 1.5)
    check(hit.get("ok", false) and not hit.get("evaded", true) and hit.get("critical", false), "forced critical event")
    check(hit.get("damage", -1) == expected and m.hp == 445 - expected, "skill power - defense attack result")
    check(hit.get("pdef_percent", -1.0) == -5.0, "water beats fire, subtracts 15 pp PDEF")
    check(f.spend_mana(20) and f.mp == 73, "mana spends unchanged")
    check(f.regenerate_mana_end_turn() == 1 and f.mp == 74, "1.8% of 93 -> 1 MP with remainder")
    check(f.regenerate_mana_end_turn() == 2 and f.mp == 76, "fractional MP carries forward")

func test_magic_books() -> void:
    var novice = load("res://data/magic_books/novice.tres")
    var forest = load("res://data/magic_books/forest_talmud.tres")
    var fire = load("res://data/magic_books/fire.tres")
    check(novice.element == Element.NEUTRAL and forest.element == Element.NEUTRAL, "two book families cause neutral magical damage")
    check(fire.element == Element.FIRE, "fire book defines spell attack element")
    check(near(Element.same_element_attack_penalty(Element.FIRE, Element.FIRE), -15.0), "same element -15% attack")
    check(near(Element.target_defense_penalty(Element.FIRE, Element.WIND), -15.0), "fire vs wind: -15 pp target defense")
    check(near(Element.target_defense_penalty(Element.NEUTRAL, Element.WIND), 0.0), "neutral magic has no elemental modifiers")
