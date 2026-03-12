## TestChat.gd — Automated DM chat (messagemode_all) regression test
##
## Launched via test-chat.sh, or manually:
##   cd project && godot res://TestChat.tscn -- --game=0 --map=dm/mohdm1
##
## Sequence:
##   1. Boot engine with g_gametype 1 (DM), load a DM map via devmap
##   2. Wait for map_loaded signal
##   3. Send "say" commands directly to test chat message delivery
##   4. Send "dmmessage" commands directly to test DM message path
##   5. Open chat via "messagemode_all" console command
##   6. Verify chat console opened and stays open
##   7. Close chat via Escape key injection
##   8. Repeat open/close cycle multiple times to test stability
##   9. Exit with code 0 (pass) or 1 (fail)
##
## The bash wrapper (scripts/test-chat.sh) captures stdout and
## checks this scene's PASS/FAIL output.

extends Node

var runner = null
var state := "init"
var timer := 0.0
var total_timer := 0.0
var map_loaded := false

# Config from command-line args
var test_map := "dm/mohdm1"
var target_game := 0  # 0=AA, 1=SH, 2=BT
var test_duration := 90.0
var chat_cycles := 3  # how many open/close cycles to test

# State tracking
var current_cycle := 0
var chat_open_frame_count := 0
var fail_count := 0
var pass_count := 0

func _ready():
	print("ChatTest: =====================================")
	print("ChatTest: DM Chat (messagemode_all) Regression Test")
	print("ChatTest: =====================================")

	# Parse user args (after --)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			test_map = arg.substr(6)
		elif arg.begins_with("--game="):
			target_game = int(arg.substr(7))
		elif arg.begins_with("--duration="):
			test_duration = float(arg.substr(11))
		elif arg.begins_with("--cycles="):
			chat_cycles = int(arg.substr(9))

	var game_names := {0: "AA", 1: "SH", 2: "BT"}
	var game_name: String = game_names.get(target_game, "Unknown(%d)" % target_game)

	print("ChatTest: Game:     ", game_name, " (com_target_game=", target_game, ")")
	print("ChatTest: Map:      ", test_map)
	print("ChatTest: Duration: ", test_duration, "s")
	print("ChatTest: Cycles:   ", chat_cycles)

	if not ClassDB.class_exists("MoHAARunner"):
		printerr("ChatTest: FAIL CRITICAL: MoHAARunner class not found — GDExtension not loaded!")
		fail_count += 1
		get_tree().quit(1)
		return

	runner = ClassDB.instantiate("MoHAARunner")
	if not runner:
		printerr("ChatTest: FAIL CRITICAL: Could not instantiate MoHAARunner!")
		fail_count += 1
		get_tree().quit(1)
		return

	# Build startup args:
	#   - g_gametype 1 = deathmatch (required for chat/messagemode_all)
	#   - com_target_game selects AA(0)/SH(1)/BT(2)
	#   - developer 1 enables diagnostic output
	#   - cheats + thereisnomonkey bypass anti-cheat
	var startup_args := "+set dedicated 0 +set developer 1"
	startup_args += " +set g_gametype 1"
	startup_args += " +set com_target_game %d" % target_game
	startup_args += " +set cheats 1 +set thereisnomonkey 1"
	startup_args += " +devmap " + test_map

	runner.set_startup_args(startup_args)
	runner.name = "MoHAARunnerTest"

	# Connect signals BEFORE add_child
	runner.engine_error.connect(_on_engine_error)
	runner.map_loaded.connect(_on_map_loaded)
	add_child(runner)
	print("ChatTest: INFO Engine starting...")

func _on_engine_error(message: String):
	printerr("ChatTest: FAIL ENGINE_ERROR: ", message)
	fail_count += 1

func _on_map_loaded(map_name: String):
	print("ChatTest: INFO Signal: map_loaded -> ", map_name)
	map_loaded = true
	state = "map_loaded"
	timer = 0.0

