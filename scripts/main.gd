extends Node

const SimScript = preload("res://scripts/sim.gd")
const GridScript = preload("res://scripts/grid.gd")
const VfsScript = preload("res://scripts/vfs.gd")
const CamFeedScript = preload("res://scripts/cam_feed.gd")

const LOGICAL_W := 640
const LOGICAL_H := 400

const C0 := Color("#000000")
const C8 := Color("#3D2E18")
const C6 := Color("#9A6B2F")
const C7 := Color("#C4A36A")
const C14 := Color("#E6C15A")
const C12 := Color("#C44532")
const C15 := Color("#F3D9A0")

const DUST := [
	Vector2i(14, 4), Vector2i(28, 6), Vector2i(51, 3), Vector2i(67, 8), Vector2i(9, 12),
	Vector2i(22, 17), Vector2i(44, 15), Vector2i(61, 18), Vector2i(33, 10), Vector2i(70, 13),
]

const APP_IDS := ["cam", "mining", "power", "radar", "repair", "terminal"]
const TILE_X := 0
const TILE_Y := 1
const TILE_W := 80
const TILE_H := 24

var sim
var vfs
var grid

var apps: Dictionary = {}
var wm: Dictionary = {}

var anim_t: float = 0.0
var fault_on: bool = true
var caret_on: bool = true
var flick: bool = true

var term_open: bool = false
var term_buf: String = ""
var term_lines: Array = []
var term_last: String = ""
var cat_wait: float = 0.0
var cat_pending: Array = []

var drag_id: String = ""
var drag_off: Vector2i = Vector2i.ZERO
var cam_feed = null
var end_retry_y: int = 12

var test_mode: bool = false


func _ready() -> void:
	sim = SimScript.new()
	vfs = VfsScript.new()
	sim.reset()
	vfs.reset(sim.interlock)

	test_mode = _has_arg("--test")
	if test_mode:
		var out: Dictionary = sim.self_test()
		print("OPS/OS TEST ", "PASS" if out.ok else "FAIL")
		print(JSON.stringify(out))
		get_tree().quit(0 if out.ok else 1)
		return

	var win := get_window()
	win.unresizable = false
	win.content_scale_size = Vector2i(LOGICAL_W, LOGICAL_H)
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	win.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	win.content_scale_factor = 1.0
	DisplayServer.window_set_size(Vector2i(1280, 800))

	grid = GridScript.new()
	add_child(grid)
	cam_feed = CamFeedScript.new()
	add_child(cam_feed)

	_boot_wm()

	var t := Timer.new()
	t.wait_time = 0.1
	t.autostart = true
	t.timeout.connect(_on_sim_tick)
	add_child(t)


func _has_arg(name: String) -> bool:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	return name in args


func _boot_wm() -> void:
	apps = {
		"power": {"id": "power", "title": "power", "ws": 1, "x": 1, "y": 1, "w": 78, "h": 7},
		"mining": {"id": "mining", "title": "mining", "ws": 2, "x": 1, "y": 1, "w": 42, "h": 11},
		"repair": {"id": "repair", "title": "repair", "ws": 2, "x": 44, "y": 1, "w": 34, "h": 6},
		"radar": {"id": "radar", "title": "radar", "ws": 3, "x": 1, "y": 1, "w": 37, "h": 22},
		"cam": {"id": "cam", "title": "cam", "ws": 3, "x": 39, "y": 1, "w": 40, "h": 22},
		"terminal": {"id": "terminal", "title": "terminal", "ws": 2, "x": 2, "y": 12, "w": 44, "h": 10},
	}
	wm = {
		"ws": 2,
		"focus": {1: "power", 2: "mining", 3: "radar"},
		"open": {"power": true, "mining": true, "repair": true, "radar": true, "cam": true, "terminal": false},
		"order": {1: ["power"], 2: ["mining", "repair"], 3: ["radar", "cam"]},
	}
	_tile_ws(1)
	_tile_ws(2)
	_tile_ws(3)
	term_open = false
	term_buf = ""
	term_lines = []
	term_last = ""
	cat_wait = 0.0
	cat_pending = []
	drag_id = ""


func _restart() -> void:
	sim.reset()
	vfs.reset(sim.interlock)
	anim_t = 0.0
	_boot_wm()
	if cam_feed != null:
		cam_feed.reset()




