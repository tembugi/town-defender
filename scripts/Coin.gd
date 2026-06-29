class_name Coin
extends Node2D

# A collectable gold coin lying on the ground. Drawn procedurally so we don't
# depend on a coin sprite. Bobs gently; the player walks over it to collect.

var value: int = 1
var _t: float = 0.0

func _ready() -> void:
	_t = randf() * TAU
	z_index = -1   # ground decal: always under the hero/buildings

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var bob := sin(_t * 3.0) * 1.2
	var c := Vector2(0, bob)
	# soft shadow on the ground
	draw_circle(Vector2(0, 2), 4.5, Color(0, 0, 0, 0.18))
	# coin body + rim + shine
	draw_circle(c, 5.0, Color(0.78, 0.55, 0.12))
	draw_circle(c, 4.0, Color(0.98, 0.80, 0.22))
	draw_circle(c + Vector2(-1.4, -1.4), 1.4, Color(1.0, 0.96, 0.75))
