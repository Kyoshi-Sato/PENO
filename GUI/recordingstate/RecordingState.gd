class_name RecordingState
extends Control
## Estado de gravação. Fluxo:
##
##   1. begin(lesson, sign_index, duration) é chamado pela LessonScreen
##      quando o estado fica visível. A duration vem do animation_player
##      (length da animação + margem) e é repassada pro holistic.
##   2. Mostra countdown 3 → 2 → 1 → "Vai!" (3 segundos)
##   3. Emite `request_start_capture(duration_seconds)` para a LessonScreen
##      configurar e chamar holistic._begin_capture()
##   4. Durante a gravação, mostra contador regressivo "Gravando Xs"
##   5. Ao receber on_capture_complete(payload), emite `recording_finished`
##
## Preview de câmera:
##   A LessonScreen chama bind_camera_textures(raw, annotated) com as
##   texturas do HolisticLandmarker. O toggle "👁" alterna entre as duas.
##
## Cancelamento (botão "Cancelar"):
##   - Durante countdown: aborta antes de iniciar a captura
##   - Durante gravação: pede reset do holistic e volta pro Showcase

signal recording_finished(payload: Dictionary)
signal cancel_requested
signal request_start_capture(duration_seconds: float)
signal request_reset_capture

const COUNTDOWN_SECONDS := 3
const DEFAULT_RECORDING_SECONDS := 10

enum Phase { IDLE, COUNTDOWN, RECORDING, DONE }

@onready var lbl_sign: Label = %SignPill
@onready var ring: PrecisionRing = %PrecisionRing
@onready var check_position: Control = %CheckPosition
@onready var check_movement: Control = %CheckMovement
@onready var check_orientation: Control = %CheckOrientation
@onready var lbl_hint: Label = %HintLabel
@onready var lbl_countdown: Label = %CountdownLabel
@onready var btn_cancel: Button = %CancelButton

@onready var camera_preview: TextureRect = %CameraPreview
@onready var btn_overlay_toggle: Button = %OverlayToggle
@onready var color_rect: ColorRect = $ColorRect

var _phase: Phase = Phase.IDLE
var _reference_landmarks: Dictionary = {}
var _current_sign_name: String = ""
var _tick_timer: Timer
var _ticks_remaining: int = 0
var _recording_seconds: int = DEFAULT_RECORDING_SECONDS
var _recording_seconds_f: float = float(DEFAULT_RECORDING_SECONDS)

## Texturas vindas do HolisticLandmarker (injetadas pela LessonScreen).
var _raw_texture: Texture2D = null
var _annotated_texture: Texture2D = null
## true = mostra landmarks por cima; false = só câmera crua.
var _overlay_enabled: bool = true


func _ready() -> void:
	btn_cancel.pressed.connect(_on_cancel_pressed)
	btn_overlay_toggle.pressed.connect(_on_overlay_toggle)

	_tick_timer = Timer.new()
	_tick_timer.wait_time = 1.0
	_tick_timer.one_shot = false
	add_child(_tick_timer)
	_tick_timer.timeout.connect(_on_tick)

	camera_preview.visible = false
	_update_overlay_button_label()


## Injeta as texturas de preview vindas do HolisticLandmarker.
## Chamado pela LessonScreen quando a câmera fica disponível.
## raw: textura crua da câmera (sem landmarks)
## annotated: textura com landmarks renderizados
func bind_camera_textures(raw: Texture2D, annotated: Texture2D) -> void:
	_raw_texture = raw
	_annotated_texture = annotated
	_apply_preview_texture()


## true = câmera frontal (espelha horizontalmente o preview).
func set_camera_mirrored(mirrored: bool) -> void:
	if camera_preview:
		camera_preview.flip_h = mirrored


