extends RefCounted

const SHIFT := 480.0
const B1 := 150.0
const B2 := 330.0

const RADAR_IW := 35
const RADAR_IH := 19

const ET := {
	"FILTER_CLOG": {"sector": "mining", "read": "filter dP high", "verb": "repair", "need": "HIGH+", "inc": [24, 16, 10], "hold": [12, 9, 6]},
	"BELT_SLIP": {"sector": "mining", "read": "belt slip", "verb": "repair", "need": "HIGH+", "inc": [16, 12, 8], "hold": [12, 9, 6]},
	"HEAT_WARN": {"sector": "mining", "read": "heat trip", "verb": "safe", "need": "MAX", "inc": [20, 14, 10], "hold": [12, 9, 6]},
	"JAM_SAFE": {"sector": "mining", "read": "feed jam", "verb": "repair", "need": "ANY", "inc": [28, 20, 14], "hold": [12, 9, 6]},
	"CELL_DIP": {"sector": "power", "read": "cell output low", "verb": "mode_or_repair", "need": "ANY", "inc": [20, 14, 10], "hold": [12, 9, 6]},
	"GRID_FLICKER": {"sector": "power", "read": "grid unstable", "verb": "expire", "need": "ANY", "inc": [10, 8, 6], "hold": [0, 0, 0]},
	"BROWNOUT": {"sector": "power", "read": "breaker open", "verb": "repair", "need": "NONE", "inc": [0, 0, 0], "hold": [12, 9, 6]},
	"CONTACT_UNID": {"sector": "security", "read": "?", "verb": "ack", "need": "ANY", "inc": [14, 10, 7], "hold": [0, 0, 0]},
	"FENCE_GLITCH": {"sector": "security", "read": "?", "verb": "ack", "need": "ANY", "inc": [14, 10, 7], "hold": [0, 0, 0]},
	"INTRUSION": {"sector": "security", "read": "?", "verb": "ack", "need": "ANY", "inc": [12, 9, 6], "hold": [0, 0, 0]},
	"COMMS_HISS": {"sector": "security", "read": "", "verb": "expire", "need": "ANY", "inc": [8, 6, 5], "hold": [0, 0, 0]},
}

var rng: int = 1
var elapsed: float = 0.0
var remaining: float = SHIFT
var mode: String = "SAFE"
var heat: float = 22.0
var materials: float = 0.0
var credits: float = 0.0
var events: Array = []
var token: int = 0
var emergency: bool = false
var radar_blank: bool = false
var classify: bool = false
var early: bool = false
var ignored_read: String = ""
var ended: String = ""
var spawn_cd: float = 8.0
var high_time: float = 0.0
var last_clog: float = -1.0
var last_dip: float = -1.0
var flicker_band: int = -1
var denied: float = 0.0
var denied_on: String = ""
var cascade_arm: float = 0.0
var interlock: String = "7K-441"
var grep_locked: bool = false
var hiss_cd: float = 8.0


func _rand() -> float:
	rng = (rng * 1664525 + 1013904223) & 0xFFFFFFFF
	return float(rng) / 4294967296.0


func _rand_int(n: int) -> int:
	return int(_rand() * float(n))


func band() -> int:
	if elapsed < B1:
		return 0
	if elapsed < B2:
		return 1
	return 2


func hold_s() -> float:
	return [12.0, 9.0, 6.0][band()]


func clock_cap() -> int:
	return 2 if band() >= 2 else 1


func cooldown() -> float:
	return [20.0, 14.0, 10.0][band()]


func rank(m: String) -> int:
	if m == "SAFE":
		return 0
	if m == "HIGH":
		return 1
	return 2


func supply() -> float:
	var s := 80.0
	for e in events:
		if e.type == "CELL_DIP":
			s = 56.0
		if e.type == "BROWNOUT" or (e.type == "CELL_DIP" and e.phase == "hold"):
			s = minf(s, 40.0)
	return s


func demand() -> float:
	var d := 24.0
	if mode == "HIGH":
		d = 48.0
	elif mode == "MAX":
		d = 76.0
	if emergency:
		d += 30.0
	return d


func _has_sector(sec: String) -> bool:
	for e in events:
		if e.sector == sec:
			return true
	return false


func _find_type(t: String) -> Dictionary:
	for e in events:
		if e.type == t:
			return e
	return {}


func _find_sector(sec: String) -> Dictionary:
	for e in events:
		if e.sector == sec:
			return e
	return {}


