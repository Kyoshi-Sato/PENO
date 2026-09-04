extends GutTest
## XP, nível e ofensiva (Global), sem tocar o disco nem o relógio do sistema.

const StubGlobal := preload("res://tests/helpers/stub_global.gd")

var g: Node


func before_each() -> void:
	g = autofree(StubGlobal.new())


# ---------- XP ----------

func test_starts_zeroed() -> void:
	assert_eq(g.get_xp(), 0)
	assert_eq(g.get_level(), 1)
	assert_eq(g.get_streak(), 0)
	assert_eq(g.get_practice_count(), 0)


func test_award_pays_stars_times_rate() -> void:
	assert_eq(g.award_sign_result(1, 0, 3), 3 * g.XP_PER_STAR)
	assert_eq(g.get_xp(), 3 * g.XP_PER_STAR)


func test_award_pays_only_the_improvement() -> void:
	g.award_sign_result(1, 0, 1)
	var second: int = g.award_sign_result(1, 0, 3)
	assert_eq(second, 2 * g.XP_PER_STAR, "paga só a diferença de 1 para 3 estrelas")
	assert_eq(g.get_xp(), 3 * g.XP_PER_STAR, "total equivale a ter tirado 3 de primeira")


func test_repeating_the_same_grade_pays_nothing() -> void:
	g.award_sign_result(1, 0, 2)
	assert_eq(g.award_sign_result(1, 0, 2), 0, "sem melhora, sem XP")
	assert_eq(g.award_sign_result(1, 0, 1), 0, "nota pior também não paga")
	assert_eq(g.get_xp(), 2 * g.XP_PER_STAR)


func test_signs_are_tracked_independently() -> void:
	g.award_sign_result(1, 0, 3)
	g.award_sign_result(1, 1, 3)
	g.award_sign_result(2, 0, 3)
	assert_eq(g.get_xp(), 9 * g.XP_PER_STAR)
	assert_eq(g.get_mastered_signs(), 3)


func test_mastered_counts_only_three_stars() -> void:
	g.award_sign_result(1, 0, 2)
	g.award_sign_result(1, 1, 3)
	assert_eq(g.get_mastered_signs(), 1)


# ---------- NÍVEL ----------

func test_level_advances_every_xp_per_level() -> void:
	assert_eq(g.get_level(), 1)
	for i in range(g.XP_PER_LEVEL / g.XP_PER_STAR):
		g.award_sign_result(1, i, 1)
	assert_eq(g.get_xp(), g.XP_PER_LEVEL)
	assert_eq(g.get_level(), 2)
	assert_eq(g.get_xp_into_level(), 0)
	assert_almost_eq(g.get_level_progress(), 0.0, 0.001)


func test_level_progress_is_a_fraction_of_the_current_level() -> void:
	g.award_sign_result(1, 0, 3)   # 60 XP de 500
	assert_eq(g.get_level(), 1)
	assert_eq(g.get_xp_into_level(), 3 * g.XP_PER_STAR)
	assert_almost_eq(g.get_level_progress(),
		float(3 * g.XP_PER_STAR) / float(g.XP_PER_LEVEL), 0.001)


# ---------- OFENSIVA ----------

func test_streak_starts_at_one() -> void:
	var s: Dictionary = g._stats()
	g._touch_streak(s, "2026-09-01")
	assert_eq(int(s["streak"]), 1)


func test_consecutive_days_increment() -> void:
	var s: Dictionary = g._stats()
	g._touch_streak(s, "2026-09-01")
	g._touch_streak(s, "2026-09-02")
	g._touch_streak(s, "2026-09-03")
	assert_eq(int(s["streak"]), 3)
	assert_eq(int(s["best_streak"]), 3)


func test_same_day_does_not_increment() -> void:
	var s: Dictionary = g._stats()
	g._touch_streak(s, "2026-09-01")
	g._touch_streak(s, "2026-09-01")
	assert_eq(int(s["streak"]), 1, "praticar duas vezes no mesmo dia conta uma")


func test_gap_resets_streak_but_keeps_best() -> void:
	var s: Dictionary = g._stats()
	g._touch_streak(s, "2026-09-01")
	g._touch_streak(s, "2026-09-02")
	g._touch_streak(s, "2026-09-05")   # pulou dois dias
	assert_eq(int(s["streak"]), 1, "sequência quebrada recomeça")
	assert_eq(int(s["best_streak"]), 2, "o recorde permanece")


func test_streak_crosses_month_boundary() -> void:
	var s: Dictionary = g._stats()
	g._touch_streak(s, "2026-08-31")
	g._touch_streak(s, "2026-09-01")
	assert_eq(int(s["streak"]), 2, "31/08 -> 01/09 são dias consecutivos")


# ---------- PRECISÃO MÉDIA ----------

func test_average_precision_is_negative_before_any_practice() -> void:
	assert_lt(g.get_average_precision(), 0.0,
		"sem tentativa, a UI precisa poder esconder o dado em vez de mostrar 0%")


func test_average_precision_averages_attempts() -> void:
	g.register_practice(1.0)
	g.register_practice(0.5)
	assert_almost_eq(g.get_average_precision(), 0.75, 0.001)
	assert_eq(g.get_practice_count(), 2)


func test_precision_is_clamped() -> void:
	g.register_practice(5.0)
	assert_almost_eq(g.get_average_precision(), 1.0, 0.001)


# ---------- CONVIVÊNCIA COM O PROGRESSO DE LIÇÕES ----------

func test_stats_key_does_not_leak_into_lesson_progress() -> void:
	# As estatísticas moram dentro do mesmo dicionário do progresso, sob uma
	# chave reservada. Ela não pode ser confundida com uma lição concluída.
	g.award_sign_result(1, 0, 3)
	g.mark_completed(1, 3)
	g.mark_completed(2, 2)
	assert_eq(g.count_completed_lessons(), 2, "só as lições contam")
	assert_false(g.is_completed(0))


func test_reset_clears_xp_and_streak() -> void:
	g.award_sign_result(1, 0, 3)
	g.register_practice(0.9)
	g.reset_progress()
	assert_eq(g.get_xp(), 0)
	assert_eq(g.get_practice_count(), 0)
	assert_lt(g.get_average_precision(), 0.0)
