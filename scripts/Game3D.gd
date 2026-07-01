extends Node3D

# 3D rebuild - hero + hex world + economy. Hero gathers nearby trees/rocks;
# hire workers (button / H) that auto-gather and carry gold to the Keep.


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H:
			hire_worker()
		elif event.keycode == KEY_SPACE:
			start_wave()

# pulled back + ~48° tilt for a zoomed-out survival-defender view (front faces of
# buildings visible, base + surroundings in frame). pitch = atan(y/z).
const CAM_OFFSET := Vector3(0, 12.5, 11.0)
const CAM_LOOK := Vector3(0, 0.5, 0)

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
const TOWER := "res://Models/hexagon/buildings/blue/building_tower_A_blue.gltf"
const WALL := "res://Models/hexagon/buildings/neutral/wall_straight.gltf"
const TOWER_COST := 70
const WALL_COST := 25

# the pack's buildings vary wildly in size; normalise them to proper buildings
const BUILDING_SCALE := {"house": 2.0, "workshop": 1.4, "barracks": 1.4}
const BUILDING_BLOB := {"house": 1.0, "workshop": 1.2, "barracks": 1.1}

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
const AUTO_WAVE_TIME := 15.0   # auto-launch the next wave if not started within this

# Enemy archetypes (base stats; scaled up per wave). aggro = how much hero damage
# it takes to turn on the player (brutes largely ignore you and rush the Keep).
const ENEMY_TYPES := {
	"minion": {"model": "res://Models/enemies/Skeleton_Minion.glb", "scale": 0.55, "hp": 55.0, "speed": NPC_SPEED * 0.8, "dmg": 6.0, "reward": 5, "aggro": 0.5},
	"runner": {"model": "res://Models/enemies/Skeleton_Rogue.glb", "scale": 0.52, "hp": 30.0, "speed": NPC_SPEED * 1.7, "dmg": 4.0, "reward": 6, "aggro": 0.5},
	"brute": {"model": "res://Models/enemies/Skeleton_Warrior.glb", "scale": 0.64, "hp": 145.0, "speed": NPC_SPEED * 0.5, "dmg": 16.0, "reward": 14, "aggro": 3.0},
	"mage": {"model": "res://Models/enemies/Skeleton_Mage.glb", "scale": 0.55, "hp": 42.0, "speed": NPC_SPEED * 0.7, "dmg": 11.0, "reward": 10, "aggro": 0.5, "ranged": true, "cast_range": 6.5},
}

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
var towers: Array = []
var walls: Array[Wall3D] = []
var buildings: Array = []   # freely-placed house/market/barracks (for overlap checks)

# everything buildable from the menu: label, type, cost
const BUILDABLES := [
	{"t": "wall", "c": 25, "l": "Wall"},
	{"t": "tower", "c": 70, "l": "Tower"},
	{"t": "house", "c": 20, "l": "House"},
	{"t": "workshop", "c": 45, "l": "Market"},
	{"t": "barracks", "c": 80, "l": "Barracks"},
]
const WALL_BLOCK_RANGE := 1.6   # how close a raider must be to a wall to attack it
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
var prep_t := AUTO_WAVE_TIME  # countdown to auto-launching the next wave
var hero_atk_cd := 0.0
var game_over := false
var _music_started := false
var shake_t := 0.0          # camera-shake time remaining
var shake_amt := 0.0        # camera-shake amplitude
var keep_fx_cd := 0.0       # throttle for the keep-hit sound + bar pulse during a siege
var hud_keep_fill: ColorRect   # Town Hall HP bar fill in the HUD
var keep_bar_flash := 0.0      # white-flash timers for the health bars
var hero_bar_flash := 0.0
const KEEP3D_COLOR := Color(0.45, 0.8, 1.0)   # base colour of the floating keep bar
const KEEP_HUD_W := 240.0
const HERO_MAX_HP := 100.0
const HERO_REGEN := 5.0        # hp/sec regen when not recently hit
var hero_hp := HERO_MAX_HP
var hero_hit_cd := 0.0         # time since last hit; regen waits for this
var hud_hero_fill: ColorRect
var lbl_hero: Label
var lbl_keep: Label
var lbl_wave: Label
var lbl_soldiers: Label
var btn_wave: Button
var btn_build: Button          # toggles the build menu
var build_menu: Array[Button] = []
var build_menu_open := false
# placement (ghost) mode
var btn_place: Button
var btn_flip: Button
var btn_cancel: Button
var build_mode := false
var build_btype := ""
var build_cost := 0
var build_flip := 0.0          # yaw from the Flip button
var ghost: Node3D              # translucent preview, dragged freely on the field
var ghost_mat: StandardMaterial3D    # single-mesh ghost (non-wall build types)
var ghost_wall_mesh: Node3D          # wall ghost: the straight-segment piece (always present)
var ghost_wall_mat: StandardMaterial3D
var ghost_corner_mesh: Node3D        # wall ghost: the corner piece (only while a corner applies)
var ghost_corner_mat: StandardMaterial3D
var ghost_target := Vector3.ZERO   # raw (unsnapped) ground position the ghost is dragged to
const WALL_SNAP_RADIUS := 1.1      # how close to an existing wall end counts as "attach here"
const WALL_RELEASE_RADIUS := 3.0   # once attached, how far you can drag before letting go
var wall_anchor := Vector3.INF     # wall-only: end point of a neighbouring wall to attach to
var wall_anchor_wall: Wall3D = null   # ...and which wall that end point belongs to
var wave_cd_fill: ColorRect   # dark overlay that shrinks as the cooldown ticks down
var overlay: ColorRect
var lbl_end: Label


