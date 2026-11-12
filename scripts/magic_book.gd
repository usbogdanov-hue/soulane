class_name SuleynMagicBook
extends Resource
## Every damaging spell inherits this book's MATTER, without exceptions.
## The Forest Talmud and Novice Book are neutral.
@export var display_name: String = "Книга магии"
@export_enum("Нейтральная", "Огонь", "Ветер/Воздух", "Вода", "Свет", "Тьма") var matter: int = 0
## Legacy read/write property (not exported) for v0.9 APIs.
var element: int:
    get:
        return matter
    set(value):
        matter = value