func _on_sim_tick() -> void:
	if test_mode:
		return
	if cat_wait > 0.0:
		cat_wait = maxf(0.0, cat_wait - 0.1)
		if cat_wait == 0.0:
			for ln in cat_pending:
				_term_print(ln)
			cat_pending = []
	sim.tick(0.1)


func _process(dt: float) -> void:
	if test_mode or grid == null:
		return
	anim_t += dt
	fault_on = int(anim_t * 2.0) % 2 == 0
	caret_on = int(anim_t * 1.0) % 2 == 0
	flick = int(anim_t * 5.0) % 2 == 0
	_paint(dt)
	grid.queue_redraw()


func _is_super(e: InputEventKey) -> bool:
	return e.meta_pressed or e.keycode == KEY_META


func _typing() -> bool:
	return focused_app() == "terminal" and wm.open.get("terminal", false)


func _unhandled_input(event: InputEvent) -> void:
	if test_mode:
		return
	if event is InputEventKey:
		var e := event as InputEventKey
		if e.pressed and not e.echo:
			_on_key(e)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_click(mb)
			else:
				drag_id = ""
	elif event is InputEventMouseMotion:
		if drag_id != "":
			_on_drag(event as InputEventMouseMotion)


func _on_key(e: InputEventKey) -> void:
	var k := e.keycode
	if sim.ended != "":
		if k == KEY_R or k == KEY_ENTER or k == KEY_KP_ENTER:
			_restart()
		get_viewport().set_input_as_handled()
		return
	var sup := _is_super(e)
	var typing := _typing()

	if sup and e.shift_pressed and e.alt_pressed and (k == KEY_1 or k == KEY_KP_1):
		_move_focused(1, false)
		get_viewport().set_input_as_handled()
		return
	if sup and e.shift_pressed and e.alt_pressed and (k == KEY_2 or k == KEY_KP_2):
		_move_focused(2, false)
		get_viewport().set_input_as_handled()
		return
	if sup and e.shift_pressed and e.alt_pressed and (k == KEY_3 or k == KEY_KP_3):
		_move_focused(3, false)
		get_viewport().set_input_as_handled()
		return
	if sup and e.shift_pressed and (k == KEY_1 or k == KEY_KP_1):
		_move_focused(1, true)
		get_viewport().set_input_as_handled()
		return
	if sup and e.shift_pressed and (k == KEY_2 or k == KEY_KP_2):
		_move_focused(2, true)
		get_viewport().set_input_as_handled()
		return
	if sup and e.shift_pressed and (k == KEY_3 or k == KEY_KP_3):
		_move_focused(3, true)
		get_viewport().set_input_as_handled()
		return
	if sup and (k == KEY_1 or k == KEY_KP_1):
		set_ws(1)
		get_viewport().set_input_as_handled()
		return
	if sup and (k == KEY_2 or k == KEY_KP_2):
		set_ws(2)
		get_viewport().set_input_as_handled()
		return
	if sup and (k == KEY_3 or k == KEY_KP_3):
		set_ws(3)
		get_viewport().set_input_as_handled()
		return
	if sup and (k == KEY_ENTER or k == KEY_KP_ENTER):
		_launch_terminal()
		get_viewport().set_input_as_handled()
		return
	if sup and k == KEY_P:
		launch("power")
		get_viewport().set_input_as_handled()
		return
	if sup and k == KEY_M:
		launch("mining")
		get_viewport().set_input_as_handled()
		return
	if sup and k == KEY_R:
		launch("repair")
		get_viewport().set_input_as_handled()
		return
	if sup and k == KEY_S:
		launch("radar")
		get_viewport().set_input_as_handled()
		return
	if sup and k == KEY_C:
		launch("cam")
		get_viewport().set_input_as_handled()
		return
	if sup and k == KEY_Q:
		close_focused()
		get_viewport().set_input_as_handled()
		return
	if sup and k == KEY_TAB:
		if e.shift_pressed:
			set_ws(wm.ws - 1 if int(wm.ws) > 1 else 3)
		else:
			set_ws(wm.ws + 1 if int(wm.ws) < 3 else 1)
		get_viewport().set_input_as_handled()
		return
	if k == KEY_TAB:
		focus_next(e.shift_pressed)
		get_viewport().set_input_as_handled()
		return
	if sup and k == KEY_W:
		close_focused()
		get_viewport().set_input_as_handled()
		return
	if sup and (k == KEY_LEFT or k == KEY_RIGHT or k == KEY_UP or k == KEY_DOWN):
		if e.shift_pressed and e.alt_pressed:
			pass
		elif e.shift_pressed:
			_swap_focused(k)
		else:
			_focus_dir(k)
		get_viewport().set_input_as_handled()
		return

	if not typing:
		if k == KEY_S:
			sim.set_mode("SAFE")
			get_viewport().set_input_as_handled()
			return
		if k == KEY_H:
			sim.set_mode("HIGH")
			get_viewport().set_input_as_handled()
			return
		if k == KEY_M:
			sim.set_mode("MAX")
			get_viewport().set_input_as_handled()
			return
		if k == KEY_BRACKETLEFT:
			if sim.mode == "MAX":
				sim.set_mode("HIGH")
			else:
				sim.set_mode("SAFE")
			get_viewport().set_input_as_handled()
			return
		if k == KEY_BRACKETRIGHT:
			if sim.mode == "SAFE":
				sim.set_mode("HIGH")
			else:
				sim.set_mode("MAX")
			get_viewport().set_input_as_handled()
			return

	if (k == KEY_ENTER or k == KEY_KP_ENTER) and focused_app() == "repair":
		if not sim.repair_targets().is_empty():
			sim.do_repair()
		get_viewport().set_input_as_handled()
		return

	if (k == KEY_ENTER or k == KEY_KP_ENTER) and focused_app() == "radar":
		sim.ack_first()
		get_viewport().set_input_as_handled()
		return

	if typing:
		_term_key(e)
		get_viewport().set_input_as_handled()


