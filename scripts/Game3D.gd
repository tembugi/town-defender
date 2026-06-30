extends Node3D

# 3D rebuild - hero + hex world + economy. Hero gathers nearby trees/rocks;
# hire workers (button / H) that auto-gather and carry gold to the Keep.


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		hire_worker()

const CAM_OFFSET := Vector3(0, 9.2, 5.6)   # steeper, more top-down "manage from above"
const CAM_LOOK := Vector3(0, 0.6, 0)

# pointy-top hex grid spacing (from measured tile: flat-width 2.0, 3/4 of point-height)
const HEX_W := 2.0
const HEX_V := 1.732
const FIELD_COLS := 13
const FIELD_ROWS := 11

const HEX_GRASS := "res://Models/hexagon/tiles/base/hex_grass.gltf"
const CASTLE := "res://Models/hexagon/buildings/blue/building_castle_blue.gltf"

const HIRE_COST := 25
const GATHER_RANGE := 1.6
const BUILD_RANGE := 1.8

const HOME := "res://Models/hexagon/buildings/blue/building_home_A_blue.gltf"
const MARKET := "res://Models/hexagon/buildings/blue/building_market_blue.gltf"
const BARRACKS := "res://Models/hexagon/buildings/blue/building_barracks_blue.gltf"

var hero: Hero3D
var cam: Camera3D
var joystick: TouchJoystick
var field_rect := Rect2()

# economy
var keep_pos := Vector3.ZERO
var gold := 100
var worker_cap := 6
var resource_nodes: Array[ResourceNode3D] = []
var workers: Array[Worker3D] = []
var build_pads: Array[BuildPad3D] = []
var workshops := 0
var barracks_count := 0
var income_t := 0.0
var lbl_gold: Label
var lbl_pop: Label
var btn_hire: Button


func _ready() -> void:
	_build_environment()
	_build_world()
	_build_pads()

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
	_tint_mesh(grass, Color(0.58, 0.72, 0.46))   # deeper, less lime grass
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

	# harvestable resource nodes, kept clear of the centre
	for n in range(18):
		var p := Vector3(randf_range(field_rect.position.x, field_rect.end.x), 0, randf_range(field_rect.position.y, field_rect.end.y))
		if Vector2(p.x, p.z).length() < 3.5:
			continue
		var node := ResourceNode3D.new()
		node.position = p
		add_child(node)
		node.setup("rock" if randf() < 0.32 else "tree")
		resource_nodes.append(node)


func _mesh_of(path: String) -> Mesh:
	var inst := (load(path) as PackedScene).instantiate()
	var mi := _find_mesh(inst)
	var m: Mesh = mi.mesh if mi else null
	inst.free()
	return m


# Tint a mesh's albedo (multiplies the atlas texture) to recolour without grading.
func _tint_mesh(m: Mesh, tint: Color) -> void:
	if m == null:
		return
	for s in range(m.get_surface_count()):
		var mat := m.surface_get_material(s)
		if mat is StandardMaterial3D:
			var d := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			d.albedo_color = tint
			m.surface_set_material(s, d)


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

	lbl_gold = _hud_label("Gold: %d" % gold, Vector2(22, 18), Color(1, 0.85, 0.25))
	layer.add_child(lbl_gold)
	lbl_pop = _hud_label("Workers: 0/%d" % worker_cap, Vector2(22, 52), Color(0.8, 1, 0.8))
	layer.add_child(lbl_pop)

	btn_hire = Button.new()
	btn_hire.text = "HIRE\nWORKER\n%dg" % HIRE_COST
	btn_hire.add_theme_font_size_override("font_size", 24)
	btn_hire.anchor_left = 1.0
	btn_hire.anchor_top = 1.0
	btn_hire.anchor_right = 1.0
	btn_hire.anchor_bottom = 1.0
	btn_hire.offset_left = -180
	btn_hire.offset_top = -160
	btn_hire.offset_right = -24
	btn_hire.offset_bottom = -44
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.45, 0.7, 0.45, 0.9)
	sb.set_corner_radius_all(18)
	btn_hire.add_theme_stylebox_override("normal", sb)
	btn_hire.add_theme_stylebox_override("hover", sb)
	btn_hire.pressed.connect(hire_worker)
	layer.add_child(btn_hire)


