extends Node
## Autoload (Net): P2P multiplayer session on native Godot networking —
## an ENet peer plus MultiplayerAPI RPCs, no master server. THE HOST
## PLAYER'S PROCESS IS THE GAME SERVER (star topology): clients connect
## straight to it, found via LAN broadcast (LanDiscovery) or direct IP
## (internet / VPN / port-forward). Milestone 1 carries the room and the
## shared match kickoff only — in-match order replication is the next
## seam (Unit2D.issue_order / queue_unit / set_rally).
##
## Host-authoritative lobby: clients send _request() RPCs, the host
## validates, mutates `room` and rebroadcasts it as _sync_room(); every
## peer (host included, via call_local) then works off the same dict.
## `room` shape:
##   name, map (resource path), started,
##   slots: [{team: int, controller: peer_id | "open" | "cpu" | "closed"}]
##   players: {peer_id: {name, ready, team}}
##   chat: [{name, text}]  (system lines have name "")

signal room_changed
signal started(config: Dictionary)
signal host_lost(reason: String)
signal peer_departed(peer_name: String)

enum Role { OFFLINE, HOST, CLIENT }

const GAME_PORT := 46656
const MAX_PLAYERS := 8
const CHAT_KEEP := 30
const UPNP_DESC := "Z remake"

var role: Role = Role.OFFLINE
var room: Dictionary = {}
var last_error := ""
var in_match := false
var match_team := 0  # this peer's team in the launched match
## shareable host addresses for the lobby (external IP first, then LAN)
var host_addresses: PackedStringArray = []

var _broadcaster: LanDiscovery
var _external_ip := ""


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


## Host -> peers economy resync cadence. push_state() shipped with NO
## caller at all, so the bounded drift correction it exists for never
## actually ran outside the test that pokes _apply_state directly.
const STATE_PUSH_SECONDS := 5.0
var _state_accum := 0.0
## Host -> peers FULL-ENTITY resync cadence. Peers apply the same
## intents to their own float physics, so positions drift; this is the
## bounded correction (MatchRelay.apply_entities reconciles by net id and
## only moves what is genuinely wrong). Slower than the economy push
## because it carries the whole roster.
const ENTITY_PUSH_SECONDS := 10.0
var _entity_accum := 0.0


func _process(delta: float) -> void:
	# announcing continues while the room is open; Net is an autoload so
	# the broadcast survives scene swaps
	if _broadcaster != null and role == Role.HOST and not in_match:
		_broadcaster.poll()
	if role == Role.HOST and in_match:
		_state_accum += delta
		if _state_accum >= STATE_PUSH_SECONDS:
			_state_accum = 0.0
			push_state()
		_entity_accum += delta
		if _entity_accum >= ENTITY_PUSH_SECONDS:
			_entity_accum = 0.0
			push_entities()


func my_id() -> int:
	return multiplayer.get_unique_id()


func is_active() -> bool:
	return role != Role.OFFLINE


# --- session -------------------------------------------------------------


func host_game(game_name: String, port := GAME_PORT, try_upnp := true) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, MAX_PLAYERS) != OK:
		last_error = "UDP PORT %d IS BUSY" % port
		return false
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	last_error = ""
	room = {
		"name": game_name, "map": _default_map(), "started": false,
		"slots": [], "players": {}, "chat": [],
	}
	_rebuild_slots()
	room.players[1] = {"name": GameSettings.player_name, "ready": true, "team": 0}
	_auto_seat(1)
	_refresh_addresses()
	if try_upnp:
		_try_upnp(port)
	if _broadcaster == null:
		_broadcaster = LanDiscovery.new()
	_broadcaster.start_broadcast(_announce(), port)
	_broadcast()
	return true


func join_game(ip: String, port := GAME_PORT) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, port) != OK:
		last_error = "COULD NOT START CONNECTING"
		return false
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	last_error = ""
	return true


func leave() -> void:
	if _broadcaster != null:
		_broadcaster.stop_broadcast()
	_teardown_peer()
	role = Role.OFFLINE
	room = {}
	in_match = false
	match_team = 0


# --- peer events ---------------------------------------------------------