func _term_key(e: InputEventKey) -> void:
	var k := e.keycode
	if k == KEY_ENTER or k == KEY_KP_ENTER:
		_term_commit()
		return
	if k == KEY_BACKSPACE:
		if term_buf.length() > 0:
			term_buf = term_buf.substr(0, term_buf.length() - 1)
		return
	if k == KEY_UP and term_last != "":
		term_buf = term_last
		return
	var u := e.unicode
	if u >= 32 and u < 127:
		term_buf += String.chr(u)


func _term_print(s: String) -> void:
	term_lines.append(s)
	while term_lines.size() > 32:
		term_lines.pop_front()


func _term_commit() -> void:
	var line := term_buf
	_term_print("$ " + line)
	term_buf = ""
	if line.strip_edges() == "":
		return
	term_last = line
	var parts := line.strip_edges().split(" ", false)
	var cmd: String = parts[0] if parts.size() > 0 else ""
	if cmd == "apps":
		_apps_cmd(parts)
		return
	if cmd == "cat":
		var out: Array = vfs.exec(line)
		cat_pending = out
		cat_wait = 0.4
		return
	var out2: Array = vfs.exec(line)
	for ln in out2:
		_term_print(str(ln))



func _apps_cmd(parts: Array) -> void:
	var sub := ""
	if parts.size() >= 2:
		sub = str(parts[1])
	if sub == "" or sub == "list":
		for id in APP_IDS:
			_term_print(id)
		return
	if apps.has(sub):
		launch(sub)
		return
	_term_print("?")


func set_ws(n: int) -> void:
	if n < 1 or n > 3:
		return
	wm.ws = n


func focused_app() -> String:
	var f = wm.focus.get(wm.ws, "")
	return str(f) if f != null else ""


func apps_on_ws(ws: int) -> Array:
	var order: Array = wm.order[ws] if wm.order.has(ws) else []
	var out: Array = []
	for id in order:
		if not wm.open.get(id, false):
			continue
		if int(apps[id].ws) == ws:
			out.append(str(id))
	return out


func _order_add(ws: int, id: String) -> void:
	if not wm.order.has(ws):
		wm.order[ws] = []
	var order: Array = wm.order[ws]
	if order.find(id) < 0:
		order.append(id)
	wm.order[ws] = order


func _order_remove(ws: int, id: String) -> void:
	if not wm.order.has(ws):
		return
	var order: Array = wm.order[ws]
	var i := order.find(id)
	if i >= 0:
		order.remove_at(i)
	wm.order[ws] = order


func _tile_ws(ws: int) -> void:
	if ws < 1 or ws > 3:
		return
	_tile_split(apps_on_ws(ws), TILE_X, TILE_Y, TILE_W, TILE_H, true)


