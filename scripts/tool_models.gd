extends RefCounted
class_name SurvivalToolModels

const WOOD := Color(0.29, 0.16, 0.075)
const WOOD_LIGHT := Color(0.48, 0.29, 0.13)
const STONE := Color(0.43, 0.45, 0.43)
const STONE_EDGE := Color(0.61, 0.62, 0.58)
const ROPE := Color(0.69, 0.57, 0.37)

static func _material(color: Color, roughness: float = 0.88, metallic: float = 0.0, emission: Color = Color.BLACK) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    if emission != Color.BLACK:
        material.emission_enabled = true
        material.emission = emission
        material.emission_energy_multiplier = 2.2
    return material

static func _mesh(parent: Node3D, mesh_resource: Mesh, material: Material, position: Vector3 = Vector3.ZERO, rotation: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.mesh = mesh_resource
    instance.material_override = material
    instance.position = position
    instance.rotation = rotation
    instance.scale = scale
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(instance)
    return instance

static func _cylinder(radius: float, height: float, radial: int = 12) -> CylinderMesh:
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius * 0.82
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.radial_segments = radial
    mesh.rings = 1
    return mesh

static func _binding(parent: Node3D, y: float, radius: float = 0.052) -> void:
    var ring := TorusMesh.new()
    ring.inner_radius = radius * 0.82
    ring.outer_radius = radius
    ring.rings = 6
    ring.ring_segments = 12
    _mesh(parent, ring, _material(ROPE), Vector3(0, y, 0))

static func _handle(parent: Node3D, height: float = 1.25) -> void:
    _mesh(parent, _cylinder(0.043, height, 10), _material(WOOD), Vector3(0, height * 0.5, 0), Vector3.ZERO, Vector3(1, 1, 1))
    var grip := _cylinder(0.047, 0.25, 10)
    _mesh(parent, grip, _material(WOOD_LIGHT), Vector3(0, 0.16, 0))

static func create_tool(kind: String) -> Node3D:
    var root := Node3D.new()
    root.name = "Tool_" + kind
    match kind.to_lower():
        "axe", "hacha":
            _handle(root, 1.32)
            var blade := BoxMesh.new()
            blade.size = Vector3(0.48, 0.39, 0.105)
            _mesh(root, blade, _material(STONE_EDGE), Vector3(0.22, 1.13, 0), Vector3(0, 0, -0.18))
            var edge := BoxMesh.new()
            edge.size = Vector3(0.12, 0.31, 0.12)
            _mesh(root, edge, _material(STONE), Vector3(0.47, 1.12, 0), Vector3(0, 0, -0.42))
            for y in [0.91, 1.00, 1.09]:
                _binding(root, y)
        "pickaxe", "pico":
            _handle(root, 1.34)
            var head := CylinderMesh.new()
            head.top_radius = 0.055
            head.bottom_radius = 0.055
            head.height = 0.92
            head.radial_segments = 8
            _mesh(root, head, _material(STONE_EDGE), Vector3(0, 1.25, 0), Vector3(0, 0, PI * 0.5))
            var tip := CylinderMesh.new()
            tip.top_radius = 0.006
            tip.bottom_radius = 0.075
            tip.height = 0.30
            tip.radial_segments = 7
            _mesh(root, tip, _material(STONE), Vector3(0.56, 1.25, 0), Vector3(0, 0, -PI * 0.5))
            _mesh(root, tip, _material(STONE), Vector3(-0.56, 1.25, 0), Vector3(0, 0, PI * 0.5))
            for y in [1.08, 1.17, 1.26, 1.35]:
                _binding(root, y)
        "stone", "piedra":
            var rock := SphereMesh.new()
            rock.radius = 0.34
            rock.height = 0.62
            rock.radial_segments = 8
            rock.rings = 5
            _mesh(root, rock, _material(STONE), Vector3(0, 0.38, 0), Vector3(0.3, 0.2, 0.4), Vector3(1.0, 0.78, 0.72))
            var chip := SphereMesh.new()
            chip.radius = 0.16
            chip.height = 0.28
            chip.radial_segments = 7
            chip.rings = 4
            _mesh(root, chip, _material(STONE_EDGE), Vector3(0.20, 0.54, 0.12), Vector3(0.4, 0.2, 0.1))
        "torch", "antorcha":
            _handle(root, 1.15)
            var wrap := _cylinder(0.075, 0.20, 8)
            _mesh(root, wrap, _material(Color(0.16, 0.13, 0.10)), Vector3(0, 1.13, 0))
            var flame := SphereMesh.new()
            flame.radius = 0.14
            flame.height = 0.42
            flame.radial_segments = 8
            flame.rings = 5
            _mesh(root, flame, _material(Color(1.0, 0.42, 0.07), 0.35, 0.0, Color(1.0, 0.22, 0.025)), Vector3(0, 1.43, 0), Vector3(0, 0, 0.12), Vector3(0.72, 1.45, 0.72))
            var inner := SphereMesh.new()
            inner.radius = 0.075
            inner.height = 0.22
            inner.radial_segments = 7
            inner.rings = 4
            _mesh(root, inner, _material(Color(1.0, 0.83, 0.32), 0.25, 0.0, Color(1.0, 0.62, 0.12)), Vector3(0, 1.40, -0.025))
            var light := OmniLight3D.new()
            light.name = "TorchLight"
            light.position = Vector3(0, 1.47, 0.02)
            light.light_color = Color(1.0, 0.56, 0.22)
            light.light_energy = 1.8
            light.omni_range = 8.0
            light.shadow_enabled = false
            root.add_child(light)
        _:
            return root
    return root

static func create_display_tool(kind: String, target_height: float = 1.0) -> Node3D:
    var model := create_tool(kind)
    var bounds := _bounds(model)
    if bounds.size.y > 0.001:
        var factor := target_height / bounds.size.y
        model.scale = Vector3.ONE * factor
        model.position = -bounds.position * factor - Vector3(0, bounds.size.y * factor * 0.5, 0)
    return model

static func _bounds(node: Node) -> AABB:
    var result := AABB()
    var found := false
    for child in node.get_children():
        if child is MeshInstance3D and child.mesh != null:
            var box: AABB = (child as MeshInstance3D).mesh.get_aabb()
            box = box * (child as MeshInstance3D).transform
            result = result.merge(box) if found else box
            found = true
    return result if found else AABB(Vector3.ZERO, Vector3.ONE)
