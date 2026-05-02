##Comparador.gd
## =====================
## Compara a similaridade de movimentos entre dois vídeos usando os JSONs
## gerados pelo hand_landmarker.
##
## Abordagem:
## - Trata pares de landmarks como os "ossos" da rig 3D
## - Calcula vetores e ângulos de cada osso por frame
## - Usa DTW (Dynamic Time Warping) para alinhar sequências de tamanhos diferentes
## - Gera relatório de similaridade
##
## Uso:
##   var comparator := MotionComparator.new()
##   var results := comparator.analyze_similarity(json_a, json_b)
##   comparator.print_summary(results, "VideoA", "VideoB")

class_name SignComparator
extends RefCounted


# ─────────────────────────────────────────────
#  TIPOS DE DADOS INTERNOS
# ─────────────────────────────────────────────

## Representa um landmark 3D
class Landmark:
	var id: int
	var x: float
	var y: float
	var z: float

	func _init(p_id: int, p_x: float, p_y: float, p_z: float) -> void:
		id = p_id
		x  = p_x
		y  = p_y
		z  = p_z


## Representa um osso (par pai → filho)
class Bone:
	var name: String
	var idx_parent: int
	var idx_child: int

	func _init(p_name: String, p_parent: int, p_child: int) -> void:
		name       = p_name
		idx_parent = p_parent
		idx_child  = p_child


## Resultado de um par de segmentos DTW
class SegmentPair:
	var pair_index: int
	var seg_a_start: int
	var seg_a_end: int
	var seg_b_start: int
	var seg_b_end: int
	var dtw_similarity_pct: float


## Resultado da análise de fase (segmentação de gestos)
class PhaseData:
	var segments_a: Array[Dictionary]   # [{start, end}]
	var segments_b: Array[Dictionary]
	var n_segments_a: int
	var n_segments_b: int
	var n_pairs: int
	var pairs: Array[Dictionary]        # Array de SegmentPair serializado
	var phase_similarity_pct: float
	var velocity_a: PackedFloat64Array
	var velocity_b: PackedFloat64Array


# ─────────────────────────────────────────────
#  PESOS DE RELEVÂNCIA POR OSSO
# ─────────────────────────────────────────────

const BONE_WEIGHTS: Dictionary = {
	# Tronco / cabeça — baixo peso
	"spine": 0.2, "hip": 0.1, "shoulders": 0.3,
	# Braços
	"upper_arm_L": 0.6, "lower_arm_L": 1.3, "hand_L": 1.0,
	"upper_arm_R": 0.6, "lower_arm_R": 1.3, "hand_R": 1.0,
	# Pernas — baixo peso
	"upper_leg_L": 0.1, "lower_leg_L": 0.1, "foot_L": 0.1,
	"upper_leg_R": 0.1, "lower_leg_R": 0.1, "foot_R": 0.1,
	# Dedos — peso alto
	"thumb_L_1": 1.5, "thumb_L_2": 1.5, "thumb_L_3": 1.5,
	"index_L_1": 1.5, "index_L_2": 1.5, "index_L_3": 1.5,
	"middle_L_1": 1.5, "middle_L_2": 1.5, "middle_L_3": 1.5,
	"ring_L_1":   1.2, "ring_L_2":   1.2, "ring_L_3":   1.2,
	"pinky_L_1":  1.2, "pinky_L_2":  1.2, "pinky_L_3":  1.2,
	"thumb_R_1": 1.5, "thumb_R_2": 1.5, "thumb_R_3": 1.5,
	"index_R_1": 1.5, "index_R_2": 1.5, "index_R_3": 1.5,
	"middle_R_1": 1.5, "middle_R_2": 1.5, "middle_R_3": 1.5,
	"ring_R_1":   1.2, "ring_R_2":   1.2, "ring_R_3":   1.2,
	"pinky_R_1":  1.2, "pinky_R_2":  1.2, "pinky_R_3":  1.2,
}

# Pesos por grupo (mãos valem muito mais que corpo)
const GROUP_WEIGHTS: Dictionary = {
	"Pose (corpo)": 0.3,
	"Mão Esquerda": 1.0,
	"Mão Direita":  1.0,
}


# ─────────────────────────────────────────────
#  DEFINIÇÃO DA HIERARQUIA DE OSSOS
# ─────────────────────────────────────────────

## Ossos do corpo (pose)
var POSE_BONES: Array[Bone] = [
	Bone.new("spine",        23, 11),
	Bone.new("hip",          23, 24),
	Bone.new("shoulders",    11, 12),
	Bone.new("upper_arm_L",  11, 13),
	Bone.new("lower_arm_L",  13, 15),
	Bone.new("hand_L",       15, 17),
	Bone.new("upper_arm_R",  12, 14),
	Bone.new("lower_arm_R",  14, 16),
	Bone.new("hand_R",       16, 18),
	Bone.new("upper_leg_L",  23, 25),
	Bone.new("lower_leg_L",  25, 27),
	Bone.new("foot_L",       27, 29),
	Bone.new("upper_leg_R",  24, 26),
	Bone.new("lower_leg_R",  26, 28),
	Bone.new("foot_R",       28, 30),
]

## Ossos da mão esquerda
var HAND_BONES_LEFT: Array[Bone] = [
	Bone.new("thumb_L_1",   1,  2), Bone.new("thumb_L_2",   2,  3), Bone.new("thumb_L_3",   3,  4),
	Bone.new("index_L_1",   5,  6), Bone.new("index_L_2",   6,  7), Bone.new("index_L_3",   7,  8),
	Bone.new("middle_L_1",  9, 10), Bone.new("middle_L_2", 10, 11), Bone.new("middle_L_3", 11, 12),
	Bone.new("ring_L_1",   13, 14), Bone.new("ring_L_2",   14, 15), Bone.new("ring_L_3",   15, 16),
	Bone.new("pinky_L_1",  17, 18), Bone.new("pinky_L_2",  18, 19), Bone.new("pinky_L_3",  19, 20),
]

