extends Node

const MIX_RATE := 22050.0
const BUF_LEN := 0.1

# Preload godot-sfxr so class_name / generator work headless without the editor plugin.
const _SfxrGlobals = preload("res://addons/godot_sfxr/SfxrGlobals.gd")
const _SfxrInterface = preload("res://addons/godot_sfxr/SfxrStreamPlayerInterface.gd")
const _SfxrGenerator = preload("res://addons/godot_sfxr/SfxrGenerator.gd")
const _SfxrStreamPlayer = preload("res://addons/godot_sfxr/SfxrStreamPlayer.gd")

var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var oneshot_player: AudioStreamPlayer

var t: float = 0.0
var pulse_phase: float = 0.0
var drone_phase: float = 0.0
var sub_phase: float = 0.0
var lfo_phase: float = 0.0
var vib_phase: float = 0.0
var noise_state: int = 1
var lp_z: float = 0.0
var noise_hp_z: float = 0.0
var drone_lp_z: float = 0.0
var drone_bp_z: float = 0.0

var mode: String = "SAFE"
var heat: float = 22.0
var bed_alive: bool = true
var bed_gain: float = 1.0
var bed_target: float = 1.0

var belt_slip: bool = false
var filter_clog: bool = false
var heat_warn: bool = false
var brownout: bool = false
var power_fault: bool = false
var mining_fault: bool = false
var radar_blank: bool = false
var jam_safe: bool = false
var intrusion: bool = false
var ended: String = ""

var saw_jam: bool = false
var saw_intrusion: bool = false
var saw_kill: bool = false

var kill_cut: bool = false

var stutter_gate: float = 1.0
var stutter_phase: float = 0.0

# Bed dials (units documented in print_bake / lab labels):
#   noise_lp / noise_hpf: Hz — noise path band (HPF then LPF)
#   drone_wave: 0=saw, 1=square (sfxr-style)
#   drone_duty: square duty 0..1 (ignored for saw)
#   drone_lpf: Hz cutoff on drone(+sub) resonant LPF (sfxr fltw style)
#   drone_lpf_res: 0..1 resonance/damping (sfxr fltdmp style)
#   vib_hz: Hz — vibrato rate on drone pitch
#   vib_depth: 0..1 fractional pitch wobble
var modes := {
	"SAFE": {
		"noise_amp": 0.008,
		"noise_lp": 1000.0,
		"noise_hpf": 120.0,
		"drone_hz": 48.0,
		"drone_amp": 0.045,
		"drone_wave": 0.0,
		"drone_duty": 0.45,
		"drone_lpf": 520.0,
		"drone_lpf_res": 0.22,
		"sub_amp": 0.022,
		"pulse_amp": 0.035,
		"pulse_hz": 0.85,
		"pulse_duty": 0.18,
		"pitch": 0.82,
		"lfo_hz": 0.035,
		"lfo_depth": 0.25,
		"vib_hz": 0.18,
		"vib_depth": 0.035,
		"grit": 0.0,
		"master": 1.0,
	},
	"HIGH": {
		"noise_amp": 0.018,
		"noise_lp": 1000.0,
		"noise_hpf": 140.0,
		"drone_hz": 55.0,
		"drone_amp": 0.09,
		"drone_wave": 0.0,
		"drone_duty": 0.4,
		"drone_lpf": 600.0,
		"drone_lpf_res": 0.28,
		"sub_amp": 0.04,
		"pulse_amp": 0.11,
		"pulse_hz": 2.2,
		"pulse_duty": 0.18,
		"pitch": 1.0,
		"lfo_hz": 0.07,
		"lfo_depth": 0.25,
		"vib_hz": 0.22,
		"vib_depth": 0.04,
		"grit": 0.0,
		"master": 1.0,
	},
	"MAX": {
		"noise_amp": 0.03,
		"noise_lp": 1200.0,
		"noise_hpf": 160.0,
		"drone_hz": 70.0,
		"drone_amp": 0.13,
		"drone_wave": 1.0,
		"drone_duty": 0.35,
		"drone_lpf": 720.0,
		"drone_lpf_res": 0.35,
		"sub_amp": 0.06,
		"pulse_amp": 0.16,
		"pulse_hz": 3.6,
		"pulse_duty": 0.18,
		"pitch": 1.18,
		"lfo_hz": 0.12,
		"lfo_depth": 0.25,
		"vib_hz": 0.35,
		"vib_depth": 0.055,
		"grit": 0.07,
		"master": 1.0,
	},
}

