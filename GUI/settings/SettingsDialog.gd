class_name SettingsDialog
extends Window
## Popup da engrenagem da Home. Três seções: som, onde rodar o reconhecimento
## (GPU/CPU) e apagar os dados locais do usuário.
##
## Uso:
##   dialog.popup_centered()
##   await dialog.data_erased
##
## O apagar é em duas etapas — o botão revela um cartão de confirmação em vez
## de agir de imediato. É a única ação irreversível do app: não existe conta
## remota, então o progresso apagado aqui não volta de lugar nenhum.

## Emitido depois que os dados foram apagados, para a tela que abriu o diálogo
## se redesenhar (XP, ofensiva e trilha mudaram debaixo dela).
signal data_erased

@onready var scroll: ScrollContainer = %Scroll
@onready var btn_sound: Button = %SoundToggle
@onready var backend_help: Label = %BackendHelp
@onready var backend_list: VBoxContainer = %BackendList
@onready var summary: Label = %DataSummary
@onready var btn_erase: Button = %EraseButton
@onready var confirm_card: PanelContainer = %ConfirmCard
@onready var confirm_text: Label = %ConfirmText
@onready var btn_cancel: Button = %CancelButton
@onready var btn_confirm: Button = %ConfirmButton
@onready var btn_close: Button = %CloseButton

## Conteúdo do botão de apagar. Ver `_decorate_erase_button`.
var _erase_glyph: HSIcon
var _erase_label: Label

## Conteúdo do botão de som. Ver `_decorate_sound_button`.
var _sound_label: Label
var _sound_check: HSIcon


func _ready() -> void:
	self.hide()
	
	_build_backend_options()
	_decorate_erase_button()
	_decorate_sound_button()

	close_requested.connect(hide)
	btn_close.pressed.connect(hide)
	btn_sound.pressed.connect(_on_sound_pressed)
	btn_erase.pressed.connect(_on_erase_pressed)
	btn_cancel.pressed.connect(_show_confirm.bind(false))
	btn_confirm.pressed.connect(_on_confirm_pressed)

	# Reabrir o diálogo tem que trazer números atuais e o cartão de confirmação
	# fechado — senão quem cancelou e voltou reencontra o "Apagar tudo?" armado.
	about_to_popup.connect(_refresh)

	Motion.attach_press(btn_erase)
	Motion.attach_press(btn_confirm)
	Motion.attach_press(btn_sound)
	# Os dois de fechar/cancelar não tinham o retorno de toque que o resto do
	# app tem — sem ele, os únicos botões mudos do diálogo seriam justamente
	# os que o usuário aperta para sair.
	Motion.attach_press(btn_cancel)
	Motion.attach_press(btn_close)

	_refresh()


# ═══════════════════════════════════════════════════════════
#  ESTADO
# ═══════════════════════════════════════════════════════════

func _refresh() -> void:
	_show_confirm(false)
	_sync_sound_button()
	_build_backend_options()
	summary.text = _summary_text()
	confirm_text.text = _confirm_text()
	_set_erase_enabled(_has_data())


## Existe algo para apagar? Um "Apagar dados" ativo numa instalação zerada
## promete um efeito que não vai acontecer.
func _has_data() -> bool:
	return Global.count_completed_lessons() > 0 \
		or Global.get_xp() > 0 \
		or Global.get_streak() > 0 \
		or Global.get_practice_count() > 0


func _summary_text() -> String:
	if not _has_data():
		return "Nada guardado ainda neste aparelho."

	var parts: PackedStringArray = PackedStringArray()

	var lessons: int = Global.count_completed_lessons()
	if lessons > 0:
		parts.append("%d lição concluída" % lessons if lessons == 1
			else "%d lições concluídas" % lessons)

	var xp: int = Global.get_xp()
	if xp > 0:
		parts.append("%d XP · nível %d" % [xp, Global.get_level()])

	var streak: int = Global.get_streak()
	if streak > 0:
		parts.append("%d dia de ofensiva" % streak if streak == 1
			else "%d dias de ofensiva" % streak)

	var practices: int = Global.get_practice_count()
	if practices > 0:
		parts.append("%d prática" % practices if practices == 1
			else "%d práticas" % practices)

	return "\n".join(parts)


func _confirm_text() -> String:
	return "Some o seu progresso, as estrelas, o XP, a ofensiva e as lições " \
		+ "já baixadas. Não dá para desfazer, nenhum dado está salvo em servidor."


## O rótulo e o ícone do botão são nós filhos, com cor própria: só marcar
## `disabled` trocaria o fundo e deixaria o conteúdo vermelho vivo por cima,
## lendo como um botão ativo.
func _set_erase_enabled(on: bool) -> void:
	btn_erase.disabled = not on
	var tint: Color = DS.DANGER_INK if on else DS.DISABLED
	_erase_glyph.color = tint
	_erase_label.add_theme_color_override("font_color", tint)


