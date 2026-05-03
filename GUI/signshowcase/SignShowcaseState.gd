class_name SignShowcaseState
extends Control
## Estado de "showcase": o avatar fica visível atrás (renderizado pela
## LessonScreen) e este Control desenha o overlay com:
##   - Topo: "Lição N" + ícone de favorito
##   - Título do sinal + pill "Cumprimentos" (categoria)
##   - Card inferior: "Observe o gesto" + "Ver devagar" + "Praticar agora"

signal play_animation_requested(animation_name: StringName, speed: float)
signal advance_requested

const NORMAL_SPEED := 1.0
const SLOW_SPEED := 0.4

@onready var lbl_lesson_index: Label = %LessonIndexLabel
@onready var lbl_sign_title: Label = %SignTitleLabel
@onready var lbl_category: Label = %CategoryPill
@onready var btn_favorite: Button = %FavoriteButton
@onready var btn_slow: Button = %SlowButton
@onready var btn_practice: Button = %PracticeButton
@onready var lbl_hint: Label = %HintLabel

var _current_sign_name: StringName = &""


func _ready() -> void:
	btn_slow.pressed.connect(_on_slow_pressed)
	btn_practice.pressed.connect(_on_practice_pressed)
	btn_favorite.pressed.connect(_on_favorite_pressed)


## Chamado pela LessonScreen ao entrar/atualizar este estado.
func setup(lesson: Lesson, sign_index: int) -> void:
	if lesson == null or lesson.sinais.is_empty():
		return
	var idx := clampi(sign_index, 0, lesson.sinais.size() - 1)
	var sinal: Dictionary = lesson.sinais[idx]
	var nome: String = String(sinal.get("nome_sinal", ""))

	_current_sign_name = StringName(nome)

	lbl_lesson_index.text = "Lição %d" % lesson.lesson_id
	lbl_sign_title.text = nome.capitalize()
	lbl_category.text = lesson.nome_exercicio
	lbl_hint.text = "Toque em \"Ver devagar\" para\nassistir em câmera lenta."

	# Toca a animação automaticamente ao entrar.
	play_animation_requested.emit(_current_sign_name, NORMAL_SPEED)


func _on_slow_pressed() -> void:
	if _current_sign_name == &"":
		return
	play_animation_requested.emit(_current_sign_name, SLOW_SPEED)


func _on_practice_pressed() -> void:
	advance_requested.emit()


func _on_favorite_pressed() -> void:
	# Hook pra futuro sistema de favoritos.
	btn_favorite.set_pressed_no_signal(not btn_favorite.button_pressed)
