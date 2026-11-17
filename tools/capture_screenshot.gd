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

    # Segunda vista de inspección: enseña la forma completa de la isla y la distribución del relieve.
    var hud := world.get("control_layer") as CanvasLayer
    if hud != null:
        hud.visible = false
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
