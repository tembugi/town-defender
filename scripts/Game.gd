extends Node2D

# ===========================================================================
# Sunnyside Town Defender - Phase 1
# A controllable Human hero on a grass arena built from the Sunnyside 16px
# tileset, a follow camera, and gold coins to collect off the ground.
# Foundation for the idle-builder / tower-defense game.
# ===========================================================================

const TILE := 16
const ATLAS := "res://Assets/Tileset/spr_tileset_sunnysideworld_16px.png"

# Arena size in tiles.
const COLS := 52
const ROWS := 32

# Grass tile variants (atlas column,row) - interior grass with light decoration.
const GRASS := [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)]

# Building sprites are single rectangular regions of the 16px atlas (pixel rects).
# Colour bands repeat every 128px: blue, green, orange, red, purple.
const BUILDINGS := {
	"house": {"rect": Rect2(520, 168, 32, 56), "smoke": true},     # blue roof
	"workshop": {"rect": Rect2(520, 424, 32, 56), "smoke": true},  # orange roof
	"barracks": {"rect": Rect2(520, 552, 32, 56), "smoke": true},  # red roof
}
const SMOKE := "res://Assets/Elements/VFX/Chimney Smoke/chimneysmoke_01_strip30.png"

# Hero is layered (base body + hair + tools overlay); all frames are 96x64.
# Each layer provides idle/run/axe/mining strips.
const HC := "res://Assets/Characters/Human/"
const HERO_LAYER_FILES := {
	"base": {
		"idle": HC + "IDLE/base_idle_strip9.png", "run": HC + "RUN/base_run_strip8.png",
		"axe": HC + "AXE/base_axe_strip10.png", "mining": HC + "MINING/base_mining_strip10.png",
		"attack": HC + "ATTACK/base_attack_strip10.png",
	},
	"hair": {
		"idle": HC + "IDLE/shorthair_idle_strip9.png", "run": HC + "RUN/shorthair_run_strip8.png",
		"axe": HC + "AXE/shorthair_axe_strip10.png", "mining": HC + "MINING/shorthair_mining_strip10.png",
		"attack": HC + "ATTACK/shorthair_attack_strip10.png",
	},
	"tools": {
		"idle": HC + "IDLE/tools_idle_strip9.png", "run": HC + "RUN/tools_run_strip8.png",
		"axe": HC + "AXE/tools_axe_strip10.png", "mining": HC + "MINING/tools_mining_strip10.png",
		"attack": HC + "ATTACK/tools_attack_strip10.png",
	},
}
# anim name -> [fps, loop]
const HERO_ANIM_DEF := {"idle": [8.0, true], "run": [12.0, true], "axe": [14.0, true], "mining": [14.0, true], "attack": [16.0, true]}
const HERO_SPEED := 95.0

# Mineable boulder region in the 16px atlas.
const ROCK_RECT := Rect2(856, 344, 32, 31)

var world: Node2D
var ground: TileMapLayer
var hero: Node2D
var hero_layers: Array[AnimatedSprite2D] = []
var hero_facing := 1.0
var hero_anim := "idle"
var cam: Camera2D

var harvest_nodes: Array[HarvestNode] = []

var coins: Array[Coin] = []
var coin_value := 2
var gold := 30   # enough to build the first House right away
var coin_spawn_timer := 0.0

var pads: Array[BuildPad] = []

# combat / defense
var keep: Wall
var walls: Array[Wall] = []
var wall_tiles := {}                 # Vector2i tile -> Wall
var hero_attack_cd := 0.0
const WALL_COST := 6
const HERO_DAMAGE := 26.0
const HERO_ATTACK_RANGE := 34.0

# waves
var wave := 0
var total_waves := 8
var wave_active := false
var spawn_list: Array = []
var spawn_t := 0.0
var enemies_alive := 0
var spawn_points: Array[Vector2] = []
var game_over := false

