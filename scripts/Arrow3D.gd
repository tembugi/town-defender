class_name Arrow3D
extends Node3D

# A tower arrow. Homes onto its target enemy and deals damage on contact, then
# frees itself. Fizzles if the target dies/escapes or after a short lifetime.

const SPEED := 18.0

var target: Enemy3D
var dmg := 14.0
var _life := 2.0


func setup(t: Enemy3D, damage: float) -> void:
	target = t
	dmg = damage
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.05, 0.5)
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.36, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0 or not is_instance_valid(target) or target.dead:
		queue_free()
		return
	var aim: Vector3 = target.global_position + Vector3(0, 1.0, 0)
	var to := aim - global_position
	var d := to.length()
	if d <= 0.55:
		target.take_damage(dmg)   # no knockback/aggro: ranged tower fire
		queue_free()
		return
	look_at(aim, Vector3.UP)
	global_position += to.normalized() * SPEED * delta
