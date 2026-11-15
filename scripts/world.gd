extends Node3D

class MinimapRadar extends Control:
    var world_ref: Node3D
    var cached_coast := PackedVector2Array()
    var redraw_elapsed := 0.0

    func _process(delta: float) -> void:
        # El contorno se calcula una sola vez y el marcador se refresca a 10 Hz.
        redraw_elapsed += delta
        if redraw_elapsed >= 0.1:
            redraw_elapsed = 0.0
            queue_redraw()

    func _draw() -> void:
        var rect := Rect2(Vector2.ZERO, size)
        draw_rect(rect, Color(0.035, 0.075, 0.065, 0.98), true)
        var center := size * 0.5
        for ring in range(1, 4):
            draw_arc(center, minf(size.x, size.y) * float(ring) / 8.0, 0.0, TAU, 48, Color(0.45, 0.62, 0.48, 0.32), 1.0, true)
        draw_line(Vector2(center.x, 2), Vector2(center.x, size.y - 2), Color(0.45, 0.62, 0.48, 0.22), 1.0)
        draw_line(Vector2(2, center.y), Vector2(size.x - 2, center.y), Color(0.45, 0.62, 0.48, 0.22), 1.0)
        if world_ref == null or not is_instance_valid(world_ref):
            return
        if cached_coast.is_empty():
            for i in range(97):
                var angle := TAU * float(i) / 96.0
                var radius := 256.0
                for step in range(1, 65):
                    var candidate := 256.0 * float(step) / 64.0
                    var sample := Vector2(cos(angle), sin(angle)) * candidate
                    if world_ref._height_at(sample.x, sample.y) <= -1.5:
                        radius = candidate
                        break
                var point := Vector2(cos(angle), sin(angle)) * radius
                cached_coast.append(Vector2(point.x / 512.0 * size.x, point.y / 512.0 * size.y))
        var coast := PackedVector2Array()
        for point in cached_coast:
            coast.append(center + point)
        if coast.size() > 2:
            draw_polyline(coast, Color(0.78, 0.79, 0.58, 0.9), 1.6, true)
        var player_node = world_ref.get("player")
        if player_node != null and is_instance_valid(player_node):
            var pos: Vector3 = player_node.global_position
            var map_pos := center + Vector2(pos.x / 512.0 * size.x, pos.z / 512.0 * size.y)
            map_pos.x = clampf(map_pos.x, 4.0, size.x - 4.0)
            map_pos.y = clampf(map_pos.y, 4.0, size.y - 4.0)
            var heading: float = -player_node.rotation.y - PI * 0.5
            draw_line(map_pos, map_pos + Vector2(cos(heading), sin(heading)) * 9.0, Color(1.0, 0.86, 0.35), 2.0)
            draw_circle(map_pos, 4.5, Color(1.0, 0.82, 0.25))
            draw_arc(map_pos, 7.0, 0.0, TAU, 24, Color(0.08, 0.10, 0.07), 1.5, true)

const PLAYER_SCRIPT = preload("res://scripts/player.gd")
const RESOURCE_SCRIPT = preload("res://scripts/resource_node.gd")
const JOYSTICK_SCRIPT = preload("res://scripts/mobile_joystick.gd")
const ANIMAL_SCRIPT = preload("res://scripts/wild_animal.gd")
const BUILDABLE_SCRIPT = preload("res://scripts/survival_buildable.gd")
const WORLD_SIZE := 512.0
const CHUNK_COUNT := 4
const CHUNK_SIZE := WORLD_SIZE / CHUNK_COUNT
const CHUNK_SEGMENTS := 112
const WATER_LEVEL := -2.5
const RESOURCE_COUNTS := {"Madera": 150, "Piedra": 80, "Fibra": 130}
const NATURE_PATH := "res://assets/kenney/nature-kit/"
const NATURE_MEGA_PATH := "res://assets/quaternius/stylized-nature-megakit/"
const MOBILE_ICON_PATH := "res://assets/ui/mobile-controls/"

var player: SurvivalPlayer
var hud: Label
var message: Label
var interact_button: Button
var control_layer: CanvasLayer
var mobile_joystick: MobileJoystick
var terrain_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var ridge_noise := FastNoiseLite.new()
var coast_noise := FastNoiseLite.new()
var biome_noise := FastNoiseLite.new()
var asset_scenes: Dictionary = {}
var rng := RandomNumberGenerator.new()
var sun_light: DirectionalLight3D
var world_environment: Environment
var day_clock := 0.22
var autosave_timer := 0.0
var resource_remaining_state: Dictionary = {}
var depleted_resource_ids: Dictionary = {}
var craft_panel: PanelContainer
var day_label: Label
var health_bar: ProgressBar
var hunger_bar: ProgressBar
var thirst_bar: ProgressBar
var stamina_bar: ProgressBar
var compass_label: Label
var minimap_coords: Label
var inventory_panel: PanelContainer
var inventory_summary: Label
var hotbar_slots: Array[Button] = []
var selected_hotbar_index := 0
var attack_cooldown := 0.0

func _ready() -> void:
    rng.seed = 48123
    _configure_noise()
    _load_nature_pack()
    _make_environment()
    _make_large_terrain()
    _make_water()
    _make_player()
    _make_hud()
    _scatter_resources()
    _scatter_ground_cover()
    _spawn_wildlife()
    _load_game()

func _unhandled_input(event: InputEvent) -> void:
    if not (event is InputEventKey and event.pressed and not event.echo):
        return
    match event.keycode:
        KEY_1: _select_hotbar_slot(0)
        KEY_2: _select_hotbar_slot(1)
        KEY_3: _select_hotbar_slot(2)
        KEY_4: _select_hotbar_slot(3)
        KEY_5: _select_hotbar_slot(4)
        KEY_6: _select_hotbar_slot(5)
        KEY_I: _toggle_inventory_panel()
        KEY_C: _toggle_craft_panel()
        KEY_ESCAPE:
            if is_instance_valid(inventory_panel) and inventory_panel.visible:
                inventory_panel.visible = false
            elif is_instance_valid(craft_panel) and craft_panel.visible:
                craft_panel.visible = false

func _process(delta: float) -> void:
    attack_cooldown = maxf(0.0, attack_cooldown - delta)
    _update_day_night(delta)
    autosave_timer += delta
    if autosave_timer >= 60.0 and is_instance_valid(player):
        autosave_timer = 0.0
        _save_game(false)
    if not is_instance_valid(player):
        return
    if is_instance_valid(health_bar):
        health_bar.value = player.health
        hunger_bar.value = player.hunger
        thirst_bar.value = player.thirst
        stamina_bar.value = player.stamina
    if is_instance_valid(compass_label):
        var heading := fposmod(rad_to_deg(player.rotation.y) + 360.0, 360.0)
        var directions := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        compass_label.text = "%s   %03d°" % [directions[int(roundi(heading / 45.0)) % 8], roundi(heading)]
    if is_instance_valid(minimap_coords):
        minimap_coords.text = "X %d  Z %d" % [roundi(player.global_position.x), roundi(player.global_position.z)]
    if is_instance_valid(inventory_summary):
        inventory_summary.text = "MADERA     %03d\nPIEDRA       %03d\nFIBRA          %03d\nCOMIDA      %03d\nAGUA           %03d" % [player.inventory["Madera"], player.inventory["Piedra"], player.inventory["Fibra"], player.inventory["Comida"], player.inventory["Agua"]]
    if is_instance_valid(day_label):
        day_label.text = "%s · DÍA %d" % [_time_of_day_name(), int(day_clock) + 1]
