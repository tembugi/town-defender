class_name BuildPad
extends Node2D

# A build pad: a green foundation square + a sign (icon + cost) + a bobbing
# arrow when affordable. Stand on it with enough gold and a build-progress bar
# fills; when full, the building is constructed in place. (Modelled on the
# Sunnyside "stand and work to build" reference.)

const BUILD_TIME := 1.3

var game: Node
var btype: String
var cost: int
var icon_path: String
var label: String

var built := false
var progress := 0.0
var _near := false
var _affordable := false

var icon: Sprite2D
var arrow: Sprite2D
var cost_label: Label
var name_label: Label


func setup(g: Node, type: String, c: int, ipath: String, lbl: String) -> void:
	game = g
	btype = type
	cost = c
	icon_path = ipath
	label = lbl


func _ready() -> void:
	z_index = -1   # ground decal

	icon = Sprite2D.new()
	icon.texture = load(icon_path)
	icon.scale = Vector2(1.4, 1.4)
	icon.position = Vector2(0, -30)
	add_child(icon)

	# Labels scale down by 1/zoom so they render at screen resolution, not
	# upscaled from tiny world-space pixels. Font sizes are chosen for 3x zoom.
	var zoom := 3.0
	var inv := 1.0 / zoom

	cost_label = Label.new()
	cost_label.text = "%dg" % cost
	cost_label.add_theme_font_size_override("font_size", 22)
	cost_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	cost_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	cost_label.add_theme_constant_override("outline_size", 6)
	cost_label.scale = Vector2(inv, inv)
	cost_label.position = Vector2(2, -32)
	add_child(cost_label)

	name_label = Label.new()
	name_label.text = label
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	name_label.add_theme_constant_override("outline_size", 6)
	name_label.scale = Vector2(inv, inv)
	name_label.position = Vector2(-20, -48)
	add_child(name_label)

	arrow = Sprite2D.new()
	arrow.texture = load("res://Assets/UI/arrow_up.png")
	arrow.flip_v = true
	arrow.scale = Vector2(1.3, 1.3)
	add_child(arrow)


func _process(delta: float) -> void:
	if built:
		return
	_near = game.hero.position.distance_to(position) < 20.0
	_affordable = game.gold >= cost

	if _near and _affordable:
		progress += delta / BUILD_TIME
		if progress >= 1.0:
			_finish()
			return
	else:
		progress = maxf(0.0, progress - delta * 0.9)

	arrow.visible = _affordable and not _near
	arrow.position = Vector2(0, -56 + sin(Time.get_ticks_msec() / 200.0) * 2.5)
	icon.modulate = Color.WHITE if _affordable else Color(0.55, 0.55, 0.55)
	cost_label.modulate = Color.WHITE if _affordable else Color(0.9, 0.5, 0.5)
	queue_redraw()


func _finish() -> void:
	built = true
	game.spend_gold(cost)
	game.spawn_building(btype, position)
	icon.queue_free()
	arrow.queue_free()
	cost_label.queue_free()
	name_label.queue_free()
	queue_redraw()


func _draw() -> void:
	if built:
		return
	var edge := Color(0.25, 0.7, 0.3) if _affordable else Color(0.45, 0.45, 0.45)
	var fill := Color(0.4, 0.85, 0.4, 0.35) if _affordable else Color(0.5, 0.5, 0.5, 0.28)
	var r := Rect2(-16, -16, 32, 32)
	draw_rect(r, fill, true)
	# dashed border
	var step := 5.0
	var corners := [Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16), Vector2(-16, -16)]
	for i in range(4):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[i + 1]
		var d := (b - a)
		var n := int(d.length() / step)
		for s in range(0, n, 2):
			draw_line(a + d * (float(s) / n), a + d * (float(s + 1) / n), edge, 1.5)

	if progress > 0.0:
		var w := 28.0
		draw_rect(Rect2(-w / 2.0, 20, w, 4), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(-w / 2.0, 20, w * progress, 4), Color(0.3, 0.9, 0.4))