var lbl_gold: Label
var lbl_hint: Label
var lbl_wave: Label
var lbl_keep: Label
var btn_start: Button
var overlay: ColorRect
var lbl_end: Label
var touch: TouchControls


func _ready() -> void:
	randomize()
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	_build_ground()
	_build_keep()
	_build_hero()
	_scatter_nodes()
	_build_camera()
	_build_ui()
	_build_touch()
	_build_pads()
	_setup_spawn_points()
	for i in range(6):
		_spawn_coin()


func _build_keep() -> void:
	keep = Wall.new()
	keep.position = arena_center()
	keep.z_index = 4
	world.add_child(keep)
	keep.setup(self, "keep")


func _setup_spawn_points() -> void:
	var w := COLS * TILE
	var h := ROWS * TILE
	spawn_points = [
		Vector2(w * 0.5, 1.5 * TILE),
		Vector2(1.5 * TILE, h * 0.5),
		Vector2(w - 1.5 * TILE, h * 0.5),
		Vector2(w * 0.5, h - 1.5 * TILE),
	]


# ---------------------------------------------------------------------------
# Ground (TileMapLayer built in code from the 16px atlas)
# ---------------------------------------------------------------------------
func _build_ground() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var src := TileSetAtlasSource.new()
	src.texture = load(ATLAS)
	src.texture_region_size = Vector2i(TILE, TILE)
	# register every atlas tile we intend to place
	for g in GRASS:
		src.create_tile(g)
	var sid := ts.add_source(src)

	ground = TileMapLayer.new()
	ground.tile_set = ts
	ground.z_index = -10
	world.add_child(ground)

	for y in range(ROWS):
		for x in range(COLS):
			var coord: Vector2i = GRASS[randi() % GRASS.size()]
			ground.set_cell(Vector2i(x, y), sid, coord)


func arena_rect() -> Rect2:
	return Rect2(0, 0, COLS * TILE, ROWS * TILE)

func arena_center() -> Vector2:
	return Vector2(COLS * TILE, ROWS * TILE) * 0.5


# ---------------------------------------------------------------------------
# Harvestable resource nodes (trees -> chop, rocks -> mine), scattered around
# the arena, kept clear of the central build-pad cluster.
# ---------------------------------------------------------------------------
func _scatter_nodes() -> void:
	var c := arena_center()
	var placed := 0
	var tries := 0
	while placed < 26 and tries < 600:
		tries += 1
		var pos := Vector2(randf_range(2 * TILE, (COLS - 2) * TILE), randf_range(2 * TILE, (ROWS - 2) * TILE))
		if pos.distance_to(c) < 130.0:
			continue   # keep the build area open
		var too_close := false
		for n in harvest_nodes:
			if n.position.distance_to(pos) < 28.0:
				too_close = true
				break
		if too_close:
			continue
		var ntype := "rock" if randf() < 0.32 else "tree"
		var n := HarvestNode.new()
		n.position = pos
		n.setup(self, ntype)
		world.add_child(n)
		harvest_nodes.append(n)
		placed += 1


# ---------------------------------------------------------------------------
# Hero (layered AnimatedSprite2D: base body + hair)
# ---------------------------------------------------------------------------
func _build_hero() -> void:
	hero = Node2D.new()
	hero.position = arena_center() + Vector2(0, 110)   # spawn below the village
	hero.z_index = 0   # y-sorted with buildings/trees
	world.add_child(hero)

	# layers drawn bottom-to-top: base body, hair, then the held tool
	for key in ["base", "hair", "tools"]:
		var files: Dictionary = HERO_LAYER_FILES[key]
		var sf := SpriteFrames.new()
		for anim in files:
			var d: Array = HERO_ANIM_DEF[anim]
			Anim.add_sheet(sf, anim, files[anim], 96, 64, d[0], d[1])
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = sf
		spr.offset = Vector2(0, -20)   # put the feet near the node origin
		spr.play("idle")
		hero.add_child(spr)
		hero_layers.append(spr)


