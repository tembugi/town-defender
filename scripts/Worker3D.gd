class_name Worker3D
extends CharacterBody3D

# Villager labour loop: fell a resource node (which drops resources on the
# ground) -> fetch a loose drop -> haul it to the Keep -> deposit gold -> repeat.
# Also hauls drops made by the hero. Uses a Rogue model at the shared scale.

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
var target: ResourceNode3D = null    # node we're felling
var carry_drop: ResourceDrop3D = null # drop we've reserved/are fetching
var carry := 0                       # resources in hand, heading to the Keep
var carry_visual: MeshInstance3D


func setup(g: Node) -> void:
	game = g
	model = (load(CHAR) as PackedScene).instantiate()
	model.scale = Vector3.ONE * CHAR_SCALE
	add_child(model)
	add_child(Rig.blob_shadow())
	Rig.make_unit_body(self)
	ap = Rig.attach(model)
	Rig.set_shadows(model, false)
	# little box shown over the head while hauling resources
	carry_visual = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.24, 0.3)
	carry_visual.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.42, 0.22)
	carry_visual.material_override = mat
	carry_visual.position = Vector3(0, 1.7, 0)
	carry_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	carry_visual.visible = false
	add_child(carry_visual)
	_play("Idle_A")


func _physics_process(delta: float) -> void:
	match state:
		"seek": _seek(delta)
		"harvest": _harvest(delta)
		"fetch": _fetch(delta)
		"carry": _carry(delta)


func _seek(delta: float) -> void:
	# prefer hauling resources already lying around (incl. ones the hero felled)
	if carry_drop == null:
		carry_drop = game.claim_drop(global_position)
	if carry_drop != null:
		state = "fetch"
		return
	# nothing loose: go fell a node to produce some
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
		game.spawn_drop(target.global_position, target.yield_amt, target.ntype)
		target = null
		state = "seek"   # next tick we'll claim a drop (likely the one just made)


func _fetch(delta: float) -> void:
	if carry_drop == null or not is_instance_valid(carry_drop) or carry_drop.taken:
		carry_drop = null
		state = "seek"
		return
	var to: Vector3 = carry_drop.global_position - global_position
	if Vector2(to.x, to.z).length() <= REACH:
		carry = carry_drop.pick_up()
		carry_drop = null
		carry_visual.visible = true
		state = "carry"
		return
	_move_toward(carry_drop.global_position, delta)


func _carry(delta: float) -> void:
	var dest: Vector3 = game.keep_pos
	var to: Vector3 = dest - global_position
	if Vector2(to.x, to.z).length() <= DEPOSIT_REACH:
		game.worker_deposit(carry)
		carry = 0
		carry_visual.visible = false
		state = "seek"
		return
	_move_toward(dest, delta)


func _move_toward(p: Vector3, _delta: float) -> void:
	var to: Vector3 = p - global_position
	to.y = 0
	velocity = to.normalized() * SPEED
	move_and_slide()
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
