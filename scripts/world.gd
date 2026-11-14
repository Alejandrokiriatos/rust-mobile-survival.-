extends Node3D

const PLAYER_SCRIPT = preload("res://scripts/player.gd")
const RESOURCE_SCRIPT = preload("res://scripts/resource_node.gd")
const WORLD_SIZE := 512.0
const CHUNK_COUNT := 4
const CHUNK_SIZE := WORLD_SIZE / CHUNK_COUNT
const CHUNK_SEGMENTS := 64
const WATER_LEVEL := -2.5
const RESOURCE_COUNTS := {"Madera": 88, "Piedra": 58, "Fibra": 76}
const NATURE_PATH := "res://assets/kenney/nature-kit/"

var player: SurvivalPlayer
var hud: Label
var message: Label
var interact_button: Button
var terrain_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var asset_scenes: Dictionary = {}
var rng := RandomNumberGenerator.new()

func _ready() -> void:
    rng.randomize()
    _configure_noise()
    _load_nature_pack()
    _make_environment()
    _make_large_terrain()
    _make_water()
    _make_player()
    _make_hud()
    _scatter_resources()

func _process(_delta: float) -> void:
    if is_instance_valid(player) and is_instance_valid(hud):
        hud.text = "VIDA %d   HAMBRE %d   SED %d\nMadera %d   Piedra %d   Fibra %d" % [
            roundi(player.health), roundi(player.hunger), roundi(player.thirst),
            player.inventory["Madera"], player.inventory["Piedra"], player.inventory["Fibra"]
        ]

func _configure_noise() -> void:
    terrain_noise.seed = 48123
    terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
    terrain_noise.frequency = 0.006
    terrain_noise.fractal_octaves = 4
    terrain_noise.fractal_gain = 0.48
    detail_noise.seed = 91827
    detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
    detail_noise.frequency = 0.025
    detail_noise.fractal_octaves = 2

func _load_nature_pack() -> void:
    var files := {
        "Madera": ["tree_default.glb", "tree_oak.glb"],
        "Piedra": ["rock_largeA.glb", "rock_smallA.glb"],
        "Fibra": ["plant_bush.glb", "plant_bushLarge.glb"]
    }
    for kind in files:
        var available: Array[PackedScene] = []
        for filename in files[kind]:
            var path := NATURE_PATH + filename
            if ResourceLoader.exists(path):
                var resource = load(path)
                if resource is PackedScene:
                    available.append(resource)
        asset_scenes[kind] = available
    var total := 0
    for kind in asset_scenes:
        total += asset_scenes[kind].size()
    if total == 0:
        push_warning("Falta Kenney Nature Kit. Consulta assets/kenney/nature-kit/README.txt.")
    else:
        print("Kenney Nature Kit: ", total, " modelos cargados.")

func _make_environment() -> void:
    var env := WorldEnvironment.new()
    var e := Environment.new()
    e.background_mode = Environment.BG_COLOR
    e.background_color = Color(0.48, 0.68, 0.82)
    e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    e.ambient_light_color = Color(0.72, 0.79, 0.9)
    e.ambient_light_energy = 0.75
    e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.environment = e
    add_child(env)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -32, 0)
    sun.light_energy = 1.0
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 75.0
    add_child(sun)

func _height_at(x: float, z: float) -> float:
    var edge := maxf(absf(x), absf(z)) / (WORLD_SIZE * 0.49)
    var land_shape := pow(clampf(1.0 - edge, 0.0, 1.0), 1.55)
    var broad := terrain_noise.get_noise_2d(x, z) * 9.0
    var detail := detail_noise.get_noise_2d(x, z) * 1.4
    return broad + detail + land_shape * 18.0 - 4.0

func _make_large_terrain() -> void:
    var terrain_material := StandardMaterial3D.new()
    terrain_material.vertex_color_use_as_albedo = true
    terrain_material.roughness = 1.0
    terrain_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    for chunk_z in range(CHUNK_COUNT):
        for chunk_x in range(CHUNK_COUNT):
            _make_terrain_chunk(chunk_x, chunk_z, terrain_material)

