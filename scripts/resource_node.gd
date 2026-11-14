extends StaticBody3D
class_name ResourceNode

@export_enum("Madera", "Piedra", "Fibra") var resource_type := "Madera"
@export var amount := 3
var remaining := 3
var resource_id := ""
var model_scene: PackedScene
var model_scale := Vector3.ONE

func _ready() -> void:
    remaining = amount
    add_to_group("harvestable")
    if model_scene == null:
        push_warning("ResourceNode sin modelo 3D asignado.")
        return
    var visual := model_scene.instantiate() as Node3D
    visual.scale = model_scale
    add_child(visual)
    var collision := CollisionShape3D.new()
    if resource_type == "Madera":
        var capsule := CapsuleShape3D.new()
        capsule.radius = 0.48
        capsule.height = 5.2
        collision.shape = capsule
        collision.position.y = 2.6
    elif resource_type == "Piedra":
        var sphere := SphereShape3D.new()
        sphere.radius = 1.15
        collision.shape = sphere
        collision.position.y = 0.65
    else:
        var bush_shape := SphereShape3D.new()
        bush_shape.radius = 1.15
        collision.shape = bush_shape
        collision.position.y = 0.8
    add_child(collision)

func harvest(player: SurvivalPlayer) -> String:
    if remaining <= 0:
        return "Agotado"
    remaining -= 1
    var yield_amount := 2 if resource_type == "Madera" and player.axe_unlocked else 1
    player.collect(resource_type, yield_amount)
    var world := get_parent()
    if world != null and world.has_method("on_resource_harvested"):
        world.on_resource_harvested(resource_id, remaining)
    if remaining == 0:
        queue_free()
    return "+%d %s" % [yield_amount, resource_type]
