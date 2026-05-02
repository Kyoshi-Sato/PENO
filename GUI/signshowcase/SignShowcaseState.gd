class_name SignShowcaseState
extends Control

## Estado de demonstração: mostra o avatar e oferece dois botões:
## 1) Tocar/Repetir a animação do gesto.
## 2) Avançar para o estado de gravação.

signal play_animation_requested(animation_name: StringName)
signal advance_requested

@onready var btn_play: Button = $Panel/VBoxContainer/Buttons/PlayAnimation
@onready var btn_advance: Button = $Panel/VBoxContainer/Buttons/Advance
@onready var lbl_title: Label = $Panel/VBoxContainer/Title
@onready var lbl_description: Label = $Panel/VBoxContainer/Description

var current_lesson: Lesson
## Índice da animação atual dentro do array de animations da lição.
## Útil quando a lição tem múltiplas animações de demonstração.
var animation_index: int = 0


func _ready() -> void:
	btn_play.pressed.connect(_on_play_pressed)
	btn_advance.pressed.connect(_on_advance_pressed)


func setup(lesson: Lesson) -> void:
	current_lesson = lesson
	if lesson == null:
		return
	lbl_title.text = lesson.lesson_name
	lbl_description.text = lesson.description
	animation_index = 0


func _on_play_pressed() -> void:
	if current_lesson == null or current_lesson.animation_names.is_empty():
		return
	var idx := animation_index % current_lesson.animation_names.size()
	play_animation_requested.emit(current_lesson.animation_names[idx])


func _on_advance_pressed() -> void:
	advance_requested.emit()
