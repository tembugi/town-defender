class_name Enemy3D
extends Node3D

# A skeleton raider. Walks to the Keep and attacks it; has HP, dies with the
# death animation, and rewards gold. Uses the skeleton's own Rig_Medium anims.

const CHAR := "res://Models/enemies/Skeleton_Minion.glb"
const CHAR_SCALE := 0.55
const WALK_REF := 1.5
const ATTACK_RANGE := 2.2

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
	ap = Rig.attach(model, "skeleton")
	_play("Idle_A")
	add_to_group("enemies")
	_make_hpbar()


func _make_hpbar() -> void:
	hpbar = Node3D.new()
	hpbar.position = Vector3(0, 1.6, 0)
	add_child(hpbar)
	hpbar.add_child(_bar_quad(Color(0, 0, 0, 0.6)))   # background
	bar_fill = _bar_quad(Color(0.3, 0.9, 0.3, 1.0))
	bar_fill.position.z = 0.01
	hpbar.add_child(bar_fill)


func _bar_quad(col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.13)
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true   # so scaling the fill actually shrinks it
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	m.material_override = mat
	return m


func _process(delta: float) -> void:
	if dead:
		return
	bar_fill.scale.x = clampf(hp / max_hp, 0.0, 1.0)
	atk_cd -= delta
	var to: Vector3 = game.keep_pos - global_position
	var dist := Vector2(to.x, to.z).length()
	if dist <= ATTACK_RANGE:
		_face(game.keep_pos)
		_play("Interact")
		ap.speed_scale = 1.0
		if atk_cd <= 0.0:
			atk_cd = atk_interval
			game.damage_keep(dmg)
	else:
		var dir := Vector3(to.x, 0, to.z).normalized()
		global_position += dir * speed * delta
		_face(game.keep_pos)
		_play("Walking_C")
		ap.speed_scale = speed / WALK_REF


func take_damage(amount: float) -> void:
	if dead:
		return
	hp -= amount
	if hp <= 0.0:
		_die()


func _die() -> void:
	dead = true
	hpbar.visible = false
	remove_from_group("enemies")
	died.emit(reward, global_position)
	_play("Death_A")
	ap.speed_scale = 1.0
	get_tree().create_timer(1.6).timeout.connect(queue_free)


func _face(p: Vector3) -> void:
	var d: Vector3 = p - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		model.rotation.y = atan2(d.x, d.z)


func _play(n: String) -> void:
	if anim == n:
		return
	anim = n
	ap.play(n)
