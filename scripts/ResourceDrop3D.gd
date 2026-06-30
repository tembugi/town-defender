class_name ResourceDrop3D
extends Node3D

# A loose pile of resources sitting on the ground after a tree/rock is felled.
# Workers walk over, pick it up, and haul it to the Keep to add to our gold.

var amount := 5
var reserved := false   # a worker has claimed this pile and is on its way
var taken := false      # picked up; pending free
var _t := 0.0


func setup(amt: int, kind := "wood") -> void:
	amount = amt
	add_to_group("drops")
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.34, 0.26, 0.34)
	m.mesh = box
	var mat := StandardMaterial3D.new()
	# wood = warm brown, stone = cool grey
	mat.albedo_color = Color(0.55, 0.36, 0.18) if kind == "wood" else Color(0.55, 0.57, 0.6)
	m.material_override = mat
	m.position.y = 0.18
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	add_child(Rig.blob_shadow(0.26))
	_mesh = m


var _mesh: MeshInstance3D


func _process(delta: float) -> void:
	# gentle bob + spin so loose resources read as pickups
	_t += delta
	if _mesh != null:
		_mesh.position.y = 0.18 + sin(_t * 3.0) * 0.04
		_mesh.rotation.y = _t * 1.2


func pick_up() -> int:
	taken = true
	queue_free()
	return amount
