extends SceneTree
var scene

func _initialize():
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	run.call_deferred()

func wait_ready():
	while scene.busy: await process_frame
	await process_frame

func run():
	await wait_ready()
	assert(scene.stage_odds.size() == 1)
	assert(absf(scene.odds[0] + scene.odds[1] + scene.odds[2] - 100) < 0.001)
	await create_timer(0.2).timeout
	root.get_texture().get_image().save_png("res://preview.png")
	# Prediction is unchanged by the actual hidden opponent hand when RNG is fixed.
	var saved_hand = scene.game.hands[1].duplicate()
	scene.rng.seed = 127
	await scene.predict()
	var first = scene.odds.duplicate()
	scene.game.hands[1] = [0, 1]
	scene.rng.seed = 127
	await scene.predict()
	assert(scene.odds == first)
	scene.game.hands[1] = saved_hand
	scene.stage_odds = [scene.odds[0]]
	scene.calculator.popup_centered()
	await scene.calculate_custom_hand()
	assert(scene.calc_result.text.contains("AA"))
	assert(scene.calc_result.text.contains("패배"))
	await process_frame
	root.get_texture().get_image().save_png("res://calculator_preview.png")
	scene.picks[1].select(scene.picks[0].selected)
	await scene.calculate_custom_hand()
	assert(scene.calc_result.text.contains("같은 카드"))
	scene.calculator.hide()
	var guard = 0
	while not scene.game.over and guard < 60:
		guard += 1
		await wait_ready()
		if scene.game.pending: await scene.next_pressed()
		elif scene.game.actor == 0: await scene.play("call")
	assert(scene.game.over)
	assert(scene.game.stacks[0] + scene.game.stacks[1] == 100000)
	await process_frame
	root.get_texture().get_image().save_png("res://showdown_preview.png")
	await scene.next_pressed()
	await wait_ready()
	assert(scene.game.hand_no == 2)
	assert(scene.stage_odds.size() == 1)
	# Check the automatic all-in runout in the GUI as well as the pure game tests.
	if scene.game.actor == 0 and not scene.game.over:
		await scene.play("allin")
		await wait_ready()
		assert(scene.game.over)
	print("UI PASS: prediction isolation, custom hand calculator, duplicate rejection, full hand, next hand, all-in")
	quit()
