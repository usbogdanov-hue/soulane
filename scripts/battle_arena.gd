extends RefCounted
## Prototype impassable hex layouts. No cover, flight or line-of-sight rules.

const KEYS: Array[String] = ["open", "gates", "pillars"]
const LABELS: Dictionary = {
    "open": "Открытое поле", "gates": "Два прохода", "pillars": "Колонны",
}
const DESCRIPTIONS: Dictionary = {
    "open": "Свободное поле без препятствий.",
    "gates": "Центральная преграда с двумя проходами. Выберите путь обхода.",
    "pillars": "Четыре закрытых гекса в центре поля. Между ними есть проходы.",
}


static func keys() -> Array[String]:
    return KEYS.duplicate()


static func label(key: String) -> String:
    return str(LABELS.get(key, ""))


static func description(key: String) -> String:
    return str(DESCRIPTIONS.get(key, ""))


static func is_supported(key: String, columns: int, rows: int) -> bool:
    if not KEYS.has(key) or columns < 4 or rows < 3:
        return false
    return key == "open" or (columns >= 7 and rows >= 5)


static func blocked_cells(key: String, columns: int, rows: int) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    if not is_supported(key, columns, rows) or key == "open":
        return result
    if key == "gates":
        var middle: int = columns / 2
        var upper_gate: int = rows / 3
        var lower_gate: int = rows * 2 / 3
        for row in range(rows):
            if row != upper_gate and row != lower_gate:
                result.append(Vector2i(middle, row))
    elif key == "pillars":
        var left: int = columns / 3
        var right: int = columns - 1 - left
        var upper: int = rows / 3
        var lower: int = rows - 1 - upper
        for column in [left, right]:
            for row in [upper, lower]:
                result.append(Vector2i(column, row))
    return result
