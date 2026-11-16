extends Control

signal action_requested(action: String, target: int)
signal next_requested
signal settings_requested
signal exit_requested

const Poker = preload("res://poker.gd")
const Game = preload("res://game.gd")
const INK = Color("edf3f6")
const MUTED = Color("a1b3c4")
const ACCENT = Color("70d6b2")
const BG = Color("111a24")
const SAMPLE_COUNT = 3000
const SkinPicker = preload("res://skin_picker.gd")
var skin_picker := SkinPicker.new()
const POT_CHIPS = preload("res://assets/ui/pot_chips.png")

var game
var font: Font
var busy := false
var game_started := false
var network_mode := false
var network_role := ""
var ai_personality := "기존"
var odds: Array = [0.0, 0.0, 0.0]
var stage_odds: Array = []
var progress := 0
var buttons: Dictionary = {}
var raise_amount: SpinBox
var calculator: AcceptDialog
var picks: Array = []
var calc_button: Button
var calc_result: Label
var calc_busy := false
var calc_chart: Control
var calc_samples := PackedFloat32Array()

func _ready() -> void:
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "Arial"])
	font = system_font
	var ui_theme := Theme.new()
	ui_theme.default_font = font
	ui_theme.default_font_size = 16
	theme = ui_theme
	build_ui()
	add_child(skin_picker)
	skin_picker.applied.connect(queue_redraw)

func update_state(state: Dictionary) -> void:
	game = state.get("game")
	busy = bool(state.get("busy", false))
	game_started = bool(state.get("game_started", false))
	network_mode = bool(state.get("network_mode", false))
	network_role = str(state.get("network_role", ""))
	ai_personality = str(state.get("ai_personality", "기존"))
	odds = state.get("odds", [0.0, 0.0, 0.0])
	stage_odds = state.get("stage_odds", [])
	progress = int(state.get("progress", 0))
	_refresh_controls()
	queue_redraw()

func _local_seat() -> int:
	return 1 if network_mode and network_role == "guest" else 0

func box(rect: Rect2, color: Color, radius: int = 12):
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	draw_style_box(style, rect)

func label_at(s: String, x: float, y: float, pixels: int = 18, color: Color = INK):
	draw_string(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, color)

func centered(s: String, x: float, y: float, pixels: int = 18, color: Color = INK):
	label_at(s, x - font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x / 2, y, pixels, color)

func chips(value: int) -> String:
	var s = str(value)
	var result = ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0: result += ","
		result += s[i]
	return result

func draw_card(value: int, pos: Vector2, hidden: bool = false):
	var rect = Rect2(pos, Vector2(84, 114))
	if hidden or value < 0:
		draw_texture_rect(SkinPicker.CARDS[skin_picker.card_index], rect, false)
	else:
		box(rect, Color("f3f3eb"), 9)
		var suit = int(value / 13)
		var color = Color("ca505c") if suit in [1, 2] else Color("1e3448")
		var rank_text = Poker.card_text(value).left(-1)
		label_at(rank_text, pos.x + 9, pos.y + 26, 22, color)
		centered(["♠", "♥", "♦", "♣"][suit], pos.x + 42, pos.y + 77, 42, color)
		label_at(rank_text, pos.x + 57, pos.y + 103, 16, color)

func hand_name(seat: int) -> String:
	if game.board.size() < 3: return "시작 핸드 " + Poker.hand_key(game.hands[seat])
	return Poker.NAMES[Poker.category(Poker.evaluate(game.hands[seat] + game.board))]

