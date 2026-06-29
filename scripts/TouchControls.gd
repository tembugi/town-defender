class_name TouchControls
extends Control

# Mobile touch layer: a floating virtual joystick (drag anywhere that isn't a
# button) to move the hero, plus finger-sized action buttons. Buttons are
# positioned from the live viewport size (and re-laid-out on resize) so they
# always hug the real bottom-right corner on any aspect ratio. Works with the
# mouse on desktop too (emulate_touch_from_mouse is on).

const RADIUS := 95.0
const DEADZONE := 0.18
const BTN_W := 156.0
const BTN_H := 130.0
const MARGIN := 24.0
const BOTTOM := 44.0
const GAP := 16.0

var game: Node
var move_vec := Vector2.ZERO

var _active := false
var _idx := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO

var btn_wall: Button
var btn_wave: Button
var btn_hire: Button


func setup(g: Node) -> void:
	game = g


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	btn_wave = _make_button("START\nWAVE", Color(0.85, 0.45, 0.4))
	btn_wave.pressed.connect(func(): game.start_wave())
	btn_wall = _make_button("BUILD\nWALL", Color(0.45, 0.55, 0.7))
	btn_wall.pressed.connect(func(): game._place_wall())
	btn_hire = _make_button("HIRE\nWORKER", Color(0.45, 0.7, 0.45))
	btn_hire.pressed.connect(func(): game.hire_worker())

	get_viewport().size_changed.connect(_layout)
	_layout()
	_layout.call_deferred()   # ensure correct after first layout pass


func _make_button(text: String, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.size = Vector2(BTN_W, BTN_H)
	b.add_theme_font_size_override("font_size", 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.88)
	sb.set_corner_radius_all(18)
	b.add_theme_stylebox_override("normal", sb)
	var sbp := StyleBoxFlat.new()
	sbp.bg_color = Color(col.r * 0.7, col.g * 0.7, col.b * 0.7, 0.96)
	sbp.set_corner_radius_all(18)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("hover", sb)
	add_child(b)
	return b


func _layout() -> void:
	var vp := get_viewport_rect().size
	var x := vp.x - MARGIN - BTN_W
	btn_wave.position = Vector2(x, vp.y - BOTTOM - BTN_H)
	btn_wall.position = Vector2(x, vp.y - BOTTOM - BTN_H * 2.0 - GAP)
	btn_hire.position = Vector2(x, vp.y - BOTTOM - BTN_H * 3.0 - GAP * 2.0)


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
