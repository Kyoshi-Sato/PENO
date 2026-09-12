class_name LoadingOverlay
extends Control
## Overlay de Carregamento estilizado de acordo com o Design System do HandSign.
##
## Exibe:
## - Fundo translúcido com elevação
## - Card com cantos arredondados (DS.RADIUS_LG) e sombra suave
## - Barra de progresso animada com porcentagem
## - Mensagem de etapa atual
## - Painel de erro integrado com botões "Tentar Novamente" e "Voltar"

signal retry_pressed
signal cancel_pressed

var _backdrop: ColorRect
var _card: PanelContainer
var _lbl_title: Label
var _lbl_step: Label
var _progress_bar: ProgressBar
var _lbl_pct: Label
var _icon: HSIcon

var _error_box: VBoxContainer
var _lbl_error_msg: Label
var _btn_retry: Button
var _btn_cancel: Button

var _current_ratio: float = 0.0


func _init() -> void:
	z_index = 100
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP # Bloqueia toques nos botões de trás durante o carregamento

	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.08, 0.11, 0.29, 0.70)
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(760, 480)

	var style := StyleBoxFlat.new()
	style.bg_color = DS.SURFACE
	style.set_corner_radius_all(DS.RADIUS_LG)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = DS.HAIRLINE
	style.shadow_color = DS.SHADOW_STRONG
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 8)
	style.content_margin_left = DS.SPACE_XL
	style.content_margin_right = DS.SPACE_XL
	style.content_margin_top = DS.SPACE_XL
	style.content_margin_bottom = DS.SPACE_XL
	_card.add_theme_stylebox_override("panel", style)
	center.add_child(_card)

	var content_box := VBoxContainer.new()
	content_box.alignment = BoxContainer.ALIGNMENT_CENTER
	content_box.add_theme_constant_override("separation", DS.SPACE_MD)
	_card.add_child(content_box)

	# Ícone Central
	_icon = HSIcon.new()
	_icon.icon = HSIcon.Name.HAND
	_icon.color = DS.PRIMARY
	_icon.custom_minimum_size = Vector2(80, 80)
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content_box.add_child(_icon)

	# Título
	_lbl_title = Label.new()
	_lbl_title.text = "Carregando Exercício"
	_lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_title.add_theme_color_override("font_color", DS.TEXT)
	_lbl_title.add_theme_font_size_override("font_size", DS.TEXT_H2)
	content_box.add_child(_lbl_title)

	# Etapa / Mensagem
	_lbl_step = Label.new()
	_lbl_step.text = "Preparando postura e sinais..."
	_lbl_step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_step.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_step.add_theme_color_override("font_color", DS.TEXT_MUTED)
	_lbl_step.add_theme_font_size_override("font_size", DS.TEXT_BODY)
	content_box.add_child(_lbl_step)

	# Barra de Progresso
	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(600, 24)
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = DS.PRIMARY_TINT
	bar_bg.set_corner_radius_all(12)

	var bar_fg := StyleBoxFlat.new()
	bar_fg.bg_color = DS.PRIMARY
	bar_fg.set_corner_radius_all(12)

	_progress_bar.add_theme_stylebox_override("background", bar_bg)
	_progress_bar.add_theme_stylebox_override("fill", bar_fg)
	content_box.add_child(_progress_bar)

	# Porcentagem
	_lbl_pct = Label.new()
	_lbl_pct.text = "0%"
	_lbl_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_pct.add_theme_color_override("font_color", DS.PRIMARY)
	_lbl_pct.add_theme_font_size_override("font_size", DS.TEXT_CAPTION)
	content_box.add_child(_lbl_pct)

	# Painel de Erro (inicialmente oculto)
	_error_box = VBoxContainer.new()
	_error_box.visible = false
	_error_box.add_theme_constant_override("separation", DS.SPACE_MD)
	content_box.add_child(_error_box)

	_lbl_error_msg = Label.new()
	_lbl_error_msg.text = "Ocorreu um erro ao carregar os dados."
	_lbl_error_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_error_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_error_msg.add_theme_color_override("font_color", DS.DANGER)
	_lbl_error_msg.add_theme_font_size_override("font_size", DS.TEXT_BODY)
	_error_box.add_child(_lbl_error_msg)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", DS.SPACE_MD)
	_error_box.add_child(btn_row)

	_btn_retry = Button.new()
	_btn_retry.text = "Tentar Novamente"
	_btn_retry.custom_minimum_size = Vector2(240, 64)
	_btn_retry.pressed.connect(func() -> void: retry_pressed.emit())
	Motion.attach_press(_btn_retry)
	btn_row.add_child(_btn_retry)

	_btn_cancel = Button.new()
	_btn_cancel.text = "Voltar"
	_btn_cancel.custom_minimum_size = Vector2(160, 64)
	_btn_cancel.pressed.connect(func() -> void: cancel_pressed.emit())
	Motion.attach_press(_btn_cancel)
	btn_row.add_child(_btn_cancel)


## Atualiza a etapa descritiva e a porcentagem com transição suave.
func set_progress(step_name: String, ratio: float) -> void:
	if not _error_box.visible:
		_lbl_step.text = step_name
		_current_ratio = clampf(ratio, 0.0, 1.0)
		_lbl_pct.text = "%d%%" % int(round(_current_ratio * 100.0))

		var tween := create_tween()
		tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(_progress_bar, "value", _current_ratio, DS.DUR_FAST)


## Configura o título principal do card.
func set_title(title_text: String) -> void:
	_lbl_title.text = title_text


## Exibe o estado de erro com mensagem amigável e botões de ação.
func show_error(error_message: String, on_retry: Callable = Callable(), on_cancel: Callable = Callable()) -> void:
	_icon.icon = HSIcon.Name.REFRESH
	_icon.color = DS.DANGER
	_lbl_title.text = "Falha no Carregamento"
	_lbl_step.visible = false
	_progress_bar.visible = false
	_lbl_pct.visible = false

	_lbl_error_msg.text = error_message
	_error_box.visible = true

	if on_retry.is_valid():
		retry_pressed.connect(on_retry, CONNECT_ONE_SHOT)
	if on_cancel.is_valid():
		cancel_pressed.connect(on_cancel, CONNECT_ONE_SHOT)


## Restaura para o estado de carregamento ativo normal.
func reset_loading(title_text: String = "Carregando Exercício") -> void:
	_icon.icon = HSIcon.Name.HAND
	_icon.color = DS.PRIMARY
	_lbl_title.text = title_text
	_lbl_step.visible = true
	_progress_bar.visible = true
	_lbl_pct.visible = true
	_error_box.visible = false
	_current_ratio = 0.0
	_progress_bar.value = 0.0
	_lbl_pct.text = "0%"
