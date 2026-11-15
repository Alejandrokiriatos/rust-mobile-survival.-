extends Node3D

# Manto de hierba local: 40.000 hojas triangulares en un radio de 20 metros.
const GRASS_RADIUS := 20.0
const GRASS_INSTANCE_COUNT := 40000
const CARPET_RESOLUTION := 48
const MIN_BLADE_HEIGHT := 0.25
const MAX_BLADE_HEIGHT := 0.65

var world_ref: Node3D
var rng := RandomNumberGenerator.new()

func build(world: Node3D) -> void:
    world_ref = world
    rng.seed = 73519
    var center := Vector3.ZERO
    if world_ref.get("player") != null and is_instance_valid(world_ref.get("player")):
        center = world_ref.get("player").global_position
    _make_green_carpet(center)
    _make_instanced_grass(center)

func _make_leaf_mesh() -> ArrayMesh:
    # Una hoja triangular real: base ancha, punta fina y una ligera curvatura.
    var vertices := PackedVector3Array([
        Vector3(-0.032, 0.0, 0.0),
        Vector3(0.032, 0.0, 0.0),
        Vector3(0.0, 0.52, 0.025)
    ])
    var colors := PackedColorArray([
        Color(0.12, 0.30, 0.055),
        Color(0.16, 0.39, 0.07),
        Color(0.48, 0.64, 0.16)
    ])
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1])
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func _make_leaf_material() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
uniform float wind_strength = 0.045;
uniform float wind_speed = 1.15;
void vertex() {
    float phase = INSTANCE_CUSTOM.r * 6.2831853;
    float h = clamp(VERTEX.y / 0.52, 0.0, 1.0);
    float breeze = sin(TIME * wind_speed + phase + INSTANCE_CUSTOM.g * 5.0);
    VERTEX.x += breeze * wind_strength * h * h;
    VERTEX.z += cos(TIME * wind_speed * 0.73 + phase) * wind_strength * 0.45 * h * h;
}
void fragment() {
    ALBEDO = COLOR.rgb;
    ROUGHNESS = 1.0;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    return material

func _make_green_carpet(center: Vector3) -> void:
    # Superficie verde continua debajo de las hojas para que la tierra no
    # quede expuesta entre las instancias. Sigue la altura real del terreno.
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var indices := PackedInt32Array()
    var diameter := GRASS_RADIUS * 2.0
    var step := diameter / float(CARPET_RESOLUTION)
    for z in range(CARPET_RESOLUTION + 1):
        for x in range(CARPET_RESOLUTION + 1):
            var lx := -GRASS_RADIUS + float(x) * step
            var lz := -GRASS_RADIUS + float(z) * step
            var wx := center.x + lx
            var wz := center.z + lz
            var gy: float = world_ref.call("_height_at", wx, wz)
            vertices.append(Vector3(lx, gy + 0.006, lz))
            normals.append(world_ref.call("_terrain_normal_at", wx, wz))
            if x < CARPET_RESOLUTION and z < CARPET_RESOLUTION:
                var a := z * (CARPET_RESOLUTION + 1) + x
                var b := a + 1
                var c := a + CARPET_RESOLUTION + 1
                var d := c + 1
                var cell_center := Vector2(lx + step * 0.5, lz + step * 0.5)
                if cell_center.length() <= GRASS_RADIUS:
                    indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.105, 0.205, 0.045)
    material.roughness = 1.0
    var carpet := MeshInstance3D.new()
    carpet.name = "GrassCarpet_20m"
    carpet.mesh = mesh
    carpet.material_override = material
    carpet.position = Vector3(center.x, 0.0, center.z)
    carpet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(carpet)

func _make_instanced_grass(center: Vector3) -> void:
    var leaf_mesh := _make_leaf_mesh()
    var multi := MultiMesh.new()
    multi.transform_format = MultiMesh.TRANSFORM_3D
    multi.use_colors = true
    multi.use_custom_data = true
    multi.mesh = leaf_mesh
    multi.instance_count = GRASS_INSTANCE_COUNT

    for i in range(GRASS_INSTANCE_COUNT):
        # Distribución uniforme en un disco de radio 20 m.
        var angle := rng.randf_range(0.0, TAU)
        var distance := GRASS_RADIUS * sqrt(rng.randf())
        var wx := center.x + cos(angle) * distance
        var wz := center.z + sin(angle) * distance
        var gy: float = world_ref.call("_height_at", wx, wz)
        var normal: Vector3 = world_ref.call("_terrain_normal_at", wx, wz)

        # Evitar colocar hierba en agua, acantilados o cimas rocosas.
        if gy <= -2.5 or gy > 26.0 or 1.0 - normal.y > 0.48:
            multi.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3(0.0, -100.0, 0.0)))
            multi.set_instance_color(i, Color.WHITE)
            multi.set_instance_custom_data(i, Color.ZERO)
            continue

        var height_scale := rng.randf_range(0.5, 1.3)
        var width_scale := rng.randf_range(0.8, 1.35)
        var yaw := rng.randf_range(0.0, TAU)
        var lean := rng.randf_range(-0.13, 0.13)
        var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, lean)
        basis = basis.scaled(Vector3(width_scale, height_scale, width_scale))
        multi.set_instance_transform(i, Transform3D(basis, Vector3(wx - center.x, gy + 0.008, wz - center.z)))

        # Verde natural aleatorio, de sombra profunda a puntas claras.
        var hue := rng.randf_range(0.23, 0.31)
        var saturation := rng.randf_range(0.52, 0.78)
        var value := rng.randf_range(0.30, 0.57)
        multi.set_instance_color(i, Color.from_hsv(hue, saturation, value))
        multi.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), 0.0, 1.0))

    var grass := MultiMeshInstance3D.new()
    grass.name = "Grass_40000_TriangularBlades"
    grass.multimesh = multi
    grass.material_override = _make_leaf_material()
    grass.position = Vector3(center.x, 0.0, center.z)
    grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    grass.custom_aabb = AABB(Vector3(-GRASS_RADIUS, -8.0, -GRASS_RADIUS), Vector3(GRASS_RADIUS * 2.0, 42.0, GRASS_RADIUS * 2.0))
    add_child(grass)
