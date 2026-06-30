extends SceneTree
func _all(n):
	var o=[]; if n is MeshInstance3D and n.mesh: o.append(n)
	for c in n.get_children(): o+=_all(c)
	return o
func sz(p):
	var i=(load(p) as PackedScene).instantiate(); root.add_child(i)
	var c=AABB(); var f=true
	for m in _all(i):
		var a=m.global_transform*m.get_aabb()
		if f: c=a;f=false
		else: c=c.merge(a)
	i.free(); return c
func _init():
	for p in ["res://Models/hexagon/buildings/blue/building_home_A.gltf","res://Models/hexagon/buildings/blue/building_market.gltf","res://Models/hexagon/buildings/blue/building_barracks.gltf"]:
		var a=sz(p); print(p.get_file()," baseY=","%.2f"%a.position.y," h=","%.2f"%a.size.y," fp=","%.1fx%.1f"%[a.size.x,a.size.z])
	quit()
