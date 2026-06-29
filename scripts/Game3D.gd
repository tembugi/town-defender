extends Node3D

# 3D rebuild - Chunk 1: a hero on a ground plane, a fixed tilted follow-camera,
# and joystick/WASD movement. Foundation for the 3D town-defender.

const CAM_OFFSET := Vector3(0, 12, 12)
const CAM_LOOK := Vector3(0, 1.0, 0)

var hero: Hero3D
var cam: Camera3D
var joystick: TouchJoystick


func _ready() -> void:
	_build_environment()
	_build_ground()

	hero = Hero3D.new()
	add_child(hero)

	cam = Camera3D.new()
	cam.fov = 42.0
	add_child(cam)
	cam.position = hero.position + CAM_OFFSET
	cam.look_at(hero.position + CAM_LOOK, Vector3.UP)

	_build_touch_ui()


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.74, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.72, 0.78)
	env.ambient_light_energy = 0.9
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -45, 0)
	sun.light_energy = 1.1
	add_child(sun)


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.6, 0.32)
	ground.material_override = mat
	add_child(ground)


func _build_touch_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	joystick = TouchJoystick.new()
	layer.add_child(joystick)


func _process(delta: float) -> void:
	# input: keyboard, else joystick
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): v.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): v.x += 1
	if v == Vector2.ZERO and joystick.move_vec != Vector2.ZERO:
		v = joystick.move_vec
	hero.move_input = v.limit_length(1.0)

	# smooth follow camera
	var t := clampf(delta * 8.0, 0.0, 1.0)
	cam.position = cam.position.lerp(hero.position + CAM_OFFSET, t)
	cam.look_at(hero.position + CAM_LOOK, Vector3.UP)