func _ready() -> void:
	if OS.has_feature("web"):
		get_viewport().scaling_3d_scale = 0.75   # render 3D at 75% on mobile/web -> big GPU win
	_build_environment()
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
	joystick = TouchJoystick.new()
	layer.add_child(joystick)

	lbl_gold = _hud_label("Gold: %d" % gold, Vector2(22, 18), Color(1, 0.85, 0.25))
	layer.add_child(lbl_gold)
	# Town Hall HP bar (background + fill + centered label)
	var keep_bg := ColorRect.new()
	keep_bg.color = Color(0, 0, 0, 0.55)
	keep_bg.position = Vector2(22, 50)
	keep_bg.size = Vector2(KEEP_HUD_W, 26)
	layer.add_child(keep_bg)
	hud_keep_fill = ColorRect.new()
	hud_keep_fill.position = Vector2(22, 50)
	hud_keep_fill.size = Vector2(KEEP_HUD_W, 26)
	layer.add_child(hud_keep_fill)
	lbl_keep = _hud_label("", Vector2(30, 51), Color(1, 1, 1))
	lbl_keep.add_theme_font_size_override("font_size", 18)
	layer.add_child(lbl_keep)
	_update_keep_hud()
	# Hero HP bar, just below the Town Hall bar
	var hero_bg := ColorRect.new()
	hero_bg.color = Color(0, 0, 0, 0.55)
	hero_bg.position = Vector2(22, 80)
	hero_bg.size = Vector2(KEEP_HUD_W, 26)
	layer.add_child(hero_bg)
	hud_hero_fill = ColorRect.new()
	hud_hero_fill.position = Vector2(22, 80)
	hud_hero_fill.size = Vector2(KEEP_HUD_W, 26)
	layer.add_child(hud_hero_fill)
	lbl_hero = _hud_label("", Vector2(30, 81), Color(1, 1, 1))
	lbl_hero.add_theme_font_size_override("font_size", 18)
	layer.add_child(lbl_hero)
	_update_hero_hud()
	lbl_pop = _hud_label("Workers: 0/%d" % worker_cap, Vector2(22, 116), Color(0.8, 1, 0.8))
	layer.add_child(lbl_pop)
	lbl_soldiers = _hud_label("Soldiers: 0", Vector2(22, 150), Color(1, 0.8, 0.6))
	layer.add_child(lbl_soldiers)
	lbl_wave = _hud_label("Wave: 0/%d" % TOTAL_WAVES, Vector2(22, 184), Color(0.95, 0.7, 0.7))
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

	# BUILD toggle (left side) opens a menu of all placeable structures
	btn_build = _hud_button("BUILD", -160, Color(0.4, 0.58, 0.42), true)
	btn_build.pressed.connect(_toggle_build_menu)
	layer.add_child(btn_build)
	var off := -160.0 - 92.0
	for bdef in BUILDABLES:
		var mb := _menu_button("%s  %dg" % [bdef["l"], bdef["c"]], off, Color(0.42, 0.5, 0.62))
		mb.set_meta("cost", bdef["c"])
		var bt: String = bdef["t"]
		var bc: int = bdef["c"]
		mb.pressed.connect(func(): _enter_build_mode(bt, bc))
		mb.visible = false
		build_menu.append(mb)
		layer.add_child(mb)
		off -= 78.0
	# placement-mode buttons (hidden until a structure is selected)
	btn_place = _hud_button("PLACE", -160, Color(0.4, 0.65, 0.4), true)
	btn_place.pressed.connect(_confirm_place)
	btn_place.visible = false
	layer.add_child(btn_place)
	btn_flip = _hud_button("FLIP", -160 - 130, Color(0.45, 0.55, 0.7), true)
	btn_flip.pressed.connect(func():
		# once a wall is attached to a neighbour, only allow clean 90deg turns --
		# the pack has no corner piece for in-between angles, which left gaps
		var step := PI * 0.5 if (build_btype == "wall" and wall_anchor != Vector3.INF) else PI * 0.25
		build_flip = fmod(build_flip + step, TAU))
	btn_flip.visible = false
	layer.add_child(btn_flip)
	btn_cancel = _hud_button("CANCEL", -160 - 260, Color(0.7, 0.4, 0.4), true)
	btn_cancel.pressed.connect(_exit_build_mode)
	btn_cancel.visible = false
	layer.add_child(btn_cancel)

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


