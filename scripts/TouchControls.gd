class_name TouchControls
extends Control

# Mobile touch layer: a floating virtual joystick (drag anywhere that isn't a
# button) for moving the hero, plus finger-sized action buttons for the things
# that aren't proximity-automatic (place wall, start wave). Works with mouse on
# desktop too (emulate_touch_from_mouse is on).

const RADIUS := 95.0
const DEADZONE := 0.18

var game: Node
var move_vec := Vector2.ZERO          # read by Game each frame (magnitude 0..1)

var _active := false
var _idx := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO

var btn_wall: Button
var btn_wave: Button


func setup(g: Node) -> void:
	game = g


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # let buttons get touches; joystick uses _unhandled_input

	# explicit viewport positions (720x1280), bottom-right cluster
	btn_wave = _make_button("START\nWAVE", Vector2(548, 1118), Color(0.85, 0.45, 0.4))
	btn_wave.pressed.connect(func(): game.start_wave())

	btn_wall = _make_button("BUILD\nWALL", Vector2(548, 968), Color(0.45, 0.55, 0.7))
	btn_wall.pressed.connect(func(): game._place_wall())


func _make_button(text: String, pos: Vector2, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(156, 130)
	b.add_theme_font_size_override("font_size", 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.85)
	sb.set_corner_radius_all(18)
	b.add_theme_stylebox_override("normal", sb)
	var sbp := StyleBoxFlat.new()
	sbp.bg_color = Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, 0.95)
	sbp.set_corner_radius_all(18)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("hover", sb)
	add_child(b)
	return b


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
	draw_circle(_knob, 36.0, Color(1, 1, 1, 0.0))
