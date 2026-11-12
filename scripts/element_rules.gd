class_name SuleynElementRules
extends RefCounted
## Deprecated compatibility wrapper for v0.9 tests and old project files.
## New gameplay calls matter_rules.gd instead. Use the term MATTER in GDD.
const Matter = preload("res://scripts/matter_rules.gd")
const NEUTRAL = Matter.NEUTRAL
const FIRE = Matter.FIRE
const WIND = Matter.WIND
const WATER = Matter.WATER
const LIGHT = Matter.LIGHT
const DARK = Matter.DARK
static func attack_element(book_element: int) -> int:
    return book_element
static func same_element_attack_penalty(a: int, b: int) -> float:
    return Matter.attack_penalty_pct(a, b)
static func target_defense_penalty(a: int, b: int) -> float:
    return Matter.defense_penalty_pp(a, b)
