extends Node

# Helper class to get public IP address for internet play

signal public_ip_received(ip: String)
signal public_ip_failed(error: String)

var http_request: HTTPRequest

func _ready() -> void:
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

func get_public_ip() -> void:
	"""Fetch public IP address from external service"""
	var error = http_request.request("https://api.ipify.org?format=text")
	if error != OK:
		public_ip_failed.emit("Failed to start HTTP request")

func get_local_ip() -> String:
	"""Get local IP address for LAN play"""
	var addresses = IP.get_local_addresses()
	for address in addresses:
		# Filter out localhost and IPv6 addresses
		if address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172."):
			return address
	return "127.0.0.1"

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		public_ip_failed.emit("HTTP request failed")
		return
	
	if response_code != 200:
		public_ip_failed.emit("HTTP response code: " + str(response_code))
		return
	
	var ip = body.get_string_from_utf8().strip_edges()
	if ip.is_empty():
		public_ip_failed.emit("Empty response from IP service")
		return
	
	public_ip_received.emit(ip)