## Ossos da mão direita (mesmo padrão, lado R)
var HAND_BONES_RIGHT: Array[Bone] = [
	Bone.new("thumb_R_1",   1,  2), Bone.new("thumb_R_2",   2,  3), Bone.new("thumb_R_3",   3,  4),
	Bone.new("index_R_1",   5,  6), Bone.new("index_R_2",   6,  7), Bone.new("index_R_3",   7,  8),
	Bone.new("middle_R_1",  9, 10), Bone.new("middle_R_2", 10, 11), Bone.new("middle_R_3", 11, 12),
	Bone.new("ring_R_1",   13, 14), Bone.new("ring_R_2",   14, 15), Bone.new("ring_R_3",   15, 16),
	Bone.new("pinky_R_1",  17, 18), Bone.new("pinky_R_2",  18, 19), Bone.new("pinky_R_3",  19, 20),
]


# ─────────────────────────────────────────────
#  FUNÇÕES AUXILIARES — LANDMARKS
# ─────────────────────────────────────────────

## Carrega um JSON de vídeo a partir de um caminho de arquivo.
## Retorna o dicionário ou um dicionário vazio em caso de erro.
func load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MotionComparator: arquivo não encontrado: %s" % path)
		return {}
	var text: String = file.get_as_text()
	file.close()
	var result: Variant = JSON.parse_string(text)
	if result == null:
		push_error("MotionComparator: falha ao parsear JSON: %s" % path)
		return {}
	return result as Dictionary


## Retorna as coordenadas [x, y, z] de um landmark pelo ID.
## Retorna Vector3.ZERO e sets found=false se não encontrar.
func get_landmark(landmarks: Array, idx: int) -> Vector3:
	for lm: Variant in landmarks:
		var lm_dict: Dictionary = lm as Dictionary
		if lm_dict.get("id", -1) == idx:
			return Vector3(
				float(lm_dict.get("x", 0.0)),
				float(lm_dict.get("y", 0.0)),
				float(lm_dict.get("z", 0.0))
			)
	return Vector3(INF, INF, INF)   # sentinela: landmark não encontrado


## Verifica se o vetor retornado por get_landmark é válido (não-sentinela).
func _is_valid_lm(v: Vector3) -> bool:
	return v.x != INF


## Calcula vetor normalizado do osso (pai → filho).
## Retorna Vector3.ZERO se inválido; use _is_valid_vec() para checar.
func bone_vector(landmarks: Array, idx_parent: int, idx_child: int) -> Vector3:
	var p: Vector3 = get_landmark(landmarks, idx_parent)
	var c: Vector3 = get_landmark(landmarks, idx_child)
	if not _is_valid_lm(p) or not _is_valid_lm(c):
		return Vector3(INF, INF, INF)
	var vec: Vector3 = c - p
	var norm: float = vec.length()
	if norm < 1e-9:
		return Vector3(INF, INF, INF)
	return vec / norm


## Verifica se o vetor retornado por bone_vector é válido.
func _is_valid_vec(v: Vector3) -> bool:
	return v.x != INF


## Ângulo em graus entre dois vetores unitários.
func angle_between(v1: Vector3, v2: Vector3) -> float:
	var dot: float = clampf(v1.dot(v2), -1.0, 1.0)
	return rad_to_deg(acos(dot))


## Converte ângulo (0–180°) em similaridade (0–100%) com curva exponencial.
## steepness controla a agressividade da curva (3.0 = padrão).
func angle_to_similarity(angle_deg: float, steepness: float = 3.0) -> float:
	var t: float = angle_deg / 180.0
	return maxf(0.0, 100.0 * pow(1.0 - t, steepness))


# ─────────────────────────────────────────────
#  ORIENTAÇÃO GLOBAL DA PALMA
# ─────────────────────────────────────────────

## Calcula o vetor normal da palma usando produto vetorial.
## Usa landmarks: 0 = pulso, 5 = base indicador, 17 = base mindinho.
## Retorna Vector3(INF, INF, INF) se inválido.
func palm_normal(landmarks: Array) -> Vector3:
	var wrist: Vector3 = get_landmark(landmarks, 0)
	var index: Vector3 = get_landmark(landmarks, 5)
	var pinky: Vector3 = get_landmark(landmarks, 17)

	if not _is_valid_lm(wrist) or not _is_valid_lm(index) or not _is_valid_lm(pinky):
		return Vector3(INF, INF, INF)

	var vec_a: Vector3 = index - wrist
	var vec_b: Vector3 = pinky - wrist
	var normal: Vector3 = vec_a.cross(vec_b)
	var norm: float = normal.length()
	if norm < 1e-9:
		return Vector3(INF, INF, INF)
	return normal / norm


## Vetor global de direção da mão: pulso (0) → ponta do dedo médio (12).
## Retorna Vector3(INF, INF, INF) se inválido.
func hand_direction_vector(landmarks: Array) -> Vector3:
	var wrist:  Vector3 = get_landmark(landmarks, 0)
	var middle: Vector3 = get_landmark(landmarks, 12)
	if not _is_valid_lm(wrist) or not _is_valid_lm(middle):
		return Vector3(INF, INF, INF)
	var vec: Vector3 = middle - wrist
	var norm: float = vec.length()
	if norm < 1e-9:
		return Vector3(INF, INF, INF)
	return vec / norm


## Retorna rótulo legível da orientação da palma com base na normal.
func palm_orientation_label(normal: Vector3) -> String:
	if not _is_valid_vec(normal):
		return "desconhecida"
	var y: float = normal.y
	var z: float = normal.z
	if abs(z) > 0.5:
		return "frente" if z > 0.0 else "trás"
	return "baixo" if y > 0.0 else "cima"


## Extrai a normal da palma para cada frame.
## hand_side = "Left" | "Right"
func extract_palm_normals_per_frame(frames: Array, hand_side: String) -> Array[Vector3]:
	var normals: Array[Vector3] = []
	for frame: Variant in frames:
		var f: Dictionary = frame as Dictionary
		var hands: Array = f.get("hands", []) as Array
		var found: bool = false
		for h: Variant in hands:
			var hand: Dictionary = h as Dictionary
			if hand.get("handedness", "") == hand_side:
				var lm: Array = hand.get("landmarks", []) as Array
				normals.append(palm_normal(lm))
				found = true
				break
		if not found:
			normals.append(Vector3(INF, INF, INF))
	return normals


