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

func _find_grass_showcase_position(world: Node3D) -> Vector3:
    # Buscar una zona verde, llana y sin nieve/arena para que la captura
    # muestre la hierba del propio mundo, no una zona de playa o desierto.
    for ring in range(1, 13):
        var step := 18.0 * float(ring)
        for z in range(-240, 241, 18):
            for x in range(-240, 241, 18):
                if Vector2(x, z).length() > step + 26.0 or Vector2(x, z).length() < step - 26.0:
                    continue
                var height: float = world._height_at(float(x), float(z))
                if height < 4.5 or height > 23.0:
                    continue
                var normal: Vector3 = world._terrain_normal_at(float(x), float(z))
                if normal.y < 0.94:
                    continue
                var terrain_color: Color = world._terrain_color_at(float(x), float(z), height, normal)
                var desert_signal := -float(x) / 384.0 + (terrain_color.r - 0.5) * 0.55
                var snow_signal := float(z) / 384.0 + (terrain_color.r - 0.5) * 0.48
                var desert := clampf((desert_signal - 0.02) / 0.46, 0.0, 1.0)
                var snow := clampf((snow_signal - 0.02) / 0.46, 0.0, 1.0) * (1.0 - desert)
                if desert < 0.30 and snow < 0.30:
                    return Vector3(float(x), height + 0.4, float(z))
    return Vector3(0.0, world._height_at(0.0, 0.0) + 0.4, 0.0)

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
    var grass_position := _find_grass_showcase_position(world)
    player.global_position = grass_position
    player.velocity = Vector3.ZERO
    player.rotation = Vector3.ZERO
    player.set_character_body_visible(true)
    if is_instance_valid(player.first_person_arms):
        player.first_person_arms.visible = false
    var held_tool: Node3D = world.get("held_tool_root")
    if is_instance_valid(held_tool):
        held_tool.visible = false
    # Vista externa temporal solo para la captura: enseña el personaje 3D
    # completo y la hierba real del escenario. La cámara del juego sigue siendo FPS.
    player.camera.fov = 58.0
    player.camera.global_position = player.global_position + Vector3(3.8, 2.6, 5.6)
    player.camera.look_at(player.global_position + Vector3(0.0, 0.95, -0.5), Vector3.UP)
    player.camera.current = true
    for i in range(24):
        await process_frame
    print("PLAYER_GRASS_CAPTURE:", player.global_position, " CAMERA:", player.camera.global_position,
        " GRASS_SYSTEM:", world.has_node("GrassSystem"))

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
