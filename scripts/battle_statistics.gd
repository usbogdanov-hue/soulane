extends RefCounted
## Counts only completed native battle events. It neither evaluates attacks nor
## reads mutable units, advances turns, spends resources or consumes combat RNG.

const COUNTERS: Array[String] = [
    "attacks", "hits", "misses", "criticals", "damage_dealt", "damage_received",
    "kills", "physical_damage", "magic_damage", "mp_spent", "mp_regenerated",
    "concussions", "concussion_skips", "moves", "steps", "passes", "mp_test_spent",
]

var _units: Dictionary = {}
var _sides: Dictionary = {}


func reset(roster: Array[Dictionary]) -> void:
    _units.clear()
    _sides.clear()
    for row in roster:
        var unit_id: Variant = row.get("id", "")
        var side: Variant = row.get("side", "")
        if typeof(unit_id) != TYPE_STRING or unit_id.is_empty() or _units.has(unit_id):
            continue
        if typeof(side) != TYPE_STRING or side not in ["blue", "red"]:
            continue
        _units[unit_id] = _zero()
        _sides[unit_id] = side


func record_attack(attacker_id: String, target_id: String, mode: String,
        result: Dictionary) -> void:
    if not _units.has(attacker_id) or not _units.has(target_id):
        return
    if attacker_id == target_id or _sides[attacker_id] == _sides[target_id]:
        return
    if mode not in ["basic", "special", "magic"] or result.get("ok", false) != true:
        return
    for key in ["ok", "evaded", "critical", "defeated", "concussion_applied"]:
        if result.has(key) and typeof(result[key]) != TYPE_BOOL:
            return
    var damage: Variant = result.get("damage", -1)
    var cost: Variant = result.get("spell_cost" if mode == "magic" else "skill_cost", 0)
    if not _nonnegative_integer(damage) or not _nonnegative_integer(cost):
        return
    var evaded: bool = result.get("evaded", false)
    if evaded and damage != 0:
        return
    var actor: Dictionary = _units[attacker_id]
    actor.attacks += 1
    actor.mp_spent += cost
    if evaded:
        actor.misses += 1
        return
    actor.hits += 1
    actor.damage_dealt += damage
    actor["magic_damage" if mode == "magic" else "physical_damage"] += damage
    _units[target_id].damage_received += damage
    if mode != "magic" and result.get("critical", false):
        actor.criticals += 1
    if result.get("defeated", false):
        actor.kills += 1
    if result.get("concussion_applied", false):
        actor.concussions += 1


func record_move(unit_id: String, steps: Variant) -> void:
    if _units.has(unit_id) and _positive_integer(steps):
        _units[unit_id].moves += 1
        _units[unit_id].steps += steps


func record_pass(unit_id: String) -> void:
    if _units.has(unit_id):
        _units[unit_id].passes += 1


func record_concussion_skip(unit_id: String) -> void:
    if _units.has(unit_id):
        _units[unit_id].concussion_skips += 1


func record_regeneration(unit_id: String, amount: Variant) -> void:
    if _units.has(unit_id) and _positive_integer(amount):
        _units[unit_id].mp_regenerated += amount


func record_test_spend(unit_id: String, amount: Variant) -> void:
    if _units.has(unit_id) and _positive_integer(amount):
        _units[unit_id].mp_spent += amount
        _units[unit_id].mp_test_spent += amount


func snapshot() -> Dictionary:
    var teams: Dictionary = {"blue": _zero(), "red": _zero()}
    var totals: Dictionary = _zero()
    for unit_id in _units:
        var counters: Dictionary = _units[unit_id]
        var team: Dictionary = teams[_sides[unit_id]]
        for key in COUNTERS:
            team[key] += counters[key]
            totals[key] += counters[key]
    return {"units": _units.duplicate(true), "teams": teams, "totals": totals}


