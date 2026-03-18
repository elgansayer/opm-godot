## ResourceSandboxManager.gd — Isolated .pck loading and unloading per server.
##
## Core challenge:  Godot's ProjectSettings.load_resource_pack() with
## replace_files=true modifies the virtual res:// filesystem for the entire
## session.  To prevent cross-server file pollution (Server A's custom pistol
## must not appear on Server B), this manager:
##
##   1. Loads all packs with replace_files=FALSE.  Mod-pack authors MUST
##      namespace their content under  res://mods/<pack_id>/  so that base
##      game paths are never shadowed.
##
##   2. Tracks every pack loaded per "session" (one server connection).
##      When the player disconnects, the session is invalidated and a new
##      session begins.  Any asset lookup via get_mod_resource() returns
##      only resources from the *active* session.
##
##   3. If a pack absolutely must override a base path (e.g. a retextured
##      weapon), the manager loads it with replace_files=true and records
##      the fact.  On session teardown it flags the engine for a soft
##      restart (re-exec the scene tree) so the base VFS is restored.
##
## Best practices for pack authors:
##   • Place all content under  res://mods/<unique_pack_id>/  inside the
##     .pck.  Example directory tree inside a pack:
##       res://mods/my_server_rocket_map/maps/v2_rocket.tscn
##       res://mods/my_server_rocket_map/models/pistol.glb
##   • Never place files at  res://maps/  or  res://models/  directly;
##     that would collide with the base game.
##   • The <unique_pack_id> should match the pack's SHA-256 prefix or
##     the server_id from the manifest to guarantee uniqueness.
##
## Usage (autoload singleton "ResourceSandboxManager"):
##   ResourceSandboxManager.begin_session("server-xyz")
##   ResourceSandboxManager.load_pack("user://cache/abc123.pck", "abc123")
##   var tex = ResourceSandboxManager.get_mod_resource("res://mods/abc123/icon.png")
##   ResourceSandboxManager.end_session()
extends Node

## Emitted when a session begins.
signal session_started(server_id: String)
## Emitted when a session ends and all packs are unloaded/invalidated.
signal session_ended(server_id: String)
## Emitted when the engine needs a soft restart to purge overridden base files.
signal soft_restart_required()

## Metadata about a loaded pack.
class PackInfo:
	var pack_id: String = ""
	var cache_path: String = ""
	var replaced_base: bool = false
	var resource_prefix: String = "" # e.g. "res://mods/abc123/"

var _active_session_id: String = ""
## Array[PackInfo] — packs loaded in the current session.
var _loaded_packs: Array = []
## Set of pack_ids loaded in *any* session this process lifetime.
## Used to detect when an already-loaded-with-replace pack would conflict.
var _ever_loaded: Dictionary = {} # { pack_id: true }
var _needs_restart: bool = false


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Start a new server session. Ends any prior session first.
func begin_session(server_id: String) -> void:
	if _active_session_id != "":
		end_session()
	_active_session_id = server_id
	_loaded_packs.clear()
	_needs_restart = false
	print("ResourceSandboxManager: Session started for server '", server_id, "'")
	session_started.emit(server_id)


## End the current session, invalidating all loaded packs.
## If any pack used replace_files=true, a soft restart is flagged.
func end_session() -> void:
	if _active_session_id == "":
		return

	var old_id := _active_session_id
	print("ResourceSandboxManager: Ending session for server '", old_id,
		"', packs=", _loaded_packs.size())

	# Godot has no API to *unload* a resource pack at runtime.  For packs
	# loaded with replace_files=false under res://mods/<id>/ we simply stop
	# referencing them — the paths remain accessible in res:// but game code
	# only accesses them through get_mod_resource(), which checks session.
	#
	# For packs that replaced base files we must restart to restore clean VFS.
	var replaced_any := false
	for info in _loaded_packs:
		if info is PackInfo and info.replaced_base:
			replaced_any = true
			break

	_loaded_packs.clear()
	_active_session_id = ""
	session_ended.emit(old_id)

	if replaced_any:
		_needs_restart = true
		print("ResourceSandboxManager: Soft restart required (base files were overridden).")
		soft_restart_required.emit()


