class_name SuleynMatterRules
extends RefCounted
## Matter is resolved from class/nature and every equipped matter-bearing item.
## A unique leading count wins; ties and no sources give NEUTRAL.
const NEUTRAL: int = 0
const FIRE: int = 1
const WIND: int = 2
const WATER: int = 3
const LIGHT: int = 4
const DARK: int = 5

static func matter_name(matter: int) -> String:
    match matter:
        FIRE: return "Огонь"
        WIND: return "Воздух"
        WATER: return "Вода"
        LIGHT: return "Свет"
        DARK: return "Тьма"
    return "Нейтральная"

static func resolve(sources: Array) -> int:
    var counts: Dictionary = {}
    for source in sources:
        var matter: int = int(source)
        if matter < FIRE or matter > DARK:
            continue
        counts[matter] = int(counts.get(matter, 0)) + 1
    var winner: int = NEUTRAL
    var high_count: int = 0
    var tie: bool = false
    for matter in counts:
        var count: int = int(counts[matter])
        if count > high_count:
            winner = int(matter)
            high_count = count
            tie = false
        elif count == high_count:
            tie = true
    return NEUTRAL if tie else winner

static func is_strong_against(attack_matter: int, target_matter: int) -> bool:
    match attack_matter:
        FIRE: return target_matter == WIND
        WIND: return target_matter == WATER
        WATER: return target_matter == FIRE
        LIGHT: return target_matter == DARK
        DARK: return target_matter == LIGHT
    return false

static func attack_penalty_pct(attack_matter: int, target_matter: int) -> float:
    if attack_matter == NEUTRAL or target_matter == NEUTRAL:
        return 0.0
    return -15.0 if attack_matter == target_matter else 0.0

static func defense_penalty_pp(attack_matter: int, target_matter: int) -> float:
    if attack_matter == NEUTRAL or target_matter == NEUTRAL:
        return 0.0
    return -15.0 if is_strong_against(attack_matter, target_matter) else 0.0
