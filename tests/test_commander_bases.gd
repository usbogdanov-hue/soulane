extends SceneTree
## Run: godot --headless --path . --script res://tests/test_commander_bases.gd

const Profile = preload("res://scripts/commander_profile.gd")
const BaseStats = preload("res://scripts/commander_base_stats.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    test_six_editable_resources()
    test_resource_edits_update_commander()
    if failures == 0:
        print("SULEYN v0.6: %d base resource checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN v0.6: %d / %d base resource checks failed." % [failures, checks])
        quit(1)


func check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAILED: " + description)


func test_six_editable_resources() -> void:
    var cases = [
        ["Воин-мужчина", 10, 8, 4, 6, 300, 50],
        ["Воин-женщина", 8, 10, 6, 4, 270, 55],
        ["Гибрид-мужчина", 7, 7, 7, 7, 220, 70],
        ["Гибрид-женщина", 6, 8, 8, 6, 190, 75],
        ["Маг-мужчина", 5, 5, 8, 10, 150, 100],
        ["Маг-женщина", 4, 6, 10, 8, 135, 105],
    ]
    check(Profile.BASES.size() == 6, "six base resources loaded")
    for i in range(cases.size()):
        var item: Array = cases[i]
        var resource = Profile.BASES[i]
        check(resource.get_script() == BaseStats, "archetype %d loaded from custom resource" % i)
        var p = Profile.new()
        p.archetype = i
        var base: Dictionary = p.base_record()
        check(base["name"] == item[0], "archetype %d: name" % i)
        check(base["str"] == item[1] and base["agi"] == item[2] and
            base["wis"] == item[3] and base["int"] == item[4],
            "archetype %d: GDD primary stats" % i)
        check(p.max_hp() == item[5] + item[1] * 10 and p.max_mp() == item[6] + item[4] * 5,
            "archetype %d: GDD HP/MP" % i)


func test_resource_edits_update_commander() -> void:
    var p = Profile.new()
    p.archetype = 1
    p.level = 10
    p.points_str = 5
    var resource = Profile.BASES[1]
    var old_str: int = resource.base_str
    var old_hp: int = resource.base_hp
    resource.base_str = old_str + 2
    resource.base_hp = old_hp + 10
    check(p.primary_stats()["STR"] == old_str + 7,
        "changing base STR changes final STR without editing code")
    check(p.max_hp() == old_hp + 10 + 45 + (old_str + 7) * 10,
        "changing base HP changes level-10 HP")
    check(p.points_unspent() == 22, "level-up point budget unchanged")
    resource.base_str = old_str
    resource.base_hp = old_hp
    check(p.primary_stats()["STR"] == 13 and p.max_hp() == 445,
        "restored defaults match GDD values")
