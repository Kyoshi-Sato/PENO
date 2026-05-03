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
@onready var btn_modules: Button = %SeeModulesButton

## Validator usado para comparar a gravação do usuário com a referência.
## Deixe null para usar o MotionComparatorValidator padrão.
## Para trocar de modelo: instancie outra subclasse de SignValidator e atribua.
var validator: SignValidator = null

var _attempts: int = 1
var _last_result: Dictionary = {}


func _ready() -> void:
	btn_next.pressed.connect(func() -> void: next_lesson_requested.emit())
	btn_modules.pressed.connect(func() -> void: retry_requested.emit())

	if validator == null:
		validator = MotionComparatorValidator.new()


func evaluate(lesson: Lesson, sign_index: int, payload: Dictionary) -> void:
	if lesson == null:
		return

	var idx := clampi(sign_index, 0, lesson.sinais.size() - 1)
	var sinal: Dictionary = lesson.sinais[idx]
	var nome: String = String(sinal.get("nome_sinal", ""))

	# A referência (json_sinal) já vem no formato {video_info, frames} do LessonService.
	var reference: Dictionary = sinal.get("json_sinal", {}) as Dictionary

	var precision := _compute_precision(payload, reference)
	var time_seconds := _compute_time_seconds(payload)

	lbl_title.text = "Parabéns!"
	lbl_subtitle.text = "Muito bom!\nVocê concluiu a lição"
	lbl_sign_pill.text = nome.capitalize()

	var num_stars := _stars_for_precision(precision)
	_update_stars(num_stars)
	lbl_xp.text = "+ %d XP" % (num_stars * 20)

	lbl_precision.text = "%d%%" % int(round(precision * 100.0))
	lbl_attempts.text = str(_attempts)
	lbl_time.text = _format_time(time_seconds)

	# Progresso do módulo
	var total := lesson.sinais.size()
	var done := idx + 1
	lbl_module_name.text = lesson.nome_exercicio
	bar_progress.max_value = float(total)
	bar_progress.value = float(done)
	lbl_progress_text.text = "%d / %d lições" % [done, total]


## Retorna o resultado completo do último validate(), pra UI mais detalhada
## (ex: tela de "ver detalhes" com precisão por mão, por osso etc).
func get_last_result() -> Dictionary:
	return _last_result


# ---------- HEURÍSTICAS ----------

func _compute_precision(payload: Dictionary, reference: Dictionary) -> float:
	if validator == null:
		push_warning("FeedbackState: nenhum validator definido")
		return 0.0

	var result: Dictionary = validator.validate(payload, reference)
	_last_result = result

	if not result.get("ok", false):
		push_warning("Validação falhou: %s" % result.get("error", ""))
		return 0.0

	return float(result.get("precision", 0.0))


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
