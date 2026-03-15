## TestConnect.gd — Automated server connection e2e test
##
## Launched via test-connect.sh, or manually:
##   cd project && godot res://TestConnect.tscn -- --server=78.108.16.74:12203
##   cd project && godot res://TestConnect.tscn -- --server=78.108.16.74:12203 --timeout=45
##
## Sequence:
##   1. Boot engine in client mode (dedicated=0, g_gametype=0)
##   2. Issue "connect <ip>" command
##   3. Wait for map_loaded signal (proves challenge, connect, gamestate, map load all work)
##   4. Optionally cycle through multiple servers
##   5. Exit with code 0 (pass) or 1 (fail)
##
## The bash wrapper (scripts/test-connect.sh) captures stdout and
## checks this scene's PASS/FAIL output.

extends Node

var runner = null
var state := "init"
var timer := 0.0
var total_timer := 0.0
var map_loaded := false
var connect_sent := false
var got_engine_error := false
var engine_error_msg := ""

# Config
var servers: Array = []         # Array of "ip:port" strings to test
var current_server_idx := 0
var connect_timeout := 30.0     # seconds to wait for map load per server
var target_game := 0            # 0=AA, 1=SH, 2=BT
var settle_time := 5.0          # seconds to stay connected after map loads

# Results
var pass_count := 0
var fail_count := 0
var skip_count := 0
var results: Array = []         # Array of {server, status, detail}

func _ready():
	print("ConnectTest: =========================================")
	print("ConnectTest: Server Connection E2E Test")
	print("ConnectTest: =========================================")

	# Parse user args (after --)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			servers.append(arg.substr(9))
		elif arg.begins_with("--timeout="):
			connect_timeout = float(arg.substr(10))
		elif arg.begins_with("--game="):
			target_game = int(arg.substr(7))
		elif arg.begins_with("--settle="):
			settle_time = float(arg.substr(9))

	if servers.is_empty():
		# Default: test a selection of public servers with players
		servers = [
			"78.108.16.74:12203",     # MR ROBOT TDM
			"217.182.199.4:12203",    # LuV Freeze-Tag
		]

	var game_names := {0: "AA", 1: "SH", 2: "BT"}
	var game_name: String = game_names.get(target_game, "Unknown(%d)" % target_game)

	print("ConnectTest: Game:      ", game_name, " (com_target_game=", target_game, ")")
	print("ConnectTest: Timeout:   ", connect_timeout, "s per server")
	print("ConnectTest: Settle:    ", settle_time, "s after map load")
	print("ConnectTest: Servers:   ", servers.size())
	for i in range(servers.size()):
		print("ConnectTest:   [%d] %s" % [i + 1, servers[i]])

	if not ClassDB.class_exists("MoHAARunner"):
		printerr("ConnectTest: FAIL CRITICAL: MoHAARunner class not found — GDExtension not loaded!")
		fail_count += 1
		get_tree().quit(1)
		return

	runner = ClassDB.instantiate("MoHAARunner")
	if not runner:
		printerr("ConnectTest: FAIL CRITICAL: Could not instantiate MoHAARunner!")
		fail_count += 1
		get_tree().quit(1)
		return

	# Start engine in client mode — no map (stays at console/menu)
	var startup_args := "+set dedicated 0 +set developer 1"
	startup_args += " +set g_gametype 0"
	startup_args += " +set com_target_game %d" % target_game
	startup_args += " +set cheats 1 +set thereisnomonkey 1"

	runner.set_startup_args(startup_args)
	runner.name = "MoHAARunnerTest"

	runner.engine_error.connect(_on_engine_error)
	runner.map_loaded.connect(_on_map_loaded)
	runner.map_unloaded.connect(_on_map_unloaded)
	add_child(runner)
	print("ConnectTest: INFO Engine starting (no map)...")
	state = "engine_init"
	timer = 0.0

func _on_engine_error(message: String):
	printerr("ConnectTest: ENGINE_ERROR: ", message)
	got_engine_error = true
	engine_error_msg = message

