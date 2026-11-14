extends Node3D

const PLAYER_SCRIPT = preload("res://scripts/player.gd")
const RESOURCE_SCRIPT = preload("res://scripts/resource_node.gd")
const JOYSTICK_SCRIPT = preload("res://scripts/mobile_joystick.gd")
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
var control_layer: CanvasLayer
var mobile_joystick: MobileJoystick
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
        "Fibra": ["plant_bush.glb", "grass.glb"]
    }
    for kind in files:
        var available: Array[PackedScene] = []
        for filename in files[kind]:
            var path: String = NATURE_PATH + str(filename)
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
    e.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sky_material := ProceduralSkyMaterial.new()
    sky_material.sky_top_color = Color(0.16, 0.38, 0.62)
    sky_material.sky_horizon_color = Color(0.62, 0.78, 0.88)
    sky_material.ground_bottom_color = Color(0.12, 0.19, 0.14)
    sky_material.ground_horizon_color = Color(0.48, 0.59, 0.48)
    sky.sky_material = sky_material
    e.sky = sky
    e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    e.ambient_light_color = Color(0.72, 0.79, 0.9)
    e.ambient_light_energy = 0.75
    e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    e.fog_enabled = true
    e.fog_light_color = Color(0.58, 0.72, 0.78)
    e.fog_density = 0.0012
    e.fog_sky_affect = 0.65
    env.environment = e
    add_child(env)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -32, 0)
    sun.light_energy = 1.0
    sun.shadow_enabled = true
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
    sun.directional_shadow_max_distance = 65.0
    sun.directional_shadow_fade_start = 0.8
    add_child(sun)

func _height_at(x: float, z: float) -> float:
    var radial_distance := Vector2(x, z).length()
    var edge := radial_distance / (WORLD_SIZE * 0.485)
    var land_shape := pow(clampf(1.0 - edge, 0.0, 1.0), 1.38)
    var broad := terrain_noise.get_noise_2d(x, z) * 5.0
    var detail := detail_noise.get_noise_2d(x, z) * 0.8
    var base_height := broad + detail + land_shape * 17.0 - 5.0
    # Meseta de inicio suave: evita aparecer en una pendiente sin crear una plataforma abrupta.
    var spawn_blend := smoothstep(0.0, 52.0, radial_distance)
    return lerpf(4.0, base_height, spawn_blend)

