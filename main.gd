extends Control

const Poker = preload("res://poker.gd")
const Game = preload("res://game.gd")
const AggressiveAI = preload("res://ai_strategy.gd")
const Realtime = preload("res://supabase_realtime.gd")
const TableUI = preload("res://holdem_table_ui.gd")
const LobbyUI = preload("res://holdem_lobby_ui.gd")
const SAMPLE_COUNT = 3000
const Feedback = preload("res://table_feedback.gd")
const STAGE_KEYS = ["preflop", "flop", "turn", "river", "showdown"]
const ACTION_NAMES = {"check": "체크", "call": "콜", "raise": "레이즈", "allin": "올인", "fold": "폴드"}
var feedback := Feedback.new()
var guest_locked := false
var prediction_version := 0

var game = Game.new()
var rng = RandomNumberGenerator.new()
var busy := false
var odds: Array = [0.0, 0.0, 0.0]
var stage_odds: Array = []
var progress := 0
var ai_personality := "기존"
var realtime
var table_ui
var lobby_ui
var network_mode := false
var network_role := ""
var game_started := false
var room_code := ""
var client_id := ""
var remote_player_id := ""
var hello_elapsed := 0.0

func _ready() -> void:
	rng.randomize()
	realtime = Realtime.new()
	add_child(realtime)
	realtime.joined.connect(_on_realtime_joined)
	realtime.message_received.connect(_on_realtime_message)
	realtime.status_changed.connect(_on_realtime_status)
	table_ui = TableUI.new()
	table_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	table_ui.action_requested.connect(play)
	table_ui.next_requested.connect(next_pressed)
	table_ui.exit_requested.connect(return_to_main_menu)
	add_child(table_ui)
	lobby_ui = LobbyUI.new()
	lobby_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 이 Control은 화면 전체를 덮지만, 로비 화면이 닫힌 뒤에도 노드 자체는 남습니다.
	# 부모가 마우스 입력을 막지 않도록 해야 아래 table_ui의 버튼을 누를 수 있습니다.
	# 로비가 열릴 때는 holdem_lobby_ui.gd의 overlay가 입력을 받습니다.
	lobby_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lobby_ui.offline_selected.connect(_start_offline)
	lobby_ui.skins_requested.connect(table_ui.skin_picker.open)
	lobby_ui.online_setup_requested.connect(show_online_setup)
	lobby_ui.create_room_requested.connect(_start_host_room)
	lobby_ui.join_room_requested.connect(_start_guest_room)
	lobby_ui.back_requested.connect(return_to_main_menu)
	add_child(lobby_ui)
	add_child(feedback)
	table_ui.settings_requested.connect(feedback.open_settings)
	lobby_ui.settings_requested.connect(feedback.open_settings)
	get_tree().node_added.connect(_wire_click)
	for button in get_tree().root.find_children("*", "BaseButton", true, false):
		_wire_click(button)
	show_main_menu()
	refresh()
func _process(delta: float) -> void:
	if network_mode and network_role == "guest" and not game_started and realtime.joined_ok:
		hello_elapsed += delta
		if hello_elapsed >= 2.0:
			hello_elapsed = 0.0
			realtime.send_message({"kind": "hello", "from": client_id})
func _local_seat() -> int:
	return 1 if network_mode and network_role == "guest" else 0

func _wire_click(node: Node):
	if node is BaseButton and not node.pressed.is_connected(feedback.click):
		node.pressed.connect(feedback.click)

func _show_cue(kind: String, code: String, seat: int):
	var who := "내" if seat == _local_seat() else ("상대" if network_mode else "컴퓨터")
	match kind:
		"stage":
			var index := STAGE_KEYS.find(code)
			if index >= 0:
				feedback.slide(Game.STAGES[index], ["개인 카드 배분", "공용 카드 세 장 공개", "네 번째 공용 카드 공개", "마지막 공용 카드 공개", "양쪽 패를 비교합니다"][index], code)
		"turn":
			feedback.slide(who + " 차례", "베팅할 차례", "you" if seat == _local_seat() else ("opponent" if network_mode else "computer"))
		"action":
			if ACTION_NAMES.has(code):
				feedback.slide(ACTION_NAMES[code], who + " 행동", code)

func _announce(kind: String, code: String, seat: int = -1):
	busy = true
	refresh()
	if network_mode and network_role == "host":
		realtime.send_message({"kind":"cue", "from":client_id, "to":remote_player_id, "cue":kind, "code":code, "seat":seat})
	_show_cue(kind, code, seat)
	await get_tree().create_timer(Feedback.DURATION).timeout