func _hud_button(text: String, top_off: float, col: Color, left := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 24)
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	if left:
		b.anchor_left = 0.0
		b.anchor_right = 0.0
		b.offset_left = 24
		b.offset_right = 180
	else:
		b.anchor_left = 1.0
		b.anchor_right = 1.0
		b.offset_left = -180
		b.offset_right = -24
	b.offset_top = top_off
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


# A compact left-side button used for the build menu list.
func _menu_button(text: String, top_off: float, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 19)
	b.anchor_top = 1.0
	b.anchor_bottom = 1.0
	b.anchor_left = 0.0
	b.anchor_right = 0.0
	b.offset_left = 24
	b.offset_right = 196
	b.offset_top = top_off
	b.offset_bottom = top_off + 68
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.92)
	sb.set_corner_radius_all(14)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	var sbd := sb.duplicate() as StyleBoxFlat
	sbd.bg_color = Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 0.92)
	b.add_theme_stylebox_override("disabled", sbd)
	return b


func _toggle_build_menu() -> void:
	_ensure_music()
	build_menu_open = not build_menu_open
	for b in build_menu:
		b.visible = build_menu_open
	btn_build.text = "BUILD ▲" if build_menu_open else "BUILD"


func _enter_build_mode(btype: String, cost: int) -> void:
	# close the menu, spawn the ghost, swap the HUD into placement mode
	build_menu_open = false
	for b in build_menu:
		b.visible = false
	btn_build.text = "BUILD"
	btn_build.visible = false
	build_mode = true
	build_btype = btype
	build_cost = cost
	build_flip = 0.0
	ghost_target = hero.position + _hero_forward() * 2.0   # start near the hero, freely placed
	wall_anchor = Vector3.INF
	wall_anchor_wall = null
	ghost = _make_ghost(btype)
	add_child(ghost)
	hero.cone.visible = false        # the ghost replaces the attack cone while building
	joystick.visible = false         # free the touch surface for dragging the ghost
	btn_place.visible = true
	btn_flip.visible = true
	btn_cancel.visible = true


func _exit_build_mode() -> void:
	build_mode = false
	if is_instance_valid(ghost):
		ghost.queue_free()   # frees ghost_wall_mesh/ghost_corner_mesh too (its children)
	ghost = null
	ghost_wall_mesh = null
	ghost_wall_mat = null
	ghost_corner_mesh = null
	ghost_corner_mat = null
	ghost_mat = null
	hero.cone.visible = true
	joystick.visible = true
	btn_build.visible = true
	btn_place.visible = false
	btn_flip.visible = false
	btn_cancel.visible = false


func _confirm_place() -> void:
	# place exactly what the ghost is showing, so what you see is what you get
	var exclude: Wall3D = wall_anchor_wall if build_btype == "wall" else null
	var pos: Vector3 = ghost_wall_mesh.position if build_btype == "wall" else ghost.position
	var yaw: float = ghost_wall_mesh.rotation.y if build_btype == "wall" else ghost.rotation.y
	if _place_building(build_btype, build_cost, pos, yaw, exclude):
		if gold < build_cost:
			_exit_build_mode()   # can't afford another -> leave placement mode


# Drag anywhere on the field (in build mode) to move the ghost -- freely, no grid.
func _unhandled_input(event: InputEvent) -> void:
	if not build_mode:
		return
	var sp := Vector2.INF
	if event is InputEventScreenDrag:
		sp = (event as InputEventScreenDrag).position
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		sp = (event as InputEventScreenTouch).position
	elif event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT):
		sp = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		sp = (event as InputEventMouseButton).position
	if sp == Vector2.INF:
		return
	var g := _screen_to_ground(sp)
	if g == Vector3.INF:
		return
	if build_btype == "wall" and wall_anchor != Vector3.INF:
		# already locked onto a neighbour's end: further dragging ROTATES the new
		# segment around that fixed point (drag in an arc to pick the corner
		# angle) instead of re-scanning for a neighbour by raw drag position --
		# otherwise a finger drifting even slightly past the tight snap radius
		# used for acquisition would silently drop the anchor and fall back to
		# free placement wherever the finger happened to be (often right on top
		# of the wall you were trying to corner off of).
		var to_drag := g - wall_anchor
		to_drag.y = 0.0
		if to_drag.length() > WALL_RELEASE_RADIUS:
			wall_anchor = Vector3.INF
			wall_anchor_wall = null
			ghost_target = g
			return
		# 90deg steps only here too (see the Flip handler for why)
		build_flip = snappedf(Vector3(1, 0, 0).signed_angle_to(to_drag, Vector3.UP), PI * 0.5)
		return
	ghost_target = g
	if build_btype != "wall":
		return
	# walls magnet-snap to the nearest end of an existing wall so segments join
	# with zero gap, in whatever direction you like (not tied to any grid)
	var anchor := _nearest_wall_anchor(g)
	if anchor.is_empty():
		wall_anchor = Vector3.INF
		wall_anchor_wall = null
	else:
		# newly acquired: default to continuing that wall's own direction; drag
		# further (or use Flip) to rotate the new segment from there
		wall_anchor = anchor["pos"]
		wall_anchor_wall = anchor["wall"]
		build_flip = anchor["yaw"]


