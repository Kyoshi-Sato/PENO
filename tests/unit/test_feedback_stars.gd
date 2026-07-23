extends GutTest
## Fronteiras do mapeamento precisão → estrelas e formatação de tempo.

var fb: FeedbackState


func before_each() -> void:
	fb = autofree(FeedbackState.new())


func test_star_boundaries() -> void:
	assert_eq(fb._stars_for_precision(1.0), 3)
	assert_eq(fb._stars_for_precision(0.9), 3, "0.9 inclusivo")
	assert_eq(fb._stars_for_precision(0.899), 2)
	assert_eq(fb._stars_for_precision(0.7), 2, "0.7 inclusivo")
	assert_eq(fb._stars_for_precision(0.699), 1)
	assert_eq(fb._stars_for_precision(0.5), 1, "0.5 inclusivo")
	assert_eq(fb._stars_for_precision(0.499), 0)
	assert_eq(fb._stars_for_precision(0.0), 0)


func test_format_time() -> void:
	assert_eq(fb._format_time(0), "00:00")
	assert_eq(fb._format_time(75), "01:15")
	assert_eq(fb._format_time(600), "10:00")
