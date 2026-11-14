extends SceneTree
## Commander preparation math and ownership, independent of UI and disk files.
const Build = preload("res://scripts/commander_build.gd")
const Setup = preload("res://scripts/battle_setup.gd")
const Rules = preload("res://scripts/combat_rules.gd")
const MALE = preload("res://data/demo_male_lv25.tres")
const FEMALE = preload("res://data/demo_female_lv25.tres")
const FALCON = preload("res://data/monsters/falcon_unit_v14.tres")
const ITEM = preload("res://data/equipment/fire_sword.tres")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    test_defaults_and_materialization()
    test_validation()
    test_resize_and_limits()
    test_setup_ownership()
    test_purity()
    if failures == 0:
        print("SULEYN commander build v1.12: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN commander build v1.12: %d / %d checks FAILED." % [failures, checks])
        quit(1)


func check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED commander build v1.12: " + label)


func zero_options(level: int = 25, armor: int = 0) -> Dictionary:
    return {"level": level, "armor": armor, "STR": 0, "AGI": 0, "WIS": 0, "INT": 0}


func snapshot(stats) -> Dictionary:
    var profile = stats.commander
    return {"level": profile.level, "armor": profile.armor_type,
        "points": Build.defaults(stats), "attributes": profile.primary_stats(),
        "hp": profile.max_hp(), "mp": profile.max_mp(),
        "matter": profile.resolved_matter(), "equipment": profile.matter_equipment.duplicate(),
        "attack": stats.attack, "defense": stats.defense, "move": stats.movement}


func test_defaults_and_materialization() -> void:
    for original in [MALE, FEMALE]:
        var before: Dictionary = snapshot(original)
        var defaults: Dictionary = Build.defaults(original)
        check(defaults.size() == 6 and Build.validate(original, defaults).ok, "catalog commander has a valid complete descriptor")
        var private_stats = Build.materialize(original, defaults)
        check(private_stats != original and private_stats.commander != original.commander, "materialized unit and commander are private Resources")
        check(snapshot(private_stats) == before, "default materialization exactly preserves original numeric results")
        check(private_stats.commander.base_stats == original.commander.base_stats, "base resource is shared read-only")
        check(private_stats.commander.critical_passive == original.commander.critical_passive, "critical passive remains unchanged")
        check(private_stats.melee_skill == original.melee_skill and private_stats.special_skill == original.special_skill, "existing physical ability kit remains unchanged")
        check(private_stats.magic_spell == original.magic_spell, "existing spell and book remain unchanged")
        var preview: Dictionary = Build.preview(original, defaults)
        var attributes: Dictionary = original.commander.primary_stats()
        check(preview.hp == before.hp and preview.mp == before.mp and preview.stats == attributes, "preview HP MP and attributes use commander methods")
        check(preview.unspent == original.commander.points_unspent(), "preview reports unspent budget")
        check(is_equal_approx(preview.evasion, Rules.final_evasion(float(attributes.AGI) * 0.5 + original.commander.armor_evasion_bonus())), "preview evasion uses existing armor and universal bounds")
        check(is_equal_approx(preview.crit, clampf(float(attributes.AGI) * 0.5, 0.0, 90.0)), "preview critical chance matches current AGI rule")
        check(preview.physical_bonus == minf(90.0, float(attributes.STR) * 2.0) and preview.magic_bonus == minf(90.0, float(attributes.INT) * 2.0), "preview damage bonuses use current two-percent rule")
        for damage_type in [Rules.PIERCING, Rules.SLASHING, Rules.BLUNT]:
            check(is_equal_approx(preview.pdef_by_type[damage_type], original.commander.physical_defense_pct(damage_type)), "preview preserves weapon-specific armor defense")
        check(is_equal_approx(preview.mdef, original.commander.magic_defense_pct()), "preview magic defense uses current profile math")
        private_stats.commander.points_str = 0
        private_stats.attack = 999
        private_stats.commander.matter_equipment.append(ITEM)
        check(snapshot(original) == before, "editing materialized values and equipment array never changes catalog")
    check(is_equal_approx(Build.materialize(FEMALE, Build.defaults(FEMALE)).commander.critical_multiplier(), 2.0), "female physical critical multiplier remains two")
    check(is_equal_approx(Build.materialize(MALE, Build.defaults(MALE)).commander.critical_multiplier(), 1.5), "male physical critical multiplier remains one and a half")
    check(Build.defaults(FALCON).is_empty() and Build.materialize(FALCON, zero_options()) == null, "monster has no editable commander descriptor")
    check(Build.preview(null, {}).is_empty() and Build.defaults(null).is_empty(), "missing commander fails safely")