func _draw():
	draw_rect(Rect2(0, 0, 1200, 800), BG)
	label_at("TEXAS HOLD’EM", 420, 45, 27)
	label_at("방 코드로 친구와 온라인 대전" if network_mode else "싱글 플레이 · AI 성향은 핸드마다 무작위", 421, 72, 15, MUTED)
	if not game_started or game == null or game.hands[_local_seat()].is_empty(): return
	label_at("핸드 #%d   ·   블라인드 500 / 1,000" % game.hand_no, 30, 109, 14, MUTED)
	for i in range(5):
		box(Rect2(30 + i * 168, 125, 158, 36), Color("325649") if game.stage == i else Color("203040"), 7)
		centered(Game.STAGES[i], 109 + i * 168, 150, 15, ACCENT if game.stage == i else MUTED)
	var table_texture: Texture2D = SkinPicker.TABLES[skin_picker.table_index]
	var texture_size := table_texture.get_size()
	var table_region := Rect2(Vector2(0, texture_size.y * 94 / 1024), Vector2(texture_size.x, texture_size.y * 836 / 1024))
	draw_texture_rect_region(table_texture, Rect2(30, 178, 830, 405), table_region)
	var my_seat = _local_seat()
	var opponent_seat = 1 - my_seat
	var opponent_title = "친구" if network_mode else "컴퓨터 (%s)" % ai_personality
	centered("내 베팅", 225, 203, 13, MUTED)
	centered(chips(game.paid[my_seat]) + " 칩", 225, 222, 16)
	centered("상대 베팅", 660, 203, 13, MUTED)
	centered(chips(game.paid[opponent_seat]) + " 칩", 660, 222, 16)
	centered("%s  ·  %s 칩" % [opponent_title, chips(game.stacks[opponent_seat])] + ("  [D]" if game.dealer == opponent_seat else ""), 445, 211, 18)
	var showdown = game.stage == 4
	var opponent_hand: Array = game.hands[opponent_seat]
	if showdown and opponent_hand.size() == 2:
		draw_card(opponent_hand[0], Vector2(352, 226))
		draw_card(opponent_hand[1], Vector2(450, 226))
	else:
		draw_card(-1, Vector2(352, 226), true)
		draw_card(-1, Vector2(450, 226), true)
	centered(hand_name(opponent_seat) if showdown else "상대 패는 쇼다운에서 공개됩니다", 445, 363, 14, MUTED)
	var pot_text := "POT   " + chips(game.pot)
	var pot_width := font.get_string_size(pot_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x
	var pot_left := 445.0 - (pot_width + 44.0) / 2.0
	draw_texture_rect(POT_CHIPS, Rect2(pot_left, 373, 38, 38), false)
	label_at(pot_text, pot_left + 44, 403, 25, ACCENT)
	for i in range(5): draw_card(game.board[i] if i < game.board.size() else -1, Vector2(205 + i * 98, 425))
	centered("공개 카드", 445, 564, 13, MUTED)
	draw_card(game.hands[my_seat][0], Vector2(31, 602))
	draw_card(game.hands[my_seat][1], Vector2(129, 602))
	label_at("내 칩  " + chips(game.stacks[my_seat]) + ("  [D]" if game.dealer == my_seat else ""), 240, 629, 22)
	label_at(hand_name(my_seat), 240, 660, 18, ACCENT)
	label_at("현재 베팅  나 %s / 상대 %s" % [chips(game.paid[my_seat]), chips(game.paid[opponent_seat])], 240, 691, 13, MUTED)
	label_at("레이즈 총액", 650, 619, 14, MUTED)
	box(Rect2(885, 125, 285, 354), Color("1b2b39"))
	label_at("내 핸드 예상 승률", 907, 158, 20)
	label_at("%.1f%%" % odds[0], 905, 223, 49, ACCENT)
	label_at("승리 %.1f%%" % odds[0], 907, 262, 17)
	label_at("무승부 %.1f%%" % odds[1], 907, 292, 17, MUTED)
	label_at("패배 %.1f%%" % odds[2], 907, 322, 17, MUTED)
	label_at("내 카드 + 공개 카드 기준", 907, 365, 14, MUTED)
	label_at("상대는 임의의 핸드로 가정", 907, 389, 14, MUTED)
	label_at("계산 중 %d / %d" % [progress, SAMPLE_COUNT] if progress < SAMPLE_COUNT else ("리버: 상대 990가지 전수 계산" if game.board.size() == 5 else "3,000회 시뮬레이션 · 추정치"), 907, 431, 13, ACCENT)
	label_at("예측은 실제 승패를 보장하지 않습니다", 907, 457, 11, MUTED)
	_draw_stage_chart()
	var status = game.message
	if network_mode and game.over:
		status = status.replace("플레이어", "호스트").replace("컴퓨터", "참가자")
	if not game.over:
		if game.pending:
			status = "베팅 완료 · 다음 단계로 진행하세요"
		elif busy:
			status = "상대 판단 중…" if network_mode else "컴퓨터 판단 중…"
		else:
			status = "내 차례" if game.actor == _local_seat() else ("친구 차례" if network_mode else "컴퓨터 차례")
	label_at(status, 31, 788, 15, ACCENT)

func _draw_stage_chart() -> void:
	box(Rect2(885, 496, 285, 220), Color("1b2b39"))
	label_at("내 승률 그래프", 907, 531, 19)
	var plot := Rect2(942, 558, 200, 100)
	for tick in [0, 50, 100]:
		var y: float = plot.end.y - plot.size.y * tick / 100.0
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color("415360"))
		label_at("%d%%" % tick, 895, y + 4, 12, MUTED)
	var points := PackedVector2Array()
	for i in range(4):
		var x := plot.position.x + plot.size.x * i / 3.0
		centered(Game.STAGES[i], x, 681, 13, MUTED)
		var rate: float
		if i < stage_odds.size():
			rate = stage_odds[i]
		elif i == game.stage and progress > 0 and progress < SAMPLE_COUNT:
			rate = odds[0]
		else:
			continue
		points.append(Vector2(x, plot.end.y - plot.size.y * rate / 100.0))
		centered("%.1f%%" % rate, x, 702, 13, ACCENT)
	if points.size() > 1:
		draw_polyline(points, ACCENT, 3.0, true)
	for point in points:
		draw_circle(point, 4.5, ACCENT)

