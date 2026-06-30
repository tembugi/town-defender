class_name EnemyBolt3D
extends Node3D

# A mage's magic bolt. Flies to a snapshot destination and, on arrival, damages
# the Keep (always hits) or the hero (only if still near the impact -> dodgeable).

const SPEED := 12.0

var game: Node
var dmg := 11.0
var dest := Vector3.ZERO
var kind := "keep"     # "keep" or "hero"
var hero_ref: Node3D
var _life := 3.5


func setup(g: Node, target: Vector3, k: String, damage: float, hero: Node3D) -> void:
	game = g
	dest = target
	kind = k
	dmg = damage
	hero_ref = hero
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	sm.radial_segments = 8
	sm.rings = 4
	m.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.4, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.3, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)


func _process(delta: float) -> void:
	_life -= delta
	var to := dest - global_position
	var d := to.length()
	if d <= maxf(0.5, SPEED * delta) or _life <= 0.0:   # arrived (overshoot-proof)
		if kind == "keep":
			game.damage_keep(dmg)
		elif is_instance_valid(hero_ref) and hero_ref.global_position.distance_to(dest) < 1.4:
			game.damage_hero(dmg)   # else the hero dodged out of the blast
		queue_free()
		return
	global_position += to.normalized() * SPEED * delta