func _on_peer_connected(id: int) -> void:
	if role != Role.HOST:
		return
	if in_match:
		_sync_room.rpc(room)  # tells the newcomer the match already began
		late_join(id)
		return
	if not room.players.has(id):
		room.players[id] = {"name": "PLAYER %d" % id, "ready": false, "team": 0}
		_broadcast()


func _on_peer_disconnected(id: int) -> void:
	if role != Role.HOST or not room.players.has(id):
		return
	var gone := str(room.players[id].get("name", "PLAYER"))
	_free_seat(id)
	room.players.erase(id)
	_system_chat("%s LEFT" % gone)
	peer_departed.emit(gone)
	_broadcast()


func _on_connected() -> void:
	if role == Role.CLIENT:
		_request.rpc({"cmd": "hello", "name": GameSettings.player_name})


func _on_connect_failed() -> void:
	if role == Role.CLIENT:
		last_error = "COULD NOT REACH HOST"
		role = Role.OFFLINE
		_cleanup_peer()
		host_lost.emit(last_error)


func _on_server_gone() -> void:
	if role == Role.CLIENT:
		last_error = "HOST LEFT"
		role = Role.OFFLINE
		_cleanup_peer()
		host_lost.emit(last_error)


func _cleanup_peer() -> void:
	# called from poll-driven signal handlers — a re-entrant poll() here
	# aborts the handler; the connection is dead anyway, just drop it
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return
	peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


## Graceful teardown (deliberate leave): tell connected peers we're going
## (their server_disconnected / peer_disconnected fires immediately),
## flush the notices, then drop the socket. A bare close() is abrupt —
## peers only notice after ENet's multi-second real-time timeout.
func _teardown_peer() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return
	if peer is ENetMultiplayerPeer:
		for id in multiplayer.get_peers():
			multiplayer.disconnect_peer(id)
		multiplayer.poll()  # push the disconnect notices out before close
	peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


# --- wire protocol -------------------------------------------------------


# --- in-match intent replication (milestone 2) --------------------------
# Host-authoritative exactly like the lobby: clients submit intents, the
# host validates the acting team against the sender's seat, then
# rebroadcasts; every peer applies through the single intakes
# (issue_order / queue_unit / set_rally — see MatchRelay). Entities are
# addressed by per-match NET ID (spawn order). Local sim state is NOT
# bit-synchronized (float physics) — peers apply the same intents to
# their own sims; the save contract is the resync/late-join path.

var replaying_intents := false  # applying a received intent never re-relays


## Peer -> host: one player intent (clients broadcast — their only
## peer IS the host; the host validates its own intents directly).
func _send_intent(intent: Dictionary) -> void:
	if role == Role.HOST:
		_validate_intent(match_team, intent)
	else:
		_submit_intent.rpc(intent)


func relay_order(u: Unit2D, o: Order) -> void:
	if not in_match or replaying_intents or u == null or o == null:
		return
	var target_id := 0
	if o.target != null and o.target.get("net_id") != null:
		target_id = int(o.target.net_id)
	_send_intent({
		"kind": "order", "team": match_team, "unit": u.net_id,
		"otype": int(o.type), "x": o.position.x, "y": o.position.y,
		"run": o.run, "target": target_id, "q": o.queued,
	})


func relay_queue(facility: Building2D, item: String) -> void:
	if not in_match or replaying_intents or facility == null:
		return
	_send_intent({"kind": "queue", "team": match_team,
		"fac": facility.net_id, "item": item})


func relay_rally(facility: Building2D, world_position: Vector2) -> void:
	if not in_match or replaying_intents or facility == null:
		return
	_send_intent({"kind": "rally", "team": match_team,
		"fac": facility.net_id, "x": world_position.x, "y": world_position.y})


## Does THIS peer run the CPU brains? Offline it always does; in a match
## only the HOST does. Every peer used to spawn its own CpuAi for the
## same seats, each with an unseeded RNG, so the peers' rosters diverged
## as soon as the AI produced anything and unit net ids stopped lining
## up. The host's brain now relays its intents like a player's
## (CpuAi._order/_queue/_rally).
func owns_ai() -> bool:
	return not in_match or role == Role.HOST