## Load a .pck from the cache into the current session.
##
## [param cache_path]   Absolute user:// path to the .pck file.
## [param pack_id]      Unique identifier (typically the SHA-256 hash prefix).
## [param replace_base] If true, loads with replace_files=true (dangerous).
##                      Defaults to false (safe, namespaced).
## Returns true on success.
func load_pack(cache_path: String, pack_id: String, replace_base: bool = false) -> bool:
	if _active_session_id == "":
		push_warning("ResourceSandboxManager: No active session — call begin_session() first.")
		return false

	if not FileAccess.file_exists(cache_path):
		push_warning("ResourceSandboxManager: Pack not found: ", cache_path)
		return false

	# If this pack was already loaded with replace=true in a previous session,
	# a restart is needed before it can be loaded differently.
	if _ever_loaded.has(pack_id) and replace_base:
		push_warning("ResourceSandboxManager: Pack '", pack_id,
			"' was previously loaded — restart to re-load with replace_base=true.")
		return false

	var ok := ProjectSettings.load_resource_pack(cache_path, replace_base)
	if not ok:
		push_warning("ResourceSandboxManager: load_resource_pack failed for ", cache_path)
		return false

	var info := PackInfo.new()
	info.pack_id = pack_id
	info.cache_path = cache_path
	info.replaced_base = replace_base
	info.resource_prefix = "res://mods/" + pack_id + "/"
	_loaded_packs.append(info)
	_ever_loaded[pack_id] = true

	print("ResourceSandboxManager: Loaded pack '", pack_id, "' replace_base=", replace_base)
	return true


## Convenience: load all required packs for a manifest (after downloading).
## Returns true when every required pack loaded successfully.
func load_manifest_packs(manifest: Dictionary) -> bool:
	var cache: Node = _get_cache_manager()
	if cache == null:
		push_warning("ResourceSandboxManager: CacheManager not found.")
		return false

	var server_id: String = manifest.get("server_id", "unknown")
	begin_session(server_id)

	var all_ok := true
	for res_entry in manifest.get("resources", []):
		if not res_entry is Dictionary:
			continue
		var sha: String = res_entry.get("sha256", "").to_lower()
		if sha == "":
			continue
		var path: String = cache.get_cached_path(sha)
		var pack_id: String = sha.left(16) # first 16 hex chars as namespace
		if not load_pack(path, pack_id):
			if res_entry.get("required", true):
				all_ok = false

	return all_ok


## Load a resource from the active session's mod namespace.
## Falls back to the base game path if not found in any loaded pack.
##
## Example:
##   get_mod_resource("maps/v2_rocket.tscn")
##   → tries res://mods/<pack_id>/maps/v2_rocket.tscn for each loaded pack
##   → falls back to res://maps/v2_rocket.tscn
func get_mod_resource(relative_path: String) -> Resource:
	if _active_session_id != "":
		for info in _loaded_packs:
			if not info is PackInfo:
				continue
			var full_path: String = info.resource_prefix + relative_path
			if ResourceLoader.exists(full_path):
				return ResourceLoader.load(full_path)

	# Fallback to base game.
	var base_path := "res://" + relative_path
	if ResourceLoader.exists(base_path):
		return ResourceLoader.load(base_path)
	return null


## Check whether a mod resource exists in the active session.
func has_mod_resource(relative_path: String) -> bool:
	if _active_session_id != "":
		for info in _loaded_packs:
			if not info is PackInfo:
				continue
			var full_path: String = info.resource_prefix + relative_path
			if ResourceLoader.exists(full_path):
				return true
	return false


## True when a previous session loaded packs with replace_base=true and a
## scene-tree restart is needed to clean the VFS.
func needs_restart() -> bool:
	return _needs_restart


## Return the active server session id (empty when no session).
func get_active_session_id() -> String:
	return _active_session_id


## Return list of pack ids currently loaded in this session.
func get_loaded_pack_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for info in _loaded_packs:
		if info is PackInfo:
			ids.append(info.pack_id)
	return ids


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_cache_manager() -> Node:
	if Engine.has_singleton("CacheManager"):
		return Engine.get_singleton("CacheManager")
	return get_node_or_null("/root/CacheManager")
