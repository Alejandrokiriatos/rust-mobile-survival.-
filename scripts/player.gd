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
var pickaxe_unlocked := false
var torch_unlocked := false
var equipped_tool := "stone"
var inventory := {"Madera": 0, "Piedra": 0, "Fibra": 0, "Comida": 0, "Agua": 0}
var health := 100.0
var hunger := 100.0
var thirst := 100.0
var stamina := 100.0
var crouching := false
var character_visual: Node3D
var character_animation: AnimationPlayer
var current_character_animation := ""
var first_person_arms: Node3D
@export_range(0, 7, 1) var character_skin_index := 0
const CHARACTER_SCENES := [
    "res://assets/characters/laboratory/SKIN_01.glb",
    "res://assets/characters/laboratory/SKIN_02.glb",
    "res://assets/characters/laboratory/SKIN_03.glb",
    "res://assets/characters/laboratory/SKIN_04.glb",
    "res://assets/characters/laboratory/SKIN_05.glb",
    "res://assets/characters/laboratory/SKIN_06.glb",
    "res://assets/characters/laboratory/SKIN_07.glb",
    "res://assets/characters/laboratory/SKIN_08.glb"
]
const CHARACTER_SOURCE_HEIGHTS := [
    1.812841, 1.671143, 1.871541, 1.675562,
    1.743802, 1.724337, 1.823005, 1.700326
]
const CHARACTER_TARGET_HEIGHT := 1.75

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
    camera.far = 320.0
    # Ángulo inicial ligeramente hacia el suelo: en Godot, el signo negativo
    # inclina la cámara hacia abajo y muestra terreno y vegetación al aparecer.
    camera.rotation.x = deg_to_rad(-12.0)
    camera.current = true
    add_child(camera)
    _build_first_person_arms()
    floor_snap_length = 0.35
    floor_max_angle = deg_to_rad(48.0)
    _load_character_visual()
    add_to_group("player")


func _load_character_visual() -> void:
    set_character_skin(character_skin_index)

func set_character_skin(index: int) -> void:
    if index < 0 or index >= CHARACTER_SCENES.size():
        push_warning("Índice de apariencia fuera de rango: " + str(index))
        return
    character_skin_index = index
    if is_instance_valid(character_visual):
        character_visual.queue_free()
    character_visual = null
    character_animation = null
    current_character_animation = ""

    var scene_path: String = CHARACTER_SCENES[index]
    if not ResourceLoader.exists(scene_path):
        push_warning("No se encontró el personaje 3D del laboratorio: " + scene_path)
        return
    var packed := ResourceLoader.load(scene_path) as PackedScene
    if packed == null:
        push_warning("Godot no pudo importar el GLB del personaje: " + scene_path)
        return
    character_visual = packed.instantiate() as Node3D
    if character_visual == null:
        push_warning("La escena del personaje no tiene un nodo Node3D raíz.")
        return
    character_visual.name = "LaboratoryCharacter_%02d" % (index + 1)
    var normalized_scale := CHARACTER_TARGET_HEIGHT / float(CHARACTER_SOURCE_HEIGHTS[index])
    character_visual.scale = Vector3.ONE * normalized_scale
    add_child(character_visual)
    # El cuerpo se oculta en FPS para evitar que la cabeza atraviese la cámara;
    # las ocho apariencias siguen disponibles y sus animaciones siguen activas.
    character_visual.visible = false
    character_animation = _find_character_animation(character_visual)
    if character_animation == null:
        push_warning("El modelo se importó, pero no contiene AnimationPlayer.")
    else:
        _play_character_animation("Idle")
    print("CHARACTER_READY: SKIN_%02d height=%.2f" % [index + 1, CHARACTER_TARGET_HEIGHT])

