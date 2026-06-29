class_name HarvestNode
extends Node2D

# A harvestable resource node. The hero stands next to it and "works" (axe for
# trees, pickaxe for rocks); a progress bar fills, then the node is depleted,
# drops coins, and regrows after a while. (Modelled on the Sunnyside gathering
# reference: work animation -> progress -> node depletes -> drops.)

const ATLAS := "res://Assets/Tileset/spr_tileset_sunnysideworld_16px.png"
const TREE := "res://Assets/Elements/Plants/spr_deco_tree_01_strip4.png"

var game: Node
var ntype: String          # "tree" | "rock"
var work_time := 1.6
var yield_coins := 4
var regrow_time := 12.0
var bar_y := -46.0

var progress := 0.0
var depleted := false
var spr: Node2D


func setup(g: Node, type: String) -> void:
	game = g
	ntype = type
	z_index = 0
	if type == "tree":
		work_time = 1.6
		yield_coins = 4
		regrow_time = 12.0
		bar_y = -48.0
		var tex := load(TREE) as Texture2D
		var fw := tex.get_width() / 4
		var fh := tex.get_height()
		var sf := SpriteFrames.new()
		Anim.add_sheet(sf, "sway", TREE, fw, fh, 5.0, true)
		var a := AnimatedSprite2D.new()
		a.sprite_frames = sf
		a.offset = Vector2(0, -fh / 2.0 + 4)
		a.frame = randi() % 4
		a.play("sway")
		spr = a
	else:
		work_time = 2.4
		yield_coins = 7
		regrow_time = 16.0
		bar_y = -24.0
		var s := Sprite2D.new()
		var at := AtlasTexture.new()
		at.atlas = load(ATLAS)
		at.region = Rect2(856, 344, 32, 31)
		s.texture = at
		s.offset = Vector2(0, -at.region.size.y / 2.0 + 2)
		spr = s
	add_child(spr)


func work(delta: float) -> void:
	if depleted:
		return
	progress += delta / work_time
	spr.position.x = sin(Time.get_ticks_msec() / 35.0) * 0.7   # shake while struck
	if progress >= 1.0:
		_deplete()
	queue_redraw()


func decay(delta: float) -> void:
	if depleted or progress <= 0.0:
		return
	progress = maxf(0.0, progress - delta * 0.6)
	spr.position.x = 0.0
	queue_redraw()


func _deplete() -> void:
	depleted = true
	progress = 0.0
	spr.position.x = 0.0
	game.drop_coins(global_position, yield_coins)
	var tw := create_tween()
	tw.tween_property(spr, "scale", Vector2(0.1, 0.1), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): spr.visible = false)
	get_tree().create_timer(regrow_time).timeout.connect(_regrow)
	queue_redraw()


func _regrow() -> void:
	depleted = false
	spr.visible = true
	spr.scale = Vector2(0.1, 0.1)
	var tw := create_tween()
	tw.tween_property(spr, "scale", Vector2(1, 1), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	if depleted or progress <= 0.0:
		return
	var w := 22.0
	draw_rect(Rect2(-w / 2.0 - 1, bar_y - 1, w + 2, 6), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(-w / 2.0, bar_y, w * progress, 4), Color(0.4, 0.88, 0.4))
