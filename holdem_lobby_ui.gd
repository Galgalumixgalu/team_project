extends Control

const LOBBY_BACKGROUND = preload("res://assets/ui/lobby.png")

signal offline_selected
signal skins_requested
signal settings_requested
signal online_setup_requested
signal create_room_requested(project_url: String, public_key: String)
signal join_room_requested(project_url: String, public_key: String, room_code: String)
signal back_requested

var overlay: ColorRect
var status_label: Label
var project_url_input: LineEdit
var public_key_input: LineEdit
var room_input: LineEdit

func show_main_menu() -> void:
	var column := _new_overlay("TEXAS HOLD’EM", "게임 방식을 선택해 주세요")
	_add_button(column, "AI와 오프라인 플레이", func(): offline_selected.emit())
	_add_button(column, "친구와 온라인 플레이 · 방 코드", func(): online_setup_requested.emit())
	_add_button(column, "스킨 설정", func(): skins_requested.emit())
	var settings := Button.new()
	settings.text = "게임 설정"
	overlay.add_child(settings)
	settings.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	settings.offset_left = -165
	settings.offset_right = -30
	settings.offset_top = 32
	settings.offset_bottom = 77
	settings.pressed.connect(func(): settings_requested.emit())

func show_online_setup(project_url: String, public_key: String) -> void:
	var column := _new_overlay("친구와 온라인 대전", "한 명이 방을 만들고 친구는 같은 Supabase 설정과 방 코드로 참가합니다.")
	_add_label(column, "Supabase 프로젝트 URL", 14)
	project_url_input = _add_line_edit(column, project_url, "https://프로젝트ID.supabase.co")
	_add_label(column, "Publishable key 또는 anon public key · service_role 키는 사용하지 마세요", 14)
	public_key_input = _add_line_edit(column, public_key, "공개 키를 입력하세요")
	public_key_input.secret = true
	_add_label(column, "참가 시에는 친구가 알려준 방 코드를 입력하세요.", 14)
	room_input = _add_line_edit(column, "", "예: A7K4Q9WP")
	status_label = _add_label(column, "주소와 공개 키는 이 기기의 게임 설정에 저장됩니다.", 14)
	_add_label(column, "테스트용 공개 채널입니다. 실제 돈이나 민감한 정보를 사용하지 마세요.", 13)
	_add_button(column, "방 만들기", func(): create_room_requested.emit(project_url_input.text, public_key_input.text))
	_add_button(column, "방 코드로 참가", func(): join_room_requested.emit(project_url_input.text, public_key_input.text, room_input.text))
	_add_button(column, "뒤로", func(): back_requested.emit())

func show_waiting_status(text: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = text

func show_table() -> void:
	close_screen()

func close_screen() -> void:
	if is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null
	status_label = null
	project_url_input = null
	public_key_input = null
	room_input = null

func _new_overlay(title: String, subtitle: String) -> VBoxContainer:
	close_screen()
	overlay = ColorRect.new()
	overlay.color = Color(0.035, 0.055, 0.075, 0.985)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var background := TextureRect.new()
	background.texture = LOBBY_BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color("102026eb")
	surface.border_color = Color("837350")
	surface.set_border_width_all(1)
	surface.set_corner_radius_all(14)
	surface.content_margin_left = 24
	surface.content_margin_right = 24
	surface.content_margin_top = 20
	surface.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", surface)
	panel.custom_minimum_size = Vector2(650, 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size = Vector2(610, 0)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 27)
	column.add_child(heading)
	var detail := Label.new()
	detail.text = subtitle
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(detail)
	return column

func _add_label(parent: VBoxContainer, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label

func _add_line_edit(parent: VBoxContainer, value: String, placeholder: String) -> LineEdit:
	var field := LineEdit.new()
	field.text = value
	field.placeholder_text = placeholder
	field.custom_minimum_size.y = 40
	parent.add_child(field)
	return field

func _add_button(parent: VBoxContainer, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(0, 42)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
