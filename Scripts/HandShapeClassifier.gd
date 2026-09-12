class_name HandShapeClassifier
extends RefCounted

## Classificador de forma de mão em LIBRAS com estabilização temporal de frames.
## Converte os 21 landmarks do MediaPipe em 42 features relativas, executa a inferência
## na rede neural (HandNeuralEngine) e aplica Média Móvel Exponencial (EMA) no vetor
## de probabilidades e filtro de mediana nos estágios anatômicos dos dedos.
## Suporta classificação simultânea e independente de ambas as mãos (Direita e Esquerda).

const HandNeuralEngineScript := preload("res://Scripts/HandNeuralEngine.gd")
const HandBiomechanicalGuidanceScript := preload("res://Scripts/HandBiomechanicalGuidance.gd")

const TIME_CONSTANT_TAU_SEC := 0.15   # 150ms de constante de tempo para suavização
const MEDIAN_WINDOW_SIZE := 5         # Janela de 5 amostras para filtro de mediana

## Estado temporal individual por mão (canal direito / canal esquerdo)
class HandChannelState:
	var handedness: String = "Right"
	var last_timestamp_ms: float = -1.0
	var smoothed_probs: PackedFloat32Array = PackedFloat32Array()
	var code_history: Array[String] = []
	var active_finger_stages: Array[int] = [0, 0, 0, 0]
	var detected_frames: int = 0
	var match_frames: int = 0
	var confidences: Array[float] = []
	var similarities: Array[float] = []
	var history_codes: Array[String] = []
	var code_frequencies: Dictionary = {}
	var last_guidance: Dictionary = {}

	func reset() -> void:
		last_timestamp_ms = -1.0
		smoothed_probs.clear()
		code_history.clear()
		active_finger_stages = [0, 0, 0, 0]
		detected_frames = 0
		match_frames = 0
		confidences.clear()
		similarities.clear()
		history_codes.clear()
		code_frequencies.clear()
		last_guidance.clear()


static var _shared_engine: RefCounted = null

## Retorna a instância compartilhada (singleton) do modelo, evitando recarregamentos do disco.
static func get_shared_engine() -> RefCounted:
	if _shared_engine == null or not bool(_shared_engine.get("is_loaded")):
		_shared_engine = HandNeuralEngineScript.new()
		_shared_engine.load_model()
	return _shared_engine


var engine: RefCounted
var right_channel := HandChannelState.new()
var left_channel := HandChannelState.new()

# Propriedades de compatibilidade para código legado que acessa smoothed_probs/code_history diretamente
var smoothed_probs: PackedFloat32Array:
	get: return right_channel.smoothed_probs
	set(v): right_channel.smoothed_probs = v
var code_history: Array[String]:
	get: return right_channel.code_history
	set(v): right_channel.code_history = v
var last_timestamp_ms: float:
	get: return right_channel.last_timestamp_ms
	set(v): right_channel.last_timestamp_ms = v
var active_finger_stages: Array[int]:
	get: return right_channel.active_finger_stages
	set(v): right_channel.active_finger_stages = v


func _init(p_engine: RefCounted = null) -> void:
	right_channel.handedness = "Right"
	left_channel.handedness = "Left"
	if p_engine != null:
		engine = p_engine
	else:
		engine = get_shared_engine()


## Reinicia os buffers temporais para iniciar uma nova captura em ambos os canais.
func reset() -> void:
	right_channel.reset()
	left_channel.reset()


## Espelha horizontalmente os landmarks (x -> 1.0 - x) para converter a mão esquerda
## no espaço de coordenadas canônico em que a rede neural foi treinada.
static func mirror_hand_landmarks(landmarks: Array) -> Array:
	var out: Array = []
	out.resize(landmarks.size())
	for i in range(landmarks.size()):
		var lm_val: Variant = landmarks[i]
		if lm_val is Dictionary:
			var d: Dictionary = (lm_val as Dictionary).duplicate()
			d["x"] = 1.0 - _get_coord(d, "x")
			out[i] = d
		elif lm_val is Object and lm_val.has_method("get"):
			out[i] = {
				"x": 1.0 - float(lm_val.get("x")),
				"y": float(lm_val.get("y")),
				"z": float(lm_val.get("z"))
			}
		else:
			out[i] = lm_val
	return out


