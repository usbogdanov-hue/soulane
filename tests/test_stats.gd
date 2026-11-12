extends SceneTree
## Run: godot --headless --path . --script res://tests/test_stats.gd

const Unit = preload("res://scripts/battle_unit.gd")
const Board = preload("res://scripts/battle_board.gd")
const Combat = preload("res://scripts/battle_combat.gd")
const Formula = preload("res://scripts/damage_calculator.gd")
const AllyTemplate = preload("res://data/demo_ally.tres")
const EnemyTemplate = preload("res://data/demo_enemy.tres")

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
    test_resource_values()
    test_formula()
    test_stats_in_combat()
    test_movement_per_unit()
    if failures == 0:
        print("SULEYN v0.4: %d stat checks passed." % checks)
        quit(0)
    else:
        printerr("SULEYN v0.4: %d of %d stat checks failed." % [failures, checks])
        quit(1)

func check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("FAILED: " + message)

func test_resource_values() -> void:
    check(AllyTemplate.max_hp == 24, "ally hp comes from .tres resource")
    check(AllyTemplate.attack == 8, "ally attack comes from .tres resource")
    check(AllyTemplate.defense == 3, "ally defense comes from .tres resource")
    check(EnemyTemplate.movement == 2, "enemy movement comes from .tres resource")

func test_formula() -> void:
    check(Formula.physical_damage(8, 0.0, 0.0) == 8, "skill power 8 with no defense")
    check(Formula.physical_damage(7, 0.0, 0.0) == 7, "skill power 7 with no defense")
    check(Formula.physical_damage(1, 0.0, 90.0) == 0, "small attacks may round to zero")
    check(Formula.physical_damage(-10, 0.0, 0.0) == 0, "negative stats are sanitized")

func test_stats_in_combat() -> void:
    var board = Board.new(4, 4)
    check(board.add_unit("A", Vector2i(1, 1)), "place A")
    check(board.add_unit("E", Vector2i(2, 1)), "place E")
    var ally = Unit.new("A", "blue", AllyTemplate.max_hp, AllyTemplate.attack,
        AllyTemplate.defense, AllyTemplate.movement, AllyTemplate.display_name)
    var enemy = Unit.new("E", "red", EnemyTemplate.max_hp, EnemyTemplate.attack,
        EnemyTemplate.defense, EnemyTemplate.movement, EnemyTemplate.display_name)
    var units: Dictionary = {"A": ally, "E": enemy}
    var blue_result: Dictionary = Combat.melee_attack(board, units, "A", "E", 99.0, 99.0)
    check(blue_result["ok"] and blue_result["damage"] == 8, "A deals 8 skill power")
    check(enemy.hp == 12, "E loses 8 HP")
    var red_result: Dictionary = Combat.melee_attack(board, units, "E", "A", 99.0, 99.0)
    check(red_result["ok"] and red_result["damage"] == 7, "E deals 7 skill power")
    check(ally.hp == 17, "A loses 7 hp")
    check(ally.movement == 3 and enemy.movement == 2, "individual movement values")
    check(ally.display_name == "Женщина-воин (синяя)", "display name loaded")

func test_movement_per_unit() -> void:
    var board = Board.new(7, 7)
    board.add_unit("A", Vector2i(0, 2))
    board.add_unit("E", Vector2i(6, 2))
    var a_dist: Dictionary = board.reachable_from(Vector2i(0, 2), AllyTemplate.movement, "A")
    var e_dist: Dictionary = board.reachable_from(Vector2i(6, 2), EnemyTemplate.movement, "E")
    check(a_dist.has(Vector2i(3, 2)), "A reaches 3 hexes")
    check(not e_dist.has(Vector2i(3, 2)), "E cannot reach 3 hexes")
