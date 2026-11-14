extends Node3D

const PLAYER_SCRIPT = preload("res://scripts/player.gd")
const RESOURCE_SCRIPT = preload("res://scripts/resource_node.gd")
const JOYSTICK_SCRIPT = preload("res://scripts/mobile_joystick.gd")
const ANIMAL_SCRIPT = preload("res://scripts/wild_animal.gd")
const BUILDABLE_SCRIPT = preload("res://scripts/survival_buildable.gd")
const WORLD_SIZE := 512.0
const CHUNK_COUNT := 4
const CHUNK_SIZE := WORLD_SIZE / CHUNK_COUNT
const CHUNK_SEGMENTS := 64
const WATER_LEVEL := -2.5
const RESOURCE_COUNTS := {"Madera": 88, "Piedra": 58, "Fibra": 76}
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
var asset_scenes: Dictionary = {}
var rng := RandomNumberGenerator.new()
var sun_light: DirectionalLight3D
var world_environment: Environment
var day_clock := 0.22
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
    _scatter_ground_cover()
    _spawn_wildlife()
    _load_game()

func _process(_delta: float) -> void:
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
        inventory_summary.text = "Madera %d | Piedra %d | Fibra %d | Comida %d | Agua %d" % [player.inventory["Madera"], player.inventory["Piedra"], player.inventory["Fibra"], player.inventory["Comida"], player.inventory["Agua"]]
    if is_instance_valid(day_label):
        day_label.text = "%s · DÍA %d" % [_time_of_day_name(), int(day_clock) + 1]
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
    e.ambient_light_energy = 0.75
    e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    e.fog_enabled = true
    e.fog_light_color = Color(0.58, 0.72, 0.78)
    e.fog_density = 0.0012
    e.fog_sky_affect = 0.65
    env.environment = e
    add_child(env)
    world_environment = e
    sun_light = DirectionalLight3D.new()
    sun_light.rotation_degrees = Vector3(-48, -32, 0)
    sun_light.light_energy = 1.0
    sun_light.shadow_enabled = true
    sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
    sun_light.directional_shadow_max_distance = 65.0
    sun_light.directional_shadow_fade_start = 0.8
    add_child(sun_light)

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
    status_title.text = "SUPERVIVENCIA  /  v0.3.4"
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
    var map_view := ColorRect.new()
    map_view.custom_minimum_size = Vector2(116, 70)
    map_view.color = Color(0.12, 0.22, 0.17, 0.96)
    map_col.add_child(map_view)
    var marker := Label.new()
    marker.text = "▲"
    marker.add_theme_font_size_override("font_size", 18)
    marker.add_theme_color_override("font_color", Color(0.96, 0.82, 0.35))
    marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    map_view.add_child(marker)
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

    # Grupo táctil circular: acciones separadas y alcanzables con el pulgar.
    _add_control_button("SALTAR", Vector2(-184, -244), Vector2(66, 66), "jump", "hold", "jump")
    _add_sprint_button()
    _add_crouch_button()
    interact_button = _create_action_button("USAR", Vector2(-104, -246), Vector2(68, 68))
    _set_action_icon(interact_button, "use")
    interact_button.pressed.connect(_try_harvest)
    control_layer.add_child(interact_button)
    var attack_button := _create_action_button("GOLPE", Vector2(-104, -164), Vector2(78, 78))
    _set_action_icon(attack_button, "attack")
    attack_button.pressed.connect(_try_attack)
    control_layer.add_child(attack_button)

    var bag := _create_action_button("", Vector2(-82, -164), Vector2(58, 58))
    _set_action_icon(bag, "backpack")
    bag.pressed.connect(_toggle_inventory_panel)
    control_layer.add_child(bag)
    var craft := _create_action_button("", Vector2(-82, -96), Vector2(58, 58))
    _set_action_icon(craft, "craft")
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
        _style_hotbar_slot(slot, i == 0)
        hotbar.add_child(slot)
        _make_hotbar_preview(slot, slot_models[i], slot_names[i], i + 1)

    _make_craft_panel()
    _make_inventory_panel()

func _make_bar(parent: VBoxContainer, caption: String, tint: Color) -> ProgressBar:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 6)
    parent.add_child(row)
    var label := Label.new()
    label.text = caption
    label.custom_minimum_size = Vector2(82, 0)
    label.add_theme_font_size_override("font_size", 10)
    label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.86))
    row.add_child(label)
    var bar := ProgressBar.new()
    bar.min_value = 0
    bar.max_value = 100
    bar.value = 100
    bar.show_percentage = true
    bar.custom_minimum_size = Vector2(128, 15)
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
    fill.set_corner_radius_all(3)
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
    _style_action_button(button, not compact)
    return button

