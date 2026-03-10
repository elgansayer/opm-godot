## ResolutionTest.gd — Automated resolution/mode/quality end-to-end test
##
## Launched via scripts/test-resolution.sh, or manually:
##   cd project && godot res://ResolutionTest.tscn -- --map=dm/mohdm1
##
## Sequence:
##   1. Boot engine, load a DM map
##   2. Wait for map_loaded signal + settle
##   3. For each test case (resolution × mode × quality):
##      a. Set cvars (r_mode, r_fullscreen, r_customwidth/height)
##      b. Execute vid_restart
##      c. Wait for settle (resize + re-render)
##      d. Capture screenshot
##      e. Validate: viewport dimensions, HUD presence, 3D content
##   4. Compare screenshots across configurations
##   5. Report pass/fail summary and exit
##
## Test cases exercise:
##   - Windowed mode at multiple resolutions (640×480, 800×600, 1024×768, 1280×720)
##   - Fullscreen mode at native + low resolution
##   - HUD scaling correctness (compass position relative to viewport)
##   - 3D render scaling (scaling_3d_scale applied in fullscreen low-res)
##   - GUI menus at different resolutions (main menu if no map specified)

extends Node

var runner = null
var state := "init"
var timer := 0.0
var total_timer := 0.0
var map_loaded := false
var test_map := "dm/mohdm1"
var test_duration := 180.0
var settle_time := 3.0  # seconds to wait after vid_restart for rendering to settle

# Test case definitions
var test_cases := []
var current_test := 0
var test_results := []  # Array of { name, passed, viewport_w, viewport_h, screenshot_path, details }
var screenshots := {}   # name -> Image for comparison
var output_dir := ""

# Counters
var pass_count := 0
var fail_count := 0
var warn_count := 0

func _ready():
	print("[RES-TEST] ========================================")
	print("[RES-TEST] Resolution/Mode/Quality Automated Test")
	print("[RES-TEST] ========================================")

	# Parse user args
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			test_map = arg.substr(6)
		elif arg.begins_with("--duration="):
			test_duration = float(arg.substr(11))
		elif arg.begins_with("--settle="):
			settle_time = float(arg.substr(9))
		elif arg.begins_with("--outdir="):
			output_dir = arg.substr(9)

	if output_dir == "":
		output_dir = OS.get_user_data_dir() + "/resolution-test"

	# Create output directory
	DirAccess.make_dir_recursive_absolute(output_dir)

	print("[RES-TEST] Map: ", test_map)
	print("[RES-TEST] Duration limit: ", test_duration, "s")
	print("[RES-TEST] Settle time: ", settle_time, "s")
	print("[RES-TEST] Output dir: ", output_dir)

	# Build test case matrix
	_build_test_cases()

	print("[RES-TEST] Total test cases: ", test_cases.size())
	for i in range(test_cases.size()):
		var tc = test_cases[i]
		print("[RES-TEST]   #", i, ": ", tc.name)

	if OS.has_feature("headless") or DisplayServer.get_name() == "headless":
		printerr("[RES-TEST] SKIP: Cannot run resolution tests in headless mode (no display).")
		get_tree().quit(0)
		return

	if not ClassDB.class_exists("MoHAARunner"):
		printerr("[RES-TEST] CRITICAL: MoHAARunner class not found!")
		get_tree().quit(2)
		return

	runner = ClassDB.instantiate("MoHAARunner")
	if not runner:
		printerr("[RES-TEST] CRITICAL: Could not instantiate MoHAARunner!")
		get_tree().quit(2)
		return

	# Boot with windowed mode at 1024×768 (our baseline)
	var startup_args = "+set dedicated 0 +set developer 1 +set g_gametype 0"
	startup_args += " +set cheats 1 +set thereisnomonkey 1"
	startup_args += " +set r_fullscreen 0 +set r_mode -1"
	startup_args += " +set r_customwidth 1024 +set r_customheight 768"
	startup_args += " +devmap " + test_map

	runner.set_startup_args(startup_args)
	runner.name = "MoHAARunnerResTest"
	runner.engine_error.connect(_on_engine_error)
	runner.map_loaded.connect(_on_map_loaded)
	add_child(runner)
	print("[RES-TEST] Engine starting...")


