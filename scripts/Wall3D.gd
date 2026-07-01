class_name Wall3D
extends StaticBody3D

# A destructible barrier. Blocks enemy movement (so it funnels them); enemies that
# are stopped by it attack it until it's destroyed. Built on a wall build pad.

# Modular stone wall: native size is exactly one hex wide (2.0) x 1.1 tall, already
# aligned to tile along X (no rotation needed). Stretched taller (Y only) to match
# tree height (~1.8) without distorting the width/tiling.
const MODEL := "res://Models/hexagon/buildings/neutral/wall_straight.gltf"
const MODEL_SCALE := Vector3(1.0, 1.63, 1.0)
const LENGTH := 2.0            # world length of one segment, along its local +X
const MAX_HP := 180.0
const BAR_W := 1.5

const BAR_COLOR := Color(0.75, 0.7, 0.45, 1.0)


# The two end points of a wall segment at `pos`/`yaw` (not placed yet), used to
# snap a new segment flush against an existing one.
static func endpoints(pos: Vector3, yaw: float) -> Array:
	var dir := Vector3(1, 0, 0).rotated(Vector3.UP, yaw) * (LENGTH * 0.5)
	return [pos + dir, pos - dir]

var game: Node
var hp := MAX_HP
var dead := false
var bar_fill: MeshInstance3D
var bar_flash := 0.0


func setup(g: Node) -> void:
	game = g
	collision_layer = Rig.L_OBSTACLE
	collision_mask = 0
	var b := (load(MODEL) as PackedScene).instantiate()
	b.scale = MODEL_SCALE
	add_child(b)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# full hex width so adjacent walls' colliders meet (no gap); height covers
	# most of the taller stretched model
	box.size = Vector3(2.0, 1.6, 0.7)
	cs.shape = box
	cs.position.y = 0.8
	add_child(cs)
	# a slim ground shadow proportioned to the wall's footprint (not a round
	# building's), so it doesn't read as an oversized dark blob next to units
	add_child(Rig.blob_shadow(0.55))
	# HP bar
	var hb := Node3D.new()
	hb.position = Vector3(0, 2.0, 0)
	add_child(hb)
	hb.add_child(Rig.bar_quad(Color(0, 0, 0, 0.6), BAR_W, 0))
	bar_fill = Rig.bar_quad(BAR_COLOR, BAR_W, 1)
	bar_fill.position.z = 0.01
	hb.add_child(bar_fill)


func _process(delta: float) -> void:
	if bar_flash <= 0.0:
		return
	bar_flash = maxf(0.0, bar_flash - delta)
	bar_fill.material_override.albedo_color = Rig.flash_color(BAR_COLOR, bar_flash)


func take_damage(amount: float) -> void:
	if dead:
		return
	hp -= amount
	bar_flash = Rig.BAR_FLASH
	var frac := clampf(hp / MAX_HP, 0.0, 1.0)
	bar_fill.scale.x = frac
	bar_fill.position.x = -BAR_W * 0.5 * (1.0 - frac)
	if hp <= 0.0:
		dead = true
		game._puff(global_position + Vector3(0, 0.6, 0), Color(0.6, 0.55, 0.4), 12, 2.6)
		Sfx.play("keep_hit", -4.0, 0.1, 3)
		queue_free()
