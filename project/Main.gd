extends Node

var runner = null

func _ready():
	print("Main: Script started.")
	if not ClassDB.class_exists("MoHAARunner"):
		printerr("Main: ERROR - Class 'MoHAARunner' not found in ClassDB. Extension might fail to load.")
		return
	
	print("Main: 'MoHAARunner' found in ClassDB.")
	runner = ClassDB.instantiate("MoHAARunner")

	if runner:
		runner.name = "MoHAARunnerInstance"
		add_child(runner)
		print("Main: MoHAARunner added to tree (dynamic).")
		
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
		print("Main: Engine is running, loading test map...")
		runner.load_map("DM/mohdm1")
		
		# Poll server status after giving the map time to load
		get_tree().create_timer(2.0).timeout.connect(_on_status_check)

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

func _on_map_unloaded():
	print("Main: SIGNAL map_unloaded")

func _on_engine_shutdown():
	print("Main: SIGNAL engine_shutdown_requested")

func _process(delta):
	pass