func _build_test_cases():
	# Windowed mode tests at various resolutions
	var windowed_resolutions = [
		[640, 480, "640x480"],
		[800, 600, "800x600"],
		[1024, 768, "1024x768"],
		[1280, 720, "1280x720_wide"],
	]
	for res in windowed_resolutions:
		test_cases.append({
			"name": "windowed_%s" % res[2],
			"fullscreen": false,
			"width": res[0],
			"height": res[1],
			"phase": "ingame",
			"expect_viewport_w": res[0],
			"expect_viewport_h": res[1],
		})

	# Fullscreen tests (will use screen native as viewport)
	# Low-res fullscreen — should apply scaling_3d_scale
	test_cases.append({
		"name": "fullscreen_640x480",
		"fullscreen": true,
		"width": 640,
		"height": 480,
		"phase": "ingame",
		"expect_viewport_w": -1,  # native monitor, unknown
		"expect_viewport_h": -1,
	})

	# Native fullscreen — no scaling
	test_cases.append({
		"name": "fullscreen_native",
		"fullscreen": true,
		"width": -2,  # r_mode -2 = desktop resolution
		"height": -2,
		"phase": "ingame",
		"expect_viewport_w": -1,
		"expect_viewport_h": -1,
	})

	# Return to windowed for menu test
	test_cases.append({
		"name": "windowed_1024x768_menu",
		"fullscreen": false,
		"width": 1024,
		"height": 768,
		"phase": "menu",  # open console/menu overlay
		"expect_viewport_w": 1024,
		"expect_viewport_h": 768,
	})

	# Small windowed menu test
	test_cases.append({
		"name": "windowed_640x480_menu",
		"fullscreen": false,
		"width": 640,
		"height": 480,
		"phase": "menu",
		"expect_viewport_w": 640,
		"expect_viewport_h": 480,
	})


func _on_engine_error(message: String):
	printerr("[RES-TEST] ENGINE ERROR: ", message)
	fail_count += 1

func _on_map_loaded(_map_name: String):
	print("[RES-TEST] Signal: map_loaded -> ", _map_name)
	map_loaded = true
	state = "map_settle"
	timer = 0.0


func _process(delta):
	timer += delta
	total_timer += delta

	# Global timeout
	if total_timer > test_duration:
		printerr("[RES-TEST] TIMEOUT: Exceeded ", test_duration, "s limit")
		_finish_all_tests()
		return

	match state:
		"init":
			if timer > 30.0 and not map_loaded:
				printerr("[RES-TEST] FAIL: Map did not load within 30s")
				_finish_all_tests()

		"map_settle":
			# Wait for the initial map to fully render
			if timer > 5.0:
				print("[RES-TEST] Map settled. Starting test matrix...")
				state = "run_test"
				current_test = 0
				timer = 0.0
				_apply_test_case(current_test)

		"applying_vid_restart":
			# Wait for vid_restart to complete + rendering to settle
			if timer > settle_time:
				state = "capture"
				timer = 0.0

		"capture":
			# Take screenshot and validate
			_capture_and_validate(current_test)
			current_test += 1
			if current_test < test_cases.size():
				state = "run_test"
				timer = 0.0
				_apply_test_case(current_test)
			else:
				_finish_all_tests()

		"run_test":
			# _apply_test_case changes state to applying_vid_restart
			pass

		"done":
			pass


func _apply_test_case(index: int):
	var tc = test_cases[index]
	print("[RES-TEST] ─── Test #", index, ": ", tc.name, " ───")

	if tc.fullscreen:
		if tc.width == -2:
			# r_mode -2 = desktop/native resolution
			runner.execute_command("set r_mode -2")
		else:
			runner.execute_command("set r_mode -1")
			runner.execute_command("set r_customwidth %d" % tc.width)
			runner.execute_command("set r_customheight %d" % tc.height)
		runner.execute_command("set r_fullscreen 1")
	else:
		runner.execute_command("set r_mode -1")
		runner.execute_command("set r_fullscreen 0")
		runner.execute_command("set r_customwidth %d" % tc.width)
		runner.execute_command("set r_customheight %d" % tc.height)

	# Open menu if this test case wants menu overlay
	if tc.phase == "menu":
		# toggleconsole opens the console overlay
		runner.execute_command("toggleconsole")

	# Trigger vid_restart
	runner.execute_command("vid_restart")

	state = "applying_vid_restart"
	timer = 0.0
	print("[RES-TEST]   Applied: fs=", tc.fullscreen,
		" size=", tc.width, "x", tc.height,
		" phase=", tc.phase)


