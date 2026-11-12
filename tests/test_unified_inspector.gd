extends SceneTree
## Run: godot --headless --path . --script res://tests/test_unified_inspector.gd

const Profile = preload("res://scripts/commander_profile.gd")
const Ally = preload("res://data/demo_ally.tres")
const Enemy = preload("res://data/demo_enemy.tres")

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
    test_connected_base_resources()
    test_editor_preview_properties()
    test_points_limit_and_level_decrease()
    test_edit_shared_base_without_changing_archetype()
    if failures == 0:
        print("SULEYN v0.9: %d unified Inspector checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN v0.9: %d/%d checks failed." % [failures, checks])
        quit(1)

func check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAILED: " + description)

func test_connected_base_resources() -> void:
    var f = Ally.commander
    var m = Enemy.commander
    check(f.base_stats != null and m.base_stats != null, "both demo commanders expose base resource")
    check(f.base_stats == Profile.BASES[1], "female reference shares the GDD archetype resource")
    check(m.base_stats == Profile.BASES[0], "male reference shares the GDD archetype resource")
    check(f.max_hp() == 395 and f.max_mp() == 93, "female fixed HP/MP growth preserved")
    check(m.max_hp() == 445 and m.max_mp() == 98, "male fixed HP/MP growth preserved")

func test_editor_preview_properties() -> void:
    var p = Ally.commander
    var props: Dictionary = {}
    for item in p.get_property_list():
        props[item["name"]] = item
    for name in ["final_str", "final_agi", "final_wis", "final_int", "final_max_hp", "final_max_mp", "earned_points", "spent_points", "remaining_points", "allocation_state"]:
        check(props.has(name), "preview includes %s" % name)
        if props.has(name):
            var flags: int = int(props[name]["usage"])
            check((flags & PROPERTY_USAGE_READ_ONLY) != 0, "preview %s is read-only" % name)
            check((flags & PROPERTY_USAGE_STORAGE) == 0, "preview %s isn't saved in resource" % name)
    check(p.get("final_str") == 8 and p.get("final_agi") == 10, "preview calculates final attributes")
    check(p.get("final_max_hp") == 395 and p.get("final_max_mp") == 93, "preview calculates final HP/MP")
    check(p.get("earned_points") == 27 and p.get("remaining_points") == 27, "preview calculates remaining points")

func test_points_limit_and_level_decrease() -> void:
    var p = Profile.new()
    p.archetype = 1
    p.level = 10
    p.points_str = 18
    p.points_agi = 12
    check(p.points_str == 18 and p.points_agi == 9, "points over remaining budget are clamped")
    check(p.points_unspent() == 0 and p.valid_allocation(), "cannot exceed 27 points")
    p.level = 5
    check(p.points_earned() == 12 and p.points_spent() == 12, "level decrease trims points")
    check(p.points_str == 12 and p.points_agi == 0, "trimming prioritizes STR then AGI")
    check(p.max_hp() == 490 and p.max_mp() == 83, "HP/MP growth after level decrease")
    p.level = 10
    check(p.points_unspent() == 15, "points reopen after level increase")

func test_edit_shared_base_without_changing_archetype() -> void:
    var p = Profile.new()
    p.archetype = 1
    p.level = 10
    p.base_stats = Profile.BASES[1]
    var b = p.base_stats
    var old_str: int = b.base_str
    var old_hp: int = b.base_hp
    b.base_str = old_str + 1
    b.base_hp = old_hp + 10
    check(p.primary_stats()["STR"] == old_str + 1, "nested base edit updates STR")
    check(p.max_hp() == old_hp + 10 + 45 + (old_str + 1) * 10, "nested base edit updates max HP")
    b.base_str = old_str
    b.base_hp = old_hp
    check(p.primary_stats()["STR"] == 8 and p.max_hp() == 395, "base values restored")