func _configure_noise() -> void:
    terrain_noise.seed = 48123
    terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
    terrain_noise.frequency = 0.0048
    terrain_noise.fractal_octaves = 5
    terrain_noise.fractal_gain = 0.52
    terrain_noise.fractal_lacunarity = 2.05
    detail_noise.seed = 91827
    detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
    detail_noise.frequency = 0.021
    detail_noise.fractal_octaves = 3
    detail_noise.fractal_gain = 0.48
    ridge_noise.seed = 27641
    ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
    ridge_noise.frequency = 0.0058
    ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
    ridge_noise.fractal_octaves = 4
    ridge_noise.fractal_gain = 0.52
    coast_noise.seed = 64913
    coast_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
    coast_noise.frequency = 0.012
    coast_noise.fractal_octaves = 3
    biome_noise.seed = 33197
    biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
    biome_noise.frequency = 0.0032
    biome_noise.fractal_octaves = 3

func _load_nature_pack() -> void:
    # Quaternius aporta árboles, rocas y vegetación con texturas; Kenney queda como respaldo ligero.
    var base_path := NATURE_MEGA_PATH
    var files := {
        "Madera": ["CommonTree_1.gltf", "CommonTree_3.gltf", "Pine_1.gltf", "Pine_3.gltf", "TwistedTree_1.gltf", "DeadTree_1.gltf"],
        "Piedra": ["Rock_Medium_1.gltf", "Rock_Medium_2.gltf", "Rock_Medium_3.gltf"],
        "Fibra": ["Bush_Common.gltf", "Bush_Common_Flowers.gltf", "Fern_1.gltf", "Plant_1_Big.gltf", "Grass_Common_Short.gltf"]
    }
    if not ResourceLoader.exists(base_path + "CommonTree_1.gltf"):
        base_path = NATURE_PATH
        files = {
            "Madera": ["tree_default.glb", "tree_oak.glb"],
            "Piedra": ["rock_largeA.glb", "rock_smallA.glb"],
            "Fibra": ["plant_bush.glb", "grass.glb"]
        }
    for kind in files:
        var available: Array[PackedScene] = []
        for filename in files[kind]:
            var path: String = base_path + str(filename)
            if ResourceLoader.exists(path):
                var resource = load(path)
                if resource is PackedScene:
                    available.append(resource)
        asset_scenes[kind] = available
    var total := 0
    for kind in asset_scenes:
        total += asset_scenes[kind].size()
    if total == 0:
        push_warning("No se encontraron modelos de vegetación. Revisa los paquetes CC0.")
    else:
        print("Modelos de naturaleza cargados: ", total)

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
    e.ambient_light_energy = 0.52
    e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    e.fog_enabled = true
    e.fog_light_color = Color(0.58, 0.72, 0.78)
    e.fog_density = 0.00085
    e.fog_sky_affect = 0.65
    env.environment = e
    add_child(env)
    world_environment = e
    sun_light = DirectionalLight3D.new()
    sun_light.rotation_degrees = Vector3(-48, -32, 0)
    sun_light.light_energy = 0.92
    sun_light.shadow_enabled = true
    sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
    sun_light.directional_shadow_max_distance = 65.0
    sun_light.directional_shadow_fade_start = 0.8
    add_child(sun_light)

func _height_at(x: float, z: float) -> float:
    var radial_distance := Vector2(x, z).length()
    # La costa no es un círculo perfecto: el ruido de baja frecuencia crea bahías y salientes.
    var coast_warp := coast_noise.get_noise_2d(x, z) * 0.105
    var edge := radial_distance / (WORLD_SIZE * 0.485) + coast_warp
    var land_shape := pow(clampf(1.0 - edge, 0.0, 1.0), 0.72)
    # Domain warping rompe las crestas paralelas y evita patrones repetitivos en las laderas.
    var warp_x := terrain_noise.get_noise_2d(x + 173.0, z - 91.0) * 17.0
    var warp_z := terrain_noise.get_noise_2d(x - 67.0, z + 211.0) * 17.0
    var warped_x := x + warp_x
    var warped_z := z + warp_z
    var broad := terrain_noise.get_noise_2d(warped_x, warped_z) * 10.5
    var detail := detail_noise.get_noise_2d(warped_x, warped_z) * 1.45
    var ridge_value := maxf(0.0, ridge_noise.get_noise_2d(warped_x, warped_z))
    var ridges := pow(ridge_value, 1.85) * 13.5
    var elevation := 24.0 + broad + detail + ridges
    var base_height := -4.0 + land_shape * elevation
    # Zona de aparición suavizada, no una plataforma plana recortada.
    var spawn_blend := smoothstep(0.0, 34.0, radial_distance)
    return lerpf(6.0, base_height, spawn_blend)

func _terrain_normal_at(x: float, z: float) -> Vector3:
    var sample_step := 1.25
    var slope_x := _height_at(x + sample_step, z) - _height_at(x - sample_step, z)
    var slope_z := _height_at(x, z + sample_step) - _height_at(x, z - sample_step)
    return Vector3(-slope_x, sample_step * 2.0, -slope_z).normalized()

func _terrain_color_at(x: float, z: float, height: float, normal: Vector3) -> Color:
    var biome_mask := clampf(0.5 + biome_noise.get_noise_2d(x, z) * 0.5, 0.0, 1.0)
    return Color(biome_mask, clampf((height + 4.0) / 38.0, 0.0, 1.0), 1.0 - normal.y, 1.0)

func _make_terrain_material() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
uniform sampler2D grass_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D dirt_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D sand_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_tex : source_color, repeat_enable, filter_linear_mipmap;
varying vec3 terrain_position;
varying vec3 terrain_normal;

vec3 triplanar(sampler2D tex, vec3 p, vec3 n, float scale) {
    vec3 weights = pow(abs(normalize(n)), vec3(4.0));
    weights /= max(weights.x + weights.y + weights.z, 0.0001);
    vec3 x_axis = texture(tex, p.zy * scale).rgb;
    vec3 y_axis = texture(tex, p.xz * scale).rgb;
    vec3 z_axis = texture(tex, p.xy * scale).rgb;
    return x_axis * weights.x + y_axis * weights.y + z_axis * weights.z;
}

