class_name MotionComparatorValidator
extends SignValidator
## Implementação de SignValidator que delega para a classe MotionComparator
## (DTW + análise por osso/palma/direção da mão).

const MotionComparatorScript := preload("res://Scripts/Comparador.gd")

## Abaixo desta precisão na comparação direta, tentamos também a versão
## espelhada da gravação (canhotos executam sinais em espelho) e ficamos
## com a melhor nota.
const MIRROR_RETRY_THRESHOLD := 0.7

## Contagens do MediaPipe, usadas para validar o formato do gabarito.
const POSE_LANDMARK_COUNT := 33
const HAND_LANDMARK_COUNT := 21


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

	# Um gabarito fora do formato esperado não pode seguir adiante: o
	# comparador degrada tudo o que não entende para NAN, e o resultado
	# seria uma nota confiantemente errada em vez de um erro.
	var schema_error: String = validate_reference_schema(reference)
	if not schema_error.is_empty():
		return _fail("Gabarito inválido: %s" % schema_error)

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


## Confere se o gabarito tem o formato que o comparador pressupõe.
## Retorna "" se estiver tudo bem, ou a descrição do problema.
##
## O comparador transforma qualquer coisa que não entende em NAN e
## depois exclui NAN da média — então, sem esta checagem, um gabarito
## só-mãos (sem pose) faria a LOCALIZAÇÃO do sinal, que é um parâmetro
## fonológico central da LIBRAS, deixar de ser avaliada silenciosamente.
func validate_reference_schema(reference: Dictionary) -> String:
	var frames: Array = reference.get("frames", []) as Array
	if frames.is_empty():
		return "sem frames"

	var frames_with_pose: int = 0
	var frames_with_hands: int = 0
	for frame: Variant in frames:
		if not frame is Dictionary:
			return "frame que não é um objeto"
		var f: Dictionary = frame as Dictionary

		var pose: Array = f.get("pose", []) as Array
		if not pose.is_empty():
			var pose_landmarks: Array = (pose[0] as Dictionary).get("landmarks", []) as Array
			if pose_landmarks.size() < POSE_LANDMARK_COUNT:
				return "pose com %d landmarks (esperado %d)" % [
					pose_landmarks.size(), POSE_LANDMARK_COUNT]
			frames_with_pose += 1

		var hands: Array = f.get("hands", []) as Array
		for h: Variant in hands:
			var hand: Dictionary = h as Dictionary
			var side: String = String(hand.get("handedness", ""))
			if side != "Left" and side != "Right":
				return "mão com handedness '%s' (esperado Left ou Right)" % side
			var hand_landmarks: Array = hand.get("landmarks", []) as Array
			if hand_landmarks.size() != HAND_LANDMARK_COUNT:
				return "mão com %d landmarks (esperado %d)" % [
					hand_landmarks.size(), HAND_LANDMARK_COUNT]
		if not hands.is_empty():
			frames_with_hands += 1

	if frames_with_pose == 0 and frames_with_hands == 0:
		return "nenhum landmark detectado em nenhum frame"
	if frames_with_pose == 0:
		return "sem dados de pose — a localização do sinal no corpo não pode ser avaliada"

	return ""


## Garante que o dict tenha video_info válido (MotionComparator usa fps).
func _ensure_doc_shape(payload: Dictionary) -> Dictionary:
	var doc: Dictionary = payload.duplicate()
	var frames: Array = doc.get("frames", []) as Array
	var info: Variant = doc.get("video_info", {})

	if not info is Dictionary or (info as Dictionary).is_empty():
		# Fallback: estima fps a partir de timestamps dos frames se possível.
		doc["video_info"] = {
			"fps": _estimate_fps(frames),
			"total_frames": frames.size(),
			"source": "runtime",
		}
		return doc

	# fps zerado ou negativo passava direto e degenerava os pesos de
	# repouso (rest_frames = 0). Recalcula a partir dos timestamps.
	var video_info: Dictionary = (info as Dictionary).duplicate()
	if float(video_info.get("fps", 0.0)) <= 0.0:
		video_info["fps"] = _estimate_fps(frames)
		doc["video_info"] = video_info

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


## Espelha horizontalmente uma gravação (delegado ao utilitário
## compartilhado — o mesmo usado pra canonicalizar capturas de câmera
## frontal na exportação).
func _mirror_doc(doc: Dictionary) -> Dictionary:
	return CaptureMirror.mirror_doc(doc)


func _fail(msg: String) -> Dictionary:
	push_warning("MotionComparatorValidator: %s" % msg)
	return {
		"precision": 0.0,
		"global_similarity_pct": 0.0,
		"details": {},
		"ok": false,
		"error": msg,
	}