func set_hero_anim(name: String) -> void:
	if hero_anim == name:
		return
	hero_anim = name
	for spr in hero_layers:
		spr.play(name)


func face_hero(target_x: float) -> void:
	if absf(target_x - hero.position.x) > 0.5:
		hero_facing = signf(target_x - hero.position.x)


func _build_camera() -> void:
	cam = Camera2D.new()
	cam.zoom = Vector2(3.0, 3.0)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	hero.add_child(cam)
	cam.make_current()


# ---------------------------------------------------------------------------
# Build pads + building construction
# ---------------------------------------------------------------------------
func _build_pads() -> void:
	var c := arena_center()
	var defs := [
		{"type": "house", "cost": 20, "icon": "res://Assets/UI/plant.png", "name": "House", "off": Vector2(-74, 26)},
		{"type": "workshop", "cost": 45, "icon": "res://Assets/UI/hammer.png", "name": "Workshop", "off": Vector2(0, 52)},
		{"type": "barracks", "cost": 80, "icon": "res://Assets/UI/sword.png", "name": "Barracks", "off": Vector2(78, 26)},
	]
	for d in defs:
		var p := BuildPad.new()
		p.position = c + d["off"]
		p.setup(self, d["type"], d["cost"], d["icon"], d["name"])
		world.add_child(p)   # _ready (which loads the icon) runs after setup
		pads.append(p)


func spend_gold(n: int) -> void:
	gold -= n
	lbl_gold.text = "Gold: %d" % gold


