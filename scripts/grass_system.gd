extends Node3D

const WORLD_SIZE := 512.0
const CHUNK_COUNT := 4
const CHUNK_SIZE := WORLD_SIZE / float(CHUNK_COUNT)
const CLUMPS_PER_CHUNK := 240000
const GRASS_HEIGHT := 0.155
const BLADE_COUNT := 9
const CARPET_RESOLUTION := 64

var world_ref: Node3D
var rng := RandomNumberGenerator.new()

func build(world: Node3D) -> void:
    world_ref = world
    rng.seed = 73519
    var blade_mesh := _make_blade_cluster()
    var blade_material := _make_wind_material()
    var carpet_material := _make_carpet_material()
    for z in range(CHUNK_COUNT):
        for x in range(CHUNK_COUNT):
            _make_carpet(x, z, carpet_material)
            _make_chunk(x, z, blade_mesh, blade_material)

func _make_blade_cluster() -> ArrayMesh:
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var colors := PackedColorArray()
    var indices := PackedInt32Array()
    for blade in range(BLADE_COUNT):
        var yaw := float(blade) * PI * 0.5 + (0.17 if blade % 2 == 0 else -0.11)
        var direction := Vector3(sin(yaw), 0.0, cos(yaw))
        var side := Vector3(cos(yaw), 0.0, -sin(yaw))
        var base := vertices.size()
        for segment in range(5):
            var t := float(segment) / 4.0
            var half_width := maxf(0.0008, 0.039 * pow(1.0 - t, 1.18))
            var center := direction * (t * t * 0.065) + Vector3.UP * (t * GRASS_HEIGHT)
            vertices.append(center - side * half_width)
            vertices.append(center + side * half_width)
            var tint := Color(0.105, 0.205, 0.055).lerp(Color(0.43, 0.43, 0.105), t)
            colors.append(tint.darkened(0.035))
            colors.append(tint.lightened(0.025))
            normals.append(Vector3.UP)
            normals.append(Vector3.UP)
            if segment < 4:
                var a := base + segment * 2
                indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func _make_wind_material() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
