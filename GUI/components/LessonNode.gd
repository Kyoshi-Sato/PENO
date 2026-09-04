@tool
class_name LessonNode
extends HBoxContainer
## Um degrau da trilha de aprendizado.
##
## Substitui o Button cru cujo rótulo era `"★★★\nnome"` ou `"🔒"`, precedido de
## um Control espaçador com largura `80 + (index % 3) * 60` para fingir um
## caminho. Aqui a trilha é real: uma coluna à esquerda desenha o trilho
## contínuo e o marcador do degrau, e o conteúdo fica num card ao lado.
##
## Estados:
##   LOCKED    trilho apagado, card sem sombra, sem toque
##   AVAILABLE marcador vazado em azul — é onde o usuário pode ir
##   CURRENT   marcador ciano preenchido + anel, card destacado (próximo passo)
##   DONE      marcador verde com check, estrelas conquistadas à direita

signal pressed(lesson_id: int)

enum State { LOCKED, AVAILABLE, CURRENT, DONE }

const RAIL_WIDTH := 132
const MARKER_RADIUS := 40.0
const CARD_GAP := DS.SPACE_SM

var lesson_id: int = -1
var state: State = State.LOCKED
var index: int = 0
var is_first: bool = false
var is_last: bool = false
var stars: int = 0

var _rail: Control
var _marker_icon: HSIcon
var _marker_label: Label
var _card: PanelContainer
var _button: Button
var _title: Label
var _subtitle: Label
var _stars: StarRow
var _chevron: HSIcon


static func create(
	id: int,
	title: String,
	node_state: State,
	position_index: int,
	star_count: int = 0
) -> LessonNode:
	var node := LessonNode.new()
	node.lesson_id = id
	node.state = node_state
	node.index = position_index
	node.stars = star_count
	node._build()
	node._title.text = title
	return node


func _init() -> void:
	add_theme_constant_override("separation", 0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _build() -> void:
	# ---- coluna do trilho ----
	_rail = Control.new()
	_rail.custom_minimum_size = Vector2(RAIL_WIDTH, 0)
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail.draw.connect(_draw_rail)
	add_child(_rail)

	# Número do degrau (estados abertos) ou ícone (bloqueado / concluído).
	_marker_label = Label.new()
	_marker_label.theme_type_variation = &"H3"
	_marker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_marker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail.add_child(_marker_label)

	_marker_icon = HSIcon.new()
	_marker_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail.add_child(_marker_icon)

	# ---- card ----
	var card_wrap := MarginContainer.new()
	card_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_wrap.add_theme_constant_override("margin_bottom", CARD_GAP)
	card_wrap.add_theme_constant_override("margin_right", DS.SPACE_XS)
	add_child(card_wrap)

	_card = PanelContainer.new()
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_wrap.add_child(_card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SPACE_SM)
	_card.add_child(row)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", DS.SPACE_XXS)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text_box)

	_title = Label.new()
	_title.theme_type_variation = &"H3"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(_title)

	_subtitle = Label.new()
	_subtitle.theme_type_variation = &"Caption"
	text_box.add_child(_subtitle)

	_stars = StarRow.create(stars, 40)
	_stars.add_theme_constant_override("separation", DS.SPACE_XXS)
	_stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_stars)

	_chevron = HSIcon.new()
	_chevron.icon = HSIcon.Name.FORWARD
	_chevron.custom_minimum_size = Vector2(44, 44)
	_chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_chevron)

	# O botão cobre o card inteiro para que a área de toque seja o card todo
	# (~210 px de altura), sem que o texto vire filho de um Button.
	#
	# Ele é o ÚLTIMO filho, ou seja, fica À FRENTE do conteúdo. O Godot
	# entrega o evento de mouse ao controle mais à frente sob o ponto, e
	# containers e Labels usam MOUSE_FILTER_STOP por padrão — com o botão
	# atrás, como estava antes, todo clique morria no VBox do texto e o card
	# inteiro ficava inerte. Na frente ele captura tudo, e como a variação
	# `NavButton` não tem stylebox em nenhum estado, ele não desenha nada por
	# cima. Qualquer conteúdo acrescentado depois continua coberto de graça.
	_button = Button.new()
	_button.theme_type_variation = &"NavButton"
	_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(_on_pressed)
	_card.add_child(_button)

	_apply_state()


func _on_pressed() -> void:
	if state == State.LOCKED:
		# Recusa audível visualmente: o card treme em vez de não fazer nada.
		Motion.shake(_card, 10.0)
		return
	Motion.pulse(_card, 0.98)
	pressed.emit(lesson_id)


# ------------------------------------------------------------
#  aparência por estado
# ------------------------------------------------------------

