extends CharacterBody3D
class_name SurvivalPlayer

@export var walk_speed := 5.2
@export var jump_velocity := 4.2
@export var look_sensitivity := 0.0035
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var look_finger := -1
var camera: Camera3D
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
    camera.fov = 78.0
    camera.far = 240.0
    camera.current = true
    add_child(camera)
    floor_snap_length = 0.3
    add_to_group("player")

func set_mobile_action(action: String, pressed: bool) -> void:
    if not InputMap.has_action(action):
        return
    if pressed:
        Input.action_press(action)
    else:
        Input.action_release(action)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            if event.position.x >= get_viewport().get_visible_rect().size.x * 0.38:
                look_finger = event.index
        elif event.index == look_finger:
            look_finger = -1
    elif event is InputEventScreenDrag and event.index == look_finger:
        rotate_y(-event.relative.x * look_sensitivity)
        camera.rotate_x(-event.relative.y * look_sensitivity)
        camera.rotation.x = clamp(camera.rotation.x, -1.25, 1.25)
    elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * look_sensitivity)
        camera.rotate_x(-event.relative.y * look_sensitivity)
        camera.rotation.x = clamp(camera.rotation.x, -1.25, 1.25)

func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= gravity * delta
    elif Input.is_action_just_pressed("jump"):
        velocity.y = jump_velocity
    var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
    if direction.length_squared() > 0.001:
        velocity.x = direction.x * walk_speed
        velocity.z = direction.z * walk_speed
    else:
        velocity.x = move_toward(velocity.x, 0, walk_speed * 7.0 * delta)
        velocity.z = move_toward(velocity.z, 0, walk_speed * 7.0 * delta)
    move_and_slide()
    hunger = maxf(0.0, hunger - delta * 0.025)
    thirst = maxf(0.0, thirst - delta * 0.04)

func collect(item: String, amount: int = 1) -> void:
    inventory[item] = int(inventory.get(item, 0)) + amount