float hash2(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash2(cell);
    float b = hash2(cell + vec2(1.0, 0.0));
    float c = hash2(cell + vec2(0.0, 1.0));
    float d = hash2(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
    terrain_position = VERTEX;
    terrain_normal = normalize(NORMAL);
}

void fragment() {
    vec3 p = terrain_position;
    vec3 n = normalize(terrain_normal);
    float height = p.y;
    float slope = 1.0 - clamp(n.y, 0.0, 1.0);

    // Proyección triplanar en espacio mundo: evita costuras entre chunks y
    // reduce las bandas y estiramientos visibles en pendientes.
    vec3 grass = triplanar(grass_tex, p, n, 0.014);
    vec3 dirt = triplanar(dirt_tex, p, n, 0.013);
    vec3 sand = triplanar(sand_tex, p, n, 0.012);
    vec3 rock = triplanar(rock_tex, p, n, 0.013);

    // Variación cromática de escala grande para romper la repetición de las
    // muestras sin añadir texturas ni coste de geometría.
    // Ruido interpolado en coordenadas de mundo para crear manchas orgánicas,
    // sin los límites cuadrados que producía el muestreo por celdas.
    float macro_a = value_noise(p.xz * 0.028);
    float macro_b = value_noise(p.xz * 0.071 + vec2(37.2, 11.8));
    float macro_noise = (macro_a - 0.5) * 0.19 + (macro_b - 0.5) * 0.055;
    grass = mix(vec3(0.15, 0.23, 0.12), grass, 0.38);
    dirt = mix(vec3(0.28, 0.22, 0.15), dirt, 0.32);
    sand = mix(vec3(0.48, 0.40, 0.27), sand, 0.28);
    rock = mix(vec3(0.27, 0.28, 0.27), rock, 0.34);
    float biome_mix = smoothstep(0.34, 0.72, COLOR.r) * 0.50;
    float beach_mix = 1.0 - smoothstep(-1.2, 4.2, height);
    float highland_mix = smoothstep(21.0, 35.0, height) * 0.42;
    float rock_mix = max(smoothstep(0.20, 0.62, slope), highland_mix);

    vec3 ground = mix(grass, dirt, biome_mix);
    ground = mix(ground, sand, beach_mix);
    ground = mix(ground, rock, rock_mix);
    ground *= 0.88 + macro_noise;
    ALBEDO = ground;
    ROUGHNESS = 0.97;
    SPECULAR = 0.08;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    var texture_paths := {
        "grass_tex": "res://assets/terrain/ambientcg/Ground013_Color.jpg",
        "dirt_tex": "res://assets/terrain/ambientcg/Ground067_Color.jpg",
        "sand_tex": "res://assets/terrain/ambientcg/Ground090_Color.jpg",
        "rock_tex": "res://assets/terrain/ambientcg/Rock063_Color.jpg"
    }
    for parameter in texture_paths:
        var path: String = texture_paths[parameter]
        if ResourceLoader.exists(path):
            material.set_shader_parameter(parameter, load(path))
        else:
            push_warning("Falta textura PBR de terreno: " + path)
    return material

func _make_large_terrain() -> void:
    var terrain_material := _make_terrain_material()
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
            var height := _height_at(px, pz)
            var normal := _terrain_normal_at(px, pz)
            vertices.append(Vector3(px, height, pz))
            normals.append(normal)
            colors.append(_terrain_color_at(px, pz, height, normal))
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
    terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    add_child(terrain)
    # Colisión de altura dedicada: evita que el jugador atraviese la malla visual
    # y es más eficiente que un trimesh cóncavo para un terreno regular.
    var heightmap := HeightMapShape3D.new()
    heightmap.map_width = int(CHUNK_SIZE) + 1
    heightmap.map_depth = int(CHUNK_SIZE) + 1
    var height_data := PackedFloat32Array()
    for collision_z in range(int(CHUNK_SIZE) + 1):
        for collision_x in range(int(CHUNK_SIZE) + 1):
            height_data.append(_height_at(origin_x + float(collision_x), origin_z + float(collision_z)))
    heightmap.map_data = height_data
    var body := StaticBody3D.new()
    body.name = "TerrainCollision_%02d_%02d" % [chunk_x, chunk_z]
    body.position = Vector3(origin_x + CHUNK_SIZE * 0.5, 0.0, origin_z + CHUNK_SIZE * 0.5)
    var collision := CollisionShape3D.new()
    collision.shape = heightmap
    body.add_child(collision)
    add_child(body)

func _make_water() -> void:
    var water := MeshInstance3D.new()
    water.name = "AnimatedOcean"
    var water_mesh := PlaneMesh.new()
    water_mesh.size = Vector2(WORLD_SIZE + 80.0, WORLD_SIZE + 80.0)
    water_mesh.subdivide_width = 96
    water_mesh.subdivide_depth = 96
    water.mesh = water_mesh
    water.position.y = WATER_LEVEL
    var water_shader := Shader.new()
    water_shader.code = """
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec4 deep_color : source_color = vec4(0.018, 0.105, 0.17, 0.96);
uniform vec4 shallow_color : source_color = vec4(0.10, 0.36, 0.40, 0.94);
uniform float wave_scale = 0.035;
varying vec3 world_pos;
varying float wave_height;

void vertex() {
    vec3 p = VERTEX;
    float t = TIME;
    float phase_a = p.x * 0.052 + t * 0.82;
    float phase_b = p.z * 0.061 - t * 0.63;
    float phase_c = (p.x + p.z) * 0.024 + t * 0.38;
    float wave_a = sin(phase_a) * 0.105;
    float wave_b = cos(phase_b) * 0.075;
    float wave_c = sin(phase_c) * 0.12;
    p.y += wave_a + wave_b + wave_c;
    VERTEX = p;
    float slope_x = cos(phase_a) * 0.105 * 0.052 + cos(phase_c) * 0.12 * 0.024;
    float slope_z = -sin(phase_b) * 0.075 * 0.061 + cos(phase_c) * 0.12 * 0.024;
    NORMAL = normalize(vec3(-slope_x, 1.0, -slope_z));
    world_pos = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
    wave_height = wave_a + wave_b + wave_c;
}

void fragment() {
    vec2 uv_a = world_pos.xz * wave_scale + vec2(TIME * 0.012, -TIME * 0.008);
    vec2 uv_b = world_pos.xz * (wave_scale * 1.73) + vec2(-TIME * 0.009, TIME * 0.006);
    float ripple_a = sin(uv_a.x * 6.28318) * cos(uv_a.y * 6.28318);
    float ripple_b = sin(uv_b.x * 6.28318 + 1.2) * cos(uv_b.y * 6.28318);
    float ripples = ripple_a * 0.5 + ripple_b * 0.5;
    float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.2);
    float foam = smoothstep(0.72, 0.94, ripples + abs(wave_height) * 1.5);
    vec3 water_color = mix(deep_color.rgb, shallow_color.rgb, clamp(0.30 + ripples * 0.10 + fresnel * 0.32, 0.0, 1.0));
    water_color += vec3(0.035, 0.075, 0.078) * smoothstep(0.48, 0.88, ripples);
    water_color = mix(water_color, vec3(0.62, 0.78, 0.72), foam * 0.22);
    ALBEDO = water_color;
    ROUGHNESS = 0.18 + (1.0 - fresnel) * 0.14;
    METALLIC = 0.06;
    SPECULAR = 0.78;
    ALPHA = 0.96;
}
"""
    var water_material := ShaderMaterial.new()
    water_material.shader = water_shader
    water.material_override = water_material
    water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(water)

func _make_player() -> void:
    player = SurvivalPlayer.new()
    player.position = Vector3(0.0, _height_at(0.0, 0.0) + 0.25, 0.0)
    add_child(player)

func _make_hud() -> void:
    control_layer = CanvasLayer.new()
    control_layer.layer = 10
    add_child(control_layer)

    # Panel de supervivencia: compacto, con contraste y valores fáciles de leer.
    var status_panel := PanelContainer.new()
    status_panel.position = Vector2(14, 12)
    status_panel.custom_minimum_size = Vector2(244, 128)
    _style_action_panel(status_panel)
    control_layer.add_child(status_panel)
    var status_stack := VBoxContainer.new()
    status_stack.add_theme_constant_override("separation", 5)
    status_panel.add_child(status_stack)
    var status_title := Label.new()
    status_title.text = "SUPERVIVENCIA  /  v0.4.0"
    status_title.add_theme_font_size_override("font_size", 12)
    status_title.add_theme_color_override("font_color", Color(0.88, 0.94, 0.88))
    status_stack.add_child(status_title)
    health_bar = _make_bar(status_stack, "VIDA", Color(0.91, 0.20, 0.18))
    hunger_bar = _make_bar(status_stack, "HAMBRE", Color(0.94, 0.57, 0.16))
    thirst_bar = _make_bar(status_stack, "SED", Color(0.18, 0.58, 0.94))
    stamina_bar = _make_bar(status_stack, "ENERGÍA", Color(0.25, 0.76, 0.40))

    # Brújula y hora en cápsulas independientes para que no se solapen.
    var compass_panel := PanelContainer.new()
    compass_panel.anchor_left = 0.5
    compass_panel.anchor_right = 0.5
    compass_panel.position = Vector2(-76, 12)
    compass_panel.custom_minimum_size = Vector2(152, 34)
    _style_action_panel(compass_panel)
    control_layer.add_child(compass_panel)
    compass_label = Label.new()
    compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    compass_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    compass_label.add_theme_font_size_override("font_size", 15)
    compass_panel.add_child(compass_label)

    day_label = Label.new()
    day_label.position = Vector2(18, 148)
    day_label.add_theme_font_size_override("font_size", 12)
    day_label.add_theme_color_override("font_color", Color(0.96, 0.91, 0.73))
    control_layer.add_child(day_label)

    # Minimapa con marco sobrio y coordenadas legibles.
    var map := PanelContainer.new()
    map.anchor_left = 1.0
    map.anchor_right = 1.0
    map.position = Vector2(-154, 12)
    map.custom_minimum_size = Vector2(140, 120)
    _style_action_panel(map)
    control_layer.add_child(map)
    var map_col := VBoxContainer.new()
    map_col.add_theme_constant_override("separation", 4)
    map.add_child(map_col)
    var map_title := Label.new()
    map_title.text = "  MAPA  /  LOCALIZACIÓN"
    map_title.add_theme_font_size_override("font_size", 10)
    map_title.add_theme_color_override("font_color", Color(0.77, 0.86, 0.77))
    map_col.add_child(map_title)
    var map_view := MinimapRadar.new()
    map_view.world_ref = self
    map_view.custom_minimum_size = Vector2(116, 70)
    map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    map_view.clip_contents = true
    map_col.add_child(map_view)
    minimap_coords = Label.new()
    minimap_coords.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    minimap_coords.add_theme_font_size_override("font_size", 10)
    map_col.add_child(minimap_coords)

    # Joystick con base y mando de alto contraste.
    mobile_joystick = JOYSTICK_SCRIPT.new()
    mobile_joystick.anchor_left = 0.0
    mobile_joystick.anchor_right = 0.0
    mobile_joystick.anchor_top = 1.0
    mobile_joystick.anchor_bottom = 1.0
    mobile_joystick.position = Vector2(24, -184)
    control_layer.add_child(mobile_joystick)
    player.joystick = mobile_joystick

    # HUD táctil estilo survival/FPS: joystick y sprint a la izquierda;
    # ataque dominante y acciones secundarias agrupadas en la esquina derecha.
    _add_sprint_button()

    var crouch_button := _create_action_button("", Vector2(-166, -204), Vector2(68, 68))
    _set_action_icon(crouch_button, "crouch")
    _add_button_caption(crouch_button, "AGACHAR")
    crouch_button.tooltip_text = "Mantener para agacharse"
    crouch_button.button_down.connect(player.set_crouching.bind(true))
    crouch_button.button_up.connect(player.set_crouching.bind(false))
    control_layer.add_child(crouch_button)

    var jump_button := _create_action_button("", Vector2(-88, -204), Vector2(68, 68))
    _set_action_icon(jump_button, "jump")
    _add_button_caption(jump_button, "SALTAR")
    jump_button.tooltip_text = "Mantener para saltar"
    jump_button.button_down.connect(player.mobile_action.bind("jump", true))
    jump_button.button_up.connect(player.mobile_action.bind("jump", false))
    control_layer.add_child(jump_button)

    interact_button = _create_action_button("", Vector2(-166, -126), Vector2(68, 68))
    _set_action_icon(interact_button, "use")
    _add_button_caption(interact_button, "RECOGER")
    interact_button.tooltip_text = "Recolectar recurso"
    interact_button.pressed.connect(_try_harvest)
    control_layer.add_child(interact_button)

    var attack_button := _create_action_button("", Vector2(-88, -126), Vector2(78, 78))
    _set_action_icon(attack_button, "attack")
    _add_button_caption(attack_button, "ATACAR")
    attack_button.tooltip_text = "Golpear / atacar"
    attack_button.pressed.connect(_try_attack)
    control_layer.add_child(attack_button)

    # Inventario y fabricación quedan como utilidades pequeñas bajo el minimapa.
    var bag := _create_action_button("", Vector2(-116, 148), Vector2(50, 50), true)
    _set_action_icon(bag, "backpack")
    _add_button_caption(bag, "MOCHILA")
    bag.tooltip_text = "Abrir inventario"
    bag.pressed.connect(_toggle_inventory_panel)
    control_layer.add_child(bag)
    var craft := _create_action_button("", Vector2(-58, 148), Vector2(50, 50), true)
    _set_action_icon(craft, "craft")
    _add_button_caption(craft, "FABRICAR")
    craft.tooltip_text = "Abrir fabricación"
    craft.pressed.connect(_toggle_craft_panel)
    control_layer.add_child(craft)

    # Hotbar compacta de seis casillas, translúcida y con selección muy visible.
    var hotbar_panel := PanelContainer.new()
    hotbar_panel.anchor_left = 0.5
    hotbar_panel.anchor_right = 0.5
    hotbar_panel.anchor_top = 1.0
    hotbar_panel.anchor_bottom = 1.0
    hotbar_panel.position = Vector2(-198, -72)
    hotbar_panel.custom_minimum_size = Vector2(396, 64)
    _style_hotbar_tray(hotbar_panel)
    control_layer.add_child(hotbar_panel)
    var hotbar := HBoxContainer.new()
    hotbar.add_theme_constant_override("separation", 4)
    hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
    hotbar_panel.add_child(hotbar)
    var slot_names := ["PIEDRA", "HACHA", "PICO", "MADERA", "FOGATA", "VACÍO"]
    var slot_models := [
        "resource-stone.glb",
        "tool-axe.glb",
        "tool-pickaxe.glb",
        "resource-wood.glb",
        "campfire-pit.glb",
        ""
    ]
    for i in range(6):
        var slot := Button.new()
        slot.text = ""
        slot.custom_minimum_size = Vector2(59, 56)
        slot.clip_contents = true
        _style_hotbar_slot(slot, i == selected_hotbar_index)
        hotbar.add_child(slot)
        hotbar_slots.append(slot)
        slot.pressed.connect(_select_hotbar_slot.bind(i))
        _make_hotbar_preview(slot, slot_models[i], slot_names[i], i + 1)

    _make_craft_panel()
    _make_inventory_panel()

func _add_button_caption(button: Button, caption: String) -> void:
    # Etiqueta siempre visible: los iconos no dependen del reconocimiento del jugador.
    var tag := Label.new()
    tag.text = caption
    tag.anchor_left = 0.0
    tag.anchor_right = 1.0
    tag.anchor_top = 1.0
    tag.anchor_bottom = 1.0
    tag.offset_left = 1.0
    tag.offset_right = -1.0
    tag.offset_top = -19.0
    tag.offset_bottom = -2.0
    tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    tag.add_theme_font_size_override("font_size", 9)
    tag.add_theme_color_override("font_color", Color(1.0, 0.98, 0.91))
    tag.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
    tag.add_theme_constant_override("shadow_offset_x", 1)
    tag.add_theme_constant_override("shadow_offset_y", 1)
    tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
    button.add_child(tag)

func _make_bar(parent: VBoxContainer, caption: String, tint: Color) -> ProgressBar:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 6)
    parent.add_child(row)
    var label := Label.new()
    label.text = caption
    label.custom_minimum_size = Vector2(82, 0)
    label.add_theme_font_size_override("font_size", 10)
    label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.88) if caption == "VIDA" else Color(0.91, 0.94, 0.93))
    row.add_child(label)
    var bar := ProgressBar.new()
    bar.min_value = 0
    bar.max_value = 100
    bar.value = 100
    bar.show_percentage = true
    bar.custom_minimum_size = Vector2(128, 19 if caption == "VIDA" else 16)
    bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.add_theme_font_size_override("font_size", 9)
    bar.add_theme_color_override("font_color", Color.WHITE)
    var track := StyleBoxFlat.new()
    track.bg_color = Color(0.025, 0.035, 0.040, 0.88)
    track.border_color = Color(0.80, 0.86, 0.86, 0.30)
    track.set_border_width_all(1)
    track.set_corner_radius_all(3)
    bar.add_theme_stylebox_override("background", track)
    var fill := StyleBoxFlat.new()
    fill.bg_color = tint
    fill.set_corner_radius_all(4)
    fill.border_color = tint.lightened(0.28)
    fill.set_border_width_all(1)
    fill.shadow_color = tint.darkened(0.45)
    fill.shadow_size = 2
    bar.add_theme_stylebox_override("fill", fill)
    row.add_child(bar)
    return bar

