@tool
class_name StatChip
extends PanelContainer
## Indicador compacto de gamificação: ícone + número + rótulo.
##
## Um único componente cobre XP, streak, nível e sinais dominados — antes cada
## tela desenhava o seu com um emoji diferente ("🔥 0 dias", "⭐ 0 XP",
## "✦ 0 XP"), o que fazia três telas do mesmo app parecerem três produtos.

enum Tone { ACCENT, VIOLET, GOLD, PRIMARY, SUCCESS }

@export var icon: HSIcon.Name = HSIcon.Name.BOLT:
	set(v):
		icon = v
		_sync()

@export var value_text: String = "0":
	set(v):
		value_text = v
		_sync()

## Rótulo curto sob o número. Vazio esconde a linha e o chip vira uma pílula.
@export var label_text: String = "":
	set(v):
		label_text = v
		_sync()

@export var tone: Tone = Tone.ACCENT:
	set(v):
		tone = v
		_sync()

var _glyph: HSIcon
var _value: Label
var _label: Label
var _text_box: VBoxContainer


static func create(
	which: HSIcon.Name,
	value: String,
	label: String = "",
	tone_value: Tone = Tone.ACCENT
) -> StatChip:
	var chip := StatChip.new()
	chip.icon = which
	chip.value_text = value
	chip.label_text = label
	chip.tone = tone_value
	return chip


func _init() -> void:
	# Chip decorativo: PASS para não bloquear a rolagem de quem o contém.
	mouse_filter = Control.MOUSE_FILTER_PASS

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SPACE_XS + 2)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)

	_glyph = HSIcon.new()
	_glyph.custom_minimum_size = Vector2(46, 46)
	_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_glyph)

	_text_box = VBoxContainer.new()
	_text_box.add_theme_constant_override("separation", 0)
	_text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_text_box)

	_value = Label.new()
	_value.theme_type_variation = &"H3"
	_text_box.add_child(_value)

	_label = Label.new()
	_label.theme_type_variation = &"Caption"
	_text_box.add_child(_label)


func _ready() -> void:
	_sync()


func _sync() -> void:
	if _glyph == null:
		return

	_glyph.icon = icon
	_value.text = value_text
	_label.text = label_text
	_label.visible = not label_text.is_empty()

	var fg: Color = DS.ACCENT_INK
	var bg: Color = DS.ACCENT_TINT
	match tone:
		Tone.VIOLET:
			fg = DS.VIOLET_INK
			bg = DS.VIOLET_TINT
		Tone.GOLD:
			fg = DS.GOLD_INK
			bg = DS.GOLD_TINT
		Tone.PRIMARY:
			fg = DS.PRIMARY
			bg = DS.PRIMARY_TINT
		Tone.SUCCESS:
			fg = DS.SUCCESS_INK
			bg = DS.SUCCESS_TINT

	_glyph.color = fg
	# Regra da família de ícones: contorno é o padrão; preenchido significa
	# "conquistado" e fica reservado a StarRow e AchievementBadge. Misturar os
	# dois tratamentos na mesma tela é o que faz um app parecer montado.
	_glyph.filled = false
	_value.add_theme_color_override("font_color", fg)
	_label.add_theme_color_override("font_color", DS.alpha(fg, 0.75))

	add_theme_stylebox_override("panel",
		DS.fill(bg, DS.RADIUS_PILL, DS.SPACE_SM + 4, DS.SPACE_XS + 2))


## Atualiza o número contando, em vez de trocar de valor de uma vez —
## o usuário precisa ver que ganhou alguma coisa.
func animate_to(new_value: int, suffix: String = "") -> void:
	var from: int = int(value_text.split(" ")[0]) if value_text.is_valid_int() else 0
	value_text = "%d%s" % [new_value, suffix]
	Motion.count_up(_value, from, new_value, "%d" + suffix)
	Motion.pulse(self, 1.08)
