extends Control
class_name MobileJoystick

@export_range(40.0, 120.0, 1.0) var radius := 62.0
@export_range(0.0, 0.4, 0.01) var deadzone := 0.12
@export var base_color := Color(0.025, 0.045, 0.04, 0.62)
@export var knob_color := Color(0.78, 0.86, 0.70, 0.92)

var input_vector := Vector2.ZERO
var _finger_index := -1
var _knob_offset := Vector2.ZERO
var _center := Vector2.ZERO

func _ready() -> void:
    custom_minimum_size = Vector2(156.0, 156.0)
    size = custom_minimum_size
    mouse_filter = Control.MOUSE_FILTER_STOP
    _center = size * 0.5
    queue_redraw()

func _gui_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed and _finger_index == -1:
            _finger_index = event.index
            _update_stick(event.position)
            accept_event()
        elif not event.pressed and event.index == _finger_index:
            _release_stick()
            accept_event()
    elif event is InputEventScreenDrag and event.index == _finger_index:
        _update_stick(event.position)
        accept_event()
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            _finger_index = -2
            _update_stick(event.position)
        else:
            _release_stick()
        accept_event()
    elif event is InputEventMouseMotion and _finger_index == -2:
        _update_stick(event.position)
        accept_event()

func _update_stick(pointer: Vector2) -> void:
    var delta := pointer - _center
    var distance := minf(delta.length(), radius)
    _knob_offset = delta.normalized() * distance if delta.length_squared() > 0.001 else Vector2.ZERO
    var strength := distance / radius
    if strength <= deadzone:
        input_vector = Vector2.ZERO
    else:
        var adjusted := (strength - deadzone) / (1.0 - deadzone)
        input_vector = _knob_offset.normalized() * adjusted
    queue_redraw()

func _release_stick() -> void:
    _finger_index = -1
    _knob_offset = Vector2.ZERO
    input_vector = Vector2.ZERO
    queue_redraw()

func _draw() -> void:
    # Doble aro y centro de alto contraste para distinguir el área táctil del escenario.
    draw_circle(_center, radius + 7.0, Color(0.015, 0.025, 0.02, 0.30))
    draw_circle(_center, radius, base_color)
    draw_arc(_center, radius, 0.0, TAU, 64, Color(0.78, 0.86, 0.74, 0.78), 3.0, true)
    draw_arc(_center, radius * 0.68, 0.0, TAU, 48, Color(0.75, 0.84, 0.72, 0.24), 1.5, true)
    draw_circle(_center + _knob_offset, radius * 0.36, knob_color)
    draw_arc(_center + _knob_offset, radius * 0.36, 0.0, TAU, 48, Color(1.0, 1.0, 0.94, 0.86), 2.0, true)