## Extrai e normaliza as 42 features relativas a partir de 21 landmarks.
## Idêntico à fórmula do TCC:
## 1. Bounding box da mão: min_x, max_x, min_y, max_y
## 2. size = max(span_x, span_y, 1e-6)
## 3. Coordenadas normalizadas: nx = (x - min_x) / size, ny = (y - min_y) / size
## 4. Subtrai Landmark 0 (pulso): features = [nx - w_x, ny - w_y]
static func extract_features(landmarks: Array) -> PackedFloat32Array:
	if landmarks.size() < 21:
		return PackedFloat32Array()

	var min_x := 1e9
	var max_x := -1e9
	var min_y := 1e9
	var max_y := -1e9

	for lm_val: Variant in landmarks:
		var x: float = _get_coord(lm_val, "x")
		var y: float = _get_coord(lm_val, "y")
		min_x = minf(min_x, x)
		max_x = maxf(max_x, x)
		min_y = minf(min_y, y)
		max_y = maxf(max_y, y)

	var span_x := max_x - min_x
	var span_y := max_y - min_y
	var size := maxf(span_x, span_y)
	if size < 1e-6:
		size = 1e-6

	var w_x := (_get_coord(landmarks[0], "x") - min_x) / size
	var w_y := (_get_coord(landmarks[0], "y") - min_y) / size

	var features := PackedFloat32Array()
	features.resize(42)

	for i in range(21):
		var nx := (_get_coord(landmarks[i], "x") - min_x) / size
		var ny := (_get_coord(landmarks[i], "y") - min_y) / size
		features[i * 2]     = nx - w_x
		features[i * 2 + 1] = ny - w_y

	return features


static func _get_coord(lm_val: Variant, axis: String) -> float:
	if lm_val is Dictionary:
		return float(lm_val.get(axis, 0.0))
	if lm_val is Object and lm_val.has_method("get"):
		return float(lm_val.get(axis))
	return 0.0


## Classifica um quadro da mão aplicando média temporal nas probabilidades
## e filtro de mediana nos estágios anatômicos. Se is_left for true, espelha
## a mão horizontalmente para alinhá-la ao espaço canônico do modelo.
func classify_hand(landmarks: Array, timestamp_ms: float = -1.0, is_left: bool = false) -> Dictionary:
	if landmarks.is_empty() or landmarks.size() < 21:
		return {
			"detected": false,
			"code": "0000000000",
			"raw_code": "0000000000",
			"confidence": 0.0,
			"top_letter": "",
			"guidance": {"match": false, "hints": ["Mão não detectada"], "finger_status": {}}
		}

	# Mão esquerda é espelhada para corresponder ao manifold canônico de treinamento
	var lms_to_process: Array = landmarks
	if is_left:
		lms_to_process = mirror_hand_landmarks(landmarks)

	var feats := extract_features(lms_to_process)
	if feats.is_empty():
		return {"detected": false, "code": "0000000000", "confidence": 0.0}

	var raw_res: Dictionary = engine.predict(feats)
	var raw_probs: PackedFloat32Array = raw_res.get("probabilities", PackedFloat32Array())
	var raw_code: String = String(raw_res.get("code", "0000000000"))

	var ch: HandChannelState = left_channel if is_left else right_channel

	# 1. Média Móvel Exponencial (EMA) temporal nas probabilidades do canal
	var dt_sec := 0.033
	if timestamp_ms >= 0.0 and ch.last_timestamp_ms >= 0.0:
		var dt_ms := timestamp_ms - ch.last_timestamp_ms
		if dt_ms > 0.0 and dt_ms < 500.0:
			dt_sec = dt_ms / 1000.0
	ch.last_timestamp_ms = timestamp_ms

	var alpha: float = 1.0 - exp(-dt_sec / TIME_CONSTANT_TAU_SEC)
	alpha = clampf(alpha, 0.1, 1.0)

	if ch.smoothed_probs.size() != raw_probs.size():
		ch.smoothed_probs = raw_probs.duplicate()
	else:
		for k in range(ch.smoothed_probs.size()):
			ch.smoothed_probs[k] = alpha * raw_probs[k] + (1.0 - alpha) * ch.smoothed_probs[k]

	# Encontra top class a partir da probabilidade suavizada
	var top_idx := 0
	var max_prob := ch.smoothed_probs[0]
	for k in range(1, ch.smoothed_probs.size()):
		if ch.smoothed_probs[k] > max_prob:
			max_prob = ch.smoothed_probs[k]
			top_idx = k

	var smoothed_code := "0000000000"
	if top_idx >= 0 and top_idx < engine.labels.size():
		smoothed_code = String(engine.labels[top_idx])

	# 2. Filtro de Mediana nos Dígitos Anatômicos
	ch.code_history.append(smoothed_code)
	if ch.code_history.size() > MEDIAN_WINDOW_SIZE:
		ch.code_history.pop_front()

	var stabilized_code := _apply_finger_median_filter(ch.code_history, smoothed_code)
	var letter_info := HandBiomechanicalGuidanceScript.get_closest_letter(stabilized_code)

	return {
		"detected": true,
		"code": stabilized_code,
		"raw_code": raw_code,
		"confidence": max_prob,
		"top_letter": String(letter_info.get("letter", "")),
		"is_exact_letter": bool(letter_info.get("is_exact", false)),
		"letter_distance": int(letter_info.get("distance", 999)),
		"handedness": "Left" if is_left else "Right"
	}


