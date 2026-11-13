extends SceneTree
## Pure deterministic AI decisions, including legal detours and existing damage rules.
const AI = preload("res://scripts/battle_ai.gd")
const Board = preload("res://scripts/battle_board.gd")
const Unit = preload("res://scripts/battle_unit.gd")
const Skill = preload("res://scripts/attack_skill.gd")
const Hex = preload("res://scripts/hex_math.gd")
const Matter = preload("res://scripts/matter_rules.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
    test_invalid_actors()
    test_modes_and_expected_damage()
    test_target_selection()
    test_ranges_and_mana()
    test_movement()
    test_obstacles_and_detours()
    test_purity()
    if failures == 0:
        print("SULEYN AI decisions v1.6: %d checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN AI decisions v1.6: %d/%d checks FAILED." % [failures, checks])
        quit(1)


func check(condition: bool, label: String) -> void:
    checks += 1
    if not condition:
        failures += 1
        printerr("FAILED AI decisions: " + label)


func fixture(width: int = 8, height: int = 6) -> Dictionary:
    var board = Board.new(width, height)
    var actor = Unit.new("red", "red", 1000, 100, 0, 3)
    var target = Unit.new("blue", "blue", 1000, 100, 0, 3)
    board.add_unit("red", Vector2i(1, 2))
    board.add_unit("blue", Vector2i(2, 2))
    return {"board": board, "actor": actor, "target": target,
        "units": {"red": actor, "blue": target}}


func choose(f: Dictionary) -> Dictionary:
    return AI.choose_action(f.board, f.units, "red")


func special(power: int = 200, cost: int = 10, minimum: int = 1, maximum: int = 1):
    var skill = Skill.new()
    skill.skill_power = power
    skill.mana_cost = cost
    skill.min_range = minimum
    skill.max_range = maximum
    return skill


func check_attack(f: Dictionary, mode: String, label: String) -> void:
    var action: Dictionary = choose(f)
    check(action.get("kind") == "attack" and action.get("target_id") == "blue"
        and action.get("mode") == mode, label)


func test_invalid_actors() -> void:
    var f = fixture()
    check(AI.choose_action(f.board, f.units, "missing") == {"kind": "pass"}, "missing actor passes")
    f.actor.hp = 0
    check(choose(f) == {"kind": "pass"}, "dead actor passes")
    f.actor.hp = 1000
    f.actor.apply_concussion(2)
    check(choose(f) == {"kind": "pass"}, "concussed actor passes without decrementing")
    check(f.actor.concussion_turns_remaining == 2, "planner preserves concussion")
    f.actor.concussion_turns_remaining = 0
    f.board.remove_unit("red")
    check(choose(f) == {"kind": "pass"}, "off-board actor passes")
    f.board.add_unit("red", Vector2i(1, 2))
    f.target.side = "red"
    check(choose(f) == {"kind": "pass"}, "only friends means no action")
    f.target.side = "blue"
    f.target.hp = 0
    check(choose(f) == {"kind": "pass"}, "only dead enemies means no action")
    f.target.hp = 1000
    f.board.remove_unit("blue")
    check(choose(f) == {"kind": "pass"}, "off-board enemy ignored")


func test_modes_and_expected_damage() -> void:
    var f = fixture()
    check_attack(f, "basic", "ordinary adjacent strike")
    f.actor.special_skill = special()
    f.actor.mp = 10
    check_attack(f, "special", "higher expected special damage chosen")
    f.actor.mp = 9
    check_attack(f, "basic", "unaffordable special ignored")
    f.actor.mp = 10
    f.actor.spell_power = 300
    f.actor.spell_mana_cost = 10
    check_attack(f, "magic", "stronger available magic chosen")
    f.actor.spell_mana_cost = 11
    check_attack(f, "special", "unaffordable magic ignored")
    f.actor.special_skill = null
    f.actor.spell_mana_cost = 10
    f.actor.spell_power = 150
    f.actor.crit_chance_pct = 90.0
    f.actor.critical_multiplier = 2.0
    check_attack(f, "basic", "expected physical crit damage affects selection")
    f.target.evasion_pct = 90.0
    check_attack(f, "magic", "magic has no evasion or critical roll")
    f.target.evasion_pct = 5.0
    f.target.base_pdef_pct = 90.0
    f.actor.spell_power = 50
    check_attack(f, "magic", "separate physical and magic defenses considered")
    f.target.base_mdef_pct = 90.0
    check_attack(f, "basic", "magic resistance can make physical attack better")
    f.target.base_pdef_pct = 0.0
    f.target.base_mdef_pct = 0.0
    f.actor.crit_chance_pct = 0.0
    f.actor.spell_power = 0
    f.actor.special_skill = special(500)
    f.target.hp = 30
    check_attack(f, "basic", "overkill not valued above actual HP; lower mana wins")
    f.actor.special_skill = special(100, 0)
    check_attack(f, "basic", "equal zero-mana modes have stable basic preference")
    f.actor.special_skill = special(100, 1)
    f.actor.matter = Matter.FIRE
    f.target.matter = Matter.FIRE
    f.actor.spell_power = 85
    f.actor.spell_mana_cost = 0
    f.actor.spell_matter = Matter.NEUTRAL
    f.target.hp = 1000
    check_attack(f, "magic", "physical same-matter penalty and neutral book respected")
    f.actor.spell_matter = Matter.FIRE
    f.actor.matter = Matter.NEUTRAL
    f.actor.spell_power = 100
    check_attack(f, "basic", "magic uses book matter rather than actor matter")


func test_target_selection() -> void:
    var f = fixture()
    var a = Unit.new("a", "blue", 1000, 100)
    var z = Unit.new("z", "blue", 1000, 100)
    f.board.remove_unit("blue")
    f.units.erase("blue")
    f.board.add_unit("a", Vector2i(2, 2))
    f.board.add_unit("z", Vector2i(1, 3))
    f.units["z"] = z
    f.units["a"] = a
    var first: Dictionary = choose(f)
    check(first == {"kind": "attack", "target_id": "a", "mode": "basic"}, "tie uses target ID, not insertion order")
    var reversed_units: Dictionary = {"a": a, "red": f.actor, "z": z}
    check(first == AI.choose_action(f.board, reversed_units, "red"), "reordered dictionary preserves choice")
    a.hp = 10
    check(choose(f).get("target_id") == "z", "actual expected HP damage avoids counting overkill")
    a.hp = 1000
    z.evasion_pct = 90.0
    check(choose(f).get("target_id") == "a", "evasion contributes to target ranking")
    a.base_pdef_pct = 90.0
    z.evasion_pct = 5.0
    check(choose(f).get("target_id") == "z", "defense contributes to target ranking")
    a.base_pdef_pct = 0.0
    f.actor.matter = Matter.FIRE
    a.matter = Matter.WIND
    check(choose(f).get("target_id") == "a", "matter advantage reduces target defense")
    a.matter = Matter.FIRE
    check(choose(f).get("target_id") == "z", "same matter reduces attack against that target")
    z.side = "red"
    check(choose(f).get("target_id") == "a", "friendly high-damage target excluded")
    a.hp = 0
    check(choose(f) == {"kind": "pass"}, "dead target excluded even if board still occupied")


func test_ranges_and_mana() -> void:
    var f = fixture()
    f.board.move_unit("blue", Vector2i(3, 2))
    f.actor.movement = 0
    f.actor.mp = 10
    f.actor.special_skill = special(120, 10, 2, 3)
    check_attack(f, "special", "special legal at two-hex distance")
    f.board.move_unit("blue", Vector2i(4, 2))
    check_attack(f, "special", "special legal at maximum distance")
    f.board.move_unit("blue", Vector2i(5, 2))
    check(choose(f) == {"kind": "pass"}, "special cannot exceed maximum range")
    f.board.move_unit("blue", Vector2i(2, 2))
    check_attack(f, "basic", "special minimum range enforced")
    f.board.move_unit("blue", Vector2i(3, 2))
    f.actor.mp = 9
    check(choose(f) == {"kind": "pass"}, "unaffordable ranged attack not used")
    f.actor.special_skill = null
    f.actor.spell_power = 300
    f.actor.spell_mana_cost = 0
    check(choose(f) == {"kind": "pass"}, "existing magic remains adjacent-only")
    f.actor.special_skill = special(120, 10, 3, 1)
    f.actor.mp = 10
    f.board.move_unit("blue", Vector2i(4, 2))
    check_attack(f, "special", "invalid max below min clamped like Combat")
    f.actor.special_skill.mana_cost = -1
    check(choose(f) == {"kind": "pass"}, "negative special cost is not affordable valid action")


func test_movement() -> void:
    var board = Board.new(8, 1)
    var actor = Unit.new("red", "red", 1000, 100, 0, 2)
    var target = Unit.new("blue", "blue", 1000, 100)
    board.add_unit("red", Vector2i(0, 0))
    board.add_unit("blue", Vector2i(7, 0))
    var units: Dictionary = {"red": actor, "blue": target}
    var first: Dictionary = AI.choose_action(board, units, "red")
    check(first == {"kind": "move", "cell": Vector2i(2, 0)}, "movement stops at own movement budget")
    check(board.position_of("red") == Vector2i(0, 0), "choosing movement does not execute it")
    actor.movement = 10
    check(AI.choose_action(board, units, "red") == {"kind": "move", "cell": Vector2i(6, 0)},
        "long move stops at attack cell rather than occupied enemy")
    actor.special_skill = special(100, 10, 2, 3)
    actor.mp = 10
    check(AI.choose_action(board, units, "red") == {"kind": "move", "cell": Vector2i(4, 0)},
        "movement considers affordable special range")
    actor.mp = 9
    check(AI.choose_action(board, units, "red") == {"kind": "move", "cell": Vector2i(6, 0)},
        "movement goal does not rely on unaffordable range")
    actor.movement = 0
    check(AI.choose_action(board, units, "red") == {"kind": "pass"}, "zero movement and no attack passes")
    actor.movement = 2
    board.set_blocked(Vector2i(3, 0), true)
    check(AI.choose_action(board, units, "red") == {"kind": "pass"}, "disconnected enemy causes pass")
    board.set_blocked(Vector2i(3, 0), false)
    var blocker = Unit.new("friend", "red", 1000, 100)
    units["friend"] = blocker
    board.add_unit("friend", Vector2i(1, 0))
    check(AI.choose_action(board, units, "red") == {"kind": "pass"}, "cannot traverse a friendly occupant")
    blocker.side = "blue"
    check(AI.choose_action(board, units, "red").get("target_id") == "friend", "hostile occupant becomes legal adjacent target")


func test_obstacles_and_detours() -> void:
    var board = Board.new(6, 6)
    var actor = Unit.new("red", "red", 1000, 100, 0, 1)
    var target = Unit.new("blue", "blue", 1000, 100)
    board.add_unit("red", Vector2i(1, 3))
    board.add_unit("blue", Vector2i(4, 3))
    for row in range(1, 6):
        board.set_blocked(Vector2i(2, row), true)
    var units: Dictionary = {"red": actor, "blue": target}
    var action: Dictionary = AI.choose_action(board, units, "red")
    check(action.get("kind") == "move", "route around long obstacle found")
    if action.get("kind") == "move":
        var cell: Vector2i = action.cell
        check(board.is_free(cell) and Hex.hex_distance(Vector2i(1, 3), cell) == 1,
            "detour step legal and within budget")
        check(Hex.hex_distance(cell, Vector2i(4, 3)) > Hex.hex_distance(Vector2i(1, 3), Vector2i(4, 3)),
            "planner can first move away to take a valid detour")
        for _repeat in range(4):
            check(action == AI.choose_action(board, {"blue": target, "red": actor}, "red"),
                "detour ties stable under reordered dictionary")
    actor.movement = 99
    action = AI.choose_action(board, units, "red")
    check(action.get("kind") == "move", "complete detour still one movement action")
    if action.get("kind") == "move":
        var path: Array[Vector2i] = board.shortest_path(Vector2i(1, 3), action.cell, "red")
        check(path.size() > 2 and Hex.hex_distance(action.cell, Vector2i(4, 3)) == 1,
            "complete path ends in an adjacent attack position")
        for cell in path:
            check(board.can_enter(cell, "red"), "detour never crosses occupied or blocked cells")
    board.set_blocked(Vector2i(2, 0), true)
    check(AI.choose_action(board, units, "red") == {"kind": "pass"}, "sealed wall prevents illegal approach")


func test_purity() -> void:
    var f = fixture()
    f.actor.mp = 50
    f.actor.max_mp = 100
    f.actor.mana_regen_fraction = 0.7
    f.actor.special_skill = special()
    f.actor.spell_power = 300
    f.actor.spell_mana_cost = 10
    f.target.apply_concussion(2)
    var old_positions: Dictionary = f.board.unit_positions.duplicate()
    var old_occupied: Dictionary = f.board.occupied.duplicate()
    var old_blocked: Dictionary = f.board.blocked.duplicate()
    seed(16406)
    var expected_random: float = randf()
    seed(16406)
    for _repeat in range(5):
        check_attack(f, "magic", "same state yields same decision")
    check(randf() == expected_random, "planner does not consume RNG")
    check(f.actor.hp == 1000 and f.target.hp == 1000, "planner does not deal damage")
    check(f.actor.mp == 50 and f.actor.mana_regen_fraction == 0.7, "planner does not spend or regenerate MP")
    check(f.target.concussion_turns_remaining == 2, "planner does not consume target status")
    check(f.board.unit_positions == old_positions and f.board.occupied == old_occupied
        and f.board.blocked == old_blocked, "planner never changes board dictionaries")