func _add_control_button(label_text: String, offset: Vector2, button_size: Vector2, action: String, _mode: String = "hold", icon_name: String = "") -> void:
    var button := _create_action_button(label_text, offset, button_size)
    if not icon_name.is_empty():
        _set_action_icon(button, icon_name)
    button.button_down.connect(player.mobile_action.bind(action, true))
    button.button_up.connect(player.mobile_action.bind(action, false))
    control_layer.add_child(button)

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
    viewport.size = Vector2i(256, 176)
    viewport.msaa_3d = Viewport.MSAA_2X
    preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    viewport.transparent_bg = true
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
    var button := _create_action_button("AGACHAR", Vector2(-184, -164), Vector2(66, 66))
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
    inventory_panel.position = Vector2(-140, -90)
    inventory_panel.custom_minimum_size = Vector2(280, 180)
    inventory_panel.visible = false
    _style_action_panel(inventory_panel)
    var column := VBoxContainer.new()
    inventory_panel.add_child(column)
    var title := Label.new()
    title.text = "MOCHILA"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    column.add_child(title)
    inventory_summary = Label.new()
    inventory_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
    var button := _create_action_button("CORRER", Vector2(-104, -326), Vector2(64, 64))
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

func _save_game() -> void:
    var config := ConfigFile.new()
    config.set_value("player", "position", player.global_position)
    config.set_value("player", "rotation", player.rotation)
    config.set_value("player", "camera_rotation", player.camera.rotation)
    config.set_value("player", "health", player.health)
    config.set_value("player", "hunger", player.hunger)
    config.set_value("player", "thirst", player.thirst)
    config.set_value("player", "inventory", player.inventory)
    config.set_value("player", "axe_unlocked", player.axe_unlocked)
    config.set_value("world", "day_clock", day_clock)
    var structures: Array[Dictionary] = []
    for item in get_tree().get_nodes_in_group("buildables"):
        structures.append({"kind": item.build_kind, "position": item.global_position})
    config.set_value("world", "structures", structures)
    var error := config.save("user://rust_mobile_save.cfg")
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
    var saved_inventory: Dictionary = config.get_value("player", "inventory", {})
    for key in saved_inventory:
        player.inventory[key] = saved_inventory[key]
    player.axe_unlocked = bool(config.get_value("player", "axe_unlocked", false))
    day_clock = float(config.get_value("world", "day_clock", day_clock))
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
    normal.bg_color = Color(0.055, 0.065, 0.070, 0.78)
    normal.border_color = Color(0.91, 0.94, 0.96, 0.58)
    normal.set_border_width_all(1)
    normal.set_corner_radius_all(999 if round_button else 12)
    normal.shadow_color = Color(0.0, 0.0, 0.0, 0.48)
    normal.shadow_size = 8
    normal.shadow_offset = Vector2(0, 3)
    normal.set_content_margin_all(7)
    button.add_theme_stylebox_override("normal", normal)
    var pressed := StyleBoxFlat.new()
    pressed.bg_color = Color(0.24, 0.30, 0.33, 0.94)
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
    button.add_theme_constant_override("icon_max_width", 30)

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
        node.model_scale = Vector3.ONE * (0.9 if ResourceLoader.exists(NATURE_MEGA_PATH + "CommonTree_1.gltf") else 4.0)
    elif kind == "Piedra":
        node.model_scale = Vector3.ONE * (1.0 if ResourceLoader.exists(NATURE_MEGA_PATH + "Rock_Medium_1.gltf") else 3.6)
    else:
        node.model_scale = Vector3.ONE * (0.85 if ResourceLoader.exists(NATURE_MEGA_PATH + "Bush_Common.gltf") else 3.0)
    add_child(node)

func _scatter_ground_cover() -> void:
    # Césped y plantas pequeñas en MultiMesh: cientos de matas con pocas llamadas de dibujo.
    _add_foliage_multimesh(NATURE_MEGA_PATH + "Grass_Common_Short.gltf", 20, 0.75, 1.15)
    _add_foliage_multimesh(NATURE_MEGA_PATH + "Fern_1.gltf", 4, 0.65, 1.0)
    _add_foliage_multimesh(NATURE_MEGA_PATH + "Flower_3_Group.gltf", 3, 0.7, 1.0)

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
                    var scale_value := rng.randf_range(min_scale, max_scale)
                    if ground_y <= WATER_LEVEL + 0.4:
                        scale_value = 0.0
                    var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_value)
                    multi.set_instance_transform(index, Transform3D(basis, Vector3(local_x, ground_y, local_z)))
                var instance := MultiMeshInstance3D.new()
                instance.multimesh = multi
                instance.position = Vector3(center_x, 0.0, center_z)
                instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
                instance.custom_aabb = AABB(Vector3(-CHUNK_SIZE * 0.5, -12.0, -CHUNK_SIZE * 0.5), Vector3(CHUNK_SIZE, 42.0, CHUNK_SIZE))
                if source_mesh.material_override != null:
                    instance.material_override = source_mesh.material_override
                add_child(instance)
    sample.free()

func _try_attack() -> void:
    if not is_instance_valid(player):
        return
    var from := player.camera.global_position
    var to := from + -player.camera.global_transform.basis.z * 2.8
    var query := PhysicsRayQueryParameters3D.create(from, to)
    query.exclude = [player.get_rid()]
    var hit := get_world_3d().direct_space_state.intersect_ray(query)
    if hit and hit.collider.is_in_group("wild_animals") and hit.collider.has_method("take_damage"):
        hit.collider.take_damage(20.0)
        message.text = "Golpeaste al animal."
    else:
        message.text = "No hay ningún animal al alcance."

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
