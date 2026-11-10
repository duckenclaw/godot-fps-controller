class_name CombatSfx
extends RefCounted

## Small synthesised placeholder sounds for melee/ranged combat, generated once
## and cached, so the addon ships no audio files for them. Replace any of them by
## assigning your own AudioStream to the matching `sfx_*` export on Hands.

const RATE: int = 22050

static var _cache: Dictionary = {}

static func stream(sound: StringName) -> AudioStream:
	if not _cache.has(sound):
		_cache[sound] = _build(sound)
	return _cache[sound]

static func _build(sound: StringName) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sound)
	var s := PackedFloat32Array()
	match sound:
		&"swing": s = _noise_sweep(rng, 0.22, 500.0, 2600.0, 900.0, 0.55)
		&"draw": s = _noise_sweep(rng, 0.26, 2500.0, 5200.0, 3800.0, 0.3)
		&"hit": s = _thud(rng, 0.16, 520.0, 95.0, 0.9)
		&"shoot": s = _thud(rng, 0.2, 2200.0, 170.0, 0.8)
		&"clang": s = _ring(rng, 0.38, 780.0, 11.0, 0.5)
		&"parry": s = _ring(rng, 0.6, 1320.0, 6.0, 0.55)
		_: s = _thud(rng, 0.1, 800.0, 120.0, 0.5)
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav

## Band-passed noise whose centre frequency sweeps f0 -> f1 -> f2 (whooshes).
static func _noise_sweep(rng: RandomNumberGenerator, dur: float, f0: float, f1: float, f2: float, gain: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / n
		var fc: float = lerpf(f0, f1, t * 2.0) if t < 0.5 else lerpf(f1, f2, t * 2.0 - 1.0)
		var f := 2.0 * sin(PI * fc / RATE)
		var high := rng.randf_range(-1.0, 1.0) - low - 0.7 * band
		band += f * high
		low += f * band
		var env := pow(sin(PI * t), 2.0)
		out[i] = band * env * gain
	return out

## Low-passed noise burst plus a falling sine (impacts, bowstring thwack).
static func _thud(rng: RandomNumberGenerator, dur: float, noise_fc: float, tone: float, gain: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var k := clampf(TAU * noise_fc / RATE, 0.0, 1.0)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += k * (rng.randf_range(-1.0, 1.0) - lp)
		phase += TAU * tone * (1.0 - 0.5 * t / dur) / RATE
		out[i] = (lp * exp(-t * 38.0) * 1.4 + sin(phase) * exp(-t * 24.0) * 0.7) * gain
	return out

## Inharmonic decaying partials with a short noise click (metal on metal).
static func _ring(rng: RandomNumberGenerator, dur: float, f0: float, decay: float, gain: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var partials := [1.0, 2.76, 5.4, 8.93]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for j in partials.size():
			v += sin(TAU * f0 * partials[j] * t) * exp(-t * (decay + 4.0 * j)) / (j + 1.0)
		v += rng.randf_range(-1.0, 1.0) * exp(-t * 260.0) * 0.8
		out[i] = v * gain * 0.6
	return out
