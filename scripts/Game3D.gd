extends Node3D

# 3D rebuild - Chunk 1: a hero on a ground plane, a fixed tilted follow-camera,
# and joystick/WASD movement. Foundation for the 3D town-defender.

const CAM_OFFSET := Vector3(0, 9.2, 5.6)   # steeper, more top-down "manage from above"
const CAM_LOOK := Vector3(0, 0.6, 0)

# pointy-top hex grid spacing (from measured tile: flat-width 2.0, 3/4 of point-height)
const HEX_W := 2.0
const HEX_V := 1.732
const FIELD_COLS := 13
const FIELD_ROWS := 11

const HEX_GRASS := "res://Models/hexagon/tiles/base/hex_grass.gltf"
const CASTLE := "res://Models/hexagon/buildings/blue/building_castle_blue.gltf"
const TREE := "res://Models/hexagon/decoration/nature/tree_single_A.gltf"
const ROCK := "res://Models/hexagon/decoration/nature/rock_single_B.gltf"

var hero: Hero3D
var cam: Camera3D
var joystick: TouchJoystick
var field_rect := Rect2()


func _ready() -> void:
	_build_environment()
	_build_world()

	hero = Hero3D.new()
	hero.bounds = field_rect
	hero.position = Vector3(0, 0, 4.0)   # spawn just south of the keep
	add_child(hero)

	cam = Camera3D.new()
	cam.fov = 42.0
	add_child(cam)
	cam.position = hero.position + CAM_OFFSET
	cam.look_at(hero.position + CAM_LOOK, Vector3.UP)

	_build_touch_ui()


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()

	# gradient sky -> nicer backdrop + cohesive ambient
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.36, 0.58, 0.88)
	psm.sky_horizon_color = Color(0.72, 0.81, 0.9)
	psm.ground_horizon_color = Color(0.72, 0.78, 0.82)
	psm.ground_bottom_color = Color(0.5, 0.52, 0.5)
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5

	# colour grade: tame the saturated lime, add a little contrast
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.88
	env.adjustment_contrast = 1.06
	env.adjustment_brightness = 0.99
	we.environment = env
	add_child(we)

	# warm sun with shadows
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -50, 0)
	sun.light_color = Color(1.0, 0.95, 0.84)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)


func _build_world() -> void:
	# ground: one MultiMesh of hex_grass tiles (single draw call)
	var grass := _mesh_of(HEX_GRASS)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = grass
	mm.instance_count = FIELD_COLS * FIELD_ROWS
	var ox := -(FIELD_COLS - 1) * HEX_W * 0.5
	var oz := -(FIELD_ROWS - 1) * HEX_V * 0.5
	var i := 0
	for r in range(FIELD_ROWS):
		for q in range(FIELD_COLS):
			var x := HEX_W * (q + 0.5 * (r & 1)) + ox
			var z := HEX_V * r + oz
			mm.set_instance_transform(i, Transform3D(Basis(), Vector3(x, 0, z)))
			i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	# playable bounds (slight inset)
	field_rect = Rect2(ox + 1.0, oz + 1.0, (FIELD_COLS - 1) * HEX_W - 2.0, (FIELD_ROWS - 1) * HEX_V - 2.0)

	# central Keep
	var castle := (load(CASTLE) as PackedScene).instantiate()
	add_child(castle)

	# scatter decoration, kept clear of the centre
	for n in range(16):
		var p := Vector3(randf_range(field_rect.position.x, field_rect.end.x), 0, randf_range(field_rect.position.y, field_rect.end.y))
		if Vector2(p.x, p.z).length() < 3.0:
			continue
		var is_tree := randf() < 0.65
		var deco := (load(TREE if is_tree else ROCK) as PackedScene).instantiate()
		deco.position = p
		deco.rotation.y = randf() * TAU
		deco.scale = Vector3.ONE * (1.5 if is_tree else 1.5)
		add_child(deco)


func _mesh_of(path: String) -> Mesh:
	var inst := (load(path) as PackedScene).instantiate()
	var mi := _find_mesh(inst)
	var m: Mesh = mi.mesh if mi else null
	inst.free()
	return m


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and n.mesh != null:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null


func _build_touch_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	joystick = TouchJoystick.new()
	layer.add_child(joystick)


func _process(delta: float) -> void:
	# input: keyboard, else joystick
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1
	if v == Vector2.ZERO and joystick.move_vec != Vector2.ZERO:
		v = joystick.move_vec
	v = v.limit_length(1.0)
	# map screen input to world using the camera's orientation (flattened to ground):
	# screen-right = camera right, screen-up (v.y is negative up) = camera forward
	var b := cam.global_transform.basis
	var fwd := Vector3(b.z.x, 0, b.z.z)        # camera looks along -Z, so -fwd is "into screen"
	var right := Vector3(b.x.x, 0, b.x.z)
	if fwd.length() > 0.001: fwd = fwd.normalized()
	if right.length() > 0.001: right = right.normalized()
	var world := right * v.x + (-fwd) * (-v.y)   # -fwd = into screen/up; -v.y because up is negative
	hero.move_input = Vector2(world.x, world.z)

	# smooth follow camera
	var t := clampf(delta * 8.0, 0.0, 1.0)
	cam.position = cam.position.lerp(hero.position + CAM_OFFSET, t)
	cam.look_at(hero.position + CAM_LOOK, Vector3.UP)
