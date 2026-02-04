extends Node

func _ready():
	print("Main: Script started.")
	if not ClassDB.class_exists("MoHAARunner"):
		printerr("Main: ERROR - Class 'MoHAARunner' not found in ClassDB. Extension might fail to load.")
		return
	
	print("Main: 'MoHAARunner' found in ClassDB.")
	var runner = ClassDB.instantiate("MoHAARunner") # Using instantiate if it's available, or just new()
	if not runner:
		# Fallback to standard instantiation if ClassDB returns null (usually for Objects, but Nodes should work)
		# Actually for GDScript registered classes:
		# runner = MoHAARunner.new()
		# But if it's not known at parse time, we might need a workaround?
		# If the extension loads, MoHAARunner IS known.
		pass
	
	# Try usage by name
	# runner = MoHAARunner.new()
	# runner.name = "MoHAARunnerInstance"
	# add_child(runner)
	# print("Main: MoHAARunner added to tree.")

	if runner:
		runner.name = "MoHAARunnerInstance"
		add_child(runner)
		print("Main: MoHAARunner added to tree (dynamic).")
	else:
		print("Main: Failed to instantiate MoHAARunner.")

func _process(delta):
	# The runner's _process should run automatically
	pass
