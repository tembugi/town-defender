class_name Rig
extends RefCounted

# Builds shared AnimationLibraries from KayKit Rig_Medium animation packs and
# attaches them to characters. Adventurers and Skeletons use separate-but-named
# Rig_Medium rigs that aren't cross-compatible, so each has its own anim set.

const SETS := {
	"adventurer": [
		"res://Models/animations/Rig_Medium_General.glb",
		"res://Models/animations/Rig_Medium_MovementBasic.glb",
		"res://Models/animations/Rig_Medium_CombatMelee.glb",
	],
	"skeleton": [
		"res://Models/enemies/animations/Rig_Medium_General.glb",
		"res://Models/enemies/animations/Rig_Medium_MovementBasic.glb",
		"res://Models/enemies/animations/Rig_Medium_CombatMelee.glb",
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
# Opaque so overlapping bars never alpha-blend into a darker shade.
static func bar_quad(col: Color, width := 0.9, priority := 0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(width, 0.13)
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col.r, col.g, col.b, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.no_depth_test = true
	# both bars skip depth-testing, so without an explicit priority the fill and
	# the black background fight for the same pixels (bar randomly goes black).
	mat.render_priority = priority
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


# Uniform "took damage" flash for any health bar: blend its colour toward white
# for BAR_FLASH seconds. Callers keep a timer, count it down, and feed it here.
const BAR_FLASH := 0.18

static func flash_color(base: Color, t: float) -> Color:
	return base.lerp(Color.WHITE, clampf(t / BAR_FLASH, 0.0, 1.0))


# A flat translucent disc used as a fake shadow under characters.
static func blob_shadow(radius := 0.38) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.02
	cyl.radial_segments = 16
	m.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0, 0, 0, 0.28)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position.y = 0.02
	return m


# Collision layers: units occupy layer 1, static obstacles occupy layer 2.
const L_UNIT := 1
const L_OBSTACLE := 2


# Capsule collider for a walking unit. Origin is at the feet (model origin), so
# the shape is centred at half-height. Call on a CharacterBody3D.
static func make_unit_body(body: CharacterBody3D, radius := 0.36, height := 1.4) -> void:
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING   # top-down: no gravity/floor
	body.collision_layer = L_UNIT
	body.collision_mask = L_UNIT | L_OBSTACLE                 # bump other units + buildings
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = maxf(height, radius * 2.0)
	cs.shape = cap
	cs.position.y = height * 0.5
	body.add_child(cs)


# A static cylindrical obstacle (building / tree / rock) that units slide around.
static func obstacle(radius: float, height := 3.0) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = L_OBSTACLE
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	cs.shape = cyl
	cs.position.y = height * 0.5
	sb.add_child(cs)
	return sb


# --- Weapons -------------------------------------------------------------
# KayKit characters ship unarmed but have a `handslot.r` bone for weapons.
# The sword is a real KayKit Fantasy Weapons Bits asset (sword_B, "sword 2" in
# the pack), same author/rig family as our characters so it scales correctly
# with no extra tuning -- its origin sits at the grip, matching handslot
# convention. The others are still built from primitives.
const SWORD_MODEL := "res://Models/weapons/sword_B.gltf"


static func _box(size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


static func make_weapon(kind := "sword") -> Node3D:
	# the hero's sword is a model asset; load it (fall back to primitives if missing)
	if kind == "sword" and ResourceLoader.exists(SWORD_MODEL):
		return (load(SWORD_MODEL) as PackedScene).instantiate()
	var w := Node3D.new()
	var steel := Color(0.74, 0.78, 0.82)
	var gold := Color(0.82, 0.66, 0.28)
	var wood := Color(0.45, 0.30, 0.17)
	var bone := Color(0.86, 0.84, 0.74)
	if kind == "axe":
		w.add_child(_box(Vector3(0.05, 1.0, 0.05), Vector3(0, 0.4, 0), wood))        # haft
		w.add_child(_box(Vector3(0.32, 0.34, 0.05), Vector3(0.08, 0.88, 0), steel))  # head
	elif kind == "bonesword":
		w.add_child(_box(Vector3(0.05, 0.24, 0.05), Vector3(0, 0.0, 0), bone))       # grip
		w.add_child(_box(Vector3(0.20, 0.05, 0.05), Vector3(0, 0.14, 0), bone))      # guard
		w.add_child(_box(Vector3(0.08, 0.66, 0.025), Vector3(0, 0.49, 0), bone))     # blade
	else: # sword
		w.add_child(_box(Vector3(0.05, 0.26, 0.05), Vector3(0, 0.0, 0), wood))       # grip
		w.add_child(_box(Vector3(0.26, 0.05, 0.06), Vector3(0, 0.15, 0), gold))      # guard
		w.add_child(_box(Vector3(0.07, 0.78, 0.025), Vector3(0, 0.56, 0), steel))    # blade
		w.add_child(_box(Vector3(0.07, 0.07, 0.07), Vector3(0, -0.15, 0), gold))     # pommel
	return w


# Parent a weapon to a character's right-hand slot so it follows the animation.
static func attach_weapon(model: Node, kind := "sword", bone := "handslot.r") -> void:
	var sk := _find_skeleton(model)
	if sk == null:
		return
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	sk.add_child(ba)
	ba.add_child(make_weapon(kind))


# Brief full-body colour flash via a material overlay (e.g. red when hit).
static func flash(host: Node, model: Node, col := Color(1, 1, 1)) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col.r, col.g, col.b, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var meshes: Array = []
	_collect_meshes(model, meshes)
	for m in meshes:
		(m as GeometryInstance3D).material_overlay = mat
	var tw := host.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.14)
	tw.tween_callback(func():
		for m in meshes:
			if is_instance_valid(m):
				(m as GeometryInstance3D).material_overlay = null)


static func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null


# Recursively toggle shadow casting on all meshes (perf: small/many objects off).
static func set_shadows(n: Node, on: bool) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	for c in n.get_children():
		set_shadows(c, on)
