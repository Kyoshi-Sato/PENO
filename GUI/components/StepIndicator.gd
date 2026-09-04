@tool
class_name StepIndicator
extends Control
## ASSISTA → PRATIQUE → RESULTADO.
##
## Resolve o problema central do fluxo: nada na tela dizia em que etapa da
## lição o usuário estava nem qual era a próxima. Fica fixo no topo dos três
## estados, então o mesmo elemento acompanha a pessoa do início ao fim.

const STEPS: Array[Dictionary] = [
	{"label": "ASSISTA", "icon": HSIcon.Name.EYE},
	{"label": "PRATIQUE", "icon": HSIcon.Name.CAMERA},
	{"label": "RESULTADO", "icon": HSIcon.Name.TROPHY},
]

const DOT_RADIUS := 28.0
const HEIGHT := 100

## 0 = assista, 1 = pratique, 2 = resultado.
@export_range(0, 2) var current: int = 0:
	set(v):
		current = clampi(v, 0, STEPS.size() - 1)
		_sync()

## Sobre a câmera o indicador precisa inverter o contraste.
@export var on_dark: bool = false:
	set(v):
		on_dark = v
		_sync()

var _glyphs: Array[HSIcon] = []
var _labels: Array[Label] = []


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for spec: Dictionary in STEPS:
		var g := HSIcon.new()
		g.icon = spec["icon"]
		g.weight = 2.4
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(g)
		_glyphs.append(g)

		var l := Label.new()
		l.text = String(spec["label"])
		l.theme_type_variation = &"Caption"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		_labels.append(l)


func _ready() -> void:
	resized.connect(_sync)
	_sync()


## Centro X de cada etapa, distribuído com meia-célula nas pontas para o
## traço entre as etapas não sobrar para fora.
func _step_x(i: int) -> float:
	var n: float = float(STEPS.size())
	return size.x * ((float(i) + 0.5) / n)


func _sync() -> void:
	var cy := DOT_RADIUS + 6.0
	for i in range(_glyphs.size()):
		var cx := _step_x(i)
		var g: HSIcon = _glyphs[i]
		var l: Label = _labels[i]

		g.size = Vector2(DOT_RADIUS, DOT_RADIUS) * 1.1
		g.position = Vector2(cx, cy) - g.size * 0.5

		l.size = Vector2(size.x / float(STEPS.size()), 32.0)
		l.position = Vector2(cx - l.size.x * 0.5, cy + DOT_RADIUS + 10.0)

		var done: bool = i < current
		var active: bool = i == current

		if active:
			g.color = DS.PRIMARY_DARK if not on_dark else DS.PRIMARY_DARK
			l.add_theme_color_override("font_color",
				DS.TEXT_ON_PRIMARY if on_dark else DS.PRIMARY)
		elif done:
			g.color = DS.TEXT_ON_PRIMARY if on_dark else DS.SUCCESS_INK
			l.add_theme_color_override("font_color",
				DS.alpha(DS.TEXT_ON_PRIMARY, 0.8) if on_dark else DS.SUCCESS_INK)
		else:
			g.color = DS.alpha(DS.TEXT_ON_PRIMARY, 0.55) if on_dark else DS.TEXT_SUBTLE
			l.add_theme_color_override("font_color",
				DS.alpha(DS.TEXT_ON_PRIMARY, 0.55) if on_dark else DS.TEXT_SUBTLE)

	queue_redraw()


func _draw() -> void:
	var cy := DOT_RADIUS + 6.0

	# Conectores primeiro, para ficarem atrás dos discos.
	for i in range(STEPS.size() - 1):
		var from := Vector2(_step_x(i) + DOT_RADIUS + 8.0, cy)
		var to := Vector2(_step_x(i + 1) - DOT_RADIUS - 8.0, cy)
		var done: bool = i < current
		var c: Color
		if on_dark:
			c = DS.alpha(DS.TEXT_ON_PRIMARY, 0.85 if done else 0.30)
		else:
			c = DS.SUCCESS if done else DS.HAIRLINE_STRONG
		draw_line(from, to, c, 5.0, true)

	for i in range(STEPS.size()):
		var center := Vector2(_step_x(i), cy)
		var done: bool = i < current
		var active: bool = i == current

		var fill_color: Color
		if active:
			fill_color = DS.ACCENT
		elif done:
			fill_color = DS.SUCCESS_TINT if not on_dark else DS.alpha(DS.SURFACE, 0.9)
		else:
			fill_color = DS.SURFACE_SUNKEN if not on_dark else DS.alpha(DS.SURFACE, 0.22)

		if active:
			draw_circle(center, DOT_RADIUS + 9.0, DS.alpha(DS.ACCENT, 0.28))
		draw_circle(center, DOT_RADIUS, fill_color)

		if not active and not on_dark:
			var edge: Color = DS.SUCCESS if done else DS.HAIRLINE_STRONG
			draw_arc(center, DOT_RADIUS - 1.0, 0.0, TAU, 32, edge, 2.5, true)
