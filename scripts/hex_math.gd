extends RefCounted
## Pure axial (q, r) pointy-top hex geometry. No game rules here.

const DIRECTIONS: Array[Vector2i] = [
    Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
    Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
]


static func axial_to_pixel(cell: Vector2i, radius: float) -> Vector2:
    return Vector2(
        sqrt(3.0) * radius * (float(cell.x) + float(cell.y) / 2.0),
        1.5 * radius * float(cell.y)
    )


static func pixel_to_axial(point: Vector2, radius: float) -> Vector2i:
    if radius <= 0.0:
        return Vector2i.ZERO
    var q: float = (sqrt(3.0) / 3.0 * point.x - point.y / 3.0) / radius
    var r: float = (2.0 / 3.0 * point.y) / radius
    return axial_round(q, r)


static func axial_round(q: float, r: float) -> Vector2i:
    # Cube coordinates are (x=q, y=-q-r, z=r).
    var x: float = q
    var y: float = -q - r
    var z: float = r
    var rx: int = roundi(x)
    var ry: int = roundi(y)
    var rz: int = roundi(z)

    var dx: float = absf(float(rx) - x)
    var dy: float = absf(float(ry) - y)
    var dz: float = absf(float(rz) - z)
    if dx > dy and dx > dz:
        rx = -ry - rz
    elif dy > dz:
        ry = -rx - rz
    else:
        rz = -rx - ry
    return Vector2i(rx, rz)


static func hex_distance(a: Vector2i, b: Vector2i) -> int:
    var dq: int = a.x - b.x
    var dr: int = a.y - b.y
    return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


static func point_in_hex(point: Vector2, center: Vector2, radius: float) -> bool:
    # Exact convex hex hit test for pointy-top orientation.
    var delta: Vector2 = point - center
    var ax: float = absf(delta.x)
    var ay: float = absf(delta.y)
    var half_width: float = sqrt(3.0) * radius / 2.0
    return ax <= half_width + 0.01 and ay + ax / sqrt(3.0) <= radius + 0.01
