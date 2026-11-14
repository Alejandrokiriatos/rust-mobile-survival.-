extends StaticBody3D
class_name ResourceNode

@export_enum("Madera", "Piedra", "Fibra") var resource_type := "Madera"
@export var amount := 3
var remaining := 3

func _ready() -> void:
    remaining = amount
    add_to_group("harvestable")

func harvest(player: SurvivalPlayer) -> String:
    if remaining <= 0:
        return "Agotado"
    remaining -= 1
    player.collect(resource_type, 1)
    if remaining == 0:
        queue_free()
    return "+1 " + resource_type
