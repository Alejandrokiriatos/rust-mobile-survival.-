extends CharacterBody3D
class_name WildAnimal

@export var move_speed := 2.2
@export var detection_range := 17.0
@export var attack_range := 1.8
@export var damage := 7.0
@export var model_path := ""
@export var species := "Deer"
@export var is_predator := false
@export var model_scale := 1.0

var target: Node3D
var home := Vector3.ZERO
var wander_target := Vector3.ZERO
var wander_timer := 0.0
var attack_timer := 0.0
var flee_timer := 0.0
var health := 60.0
var animation_player: AnimationPlayer
var current_animation := ""
var visual_root: Node3D
var animation_state := "idle"
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func configure(data: Dictionary) -> void:
    species = str(data.get("species", species))
    model_path = str(data.get("path", model_path))
    is_predator = bool(data.get("predator", is_predator))
    move_speed = float(data.get("speed", move_speed))
    model_scale = float(data.get("scale", model_scale))
    damage = float(data.get("damage", damage))

func _ready() -> void:
    add_to_group("wild_animals")
    home = global_position
    _choose_wander_target()
    _build_visual()

func _build_visual() -> void:
    visual_root = Node3D.new()
    visual_root.name = "AnimatedModel"
    visual_root.scale = Vector3.ONE * model_scale
    add_child(visual_root)
    if model_path.is_empty() or not ResourceLoader.exists(model_path):
        push_warning("No se encontró el modelo 3D de " + species + ": " + model_path)
    else:
        var packed := load(model_path) as PackedScene
        if packed != null:
            var instance := packed.instantiate()
            visual_root.add_child(instance)
            var players := instance.find_children("*", "AnimationPlayer", true, false)
            if not players.is_empty():
                animation_player = players[0] as AnimationPlayer
                print(species, " animaciones: ", animation_player.get_animation_list())
        else:
            push_warning("Godot no pudo importar el modelo de " + species)
    # La colisión acompaña la escala visual para evitar animales gigantes
    # con cápsulas de tamaño incorrecto o patas que parecen flotar.
    var collider := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    var base_height := 1.65
    if species in ["Fox", "ShibaInu", "Husky", "Wolf"]:
        base_height = 1.35
    elif species in ["Alpaca", "Donkey"]:
        base_height = 1.48
    shape.radius = (0.38 if not is_predator else 0.43) * model_scale
    shape.height = maxf(0.72, base_height * model_scale)
    collider.shape = shape
    collider.position.y = shape.height * 0.5
    add_child(collider)
    _play_state("idle")

func _physics_process(delta: float) -> void:
    if not is_instance_valid(target):
        var players := get_tree().get_nodes_in_group("player")
        if not players.is_empty():
            target = players[0] as Node3D
    if not is_on_floor():
        velocity.y -= gravity * delta
    var desired := Vector3.ZERO
    var state := "idle"
    if is_instance_valid(target):
        var to_player := target.global_position - global_position
        to_player.y = 0.0
        var distance := to_player.length()
        if is_predator and distance < detection_range:
            if distance > attack_range:
                desired = to_player.normalized() * move_speed * 1.3
                state = "run"
            else:
                attack_timer -= delta
                state = "attack"
                if attack_timer <= 0.0 and target.has_method("take_damage"):
                    target.take_damage(damage)
                    attack_timer = 1.45
        elif not is_predator and distance < 6.0:
            desired = -to_player.normalized() * move_speed * 1.35
            flee_timer = 2.0
            state = "run"
        elif distance > detection_range * 1.6:
            target = null
    if desired.length_squared() < 0.01:
        if flee_timer > 0.0:
            flee_timer -= delta
            var away := global_position - target.global_position if is_instance_valid(target) else global_position - home
            away.y = 0.0
            if away.length_squared() > 0.01:
                desired = away.normalized() * move_speed
                state = "run"
        else:
            wander_timer -= delta
            if wander_timer <= 0.0 or global_position.distance_to(wander_target) < 1.2:
                _choose_wander_target()
            var direction := wander_target - global_position
            direction.y = 0.0
            if direction.length() > 0.5:
                desired = direction.normalized() * move_speed * 0.42
                state = "walk"
    velocity.x = move_toward(velocity.x, desired.x, 7.0 * delta)
    velocity.z = move_toward(velocity.z, desired.z, 7.0 * delta)
    if desired.length_squared() > 0.05:
        look_at(global_position + Vector3(desired.x, 0.0, desired.z), Vector3.UP)
    _play_state(state)
    move_and_slide()

func _play_state(state: String) -> void:
    if animation_player == null:
        return
    var names := animation_player.get_animation_list()
    var wanted := ""
    var terms: Array[String] = []
    match state:
        "run":
            terms = ["run", "gallop", "sprint", "jog", "locomotion"]
        "walk":
            terms = ["walk", "trot", "move", "locomotion"]
        "attack":
            terms = ["attack", "bite"]
        _:
            terms = ["idle", "stand"]
    for term in terms:
        for animation_name in names:
            if str(animation_name).to_lower().contains(term):
                wanted = str(animation_name)
                break
        if not wanted.is_empty():
            break
    # No reproducir una animación arbitraria como sustituto de caminar:
    # algunos paquetes incluyen clips de presentación que dejan las patas quietas.
    if wanted.is_empty():
        if animation_player.is_playing():
            animation_player.stop()
        current_animation = ""
        animation_state = state
        return
    if wanted != current_animation:
        current_animation = wanted
        animation_state = state
        var blend_time := 0.16 if state == "walk" or state == "run" else 0.22
        animation_player.play(wanted, blend_time)
    # Algunos modelos importados traen los ciclos de patas sin repetición.
    # Fuerza bucle solo para locomoción; ataque e idle conservan su duración.
    var selected_animation := animation_player.get_animation(wanted)
    if selected_animation != null:
        if state == "walk" or state == "run":
            selected_animation.loop_mode = Animation.LOOP_LINEAR
        else:
            selected_animation.loop_mode = Animation.LOOP_NONE
    # Ajusta la cadencia del clip a la velocidad real del animal.
    animation_player.speed_scale = 1.35 if state == "run" else (0.82 if state == "walk" else 1.0)

func take_damage(amount: float) -> void:
    if health <= 0.0:
        return
    health = maxf(0.0, health - amount)
    if health <= 0.0:
        # La caza alimenta el ciclo de supervivencia: los animales dejan carne.
        var players := get_tree().get_nodes_in_group("player")
        if not players.is_empty() and players[0] is SurvivalPlayer:
            var hunter := players[0] as SurvivalPlayer
            var meat_yield := randi_range(1, 2) if is_predator else randi_range(2, 4)
            hunter.collect("Comida", meat_yield)
            var world := get_parent()
            if world != null and world.has_method("show_message"):
                world.call("show_message", "Animal cazado: +%d comida" % meat_yield)
        queue_free()

func _choose_wander_target() -> void:
    wander_target = home + Vector3(randf_range(-13.0, 13.0), 0.0, randf_range(-13.0, 13.0))
    wander_timer = randf_range(2.5, 5.0)
