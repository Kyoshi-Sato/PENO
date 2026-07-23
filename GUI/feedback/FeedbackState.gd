class_name FeedbackState
extends Control
## Estado de feedback. Recebe o payload da gravação, calcula precisão via
## SignValidator (injetável), e mostra:
##   - "Parabéns! Muito bom!" + pill com nome do sinal
##   - 3 estrelas (preenchidas conforme nota)
##   - "+XP"
##   - 3 cards: Precisão / Tentativas / Tempo
##   - Barra de progresso do módulo
##   - "Próxima lição" / "Ver módulos"

signal retry_requested
signal next_lesson_requested
signal modules_requested
## Emitido quando a validação assíncrona termina e a UI foi preenchida.
signal evaluation_completed(stars: int)

@onready var lbl_title: Label = %TitleLabel
@onready var lbl_subtitle: Label = %SubtitleLabel
@onready var lbl_sign_pill: Label = %SignPill
@onready var stars: HBoxContainer = %Stars
@onready var lbl_xp: Label = %XPLabel

@onready var lbl_precision: Label = %PrecisionValue
@onready var lbl_attempts: Label = %AttemptsValue
@onready var lbl_time: Label = %TimeValue

@onready var lbl_module_name: Label = %ModuleNameLabel
@onready var bar_progress: ProgressBar = %ModuleProgress
@onready var lbl_progress_text: Label = %ModuleProgressText

@onready var btn_next: Button = %NextLessonButton
@onready var btn_retry: Button = %RetryButton
@onready var btn_modules: Button = %BackToMapButton

## Validator usado para comparar a gravação do usuário com a referência.
## Deixe null para usar o MotionComparatorValidator padrão.
## Para trocar de modelo: instancie outra subclasse de SignValidator e atribua.
var validator: SignValidator = null

var _attempts: int = 1
var _last_sign_index: int = -1
var _last_stars: int = 0
var _last_result: Dictionary = {}
## Descarta resultados de validações antigas se o usuário reavaliar rápido.
var _eval_generation: int = 0
# Contexto da avaliação em andamento (preenchido em evaluate, lido no done).
var _pending_lesson: Lesson = null
var _pending_idx: int = 0
var _pending_payload: Dictionary = {}


func _ready() -> void:
	btn_next.pressed.connect(func() -> void: next_lesson_requested.emit())
	btn_retry.pressed.connect(func() -> void: retry_requested.emit())
	btn_modules.pressed.connect(func() -> void: modules_requested.emit())

	if validator == null:
		validator = MotionComparatorValidator.new()


## Dispara a validação em uma thread do WorkerThreadPool e mostra a UI de
## espera. O resultado chega em _on_validation_done via call_deferred —
## antes disso a análise (1-8 s em GDScript) congelava a UI inteira.
func evaluate(lesson: Lesson, sign_index: int, payload: Dictionary) -> void:
	if lesson == null:
		return

	var idx := clampi(sign_index, 0, lesson.sinais.size() - 1)
	var sinal: Dictionary = lesson.sinais[idx]
	var nome: String = String(sinal.get("nome_sinal", ""))

	# Tentativas: conta re-execuções do mesmo sinal, zera ao trocar de sinal.
	if idx == _last_sign_index:
		_attempts += 1
	else:
		_attempts = 1
		_last_sign_index = idx

	_pending_lesson = lesson
	_pending_idx = idx
	_pending_payload = payload

	# UI de espera imediata
	lbl_title.text = "Analisando..."
	lbl_subtitle.visible = true
	lbl_subtitle.text = "Avaliando sua execução do sinal."
	lbl_sign_pill.text = nome.capitalize()
	_update_stars(0)
	lbl_xp.text = ""
	_set_buttons_enabled(false)

	# A referência (json_sinal) já vem no formato {video_info, frames} do LessonService.
	var reference: Dictionary = sinal.get("json_sinal", {}) as Dictionary

	_eval_generation += 1
	var generation := _eval_generation

	if validator == null:
		push_warning("FeedbackState: nenhum validator definido")
		_on_validation_done({}, generation)
		return

	# Capturas locais: o validator (RefCounted) fica vivo pela lambda e a
	# entrega via Callable.call_deferred é ignorada se este nó for liberado.
	var val: SignValidator = validator
	var deliver: Callable = _on_validation_done
	WorkerThreadPool.add_task(func() -> void:
		var result: Dictionary = val.validate(payload, reference)
		deliver.call_deferred(result, generation)
	)


