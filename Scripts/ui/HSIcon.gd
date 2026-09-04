@tool
class_name HSIcon
extends Control
## Ícone vetorial desenhado em runtime — família única, sem assets e sem deps.
##
## Por que não texturas: o app misturava emojis (🔥 ⭐ 👋 🔒 📷 👁 ⚙ ▶ ♡) que
## mudam de desenho conforme a fonte do sistema, não aceitam cor da marca e
## quebram o alinhamento vertical dentro de botões. Desenhando aqui, todos os
## ícones compartilham grade, espessura de traço e cor do Design System.
##
## Todo ícone é desenhado numa grade de 24x24 e escalado para `size`, então a
## espessura do traço acompanha o tamanho e nada fica serrilhado.

const GRID := 24.0

enum Name {
	NONE,
	# navegação
	HOME, LESSONS, CAMERA, PROGRESS, PROFILE,
	SETTINGS, BACK, FORWARD, CLOSE,
	# ação
	PLAY, PLAY_SLOW, REFRESH, EYE, EYE_OFF,
	# estado
	CHECK, CHECK_CIRCLE, CROSS, LOCK, TARGET, CLOCK,
	# gamificação
	STAR, FLAME, BOLT, TROPHY, SPARKLE, HEART,
	# domínio
	HAND,
}

@export var icon: Name = Name.NONE:
	set(v):
		icon = v
		queue_redraw()

@export var color: Color = DS.TEXT:
	set(v):
		color = v
		queue_redraw()

## Preenchido em vez de contornado. Usado para estados "conquistados"
## (estrela ganha, coração favoritado) contra o mesmo ícone vazado.
@export var filled: bool = false:
	set(v):
		filled = v
		queue_redraw()

## Espessura do traço na grade de 24 — 2.0 é o padrão da família.
@export var weight: float = 2.0:
	set(v):
		weight = v
		queue_redraw()


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(48, 48)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _get_minimum_size() -> Vector2:
	return Vector2(24, 24)


## Escala e offset que centralizam a grade 24x24 dentro do Control,
## preservando proporção.
func _fit() -> Array:
	var s: float = minf(size.x, size.y) / GRID
	var off := (size - Vector2(GRID, GRID) * s) * 0.5
	return [s, off]


func _draw() -> void:
	if icon == Name.NONE:
		return

	var fit: Array = _fit()
	var s: float = fit[0]
	var off: Vector2 = fit[1]
	if s <= 0.0:
		return

	draw_set_transform(off, 0.0, Vector2(s, s))
	_draw_icon()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------
#  primitivas (todas em unidades da grade 24x24)
# ------------------------------------------------------------

func _stroke(points: PackedVector2Array, closed: bool = false) -> void:
	var pts := points
	if closed and pts.size() > 1:
		pts = pts.duplicate()
		pts.append(pts[0])
	draw_polyline(pts, color, weight, true)


func _shape(points: PackedVector2Array) -> void:
	if filled:
		draw_colored_polygon(points, color)
	else:
		_stroke(points, true)


func _circle(center: Vector2, radius: float) -> void:
	if filled:
		draw_circle(center, radius, color)
	else:
		draw_arc(center, radius, 0.0, TAU, 48, color, weight, true)


func _ring(center: Vector2, radius: float) -> void:
	draw_arc(center, radius, 0.0, TAU, 48, color, weight, true)


func _arc(center: Vector2, radius: float, from: float, to: float) -> void:
	draw_arc(center, radius, from, to, 32, color, weight, true)


func _rounded_rect(from: Vector2, to: Vector2, radius: float) -> void:
	var pts := PackedVector2Array()
	var r: float = minf(radius, minf(to.x - from.x, to.y - from.y) * 0.5)
	var corners := [
		[Vector2(to.x - r, from.y + r), -TAU * 0.25],
		[Vector2(to.x - r, to.y - r), 0.0],
		[Vector2(from.x + r, to.y - r), TAU * 0.25],
		[Vector2(from.x + r, from.y + r), TAU * 0.5],
	]
	for c: Array in corners:
		var center: Vector2 = c[0]
		var start: float = c[1]
		for i in range(7):
			var a: float = start + TAU * 0.25 * (float(i) / 6.0)
			pts.append(center + Vector2(cos(a), sin(a)) * r)
	_shape(pts)


## Estrela de N pontas — usada pela nota da lição.
func _star(center: Vector2, outer: float, inner: float, points: int = 5) -> void:
	var pts := PackedVector2Array()
	for i in range(points * 2):
		var r: float = outer if i % 2 == 0 else inner
		var a: float = -TAU * 0.25 + TAU * float(i) / float(points * 2)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	_shape(pts)


