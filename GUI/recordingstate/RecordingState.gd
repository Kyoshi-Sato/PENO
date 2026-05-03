class_name RecordingState
extends Control
## Estado de gravação. Fluxo:
##
##   1. begin() é chamado pela LessonScreen quando o estado fica visível
##   2. Mostra countdown 3 → 2 → 1 → "Vai!" (3 segundos)
##   3. Emite `request_start_capture` para a LessonScreen chamar
##      holistic._begin_capture() (que grava 10s e emite landmarks_detected)
##   4. Durante os 10s, mostra contador regressivo "Gravando Xs"
##   5. Ao receber on_capture_complete(payload), emite `recording_finished`
##
## Cancelamento (botão "Cancelar"):
##   - Durante countdown: aborta antes de iniciar a captura
##   - Durante gravação: pede reset do holistic e volta pro Showcase

signal recording_finished(payload: Dictionary)
signal cancel_requested
signal request_start_capture(tempo:int)
signal request_reset_capture

const COUNTDOWN_SECONDS := 3
const RECORDING_SECONDS := 10

enum Phase { IDLE, COUNTDOWN, RECORDING, DONE }

@onready var lbl_sign: Label = %SignPill
@onready var ring: PrecisionRing = %PrecisionRing
@onready var check_position: Control = %CheckPosition
@onready var check_movement: Control = %CheckMovement
@onready var check_orientation: Control = %CheckOrientation
@onready var lbl_hint: Label = %HintLabel
@onready var lbl_countdown: Label = %CountdownLabel
@onready var btn_cancel: Button = %CancelButton

var _phase: Phase = Phase.IDLE
var _reference_landmarks: Dictionary = {}
var _current_sign_name: String = ""
var _tick_timer: Timer
var _ticks_remaining: int = 0


func _ready() -> void:
	btn_cancel.pressed.connect(_on_cancel_pressed)

	_tick_timer = Timer.new()
	_tick_timer.wait_time = 1.0
	_tick_timer.one_shot = false
	add_child(_tick_timer)
	_tick_timer.timeout.connect(_on_tick)


## Chamado pela LessonScreen ao entrar neste estado.
func begin(lesson: Lesson, sign_index: int) -> void:
	if lesson == null or lesson.sinais.is_empty():
		return

	var idx := clampi(sign_index, 0, lesson.sinais.size() - 1)
	var sinal: Dictionary = lesson.sinais[idx]
	_current_sign_name = String(sinal.get("nome_sinal", ""))
	var ref: Variant = sinal.get("json_sinal", {})
	_reference_landmarks = ref if ref is Dictionary else {}

	lbl_sign.text = _current_sign_name.capitalize()
	ring.value = 0.0
	_set_check(check_position, "pending")
	_set_check(check_movement, "pending")
	_set_check(check_orientation, "pending")
	lbl_hint.text = "Posicione-se em frente à câmera"

	_start_countdown()


## Chamado pela LessonScreen quando o HolisticLandmarker termina os 10s
## e emite o signal `landmarks_detected` com o JSON exportado.
func on_capture_complete(export_data: Dictionary) -> void:
	if _phase != Phase.RECORDING:
		# Provavelmente cancelado — ignora.
		return
	_phase = Phase.DONE
	_tick_timer.stop()
	lbl_countdown.visible = false
	$ColorRect.hide()
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
	$ColorRect.show()
	lbl_countdown.text = str(_ticks_remaining)
	_tick_timer.start()


func _start_recording() -> void:
	_phase = Phase.RECORDING
	_ticks_remaining = RECORDING_SECONDS
	# "Vai!" fica visível pelo 1º segundo de gravação. No próximo tick
	# vira "Gravando 9s" e por aí vai.
	lbl_countdown.text = "Vai!"
	lbl_hint.text = "Faça o sinal agora"
	request_start_capture.emit(RECORDING_SECONDS)


func _on_tick() -> void:
	_ticks_remaining -= 1

	match _phase:
		Phase.COUNTDOWN:
			if _ticks_remaining > 0:
				# Ainda no countdown: mostra "2", "1"
				lbl_countdown.text = str(_ticks_remaining)
			else:
				# Chegou em zero: dispara captura E mostra "Vai!" simultaneamente.
				# A captura começa AGORA, não no próximo tick.
				_start_recording()
		Phase.RECORDING:
			if _ticks_remaining > 0:
				lbl_countdown.text = "Gravando %ds" % _ticks_remaining
			else:
				# O timer interno de 10s do holistic dispara
				# landmarks_detected logo após — esperamos esse signal.
				lbl_countdown.text = "Processando..."
				_tick_timer.stop()
		_:
			_tick_timer.stop()


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
	# Para o tick local
	_tick_timer.stop()
	lbl_countdown.visible = false

	# Se já tinha mandado iniciar captura, pede reset do holistic
	if _phase == Phase.RECORDING:
		request_reset_capture.emit()

	_phase = Phase.IDLE
	cancel_requested.emit()