## Compara as normais de palma entre dois vídeos.
## frame_weights: pesos por frame (PackedFloat64Array vazia = sem pesos).
func palm_orientation_similarity(
		normals_a: Array[Vector3],
		normals_b: Array[Vector3],
		frame_weights: PackedFloat64Array) -> Dictionary:

	var angle_diffs: PackedFloat64Array = PackedFloat64Array()
	var weights_used: PackedFloat64Array = PackedFloat64Array()
	var valid_frames: int = 0

	var length: int = mini(normals_a.size(), normals_b.size())
	for i: int in range(length):
		var na: Vector3 = normals_a[i]
		var nb: Vector3 = normals_b[i]
		if _is_valid_vec(na) and _is_valid_vec(nb):
			angle_diffs.append(angle_between(na, nb))
			var w: float = frame_weights[i] if (frame_weights.size() > 0 and i < frame_weights.size()) else 1.0
			weights_used.append(w)
			valid_frames += 1

	if angle_diffs.size() == 0:
		return {
			"mean_angle_diff_deg": null,
			"similarity_pct": null,
			"valid_frames": 0,
			"orientation_a": null,
			"orientation_b": null,
		}

	var mean_diff: float = _weighted_mean(angle_diffs, weights_used)
	var similarity_pct: float = angle_to_similarity(mean_diff, 3.0)

	return {
		"mean_angle_diff_deg": mean_diff,
		"similarity_pct": similarity_pct,
		"valid_frames": valid_frames,
		"orientation_a": _dominant_orientation(normals_a),
		"orientation_b": _dominant_orientation(normals_b),
		"angle_series": _packed_to_array(angle_diffs),
	}


## Orientação predominante de um array de normais.
func _dominant_orientation(normals: Array[Vector3]) -> String:
	var counts: Dictionary = {}
	for n: Vector3 in normals:
		if _is_valid_vec(n):
			var label: String = palm_orientation_label(n)
			counts[label] = counts.get(label, 0) + 1
	if counts.is_empty():
		return "desconhecida"
	var best_label: String = ""
	var best_count: int = -1
	for label: String in counts:
		if counts[label] > best_count:
			best_count = counts[label]
			best_label = label
	return best_label


# ─────────────────────────────────────────────
#  EXTRAÇÃO DE SÉRIES TEMPORAIS DE OSSOS
# ─────────────────────────────────────────────

## Fonte dos landmarks: "pose" | "hand_left" | "hand_right"
func _get_landmarks_from_frame(frame: Dictionary, source: String) -> Array:
	match source:
		"pose":
			var groups: Array = frame.get("pose", []) as Array
			if groups.size() > 0:
				return (groups[0] as Dictionary).get("landmarks", []) as Array
		"hand_left":
			var hands: Array = frame.get("hands", []) as Array
			for h: Variant in hands:
				var hand: Dictionary = h as Dictionary
				if hand.get("handedness", "") == "Left":
					return hand.get("landmarks", []) as Array
		"hand_right":
			var hands: Array = frame.get("hands", []) as Array
			for h: Variant in hands:
				var hand: Dictionary = h as Dictionary
				if hand.get("handedness", "") == "Right":
					return hand.get("landmarks", []) as Array
	return []


## Para cada osso, retorna uma série temporal de vetores normalizados.
## Retorna: Dictionary{ bone_name -> Array[Vector3] }
func extract_bone_vectors_per_frame(frames: Array, bones: Array[Bone], source: String) -> Dictionary:
	var bone_series: Dictionary = {}
	for bone: Bone in bones:
		bone_series[bone.name] = []

	for frame: Variant in frames:
		var f: Dictionary = frame as Dictionary
		var lm_list: Array = _get_landmarks_from_frame(f, source)

		for bone: Bone in bones:
			var vec: Vector3 = bone_vector(lm_list, bone.idx_parent, bone.idx_child) if lm_list.size() > 0 else Vector3(INF, INF, INF)
			(bone_series[bone.name] as Array).append(vec)

	return bone_series


## Dado dois arrays de vetores (com possíveis INF-sentinelas),
## retorna PackedFloat64Array de ângulos frame a frame (NAN onde inválido).
func series_to_angle_diff(series_a: Array, series_b: Array) -> PackedFloat64Array:
	var length: int = mini(series_a.size(), series_b.size())
	var angles: PackedFloat64Array = PackedFloat64Array()
	angles.resize(length)
	for i: int in range(length):
		var va: Vector3 = series_a[i] as Vector3
		var vb: Vector3 = series_b[i] as Vector3
		if _is_valid_vec(va) and _is_valid_vec(vb):
			angles[i] = angle_between(va, vb)
		else:
			angles[i] = NAN
	return angles


# ─────────────────────────────────────────────
#  DTW — DYNAMIC TIME WARPING
# ─────────────────────────────────────────────

## Distância DTW entre duas séries 1D (NaN substituído por 0).
## Implementação O(n*m) com matriz de custo.
func compute_dtw_distance(seq_a: PackedFloat64Array, seq_b: PackedFloat64Array) -> float:
	var n: int = seq_a.size()
	var m: int = seq_b.size()
	if n == 0 or m == 0:
		return 0.0

	# Substituir NaN por 0
	var a: PackedFloat64Array = _nan_to_zero(seq_a)
	var b: PackedFloat64Array = _nan_to_zero(seq_b)

	# Matriz DTW achatada (n x m)
	var cost: PackedFloat64Array = PackedFloat64Array()
	cost.resize(n * m)
	cost.fill(INF)

	cost[0] = abs(a[0] - b[0])

	for i: int in range(1, n):
		cost[i * m + 0] = abs(a[i] - b[0]) + cost[(i - 1) * m + 0]
	for j: int in range(1, m):
		cost[0 * m + j] = abs(a[0] - b[j]) + cost[0 * m + (j - 1)]

	for i: int in range(1, n):
		for j: int in range(1, m):
			var local_cost: float = abs(a[i] - b[j])
			var prev_min: float = minf(
				cost[(i - 1) * m + j],
				minf(cost[i * m + (j - 1)], cost[(i - 1) * m + (j - 1)])
			)
			cost[i * m + j] = local_cost + prev_min

	return cost[n * m - 1]


