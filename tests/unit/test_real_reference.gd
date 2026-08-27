extends GutTest
## Testes sobre um gabarito REAL da API (sinal "Abacaxi", 63 quadros a
## 12 fps, mão direita articulada em 39 deles).
##
## A fábrica sintética translada a mão como um bloco rígido, então as
## direções dos ossos dos dedos quase não variam — ela subestima tanto o
## problema do alinhamento por índice quanto o ganho do DTW. Aqui a
## articulação é de verdade, e os números servem para a tese.

const FIXTURE := "res://tests/fixtures/ref_abacaxi.json"

var reference: Dictionary


func before_all() -> void:
	var file := FileAccess.open(FIXTURE, FileAccess.READ)
	assert_not_null(file, "fixture do gabarito real deve existir")
	reference = JSON.parse_string(file.get_as_text()) as Dictionary


func _score(user: Dictionary, use_dtw: bool = true) -> float:
	var comparator := MotionComparator.new()
	comparator.enable_dtw_alignment = use_dtw
	return float(comparator.analyze_similarity(user, reference)["_global_similarity_pct"])


## Adia a execução repetindo o quadro de repouso no início.
func _delayed(doc: Dictionary, pad_frames: int) -> Dictionary:
	var frames: Array = doc["frames"] as Array
	var fps: float = float((doc["video_info"] as Dictionary)["fps"])
	var step_ms: float = 1000.0 / fps
	var out: Array = []
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
	result["video_info"] = { "fps": fps, "total_frames": out.size(), "source": "atrasado" }
	return result


## Reamostra para uma taxa menor (simula a captura do celular).
func _resampled(doc: Dictionary, keep_every: int, new_fps: float) -> Dictionary:
	var frames: Array = doc["frames"] as Array
	var out: Array = []
	var step_ms: float = 1000.0 / new_fps
	for i in range(frames.size()):
		if i % keep_every != 0:
			continue
		var f: Dictionary = (frames[i] as Dictionary).duplicate(true)
		f["frame"] = out.size()
		f["timestamp_ms"] = int(round(float(out.size()) * step_ms))
		out.append(f)

	var result: Dictionary = doc.duplicate()
	result["frames"] = out
	result["video_info"] = { "fps": new_fps, "total_frames": out.size(), "source": "reamostrado" }
	return result


func test_reference_compared_with_itself_is_near_perfect() -> void:
	var score := _score(reference)
	gut.p("gabarito real x ele mesmo: %.2f%%" % score)
	assert_gt(score, 95.0, "o gabarito comparado consigo mesmo deve saturar")


func test_late_execution_recovered_on_real_data() -> void:
	# 0.5 s de atraso = 6 quadros a 12 fps. É a latência normal de reação
	# ao "Vai!", e a janela de captura é curta.
	var late := _delayed(reference, 6)

	var with_dtw := _score(late, true)
	var by_index := _score(late, false)
	gut.p("ATRASO 0.5s (real): índice=%.2f%%  DTW=%.2f%%  (+%.2f pontos)"
		% [by_index, with_dtw, with_dtw - by_index])

	assert_gt(with_dtw, by_index + 5.0,
		"em dados articulados o alinhamento precisa recuperar o atraso")
	assert_gt(with_dtw, 90.0, "execução correta, só atrasada, não pode ser reprovada")


func test_slower_capture_recovered_on_real_data() -> void:
	# Metade dos quadros: mesma execução vista a ~6 fps contra 12 fps.
	var slow := _resampled(reference, 2, 6.0)

	var with_dtw := _score(slow, true)
	var by_index := _score(slow, false)
	gut.p("TAXA DIFERENTE (real): índice=%.2f%%  DTW=%.2f%%  (+%.2f pontos)"
		% [by_index, with_dtw, with_dtw - by_index])

	assert_gt(with_dtw, by_index)
	assert_gt(with_dtw, 85.0)


func test_regression_pin_on_real_reference() -> void:
	# Pin sobre dados reais: qualquer mudança no comparador aparece aqui.
	var late := _delayed(reference, 6)
	var score := _score(late)
	gut.p("PIN real (atraso 6 quadros) = %.4f" % score)
	assert_almost_eq(score, 99.9828, 0.05)
