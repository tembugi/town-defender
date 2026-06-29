class_name Hero3D
extends Node3D

# Player-controlled hero. Moves on the ground (XZ) from a 2D input vector set by
# Game3D each frame (joystick / WASD), faces its movement, and blends idle/walk.

const CHAR := "res://Models/characters/Knight.glb"
const SPEED := 4.2                # max move speed (full joystick = run)
const RUN_THRESHOLD := 2.0        # world speed above which we use the run clip
const WALK_REF := 1.5             # ground speed where Walking_C looks natural at scale 1
const RUN_REF := 4.2              # ground speed where Running_A looks natural at scale 1
# Adventurers are ~2x the Hexagon pack scale; shrink so units fit on hex tiles.
const CHAR_SCALE := 0.55
# KayKit characters face +Z, matching atan2(dir.x, dir.z); no offset needed.
const FACE_OFFSET := 0.0

var model: Node3D
var ap: AnimationPlayer
var anim := ""
var move_input := Vector2.ZERO   # x = world X, y = world Z (set by Game3D)
var bounds := Rect2()            # XZ play area; clamp position when set


func _ready() -> void:
	model = (load(CHAR) as PackedScene).instantiate()
	model.scale = Vector3.ONE * CHAR_SCALE
	add_child(model)
	ap = Rig.attach(model)
	_play("Idle_A")


func _process(delta: float) -> void:
	# move_input is a world-space XZ direction; its magnitude (0..1) is analog throttle
	var mag := minf(move_input.length(), 1.0)
	if mag > 0.15:
		var dir := Vector3(move_input.x, 0.0, move_input.y).normalized()
		var spd := SPEED * mag
		position += dir * spd * delta
		if bounds.size != Vector2.ZERO:
			position.x = clampf(position.x, bounds.position.x, bounds.end.x)
			position.z = clampf(position.z, bounds.position.y, bounds.end.y)
		model.rotation.y = atan2(dir.x, dir.z) + FACE_OFFSET
		# walk for slow, run for fast; scale playback to ground speed so feet don't slide
		if spd >= RUN_THRESHOLD:
			_play("Running_A")
			ap.speed_scale = clampf(spd / RUN_REF, 0.6, 1.6)
		else:
			_play("Walking_C")
			ap.speed_scale = clampf(spd / WALK_REF, 0.6, 1.8)
	else:
		_play("Idle_A")
		ap.speed_scale = 1.0


func _play(n: String) -> void:
	if anim == n:
		return
	anim = n
	ap.play(n)
