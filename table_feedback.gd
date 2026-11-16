extends Control

const DURATION := 1.0
const FILE := "user://table_audio.cfg"
const KEYS := ["preflop", "flop", "turn", "river", "showdown", "raise", "fold", "call", "check", "allin", "you", "computer", "opponent", "win_self", "win_cpu", "win_opponent", "draw"]
var clips := {}
var voice := AudioStreamPlayer.new()
var effect := AudioStreamPlayer.new()
var heading := Label.new()
var detail := Label.new()
var settings := AcceptDialog.new()
var banner := PanelContainer.new()
var gains := {"전체": 80.0, "음성": 90.0, "효과음": 70.0}
var animation: Tween
var save_timer := Timer.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for key in KEYS:
		clips[key] = load("res://assets/audio/%s.wav" % key)
	effect.stream = preload("res://assets/audio/click.wav")
	add_child(effect)
	add_child(voice)
	var config := ConfigFile.new()
	if config.load(FILE) == OK:
		for key in gains:
			gains[key] = clampf(float(config.get_value("sound", key, gains[key])), 0, 100)
	update_volume()
	add_child(save_timer)
	save_timer.one_shot = true
	save_timer.wait_time = 0.25
	save_timer.timeout.connect(save)
	add_child(banner)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner.offset_left = -225
	banner.offset_right = 225
	banner.offset_top = -56
	banner.offset_bottom = 56
	var style := StyleBoxFlat.new()
	style.bg_color = Color("10232cf5")
	style.border_color = Color("cbb57b")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	banner.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_child(column)
	for label in [detail, heading]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
	detail.add_theme_color_override("font_color", Color("87d9ba"))
	heading.add_theme_font_size_override("font_size", 31)
	banner.hide()
	settings.title = "게임 설정"
	settings.ok_button_text = "닫기"
	settings.transient = true
	settings.exclusive = true
	add_child(settings)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 18)
	settings.add_child(rows)
	for key in gains:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var name_label := Label.new()
		name_label.text = key
		name_label.custom_minimum_size.x = 70
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.custom_minimum_size = Vector2(230, 32)
		slider.value = gains[key]
		row.add_child(slider)
		var value_label := Label.new()
		value_label.custom_minimum_size.x = 58
		value_label.text = "%d%%" % slider.value
		row.add_child(value_label)
		slider.value_changed.connect(func(value):
			gains[key] = value
			value_label.text = "%d%%" % value
			update_volume()
			save_timer.start())
	var preview := Button.new()
	preview.text = "소리 미리 듣기"
	preview.pressed.connect(func(): speak("raise"))
	rows.add_child(preview)
	settings.visibility_changed.connect(func():
		if not settings.visible: save())

func update_volume():
	for entry in [[voice, "음성"], [effect, "효과음"]]:
		var gain: float = gains["전체"] * gains[entry[1]] / 10000.0
		entry[0].volume_db = linear_to_db(gain) if gain > 0 else -80.0
		if gain == 0: entry[0].stop()

func save():
	var config := ConfigFile.new()
	for key in gains:
		config.set_value("sound", key, gains[key])
	if config.save(FILE) != OK: push_warning("음향 설정을 저장하지 못했습니다.")

func open_settings():
	settings.popup_centered(Vector2i(430, 290))

func click():
	if gains["전체"] * gains["효과음"] > 0: effect.play()

func speak(key: String):
	if clips.has(key) and gains["전체"] * gains["음성"] > 0:
		voice.stream = clips[key]
		voice.play()

func slide(title_text: String, subtitle: String, key: String):
	if animation: animation.kill()
	heading.text = title_text
	detail.text = subtitle
	banner.modulate.a = 0
	banner.offset_left = -249
	banner.offset_right = 201
	banner.show()
	speak(key)
	animation = create_tween()
	animation.tween_property(banner, "modulate:a", 1.0, 0.18)
	animation.parallel().tween_property(banner, "offset_left", -225.0, 0.18)
	animation.parallel().tween_property(banner, "offset_right", 225.0, 0.18)
	animation.tween_interval(DURATION - 0.43)
	animation.tween_property(banner, "modulate:a", 0.0, 0.25)
	animation.tween_callback(banner.hide)

func _exit_tree():
	if animation: animation.kill()
	voice.stop()
	effect.stop()
	if not save_timer.is_stopped(): save()
