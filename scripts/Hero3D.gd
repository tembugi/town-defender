class_name Hero3D
extends CharacterBody3D

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
var gather_target: Node3D = null # when set, face it (enemy to swing at / node / pad)
var attack_anim_t := 0.0         # >0 while a swing should play, even on the move
var atk_range := 1.6             # attack-cone radius (set by Game3D to match the math)
var atk_arc := 0.785             # attack-cone half-angle
var cone: MeshInstance3D         # the drawn attack cone on the ground
var cone_mat: StandardMaterial3D


func _ready() -> void:
	model = (load(CHAR) as PackedScene).instantiate()
	model.scale = Vector3.ONE * CHAR_SCALE
	add_child(model)
	add_child(Rig.blob_shadow(0.42))
	Rig.make_unit_body(self)
	_build_cone()
	ap = Rig.attach(model)
	_play("Idle_A")


# Flat ground sector showing exactly where a swing connects (apex at the hero,
# half-angle atk_arc, radius atk_range). Faces +Z locally; rotated to match facing.
func _build_cone() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 20
	var y := 0.05
	for i in range(seg):
		var a0: float = lerpf(-atk_arc, atk_arc, float(i) / seg)
		var a1: float = lerpf(-atk_arc, atk_arc, float(i + 1) / seg)
		st.add_vertex(Vector3(0, y, 0))
		st.add_vertex(Vector3(sin(a0) * atk_range, y, cos(a0) * atk_range))
		st.add_vertex(Vector3(sin(a1) * atk_range, y, cos(a1) * atk_range))
	cone = MeshInstance3D.new()
	cone.mesh = st.commit()
	cone_mat = StandardMaterial3D.new()
	cone_mat.albedo_color = Color(1.0, 0.85, 0.3, 0.12)
	cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone.material_override = cone_mat
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cone)


func _physics_process(delta: float) -> void:
	attack_anim_t = maxf(0.0, attack_anim_t - delta)
	var swinging := attack_anim_t > 0.0
	# the cone tracks our facing and flares brighter on a swing
	cone.rotation.y = model.rotation.y
	cone_mat.albedo_color.a = 0.4 if swinging else 0.12
	# move_input is a world-space XZ direction; its magnitude (0..1) is analog throttle
	var mag := minf(move_input.length(), 1.0)
	if mag > 0.15:
		var dir := Vector3(move_input.x, 0.0, move_input.y).normalized()
		var spd := SPEED * mag
		velocity = dir * spd
		move_and_slide()
		if bounds.size != Vector2.ZERO:
			position.x = clampf(position.x, bounds.position.x, bounds.end.x)
			position.z = clampf(position.z, bounds.position.y, bounds.end.y)
		model.rotation.y = atan2(dir.x, dir.z) + FACE_OFFSET
		# swing in our current facing while moving; otherwise normal locomotion
		if swinging:
			_play("Interact")
			ap.speed_scale = 1.4
		elif spd >= RUN_THRESHOLD:
			_play("Running_A")
			ap.speed_scale = clampf(spd / RUN_REF, 0.6, 1.6)
		else:
			_play("Walking_C")
			ap.speed_scale = clampf(spd / WALK_REF, 0.6, 1.8)
		return
	velocity = Vector3.ZERO
	# standing still: swing keeps the last facing (no auto-aim onto enemies)
	if swinging:
		_play("Interact")
		ap.speed_scale = 1.4
	elif gather_target != null and is_instance_valid(gather_target):
		# building on a pad: swing in whatever direction we already face; don't
		# snap to face the pad's centre
		_play("Interact")
		ap.speed_scale = 1.0
	else:
		_play("Idle_A")
		ap.speed_scale = 1.0


func _play(n: String) -> void:
	if anim == n:
		return
	anim = n
	ap.play(n)
