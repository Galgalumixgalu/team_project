extends Control

const Poker = preload("res://poker.gd")
const Game = preload("res://game.gd")
const INK = Color("edf3f6")
const MUTED = Color("a1b3c4")
const ACCENT = Color("70d6b2")
const BG = Color("111a24")
const SAMPLE_COUNT = 3000

var game = Game.new()
var rng = RandomNumberGenerator.new()
var font: Font
var busy = false
var odds = [0.0, 0.0, 0.0] # Win, tie, loss percentages.
var stage_odds = []
var progress = 0
var buttons = {}
var raise_amount: SpinBox
var calculator: AcceptDialog
var picks = []
var calc_button: Button
var calc_result: Label
var calc_busy = false

func _ready():
	rng.randomize()
	var system_font = SystemFont.new()
	system_font.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "Arial"])
	font = system_font
	var ui_theme = Theme.new()
	ui_theme.default_font = font
	ui_theme.default_font_size = 16
	theme = ui_theme
	build_ui()
	await start_hand()

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
	if value < 0:
		box(rect, Color("20483f"), 9)
		centered("·", pos.x + 42, pos.y + 65, 30, Color("597c70"))
	elif hidden:
		box(rect, Color("324a64"), 9)
		for i in range(4):
			for j in range(6): draw_circle(pos + Vector2(15 + i * 18, 14 + j * 17), 2, Color("6b849d"))
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
	label_at("TEXAS HOLD’EM", 30, 45, 27)
	label_at("기본 대전 + 핸드 승률 예측", 31, 72, 15, MUTED)
	if game.hands[0].is_empty(): return
	label_at("핸드 #%d   ·   블라인드 500 / 1,000" % game.hand_no, 30, 109, 14, MUTED)
	for i in range(5):
		box(Rect2(30 + i * 168, 125, 158, 36), Color("325649") if game.stage == i else Color("203040"), 7)
		centered(Game.STAGES[i], 109 + i * 168, 150, 15, ACCENT if game.stage == i else MUTED)
	box(Rect2(30, 178, 830, 405), Color("173f35"), 36)
	centered("컴퓨터  ·  " + chips(game.stacks[1]) + " 칩" + ("  [D]" if game.dealer == 1 else ""), 445, 211, 18)
	var showdown = game.stage == 4
	draw_card(game.hands[1][0], Vector2(352, 226), not showdown)
	draw_card(game.hands[1][1], Vector2(450, 226), not showdown)
	centered(hand_name(1) if showdown else "상대 패는 쇼다운에서 공개됩니다", 445, 363, 14, MUTED)
	centered("POT   " + chips(game.pot), 445, 403, 25, ACCENT)
	for i in range(5): draw_card(game.board[i] if i < game.board.size() else -1, Vector2(205 + i * 98, 425))
	centered("공개 카드", 445, 564, 13, MUTED)
	draw_card(game.hands[0][0], Vector2(31, 602))
	draw_card(game.hands[0][1], Vector2(129, 602))
	label_at("내 칩  " + chips(game.stacks[0]) + ("  [D]" if game.dealer == 0 else ""), 240, 629, 22)
	label_at(hand_name(0), 240, 660, 18, ACCENT)
	label_at("현재 베팅  나 %s / 컴퓨터 %s" % [chips(game.paid[0]), chips(game.paid[1])], 240, 691, 13, MUTED)
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
	box(Rect2(885, 496, 285, 220), Color("1b2b39"))
	label_at("단계별 예상 승률", 907, 531, 19)
	for i in range(4):
		label_at(Game.STAGES[i], 907, 570 + i * 35, 16, MUTED)
		label_at("%.1f%%" % stage_odds[i] if i < stage_odds.size() else "—", 1080, 570 + i * 35, 17, ACCENT)
	var status = game.message
	if not game.over:
		status = ("컴퓨터 판단 중…" if busy else "내 차례") if not game.pending else "베팅 완료 · 다음 단계로 진행하세요"
	label_at(status, 31, 788, 15, ACCENT)

func button(key: String, caption: String, rect: Rect2, callback: Callable):
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

func build_ui():
	button("calculator", "핸드별 승률 계산기", Rect2(950, 32, 220, 45), func(): calculator.popup_centered())
	raise_amount = SpinBox.new()
	raise_amount.position = Vector2(650, 634)
	raise_amount.size = Vector2(210, 44)
	raise_amount.step = 100
	add_child(raise_amount)
	button("fold", "폴드", Rect2(30, 731, 105, 39), func(): await play("fold"))
	button("call", "체크 / 콜", Rect2(145, 731, 160, 39), func(): await play("call"))
	button("raise", "레이즈", Rect2(315, 731, 115, 39), func():
		raise_amount.apply()
		await play("raise", int(raise_amount.value)))
	button("allin", "올인", Rect2(440, 731, 105, 39), func(): await play("allin"))
	button("next", "다음 단계", Rect2(555, 731, 305, 39), next_pressed)
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
		pick.item_selected.connect(func(_index): calc_result.text = "새 핸드를 선택했습니다. 계산을 눌러 주세요.")
		picks.append(pick)
		row.add_child(pick)
	calc_button = Button.new()
	calc_button.text = "이 핸드 승률 계산 (5,000회)"
	calc_button.custom_minimum_size.y = 42
	calc_button.pressed.connect(calculate_custom_hand)
	column.add_child(calc_button)
	calc_result = Label.new()
	calc_result.text = "카드 선택 후 계산을 누르세요.\ns = 같은 무늬 / o = 다른 무늬"
	calc_result.custom_minimum_size = Vector2(580, 110)
	column.add_child(calc_result)

