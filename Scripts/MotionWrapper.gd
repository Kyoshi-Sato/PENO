class_name MotionComparatorValidator
extends SignValidator
## Implementação de SignValidator que delega para a classe MotionComparator
## (DTW + análise por osso/palma/direção da mão).

const MotionComparatorScript := preload("res://Scripts/Comparador.gd")

## Pares esquerda/direita dos 33 landmarks de pose do MediaPipe.
## Usado para espelhar uma gravação (sinalizadores canhotos).
const POSE_MIRROR_SWAP := {
	1: 4, 2: 5, 3: 6, 4: 1, 5: 2, 6: 3,
	7: 8, 8: 7, 9: 10, 10: 9,
	11: 12, 12: 11, 13: 14, 14: 13, 15: 16, 16: 15,
	17: 18, 18: 17, 19: 20, 20: 19, 21: 22, 22: 21,
	23: 24, 24: 23, 25: 26, 26: 25, 27: 28, 28: 27,
	29: 30, 30: 29, 31: 32, 32: 31,
}

## Abaixo desta precisão na comparação direta, tentamos também a versão
## espelhada da gravação (canhotos executam sinais em espelho) e ficamos
## com a melhor nota.
const MIRROR_RETRY_THRESHOLD := 0.7


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
	var mirrored := false

	# Sinalizadores canhotos executam o sinal em espelho. Se a nota direta
	# for baixa, comparamos também a versão espelhada e ficamos com a melhor.
	if global_pct / 100.0 < MIRROR_RETRY_THRESHOLD:
		var mirrored_results: Dictionary = comparator.analyze_similarity(
			_mirror_doc(user_doc), ref_doc)
		var mirrored_pct: float = float(mirrored_results.get("_global_similarity_pct", 0.0))
		if mirrored_pct > global_pct:
			results = mirrored_results
			global_pct = mirrored_pct
			mirrored = true

	return {
		"precision": clampf(global_pct / 100.0, 0.0, 1.0),
		"global_similarity_pct": global_pct,
		"details": results,
		"mirrored": mirrored,
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


## Espelha horizontalmente uma gravação: x -> 1-x (coordenadas normalizadas
## de imagem), troca os rótulos Left/Right das mãos e os landmarks pareados
## esquerda/direita da pose. y e z não mudam num espelhamento horizontal.
func _mirror_doc(doc: Dictionary) -> Dictionary:
	var mirrored: Dictionary = doc.duplicate()
	var frames_out: Array = []
	for frame: Variant in doc.get("frames", []) as Array:
		var f: Dictionary = (frame as Dictionary).duplicate()

		var hands_out: Array = []
		for h: Variant in f.get("hands", []) as Array:
			var hand: Dictionary = (h as Dictionary).duplicate()
			var side: String = String(hand.get("handedness", ""))
			hand["handedness"] = "Right" if side == "Left" else "Left"
			hand["landmarks"] = _mirror_landmarks(hand.get("landmarks", []) as Array, false)
			hands_out.append(hand)
		f["hands"] = hands_out

		var pose_out: Array = []
		for p: Variant in f.get("pose", []) as Array:
			var pose_entry: Dictionary = (p as Dictionary).duplicate()
			pose_entry["landmarks"] = _mirror_landmarks(
				pose_entry.get("landmarks", []) as Array, true)
			pose_out.append(pose_entry)
		f["pose"] = pose_out

		frames_out.append(f)
	mirrored["frames"] = frames_out
	return mirrored


## Os landmarks de mão têm a mesma topologia nos dois lados, então basta
## espelhar x; na pose os ids esquerda/direita precisam ser trocados.
func _mirror_landmarks(landmarks: Array, swap_pose_ids: bool) -> Array:
	var out: Array = []
	for lm: Variant in landmarks:
		var d: Dictionary = (lm as Dictionary).duplicate()
		var x: Variant = d.get("x")
		if x is float or x is int:
			d["x"] = 1.0 - float(x)
		if swap_pose_ids:
			var id: int = int(d.get("id", -1))
			d["id"] = int(POSE_MIRROR_SWAP.get(id, id))
		out.append(d)
	return out


func _fail(msg: String) -> Dictionary:
	push_warning("MotionComparatorValidator: %s" % msg)
	return {
		"precision": 0.0,
		"global_similarity_pct": 0.0,
		"details": {},
		"ok": false,
		"error": msg,
	}
