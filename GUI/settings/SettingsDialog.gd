class_name SettingsDialog
extends Window
## Popup da engrenagem da Home. Hoje tem uma única opção: apagar os dados
## locais do usuário.
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


func _ready() -> void:
	_decorate_erase_button()

	close_requested.connect(hide)
	btn_close.pressed.connect(hide)
	btn_erase.pressed.connect(_on_erase_pressed)
	btn_cancel.pressed.connect(_show_confirm.bind(false))
	btn_confirm.pressed.connect(_on_confirm_pressed)

	# Reabrir o diálogo tem que trazer números atuais e o cartão de confirmação
	# fechado — senão quem cancelou e voltou reencontra o "Apagar tudo?" armado.
	about_to_popup.connect(_refresh)

	Motion.attach_press(btn_erase)
	Motion.attach_press(btn_confirm)

	_refresh()


# ═══════════════════════════════════════════════════════════
#  ESTADO
# ═══════════════════════════════════════════════════════════

func _refresh() -> void:
	_show_confirm(false)
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
		+ "já baixadas. Não dá para desfazer — nada disso está salvo em servidor."


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
