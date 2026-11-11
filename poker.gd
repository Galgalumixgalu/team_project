extends RefCounted

const NAMES = ["하이카드", "원페어", "투페어", "트리플", "스트레이트", "플러시", "풀하우스", "포카드", "스트레이트 플러시", "로열 스트레이트 플러시"]
const RANKS = "23456789TJQKA"

static func rank_of(c: int) -> int:
	return c % 13 + 2

static func card_text(c: int) -> String:
	return ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"][c % 13] + ["♠", "♥", "♦", "♣"][c / 13]

static func code(s: String) -> int:
	return "shdc".find(s[-1]) * 13 + RANKS.find(s[0])

static func straight_high(ranks: Array) -> int:
	var run = 0
	for r in range(14, 0, -1):
		if ranks.has(14 if r == 1 else r):
			run += 1
			if run == 5:
				return r + 4
		else:
			run = 0
	return 0

static func pack(category: int, ranks: Array) -> int:
	var value = category
	for i in range(5):
		value = value * 15 + (int(ranks[i]) if i < ranks.size() else 0)
	return value

# Evaluates the best five cards directly; lower cards never break a five-card tie.
static func evaluate(cards: Array) -> int:
	var counts = {}
	var suits = [[], [], [], []]
	for c in cards:
		var r = rank_of(c)
		counts[r] = counts.get(r, 0) + 1
		suits[c / 13].append(r)
	var ranks = counts.keys()
	ranks.sort()
	ranks.reverse()
	var flush: Array = []
	for suit in suits:
		if suit.size() >= 5:
			flush = suit
			flush.sort()
			flush.reverse()
	if not flush.is_empty():
		var sf = straight_high(flush)
		if sf:
			return pack(9 if sf == 14 else 8, [sf])
	var four = []
	var three = []
	var pairs = []
	for r in ranks:
		if counts[r] == 4: four.append(r)
		if counts[r] >= 3: three.append(r)
		if counts[r] >= 2: pairs.append(r)
	if not four.is_empty():
		var rest = ranks.duplicate()
		rest.erase(four[0])
		return pack(7, [four[0], rest[0]])
	if not three.is_empty():
		var rest = pairs.duplicate()
		rest.erase(three[0])
		if not rest.is_empty(): return pack(6, [three[0], rest[0]])
	if not flush.is_empty(): return pack(5, flush.slice(0, 5))
	var straight = straight_high(ranks)
	if straight: return pack(4, [straight])
	if not three.is_empty():
		var rest = ranks.duplicate()
		rest.erase(three[0])
		return pack(3, [three[0]] + rest.slice(0, 2))
	if pairs.size() >= 2:
		var rest = ranks.duplicate()
		rest.erase(pairs[0])
		rest.erase(pairs[1])
		return pack(2, pairs.slice(0, 2) + rest.slice(0, 1))
	if pairs.size() == 1:
		var rest = ranks.duplicate()
		rest.erase(pairs[0])
		return pack(1, pairs + rest.slice(0, 3))
	return pack(0, ranks.slice(0, 5))

static func category(value: int) -> int:
	return value / 759375

static func hand_key(cards: Array) -> String:
	var a = cards[0]
	var b = cards[1]
	if rank_of(a) < rank_of(b):
		var temp = a
		a = b
		b = temp
	var key = RANKS[a % 13] + RANKS[b % 13]
	if rank_of(a) != rank_of(b): key += "s" if int(a / 13) == int(b / 13) else "o"
	return key

# An empty opponent array samples uniformly from all unseen two-card hands.
static func sample(hero: Array, board: Array, opponent: Array, n: int, rng: RandomNumberGenerator) -> Array:
	var remaining = []
	for c in range(52):
		if not hero.has(c) and not board.has(c) and not opponent.has(c): remaining.append(c)
	var wins = 0.0
	var ties = 0.0
	for trial in range(n):
		var pool = remaining.duplicate()
		var enemy = opponent.duplicate()
		var community = board.duplicate()
		while enemy.size() < 2:
			var i = rng.randi_range(0, pool.size() - 1)
			enemy.append(pool[i])
			pool.remove_at(i)
		while community.size() < 5:
			var i = rng.randi_range(0, pool.size() - 1)
			community.append(pool[i])
			pool.remove_at(i)
		var a = evaluate(hero + community)
		var b = evaluate(enemy + community)
		if a > b: wins += 1
		elif a == b: ties += 1
	return [wins, ties]

# River prediction: all C(45, 2) unseen opponent hands, without using the real hand.
static func river_prediction(hero: Array, board: Array) -> Array:
	assert(hero.size() == 2 and board.size() == 5)
	var remaining = []
	for c in range(52):
		if not hero.has(c) and not board.has(c): remaining.append(c)
	var own = evaluate(hero + board)
	var wins = 0.0
	var ties = 0.0
	var total = 0
	for i in range(remaining.size()):
		for j in range(i + 1, remaining.size()):
			var enemy = evaluate([remaining[i], remaining[j]] + board)
			wins += int(own > enemy)
			ties += int(own == enemy)
			total += 1
	return [wins, ties, total]
