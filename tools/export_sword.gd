extends SceneTree
# Builds the placeholder sword from primitives and exports it to a real .glb
# model file so it can be edited in Blender / swapped out. Run with:
#   Godot --headless --script tools/export_sword.gd
func box(nm, size, pos, col):
	var m := MeshInstance3D.new()
	m.name = nm
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	bm.material = mat
	m.mesh = bm
	m.position = pos
	return m
func _init():
	var steel := Color(0.74, 0.78, 0.82)
	var gold := Color(0.82, 0.66, 0.28)
	var wood := Color(0.45, 0.30, 0.17)
	var root := Node3D.new()
	root.name = "Sword"
	get_root().add_child(root)
	root.add_child(box("Grip",   Vector3(0.05, 0.26, 0.05), Vector3(0, 0.0, 0), wood))
	root.add_child(box("Guard",  Vector3(0.26, 0.05, 0.06), Vector3(0, 0.15, 0), gold))
	root.add_child(box("Blade",  Vector3(0.07, 0.78, 0.025), Vector3(0, 0.56, 0), steel))
	root.add_child(box("Pommel", Vector3(0.07, 0.07, 0.07), Vector3(0, -0.15, 0), gold))
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_scene(root, st)
	var err := doc.write_to_filesystem(st, "res://Models/weapons/sword.glb")
	print("RES export err=", err)
	quit()
