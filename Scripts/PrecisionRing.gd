@tool
class_name PrecisionRing
extends Control
## Anel de precisão: arco de progresso com a porcentagem no centro.
##
## Antes vivia no RecordingState, ancorado por offsets fixos, exibindo 0%
## permanentes porque nada nunca escrevia em `value` — era decoração. Agora
## é o número principal da tela de resultado, onde a precisão de fato existe.

@export_range(0.0, 1.0, 0.01) var value: float = 0.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()

@export var ring_thickness: float = 18.0:
	set(v):
		ring_thickness = v
		queue_redraw()

@export var color_fg: Color = DS.ACCENT:
	set(v):
		color_fg = v
		queue_redraw()

@export var color_bg: Color = DS.PRIMARY_TINT:
	set(v):
		color_bg = v
		queue_redraw()

@export var color_text: Color = DS.TEXT:
	set(v):
		color_text = v
		queue_redraw()

@export var label_text: String = "precisão":
	set(v):
		label_text = v
		queue_redraw()

## Tamanhos vêm do Design System em vez de números soltos (eram 22 e 11,
## ilegíveis num canvas de 1080 de largura).
@export var value_font_size: int = DS.TEXT_H1
@export var label_font_size: int = DS.TEXT_LABEL

var _font: Font


func _ready() -> void:
	_font = get_theme_default_font()
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(260, 260)
	# O anel é só desenho, mas Control nasce com MOUSE_FILTER_STOP: dentro de
	# um ScrollContainer ele virava um bloco de 300x300 onde o arrasto do dedo
	# não rolava a tela. IGNORE devolve o toque para quem rola.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Anima o preenchimento do anel — o número cresce junto com o arco.
func animate_to(target: float, duration: float = DS.DUR_SLOW) -> void:
	var t := create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(self, "value", clampf(target, 0.0, 1.0), duration)


func _draw() -> void:
	if _font == null:
		_font = get_theme_default_font()
	if _font == null:
		return

	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - ring_thickness * 0.5

	draw_arc(center, radius, 0.0, TAU, 96, color_bg, ring_thickness, true)

	# Progresso a partir do topo, sentido horário.
	if value > 0.0:
		var start := -TAU * 0.25
		draw_arc(center, radius, start, start + TAU * value, 96, color_fg,
			ring_thickness, true)

	var pct_str := "%d%%" % int(round(value * 100.0))
	var pct_size := _font.get_string_size(
		pct_str, HORIZONTAL_ALIGNMENT_CENTER, -1, value_font_size)
	var lbl_size := _font.get_string_size(
		label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, label_font_size)

	# Bloco número + rótulo centralizado verticalmente como um conjunto,
	# em vez de cada um posicionado por conta própria.
	var gap := 6.0
	var block_h := pct_size.y + gap + lbl_size.y
	var top := center.y - block_h * 0.5

	draw_string(_font, Vector2(center.x - pct_size.x * 0.5, top + pct_size.y * 0.78),
		pct_str, HORIZONTAL_ALIGNMENT_CENTER, -1, value_font_size, color_text)

	if not label_text.is_empty():
		draw_string(_font,
			Vector2(center.x - lbl_size.x * 0.5, top + pct_size.y + gap + lbl_size.y * 0.78),
			label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, label_font_size,
			DS.alpha(color_text, 0.65))
