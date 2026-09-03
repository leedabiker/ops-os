extends RefCounted

var root: Dictionary = {}
var cwd: String = "/"


func reset(token: String) -> void:
	cwd = "/"
	root = {
		"kind": "dir",
		"children": {
			"var": {
				"kind": "dir",
				"children": {
					"log": {
						"kind": "dir",
						"children": {
							"shift": {
								"kind": "dir",
								"children": _shift_files(token),
							}
						}
					}
				}
			}
		}
	}


func _shift_files(token: String) -> Dictionary:
	var files := {
		"00-boot.log": _boot(),
		"cell-a.log": _cell_a(),
		"cell-b.log": _cell_b(),
		"belt.log": _belt(),
		"filter.log": _filter(),
		"pump-2.log": _pump(),
		"fence.log": _fence(),
		"radar.log": _radar(),
		"comms.log": _comms(),
		"hiss.log": _hiss(),
		"shift.log": _shift(),
		"maint.log": _maint(),
	}
	var hosts := ["cell-a.log", "cell-b.log", "belt.log", "pump-2.log", "fence.log", "radar.log", "comms.log", "hiss.log"]
	var host: String = hosts[abs(token.hash()) % hosts.size()]
	var live := "03:12:44  pump-2   INTERLOCK %s  issued" % token
	files[host] = str(files[host]).strip_edges() + "\n" + live + "\n"
	var out := {}
	for name in files:
		out[name] = {"kind": "file", "body": files[name]}
	return out


func _norm(path: String) -> String:
	if path == "":
		return cwd
	var abs_path := path
	if not path.begins_with("/"):
		if cwd == "/":
			abs_path = "/" + path
		else:
			abs_path = cwd + "/" + path
	var parts: Array = []
	for p in abs_path.split("/"):
		if p == "" or p == ".":
			continue
		if p == "..":
			if parts.size() > 0:
				parts.pop_back()
			continue
		parts.append(p)
	if parts.is_empty():
		return "/"
	return "/" + "/".join(parts)


func _node(path: String) -> Dictionary:
	var n := root
	if path == "/":
		return n
	for p in path.substr(1).split("/"):
		if n.is_empty() or n.kind != "dir":
			return {}
		if not n.children.has(p):
			return {}
		n = n.children[p]
	return n


func pwd() -> String:
	return cwd


func ls(path: String = "") -> Variant:
	var p := _norm(path) if path != "" else cwd
	var n := _node(p)
	if n.is_empty():
		return null
	if n.kind != "dir":
		return null
	var names: Array = n.children.keys()
	names.sort()
	return names


func cd(path: String) -> bool:
	var p := _norm(path)
	var n := _node(p)
	if n.is_empty() or n.kind != "dir":
		return false
	cwd = p
	return true


func cat(path: String) -> Variant:
	var p := _norm(path)
	var n := _node(p)
	if n.is_empty() or n.kind != "file":
		return null
	return str(n.body)


func grep(pattern: String, path: String = "") -> Array:
	var p := _norm(path) if path != "" else cwd
	var n := _node(p)
	var hits: Array = []
	if n.is_empty():
		return hits
	if n.kind == "file":
		for line in str(n.body).split("\n"):
			if pattern in line:
				hits.append(line)
		return hits
	for name in n.children.keys():
		var child: Dictionary = n.children[name]
		if child.kind != "file":
			continue
		for line in str(child.body).split("\n"):
			if pattern in line:
				hits.append(line)
	return hits


func exec(line: String) -> Array:
	line = line.strip_edges()
	if line == "":
		return []
	var parts := line.split(" ", false)
	if parts.is_empty():
		return []
	var cmd: String = parts[0]
	var args: Array = parts.slice(1)
	if cmd == "pwd":
		return [pwd()]
	if cmd == "ls":
		var names = ls(str(args[0]) if args.size() > 0 else "")
		if names == null:
			return ["?"]
		return names
	if cmd == "cd":
		if args.is_empty():
			return ["?"]
		if not cd(args[0]):
			return ["?"]
		return []
	if cmd == "cat":
		if args.is_empty():
			return ["?"]
		var body = cat(str(args[0]))
		if body == null:
			return ["?"]
		var lines: Array = str(body).split("\n")
		if lines.size() > 0 and lines[lines.size() - 1] == "":
			lines.pop_back()
		return lines
	if cmd == "grep":
		if args.is_empty():
			return ["?"]
		var pat: String = str(args[0])
		var gp: String = args[1] if args.size() > 1 else ""
		return grep(pat, gp)
	return ["?"]


