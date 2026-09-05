extends Node

const MIX_RATE := 22050.0
const BUF_LEN := 0.1

var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback

var t: float = 0.0
var pulse_phase: float = 0.0
var lfo_phase: float = 0.0
var noise_state: int = 1

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

var thud_t: float = -1.0
var alarm_t: float = -1.0
var kill_cut: bool = false

var stutter_gate: float = 1.0
var stutter_phase: float = 0.0

var modes := {
	"SAFE": {
		"noise_amp": 0.018,
		"pulse_amp": 0.035,
		"pulse_hz": 0.85,
		"pulse_duty": 0.18,
		"pitch": 0.82,
		"lfo_hz": 0.035,
		"lfo_depth": 0.25,
		"grit": 0.0,
		"master": 1.0,
	},
	"HIGH": {
		"noise_amp": 0.045,
		"pulse_amp": 0.11,
		"pulse_hz": 2.2,
		"pulse_duty": 0.18,
		"pitch": 1.0,
		"lfo_hz": 0.07,
		"lfo_depth": 0.25,
		"grit": 0.0,
		"master": 1.0,
	},
	"MAX": {
		"noise_amp": 0.08,
		"pulse_amp": 0.16,
		"pulse_hz": 3.6,
		"pulse_duty": 0.18,
		"pitch": 1.18,
		"lfo_hz": 0.12,
		"lfo_depth": 0.25,
		"grit": 0.07,
		"master": 1.0,
	},
}

var thud := {"freq": 48.0, "decay": 14.0, "noise": 0.12, "amp": 0.85}
var alarm := {"hz": 880.0, "hz2": 660.0, "rate": 0.28, "on": 0.14, "amp": 0.22}

## Live voice params — what `_sample` reads every frame.
var live := {
	"noise_amp": 0.045,
	"pulse_amp": 0.11,
	"pulse_hz": 2.2,
	"pulse_duty": 0.18,
	"pitch": 1.0,
	"lfo_hz": 0.07,
	"lfo_depth": 0.25,
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


func reset() -> void:
	t = 0.0
	pulse_phase = 0.0
	lfo_phase = 0.0
	noise_state = 1
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
	thud_t = -1.0
	alarm_t = -1.0
	kill_cut = false
	stutter_gate = 1.0
	stutter_phase = 0.0
	load_mode_into_dials("SAFE")
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
	thud_t = 0.0


func fire_alarm() -> void:
	alarm_t = 0.0


func print_bake() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("var modes := {")
	for m in ["SAFE", "HIGH", "MAX"]:
		var row: Dictionary = modes[m]
		lines.append("\t\"%s\": {" % m)
		var keys := ["noise_amp", "pulse_amp", "pulse_hz", "pulse_duty", "pitch", "lfo_hz", "lfo_depth", "grit", "master"]
		for i in keys.size():
			var k: String = keys[i]
			var comma := "," if i < keys.size() - 1 else ""
			lines.append("\t\t\"%s\": %s%s" % [k, _fmt_num(float(row.get(k, 0.0))), comma])
		var trail := "," if m != "MAX" else ""
		lines.append("\t}%s" % trail)
	lines.append("}")
	lines.append("")
	lines.append(
		"var thud := {\"freq\": %s, \"decay\": %s, \"noise\": %s, \"amp\": %s}"
		% [_fmt_num(float(thud.freq)), _fmt_num(float(thud.decay)), _fmt_num(float(thud.noise)), _fmt_num(float(thud.amp))]
	)
	lines.append(
		"var alarm := {\"hz\": %s, \"hz2\": %s, \"rate\": %s, \"on\": %s, \"amp\": %s}"
		% [
			_fmt_num(float(alarm.hz)),
			_fmt_num(float(alarm.hz2)),
			_fmt_num(float(alarm.rate)),
			_fmt_num(float(alarm.on)),
			_fmt_num(float(alarm.amp)),
		]
	)
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
		thud_t = 0.0
	elif not jam_safe:
		saw_jam = false

	if intrusion and not saw_intrusion:
		saw_intrusion = true
		alarm_t = 0.0
	elif not intrusion:
		saw_intrusion = false

	if ended == "kill" and not saw_kill:
		saw_kill = true
		kill_cut = true
		bed_gain = 0.0
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

	if thud_t >= 0.0:
		thud_t += dt
		if thud_t > 0.35:
			thud_t = -1.0
	if alarm_t >= 0.0:
		alarm_t += dt
		if alarm_t > 1.8:
			alarm_t = -1.0

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
	var pulse_amp := float(live.pulse_amp)
	var pulse_duty := float(live.pulse_duty)
	var grit := float(live.grit)
	var pitch := float(live.pitch)
	var lfo_hz := float(live.lfo_hz)
	var lfo_depth := float(live.lfo_depth)
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

	var n := _noise()
	var hiss := n * noise_amp
	if filter_clog:
		hiss += absf(n) * n * 0.09
	if grit > 0.0:
		hiss += n * grit * (0.5 + 0.5 * sin(t * 47.0 * pitch))

	var bed := (hiss + pulse) * lfo * bed_gain * master
	out += bed

	if thud_t >= 0.0:
		var u := thud_t
		var env := exp(-u * float(thud.decay))
		var th := sin(TAU * (float(thud.freq) - u * 70.0) * u) * env * float(thud.amp)
		th += _noise() * env * float(thud.noise)
		out += th

	if alarm_t >= 0.0:
		var a := alarm_t
		var beep := 0.0
		var cycle := fmod(a, float(alarm.rate))
		if cycle < float(alarm.on):
			beep = sin(TAU * float(alarm.hz) * a) * float(alarm.amp)
			beep += sin(TAU * float(alarm.hz2) * a) * float(alarm.amp) * (0.12 / 0.22)
		var aenv := 1.0
		if a > 1.4:
			aenv = clampf(1.0 - (a - 1.4) / 0.4, 0.0, 1.0)
		out += beep * aenv

	if kill_cut:
		out *= 0.0

	return clampf(out, -1.0, 1.0)
