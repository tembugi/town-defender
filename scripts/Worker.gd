class_name Worker
extends Node2D

# An auto-gathering villager. Loops: find nearest resource node -> walk to it ->
# harvest (axe/pickaxe) -> carry the yield back to the Keep -> deposit gold ->
# repeat. Layered like the hero but with a different hairstyle (longhair) so
# you can tell workers apart.

const HC := "res://Assets/Characters/Human/"
const LAYERS := {
	"base": {
		"idle": HC + "IDLE/base_idle_strip9.png", "run": HC + "RUN/base_run_strip8.png",
		"axe": HC + "AXE/base_axe_strip10.png", "mining": HC + "MINING/base_mining_strip10.png",
		"carry": HC + "CARRY/base_carry_strip8.png",
	},
	"hair": {
		"idle": HC + "IDLE/longhair_idle_strip9.png", "run": HC + "RUN/longhair_run_strip8.png",
		"axe": HC + "AXE/longhair_axe_strip10.png", "mining": HC + "MINING/longhair_mining_strip10.png",
		"carry": HC + "CARRY/longhair_carry_strip8.png",
	},
	"tools": {
		"idle": HC + "IDLE/tools_idle_strip9.png", "run": HC + "RUN/tools_run_strip8.png",
		"axe": HC + "AXE/tools_axe_strip10.png", "mining": HC + "MINING/tools_mining_strip10.png",
		"carry": HC + "CARRY/tools_carry_strip8.png",
	},
}
const ANIMS := {"idle": [8.0, true], "run": [11.0, true], "axe": [14.0, true], "mining": [14.0, true], "carry": [11.0, true]}
const SPEED := 58.0

var game: Node
var layers: Array[AnimatedSprite2D] = []
var anim := ""
var facing := 1.0
var state := "seek"
var target: HarvestNode = null
var carry := 0


func setup(g: Node) -> void:
	game = g
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
	match state:
		"seek": _seek(delta)
		"harvest": _harvest(delta)
		"carry": _carry(delta)


func _seek(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.depleted:
		target = game.nearest_node_for_worker(global_position)
	if target == null:
		_set_anim("idle")
		return
	var to: Vector2 = target.global_position - global_position
	if to.length() <= 20.0:
		_set_anim("idle")
		state = "harvest"
		return
	global_position += to.normalized() * SPEED * delta
	_face(to.x)
	_set_anim("run")


func _harvest(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.depleted:
		state = "seek"
		return
	_face(target.global_position.x)
	_set_anim("axe" if target.ntype == "tree" else "mining")
	if target.work(delta):
		carry = target.yield_coins
		target = null
		state = "carry"


func _carry(delta: float) -> void:
	if game.keep == null or not is_instance_valid(game.keep) or game.keep.dead:
		_set_anim("idle")
		return
	var to: Vector2 = game.keep.global_position - global_position
	if to.length() <= 30.0:
		game.worker_deposit(carry, global_position)
		carry = 0
		state = "seek"
		return
	global_position += to.normalized() * SPEED * delta
	_face(to.x)
	_set_anim("carry")


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
