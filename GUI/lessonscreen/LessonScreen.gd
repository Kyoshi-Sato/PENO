class_name LessonScreen
extends Control

## Tela principal de uma lição. Orquestra:
## - Avatar 3D (toca animações sob demanda via AnimationLibrary)
## - State Machine (SignShowcase -> Recording -> Feedback)
## - Holistic Landmarker (gravação batch)
## - Seleção de câmera (dialog acionado pela engrenagem)

const LIBRARY_NAME := &"licao"
const CAPTURE_MARGIN_SECONDS := 1.0
const ANDROID_CAMERA_PERMISSION := "android.permission.CAMERA"

## Use um id >= 0 apenas para forçar uma lição específica em testes no editor.
## Em builds normais deve ficar -1 para respeitar a lição escolhida no mapa.
@export var debug_lesson_id: int = -1

var lesson: Lesson
var current_sign_index: int = 0
## Melhor número de estrelas obtido em cada sinal da lição (índice = sinal).
var _sign_stars: Array[int] = []

@onready var state_machine: Node = $LessonStateMachine
@onready var sign_showcase: Control = $States/SignShowcaseState
@onready var recording: Control = $States/RecordingState
@onready var feedback: Control = $States/FeedbackState

@onready var avatar_root: Node3D = $AvatarViewportContainer/AvatarViewport/Avatar
@onready var animation_player: AnimationPlayer = $AvatarViewportContainer/AvatarViewport/Avatar/Libra2/Armature_002/AnimationPlayer

@onready var holistic: Node = $HolisticLandmarker
@onready var btn_back: Button = %Back
@onready var btn_settings: Button = %Settings
@onready var camera_dialog: CameraSelectorDialog = $CameraSelectorDialog

var _last_payload: Dictionary = {}


func _ready() -> void:
	btn_back.pressed.connect(_on_back)
	btn_settings.pressed.connect(_on_settings_pressed)

	camera_dialog.camera_selected.connect(_on_camera_selected)

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
	feedback.modules_requested.connect(_on_see_modules)
	feedback.evaluation_completed.connect(_on_evaluation_completed)

	if holistic:
		if holistic.has_signal("landmarks_detected"):
			holistic.connect("landmarks_detected", _on_capture_complete)
		if holistic.has_signal("camera_changed"):
			holistic.connect("camera_changed", _on_camera_changed)
		# Começa desligado — só liga quando entrar no RecordingState.
		if "render_overlay_enabled" in holistic:
			holistic.render_overlay_enabled = false

	# Esconde os states até carregar a lição.
	sign_showcase.visible = false
	recording.visible = false
	feedback.visible = false

	# Pré-seleciona a melhor câmera disponível. Em web/mobile pode levar
	# alguns frames pro CameraServer popular feeds — então fazemos call_deferred.
	call_deferred("_auto_select_best_camera")
	# No Android os feeds registram assincronamente DEPOIS que o monitoramento
	# liga — a tentativa única acima roda cedo demais no dispositivo (verificado
	# via logcat: câmeras enumeradas, nenhuma selecionada). Retry por evento:
	CameraServer.camera_feed_added.connect(_on_camera_feed_added)

	var lesson_id := debug_lesson_id
	if lesson_id < 0:
		lesson_id = Global.current_lesson_id
	if lesson_id < 0:
		push_error("Nenhuma lesson_id definida")
		return

	LessonService.fetch_lesson(lesson_id, _on_lesson_loaded, _on_lesson_failed)


func _on_lesson_loaded(loaded: Lesson) -> void:
	lesson = loaded
	current_sign_index = 0
	_sign_stars.clear()
	_sign_stars.resize(lesson.sinais.size())

	if animation_player.has_animation_library(LIBRARY_NAME):
		animation_player.remove_animation_library(LIBRARY_NAME)
	animation_player.add_animation_library(LIBRARY_NAME, lesson.animation_library)

	state_machine.current_lesson = lesson
	state_machine.start()


func _on_lesson_failed(error: String) -> void:
	push_error("Falha ao carregar lição: %s" % error)


# ---------- CÂMERA ----------