## Interpola uma sequência para tamanho fixo (100 pontos).
## Ignora NaNs no processo de interpolação.
func normalize_sequence(seq: PackedFloat64Array) -> PackedFloat64Array:
	var target_size: int = 100
	var result: PackedFloat64Array = PackedFloat64Array()
	result.resize(target_size)

	# Coletar índices e valores válidos
	var valid_x: PackedFloat64Array = PackedFloat64Array()
	var valid_y: PackedFloat64Array = PackedFloat64Array()
	for i: int in range(seq.size()):
		if not is_nan(seq[i]):
			valid_x.append(float(i))
			valid_y.append(seq[i])

	if valid_x.size() < 2:
		result.fill(0.0)
		return result

	var x_start: float = valid_x[0]
	var x_end: float   = valid_x[valid_x.size() - 1]

	for i: int in range(target_size):
		var x: float = x_start + (x_end - x_start) * float(i) / float(target_size - 1)
		result[i] = _interpolate_1d(valid_x, valid_y, x)

	return result


## Interpolação linear 1D para um ponto x dado arrays sorted de xs e ys.
func _interpolate_1d(xs: PackedFloat64Array, ys: PackedFloat64Array, x: float) -> float:
	var n: int = xs.size()
	if n == 0:
		return 0.0
	if x <= xs[0]:
		return ys[0]
	if x >= xs[n - 1]:
		return ys[n - 1]
	# Busca binária
	var lo: int = 0
	var hi: int = n - 1
	while hi - lo > 1:
		var mid: int = (lo + hi) / 2
		if xs[mid] <= x:
			lo = mid
		else:
			hi = mid
	var t: float = (x - xs[lo]) / (xs[hi] - xs[lo])
	return ys[lo] + t * (ys[hi] - ys[lo])


## DTW entre duas sequências de segmento, retorna similaridade 0–100.
func segment_similarity_dtw(seq_a: PackedFloat64Array, seq_b: PackedFloat64Array) -> float:
	if seq_a.size() == 0 or seq_b.size() == 0:
		return 0.0
	var a: PackedFloat64Array = _nan_to_zero(seq_a)
	var b: PackedFloat64Array = _nan_to_zero(seq_b)
	var dist: float = compute_dtw_distance(a, b)
	var norm_dist: float = dist / float(a.size() + b.size())
	return maxf(0.0, 100.0 * (1.0 - minf(norm_dist * 10.0, 1.0)))


# ─────────────────────────────────────────────
#  PESOS TEMPORAIS — FRAMES DE REPOUSO
# ─────────────────────────────────────────────

## Gera array de pesos que reduz importância dos frames de repouso
## no início e fim do vídeo.
func build_rest_weights(n_frames: int, fps: float, rest_sec: float = 1.0, rest_weight: float = 0.1) -> PackedFloat64Array:
	var rest_frames: int = int(fps * rest_sec)
	var weights: PackedFloat64Array = PackedFloat64Array()
	weights.resize(n_frames)
	weights.fill(1.0)

	for i: int in range(n_frames):
		var dist_start: int = i
		var dist_end: int   = n_frames - 1 - i
		var dist_edge: int  = mini(dist_start, dist_end)
		if dist_edge < rest_frames:
			var t: float = float(dist_edge) / float(rest_frames)
			weights[i] = rest_weight + (1.0 - rest_weight) * t

	return weights


## Média ponderada dos ângulos de diferença, ignorando NaNs.
func weighted_mean_angle(angle_diffs: PackedFloat64Array, frame_weights: PackedFloat64Array) -> float:
	var w_sum: float = 0.0
	var w_total: float = 0.0
	var n: int = mini(angle_diffs.size(), frame_weights.size() if frame_weights.size() > 0 else angle_diffs.size())
	for i: int in range(n):
		if not is_nan(angle_diffs[i]):
			var w: float = frame_weights[i] if frame_weights.size() > 0 else 1.0
			w_sum   += angle_diffs[i] * w
			w_total += w
	if w_total < 1e-9:
		return NAN
	return w_sum / w_total


# ─────────────────────────────────────────────
#  DETECÇÃO DE FASES / SEGMENTAÇÃO DE GESTOS
# ─────────────────────────────────────────────

## Calcula a velocidade média de movimento de landmarks entre frames consecutivos.
func compute_motion_velocity(frames: Array, source: String) -> PackedFloat64Array:
	var velocities: PackedFloat64Array = PackedFloat64Array()
	velocities.resize(maxi(frames.size() - 1, 0))

	for i: int in range(1, frames.size()):
		var lm_prev: Array = _get_landmarks_from_frame(frames[i - 1] as Dictionary, source)
		var lm_curr: Array = _get_landmarks_from_frame(frames[i]     as Dictionary, source)

		if lm_prev.is_empty() or lm_curr.is_empty():
			velocities[i - 1] = 0.0
			continue

		# Mapear por id
		var prev_map: Dictionary = {}
		for lm: Variant in lm_prev:
			var d: Dictionary = lm as Dictionary
			prev_map[d.get("id", -1)] = Vector3(
				float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0))
			)

		var dists: PackedFloat64Array = PackedFloat64Array()
		for lm: Variant in lm_curr:
			var d: Dictionary = lm as Dictionary
			var idx: int = d.get("id", -1)
			if prev_map.has(idx):
				var curr_pos := Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))
				dists.append((curr_pos - prev_map[idx] as Vector3).length())

		velocities[i - 1] = _mean_packed(dists) if dists.size() > 0 else 0.0

	return velocities


## Média móvel simples (janela deslizante).
func smooth_signal(sinal: PackedFloat64Array, window: int = 5) -> PackedFloat64Array:
	var n: int = sinal.size()
	if n < window:
		return sinal.duplicate()
	var result: PackedFloat64Array = PackedFloat64Array()
	result.resize(n)
	var half: int = window / 2
	for i: int in range(n):
		var s: float = 0.0
		var count: int = 0
		for j: int in range(maxi(0, i - half), mini(n, i + half + 1)):
			s     += sinal[j]
			count += 1
		result[i] = s / float(count)
	return result