func _show_confirm(on: bool) -> void:
	confirm_card.visible = on
	# Uma das duas some para a outra aparecer: as duas visíveis dariam dois
	# botões vermelhos na tela, e o de cima já não faz nada.
	btn_erase.visible = not on

	if not on:
		return

	# Num aparelho baixo o cartão de confirmação nasce abaixo da dobra, e o
	# usuário toca "Apagar dados" sem ver o botão que confirma. Rolar até ele
	# depende do layout já ter reagido ao `visible`, daí o quadro de espera.
	await get_tree().process_frame
	if is_instance_valid(confirm_card) and confirm_card.visible:
		scroll.ensure_control_visible(confirm_card)


# ═══════════════════════════════════════════════════════════
#  SOM
# ═══════════════════════════════════════════════════════════
#
# Um botão só, que alterna. Toda a informação de estado está no rótulo, na
# variação do tema e no visto — não existe um "sino cortado" na família de
# ícones do app, e inventar um só para esta linha quebraria a família.

func _on_sound_pressed() -> void:
	var ligado: bool = not Global.is_sound_enabled()
	Global.set_sound_enabled(ligado)
	_sync_sound_button()
	# Ligar sem ouvir nada não confirma nada: o clique do próprio botão sai em
	# `button_down`, ou seja, antes da preferência mudar. Este é o retorno.
	if ligado:
		Audio.play(Audio.Cue.RECORD_START)


func _sync_sound_button() -> void:
	if _sound_label == null:
		return
	var ligado: bool = Global.is_sound_enabled()
	_sound_label.text = "Efeitos sonoros ligados" if ligado else "Efeitos sonoros desligados"
	_sound_label.add_theme_color_override("font_color",
		DS.TEXT_ON_PRIMARY if ligado else DS.TEXT)
	_sound_check.visible = ligado
	btn_sound.theme_type_variation = &"PrimaryButton" if ligado else &"SecondaryButton"


## Mesmo arranjo das linhas de backend: rótulo à esquerda, visto à direita.
func _decorate_sound_button() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", DS.SPACE_SM)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.offset_left = DS.SPACE_MD
	row.offset_right = -DS.SPACE_MD
	btn_sound.add_child(row)

	_sound_label = Label.new()
	_sound_label.theme_type_variation = &"H3"
	_sound_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sound_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sound_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_sound_label)

	_sound_check = HSIcon.new()
	_sound_check.icon = HSIcon.Name.CHECK
	_sound_check.color = DS.TEXT_ON_PRIMARY
	_sound_check.custom_minimum_size = Vector2(52, 52)
	_sound_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_sound_check)

	_sync_sound_button()


# ═══════════════════════════════════════════════════════════
#  RECONHECIMENTO — ONDE A INFERÊNCIA RODA
# ═══════════════════════════════════════════════════════════
#
# O grafo do MediaPipe não declarava aceleração nenhuma, e sem esse campo
# ele roda no XNNPACK com uma thread no desktop e no máximo quatro no
# Android — nunca na GPU. Esta seção é o que escreve
# `base_options/acceleration` (ver `Global.resolve_inference_backend` e
# `HolisticLandmarker._apply_acceleration`).

const BACKEND_ORDER: Array[Global.InferenceBackend] = [
	Global.InferenceBackend.AUTO,
	Global.InferenceBackend.GPU,
	Global.InferenceBackend.CPU,
]


func _build_backend_options() -> void:
	backend_help.text = _backend_help_text()

	for child in backend_list.get_children():
		child.queue_free()

	var marked := _marked_backend()
	for backend: Global.InferenceBackend in BACKEND_ORDER:
		backend_list.add_child(_build_backend_row(backend, backend == marked))


## Qual linha leva o destaque. É o backend EM USO, não o último tocado: com
## a GPU vetada por ter falhado, a preferência continua em GPU mas quem roda
## é a CPU, e destacar GPU faria a tela mentir sobre o que está acontecendo.
func _marked_backend() -> Global.InferenceBackend:
	var pref := Global.get_inference_backend()
	if pref == Global.InferenceBackend.GPU and Global.resolve_inference_backend() \
			!= Global.InferenceBackend.GPU:
		return Global.InferenceBackend.CPU
	return pref