func _style_action_panel(panel: Control) -> void:
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.018, 0.026, 0.024, 0.78)
    style.border_color = Color(0.78, 0.84, 0.78, 0.52)
    style.set_border_width_all(1)
    style.set_corner_radius_all(9)
    style.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
    style.shadow_size = 7
    style.shadow_offset = Vector2(0, 3)
    style.set_content_margin_all(8)
    panel.add_theme_stylebox_override("panel", style)

func _create_action_button(label_text: String, offset: Vector2, button_size: Vector2, compact: bool = false) -> Button:
    var button := Button.new()
    button.text = label_text if compact else ""
    button.size = button_size
    button.anchor_left = 1.0
    button.anchor_right = 1.0
    button.anchor_top = 1.0 if not compact else 0.0
    button.anchor_bottom = button.anchor_top
    button.position = offset
    button.add_theme_font_size_override("font_size", 10 if compact else 11)
    button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
    button.expand_icon = true
    button.focus_mode = Control.FOCUS_NONE
    button.mouse_filter = Control.MOUSE_FILTER_STOP
    _style_action_button(button, true)
    return button

func _add_control_button(label_text: String, offset: Vector2, button_size: Vector2, action: String, _mode: String = "hold", icon_name: String = "") -> void:
    var button := _create_action_button(label_text, offset, button_size)
    if not icon_name.is_empty():
        _set_action_icon(button, icon_name)
    button.button_down.connect(player.mobile_action.bind(action, true))
    button.button_up.connect(player.mobile_action.bind(action, false))
    control_layer.add_child(button)