func test_validation() -> void:
    for invalid in [null, false, true, "data", [], 12]:
        var validation: Dictionary = Build.validate(MALE, invalid)
        check(not validation.ok and not validation.reason.is_empty(), "non-dictionary descriptor rejected with explanation")
    for key in Build.KEYS:
        var missing: Dictionary = Build.defaults(MALE)
        missing.erase(key)
        check(not Build.validate(MALE, missing).ok, "missing descriptor field rejected: " + key)
    var extra: Dictionary = Build.defaults(MALE)
    extra["resource"] = "res://data/demo_male_lv25.tres"
    check(not Build.validate(MALE, extra).ok, "unknown field cannot carry a resource override")
    for key in Build.KEYS:
        for invalid in [false, "2", -1, 0.5, NAN, INF]:
            var altered: Dictionary = Build.defaults(MALE)
            altered[key] = invalid
            check(not Build.validate(MALE, altered).ok, "invalid type/range rejected: " + key)
    for invalid_level in [0, 1000]:
        var altered: Dictionary = zero_options(invalid_level)
        check(not Build.validate(MALE, altered).ok, "level range follows current commander 1..999")
    for invalid_armor in [-1, 4]:
        check(not Build.validate(MALE, zero_options(25, invalid_armor)).ok, "armor must be an existing enum entry")
    var budget: Dictionary = zero_options(2)
    budget.AGI = 4
    check(not Build.validate(MALE, budget).ok, "overspending level budget is rejected before setters")
    for attribute in ["STR", "INT"]:
        var capped: Dictionary = zero_options(999)
        capped[attribute] = 46 - int(MALE.commander.base_record()[attribute.to_lower()])
        check(not Build.validate(MALE, capped).ok, "base plus allocation must not exceed45: " + attribute)
    var excessive: Dictionary = zero_options(999)
    excessive.AGI = 2995
    check(not Build.validate(MALE, excessive).ok, "raw allocation is bounded before construction")
    var floats: Dictionary = zero_options(2)
    floats.level = 2.0
    floats.armor = 1.0
    floats.AGI = 3.0
    check(Build.validate(MALE, floats).ok and Build.materialize(MALE, floats).commander.points_agi == 3, "integral JSON floats are accepted without masking invalid fractions")
    check(not Build.validate(FALCON, zero_options()).ok and not Build.validate({}, zero_options()).ok, "non-commander targets are rejected")


func test_resize_and_limits() -> void:
    var defaults: Dictionary = Build.defaults(MALE)
    var before: Dictionary = defaults.duplicate(true)
    var reduced: Dictionary = Build.resize(MALE, defaults, 10)
    check(Build.validate(MALE, reduced).ok and reduced.level == 10, "level reduction returns a valid descriptor")
    check(reduced.STR == 27 and reduced.AGI == 0 and reduced.WIS == 0 and reduced.INT == 0, "level reduction keeps existing STR AGI WIS INT priority")
    check(defaults == before, "resizing does not mutate input options")
    var first: Dictionary = Build.resize(MALE, defaults, 1)
    check(first.STR == 0 and first.AGI == 0 and first.WIS == 0 and first.INT == 0, "level one frees all earned allocations")
    var increased: Dictionary = Build.resize(MALE, defaults, 999)
    check(increased.STR == defaults.STR and increased.AGI == defaults.AGI and increased.WIS == defaults.WIS and increased.INT == defaults.INT, "raising level never invents an allocation")
    check(Build.preview(MALE, increased).unspent == 2994 - MALE.commander.points_spent(), "remaining high-level budget is visible")
    check(Build.resize(MALE, defaults, 1000).is_empty() and Build.resize(MALE, {}, 10).is_empty(), "invalid resize input is not silently repaired")
    for armor in range(4):
        var options: Dictionary = zero_options(25, armor)
        options.WIS = 20
        var stats = Build.materialize(MALE, options)
        check(stats.commander.armor_type == armor, "existing armor choice applied")
        check(stats.commander.max_hp() == MALE.commander.base_record().hp + 24 * 5 + stats.commander.primary_stats().STR * 10, "HP retains existing level and STR formula")
        check(stats.commander.max_mp() == MALE.commander.base_record().mp + 24 * 2 + stats.commander.primary_stats().INT * 5, "MP retains existing level and INT formula")
        check(stats.commander.resolved_matter() == MALE.commander.resolved_matter() and stats.magic_spell.magic_book == MALE.magic_spell.magic_book, "armor and allocation do not rewrite physical or spell matter")
    var agility: Dictionary = zero_options(999)
    agility.AGI = 2994
    var preview: Dictionary = Build.preview(MALE, agility)
    check(preview.evasion == 90.0 and preview.crit == 90.0, "high AGI still respects current percentage caps")
    var wisdom: Dictionary = zero_options(999)
    wisdom.WIS = 2994
    check(Build.preview(MALE, wisdom).mdef == 90.0, "high WIS still respects current defense cap")