func _tile_split(list: Array, x: int, y: int, w: int, h: int, vertical: bool) -> void:
	if list.is_empty() or w < 1 or h < 1:
		return
	if list.size() == 1:
		var id := str(list[0])
		if not apps.has(id):
			return
		apps[id].x = x
		apps[id].y = y
		apps[id].w = w
		apps[id].h = h
		return
	var n: int = list.size()
	var n_a: int = int(n / 2)
	if n_a < 1:
		n_a = 1
	var left: Array = list.slice(0, n_a)
	var right: Array = list.slice(n_a)
	if vertical:
		var lw: int = int(w / 2)
		if lw < 1:
			lw = 1
		if lw >= w:
			lw = w - 1
		_tile_split(left, x, y, lw, h, false)
		_tile_split(right, x + lw, y, w - lw, h, false)
	else:
		var th: int = int(h / 2)
		if th < 1:
			th = 1
		if th >= h:
			th = h - 1
		_tile_split(left, x, y, w, th, true)
		_tile_split(right, x, y + th, w, h - th, true)


func launch(id: String) -> void:
	if not apps.has(id):
		return
	var here: int = int(wm.ws)
	var old_ws: int = int(apps[id].ws)
	var was_open: bool = bool(wm.open.get(id, false))
	if was_open and old_ws != here:
		_order_remove(old_ws, id)
		apps[id].ws = here
		wm.open[id] = true
		_order_add(here, id)
		_tile_ws(old_ws)
		_tile_ws(here)
	elif not was_open:
		apps[id].ws = here
		wm.open[id] = true
		_order_add(here, id)
		_tile_ws(here)
	wm.open[id] = true
	if id == "terminal":
		term_open = true
	wm.focus[here] = id


func _launch_terminal() -> void:
	launch("terminal")


func close_focused() -> void:
	var id := focused_app()
	if id == "" or not wm.open.get(id, false):
		return
	wm.open[id] = false
	if id == "terminal":
		term_open = false
	_order_remove(int(wm.ws), id)
	_tile_ws(int(wm.ws))
	var rest := apps_on_ws(wm.ws)
	wm.focus[wm.ws] = rest[0] if rest.size() > 0 else ""


func focus_next(back: bool = false) -> void:
	var list := apps_on_ws(wm.ws)
	if list.size() < 2:
		if list.size() == 1:
			wm.focus[wm.ws] = list[0]
		return
	var cur := focused_app()
	var i := list.find(cur)
	if i < 0:
		i = 0
	if back:
		i = (i - 1 + list.size()) % list.size()
	else:
		i = (i + 1) % list.size()
	wm.focus[wm.ws] = list[i]


func _move_focused(n: int, follow: bool = true) -> void:
	var id := focused_app()
	if id == "":
		return
	var old_ws := int(apps[id].ws)
	if old_ws != n:
		_order_remove(old_ws, id)
		apps[id].ws = n
		wm.open[id] = true
		_order_add(n, id)
		_tile_ws(old_ws)
		_tile_ws(n)
	if follow:
		wm.ws = n
		wm.focus[n] = id
	else:
		var rest := apps_on_ws(old_ws)
		wm.focus[old_ws] = rest[0] if rest.size() > 0 else ""
		wm.focus[n] = id


func _focus_dir(k: int) -> void:
	var list := apps_on_ws(wm.ws)
	if list.is_empty():
		return
	var cur := focused_app()
	if cur == "" or not apps.has(cur):
		wm.focus[wm.ws] = list[0]
		return
	var cx: int = int(apps[cur].x) + int(int(apps[cur].w) / 2)
	var cy: int = int(apps[cur].y) + int(int(apps[cur].h) / 2)
	var best := ""
	var best_d: int = 100000
	for id in list:
		if id == cur:
			continue
		var ax: int = int(apps[id].x) + int(int(apps[id].w) / 2)
		var ay: int = int(apps[id].y) + int(int(apps[id].h) / 2)
		var dx: int = ax - cx
		var dy: int = ay - cy
		var ok := false
		if k == KEY_LEFT and dx < 0 and absi(dx) >= absi(dy):
			ok = true
		elif k == KEY_RIGHT and dx > 0 and absi(dx) >= absi(dy):
			ok = true
		elif k == KEY_UP and dy < 0 and absi(dy) >= absi(dx):
			ok = true
		elif k == KEY_DOWN and dy > 0 and absi(dy) >= absi(dx):
			ok = true
		if not ok:
			continue
		var d: int = absi(dx) + absi(dy)
		if d < best_d:
			best_d = d
			best = str(id)
	if best != "":
		wm.focus[wm.ws] = best


