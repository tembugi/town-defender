extends Node3D

# Chunk 0 smoke test: show a KayKit Knight in a lit 3D scene with a tilted
# camera, and try to play an idle animation by applying the shared Rig_Medium
# animation library to the character's skeleton. Throwaway - removed at cutover.

const KNIGHT := "res://Models/characters/Knight.glb"
const ANIM_GENERAL := "res://Models/animations/Rig_Medium_General.glb"


func _ready() -> void:
	_setup_environment()

	# ground
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	ground.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.55, 0.28)
	ground.material_override = mat
	add_child(ground)

	# character
	var knight := (load(KNIGHT) as PackedScene).instantiate()
	add_child(knight)
	_attach_animations(knight)

	# tilted "town-defender" camera looking down at the character
	var cam := Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	cam.position = Vector3(0, 7.0, 7.0)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)


func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.72, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.ambient_light_energy = 0.8
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -45, 0)
	sun.light_energy = 1.1
	add_child(sun)


# Apply the shared Rig_Medium animation library to the character's own skeleton.
func _attach_animations(character: Node) -> void:
	var src := (load(ANIM_GENERAL) as PackedScene).instantiate()
	var src_ap := src.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if src_ap == null:
		push_warning("no AnimationPlayer in animation glb")
		return
	var ap := AnimationPlayer.new()
	character.add_child(ap)
	for lib_name in src_ap.get_animation_library_list():
		ap.add_animation_library("gen", src_ap.get_animation_library(lib_name))
		break
	ap.root_node = ap.get_path_to(character)
	src.queue_free()
	if ap.has_animation("gen/Idle_A"):
		ap.play("gen/Idle_A")
	else:
		print("available: ", ap.get_animation_list())
