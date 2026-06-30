class_name Wall3D
extends StaticBody3D

# A destructible barrier. Blocks enemy movement (so it funnels them); enemies that
# are stopped by it attack it until it's destroyed. Built on a wall build pad.

const MODEL := "res://Models/hexagon/buildings/neutral/wall_straight.gltf"
const SCALE := 1.8
const MAX_HP := 180.0
const BAR_W := 1.6

var game: Node
var hp := MAX_HP
var dead := false
var bar_fill: MeshInstance3D


func setup(g: Node) -> void:
	game = g
	collision_layer = Rig.L_OBSTACLE
	collision_mask = 0
	var b := (load(MODEL) as PackedScene).instantiate()
	b.scale = Vector3.ONE * SCALE
	add_child(b)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 1.5, 1.0)
	cs.shape = box
	cs.position.y = 0.75
	add_child(cs)
	add_child(Rig.blob_shadow(1.2))
	# HP bar
	var hb := Node3D.new()
	hb.position = Vector3(0, 1.9, 0)
	add_child(hb)
	hb.add_child(Rig.bar_quad(Color(0, 0, 0, 0.6), BAR_W, 0))
	bar_fill = Rig.bar_quad(Color(0.75, 0.7, 0.45, 1.0), BAR_W, 1)
	bar_fill.position.z = 0.01
	hb.add_child(bar_fill)


func take_damage(amount: float) -> void:
	if dead:
		return
	hp -= amount
	var frac := clampf(hp / MAX_HP, 0.0, 1.0)
	bar_fill.scale.x = frac
	bar_fill.position.x = -BAR_W * 0.5 * (1.0 - frac)
	if hp <= 0.0:
		dead = true
		game._puff(global_position + Vector3(0, 0.6, 0), Color(0.6, 0.55, 0.4), 12, 2.6)
		Sfx.play("keep_hit", -4.0, 0.1, 3)
		queue_free()