func _add_button(key: String, caption: String, rect: Rect2, callback: Callable):
	var b = Button.new()
	b.text = caption
	b.position = rect.position
	b.size = rect.size
	var style = StyleBoxFlat.new()
	style.bg_color = Color("2c455b")
	style.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", style)
	var hover = style.duplicate()
	hover.bg_color = Color("3c5d76")
	b.add_theme_stylebox_override("hover", hover)
	b.pressed.connect(callback)
	add_child(b)
	buttons[key] = b

func build_ui() -> void:
	_add_button("settings", "게임 설정", Rect2(190, 32, 125, 45), func(): settings_requested.emit())
	_add_button("skins", "스킨", Rect2(795, 32, 120, 45), skin_picker.open)
	_add_button("calculator", "핸드별 승률 계산기", Rect2(950, 32, 220, 45), func(): calculator.popup_centered())
	raise_amount = SpinBox.new()
	raise_amount.position = Vector2(650, 634)
	raise_amount.size = Vector2(210, 44)
	raise_amount.step = 100
	add_child(raise_amount)
	_add_button("fold", "폴드", Rect2(30, 731, 105, 39), func(): action_requested.emit("fold", 0))
	_add_button("call", "체크 / 콜", Rect2(145, 731, 160, 39), func(): action_requested.emit("call", 0))
	_add_button("raise", "레이즈", Rect2(315, 731, 115, 39), func():
		raise_amount.apply()
		action_requested.emit("raise", int(raise_amount.value)))
	_add_button("allin", "올인", Rect2(440, 731, 105, 39), func(): action_requested.emit("allin", 0))
	_add_button("next", "다음 단계", Rect2(555, 731, 305, 39), func(): next_requested.emit())
	calculator = AcceptDialog.new()
	calculator.title = "시작 핸드별 승률 예측"
	calculator.min_size = Vector2i(630, 390)
	add_child(calculator)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	calculator.add_child(column)
	var explanation = Label.new()
	explanation.text = "카드 두 장을 선택하면 해당 시작 핸드의 승률을 예측합니다.\n공개 카드 없이 임의의 상대 1명과 대결하는 조건입니다."
	column.add_child(explanation)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	column.add_child(row)
	for i in range(2):
		var pick = OptionButton.new()
		pick.custom_minimum_size = Vector2(220, 42)
		for c in range(52): pick.add_item(Poker.card_text(c), c)
		pick.select(12 if i == 0 else 25)
		pick.item_selected.connect(func(_index):
			calc_samples.clear()
			calc_chart.hide()
			calc_result.text = "새 핸드를 선택했습니다. 계산을 눌러 주세요.")
		picks.append(pick)
		row.add_child(pick)
	calc_button = Button.new()
	calc_button.text = "이 핸드 승률 계산 (5,000회)"
	calc_button.custom_minimum_size.y = 42
	calc_button.pressed.connect(calculate_custom_hand)
	column.add_child(calc_button)
	calc_chart = Control.new()
	calc_chart.custom_minimum_size = Vector2(580, 115)
	calc_chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	calc_chart.draw.connect(_draw_calc_chart)
	column.add_child(calc_chart)
	calc_chart.hide()
	calc_result = Label.new()
	calc_result.text = "카드 선택 후 계산을 누르세요.\ns = 같은 무늬 / o = 다른 무늬"
	calc_result.custom_minimum_size = Vector2(580, 110)
	column.add_child(calc_result)
	_add_button("exit", "나가기", Rect2(30, 32, 150, 45), func(): exit_requested.emit())
	buttons.exit.tooltip_text = "게임을 나가고 플레이 방식 선택 화면으로 돌아갑니다."

