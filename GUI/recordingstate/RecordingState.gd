class_name RecordingState
extends Control
## Etapa PRATIQUE. Fluxo (inalterado em relação à versão anterior):
##
##   1. begin(lesson, sign_index, duration) é chamado pela LessonScreen
##      quando o estado fica visível. A duration vem do animation_player
##      (length da animação + margem) e é repassada pro holistic.
##   2. Mostra countdown 3 → 2 → 1
##   3. Emite `request_start_capture(duration_seconds)` para a LessonScreen
##      configurar e chamar holistic._begin_capture()
##   4. Durante a gravação, mostra o tempo restante e uma barra de captura
##   5. Ao receber on_capture_complete(payload), emite `recording_finished`
##
## Mudanças de UX:
##   - A câmera fica visível DESDE a contagem. Antes a tela ficava preta até
##     a gravação começar, enquanto pedia "Posicione-se em frente à câmera" —
##     era exatamente no momento de se enquadrar que o usuário não podia se
##     ver. Um véu semitransparente garante a leitura do texto por cima.
##   - As dicas de enquadramento aparecem SÓ durante a contagem e somem quando
##     a gravação começa: durante a captura a câmera não pode competir com
##     nada. Elas substituem o antigo "checklist" de três itens que ficava
##     permanentemente em ○ porque nada nunca o atualizava — um placeholder
##     que dava a impressão de uma validação em tempo real inexistente.
##   - O escurecimento sobre a câmera some quando a gravação começa, para o
##     usuário se ver com nitidez máxima no momento que importa.

signal recording_finished(payload: Dictionary)
signal cancel_requested
signal request_start_capture(duration_seconds: float)
signal request_reset_capture

const COUNTDOWN_SECONDS := 3
const DEFAULT_RECORDING_SECONDS := 10
## Véu sobre a câmera durante a contagem. Alto o bastante para o texto branco
## ficar legível sobre qualquer cena, baixo o bastante para o usuário se ver.
const SCRIM_ALPHA := 0.4

## Ajustes de enquadramento que dependem só do usuário — nenhum deles
## pretende ser um resultado de detecção.
const FRAMING_TIPS: Array[Dictionary] = [
	{"icon": HSIcon.Name.PROFILE, "text": "Fique a um braço de distância da câmera"},
	{"icon": HSIcon.Name.HAND, "text": "Mãos e rosto inteiros dentro do quadro"},
	{"icon": HSIcon.Name.EYE, "text": "Luz de frente para você, não atrás"},
]

## Transposição do pip da contagem, do "3" ao "1". Subir meio tom por número
## faz a contagem soar como uma contagem e não como três toques iguais — é a
## mesma informação que o numeral já dá, no canal sonoro.
const COUNTDOWN_PITCHES: Array[float] = [1.0, 1.12, 1.26]

enum Phase { IDLE, WAITING_CAMERA, COUNTDOWN, RECORDING, DONE }

@onready var lbl_sign: Label = %SignPill
@onready var lbl_hint: Label = %HintLabel
@onready var lbl_countdown: Label = %CountdownLabel
@onready var lbl_status: Label = %StatusLabel
@onready var btn_cancel: Button = %CancelButton
@onready var tips_card: MarginContainer = %TipsMargin
@onready var tips_box: VBoxContainer = %Tips
@onready var capture_bar: ProgressBar = %CaptureBar
@onready var scrim: ColorRect = %Scrim
@onready var overlay_slot: HBoxContainer = %OverlaySlot

@onready var camera_preview: TextureRect = %CameraPreview

var is_camera_ready_override: bool = false
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
var _btn_overlay: IconButton


