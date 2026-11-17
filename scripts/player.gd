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
var first_person_character_animation: AnimationPlayer
var first_person_hand_attachment: BoneAttachment3D
var current_character_animation := ""
var first_person_arms: Node3D
var arms_action_tween: Tween
var arms_action_active := false
var arms_walk_phase := 0.0
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
    first_person_character_animation = null
    first_person_hand_attachment = null
    for old_arm_child in first_person_arms.get_children():
        old_arm_child.queue_free()
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
    _attach_first_person_model_arms()
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
    if first_person_character_animation != null and first_person_character_animation.has_animation(selected):
        first_person_character_animation.play(selected)

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
    # Los brazos FPS deben salir del GLB real del personaje seleccionado.
    # No crear cápsulas, esferas ni geometría sustitutiva.
    first_person_arms = Node3D.new()
    first_person_arms.name = "FirstPersonArms"
    camera.add_child(first_person_arms)

func _add_arm_segment(_parent: Node3D, _start: Vector3, _finish: Vector3, _radius: float, _material: Material) -> void:
    # Desactivado: los brazos proceden de los modelos SKIN_XX.glb.
    pass

func _add_arm_palm(_parent: Node3D, _palm_position: Vector3, _material: Material) -> void:
    # Desactivado: las manos proceden de los modelos SKIN_XX.glb.
    pass

func _attach_first_person_model_arms() -> void:
    if not is_instance_valid(character_visual):
        return
    # Instanciar el GLB desde su PackedScene original evita duplicar un árbol
    # esquelético vivo (Godot podía perder hijos durante Node.duplicate()).
    var packed := ResourceLoader.load(CHARACTER_SCENES[character_skin_index]) as PackedScene
    if packed == null:
        push_warning("No se pudo volver a instanciar el GLB para los brazos FPS.")
        return
    var arm_model := packed.instantiate() as Node3D
    if arm_model == null:
        push_warning("El GLB no produjo un Node3D para la vista FPS.")
        return
    arm_model.name = "FirstPersonCharacterArms"
    # Vista de brazos ligeramente reducida y adelantada para que no ocupen
    # media pantalla por estar demasiado cerca del plano de cámara.
    arm_model.scale = character_visual.scale * 0.72
    arm_model.position = Vector3(0.0, -1.28 * arm_model.scale.y, -0.62)
    first_person_arms.add_child(arm_model)
    arm_model.visible = true
    first_person_character_animation = _find_character_animation(arm_model)
    _filter_imported_arm_meshes(arm_model)
    if first_person_character_animation == null:
        push_warning("La copia FPS del GLB no contiene AnimationPlayer.")
    else:
        if not first_person_character_animation.animation_finished.is_connected(_on_first_person_animation_finished):
            first_person_character_animation.animation_finished.connect(_on_first_person_animation_finished)
        print("FPS_RIG_ANIMATIONS ", first_person_character_animation.get_animation_list())


func _on_first_person_animation_finished(_animation_name: StringName) -> void:
    if first_person_character_animation == null or current_character_animation.is_empty():
        return
    if first_person_character_animation.has_animation(current_character_animation):
        first_person_character_animation.play(current_character_animation)


func _filter_imported_arm_meshes(root: Node) -> void:
    # El GLB se importa como UNA sola malla skineada llamada SKIN_XX.
    # Separamos sus triángulos mediante los pesos reales de Left/RightArm,
    # ForeArm, Hand y dedos; no se crean piezas ni geometría de sustitución.
    var mesh_nodes: Array[MeshInstance3D] = []
    _collect_mesh_instances(root, mesh_nodes)
    var extracted_count := 0
    for source_node in mesh_nodes:
        if source_node.mesh == null or source_node.skin == null:
            source_node.visible = false
            continue
        var skeleton := source_node.get_node_or_null(source_node.skeleton) as Skeleton3D
        if skeleton == null:
            source_node.visible = false
            push_warning("No se encontró Skeleton3D para " + source_node.name)
            continue
        _ensure_first_person_hand_attachment(skeleton)
        var source_array_mesh := source_node.mesh as ArrayMesh
        if source_array_mesh == null:
            source_node.visible = false
            push_warning("La malla de " + source_node.name + " no es ArrayMesh.")
            continue
        var arms_mesh := _extract_skinned_arms(source_array_mesh, source_node.skin, skeleton)
        source_node.visible = false
        if arms_mesh == null or arms_mesh.get_surface_count() == 0:
            push_warning("No se pudieron extraer triángulos de brazos desde " + source_node.name)
            continue
        var arms_instance := MeshInstance3D.new()
        arms_instance.name = source_node.name + "_FPS_ARMS"
        arms_instance.mesh = arms_mesh
        arms_instance.skin = source_node.skin
        arms_instance.skeleton = source_node.skeleton
        arms_instance.transform = source_node.transform
        arms_instance.layers = source_node.layers
        arms_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        source_node.get_parent().add_child(arms_instance)
        extracted_count += 1
        print("FPS_RIG_EXTRACTED ", arms_instance.get_path(),
            " SURFACES=", arms_mesh.get_surface_count(),
            " TRIANGLES=", _count_mesh_triangles(arms_mesh))
    print("FPS_RIG_EXTRACTION_COMPLETE meshes=", extracted_count)


