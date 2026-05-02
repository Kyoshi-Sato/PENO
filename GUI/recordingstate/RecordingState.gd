class_name RecordingState
extends Control

## Estado de gravação. Faz contagem regressiva (estilo "3, 2, 1, JÁ!"),
## inicia a captura, e ao fim do tempo parametrizado emite o JSON capturado.

signal countdown_started(seconds: int)
signal countdown_tick(seconds_remaining: int)
signal recording_started
signal recording_finished(captured_json: Dictionary)

## Duração do countdown antes de começar a gravar.
@export var countdown_seconds: int = 3
## Duração da gravação propriamente dita.
@export var recording_duration_seconds: float = 5.0

@onready var lbl_countdown: Label = $Panel/Countdown
@onready var lbl_status: Label = $Panel/Status
@onready var progress: ProgressBar = $Panel/Progress
@onready var countdown_timer: Timer = $CountdownTimer
@onready var record_timer: Timer = $RecordTimer

## Frames capturados durante a gravação. Cada item é um Dictionary com
## landmarks vindo do HolisticLandmarker (ou similar).
var captured_frames: Array[Dictionary] = []
var _countdown_remaining: int = 0
var _is_recording: bool = false


func _ready() -> void:
	countdown_timer.wait_time = 1.0
	countdown_timer.one_shot = false
	countdown_timer.timeout.connect(_on_countdown_tick)
	record_timer.one_shot = true
	record_timer.timeout.connect(_on_record_finished)
	progress.value = 0
	progress.hide()
	lbl_status.text = ""


func _process(delta: float) -> void:
	if _is_recording and not record_timer.is_stopped():
		var elapsed := recording_duration_seconds - record_timer.time_left
		progress.value = (elapsed / recording_duration_seconds) * 100.0


## Inicia o fluxo: countdown -> gravação -> emite resultado.
func begin() -> void:
	captured_frames.clear()
	_is_recording = false
	progress.value = 0
	progress.hide()
	_countdown_remaining = countdown_seconds
	lbl_countdown.text = str(_countdown_remaining)
	lbl_countdown.show()
	lbl_status.text = "Prepare-se..."
	countdown_started.emit(countdown_seconds)
	countdown_timer.start()


## Chamado externamente (pelo HolisticLandmarker, por exemplo) a cada frame
## reconhecido. Só armazena se estiver de fato gravando.
func push_frame(frame: Dictionary) -> void:
	if _is_recording:
		captured_frames.append(frame)


func _on_countdown_tick() -> void:
	_countdown_remaining -= 1
	if _countdown_remaining > 0:
		lbl_countdown.text = str(_countdown_remaining)
		countdown_tick.emit(_countdown_remaining)
	else:
		countdown_timer.stop()
		_start_recording()


func _start_recording() -> void:
	_is_recording = true
	lbl_countdown.text = "REC"
	lbl_status.text = "Gravando..."
	progress.show()
	progress.value = 0
	record_timer.wait_time = recording_duration_seconds
	record_timer.start()
	recording_started.emit()


func _on_record_finished() -> void:
	_is_recording = false
	lbl_countdown.hide()
	lbl_status.text = "Processando..."
	progress.value = 100
	var payload := {
		"frames": captured_frames,
		"duration": recording_duration_seconds,
		"frame_count": captured_frames.size(),
	}
	recording_finished.emit(payload)


## Cancela a gravação em andamento (caso usuário saia da tela).
func cancel() -> void:
	countdown_timer.stop()
	record_timer.stop()
	_is_recording = false
	captured_frames.clear()


## Retorna os frames capturados no formato de payload usado pelo Feedback.
func captured_frames_payload() -> Dictionary:
	return {
		"frames": captured_frames,
		"duration": recording_duration_seconds,
		"frame_count": captured_frames.size(),
	}


## Exporta os frames capturados para um JSON em disco (útil para depuração
## ou para gerar novos JSONs de validação).
func export_to_json(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(captured_frames_payload(), "\t"))
	return OK
