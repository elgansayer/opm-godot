extends Node

var runner = null
var screenshot_pending = false
var screenshot_timer = 0.0
const SCREENSHOT_DELAY = 1.5  # seconds after map load to take screenshot
var launch_map = "obj/obj_team4"
var launch_dedicated = false
var launch_menu = ""

func _ready():
	print("Main: Script started.")
	if not ClassDB.class_exists("MoHAARunner"):
		printerr("Main: ERROR - Class 'MoHAARunner' not found in ClassDB. Extension might fail to load.")
		return
	
	print("Main: 'MoHAARunner' found in ClassDB.")
	runner = ClassDB.instantiate("MoHAARunner")

	# Optional runtime args:
	#   --dedicated       Launch dedicated server mode
	#   --client          Force client mode
	#   --map=<mapname>   Startup map (default: obj/obj_team4)
	#   --menu=<name>     Push a specific UI menu after startup (e.g. multiplayerstart)
	#   --nodev           Disable developer mode
	#   --dev             Enable developer mode (console toggle with ~)
	var user_args = OS.get_cmdline_user_args()
	var dev_mode = false
	for arg in user_args:
		if arg == "--dedicated":
			launch_dedicated = true
		elif arg == "--client":
			launch_dedicated = false
		elif arg.begins_with("--map="):
			launch_map = arg.substr(6)
		elif arg.begins_with("--menu="):
			launch_menu = arg.substr(7)
		elif arg == "--nodev":
			dev_mode = false
		elif arg == "--dev":
			dev_mode = true

	if runner:
		var startup_args = "+set dedicated %d +set developer %d" % [1 if launch_dedicated else 0, 1 if dev_mode else 0]
		runner.set_startup_args(startup_args)
		runner.name = "MoHAARunnerInstance"
		add_child(runner)
		print("Main: MoHAARunner added to tree (dynamic).")
		print("Main: Startup args -> ", startup_args)
		print("Main: Startup map  -> ", launch_map)
		if launch_menu != "":
			print("Main: Startup menu -> ", launch_menu)
		
		# Connect signals (Task 2.5.4)
		runner.engine_error.connect(_on_engine_error)
		runner.map_loaded.connect(_on_map_loaded)
		runner.map_unloaded.connect(_on_map_unloaded)
		runner.engine_shutdown_requested.connect(_on_engine_shutdown)
		
		# Try loading a map after a short delay to let the engine settle
		get_tree().create_timer(0.5).timeout.connect(_on_load_timer)
	else:
		print("Main: Failed to instantiate MoHAARunner.")

func _on_load_timer():
	if runner and runner.is_engine_initialized():
		print("Main: Engine is running. Main menu should be visible.")
		if launch_menu != "":
			if launch_menu == "mpoptions":
				runner.execute_command("ui_getplayermodel")
				print("Main: Executed -> ui_getplayermodel")
			runner.execute_command("pushmenu " + launch_menu)
			print("Main: Executed -> pushmenu ", launch_menu)
			get_tree().create_timer(0.75).timeout.connect(func(): take_screenshot("menu_" + launch_menu))
		# The engine auto-pushes the main menu on startup via CL_TryStartIntro().
		# Use runner.execute_command("pushmenu main") if menu needs to be re-opened.
		# Use runner.load_map("mapname") to load a specific map.

func _on_status_check():
	if runner and runner.is_engine_initialized():
		print("Main: --- Server Status ---")
		print("  Map loaded: ", runner.is_map_loaded())
		print("  Current map: ", runner.get_current_map())
		print("  Player count: ", runner.get_player_count())
		print("  Server state: ", runner.get_server_state_string(), " (", runner.get_server_state(), ")")

# ── Signal handlers (Task 2.5.4) ──

func _on_engine_error(message: String):
	printerr("Main: ENGINE ERROR: ", message)

func _on_map_loaded(map_name: String):
	print("Main: SIGNAL map_loaded -> ", map_name)
	# Cursor mode is now managed automatically by MoHAARunner.update_input_routing()
	# based on the engine's keyCatcher state (UI/console/gameplay).
	# Schedule auto-screenshot
	screenshot_pending = true
	screenshot_timer = 0.0
	print("Main: Screenshot scheduled in ", SCREENSHOT_DELAY, "s")

func _on_map_unloaded():
	print("Main: SIGNAL map_unloaded")
	# Cursor mode is managed automatically by update_input_routing()

func _on_engine_shutdown():
	print("Main: SIGNAL engine_shutdown_requested")

func _unhandled_key_input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
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

func _process(delta):
	# Auto-screenshot after map load delay
	if screenshot_pending:
		screenshot_timer += delta
		if screenshot_timer >= SCREENSHOT_DELAY:
			screenshot_pending = false
			take_screenshot("auto")

func take_screenshot(label: String):
	var img = get_viewport().get_texture().get_image()
	if img:
		var path = "/tmp/godot_screenshot_" + label + ".png"
		var err = img.save_png(path)
		if err == OK:
			print("Main: Screenshot saved -> ", path, " (", img.get_width(), "x", img.get_height(), ")")
		else:
			printerr("Main: Screenshot save failed: ", err)
	else:
		printerr("Main: Could not get viewport image")
