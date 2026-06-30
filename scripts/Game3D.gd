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
const BUILD_RANGE := 1.8

const HOME := "res://Models/hexagon/buildings/blue/building_home_A_blue.gltf"
const MARKET := "res://Models/hexagon/buildings/blue/building_market_blue.gltf"
const BARRACKS := "res://Models/hexagon/buildings/blue/building_barracks_blue.gltf"

# the pack's buildings vary wildly in size; normalise them to proper buildings
const BUILDING_SCALE := {"house": 2.3, "workshop": 1.9, "barracks": 1.4}
const BUILDING_BLOB := {"house": 1.0, "workshop": 1.5, "barracks": 1.1}

const HERO_ATK_RANGE := 1.6
const HERO_ARC := deg_to_rad(45.0)   # half-angle of the frontal cone the swing hits
const HERO_DMG := 20.0          # higher per-hit since swings are slower now
const HERO_ATK_CD := 0.75       # slower, more deliberate swings (less "snap snap")
const HERO_WINDUP := 0.22            # delay from swing start to the hit landing
const ENEMY_HIT_R := 0.4             # enemy body radius for "at least partly in the cone"
const HERO_PICKUP := 1.1             # the player grabs resource piles within this
const KEEP_MAX := 1500.0
const TOTAL_WAVES := 8
const WAVE_CD := 5.0          # seconds between launching waves (can stack waves)
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
var drops: Array[ResourceDrop3D] = []   # loose resources on the ground awaiting pickup
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
var in_combat := false        # enemies still pending to spawn or alive
var spawn_list: Array = []
var spawn_t := 0.0
var enemies_alive := 0
var wave_cd := 0.0            # cooldown before the next wave can be launched
var hero_atk_cd := 0.0
var game_over := false
var shake_t := 0.0          # camera-shake time remaining
var shake_amt := 0.0        # camera-shake amplitude
var keep_fx_cd := 0.0       # throttle for keep-hit shake/flash during a siege
var hurt_flash: ColorRect   # red full-screen flash when the Keep is hit
var lbl_keep: Label
var lbl_wave: Label
var lbl_soldiers: Label
var btn_wave: Button
var wave_cd_fill: ColorRect   # dark overlay that shrinks as the cooldown ticks down
var overlay: ColorRect
var lbl_end: Label