func _make_terrain_chunk(chunk_x: int, chunk_z: int, material: StandardMaterial3D) -> void:
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var colors := PackedColorArray()
    var indices := PackedInt32Array()
    var origin_x := -WORLD_SIZE * 0.5 + float(chunk_x) * CHUNK_SIZE
    var origin_z := -WORLD_SIZE * 0.5 + float(chunk_z) * CHUNK_SIZE
    var step := CHUNK_SIZE / float(CHUNK_SEGMENTS)
    for z in range(CHUNK_SEGMENTS + 1):
        for x in range(CHUNK_SEGMENTS + 1):
            var px := origin_x + float(x) * step
            var pz := origin_z + float(z) * step
            var h := _height_at(px, pz)
            vertices.append(Vector3(px, h, pz))
            var slope_x := _height_at(px + step, pz) - _height_at(px - step, pz)
            var slope_z := _height_at(px, pz + step) - _height_at(px, pz - step)
            normals.append(Vector3(-slope_x, step * 2.0, -slope_z).normalized())
            var edge_distance := maxf(absf(px), absf(pz)) / (WORLD_SIZE * 0.49)
            var tint: Color
            if h < WATER_LEVEL + 1.2:
                tint = Color(0.67, 0.59, 0.39)
            elif h > 11.0:
                tint = Color(0.43, 0.46, 0.39)
            elif edge_distance > 0.78:
                tint = Color(0.68, 0.62, 0.42)
            else:
                tint = Color(0.30, 0.48, 0.25)
            colors.append(tint)
    var row := CHUNK_SEGMENTS + 1
    for z in range(CHUNK_SEGMENTS):
        for x in range(CHUNK_SEGMENTS):
            var a := z * row + x
            var b := a + 1
            var c := a + row
            var d := c + 1
            indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    mesh.surface_set_material(0, material)
    var terrain := MeshInstance3D.new()
    terrain.name = "Terrain_%02d_%02d" % [chunk_x, chunk_z]
    terrain.mesh = mesh
    add_child(terrain)
    var body := StaticBody3D.new()
    body.name = "TerrainCollision_%02d_%02d" % [chunk_x, chunk_z]
    var collision := CollisionShape3D.new()
    collision.shape = mesh.create_trimesh_shape()
    body.add_child(collision)
    add_child(body)

func _make_water() -> void:
    var water := MeshInstance3D.new()
    var water_mesh := PlaneMesh.new()
    water_mesh.size = Vector2(WORLD_SIZE + 80.0, WORLD_SIZE + 80.0)
    water.mesh = water_mesh
    water.position.y = WATER_LEVEL
    var water_material := StandardMaterial3D.new()
    water_material.albedo_color = Color(0.08, 0.34, 0.49, 0.88)
    water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    water_material.roughness = 0.32
    water.material_override = water_material
    add_child(water)

func _make_player() -> void:
    player = SurvivalPlayer.new()
    player.position = Vector3(0.0, _height_at(0.0, 0.0) + 2.5, 0.0)
    add_child(player)

func _make_hud() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    hud = Label.new()
    hud.position = Vector2(18, 14)
    hud.add_theme_font_size_override("font_size", 18)
    hud.add_theme_color_override("font_color", Color.WHITE)
    layer.add_child(hud)
    message = Label.new()
    message.position = Vector2(18, 70)
    message.add_theme_font_size_override("font_size", 17)
    message.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
    layer.add_child(message)
    var asset_status := Label.new()
    asset_status.position = Vector2(18, 108)
    asset_status.add_theme_font_size_override("font_size", 14)
    asset_status.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
    asset_status.text = "Kenney Nature Kit: %s" % ("OK" if _has_all_resource_models() else "FALTA INSTALAR")
    layer.add_child(asset_status)
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

func _has_all_resource_models() -> bool:
    for kind in ["Madera", "Piedra", "Fibra"]:
        if asset_scenes.get(kind, []).is_empty():
            return false
    return true

func _scatter_resources() -> void:
    if not _has_all_resource_models():
        message.text = "Instala Kenney Nature Kit para activar los recursos 3D."
        return
    for kind in RESOURCE_COUNTS:
        var created := 0
        var attempts := 0
        while created < RESOURCE_COUNTS[kind] and attempts < RESOURCE_COUNTS[kind] * 8:
            attempts += 1
            var x := rng.randf_range(-WORLD_SIZE * 0.46, WORLD_SIZE * 0.46)
            var z := rng.randf_range(-WORLD_SIZE * 0.46, WORLD_SIZE * 0.46)
            if Vector2(x, z).length() < 16.0:
                continue
            var y := _height_at(x, z)
            if y < WATER_LEVEL + 1.0:
                continue
            _create_resource(Vector3(x, y, z), kind)

func _create_resource(pos: Vector3, kind: String) -> void:
    var options: Array = asset_scenes[kind]
    var model_scene: PackedScene = options[rng.randi_range(0, options.size() - 1)]
    var node: ResourceNode = RESOURCE_SCRIPT.new()
    node.resource_type = kind
    node.amount = 4 if kind == "Madera" else 3
    node.model_scene = model_scene
    node.position = pos
    if kind == "Madera":
        node.model_scale = Vector3.ONE * 4.0
    elif kind == "Piedra":
        node.model_scale = Vector3.ONE * 3.6
    else:
        node.model_scale = Vector3.ONE * 3.0
    add_child(node)

func _try_harvest() -> void:
    if not is_instance_valid(player):
        return
    var from := player.camera.global_position
    var to := from + -player.camera.global_transform.basis.z * 4.2
    var query := PhysicsRayQueryParameters3D.create(from, to)
    query.exclude = [player.get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if hit and hit.collider.is_in_group("harvestable"):
        message.text = hit.collider.harvest(player)
    else:
        message.text = "Acércate a un árbol, roca o arbusto y apunta."
