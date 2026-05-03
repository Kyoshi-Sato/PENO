class_name LessonStateMachine
extends Node
## Máquina de estados da lição. Apenas dispara signals — não controla
## visibilidade (a LessonScreen é quem mostra/esconde os States).

signal entered_sign_showcase
signal entered_recording
signal entered_feedback

enum State { IDLE, SIGN_SHOWCASE, RECORDING, FEEDBACK }

var state: State = State.IDLE
var current_lesson: Lesson


func start() -> void:
	go_to_sign_showcase()


func go_to_sign_showcase() -> void:
	state = State.SIGN_SHOWCASE
	entered_sign_showcase.emit()


func go_to_recording() -> void:
	state = State.RECORDING
	entered_recording.emit()


func go_to_feedback() -> void:
	state = State.FEEDBACK
	entered_feedback.emit()


func restart_lesson() -> void:
	go_to_sign_showcase()
