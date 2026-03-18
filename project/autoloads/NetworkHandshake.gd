## NetworkHandshake.gd — Manifest receiving and parsing for auto-download.
##
## When a client wants to connect to a server, it first queries the server's
## HTTP manifest endpoint to discover which resource packs (.pck) are required.
##
## Manifest JSON schema (served by the game server):
## {
##   "server_id":  "unique-server-identifier",
##   "server_name": "My Custom Server",
##   "protocol_version": 1,
##   "resources": [
##     {
##       "name":     "v2_rocket.pck",
##       "sha256":   "a1b2c3d4e5f6…",
##       "size":     1048576,
##       "url":      "http://cdn.example.com/packs/a1b2c3d4e5f6….pck",
##       "required": true
##     }
##   ]
## }
##
## Usage (autoload singleton "NetworkHandshake"):
##   NetworkHandshake.request_manifest("192.168.1.10", 12301)
##   NetworkHandshake.manifest_received.connect(_on_manifest)
##   NetworkHandshake.manifest_failed.connect(_on_manifest_error)
extends Node

## Emitted when a valid manifest has been parsed.
signal manifest_received(manifest: Dictionary)
## Emitted on any failure (timeout, HTTP error, parse error).
signal manifest_failed(reason: String)
## Emitted when the handshake starts (useful for UI).
signal handshake_started(server_address: String)

const PROTOCOL_VERSION := 1
const DEFAULT_HTTP_PORT := 12301
const REQUEST_TIMEOUT := 15.0 # seconds

var _http_request: HTTPRequest = null
var _current_address: String = ""


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = REQUEST_TIMEOUT
	_http_request.use_threads = not OS.has_feature("web")
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Fetch the resource manifest from a game server.
## [param server_host] IP or hostname of the server.
## [param http_port]   Port on which the server exposes its manifest endpoint.
func request_manifest(server_host: String, http_port: int = DEFAULT_HTTP_PORT) -> void:
	if _http_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http_request.cancel_request()

	var url := "http://%s:%d/manifest.json" % [server_host, http_port]
	_current_address = "%s:%d" % [server_host, http_port]
	handshake_started.emit(_current_address)
	print("NetworkHandshake: Requesting manifest from ", url)

	var err := _http_request.request(url)
	if err != OK:
		var reason := "HTTP request failed to start: error %d" % err
		push_warning("NetworkHandshake: ", reason)
		manifest_failed.emit(reason)


## Build a manifest dictionary from raw data (useful for testing or LAN-only
## setups where the server pushes the manifest over the game protocol).
func parse_manifest_json(json_text: String) -> Dictionary:
	var parsed = JSON.parse_string(json_text)
	if not parsed is Dictionary:
		return {}
	return _validate_manifest(parsed)


# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_request_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		var reason := "HTTP request error: result=%d" % result
		push_warning("NetworkHandshake: ", reason)
		manifest_failed.emit(reason)
		return

	if response_code != 200:
		var reason := "Server returned HTTP %d" % response_code
		push_warning("NetworkHandshake: ", reason)
		manifest_failed.emit(reason)
		return

	var text := body.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		var reason := "Manifest is not valid JSON"
		push_warning("NetworkHandshake: ", reason)
		manifest_failed.emit(reason)
		return

	var manifest := _validate_manifest(parsed)
	if manifest.is_empty():
		var reason := "Manifest failed validation"
		push_warning("NetworkHandshake: ", reason)
		manifest_failed.emit(reason)
		return

	print("NetworkHandshake: Manifest OK — server_id=", manifest.get("server_id", "?"),
		" resources=", manifest["resources"].size())
	manifest_received.emit(manifest)


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

func _validate_manifest(data: Dictionary) -> Dictionary:
	# Protocol version check.
	var proto: int = data.get("protocol_version", -1)
	if proto < 1 or proto > PROTOCOL_VERSION:
		push_warning("NetworkHandshake: Unsupported protocol_version=", proto)
		return {}

	if not data.has("resources") or not data["resources"] is Array:
		push_warning("NetworkHandshake: Missing or invalid 'resources' array")
		return {}

	var valid_resources: Array[Dictionary] = []
	for entry in data["resources"]:
		if not entry is Dictionary:
			continue
		# Each resource must have at minimum: name, sha256, size, url.
		var name_val: String = entry.get("name", "")
		var sha256_val: String = entry.get("sha256", "")
		var size_val: int = entry.get("size", -1)
		var url_val: String = entry.get("url", "")
		if name_val == "" or sha256_val == "" or size_val <= 0 or url_val == "":
			push_warning("NetworkHandshake: Skipping invalid resource entry: ", entry)
			continue
		# Normalize hash to lowercase.
		var resource := {
			"name": name_val,
			"sha256": sha256_val.to_lower(),
			"size": size_val,
			"url": url_val,
			"required": entry.get("required", true),
		}
		valid_resources.append(resource)

	if valid_resources.is_empty():
		push_warning("NetworkHandshake: No valid resources in manifest")
		return {}

	return {
		"server_id": data.get("server_id", "unknown"),
		"server_name": data.get("server_name", ""),
		"protocol_version": proto,
		"resources": valid_resources,
	}
