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
const AVOID_WEIGHT := 1.7   # steer around trees/rocks/buildings (no path-finding, just avoid)
const CORPSE_LINGER := 10.0 # seconds a body lies on the ground before sinking away
const AGGRO_DECAY := 0.2    # aggro bleeds off per second when not being hit

var aggro := 0.0            # builds when the hero hits us; over threshold -> chase hero
var aggro_threshold := 0.5  # per-enemy (tougher foes need more before they turn)

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
var knockback := Vector3.ZERO   # decaying impulse pushing us back when hit
const KB_FORCE := 3.2
const KB_DECAY := 14.0


func setup(g: Node, cfg: Dictionary) -> void:
	game = g
	max_hp = cfg.get("hp", 40.0)
	hp = max_hp
	dmg = cfg.get("dmg", 6.0)
	reward = cfg.get("reward", 5)
	speed = cfg.get("speed", 1.6)
	aggro_threshold = cfg.get("aggro_threshold", 0.5)
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
	aggro = maxf(0.0, aggro - AGGRO_DECAY * delta)
	# once aggroed (and the hero is alive), chase and attack the hero instead
	var aggroed: bool = aggro >= aggro_threshold and is_instance_valid(game.hero) and not game.game_over
	var target_pos: Vector3 = game.hero.global_position if aggroed else game.keep_pos
	var to: Vector3 = target_pos - global_position
	var dist := Vector2(to.x, to.z).length()
	var in_range := dist <= ATTACK_RANGE
	if in_range:
		# plant and attack; a packed crowd with nowhere to go stops dead, not jitters
		velocity = Vector3.ZERO
	else:
		var seek := Vector3(to.x, 0, to.z).normalized()
		# steer away from the crowd AND from obstacles (trees/rocks/buildings) so we
		# flow around them instead of pinning against a tree on the way in
		var push := _separation() * SEP_WEIGHT + _avoid() * AVOID_WEIGHT
		# when something sits directly between us and the target, sidestep around it
		# (consistent rotation) rather than stalling behind it
		var block := 0.0
		if push.length() > 0.01:
			block = maxf(0.0, -push.normalized().dot(seek))
		var tangent := Vector3(-seek.z, 0.0, seek.x)
		var steer := seek + push + tangent * (block * TANGENT_WEIGHT)
		var target := (steer.normalized() if steer.length() > 0.05 else seek) * speed
		velocity = velocity.lerp(target, 0.3)   # smooth so direction changes don't buzz
	# decaying knockback rides on top of whatever steering produced
	knockback = knockback.move_toward(Vector3.ZERO, KB_DECAY * delta)
	velocity += knockback
	move_and_slide()
	_face(target_pos)
	# attack on cadence (hero if aggroed, otherwise the Keep)
	if in_range and atk_cd <= 0.0:
		atk_cd = atk_interval
		if aggroed:
			game.damage_hero(dmg)
		else:
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


func add_aggro(amount: float) -> void:
	aggro = minf(aggro + amount, aggro_threshold + 2.0)   # cap so it bleeds off fast


# Steer away from static obstacles (trees, rocks, finished buildings).
func _avoid() -> Vector3:
	var a := Vector3.ZERO
	for n in game.resource_nodes:
		if not n.depleted:
			a += _repel(n.global_position, n.hit_radius() + 0.6)
	for p in game.build_pads:
		if p.built and p.btype != "train":
			a += _repel(p.position, 1.3)
	return a


func _repel(obs: Vector3, radius: float) -> Vector3:
	var away: Vector3 = global_position - obs
	away.y = 0.0
	var d := away.length()
	if d > 0.001 and d < radius:
		return (away / d) * (1.0 - d / radius)
	return Vector3.ZERO


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


func take_damage(amount: float, from := Vector3.INF) -> void:
	if dead:
		return
	hp -= amount
	Rig.flash(self, model, Color(1, 0.35, 0.35))   # red hit flash
	if from.is_finite():
		var dir: Vector3 = global_position - from
		dir.y = 0.0
		if dir.length() > 0.01:
			knockback = dir.normalized() * KB_FORCE
	if hp <= 0.0:
		_die()
		return
	# brief flinch
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
	game._puff(global_position + Vector3(0, 0.4, 0), Color(0.5, 0.5, 0.55), 10, 2.2)   # dust burst
	_play("Death_A" if randf() < 0.5 else "Death_B")
	ap.speed_scale = 1.0
	# body lies on the ground, then sinks away and frees itself after a delay
	get_tree().create_timer(CORPSE_LINGER).timeout.connect(sink_and_free)


# Sink into the ground, then free it (no popping out of existence).
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