func spawn_building(type: String, pos: Vector2) -> void:
	var data: Dictionary = BUILDINGS[type]
	var rect: Rect2 = data["rect"]
	var spr := Sprite2D.new()
	var at := AtlasTexture.new()
	at.atlas = load(ATLAS)
	at.region = rect
	spr.texture = at
	spr.position = pos
	spr.offset = Vector2(0, -rect.size.y / 2.0)   # base sits at pos (for y-sort)
	spr.z_index = 0
	world.add_child(spr)

	# construct: grow in with a little bounce
	spr.scale = Vector2(0.4, 0.4)
	spr.modulate = Color(1, 1, 1, 0.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "scale", Vector2(1, 1), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(spr, "modulate:a", 1.0, 0.25)

	if data.get("smoke", false):
		_add_smoke(pos + Vector2(6, -rect.size.y + 6))


func _add_smoke(pos: Vector2) -> void:
	var tex := load(SMOKE) as Texture2D
	if tex == null:
		return
	var fw := tex.get_width() / 30
	var fh := tex.get_height()
	var sf := SpriteFrames.new()
	Anim.add_sheet(sf, "smoke", SMOKE, fw, fh, 16.0, true)
	var a := AnimatedSprite2D.new()
	a.sprite_frames = sf
	a.position = pos
	a.z_index = 1
	a.play("smoke")
	world.add_child(a)


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	# top status bar (portrait 720 wide)
	var panel := ColorRect.new()
	panel.color = Color(0.12, 0.1, 0.16, 0.72)
	panel.position = Vector2(12, 48)        # below the iPhone status area
	panel.size = Vector2(696, 46)
	ui.add_child(panel)

	lbl_gold = Label.new()
	lbl_gold.text = "Gold: %d" % gold
	lbl_gold.position = Vector2(24, 56)
	lbl_gold.add_theme_font_size_override("font_size", 24)
	lbl_gold.add_theme_color_override("font_color", Color(1, 0.85, 0.25))
	ui.add_child(lbl_gold)

	lbl_keep = Label.new()
	lbl_keep.text = "Keep: 1500"
	lbl_keep.position = Vector2(250, 56)
	lbl_keep.add_theme_font_size_override("font_size", 24)
	lbl_keep.add_theme_color_override("font_color", Color(0.7, 0.85, 1))
	ui.add_child(lbl_keep)

	lbl_wave = Label.new()
	lbl_wave.text = "Wave: 0/%d" % total_waves
	lbl_wave.position = Vector2(520, 56)
	lbl_wave.add_theme_font_size_override("font_size", 24)
	lbl_wave.add_theme_color_override("font_color", Color(0.95, 0.7, 0.7))
	ui.add_child(lbl_wave)

	lbl_hint = Label.new()
	lbl_hint.text = "Drag to move - stand by trees/rocks/pads/enemies to act"
	lbl_hint.position = Vector2(16, 1238)
	lbl_hint.add_theme_font_size_override("font_size", 16)
	lbl_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	ui.add_child(lbl_hint)

	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.size = Vector2(720, 1280)
	overlay.visible = false
	ui.add_child(overlay)
	lbl_end = Label.new()
	lbl_end.position = Vector2(0, 520)
	lbl_end.size = Vector2(720, 80)
	lbl_end.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_end.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_end.add_theme_font_size_override("font_size", 44)
	overlay.add_child(lbl_end)
	var btn_restart := Button.new()
	btn_restart.text = "Play Again"
	btn_restart.position = Vector2(260, 660)
	btn_restart.size = Vector2(200, 64)
	btn_restart.add_theme_font_size_override("font_size", 24)
	btn_restart.pressed.connect(func(): get_tree().reload_current_scene())
	overlay.add_child(btn_restart)


func _build_touch() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	touch = TouchControls.new()
	touch.setup(self)
	layer.add_child(touch)
	# the on-screen WAVE button doubles as our start-wave control
	btn_start = touch.btn_wave


# ---------------------------------------------------------------------------
# Coins
# ---------------------------------------------------------------------------
func _spawn_coin() -> void:
	var c := Coin.new()
	c.value = coin_value
	var m := 3 * TILE
	c.position = Vector2(
		randf_range(m, COLS * TILE - m),
		randf_range(m, ROWS * TILE - m))
	world.add_child(c)
	coins.append(c)


func _collect_coin(c: Coin) -> void:
	gold += c.value
	lbl_gold.text = "Gold: %d" % gold
	coins.erase(c)
	_coin_popup(c.position, c.value)
	c.queue_free()


func _coin_popup(pos: Vector2, amount: int) -> void:
	var l := Label.new()
	l.text = "+%d" % amount
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(1, 0.88, 0.3))
	l.position = pos + Vector2(-6, -16)
	l.z_index = 30
	world.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position", l.position + Vector2(0, -14), 0.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(l.queue_free)


# ---------------------------------------------------------------------------
# Main loop: movement, harvesting, collection
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if game_over:
		return

	var moving := _move_hero(delta)
	hero_attack_cd -= delta

	# action priority while standing still: fight > harvest > idle
	var enemy: Enemy = null if moving else _nearest_enemy(HERO_ATTACK_RANGE)
	var node: HarvestNode = null
	if enemy != null:
		face_hero(enemy.global_position.x)
		set_hero_anim("attack")
		if hero_attack_cd <= 0.0:
			hero_attack_cd = 0.45
			enemy.take_damage(HERO_DAMAGE)
	else:
		if not moving:
			node = _nearest_node()
		if node != null:
			face_hero(node.position.x)
			set_hero_anim("axe" if node.ntype == "tree" else "mining")
			node.work(delta)
		elif moving:
			set_hero_anim("run")
		else:
			set_hero_anim("idle")

	# decay progress on any node the hero isn't actively working
	for n in harvest_nodes:
		if n != node:
			n.decay(delta)

	for spr in hero_layers:
		spr.flip_h = hero_facing < 0

	# collect coins within reach
	for c in coins.duplicate():
		if is_instance_valid(c) and hero.position.distance_to(c.position) < 15.0:
			_collect_coin(c)

	# a few ambient coins so the field is never empty
	coin_spawn_timer -= delta
	if coin_spawn_timer <= 0.0 and coins.size() < 8:
		_spawn_coin()
		coin_spawn_timer = 2.5

	_update_waves(delta)
	lbl_keep.text = "Keep: %d" % (0 if keep == null or keep.dead else int(keep.hp))


