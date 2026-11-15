extends Node3D

var elapsed := 0.0
var base_energy := 1.8
var flame: MeshInstance3D
var inner_flame: MeshInstance3D
var torch_light: OmniLight3D

func _ready() -> void:
    torch_light = get_node_or_null("TorchLight") as OmniLight3D
    flame = get_child(4) as MeshInstance3D if get_child_count() > 4 else null
    inner_flame = get_child(5) as MeshInstance3D if get_child_count() > 5 else null
    if is_instance_valid(torch_light):
        base_energy = torch_light.light_energy
    set_process(true)

func _process(delta: float) -> void:
    elapsed += delta
    var pulse := 0.82 + 0.14 * sin(elapsed * 13.0) + 0.08 * sin(elapsed * 21.7 + 1.4)
    if is_instance_valid(torch_light):
        torch_light.light_energy = base_energy * pulse
    if is_instance_valid(flame):
        flame.scale.y = 1.45 * (0.92 + 0.12 * sin(elapsed * 15.0))
        flame.rotation.z = 0.12 * sin(elapsed * 9.0)
    if is_instance_valid(inner_flame):
        inner_flame.scale.y = 1.0 + 0.10 * sin(elapsed * 17.0 + 0.8)