uniform float wind_strength = 0.035;
uniform float wind_speed = 1.05;
void vertex() {
    float phase = INSTANCE_CUSTOM.r * 6.28318;
    float h = clamp(VERTEX.y / 0.155, 0.0, 1.0);
    float breeze = sin(TIME * wind_speed + phase + VERTEX.x * 3.0 + VERTEX.z * 3.0);
    VERTEX.x += breeze * wind_strength * h * h;
    VERTEX.z += cos(TIME * 0.7 + phase) * wind_strength * 0.35 * h;
}
void fragment() {
    ALBEDO = COLOR.rgb;
    ROUGHNESS = 1.0;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    return material

func _make_carpet_material() -> ShaderMaterial:
    # Capa de microhierba procedural: rellena visualmente los huecos entre
    # las hojas instanciadas sin multiplicar millones de polígonos adicionales.
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
varying vec3 grass_world_pos;
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
void vertex() {
    grass_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    vec2 p = grass_world_pos.xz * 34.0;
    vec2 cell = floor(p);
    vec2 f = fract(p);
    float rnd = hash21(cell);
    float lean = (rnd - 0.5) * 0.55;
    float blade_line = abs(f.x - (0.5 + lean + (f.y - 0.5) * 0.18));
    float blade = 1.0 - smoothstep(0.025, 0.105, blade_line);
    float tip = smoothstep(0.05, 0.95, f.y);
    float variation = hash21(floor(grass_world_pos.xz * 5.0)) * 0.12;
    vec3 soil_green = vec3(0.035, 0.105, 0.018);
    vec3 leaf_green = vec3(0.105, 0.225, 0.035);
    vec3 color = mix(soil_green, leaf_green, blade * (0.65 + tip * 0.35));
    color *= 0.88 + variation;
    ALBEDO = color;
    ROUGHNESS = 1.0;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    return material

func _make_carpet(chunk_x: int, chunk_z: int, material: Material) -> void:
    var center_x := -WORLD_SIZE * 0.5 + (float(chunk_x) + 0.5) * CHUNK_SIZE
    var center_z := -WORLD_SIZE * 0.5 + (float(chunk_z) + 0.5) * CHUNK_SIZE
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var indices := PackedInt32Array()
    var step := CHUNK_SIZE / float(CARPET_RESOLUTION)
    for z in range(CARPET_RESOLUTION + 1):
        for x in range(CARPET_RESOLUTION + 1):
            var lx := -CHUNK_SIZE * 0.5 + float(x) * step
            var lz := -CHUNK_SIZE * 0.5 + float(z) * step
            var wx := center_x + lx
            var wz := center_z + lz
            var gy: float = world_ref.call("_height_at", wx, wz)
            vertices.append(Vector3(lx, gy + 0.0015, lz))
            var normal: Vector3 = world_ref.call("_terrain_normal_at", wx, wz)
            normals.append(normal)
            if x < CARPET_RESOLUTION and z < CARPET_RESOLUTION:
                var a := z * (CARPET_RESOLUTION + 1) + x
                var b := a + 1
                var c := a + CARPET_RESOLUTION + 1
                var d := c + 1
                indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var carpet := MeshInstance3D.new()
    carpet.name = "GrassCarpet_%d_%d" % [chunk_x, chunk_z]
    carpet.mesh = mesh
    carpet.material_override = material
    carpet.position = Vector3(center_x, 0.0, center_z)
    carpet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(carpet)

func _make_flowers(chunk_x: int, chunk_z: int, center_x: float, center_z: float) -> void:
    var flower_mesh := SphereMesh.new()
    flower_mesh.radius = 0.018
    flower_mesh.height = 0.036
    flower_mesh.radial_segments = 5
    flower_mesh.rings = 3
    var flower_material := StandardMaterial3D.new()
    flower_material.vertex_color_use_as_albedo = true
    flower_material.roughness = 0.85
    var flowers := MultiMesh.new()
    flowers.transform_format = MultiMesh.TRANSFORM_3D
    flowers.use_colors = true
    flowers.mesh = flower_mesh
    flowers.instance_count = 500
    for i in range(500):
        var wx := center_x + rng.randf_range(-CHUNK_SIZE * 0.49, CHUNK_SIZE * 0.49)
        var wz := center_z + rng.randf_range(-CHUNK_SIZE * 0.49, CHUNK_SIZE * 0.49)
        var gy: float = world_ref.call("_height_at", wx, wz)
        var normal: Vector3 = world_ref.call("_terrain_normal_at", wx, wz)
        if gy <= -2.5 or gy > 24.0 or 1.0 - normal.y > 0.42:
            flowers.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
            continue
        var scale := rng.randf_range(0.65, 1.15)
        var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(scale, scale, scale))
        flowers.set_instance_transform(i, Transform3D(basis, Vector3(wx - center_x, gy + 0.055, wz - center_z)))
        flowers.set_instance_color(i, Color(1.0, 0.88, 0.28) if rng.randf() > 0.5 else Color(0.96, 0.96, 0.88))
    var flower_node := MultiMeshInstance3D.new()
    flower_node.name = "Wildflowers_%d_%d" % [chunk_x, chunk_z]
    flower_node.multimesh = flowers
    flower_node.material_override = flower_material
    flower_node.position = Vector3(center_x, 0.0, center_z)
    flower_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    flower_node.custom_aabb = AABB(Vector3(-CHUNK_SIZE * 0.5, -8.0, -CHUNK_SIZE * 0.5), Vector3(CHUNK_SIZE, 42.0, CHUNK_SIZE))
    add_child(flower_node)

func _make_chunk(chunk_x: int, chunk_z: int, blade_mesh: Mesh, blade_material: Material) -> void:
    var center_x := -WORLD_SIZE * 0.5 + (float(chunk_x) + 0.5) * CHUNK_SIZE
    var center_z := -WORLD_SIZE * 0.5 + (float(chunk_z) + 0.5) * CHUNK_SIZE
    var multi := MultiMesh.new()
    multi.transform_format = MultiMesh.TRANSFORM_3D
    multi.use_colors = true
    multi.use_custom_data = true
    multi.mesh = blade_mesh
    multi.instance_count = CLUMPS_PER_CHUNK
    var grid_side := ceili(sqrt(float(CLUMPS_PER_CHUNK)))
    for i in range(CLUMPS_PER_CHUNK):
        var cell_x := i % grid_side
        var cell_z := int(i / grid_side)
        var cell_size := CHUNK_SIZE / float(grid_side)
        var lx := -CHUNK_SIZE * 0.5 + (float(cell_x) + rng.randf_range(0.08, 0.92)) * cell_size
        var lz := -CHUNK_SIZE * 0.5 + (float(cell_z) + rng.randf_range(0.08, 0.92)) * cell_size
        var wx := center_x + lx
        var wz := center_z + lz
        var gy: float = world_ref.call("_height_at", wx, wz)
        var normal: Vector3 = world_ref.call("_terrain_normal_at", wx, wz)
        if gy <= -2.5 or gy > 26.0 or 1.0 - normal.y > 0.48:
            multi.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(lx, gy, lz)))
            multi.set_instance_color(i, Color.WHITE)
            multi.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 1))
            continue
        var sx := rng.randf_range(0.82, 1.18)
        var sy := rng.randf_range(0.72, 1.12)
        var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(sx, sy, sx))
        multi.set_instance_transform(i, Transform3D(basis, Vector3(lx, gy + 0.003, lz)))
        var shade := rng.randf_range(0.82, 1.12)
        multi.set_instance_color(i, Color(shade, shade * rng.randf_range(0.96, 1.04), shade * 0.88, 1.0))
        multi.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 1))
    _make_flowers(chunk_x, chunk_z, center_x, center_z)
    var grass := MultiMeshInstance3D.new()
    grass.name = "DenseGrass_%d_%d" % [chunk_x, chunk_z]
    grass.multimesh = multi
    grass.material_override = blade_material
    grass.position = Vector3(center_x, 0.0, center_z)
    grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    grass.visibility_range_begin = 0.0
    grass.visibility_range_end = 110.0
    grass.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
    grass.custom_aabb = AABB(Vector3(-CHUNK_SIZE * 0.5, -8.0, -CHUNK_SIZE * 0.5), Vector3(CHUNK_SIZE, 42.0, CHUNK_SIZE))
    add_child(grass)
