class_name Soldier
extends Node2D

# A garrison defender spawned by a Barracks. Holds a guard post near the Keep;
# when an enemy comes within the Keep's defensive leash, it charges and attacks.
# Layered villager with spikey hair so it reads differently from hero/workers.

const HC := "res://Assets/Characters/Human/"
const LAYERS := {
	"base": {
		"idle": HC + "IDLE/base_idle_strip9.png", "run": HC + "RUN/base_run_strip8.png",
		"attack": HC + "ATTACK/base_attack_strip10.png",
	},
	"hair": {
		"idle": HC + "IDLE/spikeyhair_idle_strip9.png", "run": HC + "RUN/spikeyhair_run_strip8.png",
		"attack": HC + "ATTACK/spikeyhair_attack_strip10.png",
	},
	"tools": {
		"idle": HC + "IDLE/tools_idle_strip9.png", "run": HC + "RUN/tools_run_strip8.png",
		"attack": HC + "ATTACK/tools_attack_strip10.png",
	},
}
const ANIMS := {"idle": [8.0, true], "run": [12.0, true], "attack": [15.0, true]}
const SPEED := 72.0
const DAMAGE := 18.0
const ATK_CD := 0.6
const REACH := 22.0
const SIGHT := 220.0
const LEASH := 280.0     # only engage enemies this close to the Keep

var game: Node
var layers: Array[AnimatedSprite2D] = []
var anim := ""
var facing := 1.0
var guard_pos: Vector2
var atk_cd := 0.0


func setup(g: Node, gpos: Vector2) -> void:
	game = g
	guard_pos = gpos
	z_index = 0
	for key in ["base", "hair", "tools"]:
		var files: Dictionary = LAYERS[key]
		var sf := SpriteFrames.new()
		for a in files:
			var d: Array = ANIMS[a]
			Anim.add_sheet(sf, a, files[a], 96, 64, d[0], d[1])
		var s := AnimatedSprite2D.new()
		s.sprite_frames = sf
		s.offset = Vector2(0, -20)
		s.play("idle")
		add_child(s)
		layers.append(s)


func _process(delta: float) -> void:
	atk_cd -= delta
	var e: Enemy = _target()
	if e != null:
		var to: Vector2 = e.global_position - global_position
		if to.length() <= REACH:
			_face(to.x)
			_set_anim("attack")
			if atk_cd <= 0.0:
				atk_cd = ATK_CD
				e.take_damage(DAMAGE)
		else:
			global_position += to.normalized() * SPEED * delta
			_face(to.x)
			_set_anim("run")
	else:
		var to: Vector2 = guard_pos - global_position
		if to.length() > 5.0:
			global_position += to.normalized() * SPEED * delta
			_face(to.x)
			_set_anim("run")
		else:
			_set_anim("idle")


func _target() -> Enemy:
	if game.keep == null or not is_instance_valid(game.keep) or game.keep.dead:
		return null
	var e: Enemy = game.nearest_enemy_from(global_position, SIGHT)
	if e == null:
		return null
	if e.global_position.distance_to(game.keep.global_position) > LEASH:
		return null
	return e


func _set_anim(n: String) -> void:
	if anim == n:
		return
	anim = n
	for s in layers:
		s.play(n)


func _face(x: float) -> void:
	if absf(x) > 0.5:
		facing = signf(x)
		for s in layers:
			s.flip_h = facing < 0
