## TestMapRotation.gd — Automated map rotation stress test
##
## Launched via scripts/test-map-rotation.sh, or manually:
##   cd project && godot res://TestMapRotation.tscn -- --rotations=10
##
## Sequence:
##   1. Boot engine, load first map (devmap)
##   2. Wait for map_loaded signal
##   3. Send devmap to second map
##   4. Wait for map_loaded signal
##   5. Repeat N rotations
##   6. Exit with code 0 (pass) or 1 (fail)

extends Node

var runner = null
var map_a := "dm/mohdm1"
var map_b := "dm/mohdm2"
var num_rotations := 10
var timeout_per_map := 120.0

var state := "init"
var timer := 0.0
var current_rotation := 0
var waiting_for_map := ""
var loaded_map := ""

func _ready():
	print("MapRotationTest: ======================================")
	print("MapRotationTest: Map rotation stress test")
	print("MapRotationTest: ======================================")

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map-a="):
			map_a = arg.substr(8)
		elif arg.begins_with("--map-b="):
			map_b = arg.substr(8)
		elif arg.begins_with("--rotations="):
			num_rotations = int(arg.substr(12))
		elif arg.begins_with("--timeout="):
			timeout_per_map = float(arg.substr(10))

	print("MapRotationTest: Map A: ", map_a)
	print("MapRotationTest: Map B: ", map_b)
	print("MapRotationTest: Rotations: ", num_rotations)
	print("MapRotationTest: Timeout per map: ", timeout_per_map, "s")

	if not ClassDB.class_exists("MoHAARunner"):
		printerr("MapRotationTest: CRITICAL: MoHAARunner class not found!")
		get_tree().quit(1)
		return

	runner = ClassDB.instantiate("MoHAARunner")
	if not runner:
		printerr("MapRotationTest: CRITICAL: Failed to instantiate MoHAARunner!")
		get_tree().quit(1)
		return

	var startup_args = "+set dedicated 0 +set developer 1 +set cheats 1 +set thereisnomonkey 1 +set g_gametype 0 +devmap %s" % map_a
	runner.set_startup_args(startup_args)
	runner.name = "MoHAARunnerInstance"
	add_child(runner)

	runner.map_loaded.connect(_on_map_loaded)
	runner.engine_error.connect(_on_engine_error)

	state = "wait_first"
	waiting_for_map = map_a
	timer = 0.0
	print("MapRotationTest: Loading first map: ", map_a)

func _on_map_loaded(map_name: String):
	print("MapRotationTest: map_loaded signal -> ", map_name)
	loaded_map = map_name

func _on_engine_error(message: String):
	printerr("MapRotationTest: ENGINE ERROR: ", message)
	print("MapRotationTest: FAIL — engine error during rotation ", current_rotation)
	get_tree().quit(1)

func _process(delta):
	timer += delta

	match state:
		"wait_first":
			if loaded_map != "":
				print("MapRotationTest: First map loaded: ", loaded_map)
				_start_next_rotation()
			elif timer > timeout_per_map:
				printerr("MapRotationTest: FAIL — timeout waiting for first map")
				get_tree().quit(1)

		"wait_rotation":
			if loaded_map == waiting_for_map:
				print("MapRotationTest: Rotation %d/%d OK — loaded %s" % [current_rotation, num_rotations, loaded_map])
				if current_rotation >= num_rotations:
					print("MapRotationTest: ======================================")
					print("MapRotationTest: PASS — %d map rotations successful" % num_rotations)
					print("MapRotationTest: ======================================")
					get_tree().quit(0)
				else:
					_start_next_rotation()
			elif timer > timeout_per_map:
				printerr("MapRotationTest: FAIL — timeout on rotation %d waiting for %s" % [current_rotation, waiting_for_map])
				get_tree().quit(1)

func _start_next_rotation():
	current_rotation += 1
	var next_map = map_b if (current_rotation % 2) == 1 else map_a
	waiting_for_map = next_map
	loaded_map = ""
	timer = 0.0
	state = "wait_rotation"
	print("MapRotationTest: Rotation %d/%d: sending devmap %s" % [current_rotation, num_rotations, next_map])
	runner.execute_command("devmap " + next_map)
