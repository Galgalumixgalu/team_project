extends CanvasLayer

const SAVE_PATH = "user://holdem_records.json"
const PERSONALITIES = ["기존", "성급", "조심"]

var records: Array = []
var tracked_scene_id = 0
var active_hand_no = -1
var was_active = false
var last_saved_hand_no = -1

var stats_button: Button
var dimmer: ColorRect
var panel: PanelContainer
var summary_label: Label
var personality_label: Label
var history_label: Label
var reset_dialog: ConfirmationDialog

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_load_records()
	_build_ui()

func _process(_delta: float) -> void:
	_track_game_result()

func _track_game_result() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	var game = scene.get("game")
	if game == null:
		return
	if bool(scene.get("network_mode")):
		return

	var scene_id = scene.get_instance_id()
	if scene_id != tracked_scene_id:
		tracked_scene_id = scene_id
		active_hand_no = -1
		was_active = false
		last_saved_hand_no = -1

	var hand_no = int(game.get("hand_no"))
	var is_over = bool(game.get("over"))
	if not is_over:
		if hand_no != active_hand_no:
			active_hand_no = hand_no
			was_active = true
		return

	if was_active and hand_no == active_hand_no and hand_no != last_saved_hand_no:
		var result = int(game.get("result"))
		if result >= 0 and result <= 2:
			var personality = str(scene.get("ai_personality"))
			var player_result = result
			if not PERSONALITIES.has(personality):
				personality = "기존"
			_add_record(hand_no, player_result, personality)
			last_saved_hand_no = hand_no
			was_active = false

func _add_record(hand_no: int, result: int, personality: String) -> void:
	var outcomes = ["승리", "패배", "무승부"]
	records.append({
		"hand_no": hand_no,
		"result": outcomes[result],
		"personality": personality,
		"time": Time.get_datetime_string_from_system(false, true)
	})
	_save_records()
	_refresh_stats()

func _load_records() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		records = []
		return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		records = []
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and parsed.get("records", []) is Array:
		records = parsed["records"]
	else:
		records = []

func _save_records() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("전적 파일을 저장하지 못했습니다: " + SAVE_PATH)
		return
	file.store_string(JSON.stringify({"records": records}, "\t"))

func _build_ui() -> void:
	stats_button = Button.new()
	stats_button.text = "전적 / 통계"
	stats_button.position = Vector2(517, 520)
	stats_button.size = Vector2(165, 45)
	stats_button.visible = false
	stats_button.pressed.connect(_open_stats)
	add_child(stats_button)

	dimmer = ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.68)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.visible = false
	add_child(dimmer)

	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -340
	panel.offset_top = -270
	panel.offset_right = 340
	panel.offset_bottom = 270
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color("172633")
	panel_style.border_color = Color("547b75")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.visible = false
	add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title = Label.new()
	title.text = "전적 및 플레이 통계"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color("70d6b2"))
	column.add_child(title)

	summary_label = Label.new()
	summary_label.add_theme_font_size_override("font_size", 17)
	column.add_child(summary_label)

	personality_label = Label.new()
	personality_label.add_theme_font_size_override("font_size", 15)
	personality_label.add_theme_color_override("font_color", Color("c5d4df"))
	column.add_child(personality_label)

	var history_title = Label.new()
	history_title.text = "최근 전적 (최대 20핸드 표시)"
	history_title.add_theme_font_size_override("font_size", 16)
	column.add_child(history_title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 185)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	history_label = Label.new()
	history_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(history_label)

	var buttons_row = HBoxContainer.new()
	buttons_row.alignment = BoxContainer.ALIGNMENT_END
	buttons_row.add_theme_constant_override("separation", 10)
	column.add_child(buttons_row)

	var reset_button = Button.new()
	reset_button.text = "전적 초기화"
	reset_button.pressed.connect(func(): reset_dialog.popup_centered())
	buttons_row.add_child(reset_button)

	var close_button = Button.new()
	close_button.text = "닫기"
	close_button.pressed.connect(_close_stats)
	buttons_row.add_child(close_button)

	reset_dialog = ConfirmationDialog.new()
	reset_dialog.title = "전적 초기화"
	reset_dialog.dialog_text = "저장된 모든 전적을 삭제할까요? 이 작업은 되돌릴 수 없습니다."
	reset_dialog.confirmed.connect(_clear_records)
	add_child(reset_dialog)

	_refresh_stats()

func _open_stats() -> void:
	_refresh_stats()
	dimmer.visible = true
	panel.visible = true

func _close_stats() -> void:
	panel.visible = false
	dimmer.visible = false

func _clear_records() -> void:
	records.clear()
	_save_records()
	_refresh_stats()

func _refresh_stats() -> void:
	if summary_label == null:
		return
	var wins = 0
	var losses = 0
	var ties = 0
	for record in records:
		match str(record.get("result", "")):
			"승리": wins += 1
			"패배": losses += 1
			"무승부": ties += 1
	var total = wins + losses + ties
	var win_rate = 100.0 * wins / total if total > 0 else 0.0
	summary_label.text = "완료 핸드: %d    승리: %d    패배: %d    무승부: %d\n플레이어 승률: %.1f%%" % [total, wins, losses, ties, win_rate]

	var personality_lines: Array[String] = []
	for personality in PERSONALITIES:
		var p_wins = 0
		var p_losses = 0
		var p_ties = 0
		for record in records:
			if str(record.get("personality", "기존")) != personality:
				continue
			match str(record.get("result", "")):
				"승리": p_wins += 1
				"패배": p_losses += 1
				"무승부": p_ties += 1
		var p_total = p_wins + p_losses + p_ties
		var p_rate = 100.0 * p_wins / p_total if p_total > 0 else 0.0
		personality_lines.append("%s AI  —  %d전: 승 %d / 패 %d / 무 %d  ·  승률 %.1f%%" % [personality, p_total, p_wins, p_losses, p_ties, p_rate])
	personality_label.text = "성향별 결과\n" + "\n".join(personality_lines)

	var history_lines: Array[String] = []
	for i in range(records.size() - 1, maxi(-1, records.size() - 21), -1):
		var record = records[i]
		history_lines.append("핸드 #%s  ·  %s  ·  상대 성향: %s  ·  %s" % [str(record.get("hand_no", "?")), str(record.get("result", "?")), str(record.get("personality", "기존")), str(record.get("time", ""))])
	history_label.text = "\n".join(history_lines) if not history_lines.is_empty() else "아직 완료된 핸드가 없습니다.\n핸드가 끝나면 결과가 자동 저장됩니다."


func set_lobby_visible(visible_on_lobby: bool) -> void:
	if is_instance_valid(stats_button):
		stats_button.visible = visible_on_lobby
