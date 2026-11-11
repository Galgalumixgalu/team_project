extends SceneTree
const P = preload("res://poker.gd")
const G = preload("res://game.gd")
var checks = 0
var failures = 0

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func cards(s: String) -> Array:
	var out = []
	for token in s.split(" "): out.append(P.code(token))
	return out

func compare(board: String, a: String, b: String, expected: int):
	var av = P.evaluate(cards(board + " " + a))
	var bv = P.evaluate(cards(board + " " + b))
	check(signi(av - bv) == expected, board + " / " + a + " vs " + b)

func _init():
	var cases = ["As Ks Qs Js Ts", "9h 8h 7h 6h 5h", "Ks Kh Kd Kc 2s", "As Ah Ad 9s 9h", "As Js 8s 5s 2s", "As 2h 3d 4c 5s", "Qs Qh Qd 9s 2h", "Qs Qh 9s 9h 2d", "As Ah 9s 7h 2d", "As Kh 9s 7h 2d"]
	for i in range(cases.size()): check(P.category(P.evaluate(cards(cases[i]))) == 9 - i, "category " + str(9 - i))
	compare("2s 7s 9s Kd 3h", "As 5c", "Qs Js", -1)
	compare("2h 6d 9c Js 3d", "Ac 8d", "Ks Qd", 1)
	compare("9d 4c 7h 2s 6c", "As 9c", "Kc 9h", 1)
	compare("5h 5c 8d 2s 9c", "Qs Qd", "Js Jd", 1)
	compare("As 9c 9s 5c 4d", "Ah Ad", "Kc Kd", 1)
	compare("8s 7h 6d 5c Ks", "9s 2c", "9h Qd", 0)
	compare("8s 7s 6s 5c Kd", "9h 2d", "As 3s", -1)
	compare("Ks Kh Kd 7s 9c", "Kc 2d", "7d 7h", 1)
	compare("Qs Qh 9s 9d 2c", "Qd 5s", "9c As", 1)
	compare("Th Js Qd Kc Ah", "2s 3c", "4s 5c", 0)
	compare("2s 3h 4d 5c Kd", "Ah Qs", "6s 9h", -1)
	compare("As Js 9s 5s 2d", "8s 3h", "7s Kh", 1)
	check(P.category(P.evaluate(cards("As Ah Ad Ks Kh Kd 2s"))) == 6, "double trips full house")
	var g = G.new()
	g.new_hand()
	check(g.actor == g.dealer, "preflop SB first")
	check(not g.action(0, "check"), "cannot check facing bet")
	check(not g.action(0, "raise", 1500), "under minimum raise rejected")
	g.action(0, "call")
	check(not g.pending and g.actor == 1, "BB retains option")
	g.action(1, "check")
	check(g.pending, "betting closes")
	g.advance()
	check(g.actor == 1 and g.board.size() == 3, "postflop BB first")
	var short = G.new()
	short.stacks = [1500, 98500]
	short.new_hand()
	short.action(0, "allin")
	check(not short.can_raise[0] and short.actor == 1, "short allin action")
	short.action(1, "call")
	check(short.pending and short.pot == 3000, "short stack matching")
	while not short.over: short.advance()
	check(short.stacks[0] + short.stacks[1] == 100000, "allin chip conservation")
	var refund = G.new()
	refund.stacks = [10000, 90000]
	refund.new_hand()
	refund.action(0, "call")
	refund.action(1, "allin")
	refund.action(0, "call")
	check(refund.pot == 20000 and refund.stacks[1] == 80000, "unmatched allin returned")
	while not refund.over: refund.advance()
	check(refund.stacks[0] + refund.stacks[1] == 100000, "refund conservation")
	var random = RandomNumberGenerator.new()
	random.seed = 42
	for n in range(300):
		var sim = G.new()
		sim.rng.seed = n + 1
		sim.new_hand()
		var guard = 0
		while not sim.over and guard < 200:
			guard += 1
			if sim.pending: sim.advance()
			else:
				var action = random.randi_range(0, 9)
				var seat = sim.actor
				if action == 0: sim.action(seat, "fold")
				elif action < 4 and sim.raise_possible(seat): sim.action(seat, "raise", mini(sim.max_target(seat), sim.paid.max() + sim.min_raise))
				elif action == 4 and sim.raise_possible(seat): sim.action(seat, "allin")
				else: sim.action(seat, "call")
			check(sim.stacks[0] + sim.stacks[1] + sim.pot == 100000, "conservation randomized")
			check(sim.stacks.min() >= 0, "nonnegative stack")
		check(sim.over, "termination randomized")
	var odds = P.sample(cards("As Ah"), [], cards("Ks Kh"), 2000, random)
	check(odds[0] / 2000.0 > 0.75 and odds[0] / 2000.0 < 0.87, "AA vs KK equity")
	var aces = P.sample(cards("As Ah"), [], [], 5000, random)
	check(aces[0] / 5000.0 > 0.81 and aces[0] / 5000.0 < 0.89, "AA versus unknown opponent")
	var weak = P.sample(cards("7s 2h"), [], [], 5000, random)
	check(weak[0] < aces[0] and weak[0] / 5000.0 < 0.4, "weak starting hand")
	var royal = P.river_prediction(cards("2c 3c"), cards("As Ks Qs Js Ts"))
	check(royal == [0.0, 990.0, 990], "board royal always ties")
	var nuts = P.river_prediction(cards("As Ks"), cards("Qs Js Ts 2c 3h"))
	check(nuts == [990.0, 0.0, 990], "exclusive royal always wins")
	var uncertain = P.river_prediction(cards("As 3h"), cards("2c 7d 9s Jh Kd"))
	check(uncertain[0] > 0 and uncertain[0] < 990, "river unknown opponent is not actual showdown")
	print("TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
