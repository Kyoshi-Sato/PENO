class_name ParallelSignValidator
extends SignValidator

## Validador em paralelo (Shadow Mode).
## Executa o validador original (MotionComparatorValidator) intacto E,
## simultaneamente, a nova rede neural de classificação de forma de mão (TCC).
## Permite comparar lado a lado as duas abordagens sem alterar a lógica legada.

const MotionWrapperScript := preload("res://Scripts/MotionWrapper.gd")
const HandShapeClassifierScript := preload("res://Scripts/HandShapeClassifier.gd")
const HandBiomechanicalGuidanceScript := preload("res://Scripts/HandBiomechanicalGuidance.gd")

var legacy_validator: SignValidator


func _init() -> void:
	legacy_validator = MotionWrapperScript.new()


func validate(user_payload: Dictionary, reference: Dictionary) -> Dictionary:
	# 1. Executa o validador original intocado
	var legacy_result: Dictionary = {}
	if legacy_validator != null:
		legacy_result = legacy_validator.validate(user_payload, reference)
	else:
		legacy_result = {"precision": 0.0, "ok": false, "error": "sem legacy validator"}

	# 2. Executa a nova IA de forma de mão (TCC)
	# Instâncias independentes para garantir que o estado (EMA, histórico de mediana, timestamp)
	# da referência não se misture com o do usuário nem entre tentativas.
	var ref_classifier: RefCounted = HandShapeClassifierScript.new()
	var user_classifier: RefCounted = HandShapeClassifierScript.new()

	var ref_frames: Array = reference.get("frames", []) as Array
	var user_frames: Array = user_payload.get("frames", []) as Array

	# Identifica o nome do sinal da lição / referência
	var sign_name: String = _resolve_sign_name(reference, user_payload)
	var expected_code_by_name: String = HandBiomechanicalGuidanceScript.resolve_kinematic_code(sign_name)

	# --- PASSO A: O MODELO PASSA EM CIMA DO SINAL BASE (REFERÊNCIA) ---
	var ref_ai_result: Dictionary = {}
	var target_expected_code: String = expected_code_by_name

	# Se a referência tem um código explícito definido, respeita
	if reference.has("expected_code") and not String(reference["expected_code"]).is_empty():
		target_expected_code = String(reference["expected_code"])

	if not ref_frames.is_empty():
		# O modelo neural processa todo o sinal base para extrair a forma dominante real
		ref_ai_result = ref_classifier.evaluate_recording(ref_frames, target_expected_code)
		var ref_dom_code: String = String(ref_ai_result.get("dominant_code", ""))
		# Se a rede detectou mão na referência com código válido, adota o código inferido
		# do sinal base em exibição como o gabarito dinâmico
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
			"finger_status": {},
			"hints": ["Nenhum frame com mão detectada"]
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
	else:
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

	# 4. Retorna o contrato oficial alimentado pela IA + telemetria comparativa
	return {
		# Campos oficiais consumidos por FeedbackState, estrelas, anel e progressão
		"precision": ai_precision,
		"global_similarity_pct": ai_precision * 100.0,
		"details": details,
		"mirrored": bool(legacy_result.get("mirrored", false)) or (has_left and not has_right),
		"ok": is_ok,
		"error": "" if is_ok else "Não foi possível detectar a postura das mãos na gravação.",

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