## Aplica filtro de mediana nos estágios de flexão de cada dedo (posições 0, 2, 4, 6)
## para eliminar spikes de oclusão de 1 frame.
static func _apply_finger_median_filter(history: Array[String], fallback_code: String) -> String:
	if history.size() < 3:
		return fallback_code

	var chars := fallback_code.split("")
	if chars.size() < 10:
		return fallback_code

	var finger_indices: Array[int] = [0, 2, 4, 6]

	for idx: int in finger_indices:
		var stages: Array[int] = []
		for code_str: String in history:
			if code_str.length() > idx:
				stages.append(code_str.substr(idx, 1).to_int())
		stages.sort()
		var med: int = stages[stages.size() / 2]
		chars[idx] = str(med)

	var result := ""
	for c: String in chars:
		result += c
	return result


## Extrai todas as mãos detectadas em um frame (Direita e/ou Esquerda).
## Retorna Array de Dictionary: [{ "handedness": "Right"|"Left", "landmarks": Array }, ...]
static func extract_all_hands_from_frame(frame: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	if not frame.has("hands"):
		if frame.has("hand_right") and frame["hand_right"] is Array and (frame["hand_right"] as Array).size() >= 21:
			result.append({"handedness": "Right", "landmarks": frame["hand_right"] as Array})
		if frame.has("hand_left") and frame["hand_left"] is Array and (frame["hand_left"] as Array).size() >= 21:
			result.append({"handedness": "Left", "landmarks": frame["hand_left"] as Array})
		return result

	var hands_raw: Variant = frame["hands"]
	if hands_raw is Array:
		for item: Variant in hands_raw as Array:
			if item is Dictionary:
				var h_dict: Dictionary = item as Dictionary
				var lms: Array = h_dict.get("landmarks", []) as Array
				if lms.size() >= 21:
					var side: String = String(h_dict.get("handedness", "Right"))
					if side.is_empty():
						side = "Right"
					result.append({"handedness": side, "landmarks": lms})
			elif item is Array and (item as Array).size() >= 21:
				var side: String = "Right" if result.is_empty() else "Left"
				result.append({"handedness": side, "landmarks": item as Array})

	elif hands_raw is Dictionary:
		var dict: Dictionary = hands_raw as Dictionary
		var r: Variant = dict.get("right")
		if r is Array and (r as Array).size() >= 21:
			result.append({"handedness": "Right", "landmarks": r as Array})
		var l: Variant = dict.get("left")
		if l is Array and (l as Array).size() >= 21:
			result.append({"handedness": "Left", "landmarks": l as Array})

	return result


## Extrai landmarks de mão de um frame (mantido para compatibilidade, prioriza Direita).
static func extract_hand_landmarks_from_frame(frame: Dictionary) -> Array:
	var hands := extract_all_hands_from_frame(frame)
	if hands.is_empty():
		return []
	for h: Dictionary in hands:
		if String(h.get("handedness", "")) == "Right":
			return h.get("landmarks", []) as Array
	return hands[0].get("landmarks", []) as Array


## Analisa uma gravação completa (Array de frames), avaliando AMBAS as mãos (Direita e Esquerda).
## Permite definir códigos esperados independentes para sinais bi-manuais assimétricos.
func evaluate_recording(frames: Array, expected_code: String, expected_left_code: String = "") -> Dictionary:
	reset()
	var expected_clean_right := HandBiomechanicalGuidanceScript.resolve_kinematic_code(expected_code)
	var expected_clean_left := expected_clean_right
	if not expected_left_code.is_empty():
		expected_clean_left = HandBiomechanicalGuidanceScript.resolve_kinematic_code(expected_left_code)

	var n_frames := frames.size()
	# Amostragem com passo adaptativo (stride) para dispositivos móveis:
	# Mantém taxa de análise estável (~15-20 fps), reduzindo em até 66% as inferências
	var step := 1
	if n_frames > 60:
		step = 3
	elif n_frames > 30:
		step = 2

	for f_idx: int in range(0, n_frames, step):
		var frame: Dictionary = frames[f_idx] as Dictionary
		var ts: float = float(frame.get("timestamp_ms", -1.0))
		if ts < 0.0 and frame.has("t"):
			ts = float(frame["t"]) * 1000.0

		var all_hands: Array[Dictionary] = extract_all_hands_from_frame(frame)
		# Quadros sem mãos detectadas são desconsiderados da avaliação de forma
		if all_hands.is_empty():
			continue

		for h_entry: Dictionary in all_hands:
			var side: String = String(h_entry.get("handedness", "Right"))
			var is_left: bool = (side == "Left")
			var lms: Array = h_entry.get("landmarks", []) as Array

			if lms.size() >= 21:
				var res := classify_hand(lms, ts, is_left)
				var c: String = String(res.get("code", "0000000000"))
				var conf: float = float(res.get("confidence", 0.0))

				var ch: HandChannelState = left_channel if is_left else right_channel
				ch.detected_frames += 1
				ch.confidences.append(conf)
				ch.history_codes.append(c)
				ch.code_frequencies[c] = int(ch.code_frequencies.get(c, 0)) + 1

				var expected_target := expected_clean_left if is_left else expected_clean_right
				# Similaridade cinemática contínua (0.0 a 1.0)
				var sim: float = HandBiomechanicalGuidanceScript.calculate_posture_similarity(c, expected_target)
				ch.similarities.append(sim)

				var g := HandBiomechanicalGuidanceScript.get_biomechanical_guidance(c, expected_target)
				ch.last_guidance = g
				if bool(g.get("match", false)) or sim >= 0.70:
					ch.match_frames += 1

	var right_res := _compile_channel_results(right_channel, expected_clean_right, frames.size())
	var left_res := _compile_channel_results(left_channel, expected_clean_left, frames.size())

	var has_right: bool = right_channel.detected_frames > 0
	var has_left: bool = left_channel.detected_frames > 0
	var both_hands: bool = has_right and has_left

	# Determina a mão primária / dominante ou calcula a média combinada se ambas foram ativas
	var primary_res: Dictionary = right_res
	var dominant_hand: String = "None"
	var overall_precision: float = 0.0
	var combined_hints: Array = []

	if both_hands:
		dominant_hand = "Both"
		var total_det: int = right_channel.detected_frames + left_channel.detected_frames
		overall_precision = (
			float(right_res["hand_precision"]) * right_channel.detected_frames +
			float(left_res["hand_precision"]) * left_channel.detected_frames
		) / float(total_det)
		primary_res = right_res if float(right_res["hand_precision"]) >= float(left_res["hand_precision"]) else left_res
		combined_hints.append_array(right_res.get("hints", []))
		for h: Variant in left_res.get("hints", []):
			if not combined_hints.has(h):
				combined_hints.append(h)
	elif has_right:
		dominant_hand = "Right"
		primary_res = right_res
		overall_precision = float(right_res["hand_precision"])
		combined_hints = right_res.get("hints", [])
	elif has_left:
		dominant_hand = "Left"
		primary_res = left_res
		overall_precision = float(left_res["hand_precision"])
		combined_hints = left_res.get("hints", [])

	return {
		"ok": true,
		"has_right": has_right,
		"has_left": has_left,
		"both_hands_detected": both_hands,
		"dominant_hand": dominant_hand,
		"right_hand": right_res,
		"left_hand": left_res,

		# Chaves de nível superior preservadas para compatibilidade
		"hand_precision": clampf(overall_precision, 0.0, 1.0),
		"detected_frames": maxi(right_channel.detected_frames, left_channel.detected_frames),
		"total_frames": frames.size(),
		"dominant_code": String(primary_res.get("dominant_code", "0000000000")),
		"expected_code": expected_clean_right if (dominant_hand != "Left") else expected_clean_left,
		"dominant_letter": String(primary_res.get("dominant_letter", "")),
		"avg_confidence": float(primary_res.get("avg_confidence", 0.0)),
		"finger_status": primary_res.get("finger_status", {}),
		"hints": combined_hints
	}


func _compile_channel_results(ch: HandChannelState, expected_clean: String, total_frames: int) -> Dictionary:
	if ch.detected_frames == 0:
		return {
			"detected_frames": 0,
			"total_frames": total_frames,
			"dominant_code": "0000000000",
			"expected_code": expected_clean,
			"dominant_letter": "",
			"avg_confidence": 0.0,
			"hand_precision": 0.0,
			"finger_status": {},
			"hints": []
		}

	var best_freq := 0
	var most_frequent_code := ""
	for c: String in ch.code_frequencies:
		var f: int = int(ch.code_frequencies[c])
		if f > best_freq:
			best_freq = f
			most_frequent_code = c

	var total_conf := 0.0
	for c_val: float in ch.confidences:
		total_conf += c_val
	var avg_conf: float = total_conf / float(ch.confidences.size()) if not ch.confidences.is_empty() else 0.0

	# Cálculo de Precisão com Proximidade Contínua e Foco no Ápice da Execução:
	# Desconsidera os quadros transitórios (subida/descida da mão)
	# e calcula a média do ápice dos quadros em que a mão esteve presente (top 70%).
	var top_sim_avg := 0.0
	if not ch.similarities.is_empty():
		var sorted_sims := ch.similarities.duplicate()
		sorted_sims.sort()
		var num_top := maxi(1, int(ceil(float(sorted_sims.size()) * 0.70)))
		var start_idx := sorted_sims.size() - num_top
		var sum_top := 0.0
		for i in range(start_idx, sorted_sims.size()):
			sum_top += float(sorted_sims[i])
		top_sim_avg = sum_top / float(num_top)

	# Similaridade contínua do código dominante estabilizado
	var dominant_sim := HandBiomechanicalGuidanceScript.calculate_posture_similarity(most_frequent_code, expected_clean)

	# A precisão oficial da mão combina a postura sustentada dominante (70%) e o ápice dos frames lidos (30%)
	var hand_precision := maxf(dominant_sim, (dominant_sim * 0.70) + (top_sim_avg * 0.30))

	# Se a forma dominante ou a média do ápice atingiu alta similaridade, garante aprovação merecida
	var final_guidance := HandBiomechanicalGuidanceScript.get_biomechanical_guidance(most_frequent_code, expected_clean)
	if bool(final_guidance.get("match", false)) or dominant_sim >= 0.85:
		hand_precision = maxf(hand_precision, 0.88)

	var closest_letter := HandBiomechanicalGuidanceScript.get_closest_letter(most_frequent_code)

	return {
		"detected_frames": ch.detected_frames,
		"total_frames": total_frames,
		"dominant_code": most_frequent_code,
		"expected_code": expected_clean,
		"dominant_letter": String(closest_letter.get("letter", "")),
		"avg_confidence": avg_conf,
		"hand_precision": clampf(hand_precision, 0.0, 1.0),
		"finger_status": final_guidance.get("finger_status", {}),
		"hints": final_guidance.get("hints", [])
	}