func _backend_help_text() -> String:
	var resolved := Global.resolve_inference_backend()
	var lines: PackedStringArray = PackedStringArray()
	lines.append(
		"Onde o app procura as mãos e o corpo nos quadros da câmera, %s."
		% Global.inference_backend_label(resolved))

	# O veto vem de uma tentativa que travou o app; dizer isso é o que
	# explica por que "GPU" está escolhido e mesmo assim roda na CPU.
	if not Global.is_gpu_supported():
		lines.append(
			"A GPU está desligada nesta versão: o modelo holístico trava o "
			+ "app no delegate gráfico, tanto no celular quanto no computador.")
	elif Global.is_gpu_blocked():
		lines.append(
			"A GPU falhou na última tentativa neste aparelho e está desligada. "
			+ "rodando na CPU (%d threads)." % Global.get_inference_cpu_threads())
	else:
		# Medido num Galaxy S23: GPU não foi mais rápida. Vale manter a opção
		# porque num aparelho mais fraco a CPU pode não segurar os 30 fps.
		lines.append(
			"Medido num aparelho recente, a GPU não foi mais rápida: as duas "
			+ "acompanham a câmera e a CPU (%d threads) responde antes. "
			% Global.get_inference_cpu_threads()
			+ "Vale testar a GPU em aparelho mais fraco.")
	return "\n".join(lines)


## Mesma anatomia das linhas do CameraSelectorDialog: botão da largura toda,
## rótulo à esquerda e o "check" só na opção ativa.
func _build_backend_row(backend: Global.InferenceBackend, is_current: bool) -> Control:
	# A linha da GPU continua visível mesmo indisponível: sumir com ela faria
	# a ausência parecer esquecimento, e o rótulo é onde mora a explicação.
	var usable: bool = backend != Global.InferenceBackend.GPU or Global.is_gpu_supported()

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, DS.TOUCH_MIN)
	btn.theme_type_variation = &"PrimaryButton" if is_current else &"SecondaryButton"
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = not usable

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", DS.SPACE_SM)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.offset_left = DS.SPACE_MD
	row.offset_right = -DS.SPACE_MD
	btn.add_child(row)

	var lbl := Label.new()
	lbl.text = _backend_row_label(backend)
	lbl.theme_type_variation = &"H3"
	var ink: Color = DS.TEXT_ON_PRIMARY if is_current else DS.TEXT
	lbl.add_theme_color_override("font_color", DS.DISABLED if not usable else ink)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	if is_current:
		var check := HSIcon.new()
		check.icon = HSIcon.Name.CHECK
		check.color = DS.TEXT_ON_PRIMARY
		check.custom_minimum_size = Vector2(52, 52)
		check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(check)

	if usable:
		Motion.attach_press(btn)
		btn.pressed.connect(_on_backend_pressed.bind(backend))
	return btn


func _backend_row_label(backend: Global.InferenceBackend) -> String:
	match backend:
		Global.InferenceBackend.GPU:
			if not Global.is_gpu_supported():
				return "GPU (indisponível nesta versão)"
			if Global.is_gpu_blocked():
				return "GPU (falhou, toca para tentar de novo)"
			return "GPU (experimental)"
		Global.InferenceBackend.CPU:
			return "CPU (compatível com tudo)"
		_:
			return "Automático (recomendado)"


## Global avisa o HolisticLandmarker, que remonta o grafo na hora — trocar
## aqui no meio de uma lição já vale para a próxima gravação.
func _on_backend_pressed(backend: Global.InferenceBackend) -> void:
	Global.set_inference_backend(backend)
	_build_backend_options()


# ═══════════════════════════════════════════════════════════
#  AÇÕES
# ═══════════════════════════════════════════════════════════

func _on_erase_pressed() -> void:
	_show_confirm(true)


func _on_confirm_pressed() -> void:
	# Dois donos, dois pedidos: Global guarda o progresso em user://progress.json
	# e o LessonService guarda os .tres baixados em user://anim_cache/.
	var ok: bool = Global.erase_all_data()
	LessonService.clear_cache()

	_refresh()
	summary.text = "Dados apagados." if ok else \
		"Dados apagados desta sessão, mas o arquivo local não pôde ser removido."

	data_erased.emit()


# ═══════════════════════════════════════════════════════════
#  MONTAGEM
# ═══════════════════════════════════════════════════════════

## O Button do tema aceita `icon` como Texture2D, e o HSIcon é desenhado em
## runtime — então o ícone entra como filho, do mesmo jeito que na lista de
## câmeras do CameraSelectorDialog.
func _decorate_erase_button() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", DS.SPACE_SM)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_erase.add_child(row)

	_erase_glyph = HSIcon.new()
	_erase_glyph.icon = HSIcon.Name.TRASH
	_erase_glyph.color = DS.DANGER_INK
	_erase_glyph.custom_minimum_size = Vector2(48, 48)
	_erase_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_erase_glyph)

	_erase_label = Label.new()
	_erase_label.text = btn_erase.text
	_erase_label.theme_type_variation = &"H3"
	_erase_label.add_theme_color_override("font_color", DS.DANGER_INK)
	_erase_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_erase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_erase_label)

	# O texto agora é o Label; deixá-lo no Button desenharia o rótulo duas vezes.
	btn_erase.text = ""
