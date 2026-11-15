extends SceneTree
## Independent growth examples and exhaustive level-domain invariants.
const Growth = preload("res://scripts/commander_growth.gd")
const ARCHETYPES: Array[int] = [0, 1, 4, 5]
var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    test_approved_ratios()
    test_known_levels()
    test_all_levels()
    test_invalid_and_purity()
    if failures == 0:
        print("SULEYN commander growth v1.15: %d checks passed." % checks)
    quit(0 if failures == 0 else 1)


func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED commander growth v1.15: " + label)


func test_approved_ratios() -> void:
    check(Growth.weights(0) == {"STR": 50, "AGI": 30, "WIS": 10, "INT": 10},
        "male warrior uses the approved 50/30/10/10 percentages")
    check(Growth.weights(1) == {"STR": 30, "AGI": 40, "WIS": 20, "INT": 10},
        "female warrior favors AGI, followed by STR and WIS")
    check(Growth.weights(4) == {"STR": 10, "AGI": 10, "WIS": 30, "INT": 50},
        "male mage DEX is existing AGI and INT receives half the points")
    check(Growth.weights(5) == {"STR": 10, "AGI": 10, "WIS": 50, "INT": 30},
        "female mage DEX is existing AGI and WIS receives half the points")
    for archetype in ARCHETYPES:
        var ratios: Dictionary = Growth.weights(archetype)
        var sum: int = 0
        for key in ratios:
            sum += int(ratios[key])
        check(Growth.supports(archetype) and ratios.keys() == ["STR", "AGI", "WIS", "INT"] and sum == 100,
            "supported ratio has exactly the four existing attributes and totals 100%")


func test_known_levels() -> void:
    var cases: Array[Dictionary] = [
        {"archetype": 0, "level": 2, "expected": {"STR": 2, "AGI": 1, "WIS": 0, "INT": 0}},
        {"archetype": 1, "level": 2, "expected": {"STR": 1, "AGI": 1, "WIS": 1, "INT": 0}},
        {"archetype": 4, "level": 2, "expected": {"STR": 0, "AGI": 0, "WIS": 1, "INT": 2}},
        {"archetype": 5, "level": 2, "expected": {"STR": 0, "AGI": 0, "WIS": 2, "INT": 1}},
        {"archetype": 0, "level": 11, "expected": {"STR": 15, "AGI": 9, "WIS": 3, "INT": 3}},
        {"archetype": 1, "level": 11, "expected": {"STR": 9, "AGI": 12, "WIS": 6, "INT": 3}},
        {"archetype": 4, "level": 11, "expected": {"STR": 3, "AGI": 3, "WIS": 9, "INT": 15}},
        {"archetype": 5, "level": 11, "expected": {"STR": 3, "AGI": 3, "WIS": 15, "INT": 9}},
        {"archetype": 0, "level": 25, "expected": {"STR": 36, "AGI": 22, "WIS": 7, "INT": 7}},
        {"archetype": 1, "level": 25, "expected": {"STR": 22, "AGI": 29, "WIS": 14, "INT": 7}},
        {"archetype": 4, "level": 25, "expected": {"STR": 7, "AGI": 7, "WIS": 22, "INT": 36}},
        {"archetype": 5, "level": 25, "expected": {"STR": 7, "AGI": 7, "WIS": 36, "INT": 22}},
        {"archetype": 0, "level": 999, "expected": {"STR": 1497, "AGI": 898, "WIS": 300, "INT": 299}},
        {"archetype": 1, "level": 999, "expected": {"STR": 898, "AGI": 1198, "WIS": 599, "INT": 299}},
        {"archetype": 4, "level": 999, "expected": {"STR": 300, "AGI": 299, "WIS": 898, "INT": 1497}},
        {"archetype": 5, "level": 999, "expected": {"STR": 300, "AGI": 299, "WIS": 1497, "INT": 898}},
    ]
    for row in cases:
        check(Growth.points(row.archetype, row.level) == row.expected,
            "approved rounding example, archetype %d / level %d" % [row.archetype, row.level])
    for archetype in ARCHETYPES:
        check(Growth.points(archetype, 1) == {"STR": 0, "AGI": 0, "WIS": 0, "INT": 0},
            "first level has no earned points and does not invent base attributes")


func test_all_levels() -> void:
    for archetype in ARCHETYPES:
        var ratios: Dictionary = Growth.weights(archetype)
        var previous: Dictionary = Growth.points(archetype, 1)
        var valid_shape: bool = true
        var exact_budget: bool = true
        var monotonic: bool = true
        var fair_share: bool = true
        var exact_cycles: bool = true
        for level in range(1, 1000):
            var budget: int = 3 * (level - 1)
            var result: Dictionary = Growth.points(archetype, level)
            valid_shape = valid_shape and result.keys() == ["STR", "AGI", "WIS", "INT"]
            var sum: int = 0
            for key in ["STR", "AGI", "WIS", "INT"]:
                var amount: Variant = result.get(key, -1)
                valid_shape = valid_shape and typeof(amount) == TYPE_INT and amount >= 0
                sum += int(amount)
                monotonic = monotonic and int(amount) >= int(previous[key])
                # No floating arithmetic: deviation is strictly below one point.
                fair_share = fair_share and absi(int(amount) * 100 - budget * int(ratios[key])) < 100
                if budget % 10 == 0:
                    exact_cycles = exact_cycles and int(amount) * 100 == budget * int(ratios[key])
            exact_budget = exact_budget and sum == budget
            previous = result
        check(valid_shape, "all 999 levels contain four nonnegative integer allocations")
        check(exact_budget, "all 999 levels allocate exactly three points per gained level")
        check(monotonic, "raising level never removes an already earned attribute point")
        check(fair_share, "all 999 levels stay within one point of approved percentage targets")
        check(exact_cycles, "complete ten-point cycles match all percentages exactly")


func test_invalid_and_purity() -> void:
    for archetype in [-1, 2, 3, 6, 99]:
        check(not Growth.supports(archetype) and Growth.weights(archetype).is_empty()
            and Growth.points(archetype, 25).is_empty(), "unapproved archetype has no invented automatic allocation")
    for level in [-100, 0, 1000, 2147483647]:
        check(Growth.points(0, level).is_empty(), "unsupported level is rejected before budget arithmetic")
    var ratios: Dictionary = Growth.weights(0)
    var second_ratios: Dictionary = Growth.weights(0)
    ratios.STR = 999
    check(second_ratios.STR == 50 and Growth.weights(0).STR == 50, "returned percentage dictionaries are independent")
    var first: Dictionary = Growth.points(0, 25)
    var second: Dictionary = Growth.points(0, 25)
    first.STR = 999
    check(second.STR == 36 and Growth.points(0, 25).STR == 36, "returned allocation dictionaries are independent")
    seed(115015)
    var expected_random: int = randi()
    seed(115015)
    for archetype in ARCHETYPES:
        Growth.supports(archetype)
        Growth.weights(archetype)
        Growth.points(archetype, 1)
        Growth.points(archetype, 25)
        Growth.points(archetype, 999)
    check(randi() == expected_random, "growth and rounding never consume battle RNG")