func sector_state(sec: String) -> String:
	if sec == "mining" and heat >= 100.0:
		return "FAULT"
	if sec == "security" and radar_blank:
		return "FAULT"
	var any_event := false
	for e in events:
		if e.sector != sec:
			continue
		if e.type == "COMMS_HISS":
			continue
		any_event = true
		if e.phase == "hold":
			return "FAULT"
	if any_event:
		return "STRESSED"
	if sec == "power" and demand() > supply():
		return "STRESSED"
	return "STABLE"


func live_clocks() -> int:
	var n := 0
	for e in events:
		if e.type == "COMMS_HISS":
			continue
		n += 1
	return n


func is_radar_contact(e: Dictionary) -> bool:
	if e.is_empty():
		return false
	var t: String = str(e.type)
	return t == "CONTACT_UNID" or t == "FENCE_GLITCH" or t == "INTRUSION"


func radar_contacts() -> Array:
	var list: Array = []
	for e in events:
		if is_radar_contact(e):
			list.append(e)
	return list


func security_label(e: Dictionary) -> String:
	if e.is_empty() or str(e.type) == "COMMS_HISS":
		return ""
	if not classify:
		return "?"
	if e.type == "CONTACT_UNID":
		return "contact"
	if e.type == "FENCE_GLITCH":
		return "fence"
	if e.type == "INTRUSION":
		return "intrusion"
	return "?"


func _security_contact_busy() -> bool:
	for e in events:
		if e.sector == "security" and e.type != "COMMS_HISS":
			return true
	return false


func ack_event(e: Dictionary) -> bool:
	if ended != "":
		return false
	if not is_radar_contact(e):
		return false
	clear_event(e)
	return true


func ack_first() -> bool:
	var list := radar_contacts()
	if list.is_empty():
		return false
	return ack_event(list[0])


func ack_at(px: int, py: int) -> bool:
	for e in radar_contacts():
		if int(e.x) == px and int(e.y) == py:
			return ack_event(e)
	return false


func _place_security(e: Dictionary) -> void:
	if e.sector != "security":
		return
	e["x"] = 2 + _rand_int(maxi(1, RADAR_IW - 4))
	e["y"] = 2 + _rand_int(maxi(1, RADAR_IH - 4))
	if e.type == "COMMS_HISS":
		e["hiss_n"] = 4 + _rand_int(5)
		e["hiss_seed"] = rng


func make_event(type: String) -> Dictionary:
	var d: Dictionary = ET[type]
	var b := band()
	var inc: float = float(d.inc[b])
	if early and d.sector == "security" and type != "COMMS_HISS":
		inc += 6.0
	var hold: float = float(d.hold[b])
	var e := {
		"type": type,
		"sector": d.sector,
		"read": d.read,
		"verb": d.verb,
		"phase": "hold" if inc <= 0.0 else "incident",
		"incident": inc,
		"hold": hold,
		"t": hold if inc <= 0.0 else inc,
		"x": 0,
		"y": 0,
	}
	return e


func spawn_event(type: String) -> Dictionary:
	if not ET.has(type):
		return {}
	if ended != "":
		return {}
	var d: Dictionary = ET[type]
	if type != "BROWNOUT":
		for e in events:
			if e.sector != d.sector:
				continue
			if d.sector == "security":
				if type == "COMMS_HISS" or e.type == "COMMS_HISS":
					continue
			return {}
	var ev := make_event(type)
	_place_security(ev)
	if type == "INTRUSION" and radar_blank:
		ignored_read = "intrusion"
		token = 6
		ended = "kill"
	if ev.phase == "hold":
		enter_fault(ev)
	events.append(ev)
	if type != "COMMS_HISS":
		spawn_cd = cooldown()
	if type == "FILTER_CLOG":
		last_clog = elapsed
	if type == "GRID_FLICKER":
		flicker_band = band()
	if type == "CELL_DIP":
		last_dip = elapsed
	return ev


func enter_fault(e: Dictionary) -> void:
	e.phase = "hold"
	e.t = e.hold if e.hold > 0.0 else hold_s()
	if e.verb == "safe":
		e.verb = "repair"
	if e.verb == "expire":
		return
	if e.sector == "mining":
		if ignored_read == "":
			ignored_read = e.read
		emergency = true
		if token < 2:
			token = 2
	if e.sector == "power":
		if token < 3:
			token = 3


