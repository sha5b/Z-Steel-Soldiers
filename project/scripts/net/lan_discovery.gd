class_name LanDiscovery
extends RefCounted
## Serverless LAN autodiscovery over native UDP: the host broadcasts a
## small JSON announce every second; browse screens listen and drop games
## that go quiet (TTL). An announce is just a UDP packet to a list of
## targets — pointing `targets` at an ordinary address instead of the LAN
## broadcast is exactly how a future community list server would plug in.
## Poll-driven (no timers): the owner calls poll() every frame, so
## headless tests can drive it deterministically.

signal game_found(key: String, info: Dictionary)
signal game_updated(key: String, info: Dictionary)
signal game_lost(key: String)

const DISCOVERY_PORT := 46755
const MAGIC := "zss1"
const BROADCAST := "255.255.255.255"
const ANNOUNCE_SECONDS := 1.0
const TTL_MSEC := 5000

var announce_interval := ANNOUNCE_SECONDS  # test lever
var ttl := TTL_MSEC                        # test lever

var _targets: PackedStringArray = [BROADCAST]
var _info := {}          # what the host broadcasts (room summary)
var _sender: PacketPeerUDP
var _listener: PacketPeerUDP
var _last_sent_msec := -(1 << 30)
var _games := {}         # "ip:gameport" -> announce dict + "seen" msec


func _init(targets: PackedStringArray = [BROADCAST]) -> void:
	_targets = targets


## Host side: announce `info` (plus the game port) until stop_broadcast().
## Calling again just replaces the payload (room name/map/player count).
func start_broadcast(info: Dictionary, game_port: int) -> void:
	_info = {"magic": MAGIC, "port": game_port}
	for k in info:
		_info[k] = info[k]
	if _sender == null:
		_sender = PacketPeerUDP.new()
		_sender.set_broadcast_enabled(true)
	_send()


func stop_broadcast() -> void:
	if _sender != null:
		_sender.close()
		_sender = null


## Browse side: bind the discovery port. False when another process on
## this machine is already listening (Direct IP still works).
func listen() -> bool:
	if _listener == null:
		var peer := PacketPeerUDP.new()
		if peer.bind(DISCOVERY_PORT) != OK:
			return false
		_listener = peer
	return true


func stop_listen() -> void:
	if _listener != null:
		_listener.close()
		_listener = null


## Drive both directions: resend due announces, drain received packets,
## expire stale games. Emits game_found/game_updated/game_lost.
func poll() -> void:
	if _sender != null and Time.get_ticks_msec() - _last_sent_msec \
			>= int(announce_interval * 1000.0):
		_send()
	if _listener == null:
		return
	while _listener.get_available_packet_count() > 0:
		var parsed = JSON.parse_string(
			_listener.get_packet().get_string_from_utf8())
		if parsed is Dictionary and String(parsed.get("magic", "")) == MAGIC:
			_accept(parsed)
	var now := Time.get_ticks_msec()
	for key in _games.keys().duplicate():
		if now - int(_games[key].get("seen", 0)) > ttl:
			_games.erase(key)
			game_lost.emit(key)


## Announces currently visible, in arrival order.
func games() -> Array:
	return _games.values()


func game_info(key: String) -> Dictionary:
	return _games.get(key, {})


func _send() -> void:
	var data := JSON.stringify(_info).to_utf8_buffer()
	for t in _targets:
		_sender.set_dest_address(t, DISCOVERY_PORT)
		_sender.put_packet(data)
	_last_sent_msec = Time.get_ticks_msec()


func _accept(info: Dictionary) -> void:
	var ip := _listener.get_packet_ip()
	var key := "%s:%d" % [ip, int(info.get("port", 0))]
	var is_new := not _games.has(key)
	var rec := info.duplicate()
	rec["seen"] = Time.get_ticks_msec()
	rec["ip"] = ip
	_games[key] = rec
	var sig := game_found if is_new else game_updated
	sig.emit(key, rec.duplicate(true))