func test_setup_ownership() -> void:
    var setup = Setup.new()
    check(setup.profile_stats("ally_1") == MALE and setup.profile_stats("ally_2") == FEMALE, "unmodified setup preserves catalog identity")
    var options: Dictionary = zero_options(10, 2)
    options.STR = 10
    options.WIS = 7
    check(setup.set_commander_options("ally_1", options), "valid per-slot commander options accepted")
    options.STR = 0
    check(setup.current_commander_options("ally_1").STR == 10, "setter stores an independent descriptor")
    var returned: Dictionary = setup.current_commander_options("ally_1")
    returned.WIS = 0
    check(setup.current_commander_options("ally_1").WIS == 7, "getter returns an independent descriptor")
    var actor = setup.profile_stats("ally_1")
    var other = setup.profile_stats("ally_1")
    check(actor != MALE and actor != other and actor.commander != other.commander, "each materialization is private")
    check(actor.commander.level == 10 and actor.commander.armor_type == 2 and actor.commander.points_str == 10, "private commander uses stored choices")
    check(setup.profile_stats("ally_2") == FEMALE and setup.is_valid(), "one configured slot does not change the others")
    var copied = setup.copy()
    copied.commander_options.ally_1.STR = 1
    check(setup.commander_options.ally_1.STR == 10, "copy deeply isolates commander options")
    setup.set_enabled("ally_1", false)
    check(setup.current_commander_options("ally_1").STR == 10, "disabled slot remembers current draft build")
    setup.set_profile("ally_1", "male")
    check(setup.is_enabled("ally_1") and setup.current_commander_options("ally_1").STR == 10, "same profile re-enables without erasing build")
    setup.reset_positions()
    check(setup.current_commander_options("ally_1").STR == 10, "position reset preserves commander settings")
    var before: Dictionary = setup.commander_options.duplicate(true)
    check(not setup.set_commander_options("ally_1", zero_options(0)) and setup.commander_options == before, "invalid setter leaves prior configuration unchanged")
    check(not setup.set_commander_options("ally_3", zero_options()) and not setup.set_commander_options("unknown", zero_options()), "monster and unknown slot cannot receive commander settings")
    setup.set_profile("ally_1", "female")
    check(not setup.commander_options.has("ally_1") and setup.profile_stats("ally_1") == FEMALE, "changing profile clears incompatible custom settings")
    setup.set_commander_options("ally_1", zero_options(12))
    setup.reset_commander_options("ally_1")
    check(setup.profile_stats("ally_1") == FEMALE, "explicit build reset restores catalog identity")
    setup.set_commander_options("ally_1", zero_options(12))
    setup.reset_defaults()
    check(setup.commander_options.is_empty() and setup.profile_stats("ally_1") == MALE, "default example resets all build settings")
    setup.commander_options.unknown = zero_options()
    check(not setup.is_valid(), "unknown override slot is rejected")
    setup.commander_options.clear()
    setup.commander_options.ally_3 = zero_options()
    setup.set_enabled("ally_3", false)
    check(not setup.is_valid(), "invalid monster override remains invalid even while inactive")


func test_purity() -> void:
    var male_before: Dictionary = snapshot(MALE)
    var female_before: Dictionary = snapshot(FEMALE)
    var setup = Setup.new()
    setup.set_commander_options("ally_1", zero_options(50, 1))
    seed(91572)
    var expected: float = randf()
    seed(91572)
    for iteration in range(8):
        Build.defaults(MALE)
        Build.preview(MALE, zero_options(25, iteration % 4))
        Build.materialize(FEMALE, Build.defaults(FEMALE))
        Build.resize(MALE, Build.defaults(MALE), 10 + iteration)
        setup.profile_stats("ally_1")
        setup.copy()
    check(randf() == expected, "building, previewing and copying never consume battle RNG")
    check(snapshot(MALE) == male_before and snapshot(FEMALE) == female_before, "all catalog resources remain unchanged after repeated building")
