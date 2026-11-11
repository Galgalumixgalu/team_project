extends RefCounted
const Poker = preload("res://poker.gd")
const STAGES = ["프리플랍", "플랍", "턴", "리버", "쇼다운"]
var rng = RandomNumberGenerator.new()
var stacks = [50000, 50000]
var paid = [0, 0]
var acted = [false, false]
var can_raise = [true, true]
var hands = [[], []]
var deck = []
var board = []
var stage = 0
var dealer = 1
var actor = 0
var pot = 0
var min_raise = 1000
var pending = false
var over = true
var result = -1
var message = ""
var logs: Array[String] = []
var start_stack = 50000
var hand_no = 0

func _init():
	rng.randomize()

func note(s: String):
	message = s
	logs.push_front(s)
	if logs.size() > 50: logs.resize(50)

func pay(seat: int, amount: int):
	var chips = clampi(amount, 0, stacks[seat])
	stacks[seat] -= chips
	paid[seat] += chips
	pot += chips

func new_hand():
	if not over: return
	if stacks.min() <= 0: stacks = [50000, 50000]
	start_stack = stacks[0]
	hand_no += 1
	dealer = 1 - dealer
	deck = range(52)
	for i in range(51, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = deck[i]
		deck[i] = deck[j]
		deck[j] = temp
	hands = [[deck.pop_back(), deck.pop_back()], [deck.pop_back(), deck.pop_back()]]
	board = []
	paid = [0, 0]
	acted = [false, false]
	can_raise = [true, true]
	pot = 0
	stage = 0
	min_raise = 1000
	pending = false
	over = false
	result = -1
	logs.clear()
	pay(dealer, 500)
	pay(1 - dealer, 1000)
	actor = dealer
	note("핸드 #%d · SB 500 / BB 1,000" % hand_no)
	resolve()

func owed(seat: int) -> int:
	return maxi(0, paid[1 - seat] - paid[seat])

func max_target(seat: int) -> int:
	return paid[seat] + stacks[seat]

func raise_possible(seat: int) -> bool:
	return can_raise[seat] and stacks[1 - seat] > 0 and max_target(seat) > paid.max()

func action(seat: int, kind: String, target: int = 0) -> bool:
	if over or pending or actor != seat: return false
	var who = "플레이어" if seat == 0 else "컴퓨터"
	if kind == "fold":
		finish(1 - seat, who + " 폴드")
		return true
	if kind == "check" and owed(seat) > 0: return false
	if kind == "allin":
		target = max_target(seat)
		kind = "raise" if target > paid.max() else "call"
	if kind == "raise":
		if not raise_possible(seat): return false
		var highest = int(paid.max())
		target = mini(target, max_target(seat))
		var increment = target - highest
		if increment <= 0: return false
		if increment < min_raise and target != max_target(seat): return false
		if increment >= min_raise:
			min_raise = increment
			can_raise[1 - seat] = true
		acted[1 - seat] = false
		pay(seat, target - paid[seat])
		note(who + " 레이즈 → " + str(target))
	elif kind == "call" or kind == "check":
		var amount = mini(owed(seat), stacks[seat])
		pay(seat, amount)
		note(who + (" 체크" if amount == 0 else " 콜 " + str(amount)))
	else: return false
	acted[seat] = true
	can_raise[seat] = false
	actor = 1 - seat
	resolve()
	return true

func resolve():
	# A player facing an all-in still gets a fold/call decision.
	if stacks.min() == 0:
		var live = 0 if stacks[0] > 0 else 1
		if stacks[live] > 0 and owed(live) > 0:
			actor = live
			return
		refund()
		pending = true
	elif acted[0] and acted[1] and paid[0] == paid[1]:
		pending = true

func refund():
	var extra = absi(paid[0] - paid[1])
	if extra > 0:
		var seat = 0 if paid[0] > paid[1] else 1
		stacks[seat] += extra
		paid[seat] -= extra
		pot -= extra
		note("매칭되지 않은 칩 %d 반환" % extra)

func advance():
	if not pending or over: return
	if stage == 3:
		stage = 4
		var a = Poker.evaluate(hands[0] + board)
		var b = Poker.evaluate(hands[1] + board)
		finish(0 if a > b else (1 if b > a else 2), "쇼다운")
		return
	stage += 1
	deck.pop_back() # Burn card.
	for i in range(3 if stage == 1 else 1): board.append(deck.pop_back())
	paid = [0, 0]
	acted = [false, false]
	can_raise = [true, true]
	min_raise = 1000
	actor = 1 - dealer
	pending = stacks.min() == 0
	note(STAGES[stage] + " 공개")

func finish(winner: int, reason: String):
	refund()
	result = winner
	over = true
	pending = false
	if winner == 2:
		var half = int(pot / 2)
		stacks[0] += half
		stacks[1] += half
		stacks[1 - dealer] += pot % 2
	else: stacks[winner] += pot
	note(reason + " · " + ["플레이어 승리", "컴퓨터 승리", "무승부 / 팟 분배"][winner] + " · 팟 " + str(pot))
	pot = 0