func _swap_focused(k: int) -> void:
	var cur := focused_app()
	if cur == "":
		return
	_focus_dir(k)
	var other := focused_app()
	if other == "" or other == cur:
		wm.focus[wm.ws] = cur
		return
	var order: Array = wm.order[wm.ws] if wm.order.has(wm.ws) else []
	var i := order.find(cur)
	var j := order.find(other)
	if i >= 0 and j >= 0:
		order[i] = other
		order[j] = cur
		wm.order[wm.ws] = order
		_tile_ws(int(wm.ws))
	wm.focus[wm.ws] = cur


func _cell_at(mouse: Vector2) -> Vector2i:
	var p := get_viewport().get_canvas_transform().affine_inverse() * mouse
	return Vector2i(int(p.x / 8.0), int(p.y / 16.0))


func hit_app(cx: int, cy: int) -> String:
	var foc := focused_app()
	if foc != "" and wm.open.get(foc, false):
		var a: Dictionary = apps[foc]
		if cx >= int(a.x) and cy >= int(a.y) and cx < int(a.x) + int(a.w) and cy < int(a.y) + int(a.h):
			return foc
	var list := apps_on_ws(wm.ws)
	for i in range(list.size() - 1, -1, -1):
		var id: String = list[i]
		var b: Dictionary = apps[id]
		if cx >= int(b.x) and cy >= int(b.y) and cx < int(b.x) + int(b.w) and cy < int(b.y) + int(b.h):
			return id
	return ""


func _on_click(mb: InputEventMouseButton) -> void:
	var c := _cell_at(mb.position)
	if sim.ended != "":
		if c.y == end_retry_y and c.x >= 10 and c.x <= 18:
			_restart()
		return
	if c.y == 0:
		if c.x >= 1 and c.x <= 4:
			set_ws(1)
		elif c.x >= 6 and c.x <= 9:
			set_ws(2)
		elif c.x >= 11 and c.x <= 14:
			set_ws(3)
		return
	var id := hit_app(c.x, c.y)
	if id == "":
		return
	wm.focus[wm.ws] = id
	var a: Dictionary = apps[id]
	if c.y == int(a.y):
		drag_id = id
		drag_off = Vector2i(c.x - int(a.x), c.y - int(a.y))
	if id == "repair":
		var inner_y := c.y - int(a.y)
		if not sim.repair_targets().is_empty():
			sim.do_repair()
		elif inner_y == 1:
			sim.buy_upgrade("classify")
		elif inner_y == 2:
			sim.buy_upgrade("early")
	if id == "radar" and c.y > int(a.y):
		var rx := c.x - int(a.x) - 1
		var ry := c.y - int(a.y) - 1
		sim.ack_at(rx, ry)


func _on_drag(_mm: InputEventMouseMotion) -> void:
	# Tiled. Title drag does not float a window.
	return


func mode_color(m: String) -> Color:
	if m == "MAX":
		return C12
	if m == "HIGH":
		return C7
	return C6


func state_color(st: String) -> Color:
	if st == "FAULT":
		return C12
	if st == "STRESSED":
		return C14
	return C6


func heat_color(h: float) -> Color:
	if h >= 80.0:
		return C12
	if h >= 50.0:
		return C14
	return C7


func fmt3(n: float) -> String:
	var s := str(int(n))
	while s.length() < 3:
		s = " " + s
	return s


func clock_str(sec: float) -> String:
	var t := int(ceil(sec - 0.0001))
	if t < 0:
		t = 0
	var m := int(t / 60)
	var s := t % 60
	return "%02d:%02d" % [m, s]


func draw_window(a: Dictionary, focused: bool) -> void:
	var x: int = int(a.x)
	var y: int = int(a.y)
	var w: int = int(a.w)
	var h: int = int(a.h)
	var tl: String
	var tr: String
	var bl: String
	var br: String
	var hb: String
	var vb: String
	var frame: Color
	var tcol: Color
	if focused:
		tl = "╔"
		tr = "╗"
		bl = "╚"
		br = "╝"
		hb = "═"
		vb = "║"
		frame = C15
		tcol = C14
	else:
		tl = "┌"
		tr = "┐"
		bl = "└"
		br = "┘"
		hb = "─"
		vb = "│"
		frame = C8
		tcol = C6
	grid.fill(x, y, w, h, " ", C0, C0)
	grid.put(x, y, tl, frame)
	grid.put(x + w - 1, y, tr, frame)
	grid.put(x, y + h - 1, bl, frame)
	grid.put(x + w - 1, y + h - 1, br, frame)
	for yy in range(y + 1, y + h - 1):
		grid.put(x, yy, vb, frame)
		grid.put(x + w - 1, yy, vb, frame)
	for xx in range(x + 1, x + w - 1):
		grid.put(xx, y, hb, frame)
		grid.put(xx, y + h - 1, hb, frame)
	var run := " " + str(a.title) + " "
	if 2 + run.length() <= w - 2:
		grid.text(x + 2, y, run, tcol)