# One-shot sfxr config: preset name + seed + optional param overrides.
# Presets map to SfxrGlobals.PRESETS (HIT / BLIP / EXPLOSION).
var oneshots := {
	"thud": {
		"preset": "HIT",
		"seed": 42,
		"sound_vol": 0.42,
		"p_base_freq": 0.11,
		"p_freq_ramp": -0.42,
		"p_env_sustain": 0.08,
		"p_env_decay": 0.28,
		"p_env_punch": 0.45,
		"wave_type": 3,
	},
	"alarm": {
		"preset": "BLIP",
		"seed": 7,
		"sound_vol": 0.32,
		"p_base_freq": 0.58,
		"p_env_sustain": 0.14,
		"p_env_decay": 0.55,
		"p_repeat_speed": 0.42,
		"p_hpf_freq": 0.12,
		"wave_type": 0,
		"p_duty": 0.28,
	},
	"kill": {
		"preset": "EXPLOSION",
		"seed": 99,
		"sound_vol": 0.48,
		"p_base_freq": 0.09,
		"p_freq_ramp": -0.38,
		"p_env_sustain": 0.22,
		"p_env_decay": 0.45,
		"p_env_punch": 0.65,
		"p_hpf_freq": 0.08,
		"wave_type": 3,
	},
}

## Live voice params — what `_sample` reads every frame.
var live := {
	"noise_amp": 0.018,
	"noise_lp": 1000.0,
	"noise_hpf": 140.0,
	"drone_hz": 55.0,
	"drone_amp": 0.09,
	"drone_wave": 0.0,
	"drone_duty": 0.4,
	"drone_lpf": 600.0,
	"drone_lpf_res": 0.28,
	"sub_amp": 0.04,
	"pulse_amp": 0.11,
	"pulse_hz": 2.2,
	"pulse_duty": 0.18,
	"pitch": 1.0,
	"lfo_hz": 0.07,
	"lfo_depth": 0.25,
	"vib_hz": 0.22,
	"vib_depth": 0.04,
	"grit": 0.0,
	"master": 1.0,
}


func _ready() -> void:
	player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = BUF_LEN
	player.stream = gen
	player.bus = "Master"
	add_child(player)
	player.play()
	playback = player.get_stream_playback() as AudioStreamGeneratorPlayback

	oneshot_player = AudioStreamPlayer.new()
	oneshot_player.bus = "Master"
	add_child(oneshot_player)


func reset() -> void:
	t = 0.0
	pulse_phase = 0.0
	drone_phase = 0.0
	sub_phase = 0.0
	lfo_phase = 0.0
	vib_phase = 0.0
	noise_state = 1
	lp_z = 0.0
	noise_hp_z = 0.0
	drone_lp_z = 0.0
	drone_bp_z = 0.0
	mode = "SAFE"
	heat = 22.0
	bed_alive = true
	bed_gain = 1.0
	bed_target = 1.0
	belt_slip = false
	filter_clog = false
	heat_warn = false
	brownout = false
	power_fault = false
	mining_fault = false
	radar_blank = false
	jam_safe = false
	intrusion = false
	ended = ""
	saw_jam = false
	saw_intrusion = false
	saw_kill = false
	kill_cut = false
	stutter_gate = 1.0
	stutter_phase = 0.0
	load_mode_into_dials("SAFE")
	if oneshot_player != null and oneshot_player.playing:
		oneshot_player.stop()
	if player != null and not player.playing:
		player.play()
		playback = player.get_stream_playback() as AudioStreamGeneratorPlayback


func set_mode(m: String) -> void:
	if not modes.has(m):
		return
	mode = m
	load_mode_into_dials(m)


func get_mode() -> String:
	return mode


func get_dials() -> Dictionary:
	return live.duplicate()


func set_dials(d: Dictionary) -> void:
	for k in live.keys():
		if d.has(k):
			live[k] = float(d[k])


func load_mode_into_dials(m: String) -> void:
	if not modes.has(m):
		return
	var src: Dictionary = modes[m]
	for k in live.keys():
		if src.has(k):
			live[k] = float(src[k])