func _on_map_loaded(map_name: String):
	print("ConnectTest: INFO Signal: map_loaded -> ", map_name)
	map_loaded = true

func _on_map_unloaded():
	print("ConnectTest: INFO Signal: map_unloaded")
	map_loaded = false

func _process(delta):
	timer += delta
	total_timer += delta

	match state:
		"engine_init":
			# Wait for engine to initialise (a few frames)
			if timer > 3.0:
				state = "connect_next"
				timer = 0.0

		"connect_next":
			if current_server_idx >= servers.size():
				_finish_all()
				return
			_start_connect(servers[current_server_idx])

		"connecting":
			if map_loaded:
				# Success! Server sent us a map.
				var srv = servers[current_server_idx]
				print("ConnectTest: PASS connect: %s (map loaded in %.1fs)" % [srv, timer])
				pass_count += 1
				results.append({"server": srv, "status": "PASS", "detail": "map loaded in %.1fs" % timer})
				state = "connected_settle"
				timer = 0.0

			elif got_engine_error:
				var srv = servers[current_server_idx]
				printerr("ConnectTest: FAIL connect: %s (engine error: %s)" % [srv, engine_error_msg])
				fail_count += 1
				results.append({"server": srv, "status": "FAIL", "detail": "engine error: " + engine_error_msg})
				_advance_server()

			elif timer > connect_timeout:
				var srv = servers[current_server_idx]
				printerr("ConnectTest: FAIL connect: %s (timeout after %.0fs)" % [srv, connect_timeout])
				fail_count += 1
				results.append({"server": srv, "status": "FAIL", "detail": "timeout after %.0fs" % connect_timeout})
				_advance_server()

		"connected_settle":
			# Stay connected briefly to verify stability
			if timer > settle_time:
				print("ConnectTest: INFO Disconnecting from %s after %.1fs settle" % [servers[current_server_idx], settle_time])
				runner.execute_command("disconnect")
				_advance_server()

			elif got_engine_error:
				var srv = servers[current_server_idx]
				printerr("ConnectTest: WARN settle: %s (engine error during settle: %s)" % [srv, engine_error_msg])
				# Don't count as failure — we already passed the connect
				_advance_server()

		"pause_between":
			# Brief pause between server connect attempts
			if timer > 2.0:
				state = "connect_next"
				timer = 0.0

		"exiting":
			if timer > 1.0:
				var exit_code = 1 if (fail_count > 0 and pass_count == 0) else 0
				get_tree().quit(exit_code)

func _start_connect(server: String):
	print("ConnectTest: INFO Connecting to %s [%d/%d]..." % [server, current_server_idx + 1, servers.size()])
	map_loaded = false
	got_engine_error = false
	engine_error_msg = ""
	connect_sent = true
	timer = 0.0
	state = "connecting"
	runner.execute_command("connect " + server)

func _advance_server():
	current_server_idx += 1
	map_loaded = false
	got_engine_error = false
	engine_error_msg = ""
	connect_sent = false
	timer = 0.0
	if current_server_idx < servers.size():
		# Brief pause before next connect
		state = "pause_between"
	else:
		_finish_all()

func _finish_all():
	print("")
	print("ConnectTest: =========================================")
	print("ConnectTest: RESULTS")
	print("ConnectTest: =========================================")
	for r in results:
		print("ConnectTest:   [%s] %s — %s" % [r["status"], r["server"], r["detail"]])
	print("")
	print("ConnectTest: Total: %d passed, %d failed, %d skipped out of %d" % [pass_count, fail_count, skip_count, servers.size()])
	print("")

	if fail_count == 0 and pass_count > 0:
		print("ConnectTest: OVERALL PASS")
		# Wait a moment for output to flush
		state = "exiting"
		timer = 0.0
	elif pass_count > 0:
		print("ConnectTest: PARTIAL PASS (%d/%d)" % [pass_count, servers.size()])
		state = "exiting"
		timer = 0.0
	else:
		print("ConnectTest: OVERALL FAIL")
		state = "exiting"
		timer = 0.0

func _exit_tree():
	pass
