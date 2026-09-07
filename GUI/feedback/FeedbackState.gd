class_name FeedbackState
extends Control
## Etapa RESULTADO. Recebe o payload da gravação, calcula precisão via
## SignValidator (injetável) e responde a duas perguntas, nesta ordem:
##
##   1. "Fui bem?"      → título, anel de precisão, estrelas, XP ganho
##   2. "O que corrigir?" → uma linha por parâmetro do sinal (corpo, mão
##      esquerda, mão direita) com nota, cobertura de detecção e o que fazer
##
## A segunda parte é nova. Os dados sempre existiram — `MotionComparator`
## devolve `group_similarity_pct`, `detection_coverage` e `missing_in_user`
## por grupo — mas eram descartados, e a tela mostrava apenas uma
## porcentagem global. Um usuário com 40% não tinha como saber se errou o
## movimento ou se simplesmente estava fora do quadro.

signal retry_requested
signal next_lesson_requested
signal modules_requested
## Emitido quando a validação assíncrona termina e a UI foi preenchida.
signal evaluation_completed(stars: int)

## Rótulos amigáveis para os grupos que o comparador devolve.
const GROUP_LABELS: Dictionary = {
	"Pose (corpo)": "Corpo e posicionamento",
	"Mão Esquerda": "Mão esquerda",
	"Mão Direita": "Mão direita",
}

@onready var result_card: PanelContainer = %ResultCard
@onready var lbl_title: Label = %TitleLabel
@onready var lbl_subtitle: Label = %SubtitleLabel
@onready var ring: PrecisionRing = %PrecisionRing
@onready var stars_row: HBoxContainer = %StarsRow
@onready var reward_row: HBoxContainer = %RewardRow

@onready var lbl_breakdown_title: Label = %BreakdownTitle
@onready var breakdown: VBoxContainer = %Breakdown
@onready var metrics_row: HBoxContainer = %MetricsRow

@onready var module_card: PanelContainer = %ModuleCard
@onready var lbl_module_name: Label = %ModuleNameLabel
@onready var bar_progress: ProgressBar = %ModuleProgress
@onready var lbl_progress_text: Label = %ModuleProgressText

@onready var btn_next: Button = %NextLessonButton
@onready var btn_retry: Button = %RetryButton
@onready var btn_modules: Button = %BackToMapButton

## Validator usado para comparar a gravação do usuário com a referência.
## Deixe null para usar o MotionComparatorValidator padrão.
var validator: SignValidator = null

var _stars: StarRow
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

	for b: Button in [btn_next, btn_retry, btn_modules]:
		Motion.attach_press(b)

	_stars = StarRow.create(0, 96)
	stars_row.add_child(_stars)

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

	# Tentativas: conta re-execuções do mesmo sinal, zera ao trocar de sinal.
	if idx == _last_sign_index:
		_attempts += 1
	else:
		_attempts = 1
		_last_sign_index = idx

	_pending_lesson = lesson
	_pending_idx = idx
	_pending_payload = payload

	_show_analyzing()

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


## Estado de espera: a tela some quase inteira e sobra só o essencial, para
## não piscar números velhos enquanto a nova análise roda.
func _show_analyzing() -> void:
	lbl_title.text = "Analisando…"
	lbl_subtitle.text = "Comparando sua execução com o sinal de referência."
	ring.value = 0.0
	ring.color_fg = DS.PRIMARY_TINT_STRONG
	_stars.stars = 0

	_clear(reward_row)
	_clear(breakdown)
	_clear(metrics_row)
	lbl_breakdown_title.visible = false
	module_card.visible = false
	_set_buttons_enabled(false)


func _on_validation_done(result: Dictionary, generation: int) -> void:
	if generation != _eval_generation:
		return   # resultado de uma avaliação antiga — descarta

	_last_result = result

	var precision := 0.0
	if result.get("ok", false):
		precision = float(result.get("precision", 0.0))
	elif not result.is_empty():
		push_warning("Validação falhou: %s" % result.get("error", ""))

	var num_stars := _stars_for_precision(precision)
	_last_stars = num_stars
	_apply_result_copy(num_stars)

	_fill_score(precision, num_stars)
	_fill_reward(num_stars)
	_fill_breakdown()
	_fill_metrics(precision)
	_fill_module_progress()

	_set_buttons_enabled(true)
	Motion.fade_in(result_card, DS.DUR_BASE, 0.0)
	evaluation_completed.emit(num_stars)


