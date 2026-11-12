extends SceneTree
## Run: godot --headless --path . --script res://tests/test_commanders.gd

const Profile = preload("res://scripts/commander_profile.gd")
const Unit = preload("res://scripts/battle_unit.gd")
const Ally = preload("res://data/demo_ally.tres")
const Enemy = preload("res://data/demo_enemy.tres")

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
    test_all_base_profiles()
    test_level_ten_warriors()
    test_point_distribution()
    test_runtime_health_and_mana()
    if failures == 0:
        print("SULEYN v0.9: %d commander checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN v0.9: %d / %d checks failed." % [failures, checks])
        quit(1)

func check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAILED: " + description)

func test_all_base_profiles() -> void:
    var cases = [
        [0, 10, 8, 4, 6, 300, 50],
        [1, 8, 10, 6, 4, 270, 55],
        [2, 7, 7, 7, 7, 220, 70],
        [3, 6, 8, 8, 6, 190, 75],
        [4, 5, 5, 8, 10, 150, 100],
        [5, 4, 6, 10, 8, 135, 105],
    ]
    for item in cases:
        var p = Profile.new()
        p.archetype = item[0]
        var s: Dictionary = p.primary_stats()
        check(s["STR"] == item[1] and s["AGI"] == item[2]
            and s["WIS"] == item[3] and s["INT"] == item[4],
            "class %d: GDD attributes at level 1" % item[0])
        check(p.max_hp() == item[5] + item[1] * 10 and p.max_mp() == item[6] + item[4] * 5,
            "class %d: GDD HP/MP at level 1" % item[0])
        check(p.points_earned() == 0 and p.points_unspent() == 0,
            "class %d: level 1 has no level-up points" % item[0])

func test_level_ten_warriors() -> void:
    var f = Ally.commander
    var m = Enemy.commander
    check(f.archetype == 1 and f.level == 10 and f.armor_type == 3,
        "female warrior level 10, heavy armor")
    check(m.archetype == 0 and m.level == 10 and m.armor_type == 2,
        "male warrior level 10, medium armor")
    check(f.max_hp() == 395 and f.max_mp() == 93, "female HP/MP level 10")
    check(m.max_hp() == 445 and m.max_mp() == 98, "male HP/MP level 10")
    check(f.points_unspent() == 27 and m.points_unspent() == 27,
        "nine level-ups means 27 unallocated points each")
    check(f.primary_stats() == {"STR": 8, "AGI": 10, "WIS": 6, "INT": 4},
        "female base attributes remain untouched")
    check(m.primary_stats() == {"STR": 10, "AGI": 8, "WIS": 4, "INT": 6},
        "male base attributes remain untouched")

func test_point_distribution() -> void:
    var p = Profile.new()
    p.level = 10
    p.archetype = 1
    p.points_str = 12
    p.points_agi = 9
    p.points_wis = 6
    check(p.valid_allocation(), "27 selected points are valid")
    check(p.points_unspent() == 0, "all selectable points consumed")
    var s: Dictionary = p.primary_stats()
    check(s["STR"] == 20 and s["AGI"] == 19 and s["WIS"] == 12 and s["INT"] == 4,
        "points only affect selected attributes")
    check(p.max_hp() == 515 and p.max_mp() == 93,
        "allocated STR affects HP; INT remains base")
    p.points_int = 1
    check(p.valid_allocation() and p.points_unspent() == 0 and p.points_int == 0,
        "overallocated level-up points are prevented")

func test_runtime_health_and_mana() -> void:
    var f = Unit.new("A", "blue", Ally.commander.max_hp(), Ally.attack,
        Ally.defense, Ally.movement, Ally.display_name)
    f.max_mp = Ally.commander.max_mp()
    f.mp = f.max_mp
    check(f.max_hp == 395 and f.hp == 395 and f.mp == 93,
        "female runtime HP/MP match GDD")
    check(f.receive_damage(12) == 12 and f.hp == 383,
        "existing damage path works on commander HP")