func _move_hero(delta: float) -> bool:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
	# touch joystick takes over when there's no keyboard input
	if dir == Vector2.ZERO and touch != null and touch.move_vec != Vector2.ZERO:
		dir = touch.move_vec

	var moving := dir.length() > 0.1
	if moving:
		var move := dir.limit_length(1.0)
		hero.position += move * HERO_SPEED * delta
		var r := arena_rect().grow(-TILE)
		hero.position.x = clampf(hero.position.x, r.position.x, r.position.x + r.size.x)
		hero.position.y = clampf(hero.position.y, r.position.y, r.position.y + r.size.y)
		if absf(move.x) > 0.01:
			hero_facing = signf(move.x)
	return moving


func _nearest_node() -> HarvestNode:
	var best: HarvestNode = null
	var bestd := 26.0
	for n in harvest_nodes:
		if n.depleted:
			continue
		var d := hero.position.distance_to(n.position)
		if d < bestd:
			bestd = d
			best = n
	return best


func drop_coins(pos: Vector2, n: int) -> void:
	for i in range(n):
		var c := Coin.new()
		c.value = coin_value
		c.position = pos + Vector2(randf_range(-14, 14), randf_range(-6, 12))
		world.add_child(c)
		coins.append(c)
		c.scale = Vector2(0.2, 0.2)
		var tw := create_tween()
		tw.tween_property(c, "scale", Vector2(1, 1), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------------------
# Combat helpers
# ---------------------------------------------------------------------------
func _nearest_enemy(rng: float) -> Enemy:
	var best: Enemy = null
	var bestd := rng
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.dead:
			continue
		var d: float = hero.position.distance_to(e.global_position)
		if d < bestd:
			bestd = d
			best = e
	return best


# nearest attackable structure (wall or keep) within range, for enemies
func nearest_structure(from: Vector2, rng: float) -> Wall:
	var best: Wall = null
	var bestd := rng
	if keep != null and not keep.dead:
		var dk := from.distance_to(keep.global_position)
		if dk < bestd:
			bestd = dk
			best = keep
	for w in walls:
		if not is_instance_valid(w) or w.dead:
			continue
		var d := from.distance_to(w.global_position)
		if d < bestd:
			bestd = d
			best = w
	return best


# ---------------------------------------------------------------------------
# Walls
# ---------------------------------------------------------------------------
func _place_wall() -> void:
	if game_over:
		return
	var tile := Vector2i((hero.position / TILE).floor())
	var pos := Vector2(tile.x * TILE + TILE / 2.0, tile.y * TILE + TILE / 2.0)
	if wall_tiles.has(tile):
		return
	if pos.distance_to(arena_center()) < 34.0:
		flash_hint("Can't build on the keep!")
		return
	if gold < WALL_COST:
		flash_hint("Need %d gold for a wall" % WALL_COST)
		return
	spend_gold(WALL_COST)
	var w := Wall.new()
	w.position = pos
	world.add_child(w)
	w.setup(self, "wall")
	w.tile = tile
	walls.append(w)
	wall_tiles[tile] = w
	_refresh_wall_neighbors(tile)


func remove_wall(w: Wall) -> void:
	var t: Vector2i = w.tile
	walls.erase(w)
	wall_tiles.erase(t)
	_refresh_wall_neighbors(t)


# Pick horizontal vs vertical sprite for a wall based on its neighbours.
func _refresh_wall(t: Vector2i) -> void:
	if not wall_tiles.has(t):
		return
	var w: Wall = wall_tiles[t]
	var vert := wall_tiles.has(t + Vector2i(0, -1)) or wall_tiles.has(t + Vector2i(0, 1))
	var horiz := wall_tiles.has(t + Vector2i(-1, 0)) or wall_tiles.has(t + Vector2i(1, 0))
	w.set_shape(vert and not horiz)


func _refresh_wall_neighbors(t: Vector2i) -> void:
	_refresh_wall(t)
	_refresh_wall(t + Vector2i(0, -1))
	_refresh_wall(t + Vector2i(0, 1))
	_refresh_wall(t + Vector2i(-1, 0))
	_refresh_wall(t + Vector2i(1, 0))


func spawn_poof(pos: Vector2) -> void:
	var glint := "res://Assets/Elements/VFX/Glint/spr_deco_glint_01_strip6.png"
	var tex := load(glint) as Texture2D
	if tex == null:
		return
	var fw := tex.get_width() / 6
	var sf := SpriteFrames.new()
	Anim.add_sheet(sf, "p", glint, fw, tex.get_height(), 18.0, false)
	var a := AnimatedSprite2D.new()
	a.sprite_frames = sf
	a.position = pos
	a.z_index = 30
	a.scale = Vector2(1.5, 1.5)
	a.play("p")
	a.animation_finished.connect(func(): a.queue_free())
	world.add_child(a)


# ---------------------------------------------------------------------------
# Waves
# ---------------------------------------------------------------------------
func start_wave() -> void:
	if wave_active or game_over or wave >= total_waves:
		return
	wave += 1
	var count := 3 + wave * 2
	spawn_list.clear()
	for i in range(count):
		spawn_list.append(_enemy_cfg(wave))
	wave_active = true
	spawn_t = 0.4
	btn_start.disabled = true
	lbl_wave.text = "Wave: %d/%d" % [wave, total_waves]
	flash_hint("Wave %d incoming!" % wave)


func _enemy_cfg(n: int) -> Dictionary:
	return {
		"hp": 40.0 + n * 10.0,
		"speed": 20.0 + n * 1.0,
		"reward": 5 + n,
		"dmg": 5.0 + n * 0.8,
	}


func _update_waves(delta: float) -> void:
	if not wave_active:
		return
	if not spawn_list.is_empty():
		spawn_t -= delta
		if spawn_t <= 0.0:
			var cfg: Dictionary = spawn_list.pop_back()
			_spawn_enemy(cfg, spawn_points[randi() % spawn_points.size()])
			spawn_t = maxf(0.35, 0.9 - wave * 0.04)
	elif enemies_alive <= 0:
		wave_active = false
		var bonus := 20 + wave * 8
		gold += bonus
		lbl_gold.text = "Gold: %d" % gold
		if wave >= total_waves:
			_end_game(true)
		else:
			btn_start.disabled = false
			flash_hint("Wave %d cleared!  +%d gold" % [wave, bonus])


func _spawn_enemy(cfg: Dictionary, pos: Vector2) -> void:
	var e := Enemy.new()
	e.add_to_group("enemies")
	e.global_position = pos
	world.add_child(e)
	e.setup(self, cfg)
	e.died.connect(_on_enemy_died)
	enemies_alive += 1


func _on_enemy_died(reward: int, pos: Vector2) -> void:
	enemies_alive -= 1
	gold += reward
	lbl_gold.text = "Gold: %d" % gold
	_coin_popup(pos + Vector2(0, -30), reward)


func on_keep_destroyed() -> void:
	if not game_over:
		_end_game(false)


func _end_game(victory: bool) -> void:
	game_over = true
	overlay.visible = true
	if victory:
		lbl_end.text = "VICTORY! The town stands."
		lbl_end.add_theme_color_override("font_color", Color(1, 0.9, 0.35))
	else:
		lbl_end.text = "DEFEAT! The keep has fallen."
		lbl_end.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))


func flash_hint(msg: String) -> void:
	lbl_hint.text = msg


func _input(event: InputEvent) -> void:
	if game_over:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			_place_wall()
		elif event.keycode == KEY_SPACE:
			start_wave()