# ---------- BLOCOS DA TELA ----------

func _fill_score(precision: float, num_stars: int) -> void:
	var tone := DS.score_color(num_stars)
	ring.color_fg = tone
	ring.color_text = DS.TEXT
	ring.color_bg = DS.alpha(tone, 0.16)
	ring.value = 0.0
	ring.animate_to(precision)
	_stars.reveal(num_stars)


## XP e ofensiva são creditados aqui — este é o único ponto do app onde o
## usuário efetivamente termina uma execução avaliada.
func _fill_reward(num_stars: int) -> void:
	_clear(reward_row)

	var lesson_id: int = _pending_lesson.lesson_id if _pending_lesson else -1
	var gained: int = 0
	if lesson_id >= 0:
		gained = Global.award_sign_result(lesson_id, _pending_idx, num_stars)
	Global.register_practice(float(_last_result.get("precision", 0.0)))

	if gained > 0:
		var chip := StatChip.create(HSIcon.Name.BOLT, "+%d" % gained, "XP conquistado",
			StatChip.Tone.VIOLET)
		reward_row.add_child(chip)
		chip.animate_to(gained, "")
	else:
		# Sem XP novo o usuário precisa entender POR QUE, senão parece bug.
		var lbl := Label.new()
		lbl.theme_type_variation = &"Caption"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# EXPAND_FILL é obrigatório aqui: um Label com autowrap declara largura
		# mínima de um caractere, e num HBoxContainer ele recebe exatamente
		# isso — o texto descia uma letra por linha, na vertical. Só aparecia
		# quando não havia XP a conceder (nota 0, precisão < 50%), que é o
		# caminho menos testado da tela.
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = "Você já tinha ganho o XP deste sinal, aumente sua nota para ganhar mais." \
			if num_stars > 0 else "Faça o sinal com mais precisão para ganhar XP."
		reward_row.add_child(lbl)


## Uma linha por parâmetro avaliado. É a resposta ao "por quê" da nota.
func _fill_breakdown() -> void:
	_clear(breakdown)

	var details: Dictionary = _last_result.get("details", {}) as Dictionary
	if details.is_empty():
		lbl_breakdown_title.visible = false
		return

	var missing: Array = details.get("_missing_groups", []) as Array

	# Coleta antes de montar: precisamos saber qual é o pior parâmetro para
	# dar a orientação nele e só nele. Com três linhas ruins ao mesmo tempo,
	# a mesma frase de conselho aparecia três vezes.
	var entries: Array[Dictionary] = []
	var worst_pct: float = INF
	for group_key: String in GROUP_LABELS:
		if not details.has(group_key):
			continue
		var data: Dictionary = details[group_key] as Dictionary
		var pct: float = float(data.get("group_similarity_pct", NAN))
		if is_nan(pct):
			# Grupo que a referência não exige — não avaliar é diferente de
			# avaliar mal, e mostrar 0% aqui seria mentira.
			continue
		entries.append({
			"label": String(GROUP_LABELS[group_key]),
			"pct": pct,
			"coverage": float(data.get("detection_coverage", 1.0)),
			"missing": missing.has(group_key),
		})
		worst_pct = minf(worst_pct, pct)

	var rows: int = 0
	var hinted: bool = false
	for e: Dictionary in entries:
		# Só a primeira linha com a pior nota recebe o conselho genérico.
		var is_worst: bool = not hinted and is_equal_approx(float(e["pct"]), worst_pct)
		if is_worst:
			hinted = true
		breakdown.add_child(ScoreRow.create(
			String(e["label"]), float(e["pct"]), float(e["coverage"]),
			bool(e["missing"]), is_worst))
		rows += 1

	# Espelhamento é informação útil e já calculada — sinalizadores canhotos
	# executam o sinal em espelho e o validador aceita as duas execuções.
	# Vive aqui, como nota explicativa, e não como métrica: é uma frase, e
	# frase não cabe num slot dimensionado para número.
	if rows > 0 and bool(_last_result.get("mirrored", false)):
		var note := Label.new()
		note.theme_type_variation = &"Caption"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.text = "Reconhecemos sua execução espelhada (mão dominante invertida), ela vale a mesma nota."
		breakdown.add_child(note)

	lbl_breakdown_title.visible = rows > 0