func bar16(x: int, y: int, filln: int, fill_fg: Color) -> void:
	grid.put(x, y, "[", C8)
	for i in range(16):
		if i < filln:
			grid.put(x + 1 + i, y, "▄", fill_fg)
		else:
			grid.put(x + 1 + i, y, " ", C8, C0)
	grid.put(x + 17, y, "]", C8)


func draw_chrome() -> void:
	grid.fill(0, 0, 80, 1, " ", C0, C0)
	_tab(1, " 1 ", 1)
	_tab(6, " 2 ", 2)
	_tab(11, " 3 ", 3)
	var mode: String = sim.mode
	var mode_pad: String = (mode + "    ").substr(0, 4)
	grid.text(36, 0, mode_pad, mode_color(mode))
	var dem: float = sim.demand()
	var sup: float = sim.supply()
	var en_col: Color = C12 if dem >= sup * 0.9 else C7
	var clk: String = clock_str(float(sim.remaining))
	grid.text(80 - clk.length(), 0, clk, C14)
	var res := "EN %d  MAT %d  CR %d" % [int(sup), int(sim.materials), int(sim.credits)]
	var rx := 80 - clk.length() - 2 - res.length()
	if rx < 42:
		rx = 42
	grid.text(rx, 0, res, C7)
	grid.text(rx, 0, "EN", en_col)
	grid.text(rx + 3, 0, str(int(sup)), en_col)


func _tab(x: int, label: String, n: int) -> void:
	if int(wm.ws) == n:
		grid.text(x, 0, label, C15, C14)
	else:
		grid.text(x, 0, label, C6, C0)


func mining_event() -> Dictionary:
	return sim._find_sector("mining")


func power_event() -> Dictionary:
	return sim._find_sector("power")


func trough_val() -> Dictionary:
	var filter := 14.0
	var belt := 12.0
	var pump := 25.0
	if sim.mode == "HIGH":
		filter = 28.0
		belt = 22.0
	elif sim.mode == "MAX":
		filter = 42.0
		belt = 36.0
	var e := mining_event()
	if not e.is_empty():
		if e.type == "FILTER_CLOG":
			filter = 100.0 if e.phase == "hold" else 94.0
		if e.type == "BELT_SLIP":
			belt = 100.0 if e.phase == "hold" else 88.0
		if e.type == "JAM_SAFE":
			pump = 96.0 if e.phase == "hold" else 80.0
	return {"filter": filter, "belt": belt, "pump": pump}


func draw_mining(a: Dictionary, focused: bool) -> void:
	draw_window(a, focused)
	var x: int = int(a.x)
	var y: int = int(a.y)
	var st: String = sim.sector_state("mining")
	grid.text(x + 2, y + 1, sim.mode, mode_color(sim.mode))
	var st_col := state_color(st)
	if st == "FAULT" and not fault_on:
		st_col = C0
	var st_str: String = st
	grid.text(x + int(a.w) - 2 - st_str.length(), y + 1, st_str, st_col)
	var tv := trough_val()
	var me := mining_event()
	_trough_row(x, y + 3, "heat", sim.heat, not me.is_empty() and me.type == "HEAT_WARN", st)
	_trough_row(x, y + 4, "filter", float(tv.filter), not me.is_empty() and me.type == "FILTER_CLOG", st)
	_trough_row(x, y + 5, "belt", float(tv.belt), not me.is_empty() and me.type == "BELT_SLIP", st)
	_trough_row(x, y + 6, "pump", float(tv.pump), not me.is_empty() and me.type == "JAM_SAFE", st)
	if not me.is_empty():
		var rc: Color = C12 if st == "FAULT" else C14
		if st == "FAULT" and not fault_on:
			rc = C0
		grid.text(x + 2, y + 7, str(me.read), rc)