func _apply_state() -> void:
	var locked: bool = state == State.LOCKED
	var done: bool = state == State.DONE
	var current: bool = state == State.CURRENT

	_marker_label.visible = not locked and not done
	_marker_label.text = str(index + 1)
	_marker_icon.visible = locked or done
	_marker_icon.icon = HSIcon.Name.LOCK if locked else HSIcon.Name.CHECK
	_marker_icon.filled = false
	_marker_icon.weight = 2.6

	_stars.visible = done
	_stars.stars = stars
	_chevron.visible = not done and not locked

	if done:
		_marker_icon.color = DS.TEXT_ON_PRIMARY
		_subtitle.text = "Concluída"
		_subtitle.add_theme_color_override("font_color", DS.SUCCESS_INK)
		_title.add_theme_color_override("font_color", DS.TEXT)
		_card.add_theme_stylebox_override("panel", _card_style(false))
		_chevron.color = DS.TEXT_SUBTLE
	elif current:
		_marker_label.add_theme_color_override("font_color", DS.PRIMARY_DARK)
		_subtitle.text = "Continue daqui"
		_subtitle.add_theme_color_override("font_color", DS.ACCENT_INK)
		_title.add_theme_color_override("font_color", DS.TEXT)
		_card.add_theme_stylebox_override("panel", _card_style(true))
		_chevron.color = DS.ACCENT_INK
	elif locked:
		_marker_icon.color = DS.DISABLED
		_subtitle.text = "Conclua a lição anterior"
		_subtitle.add_theme_color_override("font_color", DS.TEXT_SUBTLE)
		_title.add_theme_color_override("font_color", DS.TEXT_SUBTLE)
		# O estado travado é comunicado por cor de texto e ausência de sombra.
		# Rebaixar o `modulate` do card também funcionaria, mas colide com as
		# animações de entrada, que animam justamente `modulate:a`.
		_card.add_theme_stylebox_override("panel",
			DS.fill(DS.SURFACE_SUNKEN, DS.RADIUS_LG, DS.SPACE_MD, DS.SPACE_MD))
	else:
		_marker_label.add_theme_color_override("font_color", DS.PRIMARY)
		_subtitle.text = "Disponível"
		_subtitle.add_theme_color_override("font_color", DS.TEXT_SUBTLE)
		_title.add_theme_color_override("font_color", DS.TEXT)
		_card.add_theme_stylebox_override("panel", _card_style(false))
		_chevron.color = DS.TEXT_SUBTLE

	if _rail:
		_rail.queue_redraw()


func _card_style(highlight: bool) -> StyleBoxFlat:
	if highlight:
		# O próximo passo é o único card com contorno ciano — só pode haver
		# um por tela, senão o destaque deixa de destacar.
		var sb := DS.card(DS.SURFACE, DS.RADIUS_LG, DS.SPACE_MD, true)
		sb.set_border_width_all(3)
		sb.border_color = DS.ACCENT
		sb.shadow_color = DS.alpha(DS.ACCENT_INK, 0.20)
		return sb
	return DS.card(DS.SURFACE, DS.RADIUS_LG, DS.SPACE_MD)


func _marker_colors() -> Array:
	match state:
		State.DONE:
			return [DS.SUCCESS_INK, DS.SUCCESS_INK]
		State.CURRENT:
			return [DS.ACCENT, DS.ACCENT_INK]
		State.LOCKED:
			return [DS.DISABLED_TINT, DS.DISABLED]
		_:
			return [DS.SURFACE, DS.PRIMARY_TINT_STRONG]


# ------------------------------------------------------------
#  trilho
# ------------------------------------------------------------

func _draw_rail() -> void:
	var center := Vector2(float(RAIL_WIDTH) * 0.5, MARKER_RADIUS + DS.SPACE_MD)
	var rail_color: Color = DS.HAIRLINE_STRONG if state != State.LOCKED else DS.HAIRLINE
	var line_w := 6.0

	# Segmentos acima e abaixo do marcador. Com separation 0 no VBox pai,
	# os segmentos de nós vizinhos se encostam e formam uma linha contínua.
	if not is_first:
		_rail.draw_line(Vector2(center.x, 0.0), Vector2(center.x, center.y - MARKER_RADIUS),
			rail_color, line_w, true)
	if not is_last:
		_rail.draw_line(Vector2(center.x, center.y + MARKER_RADIUS),
			Vector2(center.x, _rail.size.y), rail_color, line_w, true)

	var colors: Array = _marker_colors()
	var fill_color: Color = colors[0]
	var edge: Color = colors[1]

	# Anel externo suave só no degrau atual — o "você está aqui".
	if state == State.CURRENT:
		_rail.draw_circle(center, MARKER_RADIUS + 14.0, DS.alpha(DS.ACCENT, 0.22))

	_rail.draw_circle(center, MARKER_RADIUS, fill_color)
	_rail.draw_arc(center, MARKER_RADIUS - 1.5, 0.0, TAU, 40, edge, 3.0, true)

	# Posiciona o conteúdo do marcador junto do desenho.
	var box := Rect2(center - Vector2(MARKER_RADIUS, MARKER_RADIUS),
		Vector2(MARKER_RADIUS, MARKER_RADIUS) * 2.0)
	_marker_label.position = box.position
	_marker_label.size = box.size
	_marker_icon.position = box.position + box.size * 0.22
	_marker_icon.size = box.size * 0.56