func _make_terrain_shader() -> Shader:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
void fragment() {
    float slope = 1.0 - clamp(dot(normalize(world_normal), vec3(0.0, 1.0, 0.0)), 0.0, 1.0);
    float n = hash21(floor(world_position.xz * 0.32));
    float height = world_position.y;
    vec3 grass_dark = vec3(0.105, 0.235, 0.105);
    vec3 grass_light = vec3(0.19, 0.34, 0.145);
    vec3 sand = vec3(0.55, 0.47, 0.30);
    vec3 rock = vec3(0.34, 0.35, 0.32);
    vec3 grass = mix(grass_dark, grass_light, smoothstep(0.15, 0.85, n));
    float beach = 1.0 - smoothstep(-1.5, 1.2, height);
    float highland = smoothstep(10.0, 18.0, height);
    vec3 base = mix(grass, sand, beach * 0.92);
    base = mix(base, vec3(0.27, 0.34, 0.25), highland * 0.55);
    base = mix(base, rock, smoothstep(0.30, 0.72, slope) * 0.82);
    ALBEDO = base;
    ROUGHNESS = 0.96;
}
"""
    return shader

func _make_large_terrain() -> void:
    var terrain_material := ShaderMaterial.new()
    terrain_material.shader = _make_terrain_shader()
    for chunk_z in range(CHUNK_COUNT):
        for chunk_x in range(CHUNK_COUNT):
            _make_terrain_chunk(chunk_x, chunk_z, terrain_material)

func _make_terrain_chunk(chunk_x: int, chunk_z: int, material: ShaderMaterial) -> void:
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
                tint = Color(0.34, 0.48, 0.30)
            elif edge_distance > 0.78:
                tint = Color(0.68, 0.62, 0.42)
            else:
                tint = Color(0.25, 0.43, 0.20)
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
    player.position = Vector3(0.0, _height_at(0.0, 0.0) + 1.2, 0.0)
    add_child(player)

func _make_hud() -> void:
    control_layer = CanvasLayer.new()
    add_child(control_layer)

    var hud_panel := Panel.new()
    hud_panel.position = Vector2(12, 10)
    hud_panel.size = Vector2(350, 92)
    var panel_style := StyleBoxFlat.new()
    panel_style.bg_color = Color(0.035, 0.07, 0.055, 0.78)
    panel_style.set_corner_radius_all(12)
    panel_style.set_content_margin_all(10)
    hud_panel.add_theme_stylebox_override("panel", panel_style)
    control_layer.add_child(hud_panel)

    hud = Label.new()
    hud.position = Vector2(22, 18)
    hud.add_theme_font_size_override("font_size", 17)
    hud.add_theme_color_override("font_color", Color(0.95, 0.98, 0.91))
    hud_panel.add_child(hud)

    message = Label.new()
    message.position = Vector2(18, 112)
    message.add_theme_font_size_override("font_size", 16)
    message.add_theme_color_override("font_color", Color(1.0, 0.91, 0.58))
    control_layer.add_child(message)

    _add_hold_button("▲", Vector2(78, -166), "move_forward")
    _add_hold_button("◀", Vector2(20, -110), "move_left")
    _add_hold_button("▼", Vector2(78, -54), "move_back")
    _add_hold_button("▶", Vector2(136, -110), "move_right")
    _add_hold_button("SALTAR", Vector2(-158, -166), "jump", true)

    interact_button = Button.new()
    interact_button.text = "RECOGER"
    interact_button.size = Vector2(138, 58)
    interact_button.anchor_left = 1.0
    interact_button.anchor_right = 1.0
    interact_button.anchor_top = 1.0
    interact_button.anchor_bottom = 1.0
    interact_button.position = Vector2(-158, -100)
    interact_button.add_theme_font_size_override("font_size", 17)
    _style_action_button(interact_button)
    interact_button.pressed.connect(_try_harvest)
    control_layer.add_child(interact_button)

    var look_hint := Label.new()
    look_hint.text = "DESLIZA AQUÍ PARA MIRAR"
    look_hint.anchor_left = 1.0
    look_hint.anchor_right = 1.0
    look_hint.anchor_top = 1.0
    look_hint.anchor_bottom = 1.0
    look_hint.position = Vector2(-300, -30)
    look_hint.size = Vector2(285, 24)
    look_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    look_hint.add_theme_font_size_override("font_size", 12)
    look_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
    control_layer.add_child(look_hint)

func _add_hold_button(label_text: String, offset: Vector2, action: String, wide: bool = false) -> void:
    var button := Button.new()
    button.text = label_text
    button.size = Vector2(58, 54) if not wide else Vector2(138, 54)
    button.anchor_left = 0.0 if offset.x >= 0.0 else 1.0
    button.anchor_right = button.anchor_left
    button.anchor_top = 1.0
    button.anchor_bottom = 1.0
    button.position = offset
    button.add_theme_font_size_override("font_size", 17 if wide else 25)
    _style_action_button(button)
    button.button_down.connect(player.set_mobile_action.bind(action, true))
    button.button_up.connect(player.set_mobile_action.bind(action, false))
    control_layer.add_child(button)

func _add_sprint_button() -> void:
    var button := Button.new()
    button.text = "CORRER"
    button.size = Vector2(138, 48)
    button.anchor_left = 1.0
    button.anchor_right = 1.0
    button.anchor_top = 1.0
    button.anchor_bottom = 1.0
    button.position = Vector2(-158, -232)
    button.add_theme_font_size_override("font_size", 15)
    _style_action_button(button)
    button.button_down.connect(player.set_sprinting.bind(true))
    button.button_up.connect(player.set_sprinting.bind(false))
    control_layer.add_child(button)

func _style_action_button(button: Button) -> void:
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.035, 0.075, 0.065, 0.76)
    normal.border_color = Color(0.72, 0.86, 0.72, 0.85)
    normal.set_border_width_all(2)
    normal.set_corner_radius_all(13)
    button.add_theme_stylebox_override("normal", normal)
    var pressed := normal.duplicate() as StyleBoxFlat
    pressed.bg_color = Color(0.18, 0.36, 0.25, 0.94)
    button.add_theme_stylebox_override("pressed", pressed)
    button.add_theme_color_override("font_color", Color.WHITE)
    button.add_theme_color_override("font_pressed_color", Color(1.0, 0.92, 0.62))

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
