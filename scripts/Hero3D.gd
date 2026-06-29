class_name Hero3D
extends Node3D

# Player-controlled hero. Moves on the ground (XZ) from a 2D input vector set by
# Game3D each frame (joystick / WASD), faces its movement, and blends idle/walk.

const CHAR := "res://Models/characters/Knight.glb"
const SPEED := 5.0
# KayKit characters face -Z by default; flip if the model looks backwards.
const FACE_OFFSET := PI

var model: Node3D
var ap: AnimationPlayer
var anim := ""
var move_input := Vector2.ZERO   # x = world X, y = world Z (set by Game3D)
var bounds := Rect2()            # XZ play area; clamp position when set


func _ready() -> void:
	model = (load(CHAR) as PackedScene).instantiate()
	add_child(model)
	ap = Rig.attach(model)
	_play("Idle_A")


func _process(delta: float) -> void:
	var dir := Vector3(move_input.x, 0.0, move_input.y)
	if dir.length() > 0.15:
		dir = dir.normalized()
		position += dir * SPEED * delta
		if bounds.size != Vector2.ZERO:
			position.x = clampf(position.x, bounds.position.x, bounds.end.x)
			position.z = clampf(position.z, bounds.position.y, bounds.end.y)
		model.rotation.y = atan2(dir.x, dir.z) + FACE_OFFSET
		_play("Walking_C")
	else:
		_play("Idle_A")


func _play(n: String) -> void:
	if anim == n:
		return
	anim = n
	ap.play(n)
