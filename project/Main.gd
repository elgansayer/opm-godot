extends Node

var runner = null
var screenshot_pending = false
var screenshot_timer = 0.0
const SCREENSHOT_DELAY = 1.5  # seconds after map load to take screenshot
var status_log_timer = 0.0
var launch_dedicated = false
# launch_map: empty = start at main menu; set via --map= or ?map= URL param
var launch_map = ""
# exec_cfg: exec this config at startup (e.g. "server.cfg" loads its map)
var exec_cfg = ""
var last_state_logged = -999
var web_net_tweaks_applied = false  # DEPRECATED: kept for compat, no longer used

func _ready():
	print("Main: Script started.")
	if not ClassDB.class_exists("MoHAARunner"):
		printerr("Main: ERROR - Class 'MoHAARunner' not found in ClassDB. Extension might fail to load.")
		return

	print("Main: 'MoHAARunner' found in ClassDB.")
	runner = ClassDB.instantiate("MoHAARunner")

	# Parse command-line args (after --):
	#   --dedicated      Launch as dedicated server
	#   --client         Force client mode
	#   --map=<name>     Startup map override
	#   --exec=<cfg>     Exec config at startup (e.g. --exec=server.cfg)
	#   --server         Shorthand for --exec=server.cfg
	#   --dev / --nodev  Toggle developer mode
	#   +connect <ip>    Connect to a server (forwarded to engine)
	#   +<cmd> [args]    Any Quake-style +command forwarded to the engine
	var user_args = OS.get_cmdline_user_args()
	var dev_mode = false
	var extra_engine_cmds = ""  # raw +command args forwarded to engine
	var in_plus_cmd = false     # true while collecting args for a +command
	for arg in user_args:
		if arg == "--dedicated":
			launch_dedicated = true
			in_plus_cmd = false
		elif arg == "--client":
			launch_dedicated = false
			in_plus_cmd = false
		elif arg.begins_with("--map="):
			launch_map = arg.substr(6)
			in_plus_cmd = false
		elif arg.begins_with("--exec="):
			exec_cfg = arg.substr(7)
			in_plus_cmd = false
		elif arg == "--server":
			exec_cfg = "server.cfg"
			in_plus_cmd = false
		elif arg == "--nodev":
			dev_mode = false
			in_plus_cmd = false
		elif arg == "--dev":
			dev_mode = true
			in_plus_cmd = false
		elif arg.begins_with("+"):
			# Quake-style +command -- forward directly to engine
			# e.g. "+connect" "127.0.0.1" arrives as two separate user args
			extra_engine_cmds += " " + arg
			in_plus_cmd = true
		elif in_plus_cmd:
			# Value-arg following a +command (e.g. the IP in "+connect <ip>")
			extra_engine_cmds += " " + arg
			# A new +command resets this; bare args "consume" one token only
			in_plus_cmd = false

	# On web: also read URL query params
	# e.g. http://localhost:8086/mohaa.html\?map\=dm/mohdm1
	#       http://localhost:8086/mohaa.html\?server\=1   (exec server.cfg)
	if OS.has_feature("web"):
		var url_params = _parse_url_params()
		if url_params.has("map"):
			launch_map = url_params["map"]
		if url_params.has("exec"):
			exec_cfg = url_params["exec"]
		if url_params.has("server") and url_params["server"] == "1":
			exec_cfg = "server.cfg"
		if url_params.has("dedicated") and url_params["dedicated"] == "1":
			launch_dedicated = true
		if url_params.has("connect"):
			extra_engine_cmds += " +connect " + url_params["connect"]
		if url_params.has("relay"):
			# WebSocket relay: store host:port only (no ws:// — engine parser
			# treats // as comment). C code prepends ws:// at connect time.
			var relay_val = url_params["relay"].replace("ws://", "").replace("wss://", "")
			extra_engine_cmds += " +set net_ws_relay " + relay_val
		else:
			# Auto-default: relay runs on same host as web server, port 12300
			var relay_url = _auto_relay_url()
			if relay_url != "":
				extra_engine_cmds += " +set net_ws_relay " + relay_url
				print("Main: Auto-detected relay URL -> ", relay_url)

	if runner:
		var startup_args = "+set dedicated %d +set developer %d" % [
			1 if launch_dedicated else 0,
			1 if dev_mode else 0
		]
		if OS.has_feature("web"):
			# Web: emscripten VFS root = game data dir; GameSpy off
			startup_args += " +set fs_basepath . +set fs_homedatapath . +set fs_homepath . +set r_fullscreen 0 +set ui_gamespy 0 +set sv_gamespy 0"

		# Startup command: exec config takes priority over direct +map
		if exec_cfg != "":
			startup_args += " +exec " + exec_cfg
		elif launch_map != "":
			startup_args += " +map " + launch_map
		# else: no startup command -> engine shows main menu

		# Append any raw +command args forwarded from user args (e.g. +connect <ip>)
		if extra_engine_cmds != "":
			startup_args += extra_engine_cmds

		runner.set_startup_args(startup_args)
		runner.name = "MoHAARunnerInstance"
		add_child(runner)
		print("Main: MoHAARunner added to tree.")
		print("Main: Startup args -> ", startup_args)
		if exec_cfg != "":
			print("Main: Exec cfg -> ", exec_cfg)
		elif extra_engine_cmds != "":
			print("Main: Extra engine cmds -> ", extra_engine_cmds.strip_edges())
		elif launch_map != "":
			print("Main: Startup map -> ", launch_map)
		else:
			print("Main: Starting at main menu (no auto-map).")

		runner.engine_error.connect(_on_engine_error)
		runner.map_loaded.connect(_on_map_loaded)
		runner.map_unloaded.connect(_on_map_unloaded)
		runner.engine_shutdown_requested.connect(_on_engine_shutdown)
	else:
		print("Main: Failed to instantiate MoHAARunner.")

