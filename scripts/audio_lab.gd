extends Control

const C0 := Color("#000000")
const C6 := Color("#9A6B2F")
const C7 := Color("#C4A36A")
const C14 := Color("#E6C15A")
const C12 := Color("#C44532")
const C8 := Color("#3D2E18")

var audio = null

var dial_sliders: Dictionary = {}
var event_checks: Dictionary = {}
var mode_buttons: Dictionary = {}
var oneshot_preset_opts: Dictionary = {}
var bake_edit: TextEdit
var syncing_ui: bool = false
var status_label: Label

const PRESET_NAMES := ["HIT", "EXPLOSION", "BLIP", "LASER", "CLICK", "MUTATE", "JUMP", "POWERUP"]


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(a) -> void:
	audio = a
	_build_ui()
	audio.set_mode("HIGH")
	_pull_dials_from_audio()
	_pull_oneshot_presets()
	_highlight_mode("HIGH")


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = C0
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	scroll.add_child(root)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 20)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(col)

	var header := Label.new()
	header.text = "OPS/OS audio lab"
	_style_label(header, C14, 22)
	col.add_child(header)

	status_label = Label.new()
	status_label.text = "mode HIGH — dials live"
	_style_label(status_label, C6, 14)
	col.add_child(status_label)

	col.add_child(_section("Dials"))
	var dial_specs := [
		["master", "master / bed gain", 0.0, 2.0, 0.01],
		["drone_hz", "drone Hz", 30.0, 100.0, 0.5],
		["drone_amp", "drone amp", 0.0, 0.4, 0.001],
		["drone_wave", "drone wave (0=saw 1=sq)", 0.0, 1.0, 1.0],
		["drone_duty", "drone duty (square)", 0.05, 0.95, 0.01],
		["drone_lpf", "drone LPF Hz", 80.0, 4000.0, 10.0],
		["drone_lpf_res", "drone LPF res 0..1", 0.0, 1.0, 0.01],
		["sub_amp", "sub amp", 0.0, 0.2, 0.001],
		["noise_amp", "noise amp", 0.0, 0.2, 0.001],
		["noise_hpf", "noise HPF Hz", 20.0, 2000.0, 5.0],
		["noise_lp", "noise LP Hz (cutoff)", 100.0, 8000.0, 10.0],
		["pulse_amp", "pulse amp", 0.0, 0.4, 0.001],
		["pulse_hz", "pulse Hz", 0.1, 8.0, 0.01],
		["pulse_duty", "pulse duty", 0.02, 0.8, 0.01],
		["pitch", "pitch", 0.4, 2.0, 0.01],
		["lfo_hz", "LFO rate", 0.0, 0.5, 0.001],
		["lfo_depth", "LFO depth", 0.0, 1.0, 0.01],
		["vib_hz", "vibrato Hz", 0.0, 2.0, 0.01],
		["vib_depth", "vibrato depth", 0.0, 0.25, 0.001],
		["grit", "grit", 0.0, 0.3, 0.001],
	]
	for spec in dial_specs:
		var row := _make_slider_row(str(spec[0]), str(spec[1]), float(spec[2]), float(spec[3]), float(spec[4]))
		dial_sliders[spec[0]] = row
		col.add_child(row.box)

	col.add_child(_section("Presets"))
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	col.add_child(preset_row)
	for m in ["SAFE", "HIGH", "MAX"]:
		var b := _make_button(m)
		b.pressed.connect(_on_preset.bind(m))
		preset_row.add_child(b)
		mode_buttons[m] = b
	var save_btn := _make_button("Save")
	save_btn.pressed.connect(_on_save)
	preset_row.add_child(save_btn)

	col.add_child(_section("Events"))
	var ev_row := HBoxContainer.new()
	ev_row.add_theme_constant_override("separation", 12)
	col.add_child(ev_row)
	for ev in ["slip", "clog", "heat", "brownout", "jam", "intrusion", "kill"]:
		var cb := CheckButton.new()
		cb.text = ev
		_style_check(cb)
		cb.toggled.connect(_on_event.bind(ev))
		ev_row.add_child(cb)
		event_checks[ev] = cb

	col.add_child(_section("One-shots (sfxr)"))
	for kind in ["thud", "alarm", "kill"]:
		col.add_child(_make_oneshot_row(kind))

	col.add_child(_section("Bake"))
	var bake_btn := _make_button("print bake")
	bake_btn.pressed.connect(_on_bake)
	col.add_child(bake_btn)
	bake_edit = TextEdit.new()
	bake_edit.custom_minimum_size = Vector2(0, 220)
	bake_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bake_edit.editable = true
	bake_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_style_textedit(bake_edit)
	col.add_child(bake_edit)