func _select_hotbar_slot(index: int) -> void:
    if index < 0 or index >= hotbar_slots.size():
        return
    selected_hotbar_index = index
    for i in range(hotbar_slots.size()):
        _style_hotbar_slot(hotbar_slots[i], i == selected_hotbar_index)
    var selected_names := ["PIEDRA", "HACHA", "PICO", "MADERA", "FOGATA", "VACÍO"]
    if is_instance_valid(message):
        message.text = "Seleccionado: " + selected_names[index]

func _make_hotbar_preview(slot: Button, model_file: String, item_name: String, slot_number: int) -> void:
    var preview := SubViewportContainer.new()
    preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    preview.offset_left = 2
    preview.offset_top = 2
    preview.offset_right = -2
    preview.offset_bottom = -15
    preview.stretch = true
    preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
    slot.add_child(preview)

    var viewport := SubViewport.new()
    # Renderizar a 4x el tamaño visible para que los modelos no se vean dentados al reducirlos.
    viewport.size = Vector2i(160, 112)
    viewport.msaa_3d = Viewport.MSAA_2X
    preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    viewport.transparent_bg = true
    viewport.own_world_3d = true
    # Los iconos 3D de la hotbar son estáticos: no deben renderizarse en cada frame.
    viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
    preview.add_child(viewport)

    if not model_file.is_empty():
        var model_path := "res://assets/kenney/survival-kit/" + model_file
        if ResourceLoader.exists(model_path):
            var packed := load(model_path) as PackedScene
            if packed:
                var model := packed.instantiate() as Node3D
                if model:
                    viewport.add_child(model)
                    var bounds := _preview_bounds(model, Transform3D.IDENTITY)
                    if bounds.size.length() > 0.001:
                        var center := bounds.position + bounds.size * 0.5
                        var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
                        model.scale = Vector3.ONE * (1.05 / maxf(longest, 0.01))
                        model.position = -center * model.scale.x
                    var camera := Camera3D.new()
                    camera.position = Vector3(1.45, 1.15, 1.75)
                    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
                    camera.size = 1.62
                    viewport.add_child(camera)
                    camera.look_at(Vector3.ZERO, Vector3.UP)
                    camera.current = true
                    var light := DirectionalLight3D.new()
                    light.rotation_degrees = Vector3(-42, -28, 0)
                    light.light_energy = 1.6
                    viewport.add_child(light)
                    var fill := OmniLight3D.new()
                    fill.position = Vector3(-1.0, 1.0, 0.8)
                    fill.light_energy = 0.65
                    fill.omni_range = 4.0
                    viewport.add_child(fill)

    var number := Label.new()
    number.text = str(slot_number)
    number.position = Vector2(3, 1)
    number.add_theme_font_size_override("font_size", 9)
    number.add_theme_color_override("font_color", Color(1.0, 0.91, 0.62))
    number.mouse_filter = Control.MOUSE_FILTER_IGNORE
    slot.add_child(number)

    var caption := Label.new()
    caption.text = item_name
    caption.anchor_left = 0.0
    caption.anchor_right = 1.0
    caption.anchor_top = 1.0
    caption.anchor_bottom = 1.0
    caption.offset_top = -14
    caption.offset_bottom = -1
    caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    caption.add_theme_font_size_override("font_size", 8)
    caption.add_theme_color_override("font_color", Color(0.96, 0.96, 0.89))
    caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
    slot.add_child(caption)

func _preview_bounds(node: Node, parent_transform: Transform3D) -> AABB:
    var combined := AABB()
    var has_bounds := false
    var current_transform := parent_transform
    if node is Node3D:
        current_transform = parent_transform * (node as Node3D).transform
    if node is MeshInstance3D and (node as MeshInstance3D).mesh:
        var mesh_bounds: AABB = (node as MeshInstance3D).mesh.get_aabb() * current_transform
        combined = mesh_bounds
        has_bounds = true
    for child in node.get_children():
        var child_bounds := _preview_bounds(child, current_transform)
        if child_bounds.size.length() > 0.001:
            if has_bounds:
                combined = combined.merge(child_bounds)
            else:
                combined = child_bounds
                has_bounds = true
    return combined if has_bounds else AABB()

func _style_hotbar_tray(panel: PanelContainer) -> void:
    var tray := StyleBoxFlat.new()
    tray.bg_color = Color(0.012, 0.018, 0.016, 0.66)
    tray.border_color = Color(0.72, 0.80, 0.70, 0.42)
    tray.set_border_width_all(1)
    tray.set_corner_radius_all(11)
    tray.set_content_margin_all(4)
    panel.add_theme_stylebox_override("panel", tray)

func _style_hotbar_slot(button: Button, selected: bool) -> void:
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.26, 0.29, 0.20, 0.92) if selected else Color(0.035, 0.050, 0.045, 0.58)
    normal.border_color = Color(0.91, 0.75, 0.34, 0.95) if selected else Color(0.55, 0.65, 0.56, 0.55)
    normal.set_border_width_all(2 if selected else 1)
    normal.set_corner_radius_all(6)
    normal.set_content_margin_all(4)
    button.add_theme_stylebox_override("normal", normal)
    var pressed := normal.duplicate() as StyleBoxFlat
    pressed.bg_color = Color(0.23, 0.29, 0.22, 1.0)
    button.add_theme_stylebox_override("pressed", pressed)
    button.add_theme_color_override("font_color", Color(0.94, 0.95, 0.89))
    button.add_theme_color_override("font_pressed_color", Color(1.0, 0.88, 0.48))

func _add_crouch_button() -> void:
    var button := _create_action_button("AGACHAR", Vector2(-180, -110), Vector2(66, 66))
    _set_action_icon(button, "crouch")
    button.button_down.connect(player.set_crouching.bind(true))
    button.button_up.connect(player.set_crouching.bind(false))
    control_layer.add_child(button)

func _make_inventory_panel() -> void:
    inventory_panel = PanelContainer.new()
    inventory_panel.anchor_left = 0.5
    inventory_panel.anchor_right = 0.5
    inventory_panel.anchor_top = 0.5
    inventory_panel.anchor_bottom = 0.5
    inventory_panel.position = Vector2(-132, -142)
    inventory_panel.custom_minimum_size = Vector2(264, 284)
    inventory_panel.visible = false
    _style_action_panel(inventory_panel)
    var column := VBoxContainer.new()
    inventory_panel.add_child(column)
    var title := Label.new()
    title.text = "MOCHILA  /  RECURSOS"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 16)
    title.add_theme_color_override("font_color", Color(0.91, 0.94, 0.84))
    column.add_child(title)
    inventory_summary = Label.new()
    inventory_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    inventory_summary.add_theme_font_size_override("font_size", 15)
    inventory_summary.add_theme_color_override("font_color", Color(0.95, 0.93, 0.83))
    column.add_child(inventory_summary)
    var close := Button.new()
    close.text = "CERRAR"
    close.pressed.connect(_toggle_inventory_panel)
    column.add_child(close)
    control_layer.add_child(inventory_panel)