func _ready() -> void:
	btn_cancel.pressed.connect(_on_cancel_pressed)
	Motion.attach_press(btn_cancel)

	_btn_overlay = IconButton.create(HSIcon.Name.EYE, IconButton.Tone.ON_DARK)
	_btn_overlay.pressed.connect(_on_overlay_toggle)
	overlay_slot.add_child(_btn_overlay)

	_build_tips()

	_tick_timer = Timer.new()
	_tick_timer.wait_time = 1.0
	_tick_timer.one_shot = false
	add_child(_tick_timer)
	_tick_timer.timeout.connect(_on_tick)

	capture_bar.visible = false
	_update_overlay_button()


func _build_tips() -> void:
	for spec: Dictionary in FRAMING_TIPS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", DS.SPACE_SM)
		tips_box.add_child(row)

		var glyph := HSIcon.new()
		glyph.icon = spec["icon"]
		glyph.color = DS.PRIMARY
		glyph.custom_minimum_size = Vector2(48, 48)
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(glyph)

		var lbl := Label.new()
		lbl.theme_type_variation = &"BodySm"
		lbl.text = String(spec["text"])
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(lbl)


## Injeta as texturas de preview vindas do HolisticLandmarker.
func bind_camera_textures(raw: Texture2D, annotated: Texture2D) -> void:
	_raw_texture = raw
	_annotated_texture = annotated
	_apply_preview_texture()
	if raw != null or annotated != null:
		notify_camera_ready()


func notify_camera_ready() -> void:
	is_camera_ready_override = true
	if _phase == Phase.WAITING_CAMERA:
		lbl_status.text = "Prepare-se"
		lbl_hint.text = "Posicione-se em frente à câmera"
		_start_countdown()


func _is_camera_ready() -> bool:
	if is_camera_ready_override:
		return true
	return _raw_texture != null or _annotated_texture != null


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

	lbl_sign.text = DS.sentence_case(_current_sign_name)

	capture_bar.visible = false
	capture_bar.value = 0.0
	tips_card.visible = true
	tips_card.modulate.a = 1.0
	scrim.visible = true
	scrim.color.a = SCRIM_ALPHA

	# A câmera já entra visível: é durante a contagem que o usuário precisa
	# se enquadrar. O ColorRect fica atrás como fundo para o caso de a
	# textura ainda não ter chegado no primeiro quadro.
	camera_preview.visible = true
	_apply_preview_texture()

	if not _is_camera_ready():
		_wait_for_camera_and_start()
	else:
		lbl_hint.text = "Posicione-se em frente à câmera"
		lbl_status.text = "Prepare-se"
		_start_countdown()


func _wait_for_camera_and_start() -> void:
	_phase = Phase.WAITING_CAMERA
	lbl_status.text = "Iniciando câmera..."
	lbl_hint.text = "Aguarde a câmera carregar para se posicionar"
	lbl_countdown.visible = true
	_set_countdown("⏳")

	# Aguarda até a câmera estar pronta com timeout de segurança (4.0s)
	var timed_out := false
	var timer := get_tree().create_timer(4.0)
	timer.timeout.connect(func() -> void: timed_out = true)

	while not _is_camera_ready() and not timed_out:
		await get_tree().process_frame
		_apply_preview_texture()

	if _phase == Phase.WAITING_CAMERA:
		lbl_status.text = "Prepare-se"
		lbl_hint.text = "Posicione-se em frente à câmera"
		_start_countdown()


