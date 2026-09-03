extends Node2D

const FW := 76
const FH := 80

const VOID := 0.04
const GROUND := 0.11
const MASS := 0.42
const MASS_DK := 0.18
const SLAT := 0.74
const LAMP := 0.96
const ORE := 0.62

var img: Image
var tex: ImageTexture
var mat: ShaderMaterial
var frozen: bool = false
var acc: float = 1.0
var t: float = 0.0
var dropout: float = 0.0
var noise_amt: float = 0.06
var flicker: float = 1.0
var dest: Rect2 = Rect2()
var active: bool = false
var shake: Vector2 = Vector2.ZERO


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	z_as_relative = false
	img = Image.create(FW, FH, false, Image.FORMAT_RGBA8)
	img.fill(_c(VOID))
	tex = ImageTexture.create_from_image(img)
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/cam_feed.gdshader")
	material = mat


func reset() -> void:
	frozen = false
	dropout = 0.0
	acc = 1.0
	t = 0.0
	noise_amt = 0.06
	flicker = 1.0
	shake = Vector2.ZERO


func hide_feed() -> void:
	if active:
		active = false
		queue_redraw()


func sync(a: Dictionary, sim, anim_t: float, dt: float) -> void:
	active = true
	t = anim_t
	var px: int = (int(a.x) + 1) * 8
	var py: int = (int(a.y) + 1) * 16
	var pw: int = (int(a.w) - 2) * 8
	var ph: int = (int(a.h) - 2) * 16
	dest = Rect2(px, py, pw, ph)

	var mining_st: String = sim.sector_state("mining")
	var power_st: String = sim.sector_state("power")
	var blank: bool = bool(sim.radar_blank)
	var heat: float = float(sim.heat)
	var mode: String = str(sim.mode)
	var mining_type := ""
	var power_type := ""
	for e in sim.events:
		if e.sector == "mining" and mining_type == "":
			mining_type = str(e.type)
		if e.sector == "power" and power_type == "":
			power_type = str(e.type)

	var fry := blank or power_st == "FAULT"
	if fry:
		frozen = true
		dropout = minf(1.0, dropout + dt * 1.6)
	else:
		if frozen:
			acc = 1.0
		frozen = false
		dropout = maxf(0.0, dropout - dt * 2.2)

	var burst := fmod(anim_t * 0.41, 13.0)
	if burst > 12.62:
		dropout = maxf(dropout, 0.62)

	if mining_st == "FAULT":
		noise_amt = 0.16
	elif mining_st == "STRESSED":
		noise_amt = 0.10
	else:
		noise_amt = 0.06
	noise_amt = minf(noise_amt, 0.16)

	flicker = 1.0
	if mining_st == "FAULT" or heat >= 80.0:
		flicker = 0.52 if int(anim_t * 9.0) % 3 == 0 else 1.0
	if power_type == "GRID_FLICKER":
		flicker = 0.32 if int(anim_t * 6.0) % 2 == 0 else 0.9
	if power_type == "CELL_DIP":
		flicker = minf(flicker, 0.72)

	var glitch := 0.18
	if mining_st == "STRESSED":
		glitch = 0.42
	elif mining_st == "FAULT":
		glitch = 0.72
	if fry:
		glitch = maxf(glitch, 0.85)

	var amp := 0.35
	if mode == "HIGH":
		amp = 0.85
	elif mode == "MAX":
		amp = 1.55
	if mining_st == "FAULT":
		amp = 2.1
	shake.x = sin(anim_t * 17.3) * amp
	shake.y = cos(anim_t * 13.1) * amp * 0.55

	if not frozen:
		acc += dt
		if acc >= 0.07:
			acc = 0.0
			_render_scene(mode, mining_st, mining_type, heat)
			tex.update(img)

	if mat:
		mat.set_shader_parameter("noise_amt", noise_amt)
		mat.set_shader_parameter("dropout", dropout)
		mat.set_shader_parameter("flicker", flicker)
		mat.set_shader_parameter("glitch", glitch)
	queue_redraw()


func _c(lum: float) -> Color:
	return Color(lum, lum, lum, 1.0)


func _px(x: int, y: int, lum: float) -> void:
	if x < 0 or y < 0 or x >= FW or y >= FH:
		return
	img.set_pixel(x, y, _c(lum))


func _rect(r: Rect2i, lum: float) -> void:
	img.fill_rect(r, _c(lum))