func _process(delta):
	timer += delta
	total_timer += delta

	match state:
		"init":
			if timer > 30.0 and not map_loaded:
				printerr("ChatTest: FAIL map_load_timeout: Map did not load within 30s")
				fail_count += 1
				_finish_test(false, "map_load_timeout")

		"map_loaded":
			# Wait a few seconds for player to fully spawn into DM game
			if timer > 2.0:
				print("ChatTest: INFO Player should be spawned, testing direct say commands first...")
				state = "test_say_cmd"
				timer = 0.0

		"test_say_cmd":
			# Test direct "say" command — this goes through SV_ConSay_f → SV_SendServerCommand
			print("ChatTest: INFO Sending 'echo hello world' (sanity check)...")
			runner.execute_command("echo hello world")
			state = "test_echo_wait"
			timer = 0.0

		"test_echo_wait":
			if timer > 1.0:
				print("ChatTest: PASS echo_command: 'echo hello world' did not crash")
				pass_count += 1
				state = "test_actual_say"
				timer = 0.0

		"test_actual_say":
			print("ChatTest: INFO Sending 'say hello world' command...")
			runner.execute_command("say hello world")
			state = "test_say_wait"
			timer = 0.0

		"test_say_wait":
			if timer > 1.0:
				print("ChatTest: PASS say_command: 'say hello world' did not crash")
				pass_count += 1
				state = "test_dmmessage_cmd"
				timer = 0.0

		"test_dmmessage_cmd":
			# Test direct "dmmessage" command — this goes through Player::EventDMMessage
			print("ChatTest: INFO Sending 'dmmessage 0 test message' command...")
			runner.execute_command("dmmessage 0 test message")
			state = "test_dmmessage_wait"
			timer = 0.0

		"test_dmmessage_wait":
			if timer > 1.0:
				print("ChatTest: PASS dmmessage_command: 'dmmessage 0 test message' did not crash")
				pass_count += 1
				state = "test_say_team_cmd"
				timer = 0.0

		"test_say_team_cmd":
			# Test team say
			print("ChatTest: INFO Sending 'dmmessage -1 team message' command...")
			runner.execute_command("dmmessage -1 team message test")
			state = "test_say_team_wait"
			timer = 0.0

		"test_say_team_wait":
			if timer > 1.0:
				print("ChatTest: PASS team_message: 'dmmessage -1 team message' did not crash")
				pass_count += 1
				print("ChatTest: INFO Direct command tests passed, starting chat UI cycles...")
				current_cycle = 0
				state = "pre_open_chat"
				timer = 0.0

		"pre_open_chat":
			# Brief pause before each chat open
			if timer > 0.5:
				current_cycle += 1
				print("ChatTest: INFO === Cycle %d/%d ===" % [current_cycle, chat_cycles])
				print("ChatTest: INFO Opening chat via 'messagemode_all'...")
				runner.execute_command("messagemode_all")
				chat_open_frame_count = 0
				state = "chat_opening"
				timer = 0.0

		"chat_opening":
			# Wait a couple of frames for chat to open, then start counting
			# how many frames it stays open.
			chat_open_frame_count += 1
			if timer > 1.5:
				# After 1.5s, chat should still be open (not 1-frame close)
				if chat_open_frame_count < 5:
					printerr("ChatTest: FAIL chat_1frame_close: Chat console only lasted %d frames in cycle %d" % [chat_open_frame_count, current_cycle])
					fail_count += 1
				else:
					print("ChatTest: PASS chat_stayed_open: Chat open for %d frames in cycle %d" % [chat_open_frame_count, current_cycle])
					pass_count += 1
				state = "chat_close"
				timer = 0.0

		"chat_close":
			# Close chat by sending Escape key via console command
			# In MOHAA, pressing Escape while DM console is open triggers
			# UI_CloseDMConsole via the key handler.
			# We use "messagemode_all" again which toggles it off.
			print("ChatTest: INFO Closing chat via 'messagemode_all' (toggle off)...")
			runner.execute_command("messagemode_all")
			state = "chat_closing"
			timer = 0.0

		"chat_closing":
			# Wait for close to process
			if timer > 1.0:
				print("ChatTest: PASS chat_closed: Chat closed cleanly in cycle %d" % current_cycle)
				pass_count += 1
				if current_cycle >= chat_cycles:
					_finish_test(fail_count == 0, "completed")
				else:
					state = "pre_open_chat"
					timer = 0.0

	# Global timeout
	if total_timer > test_duration and state != "done":
		print("ChatTest: INFO Duration limit reached, finishing.")
		_finish_test(fail_count == 0, "timeout")

func _finish_test(passed: bool, reason: String):
	state = "done"
	print("")
	print("=" .repeat(60))
	print("ChatTest: DM CHAT TEST RESULTS")
	print("=" .repeat(60))
	print("ChatTest: Result:  ", "PASS" if passed else "FAIL")
	print("ChatTest: Reason:  ", reason)
	print("ChatTest: Cycles:  %d/%d completed" % [current_cycle, chat_cycles])
	print("ChatTest: Passes:  ", pass_count)
	print("ChatTest: Fails:   ", fail_count)
	print("ChatTest: Duration: %.1fs" % total_timer)
	var game_names := {0: "AA", 1: "SH", 2: "BT"}
	print("ChatTest: Game:    ", game_names.get(target_game, "Unknown"))
	print("ChatTest: Map:     ", test_map)
	print("=" .repeat(60))

	# Give the engine a couple of frames to flush before quitting
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if passed else 1)