func _make_oneshot_row(kind: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var lab := Label.new()
	lab.text = kind
	lab.custom_minimum_size = Vector2(70, 0)
	_style_label(lab, C6, 13)
	row.add_child(lab)

	var opt := OptionButton.new()
	for i in PRESET_NAMES.size():
		opt.add_item(PRESET_NAMES[i], i)
	opt.custom_minimum_size = Vector2(140, 28)
	opt.add_theme_color_override("font_color", C7)
	opt.item_selected.connect(func(idx: int):
		if syncing_ui or audio == null:
			return
		audio.oneshots[kind]["preset"] = PRESET_NAMES[idx]
		status_label.text = "%s preset = %s" % [kind, PRESET_NAMES[idx]]
	)
	row.add_child(opt)
	oneshot_preset_opts[kind] = opt

	var fire := _make_button("Fire %s" % kind)
	fire.pressed.connect(func():
		match kind:
			"thud":
				audio.fire_thud()
			"alarm":
				audio.fire_alarm()
			"kill":
				audio.fire_kill()
		status_label.text = "fired sfxr %s" % kind
	)
	row.add_child(fire)
	return row


func _section(title: String) -> Label:
	var l := Label.new()
	l.text = title
	_style_label(l, C14, 16)
	return l


func _style_label(l: Label, col: Color, size: int) -> void:
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", size)


func _style_check(cb: CheckButton) -> void:
	cb.add_theme_color_override("font_color", C7)
	cb.add_theme_color_override("font_pressed_color", C14)
	cb.add_theme_color_override("font_hover_color", C14)


func _style_textedit(te: TextEdit) -> void:
	te.add_theme_color_override("font_color", C7)
	te.add_theme_color_override("background_color", C0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C0
	sb.border_color = C8
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	te.add_theme_stylebox_override("normal", sb)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 28)
	var normal := StyleBoxFlat.new()
	normal.bg_color = C0
	normal.border_color = C6
	normal.set_border_width_all(1)
	normal.set_content_margin_all(6)
	var hover := normal.duplicate()
	hover.border_color = C14
	var pressed := normal.duplicate()
	pressed.bg_color = C8
	pressed.border_color = C14
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", C7)
	b.add_theme_color_override("font_hover_color", C14)
	b.add_theme_color_override("font_pressed_color", C14)
	return b


func _make_slider_row(key: String, label: String, mn: float, mx: float, step: float, group: String = "dial") -> Dictionary:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lab := Label.new()
	lab.text = label
	lab.custom_minimum_size = Vector2(200, 0)
	_style_label(lab, C6, 13)
	box.add_child(lab)

	var slider := HSlider.new()
	slider.min_value = mn
	slider.max_value = mx
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(280, 18)
	_style_slider(slider)
	box.add_child(slider)

	var val := Label.new()
	val.custom_minimum_size = Vector2(72, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style_label(val, C7, 13)
	box.add_child(val)

	slider.value_changed.connect(func(v: float):
		val.text = _fmt(v)
		if syncing_ui:
			return
		_on_slider(group, key, v)
	)
	return {"box": box, "slider": slider, "val": val, "key": key}


func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = C8
	track.set_content_margin_all(2)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var fill := StyleBoxFlat.new()
	fill.bg_color = C6
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)


func _fmt(v: float) -> String:
	if absf(v) >= 100.0:
		return "%.0f" % v
	if absf(v) >= 10.0:
		return "%.1f" % v
	if absf(v) >= 1.0:
		return "%.2f" % v
	return "%.3f" % v


func _on_slider(group: String, key: String, v: float) -> void:
	if audio == null:
		return
	if group == "dial":
		var d: Dictionary = audio.get_dials()
		d[key] = v
		audio.set_dials(d)
		status_label.text = "mode %s — dials live" % audio.get_mode()


func _on_preset(m: String) -> void:
	audio.set_mode(m)
	_pull_dials_from_audio()
	_highlight_mode(m)
	status_label.text = "mode %s — loaded preset" % m


func _on_save() -> void:
	var m: String = audio.get_mode()
	audio.save_dials_into_mode(m)
	status_label.text = "saved dials into %s" % m


func _on_event(ev: String, on: bool) -> void:
	audio.set_event(ev, on)
	status_label.text = "event %s = %s" % [ev, str(on)]


func _on_bake() -> void:
	var text: String = audio.print_bake()
	bake_edit.text = text
	status_label.text = "bake printed (stdout + panel)"


func _highlight_mode(m: String) -> void:
	for id in mode_buttons.keys():
		var b: Button = mode_buttons[id]
		if id == m:
			b.add_theme_color_override("font_color", C14)
		else:
			b.add_theme_color_override("font_color", C7)


func _pull_dials_from_audio() -> void:
	syncing_ui = true
	var d: Dictionary = audio.get_dials()
	for k in dial_sliders.keys():
		if not d.has(k):
			continue
		var row: Dictionary = dial_sliders[k]
		var v := float(d[k])
		row.slider.value = v
		row.val.text = _fmt(v)
	syncing_ui = false


func _pull_oneshot_presets() -> void:
	syncing_ui = true
	for kind in oneshot_preset_opts.keys():
		var opt: OptionButton = oneshot_preset_opts[kind]
		var name: String = str(audio.oneshots[kind].get("preset", "HIT")).to_upper()
		var idx := PRESET_NAMES.find(name)
		if idx < 0:
			idx = 0
		opt.select(idx)
	syncing_ui = false
