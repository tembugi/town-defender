class_name Rig
extends RefCounted

# Builds a shared AnimationLibrary from the KayKit Rig_Medium animation packs
# and attaches it to any character that uses that rig (Knight, Skeleton, etc.).
# Character .glb files have the mesh+skeleton but no animations; the anims live
# in the General/MovementBasic libraries and are applied via the matching rig.

const GENERAL := "res://Models/animations/Rig_Medium_General.glb"
const MOVEMENT := "res://Models/animations/Rig_Medium_MovementBasic.glb"
# clips that should loop (locomotion/idle); everything else plays once
const LOOPING := ["Idle_A", "Idle_B", "Walking_A", "Walking_B", "Walking_C", "Running_A", "Running_B"]

static var _lib: AnimationLibrary = null


static func _ensure() -> void:
	if _lib != null:
		return
	_lib = AnimationLibrary.new()
	for path in [GENERAL, MOVEMENT]:
		var inst := (load(path) as PackedScene).instantiate()
		var sap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		for ln in sap.get_animation_library_list():
			var src := sap.get_animation_library(ln)
			for an in src.get_animation_list():
				if _lib.has_animation(an):
					continue
				var a := src.get_animation(an)
				if an in LOOPING:
					a.loop_mode = Animation.LOOP_LINEAR
				_lib.add_animation(an, a)
		inst.free()


# Adds an AnimationPlayer holding all anims to a character; default root_node
# ("..") resolves the Rig_Medium/Skeleton3D:bone tracks against the character.
static func attach(character: Node) -> AnimationPlayer:
	_ensure()
	var ap := AnimationPlayer.new()
	character.add_child(ap)
	ap.add_animation_library("", _lib)
	return ap