func _boot() -> String:
	return """00:00:01  boot     site online
00:00:01  boot     workspaces 3
00:00:02  boot     apps: term radar cam power mining repair
00:00:03  boot     miner SAFE
00:00:04  boot     radar tier 0
00:00:05  cell-a   online  1.00
00:00:05  cell-b   online  1.00
00:00:06  pump-2   primed
00:00:07  belt     idle
00:00:08  fence    loop closed
00:00:09  boot     INTERLOCK superseded
00:00:10  boot     shift start
00:00:12  boot     remote session 1
00:00:14  boot     no local crew
"""


func _cell_a() -> String:
	return """00:00:05  cell-a   online
00:04:10  cell-a   V 48.1  I 12.0  T 31
00:11:22  cell-a   V 47.9  I 12.4  T 33
00:18:40  cell-a   V 47.6  I 13.1  T 36
00:26:02  cell-a   V 47.4  I 13.8  T 38
00:33:11  cell-a   V 47.1  I 14.6  T 41
00:41:00  cell-a   V 46.8  I 15.2  T 44
00:48:19  cell-a   ripple 0.04  ignore
00:55:07  cell-a   V 46.6  I 15.9  T 46
01:02:44  cell-a   V 46.3  I 16.4  T 49
01:10:12  cell-a   balancer ok
01:18:30  cell-a   V 46.1  I 16.8  T 51
01:25:00  cell-a   balancer ok
01:33:18  cell-a   V 45.9  I 17.1  T 53
"""


func _cell_b() -> String:
	return """00:00:05  cell-b   online
00:05:00  cell-b   V 48.0  I 11.8  T 30
00:12:14  cell-b   V 47.8  I 12.2  T 32
00:20:01  cell-b   V 47.7  I 12.9  T 35
00:27:40  cell-b   V 47.5  I 13.5  T 37
00:35:22  cell-b   V 47.2  I 14.1  T 40
00:42:08  cell-b   V 47.0  I 14.7  T 42
00:50:55  cell-b   balancer ok
00:58:13  cell-b   V 46.8  I 15.3  T 45
01:06:41  cell-b   V 46.5  I 15.8  T 47
01:14:09  cell-b   V 46.4  I 16.2  T 49
01:21:33  cell-b   ripple 0.03  ignore
01:29:00  cell-b   V 46.2  I 16.6  T 50
01:36:47  cell-b   V 46.0  I 17.0  T 52
"""


func _belt() -> String:
	return """00:00:07  belt     idle
00:02:00  belt     run HIGH
00:08:11  belt     load 0.41  slip 0.00
00:15:04  belt     load 0.44  slip 0.00
00:22:40  belt     load 0.48  slip 0.01
00:29:18  belt     tracking ok
00:36:02  belt     load 0.51  slip 0.01
00:43:55  belt     load 0.53  slip 0.02
00:51:12  belt     idler 4  warm
00:58:30  belt     load 0.56  slip 0.02
01:05:08  belt     load 0.58  slip 0.03
01:12:44  belt     tracking ok
01:20:01  belt     load 0.61  slip 0.03
01:27:19  belt     tracking ok
"""


func _filter() -> String:
	return """00:01:10  filter   dP 0.20  clean
00:07:22  filter   dP 0.24
00:14:00  filter   dP 0.31
00:21:18  filter   dP 0.38
00:28:40  filter   pulse  ok
00:35:05  filter   dP 0.44
00:42:11  filter   dP 0.51
00:49:33  filter   dP 0.58
00:56:02  filter   pulse  ok
01:03:40  filter   dP 0.66
01:10:15  filter   dP 0.72
01:17:48  filter   dP 0.79
01:24:22  filter   dP 0.84
01:40:11  filter   INTERLOCK pending
"""


func _pump() -> String:
	return """00:00:06  pump-2   primed
00:03:12  pump-2   run  1480 rpm  41
00:09:40  pump-2   run  1480 rpm  43
00:16:05  pump-2   run  1492 rpm  46
00:23:18  pump-2   seal  ok
00:30:00  pump-2   run  1492 rpm  49
00:37:44  pump-2   run  1501 rpm  52
00:44:10  pump-2   run  1501 rpm  54
00:51:33  pump-2   seal  ok
00:58:02  pump-2   run  1510 rpm  57
01:05:19  pump-2   run  1510 rpm  59
01:12:40  pump-2   vibration 0.02  ignore
01:19:08  pump-2   run  1518 rpm  61
"""


