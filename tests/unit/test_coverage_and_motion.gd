extends GutTest
## Piso de cobertura de detecção (item 14) e comparação de quantidade de
## movimento (item 15) — os dois comportamentos que substituíram,
## respectivamente, o "tudo ou nada" da detecção e o emparelhamento de
## segmentos por índice.

var c: MotionComparator


func before_each() -> void:
	c = MotionComparator.new()


## Mistura cada quadro com o primeiro: reduz o percurso do gesto sem
## mudar a postura inicial nem a duração.
func _scaled_motion(doc: Dictionary, factor: float) -> Dictionary:
	var frames: Array = doc["frames"] as Array
	var first: Dictionary = frames[0] as Dictionary
	var out: Array = []

	for i in range(frames.size()):
		var f: Dictionary = (frames[i] as Dictionary).duplicate(true)
		f["pose"] = _blend_group(f["pose"] as Array, first["pose"] as Array, factor)
		f["hands"] = _blend_group(f["hands"] as Array, first["hands"] as Array, factor)
		out.append(f)

	var result: Dictionary = doc.duplicate()
	result["frames"] = out
	return result


func _blend_group(current: Array, reference: Array, factor: float) -> Array:
	var out: Array = []
	for i in range(current.size()):
		var entry: Dictionary = (current[i] as Dictionary).duplicate(true)
		if i >= reference.size():
			out.append(entry)
			continue
		var base: Array = (reference[i] as Dictionary)["landmarks"] as Array
		var landmarks: Array = entry["landmarks"] as Array
		for k in range(mini(landmarks.size(), base.size())):
			var lm: Dictionary = landmarks[k] as Dictionary
			var start: Dictionary = base[k] as Dictionary
			for axis: String in ["x", "y", "z"]:
				lm[axis] = float(start[axis]) + \
					(float(lm[axis]) - float(start[axis])) * factor
		out.append(entry)
	return out


## Remove as mãos de parte dos quadros, simulando detecção intermitente.
func _drop_hands(doc: Dictionary, keep_every: int) -> Dictionary:
	var frames: Array = doc["frames"] as Array
	var out: Array = []
	for i in range(frames.size()):
		var f: Dictionary = (frames[i] as Dictionary).duplicate(true)
		if i % keep_every != 0:
			f["hands"] = []
		out.append(f)
	var result: Dictionary = doc.duplicate()
	result["frames"] = out
	return result


# ---------- item 15: quantidade de movimento ----------

func test_half_motion_scores_about_half_on_the_phase_term() -> void:
	var reference := CaptureDocFactory.make_doc(60, 30.0, true, true)
	var timid := _scaled_motion(reference, 0.5)

	var results: Dictionary = c.analyze_similarity(timid, reference)
	var phase: Dictionary = (results["Mão Direita"] as Dictionary)["phase"]
	var phase_sim := float(phase["phase_similarity_pct"])
	gut.p("percurso: usuário=%.4f gabarito=%.4f -> fase=%.1f%%"
		% [float(phase["travel_a"]), float(phase["travel_b"]), phase_sim])

	assert_between(phase_sim, 30.0, 70.0,
		"metade do percurso deve valer aproximadamente metade do termo")


func test_same_motion_saturates_the_phase_term() -> void:
	var doc := CaptureDocFactory.make_doc(60, 30.0, true, true)
	var results: Dictionary = c.analyze_similarity(doc, doc)
	var phase: Dictionary = (results["Mão Direita"] as Dictionary)["phase"]
	assert_almost_eq(float(phase["phase_similarity_pct"]), 100.0, 0.001,
		"percursos iguais = termo cheio")


func test_phase_term_is_frame_rate_independent() -> void:
	# O percurso total não pode depender da taxa de amostragem: a mesma
	# execução vista a 15 fps e a 30 fps deve dar o mesmo termo.
	var reference := CaptureDocFactory.make_doc(60, 30.0, true, true)
	var half_rate := CaptureDocFactory.make_doc(30, 15.0, true, true)

	var results: Dictionary = c.analyze_similarity(half_rate, reference)
	var phase: Dictionary = (results["Mão Direita"] as Dictionary)["phase"]
	gut.p("15fps vs 30fps -> fase=%.1f%%" % float(phase["phase_similarity_pct"]))
	assert_gt(float(phase["phase_similarity_pct"]), 80.0,
		"taxa diferente não pode ser confundida com movimento a menos")


func test_reference_without_motion_does_not_apply_the_term() -> void:
	var still := CaptureDocFactory.make_doc(40, 30.0, false, true)
	var results: Dictionary = c.analyze_similarity(still, still)
	var phase: Dictionary = (results["Mão Direita"] as Dictionary)["phase"]
	assert_true(is_nan(float(phase["phase_similarity_pct"])),
		"gabarito parado: o termo não se aplica, em vez de punir")


# ---------- item 14: piso de cobertura ----------

func test_intermittent_detection_scales_the_group_score() -> void:
	var reference := CaptureDocFactory.make_doc(60, 30.0, true, true)
	# Mão visível em 1 de cada 5 quadros = 20% de cobertura, abaixo dos
	# 30% exigidos -> fator 0.2/0.3 = 0.667.
	var flickering := _drop_hands(reference, 5)

	var results: Dictionary = c.analyze_similarity(flickering, reference)
	var hand: Dictionary = results["Mão Direita"]
	gut.p("cobertura=%.2f fator=%.3f nota=%.1f%%" % [
		float(hand["detection_coverage"]),
		float(hand["coverage_factor"]),
		float(hand["group_similarity_pct"])])

	assert_almost_eq(float(hand["coverage_factor"]), 0.667, 0.05,
		"o fator é proporcional à cobertura que falta")

	var full: Dictionary = c.analyze_similarity(reference, reference)
	assert_lt(float(hand["group_similarity_pct"]),
		float((full["Mão Direita"] as Dictionary)["group_similarity_pct"]),
		"detecção intermitente não pode valer nota cheia")


func test_full_coverage_is_not_penalized() -> void:
	var doc := CaptureDocFactory.make_doc(40, 30.0, true, true)
	var results: Dictionary = c.analyze_similarity(doc, doc)
	var hand: Dictionary = results["Mão Direita"]
	assert_almost_eq(float(hand["coverage_factor"]), 1.0, 0.001,
		"cobertura igual à do gabarito não sofre desconto")


func test_coverage_factor_is_continuous() -> void:
	# A correção não pode recriar o degrau que ela veio corrigir: mais
	# cobertura nunca pode dar nota menor.
	var reference := CaptureDocFactory.make_doc(60, 30.0, true, true)
	var previous := -1.0
	for keep_every: int in [6, 4, 3, 2, 1]:
		var results: Dictionary = c.analyze_similarity(
			_drop_hands(reference, keep_every), reference)
		var factor := float((results["Mão Direita"] as Dictionary)["coverage_factor"])
		assert_gte(factor, previous, "fator deve crescer com a cobertura")
		previous = factor
	assert_almost_eq(previous, 1.0, 0.001, "cobertura total = sem desconto")
