extends Node3D

const PLAYER_SCRIPT = preload("res://scripts/player.gd")
const RESOURCE_SCRIPT = preload("res://scripts/resource_node.gd")
var player: SurvivalPlayer
var hud: Label
var message: Label
var interact_button: Button
var noise := FastNoiseLite.new()

func _ready() -> void:
    _make_environment()
    _make_island()
    _make_player()
    _make_hud()
    _scatter_resources()
    set_process(true)

func _process(_delta: float) -> void:
    if is_instance_valid(player) and is_instance_valid(hud):
        hud.text = "VIDA %d   HAMBRE %d   SED %d\nMadera %d   Piedra %d   Fibra %d" % [player.health, player.hunger, player.thirst, player.inventory["Madera"], player.inventory["Piedra"], player.inventory["Fibra"]]

func _make_environment() -> void:
    var env := WorldEnvironment.new()
    var e := Environment.new()
    e.background_mode = Environment.BG_SKY
    e.sky = Sky.new()
    e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    e.ambient_light_color = Color(0.72, 0.79, 0.9)
    e.ambient_light_energy = 0.8
    env.environment = e
    add_child(env)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -32, 0)
    sun.light_energy = 1.15
    sun.shadow_enabled = true
    add_child(sun)

func _make_island() -> void:
    noise.seed = 48123
    noise.frequency = 0.035
    var vertices := PackedVector3Array()
    var indices := PackedInt32Array()
    var colors := PackedColorArray()
    var n := 64
    var extent := 80.0
    for z in range(n + 1):
        for x in range(n + 1):
            var px := (float(x) / n - 0.5) * extent
            var pz := (float(z) / n - 0.5) * extent
            var edge := maxf(absf(px), absf(pz)) / (extent * 0.5)
            var h := noise.get_noise_2d(px, pz) * 3.2 + maxf(0.0, 1.0 - edge) * 2.5 - 1.2
            vertices.append(Vector3(px, h, pz))
            var tint := Color(0.26, 0.55, 0.28) if h > 0.25 else Color(0.72, 0.65, 0.39)
            colors.append(tint)
    for z in range(n):
        for x in range(n):
            var a := z * (n + 1) + x
            var b := a + 1
            var c := a + n + 1
            var d := c + 1
            indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_INDEX] = indices
    arrays[Mesh.ARRAY_COLOR] = colors
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.roughness = 1.0
    mesh.surface_set_material(0, mat)
    var terrain := MeshInstance3D.new()
    terrain.mesh = mesh
    add_child(terrain)
    var body := StaticBody3D.new()
    var shape := CollisionShape3D.new()
    shape.shape = mesh.create_trimesh_shape()
    body.add_child(shape)
    add_child(body)
    var water := MeshInstance3D.new()
    var water_mesh := PlaneMesh.new()
    water_mesh.size = Vector2(180, 180)
    water.mesh = water_mesh
    water.position.y = -1.15
    var water_mat := StandardMaterial3D.new()
    water_mat.albedo_color = Color(0.12, 0.48, 0.68, 0.82)
    water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    water_mat.roughness = 0.25
    water.material_override = water_mat
    add_child(water)

func _make_player() -> void:
    player = SurvivalPlayer.new()
    player.position = Vector3(0, 5, 0)
    add_child(player)

func _make_hud() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    hud = Label.new()
    hud.position = Vector2(18, 16)
    hud.add_theme_font_size_override("font_size", 20)
    hud.add_theme_color_override("font_color", Color.WHITE)
    layer.add_child(hud)
    message = Label.new()
    message.position = Vector2(18, 78)
    message.add_theme_font_size_override("font_size", 18)
    message.add_theme_color_override("font_color", Color(1, 0.9, 0.55))
    layer.add_child(message)
    interact_button = Button.new()
    interact_button.text = "RECOGER"
    interact_button.size = Vector2(130, 58)
    interact_button.anchor_left = 1.0
    interact_button.anchor_right = 1.0
    interact_button.anchor_top = 1.0
    interact_button.anchor_bottom = 1.0
    interact_button.position = Vector2(-155, -95)
    interact_button.pressed.connect(_try_harvest)
    layer.add_child(interact_button)

func _scatter_resources() -> void:
    for i in range(34):
        var x := randf_range(-31, 31)
        var z := randf_range(-31, 31)
        if Vector2(x, z).length() < 5.0:
            continue
        var kind := ["Madera", "Piedra", "Fibra"][randi() % 3]
        _create_resource(Vector3(x, 0.0, z), kind)

func _create_resource(pos: Vector3, kind: String) -> void:
    var node = RESOURCE_SCRIPT.new()
    node.resource_type = kind
    node.amount = 3
    node.position = pos
    var visual := MeshInstance3D.new()
    var material := StandardMaterial3D.new()
    if kind == "Madera":
        var trunk := CylinderMesh.new()
        trunk.top_radius = 0.22
        trunk.bottom_radius = 0.34
        trunk.height = 2.2
        visual.mesh = trunk
        material.albedo_color = Color(0.38, 0.22, 0.11)
        visual.position.y = 1.1
    elif kind == "Piedra":
        var rock := SphereMesh.new()
        rock.radius = 0.65
        rock.height = 1.0
        visual.mesh = rock
        material.albedo_color = Color(0.43, 0.46, 0.48)
        visual.position.y = 0.45
        visual.scale = Vector3(1.2, 0.8, 1.0)
    else:
        var bush := SphereMesh.new()
        bush.radius = 0.65
        bush.height = 1.0
        visual.mesh = bush
        material.albedo_color = Color(0.28, 0.58, 0.24)
        visual.position.y = 0.45
    visual.material_override = material
    node.add_child(visual)
    var collision := CollisionShape3D.new()
    var shape := SphereShape3D.new()
    shape.radius = 0.9
    collision.shape = shape
    collision.position.y = 0.8
    node.add_child(collision)
    add_child(node)

func _try_harvest() -> void:
    var from := player.camera.global_position
    var to := from + -player.camera.global_transform.basis.z * 4.0
    var query := PhysicsRayQueryParameters3D.create(from, to)
    query.exclude = [player.get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if hit and hit.collider.is_in_group("harvestable"):
        message.text = hit.collider.harvest(player)
    else:
        message.text = "Acércate a un recurso y apunta hacia él."
