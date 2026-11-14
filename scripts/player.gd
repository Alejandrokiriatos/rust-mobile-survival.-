extends CharacterBody3D
class_name SurvivalPlayer

@export var walk_speed := 5.0
@export var jump_velocity := 4.2
@export var look_sensitivity := 0.003
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var touch_move := Vector2.ZERO
var look_finger := -1
var move_finger := -1
var last_look := Vector2.ZERO
var inventory := {"Madera": 0, "Piedra": 0, "Fibra": 0}
var health := 100.0
var hunger := 100.0
var thirst := 100.0
var camera: Camera3D

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
    camera.current = true
    add_child(camera)
    floor_snap_length = 0.25
    add_to_group("player")

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            if event.position.x < get_viewport().get_visible_rect().size.x * 0.42 and move_finger == -1:
                move_finger = event.index
                _set_touch_move(event.position)
            elif look_finger == -1:
                look_finger = event.index
                last_look = event.position
        else:
            if event.index == move_finger:
                move_finger = -1
                touch_move = Vector2.ZERO
            if event.index == look_finger:
                look_finger = -1
    elif event is InputEventScreenDrag:
        if event.index == move_finger:
            _set_touch_move(event.position)
        elif event.index == look_finger:
            rotate_y(-event.relative.x * look_sensitivity)
            camera.rotate_x(-event.relative.y * look_sensitivity)
            camera.rotation.x = clamp(camera.rotation.x, -1.35, 1.35)
    elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * look_sensitivity)
        camera.rotate_x(-event.relative.y * look_sensitivity)
        camera.rotation.x = clamp(camera.rotation.x, -1.35, 1.35)

func _set_touch_move(pos: Vector2) -> void:
    var size := get_viewport().get_visible_rect().size
    var center := Vector2(size.x * 0.19, size.y * 0.78)
    touch_move = ((pos - center) / 90.0).limit_length(1.0)
    touch_move.y = -touch_move.y

func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= gravity * delta
    elif Input.is_action_just_pressed("jump"):
        velocity.y = jump_velocity
    var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    if touch_move.length() > 0.12:
        input_dir = touch_move
    var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
    if direction:
        velocity.x = direction.x * walk_speed
        velocity.z = direction.z * walk_speed
    else:
        velocity.x = move_toward(velocity.x, 0, walk_speed * 5 * delta)
        velocity.z = move_toward(velocity.z, 0, walk_speed * 5 * delta)
    move_and_slide()
    hunger = maxf(0.0, hunger - delta * 0.025)
    thirst = maxf(0.0, thirst - delta * 0.04)

func collect(item: String, amount: int = 1) -> void:
    inventory[item] = int(inventory.get(item, 0)) + amount