func _on_validation_done(result: Dictionary, generation: int) -> void:
	if generation != _eval_generation:
		return   # resultado de uma avaliação antiga — descarta

	_last_result = result

	var precision := 0.0
	if result.get("ok", false):
		precision = float(result.get("precision", 0.0))
	elif not result.is_empty():
		push_warning("Validação falhou: %s" % result.get("error", ""))

	var time_seconds := _compute_time_seconds(_pending_payload)
	var num_stars := _stars_for_precision(precision)
	_last_stars = num_stars
	_apply_result_copy(num_stars)

	_update_stars(num_stars)
	lbl_xp.text = "+ %d XP" % (num_stars * 20)

	lbl_precision.text = "%d%%" % int(round(precision * 100.0))
	lbl_attempts.text = str(_attempts)
	lbl_time.text = _format_time(time_seconds)

	# Progresso do módulo
	var total := _pending_lesson.sinais.size() if _pending_lesson else 0
	var done := _pending_idx + 1
	lbl_module_name.text = _pending_lesson.nome_exercicio if _pending_lesson else ""
	bar_progress.max_value = float(maxi(total, 1))
	bar_progress.value = float(done)
	lbl_progress_text.text = "%d / %d lições" % [done, total]

	_set_buttons_enabled(true)
	evaluation_completed.emit(num_stars)


func _set_buttons_enabled(enabled: bool) -> void:
	btn_next.disabled = not enabled
	btn_retry.disabled = not enabled
	btn_modules.disabled = not enabled


## Retorna o resultado completo do último validate(), pra UI mais detalhada
## (ex: tela de "ver detalhes" com precisão por mão, por osso etc).
func get_last_result() -> Dictionary:
	return _last_result


## Estrelas da última avaliação — usado pelo LessonScreen pra persistir
## o progresso real da lição.
func get_last_stars() -> int:
	return _last_stars


## Título/subtítulo condizentes com o resultado (antes era sempre "Parabéns!").
func _apply_result_copy(num_stars: int) -> void:
	lbl_subtitle.visible = true

	if not bool(_last_result.get("ok", false)):
		lbl_title.text = "Ops!"
		lbl_subtitle.text = "Não conseguimos avaliar sua gravação.\nConfira se você aparece na câmera e tente de novo."
		return

	# Grupos exigidos pelo gabarito mas nunca detectados no usuário
	# (flag preenchida pelo MotionComparator — ver _missing_groups).
	var details: Dictionary = _last_result.get("details", {}) as Dictionary
	var missing: Array = details.get("_missing_groups", []) as Array
	if missing.has("Mão Esquerda") or missing.has("Mão Direita"):
		lbl_title.text = "Não vimos suas mãos"
		lbl_subtitle.text = "Fique visível na câmera, com as mãos aparecendo,\ne tente novamente."
		return

	match num_stars:
		3:
			lbl_title.text = "Perfeito!"
			lbl_subtitle.text = "Execução impecável do sinal!"
		2:
			lbl_title.text = "Parabéns!"
			lbl_subtitle.text = "Muito bom! Continue praticando."
		1:
			lbl_title.text = "Quase lá!"
			lbl_subtitle.text = "Bom começo — tente de novo para melhorar."
		_:
			lbl_title.text = "Vamos tentar de novo?"
			lbl_subtitle.text = "Observe o avatar com atenção e repita o sinal."


# ---------- HEURÍSTICAS ----------

func _compute_time_seconds(payload: Dictionary) -> int:
	# O HolisticLandmarker exporta video_info com total_frames + fps reais.
	var info: Variant = payload.get("video_info", {})
	if info is Dictionary:
		var fps: float = float(info.get("fps", 0.0))
		var total: int = int(info.get("total_frames", 0))
		if fps > 0.0 and total > 0:
			return int(round(float(total) / fps))
	# Fallback: assume ~30fps.
	var frames: Array = payload.get("frames", [])
	return int(round(float(frames.size()) / 30.0))


func _stars_for_precision(precision: float) -> int:
	if precision >= 0.9:
		return 3
	elif precision >= 0.7:
		return 2
	elif precision >= 0.5:
		return 1
	return 0


func _update_stars(num: int) -> void:
	for i in range(stars.get_child_count()):
		var star: Label = stars.get_child(i)
		if i < num:
			star.text = "★"
			star.modulate = Color(1.0, 0.78, 0.2)
		else:
			star.text = "☆"
			star.modulate = Color(0.85, 0.88, 0.92)


func _format_time(total_seconds: int) -> String:
	var m := total_seconds / 60
	var s := total_seconds % 60
	return "%02d:%02d" % [m, s]
