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
	if player != null and not player.playing:
		player.play()
		playback = player.get_stream_playback() as AudioStreamGeneratorPlayback


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

	if kill_cut or ended == "kill" or jam_safe or mining_fault:
		bed_alive = false
		bed_target = 0.0
	else:
		bed_alive = true
		if power_fault or radar_blank or brownout:
			bed_target = 0.08
		else:
			bed_target = 1.0


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

	var pulse_hz := 2.2
	var noise_amp := 0.045
	var pulse_amp := 0.11
	var grit := 0.0
	var pitch := 1.0
	var lfo_hz := 0.07
	if mode == "SAFE":
		pulse_hz = 0.85
		noise_amp = 0.018
		pulse_amp = 0.035
		lfo_hz = 0.035
		pitch = 0.82
	elif mode == "MAX":
		pulse_hz = 3.6
		noise_amp = 0.08
		pulse_amp = 0.16
		grit = 0.07
		lfo_hz = 0.12
		pitch = 1.18

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
	var lfo := 0.75 + 0.25 * sin(lfo_phase * TAU)

	if belt_slip:
		stutter_phase = fmod(stutter_phase + 9.0 * dt, 1.0)
		stutter_gate = 1.0 if stutter_phase < 0.55 else 0.08
	else:
		stutter_gate = move_toward(stutter_gate, 1.0, dt * 6.0)
		stutter_phase = 0.0

	pulse_phase = fmod(pulse_phase + pulse_hz * pitch * dt, 1.0)
	var pulse := 0.0
	if pulse_phase < 0.18:
		pulse = sin((pulse_phase / 0.18) * PI)
	pulse *= pulse_amp * stutter_gate

	var n := _noise()
	var hiss := n * noise_amp
	if filter_clog:
		hiss += absf(n) * n * 0.09
	if grit > 0.0:
		hiss += n * grit * (0.5 + 0.5 * sin(t * 47.0 * pitch))

	var bed := (hiss + pulse) * lfo * bed_gain
	out += bed

	if thud_t >= 0.0:
		var u := thud_t
		var env := exp(-u * 14.0)
		var thud := sin(TAU * (48.0 - u * 70.0) * u) * env * 0.85
		thud += _noise() * env * 0.12
		out += thud

	if alarm_t >= 0.0:
		var a := alarm_t
		var beep := 0.0
		var cycle := fmod(a, 0.28)
		if cycle < 0.14:
			beep = sin(TAU * 880.0 * a) * 0.22
			beep += sin(TAU * 660.0 * a) * 0.12
		var aenv := 1.0
		if a > 1.4:
			aenv = clampf(1.0 - (a - 1.4) / 0.4, 0.0, 1.0)
		out += beep * aenv

	if kill_cut:
		out *= 0.0

	return clampf(out, -1.0, 1.0)