func _update_ghost() -> void:
	if ghost == null:
		return
	var pos_check: Vector3
	var exclude: Wall3D = null
	if build_btype == "wall":
		exclude = wall_anchor_wall
		pos_check = _update_wall_ghost()
	else:
		ghost.position = ghost_target
		ghost.rotation.y = build_flip
		pos_check = ghost.position
	var ok: bool = gold >= build_cost and _valid_build_spot(pos_check, exclude)
	var col := Color(0.4, 1.0, 0.4, 0.45) if ok else Color(1.0, 0.35, 0.35, 0.45)
	if build_btype == "wall":
		ghost_wall_mat.albedo_color = col
		if ghost_corner_mat != null:
			ghost_corner_mat.albedo_color = col
	else:
		ghost_mat.albedo_color = col


# Positions the wall ghost each frame; when the current angle forms a right-angle
# corner with the wall it's snapped to, ALSO shows the corner piece live (pushing
# the wall ghost further out to leave room for it), so you see the join before
# you commit to it. Returns the position to run the build-validity check against.
func _update_wall_ghost() -> Vector3:
	var dir_b := Vector3(1, 0, 0).rotated(Vector3.UP, build_flip)
	var layout := {}
	if wall_anchor != Vector3.INF and wall_anchor_wall != null and is_instance_valid(wall_anchor_wall):
		var dir_a: Vector3 = wall_anchor_wall.position - wall_anchor
		dir_a.y = 0.0
		if dir_a.length() > 0.01:
			layout = _corner_layout(wall_anchor, dir_a.normalized(), dir_b)
	if not layout.is_empty():
		ghost_wall_mesh.position = layout["wall_pos"]
		ghost_wall_mesh.rotation.y = build_flip
		if ghost_corner_mesh == null:
			ghost_corner_mesh = (load(WALL_CORNER_OUTSIDE) as PackedScene).instantiate()
			ghost_corner_mesh.scale = Wall3D.MODEL_SCALE
			ghost_corner_mat = _tint_ghost(ghost_corner_mesh)
			ghost.add_child(ghost_corner_mesh)
		ghost_corner_mesh.position = layout["corner_pos"]
		ghost_corner_mesh.rotation.y = layout["corner_yaw"]
		return layout["wall_pos"]
	if ghost_corner_mesh != null:
		ghost_corner_mesh.queue_free()
		ghost_corner_mesh = null
		ghost_corner_mat = null
	var pos: Vector3 = (wall_anchor + dir_b * (Wall3D.LENGTH * 0.5)) if wall_anchor != Vector3.INF else ghost_target
	ghost_wall_mesh.position = pos
	ghost_wall_mesh.rotation.y = build_flip
	return pos


# Geometry for a right-angle wall corner, derived from the corner asset's own
# measured reach (~1.0 units along each arm from its local origin -- it's a real
# piece with its own footprint, not a zero-size decoration that slots invisibly
# between two already-touching straight segments). Pushes the new wall further
# out to leave room for the corner. Returns {} if dir_a/dir_b aren't a ~90deg
# turn (a straight run, or an angle we don't support corners for).
const CORNER_REACH := 1.0
const CORNER_ANGLE_TOL := 20.0
const WALL_CORNER_OUTSIDE := "res://Models/hexagon/buildings/neutral/wall_corner_A_outside.gltf"

func _corner_layout(anchor: Vector3, dir_a: Vector3, dir_b: Vector3) -> Dictionary:
	if absf(dir_a.angle_to(dir_b) - PI * 0.5) > deg_to_rad(CORNER_ANGLE_TOL):
		return {}
	# The corner piece's two local arms -- (-1,0,0) and (0,0,-1) -- have a FIXED
	# handedness (arm (0,0,-1) always sits at a signed -90deg from arm (-1,0,0);
	# rotating the whole piece can't change that, only mirroring could, and
	# mirroring via negative scale would flip its face winding and risk the mesh
	# disappearing to backface culling). A wall can turn either clockwise or
	# counter-clockwise from the one it's attached to, but only ONE of those
	# senses matches the piece's own fixed handedness -- so for the other sense,
	# swap which local arm plays "attached to dir_a" vs "extends toward dir_b"
	# instead of trying to force a single fixed assignment to fit both.
	var arm_to_a := Vector3(-1, 0, 0)
	var arm_to_b := Vector3(0, 0, -1)
	if dir_a.signed_angle_to(dir_b, Vector3.UP) > 0.0:
		var tmp := arm_to_a
		arm_to_a = arm_to_b
		arm_to_b = tmp
	var corner_pos := anchor - dir_a * CORNER_REACH
	var corner_yaw := arm_to_a.signed_angle_to(dir_a, Vector3.UP)
	var wall_pos := corner_pos + dir_b * (CORNER_REACH + Wall3D.LENGTH * 0.5)
	return {"corner_pos": corner_pos, "corner_yaw": corner_yaw, "wall_pos": wall_pos}