# Parse URL query string into a dictionary (web only).
func _parse_url_params() -> Dictionary:
	var result = {}
	if not OS.has_feature("web"):
		return result
	var query = ""
	if Engine.has_singleton("JavaScriptBridge"):
		var js = Engine.get_singleton("JavaScriptBridge")
		if js:
			var q = js.eval("window.location.search")
			if typeof(q) == TYPE_STRING:
				query = q
	if query.begins_with("?"):
		query = query.substr(1)
	for pair in query.split("&"):
		var kv = pair.split("=", true, 2)
		if kv.size() == 2:
			result[kv[0].uri_decode()] = kv[1].uri_decode()
		elif kv.size() == 1 and kv[0] != "":
			result[kv[0]] = "1"
	return result

# Auto-detect relay host:port from the current page hostname (web only).
# Returns host:port only (no ws:// prefix — the engine command parser treats
# // as a comment delimiter). C code prepends ws:// at connect time.
func _auto_relay_url() -> String:
	if not Engine.has_singleton("JavaScriptBridge"):
		return ""
	var js = Engine.get_singleton("JavaScriptBridge")
	if not js:
		return ""
	var hostname = js.eval("window.location.hostname")
	if typeof(hostname) != TYPE_STRING or hostname == "":
		return ""
	return hostname + ":12300"

# -- Signal handlers --

func _on_engine_error(message: String):
	printerr("Main: ENGINE ERROR: ", message)

func _on_map_loaded(map_name: String):
	print("Main: SIGNAL map_loaded -> ", map_name)
	screenshot_pending = true
	screenshot_timer = 0.0
	print("Main: Screenshot scheduled in ", SCREENSHOT_DELAY, "s")

func _on_map_unloaded():
	print("Main: SIGNAL map_unloaded")

func _on_engine_shutdown():
	print("Main: SIGNAL engine_shutdown_requested")

func _unhandled_key_input(event: InputEvent):
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	if event.is_action("toggle_mouse_capture"):
		if runner:
			var captured = runner.is_mouse_captured()
			runner.set_mouse_captured(not captured)
			print("Main: Mouse capture toggled -> ", not captured)
	elif event.is_action("screenshot"):
		take_screenshot("manual")
	elif event.is_action("toggle_hud"):
		if runner:
			runner.set_hud_visible(not runner.is_hud_visible())
			print("Main: HUD toggled -> ", runner.is_hud_visible())
	elif event.is_action("toggle_fullscreen"):
		var mode = DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		print("Main: Fullscreen toggled")
	elif event.keycode == KEY_F10:
		# F10 -- exec server.cfg (listen server: host + play on dm/mohdm1)
		if runner and runner.is_engine_initialized():
			runner.execute_command("exec server.cfg; set ui_gamespy 0; set sv_gamespy 0")
			print("Main: Executed -> exec server.cfg; set ui_gamespy 0; set sv_gamespy 0")
	elif event.keycode == KEY_F11:
		# F11 -- connect to localhost as pure client (join local server)
		if runner and runner.is_engine_initialized():
			runner.execute_command("connect localhost")
			print("Main: Executed -> connect localhost")

func _process(delta):
	# One-time GameSpy re-disable for web (in case engine reset the cvars)
	if OS.has_feature("web") and runner and runner.is_engine_initialized() and not web_net_tweaks_applied:
		web_net_tweaks_applied = true
		runner.execute_command("set ui_gamespy 0; set sv_gamespy 0")
		print("Main: Web tweaks applied -> ui_gamespy=0 sv_gamespy=0")

	if screenshot_pending:
		screenshot_timer += delta
		if screenshot_timer >= SCREENSHOT_DELAY:
			screenshot_pending = false
			take_screenshot("auto")

	if runner and runner.is_engine_initialized():
		var server_state = runner.get_server_state()
		if server_state != last_state_logged:
			last_state_logged = server_state
			print("Main: server_state -> ", runner.get_server_state_string(),
				" (", server_state, ")")

		status_log_timer += delta
		if status_log_timer >= 5.0:
			status_log_timer = 0.0
			print("Main: Status state=", runner.get_server_state_string(),
				" map=", runner.get_current_map(),
				" players=", runner.get_player_count())

func take_screenshot(label: String):
	var img = get_viewport().get_texture().get_image()
	if img:
		var path = "/tmp/godot_screenshot_" + label + ".png"
		var err = img.save_png(path)
		if err == OK:
			print("Main: Screenshot saved -> ", path,
" (", img.get_width(), "x", img.get_height(), ")")
		else:
			printerr("Main: Screenshot save failed: ", err)
	else:
		printerr("Main: Could not get viewport image")