func _find_character_animation(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := _find_character_animation(child)
        if found != null:
            return found
    return null

func _play_character_animation(preferred: String) -> void:
    if character_animation == null:
        return
    var selected := ""
    for animation_name in character_animation.get_animation_list():
        if String(animation_name).to_lower() == preferred.to_lower():
            selected = String(animation_name)
            break
    if selected.is_empty():
        var needle := preferred.to_lower()
        for animation_name in character_animation.get_animation_list():
            if String(animation_name).to_lower().contains(needle):
                selected = String(animation_name)
                break
    if selected.is_empty() or selected == current_character_animation:
        return
    current_character_animation = selected
    character_animation.play(selected)

func _update_character_animation() -> void:
    if character_animation == null:
        return
    if not is_on_floor():
        _play_character_animation("Jump")
    elif crouching:
        _play_character_animation("Crouch idle")
    elif Vector2(velocity.x, velocity.z).length() > 0.35:
        _play_character_animation("Run" if sprinting else "Walk")
    else:
        _play_character_animation("Idle")

func set_character_body_visible(visible_value: bool) -> void:
    if is_instance_valid(character_visual):
        character_visual.visible = visible_value

func _build_first_person_arms() -> void:
    first_person_arms = Node3D.new()
    first_person_arms.name = "FirstPersonArms"
    camera.add_child(first_person_arms)

    var sleeve := StandardMaterial3D.new()
    sleeve.albedo_color = Color(0.22, 0.29, 0.19)
    sleeve.roughness = 0.94
    var skin := StandardMaterial3D.new()
    skin.albedo_color = Color(0.66, 0.43, 0.31)
    skin.roughness = 0.9

    # Brazos de bajo poligonaje, unidos a la cámara y animados con el movimiento
    # de las herramientas. No sustituyen el rig del personaje: son su vista de manos.
    _add_arm_segment(first_person_arms, Vector3(-0.37, -0.25, -0.25), Vector3(-0.22, -0.37, -0.48), 0.115, sleeve)
    _add_arm_segment(first_person_arms, Vector3(-0.22, -0.37, -0.48), Vector3(0.27, -0.42, -0.70), 0.078, skin)
    _add_arm_segment(first_person_arms, Vector3(0.36, -0.25, -0.25), Vector3(0.40, -0.37, -0.49), 0.115, sleeve)
    _add_arm_segment(first_person_arms, Vector3(0.40, -0.37, -0.49), Vector3(0.43, -0.44, -0.70), 0.078, skin)
    _add_arm_palm(first_person_arms, Vector3(0.27, -0.42, -0.72), skin)
    _add_arm_palm(first_person_arms, Vector3(0.43, -0.44, -0.73), skin)

func _add_arm_segment(parent: Node3D, start: Vector3, finish: Vector3, radius: float, material: Material) -> void:
    var direction := finish - start
    var length := direction.length()
    if length < 0.001:
        return
    var capsule := CapsuleMesh.new()
    capsule.radius = radius
    capsule.height = length + radius * 2.0
    capsule.radial_segments = 8
    capsule.rings = 3
    var arm := MeshInstance3D.new()
    arm.mesh = capsule
    arm.material_override = material
    arm.position = (start + finish) * 0.5
    arm.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
    arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(arm)

func _add_arm_palm(parent: Node3D, palm_position: Vector3, material: Material) -> void:
    var palm_mesh := SphereMesh.new()
    palm_mesh.radius = 0.092
    palm_mesh.height = 0.16
    palm_mesh.radial_segments = 10
    palm_mesh.rings = 5
    var palm := MeshInstance3D.new()
    palm.mesh = palm_mesh
    palm.material_override = material
    palm.position = palm_position
    palm.scale = Vector3(0.82, 0.72, 1.12)
    palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(palm)

func _update_first_person_arms(delta: float) -> void:
    if not is_instance_valid(first_person_arms):
        return
    var movement := Vector2(velocity.x, velocity.z).length()
    var strength := clampf(movement / maxf(walk_speed, 0.1), 0.0, 1.0)
    var phase := float(Time.get_ticks_msec()) * 0.008
    first_person_arms.position.y = sin(phase) * 0.012 * strength
    first_person_arms.rotation.z = sin(phase * 0.5) * 0.018 * strength

func set_sprinting(enabled: bool) -> void:
    sprinting = enabled and stamina > 1.0

func set_crouching(enabled: bool) -> void:
    crouching = enabled
    if is_instance_valid(camera):
        camera.position.y = 1.05 if crouching else 1.58

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
    if sprinting and not crouching and input_dir.length_squared() > 0.01:
        stamina = maxf(0.0, stamina - delta * 18.0)
        if stamina <= 0.0:
            sprinting = false
    else:
        stamina = minf(100.0, stamina + delta * 12.0)
    var target_speed := walk_speed * 0.48 if crouching else (sprint_speed if sprinting and stamina > 0.0 else walk_speed)
    var target_velocity := direction * target_speed
    var acceleration := ground_acceleration if is_on_floor() else air_acceleration
    velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
    velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
    move_and_slide()
    _update_character_animation()
    _update_first_person_arms(delta)

    hunger = maxf(0.0, hunger - delta * 0.018)
    thirst = maxf(0.0, thirst - delta * 0.032)
    if hunger <= 0.0 or thirst <= 0.0:
        take_damage(delta * (1.0 if hunger <= 0.0 and thirst <= 0.0 else 0.45))

func collect(item: String, amount: int = 1) -> void:
    inventory[item] = int(inventory.get(item, 0)) + amount