func _ready() -> void:
	if OS.has_feature("web"):
		get_viewport().scaling_3d_scale = 0.75   # render 3D at 75% on mobile/web -> big GPU win
	_build_environment()
	_build_pads()    # before _build_world so resources avoid building plots
	_build_world()

	hero = Hero3D.new()
	hero.bounds = field_rect
	hero.atk_range = HERO_ATK_RANGE      # so the drawn cone matches the hit math
	hero.atk_arc = HERO_ARC
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
	var keep_blob := Rig.blob_shadow(1.5)
	keep_blob.position.y = 0.03
	keep_node.add_child(keep_blob)
	keep_node.add_child(Rig.obstacle(1.3, 4.0))   # units can't walk into the Keep
	var kb := Node3D.new()
	kb.position = Vector3(0, 4.6, 0)
	keep_node.add_child(kb)
	kb.add_child(Rig.bar_quad(Color(0, 0, 0, 0.6), KEEP_BAR_W, 0))
	keep_bar_fill = Rig.bar_quad(Color(0.45, 0.8, 1.0, 1.0), KEEP_BAR_W, 1)
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

	# harvestable resource nodes, kept clear of the centre and the building plots
	var placed := 0
	var tries := 0
	while placed < 18 and tries < 300:
		tries += 1
		var p := Vector3(randf_range(field_rect.position.x, field_rect.end.x), 0, randf_range(field_rect.position.y, field_rect.end.y))
		if Vector2(p.x, p.z).length() < 3.5:
			continue
		if _too_close_to_pad(p, 2.4):
			continue
		var node := ResourceNode3D.new()
		node.position = p
		add_child(node)
		node.setup("rock" if randf() < 0.32 else "tree")
		resource_nodes.append(node)
		placed += 1


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
	# red screen flash for when the Keep takes damage (sits behind the controls)
	hurt_flash = ColorRect.new()
	hurt_flash.color = Color(0.8, 0.0, 0.0, 0.0)
	hurt_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hurt_flash)
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
	btn_wave.clip_contents = true
	wave_cd_fill = ColorRect.new()
	wave_cd_fill.color = Color(0, 0, 0, 0.45)
	wave_cd_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	wave_cd_fill.anchor_right = 0.0   # hidden until a cooldown is running
	wave_cd_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_wave.add_child(wave_cd_fill)
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
	var sbd := sb.duplicate() as StyleBoxFlat
	sbd.bg_color = Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 0.9)
	b.add_theme_stylebox_override("disabled", sbd)
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

	var moving := v.length() >= 0.05
	# the player instantly collects any resource pile it walks over (no carrying)
	for d in get_tree().get_nodes_in_group("drops"):
		var rd := d as ResourceDrop3D
		if rd.taken:
			continue
		if Vector2(rd.position.x - hero.position.x, rd.position.z - hero.position.z).length() <= HERO_PICKUP:
			_gain_gold(rd.pick_up())
	# the swing is universal: it works on the move, faces wherever the hero faces
	# (no lock-on), and acts on whatever is at least partly inside the cone --
	# enemies take damage, trees/rocks get chopped. A swing only starts if there's
	# such a target, and the hit re-checks the cone on landing (dodge/move out = miss).
	var hfwd := _hero_forward()
	var has_target := _target_in_cone(hero.position, hfwd)
	if has_target and hero_atk_cd <= 0.0:
		hero_atk_cd = HERO_ATK_CD
		hero.swing()
		_hero_swing(hero.position, hfwd)
	if moving or has_target:
		hero.gather_target = null
	else:
		# standing still with nothing in the cone: build on a pad we're stood on
		var pad := nearest_pad(hero.position, BUILD_RANGE)
		if pad != null and gold >= pad.cost:
			hero.gather_target = pad
			if pad.advance(delta):
				if pad.btype == "train":
					_train_soldier(pad)
				else:
					_construct(pad)
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

	# smooth follow camera (+ decaying shake offset)
	if keep_fx_cd > 0.0:
		keep_fx_cd -= delta
	var shake := Vector3.ZERO
	if shake_t > 0.0:
		shake_t -= delta
		var s := shake_amt * clampf(shake_t / SHAKE_DUR, 0.0, 1.0)
		shake = Vector3(randf_range(-s, s), randf_range(-s, s), randf_range(-s, s))
	var t := clampf(delta * 8.0, 0.0, 1.0)
	cam.position = cam.position.lerp(hero.position + CAM_OFFSET, t) + shake
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


func spawn_drop(pos: Vector3, amt: int, ntype := "tree") -> void:
	drops = drops.filter(func(d): return is_instance_valid(d) and not d.taken)
	var d := ResourceDrop3D.new()
	d.position = pos + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
	add_child(d)
	d.setup(amt, "stone" if ntype == "rock" else "wood")
	drops.append(d)


# Reserve the nearest loose drop for a worker (so two workers don't chase one).
func claim_drop(from: Vector3) -> ResourceDrop3D:
	var best: ResourceDrop3D = null
	var bestd := INF
	for d in drops:
		if not is_instance_valid(d) or d.taken or d.reserved:
			continue
		var dist := Vector2(d.position.x - from.x, d.position.z - from.z).length()
		if dist < bestd:
			bestd = dist
			best = d
	if best != null:
		best.reserved = true
	return best


const SHAKE_DUR := 0.3


func _camera_shake(amp: float) -> void:
	shake_amt = maxf(shake_amt * clampf(shake_t / SHAKE_DUR, 0.0, 1.0), amp)
	shake_t = SHAKE_DUR