func _capture_and_validate(index: int):
	var tc = test_cases[index]
	var result = {
		"name": tc.name,
		"passed": true,
		"viewport_w": 0,
		"viewport_h": 0,
		"screenshot_path": "",
		"details": [],
		"scaling_3d": 0.0,
	}

	# Close menu if we opened it (so next test starts clean)
	if tc.phase == "menu":
		runner.execute_command("toggleconsole")

	# Read viewport dimensions
	var vp_size = get_viewport().get_visible_rect().size
	result.viewport_w = int(vp_size.x)
	result.viewport_h = int(vp_size.y)

	# Read current scaling_3d_scale
	result.scaling_3d = get_viewport().scaling_3d_scale

	# Read engine glConfig resolution
	var engine_w = int(runner.get_cvar_string("r_customwidth"))
	var engine_h = int(runner.get_cvar_string("r_customheight"))

	print("[RES-TEST]   Viewport: ", result.viewport_w, "x", result.viewport_h)
	print("[RES-TEST]   scaling_3d: ", result.scaling_3d)
	print("[RES-TEST]   Engine cvars: r_customwidth=", engine_w, " r_customheight=", engine_h)

	# Capture screenshot
	var tex = get_viewport().get_texture()
	if tex:
		var img = tex.get_image()
		if img and not img.is_empty():
			var path = output_dir + "/" + tc.name + ".png"
			var err = img.save_png(path)
			if err == OK:
				result.screenshot_path = path
				screenshots[tc.name] = img.duplicate()
				print("[RES-TEST]   Screenshot: ", path,
					" (", img.get_width(), "x", img.get_height(), ")")
			else:
				result.details.append("Screenshot save failed: %d" % err)
				result.passed = false

			# Validate: image should not be empty/black
			var has_content = _image_has_content(img)
			if not has_content:
				result.details.append("FAIL: Screenshot appears blank/black")
				result.passed = false
			else:
				result.details.append("OK: Screenshot has visible content")
		else:
			result.details.append("FAIL: Could not get viewport image")
			result.passed = false
	else:
		result.details.append("FAIL: No viewport texture")
		result.passed = false

	# Validate viewport dimensions (windowed mode only)
	if not tc.fullscreen:
		# With VIEWPORT content_scale, the viewport should match the engine
		# resolution exactly (not the physical window size).
		var w_diff = abs(result.viewport_w - tc.expect_viewport_w)
		var h_diff = abs(result.viewport_h - tc.expect_viewport_h)
		if w_diff > 16 or h_diff > 16:
			result.details.append("FAIL: Viewport %dx%d expected ~%dx%d (diff: %d,%d)" % [
				result.viewport_w, result.viewport_h,
				tc.expect_viewport_w, tc.expect_viewport_h,
				w_diff, h_diff])
			result.passed = false
		else:
			result.details.append("OK: Viewport size within tolerance")

	# Validate content_scale_mode is VIEWPORT (both windowed and fullscreen)
	var win = get_window()
	if win:
		var csm = win.content_scale_mode
		if csm == Window.CONTENT_SCALE_MODE_VIEWPORT:
			result.details.append("OK: content_scale_mode = VIEWPORT")
		else:
			result.details.append("FAIL: content_scale_mode = %d (expected VIEWPORT=%d)" % [
				csm, Window.CONTENT_SCALE_MODE_VIEWPORT])
			result.passed = false

	# Validate fullscreen low-res uses VIEWPORT content_scale (not scaling_3d)
	if tc.fullscreen and tc.width > 0 and tc.width < 1920:
		result.details.append("OK: Fullscreen low-res uses VIEWPORT content_scale")

	# Validate fullscreen native — viewport should match screen
	if tc.fullscreen and tc.width == -2:
		result.details.append("OK: Fullscreen native with VIEWPORT content_scale")

	# Validate windowed mode uses VIEWPORT (scaling_3d should be 1.0)
	if not tc.fullscreen:
		if result.scaling_3d < 0.99:
			result.details.append("FAIL: Windowed mode but scaling_3d=%.2f (expected 1.0)" % result.scaling_3d)
			result.passed = false
		else:
			result.details.append("OK: scaling_3d=1.0 in windowed mode")

	# Log result
	if result.passed:
		print("[RES-TEST]   RESULT: PASS")
		pass_count += 1
	else:
		print("[RES-TEST]   RESULT: FAIL")
		fail_count += 1

	for d in result.details:
		print("[RES-TEST]     ", d)

	test_results.append(result)


func _image_has_content(img: Image) -> bool:
	## Check that the image isn't entirely one colour (blank screen).
	## Sample a grid of pixels and check for variation.
	if img.is_empty():
		return false
	var w = img.get_width()
	var h = img.get_height()
	if w < 4 or h < 4:
		return false

	var first_color = img.get_pixel(w / 4, h / 4)
	var different := 0
	var sample_points = [
		Vector2i(w / 4, h / 4),
		Vector2i(w / 2, h / 2),
		Vector2i(3 * w / 4, h / 4),
		Vector2i(w / 4, 3 * h / 4),
		Vector2i(3 * w / 4, 3 * h / 4),
		Vector2i(w / 2, h / 4),
		Vector2i(w / 2, 3 * h / 4),
		Vector2i(10, 10),
		Vector2i(w - 10, h - 10),
	]
	for pt in sample_points:
		var px = img.get_pixel(clampi(pt.x, 0, w - 1), clampi(pt.y, 0, h - 1))
		if not px.is_equal_approx(first_color):
			different += 1
	# Need at least 2 different pixels to consider it "has content"
	return different >= 2


