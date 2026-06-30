class_name Worker3D
extends Node3D

# Auto-gathering villager: seek nearest resource -> walk -> harvest -> carry the
# yield to the Keep -> deposit gold -> repeat. Uses a Rogue model (distinct from
# the Knight hero) at the shared character scale.

const CHAR := "res://Models/characters/Rogue.glb"
const CHAR_SCALE := 0.55
const SPEED := 2.2               # slower than the player
const WALK_REF := 1.5            # ground speed where Walking_C looks natural at scale 1
const REACH := 1.4
const DEPOSIT_REACH := 2.0

var game: Node
var model: Node3D
var ap: AnimationPlayer
var anim := ""
var state := "seek"
var target: ResourceNode3D = null
var carry := 0


func setup(g: Node) -> void:
	game = g
	model = (load(CHAR) as PackedScene).instantiate()
	model.scale = Vector3.ONE * CHAR_SCALE
	add_child(model)
	add_child(Rig.blob_shadow())
	ap = Rig.attach(model)
	Rig.set_shadows(model, false)
	_play("Idle_A")


func _process(delta: float) -> void:
	match state:
		"seek": _seek(delta)
		"harvest": _harvest(delta)
		"carry": _carry(delta)


func _seek(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.depleted:
		target = game.nearest_resource(global_position)
	if target == null:
		_play("Idle_A")
		ap.speed_scale = 1.0
		return
	var to: Vector3 = target.global_position - global_position
	if Vector2(to.x, to.z).length() <= REACH:
		state = "harvest"
		return
	_move_toward(target.global_position, delta)


func _harvest(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.depleted:
		state = "seek"
		return
	_face(target.global_position)
	_play("Interact")
	ap.speed_scale = 1.0
	if target.work(delta):
		carry = target.yield_amt
		target = null
		state = "carry"


func _carry(delta: float) -> void:
	var dest: Vector3 = game.keep_pos
	var to: Vector3 = dest - global_position
	if Vector2(to.x, to.z).length() <= DEPOSIT_REACH:
		game.worker_deposit(carry)
		carry = 0
		state = "seek"
		return
	_move_toward(dest, delta)


func _move_toward(p: Vector3, delta: float) -> void:
	var to: Vector3 = p - global_position
	to.y = 0
	var dir := to.normalized()
	global_position += dir * SPEED * delta
	_face(p)
	_play("Walking_C")
	ap.speed_scale = SPEED / WALK_REF   # match feet to ground speed (no skating)


func _face(p: Vector3) -> void:
	var d: Vector3 = p - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		model.rotation.y = atan2(d.x, d.z)


func _play(n: String) -> void:
	if anim == n:
		return
	anim = n
	ap.play(n)