# Floating world-space number (e.g. damage), rises and fades, then frees itself.
func _popup(pos: Vector3, text: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0016
	l.font_size = 40
	l.outline_size = 5
	l.modulate = col
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", pos.y + 1.3, 0.7)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(l.queue_free)


# One-shot burst of little cubes (dust/chips), auto-freed after its lifetime.
func _puff(pos: Vector3, col: Color, count := 8, speed := 2.5) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = 0.5
	p.direction = Vector3(0, 1, 0)
	p.spread = 65.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -7.0, 0)
	p.scale_amount_min = 0.07
	p.scale_amount_max = 0.16
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = mat
	p.mesh = bm
	add_child(p)
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)


func _gain_gold(amt: int) -> void:
	gold += amt
	lbl_gold.text = "Gold: %d" % gold
	# brief brighten so the counter "pops" when it changes
	lbl_gold.modulate = Color(1.7, 1.7, 1.3)
	create_tween().tween_property(lbl_gold, "modulate", Color.WHITE, 0.25)


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


func _too_close_to_pad(p: Vector3, clearance: float) -> bool:
	for pad in build_pads:
		if Vector2(p.x - pad.position.x, p.z - pad.position.z).length() < clearance:
			return true
	return false


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
	var bscale: float = BUILDING_SCALE.get(pad.btype, 1.0)
	var b := (load(pad.building_path) as PackedScene).instantiate()
	b.position = pad.position
	add_child(b)
	b.scale = Vector3.ONE * bscale * 0.3
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector3.ONE * bscale, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# fake ground shadow under the building (not parented to b, so it isn't scaled)
	var brad: float = BUILDING_BLOB.get(pad.btype, 1.0)
	var blob := Rig.blob_shadow(brad)
	blob.position = pad.position
	blob.position.y = 0.03
	add_child(blob)
	var col := Rig.obstacle(brad * 0.8)   # solid building footprint
	col.position = pad.position
	add_child(col)
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
# Unit forward vector from the hero's current facing (faces +Z at yaw 0).
func _hero_forward() -> Vector3:
	var yaw: float = hero.model.rotation.y
	return Vector3(sin(yaw), 0.0, cos(yaw))


# True if an enemy's body circle (radius ENEMY_HIT_R) overlaps the cone defined by
# apex `origin`, axis `fwd`, half-angle HERO_ARC and radius HERO_ATK_RANGE. This is
# an exact circle-vs-(convex)-sector overlap test in the XZ plane.
func _cone_overlaps(origin: Vector3, fwd: Vector3, c: Vector3, r := ENEMY_HIT_R) -> bool:
	var rel := c - origin
	rel.y = 0.0
	var d := rel.length()
	if d <= r:
		return true                                  # right on top of the hero
	var ang := acos(clampf(rel.dot(fwd) / d, -1.0, 1.0))
	if ang <= HERO_ARC:
		return d <= HERO_ATK_RANGE + r               # inside the wedge: just the radius
	# outside the wedge angularly: distance to the nearer edge ray (segment 0..R)
	var perp := Vector3(-fwd.z, 0.0, fwd.x)
	var s := signf(rel.dot(perp))
	if s == 0.0:
		s = 1.0
	var a := s * HERO_ARC
	var edge := Vector3(fwd.x * cos(a) - fwd.z * sin(a), 0.0, fwd.x * sin(a) + fwd.z * cos(a))
	var t := clampf(rel.dot(edge), 0.0, HERO_ATK_RANGE)
	return rel.distance_to(edge * t) <= r


# Is there anything actionable (a live enemy or a standing resource node) at least
# partly inside the cone? Used to decide whether a swing should start.
func _target_in_cone(origin: Vector3, fwd: Vector3) -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy3D
		if not en.dead and _cone_overlaps(origin, fwd, en.global_position):
			return true
	for n in resource_nodes:
		if not n.depleted and _cone_overlaps(origin, fwd, n.global_position, n.hit_radius()):
			return true
	return false


