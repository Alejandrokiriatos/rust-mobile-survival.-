extends StaticBody3D
class_name SurvivalBuildable

var build_kind := "Refugio"

func _ready() -> void:
    add_to_group("buildables")
    _create_geometry()

func _create_geometry() -> void:
    if build_kind == "Fogata":
        _add_box(Vector3(1.0, 0.22, 1.0), Vector3(0, 0.16, 0), Color(0.25, 0.23, 0.20))
        for i in range(3):
            var log := MeshInstance3D.new()
            var mesh := CylinderMesh.new()
            mesh.top_radius = 0.09
            mesh.bottom_radius = 0.09
            mesh.height = 0.9
            log.mesh = mesh
            log.position = Vector3(0, 0.38, 0).rotated(Vector3.UP, float(i) * TAU / 3.0)
            log.rotation.z = PI * 0.5
            var mat := StandardMaterial3D.new()
            mat.albedo_color = Color(0.28, 0.16, 0.08)
            log.material_override = mat
            add_child(log)
        var flame := MeshInstance3D.new()
        var flame_mesh := SphereMesh.new()
        flame_mesh.radius = 0.28
        flame_mesh.height = 0.65
        flame.mesh = flame_mesh
        flame.position.y = 0.65
        var flame_mat := StandardMaterial3D.new()
        flame_mat.albedo_color = Color(1.0, 0.35, 0.06)
        flame_mat.emission_enabled = true
        flame_mat.emission = Color(1.0, 0.18, 0.015)
        flame_mat.emission_energy_multiplier = 1.8
        flame.material_override = flame_mat
        add_child(flame)
        var light := OmniLight3D.new()
        light.position.y = 1.0
        light.light_color = Color(1.0, 0.42, 0.12)
        light.light_energy = 1.2
        light.omni_range = 7.0
        add_child(light)
    else:
        # Refugio compacto de tablones estilizados, construido con piezas económicas.
        _add_box(Vector3(3.2, 0.18, 2.8), Vector3(0, 0.12, 0), Color(0.30, 0.19, 0.10))
        _add_box(Vector3(0.18, 2.1, 0.18), Vector3(-1.42, 1.12, -1.2), Color(0.34, 0.22, 0.12))
        _add_box(Vector3(0.18, 2.1, 0.18), Vector3(1.42, 1.12, -1.2), Color(0.34, 0.22, 0.12))
        _add_box(Vector3(0.18, 2.1, 0.18), Vector3(-1.42, 1.12, 1.2), Color(0.34, 0.22, 0.12))
        _add_box(Vector3(0.18, 2.1, 0.18), Vector3(1.42, 1.12, 1.2), Color(0.34, 0.22, 0.12))
        _add_box(Vector3(3.0, 0.16, 0.16), Vector3(0, 2.12, -1.2), Color(0.27, 0.16, 0.09))
        _add_box(Vector3(3.0, 0.16, 0.16), Vector3(0, 2.12, 1.2), Color(0.27, 0.16, 0.09))
        _add_box(Vector3(3.5, 0.18, 1.65), Vector3(0, 2.35, 0), Color(0.22, 0.14, 0.08))

func _add_box(dimensions: Vector3, offset: Vector3, color: Color) -> void:
    var visual := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = dimensions
    visual.mesh = mesh
    visual.position = offset
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.9
    visual.material_override = material
    add_child(visual)