func step_cascade() -> void:
	if ended != "":
		return
	if token < 2:
		token = 2
	token += 1
	if token == 3:
		var kept: Array = []
		for e in events:
			if e.type != "GRID_FLICKER":
				kept.append(e)
		events = kept
		var pe := _find_sector("power")
		if not pe.is_empty():
			pe.phase = "hold"
			pe.t = hold_s()
			pe.verb = "repair"
			if pe.type != "CELL_DIP":
				pe.read = "breaker open"
		else:
			spawn_event("BROWNOUT")
			token = maxi(token, 3)
	if token >= 4:
		radar_blank = true
	if token >= 6:
		token = 6
		ended = "kill"


func clear_event(e: Dictionary) -> void:
	var kept: Array = []
	for x in events:
		if x != e:
			kept.append(x)
	events = kept
	if e.sector == "mining":
		if token <= 2:
			token = 0
			emergency = false
			ignored_read = ""
	if e.sector == "power":
		if token == 3:
			cascade_arm = 0.0


func can_repair(e: Dictionary) -> bool:
	if e.is_empty():
		return false
	if e.verb == "repair" or e.verb == "mode_or_repair":
		return true
	if e.verb == "safe" and e.phase == "hold":
		return true
	return false


func repair_targets() -> Array:
	var list: Array = []
	for e in events:
		if can_repair(e):
			list.append(e)
	list.sort_custom(func(a, b):
		var fa := 0 if a.phase == "hold" else 1
		var fb := 0 if b.phase == "hold" else 1
		if fa != fb:
			return fa < fb
		var sa := 0 if a.sector == "mining" else 1
		var sb := 0 if b.sector == "mining" else 1
		return sa < sb
	)
	return list


func do_repair() -> bool:
	if ended != "":
		return false
	var t := repair_targets()
	if t.is_empty():
		return false
	clear_event(t[0])
	denied = 0.0
	return true


func set_mode(m: String) -> void:
	if ended != "":
		return
	if m != "SAFE" and m != "HIGH" and m != "MAX":
		return
	var old := mode
	var dropped := rank(m) < rank(old)
	mode = m
	if dropped:
		var snap: Array = events.duplicate()
		for e in snap:
			if e.phase != "incident":
				continue
			if e.type == "CELL_DIP":
				clear_event(e)
			if e.type == "HEAT_WARN" and m == "SAFE":
				clear_event(e)


func buy_upgrade(which: String) -> bool:
	var cost := 20.0 if which == "classify" else 30.0
	if materials < cost:
		denied = 0.6
		denied_on = which
		return false
	if which == "classify":
		if classify:
			denied = 0.6
			denied_on = which
			return false
		materials -= cost
		classify = true
	else:
		if early:
			denied = 0.6
			denied_on = which
			return false
		materials -= cost
		early = true
	return true


func maybe_spawn(dt: float) -> void:
	if ended != "":
		return
	hiss_cd -= dt
	if elapsed >= 8.0 and hiss_cd <= 0.0 and _find_type("COMMS_HISS").is_empty():
		var hs := spawn_event("COMMS_HISS")
		if not hs.is_empty():
			hiss_cd = 12.0 + _rand() * 10.0
		else:
			hiss_cd = 4.0
	spawn_cd -= dt
	var mining_busy := _has_sector("mining")
	if (mode == "HIGH" or mode == "MAX") and not mining_busy:
		high_time += dt
		if high_time >= 5.0 and (last_clog < 0.0 or elapsed - last_clog >= 36.0):
			spawn_event("FILTER_CLOG")
			high_time = 0.0
			return
	else:
		high_time = 0.0
	if elapsed < 8.0:
		return
	if spawn_cd > 0.0:
		return
	if live_clocks() >= clock_cap():
		return
	var power_busy := _has_sector("power")
	var cands: Array = []
	if not mining_busy:
		if mode == "HIGH" or mode == "MAX":
			for i in range(5):
				cands.append("FILTER_CLOG")
			for i in range(3):
				cands.append("BELT_SLIP")
		if mode == "MAX" and heat >= 70.0:
			for i in range(6):
				cands.append("HEAT_WARN")
		if mode == "SAFE" and elapsed > 28.0:
			cands.append("JAM_SAFE")
	if not power_busy:
		if last_dip < 0.0 or elapsed - last_dip > 48.0:
			for i in range(2):
				cands.append("CELL_DIP")
		if flicker_band != band():
			for i in range(2):
				cands.append("GRID_FLICKER")
	if not _security_contact_busy():
		if band() >= 1:
			cands.append("CONTACT_UNID")
			cands.append("FENCE_GLITCH")
		if band() >= 2:
			cands.append("INTRUSION")
	if cands.is_empty():
		spawn_cd = 4.0
		return
	spawn_event(cands[_rand_int(cands.size())])