func on_capture_complete(export_data: Dictionary) -> void:
	if _phase != Phase.RECORDING:
		return
	_phase = Phase.DONE
	_tick_timer.stop()
	lbl_countdown.visible = false
	capture_bar.visible = false
	# Duas notas descendo: "pode baixar as mãos". Deliberadamente neutro — a
	# nota ainda não foi calculada, e um som de acerto aqui prometeria um
	# resultado que a análise ainda pode desmentir.
	Audio.play(Audio.Cue.CAPTURE_DONE)

	var payload := {
		"sign_id": _current_sign_name,
		"nome_sinal": _current_sign_name,
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
	_set_countdown(str(_ticks_remaining))
	_tick_timer.start()


func _start_recording() -> void:
	_phase = Phase.RECORDING
	_ticks_remaining = _recording_seconds
	lbl_countdown.visible = false
	lbl_status.text = "Gravando"
	lbl_hint.text = "Faça o sinal agora"

	# Câmera limpa: dicas, véu e numeral saem de cena juntos.
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(tips_card, "modulate:a", 0.0, DS.DUR_FAST)
	t.tween_property(scrim, "color:a", 0.0, DS.DUR_FAST)
	t.chain().tween_callback(func() -> void:
		tips_card.visible = false
		scrim.visible = false)

	capture_bar.visible = true
	capture_bar.value = 0.0
	Motion.fill_bar(capture_bar, 1.0, _recording_seconds_f)

	_apply_preview_texture()
	# Antes de emitir: o `request_start_capture` faz a LessonScreen montar a
	# captura, e essa chamada pode segurar o quadro. O som tem que sair junto
	# com a barra, não depois dela.
	Audio.play(Audio.Cue.RECORD_START)
	request_start_capture.emit(_recording_seconds_f)


func _set_countdown(text: String) -> void:
	lbl_countdown.text = text
	# Cada número entra com um pulso: sem isso a contagem parece travada,
	# porque só o glifo muda numa tela sem mais nenhum movimento.
	Motion.pulse(lbl_countdown, 1.18)
	# O pip permite se enquadrar olhando para a câmera em vez de para o
	# numeral — que é justamente o que a contagem existe para o usuário fazer.
	Audio.play(Audio.Cue.COUNTDOWN, _countdown_pitch())


## Pitch do pip atual. `_ticks_remaining` conta para baixo (3, 2, 1), então o
## índice sobe conforme a contagem desce e a melodia sobe junto.
func _countdown_pitch() -> float:
	var idx: int = COUNTDOWN_SECONDS - _ticks_remaining
	if idx < 0 or idx >= COUNTDOWN_PITCHES.size():
		return 1.0
	return COUNTDOWN_PITCHES[idx]


func _on_tick() -> void:
	_ticks_remaining -= 1

	match _phase:
		Phase.COUNTDOWN:
			if _ticks_remaining > 0:
				_set_countdown(str(_ticks_remaining))
			else:
				_start_recording()
		Phase.RECORDING:
			if _ticks_remaining > 0:
				lbl_status.text = "Gravando · %ds" % _ticks_remaining
			else:
				lbl_status.text = "Analisando seu sinal…"
				lbl_hint.text = "Só um instante"
				_tick_timer.stop()
		_:
			_tick_timer.stop()


# ---------- PREVIEW DA CÂMERA ----------

func _on_overlay_toggle() -> void:
	_overlay_enabled = not _overlay_enabled
	_update_overlay_button()
	_apply_preview_texture()


func _update_overlay_button() -> void:
	if _btn_overlay == null:
		return
	# O próprio ícone diz o estado (olho aberto / olho cortado); o rótulo
	# "👁 Pontos: ON" virava um botão de texto largo em cima da câmera.
	_btn_overlay.glyph_icon = HSIcon.Name.EYE if _overlay_enabled else HSIcon.Name.EYE_OFF
	_btn_overlay.tooltip_text = "Pontos de detecção: %s" % (
		"visíveis" if _overlay_enabled else "ocultos")


func _apply_preview_texture() -> void:
	if camera_preview == null:
		return
	if _overlay_enabled and _annotated_texture != null:
		camera_preview.texture = _annotated_texture
	elif _raw_texture != null:
		camera_preview.texture = _raw_texture


# ---------- CANCELAMENTO ----------

func _on_cancel_pressed() -> void:
	_tick_timer.stop()
	lbl_countdown.visible = false
	capture_bar.visible = false

	if _phase == Phase.RECORDING:
		request_reset_capture.emit()

	_phase = Phase.IDLE
	cancel_requested.emit()
