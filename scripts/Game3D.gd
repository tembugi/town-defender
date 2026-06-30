extends Node3D

# 3D rebuild - hero + hex world + economy. Hero gathers nearby trees/rocks;
# hire workers (button / H) that auto-gather and carry gold to the Keep.


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H:
			hire_worker()
		elif event.keycode == KEY_SPACE:
			start_wave()

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

const HERO_ATK_RANGE := 2.6
const HERO_DMG := 14.0
const HERO_ATK_CD := 0.5
const KEEP_MAX := 1500.0
const TOTAL_WAVES := 8
const SOLDIER_COST := 30
const NPC_SPEED := 2.1   # ~50% of the player's max speed (4.2)

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

# combat / waves
var keep_node: Node3D
var keep_hp := KEEP_MAX
var keep_bar_fill: MeshInstance3D
const KEEP_BAR_W := 1.8
var soldiers: Array[Soldier3D] = []
var spawn_points: Array[Vector3] = []
var wave := 0
var wave_active := false
var spawn_list: Array = []
var spawn_t := 0.0
var enemies_alive := 0
var hero_atk_cd := 0.0
var game_over := false
var lbl_keep: Label
var lbl_wave: Label
var lbl_soldiers: Label
var btn_wave: Button
var overlay: ColorRect
var lbl_end: Label


func _ready() -> void:
	if OS.has_feature("web"):
		get_viewport().scaling_3d_scale = 0.75   # render 3D at 75% on mobile/web -> big GPU win
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

	# warm sun; no real shadows (characters use fake blob shadows instead)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -50, 0)
	sun.light_color = Color(1.0, 0.95, 0.84)
	sun.light_energy = 1.4
	sun.shadow_enabled = false
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

	# central Keep + its always-on health bar
	keep_node = (load(CASTLE) as PackedScene).instantiate()
	add_child(keep_node)
	var kb := Node3D.new()
	kb.position = Vector3(0, 4.6, 0)
	keep_node.add_child(kb)
	kb.add_child(Rig.bar_quad(Color(0, 0, 0, 0.6), KEEP_BAR_W))
	keep_bar_fill = Rig.bar_quad(Color(0.45, 0.8, 1.0, 1.0), KEEP_BAR_W)
	keep_bar_fill.position.z = 0.01
	kb.add_child(keep_bar_fill)

	# enemy spawn points at the field edges
	var r := field_rect
	spawn_points = [
		Vector3(r.position.x + 0.5, 0, (r.position.y + r.end.y) * 0.5),
		Vector3(r.end.x - 0.5, 0, (r.position.y + r.end.y) * 0.5),
		Vector3((r.position.x + r.end.x) * 0.5, 0, r.position.y + 0.5),
		Vector3((r.position.x + r.end.x) * 0.5, 0, r.end.y - 0.5),
	]

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
	lbl_keep = _hud_label("Keep: %d" % int(keep_hp), Vector2(22, 52), Color(0.7, 0.85, 1))
	layer.add_child(lbl_keep)
	lbl_pop = _hud_label("Workers: 0/%d" % worker_cap, Vector2(22, 86), Color(0.8, 1, 0.8))
	layer.add_child(lbl_pop)
	lbl_soldiers = _hud_label("Soldiers: 0", Vector2(22, 120), Color(1, 0.8, 0.6))
	layer.add_child(lbl_soldiers)
	lbl_wave = _hud_label("Wave: 0/%d" % TOTAL_WAVES, Vector2(22, 154), Color(0.95, 0.7, 0.7))
	layer.add_child(lbl_wave)

	btn_hire = _hud_button("HIRE\nWORKER\n%dg" % HIRE_COST, -160, Color(0.45, 0.7, 0.45))
	btn_hire.pressed.connect(hire_worker)
	layer.add_child(btn_hire)
	btn_wave = _hud_button("START\nWAVE", -160 - 130, Color(0.8, 0.45, 0.4))
	btn_wave.pressed.connect(start_wave)
	layer.add_child(btn_wave)

	# end-of-game overlay
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	layer.add_child(overlay)
	lbl_end = Label.new()
	lbl_end.anchor_left = 0.0
	lbl_end.anchor_right = 1.0
	lbl_end.anchor_top = 0.5
	lbl_end.anchor_bottom = 0.5
	lbl_end.offset_top = -120
	lbl_end.offset_bottom = -20
	lbl_end.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_end.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_end.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_end.add_theme_font_size_override("font_size", 44)
	overlay.add_child(lbl_end)
	var btn_restart := Button.new()
	btn_restart.text = "Play Again"
	btn_restart.anchor_left = 0.5
	btn_restart.anchor_right = 0.5
	btn_restart.anchor_top = 0.5
	btn_restart.anchor_bottom = 0.5
	btn_restart.offset_left = -110
	btn_restart.offset_right = 110
	btn_restart.offset_top = 30
	btn_restart.offset_bottom = 94
	btn_restart.add_theme_font_size_override("font_size", 24)
	btn_restart.pressed.connect(func(): get_tree().reload_current_scene())
	overlay.add_child(btn_restart)


