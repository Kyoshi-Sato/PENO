class_name MotionComparatorValidator
extends SignValidator
## Implementação de SignValidator que delega para a classe MotionComparator
## (DTW + análise por osso/palma/direção da mão).

const MotionComparatorScript := preload("res://Scripts/Comparador.gd")


func validate(user_payload: Dictionary, reference: Dictionary) -> Dictionary:
	# Validação de entrada
	if user_payload.is_empty():
		return _fail("user_payload vazio")
	if reference.is_empty():
		return _fail("reference vazia")

	var user_frames: Array = user_payload.get("frames", []) as Array
	var ref_frames: Array = reference.get("frames", []) as Array
	if user_frames.is_empty():
		return _fail("Sem frames do usuário")
	if ref_frames.is_empty():
		return _fail("Sem frames de referência")

	# MotionComparator.analyze_similarity espera os dois dicts no mesmo
	# formato exportado pelo HolisticLandmarker.
	var user_doc := _ensure_doc_shape(user_payload)
	var ref_doc := _ensure_doc_shape(reference)

	var comparator: MotionComparator = MotionComparatorScript.new()
	var results: Dictionary = comparator.analyze_similarity(user_doc, ref_doc)

	var global_pct: float = float(results.get("_global_similarity_pct", 0.0))

	return {
		"precision": clampf(global_pct / 100.0, 0.0, 1.0),
		"global_similarity_pct": global_pct,
		"details": results,
		"ok": true,
		"error": "",
	}


## Garante que o dict tenha video_info válido (MotionComparator usa fps).
func _ensure_doc_shape(payload: Dictionary) -> Dictionary:
	var doc: Dictionary = payload.duplicate()
	var info: Variant = doc.get("video_info", {})
	if not info is Dictionary or (info as Dictionary).is_empty():
		# Fallback: estima fps a partir de timestamps dos frames se possível.
		var frames: Array = doc.get("frames", []) as Array
		var fps := _estimate_fps(frames)
		doc["video_info"] = {
			"fps": fps,
			"total_frames": frames.size(),
			"source": "runtime",
		}
	return doc


func _estimate_fps(frames: Array) -> float:
	if frames.size() < 2:
		return 30.0
	var first: Dictionary = frames[0] as Dictionary
	var last: Dictionary = frames[frames.size() - 1] as Dictionary
	var t0: float = float(first.get("timestamp_ms", 0))
	var t1: float = float(last.get("timestamp_ms", 0))
	var dur_s: float = (t1 - t0) / 1000.0
	if dur_s <= 0.0:
		return 30.0
	return float(frames.size() - 1) / dur_s


func _fail(msg: String) -> Dictionary:
	push_warning("MotionComparatorValidator: %s" % msg)
	return {
		"precision": 0.0,
		"global_similarity_pct": 0.0,
		"details": {},
		"ok": false,
		"error": msg,
	}
