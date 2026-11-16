extends RefCounted

const Poker = preload("res://poker.gd")

# 매 핸드 시작 때 기존/성급/조심 중 하나를 같은 확률로 정합니다.
static func pick_personality(rng: RandomNumberGenerator) -> String:
	return ["기존", "성급", "조심"][rng.randi_range(0, 2)]

# 특정 카드 패턴이 있을 때만 가중 무작위 행동을 고릅니다.
# 패턴이 없으면 빈 문자열을 돌려 기존 AI 판단을 사용하게 합니다.
static func choose_action(hand: Array, board: Array, owed: int, can_raise: bool, rng: RandomNumberGenerator) -> String:
	if not _has_special_pattern(hand, board):
		return ""

	var actions: Array[String] = []
	var weights: Array[int] = []
	var total_weight = 0

	if can_raise:
		actions.append("raise")
		weights.append(35)
		total_weight += 35

	if owed > 0:
		actions.append("call")
		weights.append(35)
		total_weight += 35
	else:
		actions.append("check")
		weights.append(20)
		total_weight += 20

	actions.append("fold")
	weights.append(10)
	total_weight += 10

	var roll = rng.randi_range(1, total_weight)
	for i in range(actions.size()):
		roll -= weights[i]
		if roll <= 0:
			return actions[i]
	return actions.back()


# One decision API used by the controller. Game.gd still validates every action.
static func choose_betting_action(hand: Array, board: Array, owed: int, can_raise: bool, max_target: int, highest_paid: int, min_raise: int, pot: int, stack: int, personality: String, rng: RandomNumberGenerator) -> Dictionary:
	var pattern_action := ""
	if personality == "성급":
		pattern_action = choose_action(hand, board, owed, can_raise, rng)
	if pattern_action == "raise":
		return {"action": "raise", "target": _raise_target(max_target, highest_paid, min_raise, pot)}
	if pattern_action != "":
		return {"action": pattern_action, "target": 0}

	var totals := [0.0, 0.0]
	for i in range(6):
		var outcome: Array = Poker.sample(hand, board, [], 50, rng)
		totals[0] += outcome[0]
		totals[1] += outcome[1]
	var equity: float = (totals[0] + totals[1] / 2.0) / 300.0
	var call_cost: int = mini(owed, stack)
	var pot_odds: float = float(call_cost) / maxf(1.0, float(pot + call_cost))
	if personality == "조심":
		if call_cost > 0 and equity < pot_odds + 0.05:
			return {"action": "fold", "target": 0}
		if can_raise and equity >= 0.78:
			return {"action": "raise", "target": _raise_target(max_target, highest_paid, min_raise, pot)}
		return {"action": "call", "target": 0}
	if call_cost > 0 and equity < pot_odds - 0.04:
		return {"action": "fold", "target": 0}
	if can_raise and (equity > 0.67 or rng.randf() < 0.05):
		return {"action": "raise", "target": _raise_target(max_target, highest_paid, min_raise, pot)}
	return {"action": "call", "target": 0}

static func _raise_target(max_target: int, highest_paid: int, min_raise: int, pot: int) -> int:
	return mini(max_target, highest_paid + maxi(min_raise, int(pot * 0.5)))

static func _has_special_pattern(hand: Array, board: Array) -> bool:
	var cards = hand + board
	var rank_suits = {}
	var suit_ranks = [[], [], [], []]

	for card in cards:
		var rank = card % 13 + 2
		var suit = int(card / 13)
		if not rank_suits.has(rank):
			rank_suits[rank] = []
		if not rank_suits[rank].has(suit):
			rank_suits[rank].append(suit)
		if not suit_ranks[suit].has(rank):
			suit_ranks[suit].append(rank)
		# 에이스는 A-K-Q...뿐 아니라 A-2-3-4의 낮은 에이스로도 확인합니다.
		if rank == 14:
			if not rank_suits.has(1):
				rank_suits[1] = []
			rank_suits[1].append(suit)

	# 서로 다른 무늬가 섞인 3장 또는 4장의 연속 숫자가 있는지 확인합니다.
	for length in [3, 4]:
		for start in range(1, 15):
			if start + length - 1 > 14:
				continue
			var all_ranks_present = true
			var suits_in_run = []
			for rank in range(start, start + length):
				if not rank_suits.has(rank):
					all_ranks_present = false
					break
				for suit in rank_suits[rank]:
					if not suits_in_run.has(suit):
						suits_in_run.append(suit)
			if all_ranks_present and suits_in_run.size() >= 2:
				return true

	# 같은 무늬의 서로 다른 숫자 카드가 3장 이상이면 패턴으로 봅니다.
	for ranks_in_suit in suit_ranks:
		if ranks_in_suit.size() >= 3:
			return true

	return false
