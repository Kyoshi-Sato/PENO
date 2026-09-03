extends GutTest
## Alinhamento temporal por DTW (banda de Sakoe-Chiba + caminho ótimo).
##
## Os testes de ablação comparam o mesmo par de gravações com e sem
## alinhamento — é a medida do que o DTW acrescenta, e o número que a
## tese precisa reportar.

var c: MotionComparator


func before_each() -> void:
	c = MotionComparator.new()


# ---------- propriedades do caminho ----------

func _simple_path(n_a: int, n_b: int) -> Array[Vector2i]:
	var doc_a := CaptureDocFactory.make_doc(n_a, 30.0, true, true)
	var doc_b := CaptureDocFactory.make_doc(n_b, 30.0, true, true)
	var bones: Array[MotionComparator.Bone] = c.HAND_BONES_RIGHT
	var series_a := c.extract_bone_vectors_per_frame(doc_a["frames"], bones, "hand_right")
	var series_b := c.extract_bone_vectors_per_frame(doc_b["frames"], bones, "hand_right")
	return c.compute_alignment_path(series_a, series_b, bones, n_a, n_b)


func test_path_spans_both_sequences() -> void:
	var path := _simple_path(40, 30)
	assert_gt(path.size(), 0, "deve existir caminho")
	assert_eq(path[0], Vector2i(0, 0), "começa no primeiro par")
	assert_eq(path[path.size() - 1], Vector2i(39, 29), "termina no último par")


func test_path_is_monotonic_and_continuous() -> void:
	var path := _simple_path(40, 30)
	for k in range(1, path.size()):
		var step: Vector2i = path[k] - path[k - 1]
		assert_between(step.x, 0, 1, "passo em A é 0 ou 1")
		assert_between(step.y, 0, 1, "passo em B é 0 ou 1")
		assert_gt(step.x + step.y, 0, "o caminho não pode ficar parado")


func test_identical_sequences_align_on_the_diagonal() -> void:
	var path := _simple_path(30, 30)
	for step: Vector2i in path:
		assert_eq(step.x, step.y, "sequências idênticas alinham na diagonal")


func test_path_stays_inside_the_band() -> void:
	# Nenhum par pode se afastar da diagonal mais que o raio da banda.
	var n_a := 60
	var n_b := 40
	var path := _simple_path(n_a, n_b)
	var radius: int = maxi(
		int(ceil(c.DTW_BAND_FRACTION * float(maxi(n_a, n_b)))),
		absi(n_a - n_b) + 1)
	for step: Vector2i in path:
		var center: float = float(step.x) * float(n_b - 1) / float(n_a - 1)
		assert_lte(absf(float(step.y) - center), float(radius) + 1.0,
			"par (%d,%d) fora da banda" % [step.x, step.y])


func test_empty_inputs_return_empty_path() -> void:
	var bones: Array[MotionComparator.Bone] = c.HAND_BONES_RIGHT
	assert_eq(c.compute_alignment_path({}, {}, bones, 0, 0).size(), 0)


func test_identity_path_is_the_fallback() -> void:
	var path := c.identity_path(5, 3)
	assert_eq(path.size(), 3)
	assert_eq(path[2], Vector2i(2, 2))


# ---------- o que o alinhamento conserta ----------

## Adia a execução: repete o primeiro quadro (postura de repouso) no
## início, como um usuário que reage tarde ao "Vai!".
func _delayed(doc: Dictionary, pad_frames: int, fps: float) -> Dictionary:
	var frames: Array = doc["frames"] as Array
	var out: Array = []
	var step_ms: float = 1000.0 / fps
	for i in range(pad_frames):
		var rest: Dictionary = (frames[0] as Dictionary).duplicate(true)
		rest["frame"] = i
		rest["timestamp_ms"] = int(round(float(i) * step_ms))
		out.append(rest)
	for i in range(frames.size()):
		var f: Dictionary = (frames[i] as Dictionary).duplicate(true)
		f["frame"] = pad_frames + i
		f["timestamp_ms"] = int(round(float(pad_frames + i) * step_ms))
		out.append(f)

	var result: Dictionary = doc.duplicate()
	result["frames"] = out
	result["video_info"] = {
		"fps": fps, "total_frames": out.size(), "source": "delayed",
	}
	return result


func _score(user: Dictionary, reference: Dictionary, use_dtw: bool) -> float:
	var comparator := MotionComparator.new()
	comparator.enable_dtw_alignment = use_dtw
	return float(comparator.analyze_similarity(user, reference)["_global_similarity_pct"])


func test_late_start_is_recovered_by_alignment() -> void:
	# Mesmo gesto, começando 0.5 s depois (15 quadros a 30 fps).
	var reference := CaptureDocFactory.make_doc(60, 30.0, true, true)
	var late := _delayed(reference, 15, 30.0)

	var with_dtw := _score(late, reference, true)
	var by_index := _score(late, reference, false)
	gut.p("execução atrasada 0.5s: índice=%.2f%%  DTW=%.2f%%  (+%.2f)"
		% [by_index, with_dtw, with_dtw - by_index])

	# Limiar modesto de propósito: nesta fábrica a mão translada como um
	# bloco rígido, então as direções dos ossos dos dedos quase não mudam
	# e o alinhamento tem pouco a corrigir. A medida honesta do ganho está
	# em test_real_reference.gd, com articulação de verdade (+16.8 pontos).
	assert_gt(with_dtw, by_index + 2.0,
		"o alinhamento tem que recuperar parte do atraso")
	assert_gt(with_dtw, 90.0, "gesto correto, só atrasado, deve pontuar alto")


func test_different_frame_rates_still_match() -> void:
	# O celular grava a ~12 fps e o gabarito a 30: a mesma execução tem
	# comprimentos bem diferentes.
	var reference := CaptureDocFactory.make_doc(60, 30.0, true, true)
	var slow_capture := CaptureDocFactory.make_doc(24, 12.0, true, true)

	var with_dtw := _score(slow_capture, reference, true)
	var by_index := _score(slow_capture, reference, false)
	gut.p("12fps vs 30fps: índice=%.2f%%  DTW=%.2f%%  (+%.2f)"
		% [by_index, with_dtw, with_dtw - by_index])

	assert_gt(with_dtw, by_index,
		"com taxas diferentes o índice compara instantes diferentes")
	assert_gt(with_dtw, 85.0)


func test_alignment_does_not_rescue_a_wrong_gesture() -> void:
	# Salvaguarda contra o risco do DTW: ele não pode fazer um gesto
	# errado (ou ausente) passar por certo à força de deformar o tempo.
	var reference := CaptureDocFactory.make_doc(60, 30.0, true, true)
	var motionless := CaptureDocFactory.make_doc(60, 30.0, false, false)

	var score := _score(motionless, reference, true)
	gut.p("usuário parado, com DTW: %.2f%%" % score)
	assert_lt(score, 35.0, "alinhar não pode inventar semelhança")
