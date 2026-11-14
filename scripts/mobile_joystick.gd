extends Control
class_name MobileJoystick

@export_range(40.0, 120.0, 1.0) var radius := 66.0
@export_range(0.0, 0.4, 0.01) var deadzone := 0.12
@export var base_color := Color(0.04, 0.09, 0.07, 0.48)
@export var knob_color := Color(0.72, 0.88, 0.72, 0.72)

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
    draw_circle(_center, radius, base_color)
    draw_arc(_center, radius, 0.0, TAU, 48, Color(0.82, 0.92, 0.82, 0.52), 3.0, true)
    draw_circle(_center + _knob_offset, radius * 0.39, knob_color)
    draw_arc(_center + _knob_offset, radius * 0.39, 0.0, TAU, 36, Color(1, 1, 1, 0.45), 2.0, true)
