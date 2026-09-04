@tool
class_name IconButton
extends Button
## Botão circular só de ícone. Substitui os botões que usavam glifos de texto
## ("‹", "⚙", "👁", "<") e por isso mudavam de tamanho e alinhamento conforme
## a fonte instalada.

enum Tone { LIGHT, SURFACE, ON_DARK }

@export var glyph_icon: HSIcon.Name = HSIcon.Name.NONE:
	set(v):
		glyph_icon = v
		_sync()

@export var tone: Tone = Tone.LIGHT:
	set(v):
		tone = v
		_sync()

@export var diameter: int = DS.ICON_BUTTON:
	set(v):
		diameter = v
		_sync()

## Fração do botão ocupada pelo ícone.
@export_range(0.3, 0.9, 0.01) var icon_ratio: float = 0.48:
	set(v):
		icon_ratio = v
		_sync()

var _glyph: HSIcon


static func create(
	which: HSIcon.Name,
	tone_value: Tone = Tone.LIGHT,
	size_px: int = DS.ICON_BUTTON
) -> IconButton:
	var b := IconButton.new()
	b.glyph_icon = which
	b.tone = tone_value
	b.diameter = size_px
	return b


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	_glyph = HSIcon.new()
	_glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glyph)


func _ready() -> void:
	_sync()
	if not Engine.is_editor_hint():
		Motion.attach_press(self)


func _sync() -> void:
	if _glyph == null:
		return

	custom_minimum_size = Vector2(diameter, diameter)
	_glyph.icon = glyph_icon
	# O ícone é centralizado com uma margem proporcional, não com um
	# offset fixo — assim o mesmo componente serve a 80px e a 160px.
	var inset: float = float(diameter) * (1.0 - icon_ratio) * 0.5
	_glyph.offset_left = inset
	_glyph.offset_top = inset
	_glyph.offset_right = -inset
	_glyph.offset_bottom = -inset

	match tone:
		Tone.SURFACE:
			theme_type_variation = &"IconButtonSurface"
			_glyph.color = DS.PRIMARY
		Tone.ON_DARK:
			theme_type_variation = &"IconButtonOnDark"
			_glyph.color = DS.TEXT_ON_PRIMARY
		_:
			theme_type_variation = &"IconButton"
			_glyph.color = DS.PRIMARY


## Permite recolorir o ícone sem sair do tom (ex.: favorito ativo).
func set_icon_color(c: Color) -> void:
	if _glyph:
		_glyph.color = c


func set_icon_filled(v: bool) -> void:
	if _glyph:
		_glyph.filled = v
