class_name ResourceNode3D
extends Node3D

# A harvestable tree or rock. Someone (hero/worker) stands next to it and works;
# progress fills, the node depletes (shrinks away), yields gold, and regrows.

const TREE := "res://Models/hexagon/decoration/nature/tree_single_A.gltf"
const ROCK := "res://Models/hexagon/decoration/nature/rock_single_B.gltf"
const BASE_SCALE := 1.5

var ntype := "tree"          # "tree" | "rock"
var work_time := 1.4
var yield_amt := 5
var regrow_time := 10.0
var progress := 0.0
var depleted := false
var model: Node3D
var body: StaticBody3D


func setup(type: String) -> void:
	ntype = type
	if type == "rock":
		work_time = 4.5
		yield_amt = 8
		regrow_time = 12.0
		model = (load(ROCK) as PackedScene).instantiate()
	else:
		work_time = 3.0
		yield_amt = 5
		regrow_time = 10.0
		model = (load(TREE) as PackedScene).instantiate()
	model.scale = Vector3.ONE * BASE_SCALE
	model.rotation.y = randf() * TAU
	add_child(model)
	Rig.set_shadows(model, false)   # perf: many props, skip their shadows
	body = Rig.obstacle(0.5 if type == "rock" else 0.4, 1.5)
	add_child(body)


# Body radius for the hero's cone-overlap test (matches the collider footprint).
func hit_radius() -> float:
	return 0.5 if ntype == "rock" else 0.4


func work(delta: float) -> bool:
	if depleted:
		return false
	progress += delta / work_time
	if progress >= 1.0:
		_deplete()
		return true
	return false


func _deplete() -> void:
	depleted = true
	progress = 0.0
	body.collision_layer = 0   # nothing to bump into while it's gone
	var tw := create_tween()
	tw.tween_property(model, "scale", Vector3.ONE * 0.05, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): model.visible = false)
	get_tree().create_timer(regrow_time).timeout.connect(_regrow)


func _regrow() -> void:
	depleted = false
	body.collision_layer = Rig.L_OBSTACLE
	model.visible = true
	model.scale = Vector3.ONE * 0.05
	var tw := create_tween()
	tw.tween_property(model, "scale", Vector3.ONE * BASE_SCALE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