func tick_events(dt: float) -> void:
	var snap: Array = events.duplicate()
	for e in snap:
		if e.type == "INTRUSION" and radar_blank:
			e.t = 0.0
		e.t -= dt
		if e.t > 0.0:
			continue
		if e.type == "INTRUSION":
			if ignored_read == "":
				ignored_read = "intrusion"
			token = 6
			ended = "kill"
			return
		if e.verb == "expire" or e.type == "GRID_FLICKER" or e.type == "CONTACT_UNID" or e.type == "FENCE_GLITCH" or e.type == "COMMS_HISS":
			var kept: Array = []
			for x in events:
				if x != e:
					kept.append(x)
			events = kept
			continue
		if e.phase == "incident":
			enter_fault(e)
			continue
		if ignored_read == "":
			ignored_read = e.read
		step_cascade()
		if ended != "":
			return
		e.t = hold_s()


func tick_heat(dt: float) -> void:
	if mode == "SAFE":
		heat = maxf(0.0, heat - 3.5 * dt)
	elif mode == "HIGH":
		heat = minf(100.0, heat + 0.10 * dt)
	else:
		heat = minf(100.0, heat + 0.85 * dt)
	if heat >= 100.0:
		heat = 100.0
		var hw := _find_type("HEAT_WARN")
		if not hw.is_empty():
			if hw.phase == "incident":
				enter_fault(hw)
		elif not _has_sector("mining"):
			var e := make_event("HEAT_WARN")
			e.phase = "hold"
			e.t = e.hold
			e.verb = "repair"
			events.append(e)
			enter_fault(e)


func tick_extract(dt: float) -> void:
	if sector_state("mining") == "FAULT":
		return
	var rate := 0.35
	if mode == "HIGH":
		rate = 0.70
	elif mode == "MAX":
		rate = 1.225
	var g := rate * dt
	materials += g
	credits += g


func tick(dt: float) -> void:
	if ended != "":
		return
	elapsed += dt
	remaining = maxf(0.0, SHIFT - elapsed)
	if denied > 0.0:
		denied = maxf(0.0, denied - dt)
	tick_heat(dt)
	tick_extract(dt)
	tick_events(dt)
	if ended != "":
		return
	maybe_spawn(dt)
	if remaining <= 0.0:
		remaining = 0.0
		if token < 6:
			ended = "win"


func _make_token() -> String:
	var chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var a: String = chars.substr(_rand_int(36), 1)
	var b: String = chars.substr(_rand_int(36), 1)
	return "%s%s-%03d" % [a, b, _rand_int(1000)]


func reset(seed: int = 0) -> void:
	if seed == 0:
		rng = int(Time.get_unix_time_from_system()) & 0xFFFFFFFF
		if rng == 0:
			rng = 1
	else:
		rng = seed
	elapsed = 0.0
	remaining = SHIFT
	mode = "SAFE"
	heat = 22.0
	materials = 0.0
	credits = 0.0
	events = []
	token = 0
	emergency = false
	radar_blank = false
	classify = false
	early = false
	ignored_read = ""
	ended = ""
	spawn_cd = 8.0
	high_time = 0.0
	last_clog = -1.0
	last_dip = -1.0
	flicker_band = -1
	denied = 0.0
	denied_on = ""
	cascade_arm = 0.0
	interlock = _make_token()
	grep_locked = false
	hiss_cd = 8.0


