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


func auto_options(level: int = 25, armor: int = 0, base_stats = MALE) -> Dictionary:
    var options: Dictionary = Build.defaults(base_stats)
    if level >= 1 and level <= 999:
        options = Build.resize(base_stats, options, level)
    else:
        options.level = level
    options.armor = armor
    return options


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
        check(defaults.size() == Build.KEYS.size() and Build.validate(original, defaults).ok, "catalog commander has a valid complete descriptor")
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
        check(preview.physical_bonus == minf(90.0, float(attributes.STR)) and preview.magic_bonus == minf(90.0, float(attributes.INT)), "preview damage bonuses use the approved one-percent rule")
        for damage_type in [Rules.PIERCING, Rules.SLASHING, Rules.BLUNT]:
            check(is_equal_approx(preview.pdef_by_type[damage_type], original.commander.physical_defense_pct(damage_type)), "preview preserves weapon-specific armor defense")
        check(is_equal_approx(preview.mdef, original.commander.magic_defense_pct()), "preview magic defense uses current profile math")
        private_stats.commander.level = 10
        private_stats.attack = 999
        private_stats.commander.matter_equipment.append(ITEM)
        check(snapshot(original) == before, "editing materialized values and equipment array never changes catalog")
    check(is_equal_approx(Build.materialize(FEMALE, Build.defaults(FEMALE)).commander.critical_multiplier(), 2.0), "female physical critical multiplier remains two")
    check(is_equal_approx(Build.materialize(MALE, Build.defaults(MALE)).commander.critical_multiplier(), 1.5), "male physical critical multiplier remains one and a half")
    check(Build.defaults(FALCON).is_empty() and Build.materialize(FALCON, auto_options()) == null, "monster has no editable commander descriptor")
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
    for key in Build.LEGACY_KEYS:
        for invalid in [false, "2", -1, 0.5, NAN, INF]:
            var altered: Dictionary = Build.defaults(MALE)
            altered[key] = invalid
            check(not Build.validate(MALE, altered).ok, "invalid type/range rejected: " + key)
    for invalid_level in [0, 1000]:
        var altered: Dictionary = auto_options(invalid_level)
        check(not Build.validate(MALE, altered).ok, "level range follows current commander 1..999")
    for invalid_armor in [-1, 4]:
        check(not Build.validate(MALE, auto_options(25, invalid_armor)).ok, "armor must be an existing enum entry")
    var budget: Dictionary = auto_options(2)
    budget.AGI = 4
    check(not Build.validate(MALE, budget).ok, "overspending level budget is rejected before setters")
    var high: Dictionary = auto_options(999)
    var high_stats = Build.materialize(MALE, high)
    for attribute in ["STR", "INT"]:
        check(Build.validate(MALE, high).ok and high_stats.commander.primary_stats()[attribute] > 45,
            "valid automatic attributes may exceed the removed 45-point limit: " + attribute)
    var altered_distribution: Dictionary = auto_options(25)
    altered_distribution.STR -= 1
    altered_distribution.AGI += 1
    check(not Build.validate(MALE, altered_distribution).ok,
        "manually moving points is rejected even when the total budget still matches")
    var excessive: Dictionary = auto_options(999)
    excessive.AGI = 2995
    check(not Build.validate(MALE, excessive).ok, "raw allocation is bounded before construction")
    var floats: Dictionary = auto_options(2, 1)
    for key in Build.LEGACY_KEYS:
        floats[key] = float(floats[key])
    check(Build.validate(MALE, floats).ok and Build.materialize(MALE, floats).commander.points_str == 2
        and Build.materialize(MALE, floats).commander.points_agi == 1,
        "integral JSON floats matching automatic growth are accepted without masking fractions")
    check(not Build.validate(FALCON, auto_options()).ok and not Build.validate({}, auto_options()).ok, "non-commander targets are rejected")