func _toggle_inventory_panel() -> void:
    inventory_panel.visible = not inventory_panel.visible
func _add_hold_button(label_text: String, offset: Vector2, action: String, wide: bool = false) -> void:
    var button := Button.new()
    button.text = label_text
    button.size = Vector2(138, 48) if wide else Vector2(58, 54)
    button.anchor_left = 1.0 if offset.x < 0.0 else 0.0
    button.anchor_right = button.anchor_left
    button.anchor_top = 1.0
    button.anchor_bottom = 1.0
    button.position = offset
    button.add_theme_font_size_override("font_size", 16 if wide else 24)
    _style_action_button(button)
    button.button_down.connect(player.mobile_action.bind(action, true))
    button.button_up.connect(player.mobile_action.bind(action, false))
    control_layer.add_child(button)

func _add_sprint_button() -> void:
    # Sprint queda encima y a la derecha del joystick, en la zona del pulgar izquierdo.
    var button := _create_action_button("", Vector2(142, -260), Vector2(58, 58))
    button.anchor_left = 0.0
    button.anchor_right = 0.0
    button.position = Vector2(142, -260)
    _set_action_icon(button, "sprint")
    button.button_down.connect(player.set_sprinting.bind(true))
    button.button_up.connect(player.set_sprinting.bind(false))
    control_layer.add_child(button)

func _make_craft_panel() -> void:
    craft_panel = PanelContainer.new()
    craft_panel.anchor_left = 1.0
    craft_panel.anchor_right = 1.0
    craft_panel.position = Vector2(-184, 112)
    craft_panel.size = Vector2(170, 230)
    craft_panel.visible = false
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.025, 0.055, 0.045, 0.94)
    style.set_corner_radius_all(12)
    style.set_content_margin_all(8)
    craft_panel.add_theme_stylebox_override("panel", style)
    var list := VBoxContainer.new()
    list.add_theme_constant_override("separation", 6)
    craft_panel.add_child(list)
    var title := Label.new()
    title.text = "SUPERVIVENCIA"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 14)
    list.add_child(title)
    _add_craft_option(list, "HACHA  3M + 2P", _craft_axe)
    _add_craft_option(list, "REFUGIO  12M + 6F", _craft_shelter)
    _add_craft_option(list, "FOGATA  5M + 3P", _craft_campfire)
    _add_craft_option(list, "RACIONES  1M + 3F", _craft_rations)
    _add_craft_option(list, "COMER", _eat)
    _add_craft_option(list, "BEBER", _drink)
    _add_craft_option(list, "CERRAR", _toggle_craft_panel)
    control_layer.add_child(craft_panel)

func _add_craft_option(parent: VBoxContainer, title: String, callback: Callable) -> void:
    var button := Button.new()
    button.text = title
    button.custom_minimum_size = Vector2(150, 28)
    button.add_theme_font_size_override("font_size", 12)
    _style_action_button(button)
    button.pressed.connect(callback)
    parent.add_child(button)

func _toggle_craft_panel() -> void:
    craft_panel.visible = not craft_panel.visible

func _has_cost(wood: int, stone: int, fiber: int) -> bool:
    return int(player.inventory.get("Madera", 0)) >= wood and int(player.inventory.get("Piedra", 0)) >= stone and int(player.inventory.get("Fibra", 0)) >= fiber

func _pay_cost(wood: int, stone: int, fiber: int) -> void:
    player.inventory["Madera"] -= wood
    player.inventory["Piedra"] -= stone
    player.inventory["Fibra"] -= fiber

func _craft_axe() -> void:
    if player.axe_unlocked:
        message.text = "Ya tienes un hacha."
    elif _has_cost(3, 2, 0):
        _pay_cost(3, 2, 0)
        player.axe_unlocked = true
        message.text = "Hacha fabricada: recolectas el doble de madera."
    else:
        message.text = "Necesitas 3 madera y 2 piedra."

func _craft_shelter() -> void:
    if not _has_cost(12, 0, 6):
        message.text = "Necesitas 12 madera y 6 fibra."
        return
    _pay_cost(12, 0, 6)
    _place_buildable("Refugio")
    message.text = "Refugio construido."

func _craft_campfire() -> void:
    if not _has_cost(5, 3, 0):
        message.text = "Necesitas 5 madera y 3 piedra."
        return
    _pay_cost(5, 3, 0)
    _place_buildable("Fogata")
    message.text = "Fogata encendida: ilumina de noche."

func _craft_rations() -> void:
    if not _has_cost(1, 0, 3):
        message.text = "Necesitas 1 madera y 3 fibra."
        return
    _pay_cost(1, 0, 3)
    player.inventory["Comida"] = int(player.inventory.get("Comida", 0)) + 2
    message.text = "Preparaste 2 raciones."

func _place_buildable(kind: String, saved_position: Vector3 = Vector3.INF) -> void:
    var structure: SurvivalBuildable = BUILDABLE_SCRIPT.new()
    structure.build_kind = kind
    if saved_position == Vector3.INF:
        var forward := -player.global_transform.basis.z
        var candidate := player.global_position + forward * 3.2
        candidate.y = _height_at(candidate.x, candidate.z)
        structure.position = candidate
    else:
        structure.position = saved_position
    add_child(structure)

func _eat() -> void:
    if int(player.inventory.get("Comida", 0)) <= 0:
        message.text = "No tienes comida. Fabrica raciones."
        return
    player.inventory["Comida"] -= 1
    player.restore_needs(35.0, 0.0)
    message.text = "Comiste una ración."

func _drink() -> void:
    var near_water := absf(player.global_position.y - WATER_LEVEL) < 3.0 and Vector2(player.global_position.x, player.global_position.z).length() > WORLD_SIZE * 0.35
    if near_water:
        player.restore_needs(0.0, 45.0)
        message.text = "Bebiste agua de la costa."
    elif int(player.inventory.get("Agua", 0)) > 0:
        player.inventory["Agua"] -= 1
        player.restore_needs(0.0, 40.0)
        message.text = "Bebiste agua almacenada."
    else:
        message.text = "Acércate a la costa para beber."

func _spawn_wildlife() -> void:
    # Repartimos especies para que el bosque tenga fauna variada.
    var species_data: Array[Dictionary] = [
        {"species": "Deer", "file": "Deer.gltf", "predator": false, "speed": 2.6, "scale": 1.0},
        {"species": "Stag", "file": "Stag.gltf", "predator": false, "speed": 2.8, "scale": 1.05},
        {"species": "Fox", "file": "Fox.gltf", "predator": false, "speed": 3.1, "scale": 0.85},
        {"species": "Wolf", "file": "Wolf.gltf", "predator": true, "speed": 3.0, "scale": 0.95},
        {"species": "Husky", "file": "Husky.gltf", "predator": false, "speed": 2.8, "scale": 0.9},
        {"species": "ShibaInu", "file": "ShibaInu.gltf", "predator": false, "speed": 2.6, "scale": 0.8},
        {"species": "Cow", "file": "Cow.gltf", "predator": false, "speed": 1.8, "scale": 1.0},
        {"species": "Bull", "file": "Bull.gltf", "predator": false, "speed": 2.0, "scale": 1.05},
        {"species": "Horse", "file": "Horse.gltf", "predator": false, "speed": 3.2, "scale": 1.0},
        {"species": "Horse_White", "file": "Horse_White.gltf", "predator": false, "speed": 3.2, "scale": 1.0},
        {"species": "Alpaca", "file": "Alpaca.gltf", "predator": false, "speed": 2.0, "scale": 0.9},
        {"species": "Donkey", "file": "Donkey.gltf", "predator": false, "speed": 2.0, "scale": 0.9}
    ]
    for data in species_data:
        var placed := false
        for attempt in range(18):
            var angle := rng.randf_range(0.0, TAU)
            var radius := rng.randf_range(58.0, WORLD_SIZE * 0.34)
            var x := cos(angle) * radius
            var z := sin(angle) * radius
            var y := _height_at(x, z)
            if y <= WATER_LEVEL + 1.0:
                continue
            var animal: WildAnimal = ANIMAL_SCRIPT.new()
            data["path"] = "res://assets/quaternius/ultimate-animated-animals/" + str(data["file"])
            animal.configure(data)
            animal.position = Vector3(x, y + 0.12, z)
            add_child(animal)
            placed = true
            break
        if not placed:
            push_warning("No se pudo colocar " + str(data["species"]) + " en terreno seco.")