func refresh():
	var enabled = not busy and not game.over and not game.pending and game.actor == 0
	for key in ["fold", "call", "raise", "allin"]: buttons[key].disabled = not enabled
	buttons.call.text = "체크" if game.owed(0) == 0 else "콜 " + chips(mini(game.owed(0), game.stacks[0]))
	buttons.raise.disabled = not enabled or not game.raise_possible(0) or game.max_target(0) < game.paid.max() + game.min_raise
	buttons.allin.disabled = not enabled or (game.max_target(0) > game.paid.max() and not game.raise_possible(0))
	raise_amount.max_value = game.max_target(0)
	raise_amount.min_value = mini(game.paid.max() + game.min_raise, game.max_target(0))
	raise_amount.editable = not buttons.raise.disabled
	buttons.next.disabled = busy or (not game.pending and not game.over)
	buttons.next.text = ("새 매치 · 각 50,000칩" if game.stacks.min() == 0 else "다음 핸드") if game.over else ("쇼다운" if game.stage == 3 else "다음 카드 공개")
	buttons.calculator.disabled = busy
	queue_redraw()

func start_hand():
	game.new_hand()
	stage_odds.clear()
	await predict()
	await drive()

func predict():
	busy = true
	progress = 0
	refresh()
	var wins = 0.0
	var ties = 0.0
	if game.board.size() == 5:
		await get_tree().process_frame
		var counts = Poker.river_prediction(game.hands[0], game.board)
		odds = [counts[0] * 100 / counts[2], counts[1] * 100 / counts[2], (counts[2] - counts[0] - counts[1]) * 100 / counts[2]]
	else:
		while progress < SAMPLE_COUNT:
			# Neither the actual opponent's cards nor burned cards are known to the player.
			var counts = Poker.sample(game.hands[0], game.board, [], 60, rng)
			wins += counts[0]
			ties += counts[1]
			progress += 60
			odds = [wins * 100 / progress, ties * 100 / progress, (progress - wins - ties) * 100 / progress]
			queue_redraw()
			await get_tree().process_frame
	progress = SAMPLE_COUNT
	stage_odds.append(odds[0])
	busy = false
	refresh()

func play(kind: String, target: int = 0):
	if busy: return
	if game.action(0, kind, target): await drive()

func next_pressed():
	if busy: return
	if game.over: await start_hand()
	elif game.pending:
		game.advance()
		if not game.over: await predict()
		await drive()

func drive():
	while not game.over:
		refresh()
		if game.pending:
			if game.stacks.min() == 0:
				busy = true
				refresh()
				await get_tree().create_timer(0.5).timeout
				game.advance()
				busy = false
				if not game.over: await predict()
				continue
			break
		if game.actor == 0: break
		busy = true
		refresh()
		await get_tree().create_timer(0.35).timeout
		var sums = [0.0, 0.0]
		for i in range(6):
			var batch = Poker.sample(game.hands[1], game.board, [], 50, rng)
			sums[0] += batch[0]
			sums[1] += batch[1]
			await get_tree().process_frame
		var strength = (sums[0] + sums[1] / 2) / 300
		var cost = mini(game.owed(1), game.stacks[1])
		var pot_odds = float(cost) / maxf(1, game.pot + cost)
		if cost > 0 and strength < pot_odds - 0.04:
			game.action(1, "fold")
		elif game.raise_possible(1) and (strength > 0.67 or rng.randf() < 0.05):
			game.action(1, "raise", mini(game.max_target(1), game.paid.max() + maxi(game.min_raise, int(game.pot * 0.5))))
		else: game.action(1, "call")
		busy = false
	refresh()

func calculate_custom_hand():
	if calc_busy: return
	var selected = [picks[0].get_selected_id(), picks[1].get_selected_id()]
	if selected[0] == selected[1]:
		calc_result.text = "같은 카드를 두 번 선택할 수 없습니다."
		return
	calc_busy = true
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
		calc_result.text = "%s · 계산 중 %d / 5,000" % [Poker.hand_key(selected), (i + 1) * 50]
		await get_tree().process_frame
	calc_result.text = "%s  (%s, %s)\n승리 %.1f%%  ·  무승부 %.1f%%  ·  패배 %.1f%%\n5,000회 시뮬레이션 추정치 · 상대 행동/성향은 반영하지 않음" % [Poker.hand_key(selected), Poker.card_text(selected[0]), Poker.card_text(selected[1]), wins / 50, ties / 50, (5000 - wins - ties) / 50]
	for pick in picks: pick.disabled = false
	calc_button.disabled = false
	calc_busy = false
