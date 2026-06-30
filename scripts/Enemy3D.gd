class_name Enemy3D
extends CharacterBody3D

# A skeleton raider. Walks to the Keep and attacks it; has HP, dies with the
# death animation, and rewards gold. Uses the skeleton's own Rig_Medium anims.

const CHAR := "res://Models/enemies/Skeleton_Minion.glb"
const CHAR_SCALE := 0.55
const WALK_REF := 1.5
const ATTACK_RANGE := 2.2
const SEP_RADIUS := 1.4     # raiders push apart within this distance...
const SEP_WEIGHT := 1.3     # ...strongly enough to flow around each other to open gaps
const TANGENT_WEIGHT := 1.4 # sidestep force when a neighbour blocks the path to the Keep

signal died(reward: int, pos: Vector3)

var game: Node
var model: Node3D
var ap: AnimationPlayer
var anim := ""
var max_hp := 40.0
var hp := 40.0
var dmg := 6.0
var reward := 5
var speed := 1.6
var atk_interval := 1.2
var atk_cd := 0.0
var dead := false
var hpbar: Node3D
var bar_fill: MeshInstance3D
var hit_t := 0.0          # >0 while showing a flinch reaction
var hit_clip := "Hit_A"
var spawn_t := 0.0        # >0 while rising from the ground (no acting yet)


func setup(g: Node, cfg: Dictionary) -> void:
	game = g
	max_hp = cfg.get("hp", 40.0)
	hp = max_hp
	dmg = cfg.get("dmg", 6.0)
	reward = cfg.get("reward", 5)
	speed = cfg.get("speed", 1.6)
	model = (load(CHAR) as PackedScene).instantiate()
	model.scale = Vector3.ONE * CHAR_SCALE
	add_child(model)
	add_child(Rig.blob_shadow())
	Rig.make_unit_body(self)
	ap = Rig.attach(model, "skeleton")
	Rig.set_shadows(model, false)   # perf: skeletons don't cast shadows
	add_to_group("enemies")
	_make_hpbar()
	# rise out of the ground before marching
	var sa := ap.get_animation("Spawn_Ground")
	spawn_t = sa.length if sa != null else 0.0
	_play("Spawn_Ground" if spawn_t > 0.0 else "Idle_A")


const BAR_W := 0.9

func _make_hpbar() -> void:
	hpbar = Node3D.new()
	hpbar.position = Vector3(0, 1.6, 0)
	add_child(hpbar)
	hpbar.add_child(Rig.bar_quad(Color(0, 0, 0, 0.6), BAR_W, 0))   # background
	bar_fill = Rig.bar_quad(Color(0.3, 0.9, 0.3, 1.0), BAR_W, 1)   # always on top
	bar_fill.position.z = 0.01
	hpbar.add_child(bar_fill)


func _physics_process(delta: float) -> void:
	if dead:
		return
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	bar_fill.scale.x = frac
	bar_fill.position.x = -BAR_W * 0.5 * (1.0 - frac)   # anchor left -> empties right to left
	# spawning: stand still and finish rising out of the ground
	if spawn_t > 0.0:
		spawn_t -= delta
		velocity = Vector3.ZERO
		_play("Spawn_Ground")
		return
	atk_cd -= delta
	var to: Vector3 = game.keep_pos - global_position
	var dist := Vector2(to.x, to.z).length()
	var in_range := dist <= ATTACK_RANGE
	if in_range:
		# plant and attack; a packed crowd with nowhere to go stops dead, not jitters
		velocity = Vector3.ZERO
	else:
		var seek := Vector3(to.x, 0, to.z).normalized()
		var sep := _separation()
		# when a neighbour sits directly between us and the Keep, sidestep around
		# it (consistent rotational direction) instead of stopping behind it -> the
		# crowd fans out and surrounds the Keep rather than forming a single file
		var block := 0.0
		if sep.length() > 0.01:
			block = maxf(0.0, -sep.normalized().dot(seek))
		var tangent := Vector3(-seek.z, 0.0, seek.x)
		var steer := seek + sep * SEP_WEIGHT + tangent * (block * TANGENT_WEIGHT)
		var target := (steer.normalized() if steer.length() > 0.05 else seek) * speed
		velocity = velocity.lerp(target, 0.3)   # smooth so direction changes don't buzz
	move_and_slide()
	_face(game.keep_pos)
	# damage the Keep on cadence regardless of the displayed clip
	if in_range and atk_cd <= 0.0:
		atk_cd = atk_interval
		game.damage_keep(dmg)
		anim = ""   # restart the swing clip on each strike
	# animation (a hit flinch briefly overrides everything else)
	if hit_t > 0.0:
		hit_t -= delta
		_play(hit_clip)
		ap.speed_scale = 1.0
	elif in_range:
		_play("Melee_1H_Attack_Chop")        # swing at the Keep
		ap.speed_scale = 1.0
	elif velocity.length() > 0.05:
		_play("Walking_C")
		ap.speed_scale = speed / WALK_REF
	else:
		_play("Idle_A")          # held by the crowd: stand, don't skate in place
		ap.speed_scale = 1.0


# push away from nearby raiders, weighted stronger the closer they are
func _separation() -> Vector3:
	var sep := Vector3.ZERO
	for o in get_tree().get_nodes_in_group("enemies"):
		if o == self or (o as Enemy3D).dead:
			continue
		var away: Vector3 = global_position - o.global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.001 and d < SEP_RADIUS:
			sep += (away / d) * (1.0 - d / SEP_RADIUS)
	return sep


func take_damage(amount: float) -> void:
	if dead:
		return
	hp -= amount
	if hp <= 0.0:
		_die()
		return
	# brief flinch (skip while attacking the Keep so it keeps swinging)
	hit_clip = "Hit_A" if randf() < 0.5 else "Hit_B"
	hit_t = 0.16
	anim = ""   # force the flinch clip to restart even if already showing


func _die() -> void:
	dead = true
	hpbar.visible = false
	collision_layer = 0   # corpse stops blocking the living
	collision_mask = 0
	remove_from_group("enemies")   # also drops out of others' separation checks
	died.emit(reward, global_position)
	_play("Death_A" if randf() < 0.5 else "Death_B")
	ap.speed_scale = 1.0
	# the body stays on the ground; Game3D decides when to retire it
	game.register_corpse(self)


# Retire an old corpse: let it sink into the ground, then free it (no popping out).
func sink_and_free() -> void:
	var tw := create_tween()
	tw.tween_interval(0.3)
	tw.tween_property(self, "position:y", position.y - 2.0, 1.1).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _face(p: Vector3) -> void:
	var d: Vector3 = p - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		model.rotation.y = atan2(d.x, d.z)


func _play(n: String) -> void:
	if anim == n:
		return
	anim = n
	ap.play(n)