func _advance_stage():
	await _announce("stage", STAGE_KEYS[game.stage + 1])
	game.advance()
	if not game.over:
		await predict()

func _show_result():
	var reason := "쇼다운 결과" if game.stage == 4 else "폴드로 종료"
	if game.result == 2:
		feedback.slide("무승부", reason, "draw")
	elif game.result == _local_seat():
		feedback.slide("내가 승리했습니다", reason, "win_self")
	elif network_mode:
		feedback.slide("상대 플레이어 승리", reason, "win_opponent")
	else:
		feedback.slide("컴퓨터 승리", reason, "win_cpu")

func _announce_result():
	busy = true
	refresh()
	_send_game_state(true)
	_show_result()
	await get_tree().create_timer(Feedback.DURATION).timeout

func _accept_action(seat: int, kind: String, target: int):
	var spoken := kind
	if kind == "call" and game.owed(seat) == 0: spoken = "check"
	if not game.action(seat, kind, target): return false
	await _announce("action", spoken, seat)
	return true

func start_hand():
	if network_mode and network_role == "guest":
		return
	if not network_mode:
		ai_personality = AggressiveAI.pick_personality(rng)
	await _announce("stage", "preflop")
	game.new_hand()
	stage_odds.clear()
	await predict()
	await drive()
func predict():
	prediction_version += 1
	var version := prediction_version
	busy = true
	progress = 0
	refresh()
	var wins = 0.0
	var ties = 0.0
	var hero_cards = game.hands[_local_seat()]
	if game.board.size() == 5:
		await get_tree().process_frame
		if version != prediction_version: return
		var counts = Poker.river_prediction(hero_cards, game.board)
		odds = [counts[0] * 100 / counts[2], counts[1] * 100 / counts[2], (counts[2] - counts[0] - counts[1]) * 100 / counts[2]]
	else:
		while progress < SAMPLE_COUNT:
			var counts = Poker.sample(hero_cards, game.board, [], 60, rng)
			wins += counts[0]
			ties += counts[1]
			progress += 60
			odds = [wins * 100 / progress, ties * 100 / progress, (progress - wins - ties) * 100 / progress]
			refresh()
			await get_tree().process_frame
			if version != prediction_version: return
	progress = SAMPLE_COUNT
	stage_odds.append(odds[0])
	busy = false
	refresh()
func play(kind: String, target: int = 0):
	if busy or guest_locked or not game_started:
		return
	var seat := _local_seat()
	if network_mode and network_role == "guest":
		busy = true
		if not realtime.send_message({"kind": "action", "from": client_id, "action": kind, "target": target}):
			busy = false
			game.message = "연결이 끊겼습니다. 방에 다시 참가해 주세요."
		refresh()
		return
	if await _accept_action(seat, kind, target):
		await drive()
func next_pressed():
	if busy or guest_locked or not game_started:
		return
	if network_mode and network_role == "guest":
		busy = true
		if not realtime.send_message({"kind": "next", "from": client_id}):
			busy = false
			game.message = "연결이 끊겼습니다. 방에 다시 참가해 주세요."
		refresh()
		return
	if game.over:
		await start_hand()
	elif game.pending:
		await _advance_stage()
		await drive()

func drive() -> void:
	if network_mode:
		while not game.over and game.pending and game.stacks.min() == 0:
			_send_game_state(true)
			await _advance_stage()
		if not game.over and not game.pending:
			_send_game_state(true)
			await _announce("turn", "", game.actor)
		if game.over:
			await _announce_result()
		busy = false
		_send_game_state()
		refresh()
		return
	while not game.over:
		refresh()
		if game.pending:
			if game.stacks.min() == 0:
				await _advance_stage()
				continue
			break
		await _announce("turn", "", game.actor)
		if game.actor == 0:
			break
		busy = true
		refresh()
		await get_tree().create_timer(0.35).timeout
		var decision: Dictionary = AggressiveAI.choose_betting_action(
			game.hands[1], game.board, game.owed(1), game.raise_possible(1),
			game.max_target(1), int(game.paid.max()), game.min_raise, game.pot,
			game.stacks[1], ai_personality, rng
		)
		await _accept_action(1, str(decision.get("action", "call")), int(decision.get("target", 0)))
		busy = false
	if game.over:
		await _announce_result()
	busy = false
	refresh()
