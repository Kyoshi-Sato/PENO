extends GutTest
## Progresso e destravamento de lições (Global), sem tocar o disco.

const StubGlobal := preload("res://tests/helpers/stub_global.gd")

const CATALOG := [
	{"id": 1, "nome": "A"},
	{"id": 2, "nome": "B"},
	{"id": 3, "nome": "C"},
]

var g: Node


func before_each() -> void:
	g = autofree(StubGlobal.new())


func test_first_lesson_always_unlocked() -> void:
	assert_true(g.is_unlocked(1, CATALOG))


func test_second_lesson_locked_until_first_completed() -> void:
	assert_false(g.is_unlocked(2, CATALOG))
	g.mark_completed(1, 2)
	assert_true(g.is_unlocked(2, CATALOG))
	assert_false(g.is_unlocked(3, CATALOG), "3 continua travada até completar a 2")


func test_empty_catalog_unlocks_everything() -> void:
	assert_true(g.is_unlocked(42, []))


func test_unknown_lesson_is_locked() -> void:
	assert_false(g.is_unlocked(99, CATALOG))


func test_stars_are_clamped_and_stored() -> void:
	g.mark_completed(1, 5)
	assert_eq(g.get_stars(1), 3, "clamp em 3")
	assert_true(g.is_completed(1))


func test_mark_completed_keeps_best_stars() -> void:
	g.mark_completed(1, 3)
	g.mark_completed(1, 1)
	assert_eq(g.get_stars(1), 3, "rejogar pior não rebaixa")
	g.mark_completed(1, 2)
	assert_eq(g.get_stars(1), 3)


func test_defaults_for_untouched_lesson() -> void:
	assert_false(g.is_completed(7))
	assert_eq(g.get_stars(7), 0)


func test_reset_progress() -> void:
	g.mark_completed(1, 3)
	g.reset_progress()
	assert_false(g.is_completed(1))


func test_bundled_mediapipe_model_resolves() -> void:
	# O modelo do Holistic é embarcado em res://assets/mediapipe e precisa
	# resolver pelo caminho longo usado pelo HolisticLandmarker — sem isso
	# o app exportado não tem detecção nenhuma.
	var f: FileAccess = g.get_model(
		"holistic_landmarker/holistic_landmarker/float16/latest/holistic_landmarker.task")
	assert_not_null(f, "modelo embarcado deve ser encontrado")
	if f != null:
		assert_gt(f.get_length(), 1_000_000, "arquivo do modelo íntegro")