func _hud_button(text: String, top_off: float, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 24)
	b.anchor_left = 1.0
	b.anchor_top = 1.0
	b.anchor_right = 1.0
	b.anchor_bottom = 1.0
	b.offset_left = -180
	b.offset_top = top_off
	b.offset_right = -24
	b.offset_bottom = top_off + 116
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.9)
	sb.set_corner_radius_all(18)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	return b


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
	if game_over:
		return
	hero_atk_cd -= delta
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

	# when standing still: fight nearby enemy (priority) > build on pad > gather
	if v.length() < 0.05:
		var enemy := nearest_enemy(hero.position, HERO_ATK_RANGE)
		if enemy != null:
			hero.gather_target = enemy
			if hero_atk_cd <= 0.0:
				hero_atk_cd = HERO_ATK_CD
				var tgt := enemy
				get_tree().create_timer(0.25).timeout.connect(func():
					if is_instance_valid(tgt) and not tgt.dead:
						tgt.take_damage(HERO_DMG))
		else:
			var pad := nearest_pad(hero.position, BUILD_RANGE)
			if pad != null and gold >= pad.cost:
				hero.gather_target = pad
				if pad.advance(delta):
					if pad.btype == "train":
						_train_soldier(pad)
					else:
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

	_update_waves(delta)

	# keep health bar (always visible, empties right to left)
	var kf := clampf(keep_hp / KEEP_MAX, 0.0, 1.0)
	keep_bar_fill.scale.x = kf
	keep_bar_fill.position.x = -KEEP_BAR_W * 0.5 * (1.0 - kf)

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
			# place a reusable "train soldier" pad beside the barracks
			var tp := BuildPad3D.new()
			tp.position = pad.position + Vector3(1.8, 0, 0)
			tp.setup(self, "train", SOLDIER_COST, "Train", BARRACKS)
			add_child(tp)
			build_pads.append(tp)


# ---------------------------------------------------------------------------
# Combat / waves
# ---------------------------------------------------------------------------
func nearest_enemy(from: Vector3, rng: float) -> Enemy3D:
	var best: Enemy3D = null
	var bestd := rng
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy3D
		if e == null or e.dead:
			continue
		var d := Vector2(e.global_position.x - from.x, e.global_position.z - from.z).length()
		if d < bestd:
			bestd = d
			best = e
	return best


func damage_keep(amt: float) -> void:
	if game_over:
		return
	keep_hp -= amt
	lbl_keep.text = "Keep: %d" % maxi(0, int(keep_hp))
	if keep_hp <= 0.0:
		_end_game(false)


func _train_soldier(pad: BuildPad3D) -> void:
	if gold < SOLDIER_COST:
		return
	gold -= SOLDIER_COST
	lbl_gold.text = "Gold: %d" % gold
	_spawn_soldier(pad.position)
	pad.reset()


func _spawn_soldier(from: Vector3) -> void:
	# guard post: a ring around the Keep
	var ang := randf() * TAU
	var guard := keep_pos + Vector3(cos(ang), 0, sin(ang)) * 3.2
	var s := Soldier3D.new()
	s.position = from
	add_child(s)
	s.setup(self, guard)
	soldiers.append(s)
	lbl_soldiers.text = "Soldiers: %d" % soldiers.size()


func start_wave() -> void:
	if wave_active or game_over or wave >= TOTAL_WAVES:
		return
	wave += 1
	var count := 3 + wave * 2
	spawn_list.clear()
	for n in range(count):
		spawn_list.append(_enemy_cfg(wave))
	wave_active = true
	spawn_t = 0.4
	lbl_wave.text = "Wave: %d/%d" % [wave, TOTAL_WAVES]


func _enemy_cfg(n: int) -> Dictionary:
	return {
		"hp": 55.0 + n * 14.0,     # several hits to kill (not one-shot)
		"speed": NPC_SPEED,
		"reward": 5 + n,
		"dmg": 5.0 + n * 0.8,
	}


func _update_waves(delta: float) -> void:
	if not wave_active:
		return
	if not spawn_list.is_empty():
		spawn_t -= delta
		if spawn_t <= 0.0:
			_spawn_enemy(spawn_list.pop_back(), spawn_points[randi() % spawn_points.size()])
			spawn_t = maxf(0.4, 1.0 - wave * 0.05)
	elif enemies_alive <= 0:
		wave_active = false
		_gain_gold(20 + wave * 8)
		if wave >= TOTAL_WAVES:
			_end_game(true)


func _spawn_enemy(cfg: Dictionary, pos: Vector3) -> void:
	var e := Enemy3D.new()
	e.position = pos
	add_child(e)
	e.setup(self, cfg)
	e.died.connect(_on_enemy_died)
	enemies_alive += 1


func _on_enemy_died(reward: int, _pos: Vector3) -> void:
	enemies_alive -= 1
	_gain_gold(reward)


func _end_game(victory: bool) -> void:
	game_over = true
	overlay.visible = true
	if victory:
		lbl_end.text = "VICTORY! The town stands."
		lbl_end.add_theme_color_override("font_color", Color(1, 0.9, 0.35))
	else:
		lbl_end.text = "DEFEAT! The Keep has fallen."
		lbl_end.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))