## Chamado pela LessonScreen ao entrar neste estado.
func begin(lesson: Lesson, sign_index: int, duration_seconds: float = -1.0) -> void:
	if lesson == null or lesson.sinais.is_empty():
		return

	var idx := clampi(sign_index, 0, lesson.sinais.size() - 1)
	var sinal: Dictionary = lesson.sinais[idx]
	_current_sign_name = String(sinal.get("nome_sinal", ""))
	var ref: Variant = sinal.get("json_sinal", {})
	_reference_landmarks = ref if ref is Dictionary else {}

	if duration_seconds > 0.0:
		_recording_seconds_f = duration_seconds
		_recording_seconds = int(ceilf(duration_seconds))
	else:
		_recording_seconds_f = float(DEFAULT_RECORDING_SECONDS)
		_recording_seconds = DEFAULT_RECORDING_SECONDS

	lbl_sign.text = _current_sign_name.capitalize()
	ring.value = 0.0
	_set_check(check_position, "pending")
	_set_check(check_movement, "pending")
	_set_check(check_orientation, "pending")
	lbl_hint.text = "Posicione-se em frente à câmera"

	# Esconde preview no início — só aparece quando a gravação começar
	camera_preview.visible = false
	color_rect.show()

	_start_countdown()


func on_capture_complete(export_data: Dictionary) -> void:
	if _phase != Phase.RECORDING:
		return
	_phase = Phase.DONE
	_tick_timer.stop()
	lbl_countdown.visible = false
	color_rect.hide()
	camera_preview.visible = false

	var payload := {
		"sign_id": _current_sign_name,
		"frames": export_data.get("frames", []),
		"video_info": export_data.get("video_info", {}),
		"reference": _reference_landmarks,
	}
	recording_finished.emit(payload)


# ---------- COUNTDOWN ----------

func _start_countdown() -> void:
	_phase = Phase.COUNTDOWN
	_ticks_remaining = COUNTDOWN_SECONDS
	lbl_countdown.visible = true
	color_rect.show()
	lbl_countdown.text = str(_ticks_remaining)
	_tick_timer.start()


func _start_recording() -> void:
	_phase = Phase.RECORDING
	_ticks_remaining = _recording_seconds
	lbl_countdown.text = "Vai!"
	lbl_hint.text = "Faça o sinal agora"
	# Câmera fica visível durante a gravação (cobre o ColorRect preto)
	camera_preview.visible = true
	color_rect.hide()
	_apply_preview_texture()
	request_start_capture.emit(_recording_seconds_f)


func _on_tick() -> void:
	_ticks_remaining -= 1

	match _phase:
		Phase.COUNTDOWN:
			if _ticks_remaining > 0:
				lbl_countdown.text = str(_ticks_remaining)
			else:
				_start_recording()
		Phase.RECORDING:
			if _ticks_remaining > 0:
				lbl_countdown.text = "Gravando %ds" % _ticks_remaining
			else:
				lbl_countdown.text = "Processando..."
				_tick_timer.stop()
		_:
			_tick_timer.stop()


# ---------- PREVIEW DA CÂMERA ----------

func _on_overlay_toggle() -> void:
	_overlay_enabled = not _overlay_enabled
	_update_overlay_button_label()
	_apply_preview_texture()


func _update_overlay_button_label() -> void:
	if btn_overlay_toggle == null:
		return
	if _overlay_enabled:
		btn_overlay_toggle.text = "👁  Pontos: ON"
	else:
		btn_overlay_toggle.text = "👁  Pontos: OFF"


func _apply_preview_texture() -> void:
	if camera_preview == null:
		return
	if _overlay_enabled and _annotated_texture != null:
		camera_preview.texture = _annotated_texture
	elif _raw_texture != null:
		camera_preview.texture = _raw_texture


# ---------- CHECKLIST ----------

## status: "pending" | "ok" | "warn" | "fail"
func _set_check(check_node: Control, status: String) -> void:
	if check_node == null:
		return
	var icon: Label = check_node.get_node_or_null("HBox/Icon")
	if icon == null:
		return
	match status:
		"ok":
			icon.text = "✓"
			icon.modulate = Color(0.18, 0.78, 0.45)
		"warn":
			icon.text = "!"
			icon.modulate = Color(0.95, 0.65, 0.15)
		"fail":
			icon.text = "✕"
			icon.modulate = Color(0.85, 0.25, 0.25)
		_:
			icon.text = "○"
			icon.modulate = Color(0.65, 0.68, 0.72)


# ---------- CANCELAMENTO ----------

func _on_cancel_pressed() -> void:
	_tick_timer.stop()
	lbl_countdown.visible = false
	color_rect.hide()
	camera_preview.visible = false

	if _phase == Phase.RECORDING:
		request_reset_capture.emit()

	_phase = Phase.IDLE
	cancel_requested.emit()