## Teams seated by HUMAN players in the launched match — those get no
## CpuAi stand-in (the AI only plays open/CPU seats).
func human_teams() -> Array:
	if not in_match:
		return []
	var teams := []
	for id in room.players:
		var t := int(room.players[id].get("team", 0))
		if t != 0:
			teams.append(t)
	return teams


@rpc("any_peer", "reliable")
func _submit_intent(intent: Dictionary) -> void:
	if role == Role.HOST:
		var sender := multiplayer.get_remote_sender_id()
		_validate_intent(int(room.players.get(sender, {}).get("team", 0)), intent)


## Host-side validation, split like _handle_request so tests drive it
## with a fake seat team. The acting team MUST match the sender's seat.
func _validate_intent(sender_team: int, intent: Dictionary) -> void:
	if role != Role.HOST:
		return
	if int(intent.get("team", 0)) != sender_team:
		return  # not yours to command
	_apply_intent.rpc(intent)


## Host -> peers: authoritative economy snapshot (money/zones/levels,
## save-contract shape) — the bounded resync. Push on a cadence or on
## demand; full-entity resync stays future work.
@rpc("authority", "call_local", "reliable")
func _apply_state(state: Dictionary) -> void:
	MatchRelay.apply_state(state)


## Host: broadcast the current economy snapshot to every peer.
func push_state() -> void:
	if role == Role.HOST and in_match and MatchState.current != null:
		_apply_state.rpc(MatchState.current.economy_snapshot())


## Host -> peers: the whole roster (MatchRelay.apply_entities). Clients
## reconcile; the host's own copy is already the truth, so this one is
## NOT call_local.
@rpc("authority", "reliable")
func _apply_entities(state: Dictionary) -> void:
	MatchRelay.apply_entities(state)


func push_entities() -> void:
	if role == Role.HOST and in_match and MatchState.current != null:
		_apply_entities.rpc(MatchRelay.entity_snapshot())


@rpc("authority", "call_local", "reliable")
func _apply_intent(intent: Dictionary) -> void:
	replaying_intents = true
	MatchRelay.apply(intent)
	replaying_intents = false


@rpc("any_peer", "reliable")
func _request(cmd: Dictionary) -> void:
	if role == Role.HOST:
		_handle_request(multiplayer.get_remote_sender_id(), cmd)


## Host-side handling of one client request. Split from the RPC so tests
## can drive the full protocol with a fake sender id.
func _handle_request(sender: int, cmd: Dictionary) -> void:
	if role != Role.HOST:
		return
	# a hello can race ahead of peer_connected — seat the peer FIRST so
	# the guard below admits it (the old order silently dropped the
	# racing hello and the client's name/seat flow never ran)
	if str(cmd.get("cmd", "")) == "hello" and not room.players.has(sender):
		room.players[sender] = {"ready": false, "team": 0}
	if not room.players.has(sender):
		return
	match str(cmd.get("cmd", "")):
		"hello":
			room.players[sender]["name"] = _clean_name(str(cmd.get("name", "")))
			_system_chat("%s JOINED" % player_name(sender))
			_auto_seat(sender)
			_broadcast()
		"seat":
			_move_player(sender, int(cmd.get("team", 0)))
		"ready":
			room.players[sender]["ready"] = bool(cmd.get("on", false))
			_broadcast()
		"chat":
			var text := _clean_chat(str(cmd.get("text", "")))
			if text != "":
				room.chat.append({"name": player_name(sender), "text": text})
				_trim_chat()
				_broadcast()


@rpc("authority", "call_local", "reliable")
func _sync_room(state: Dictionary) -> void:
	room = state
	room_changed.emit()


@rpc("authority", "call_local", "reliable")
func _start_game(config: Dictionary) -> void:
	match_team = int(config.get("teams", {}).get(my_id(), 0))
	in_match = true
	started.emit(config)


