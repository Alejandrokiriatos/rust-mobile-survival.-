extends CharacterBody3D
class_name WildAnimal

@export var move_speed := 2.2
@export var detection_range := 15.0
@export var attack_range := 1.8
@export var damage := 5.0

var target: Node3D
var home := Vector3.ZERO
var wander_target := Vector3.ZERO
var wander_timer := 0.0
var attack_timer := 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
    home = global_position
    _choose_wander_target()
    _build_visual()

func _build_visual() -> void:
    var body_mesh := MeshInstance3D.new()
    var body := CapsuleMesh.new()
    body.radius = 0.48
    body.height = 1.15
    body_mesh.mesh = body
    body_mesh.position.y = 0.62
    var body_mat := StandardMaterial3D.new()
    body_mat.albedo_color = Color(0.28, 0.19, 0.14)
    body_mat.roughness = 0.95
    body_mesh.material_override = body_mat
    add_child(body_mesh)

    var head_mesh := MeshInstance3D.new()
    var head := SphereMesh.new()
    head.radius = 0.34
    head.height = 0.62
    head_mesh.mesh = head
    head_mesh.position = Vector3(0, 0.68, -0.48)
    head_mesh.scale = Vector3(1.0, 0.82, 1.15)
    head_mesh.material_override = body_mat
    add_child(head_mesh)

    var collider := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    shape.radius = 0.42
    shape.height = 1.15
    collider.shape = shape
    collider.position.y = 0.58
    add_child(collider)

func _physics_process(delta: float) -> void:
    if not is_instance_valid(target):
        var players := get_tree().get_nodes_in_group("player")
        if not players.is_empty():
            target = players[0] as Node3D
    if not is_on_floor():
        velocity.y -= gravity * delta
    var desired := Vector3.ZERO
    if is_instance_valid(target):
        var to_player := target.global_position - global_position
        to_player.y = 0.0
        if to_player.length() < detection_range:
            if to_player.length() > attack_range:
                desired = to_player.normalized() * move_speed * 1.25
            else:
                attack_timer -= delta
                if attack_timer <= 0.0 and target.has_method("take_damage"):
                    target.take_damage(damage)
                    attack_timer = 1.35
        else:
            target = null
    if desired.length_squared() < 0.01:
        wander_timer -= delta
        if wander_timer <= 0.0 or global_position.distance_to(wander_target) < 1.2:
            _choose_wander_target()
        var direction := wander_target - global_position
        direction.y = 0.0
        if direction.length() > 0.5:
            desired = direction.normalized() * move_speed * 0.42
    velocity.x = move_toward(velocity.x, desired.x, 7.0 * delta)
    velocity.z = move_toward(velocity.z, desired.z, 7.0 * delta)
    if desired.length_squared() > 0.05:
        look_at(global_position + Vector3(desired.x, 0, desired.z), Vector3.UP)
    move_and_slide()

func _choose_wander_target() -> void:
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    wander_target = home + Vector3(rng.randf_range(-10, 10), 0, rng.randf_range(-10, 10))
    wander_timer = rng.randf_range(2.5, 5.0)