func save_dials_into_mode(m: String) -> void:
	if not modes.has(m):
		return
	var row: Dictionary = modes[m]
	for k in live.keys():
		row[k] = float(live[k])
	modes[m] = row


func set_event(name: String, on: bool) -> void:
	match name:
		"slip":
			belt_slip = on
		"clog":
			filter_clog = on
		"heat":
			heat_warn = on
			if on:
				heat = maxf(heat, 82.0)
			else:
				heat = 22.0
		"brownout":
			brownout = on
		"jam":
			jam_safe = on
		"intrusion":
			intrusion = on
		"kill":
			if on:
				ended = "kill"
				kill_cut = true
				saw_kill = true
			else:
				ended = ""
				kill_cut = false
				saw_kill = false
		_:
			return
	_refresh_bed_state()


func fire_thud() -> void:
	_play_oneshot("thud")


func fire_alarm() -> void:
	_play_oneshot("alarm")


func fire_kill() -> void:
	_play_oneshot("kill")


func _preset_enum(name: String) -> int:
	# SfxrGlobals.PRESETS: NONE=0 … HIT=5 … BLIP=8 … EXPLOSION=3 … MUTATE=12
	match name.to_upper():
		"PICKUP":
			return 1
		"LASER":
			return 2
		"EXPLOSION":
			return 3
		"POWERUP":
			return 4
		"HIT":
			return 5
		"JUMP":
			return 6
		"CLICK":
			return 7
		"BLIP":
			return 8
		"SYNTH":
			return 9
		"RANDOM":
			return 10
		"TONE":
			return 11
		"MUTATE":
			return 12
		_:
			return 5


func _build_oneshot_wav(kind: String) -> AudioStreamWAV:
	var cfg: Dictionary = oneshots.get(kind, {})
	var bag = _SfxrStreamPlayer.new()
	# Ensure interface defaults / globals resolve via preloads.
	var _g = _SfxrGlobals
	var _i = _SfxrInterface
	seed(int(cfg.get("seed", 1)))
	bag.preset_values(_preset_enum(str(cfg.get("preset", "HIT"))))
	for k in cfg.keys():
		if k == "preset" or k == "seed":
			continue
		bag.set(k, cfg[k])
	var gen = _SfxrGenerator.new()
	var wav: AudioStreamWAV = gen.build_sample(bag)
	if wav != null:
		wav.format = AudioStreamWAV.FORMAT_8_BITS
	bag.free()
	return wav


func _play_oneshot(kind: String) -> void:
	if oneshot_player == null:
		return
	var wav := _build_oneshot_wav(kind)
	if wav == null:
		return
	if oneshot_player.playing:
		oneshot_player.stop()
	oneshot_player.stream = wav
	oneshot_player.play()


func print_bake() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Bed dial units:")
	lines.append("#   noise_lp / noise_hpf: Hz on noise path (HPF then LPF).")
	lines.append("#   drone_wave: 0=saw, 1=square; drone_duty: square duty 0..1.")
	lines.append("#   drone_lpf: Hz resonant LPF on drone(+sub); drone_lpf_res: 0..1 damping.")
	lines.append("#   vib_hz: Hz vibrato rate; vib_depth: 0..1 pitch wobble (sfxr vib).")
	lines.append("var modes := {")
	for m in ["SAFE", "HIGH", "MAX"]:
		var row: Dictionary = modes[m]
		lines.append("\t\"%s\": {" % m)
		var keys := [
			"noise_amp",
			"noise_lp",
			"noise_hpf",
			"drone_hz",
			"drone_amp",
			"drone_wave",
			"drone_duty",
			"drone_lpf",
			"drone_lpf_res",
			"sub_amp",
			"pulse_amp",
			"pulse_hz",
			"pulse_duty",
			"pitch",
			"lfo_hz",
			"lfo_depth",
			"vib_hz",
			"vib_depth",
			"grit",
			"master",
		]
		for i in keys.size():
			var k: String = keys[i]
			var comma := "," if i < keys.size() - 1 else ""
			lines.append("\t\t\"%s\": %s%s" % [k, _fmt_num(float(row.get(k, 0.0))), comma])
		var trail := "," if m != "MAX" else ""
		lines.append("\t}%s" % trail)
	lines.append("}")
	lines.append("")
	lines.append("# One-shots via vendored godot-sfxr (HIT / BLIP / EXPLOSION).")
	for kind in ["thud", "alarm", "kill"]:
		var cfg: Dictionary = oneshots[kind]
		lines.append("oneshots[\"%s\"] preset=%s seed=%s" % [kind, str(cfg.get("preset", "")), str(cfg.get("seed", 0))])
	var text := "\n".join(lines)
	print(text)
	return text