func _trough_row(x: int, yy: int, label: String, val: float, failing: bool, st: String) -> void:
	var lab := (label + "       ").substr(0, 7)
	grid.text(x + 2, yy, lab, C6)
	var n := int(round(clampf(val / 100.0, 0.0, 1.0) * 16.0))
	var fg := C7
	if label == "heat":
		fg = heat_color(val)
	elif failing:
		fg = C12 if st == "FAULT" else C14
	bar16(x + 9, yy, n, fg)
	if (not failing) and label != "heat":
		grid.text(x + 28, yy, "  ok", C6)
	else:
		grid.text(x + 28, yy, fmt3(val), C7)


func draw_power(a: Dictionary, focused: bool) -> void:
	draw_window(a, focused)
	var x: int = int(a.x)
	var y: int = int(a.y)
	var st: String = sim.sector_state("power")
	var st_col := state_color(st)
	if st == "FAULT" and not fault_on:
		st_col = C0
	grid.text(x + 2, y + 1, st, st_col)
	var sup: float = sim.supply()
	var dem: float = sim.demand()
	var pe := power_event()
	var flicker_dim: bool = (not pe.is_empty()) and pe.type == "GRID_FLICKER" and not flick
	grid.text(x + 2, y + 3, "SUP", C6)
	bar16(x + 6, y + 3, int(round(clampf(sup / 100.0, 0.0, 1.0) * 16.0)), C7)
	grid.text(x + 25, y + 3, fmt3(sup), C7)
	grid.text(x + 2, y + 4, "DEM", C6)
	var dfg: Color = C12 if dem > sup else C7
	if flicker_dim:
		dfg = C8
	bar16(x + 6, y + 4, int(round(clampf(dem / 100.0, 0.0, 1.0) * 16.0)), dfg)
	grid.text(x + 25, y + 4, fmt3(dem), dfg)
	if not pe.is_empty():
		var rc: Color = C12 if st == "FAULT" else C14
		if st == "FAULT" and not fault_on:
			rc = C0
		grid.text(x + 2, y + 5, str(pe.read), rc)


func draw_repair(a: Dictionary, focused: bool) -> void:
	draw_window(a, focused)
	var x: int = int(a.x)
	var y: int = int(a.y)
	var t: Array = sim.repair_targets()
	if t.size() > 0:
		for i in range(mini(3, t.size())):
			var e: Dictionary = t[i]
			var col: Color = C12 if e.phase == "hold" else C14
			if e.phase == "hold" and not fault_on:
				col = C0
			var bg := C0
			if focused and i == 0:
				bg = C14
				col = C15
			var line := (str(e.read) + "                              ").substr(0, int(a.w) - 4)
			grid.text(x + 2, y + 1 + i, line, col, bg)
		return
	if sim.denied > 0.0:
		grid.text(x + 2, y + 1, "denied", C12)
		return
	var c1: Color = C6 if sim.classify else C7
	var c2: Color = C6 if sim.early else C7
	grid.text(x + 2, y + 1, "classify", c1)
	grid.text(x + 2, y + 2, "early", c2)


func draw_radar(a: Dictionary, focused: bool) -> void:
	draw_window(a, focused)
	var x: int = int(a.x)
	var y: int = int(a.y)
	var w: int = int(a.w)
	var h: int = int(a.h)
	var iw := w - 2
	var ih := h - 2
	var field_h := maxi(1, ih - 1)
	if sim.radar_blank:
		var msg := "NO SIGNAL"
		var tx := x + 1 + int((iw - msg.length()) / 2)
		var ty := y + 1 + int(ih / 2)
		grid.text(tx, ty, msg, C12)
		return
	var pe := power_event()
	var hide_dust: bool = (not pe.is_empty()) and pe.type == "GRID_FLICKER" and not flick
	if not hide_dust and iw > 2 and field_h > 2:
		for i in range(16):
			var px := int(absf(sin(float(i) * 12.9898 + anim_t * 0.11)) * 1000.0) % iw
			var py := int(absf(cos(float(i) * 78.233 + anim_t * 0.05)) * 1000.0) % field_h
			if int(anim_t * 3.5 + float(i)) % 5 == 0:
				continue
			grid.put(x + 1 + px, y + 1 + py, "∙", C8)
		for p in DUST:
			if p.x >= iw or p.y >= field_h:
				continue
			if int(anim_t * 2.0 + float(p.x)) % 7 == 0:
				continue
			grid.put(x + 1 + p.x, y + 1 + p.y, "∙", C8)
	var hiss_frame := 0 if flick else 1
	for e in sim.events:
		if e.type != "COMMS_HISS":
			continue
		var n: int = int(e.hiss_n) if e.has("hiss_n") else 6
		var seed: int = int(e.hiss_seed) if e.has("hiss_seed") else 1
		n = clampi(n, 4, 8)
		for i in range(n):
			var hv := (seed * 1103515245 + 12345 + i * 9973 + hiss_frame * 7919) & 0x7fffffff
			var hx := hv % maxi(1, iw)
			var hy := int(hv / maxi(1, iw)) % maxi(1, field_h)
			grid.put(x + 1 + hx, y + 1 + hy, "░", C8)
	var nearest: Dictionary = {}
	var nearest_d := 1000000
	var cx := int(iw / 2)
	var cy := int(field_h / 2)
	for e in sim.events:
		if not sim.is_radar_contact(e):
			continue
		var bx := clampi(int(e.x), 0, maxi(0, iw - 1))
		var by := clampi(int(e.y), 0, maxi(0, field_h - 1))
		grid.put(x + 1 + bx, y + 1 + by, "■", C7)
		var d := absi(bx - cx) + absi(by - cy)
		if nearest.is_empty() or d < nearest_d:
			nearest = e
			nearest_d = d
	if not nearest.is_empty():
		var lab: String = sim.security_label(nearest)
		if lab != "":
			grid.text(x + 2, y + h - 2, lab, C7)


