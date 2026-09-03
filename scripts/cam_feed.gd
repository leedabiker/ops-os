extends Node2D

const FW := 76
const FH := 80

var img: Image
var tex: ImageTexture
var mat: ShaderMaterial
var frozen: bool = false
var acc: float = 1.0
var t: float = 0.0
var dropout: float = 0.0
var noise_amt: float = 0.14
var flicker: float = 1.0
var dest: Rect2 = Rect2()
var active: bool = false
var shake: Vector2 = Vector2.ZERO
var lens: Array = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	z_as_relative = false
	img = Image.create(FW, FH, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.02, 0.03, 0.02, 1))
	tex = ImageTexture.create_from_image(img)
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/cam_feed.gdshader")
	material = mat
	lens = [
		Vector2i(8, 11), Vector2i(61, 7), Vector2i(18, 52),
		Vector2i(70, 44), Vector2i(33, 19), Vector2i(4, 71),
	]


func reset() -> void:
	frozen = false
	dropout = 0.0
	acc = 1.0
	t = 0.0
	noise_amt = 0.14
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

	noise_amt = 0.12 + clampf(heat / 100.0, 0.0, 1.0) * 0.30
	if mining_st == "FAULT":
		noise_amt = 0.58
		dropout = maxf(dropout, 0.25)
	elif mining_st == "STRESSED":
		noise_amt += 0.10
	if heat >= 80.0:
		noise_amt += 0.08

	flicker = 1.0
	if mining_st == "FAULT" or heat >= 80.0:
		flicker = 0.52 if int(anim_t * 9.0) % 3 == 0 else 1.0
	var pe: Dictionary = {}
	for e in sim.events:
		if e.sector == "power":
			pe = e
			break
	if not pe.is_empty() and pe.type == "GRID_FLICKER":
		flicker = 0.32 if int(anim_t * 6.0) % 2 == 0 else 0.9

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
			_render_scene(mode, mining_st)
			tex.update(img)

	if mat:
		mat.set_shader_parameter("noise_amt", noise_amt)
		mat.set_shader_parameter("dropout", dropout)
		mat.set_shader_parameter("flicker", flicker)
	queue_redraw()


