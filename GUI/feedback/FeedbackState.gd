class_name FeedbackState
extends Control

## Estado de feedback. Recebe o JSON capturado, compara com os JSONs de validação
## da lição, exibe pontuação ao usuário e atualiza os stats do jogador.

signal retry_requested
signal next_lesson_requested
signal stats_updated(xp_gained: int, accuracy: float)

@onready var lbl_title: Label = $Panel/VBoxContainer/Title
@onready var lbl_score: Label = $Panel/VBoxContainer/Score
@onready var lbl_message: Label = $Panel/VBoxContainer/Message
@onready var progress_accuracy: ProgressBar = $Panel/VBoxContainer/Accuracy
@onready var btn_retry: Button = $Panel/VBoxContainer/Buttons/Retry
@onready var btn_next: Button = $Panel/VBoxContainer/Buttons/Next

## Limite mínimo (0..1) para considerar acerto.
@export var pass_threshold: float = 0.7

var current_lesson: Lesson
var last_capture: Dictionary = {}
var last_accuracy: float = 0.0


func _ready() -> void:
	btn_retry.pressed.connect(func() -> void: retry_requested.emit())
	btn_next.pressed.connect(func() -> void: next_lesson_requested.emit())


func evaluate(lesson: Lesson, capture: Dictionary) -> void:
	current_lesson = lesson
	last_capture = capture
	lbl_title.text = "Resultado: %s" % lesson.lesson_name

	var accuracy := _compare_with_validation(lesson, capture)
	last_accuracy = accuracy
	progress_accuracy.value = accuracy * 100.0
	lbl_score.text = "%d%%" % int(accuracy * 100.0)

	var passed := accuracy >= pass_threshold
	if passed:
		lbl_message.text = "Mandou bem! Gesto reconhecido."
		var xp := lesson.reward_xp
		_apply_player_stats(xp, accuracy)
		stats_updated.emit(xp, accuracy)
	else:
		lbl_message.text = "Quase lá. Tente novamente."
		stats_updated.emit(0, accuracy)


## Stub de comparação. Substitua pela sua lógica real (DTW, cosseno entre
## landmarks, etc). Recebe a lição (com os JSONs de referência) e o
## dicionário capturado pelo RecordingState.
func _compare_with_validation(lesson: Lesson, capture: Dictionary) -> float:
	if lesson == null or lesson.validation_jsons.is_empty():
		return 0.0
	if capture.is_empty() or not capture.has("frames"):
		return 0.0

	var best_score := 0.0
	for json_path in lesson.validation_jsons:
		var reference := _load_json(json_path)
		if reference.is_empty():
			continue
		var score := _score_single(reference, capture)
		best_score = max(best_score, score)
	return best_score


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("Arquivo de validação não encontrado: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}


## TODO: implementar comparação real entre referência e captura.
## Por hora retorna um valor simulado para permitir testar o fluxo.
func _score_single(_reference: Dictionary, _capture: Dictionary) -> float:
	return randf_range(0.5, 1.0)


## Aplica os stats no Global / sistema de save do jogador.
## Adapte para a sua arquitetura real (autoload, signal bus, etc).
func _apply_player_stats(xp_gained: int, accuracy: float) -> void:
	if Engine.has_singleton("Global"):
		var global := Engine.get_singleton("Global")
		if global.has_method("add_player_xp"):
			global.add_player_xp(xp_gained)
		if global.has_method("register_lesson_attempt"):
			global.register_lesson_attempt(current_lesson.id, accuracy)
