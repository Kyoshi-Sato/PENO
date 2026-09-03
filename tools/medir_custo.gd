extends SceneTree
## Mede o custo de analyze_similarity com tamanhos realistas de captura,
## e o quanto cada etapa do pipeline acrescenta.
##
## Uso: godot --headless -s tools/medir_custo.gd

const REFERENCE_FIXTURE := "res://tests/fixtures/ref_abacaxi.json"


func _load_reference() -> Dictionary:
	var file := FileAccess.open(REFERENCE_FIXTURE, FileAccess.READ)
	if file == null:
		push_error("fixture não encontrado")
		return {}
	return JSON.parse_string(file.get_as_text()) as Dictionary


## Estica o gabarito para simular uma captura mais longa e em taxa maior.
func _stretch(doc: Dictionary, repeats: int, fps: float) -> Dictionary:
	var frames: Array = doc["frames"] as Array
	var out: Array = []
	var step_ms: float = 1000.0 / fps
	for r in range(repeats):
		for f: Variant in frames:
			var copy: Dictionary = (f as Dictionary).duplicate(true)
			copy["frame"] = out.size()
			copy["timestamp_ms"] = int(round(float(out.size()) * step_ms))
			out.append(copy)
	var result: Dictionary = doc.duplicate()
	result["frames"] = out
	result["video_info"] = { "fps": fps, "total_frames": out.size(), "source": "esticado" }
	return result


func _time_ms(user: Dictionary, reference: Dictionary,
		smoothing: bool, normalization: bool, dtw: bool) -> float:
	var comparator := MotionComparator.new()
	comparator.enable_smoothing = smoothing
	comparator.enable_body_normalization = normalization
	comparator.enable_dtw_alignment = dtw
	var started := Time.get_ticks_usec()
	comparator.analyze_similarity(user, reference)
	return float(Time.get_ticks_usec() - started) / 1000.0


func _init() -> void:
	var reference := _load_reference()
	if reference.is_empty():
		quit(1)
		return

	print("gabarito: %d quadros\n" % (reference["frames"] as Array).size())

	for repeats: int in [1, 2, 4]:
		var user := _stretch(reference, repeats, 25.0)
		var n := (user["frames"] as Array).size()
		var full := _time_ms(user, reference, true, true, true)
		var no_dtw := _time_ms(user, reference, true, true, false)
		var raw := _time_ms(user, reference, false, false, false)
		print("captura de %3d quadros (%4.1f s a 25 fps):" % [n, float(n) / 25.0])
		print("    pipeline completo      %7.1f ms" % full)
		print("    sem DTW                %7.1f ms  (alinhamento custa %.1f ms)"
			% [no_dtw, full - no_dtw])
		print("    sem filtro/normalização %6.1f ms  (pré-processo custa %.1f ms)"
			% [raw, no_dtw - raw])
	quit()
