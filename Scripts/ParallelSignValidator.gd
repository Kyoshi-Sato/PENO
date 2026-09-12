class_name ParallelSignValidator
extends SignValidator

## Validador em paralelo (Shadow Mode).
## Executa o validador original (MotionComparatorValidator) intacto E,
## simultaneamente, a nova rede neural de classificação de forma de mão (TCC).
## Permite comparar lado a lado as duas abordagens sem alterar a lógica legada.

const MotionWrapperScript := preload("res://Scripts/MotionWrapper.gd")
const HandShapeClassifierScript := preload("res://Scripts/HandShapeClassifier.gd")
const HandBiomechanicalGuidanceScript := preload("res://Scripts/HandBiomechanicalGuidance.gd")

static var _ref_eval_cache: Dictionary = {}

var legacy_validator: SignValidator


func _init() -> void:
	legacy_validator = MotionWrapperScript.new()


func validate(user_payload: Dictionary, reference: Dictionary) -> Dictionary:
	var user_frames: Array = user_payload.get("frames", []) as Array

	# Trava de proteção: se por anomalia a gravação contiver um número excessivo de frames,
	# subamostra proporcionalmente para no máximo 200 frames para evitar travamento do algoritmo DTW.
	if user_frames.size() > 250:
		var stride: float = float(user_frames.size()) / 200.0
		var downsampled_user_frames: Array = []
		for i in range(200):
			var idx: int = mini(int(round(float(i) * stride)), user_frames.size() - 1)
			downsampled_user_frames.append(user_frames[idx])
		user_frames = downsampled_user_frames
		user_payload["frames"] = user_frames

	# 1. Executa o validador original intocado
	var legacy_result: Dictionary = {}
	if legacy_validator != null:
		legacy_result = legacy_validator.validate(user_payload, reference)
	else:
		legacy_result = {"precision": 0.0, "ok": false, "error": "sem legacy validator"}

	# 2. Executa a IA de forma de mão (TCC)
	var user_classifier: RefCounted = HandShapeClassifierScript.new()

	var ref_frames: Array = reference.get("frames", []) as Array

	# Identifica o nome do sinal da lição / referência
	var sign_name: String = _resolve_sign_name(reference, user_payload)
	var expected_code_by_name: String = HandBiomechanicalGuidanceScript.resolve_kinematic_code(sign_name)

	# --- PASSO A: O MODELO PASSA EM CIMA DO SINAL BASE (COM CACHE INTELIGENTE) ---
	var ref_ai_result: Dictionary = {}
	var target_expected_code: String = expected_code_by_name

	# Se a referência tem um código explícito definido, respeita
	if reference.has("expected_code") and not String(reference["expected_code"]).is_empty():
		target_expected_code = String(reference["expected_code"])

	if not ref_frames.is_empty():
		# Otimização: Cacheia a análise do sinal base para evitar recomputação pesada na CPU móvel
		var cache_key := "%s_%d" % [sign_name, ref_frames.size()]
		if _ref_eval_cache.has(cache_key):
			ref_ai_result = _ref_eval_cache[cache_key]
		else:
			var ref_classifier: RefCounted = HandShapeClassifierScript.new()
			ref_ai_result = ref_classifier.evaluate_recording(ref_frames, target_expected_code)
			_ref_eval_cache[cache_key] = ref_ai_result

		var ref_dom_code: String = String(ref_ai_result.get("dominant_code", ""))
		if not ref_dom_code.is_empty() and ref_dom_code != "0000000000":
			target_expected_code = ref_dom_code
	# Determina os códigos esperados para mão direita e esquerda a partir da análise da base
	var target_right_code: String = target_expected_code
	var target_left_code: String = target_expected_code

	if bool(ref_ai_result.get("both_hands_detected", false)):
		var r_dom: String = String(ref_ai_result.get("right_hand", {}).get("dominant_code", ""))
		var l_dom: String = String(ref_ai_result.get("left_hand", {}).get("dominant_code", ""))
		if not r_dom.is_empty() and r_dom != "0000000000":
			target_right_code = r_dom
		if not l_dom.is_empty() and l_dom != "0000000000":
			target_left_code = l_dom
	elif bool(ref_ai_result.get("has_left", false)) and not bool(ref_ai_result.get("has_right", false)):
		var l_dom: String = String(ref_ai_result.get("left_hand", {}).get("dominant_code", ""))
		if not l_dom.is_empty() and l_dom != "0000000000":
			target_left_code = l_dom
			target_right_code = l_dom
	elif bool(ref_ai_result.get("has_right", false)):
		var r_dom: String = String(ref_ai_result.get("right_hand", {}).get("dominant_code", ""))
		if not r_dom.is_empty() and r_dom != "0000000000":
			target_right_code = r_dom
			target_left_code = r_dom

	# --- PASSO B: O MODELO PASSA EM CIMA DO SINAL DO USUÁRIO ---
	var ai_result: Dictionary = {}
	if not user_frames.is_empty():
		ai_result = user_classifier.evaluate_recording(user_frames, target_right_code, target_left_code)
	else:
		ai_result = {
			"ok": false,
			"hand_precision": 0.0,
			"dominant_code": "0000000000",
			"expected_code": target_expected_code,
			"dominant_letter": "",
			"detected_frames": 0,
			"total_frames": 0,
			"avg_confidence": 0.0,
			"finger_status": {
				"thumb": "MISSING",
				"index": "MISSING",
				"middle": "MISSING",
				"ring": "MISSING",
				"pinky": "MISSING",
				"spread": "MISSING"
			},
			"hints": ["Nenhuma mão detectada na gravação. Posicione sua mão visível em frente à câmera."]
		}

	# Inclui metadados do sinal base analisado no resultado da IA
	ai_result["reference_ai"] = ref_ai_result
	ai_result["sign_name"] = sign_name
	ai_result["base_letter"] = String(ref_ai_result.get("dominant_letter", sign_name))
	ai_result["base_code"] = target_expected_code

	var ai_precision: float = float(ai_result.get("hand_precision", 0.0))
	var det_frames: int = int(ai_result.get("detected_frames", 0))
	var is_ok: bool = bool(ai_result.get("ok", true)) and det_frames > 0

	# 3. Monta o detalhamento (details) para a UI de feedback
	var details: Dictionary = {}
	var both_hands: bool = bool(ai_result.get("both_hands_detected", false))
	var has_right: bool = bool(ai_result.get("has_right", false))
	var has_left: bool = bool(ai_result.get("has_left", false))

	if det_frames == 0:
		details["_missing_groups"] = ["Mão Direita", "Mão Esquerda"]
	elif both_hands:
		var r_dict: Dictionary = ai_result.get("right_hand", {}) as Dictionary
		var l_dict: Dictionary = ai_result.get("left_hand", {}) as Dictionary
		var r_prec: float = float(r_dict.get("hand_precision", 0.0)) * 100.0
		var l_prec: float = float(l_dict.get("hand_precision", 0.0)) * 100.0
		var r_det: int = int(r_dict.get("detected_frames", 0))
		var l_det: int = int(l_dict.get("detected_frames", 0))
		var r_tot: int = maxi(1, int(r_dict.get("total_frames", 1)))
		var l_tot: int = maxi(1, int(l_dict.get("total_frames", 1)))
		details["Mão Direita"] = {
			"group_similarity_pct": r_prec,
			"detection_coverage": float(r_det) / float(r_tot),
		}
		details["Mão Esquerda"] = {
			"group_similarity_pct": l_prec,
			"detection_coverage": float(l_det) / float(l_tot),
		}
	elif has_left and not has_right:
		var l_dict: Dictionary = ai_result.get("left_hand", {}) as Dictionary
		var l_prec: float = float(l_dict.get("hand_precision", ai_precision)) * 100.0
		var l_det: int = int(l_dict.get("detected_frames", det_frames))
		var l_tot: int = maxi(1, int(l_dict.get("total_frames", ai_result.get("total_frames", 1))))
		details["Mão Esquerda"] = {
			"group_similarity_pct": l_prec,
			"detection_coverage": float(l_det) / float(l_tot),
		}
	elif has_right:
		var r_dict: Dictionary = ai_result.get("right_hand", {}) as Dictionary
		var r_prec: float = float(r_dict.get("hand_precision", ai_precision)) * 100.0
		var r_det: int = int(r_dict.get("detected_frames", det_frames))
		var r_tot: int = maxi(1, int(r_dict.get("total_frames", ai_result.get("total_frames", 1))))
		details["Mão Direita"] = {
			"group_similarity_pct": r_prec,
			"detection_coverage": float(r_det) / float(r_tot),
		}

	# Preserva o diagnóstico de posicionamento corporal se disponível no legado
	if legacy_result.has("details") and legacy_result["details"] is Dictionary:
		var leg_det: Dictionary = legacy_result["details"] as Dictionary
		if leg_det.has("Pose (corpo)"):
			details["Pose (corpo)"] = leg_det["Pose (corpo)"]

	# 4. Cálculo da Precisão Ponderada:
	# 70% Forma da Mão (Rede Neural IA) + 30% Movimento e Posição Corporal (Pose / DTW)
	var motion_precision: float = float(legacy_result.get("precision", 0.0))
	var legacy_ok: bool = bool(legacy_result.get("ok", false))

	var final_precision: float = 0.0
	var overall_ok: bool = false
	var err_msg: String = ""

	if det_frames == 0:
		# REGRA FUNDAMENTAL: Sem detecção de mãos, o sinal de Libras NÃO pode ser validado nem pontuado
		final_precision = 0.0
		overall_ok = false
		err_msg = "Nenhuma mão detectada na gravação. Posicione sua mão visível em frente à câmera."
	elif is_ok and legacy_ok:
		final_precision = (ai_precision * 0.70) + (motion_precision * 0.30)
		overall_ok = true
	elif is_ok:
		# Se apenas a forma da mão foi detectada (ex.: captura focada na mão sem landmarks de pose)
		final_precision = ai_precision
		overall_ok = true
	elif legacy_ok:
		# Mão foi detectada mas forma divergiu do gabarito: pontua apenas a fração de movimento corporal
		final_precision = motion_precision * 0.30
		overall_ok = false
		err_msg = "Forma da mão incorreta para o sinal esperado."
	else:
		final_precision = 0.0
		overall_ok = false
		err_msg = "Não foi possível validar o sinal na gravação."

	final_precision = clampf(final_precision, 0.0, 1.0)

	ai_result["combined_precision"] = final_precision
	ai_result["hand_shape_weight"] = 0.70
	ai_result["motion_position_weight"] = 0.30
	ai_result["motion_precision"] = motion_precision

	# 5. Retorna o contrato oficial alimentado pela média ponderada + telemetria comparativa
	return {
		# Campos oficiais consumidos por FeedbackState, estrelas, anel e progressão
		"precision": final_precision,
		"global_similarity_pct": final_precision * 100.0,
		"details": details,
		"mirrored": bool(legacy_result.get("mirrored", false)) or (has_left and not has_right),
		"ok": overall_ok,
		"error": err_msg if not overall_ok else "",

		# Carga completa para diagnóstico e telemetria
		"has_ai": true,
		"legacy_result": legacy_result,
		"ai_result": ai_result
	}


func _resolve_sign_name(reference: Dictionary, user_payload: Dictionary) -> String:
	if reference.has("nome_sinal") and not String(reference["nome_sinal"]).is_empty():
		return String(reference["nome_sinal"])
	if reference.has("name") and not String(reference["name"]).is_empty():
		return String(reference["name"])
	if user_payload.has("nome_sinal") and not String(user_payload["nome_sinal"]).is_empty():
		return String(user_payload["nome_sinal"])
	if user_payload.has("sign_id") and not String(user_payload["sign_id"]).is_empty():
		return String(user_payload["sign_id"])
	return ""
