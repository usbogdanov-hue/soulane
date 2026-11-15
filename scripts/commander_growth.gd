extends RefCounted
## Level-up points only; callers add the commander's existing base attributes.
## DEX in the approved mage ratios is the existing AGI attribute.
## Hybrids have no approved automatic growth ratios yet.

const KEYS: Array[String] = ["STR", "AGI", "WIS", "INT"]
const MIN_LEVEL: int = 1
const MAX_LEVEL: int = 999
const POINTS_PER_LEVEL: int = 3


static func supports(archetype: int) -> bool:
    return archetype in [0, 1, 4, 5]


static func weights(archetype: int) -> Dictionary:
    match archetype:
        0: return {"STR": 50, "AGI": 30, "WIS": 10, "INT": 10}
        1: return {"STR": 30, "AGI": 40, "WIS": 20, "INT": 10}
        4: return {"STR": 10, "AGI": 10, "WIS": 30, "INT": 50}
        5: return {"STR": 10, "AGI": 10, "WIS": 50, "INT": 30}
    return {}


static func points(archetype: int, level: int) -> Dictionary:
    if not supports(archetype) or level < MIN_LEVEL or level > MAX_LEVEL:
        return {}
    var budget: int = POINTS_PER_LEVEL * (level - MIN_LEVEL)
    @warning_ignore("integer_division")
    var full_cycles: int = budget / 10
    var ratios: Dictionary = weights(archetype)
    var result: Dictionary = {}
    var prefix: Dictionary = {}
    for key in KEYS:
        @warning_ignore("integer_division")
        var per_cycle: int = int(ratios[key]) / 10
        ratios[key] = per_cycle
        result[key] = full_cycles * per_cycle
        prefix[key] = 0
    # All approved ratios are multiples of 10%. Ten individual allocations
    # complete the exact ratio, so only the remaining prefix needs evaluation.
    # Each next point goes to the greatest deficit from its current target;
    # stable STR -> AGI -> WIS -> INT order resolves equal deficits.
    # Every higher level extends the same allocation sequence: existing points
    # never disappear merely because a larger total was rounded again.
    for step in range(1, budget % 10 + 1):
        var chosen: String = KEYS[0]
        var deficit: int = step * int(ratios[chosen]) - int(prefix[chosen]) * 10
        for index in range(1, KEYS.size()):
            var key: String = KEYS[index]
            var candidate: int = step * int(ratios[key]) - int(prefix[key]) * 10
            if candidate > deficit:
                chosen = key
                deficit = candidate
        prefix[chosen] += 1
    for key in KEYS:
        result[key] += prefix[key]
    return result
