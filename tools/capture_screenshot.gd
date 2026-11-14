extends SceneTree

func _initialize() -> void:
    call_deferred("_capture")

func _capture() -> void:
    var scene := load("res://scenes/main.tscn") as PackedScene
    if scene == null:
        push_error("No se pudo cargar scenes/main.tscn")
        quit(1)
        return
    var instance := scene.instantiate()
    root.add_child(instance)
    for i in range(8):
        await process_frame
    await create_timer(5.0).timeout
    var image := root.get_texture().get_image()
    if image.is_empty():
        push_error("La captura quedó vacía")
        quit(1)
        return
    var output_dir := "user://capture"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
    var output_path := output_dir + "/rust-mobile-survival-preview.png"
    var error := image.save_png(output_path)
    if error != OK:
        push_error("No se pudo guardar la captura: %s" % error)
        quit(1)
        return
    print("CAPTURE_SAVED:", ProjectSettings.globalize_path(output_path))
    quit()