func _render_scene(mode: String, mining_st: String, mining_type: String, heat: float) -> void:
	img.fill(_c(VOID))

	var clog := mining_type == "FILTER_CLOG"
	var slip := mining_type == "BELT_SLIP"
	var jammed := mining_type == "JAM_SAFE"
	var heat_warn := mining_type == "HEAT_WARN"
	var stalled := mining_st == "FAULT" or mining_type == "PUMP_STALL"

	var cabin_lum := MASS
	var window_lum := MASS_DK
	if heat_warn or heat >= 80.0:
		cabin_lum = 0.62
		window_lum = 0.50

	var lamp_lum := 0.70
	if mode == "HIGH":
		lamp_lum = 0.90
	elif mode == "MAX":
		lamp_lum = LAMP

	var bob := 0
	if mode == "HIGH":
		bob = 1 if sin(t * 2.2) >= 0.0 else 0
	elif mode == "MAX":
		bob = int(round(sin(t * 3.1) * 2.0))

	var speed := 1
	var ore_n := 1
	if mode == "HIGH":
		speed = 3
		ore_n = 3
	elif mode == "MAX":
		speed = 5
		ore_n = 5
	if clog:
		ore_n = 0
	if jammed or stalled:
		speed = 0
		ore_n = 0

	var tick := int(floor(t / 0.07))
	var slat_off := 0
	if speed > 0:
		if slip:
			slat_off = posmod(int(floor(float(tick) / 4.0)), 8)
		else:
			slat_off = posmod(tick * speed, 8)

	# ground slab
	_rect(Rect2i(0, 66, FW, 14), GROUND)

	# 1. cabin
	_rect(Rect2i(4, 28, 26, 38), cabin_lum)
	_rect(Rect2i(4, 16, 20, 16), cabin_lum)
	_rect(Rect2i(8, 20, 12, 8), window_lum)
	_rect(Rect2i(6, 64, 8, 4), MASS_DK)
	_rect(Rect2i(18, 64, 8, 4), MASS_DK)
	_rect(Rect2i(8, 38, 12, 10), MASS_DK)
	if clog:
		_rect(Rect2i(8, 38, 12, 10), MASS)
		_rect(Rect2i(12, 40, 2, 2), ORE)
	else:
		var gx := 10
		while gx < 20:
			_rect(Rect2i(gx, 39, 1, 8), cabin_lum)
			gx += 3

	# 2. boom + lamp (bob only)
	for x in range(22, 61):
		var u := float(x - 22) / 38.0
		var y0 := int(round(18.0 + (8.0 - 18.0) * u)) + bob
		var y1 := int(round(26.0 + (16.0 - 26.0) * u)) + bob
		if y1 < y0:
			var tmp := y0
			y0 = y1
			y1 = tmp
		_rect(Rect2i(x, y0, 1, y1 - y0 + 1), MASS)
	_rect(Rect2i(60, 6 + bob, 8, 8), lamp_lum)

	# 3. hopper
	_rect(Rect2i(30, 34, 24, 8), MASS)
	for y in range(42, 55):
		var hu := float(y - 42) / 13.0
		var half := int(round(12.0 * (1.0 - hu) + 4.0 * hu))
		_rect(Rect2i(42 - half, y, half * 2, 1), MASS)
	_rect(Rect2i(38, 54, 8, 4), MASS_DK)

	# 4. belt
	_rect(Rect2i(16, 58, 56, 8), MASS_DK)
	for x in range(16, 72):
		if posmod(x - 16 + slat_off, 8) < 5:
			_rect(Rect2i(x, 59, 1, 4), SLAT)
	_rect(Rect2i(16, 65, 56, 1), 0.08)

	# cone: VOID only, right of hopper, max half-width 5
	var lamp_cx := 64
	var lamp_by := 14 + bob
	for y in range(lamp_by, 58):
		var cu := float(y - lamp_by) / float(maxi(1, 58 - lamp_by))
		var chalf := mini(5, int(2.0 + cu * 5.0))
		for x in range(maxi(54, lamp_cx - chalf), lamp_cx + chalf + 1):
			if x < 0 or x >= FW:
				continue
			if img.get_pixel(x, y).r <= VOID + 0.002:
				_px(x, y, 0.12 + (1.0 - cu) * 0.10)

	# ore / faults
	if slip:
		_rect(Rect2i(38, 56, 10, 4), ORE)
	elif jammed:
		_rect(Rect2i(36, 56, 10, 6), SLAT)
	elif ore_n > 0:
		for i in range(ore_n):
			var prog := posmod(tick * 2 + i * 7, 20)
			var ox := 40
			var oy := 54
			if prog < 5:
				ox = 40 + (i % 3) * 2
				oy = 54 + prog
			else:
				ox = 40 + (prog - 5) * 2
				oy = 59
				# stick to a slat that is on
				var align := posmod(ox - 16 + slat_off, 8)
				if align >= 5:
					ox += 8 - align
			if ox > 68:
				continue
			_rect(Rect2i(ox, oy, 2, 2), ORE)

func _draw() -> void:
	if not active or tex == null:
		return
	var r := dest
	r.position += shake
	draw_texture_rect(tex, r, false)