func _make_room_code() -> String:
	const alphabet := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for i in range(8):
		code += alphabet[rng.randi_range(0, alphabet.length() - 1)]
	return code
func _make_client_id() -> String:
	return "%d_%08x" % [Time.get_ticks_usec(), rng.randi()]
func _on_realtime_joined() -> void:
	if not network_mode:
		return
	if network_role == "host":
		lobby_ui.show_waiting_status("방 코드: %s\n연결됐습니다. 친구가 이 코드를 입력할 때까지 기다리세요." % room_code)
	else:
		hello_elapsed = 2.0
		lobby_ui.show_waiting_status("방에 연결됐습니다. 호스트 응답을 기다리는 중…")
func _on_realtime_message(message: Dictionary) -> void:
	if not network_mode:
		return
	var sender := str(message.get("from", ""))
	var kind := str(message.get("kind", ""))
	if sender.is_empty() or sender == client_id:
		return
	if network_role == "host":
		if kind == "hello":
			if not remote_player_id.is_empty() and remote_player_id != sender:
				realtime.send_message({"kind": "reject", "from": client_id, "to": sender, "reason": "이 방은 이미 두 명이 사용 중입니다."})
				return
			remote_player_id = sender
			realtime.send_message({"kind": "welcome", "from": client_id, "to": sender})
			if not game_started:
				game_started = true
				lobby_ui.show_table()
				await start_hand()
			elif not busy:
				_send_game_state()
			return
		if sender != remote_player_id:
			return
		if busy: return
		if kind == "action":
			if game_started and game.actor == 1 and not game.pending and not game.over:
				var action_name := str(message.get("action", ""))
				var target := int(message.get("target", 0))
				if await _accept_action(1, action_name, target):
					await drive()
				else:
					_send_game_state()
			else:
				_send_game_state()
		elif kind == "next":
			if game_started and game.over:
				await start_hand()
			elif game_started and game.pending:
				await _advance_stage()
				await drive()
			else:
				_send_game_state()
	else:
		if kind == "reject":
			if lobby_ui.status_label != null:
				lobby_ui.show_waiting_status(str(message.get("reason", "방에 참가할 수 없습니다.")))
			return
		if kind == "welcome":
			remote_player_id = sender
			if lobby_ui.status_label != null:
				lobby_ui.show_waiting_status("호스트와 연결됐습니다. 게임 정보를 기다리는 중…")
			return
		if sender != remote_player_id and not remote_player_id.is_empty():
			return
		if kind == "cue" and sender == remote_player_id:
			guest_locked = true
			lobby_ui.show_table()
			_show_cue(str(message.get("cue", "")), str(message.get("code", "")), int(message.get("seat", -1)))
			refresh()
			return
		if kind == "state":
			remote_player_id = sender
			await _apply_game_state(message)
func _send_game_state(locked := false) -> void:
	if not network_mode or network_role != "host" or remote_player_id.is_empty() or not game_started:
		return
	var revealed_hands: Array = game.hands if game.stage == 4 else []
	var snapshot := {
		"kind": "state",
		"locked": locked,
		"from": client_id,
		"to": remote_player_id,
		"hand_no": game.hand_no,
		"stage": game.stage,
		"stacks": game.stacks,
		"paid": game.paid,
		"acted": game.acted,
		"can_raise": game.can_raise,
		"board": game.board,
		"pot": game.pot,
		"dealer": game.dealer,
		"actor": game.actor,
		"min_raise": game.min_raise,
		"pending": game.pending,
		"over": game.over,
		"result": game.result,
		"message": game.message,
		"private_hand": game.hands[1],
		"revealed_hands": revealed_hands
	}
	realtime.send_message(snapshot)