func self_test() -> Dictionary:
	var r: Array = []
	var ok := true

	reset(1)
	ok = remaining == 480.0
	r.append({"name": "clock", "pass": ok})

	mode = "HIGH"
	for i in range(80):
		tick(0.1)
	var clog: Dictionary = _find_type("FILTER_CLOG")
	ok = not clog.is_empty()
	r.append({"name": "HIGH_FILTER_CLOG", "pass": ok, "extra": str(events)})
	ok = sector_state("mining") == "STRESSED"
	r.append({"name": "mining_STRESSED", "pass": ok})

	var repaired := do_repair()
	ok = repaired and _find_type("FILTER_CLOG").is_empty() and sector_state("mining") == "STABLE"
	r.append({"name": "repair_clears", "pass": ok})

	reset(1)
	mode = "HIGH"
	spawn_event("FILTER_CLOG")
	var ev: Dictionary = events[0] if events.size() > 0 else {}
	var inc := float(ev.incident) if not ev.is_empty() else 24.0
	for i in range(int(ceil((inc + 0.3) * 10.0))):
		tick(0.1)
	ok = sector_state("mining") == "FAULT"
	r.append({"name": "ignore_FAULT", "pass": ok, "extra": sector_state("mining") + " token=" + str(token)})
	ok = token >= 2
	r.append({"name": "token_AB", "pass": ok, "extra": str(token)})

	var hold := hold_s()
	for i in range(int(ceil((hold + 0.3) * 10.0))):
		tick(0.1)
	ok = token >= 3
	r.append({"name": "cascade_C", "pass": ok, "extra": str(token)})

	reset(1)
	ok = mode == "SAFE"
	r.append({"name": "boot_SAFE", "pass": ok})
	tick(1.0)
	ok = remaining == 479.0 and elapsed == 1.0
	r.append({"name": "clock_ticks", "pass": ok})

	reset(1)
	mode = "MAX"
	heat = 80.0
	spawn_event("HEAT_WARN")
	ok = sector_state("mining") == "STRESSED"
	r.append({"name": "heat_warn_stressed", "pass": ok})
	set_mode("SAFE")
	ok = _find_type("HEAT_WARN").is_empty() and sector_state("mining") == "STABLE"
	r.append({"name": "heat_warn_SAFE_clears", "pass": ok})

	reset(1)
	spawn_event("GRID_FLICKER")
	var ginc: float = float(events[0].incident)
	for i in range(int(ceil((ginc + 0.4) * 10.0))):
		tick(0.1)
	ok = sector_state("power") != "FAULT" and _find_type("GRID_FLICKER").is_empty() and token == 0
	r.append({"name": "flicker_no_FAULT", "pass": ok})

	reset(1)
	mode = "SAFE"
	heat = 50.0
	for i in range(40):
		tick(0.1)
	ok = heat < 50.0 and demand() == 24.0
	r.append({"name": "SAFE_heat_falls", "pass": ok, "extra": str(heat)})

	reset(1)
	mode = "MAX"
	heat = 50.0
	for i in range(40):
		tick(0.1)
	ok = heat > 50.0 and absf(demand() - 76.0) < 0.01
	r.append({"name": "MAX_heat_climbs", "pass": ok, "extra": str(heat) + " dem=" + str(demand())})

	reset(1)
	mode = "HIGH"
	var dem_h: float = demand()
	ok = absf(dem_h - 48.0) < 0.01
	r.append({"name": "HIGH_draw_60", "pass": ok, "extra": str(dem_h)})

	reset(1)
	mode = "MAX"
	heat = 80.0
	spawn_event("HEAT_WARN")
	var before: int = events.size()
	do_repair()
	ok = events.size() == before
	r.append({"name": "HEAT_WARN_Enter_no_clear", "pass": ok})

	reset(1)
	mode = "MAX"
	spawn_event("CELL_DIP")
	ok = demand() > supply()
	r.append({"name": "MAX_CELL_DIP_brownout_ready", "pass": ok, "extra": "dem=%s sup=%s" % [demand(), supply()]})

	reset(1)
	var cu := spawn_event("CONTACT_UNID")
	ok = not cu.is_empty() and cu.has("x") and cu.has("y") and sector_state("security") == "STRESSED"
	r.append({"name": "contact_blob", "pass": ok, "extra": str(cu)})
	var cinc := float(cu.incident)
	ok = absf(cinc - 14.0) < 0.01
	r.append({"name": "contact_inc_b1", "pass": ok, "extra": str(cinc)})
	for i in range(int(ceil((cinc + 0.3) * 10.0))):
		tick(0.1)
	ok = ended == "" and token == 0 and _find_type("CONTACT_UNID").is_empty() and sector_state("security") == "STABLE"
	r.append({"name": "contact_expire_tax", "pass": ok, "extra": "ended=%s token=%s" % [ended, token]})

	reset(1)
	var fg := spawn_event("FENCE_GLITCH")
	ok = not fg.is_empty() and absf(float(fg.incident) - 14.0) < 0.01
	r.append({"name": "fence_same_timer", "pass": ok, "extra": str(fg.incident) if not fg.is_empty() else "empty"})
	reset(1)
	spawn_event("CONTACT_UNID")
	spawn_event("FENCE_GLITCH")
	ok = radar_contacts().size() == 1
	r.append({"name": "one_security_contact", "pass": ok, "extra": str(radar_contacts().size())})

	reset(1)
	spawn_event("FENCE_GLITCH")
	ok = ack_first() and _find_type("FENCE_GLITCH").is_empty() and token == 0 and ended == ""
	r.append({"name": "fence_ack_clears", "pass": ok})

	reset(1)
	var ce := spawn_event("CONTACT_UNID")
	ok = ack_at(int(ce.x), int(ce.y)) and _find_type("CONTACT_UNID").is_empty()
	r.append({"name": "contact_ack_at", "pass": ok})

	reset(1)
	early = true
	var ce2 := spawn_event("CONTACT_UNID")
	ok = absf(float(ce2.incident) - 20.0) < 0.01
	r.append({"name": "early_contact_plus6", "pass": ok, "extra": str(ce2.incident)})
	var fe2 := spawn_event("FENCE_GLITCH")
	ok = fe2.is_empty()
	r.append({"name": "early_no_second_contact", "pass": ok})
	reset(1)
	early = true
	var ie := spawn_event("INTRUSION")
	ok = absf(float(ie.incident) - 18.0) < 0.01
	r.append({"name": "early_intrusion_plus6", "pass": ok, "extra": str(ie.incident)})
	reset(1)
	early = true
	var hs := spawn_event("COMMS_HISS")
	ok = absf(float(hs.incident) - 8.0) < 0.01
	r.append({"name": "early_hiss_no_plus6", "pass": ok, "extra": str(hs.incident)})

	reset(1)
	classify = true
	var cl := spawn_event("CONTACT_UNID")
	ok = security_label(cl) == "contact"
	r.append({"name": "classify_contact_label", "pass": ok, "extra": security_label(cl)})
	reset(1)
	var raw := spawn_event("INTRUSION")
	ok = security_label(raw) == "?"
	r.append({"name": "unclassified_question", "pass": ok})
	classify = true
	ok = security_label(raw) == "intrusion"
	r.append({"name": "classify_live_relabel", "pass": ok, "extra": security_label(raw)})

	reset(1)
	spawn_event("INTRUSION")
	var iinc: float = float(events[0].incident)
	for i in range(int(ceil((iinc + 0.3) * 10.0))):
		tick(0.1)
	ok = ended == "kill" and ignored_read == "intrusion" and token >= 6
	r.append({"name": "intrusion_expire_kill", "pass": ok, "extra": "ended=%s ign=%s token=%s" % [ended, ignored_read, token]})

	reset(1)
	radar_blank = true
	spawn_event("INTRUSION")
	ok = ended == "kill" and ignored_read == "intrusion"
	r.append({"name": "intrusion_blank_kill", "pass": ok, "extra": "ended=%s" % ended})

	reset(1)
	spawn_event("COMMS_HISS")
	hiss_cd = 999.0
	ok = sector_state("security") == "STABLE" and live_clocks() == 0
	r.append({"name": "hiss_not_clock", "pass": ok})
	var hinc: float = float(events[0].incident)
	for i in range(int(ceil((hinc + 0.3) * 10.0))):
		tick(0.1)
	ok = ended == "" and token == 0 and _find_type("COMMS_HISS").is_empty()
	r.append({"name": "hiss_fade_no_kill", "pass": ok})

	reset(1)
	spawn_event("CONTACT_UNID")
	spawn_event("COMMS_HISS")
	ok = radar_contacts().size() == 1 and not _find_type("COMMS_HISS").is_empty()
	r.append({"name": "hiss_with_contact", "pass": ok})
	ack_first()
	ok = radar_contacts().is_empty() and not _find_type("COMMS_HISS").is_empty() and token == 0
	r.append({"name": "ack_skips_hiss", "pass": ok})

	reset(1)
	elapsed = 160.0
	mode = "HIGH"
	spawn_event("FILTER_CLOG")
	ok = live_clocks() == 1
	var before_sec := _security_contact_busy()
	# band 1, cap 1 — security must not spawn over mining
	spawn_cd = 0.0
	maybe_spawn(0.1)
	ok = not _find_type("FILTER_CLOG").is_empty() and live_clocks() == 1
	r.append({"name": "security_no_drown_mining", "pass": ok, "extra": str(events)})

	var failed: Array = []
	for x in r:
		if not x.pass:
			failed.append(x.name)
	return {"ok": failed.is_empty(), "results": r, "failed": failed}