## LATE JOIN: a peer that connects mid-match gets the running match the
## same way a save is loaded — the map path plus a full-entity snapshot
## in save-contract shape (MatchConfig.save_data), which the map applies
## after spawning (Match._apply_load). It takes the first open seat, or
## rides along as an observer on team 0 when the map is full.
func late_join(id: int) -> void:
	if role != Role.HOST or not in_match or MatchState.current == null:
		return
	if not room.players.has(id):
		room.players[id] = {"name": "PLAYER %d" % id, "ready": true, "team": 0}
	var seat := _open_seat_for(id)
	room.players[id]["team"] = seat
	_broadcast()
	var snapshot: Dictionary = SaveSystem.capture_save()
	snapshot["entities"] = MatchRelay.entity_snapshot()
	_start_game.rpc_id(id, {
		"map": str(room.get("map", "")),
		"teams": {id: seat},
		"state": snapshot,
		"late": true,
	})


## First seat no player holds (0 = watch only).
func _open_seat_for(id: int) -> int:
	var taken := {}
	for pid in room.players:
		if pid != id:
			taken[int(room.players[pid].get("team", 0))] = true
	for slot in room.get("slots", []):
		var team := int(slot.get("team", 0))
		if team != 0 and not taken.has(team):
			return team
	return 0


# --- lobby actions (called by the room screen) ---------------------------


## Host: switch the map — slots rebuild, seated players keep a team that
## still exists (re-seated otherwise), ready flags reset.
func host_set_map(path: String) -> void:
	if role != Role.HOST or in_match or path == str(room.get("map", "")):
		return
	room["map"] = path
	_rebuild_slots()
	for id in room.players:
		room.players[id]["ready"] = false
	room.players[1]["ready"] = true  # the host is always ready
	_broadcast()


## Host: cycle an unoccupied slot OPEN -> CPU -> CLOSED -> OPEN.
func host_toggle_slot(team: int) -> void:
	if role != Role.HOST or in_match:
		return
	var slot := _slot(team)
	if slot.is_empty() or slot.get("controller") is int:
		return
	slot["controller"] = {"open": "cpu", "cpu": "closed", "closed": "open"}[
		str(slot["controller"])]
	_broadcast()


## Client: claim a free seat (or the one already held).
func request_seat(team: int) -> void:
	if role == Role.CLIENT:
		_request.rpc({"cmd": "seat", "team": team})


## Host: move themselves to a free seat.
func host_take_seat(team: int) -> void:
	if role == Role.HOST and room.players.has(1):
		_move_player(1, team)


## Controller of a slot: a peer id, or "open"/"cpu"/"closed".
func slot_controller(team: int) -> Variant:
	var slot := _slot(team)
	return slot.get("controller", "closed") if not slot.is_empty() else "closed"


func set_ready(on: bool) -> void:
	if role == Role.CLIENT:
		_request.rpc({"cmd": "ready", "on": on})
	elif role == Role.HOST and room.players.has(1):
		room.players[1]["ready"] = on
		_broadcast()


func send_chat(text: String) -> void:
	var clean := _clean_chat(text)
	if clean == "":
		return
	if role == Role.CLIENT:
		_request.rpc({"cmd": "chat", "text": clean})
	elif role == Role.HOST:
		room.chat.append({"name": player_name(1), "text": clean})
		_trim_chat()
		_broadcast()


## Host: launch. Empty string means clear to start.
func start_blocker() -> String:
	if role != Role.HOST:
		return "NOT HOSTING"
	if in_match:
		return "ALREADY STARTED"
	if str(room.get("map", "")) == "":
		return "PICK A MAP"
	for id in room.players:
		var p: Dictionary = room.players[id]
		if int(p.get("team", 0)) <= 0:
			return "%s HAS NO TEAM" % str(p.get("name", "PLAYER"))
		if id != 1 and not bool(p.get("ready", false)):
			return "%s NOT READY" % str(p.get("name", "PLAYER"))
	return ""


func host_start() -> bool:
	if start_blocker() != "":
		return false
	var teams := {}
	for id in room.players:
		teams[id] = int(room.players[id].get("team", 0))
	room["started"] = true
	in_match = true
	if _broadcaster != null:
		_broadcaster.stop_broadcast()
	_broadcast()
	_start_game.rpc({"map": str(room.get("map", "")), "teams": teams})
	return true


func player_name(id: int) -> String:
	if room.players.has(id):
		return str(room.players[id].get("name", "PLAYER"))
	return "PLAYER %d" % id