func _ensure_first_person_hand_attachment(skeleton: Skeleton3D) -> void:
    if is_instance_valid(first_person_hand_attachment):
        return
    var hand_bone_index := skeleton.find_bone("RightHand")
    if hand_bone_index < 0:
        push_warning("El esqueleto GLB no contiene el hueso RightHand.")
        return
    var attachment := BoneAttachment3D.new()
    attachment.name = "FPSRightHandAttachment"
    attachment.bone_idx = hand_bone_index
    skeleton.add_child(attachment)
    first_person_hand_attachment = attachment
    print("FPS_HAND_ATTACHMENT bone=RightHand index=", hand_bone_index)


func get_first_person_hand_attachment() -> BoneAttachment3D:
    if is_instance_valid(first_person_hand_attachment):
        return first_person_hand_attachment
    return null


func _collect_mesh_instances(node: Node, output: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        output.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_mesh_instances(child, output)


func _is_first_person_arm_bone(bone_name: String) -> bool:
    var normalized := bone_name.to_lower().replace("_", "").replace(" ", "")
    # Excluir Shoulder: algunos GLB asignan parte del torso a esos pesos.
    # La vista FPS conserva brazos superiores, antebrazos, manos y dedos.
    return normalized.begins_with("leftarm") \
        or normalized.begins_with("leftforearm") \
        or normalized.begins_with("lefthand") \
        or normalized.begins_with("rightarm") \
        or normalized.begins_with("rightforearm") \
        or normalized.begins_with("righthand")


func _extract_skinned_arms(source: ArrayMesh, skin: Skin, skeleton: Skeleton3D) -> ArrayMesh:
    var arm_bind_indices: Dictionary = {}
    for bind_index in range(skin.get_bind_count()):
        var bind_name := String(skin.get_bind_name(bind_index))
        if bind_name.is_empty():
            var skeleton_bone := skin.get_bind_bone(bind_index)
            if skeleton_bone >= 0 and skeleton_bone < skeleton.get_bone_count():
                bind_name = skeleton.get_bone_name(skeleton_bone)
        if _is_first_person_arm_bone(bind_name):
            arm_bind_indices[bind_index] = true
    if arm_bind_indices.is_empty():
        push_warning("Skin no contiene binds nombrados de brazos/manos.")
        return null
    var bind_report := PackedStringArray()
    for bind_index in arm_bind_indices:
        bind_report.append("%d:%s" % [bind_index, String(skin.get_bind_name(bind_index))])
    print("FPS_RIG_ARM_BINDS ", bind_report)

    var result := ArrayMesh.new()
    var total_kept_triangles := 0
    for surface_index in range(source.get_surface_count()):
        if source.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
            continue
        var arrays := source.surface_get_arrays(surface_index)
        var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var bone_data: Variant = arrays[Mesh.ARRAY_BONES]
        var weight_data: Variant = arrays[Mesh.ARRAY_WEIGHTS]
        if vertices.is_empty() or bone_data == null or weight_data == null:
            continue
        var influences_per_vertex := 8 if bone_data.size() == vertices.size() * 8 else 4
        var vertex_arm_weights := PackedFloat32Array()
        vertex_arm_weights.resize(vertices.size())
        for vertex_index in range(vertices.size()):
            var arm_weight := 0.0
            var base := vertex_index * influences_per_vertex
            for influence in range(influences_per_vertex):
                var palette_index := int(bone_data[base + influence])
                var weight := float(weight_data[base + influence])
                if weight > 0.0 and arm_bind_indices.has(palette_index):
                    arm_weight += weight
            vertex_arm_weights[vertex_index] = arm_weight

        var source_indices := PackedInt32Array()
        var raw_indices: Variant = arrays[Mesh.ARRAY_INDEX]
        if raw_indices is PackedInt32Array:
            source_indices = raw_indices
        if source_indices.is_empty():
            for vertex_index in range(vertices.size()):
                source_indices.append(vertex_index)
        var arm_indices := PackedInt32Array()
        for triangle_start in range(0, source_indices.size() - 2, 3):
            var a := source_indices[triangle_start]
            var b := source_indices[triangle_start + 1]
            var d := source_indices[triangle_start + 2]
            if a >= vertices.size() or b >= vertices.size() or d >= vertices.size():
                continue
            var wa := vertex_arm_weights[a]
            var wb := vertex_arm_weights[b]
            var wd := vertex_arm_weights[d]
            var influenced_vertices := int(wa >= 0.25) + int(wb >= 0.25) + int(wd >= 0.25)
            var average_arm_weight := (wa + wb + wd) / 3.0
            # Incluye triángulos de transición del hombro sin arrastrar el torso.
            if average_arm_weight >= 0.46 and influenced_vertices >= 2:
                arm_indices.append(a)
                arm_indices.append(b)
                arm_indices.append(d)
        if arm_indices.is_empty():
            continue

        var arm_arrays: Array = []
        arm_arrays.resize(Mesh.ARRAY_MAX)
        for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT,
            Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2,
            Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
            arm_arrays[channel] = arrays[channel]
        arm_arrays[Mesh.ARRAY_INDEX] = arm_indices
        var flags := 0
        if influences_per_vertex == 8:
            flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
        result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arm_arrays, [], {}, flags)
        var new_surface_index := result.get_surface_count() - 1
        result.surface_set_name(new_surface_index, source.surface_get_name(surface_index))
        total_kept_triangles += arm_indices.size() / 3
    if total_kept_triangles == 0:
        return null
    return result