func test_resize_and_limits() -> void:
    var defaults: Dictionary = Build.defaults(MALE)
    var before: Dictionary = defaults.duplicate(true)
    var reduced: Dictionary = Build.resize(MALE, defaults, 10)
    check(Build.validate(MALE, reduced).ok and reduced.level == 10, "level reduction returns a valid descriptor")
    check(reduced.STR == 13 and reduced.AGI == 8 and reduced.WIS == 3 and reduced.INT == 3, "level reduction recalculates the approved automatic ratio")
    check(defaults == before, "resizing does not mutate input options")
    var first: Dictionary = Build.resize(MALE, defaults, 1)
    check(first.STR == 0 and first.AGI == 0 and first.WIS == 0 and first.INT == 0, "level one frees all earned allocations")
    var increased: Dictionary = Build.resize(MALE, defaults, 999)
    check(increased.STR == 1497 and increased.AGI == 898 and increased.WIS == 300 and increased.INT == 299, "raising level automatically assigns the complete new budget without a 45-point cap")
    check(Build.preview(MALE, increased).unspent == 0, "automatic growth leaves no earned points unallocated")
    check(Build.resize(MALE, defaults, 1000).is_empty() and Build.resize(MALE, {}, 10).is_empty(), "invalid resize input is not silently repaired")
    for armor in range(4):
        var options: Dictionary = auto_options(25, armor)
        var stats = Build.materialize(MALE, options)
        check(stats.commander.armor_type == armor, "existing armor choice applied")
        check(stats.commander.max_hp() == MALE.commander.base_record().hp + 24 * 5 + stats.commander.primary_stats().STR * 10, "HP retains existing level and STR formula")
        check(stats.commander.max_mp() == MALE.commander.base_record().mp + 24 * 2 + stats.commander.primary_stats().INT * 5, "MP retains existing level and INT formula")
        check(stats.commander.resolved_matter() == MALE.commander.resolved_matter() and stats.magic_spell.magic_book == MALE.magic_spell.magic_book, "armor and allocation do not rewrite physical or spell matter")
    var preview: Dictionary = Build.preview(MALE, auto_options(999))
    check(preview.evasion == 90.0 and preview.crit == 90.0, "high automatic AGI respects percentage caps")
    check(preview.mdef == 90.0, "high automatic WIS respects the existing defense cap")
    check(preview.physical_bonus == 90.0 and preview.magic_bonus == 90.0,
        "unbounded STR and INT still obey the separate 90-percent damage bonus cap")
    var male_preview: Dictionary = Build.preview(MALE, Build.defaults(MALE))
    var female_preview: Dictionary = Build.preview(FEMALE, Build.defaults(FEMALE))
    check(male_preview.stats == {"STR": 46, "AGI": 30, "WIS": 11, "INT": 13}
        and male_preview.hp == 880 and male_preview.mp == 163
        and male_preview.physical_bonus == 46.0 and male_preview.magic_bonus == 13.0,
        "male level25 uses independent approved growth, unchanged HP/MP formula and one-percent bonuses")
    check(female_preview.stats == {"STR": 30, "AGI": 39, "WIS": 20, "INT": 11}
        and female_preview.hp == 690 and female_preview.mp == 158
        and female_preview.physical_bonus == 30.0 and female_preview.magic_bonus == 11.0,
        "female level25 uses its own approved growth and unchanged HP/MP formula")
    for archetype in [4, 5]:
        var mage: SuleynUnitStats = MALE.duplicate(false) as SuleynUnitStats
        mage.commander = MALE.commander.duplicate(false) as SuleynCommanderProfile
        mage.commander.archetype = archetype
        var mage_preview: Dictionary = Build.preview(mage, Build.defaults(mage))
        check(Build.validate(mage, Build.defaults(mage)).ok and mage_preview.unspent == 0,
            "approved mage growth is supported by the builder without inventing a playable kit")
        check(mage_preview.stats == ({"STR": 12, "AGI": 12, "WIS": 30, "INT": 46} if archetype == 4
            else {"STR": 11, "AGI": 13, "WIS": 46, "INT": 30}),
            "each mage adds automatic growth to its own base, interpreting DEX as AGI")


