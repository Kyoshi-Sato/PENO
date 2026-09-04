class_name SignShowcaseState
extends Control
## Etapa ASSISTA.
##
## O avatar 3D é renderizado atrás (pela LessonScreen) e este Control desenha
## uma ÚNICA folha inferior, com o nome do sinal, a instrução e as ações.
##
## Havia antes um segundo card no topo com o nome do sinal. Dois painéis
## espremiam o avatar numa faixa estreita no meio da tela — e em Libras a
## expressão facial é parâmetro gramatical, então tapar a cabeça do avatar
## não é só questão de estética. Juntando tudo numa folha só, o topo fica
## livre e sobra o dobro de altura para o gesto.
##
## A folha se dimensiona pelo conteúdo (VBox com espaçador expansível) em vez
## de um `offset_top` fixo: assim ela não corta texto em telas mais estreitas
## nem sobra vazio nas mais largas.
##
## A hierarquia é explícita: uma única ação principal ("Praticar agora", em
## azul cheio) e uma secundária contornada. Antes as duas eram `flat` e o
## botão principal ficava indistinguível do "Ver devagar".

signal play_animation_requested(animation_name: StringName, speed: float)
signal advance_requested

const NORMAL_SPEED := 1.0
const SLOW_SPEED := 0.4

@onready var lbl_lesson_index: Label = %LessonIndexLabel
@onready var lbl_sign_title: Label = %SignTitleLabel
@onready var favorite_slot: HBoxContainer = %FavoriteSlot
@onready var observe_row: HBoxContainer = %ObserveRow
@onready var btn_slow: Button = %SlowButton
@onready var btn_practice: Button = %PracticeButton
@onready var lbl_hint: Label = %HintLabel
@onready var card: PanelContainer = %BottomCard

var _current_sign_name: StringName = &""
var _btn_favorite: IconButton
var _favorited: bool = false


func _ready() -> void:
	_btn_favorite = IconButton.create(HSIcon.Name.HEART, IconButton.Tone.LIGHT, 100)
	_btn_favorite.pressed.connect(_on_favorite_pressed)
	favorite_slot.add_child(_btn_favorite)

	# Ícone de olho ao lado de "Observe o gesto": reforça a etapa atual sem
	# repetir a palavra, e casa com o passo ASSISTA do StepIndicator.
	var eye := HSIcon.new()
	eye.icon = HSIcon.Name.EYE
	eye.color = DS.PRIMARY
	eye.custom_minimum_size = Vector2(56, 56)
	eye.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	observe_row.add_child(eye)
	observe_row.move_child(eye, 0)

	btn_slow.pressed.connect(_on_slow_pressed)
	btn_practice.pressed.connect(_on_practice_pressed)

	Motion.attach_press(btn_slow)
	Motion.attach_press(btn_practice)


## Chamado pela LessonScreen ao entrar/atualizar este estado.
func setup(lesson: Lesson, sign_index: int) -> void:
	if lesson == null or lesson.sinais.is_empty():
		return
	var idx := clampi(sign_index, 0, lesson.sinais.size() - 1)
	var sinal: Dictionary = lesson.sinais[idx]
	var nome: String = String(sinal.get("nome_sinal", ""))

	_current_sign_name = StringName(nome)

	# Sinal N de M dá ao usuário a noção de onde está dentro da lição —
	# antes só existia o número da lição, sem progresso interno nenhum.
	lbl_lesson_index.text = "LIÇÃO %d · %s · SINAL %d DE %d" % [
		lesson.lesson_id, lesson.nome_exercicio.to_upper(),
		idx + 1, lesson.sinais.size()]
	lbl_sign_title.text = DS.sentence_case(nome)
	lbl_hint.text = "Observe o gesto. Toque em Ver devagar para acompanhar cada etapa."

	Motion.fade_in(card, DS.DUR_BASE, 0.0)

	# Toca a animação automaticamente ao entrar.
	play_animation_requested.emit(_current_sign_name, NORMAL_SPEED)


func _on_slow_pressed() -> void:
	if _current_sign_name == &"":
		return
	play_animation_requested.emit(_current_sign_name, SLOW_SPEED)


func _on_practice_pressed() -> void:
	advance_requested.emit()


func _on_favorite_pressed() -> void:
	# Hook pra futuro sistema de favoritos — o estado é só visual por enquanto.
	_favorited = not _favorited
	_btn_favorite.set_icon_filled(_favorited)
	_btn_favorite.set_icon_color(DS.DANGER if _favorited else DS.PRIMARY)
	if _favorited:
		Motion.pulse(_btn_favorite, 1.2)