func _fence() -> String:
	return """00:00:08  fence    loop closed
00:06:00  fence    sector 1-4  quiet
00:13:22  fence    sector 2  glitch  40ms  cleared
00:20:10  fence    loop closed
00:27:41  fence    sector 3  quiet
00:34:05  fence    sector 1-4  quiet
00:41:18  fence    sector 4  glitch  12ms  cleared
00:48:00  fence    loop closed
00:55:33  fence    sector 2  quiet
01:02:14  fence    sector 1-4  quiet
01:09:50  fence    loop closed
01:16:07  fence    sector 3  glitch  8ms  cleared
01:23:29  fence    loop closed
01:30:00  fence    loop closed
"""


func _radar() -> String:
	return """00:00:04  radar    tier 0
00:04:40  radar    sweep  ok  contacts 0
00:11:02  radar    sweep  ok  contacts 0
00:18:15  radar    sweep  ok  contacts 1  dropped
00:25:00  radar    sweep  ok  contacts 0
00:32:22  radar    gain  max
00:39:10  radar    sweep  ok  contacts 0
00:46:41  radar    sweep  ok  contacts 2  dropped
00:53:08  radar    sweep  ok  contacts 0
01:00:30  radar    classification  unavailable
01:07:12  radar    sweep  ok  contacts 0
01:14:44  radar    sweep  ok  contacts 1  dropped
01:21:01  radar    sweep  ok  contacts 0
01:28:19  radar    sweep  ok  contacts 0
"""


func _comms() -> String:
	return """00:01:00  comms    uplink  ok
00:08:14  comms    uplink  ok  ping 640ms
00:15:02  comms    uplink  ok  ping 710ms
00:22:40  comms    crc  0
00:29:11  comms    uplink  ok  ping 680ms
00:36:33  comms    uplink  ok  ping 820ms
00:43:05  comms    crc  1  ignored
00:50:22  comms    uplink  ok  ping 760ms
00:57:40  comms    uplink  ok  ping 900ms
01:04:08  comms    crc  0
01:11:51  comms    uplink  ok  ping 840ms
01:18:14  comms    hiss  burst  2s
01:25:00  comms    uplink  ok  ping 700ms
01:32:22  comms    crc  0
"""


func _hiss() -> String:
	return """00:10:00  hiss     floor  -41 dB
00:17:12  hiss     floor  -40 dB
00:24:40  hiss     floor  -42 dB
00:31:05  hiss     burst  -28 dB  1.2s
00:38:18  hiss     floor  -41 dB
00:45:00  hiss     floor  -39 dB
00:52:22  hiss     burst  -30 dB  0.8s
00:59:10  hiss     floor  -41 dB
01:06:33  hiss     floor  -40 dB
01:13:48  hiss     burst  -27 dB  2.0s
01:20:01  hiss     floor  -42 dB
01:27:14  hiss     floor  -41 dB
01:34:00  hiss     floor  -41 dB
01:41:22  hiss     floor  -40 dB
"""


func _shift() -> String:
	return """00:00:10  shift    start
00:00:12  shift    operator  remote
00:00:14  shift    crew     none
00:12:00  shift    mode SAFE
00:40:00  shift    mode HIGH
01:10:00  shift    materials  +
01:40:00  shift    energy    ok
02:10:00  shift    mode HIGH
02:40:00  shift    materials  +
03:10:00  shift    energy    ok
03:40:00  shift    mode MAX
04:02:18  shift    INTERLOCK check skipped
04:10:00  shift    clock  running
04:40:00  shift    producing
"""


func _maint() -> String:
	return """00:02:00  maint    last local  11d
00:20:00  maint    filter  pulse schedule  auto
00:40:00  maint    belt    idler 4  watch
01:00:00  maint    pump-2  seal  ok
01:20:00  maint    cell-a  ripple  ignore
01:40:00  maint    cell-b  ripple  ignore
02:00:00  maint    fence   loop  closed
02:11:00  maint    INTERLOCK void (auto-cleared)
02:20:00  maint    radar   tier 0  expected
02:40:00  maint    comms   ping high  expected
03:00:00  maint    no spare  on site
03:20:00  maint    repair  remote only
03:40:00  maint    next local  unscheduled
04:00:00  maint    idle
"""
