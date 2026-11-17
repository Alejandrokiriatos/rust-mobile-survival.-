extends SceneTree

func _initialize() -> void:
    call_deferred("_capture")

func _save_view(output_dir: String, filename: String) -> bool:
    var image := root.get_texture().get_image()
    if image.is_empty():
        push_error("La captura quedó vacía: " + filename)
        return false
    var error := image.save_png(output_dir + "/" + filename)
    if error != OK:
        push_error("No se pudo guardar " + filename + ": %s" % error)
        return false
    print("CAPTURE_SAVED:", ProjectSettings.globalize_path(output_dir + "/" + filename))
    return true

func _capture() -> void:
    var scene := load("res://scenes/main.tscn") as PackedScene
    if scene == null:
        push_error("No se pudo cargar scenes/main.tscn")
        quit(1)
        return
    var instance := scene.instantiate()
    root.add_child(instance)
    for i in range(12):
        await process_frame

    var world := instance
    var player := world.get("player") as SurvivalPlayer
    if player == null or not is_instance_valid(player.camera):
        push_error("No se encontró el jugador o su cámara para la captura.")
        quit(1)
        return

    print("MAP_HEIGHTS:", world._height_at(0.0, 0.0), ",", world._height_at(80.0, 0.0), ",", world._height_at(160.0, 0.0), ",", world._height_at(220.0, 0.0))
    print("PLAYER_BEFORE_CAPTURE:", player.global_position)
    world.day_clock = 0.38
    world._update_day_night(0.0)
    # La captura conserva la cámara del juego en primera persona: manos y herramienta visibles.
    player.set_character_body_visible(false)
    if is_instance_valid(player.first_person_arms):
        player.first_person_arms.visible = true
    var held_tool: Node3D = world.get("held_tool_root")
    if is_instance_valid(held_tool):
        held_tool.visible = true
    for i in range(24):
        await process_frame
    print("PLAYER_FIRST_PERSON_CAPTURE:", player.global_position, " CAMERA:", player.camera.global_position,
        " ARMS_VISIBLE:", player.first_person_arms.visible)

    var output_dir := ProjectSettings.globalize_path("user://capture")
    DirAccess.make_dir_recursive_absolute(output_dir)
    if not _save_view(output_dir, "rust-mobile-survival-preview.png"):
        quit(1)
        return

    # Tercera persona: colocamos un personaje real delante de la cámara,
    # mirando al espectador y usando una pose de agarre con los codos flexionados.
    var hud := world.get("control_layer") as CanvasLayer
    if hud != null:
        hud.visible = false

    var character_packed := load("res://assets/characters/laboratory/SKIN_01.glb") as PackedScene
    if character_packed == null:
        push_error("No se pudo cargar SKIN_01.glb para la vista de postura.")
        quit(1)
        return
    var showcase_character := character_packed.instantiate() as Node3D
    if showcase_character == null:
        push_error("El GLB no produjo un personaje Node3D para la vista de postura.")
        quit(1)
        return
    showcase_character.name = "CharacterFacingCameraPreview"
    showcase_character.scale = Vector3.ONE * (1.75 / 1.812841)
    world.add_child(showcase_character)

    var forward := (-player.global_transform.basis.z).normalized()
    var character_position := player.global_position + forward * 3.7
    character_position.y = world._height_at(character_position.x, character_position.z) + 0.025
    showcase_character.global_position = character_position

    var showcase_camera := Camera3D.new()
    showcase_camera.name = "CharacterPosturePreviewCamera"
    showcase_camera.fov = 42.0
    showcase_camera.near = 0.05
    showcase_camera.far = 320.0
    world.add_child(showcase_camera)
    var camera_target := character_position + Vector3(0.0, 0.92, 0.0)
    showcase_camera.global_position = character_position - forward * 5.0 + Vector3(0.0, 1.28, 0.0)
    showcase_camera.look_at(camera_target, Vector3.UP)
    showcase_camera.current = true

    # Estos modelos miran hacia +Z; orientamos el frente del personaje hacia la cámara.
    var to_camera := (showcase_camera.global_position - character_position).normalized()
    showcase_character.rotation.y = atan2(to_camera.x, to_camera.z)

    var showcase_animation := _find_animation_player(showcase_character)
    if showcase_animation != null:
        if showcase_animation.has_animation("Rifle idle (low ready)"):
            showcase_animation.play("Rifle idle (low ready)")
        elif showcase_animation.has_animation("Idle"):
            showcase_animation.play("Idle")

    # Objeto sujeto al hueso real de la mano derecha para que la pose se entienda.
    var showcase_skeleton := _find_skeleton(showcase_character)
    if showcase_skeleton != null:
        var hand_index := showcase_skeleton.find_bone("RightHand")
        if hand_index >= 0:
            var hand_attachment := BoneAttachment3D.new()
            hand_attachment.name = "ShowcaseRightHandAttachment"
            hand_attachment.bone_idx = hand_index
            showcase_skeleton.add_child(hand_attachment)
            var showcase_stone := SurvivalToolModels.create_tool("stone")
            showcase_stone.name = "ShowcaseHeldStone"
            showcase_stone.scale = Vector3.ONE * 0.48
            hand_attachment.add_child(showcase_stone)

    for i in range(36):
        await process_frame
    print("CHARACTER_POSTURE_CAPTURE: position=", showcase_character.global_position,
        " animation=", showcase_animation.current_animation if showcase_animation != null else "none")
    if not _save_view(output_dir, "rust-mobile-survival-character-preview.png"):
        quit(1)
        return

    showcase_character.queue_free()
    showcase_camera.queue_free()
    for i in range(2):
        await process_frame

    # Segunda vista de inspección: enseña la forma completa de la isla y la distribución del relieve.
    var overview := Camera3D.new()
    overview.name = "AutomatedMapOverviewCamera"
    overview.fov = 55.0
    overview.far = 700.0
    world.add_child(overview)
    overview.global_position = Vector3(0.0, 270.0, 330.0)
    overview.look_at(Vector3(0.0, 2.0, 0.0), Vector3.UP)
    overview.current = true
    for i in range(3):
        await process_frame
    if not _save_view(output_dir, "rust-mobile-survival-map.png"):
        quit(1)
        return
    quit()


func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null


func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null