func _hud_label(text: String, pos: Vector2, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	return l


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

	# hero gathers the nearest node when standing still beside it
	if v.length() < 0.05:
		# standing on a build pad takes priority over gathering
		var pad := nearest_pad(hero.position, BUILD_RANGE)
		if pad != null:
			hero.gather_target = pad
			if gold >= pad.cost and pad.advance(delta):
				_construct(pad)
		else:
			var node := nearest_resource(hero.position, GATHER_RANGE)
			hero.gather_target = node
			if node != null and node.work(delta):
				_gain_gold(node.yield_amt)
	else:
		hero.gather_target = null

	# passive income from workshops/markets
	if workshops > 0:
		income_t -= delta
		if income_t <= 0.0:
			income_t = 3.0
			_gain_gold(workshops * 3)

	# smooth follow camera
	var t := clampf(delta * 8.0, 0.0, 1.0)
	cam.position = cam.position.lerp(hero.position + CAM_OFFSET, t)
	cam.look_at(hero.position + CAM_LOOK, Vector3.UP)


# ---------------------------------------------------------------------------
# Economy
# ---------------------------------------------------------------------------
func nearest_resource(from: Vector3, max_range := INF) -> ResourceNode3D:
	var best: ResourceNode3D = null
	var bestd := max_range
	for n in resource_nodes:
		if n.depleted:
			continue
		var d := Vector2(n.global_position.x - from.x, n.global_position.z - from.z).length()
		if d < bestd:
			bestd = d
			best = n
	return best


func _gain_gold(amt: int) -> void:
	gold += amt
	lbl_gold.text = "Gold: %d" % gold


func worker_deposit(amt: int) -> void:
	_gain_gold(amt)


func hire_worker() -> void:
	if workers.size() >= worker_cap or gold < HIRE_COST:
		return
	gold -= HIRE_COST
	lbl_gold.text = "Gold: %d" % gold
	var w := Worker3D.new()
	w.position = keep_pos + Vector3(randf_range(-1.5, 1.5), 0, 2.0)
	add_child(w)
	w.setup(self)
	workers.append(w)
	lbl_pop.text = "Workers: %d/%d" % [workers.size(), worker_cap]


# ---------------------------------------------------------------------------
# Build system
# ---------------------------------------------------------------------------
func _build_pads() -> void:
	var defs := [
		{"type": "house", "cost": 20, "label": "House", "path": HOME, "pos": Vector3(-3.6, 0, 1.7)},
		{"type": "workshop", "cost": 45, "label": "Market", "path": MARKET, "pos": Vector3(3.6, 0, 1.7)},
		{"type": "barracks", "cost": 80, "label": "Barracks", "path": BARRACKS, "pos": Vector3(0, 0, -3.6)},
	]
	for d in defs:
		var p := BuildPad3D.new()
		p.position = d["pos"]
		p.setup(self, d["type"], d["cost"], d["label"], d["path"])
		add_child(p)
		build_pads.append(p)


func nearest_pad(from: Vector3, rng: float) -> BuildPad3D:
	var best: BuildPad3D = null
	var bestd := rng
	for p in build_pads:
		if p.built:
			continue
		var d := Vector2(p.position.x - from.x, p.position.z - from.z).length()
		if d < bestd:
			bestd = d
			best = p
	return best


func _construct(pad: BuildPad3D) -> void:
	if pad.built:
		return
	gold -= pad.cost
	lbl_gold.text = "Gold: %d" % gold
	pad.mark_built()
	var b := (load(pad.building_path) as PackedScene).instantiate()
	b.position = pad.position
	add_child(b)
	b.scale = Vector3.ONE * 0.3
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	match pad.btype:
		"house":
			worker_cap += 2
			lbl_pop.text = "Workers: %d/%d" % [workers.size(), worker_cap]
		"workshop":
			workshops += 1
		"barracks":
			barracks_count += 1