func _fmt_num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return "%.1f" % v
	var s := "%.6f" % v
	while s.ends_with("0") and s.contains("."):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s += "0"
	return s


func _refresh_bed_state() -> void:
	if kill_cut or ended == "kill" or jam_safe or mining_fault:
		bed_alive = false
		bed_target = 0.0
	else:
		bed_alive = true
		if power_fault or radar_blank or brownout:
			bed_target = 0.08
		else:
			bed_target = 1.0


func sync(sim) -> void:
	mode = str(sim.mode)
	heat = float(sim.heat)
	ended = str(sim.ended)
	radar_blank = bool(sim.radar_blank)
	power_fault = str(sim.sector_state("power")) == "FAULT"
	mining_fault = str(sim.sector_state("mining")) == "FAULT"

	belt_slip = false
	filter_clog = false
	heat_warn = false
	brownout = false
	jam_safe = false
	intrusion = false
	for e in sim.events:
		var typ := str(e.type)
		if typ == "BELT_SLIP":
			belt_slip = true
		elif typ == "FILTER_CLOG":
			filter_clog = true
		elif typ == "HEAT_WARN":
			heat_warn = true
		elif typ == "BROWNOUT":
			brownout = true
		elif typ == "JAM_SAFE":
			jam_safe = true
		elif typ == "INTRUSION":
			intrusion = true

	load_mode_into_dials(mode)

	if jam_safe and not saw_jam:
		saw_jam = true
		fire_thud()
	elif not jam_safe:
		saw_jam = false

	if intrusion and not saw_intrusion:
		saw_intrusion = true
		fire_alarm()
	elif not intrusion:
		saw_intrusion = false

	if ended == "kill" and not saw_kill:
		saw_kill = true
		kill_cut = true
		bed_gain = 0.0
		fire_kill()
	elif ended != "kill":
		saw_kill = false
		kill_cut = false

	_refresh_bed_state()


func _process(dt: float) -> void:
	if playback == null:
		if player != null and player.playing:
			playback = player.get_stream_playback() as AudioStreamGeneratorPlayback
		if playback == null:
			return

	if kill_cut:
		bed_gain = 0.0
	elif not bed_alive:
		bed_gain = move_toward(bed_gain, 0.0, dt * 4.0)
	else:
		bed_gain = move_toward(bed_gain, bed_target, dt * 2.5)

	var frames: int = playback.get_frames_available()
	if frames <= 0:
		return
	var inv_rate := 1.0 / MIX_RATE
	for _i in frames:
		playback.push_frame(Vector2.ONE * _sample(inv_rate))


func _noise() -> float:
	noise_state = (noise_state * 1103515245 + 12345) & 0x7fffffff
	return float(noise_state) / 1073741824.0 - 1.0


