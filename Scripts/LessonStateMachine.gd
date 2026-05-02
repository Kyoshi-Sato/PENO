class_name LessonStateMachine
extends Node

## Máquina de estados da lição. Dispara sinais a cada transição
## para que estados (e UI) reajam de forma desacoplada.
##
## Fluxo: SIGN_SHOWCASE -> RECORDING -> FEEDBACK -> (reinício ou próxima lição)

enum State {
	NONE,
	SIGN_SHOWCASE,
	RECORDING,
	FEEDBACK,
}

signal state_changed(from: State, to: State)
signal entered_sign_showcase
signal entered_recording
signal entered_feedback

## Referência à lição atual. Setada antes de iniciar a máquina.
var current_lesson: Lesson

var current_state: State = State.NONE


func start() -> void:
	transition_to(State.SIGN_SHOWCASE)


func transition_to(new_state: State) -> void:
	if new_state == current_state:
		return
	var old_state := current_state
	current_state = new_state
	state_changed.emit(old_state, new_state)
	match new_state:
		State.SIGN_SHOWCASE:
			entered_sign_showcase.emit()
		State.RECORDING:
			entered_recording.emit()
		State.FEEDBACK:
			entered_feedback.emit()


## Atalhos para uso pelos estados / UI.
func go_to_recording() -> void:
	transition_to(State.RECORDING)


func go_to_feedback() -> void:
	transition_to(State.FEEDBACK)


func restart_lesson() -> void:
	transition_to(State.SIGN_SHOWCASE)
