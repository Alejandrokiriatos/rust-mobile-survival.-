extends StaticBody3D
class_name ResourceNode

@export_enum("Madera", "Piedra", "Fibra") var resource_type := "Madera"
@export var amount := 3
var remaining := 3
var model_scene: PackedScene
var model_scale := Vector3.ONE

func _ready() -> void:
    remaining = amount
    add_to_group("harvestable")
    if model_scene == null:
        push_warning("ResourceNode sin modelo 3D asignado.")
        return
    var visual := model_scene.instantiate()
    visual.scale = model_scale
    add_child(visual)
    var collision := CollisionShape3D.new()
    if resource_type == "Madera":
        var capsule := CapsuleShape3D.new()
        capsule.radius = 0.42
        capsule.height = 2.8
        collision.shape = capsule
        collision.position.y = 1.35 * model_scale.y
    elif resource_type == "Piedra":
        var sphere := SphereShape3D.new()
        sphere.radius = 0.85
        collision.shape = sphere
        collision.position.y = 0.55 * model_scale.y
    else:
        var bush_shape := SphereShape3D.new()
        bush_shape.radius = 0.7
        collision.shape = bush_shape
        collision.position.y = 0.45 * model_scale.y
    add_child(collision)

func harvest(player: SurvivalPlayer) -> String:
    if remaining <= 0:
        return "Agotado"
    remaining -= 1
    player.collect(resource_type, 1)
    if remaining == 0:
        queue_free()
    return "+1 " + resource_type