# Project a screen point onto the ground plane (y = 0).
func _screen_to_ground(screen: Vector2) -> Vector3:
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return Vector3.INF
	return from + dir * (-from.y / dir.y)


# Nearest end point of any existing wall within WALL_SNAP_RADIUS of `pos`.
func _nearest_wall_anchor(pos: Vector3) -> Dictionary:
	var best := {}
	var bestd := WALL_SNAP_RADIUS
	for w in walls:
		if not is_instance_valid(w) or w.dead:
			continue
		for ep in Wall3D.endpoints(w.position, w.rotation.y):
			var d: float = Vector2(pos.x - ep.x, pos.z - ep.z).length()
			if d < bestd:
				bestd = d
				best = {"pos": ep, "yaw": w.rotation.y, "wall": w}
	return best


# A translucent green/red preview of a structure (no collider, no logic). Walls
# are a container: _update_wall_ghost populates/repositions the straight-segment
# piece (and, when a corner applies, the corner piece too) each frame, since they
# sit at different world points rather than a single shared offset.
func _make_ghost(btype: String) -> Node3D:
	if btype == "wall":
		var root := Node3D.new()
		ghost_wall_mesh = (load(WALL) as PackedScene).instantiate()
		ghost_wall_mesh.scale = Wall3D.MODEL_SCALE
		ghost_wall_mat = _tint_ghost(ghost_wall_mesh)
		root.add_child(ghost_wall_mesh)
		return root
	var path: String = {"house": HOME, "workshop": MARKET, "barracks": BARRACKS, "tower": TOWER}[btype]
	var g := (load(path) as PackedScene).instantiate()
	g.scale = Vector3.ONE * (Tower3D.SCALE if btype == "tower" else BUILDING_SCALE.get(btype, 1.0))
	ghost_mat = _tint_ghost(g)
	return g


