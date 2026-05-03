class_name PrecisionRing
extends Control
## Desenha o anel circular de precisão no estilo do mockup.
## Verde no progresso, cinza claro no resto, com o número no centro.

@export_range(0.0, 1.0, 0.01) var value: float = 0.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()

@export var ring_thickness: float = 6.0
@export var color_fg: Color = Color(0.18, 0.78, 0.45)        # verde
@export var color_bg: Color = Color(0.85, 0.88, 0.92)        # cinza claro
@export var color_text: Color = Color(0.18, 0.78, 0.45)
@export var label_text: String = "Precisão"

var _font: Font


func _ready() -> void:
	_font = get_theme_default_font()
	custom_minimum_size = Vector2(96, 96)


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - ring_thickness * 0.5

	# Anel de fundo
	draw_arc(center, radius, 0.0, TAU, 64, color_bg, ring_thickness, true)

	# Progresso (começa do topo, sentido horário)
	if value > 0.0:
		var start := -TAU * 0.25
		var end := start + TAU * value
		draw_arc(center, radius, start, end, 64, color_fg, ring_thickness, true)

	# Número central
	var pct := int(round(value * 100.0))
	var pct_str := "%d%%" % pct
	var pct_size := _font.get_string_size(pct_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 22)
	draw_string(_font, center - pct_size * 0.5 + Vector2(0, pct_size.y * 0.35),
		pct_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 22, color_text)

	# Label "Precisão" pequeno acima do número
	var lbl_size := _font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
	draw_string(_font, center - Vector2(lbl_size.x * 0.5, pct_size.y * 0.6),
		label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, color_text)
