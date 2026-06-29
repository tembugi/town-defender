class_name Enemy
extends Node2D

# A skeleton raider. Walks toward the Keep; if a wall (or the keep) is within
# reach it stops and attacks it. Has HP + health bar, dies with a death anim,
# and rewards gold.

signal died(reward: int, pos: Vector2)

const SK := "res://Assets/Characters/Skeleton/PNG/"

var game: Node
var speed := 26.0
var max_hp := 60.0
var hp := 60.0
var reward := 6
var dmg := 12.0
var atk_interval := 1.2
var atk_cd := 0.0

var dead := false
var state := "walk"
var facing := -1.0
var spr: AnimatedSprite2D
var _flash := 0.0


func setup(g: Node, cfg: Dictionary) -> void:
	game = g
	speed = cfg.get("speed", 26.0)
	max_hp = cfg.get("hp", 60.0)
	hp = max_hp
	reward = cfg.get("reward", 6)
	dmg = cfg.get("dmg", 12.0)
	z_index = 6

	var sf := SpriteFrames.new()
	Anim.add_sheet(sf, "walk", SK + "skeleton_walk_strip8.png", 96, 64, 10.0, true)
	Anim.add_sheet(sf, "attack", SK + "skeleton_attack_strip7.png", 96, 64, 11.0, true)
	Anim.add_sheet(sf, "death", SK + "skeleton_death_strip10.png", 96, 64, 12.0, false)
	spr = AnimatedSprite2D.new()
	spr.sprite_frames = sf
	spr.offset = Vector2(0, -18)
	spr.play("walk")
	add_child(spr)


func _process(delta: float) -> void:
	if dead:
		return
	if _flash > 0.0:
		_flash -= delta
		spr.modulate = Color(1, 0.4, 0.4) if _flash > 0.0 else Color.WHITE

	atk_cd -= delta
	var obstacle = game.nearest_structure(global_position, 18.0)
	if obstacle != null:
		_set_state("attack")
		_face(obstacle.global_position.x)
		if atk_cd <= 0.0:
			atk_cd = atk_interval
			obstacle.take_damage(dmg)
	else:
		_set_state("walk")
		var to: Vector2 = game.keep.global_position - global_position
		if to.length() > 2.0:
			var dir := to.normalized()
			global_position += dir * speed * delta
			_face(dir.x)
	queue_redraw()


func take_damage(amount: float) -> void:
	if dead:
		return
	hp -= amount
	_flash = 0.12
	queue_redraw()
	if hp <= 0.0:
		_die()


func _die() -> void:
	dead = true
	died.emit(reward, global_position)
	state = "death"
	z_index = 4
	spr.modulate = Color.WHITE
	spr.play("death")
	spr.animation_finished.connect(func(): queue_free())
	queue_redraw()


func _set_state(s: String) -> void:
	if state == s or dead:
		return
	state = s
	spr.play(s)


func _face(x: float) -> void:
	if absf(x - global_position.x) > 0.5:
		facing = signf(x - global_position.x)
		spr.flip_h = facing < 0


func _draw() -> void:
	if dead:
		return
	var w := 26.0
	var y := -44.0
	var frac: float = clampf(hp / max_hp, 0.0, 1.0)
	draw_rect(Rect2(-w / 2.0 - 1, y - 1, w + 2, 6), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-w / 2.0, y, w, 4), Color(0.3, 0.05, 0.05))
	var col := Color(0.9, 0.25, 0.2) if frac < 0.5 else Color(0.85, 0.5, 0.2)
	draw_rect(Rect2(-w / 2.0, y, w * frac, 4), col)