## Detecta segmentos de gesto (regiões de alta atividade).
## Retorna Array de Dictionary{start, end}.
func detect_gesture_segments(
		velocity: PackedFloat64Array,
		threshold_factor: float = 1.2,
		min_segment_frames: int = 5,
		merge_gap_frames: int = 8) -> Array[Dictionary]:

	var result: Array[Dictionary] = []
	if velocity.size() == 0:
		return result

	var smoothed: PackedFloat64Array = smooth_signal(velocity)

	# Mediana dos valores positivos
	var positives: PackedFloat64Array = PackedFloat64Array()
	for v: float in smoothed:
		if v > 0.0:
			positives.append(v)
	var median_val: float = _median_packed(positives) if positives.size() > 0 else 0.0
	var threshold: float = maxf(median_val * threshold_factor, 0.01)

	# Encontrar blocos contínuos acima do threshold
	var segments: Array[Dictionary] = []
	var in_seg: bool = false
	var seg_start: int = 0

	for i: int in range(smoothed.size()):
		var active: bool = smoothed[i] > threshold
		if active and not in_seg:
			seg_start = i
			in_seg = true
		elif not active and in_seg:
			segments.append({"start": seg_start, "end": i})
			in_seg = false
	if in_seg:
		segments.append({"start": seg_start, "end": smoothed.size()})

	# Mesclar segmentos próximos
	var merged: Array[Dictionary] = []
	for seg: Dictionary in segments:
		if merged.size() > 0 and (seg["start"] as int) - (merged[merged.size() - 1]["end"] as int) <= merge_gap_frames:
			merged[merged.size() - 1]["end"] = seg["end"]
		else:
			merged.append({"start": seg["start"], "end": seg["end"]})

	# Filtrar curtos e ajustar extremidade (+1 pela lógica de velocity)
	for seg: Dictionary in merged:
		var dur: int = (seg["end"] as int) - (seg["start"] as int)
		if dur >= min_segment_frames:
			result.append({
				"start": seg["start"],
				"end": mini((seg["end"] as int) + 1, velocity.size())
			})

	return result


## Detecta fases de gesto, emparelha segmentos e calcula DTW por par.
func analyze_gesture_phases(
		frames_a: Array,
		frames_b: Array,
		source: String,
		bones: Array[Bone]) -> Dictionary:

	var vel_a: PackedFloat64Array = compute_motion_velocity(frames_a, source)
	var vel_b: PackedFloat64Array = compute_motion_velocity(frames_b, source)

	var segs_a: Array[Dictionary] = detect_gesture_segments(vel_a)
	var segs_b: Array[Dictionary] = detect_gesture_segments(vel_b)

	var n_pairs: int = mini(segs_a.size(), segs_b.size())
	var pairs: Array[Dictionary] = []

	# Usar o primeiro osso como proxy para DTW de segmento
	var proxy_bone: Bone = bones[0] if bones.size() > 0 else null

	if proxy_bone != null:
		for i: int in range(n_pairs):
			var sa_start: int = segs_a[i]["start"]
			var sa_end:   int = segs_a[i]["end"]
			var sb_start: int = segs_b[i]["start"]
			var sb_end:   int = segs_b[i]["end"]

			var seg_vecs_a: PackedFloat64Array = _extract_bone_x_segment(frames_a, proxy_bone, source, sa_start, sa_end)
			var seg_vecs_b: PackedFloat64Array = _extract_bone_x_segment(frames_b, proxy_bone, source, sb_start, sb_end)

			var dtw_sim: float = segment_similarity_dtw(seg_vecs_a, seg_vecs_b)

			pairs.append({
				"pair_index": i + 1,
				"segment_a": {"start": sa_start, "end": sa_end, "duration_frames": sa_end - sa_start},
				"segment_b": {"start": sb_start, "end": sb_end, "duration_frames": sb_end - sb_start},
				"dtw_similarity_pct": snappedf(dtw_sim, 0.1),
			})

	# Score de fase: média ponderada pela cobertura
	var phase_sim: float = NAN
	if pairs.size() > 0:
		var dtw_scores: PackedFloat64Array = PackedFloat64Array()
		for p: Dictionary in pairs:
			dtw_scores.append(float(p["dtw_similarity_pct"]))
		var base_score: float = _mean_packed(dtw_scores)
		var max_segs: int = maxi(segs_a.size(), segs_b.size())
		var coverage: float = float(n_pairs) / float(max_segs) if max_segs > 0 else 1.0
		phase_sim = base_score * coverage

	# Serializar segmentos para Dictionary
	var segs_a_dict: Array[Dictionary] = []
	for s: Dictionary in segs_a:
		segs_a_dict.append({"start": s["start"], "end": s["end"]})
	var segs_b_dict: Array[Dictionary] = []
	for s: Dictionary in segs_b:
		segs_b_dict.append({"start": s["start"], "end": s["end"]})

	return {
		"segments_a": segs_a_dict,
		"segments_b": segs_b_dict,
		"n_segments_a": segs_a.size(),
		"n_segments_b": segs_b.size(),
		"n_pairs": n_pairs,
		"pairs": pairs,
		"phase_similarity_pct": phase_sim,
		"velocity_a": _packed_to_array(vel_a),
		"velocity_b": _packed_to_array(vel_b),
	}


## Extrai a componente X do vetor de um osso num segmento de frames.
func _extract_bone_x_segment(
		frames: Array,
		bone: Bone,
		source: String,
		seg_start: int,
		seg_end: int) -> PackedFloat64Array:

	var result: PackedFloat64Array = PackedFloat64Array()
	for fi: int in range(seg_start, mini(seg_end, frames.size())):
		var lm_list: Array = _get_landmarks_from_frame(frames[fi] as Dictionary, source)
		var vec: Vector3 = bone_vector(lm_list, bone.idx_parent, bone.idx_child) if lm_list.size() > 0 else Vector3(INF, INF, INF)
		result.append(vec.x if _is_valid_vec(vec) else NAN)
	return result


# ─────────────────────────────────────────────
#  ANÁLISE PRINCIPAL
# ─────────────────────────────────────────────