func test_setup_ownership() -> void:
    var setup = Setup.new()
    check(setup.profile_stats("ally_1") == MALE and setup.profile_stats("ally_2") == FEMALE, "unmodified setup preserves catalog identity")
    var options: Dictionary = auto_options(10, 2)
    check(setup.set_commander_options("ally_1", options), "valid per-slot commander options accepted")
    options.STR = 0
    check(setup.current_commander_options("ally_1").STR == 13, "setter stores an independent descriptor")
    var returned: Dictionary = setup.current_commander_options("ally_1")
    returned.WIS = 0
    check(setup.current_commander_options("ally_1").WIS == 3, "getter returns an independent descriptor")
    var actor = setup.profile_stats("ally_1")
    var other = setup.profile_stats("ally_1")
    check(actor != MALE and actor != other and actor.commander != other.commander, "each materialization is private")
    check(actor.commander.level == 10 and actor.commander.armor_type == 2 and actor.commander.points_str == 13, "private commander uses stored choices")
    check(setup.profile_stats("ally_2") == FEMALE and setup.is_valid(), "one configured slot does not change the others")
    var copied = setup.copy()
    copied.commander_options.ally_1.STR = 1
    check(setup.commander_options.ally_1.STR == 13, "copy deeply isolates commander options")
    setup.set_enabled("ally_1", false)
    check(setup.current_commander_options("ally_1").STR == 13, "disabled slot remembers current draft build")
    setup.set_profile("ally_1", "male")
    check(setup.is_enabled("ally_1") and setup.current_commander_options("ally_1").STR == 13, "same profile re-enables without erasing build")
    setup.reset_positions()
    check(setup.current_commander_options("ally_1").STR == 13, "position reset preserves commander settings")
    var before: Dictionary = setup.commander_options.duplicate(true)
    check(not setup.set_commander_options("ally_1", auto_options(0)) and setup.commander_options == before, "invalid setter leaves prior configuration unchanged")
    check(not setup.set_commander_options("ally_3", auto_options()) and not setup.set_commander_options("unknown", auto_options()), "monster and unknown slot cannot receive commander settings")
    setup.set_profile("ally_1", "female")
    check(not setup.commander_options.has("ally_1") and setup.profile_stats("ally_1") == FEMALE, "changing profile clears incompatible custom settings")
    setup.set_commander_options("ally_1", auto_options(12, 0, FEMALE))
    setup.reset_commander_options("ally_1")
    check(setup.profile_stats("ally_1") == FEMALE, "explicit build reset restores catalog identity")
    setup.set_commander_options("ally_1", auto_options(12, 0, FEMALE))
    setup.reset_defaults()
    check(setup.commander_options.is_empty() and setup.profile_stats("ally_1") == MALE, "default example resets all build settings")
    setup.commander_options.unknown = auto_options()
    check(not setup.is_valid(), "unknown override slot is rejected")
    setup.commander_options.clear()
    setup.commander_options.ally_3 = auto_options()
    setup.set_enabled("ally_3", false)
    check(not setup.is_valid(), "invalid monster override remains invalid even while inactive")


func test_purity() -> void:
    var male_before: Dictionary = snapshot(MALE)
    var female_before: Dictionary = snapshot(FEMALE)
    var setup = Setup.new()
    setup.set_commander_options("ally_1", auto_options(50, 1))
    seed(91572)
    var expected: float = randf()
    seed(91572)
    for iteration in range(8):
        Build.defaults(MALE)
        Build.preview(MALE, auto_options(25, iteration % 4))
        Build.materialize(FEMALE, Build.defaults(FEMALE))
        Build.resize(MALE, Build.defaults(MALE), 10 + iteration)
        setup.profile_stats("ally_1")
        setup.copy()
    check(randf() == expected, "building, previewing and copying never consume battle RNG")
    check(snapshot(MALE) == male_before and snapshot(FEMALE) == female_before, "all catalog resources remain unchanged after repeated building")
