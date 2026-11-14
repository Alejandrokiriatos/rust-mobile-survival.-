extends CharacterBody3D
class_name SurvivalPlayer

@export var walk_speed := 5.2
@export var sprint_speed := 7.0
@export var jump_velocity := 4.2
@export var look_sensitivity := 0.0032
@export var ground_acceleration := 19.0
@export var air_acceleration := 5.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var look_finger := -1
var camera: Camera3D
var joystick: MobileJoystick
var sprinting := false
var axe_unlocked := false
var inventory := {"Madera": 0, "Piedra": 0, "Fibra": 0}
var health := 100.0
var hunger := 100.0
var thirst := 100.0

func _ready() -> void:
    name = "Player"
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.38
    capsule.height = 1.8
    var collision := CollisionShape3D.new()
    collision.shape = capsule
    collision.position.y = 0.9
    add_child(collision)
    camera = Camera3D.new()
    camera.position = Vector3(0, 1.58, 0)
    camera.fov = 76.0
    camera.far = 190.0
    camera.current = true
    add_child(camera)
    floor_snap_length = 0.35
    floor_max_angle = deg_to_rad(48.0)
    add_to_group("player")

func set_sprinting(enabled: bool) -> void:
    sprinting = enabled

func mobile_action(action: String, pressed: bool) -> void:
    if InputMap.has_action(action):
        if pressed:
            Input.action_press(action)
        else:
            Input.action_release(action)

func take_damage(amount: float) -> void:
    health = maxf(0.0, health - amount)

func restore_needs(food: float, water: float) -> void:
    hunger = minf(100.0, hunger + food)
    thirst = minf(100.0, thirst + water)

func _unhandled_input(event: InputEvent) -> void:
    var viewport_size := get_viewport().get_visible_rect().size
    if event is InputEventScreenTouch:
        if event.pressed:
            # La zona superior/derecha queda reservada para mirar; los botones inferiores no roban la cámara.
            if event.position.x >= viewport_size.x * 0.48 and event.position.y < viewport_size.y * 0.72 and look_finger == -1:
                look_finger = event.index
        elif event.index == look_finger:
            look_finger = -1
    elif event is InputEventScreenDrag and event.index == look_finger:
        _apply_look(event.relative)
    elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        _apply_look(event.relative)

func _apply_look(relative: Vector2) -> void:
    rotate_y(-relative.x * look_sensitivity)
    camera.rotate_x(-relative.y * look_sensitivity)
    camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-78.0), deg_to_rad(78.0))

func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= gravity * delta
    elif Input.is_action_just_pressed("jump"):
        velocity.y = jump_velocity

    var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    if is_instance_valid(joystick) and joystick.input_vector.length_squared() > 0.001:
        input_dir = joystick.input_vector
    input_dir = input_dir.limit_length(1.0)

    var local_direction := Vector3(input_dir.x, 0.0, input_dir.y)
    var direction := (global_transform.basis * local_direction).normalized()
    var target_speed := sprint_speed if sprinting else walk_speed
    var target_velocity := direction * target_speed
    var acceleration := ground_acceleration if is_on_floor() else air_acceleration
    velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
    velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
    move_and_slide()

    hunger = maxf(0.0, hunger - delta * 0.018)
    thirst = maxf(0.0, thirst - delta * 0.032)
    if hunger <= 0.0 or thirst <= 0.0:
        take_damage(delta * (1.0 if hunger <= 0.0 and thirst <= 0.0 else 0.45))

func collect(item: String, amount: int = 1) -> void:
    inventory[item] = int(inventory.get(item, 0)) + amount