## Um feed novo registrou no CameraServer. Se ainda estamos sem câmera,
## refaz a auto-seleção (a escolha manual do usuário nunca é sobrescrita
## porque com câmera ativa este handler não faz nada).
func _on_camera_feed_added(_id: int) -> void:
	if holistic == null or holistic.camera_feed != null:
		return
	call_deferred("_auto_select_best_camera")


func _auto_select_best_camera() -> void:
	if holistic == null or not holistic.has_method("pick_best_camera_id"):
		return
	if holistic.camera_feed != null:
		return   # já há câmera selecionada — evita restart em eventos em rajada
	if not _ensure_camera_permission():
		return
	var best_id: int = holistic.pick_best_camera_id()
	if best_id < 0:
		push_warning("Nenhuma câmera disponível para auto-seleção")
		return
	if not holistic.start_camera_with_feed(best_id):
		push_warning("Falha ao iniciar a câmera id=%d" % best_id)


## Em Android a permissão de câmera precisa ser concedida em runtime.
## Retorna true se a câmera já pode ser usada. Caso contrário dispara o
## pedido de permissão e a auto-seleção é refeita em _on_permissions_result.
func _ensure_camera_permission() -> bool:
	if OS.get_name() != "Android":
		return true
	if ANDROID_CAMERA_PERMISSION in OS.get_granted_permissions():
		return true
	if not get_tree().on_request_permissions_result.is_connected(_on_permissions_result):
		get_tree().on_request_permissions_result.connect(_on_permissions_result)
	OS.request_permission("CAMERA")
	return false


func _on_permissions_result(permission: String, granted: bool) -> void:
	if permission != ANDROID_CAMERA_PERMISSION:
		return
	if not granted:
		push_warning("Permissão de câmera negada — gravação indisponível")
		return
	# Força o CameraServer a re-enumerar os feeds agora que temos permissão.
	CameraServer.monitoring_feeds = false
	call_deferred("_auto_select_best_camera")


func _on_settings_pressed() -> void:
	if holistic == null:
		return
	var cameras: Array = holistic.list_available_cameras()
	var current_id := -1
	if holistic.camera_feed != null:
		current_id = holistic.camera_feed.get_id()
	camera_dialog.populate(cameras, current_id)
	camera_dialog.popup_centered()


func _on_camera_selected(feed_id: int) -> void:
	if holistic and holistic.has_method("start_camera_with_feed"):
		holistic.start_camera_with_feed(feed_id)


## Sempre que a câmera ativa muda, re-injeta as texturas no RecordingState.
func _on_camera_changed(_feed_name: String) -> void:
	_inject_camera_textures()


## Passa as texturas (crua + anotada) do holistic pro RecordingState.
## Adia o acesso à `image_view.texture` porque ela é criada após o
## primeiro frame processado.
func _inject_camera_textures() -> void:
	if holistic == null or recording == null:
		return
	if not recording.has_method("bind_camera_textures"):
		return

	var raw: Texture2D = null
	var annotated: Texture2D = null
	if holistic.has_method("get_camera_texture"):
		raw = holistic.get_camera_texture()
	if holistic.has_method("get_annotated_texture"):
		annotated = holistic.get_annotated_texture()
	recording.bind_camera_textures(raw, annotated)

	# As duas texturas saem do SubViewport, que já aplica rotação e o
	# espelhamento de selfie — um flip adicional aqui desfaria o espelho
	# (era o bug do overlay que invertia o mundo ao alternar o 👁).
	if recording.has_method("set_camera_mirrored"):
		recording.set_camera_mirrored(false)


# ---------- TRANSIÇÕES DE ESTADO ----------

func _show_only(state_node: Control) -> void:
	sign_showcase.visible = state_node == sign_showcase
	recording.visible = state_node == recording
	feedback.visible = state_node == feedback

	# Render do overlay do holistic é caro — só ligamos quando o
	# RecordingState está visível (ele é quem mostra o preview).
	if holistic and "render_overlay_enabled" in holistic:
		holistic.render_overlay_enabled = (state_node == recording)


func _on_enter_showcase() -> void:
	_show_only(sign_showcase)
	# Fora da gravação a câmera (feed + readback + inferência) fica pausada:
	# rodava o tempo todo gastando bateria com resultados descartados.
	if holistic and holistic.has_method("pause_camera"):
		holistic.pause_camera()
	btn_settings.disabled = false
	sign_showcase.setup(lesson, current_sign_index)