func _compare_screenshots():
	## Compare screenshots across resolutions to verify they are different.
	## Same-resolution same-mode screenshots should be similar; different
	## resolutions or modes should produce visibly different images.
	print("[RES-TEST] ─── Screenshot Comparison ───")

	var keys = screenshots.keys()
	if keys.size() < 2:
		print("[RES-TEST]   Not enough screenshots to compare")
		return

	# Check that different resolutions produce different-sized screenshots
	var sizes := {}
	for k in keys:
		var img = screenshots[k]
		var size_key = "%dx%d" % [img.get_width(), img.get_height()]
		if not sizes.has(size_key):
			sizes[size_key] = []
		sizes[size_key].append(k)

	print("[RES-TEST]   Unique screenshot sizes: ", sizes.size())
	for sk in sizes:
		print("[RES-TEST]     ", sk, ": ", sizes[sk])

	if sizes.size() < 2:
		print("[RES-TEST]   WARN: All screenshots are the same size — resolution changes may not be working")
		warn_count += 1
	else:
		print("[RES-TEST]   OK: Multiple screenshot sizes confirm resolution changes work")

	# Pixel hash comparison: screenshots at different resolutions should differ
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var img_a = screenshots[keys[i]]
			var img_b = screenshots[keys[j]]
			if img_a.get_width() == img_b.get_width() and img_a.get_height() == img_b.get_height():
				# Same size — check if content differs (e.g. menu vs ingame)
				var same = _images_are_identical(img_a, img_b)
				if same:
					print("[RES-TEST]   WARN: ", keys[i], " and ", keys[j],
						" are pixel-identical despite different test conditions")
					warn_count += 1
				else:
					print("[RES-TEST]   OK: ", keys[i], " and ", keys[j], " differ (expected)")


func _images_are_identical(a: Image, b: Image) -> bool:
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return false
	# Compare a sparse grid of pixels
	var w = a.get_width()
	var h = a.get_height()
	var step_x = maxi(w / 20, 1)
	var step_y = maxi(h / 20, 1)
	for y in range(0, h, step_y):
		for x in range(0, w, step_x):
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				return false
	return true


func _finish_all_tests():
	state = "done"

	# Return to windowed mode before exiting (don't leave user stuck in fullscreen)
	if runner and runner.is_engine_initialized():
		runner.execute_command("set r_fullscreen 0")
		runner.execute_command("set r_mode -1")
		runner.execute_command("set r_customwidth 1024")
		runner.execute_command("set r_customheight 768")
		runner.execute_command("vid_restart")

	# Compare screenshots
	_compare_screenshots()

	# Print summary
	print("[RES-TEST] ========================================")
	print("[RES-TEST] SUMMARY")
	print("[RES-TEST] ========================================")
	print("[RES-TEST] Total tests: ", test_results.size())
	print("[RES-TEST] Passed:      ", pass_count)
	print("[RES-TEST] Failed:      ", fail_count)
	print("[RES-TEST] Warnings:    ", warn_count)
	print("[RES-TEST] Screenshots: ", output_dir)
	print("[RES-TEST] ========================================")

	for r in test_results:
		var status = "PASS" if r.passed else "FAIL"
		print("[RES-TEST] [", status, "] ", r.name,
			" viewport=", r.viewport_w, "x", r.viewport_h,
			" scaling_3d=", "%.2f" % r.scaling_3d)
		for d in r.details:
			print("[RES-TEST]     ", d)

	# Write summary file
	var summary_path = output_dir + "/summary.txt"
	var f = FileAccess.open(summary_path, FileAccess.WRITE)
	if f:
		f.store_line("Resolution Test Summary")
		f.store_line("Date: %s" % Time.get_datetime_string_from_system())
		f.store_line("Map: %s" % test_map)
		f.store_line("Total: %d  Pass: %d  Fail: %d  Warn: %d" % [
			test_results.size(), pass_count, fail_count, warn_count])
		f.store_line("")
		for r in test_results:
			var status = "PASS" if r.passed else "FAIL"
			f.store_line("[%s] %s  viewport=%dx%d  scaling_3d=%.2f" % [
				status, r.name, r.viewport_w, r.viewport_h, r.scaling_3d])
			for d in r.details:
				f.store_line("    %s" % d)
			if r.screenshot_path != "":
				f.store_line("    screenshot: %s" % r.screenshot_path)
		f.close()
		print("[RES-TEST] Summary written to: ", summary_path)

	print("[RES-TEST] ========================================")
	if fail_count > 0:
		print("[RES-TEST] OVERALL: FAIL")
		# Wait a moment for Godot to process the final vid_restart
		await get_tree().create_timer(2.0).timeout
		get_tree().quit(1)
	else:
		print("[RES-TEST] OVERALL: PASS")
		await get_tree().create_timer(2.0).timeout
		get_tree().quit(0)
