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
    test_level_decrease_priority_boundaries()
    test_repeated_level_decrease_and_increase()
    test_level_decrease_with_unspent_points()
    test_nested_base_caps_preserve_other_allocations()
    test_replaced_base_caps_before_level_decrease()
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

func test_level_decrease_priority_boundaries() -> void:
    var scenarios: Array = [
        {"level": 9, "points": [6, 6, 6, 6], "hp": 450, "mp": 121},
        {"level": 6, "points": [6, 6, 3, 0], "hp": 435, "mp": 85},
        {"level": 4, "points": [6, 3, 0, 0], "hp": 425, "mp": 81},
        {"level": 2, "points": [3, 0, 0, 0], "hp": 385, "mp": 77},
        {"level": 1, "points": [0, 0, 0, 0], "hp": 350, "mp": 75},
    ]
    for scenario in scenarios:
        var p = Profile.new()
        p.archetype = 1
        p.level = 10
        p.points_str = 6
        p.points_agi = 6
        p.points_wis = 6
        p.points_int = 9
        p.level = scenario["level"]
        var label: String = "level 10 -> %d" % p.level
        check([p.points_str, p.points_agi, p.points_wis, p.points_int] == scenario["points"],
            label + " preserves STR > AGI > WIS > INT")
        check(p.valid_allocation() and p.points_unspent() == 0,
            label + " retains the full available budget")
        check(p.max_hp() == scenario["hp"] and p.max_mp() == scenario["mp"]
            and p.get("final_max_hp") == scenario["hp"] and p.get("final_max_mp") == scenario["mp"],
            label + " updates HP/MP and Inspector previews")

func test_repeated_level_decrease_and_increase() -> void:
    var p = Profile.new()
    p.archetype = 1
    p.level = 10
    p.points_str = 18
    p.points_agi = 9
    p.level = 5
    p.level = 3
    check([p.points_str, p.points_agi, p.points_wis, p.points_int] == [6, 0, 0, 0]
        and p.valid_allocation(), "repeated decreases preserve the highest-priority points")
    p.level = 1
    check(p.points_spent() == 0 and p.points_earned() == 0 and p.valid_allocation(),
        "level one clears every allocated point")
    p.level = 10
    check(p.points_spent() == 0 and p.points_unspent() == 27,
        "increasing after a reset returns unspent points without restoring allocations")
    check(p.max_hp() == 395 and p.max_mp() == 93,
        "HP/MP growth after a reset retains base and level formulas")

func test_level_decrease_with_unspent_points() -> void:
    var p = Profile.new()
    p.archetype = 1
    p.level = 10
    p.points_str = 2
    p.points_agi = 3
    p.points_wis = 1
    p.points_int = 2
    p.level = 5
    check([p.points_str, p.points_agi, p.points_wis, p.points_int] == [2, 3, 1, 2],
        "a sufficient reduced budget preserves every allocation")
    check(p.points_unspent() == 4 and p.valid_allocation(),
        "a sufficient reduced budget keeps unused points available")
    check(p.max_hp() == 390 and p.max_mp() == 93,
        "under-budget allocation retains STR/INT HP/MP contributions")
    p.level = 5
    check([p.points_str, p.points_agi, p.points_wis, p.points_int] == [2, 3, 1, 2],
        "reapplying the same level leaves allocations unchanged")

func test_nested_base_caps_preserve_other_allocations() -> void:
    var p = Profile.new()
    p.archetype = 1
    p.base_stats = Profile.BASES[1].duplicate()
    p.level = 10
    p.points_str = 6
    p.points_agi = 6
    p.points_wis = 6
    p.points_int = 9
    p.base_stats.base_str = 43
    check([p.points_str, p.points_agi, p.points_wis, p.points_int] == [2, 6, 6, 9],
        "a nested STR cap edit returns only excess STR points")
    check(p.primary_stats()["STR"] == 45 and p.points_unspent() == 4 and p.valid_allocation(),
        "nested STR edit enforces the hard cap and returns points to the budget")
    p.base_stats.base_int = 43
    check([p.points_str, p.points_agi, p.points_wis, p.points_int] == [2, 6, 6, 2],
        "a nested INT cap edit preserves unrelated allocations")
    check(p.primary_stats()["INT"] == 45 and p.points_unspent() == 11 and p.valid_allocation(),
        "nested INT edit enforces the hard cap and returns points to the budget")
    check(p.max_hp() == 765 and p.max_mp() == 298,
        "capped base edits preserve HP/MP formulas")
    p.level = 5
    check([p.points_str, p.points_agi, p.points_wis, p.points_int] == [2, 6, 4, 0],
        "level decrease after cap edits still prioritizes STR > AGI > WIS > INT")
    check(p.points_unspent() == 0 and p.valid_allocation(),
        "level decrease after cap edits uses the new budget")
    check(p.max_hp() == 740 and p.max_mp() == 278,
        "level decrease after cap edits recalculates HP/MP")

func test_replaced_base_caps_before_level_decrease() -> void:
    var scenarios: Array = [
        {"base_str": 40, "points": [5, 7, 0, 0], "unspent": 0},
        {"base_str": 45, "points": [0, 9, 0, 0], "unspent": 3},
    ]
    for scenario in scenarios:
        var p = Profile.new()
        p.archetype = 1
        p.level = 10
        p.points_str = 18
        p.points_agi = 9
        var replacement = Profile.BASES[1].duplicate()
        replacement.base_str = scenario["base_str"]
        p.base_stats = replacement
        p.level = 5
        var label: String = "replaced base STR%d" % replacement.base_str
        check([p.points_str, p.points_agi, p.points_wis, p.points_int] == scenario["points"],
            label + " caps STR before assigning the reduced budget")
        check(p.points_unspent() == scenario["unspent"] and p.valid_allocation(),
            label + " preserves AGI points that fit the reduced budget")
        check(p.max_hp() == 740 and p.max_mp() == 83,
            label + " retains capped STR and HP/MP formulas")

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