# Tints a model's meshes translucent green (valid/affordable) or red (blocked),
# via an overlay material that _update_ghost repaints each frame; returns it.
func _tint_ghost(g: Node3D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 1.0, 0.4, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var meshes: Array = []
	Rig._collect_meshes(g, meshes)
	for m in meshes:
		(m as GeometryInstance3D).material_overlay = mat
		(m as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mat


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
	if v.length() > 0.01:
		_ensure_music()   # first user gesture -> safe to start audio on web
	# dim buttons we can't act on
	btn_hire.disabled = gold < HIRE_COST or workers.size() >= worker_cap
	if build_menu_open:
		for mb in build_menu:
			mb.disabled = gold < int(mb.get_meta("cost"))

	var moving := v.length() >= 0.05
	# the player instantly collects any resource pile it walks over (no carrying)
	for d in get_tree().get_nodes_in_group("drops"):
		var rd := d as ResourceDrop3D
		if rd.taken:
			continue
		if Vector2(rd.position.x - hero.position.x, rd.position.z - hero.position.z).length() <= HERO_PICKUP:
			_gain_gold(rd.pick_up())
			Sfx.play("coin", -4.0, 0.12, 3)
	if build_mode:
		# placement mode: hero stays put, you drag the ghost on the grid instead
		hero.move_input = Vector2.ZERO
		hero.gather_target = null
		_update_ghost()
	else:
		# the swing is universal: works on the move, faces wherever the hero faces
		# (no lock-on), acting on whatever is at least partly inside the cone --
		# enemies take damage, trees/rocks get chopped. The hit re-checks the cone
		# on landing (dodge/move out = miss).
		var hfwd := _hero_forward()
		var has_target := _target_in_cone(hero.position, hfwd)
		if has_target and hero_atk_cd <= 0.0:
			hero_atk_cd = HERO_ATK_CD
			hero.swing()
			Sfx.play("swing", -6.0, 0.15, 3)
			_hero_swing(hero.position, hfwd)
		if moving or has_target:
			hero.gather_target = null
		else:
			# standing still with nothing in the cone: train soldiers on a barracks pad
			var pad := nearest_pad(hero.position, BUILD_RANGE)
			if pad != null and gold >= pad.cost:
				hero.gather_target = pad
				if pad.advance(delta):
					_train_soldier(pad)
			else:
				hero.gather_target = null

	# passive income from workshops/markets
	if workshops > 0:
		income_t -= delta
		if income_t <= 0.0:
			income_t = 3.0
			_gain_gold(workshops * 3)

	# hero out-of-combat HP regen
	if hero_hit_cd > 0.0:
		hero_hit_cd -= delta
	elif hero_hp < HERO_MAX_HP:
		hero_hp = minf(HERO_MAX_HP, hero_hp + HERO_REGEN * delta)
		_update_hero_hud()

	_update_waves(delta)

	# health-bar damage flashes decay over time
	keep_bar_flash = maxf(0.0, keep_bar_flash - delta)
	hero_bar_flash = maxf(0.0, hero_bar_flash - delta)
	# keep health bar (always visible, empties right to left), flashing the fill
	var kf := clampf(keep_hp / KEEP_MAX, 0.0, 1.0)
	keep_bar_fill.scale.x = kf
	keep_bar_fill.position.x = -KEEP_BAR_W * 0.5 * (1.0 - kf)
	keep_bar_fill.material_override.albedo_color = Rig.flash_color(KEEP3D_COLOR, keep_bar_flash)
	_update_keep_hud()
	_update_hero_hud()

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


func _update_keep_hud() -> void:
	var f := clampf(keep_hp / KEEP_MAX, 0.0, 1.0)
	hud_keep_fill.size.x = KEEP_HUD_W * f
	var base := Color(0.85, 0.3, 0.3).lerp(Color(0.4, 0.85, 0.45), f)   # red when low
	hud_keep_fill.color = Rig.flash_color(base, keep_bar_flash)
	lbl_keep.text = "Town Hall: %d / %d" % [maxi(0, int(keep_hp)), int(KEEP_MAX)]


func _update_hero_hud() -> void:
	var f := clampf(hero_hp / HERO_MAX_HP, 0.0, 1.0)
	hud_hero_fill.size.x = KEEP_HUD_W * f
	var base := Color(0.85, 0.3, 0.3).lerp(Color(0.45, 0.7, 0.95), f)   # red when low
	hud_hero_fill.color = Rig.flash_color(base, hero_bar_flash)
	lbl_hero.text = "Hero: %d / %d" % [maxi(0, int(hero_hp)), int(HERO_MAX_HP)]


func damage_hero(amt: float) -> void:
	if game_over:
		return
	hero_hp -= amt
	hero_hit_cd = 2.5
	hero_bar_flash = Rig.BAR_FLASH
	_update_hero_hud()
	Rig.flash(hero, hero.model, Color(1, 0.3, 0.3))
	_camera_shake(0.08)
	Sfx.play("hero_hurt", -3.0, 0.1, 3)
	if hero_hp <= 0.0:
		_end_game(false, "DEFEAT! The hero has fallen.")


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
	# render the glyph big (sharp) but keep it small on screen via pixel_size;
	# a thick dark outline gives it weight/boldness and readability over the field
	l.pixel_size = 0.0007
	l.font_size = 110
	l.outline_size = 22
	l.outline_modulate = Color(0, 0, 0, 0.9)
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
	Sfx.play("coin", -6.0, 0.12, 3)


func _ensure_music() -> void:
	if not _music_started:
		_music_started = true
		Sfx.play_music()


func hire_worker() -> void:
	_ensure_music()
	if workers.size() >= worker_cap or gold < HIRE_COST:
		return
	gold -= HIRE_COST
	lbl_gold.text = "Gold: %d" % gold
	Sfx.play("hire", -3.0, 0.05, 2)
	var w := Worker3D.new()
	w.position = keep_pos + Vector3(randf_range(-1.5, 1.5), 0, 2.0)
	add_child(w)
	w.setup(self)
	workers.append(w)
	lbl_pop.text = "Workers: %d/%d" % [workers.size(), worker_cap]


# ---------------------------------------------------------------------------
# Build system
# ---------------------------------------------------------------------------
# Free placement: drops the chosen structure wherever the ghost was left (no
# grid). `exclude_wall` lets a wall ignore its own snap-neighbour in the overlap
# check, since a properly attached pair sits exactly LENGTH apart, not overlapping.
func _place_building(btype: String, cost: int, pos: Vector3, yaw := 0.0, exclude_wall: Wall3D = null) -> bool:
	_ensure_music()
	if game_over or gold < cost:
		return false
	pos.y = 0.0
	if not _valid_build_spot(pos, exclude_wall):
		_popup(pos + Vector3(0, 2.2, 0), "Blocked", Color(1, 0.5, 0.4))
		Sfx.play("click", -6.0, 0.1, 2)
		return false
	gold -= cost
	lbl_gold.text = "Gold: %d" % gold
	Sfx.play("build", -3.0, 0.05, 3)
	match btype:
		"tower":
			var t := Tower3D.new()
			t.position = pos
			t.rotation.y = yaw
			add_child(t)
			t.setup(self)
			towers.append(t)
			_pop_in(t, 1.0)
		"wall":
			var w := Wall3D.new()
			w.position = pos
			w.rotation.y = yaw
			add_child(w)
			w.setup(self)
			walls.append(w)
			_pop_in(w, 1.0)
			# a corner was previewed and confirmed -> drop the real (non-decorative
			# in terms of gameplay, but still collision/HP-free) corner piece too,
			# using the exact same layout math the ghost preview used
			if exclude_wall != null and wall_anchor != Vector3.INF and is_instance_valid(exclude_wall):
				var dir_a: Vector3 = exclude_wall.position - wall_anchor
				dir_a.y = 0.0
				if dir_a.length() > 0.01:
					var dir_b := Vector3(1, 0, 0).rotated(Vector3.UP, yaw)
					var layout := _corner_layout(wall_anchor, dir_a.normalized(), dir_b)
					if not layout.is_empty():
						var cap := (load(WALL_CORNER_OUTSIDE) as PackedScene).instantiate()
						cap.scale = Wall3D.MODEL_SCALE
						cap.position = layout["corner_pos"]
						cap.rotation.y = layout["corner_yaw"]
						add_child(cap)
		_:
			_make_building(btype, pos, yaw)
	return true


func _make_building(btype: String, pos: Vector3, yaw: float) -> void:
	var path: String = {"house": HOME, "workshop": MARKET, "barracks": BARRACKS}[btype]
	var bscale: float = BUILDING_SCALE.get(btype, 1.0)
	var b := (load(path) as PackedScene).instantiate()
	b.position = pos
	b.rotation.y = yaw
	add_child(b)
	_pop_in(b, bscale)
	buildings.append(b)
	var brad: float = BUILDING_BLOB.get(btype, 1.0)
	var blob := Rig.blob_shadow(brad)
	blob.position = pos
	blob.position.y = 0.03
	add_child(blob)
	var col := Rig.obstacle(brad * 0.8)
	col.position = pos
	add_child(col)
	match btype:
		"house":
			worker_cap += 2
			lbl_pop.text = "Workers: %d/%d" % [workers.size(), worker_cap]
		"workshop":
			workshops += 1
		"barracks":
			barracks_count += 1
			# reusable "train soldier" pad beside the barracks (rotated with it)
			var tp := BuildPad3D.new()
			tp.position = pos + Vector3(2.0, 0, 0).rotated(Vector3.UP, yaw)
			tp.setup(self, "train", SOLDIER_COST, "Train", BARRACKS)
			add_child(tp)
			build_pads.append(tp)


func _valid_build_spot(pos: Vector3, exclude_wall: Wall3D = null) -> bool:
	var r := field_rect
	if pos.x < r.position.x + 0.5 or pos.x > r.end.x - 0.5 or pos.z < r.position.y + 0.5 or pos.z > r.end.y - 0.5:
		return false
	if Vector2(pos.x, pos.z).length() < 2.8:   # keep clear of the Keep
		return false
	for p in build_pads:
		if Vector2(pos.x - p.position.x, pos.z - p.position.z).length() < 1.7:
			return false
	for t in towers:
		if is_instance_valid(t) and Vector2(pos.x - t.position.x, pos.z - t.position.z).length() < 1.9:
			return false
	for w in walls:
		if w == exclude_wall:
			continue   # the wall we're intentionally attaching to (sits ~LENGTH away, not overlapping)
		if is_instance_valid(w) and Vector2(pos.x - w.position.x, pos.z - w.position.z).length() < 1.4:
			return false
	for bd in buildings:
		if is_instance_valid(bd) and Vector2(pos.x - bd.position.x, pos.z - bd.position.z).length() < 2.2:
			return false
	for nn in resource_nodes:
		if not nn.depleted and Vector2(pos.x - nn.global_position.x, pos.z - nn.global_position.z).length() < 1.3:
			return false
	return true


func _pop_in(node: Node3D, target_scale: float) -> void:
	node.scale = Vector3.ONE * target_scale * 0.3
	create_tween().tween_property(node, "scale", Vector3.ONE * target_scale, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Nearest live wall close to `from` that lies in the `dir` we want to travel
# (i.e. is blocking our path), so raiders chew through it instead of stalling.
func nearest_blocking_wall(from: Vector3, dir: Vector3) -> Wall3D:
	var best: Wall3D = null
	var bestd := WALL_BLOCK_RANGE
	for w in walls:
		if not is_instance_valid(w) or w.dead:
			continue
		var to: Vector3 = w.global_position - from
		to.y = 0.0
		var d := to.length()
		if d < bestd and d > 0.001 and to.normalized().dot(dir) > 0.25:
			bestd = d
			best = w
	return best


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


# ---------------------------------------------------------------------------
# Combat / waves
# ---------------------------------------------------------------------------
# A mage casts a bolt at the hero (if it's aggroed) or the Keep.
func cast_bolt(origin: Vector3, aggroed: bool, dmg: float) -> void:
	var b := EnemyBolt3D.new()
	add_child(b)
	b.global_position = origin
	if aggroed and is_instance_valid(hero):
		b.setup(self, hero.global_position + Vector3(0, 1.0, 0), "hero", dmg, hero)
	else:
		b.setup(self, keep_pos + Vector3(0, 1.5, 0), "keep", dmg, null)
	Sfx.play("swing", -8.0, 0.2, 4)


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
		var hit_any := false
		var chop_any := false
		for e in get_tree().get_nodes_in_group("enemies"):
			var en := e as Enemy3D
			if not en.dead and _cone_overlaps(origin, fwd, en.global_position):
				en.take_damage(HERO_DMG, origin)
				en.add_aggro(1.0)   # hitting it makes it come after the hero
				_popup(en.global_position + Vector3(0, 2.0, 0), str(int(HERO_DMG)), Color(1, 0.95, 0.5))
				hit_any = true
		for n in resource_nodes:
			if not n.depleted and _cone_overlaps(origin, fwd, n.global_position, n.hit_radius()):
				# wood chips / stone shards fly off as we chop
				var chip := Color(0.55, 0.36, 0.18) if n.ntype != "rock" else Color(0.55, 0.57, 0.6)
				_puff(n.global_position + Vector3(0, 0.8, 0), chip, 6, 2.0)
				chop_any = true
				if n.work(HERO_ATK_CD):   # each swing advances felling by one attack interval
					spawn_drop(n.global_position, n.yield_amt, n.ntype)
		if hit_any:
			Sfx.play("hit", -2.0, 0.12, 4)
		if chop_any:
			Sfx.play("chop", -5.0, 0.15, 3))


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
	# feedback lives on the health bar, not the screen: pulse the bar (throttled so
	# a heavy siege gives a steady pulse rather than a solid white bar) + a sound
	if keep_fx_cd <= 0.0:
		keep_fx_cd = 0.4
		keep_bar_flash = Rig.BAR_FLASH
		Sfx.play("keep_hit", -4.0, 0.1, 2)
	_update_keep_hud()
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
	_ensure_music()
	# waves can be stacked: launching one only requires the cooldown to be up
	if game_over or wave_cd > 0.0 or wave >= TOTAL_WAVES:
		return
	if spawn_list.is_empty():
		spawn_t = 0.4
	wave += 1
	prep_t = AUTO_WAVE_TIME
	# wave composition: runners join from wave 2, brutes from wave 3 (both rarer)
	var count := 3 + wave * 2
	for n in range(count):
		var roll := randf()
		var t := "minion"
		if wave >= 2 and roll < 0.28:
			t = "runner"
		elif wave >= 3 and roll > 0.86:
			t = "brute"
		elif wave >= 4 and roll > 0.66 and roll < 0.80:
			t = "mage"
		spawn_list.append(_enemy_cfg(t, wave))
	in_combat = true
	wave_cd = WAVE_CD
	lbl_wave.text = "Wave: %d/%d" % [wave, TOTAL_WAVES]
	Sfx.play("wave", -3.0, 0.05, 1)


func _enemy_cfg(type: String, n: int) -> Dictionary:
	var b: Dictionary = ENEMY_TYPES[type]
	var cfg := {
		"model": b["model"],
		"scale": b["scale"],
		"hp": float(b["hp"]) * (1.0 + 0.16 * n),   # tankier each wave
		"speed": b["speed"],
		"dmg": float(b["dmg"]) + n * 0.6,
		"reward": int(b["reward"]) + n / 2,
		"aggro_threshold": b["aggro"],
	}
	if b.get("ranged", false):
		cfg["ranged"] = true
		cfg["cast_range"] = b.get("cast_range", 6.0)
	return cfg


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
	# auto-launch the next wave if the player dawdles past the prep window --
	# except the very first one, which always needs a manual press (handy while
	# testing/building so combat doesn't force its way in before you're ready)
	if not game_over and wave > 0 and wave < TOTAL_WAVES and wave_cd <= 0.0:
		prep_t -= delta
		if prep_t <= 0.0:
			start_wave()
	else:
		prep_t = AUTO_WAVE_TIME
	_refresh_wave_btn()


func _refresh_wave_btn() -> void:
	if game_over:
		return
	wave_cd_fill.anchor_right = clampf(wave_cd / WAVE_CD, 0.0, 1.0)
	var can_start := wave_cd <= 0.0 and wave < TOTAL_WAVES
	btn_wave.disabled = not can_start
	var remaining := spawn_list.size() + enemies_alive
	if can_start:
		# enabled: show the auto-launch countdown (and current count if mid-siege);
		# the first wave never auto-launches, so it has no countdown to show
		var tail := "  (%d left)" % remaining if remaining > 0 else ""
		if wave == 0:
			btn_wave.text = "START WAVE"
		else:
			btn_wave.text = "START WAVE\nauto %ds%s" % [int(ceil(prep_t)), tail]
	elif remaining > 0:
		btn_wave.text = "WAVE %d\n%d left" % [wave, remaining]
	else:
		btn_wave.text = "FINAL WAVE"


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


func _end_game(victory: bool, defeat_text := "DEFEAT! The Keep has fallen.") -> void:
	game_over = true
	overlay.visible = true
	if victory:
		lbl_end.text = "VICTORY! The town stands."
		lbl_end.add_theme_color_override("font_color", Color(1, 0.9, 0.35))
		Sfx.play("victory", 0.0, 0.0, 1)
	else:
		lbl_end.text = defeat_text
		lbl_end.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))
		Sfx.play("defeat", 0.0, 0.0, 1)
