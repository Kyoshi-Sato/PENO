@tool
class_name MetricCard
extends PanelContainer
## Cartão de métrica: ícone + número grande + rótulo.
##
## Usado no resultado da lição (precisão / tentativas / tempo) e na tela de
## progresso, para que o mesmo dado tenha a mesma cara nos dois lugares.

@export var icon: HSIcon.Name = HSIcon.Name.TARGET:
	set(v):
		icon = v
		_sync()

@export var value_text: String = "—":
	set(v):
		value_text = v
		_sync()

@export var label_text: String = "":
	set(v):
		label_text = v
		_sync()

@export var accent: Color = DS.PRIMARY:
	set(v):
		accent = v
		_sync()

var _glyph: HSIcon
var _value: Label
var _label: Label


static func create(
	which: HSIcon.Name,
	value: String,
	label: String,
	tint: Color = DS.PRIMARY
) -> MetricCard:
	var card := MetricCard.new()
	card.icon = which
	card.value_text = value
	card.label_text = label
	card.accent = tint
	return card


func _init() -> void:
	theme_type_variation = &"CardSunken"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Card decorativo: sem PASS, o PanelContainer engole o arrasto do
	# ScrollContainer e a tela não rola em cima dele.
	mouse_filter = Control.MOUSE_FILTER_PASS

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", DS.SPACE_XXS)
	add_child(box)

	_glyph = HSIcon.new()
	_glyph.custom_minimum_size = Vector2(52, 52)
	_glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_glyph)

	_value = Label.new()
	_value.theme_type_variation = &"Metric"
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Este slot é dimensionado para número curto ("1", "78%", "00:18"). Um
	# valor comprido não pode empurrar a largura do card e desalinhar a
	# fileira inteira; se não couber, corta.
	_value.clip_text = true
	box.add_child(_value)

	_label = Label.new()
	_label.theme_type_variation = &"MetricLabel"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_label)


func _ready() -> void:
	_sync()


func _sync() -> void:
	if _glyph == null:
		return
	_glyph.icon = icon
	_glyph.color = accent
	_value.text = value_text
	_value.add_theme_color_override("font_color", accent)
	_label.text = label_text


## Anima o número entrando (usado quando o resultado da validação chega).
func reveal_number(to_value: int, suffix: String = "") -> void:
	Motion.count_up(_value, 0, to_value, "%d" + suffix)
