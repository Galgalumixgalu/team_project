extends AcceptDialog

signal applied

const SAVE_PATH := "user://skins.cfg"
const IDS := ["classic", "moon", "koi"]
const CARD_NAMES := ["황금 은행잎", "은빛 초승달", "비단잉어"]
const TABLE_NAMES := ["에메랄드", "밤하늘", "붉은 물결"]
const CARDS := [preload("res://assets/ui/card_back.png"), preload("res://assets/ui/skins/moon_card.png"), preload("res://assets/ui/skins/koi_card.png")]
const TABLES := [preload("res://assets/ui/table_8seat.png"), preload("res://assets/ui/skins/moon_table.png"), preload("res://assets/ui/skins/koi_table.png")]

var card_index := 0
var table_index := 0
var card_buttons: Array[Button] = []
var table_buttons: Array[Button] = []

func _ready() -> void:
	title = "스킨"
	exclusive = true
	transient = true
	ok_button_text = "적용"
	add_cancel_button("취소")
	var settings := ConfigFile.new()
	if settings.load(SAVE_PATH) == OK:
		card_index = maxi(0, IDS.find(settings.get_value("skin", "card", "classic")))
		table_index = maxi(0, IDS.find(settings.get_value("skin", "table", "classic")))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	_add_options(column, "카드 뒷면", CARDS, CARD_NAMES, card_buttons)
	_add_options(column, "테이블 배경", TABLES, TABLE_NAMES, table_buttons)
	confirmed.connect(_apply)

func _add_options(column: VBoxContainer, caption: String, textures: Array, names: Array, buttons: Array[Button]) -> void:
	var heading := Label.new()
	heading.text = caption
	column.add_child(heading)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var group := ButtonGroup.new()
	for i in range(textures.size()):
		var option := Button.new()
		option.custom_minimum_size = Vector2(184, 148)
		option.text = names[i]
		option.icon = textures[i]
		option.expand_icon = true
		option.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		option.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		option.toggle_mode = true
		option.button_group = group
		var selected := StyleBoxFlat.new()
		selected.bg_color = Color("183c37")
		selected.border_color = Color("70d6b2")
		selected.set_border_width_all(3)
		selected.set_corner_radius_all(8)
		option.add_theme_stylebox_override("pressed", selected)
		option.add_theme_stylebox_override("hover_pressed", selected)
		row.add_child(option)
		buttons.append(option)

func open() -> void:
	card_buttons[card_index].button_pressed = true
	table_buttons[table_index].button_pressed = true
	popup_centered(Vector2i(630, 470))

func _apply() -> void:
	card_index = card_buttons.find(card_buttons[0].button_group.get_pressed_button())
	table_index = table_buttons.find(table_buttons[0].button_group.get_pressed_button())
	var settings := ConfigFile.new()
	settings.set_value("skin", "card", IDS[card_index])
	settings.set_value("skin", "table", IDS[table_index])
	if settings.save(SAVE_PATH) != OK:
		push_warning("스킨 설정을 저장하지 못했습니다.")
	applied.emit()
