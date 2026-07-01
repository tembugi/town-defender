class_name Wall3D
extends StaticBody3D

# A destructible barrier. Blocks enemy movement (so it funnels them); enemies that
# are stopped by it attack it until it's destroyed. Built on a wall build pad.

# Halloween-pack iron fence: a symmetric rail 4.0 long x 2.2 tall x 0.5 deep,
# aligned along its local +X (no facing/flip problem -- both sides are identical).
# Corner/end POSTS are separate fence_pillar pieces dropped by Game3D at each
# endpoint, so runs join cleanly at any angle. Swaps to a broken model when badly
# damaged. Native scale -- the piece is already the right size, no stretching.
const MODEL := "res://Models/halloween/fence.gltf"
const BROKEN_MODEL := "res://Models/halloween/fence_broken.gltf"
const MODEL_SCALE := Vector3.ONE
const LENGTH := 4.0            # world length of one segment, along its local +X
const MAX_HP := 180.0
const BAR_W := 2.5
const BROKEN_FRAC := 0.4       # swap to the broken model once HP drops below this

const BAR_COLOR := Color(0.75, 0.7, 0.45, 1.0)


# The two end points of a wall segment at `pos`/`yaw` (not placed yet), used to
# snap a new segment flush against an existing one.
static func endpoints(pos: Vector3, yaw: float) -> Array:
	var dir := Vector3(1, 0, 0).rotated(Vector3.UP, yaw) * (LENGTH * 0.5)
	return [pos + dir, pos - dir]

var game: Node
var hp := MAX_HP
var dead := false
var broken := false
var body: Node3D
var bar_fill: MeshInstance3D
var bar_flash := 0.0


func setup(g: Node) -> void:
	game = g
	collision_layer = Rig.L_OBSTACLE
	collision_mask = 0
	body = (load(MODEL) as PackedScene).instantiate()
	body.scale = MODEL_SCALE
	add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# full segment length so adjacent fences' colliders meet (no gap); height
	# covers most of the fence so enemies bump it rather than clip through
	box.size = Vector3(LENGTH, 2.0, 0.5)
	cs.shape = box
	cs.position.y = 1.0
	add_child(cs)
	# HP bar
	var hb := Node3D.new()
	hb.position = Vector3(0, 2.5, 0)
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
	# once it's taken a beating, swap the intact rail for the broken model
	if not broken and frac < BROKEN_FRAC and is_instance_valid(body):
		broken = true
		body.queue_free()
		body = (load(BROKEN_MODEL) as PackedScene).instantiate()
		body.scale = MODEL_SCALE
		add_child(body)
	if hp <= 0.0:
		dead = true
		game._puff(global_position + Vector3(0, 0.6, 0), Color(0.55, 0.5, 0.45), 12, 2.6)
		Sfx.play("keep_hit", -4.0, 0.1, 3)
		queue_free()