func _update_day_night(delta: float) -> void:
    day_clock += delta / 900.0
    var phase := fposmod(day_clock, 1.0)
    var daylight := clampf(sin(phase * TAU), 0.0, 1.0)
    if is_instance_valid(sun_light):
        sun_light.rotation_degrees.x = -90.0 + phase * 360.0
        sun_light.light_energy = 0.08 + daylight * 1.05
        sun_light.light_color = Color(1.0, 0.70 + daylight * 0.25, 0.48 + daylight * 0.48)
    if world_environment != null:
        world_environment.ambient_light_energy = 0.18 + daylight * 0.62
        world_environment.fog_light_color = Color(0.055, 0.075, 0.12).lerp(Color(0.58, 0.72, 0.78), daylight)
        world_environment.background_energy_multiplier = 0.25 + daylight * 0.75

func _time_of_day_name() -> String:
    var phase := fposmod(day_clock, 1.0)
    if phase < 0.20 or phase > 0.82:
        return "NOCHE"
    if phase < 0.30:
        return "AMANECER"
    if phase > 0.72:
        return "ATARDECER"
    return "DÍA"

func on_resource_harvested(resource_id: String, remaining: int) -> void:
    if resource_id.is_empty():
        return
    if remaining <= 0:
        resource_remaining_state.erase(resource_id)
        depleted_resource_ids[resource_id] = true
    else:
        resource_remaining_state[resource_id] = remaining

func _save_game(show_message: bool = true) -> void:
    var config := ConfigFile.new()
    config.set_value("player", "position", player.global_position)
    config.set_value("player", "rotation", player.rotation)
    config.set_value("player", "camera_rotation", player.camera.rotation)
    config.set_value("player", "health", player.health)
    config.set_value("player", "hunger", player.hunger)
    config.set_value("player", "thirst", player.thirst)
    config.set_value("player", "stamina", player.stamina)
    config.set_value("player", "inventory", player.inventory)
    config.set_value("player", "axe_unlocked", player.axe_unlocked)
    config.set_value("world", "day_clock", day_clock)
    config.set_value("world", "resource_remaining", resource_remaining_state)
    config.set_value("world", "depleted_resources", depleted_resource_ids.keys())
    var structures: Array[Dictionary] = []
    for item in get_tree().get_nodes_in_group("buildables"):
        structures.append({"kind": item.build_kind, "position": item.global_position})
    config.set_value("world", "structures", structures)
    var error := config.save("user://rust_mobile_save.cfg")
    if show_message and is_instance_valid(message):
        message.text = "Partida guardada." if error == OK else "Error al guardar: %s" % error

func _load_game() -> void:
    var config := ConfigFile.new()
    if config.load("user://rust_mobile_save.cfg") != OK:
        return
    player.global_position = config.get_value("player", "position", player.global_position)
    player.rotation = config.get_value("player", "rotation", player.rotation)
    player.camera.rotation = config.get_value("player", "camera_rotation", player.camera.rotation)
    player.health = float(config.get_value("player", "health", 100.0))
    player.hunger = float(config.get_value("player", "hunger", 100.0))
    player.thirst = float(config.get_value("player", "thirst", 100.0))
    player.stamina = float(config.get_value("player", "stamina", 100.0))
    var saved_inventory: Dictionary = config.get_value("player", "inventory", {})
    for key in saved_inventory:
        player.inventory[key] = saved_inventory[key]
    player.axe_unlocked = bool(config.get_value("player", "axe_unlocked", false))
    day_clock = float(config.get_value("world", "day_clock", day_clock))
    resource_remaining_state = config.get_value("world", "resource_remaining", {})
    depleted_resource_ids.clear()
    for resource_id in config.get_value("world", "depleted_resources", []):
        depleted_resource_ids[str(resource_id)] = true
    for resource_node in get_tree().get_nodes_in_group("harvestable"):
        var node_id := str(resource_node.resource_id)
        if depleted_resource_ids.has(node_id):
            resource_node.queue_free()
        elif resource_remaining_state.has(node_id):
            resource_node.remaining = int(resource_remaining_state[node_id])
    var structures: Array = config.get_value("world", "structures", [])
    for entry in structures:
        _place_buildable(str(entry.get("kind", "Refugio")), entry.get("position", Vector3.ZERO))

func _set_action_icon(button: Button, icon_name: String) -> void:
    var icon_path := MOBILE_ICON_PATH + icon_name + ".svg"
    if ResourceLoader.exists(icon_path):
        button.icon = load(icon_path) as Texture2D
        button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _style_action_button(button: Button, round_button: bool = false) -> void:
    # Control táctil circular: vidrio ahumado, aro claro y sombra para separarlo del mundo.
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.025, 0.038, 0.046, 0.88)
    normal.border_color = Color(0.82, 0.90, 0.94, 0.76)
    normal.set_border_width_all(2)
    normal.set_corner_radius_all(999 if round_button else 12)
    normal.shadow_color = Color(0.0, 0.0, 0.0, 0.48)
    normal.shadow_size = 8
    normal.shadow_offset = Vector2(0, 3)
    normal.set_content_margin_all(7)
    button.add_theme_stylebox_override("normal", normal)
    var pressed := StyleBoxFlat.new()
    pressed.bg_color = Color(0.12, 0.24, 0.30, 0.97)
    pressed.border_color = Color(0.68, 0.86, 1.0, 0.95)
    pressed.set_border_width_all(2)
    pressed.set_corner_radius_all(999 if round_button else 12)
    pressed.shadow_color = Color(0.0, 0.0, 0.0, 0.34)
    pressed.shadow_size = 3
    pressed.shadow_offset = Vector2(0, 1)
    pressed.set_content_margin_all(7)
    button.add_theme_stylebox_override("pressed", pressed)
    var hover := normal.duplicate() as StyleBoxFlat
    hover.bg_color = Color(0.13, 0.16, 0.18, 0.90)
    button.add_theme_stylebox_override("hover", hover)
    button.add_theme_color_override("font_color", Color(0.97, 0.98, 1.0))
    button.add_theme_color_override("font_pressed_color", Color.WHITE)
    button.add_theme_color_override("font_hover_color", Color.WHITE)
    button.add_theme_font_size_override("font_size", 11)
    button.add_theme_constant_override("icon_max_width", 46)

func _has_all_resource_models() -> bool:
    for kind in ["Madera", "Piedra", "Fibra"]:
        if asset_scenes.get(kind, []).is_empty():
            return false
    return true

