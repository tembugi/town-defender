class_name Anim
extends RefCounted

# Helpers for building SpriteFrames at runtime from horizontal sprite sheets.
# All Tiny Swords unit sheets use 192x192 frames laid out in a single row.

static func add_sheet(sf: SpriteFrames, anim: String, path: String, frame_w: int, frame_h: int, fps: float, loop: bool) -> void:
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("Anim: could not load texture " + path)
		return
	var cols := int(tex.get_width() / frame_w)
	var rows := int(tex.get_height() / frame_h)
	if not sf.has_animation(anim):
		sf.add_animation(anim)
	sf.set_animation_loop(anim, loop)
	sf.set_animation_speed(anim, fps)
	for r in range(rows):
		for c in range(cols):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(c * frame_w, r * frame_h, frame_w, frame_h)
			sf.add_frame(anim, at)

# Build a one-shot AnimatedSprite2D effect (explosion, dust, splash) that frees itself.
static func make_effect(path: String, fps: float, scale: float = 1.0) -> AnimatedSprite2D:
	var sf := SpriteFrames.new()
	add_sheet(sf, "play", path, 192, 192, fps, false)
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = sf
	spr.scale = Vector2(scale, scale)
	spr.animation = "play"
	spr.play("play")
	spr.animation_finished.connect(func(): spr.queue_free())
	return spr
