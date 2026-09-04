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


func test_erase_all_data_limpa_progresso_e_estatisticas() -> void:
	g.mark_completed(1, 3)
	g.mark_completed(2, 2)
	g.award_sign_result(1, 0, 3)
	g.register_practice(0.9)

	assert_true(g.erase_all_data(), "grava o estado vazio com sucesso")

	assert_eq(g.count_completed_lessons(), 0)
	assert_false(g.is_completed(1))
	assert_eq(g.get_stars(1), 0)
	assert_eq(g.get_xp(), 0)
	assert_eq(g.get_level(), 1)
	assert_eq(g.get_streak(), 0)
	assert_eq(g.get_practice_count(), 0)
	assert_eq(g.get_mastered_signs(), 0)
	assert_eq(g.get_average_precision(), -1.0, "sem prática, sem média")


## Apagar não pode travar o usuário fora do app: a primeira lição continua
## acessível, como em qualquer catálogo.
func test_erase_all_data_mantem_primeira_licao_liberada() -> void:
	g.mark_completed(1, 3)
	g.erase_all_data()
	assert_true(g.is_unlocked(1, CATALOG))
	assert_false(g.is_unlocked(2, CATALOG), "as seguintes voltam a travar")


func test_erase_all_data_e_idempotente() -> void:
	g.erase_all_data()
	assert_true(g.erase_all_data(), "apagar de novo continua ok")
	assert_eq(g.count_completed_lessons(), 0)


func test_bundled_mediapipe_model_resolves() -> void:
	# O modelo do Holistic é embarcado em res://assets/mediapipe e precisa
	# resolver pelo caminho longo usado pelo HolisticLandmarker — sem isso
	# o app exportado não tem detecção nenhuma.
	var f: FileAccess = g.get_model(
		"holistic_landmarker/holistic_landmarker/float16/latest/holistic_landmarker.task")
	assert_not_null(f, "modelo embarcado deve ser encontrado")
	if f != null:
		assert_gt(f.get_length(), 1_000_000, "arquivo do modelo íntegro")