func _draw_calc_chart() -> void:
	var left := 52.0
	var right := calc_chart.size.x - 28.0
	var top := 15.0
	var bottom := 84.0
	for tick in [0, 50, 100]:
		var y := lerpf(bottom, top, tick / 100.0)
		calc_chart.draw_line(Vector2(left, y), Vector2(right, y), Color("415360"))
		calc_chart.draw_string(font, Vector2(2, y + 4), "%d%%" % tick, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
	calc_chart.draw_string(font, Vector2(left, 107), "0회", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
	calc_chart.draw_string(font, Vector2(right - 50, 107), "5,000회", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
	var points := PackedVector2Array()
	for i in range(calc_samples.size()):
		points.append(Vector2(lerpf(left, right, (i + 1) / 100.0), lerpf(bottom, top, calc_samples[i] / 100.0)))
	if points.size() > 1:
		calc_chart.draw_polyline(points, ACCENT, 2, true)
	if not points.is_empty():
		calc_chart.draw_circle(points[-1], 3, ACCENT)

func calculate_custom_hand() -> void:
	if calc_busy: return
	calc_samples.clear()
	calc_chart.hide()
	var selected = [picks[0].get_selected_id(), picks[1].get_selected_id()]
	if selected[0] == selected[1]:
		calc_result.text = "같은 카드를 두 번 선택할 수 없습니다."
		return
	calc_busy = true
	calc_chart.show()
	calc_button.disabled = true
	for pick in picks: pick.disabled = true
	var custom_rng = RandomNumberGenerator.new()
	custom_rng.randomize()
	var wins = 0.0
	var ties = 0.0
	for i in range(100):
		var sample = Poker.sample(selected, [], [], 50, custom_rng)
		wins += sample[0]
		ties += sample[1]
		calc_samples.append(100.0 * wins / ((i + 1) * 50))
		calc_chart.queue_redraw()
		calc_result.text = "%s · 계산 중 %d / 5,000" % [Poker.hand_key(selected), (i + 1) * 50]
		await get_tree().process_frame
	calc_result.text = "%s  (%s, %s)\n승리 %.1f%%  ·  무승부 %.1f%%  ·  패배 %.1f%%\n5,000회 시뮬레이션 추정치 · 상대 행동/성향은 반영하지 않음" % [Poker.hand_key(selected), Poker.card_text(selected[0]), Poker.card_text(selected[1]), wins / 50, ties / 50, (5000 - wins - ties) / 50]
	for pick in picks: pick.disabled = false
	calc_button.disabled = false
	calc_busy = false

func _refresh_controls() -> void:
	if game == null or buttons.is_empty():
		return
	if not game_started:
		for key in ["fold", "call", "raise", "allin", "next"]:
			buttons[key].disabled = true
		buttons.exit.visible = false
		buttons.calculator.disabled = true
		return
	var seat := _local_seat()
	var enabled: bool = not busy and not game.over and not game.pending and game.actor == seat
	for key in ["fold", "call", "raise", "allin"]:
		buttons[key].disabled = not enabled
	buttons.call.text = "체크" if game.owed(seat) == 0 else "콜 " + chips(mini(game.owed(seat), game.stacks[seat]))
	buttons.raise.disabled = not enabled or not game.raise_possible(seat) or game.max_target(seat) < game.paid.max() + game.min_raise
	buttons.allin.disabled = not enabled or (game.max_target(seat) > game.paid.max() and not game.raise_possible(seat))
	raise_amount.max_value = game.max_target(seat)
	raise_amount.min_value = mini(game.paid.max() + game.min_raise, game.max_target(seat))
	raise_amount.editable = not buttons.raise.disabled
	buttons.next.disabled = busy or (not game.pending and not game.over)
	buttons.next.text = ("새 매치 · 각 50,000칩" if game.stacks.min() == 0 else "다음 핸드") if game.over else ("쇼다운" if game.stage == 3 else "다음 카드 공개")
	buttons.calculator.disabled = busy
	buttons.exit.visible = true
	buttons.exit.disabled = busy