## Realiza toda a análise de similaridade entre dois vídeos.
## json_a / json_b: Dictionaries já carregados (use load_json).
## Retorna Dictionary com resultados por grupo de ossos + "_global_similarity_pct".
func compare(json_a: Dictionary, json_b: Dictionary) -> Dictionary:
	var frames_a: Array = json_a.get("frames", []) as Array
	var frames_b: Array = json_b.get("frames", []) as Array

	var video_info_a: Dictionary = json_a.get("video_info", {}) as Dictionary
	var video_info_b: Dictionary = json_b.get("video_info", {}) as Dictionary
	var fps_a: float = float(video_info_a.get("fps", 30.0))
	var fps_b: float = float(video_info_b.get("fps", 30.0))

	var rest_weights_a: PackedFloat64Array = build_rest_weights(frames_a.size(), fps_a)
	var rest_weights_b: PackedFloat64Array = build_rest_weights(frames_b.size(), fps_b)

	var n_common: int = mini(frames_a.size(), frames_b.size())
	# frame_weights = min(wa, wb) para cada frame em comum
	var frame_weights: PackedFloat64Array = PackedFloat64Array()
	frame_weights.resize(n_common)
	for i: int in range(n_common):
		frame_weights[i] = minf(rest_weights_a[i], rest_weights_b[i])

	var results: Dictionary = {}

	# Grupos: [nome, bones, source]
	var groups: Array[Dictionary] = [
		{"name": "Pose (corpo)",  "bones": POSE_BONES,        "source": "pose"},
		{"name": "Mão Esquerda",  "bones": HAND_BONES_LEFT,   "source": "hand_left"},
		{"name": "Mão Direita",   "bones": HAND_BONES_RIGHT,  "source": "hand_right"},
	]

	for group_info: Dictionary in groups:
		var group_name: String = group_info["name"] as String
		var bones: Array[Bone]  = group_info["bones"] as Array[Bone]
		var source: String      = group_info["source"] as String

		var series_a: Dictionary = extract_bone_vectors_per_frame(frames_a, bones, source)
		var series_b: Dictionary = extract_bone_vectors_per_frame(frames_b, bones, source)

		var bone_results: Dictionary = {}

		for bone: Bone in bones:
			var raw_a: Array = series_a[bone.name] as Array
			var raw_b: Array = series_b[bone.name] as Array

			# Série X normalizada para DTW global
			var x_a_raw: PackedFloat64Array = PackedFloat64Array()
			var x_b_raw: PackedFloat64Array = PackedFloat64Array()
			for v: Variant in raw_a:
				var vec: Vector3 = v as Vector3
				x_a_raw.append(vec.x if _is_valid_vec(vec) else NAN)
			for v: Variant in raw_b:
				var vec: Vector3 = v as Vector3
				x_b_raw.append(vec.x if _is_valid_vec(vec) else NAN)

			var sa: PackedFloat64Array = normalize_sequence(x_a_raw)
			var sb: PackedFloat64Array = normalize_sequence(x_b_raw)
			var dtw_dist: float = compute_dtw_distance(sa, sb)

			# Ângulo médio ponderado
			var angle_diffs: PackedFloat64Array = series_to_angle_diff(raw_a, raw_b)
			var mean_angle_diff: float = weighted_mean_angle(angle_diffs, frame_weights)

			var steepness: float = 3.0 if source != "pose" else 2.0
			var similarity_pct: float = angle_to_similarity(mean_angle_diff, steepness) if not is_nan(mean_angle_diff) else NAN

			bone_results[bone.name] = {
				"mean_angle_diff_deg": mean_angle_diff,
				"dtw_distance": dtw_dist,
				"similarity_pct": similarity_pct,
				"weight": BONE_WEIGHTS.get(bone.name, 1.0),
				"angle_series_a": _packed_to_array(sa),
				"angle_series_b": _packed_to_array(sb),
			}

		# Similaridade média ponderada do grupo
		var w_sum: float = 0.0
		var w_total: float = 0.0
		for bone_name: String in bone_results:
			var bd: Dictionary = bone_results[bone_name] as Dictionary
			var sim: float = float(bd.get("similarity_pct", NAN))
			if not is_nan(sim):
				var w: float = BONE_WEIGHTS.get(bone_name, 1.0)
				w_sum   += sim * w
				w_total += w
		var group_similarity: float = (w_sum / w_total) if w_total > 0.0 else NAN

		# ── Análise de fase (segmentação + DTW por segmento) ──
		print("  Detectando fases de gesto: %s..." % group_name)
		var phase_data: Dictionary = analyze_gesture_phases(frames_a, frames_b, source, bones)

		var phase_sim: float = float(phase_data.get("phase_similarity_pct", NAN))
		if not is_nan(phase_sim):
			var phase_weight: float = 1.5
			if not is_nan(group_similarity):
				group_similarity = (group_similarity * w_total + phase_sim * phase_weight) / (w_total + phase_weight)
			else:
				group_similarity = phase_sim

		results[group_name] = {
			"group_similarity_pct": group_similarity,
			"bones": bone_results,
			"phase": phase_data,
		}

	# ── Orientação global da palma ──
	var hand_sides: Array[Dictionary] = [
		{"side": "Left",  "label": "Mão Esquerda"},
		{"side": "Right", "label": "Mão Direita"},
	]

	for hs: Dictionary in hand_sides:
		var side: String  = hs["side"] as String
		var label: String = hs["label"] as String

		var normals_a: Array[Vector3] = extract_palm_normals_per_frame(frames_a, side)
		var normals_b: Array[Vector3] = extract_palm_normals_per_frame(frames_b, side)
		var palm_sim: Dictionary = palm_orientation_similarity(normals_a, normals_b, frame_weights)

		var key: String = "_palm_%s" % side.to_lower()
		results[key] = palm_sim

		var palm_sim_pct: float = float(palm_sim.get("similarity_pct", NAN))
		if not is_nan(palm_sim_pct) and results.has(label):
			var palm_weight: float = 3.5
			var dir_weight: float  = 4.0

			# Direção global da mão — pulso → ponta dedo médio
			var dirs_a: Array[Vector3] = _extract_hand_directions(frames_a, side)
			var dirs_b: Array[Vector3] = _extract_hand_directions(frames_b, side)
			var dir_diffs: PackedFloat64Array = series_to_angle_diff(
				_vec3_array_to_variant(dirs_a), _vec3_array_to_variant(dirs_b))
			var mean_dir_diff: float = weighted_mean_angle(dir_diffs, frame_weights)
			var dir_sim: float = angle_to_similarity(mean_dir_diff, 3.5) if not is_nan(mean_dir_diff) else NAN

			# Recalcular w_sum / w_total a partir dos ossos do grupo
			var group_dict: Dictionary = results[label] as Dictionary
			var bones_dict: Dictionary = group_dict["bones"] as Dictionary
			var old_w_sum: float = 0.0
			var old_w_total: float = 0.0
			for bn: String in bones_dict:
				var bd: Dictionary = bones_dict[bn] as Dictionary
				var s: float = float(bd.get("similarity_pct", NAN))
				if not is_nan(s):
					var w: float = BONE_WEIGHTS.get(bn, 1.0)
					old_w_sum   += s * w
					old_w_total += w

			var new_w_sum:   float = old_w_sum   + palm_sim_pct * palm_weight
			var new_w_total: float = old_w_total + palm_weight

			if not is_nan(dir_sim):
				new_w_sum   += dir_sim * dir_weight
				new_w_total += dir_weight

			group_dict["group_similarity_pct"] = new_w_sum / new_w_total
			group_dict["palm_orientation"] = palm_sim
			group_dict["hand_direction"] = {
				"mean_angle_diff_deg": mean_dir_diff,
				"similarity_pct": dir_sim,
			}

	# ── Similaridade global ponderada ──
	var g_sum: float = 0.0
	var g_total: float = 0.0
	for gname: String in results:
		if not gname.begins_with("_"):
			var gd: Dictionary = results[gname] as Dictionary
			var gsim: float = float(gd.get("group_similarity_pct", NAN))
			if not is_nan(gsim):
				var gw: float = GROUP_WEIGHTS.get(gname, 1.0)
				g_sum   += gsim * gw
				g_total += gw

	results["_global_similarity_pct"] = (g_sum / g_total) if g_total > 0.0 else 0.0
	return results


