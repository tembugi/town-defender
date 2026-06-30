class_name BuildPad3D
extends Node3D

# A construction spot: a translucent green ground marker + a floating label with
# the building name and cost. The hero stands on it (with enough gold) to build.

const BUILD_TIME := 1.6

var game: Node
var btype := ""
var cost := 0
var label_text := ""
var building_path := ""

var built := false
var progress := 0.0
var marker: MeshInstance3D
var label: Label3D
var _mat: StandardMaterial3D
var _afford := true


func setup(g: Node, type: String, c: int, lbl: String, bpath: String) -> void:
	game = g
	btype = type
	cost = c
	label_text = lbl
	building_path = bpath


func _ready() -> void:
	marker = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.9
	cyl.bottom_radius = 0.9
	cyl.height = 0.06
	marker.mesh = cyl
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.emission_enabled = true
	_mat.emission_energy_multiplier = 0.5
	marker.material_override = _mat
	marker.position.y = 0.05
	add_child(marker)

	label = Label3D.new()
	label.text = "%s\n%dg" % [label_text, cost]
	label.position = Vector3(0, 1.7, 0)
	label.font_size = 64
	label.outline_size = 18
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)
	_apply_afford(true)


func _process(_delta: float) -> void:
	if built:
		return
	var ok: bool = game.gold >= cost
	if ok != _afford:
		_afford = ok
		_apply_afford(ok)


func _apply_afford(ok: bool) -> void:
	if ok:
		_mat.albedo_color = Color(0.3, 0.9, 0.4, 0.45)
		_mat.emission = Color(0.2, 0.7, 0.3)
		label.modulate = Color(1, 1, 1)
	else:
		_mat.albedo_color = Color(0.6, 0.6, 0.6, 0.4)
		_mat.emission = Color(0.3, 0.3, 0.3)
		label.modulate = Color(0.95, 0.55, 0.5)   # reddish "can't afford"


func advance(delta: float) -> bool:
	progress += delta / BUILD_TIME
	return progress >= 1.0


func mark_built() -> void:
	built = true
	marker.visible = false
	label.visible = false
