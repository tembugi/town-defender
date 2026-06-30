class_name Rig
extends RefCounted

# Builds shared AnimationLibraries from KayKit Rig_Medium animation packs and
# attaches them to characters. Adventurers and Skeletons use separate-but-named
# Rig_Medium rigs that aren't cross-compatible, so each has its own anim set.

const SETS := {
	"adventurer": [
		"res://Models/animations/Rig_Medium_General.glb",
		"res://Models/animations/Rig_Medium_MovementBasic.glb",
	],
	"skeleton": [
		"res://Models/enemies/animations/Rig_Medium_General.glb",
		"res://Models/enemies/animations/Rig_Medium_MovementBasic.glb",
	],
}
# clips that should loop (locomotion/idle/gather); everything else plays once
const LOOPING := ["Idle_A", "Idle_B", "Walking_A", "Walking_B", "Walking_C", "Running_A", "Running_B", "Interact"]

static var _libs := {}


static func _ensure(source: String) -> void:
	if _libs.has(source):
		return
	var lib := AnimationLibrary.new()
	for path in SETS[source]:
		var inst := (load(path) as PackedScene).instantiate()
		var sap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		for ln in sap.get_animation_library_list():
			var src := sap.get_animation_library(ln)
			for an in src.get_animation_list():
				if lib.has_animation(an):
					continue
				var a := src.get_animation(an)
				if an in LOOPING:
					a.loop_mode = Animation.LOOP_LINEAR
				lib.add_animation(an, a)
		inst.free()
	_libs[source] = lib


static func attach(character: Node, source := "adventurer") -> AnimationPlayer:
	_ensure(source)
	var ap := AnimationPlayer.new()
	character.add_child(ap)
	ap.add_animation_library("", _libs[source])
	return ap


# A camera-facing quad for HP bars (keeps scale so the fill can shrink).
static func bar_quad(col: Color, width := 0.9) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(width, 0.13)
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


# Recursively toggle shadow casting on all meshes (perf: small/many objects off).
static func set_shadows(n: Node, on: bool) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	for c in n.get_children():
		set_shadows(c, on)
