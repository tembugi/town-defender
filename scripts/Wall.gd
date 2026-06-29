class_name Wall
extends Node2D

# A destructible structure: either a stone Wall segment the player places, or
# the central Keep (the thing to defend). Enemies attack these. When the keep
# falls, it's game over.

const ATLAS := "res://Assets/Tileset/spr_tileset_sunnysideworld_16px.png"

const WALL_H := Rect2(704, 16, 16, 30)   # horizontal run (crenellated top)
const WALL_V := Rect2(696, 56, 16, 18)   # vertical run (north-south)

var game: Node
var kind := "wall"           # "wall" | "keep"
var tile := Vector2i.ZERO    # grid cell (walls only)
var max_hp := 120.0
var hp := 120.0
var dead := false
var bar_y := -26.0
var spr: Sprite2D
var _flash := 0.0


func setup(g: Node, k: String) -> void:
	game = g
	kind = k
	z_index = 0
	var s := Sprite2D.new()
	var at := AtlasTexture.new()
	at.atlas = load(ATLAS)
	if k == "keep":
		max_hp = 1500.0
		at.region = Rect2(520, 680, 32, 56)   # purple compact house
		s.offset = Vector2(0, -28)
		s.scale = Vector2(1.3, 1.3)
		bar_y = -82.0
	else:
		max_hp = 120.0
		at.region = WALL_H                      # default horizontal segment
		s.offset = Vector2(0, -13)
		bar_y = -26.0
	hp = max_hp
	s.texture = at
	spr = s
	add_child(spr)


# Orient a wall segment based on its neighbours (called by Game on place/remove).
func set_shape(vertical: bool) -> void:
	if kind != "wall" or spr == null:
		return
	var at := spr.texture as AtlasTexture
	if vertical:
		at.region = WALL_V
		spr.offset = Vector2(0, -8)
	else:
		at.region = WALL_H
		spr.offset = Vector2(0, -13)


func take_damage(amount: float) -> void:
	if dead:
		return
	hp -= amount
	_flash = 0.1
	queue_redraw()
	if hp <= 0.0:
		_destroy()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		spr.modulate = Color(1, 0.5, 0.5) if _flash > 0.0 else Color.WHITE


func _destroy() -> void:
	dead = true
	game.spawn_poof(global_position)
	if kind == "keep":
		game.on_keep_destroyed()
	else:
		game.remove_wall(self)
	queue_free()


func _draw() -> void:
	if dead or hp >= max_hp:
		return
	var w := 36.0 if kind == "keep" else 18.0
	var frac: float = clampf(hp / max_hp, 0.0, 1.0)
	draw_rect(Rect2(-w / 2.0 - 1, bar_y - 1, w + 2, 6), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-w / 2.0, bar_y, w, 4), Color(0.2, 0.05, 0.05))
	var col := Color(0.35, 0.8, 0.4) if frac > 0.4 else Color(0.9, 0.3, 0.2)
	draw_rect(Rect2(-w / 2.0, bar_y, w * frac, 4), col)