func _apply_game_state(snapshot: Dictionary) -> void:
	var was_over: bool = game.over
	guest_locked = snapshot.get("locked", false)
	var old_hand_no: int = int(game.hand_no)
	var old_board: String = str(game.board)
	game.hand_no = int(snapshot.get("hand_no", game.hand_no))
	game.stage = int(snapshot.get("stage", game.stage))
	game.stacks = snapshot.get("stacks", game.stacks)
	game.paid = snapshot.get("paid", game.paid)
	game.acted = snapshot.get("acted", game.acted)
	game.can_raise = snapshot.get("can_raise", game.can_raise)
	game.board = snapshot.get("board", game.board)
	game.pot = int(snapshot.get("pot", game.pot))
	game.dealer = int(snapshot.get("dealer", game.dealer))
	game.actor = int(snapshot.get("actor", game.actor))
	game.min_raise = int(snapshot.get("min_raise", game.min_raise))
	game.pending = bool(snapshot.get("pending", game.pending))
	game.over = bool(snapshot.get("over", game.over))
	game.result = int(snapshot.get("result", game.result))
	game.message = str(snapshot.get("message", game.message))
	var revealed: Array = snapshot.get("revealed_hands", [])
	if revealed.size() == 2:
		game.hands = [revealed[0], revealed[1]]
	else:
		game.hands = [[], []]
		game.hands[1] = snapshot.get("private_hand", [])
	if old_hand_no != game.hand_no:
		stage_odds.clear()
	game_started = true
	lobby_ui.show_table()
	if game.over and (not was_over or old_hand_no != game.hand_no):
		_show_result()
	var should_predict: bool = old_hand_no != int(game.hand_no) or old_board != str(game.board)
	if should_predict and game.hands[1].size() == 2:
		await predict()
	else:
		if not busy or progress == SAMPLE_COUNT: busy = false
		refresh()
func _start_offline() -> void:
	StatsTracker.set_lobby_visible(false)
	network_mode = false
	network_role = ""
	game_started = true
	game = Game.new()
	lobby_ui.show_table()
	refresh()
	await start_hand()

func show_main_menu() -> void:
	StatsTracker.set_lobby_visible(true)
	lobby_ui.show_main_menu()
	refresh()

func show_online_setup() -> void:
	StatsTracker.set_lobby_visible(false)
	var config := ConfigFile.new()
	config.load("user://holdem_supabase.cfg")
	lobby_ui.show_online_setup(str(config.get_value("supabase", "url", "")), str(config.get_value("supabase", "public_key", "")))

func _start_host_room(url: String, key: String) -> void:
	_start_online(true, url, key, "")

func _start_guest_room(url: String, key: String, code: String) -> void:
	_start_online(false, url, key, code)

func _start_online(as_host: bool, url: String, key: String, entered_code: String) -> void:
	url = url.strip_edges()
	key = key.strip_edges()
	entered_code = entered_code.strip_edges().to_upper()
	if url.is_empty() or key.is_empty():
		lobby_ui.show_waiting_status("Supabase 프로젝트 URL과 공개 키를 입력해 주세요.")
		return
	if not as_host and entered_code.is_empty():
		lobby_ui.show_waiting_status("참가하려면 친구에게 받은 방 코드를 입력해 주세요.")
		return
	var config := ConfigFile.new()
	config.set_value("supabase", "url", url)
	config.set_value("supabase", "public_key", key)
	var save_error := config.save("user://holdem_supabase.cfg")
	if save_error != OK:
		lobby_ui.show_waiting_status("설정을 이 기기에 저장하지 못했습니다. 다시 시도해 주세요.")
		return
	network_mode = true
	network_role = "host" if as_host else "guest"
	game_started = false
	remote_player_id = ""
	room_code = _make_room_code() if as_host else entered_code
	client_id = _make_client_id()
	game = Game.new()
	if as_host:
		lobby_ui.room_input.text = room_code
		lobby_ui.show_waiting_status("방 코드: %s\n친구에게 이 코드를 보내고, 참가할 때까지 기다리세요." % room_code)
	else:
		lobby_ui.show_waiting_status("방 %s 에 연결하는 중…" % room_code)
	if not realtime.connect_room(url, key, room_code, client_id):
		network_mode = false
	refresh()

func _on_realtime_status(text: String) -> void:
	if lobby_ui.status_label != null:
		lobby_ui.show_waiting_status(text)
	elif network_mode and game_started:
		game.message = "연결 상태: " + text
		refresh()

func refresh() -> void:
	if not is_instance_valid(table_ui):
		return
	table_ui.update_state({
		"game": game,
		"busy": busy or guest_locked,
		"game_started": game_started,
		"network_mode": network_mode,
		"network_role": network_role,
		"ai_personality": ai_personality,
		"odds": odds,
		"stage_odds": stage_odds,
		"progress": progress
	})

func return_to_main_menu() -> void:
	guest_locked = false
	prediction_version += 1
	realtime.close_room()
	network_mode = false
	network_role = ""
	game_started = false
	busy = false
	room_code = ""
	client_id = ""
	remote_player_id = ""
	hello_elapsed = 0.0
	game = Game.new()
	odds = [0.0, 0.0, 0.0]
	stage_odds.clear()
	progress = 0
	StatsTracker.set_lobby_visible(true)
	lobby_ui.show_main_menu()
	refresh()
