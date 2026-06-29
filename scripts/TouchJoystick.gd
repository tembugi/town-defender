class_name TouchJoystick
extends Control

# Minimal floating virtual joystick for the 3D game: drag anywhere to steer.
# Exposes move_vec (Vector2, magnitude 0..1). Works with mouse on desktop
# (emulate_touch_from_mouse is on).

const RADIUS := 95.0
const DEADZONE := 0.18

var move_vec := Vector2.ZERO
var _active := false
var _idx := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if not _active:
				_active = true
				_idx = event.index
				_origin = event.position
				_knob = event.position
		elif event.index == _idx:
			_active = false
			_idx = -1
			move_vec = Vector2.ZERO
		queue_redraw()
	elif event is InputEventScreenDrag and _active and event.index == _idx:
		var off: Vector2 = event.position - _origin
		if off.length() > RADIUS:
			off = off.normalized() * RADIUS
		_knob = _origin + off
		var v: Vector2 = off / RADIUS
		move_vec = v if v.length() > DEADZONE else Vector2.ZERO
		queue_redraw()


func _draw() -> void:
	if not _active:
		return
	draw_circle(_origin, RADIUS, Color(1, 1, 1, 0.10))
	draw_arc(_origin, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.35), 4.0, true)
	draw_circle(_knob, 36.0, Color(1, 1, 1, 0.45))