func _on_enter_recording() -> void:
	_show_only(recording)
	if holistic and holistic.has_method("resume_camera"):
		holistic.resume_camera()
	# Trocar de câmera no meio de uma captura resetava o pipeline e deixava
	# o estado preso em RECORDING pra sempre — engrenagem travada aqui.
	btn_settings.disabled = true
	# Garante que as texturas estão atualizadas (a anotada pode só existir
	# depois do primeiro frame ser processado, então atualizamos toda vez).
	_inject_camera_textures()
	var duration := _compute_capture_duration()
	recording.begin(lesson, current_sign_index, duration)


func _on_enter_feedback() -> void:
	_show_only(feedback)
	if holistic and holistic.has_method("pause_camera"):
		holistic.pause_camera()
	btn_settings.disabled = false
	feedback.evaluate(lesson, current_sign_index, _last_payload)


## A validação roda numa worker thread; as estrelas chegam por sinal.
## Guarda a melhor nota deste sinal (o usuário pode tentar de novo).
func _on_evaluation_completed(stars: int) -> void:
	if current_sign_index >= 0 and current_sign_index < _sign_stars.size():
		_sign_stars[current_sign_index] = maxi(_sign_stars[current_sign_index], stars)


## Duração da gravação = duração da animação do sinal atual + margem.
func _compute_capture_duration() -> float:
	if lesson == null or animation_player == null:
		return -1.0
	if current_sign_index < 0 or current_sign_index >= lesson.sinais.size():
		return -1.0

	var sinal: Dictionary = lesson.sinais[current_sign_index]
	var nome: String = String(sinal.get("nome_sinal", ""))
	if nome.is_empty():
		return -1.0

	var anim_path := "%s/%s" % [LIBRARY_NAME, nome]
	if not animation_player.has_animation(anim_path):
		push_warning("Animação '%s' não encontrada — usando duração default" % anim_path)
		return -1.0

	var anim: Animation = animation_player.get_animation(anim_path)
	if anim == null:
		return -1.0

	return anim.length + CAPTURE_MARGIN_SECONDS


# ---------- HOLISTIC ----------

func _on_request_start_capture(duration_seconds: float) -> void:
	if not holistic:
		push_warning("HolisticLandmarker indisponível")
		return

	if duration_seconds > 0.0:
		holistic.capture_duration_seconds = duration_seconds
		if holistic.capture_timer != null:
			holistic.capture_timer.wait_time = duration_seconds

	if holistic.has_method("_begin_capture"):
		holistic._begin_capture(duration_seconds)
	else:
		push_warning("HolisticLandmarker._begin_capture() indisponível")


func _on_request_reset_capture() -> void:
	if holistic and holistic.has_method("_reset"):
		holistic._reset()


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
		animation_player.play(path, 0.25, speed)
	else:
		push_warning("Animação não encontrada: %s" % path)


func _on_recording_finished(payload: Dictionary) -> void:
	_last_payload = payload
	state_machine.go_to_feedback()


func _on_recording_cancelled() -> void:
	state_machine.go_to_sign_showcase()


func _on_retry() -> void:
	state_machine.go_to_sign_showcase()


## Sai para o mapa sem marcar a lição como concluída.
func _on_see_modules() -> void:
	Global.go_to_map()


func _on_next_lesson() -> void:
	if lesson == null:
		Global.go_to_map()
		return

	current_sign_index += 1
	if current_sign_index < lesson.sinais.size():
		state_machine.go_to_sign_showcase()
	else:
		Global.mark_completed(lesson.lesson_id, _lesson_stars())
		Global.go_to_map()


## Estrelas da lição = pior sinal (a lição vale o quanto vale o sinal
## mais fraco). Antes era um 3 fixo que ignorava a nota calculada.
func _lesson_stars() -> int:
	if _sign_stars.is_empty():
		return 0
	var worst: int = 3
	for s: int in _sign_stars:
		worst = mini(worst, s)
	return worst


func _on_back() -> void:
	# Para captura e feed em qualquer estado — o CameraFeed vive no
	# CameraServer e sobreviveria à troca de cena.
	if holistic and holistic.has_method("_reset"):
		holistic._reset()
	Global.go_to_main_scene()
