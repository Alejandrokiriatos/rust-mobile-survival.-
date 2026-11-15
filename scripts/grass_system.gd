extends Node3D

const WORLD_SIZE := 512.0
const CHUNK_COUNT := 4
const CHUNK_SIZE := WORLD_SIZE / float(CHUNK_COUNT)
const CLUMPS_PER_CHUNK := 35000
const GRASS_HEIGHT := 0.45

var world_ref: Node3D
var rng := RandomNumberGenerator.new()

func build(world: Node3D) -> void:
    world_ref = world
    rng.seed = 73519
    var blade_mesh := _make_blade_cluster()
    var blade_material := _make_wind_material()
    for chunk_z in range(CHUNK_COUNT):
        for chunk_x in range(CHUNK_COUNT):
            _make_chunk(chunk_x, chunk_z, blade_mesh, blade_material)

func _make_blade_cluster() -> ArrayMesh:
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var indices := PackedInt32Array()
    var segments := 3
    var width := 0.04
    var height := GRASS_HEIGHT
    # Tres hojas cruzadas por mata: volumen tupido sin añadir colisiones.
    for blade in range(3):
        var yaw := float(blade) * PI / 3.0
        var direction := Vector3(sin(yaw), 0.0, cos(yaw))
        var side := Vector3(cos(yaw), 0.0, -sin(yaw))
        var base := vertices.size()
        for segment in range(segments + 1):
            var t := float(segment) / float(segments)
            var y := t * height
            var half_width := width * (1.0 - t * 0.82)
            var bend := t * t * 0.075
            var center := direction * bend + Vector3.UP * y
            var left := center - side * half_width
            var right := center + side * half_width
            vertices.append(left)
            vertices.append(right)
            normals.append(Vector3.UP)
            normals.append(Vector3.UP)
            if segment < segments:
                var a := base + segment * 2
                indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func _make_wind_material() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
uniform float wind_strength = 0.045;
uniform float wind_speed = 1.0;
void vertex() {
    float phase = INSTANCE_CUSTOM.r * 6.28318;
    float height_factor = clamp(VERTEX.y / 0.45, 0.0, 1.0);
    float breeze = sin(TIME * wind_speed + phase + VERTEX.x * 4.0 + VERTEX.z * 4.0);
    VERTEX.x += breeze * wind_strength * height_factor * height_factor;
    VERTEX.z += cos(TIME * 0.8 + phase) * wind_strength * 0.55 * height_factor;
}
void fragment() {
    ALBEDO = COLOR.rgb;
    ROUGHNESS = 0.96;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    return material

func _make_chunk(chunk_x: int, chunk_z: int, blade_mesh: Mesh, blade_material: Material) -> void:
    var center_x := -WORLD_SIZE * 0.5 + (float(chunk_x) + 0.5) * CHUNK_SIZE
    var center_z := -WORLD_SIZE * 0.5 + (float(chunk_z) + 0.5) * CHUNK_SIZE
    var multi := MultiMesh.new()
    multi.transform_format = MultiMesh.TRANSFORM_3D
    multi.use_colors = true
    multi.use_custom_data = true
    multi.mesh = blade_mesh
    multi.instance_count = CLUMPS_PER_CHUNK
    var dummy := Transform3D()
    var accepted := 0
    var attempts := 0
    while accepted < CLUMPS_PER_CHUNK and attempts < CLUMPS_PER_CHUNK * 2:
        attempts += 1
        # Muestreo con jitter sobre una rejilla: evita calvas y patrones repetidos.
        var grid_side := ceili(sqrt(float(CLUMPS_PER_CHUNK)))
        var cell_x := accepted % grid_side
        var cell_z := int(accepted / grid_side)
        var cell_size := CHUNK_SIZE / float(grid_side)
        var local_x := -CHUNK_SIZE * 0.5 + (float(cell_x) + rng.randf_range(0.12, 0.88)) * cell_size
        var local_z := -CHUNK_SIZE * 0.5 + (float(cell_z) + rng.randf_range(0.12, 0.88)) * cell_size
        var world_x := center_x + local_x
        var world_z := center_z + local_z
        var ground_y: float = world_ref.call("_height_at", world_x, world_z)
        var normal: Vector3 = world_ref.call("_terrain_normal_at", world_x, world_z)
        var slope := 1.0 - normal.y
        # Hierba solo en suelo firme y praderas: nada de agua, roca alta ni nieve.
        if ground_y <= -2.5 or ground_y > 26.0 or slope > 0.48:
            # Mantiene la distribución uniforme y simplemente deja la mata invisible.
            dummy = Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(local_x, ground_y, local_z))
            multi.set_instance_transform(accepted, dummy)
            multi.set_instance_color(accepted, Color(0.0, 0.0, 0.0, 0.0))
            multi.set_instance_custom_data(accepted, Color(rng.randf(), 0.0, 0.0, 1.0))
            accepted += 1
            continue
        var scale_x := rng.randf_range(0.80, 1.20)
        var scale_y := rng.randf_range(0.50, 1.10)
        var yaw := rng.randf_range(0.0, TAU)
        var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale_x, scale_y, scale_x))
        multi.set_instance_transform(accepted, Transform3D(basis, Vector3(local_x, ground_y + 0.015, local_z)))
        var hue := rng.randf_range(0.25, 0.30)
        var saturation := rng.randf_range(0.50, 0.80)
        var value := rng.randf_range(0.25, 0.50)
        multi.set_instance_color(accepted, Color.from_hsv(hue, saturation, value))
        multi.set_instance_custom_data(accepted, Color(rng.randf(), 0.0, 0.0, 1.0))
        accepted += 1
    var grass_instance := MultiMeshInstance3D.new()
    grass_instance.name = "DenseGrass_%d_%d" % [chunk_x, chunk_z]
    grass_instance.multimesh = multi
    grass_instance.material_override = blade_material
    grass_instance.position = Vector3(center_x, 0.0, center_z)
    grass_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    grass_instance.visibility_range_begin = 0.0
    grass_instance.visibility_range_end = 110.0
    grass_instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
    grass_instance.custom_aabb = AABB(Vector3(-CHUNK_SIZE * 0.5, -8.0, -CHUNK_SIZE * 0.5), Vector3(CHUNK_SIZE, 42.0, CHUNK_SIZE))
    add_child(grass_instance)