func _px(x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= FW or y >= FH:
		return
	img.set_pixel(x, y, c)


func _blend(x: int, y: int, c: Color, a: float) -> void:
	if x < 0 or y < 0 or x >= FW or y >= FH:
		return
	var p := img.get_pixel(x, y)
	img.set_pixel(x, y, p.lerp(c, a))


func _hash(n: int) -> float:
	var x := (n * 1664525 + 1013904223) & 0x7fffffff
	return float(x) / 2147483647.0


func _line(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx := absi(x1 - x0)
	var sx := 1 if x0 < x1 else -1
	var dy := -absi(y1 - y0)
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	while true:
		_px(x, y, c)
		if x == x1 and y == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy


func _render_scene(mode: String, mining_st: String) -> void:
	var sky := Color(0.015, 0.02, 0.018, 1)
	img.fill(sky)
	var bob := int(round(sin(t * 1.35) * (1.2 if mode != "SAFE" else 0.4)))
	var rim := 13
	var floor_y := 58
	img.fill_rect(Rect2i(0, 0, FW, rim), Color(0.012, 0.016, 0.014, 1))

	for y in range(rim, floor_y):
		var u := float(y - rim) / float(maxi(1, floor_y - rim))
		var inset := int(lerpf(21.0, 2.0, u))
		var wall := Color(0.05, 0.055, 0.045, 1).lerp(Color(0.09, 0.10, 0.08, 1), u)
		var far := Color(0.035, 0.04, 0.032, 1).lerp(Color(0.07, 0.078, 0.055, 1), u)
		if inset > 0:
			img.fill_rect(Rect2i(0, y, inset, 1), wall)
			img.fill_rect(Rect2i(FW - inset, y, inset, 1), wall)
		var mid_w := FW - inset * 2
		if mid_w > 0:
			img.fill_rect(Rect2i(inset, y, mid_w, 1), far)

	for y in range(floor_y, FH):
		var u := float(y - floor_y) / float(maxi(1, FH - floor_y))
		var c := Color(0.075, 0.082, 0.06, 1).lerp(Color(0.12, 0.13, 0.09, 1), u)
		img.fill_rect(Rect2i(0, y, FW, 1), c)

	# strata on the far face
	for i in range(7):
		var sy := rim + 5 + i * 5
		for x in range(18, 58):
			_blend(x, sy, Color(0.02, 0.02, 0.018, 1), 0.28)

	# boom lamp + cone
	var lx := 54
	var ly := 21 + bob
	for y in range(ly, mini(FH, floor_y + 10)):
		var u := float(y - ly) / 42.0
		var half := int(2.0 + u * 15.0)
		var a := 0.16 * (1.0 - clampf(u, 0.0, 1.0) * 0.55)
		for x in range(lx - half, lx + half + 1):
			_blend(x, y, Color(0.42, 0.46, 0.24, 1), a)
	_px(lx, ly, Color(0.95, 0.96, 0.72, 1))
	_px(lx + 1, ly, Color(0.72, 0.74, 0.4, 1))
	_blend(lx, ly + 1, Color(0.8, 0.82, 0.4, 1), 0.85)

	# cabin / body (cam is bolted here — large in the near field)
	for y in range(48, 72):
		img.fill_rect(Rect2i(6, y, 24, 1), Color(0.15, 0.16, 0.13, 1))
	img.fill_rect(Rect2i(8, 44, 18, 8), Color(0.11, 0.12, 0.1, 1))
	for y in range(26, 50):
		_px(17, y, Color(0.2, 0.21, 0.16, 1))
		_px(18, y, Color(0.18, 0.19, 0.14, 1))
	for y in range(62, FH):
		var w := 22 + (y - 62)
		img.fill_rect(Rect2i(0, y, mini(FW, w), 1), Color(0.13, 0.14, 0.11, 1))

	# boom
	_line(19, 30, lx - 1, ly + 1, Color(0.22, 0.23, 0.16, 1))
	_line(19, 31, lx - 1, ly + 2, Color(0.17, 0.18, 0.13, 1))
	img.fill_rect(Rect2i(lx - 2, ly + 1, 5, 5), Color(0.2, 0.21, 0.15, 1))

	# tracks
	for x in range(4, 38):
		_px(x, 70, Color(0.07, 0.07, 0.06, 1))
		_px(x, 72, Color(0.07, 0.07, 0.06, 1))

	# dust in the lamp
	var tick := int(t * 11.0)
	var n := 16 if mode == "SAFE" else 22
	if mining_st == "FAULT":
		n = 28
	for i in range(n):
		var h1 := _hash(i * 31 + tick / 2)
		var h2 := _hash(i * 17 + 9)
		var dx := 34 + int(h1 * 30.0)
		var dy := 18 + int(fmod(t * (3.5 + h2 * 7.0) + float(i) * 4.1, 42.0))
		_px(dx, dy, Color(0.5, 0.54, 0.34, 1))
		if _hash(i + tick) > 0.7:
			_px(dx + 1, dy, Color(0.32, 0.34, 0.22, 1))

	# fog band
	var fy := 16 + int(fmod(t * 5.5, 36.0))
	for y in range(fy, fy + 4):
		for x in range(FW):
			_blend(x, y, Color(0.22, 0.24, 0.17, 1), 0.07)

	# dirty lens
	for s in lens:
		var p: Vector2i = s
		_blend(p.x, p.y, Color(0, 0, 0, 1), 0.5)
		_blend(p.x + 1, p.y, Color(0, 0, 0, 1), 0.28)
		_blend(p.x, p.y + 1, Color(0, 0, 0, 1), 0.22)

	# rolling snow bar
	var bar := int(fmod(t * 26.0, float(FH + 12))) - 3
	if bar >= 0 and bar < FH:
		for x in range(FW):
			var ns := _hash(x * 13 + int(t * 70.0))
			_px(x, bar, Color(ns, ns, ns * 0.85, 1))
			if bar + 1 < FH:
				_blend(x, bar + 1, Color(ns, ns, ns, 1), 0.35)


func _draw() -> void:
	if not active or tex == null:
		return
	var r := dest
	r.position += shake
	draw_texture_rect(tex, r, false)
