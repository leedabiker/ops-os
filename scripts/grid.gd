extends Node2D

const COLS := 80
const ROWS := 25
const CW := 8
const CH := 16

const CP := {
	"█": 0xDB, "▄": 0xDC, "■": 0xFE, "∙": 0xF9, "░": 0xB0,
	"╔": 0xC9, "╗": 0xBB, "╚": 0xC8, "╝": 0xBC, "═": 0xCD, "║": 0xBA,
	"┌": 0xDA, "┐": 0xBF, "└": 0xC0, "┘": 0xD9, "─": 0xC4, "│": 0xB3,
	"┬": 0xC2, "┴": 0xC1, "├": 0xC3, "┤": 0xB4, "┼": 0xC5,
	"╦": 0xCB, "╩": 0xCA, "╠": 0xCC, "╣": 0xB9, "╬": 0xCE,
}

var ch_buf: PackedByteArray = PackedByteArray()
var fg_buf: Array = []
var bg_buf: Array = []
var atlas: ImageTexture
var _n: int = COLS * ROWS


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	ch_buf.resize(_n)
	fg_buf.resize(_n)
	bg_buf.resize(_n)
	clear()
	atlas = _load_atlas()


func _load_atlas() -> ImageTexture:
	var img := Image.create(128, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var f := FileAccess.open("res://assets/vga8.f16", FileAccess.READ)
	if f == null:
		push_error("missing res://assets/vga8.f16")
		return ImageTexture.create_from_image(img)
	var data := f.get_buffer(4096)
	f.close()
	if data.size() < 4096:
		push_error("vga8.f16 short")
		return ImageTexture.create_from_image(img)
	for code in range(256):
		var col := code % 16
		var row := int(code / 16)
		for y in range(16):
			var bits: int = data[code * 16 + y]
			for x in range(8):
				if bits & (0x80 >> x):
					img.set_pixel(col * 8 + x, row * 16 + y, Color(1, 1, 1, 1))
	var tex := ImageTexture.create_from_image(img)
	return tex


func clear() -> void:
	for i in range(_n):
		ch_buf[i] = 32
		fg_buf[i] = Color(0, 0, 0, 1)
		bg_buf[i] = Color(0, 0, 0, 1)


func _cp(ch: String) -> int:
	if CP.has(ch):
		return int(CP[ch])
	var o := ch.unicode_at(0)
	if o < 128:
		return o
	return 0x3F


func put(x: int, y: int, ch, fg: Color = Color(0, 0, 0, 1), bg: Color = Color(0, 0, 0, 1)) -> void:
	if x < 0 or y < 0 or x >= COLS or y >= ROWS:
		return
	var i := y * COLS + x
	if typeof(ch) == TYPE_INT:
		ch_buf[i] = int(ch) & 255
	else:
		ch_buf[i] = _cp(str(ch))
	fg_buf[i] = fg
	bg_buf[i] = bg


func text(x: int, y: int, s: String, fg: Color = Color(0, 0, 0, 1), bg: Color = Color(0, 0, 0, 1)) -> void:
	for i in range(s.length()):
		put(x + i, y, s.substr(i, 1), fg, bg)


func fill(x: int, y: int, w: int, h: int, ch, fg: Color = Color(0, 0, 0, 1), bg: Color = Color(0, 0, 0, 1)) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			put(xx, yy, ch, fg, bg)


func _draw() -> void:
	if atlas == null:
		return
	for y in range(ROWS):
		for x in range(COLS):
			var i := y * COLS + x
			var bg: Color = bg_buf[i]
			var fg: Color = fg_buf[i]
			var code: int = ch_buf[i]
			var dx := x * CW
			var dy := y * CH
			draw_rect(Rect2(dx, dy, CW, CH), bg)
			if code == 32:
				continue
			var col := code % 16
			var row := int(code / 16)
			var src := Rect2(col * CW, row * CH, CW, CH)
			draw_texture_rect_region(atlas, Rect2(dx, dy, CW, CH), src, fg)