func _count_mesh_triangles(mesh: Mesh) -> int:
    var total := 0
    for surface_index in range(mesh.get_surface_count()):
        total += mesh.surface_get_array_index_len(surface_index) / 3
    return total


func _update_first_person_arms(delta: float) -> void:
    if not is_instance_valid(first_person_arms) or arms_action_active:
        return
    var movement := Vector2(velocity.x, velocity.z).length()
    var strength := clampf(movement / maxf(walk_speed, 0.1), 0.0, 1.0)
    arms_walk_phase += delta * (10.5 if sprinting else 7.2)
    var walk_x := sin(arms_walk_phase * 0.5) * 0.018 * strength
    var walk_y := absf(cos(arms_walk_phase)) * 0.035 * strength
    var crouch_offset := Vector3(0.0, -0.055, 0.025) if crouching else Vector3.ZERO
    var idle_breath := sin(float(Time.get_ticks_msec()) * 0.0018) * 0.004
    first_person_arms.position = Vector3(walk_x, walk_y + idle_breath, 0.0) + crouch_offset
    first_person_arms.rotation_degrees = Vector3(-2.0 * strength, 0.0, sin(arms_walk_phase * 0.5) * 1.8 * strength)

func play_first_person_action(action: String) -> void:
    if not is_instance_valid(first_person_arms):
        return
    if arms_action_tween != null and arms_action_tween.is_running():
        arms_action_tween.kill()
    arms_action_active = true
    var target_rotation := Vector3(-18.0, 0.0, 10.0)
    var target_position := Vector3(0.0, -0.10, -0.06)
    var windup := 0.10
    var impact := 0.11
    match action:
        "chop":
            target_rotation = Vector3(-48.0, 0.0, 24.0)
            target_position = Vector3(0.03, -0.18, 0.08)
            windup = 0.22
            impact = 0.12
        "mine":
            target_rotation = Vector3(-42.0, -8.0, -18.0)
            target_position = Vector3(-0.02, -0.16, 0.07)
            windup = 0.20
        "shoot":
            target_rotation = Vector3(9.0, 0.0, 0.0)
            target_position = Vector3(0.0, 0.035, 0.12)
            windup = 0.045
            impact = 0.055
        "reload":
            target_rotation = Vector3(-12.0, 8.0, -12.0)
            target_position = Vector3(0.0, -0.08, 0.06)
            windup = 0.28
            impact = 0.22
        "punch":
            target_rotation = Vector3(-24.0, 0.0, -18.0)
            target_position = Vector3(0.0, -0.08, -0.12)
        "jump":
            target_rotation = Vector3(7.0, 0.0, 0.0)
            target_position = Vector3(0.0, 0.05, -0.02)
        _:
            target_rotation = Vector3(-12.0, 0.0, 8.0)

    # Los GLB incluyen clips específicos para puñetazo, disparo y recarga.
    # Usarlos en el rig FPS mantiene el movimiento en los huesos reales.
    var action_clip := ""
    match action:
        "punch":
            action_clip = "Punch"
        "shoot":
            action_clip = "Rifle fire (single)"
        "reload":
            action_clip = "Rifle reload"
        "jump":
            action_clip = "Jump start"
    if not action_clip.is_empty() and first_person_character_animation != null:
        if first_person_character_animation.has_animation(action_clip):
            first_person_character_animation.play(action_clip)

    arms_action_tween = create_tween()
    arms_action_tween.tween_property(first_person_arms, "rotation_degrees", target_rotation, windup).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
    arms_action_tween.parallel().tween_property(first_person_arms, "position", target_position, windup)
    arms_action_tween.tween_property(first_person_arms, "rotation_degrees", Vector3.ZERO, impact).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    arms_action_tween.parallel().tween_property(first_person_arms, "position", Vector3.ZERO, impact)
    arms_action_tween.tween_callback(func(): arms_action_active = false)

func play_shoot_animation() -> void:
    play_first_person_action("shoot")

func set_sprinting(enabled: bool) -> void:
    sprinting = enabled and stamina > 1.0

func set_crouching(enabled: bool) -> void:
    crouching = enabled
    if is_instance_valid(camera):
        var camera_tween := create_tween()
        camera_tween.tween_property(camera, "position:y", 1.05 if crouching else 1.58, 0.16)
    if is_instance_valid(first_person_arms) and not arms_action_active:
        var crouch_tween := create_tween()
        crouch_tween.tween_property(first_person_arms, "position:y", -0.055 if crouching else 0.0, 0.16)

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
        play_first_person_action("jump")

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