## Extrai vetores de direção da mão por frame (pulso → ponta dedo médio).
func _extract_hand_directions(frames: Array, side: String) -> Array[Vector3]:
	var dirs: Array[Vector3] = []
	for frame: Variant in frames:
		var f: Dictionary = frame as Dictionary
		var hands: Array = f.get("hands", []) as Array
		var found: bool = false
		for h: Variant in hands:
			var hand: Dictionary = h as Dictionary
			if hand.get("handedness", "") == side:
				var lm: Array = hand.get("landmarks", []) as Array
				dirs.append(hand_direction_vector(lm))
				found = true
				break
		if not found:
			dirs.append(Vector3(INF, INF, INF))
	return dirs


# ─────────────────────────────────────────────
#  SCORE INSTANTÂNEO (FRAME A FRAME)
# ─────────────────────────────────────────────

## Calcula a similaridade instantânea entre dois frames específicos.
## Usado para exibição em tempo real (ex.: vídeo de comparação).
func frame_instant_similarity(frame_a: Dictionary, frame_b: Dictionary) -> Dictionary:
	var scores: Dictionary = {}

	var group_defs: Array[Dictionary] = [
		{"name": "Pose (corpo)",  "bones": POSE_BONES,       "source": "pose"},
		{"name": "Mão Esquerda",  "bones": HAND_BONES_LEFT,  "source": "hand_left"},
		{"name": "Mão Direita",   "bones": HAND_BONES_RIGHT, "source": "hand_right"},
	]

	var global_w_sum: float = 0.0
	var global_w_total: float = 0.0

	for gdef: Dictionary in group_defs:
		var gname: String  = gdef["name"] as String
		var gbones: Array[Bone] = gdef["bones"] as Array[Bone]
		var gsrc: String   = gdef["source"] as String

		var lm_a: Array = _get_landmarks_from_frame(frame_a, gsrc)
		var lm_b: Array = _get_landmarks_from_frame(frame_b, gsrc)

		if lm_a.is_empty() or lm_b.is_empty():
			scores[gname] = null
			continue

		var bone_sims: Array[Dictionary] = []  # [{sim, weight}]

		for bone: Bone in gbones:
			var va: Vector3 = bone_vector(lm_a, bone.idx_parent, bone.idx_child)
			var vb: Vector3 = bone_vector(lm_b, bone.idx_parent, bone.idx_child)
			if _is_valid_vec(va) and _is_valid_vec(vb):
				var ang: float = angle_between(va, vb)
				var steep: float = 3.0 if gsrc != "pose" else 2.0
				bone_sims.append({"sim": angle_to_similarity(ang, steep), "weight": BONE_WEIGHTS.get(bone.name, 1.0)})

		# Normal da palma (peso 3.5)
		if gsrc != "pose":
			var na: Vector3 = palm_normal(lm_a)
			var nb: Vector3 = palm_normal(lm_b)
			if _is_valid_vec(na) and _is_valid_vec(nb):
				bone_sims.append({"sim": angle_to_similarity(angle_between(na, nb), 3.0), "weight": 3.5})

			# Direção global da mão (peso 4.0)
			var da: Vector3 = hand_direction_vector(lm_a)
			var db: Vector3 = hand_direction_vector(lm_b)
			if _is_valid_vec(da) and _is_valid_vec(db):
				bone_sims.append({"sim": angle_to_similarity(angle_between(da, db), 3.5), "weight": 4.0})

		var group_sim: float = NAN
		if bone_sims.size() > 0:
			var ws: float = 0.0
			var wt: float = 0.0
			for bs: Dictionary in bone_sims:
				ws += float(bs["sim"]) * float(bs["weight"])
				wt += float(bs["weight"])
			group_sim = ws / wt

		scores[gname] = group_sim

		if not is_nan(group_sim):
			var gw: float = GROUP_WEIGHTS.get(gname, 1.0)
			global_w_sum   += group_sim * gw
			global_w_total += gw

	scores["_global"] = (global_w_sum / global_w_total) if global_w_total > 0.0 else 0.0
	return scores


# ─────────────────────────────────────────────
#  RELATÓRIO TEXTUAL
# ─────────────────────────────────────────────