static func report(summary: Dictionary) -> String:
    var winner: String = str(summary.get("winner_side", ""))
    var winner_name: String = _side_name(winner) if winner in ["blue", "red"] else "не определён"
    var lines: PackedStringArray = [
        "СУЛЭЙН · ОТЧЁТ БОЯ · v1.14",
        "Победитель: %s" % winner_name,
        "Раунд: %d · Арена: %s" % [maxi(1, int(summary.get("rounds", 1))), str(summary.get("arena", "—"))],
        "",
        "Урон — фактически снятые HP, без избыточного урона. Магия не критует.",
        "Контузии — успешные применения, включая обновление; пропуски — выполненные собственные ходы.",
        "MP восстановлено — фактическая регенерация с учётом максимума. Тестовый расход M показан отдельно.",
        "",
        "КОМАНДЫ",
    ]
    var statistics: Dictionary = summary.get("statistics", {})
    var team_stats: Dictionary = statistics.get("teams", {})
    var teams: Dictionary = summary.get("teams", {})
    for side in ["blue", "red"]:
        var team: Dictionary = teams.get(side, {})
        lines.append("%s · В строю: %d из %d · Потери: %d" % [_side_name(side),
            int(team.get("alive", 0)), int(team.get("total", 0)), int(team.get("fallen", 0))])
        lines.append_array(_counter_lines(team_stats.get(side, {})))
        lines.append("")
    lines.append("СУММА БОЯ")
    lines.append_array(_counter_lines(statistics.get("totals", {})))
    lines.append("")
    lines.append("БОЙЦЫ")
    var unit_stats: Dictionary = statistics.get("units", {})
    for raw in summary.get("units", []):
        if not raw is Dictionary:
            continue
        var unit: Dictionary = raw
        var level: int = int(unit.get("level", 0))
        var heading: String = "%s · %s" % [str(unit.get("label", "Боец")), _side_name(str(unit.get("side", "")))]
        if level > 0:
            heading += " · Уровень %d" % level
        lines.append(heading)
        lines.append("%s · HP %d/%d · MP %d/%d" % ["В строю" if unit.get("alive", false) else "Повержен",
            int(unit.get("hp", 0)), int(unit.get("max_hp", 0)),
            int(unit.get("mp", 0)), int(unit.get("max_mp", 0))])
        lines.append("Материя бойца: %s · Материя магии: %s" % [
            str(unit.get("matter", "—")), str(unit.get("spell_matter", "—"))])
        lines.append_array(_counter_lines(unit_stats.get(str(unit.get("id", "")), {})))
        lines.append("")
    var setup_code: String = str(summary.get("setup_code", ""))
    if not setup_code.is_empty():
        lines.append("КОД НАЧАЛЬНОЙ ПОДГОТОВКИ")
        lines.append("Код переносит только состав и расстановку. Это не сохранение и не повтор боя: HP, MP, очередь и случайные исходы не восстанавливаются.")
        lines.append(setup_code)
    return "\n".join(lines)


static func _counter_lines(counters: Dictionary) -> PackedStringArray:
    return PackedStringArray([
        "Урон: нанесено %d HP (физический %d, магический %d) · Получено %d HP" % [
            int(counters.get("damage_dealt", 0)), int(counters.get("physical_damage", 0)),
            int(counters.get("magic_damage", 0)), int(counters.get("damage_received", 0))],
        "Атаки %d · Попадания %d · Промахи %d · Криты %d · Добивания %d" % [
            int(counters.get("attacks", 0)), int(counters.get("hits", 0)), int(counters.get("misses", 0)),
            int(counters.get("criticals", 0)), int(counters.get("kills", 0))],
        "MP: расход %d (из них тест M: %d) · Восстановлено %d" % [
            int(counters.get("mp_spent", 0)), int(counters.get("mp_test_spent", 0)), int(counters.get("mp_regenerated", 0))],
        "Контузии: применено %d · Собственные пропуски %d" % [
            int(counters.get("concussions", 0)), int(counters.get("concussion_skips", 0))],
        "Перемещения %d · Шаги %d · Добровольные пропуски %d" % [
            int(counters.get("moves", 0)), int(counters.get("steps", 0)), int(counters.get("passes", 0))],
    ])


static func _side_name(side: String) -> String:
    return "Синяя команда" if side == "blue" else ("Красная команда" if side == "red" else "Команда")


static func _zero() -> Dictionary:
    var result: Dictionary = {}
    for key in COUNTERS:
        result[key] = 0
    return result


static func _nonnegative_integer(value: Variant) -> bool:
    return typeof(value) == TYPE_INT and value >= 0


static func _positive_integer(value: Variant) -> bool:
    return _nonnegative_integer(value) and value > 0
