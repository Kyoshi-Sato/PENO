class_name LessonScreen
extends Control

## Tela principal de uma lição. Orquestra:
## - Avatar 3D (toca animações sob demanda)
## - State Machine (SignShowcase -> Recording -> Feedback)
## - Câmera / Holistic Landmarker (alimenta frames durante gravação)

@export var lesson: Lesson

@onready var state_machine: LessonStateMachine = $LessonStateMachine
@onready var sign_showcase: SignShowcaseState = $States/SignShowcaseState
@onready var recording: RecordingState = $States/RecordingState
@onready var feedback: FeedbackState = $States/FeedbackState

@onready var avatar_root: Node3D = $AvatarViewportContainer/AvatarViewport/Avatar
@onready var animation_player: AnimationPlayer = $AvatarViewportContainer/AvatarViewport/Avatar/Libra2/Armature_002/AnimationPlayer

## Holistic landmarker já existente no projeto. Pode ser nulo durante o
## SignShowcase e só ativado no Recording.
@onready var holistic: Node = $HolisticLandmarker


func _ready() -> void:
	# Conexões da state machine -> orquestração de UI
	state_machine.entered_sign_showcase.connect(_on_enter_showcase)
	state_machine.entered_recording.connect(_on_enter_recording)
	state_machine.entered_feedback.connect(_on_enter_feedback)

	# Conexões dos estados -> state machine
	sign_showcase.play_animation_requested.connect(_on_play_animation)
	sign_showcase.advance_requested.connect(state_machine.go_to_recording)

	recording.recording_finished.connect(_on_recording_finished)

	feedback.retry_requested.connect(state_machine.restart_lesson)
	feedback.next_lesson_requested.connect(_on_next_lesson)

	# Se o holistic landmarker expõe um sinal de frame pronto, conectamos aqui.
	# Adapte o nome do sinal para o que existe no seu HolisticLandmarker.gd.
	if holistic and holistic.has_signal("landmarks_detected"):
		holistic.connect("landmarks_detected", _on_landmarks_detected)

	state_machine.current_lesson = lesson
	sign_showcase.setup(lesson)
	_show_only(sign_showcase)
	state_machine.start()


func _show_only(state_node: Control) -> void:
	sign_showcase.visible = state_node == sign_showcase
	recording.visible = state_node == recording
	feedback.visible = state_node == feedback


func _on_enter_showcase() -> void:
	_show_only(sign_showcase)
	sign_showcase.setup(lesson)


func _on_enter_recording() -> void:
	_show_only(recording)
	recording.begin()


func _on_enter_feedback() -> void:
	_show_only(feedback)
	feedback.evaluate(lesson, recording.captured_frames_payload())


func _on_play_animation(animation_name: StringName) -> void:
	if animation_player == null:
		return
	if animation_player.has_animation(animation_name):
		animation_player.play(animation_name)
	else:
		push_warning("Animação não encontrada: %s" % animation_name)


func _on_recording_finished(_payload: Dictionary) -> void:
	state_machine.go_to_feedback()


func _on_landmarks_detected(frame_data: Dictionary) -> void:
	recording.push_frame(frame_data)


func _on_next_lesson() -> void:
	# Hook para o sistema de progressão. Por padrão volta pra cena principal.
	if Engine.has_singleton("Global"):
		var global := Engine.get_singleton("Global")
		if global.has_method("go_to_main_scene"):
			global.go_to_main_scene()
