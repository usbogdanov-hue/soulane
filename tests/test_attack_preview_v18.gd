extends SceneTree
## Preview must agree with actual combat and remain safe to call every frame.
const Preview = preload("res://scripts/attack_preview.gd")
const Combat = preload("res://scripts/battle_combat.gd")
const Board = preload("res://scripts/battle_board.gd")
const Unit = preload("res://scripts/battle_unit.gd")
const Skill = preload("res://scripts/attack_skill.gd")
const Matter = preload("res://scripts/matter_rules.gd")
const Rules = preload("res://scripts/combat_rules.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    test_invalid_inputs()
    test_ranges_and_costs()
    test_combat_outcomes()
    test_expected_damage()
    test_purity()
    if failures == 0:
        print("SULEYN attack preview v1.8: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN attack preview v1.8: %d/%d checks FAILED." % [failures, checks])
        quit(1)


func check(condition: bool, label: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAILED preview: " + label)


func near(actual: float, expected: float, label: String) -> void:
    check(absf(actual - expected) < 0.00001, label)


func fixture(actor_values: Dictionary = {}, target_values: Dictionary = {}, target_cell: Vector2i = Vector2i(2, 2)) -> Dictionary:
    var actor = Unit.new("actor", "blue", 1000, 100)
    var target = Unit.new("target", "red", 1000, 100)
    actor.max_mp = 100
    actor.mp = 100
    for property in actor_values:
        actor.set(property, actor_values[property])
    for property in target_values:
        target.set(property, target_values[property])
    var board = Board.new(8, 6)
    board.add_unit("actor", Vector2i(1, 2))
    board.add_unit("target", target_cell)
    return {"board": board, "actor": actor, "target": target,
        "units": {"actor": actor, "target": target}}


func preview(f: Dictionary, mode: String = "basic") -> Dictionary:
    return Preview.evaluate(f.board, f.units, "actor", "target", mode)


func special(minimum: int = 1, maximum: int = 1):
    var skill = Skill.new()
    skill.display_name = "Тестовый удар"
    skill.skill_power = 140
    skill.mana_cost = 20
    skill.damage_type = Rules.PIERCING
    skill.min_range = minimum
    skill.max_range = maximum
    skill.concussion_chance_pct = 33.0
    skill.concussion_skipped_turns = 2
    return skill


func reject(result: Dictionary, fragment: String, label: String) -> void:
    check(not result.available and fragment.to_lower() in result.reason.to_lower(), label)


func test_invalid_inputs() -> void:
    var f = fixture()
    var keys: Array = preview(f).keys()
    var absent: Dictionary = Preview.evaluate(f.board, f.units, "missing", "target")
    reject(absent, "выберите", "missing attacker explains selection")
    check(absent.keys() == keys, "invalid projection retains full schema")
    reject(Preview.evaluate(f.board, f.units, "actor", "missing"), "противника", "missing target")
    reject(Preview.evaluate(null, f.units, "actor", "target"), "поле", "null board")
    reject(Preview.evaluate(f.board, {"actor": null, "target": f.target}, "actor", "target"), "выберите", "null actor")
    reject(preview(f, "unknown"), "удар", "invalid attack mode")
    reject(preview(f, "special"), "нет дополнительного", "missing special")
    reject(preview(f, "magic"), "нет атакующего", "missing spell")
    f.actor.hp = 0
    reject(preview(f), "поверженный", "dead actor")
    f.actor.hp = 1000
    f.target.hp = 0
    reject(preview(f), "повержен", "dead target")
    f.target.hp = 1000
    f.target.side = "blue"
    reject(preview(f), "своих", "friendly target")
    reject(Preview.evaluate(f.board, f.units, "actor", "actor"), "своих", "self targeting")
    f.target.side = "red"
    f.board.remove_unit("target")
    reject(preview(f), "поле", "off-board target")
    f.board.add_unit("target", Vector2i(2, 2))
    f.board.remove_unit("actor")
    reject(preview(f), "поле", "off-board actor")
    f.board.add_unit("actor", Vector2i(1, 2))
    f.actor.apply_concussion(2)
    reject(preview(f), "2", "stun explains remaining own turns")
    check(f.actor.concussion_turns_remaining == 2, "stun preview does not skip")


func test_ranges_and_costs() -> void:
    var skill = special(2, 3)
    var f = fixture({"special_skill": skill}, {}, Vector2i(3, 2))
    var p: Dictionary = preview(f, "special")
    check(p.available and p.distance == 2 and p.min_range == 2 and p.max_range == 3, "minimum special distance allowed")
    check(p.name == skill.display_name and p.cost == 20, "skill name and cost")
    check(p.concussion_chance_pct == 33.0 and p.concussion_turns == 2, "skill stun preview")
    check(f.board.move_unit("target", Vector2i(4, 2)), "move to maximum distance")
    check(preview(f, "special").available, "maximum special distance allowed")
    f.board.move_unit("target", Vector2i(5, 2))
    p = preview(f, "special")
    reject(p, "дальности", "too far reason")
    check(p.normal_damage > 0 and p.cost == 20, "range rejection retains combat math")
    f.board.move_unit("target", Vector2i(2, 2))
    reject(preview(f, "special"), "дальности", "too close reason")
    f.board.move_unit("target", Vector2i(3, 2))
    f.actor.mp = 19
    p = preview(f, "special")
    reject(p, "недостаточно MP", "unaffordable skill explains MP")
    check(p.normal_damage > 0 and p.cost == 20, "mana rejection retains combat math")
    f.actor.mp = 20
    check(preview(f, "special").available, "exact MP cost allowed")
    skill.mana_cost = -1
    reject(preview(f, "special"), "стоимость", "negative resource cost unavailable")
    skill.mana_cost = 20
    skill.min_range = 0
    skill.max_range = -2
    f.board.move_unit("target", Vector2i(2, 2))
    p = preview(f, "special")
    check(p.available and p.min_range == 1 and p.max_range == 1, "range normalization matches combat")
    f.actor.spell_power = 100
    f.actor.spell_mana_cost = 21
    reject(preview(f, "magic"), "недостаточно", "unaffordable magic")
    f.actor.mp = 21
    check(preview(f, "magic").available, "exact magic MP cost")
    f.board.move_unit("target", Vector2i(3, 2))
    reject(preview(f, "magic"), "дальности", "magic remains adjacent despite ranged special")
    reject(preview(f), "дальности", "basic remains adjacent")


func test_combat_outcomes() -> void:
    var cases: Array[Dictionary] = [
        {"actor": {}, "target": {}},
        {"actor": {"crit_chance_pct": 35.0, "critical_multiplier": 2.0}, "target": {"armor_pdef_pct": 20.0}},
        {"actor": {"physical_damage_bonus_pct": 120.0, "crit_chance_pct": 150.0}, "target": {"base_pdef_pct": 120.0, "evasion_pct": 150.0}},
        {"actor": {"matter": Matter.FIRE, "crit_chance_pct": 25.0}, "target": {"matter": Matter.FIRE, "base_pdef_pct": -30.0}},
        {"actor": {"matter": Matter.FIRE, "crit_chance_pct": 25.0}, "target": {"matter": Matter.WIND, "base_pdef_pct": 100.0}},
        {"actor": {"melee_damage_type": Rules.PIERCING, "melee_skill_power": 75, "crit_chance_pct": 25.0}, "target": {"is_monster": true, "monster_categories": Rules.FLYING, "armor_pdef_pct": 90.0}},
        {"actor": {"attack": 52, "crit_chance_pct": -20.0}, "target": {"evasion_pct": -10.0, "hp": 30}},
    ]
    for values in cases:
        for mode in ["basic", "special", "magic"]:
            var actor_values: Dictionary = values.actor.duplicate()
            actor_values.special_skill = special()
            actor_values.spell_power = 160
            actor_values.spell_mana_cost = 10
            actor_values.spell_matter = Matter.WATER
            actor_values.magic_power_pct = 90.0
            var f = fixture(actor_values, values.target)
            var p: Dictionary = preview(f, mode)
            check(p.available, "comparison fixture available: " + mode)
            var hit: Dictionary = execute(f, mode, 99.0)
            check(hit.ok and hit.damage == p.normal_damage, "normal outcome matches actual combat: " + mode)
            var crit_fixture = fixture(actor_values, values.target)
            var crit: Dictionary = execute(crit_fixture, mode, 0.0)
            var expected_critical: int = p.critical_damage if p.crit_chance_pct > 0.0 else p.normal_damage
            check(crit.ok and crit.damage == expected_critical, "critical outcome matches actual combat: " + mode)
            if mode == "magic":
                check(not hit.evaded and not hit.critical and p.hit_chance_pct == 100.0 and p.crit_chance_pct == 0.0, "magic does not evade or crit")
            else:
                var dodge_fixture = fixture(actor_values, values.target)
                var miss: Dictionary = Combat.physical_attack(dodge_fixture.board, dodge_fixture.units,
                    "actor", "target", dodge_fixture.actor.special_skill if mode == "special" else null, 0.0, 99.0)
                check(miss.evaded and miss.damage == 0, "physical miss remains possible")


func execute(f: Dictionary, mode: String, critical_roll: float) -> Dictionary:
    if mode == "magic":
        return Combat.magic_attack(f.board, f.units, "actor", "target")
    return Combat.physical_attack(f.board, f.units, "actor", "target",
        f.actor.special_skill if mode == "special" else null, 99.0, critical_roll, 99.0)


func test_expected_damage() -> void:
    var f = fixture({"crit_chance_pct": 40.0, "critical_multiplier": 2.0}, {"evasion_pct": 25.0})
    var p: Dictionary = preview(f)
    check(p.normal_damage == 100 and p.critical_damage == 200, "ordinary and critical outcomes")
    near(p.expected_damage, 105.0, "expected damage weights hit and crit")
    f.target.hp = 120
    p = preview(f)
    check(p.normal_damage == 100 and p.critical_damage == 120, "critical damage capped before expectation")
    near(p.expected_damage, 81.0, "overkill contributes no extra expected damage")
    f.target.hp = 20
    p = preview(f)
    near(p.expected_damage, 15.0, "both outcomes capped to HP")
    f.actor.spell_power = 100
    f.target.evasion_pct = 90.0
    p = preview(f, "magic")
    near(p.expected_damage, 20.0, "magic expectation independent of evasion and crit")
    f.actor.matter = Matter.FIRE
    f.target.matter = Matter.FIRE
    p = preview(f)
    check(p.matter_attack_penalty_pct == -15.0 and p.matter_defense_penalty_pp == 0.0, "same matter attack penalty")
    f.target.matter = Matter.WIND
    p = preview(f)
    check(p.matter_attack_penalty_pct == 0.0 and p.matter_defense_penalty_pp == -15.0, "advantage defense penalty")
    check(p.defense_pct == -15.0, "negative final defense retained")
    f.actor.spell_matter = Matter.NEUTRAL
    p = preview(f, "magic")
    check(p.attack_matter == Matter.NEUTRAL and p.matter_defense_penalty_pp == 0.0, "magic uses book matter, not physical matter")


func snapshot(f: Dictionary) -> Dictionary:
    var state: Dictionary = {"positions": f.board.unit_positions.duplicate(true),
        "occupied": f.board.occupied.duplicate(true), "blocked": f.board.blocked.duplicate(true)}
    for id in f.units:
        var values: Dictionary = {}
        var unit = f.units[id]
        for property in unit.get_property_list():
            var value = unit.get(property.name)
            if not value is Object:
                values[property.name] = value.duplicate(true) if value is Dictionary or value is Array else value
        state[id] = values
    return state


func test_purity() -> void:
    var skill = special()
    var f = fixture({"special_skill": skill, "spell_power": 100, "spell_mana_cost": 10,
        "crit_chance_pct": 50.0, "mana_regen_fraction": 0.35}, {"concussion_turns_remaining": 2, "concussion_total_turns": 2})
    f.board.set_blocked(Vector2i(4, 4), true)
    var before: Dictionary = snapshot(f)
    seed(984)
    var expected_first: float = randf()
    var expected_second: float = randf()
    seed(984)
    near(randf(), expected_first, "seed setup")
    for count in range(100):
        for mode in ["basic", "special", "magic"]:
            var a: Dictionary = preview(f, mode)
            var b: Dictionary = preview(f, mode)
            if count == 0:
                check(a == b, "repeated evaluation stable: " + mode)
    near(randf(), expected_second, "preview consumes no global RNG")
    check(snapshot(f) == before, "preview preserves all scalar, collection, HP, MP, stun and board state")
    check(skill.skill_power == 140 and skill.mana_cost == 20 and skill.concussion_chance_pct == 33.0
        and skill.concussion_skipped_turns == 2, "shared skill resource unchanged")
