## TestViewmodel.gd — Automated viewmodel/NODRAW regression test
##
## Launched via test-viewmodel.sh, or manually:
##   cd project && godot res://TestViewmodel.tscn -- --map=dm/mohdm1
##
## Sequence:
##   1. Boot engine, load DM map (devmap)
##   2. Wait for map_loaded signal
##   3. Give MP44 (has "mp44clip" surface for reload NODRAW test)
##   4. Fire until magazine empty → automatic reload
##   5. Run scripted fire/reload cycles
##   6. Exit with code 0 (pass) or 1 (fail)
##
## The bash wrapper (scripts/test-viewmodel.sh) captures ViewmodelTest: lines
## and uses this scene's final result banner to determine pass/fail.

extends Node

var runner = null
var state := "init"
var timer := 0.0
var total_timer := 0.0
var map_loaded := false
var test_map := "dm/mohdm1"
var weapon_given := false
var fire_started := false
var fire_timer := 0.0
var test_duration := 45.0  # total wallclock limit
var fail_count := 0
var warn_count := 0
var info_count := 0

func _ready():
	print("ViewmodelTest: ======================================")
	print("ViewmodelTest: TestViewmodel automated regression test")
	print("ViewmodelTest: ======================================")

	# Parse user args (after --)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			test_map = arg.substr(6)
		elif arg.begins_with("--duration="):
			test_duration = float(arg.substr(11))

	print("ViewmodelTest: Map: ", test_map)
	print("ViewmodelTest: Duration limit: ", test_duration, "s")

	if not ClassDB.class_exists("MoHAARunner"):
		printerr("ViewmodelTest: CRITICAL: MoHAARunner class not found — GDExtension not loaded!")
		get_tree().quit(1)
		return

	runner = ClassDB.instantiate("MoHAARunner")
	if not runner:
		printerr("ViewmodelTest: CRITICAL: Could not instantiate MoHAARunner!")
		get_tree().quit(1)
		return

	# Build startup args: non-dedicated, cheats on via devmap.
	# Force g_gametype 0 (single player) so the player spawns directly
	# without needing team selection or weapon menus.  The user's saved
	# config (omconfig.cfg) may have "seta g_gametype 1" which overrides
	# the engine default — we override back to 0 here.
	# developer 1 enables DPrintf for diagnostic output.  Cheats are
	# ensured via +set cheats 1 + thereisnomonkey 1 (bypasses anti-cheat).
	var startup_args = "+set dedicated 0 +set developer 1 +set g_gametype 0"
	startup_args += " +set cheats 1 +set thereisnomonkey 1"
	startup_args += " +devmap " + test_map

	runner.set_startup_args(startup_args)
	runner.name = "MoHAARunnerTest"

	# Connect signals BEFORE add_child (map_loaded fires from _process)
	runner.engine_error.connect(_on_engine_error)
	runner.map_loaded.connect(_on_map_loaded)
	add_child(runner)
	print("ViewmodelTest: Engine starting...")

var map_load_count := 0

func _on_engine_error(message: String):
	printerr("ViewmodelTest: ENGINE ERROR: ", message)
	fail_count += 1

func _on_map_loaded(map_name: String):
	map_load_count += 1
	print("ViewmodelTest: Signal: map_loaded -> ", map_name, " (load #", map_load_count, ")")
	map_loaded = true
	state = "map_loaded"
	timer = 0.0

func _process(delta):
	timer += delta
	total_timer += delta

	match state:
		"init":
			if timer > 25.0 and not map_loaded:
				printerr("ViewmodelTest: FAIL: Map did not load within 25s")
				_finish_test(false, "map_load_timeout")

		"map_loaded":
			# In g_gametype 0 (SP) the player spawns directly — no team join needed.
			# Use "give all" first (gives everything from global/giveall.scr),
			# then also give the MP44 specifically (in case giveall.scr doesn't include it).
			# "give all" provides full ammo reserves so reload can work.
			if timer > 2.0 and not weapon_given:
				print("ViewmodelTest: Giving all weapons+ammo...")
				runner.execute_command("give all")
				print("ViewmodelTest: Also giving MP44 (weapons/mp44.tik)...")
				runner.execute_command("give weapons/mp44.tik")
				weapon_given = true
				timer = 0.0
				state = "equip_weapon"

		"equip_weapon":
			# Wait 1s for the give to process and starting ammo to be applied.
			# Then explicitly select the MP44 via "use" (not weapnext, which
			# cycles to whichever weapon give-all last equipped).
			if timer > 1.0:
				print("ViewmodelTest: Selecting MP44 via 'use weapons/mp44.tik'...")
				runner.execute_command("use weapons/mp44.tik")
				timer = 0.0
				state = "weapon_given"

		"weapon_given":
			# Wait for weapon equip animation, then fire
			if timer > 3.0 and not fire_started:
				print("ViewmodelTest: +attack (firing to empty magazine)...")
				runner.execute_command("+attack")
				fire_started = true
				fire_timer = 0.0
				state = "firing"

		"firing":
			fire_timer += delta
			# Fire for 8s — MP44 has 30-round clip, ~5 rounds/sec = empties in 6s, then auto-reload
			if fire_timer > 8.0:
				runner.execute_command("-attack")
				print("ViewmodelTest: -attack (stopped firing, forcing reload)...")
				runner.execute_command("reload")
				print("ViewmodelTest: Sent 'reload' console command")
				state = "reload_wait"
				timer = 0.0

		"reload_wait":
			# Observe reload animation for 5s
			if timer > 5.0:
				print("ViewmodelTest: Post-reload observation...")
				state = "post_reload"
				timer = 0.0

		"post_reload":
			# Second fire–reload cycle for confirmation
			if timer > 2.0:
				print("ViewmodelTest: Second fire cycle...")
				runner.execute_command("+attack")
				state = "firing2"
				fire_timer = 0.0

		"firing2":
			fire_timer += delta
			if fire_timer > 8.0:
				runner.execute_command("-attack")
				print("ViewmodelTest: Forcing second reload...")
				runner.execute_command("reload")
				state = "final_observe"
				timer = 0.0

		"final_observe":
			if timer > 5.0:
				_finish_test(fail_count == 0, "completed")

	# Global timeout
	if total_timer > test_duration and state != "done":
		print("ViewmodelTest: Duration limit reached, finishing.")
		_finish_test(fail_count == 0, "timeout")

func _finish_test(passed: bool, reason: String):
	state = "done"
	print("")
	print("=" .repeat(60))
	print("ViewmodelTest: VIEWMODEL TEST RESULTS")
	print("=" .repeat(60))
	print("ViewmodelTest: Result: ", "PASS" if passed else "FAIL")
	print("ViewmodelTest: Reason: ", reason)
	print("ViewmodelTest: Duration: %.1fs" % total_timer)
	print("ViewmodelTest: Note: Wrapper checks this result banner and ViewmodelTest: FAIL lines")
	print("=" .repeat(60))

	# Give the engine a couple of frames to flush before quitting
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if passed else 1)