func draw_terminal(a: Dictionary, focused: bool) -> void:
	draw_window(a, focused)
	var x: int = int(a.x)
	var y: int = int(a.y)
	var w: int = int(a.w)
	var h: int = int(a.h)
	var inner_h := h - 2
	var inner_w := w - 2
	var vis: Array = []
	for ln in term_lines:
		vis.append(str(ln))
	var prompt := "$ " + term_buf
	vis.append(prompt)
	var start := maxi(0, vis.size() - inner_h)
	var row := 0
	for i in range(start, vis.size()):
		var s: String = vis[i]
		if s.length() > inner_w:
			s = s.substr(0, inner_w)
		grid.text(x + 1, y + 1 + row, s, C7)
		row += 1
	if focused and caret_on:
		var caret_x := prompt.length()
		if caret_x > inner_w - 1:
			caret_x = inner_w - 1
		var caret_y := vis.size() - start - 1
		if caret_y >= 0 and caret_y < inner_h:
			grid.put(x + 1 + caret_x, y + 1 + caret_y, "█", C15)


func draw_end() -> void:
	grid.fill(0, 0, 80, 25, " ", C0, C0)
	var lines: Array
	var col: Color
	if sim.ended == "win":
		lines = ["SHIFT END", "producing", "CR %d" % int(sim.credits)]
		col = C7
	else:
		var ign: String = sim.ignored_read if sim.ignored_read != "" else "filter dP high"
		lines = [
			"SITE KILL",
			"ignored: " + ign,
			"emergency draw",
			"brownout",
			"radar blank",
			"intrusion",
		]
		col = C12
	for i in range(lines.size()):
		grid.text(10, 8 + i, str(lines[i]), col)
	end_retry_y = 8 + lines.size() + 1
	grid.text(10, end_retry_y, "r  retry", C7)


func draw_cam(a: Dictionary, focused: bool) -> void:
	draw_window(a, focused)


func paint_app(id: String, focused: bool) -> void:
	var a: Dictionary = apps[id]
	if id == "mining":
		draw_mining(a, focused)
	elif id == "power":
		draw_power(a, focused)
	elif id == "repair":
		draw_repair(a, focused)
	elif id == "radar":
		draw_radar(a, focused)
	elif id == "cam":
		draw_cam(a, focused)
	elif id == "terminal":
		draw_terminal(a, focused)


func _paint(dt: float = 0.016) -> void:
	grid.clear()
	if sim.ended != "":
		if cam_feed != null:
			cam_feed.hide_feed()
		draw_end()
		return
	draw_chrome()
	var list := apps_on_ws(wm.ws)
	var foc := focused_app()
	for id in list:
		if id == foc:
			continue
		paint_app(id, false)
	if foc != "" and wm.open.get(foc, false):
		paint_app(foc, true)
	if cam_feed == null:
		return
	if apps.has("cam") and wm.open.get("cam", false) and int(apps["cam"].ws) == int(wm.ws):
		cam_feed.sync(apps["cam"], sim, anim_t, dt)
	else:
		cam_feed.hide_feed()