func _sample(dt: float) -> float:
	t += dt
	var out := 0.0

	var pulse_hz := float(live.pulse_hz)
	var noise_amp := float(live.noise_amp)
	var noise_lp := float(live.noise_lp)
	var noise_hpf := float(live.noise_hpf)
	var drone_hz := float(live.drone_hz)
	var drone_amp := float(live.drone_amp)
	var drone_wave := float(live.drone_wave)
	var drone_duty := float(live.drone_duty)
	var drone_lpf := float(live.drone_lpf)
	var drone_lpf_res := float(live.drone_lpf_res)
	var sub_amp := float(live.sub_amp)
	var pulse_amp := float(live.pulse_amp)
	var pulse_duty := float(live.pulse_duty)
	var grit := float(live.grit)
	var pitch := float(live.pitch)
	var lfo_hz := float(live.lfo_hz)
	var lfo_depth := float(live.lfo_depth)
	var vib_hz := float(live.vib_hz)
	var vib_depth := float(live.vib_depth)
	var master := float(live.master)

	if heat_warn or heat >= 80.0:
		var climb := clampf((heat - 70.0) / 30.0, 0.0, 1.0)
		if heat_warn:
			climb = maxf(climb, 0.55)
		pitch *= 1.0 + climb * 0.55
		pulse_hz *= 1.0 + climb * 0.35

	if filter_clog:
		grit += 0.12
		noise_amp += 0.05

	lfo_phase = fmod(lfo_phase + lfo_hz * dt, 1.0)
	var lfo := (1.0 - lfo_depth) + lfo_depth * sin(lfo_phase * TAU)

	if belt_slip:
		stutter_phase = fmod(stutter_phase + 9.0 * dt, 1.0)
		stutter_gate = 1.0 if stutter_phase < 0.55 else 0.08
	else:
		stutter_gate = move_toward(stutter_gate, 1.0, dt * 6.0)
		stutter_phase = 0.0

	pulse_duty = clampf(pulse_duty, 0.01, 0.95)
	pulse_phase = fmod(pulse_phase + pulse_hz * pitch * dt, 1.0)
	var pulse := 0.0
	if pulse_phase < pulse_duty:
		pulse = sin((pulse_phase / pulse_duty) * PI)
	pulse *= pulse_amp * stutter_gate

	# Vibrato modulates drone instantaneous pitch (sfxr vib).
	vib_phase = fmod(vib_phase + maxf(vib_hz, 0.0) * dt, 1.0)
	var vib := 1.0 + vib_depth * sin(vib_phase * TAU)

	var tone_hz := maxf(drone_hz * pitch * vib, 1.0)
	drone_phase = fmod(drone_phase + tone_hz * dt, 1.0)
	sub_phase = fmod(sub_phase + tone_hz * 0.5 * dt, 1.0)

	# Drone wave: 0=saw, 1=square with duty (sfxr square/saw).
	var drone_raw := 0.0
	if drone_wave >= 0.5:
		var duty := clampf(drone_duty, 0.02, 0.98)
		drone_raw = 0.5 if drone_phase < duty else -0.5
	else:
		drone_raw = 2.0 * drone_phase - 1.0
	var drone := drone_raw * drone_amp
	var sub := sin(sub_phase * TAU) * sub_amp

	# Resonant LPF on drone(+sub) only — sfxr fltw/fltdmp style, cutoff in Hz.
	var body := drone + sub
	var fltw := clampf(pow(clampf(drone_lpf / (MIX_RATE * 0.45), 0.0, 1.0), 3.0) * 0.1, 0.0001, 0.1)
	var fltdmp := 5.0 / (1.0 + pow(clampf(drone_lpf_res, 0.0, 1.0), 2.0) * 20.0) * (0.01 + fltw)
	if fltdmp > 0.8:
		fltdmp = 0.8
	drone_bp_z += (body - drone_lp_z) * fltw
	drone_bp_z -= drone_bp_z * fltdmp
	drone_lp_z += drone_bp_z
	var filtered_body := drone_lp_z

	var n := _noise()
	var noise_in := n * noise_amp
	if filter_clog:
		noise_in += absf(n) * n * 0.09
	if grit > 0.0:
		noise_in += n * grit * (0.5 + 0.5 * sin(t * 47.0 * pitch))

	# Noise HPF (sfxr flthp) then LPF — cutoff params in Hz.
	var hp_coeff := clampf(1.0 - exp(-TAU * maxf(noise_hpf, 1.0) / MIX_RATE), 0.0, 0.999)
	noise_hp_z += hp_coeff * (noise_in - noise_hp_z)
	var hp_out := noise_in - noise_hp_z
	# One-pole LP: noise_lp is cutoff in Hz; air around the drone, not the body.
	var lp_coeff := 1.0 - exp(-TAU * maxf(noise_lp, 1.0) / MIX_RATE)
	lp_z += lp_coeff * (hp_out - lp_z)
	var hiss := lp_z

	var bed := (hiss + pulse + filtered_body) * lfo * bed_gain * master
	out += bed

	# One-shots play on oneshot_player (sfxr WAV) — not mixed into the bed.

	if kill_cut:
		out *= 0.0

	return clampf(out, -1.0, 1.0)