# --- room internals (host side only) --------------------------------------


func _broadcast() -> void:
	if role != Role.HOST:
		return
	_sync_room.rpc(room)
	if _broadcaster != null:
		_broadcaster.start_broadcast(_announce(), GAME_PORT)


func _announce() -> Dictionary:
	var path := str(room.get("map", ""))
	var title := MapCatalog.display_title(path.get_file().get_basename())
	return {
		"name": str(room.get("name", "GAME")),
		"map": title,
		"cur": room.players.size(),
		"max": room.slots.size(),
	}


func _default_map() -> String:
	for e in MapCatalog.entries():
		if not e.sandbox:
			return str(e.path)
	return ""


## Rebuild slots for the current map and re-seat players where possible.
func _rebuild_slots() -> void:
	var path := str(room.get("map", ""))
	var teams: Array = MapCatalog.fort_teams(path.get_file().get_basename()) \
			if path != "" else [1, 2]
	var seated := {}  # team -> peer id, kept from the old slots
	for slot in room.get("slots", []):
		if slot.get("controller") is int:
			seated[int(slot.team)] = int(slot.controller)
	room["slots"] = []
	for t in teams:
		room.slots.append({
			"team": int(t),
			"controller": seated.get(int(t), "open"),
		})
	for id in room.players:
		var p: Dictionary = room.players[id]
		var t := int(p.get("team", 0))
		if t > 0 and not seated.has(t):
			p["team"] = 0
			_auto_seat(id)


func _slot(team: int) -> Dictionary:
	for slot in room.get("slots", []):
		if int(slot.get("team", 0)) == team:
			return slot
	return {}


func _auto_seat(id: int) -> void:
	if int(room.players[id].get("team", 0)) > 0:
		return
	for slot in room.slots:
		if str(slot.controller) == "open":
			slot["controller"] = id
			room.players[id]["team"] = int(slot.team)
			room.players[id]["ready"] = false
			return


func _move_player(id: int, team: int) -> void:
	var slot := _slot(team)
	if slot.is_empty() or int(room.players[id].get("team", 0)) == team:
		return
	# only free seats (or the mover's own) may be taken
	if slot.get("controller") is int and int(slot.controller) != id:
		return
	_free_seat(id)
	slot["controller"] = id
	room.players[id]["team"] = team
	room.players[id]["ready"] = false
	_broadcast()


func _free_seat(id: int) -> void:
	for slot in room.get("slots", []):
		if slot.get("controller") is int and int(slot.controller) == id:
			slot["controller"] = "open"


func _system_chat(text: String) -> void:
	room.chat.append({"name": "", "text": text})
	_trim_chat()


func _trim_chat() -> void:
	while room.chat.size() > CHAT_KEEP:
		room.chat.pop_front()


func _clean_name(raw: String) -> String:
	var s := raw.strip_edges().substr(0, 14).to_upper()
	return s if s != "" else "COMMANDER"


func _clean_chat(raw: String) -> String:
	return raw.strip_edges().substr(0, 120)


# --- addressing (host display) --------------------------------------------


func _refresh_addresses() -> void:
	host_addresses.clear()
	if _external_ip != "":
		host_addresses.append(_external_ip)
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.contains(".") and not s.contains(":") and not s.begins_with("127.") \
				and not host_addresses.has(s):
			host_addresses.append(s)


## Best-effort UPnP port forward (native UPNP class) so direct-IP joins
## from the internet can reach this host; silent no-op without a gateway.
## Runs on a thread — discover() blocks for its timeout.
func _try_upnp(port: int) -> void:
	var worker := Thread.new()
	worker.start(func() -> void:
		var upnp := UPNP.new()
		var ext := ""
		if upnp.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS \
				and upnp.add_port_mapping(port, port, UPNP_DESC, "UDP") == OK:
			var addr := upnp.query_external_address()
			if addr != "" and addr != "0.0.0.0":
				ext = addr
		_upnp_done.call_deferred(ext, worker))


func _upnp_done(external: String, worker: Thread) -> void:
	worker.wait_to_finish()
	if external != "" and role == Role.HOST:
		_external_ip = external
		_refresh_addresses()