## Bezier quadrática amostrada — curvas orgânicas (olho, coração).
func _quad(a: Vector2, ctrl: Vector2, b: Vector2, steps: int = 12) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return pts


# ------------------------------------------------------------
#  desenhos
# ------------------------------------------------------------

func _draw_icon() -> void:
	match icon:
		Name.HOME:
			_stroke(PackedVector2Array([
				Vector2(2.8, 10.8), Vector2(12, 3.2), Vector2(21.2, 10.8)]))
			_stroke(PackedVector2Array([
				Vector2(5.4, 9.4), Vector2(5.4, 20.4), Vector2(18.6, 20.4),
				Vector2(18.6, 9.4)]))

		Name.LESSONS:
			_stroke(PackedVector2Array([
				Vector2(12, 6.4), Vector2(4, 4.6), Vector2(4, 18.4), Vector2(12, 20.2)]))
			_stroke(PackedVector2Array([
				Vector2(12, 6.4), Vector2(20, 4.6), Vector2(20, 18.4), Vector2(12, 20.2)]))

		Name.CAMERA:
			_stroke(PackedVector2Array([
				Vector2(8.4, 7.0), Vector2(9.7, 4.2), Vector2(14.3, 4.2), Vector2(15.6, 7.0)]))
			var was: bool = filled
			filled = false
			_rounded_rect(Vector2(3, 6.6), Vector2(21, 20.2), 3.2)
			filled = was
			_ring(Vector2(12, 13.4), 4.0)

		Name.PROGRESS:
			for bar: Vector2 in [Vector2(6.2, 13.4), Vector2(12, 7.6), Vector2(17.8, 15.2)]:
				draw_line(Vector2(bar.x, 20.2), Vector2(bar.x, bar.y), color, weight * 1.6, true)

		Name.PROFILE:
			_ring(Vector2(12, 8.8), 3.9)
			_arc(Vector2(12, 21.6), 6.8, TAU * 0.5, TAU)

		Name.SETTINGS:
			# Dentes curtos e grossos cruzando um aro externo. Sem o aro, os
			# raios sozinhos liam como um sol.
			for i in range(8):
				var a: float = TAU * float(i) / 8.0
				var d := Vector2(cos(a), sin(a))
				draw_line(Vector2(12, 12) + d * 6.6, Vector2(12, 12) + d * 9.3,
					color, weight * 2.1, true)
			_ring(Vector2(12, 12), 7.0)
			_ring(Vector2(12, 12), 3.1)

		Name.BACK:
			_stroke(PackedVector2Array([
				Vector2(15.2, 4.8), Vector2(8.2, 12), Vector2(15.2, 19.2)]))

		Name.FORWARD:
			_stroke(PackedVector2Array([
				Vector2(8.8, 4.8), Vector2(15.8, 12), Vector2(8.8, 19.2)]))

		Name.CLOSE:
			draw_line(Vector2(6.2, 6.2), Vector2(17.8, 17.8), color, weight, true)
			draw_line(Vector2(17.8, 6.2), Vector2(6.2, 17.8), color, weight, true)

		Name.PLAY:
			draw_colored_polygon(PackedVector2Array([
				Vector2(8.2, 4.8), Vector2(19.2, 12), Vector2(8.2, 19.2)]), color)

		Name.PLAY_SLOW:
			draw_colored_polygon(PackedVector2Array([
				Vector2(9.6, 7.6), Vector2(16.8, 12), Vector2(9.6, 16.4)]), color)
			_arc(Vector2(12, 12), 9.4, -TAU * 0.32, TAU * 0.18)
			_arc(Vector2(12, 12), 9.4, TAU * 0.32, TAU * 0.68)

		Name.REFRESH:
			_arc(Vector2(12, 12), 7.8, -TAU * 0.20, TAU * 0.62)
			draw_colored_polygon(PackedVector2Array([
				Vector2(15.4, 2.6), Vector2(20.4, 6.2), Vector2(14.6, 8.4)]), color)

		Name.EYE, Name.EYE_OFF:
			_stroke(_quad(Vector2(2.8, 12.4), Vector2(12, 4.2), Vector2(21.2, 12.4)))
			_stroke(_quad(Vector2(2.8, 12.4), Vector2(12, 20.2), Vector2(21.2, 12.4)))
			_circle(Vector2(12, 12.4), 3.0)
			if icon == Name.EYE_OFF:
				draw_line(Vector2(4.4, 20.0), Vector2(19.6, 4.4), color, weight * 1.3, true)

		Name.CHECK:
			_stroke(PackedVector2Array([
				Vector2(5.2, 12.6), Vector2(9.8, 17.4), Vector2(18.8, 6.8)]))

		Name.CHECK_CIRCLE:
			_ring(Vector2(12, 12), 8.9)
			_stroke(PackedVector2Array([
				Vector2(7.4, 12.3), Vector2(10.7, 15.7), Vector2(16.6, 8.6)]))

		Name.CROSS:
			_ring(Vector2(12, 12), 8.9)
			draw_line(Vector2(8.6, 8.6), Vector2(15.4, 15.4), color, weight, true)
			draw_line(Vector2(15.4, 8.6), Vector2(8.6, 15.4), color, weight, true)

		Name.LOCK:
			_arc(Vector2(12, 11.2), 4.3, TAU * 0.5, TAU)
			_rounded_rect(Vector2(5.4, 11.0), Vector2(18.6, 20.6), 2.6)

		Name.TARGET:
			_ring(Vector2(12, 12), 8.7)
			_ring(Vector2(12, 12), 4.9)
			draw_circle(Vector2(12, 12), 1.9, color)

		Name.CLOCK:
			_ring(Vector2(12, 12), 8.7)
			draw_line(Vector2(12, 12), Vector2(12, 6.8), color, weight, true)
			draw_line(Vector2(12, 12), Vector2(15.8, 13.8), color, weight, true)

		Name.STAR:
			_star(Vector2(12, 12.4), 9.2, 3.9)

		Name.FLAME:
			# Ponta fina, base larga e uma segunda chama interna. É a chama
			# interna que separa a silhueta de uma gota d'água nos tamanhos
			# pequenos do chip — tentar sugerir isso com um recorte no próprio
			# contorno só produzia uma gota com um amassado.
			_shape(PackedVector2Array([
				Vector2(12.0, 1.6), Vector2(13.6, 5.4), Vector2(15.8, 7.8),
				Vector2(17.8, 11.2), Vector2(18.6, 15.0), Vector2(17.0, 18.8),
				Vector2(13.6, 21.8), Vector2(10.4, 21.8), Vector2(7.0, 18.8),
				Vector2(5.4, 15.0), Vector2(6.2, 11.2), Vector2(8.2, 8.0),
				Vector2(10.4, 5.4)]))
			if not filled:
				_stroke(PackedVector2Array([
					Vector2(12.0, 10.2), Vector2(14.2, 13.6), Vector2(14.6, 16.8),
					Vector2(12.0, 19.8), Vector2(9.4, 16.8), Vector2(9.8, 13.6)]),
					true)

		Name.BOLT:
			_shape(PackedVector2Array([
				Vector2(13.6, 2.4), Vector2(6.2, 13.6), Vector2(11.2, 13.6),
				Vector2(10.4, 21.6), Vector2(17.8, 10.4), Vector2(12.8, 10.4)]))

		Name.TROPHY:
			_shape(PackedVector2Array([
				Vector2(7.8, 3.4), Vector2(16.2, 3.4), Vector2(16.2, 9.6),
				Vector2(12, 14.2), Vector2(7.8, 9.6)]))
			_arc(Vector2(7.8, 6.4), 2.8, TAU * 0.25, TAU * 0.75)
			_arc(Vector2(16.2, 6.4), 2.8, -TAU * 0.25, TAU * 0.25)
			draw_line(Vector2(12, 14.2), Vector2(12, 18.0), color, weight, true)
			draw_line(Vector2(8.0, 20.4), Vector2(16.0, 20.4), color, weight * 1.4, true)

		Name.SPARKLE:
			_shape(PackedVector2Array([
				Vector2(12, 2.6), Vector2(13.9, 10.1), Vector2(21.4, 12),
				Vector2(13.9, 13.9), Vector2(12, 21.4), Vector2(10.1, 13.9),
				Vector2(2.6, 12), Vector2(10.1, 10.1)]))

		Name.HEART:
			_shape(PackedVector2Array([
				Vector2(12, 20.6), Vector2(5.4, 13.6), Vector2(4.0, 10.2),
				Vector2(5.2, 7.0), Vector2(8.4, 5.6), Vector2(10.8, 6.6),
				Vector2(12, 8.8), Vector2(13.2, 6.6), Vector2(15.6, 5.6),
				Vector2(18.8, 7.0), Vector2(20.0, 10.2), Vector2(18.6, 13.6)]))

		Name.HAND:
			draw_line(Vector2(8.6, 12.4), Vector2(8.6, 8.6), color, weight, true)
			draw_line(Vector2(11.6, 12.4), Vector2(11.6, 5.4), color, weight, true)
			draw_line(Vector2(14.6, 12.4), Vector2(14.6, 7.2), color, weight, true)
			_stroke(PackedVector2Array([
				Vector2(5.8, 11.4), Vector2(5.8, 16.4), Vector2(8.6, 20.6),
				Vector2(15.2, 20.6), Vector2(17.6, 16.4), Vector2(17.6, 10.2)]))
