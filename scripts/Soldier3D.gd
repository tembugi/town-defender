class_name Soldier3D
extends Node3D

# A Barracks defender (Barbarian). Holds a guard post near the Keep; charges and
# attacks enemies that come within the Keep's defensive leash, then returns.

const CHAR := "res://Models/characters/Barbarian.glb"
const CHAR_SCALE := 0.55
const WALK_REF := 1.5
const SPEED := 3.0
const DAMAGE := 20.0
const ATK_CD := 0.7
const REACH := 1.8
const SIGHT := 9.0
const LEASH := 11.0     # only engage enemies this close to the Keep

var game: Node
var model: Node3D
var ap: AnimationPlayer
var anim := ""
var guard_pos: Vector3
var atk_cd := 0.0


func setup(g: Node, gpos: Vector3) -> void:
	game = g
	guard_pos = gpos
	model = (load(CHAR) as PackedScene).instantiate()
	model.scale = Vector3.ONE * CHAR_SCALE
	add_child(model)
	ap = Rig.attach(model, "adventurer")
	_play("Idle_A")


func _process(delta: float) -> void:
	atk_cd -= delta
	var e := _target()
	if e != null:
		var to: Vector3 = e.global_position - global_position
		if Vector2(to.x, to.z).length() <= REACH:
			_face(e.global_position)
			_play("Interact")
			ap.speed_scale = 1.0
			if atk_cd <= 0.0:
				atk_cd = ATK_CD
				e.take_damage(DAMAGE)
		else:
			_move_toward(e.global_position, delta)
	else:
		var d: Vector3 = guard_pos - global_position
		if Vector2(d.x, d.z).length() > 0.4:
			_move_toward(guard_pos, delta)
		else:
			_play("Idle_A")
			ap.speed_scale = 1.0


func _target() -> Enemy3D:
	if not is_instance_valid(game.keep_node) or game.keep_hp <= 0:
		return null
	var e: Enemy3D = game.nearest_enemy(global_position, SIGHT)
	if e == null:
		return null
	var to_keep: Vector3 = e.global_position - game.keep_pos
	if Vector2(to_keep.x, to_keep.z).length() > LEASH:
		return null
	return e


func _move_toward(p: Vector3, delta: float) -> void:
	var to: Vector3 = p - global_position
	to.y = 0
	global_position += to.normalized() * SPEED * delta
	_face(p)
	_play("Walking_C")
	ap.speed_scale = SPEED / WALK_REF


func _face(p: Vector3) -> void:
	var d: Vector3 = p - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		model.rotation.y = atan2(d.x, d.z)


func _play(n: String) -> void:
	if anim == n:
		return
	anim = n
	ap.play(n)
