## MapDownloader.gd — Asynchronous HTTP download manager with integrity checks.
##
## Accepts a list of resource entries (from the manifest) and downloads any
## files that are not already present in the CacheManager. Downloads are queued
## and processed one at a time to avoid saturating the connection.
##
## Signals:
##   download_started(resource)          — A single file download has begun.
##   download_progress(resource, pct)    — Progress update for current file.
##   download_completed(resource)        — A single file downloaded & verified.
##   download_failed(resource, reason)   — A single file failed.
##   all_downloads_finished(success)     — Queue fully processed.
##
## Usage (autoload singleton "MapDownloader"):
##   MapDownloader.enqueue(resource_list)  # Array[Dictionary]
##   MapDownloader.all_downloads_finished.connect(_on_done)
extends Node

signal download_started(resource: Dictionary)
signal download_progress(resource: Dictionary, percent: float)
signal download_completed(resource: Dictionary)
signal download_failed(resource: Dictionary, reason: String)
signal all_downloads_finished(success: bool)

const DOWNLOAD_TIMEOUT := 120.0 # seconds per file
const MAX_RETRIES := 2
const CHUNK_REPORT_INTERVAL := 0.25 # seconds between progress signals

var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _downloading: bool = false
var _retry_count: int = 0
var _had_failure: bool = false
var _http: HTTPRequest = null
var _progress_timer: float = 0.0
var _download_path: String = "" # temp path while downloading


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = DOWNLOAD_TIMEOUT
	_http.use_threads = not OS.has_feature("web")
	# Download to a temp file first; rename on success.
	_http.download_chunk_size = 65536
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Add resources to the download queue. Entries already in the cache are
## skipped automatically.
func enqueue(resources: Array) -> void:
	var cache: Node = _get_cache_manager()
	for res_entry in resources:
		if not res_entry is Dictionary:
			continue
		var sha: String = res_entry.get("sha256", "").to_lower()
		if sha == "":
			continue
		if cache and cache.has_file(sha) and cache.verify_file(sha):
			print("MapDownloader: Already cached — ", res_entry.get("name", sha))
			continue
		_queue.append(res_entry)

	if not _downloading and not _queue.is_empty():
		_process_next()


## Cancel all pending downloads and clear the queue.
func cancel_all() -> void:
	_queue.clear()
	if _downloading:
		_http.cancel_request()
		_downloading = false
		_cleanup_temp()
	print("MapDownloader: All downloads cancelled.")


## True when there are downloads in progress or queued.
func is_busy() -> bool:
	return _downloading or not _queue.is_empty()


# ---------------------------------------------------------------------------
# Queue processing
# ---------------------------------------------------------------------------

func _process_next() -> void:
	if _queue.is_empty():
		_downloading = false
		all_downloads_finished.emit(not _had_failure)
		_had_failure = false
		return

	_current = _queue.pop_front()
	_retry_count = 0
	_start_download()


func _start_download() -> void:
	_downloading = true
	_progress_timer = 0.0
	var sha: String = _current.get("sha256", "")
	_download_path = "user://cache/_downloading_" + sha + ".tmp"

	# Godot's HTTPRequest can write directly to a file.
	_http.download_file = _download_path

	var url: String = _current.get("url", "")
	print("MapDownloader: Downloading ", _current.get("name", "?"), " from ", url)
	download_started.emit(_current)

	var err := _http.request(url)
	if err != OK:
		var reason := "HTTPRequest.request() failed: error %d" % err
		_handle_failure(reason)


func _process(delta: float) -> void:
	if not _downloading:
		return
	_progress_timer += delta
	if _progress_timer >= CHUNK_REPORT_INTERVAL:
		_progress_timer = 0.0
		var body_size := _http.get_body_size()
		var downloaded := _http.get_downloaded_bytes()
		if body_size > 0:
			var pct := clampf(float(downloaded) / float(body_size) * 100.0, 0.0, 100.0)
			download_progress.emit(_current, pct)


# ---------------------------------------------------------------------------
# HTTP response
# ---------------------------------------------------------------------------

func _on_http_completed(result: int, response_code: int,
		_headers: PackedStringArray, _body: PackedByteArray) -> void:
	_http.download_file = "" # stop writing

	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_failure("HTTP result %d" % result)
		return

	if response_code < 200 or response_code >= 300:
		_handle_failure("HTTP %d" % response_code)
		return

	# --- Integrity check ---------------------------------------------------
	var sha_expected: String = _current.get("sha256", "").to_lower()
	var sha_actual := _sha256_of_file(_download_path)

	if sha_actual != sha_expected:
		_handle_failure("Hash mismatch: expected %s, got %s" % [sha_expected, sha_actual])
		return

	# Move temp file to its final cache location.
	var cache: Node = _get_cache_manager()
	var final_path: String = ""
	if cache:
		final_path = cache.get_cached_path(sha_expected)
	else:
		final_path = "user://cache/" + sha_expected + ".pck"

	# Ensure cache dir exists.
	if not DirAccess.dir_exists_absolute("user://cache/"):
		DirAccess.make_dir_recursive_absolute("user://cache/")

	# Remove previous copy if any, then rename temp.
	if FileAccess.file_exists(final_path):
		DirAccess.remove_absolute(final_path)
	var rename_err := DirAccess.rename_absolute(_download_path, final_path)
	if rename_err != OK:
		_handle_failure("Could not move temp to cache: error %d" % rename_err)
		return

	# Register in cache.
	if cache:
		var original_name: String = _current.get("name", sha_expected)
		var size_bytes: int = _current.get("size", 0)
		cache.register_file(sha_expected, original_name, size_bytes)

	print("MapDownloader: Verified & cached ", _current.get("name", "?"))
	download_completed.emit(_current)
	_process_next()


# ---------------------------------------------------------------------------
# Failure / retry
# ---------------------------------------------------------------------------

func _handle_failure(reason: String) -> void:
	_cleanup_temp()
	_retry_count += 1
	if _retry_count <= MAX_RETRIES:
		push_warning("MapDownloader: Retry %d/%d for %s — %s" % [
			_retry_count, MAX_RETRIES, _current.get("name", "?"), reason])
		# Exponential back-off via a short timer.
		var delay := 1.0 * _retry_count
		get_tree().create_timer(delay).timeout.connect(_start_download)
		return

	push_warning("MapDownloader: Failed ", _current.get("name", "?"), " — ", reason)
	_had_failure = true
	download_failed.emit(_current, reason)
	_process_next()


func _cleanup_temp() -> void:
	if _download_path != "" and FileAccess.file_exists(_download_path):
		DirAccess.remove_absolute(_download_path)
	_download_path = ""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _sha256_of_file(path: String) -> String:
	# Delegate to CacheManager's static utility to avoid duplication.
	return CacheManager.sha256_of_file(path)


func _get_cache_manager() -> Node:
	return get_node_or_null("/root/CacheManager")
