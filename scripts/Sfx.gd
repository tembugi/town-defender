extends Node

# Tiny sound manager (autoloaded as `Sfx`). Holds a pool of AudioStreamPlayers,
# plays one-shot SFX with a little pitch variation, and caps how many copies of
# the same sound can overlap so a swarm of deaths doesn't pile into a roar.
# Sounds are placeholder procedural .wav files under res://Audio/sfx/.

const POOL := 14
const NAMES := [
	"swing", "hit", "enemy_death", "chop", "coin", "build", "hire",
	"wave", "keep_hit", "hero_hurt", "victory", "defeat", "click", "step",
]
const MUSIC_DB := -15.0

var streams := {}
var players: Array[AudioStreamPlayer] = []
var music_player: AudioStreamPlayer


func _ready() -> void:
	for n in NAMES:
		var path := "res://Audio/sfx/%s.wav" % n
		if ResourceLoader.exists(path):
			streams[n] = load(path)
	for i in range(POOL):
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	# looping background music on its own player
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = MUSIC_DB
	add_child(music_player)
	var mpath := "res://Audio/sfx/music.wav"
	if ResourceLoader.exists(mpath):
		var m := load(mpath)
		if m is AudioStreamWAV:
			# music is imported uncompressed (PCM), so bytes/2 == frame count (16-bit mono)
			m.loop_mode = AudioStreamWAV.LOOP_FORWARD
			m.loop_begin = 0
			m.loop_end = m.data.size() / 2
		music_player.stream = m


func play_music() -> void:
	if music_player.stream != null and not music_player.playing:
		music_player.play()


func toggle_music(on: bool) -> void:
	if on:
		play_music()
	else:
		music_player.stop()


func play(name: String, volume_db := 0.0, pitch_var := 0.1, max_concurrent := 4) -> void:
	if not streams.has(name):
		return
	var stream: AudioStream = streams[name]
	var playing := 0
	for p in players:
		if p.playing and p.stream == stream:
			playing += 1
	if playing >= max_concurrent:
		return
	var free := _free_player()
	if free == null:
		return
	free.stream = stream
	free.volume_db = volume_db
	free.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	free.play()


func _free_player() -> AudioStreamPlayer:
	for p in players:
		if not p.playing:
			return p
	return null   # all busy: drop this one rather than cut another off
