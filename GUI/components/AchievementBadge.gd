@tool
class_name AchievementBadge
extends PanelContainer
## Cartão de conquista.
##
## Conquista bloqueada não some nem vira um cadeado mudo: mostra o mesmo
## desenho em cinza e o quanto falta. É o que transforma a lista de conquistas
## em objetivo em vez de troféu de vitrine.

var _glyph: HSIcon
var _title: Label
var _desc: Label
var _bar: ProgressBar
var _disc: PanelContainer


static func create(data: Dictionary) -> AchievementBadge:
	var badge := AchievementBadge.new()
	badge._apply(data)
	return badge


func _init() -> void:
	theme_type_variation = &"CardFlat"

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SPACE_SM)
	add_child(row)

	_disc = PanelContainer.new()
	_disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_disc)

	_glyph = HSIcon.new()
	_glyph.custom_minimum_size = Vector2(64, 64)
	_disc.add_child(_glyph)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", DS.SPACE_XXS)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(box)

	_title = Label.new()
	_title.theme_type_variation = &"H3"
	box.add_child(_title)

	_desc = Label.new()
	_desc.theme_type_variation = &"Caption"
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_desc)

	_bar = ProgressBar.new()
	_bar.theme_type_variation = &"ProgressBarThin"
	_bar.custom_minimum_size = Vector2(0, 14)
	_bar.max_value = 1.0
	_bar.show_percentage = false
	box.add_child(_bar)


func _apply(data: Dictionary) -> void:
	var unlocked: bool = bool(data.get("unlocked", false))
	var tone: StatChip.Tone = data.get("tone", StatChip.Tone.ACCENT)

	_glyph.icon = data.get("icon", HSIcon.Name.TROPHY)
	_glyph.filled = unlocked
	_title.text = String(data.get("title", ""))
	_desc.text = String(data.get("description", ""))

	var fg: Color = DS.ACCENT_INK
	var bg: Color = DS.ACCENT_TINT
	match tone:
		StatChip.Tone.VIOLET:
			fg = DS.VIOLET_INK
			bg = DS.VIOLET_TINT
		StatChip.Tone.GOLD:
			fg = DS.GOLD_INK
			bg = DS.GOLD_TINT
		StatChip.Tone.SUCCESS:
			fg = DS.SUCCESS_INK
			bg = DS.SUCCESS_TINT
		StatChip.Tone.PRIMARY:
			fg = DS.PRIMARY
			bg = DS.PRIMARY_TINT

	if unlocked:
		_glyph.color = fg
		_disc.add_theme_stylebox_override("panel",
			DS.fill(bg, DS.RADIUS_PILL, DS.SPACE_SM, DS.SPACE_SM))
		_title.add_theme_color_override("font_color", DS.TEXT)
		_desc.add_theme_color_override("font_color", DS.TEXT_MUTED)
		_bar.visible = false
	else:
		_glyph.color = DS.DISABLED
		_disc.add_theme_stylebox_override("panel",
			DS.fill(DS.DISABLED_TINT, DS.RADIUS_PILL, DS.SPACE_SM, DS.SPACE_SM))
		_title.add_theme_color_override("font_color", DS.TEXT_MUTED)
		_desc.add_theme_color_override("font_color", DS.TEXT_SUBTLE)
		_bar.visible = true
		_bar.value = 0.0
		Motion.fill_bar(_bar, float(data.get("progress", 0.0)))
		modulate = Color(1, 1, 1, 0.9)