# A universal directional swing. The cone (apex + facing) is committed at swing
# start; after a short windup it acts on everything still overlapping that cone --
# enemies take damage, resource nodes get chopped (and drop on felling). Anything
# that leaves the zone in time is missed.
func _hero_swing(origin: Vector3, fwd: Vector3) -> void:
	get_tree().create_timer(HERO_WINDUP).timeout.connect(func():
		for e in get_tree().get_nodes_in_group("enemies"):
			var en := e as Enemy3D
			if not en.dead and _cone_overlaps(origin, fwd, en.global_position):
				en.take_damage(HERO_DMG, origin)
				_popup(en.global_position + Vector3(0, 2.0, 0), str(int(HERO_DMG)), Color(1, 0.95, 0.5))
		for n in resource_nodes:
			if not n.depleted and _cone_overlaps(origin, fwd, n.global_position, n.hit_radius()):
				# wood chips / stone shards fly off as we chop
				var chip := Color(0.55, 0.36, 0.18) if n.ntype != "rock" else Color(0.55, 0.57, 0.6)
				_puff(n.global_position + Vector3(0, 0.8, 0), chip, 6, 2.0)
				if n.work(HERO_ATK_CD):   # each swing advances felling by one attack interval
					spawn_drop(n.global_position, n.yield_amt, n.ntype))


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
	# throttled shake + red flash so a heavy siege doesn't shake constantly
	if keep_fx_cd <= 0.0:
		keep_fx_cd = 0.35
		_camera_shake(0.18)
		hurt_flash.color.a = 0.22
		create_tween().tween_property(hurt_flash, "color:a", 0.0, 0.45)
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
	# spawn just outside the barracks footprint (toward the Keep) so it isn't
	# born inside the building's collider
	var out: Vector3 = (keep_pos - from)
	out.y = 0
	s.position = from + out.normalized() * 1.6
	add_child(s)
	s.setup(self, guard)
	soldiers.append(s)
	lbl_soldiers.text = "Soldiers: %d" % soldiers.size()


func start_wave() -> void:
	# waves can be stacked: launching one only requires the cooldown to be up
	if game_over or wave_cd > 0.0 or wave >= TOTAL_WAVES:
		return
	if spawn_list.is_empty():
		spawn_t = 0.4
	wave += 1
	var count := 3 + wave * 2
	for n in range(count):
		spawn_list.append(_enemy_cfg(wave))
	in_combat = true
	wave_cd = WAVE_CD
	lbl_wave.text = "Wave: %d/%d" % [wave, TOTAL_WAVES]


func _enemy_cfg(n: int) -> Dictionary:
	return {
		"hp": 55.0 + n * 14.0,     # several hits to kill (not one-shot)
		"speed": NPC_SPEED,
		"reward": 5 + n,
		"dmg": 5.0 + n * 0.8,
	}


func _update_waves(delta: float) -> void:
	if wave_cd > 0.0:
		wave_cd = maxf(0.0, wave_cd - delta)
	if not spawn_list.is_empty():
		spawn_t -= delta
		if spawn_t <= 0.0:
			_spawn_enemy(spawn_list.pop_back(), spawn_points[randi() % spawn_points.size()])
			spawn_t = maxf(0.4, 1.0 - wave * 0.05)
	elif enemies_alive <= 0 and in_combat:
		in_combat = false
		_gain_gold(20 + wave * 8)
		if wave >= TOTAL_WAVES:
			_end_game(true)
	_refresh_wave_btn()


func _refresh_wave_btn() -> void:
	if game_over:
		return
	wave_cd_fill.anchor_right = clampf(wave_cd / WAVE_CD, 0.0, 1.0)
	btn_wave.disabled = wave_cd > 0.0 or wave >= TOTAL_WAVES
	var remaining := spawn_list.size() + enemies_alive
	if remaining > 0:
		btn_wave.text = "WAVE %d\n%d left" % [wave, remaining]
	else:
		btn_wave.text = "START\nWAVE"


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
