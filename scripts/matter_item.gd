@tool
class_name SuleynMatterItem
extends Resource
## One equipped item contributes at most ONE matter source.
@export var display_name: String = "Предмет"
@export_enum("Нет", "Огонь", "Воздух", "Вода", "Свет", "Тьма") var matter: int = 0