func _scatter_resources() -> void:
    if not _has_all_resource_models():
        message.text = "Instala Kenney Nature Kit para activar los recursos 3D."
        return
    # Separación mínima entre nodos para evitar árboles, rocas y arbustos apilados.
    var occupied_positions: Array[Vector3] = []
    for kind in RESOURCE_COUNTS:
        var created := 0
        var attempts := 0
        var target_count: int = int(RESOURCE_COUNTS[kind])
        while created < target_count and attempts < target_count * 28:
            attempts += 1
            var x := rng.randf_range(-WORLD_SIZE * 0.46, WORLD_SIZE * 0.46)
            var z := rng.randf_range(-WORLD_SIZE * 0.46, WORLD_SIZE * 0.46)
            var distance := Vector2(x, z).length()
            if distance < 30.0:
                continue
            var y := _height_at(x, z)
            # Ningún recurso aparece sumergido ni pegado a la línea de marea.
            if y < WATER_LEVEL + 3.0:
                continue
            var normal := _terrain_normal_at(x, z)
            var slope := 1.0 - normal.y
            var biome := biome_noise.get_noise_2d(x, z)
            var ridge := ridge_noise.get_noise_2d(x, z)
            if slope > 0.62:
                continue
            # Cada recurso tiene un hábitat propio: bosque, ladera rocosa o matorral.
            if kind == "Madera":
                if biome < -0.22 or y < 1.5 or y > 31.0 or slope > 0.38:
                    continue
                if rng.randf() > clampf(0.82 + biome * 0.16, 0.58, 0.96):
                    continue
            elif kind == "Piedra":
                if y < 3.5 and ridge < 0.18:
                    continue
                if rng.randf() > clampf(0.54 + maxf(ridge, 0.0) * 0.42 + slope * 0.22, 0.48, 0.96):
                    continue
            elif kind == "Fibra":
                if y > 29.0 or slope > 0.42:
                    continue
                if rng.randf() > clampf(0.82 - maxf(biome, 0.0) * 0.20, 0.52, 0.90):
                    continue
            var too_close := false
            for existing in occupied_positions:
                if Vector2(existing.x - x, existing.z - z).length_squared() < 13.0:
                    too_close = true
                    break
            if too_close:
                continue
            var resource_position := Vector3(x, y, z)
            _create_resource(resource_position, kind)
            occupied_positions.append(resource_position)
            created += 1
        if created < target_count:
            push_warning("Distribución de %s: se colocaron %d de %d nodos." % [kind, created, target_count])

func _create_resource(pos: Vector3, kind: String) -> void:
    var options: Array = asset_scenes[kind]
    var model_scene: PackedScene = options[rng.randi_range(0, options.size() - 1)]
    var node: ResourceNode = RESOURCE_SCRIPT.new()
    node.resource_type = kind
    node.resource_id = "%s_%d_%d_%d" % [kind, roundi(pos.x * 10.0), roundi(pos.y * 10.0), roundi(pos.z * 10.0)]
    node.amount = 4 if kind == "Madera" else 3
    node.model_scene = model_scene
    node.position = pos
    if kind == "Madera":
        node.model_scale = Vector3.ONE * (0.9 if ResourceLoader.exists(NATURE_MEGA_PATH + "CommonTree_1.gltf") else 4.0)
    elif kind == "Piedra":
        node.model_scale = Vector3.ONE * (1.0 if ResourceLoader.exists(NATURE_MEGA_PATH + "Rock_Medium_1.gltf") else 3.6)
    else:
        node.model_scale = Vector3.ONE * (0.85 if ResourceLoader.exists(NATURE_MEGA_PATH + "Bush_Common.gltf") else 3.0)
    add_child(node)

func _scatter_ground_cover() -> void:
    # Instancias de modelos 3D reales; las zonas rocosas, playas y laderas quedan despejadas.
    _add_foliage_multimesh(NATURE_MEGA_PATH + "Grass_Common_Short.gltf", 42, 0.78, 1.18)
    _add_foliage_multimesh(NATURE_MEGA_PATH + "Fern_1.gltf", 8, 0.62, 0.96)
    _add_foliage_multimesh(NATURE_MEGA_PATH + "Flower_3_Group.gltf", 5, 0.62, 0.95)

func _add_foliage_multimesh(model_path: String, per_chunk: int, min_scale: float, max_scale: float) -> void:
    if not ResourceLoader.exists(model_path):
        return
    var packed := load(model_path) as PackedScene
    if packed == null:
        return
    var sample := packed.instantiate()
    var mesh_nodes: Array[MeshInstance3D] = []
    if sample is MeshInstance3D:
        mesh_nodes.append(sample as MeshInstance3D)
    for node in sample.find_children("*", "MeshInstance3D", true, false):
        if node is MeshInstance3D:
            mesh_nodes.append(node as MeshInstance3D)
    if mesh_nodes.is_empty():
        sample.free()
        return
    for chunk_z in range(CHUNK_COUNT):
        for chunk_x in range(CHUNK_COUNT):
            var center_x := -WORLD_SIZE * 0.5 + (float(chunk_x) + 0.5) * CHUNK_SIZE
            var center_z := -WORLD_SIZE * 0.5 + (float(chunk_z) + 0.5) * CHUNK_SIZE
            for source_mesh in mesh_nodes:
                if source_mesh.mesh == null:
                    continue
                var multi := MultiMesh.new()
                multi.transform_format = MultiMesh.TRANSFORM_3D
                multi.mesh = source_mesh.mesh
                multi.instance_count = per_chunk
                for index in range(per_chunk):
                    var local_x := rng.randf_range(-CHUNK_SIZE * 0.48, CHUNK_SIZE * 0.48)
                    var local_z := rng.randf_range(-CHUNK_SIZE * 0.48, CHUNK_SIZE * 0.48)
                    var world_x := center_x + local_x
                    var world_z := center_z + local_z
                    var ground_y := _height_at(world_x, world_z)
                    var normal := _terrain_normal_at(world_x, world_z)
                    var slope := 1.0 - normal.y
                    var scale_value := rng.randf_range(min_scale, max_scale)
                    var biome_value := biome_noise.get_noise_2d(world_x, world_z)
                    # Hierba densa en praderas; helechos y flores aparecen en manchas más selectivas.
                    if ground_y <= WATER_LEVEL + 3.0 or slope > 0.48:
                        scale_value = 0.0
                    elif ground_y < 1.0:
                        scale_value *= 0.18
                    elif ground_y > 26.0:
                        scale_value *= 0.32
                    elif biome_value < -0.62:
                        scale_value *= 0.20
                    elif biome_value > 0.35:
                        scale_value *= 1.12
                    var yaw := rng.randf_range(0.0, TAU)
                    var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_value)
                    var placement := Transform3D(basis, Vector3(local_x, ground_y, local_z))
                    # Conserva la posición y orientación internas de cada pieza del modelo GLTF.
                    multi.set_instance_transform(index, placement * source_mesh.transform)
                var instance := MultiMeshInstance3D.new()
                instance.multimesh = multi
                instance.position = Vector3(center_x, 0.0, center_z)
                instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
                instance.custom_aabb = AABB(Vector3(-CHUNK_SIZE * 0.5, -12.0, -CHUNK_SIZE * 0.5), Vector3(CHUNK_SIZE, 42.0, CHUNK_SIZE))
                if source_mesh.material_override != null:
                    instance.material_override = source_mesh.material_override
                add_child(instance)
    sample.free()

func show_message(text_value: String) -> void:
    if is_instance_valid(message):
        message.text = text_value

func _try_attack() -> void:
    if not is_instance_valid(player):
        return
    if attack_cooldown > 0.0:
        show_message("Espera %.1f s para golpear." % attack_cooldown)
        return
    attack_cooldown = 0.48
    var from := player.camera.global_position
    var to := from + -player.camera.global_transform.basis.z * 3.2
    var query := PhysicsRayQueryParameters3D.create(from, to)
    query.exclude = [player.get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if hit and hit.collider.is_in_group("wild_animals") and hit.collider.has_method("take_damage"):
        hit.collider.take_damage(25.0)
        if is_instance_valid(hit.collider):
            show_message("Impacto: fauna herida.")
    else:
        show_message("No hay ningún animal al alcance.")

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

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
        if is_instance_valid(player):
            _save_game()
