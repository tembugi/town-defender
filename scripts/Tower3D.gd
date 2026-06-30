class_name Tower3D
extends Node3D

# An arrow tower. Auto-targets the nearest enemy in range and fires homing arrows
# on a cooldown. Built on a tower build pad.

const MODEL := "res://Models/hexagon/buildings/blue/building_tower_A_blue.gltf"
const SCALE := 2.0
const RANGE := 8.0
const FIRE_CD := 1.0
const DMG := 16.0
const MUZZLE_Y := 2.3

var game: Node
var cd := 0.0


func setup(g: Node) -> void:
	game = g
	var b := (load(MODEL) as PackedScene).instantiate()
	b.scale = Vector3.ONE * SCALE
	add_child(b)
	add_child(Rig.blob_shadow(0.9))
	var col := Rig.obstacle(0.8, 4.0)   # units path around the tower
	add_child(col)


func _process(delta: float) -> void:
	cd -= delta
	if cd > 0.0:
		return
	var e: Enemy3D = game.nearest_enemy(global_position, RANGE)
	if e == null:
		return
	cd = FIRE_CD
	var a := Arrow3D.new()
	game.add_child(a)
	a.global_position = global_position + Vector3(0, MUZZLE_Y, 0)
	a.setup(e, DMG)
	Sfx.play("swing", -10.0, 0.18, 4)   # bow twang (placeholder)
