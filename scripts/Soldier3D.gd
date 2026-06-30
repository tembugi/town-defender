class_name Soldier3D
extends CharacterBody3D

# A Barracks defender (Barbarian). Holds a guard post near the Keep; charges and
# attacks enemies that come within the Keep's defensive leash, then returns.

const CHAR := "res://Models/characters/Barbarian.glb"
const CHAR_SCALE := 0.55
const WALK_REF := 1.5
const SPEED := 2.1     # ~50% of player speed
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
	add_child(Rig.blob_shadow(0.42))
	Rig.make_unit_body(self)
	ap = Rig.attach(model, "adventurer")
	Rig.set_shadows(model, false)
	_play("Idle_A")


func _physics_process(delta: float) -> void:
	atk_cd -= delta
	var e := _target()
	if e != null:
		var to: Vector3 = e.global_position - global_position
		if Vector2(to.x, to.z).length() <= REACH:
			_face(e.global_position)
			_play("Melee_1H_Attack_Chop")
			ap.speed_scale = 1.0
			if atk_cd <= 0.0:
				atk_cd = ATK_CD
				anim = ""   # restart the swing clip on each strike
				_strike(e)
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


# damage lands partway through the swing, not the instant we're in range
func _strike(e: Enemy3D) -> void:
	var tgt := e
	get_tree().create_timer(0.3).timeout.connect(func():
		if is_instance_valid(tgt) and not tgt.dead:
			var d := Vector2(tgt.global_position.x - global_position.x, tgt.global_position.z - global_position.z).length()
			if d <= REACH + 0.6:
				tgt.take_damage(DAMAGE))


func _move_toward(p: Vector3, _delta: float) -> void:
	var to: Vector3 = p - global_position
	to.y = 0
	velocity = to.normalized() * SPEED
	move_and_slide()
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
