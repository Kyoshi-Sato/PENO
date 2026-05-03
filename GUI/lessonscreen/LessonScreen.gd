class_name LessonScreen
extends Control

## Tela principal de uma lição. Orquestra:
## - Avatar 3D (toca animações sob demanda via AnimationLibrary)
## - State Machine (SignShowcase -> Recording -> Feedback)
## - Holistic Landmarker (gravação batch de 10s)
##
## A lição é buscada na API no _ready, usando o id que o LessonMapScreen
## deixou em `Global.current_lesson_id`.

const LIBRARY_NAME := &"licao"

## Pode ser preenchida no inspector para testes isolados sem passar pelo mapa.
@export var debug_lesson_id: int = 1

var lesson: Lesson
var current_sign_index: int = 1

@onready var state_machine: LessonStateMachine = $LessonStateMachine
@onready var recording: RecordingState = $States/RecordingState
@onready var sign_showcase: SignShowcaseState = $States/SignShowcaseState
@onready var feedback: FeedbackState = $States/FeedbackState

@onready var avatar_root: Node3D = $AvatarViewportContainer/AvatarViewport/Avatar
@onready var animation_player: AnimationPlayer = $AvatarViewportContainer/AvatarViewport/Avatar/Libra2/Armature_002/AnimationPlayer

@onready var holistic: Node = $HolisticLandmarker
@onready var btn_back: Button = %Back


func _ready() -> void:
	btn_back.pressed.connect(_on_back)

	# state_machine -> UI
	state_machine.entered_sign_showcase.connect(_on_enter_showcase)
	state_machine.entered_recording.connect(_on_enter_recording)
	state_machine.entered_feedback.connect(_on_enter_feedback)

	# states -> orquestração
	sign_showcase.play_animation_requested.connect(_on_play_animation)
	sign_showcase.advance_requested.connect(state_machine.go_to_recording)

	recording.recording_finished.connect(_on_recording_finished)
	recording.cancel_requested.connect(_on_recording_cancelled)
	recording.request_start_capture.connect(_on_request_start_capture)
	recording.request_reset_capture.connect(_on_request_reset_capture)

	feedback.retry_requested.connect(_on_retry)
	feedback.next_lesson_requested.connect(_on_next_lesson)

	# holistic emite landmarks_detected UMA VEZ ao final dos 10s, com o
	# JSON exportado completo. Repassamos pro RecordingState.
	if holistic and holistic.has_signal("landmarks_detected"):
		holistic.connect("landmarks_detected", _on_capture_complete)

	# Esconde tudo até a lição carregar.
	sign_showcase.visible = false
	recording.visible = false
	feedback.visible = false

	var lesson_id := debug_lesson_id
	if lesson_id < 0:
		lesson_id = Global.current_lesson_id
	if lesson_id < 0:
		push_error("Nenhuma lesson_id definida (Global.current_lesson_id e debug_lesson_id ambos < 0)")
		return

	LessonService.fetch_lesson(lesson_id, _on_lesson_loaded, _on_lesson_failed)


func _on_lesson_loaded(loaded: Lesson) -> void:
	lesson = loaded
	current_sign_index = 0

	if animation_player.has_animation_library(LIBRARY_NAME):
		animation_player.remove_animation_library(LIBRARY_NAME)
	animation_player.add_animation_library(LIBRARY_NAME, lesson.animation_library)

	state_machine.current_lesson = lesson
	state_machine.start()


func _on_lesson_failed(error: String) -> void:
	push_error("Falha ao carregar lição: %s" % error)


# ---------- TRANSIÇÕES DE ESTADO ----------

func _show_only(state_node: Control) -> void:
	sign_showcase.visible = state_node == sign_showcase
	recording.visible = state_node == recording
	feedback.visible = state_node == feedback


func _on_enter_showcase() -> void:
	_show_only(sign_showcase)
	sign_showcase.setup(lesson, current_sign_index)


func _on_enter_recording() -> void:
	_show_only(recording)
	recording.begin(lesson, current_sign_index)


func _on_enter_feedback() -> void:
	_show_only(feedback)
	feedback.evaluate(lesson, current_sign_index, _last_payload)


var _last_payload: Dictionary = {}


# ---------- HOLISTIC ----------

## RecordingState terminou o countdown e quer iniciar a gravação de 10s.
func _on_request_start_capture(tempo:int) -> void:
	if holistic and holistic.has_method("_begin_capture"):
		holistic._begin_capture(tempo)
	else:
		push_warning("HolisticLandmarker._begin_capture() indisponível")


## RecordingState foi cancelado — descarta o que estava sendo gravado.
func _on_request_reset_capture() -> void:
	if holistic and holistic.has_method("_reset"):
		holistic._reset()


## HolisticLandmarker emitiu landmarks_detected após os 10s.
## `export_data` é o {video_info, frames} produzido por _export_capture_json.
func _on_capture_complete(export_data: Dictionary) -> void:
	if recording.visible:
		recording.on_capture_complete(export_data)


# ---------- AÇÕES ----------

func _on_play_animation(animation_name: StringName, speed: float = 1.0) -> void:
	if animation_player == null:
		return

	var path := String(animation_name)
	if not path.contains("/"):
		path = "%s/%s" % [LIBRARY_NAME, path]

	if animation_player.has_animation(path):
		animation_player.play(path, -1, speed)
	else:
		push_warning("Animação não encontrada: %s" % path)


func _on_recording_finished(payload: Dictionary) -> void:
	_last_payload = payload
	state_machine.go_to_feedback()


func _on_recording_cancelled() -> void:
	state_machine.go_to_sign_showcase()


func _on_retry() -> void:
	state_machine.go_to_sign_showcase()


func _on_next_lesson() -> void:
	if lesson == null:
		Global.go_to_map()
		return

	current_sign_index += 1
	if current_sign_index < lesson.sinais.size():
		state_machine.go_to_sign_showcase()
	else:
		Global.mark_completed(lesson.lesson_id, 3)
		Global.go_to_map()


func _on_back() -> void:
	# Se estiver gravando, cancela a captura antes de sair.
	if recording.visible and holistic and holistic.has_method("_reset"):
		holistic._reset()
	Global.go_to_map()