## Imprime o relatório de similaridade no Output do Godot.
func print_summary(results: Dictionary, label_a: String, label_b: String) -> void:
	var line: String = "─".repeat(60)
	print("\n%s" % line)
	print("  RELATÓRIO DE SIMILARIDADE DE MOVIMENTO")
	print("  Vídeo A: %s" % label_a)
	print("  Vídeo B: %s" % label_b)
	print(line)

	for group_name: String in results:
		if group_name.begins_with("_"):
			continue

		var group_data: Dictionary = results[group_name] as Dictionary
		var group_sim: float = float(group_data.get("group_similarity_pct", NAN))
		print("\n  %s" % group_name)

		if not is_nan(group_sim):
			var filled: int = int(group_sim / 5.0)
			var bar: String = "█".repeat(filled) + "░".repeat(20 - filled)
			print("  [%s] %.1f%%" % [bar, group_sim])
		else:
			print("  [Sem detecções suficientes]")

		var bones_dict: Dictionary = group_data.get("bones", {}) as Dictionary
		for bone_name: String in bones_dict:
			var bd: Dictionary = bones_dict[bone_name] as Dictionary
			var sim: float  = float(bd.get("similarity_pct", NAN))
			var diff: float = float(bd.get("mean_angle_diff_deg", NAN))
			var dtw_d: float = float(bd.get("dtw_distance", NAN))
			if not is_nan(sim):
				var status: String = "✓" if sim >= 70.0 else ("~" if sim >= 40.0 else "✗")
				print("    %s %-20s sim=%5.1f%%  ΔAngulo=%5.1f°  DTW=%.3f" % [status, bone_name, sim, diff, dtw_d])

		# Orientação da palma
		if group_data.has("palm_orientation"):
			var palm: Dictionary = group_data["palm_orientation"] as Dictionary
			var sim_p: float = float(palm.get("similarity_pct", NAN))
			var diff_p: float = float(palm.get("mean_angle_diff_deg", NAN))
			if not is_nan(sim_p):
				var ori_a: String = str(palm.get("orientation_a", "?"))
				var ori_b: String = str(palm.get("orientation_b", "?"))
				var status: String = "✓" if sim_p >= 70.0 else ("~" if sim_p >= 40.0 else "✗")
				var match_str: String = "✓ mesma direção" if ori_a == ori_b else ("✗ diverge  (%s vs %s)" % [ori_a, ori_b])
				print("    %s %-20s sim=%5.1f%%  ΔAngulo=%5.1f°  orientação: %s" % [status, "[NORMAL PALMA]", sim_p, diff_p, match_str])

		# Direção global da mão
		if group_data.has("hand_direction"):
			var hdir: Dictionary = group_data["hand_direction"] as Dictionary
			var sim_d: float = float(hdir.get("similarity_pct", NAN))
			var diff_d: float = float(hdir.get("mean_angle_diff_deg", NAN))
			if not is_nan(sim_d):
				var status: String = "✓" if sim_d >= 70.0 else ("~" if sim_d >= 40.0 else "✗")
				print("    %s %-20s sim=%5.1f%%  ΔAngulo=%5.1f°" % [status, "[DIREÇÃO MÃO]", sim_d, diff_d])

		# Análise de fase
		if group_data.has("phase"):
			var phase: Dictionary = group_data["phase"] as Dictionary
			var n_a: int   = int(phase.get("n_segments_a", 0))
			var n_b: int   = int(phase.get("n_segments_b", 0))
			var n_p: int   = int(phase.get("n_pairs", 0))
			var p_sim: float = float(phase.get("phase_similarity_pct", NAN))
			print("\n    📊 Fase do gesto: %d segmentos(A) × %d segmentos(B) → %d pares" % [n_a, n_b, n_p])
			if not is_nan(p_sim):
				var status: String = "✓" if p_sim >= 70.0 else ("~" if p_sim >= 40.0 else "✗")
				print("    %s %-20s sim=%5.1f%%" % [status, "[FASE DTW]", p_sim])
				var pairs_arr: Array = phase.get("pairs", []) as Array
				if pairs_arr.size() > 0:
					print("       %-5s %8s  %10s  %10s" % ["Par", "Sim DTW", "Frames A", "Frames B"])
					for p: Variant in pairs_arr:
						var pd: Dictionary = p as Dictionary
						var dur_a: int = int((pd["segment_a"] as Dictionary).get("duration_frames", 0))
						var dur_b: int = int((pd["segment_b"] as Dictionary).get("duration_frames", 0))
						print("       #%-4d %7.1f%%  %8df   %8df" % [int(pd["pair_index"]), float(pd["dtw_similarity_pct"]), dur_a, dur_b])
			else:
				print("    ~ [FASE DTW]             Sem pares detectados")

	print("\n%s" % line)
	print("  SIMILARIDADE GLOBAL: %.1f%%" % float(results.get("_global_similarity_pct", 0.0)))
	print(line)


# ─────────────────────────────────────────────
#  UTILITÁRIOS MATEMÁTICOS INTERNOS
# ─────────────────────────────────────────────

## Substitui NaN por 0 em uma PackedFloat64Array.
func _nan_to_zero(arr: PackedFloat64Array) -> PackedFloat64Array:
	var result: PackedFloat64Array = arr.duplicate()
	for i: int in range(result.size()):
		if is_nan(result[i]):
			result[i] = 0.0
	return result


## Média simples de uma PackedFloat64Array.
func _mean_packed(arr: PackedFloat64Array) -> float:
	if arr.size() == 0:
		return 0.0
	var s: float = 0.0
	for v: float in arr:
		s += v
	return s / float(arr.size())


## Média ponderada de dois arrays de mesmo tamanho.
func _weighted_mean(values: PackedFloat64Array, weights: PackedFloat64Array) -> float:
	var w_sum: float = 0.0
	var w_total: float = 0.0
	var n: int = mini(values.size(), weights.size())
	for i: int in range(n):
		w_sum   += values[i] * weights[i]
		w_total += weights[i]
	return w_sum / w_total if w_total > 0.0 else 0.0


## Mediana de uma PackedFloat64Array.
func _median_packed(arr: PackedFloat64Array) -> float:
	if arr.size() == 0:
		return 0.0
	var sorted_arr: PackedFloat64Array = arr.duplicate()
	# Ordenação por inserção (suficiente para arrays pequenos de velocidades)
	for i: int in range(1, sorted_arr.size()):
		var key: float = sorted_arr[i]
		var j: int = i - 1
		while j >= 0 and sorted_arr[j] > key:
			sorted_arr[j + 1] = sorted_arr[j]
			j -= 1
		sorted_arr[j + 1] = key
	var mid: int = sorted_arr.size() / 2
	if sorted_arr.size() % 2 == 0:
		return (sorted_arr[mid - 1] + sorted_arr[mid]) / 2.0
	return sorted_arr[mid]


## Converte PackedFloat64Array para Array (para serialização JSON).
func _packed_to_array(arr: PackedFloat64Array) -> Array:
	var result: Array = []
	result.resize(arr.size())
	for i: int in range(arr.size()):
		result[i] = arr[i]
	return result


## Converte Array[Vector3] para Array[Variant] para funções que aceitam Array genérico.
func _vec3_array_to_variant(arr: Array[Vector3]) -> Array:
	var result: Array = []
	result.resize(arr.size())
	for i: int in range(arr.size()):
		result[i] = arr[i]
	return result
