@tool
class_name AppHeader
extends HBoxContainer
## Cabeçalho de tela: voltar + título (+ ação opcional à direita).
##
## Padroniza a altura, o alvo de toque do "voltar" e o alinhamento do título.
## Antes cada tela tinha o seu: um Button "‹" de 44px, outro "<" de 80x60 e um
## terceiro posicionado por offsets absolutos (32, 40, 144, 152).

signal back_pressed

enum Tone { LIGHT, ON_DARK }

@export var title: String = "":
	set(v):
		title = v
		if _title:
			_title.text = v

@export var subtitle: String = "":
	set(v):
		subtitle = v
		if _subtitle:
			_subtitle.text = v
			_subtitle.visible = not v.is_empty()

@export var tone: Tone = Tone.LIGHT:
	set(v):
		tone = v
		_sync_tone()

@export var show_back: bool = true:
	set(v):
		show_back = v
		if _back:
			_back.visible = v

var _back: IconButton
var _title: Label
var _subtitle: Label
var _slot: HBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", DS.SPACE_SM)
	custom_minimum_size = Vector2(0, DS.ICON_BUTTON)

	_back = IconButton.create(HSIcon.Name.BACK, IconButton.Tone.LIGHT)
	_back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(_back)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 0)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(text_box)

	_title = Label.new()
	_title.theme_type_variation = &"H2"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(_title)

	_subtitle = Label.new()
	_subtitle.theme_type_variation = &"Caption"
	_subtitle.visible = false
	text_box.add_child(_subtitle)

	# Espaço reservado para uma ação à direita (engrenagem, favorito).
	# Fica sempre presente para o título não pular quando a ação aparece.
	_slot = HBoxContainer.new()
	_slot.add_theme_constant_override("separation", DS.SPACE_XS)
	_slot.custom_minimum_size = Vector2(DS.ICON_BUTTON, 0)
	_slot.alignment = BoxContainer.ALIGNMENT_END
	add_child(_slot)


func _ready() -> void:
	_sync_tone()


func _sync_tone() -> void:
	if _title == null:
		return
	var on_dark: bool = tone == Tone.ON_DARK
	_title.theme_type_variation = &"OnPrimaryH2" if on_dark else &"H2"
	_subtitle.add_theme_color_override("font_color",
		DS.alpha(DS.TEXT_ON_PRIMARY, 0.75) if on_dark else DS.TEXT_SUBTLE)
	if _back:
		_back.tone = IconButton.Tone.ON_DARK if on_dark else IconButton.Tone.LIGHT


## Adiciona um controle à direita do título.
func add_action(control: Control) -> void:
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slot.add_child(control)