func _fill_metrics(precision: float) -> void:
	_clear(metrics_row)

	metrics_row.add_child(MetricCard.create(HSIcon.Name.REFRESH,
		str(_attempts), "Tentativas", DS.PRIMARY))

	metrics_row.add_child(MetricCard.create(HSIcon.Name.CLOCK,
		_format_time(_compute_time_seconds(_pending_payload)), "Duração", DS.PRIMARY))

	# Os três slots são sempre numéricos e sempre os mesmos. Antes o terceiro
	# virava a palavra "Espelhado" em corpo 72 quando o validador detectava
	# execução em espelho: o card ficava largo demais, espremia os vizinhos e
	# a fileira inteira desalinhava conforme o resultado.
	metrics_row.add_child(MetricCard.create(HSIcon.Name.TARGET,
		"%d%%" % int(round(precision * 100.0)), "Precisão", DS.ACCENT_INK))


func _fill_module_progress() -> void:
	if _pending_lesson == null:
		module_card.visible = false
		return

	module_card.visible = true
	var total: int = _pending_lesson.sinais.size()
	var done: int = _pending_idx + 1

	lbl_module_name.text = _pending_lesson.nome_exercicio
	lbl_progress_text.text = "%d de %d sinais" % [done, total]
	bar_progress.max_value = float(maxi(total, 1))
	bar_progress.value = float(maxi(done - 1, 0))
	Motion.fill_bar(bar_progress, float(done))

	# O rótulo do botão principal precisa dizer para onde ele leva: o antigo
	# "Próxima lição" aparecia mesmo quando ainda havia sinais no módulo.
	btn_next.text = "Próximo sinal" if done < total else "Concluir lição"


func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _set_buttons_enabled(enabled: bool) -> void:
	btn_next.disabled = not enabled
	btn_retry.disabled = not enabled
	btn_modules.disabled = not enabled


## Retorna o resultado completo do último validate(), pra UI mais detalhada.
func get_last_result() -> Dictionary:
	return _last_result


## Estrelas da última avaliação — usado pelo LessonScreen pra persistir
## o progresso real da lição.
func get_last_stars() -> int:
	return _last_stars


## Título/subtítulo condizentes com o resultado (antes era sempre "Parabéns!").
func _apply_result_copy(num_stars: int) -> void:
	if not bool(_last_result.get("ok", false)):
		lbl_title.text = "Não deu para avaliar"
		lbl_subtitle.text = "A gravação não tinha dados suficientes. Confira se você aparece na câmera e tente de novo."
		return

	# Grupos exigidos pelo gabarito mas nunca detectados no usuário
	# (flag preenchida pelo MotionComparator — ver _missing_groups).
	var details: Dictionary = _last_result.get("details", {}) as Dictionary
	var missing: Array = details.get("_missing_groups", []) as Array
	if missing.has("Mão Esquerda") or missing.has("Mão Direita"):
		lbl_title.text = "Não vimos suas mãos"
		lbl_subtitle.text = "Fique visível na câmera, com as mãos aparecendo, e tente novamente."
		return

	match num_stars:
		3:
			lbl_title.text = "Perfeito!"
			lbl_subtitle.text = "Execução impecável do sinal."
		2:
			lbl_title.text = "Muito bom!"
			lbl_subtitle.text = "Faltou pouco para a nota máxima, veja abaixo o que ajustar."
		1:
			lbl_title.text = "Quase lá"
			lbl_subtitle.text = "Bom começo. O detalhamento abaixo mostra onde melhorar."
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
	if precision >= 0.7:
		return 3
	elif precision >= 0.6:
		return 2
	elif precision >= 0.5:
		return 1
	return 0


func _format_time(total_seconds: int) -> String:
	var m := total_seconds / 60
	var s := total_seconds % 60
	return "%02d:%02d" % [m, s]
