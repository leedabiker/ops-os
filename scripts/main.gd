extends Node

const SimScript = preload("res://scripts/sim.gd")
const GridScript = preload("res://scripts/grid.gd")
const VfsScript = preload("res://scripts/vfs.gd")

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

var sim
var vfs
var grid
var vp: SubViewport
var screen: Sprite2D
var scale_i: int = 2

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

	get_window().unresizable = false
	DisplayServer.window_set_size(Vector2i(1280, 800))
	get_window().size_changed.connect(_fit)

	vp = SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.size = Vector2i(LOGICAL_W, LOGICAL_H)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.handle_input_locally = false
	add_child(vp)

	grid = GridScript.new()
	vp.add_child(grid)

	screen = Sprite2D.new()
	screen.centered = false
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(screen)
	screen.texture = vp.get_texture()

	_boot_wm()
	_fit()

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
		"mining": {"id": "mining", "title": "mining", "ws": 2, "x": 1, "y": 1, "w": 39, "h": 9},
		"repair": {"id": "repair", "title": "repair", "ws": 2, "x": 41, "y": 1, "w": 32, "h": 6},
		"radar": {"id": "radar", "title": "radar", "ws": 3, "x": 1, "y": 1, "w": 78, "h": 22},
		"terminal": {"id": "terminal", "title": "terminal", "ws": 2, "x": 2, "y": 12, "w": 44, "h": 10},
	}
	wm = {
		"ws": 2,
		"focus": {1: "power", 2: "mining", 3: "radar"},
		"open": {"power": true, "mining": true, "repair": true, "radar": true, "terminal": false},
	}
	term_open = false
	term_buf = ""
	term_lines = []
	term_last = ""


func _fit() -> void:
	if screen == null:
		return
	var wsz := get_viewport().get_visible_rect().size
	var wx := int(wsz.x)
	var wy := int(wsz.y)
	scale_i = maxi(1, mini(int(wx / LOGICAL_W), int(wy / LOGICAL_H)))
	screen.scale = Vector2(scale_i, scale_i)
	var dw := LOGICAL_W * scale_i
	var dh := LOGICAL_H * scale_i
	screen.position = Vector2((wx - dw) / 2.0, (wy - dh) / 2.0)


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
	_paint()
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
	if sim.ended != "":
		return
	var sup := _is_super(e)
	var typing := _typing()
	var k := e.keycode

	if sup and e.shift_pressed and (k == KEY_1 or k == KEY_KP_1):
		_move_focused(1)
		get_viewport().set_input_as_handled()
		return
	if sup and e.shift_pressed and (k == KEY_2 or k == KEY_KP_2):
		_move_focused(2)
		get_viewport().set_input_as_handled()
		return
	if sup and e.shift_pressed and (k == KEY_3 or k == KEY_KP_3):
		_move_focused(3)
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
	if sup and k == KEY_Q:
		close_focused()
		get_viewport().set_input_as_handled()
		return
	if k == KEY_TAB:
		focus_next(e.shift_pressed)
		get_viewport().set_input_as_handled()
		return

	if not typing:
		if k == KEY_1 or k == KEY_KP_1:
			set_ws(1)
			get_viewport().set_input_as_handled()
			return
		if k == KEY_2 or k == KEY_KP_2:
			set_ws(2)
			get_viewport().set_input_as_handled()
			return
		if k == KEY_3 or k == KEY_KP_3:
			set_ws(3)
			get_viewport().set_input_as_handled()
			return
		if k == KEY_Q:
			close_focused()
			get_viewport().set_input_as_handled()
			return
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
	if cmd == "cat":
		var out: Array = vfs.exec(line)
		cat_pending = out
		cat_wait = 0.4
		return
	var out2: Array = vfs.exec(line)
	for ln in out2:
		_term_print(str(ln))


func set_ws(n: int) -> void:
	if n < 1 or n > 3:
		return
	wm.ws = n


func focused_app() -> String:
	var f = wm.focus.get(wm.ws, "")
	return str(f) if f != null else ""


func apps_on_ws(ws: int) -> Array:
	var order := ["power", "mining", "repair", "radar", "terminal"]
	var out: Array = []
	for id in order:
		if not wm.open.get(id, false):
			continue
		if int(apps[id].ws) == ws:
			out.append(id)
	return out


func launch(id: String) -> void:
	if not apps.has(id):
		return
	wm.open[id] = true
	if id == "terminal":
		apps[id].ws = wm.ws
		term_open = true
	else:
		wm.ws = int(apps[id].ws)
	wm.focus[int(apps[id].ws)] = id


func _launch_terminal() -> void:
	apps["terminal"].ws = wm.ws
	apps["terminal"].x = 2
	apps["terminal"].y = 12
	wm.open["terminal"] = true
	term_open = true
	wm.focus[wm.ws] = "terminal"


func close_focused() -> void:
	var id := focused_app()
	if id == "" or not wm.open.get(id, false):
		return
	wm.open[id] = false
	if id == "terminal":
		term_open = false
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


func _move_focused(n: int) -> void:
	var id := focused_app()
	if id == "":
		return
	apps[id].ws = n
	wm.open[id] = true
	wm.ws = n
	wm.focus[n] = id


func _cell_at(mouse: Vector2) -> Vector2i:
	var p := mouse - screen.position
	p /= float(scale_i)
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
	if sim.ended != "":
		return
	var c := _cell_at(mb.position)
	if c.y == 0:
		if c.x >= 0 and c.x <= 6:
			set_ws(1)
		elif c.x >= 8 and c.x <= 15:
			set_ws(2)
		elif c.x >= 17 and c.x <= 23:
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


func _on_drag(mm: InputEventMouseMotion) -> void:
	if drag_id == "" or not apps.has(drag_id):
		return
	var c := _cell_at(mm.position)
	var a: Dictionary = apps[drag_id]
	var nx := c.x - drag_off.x
	var ny := c.y - drag_off.y
	nx = clampi(nx, 0, 80 - int(a.w))
	ny = clampi(ny, 1, 25 - int(a.h))
	a.x = nx
	a.y = ny


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
			grid.put(x + 1 + i, y, "█", fill_fg)
		else:
			grid.put(x + 1 + i, y, " ", C0)
	grid.put(x + 17, y, "]", C8)


func draw_chrome() -> void:
	grid.fill(0, 0, 80, 1, " ", C0, C0)
	_tab(0, " 1 PWR ", 1)
	_tab(8, " 2 MINE ", 2)
	_tab(17, " 3 SEC ", 3)
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
	if sim.radar_blank:
		var msg := "NO SIGNAL"
		var tx := x + 1 + int((w - 2 - msg.length()) / 2)
		var ty := y + 1 + int((h - 2) / 2)
		grid.text(tx, ty, msg, C12)
		return
	var pe := power_event()
	var hide_dust: bool = (not pe.is_empty()) and pe.type == "GRID_FLICKER" and not flick
	if not hide_dust:
		for p in DUST:
			grid.put(x + 1 + p.x, y + 1 + p.y, "∙", C8)


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
		var c := col
		grid.text(10, 8 + i, str(lines[i]), c)


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
	elif id == "terminal":
		draw_terminal(a, focused)


func _paint() -> void:
	grid.clear()
	if sim.ended != "":
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
