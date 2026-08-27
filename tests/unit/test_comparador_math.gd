extends GutTest
## Testes unitários das funções matemáticas puras do MotionComparator.
## Pinam o comportamento atual antes de qualquer mudança no núcleo.

var c: MotionComparator


func before_each() -> void:
	c = MotionComparator.new()


# ---------- angle_between ----------

func test_angle_between_orthogonal_is_90() -> void:
	assert_almost_eq(c.angle_between(Vector3(1, 0, 0), Vector3(0, 1, 0)), 90.0, 0.001)


func test_angle_between_parallel_is_0() -> void:
	assert_almost_eq(c.angle_between(Vector3(1, 0, 0), Vector3(1, 0, 0)), 0.0, 0.001)


func test_angle_between_opposite_is_180() -> void:
	assert_almost_eq(c.angle_between(Vector3(1, 0, 0), Vector3(-1, 0, 0)), 180.0, 0.001)


func test_angle_between_clamps_dot_product() -> void:
	# Vetores quase paralelos com erro numérico não podem gerar NaN.
	var v := Vector3(1.0000001, 0, 0)
	assert_false(is_nan(c.angle_between(v, v)))


# ---------- angle_to_similarity ----------

func test_similarity_of_zero_angle_is_100() -> void:
	assert_almost_eq(c.angle_to_similarity(0.0, 3.0), 100.0, 0.001)


func test_similarity_of_180_is_0() -> void:
	assert_almost_eq(c.angle_to_similarity(180.0, 3.0), 0.0, 0.001)


func test_similarity_30deg_steepness3_pinned() -> void:
	# 100 * (1 - 30/180)^3 = 57.87 — valor citado no relatório de revisão.
	assert_almost_eq(c.angle_to_similarity(30.0, 3.0), 57.87, 0.01)


func test_similarity_30deg_steepness2_pinned() -> void:
	# 100 * (5/6)^2 = 69.44
	assert_almost_eq(c.angle_to_similarity(30.0, 2.0), 69.44, 0.01)


func test_similarity_monotonically_decreasing() -> void:
	var prev := 101.0
	for angle: float in [0.0, 15.0, 30.0, 60.0, 90.0, 120.0, 180.0]:
		var s: float = c.angle_to_similarity(angle, 3.0)
		assert_lt(s, prev, "similaridade deve cair com o ângulo")
		prev = s


# ---------- get_landmark / bone_vector / palm_normal ----------

func _lm(id: int, x: float, y: float, z: float = 0.0) -> Dictionary:
	return {"id": id, "x": x, "y": y, "z": z}


func test_get_landmark_found_and_missing() -> void:
	var lms := [_lm(0, 0.1, 0.2), _lm(5, 0.5, 0.6)]
	assert_eq(c.get_landmark(lms, 5), Vector3(0.5, 0.6, 0.0))
	assert_false(c._is_valid_lm(c.get_landmark(lms, 3)), "id ausente vira sentinela INF")


func test_bone_vector_is_normalized() -> void:
	var lms := [_lm(0, 0.0, 0.0), _lm(1, 0.3, 0.4)]
	var v: Vector3 = c.bone_vector(lms, 0, 1)
	assert_almost_eq(v.length(), 1.0, 0.0001)
	assert_almost_eq(v.x, 0.6, 0.0001)
	assert_almost_eq(v.y, 0.8, 0.0001)


func test_bone_vector_degenerate_is_invalid() -> void:
	var lms := [_lm(0, 0.5, 0.5), _lm(1, 0.5, 0.5)]
	assert_false(c._is_valid_vec(c.bone_vector(lms, 0, 1)), "osso de comprimento zero é inválido")


func test_palm_normal_unit_and_invalid_when_missing() -> void:
	var lms := [_lm(0, 0.5, 0.5), _lm(5, 0.6, 0.5), _lm(17, 0.5, 0.4)]
	var n: Vector3 = c.palm_normal(lms)
	assert_almost_eq(n.length(), 1.0, 0.0001)
	assert_false(c._is_valid_vec(c.palm_normal([_lm(0, 0.5, 0.5)])))


# ---------- build_rest_weights ----------

func test_rest_weights_middle_is_full_and_edges_low() -> void:
	var w: PackedFloat64Array = c.build_rest_weights(90, 30.0, 1.0, 0.1)
	assert_almost_eq(w[0], 0.1, 0.0001, "borda inicial = rest_weight")
	assert_almost_eq(w[45], 1.0, 0.0001, "meio = peso cheio")
	assert_almost_eq(w[89], 0.1, 0.0001, "borda final = rest_weight")


func test_rest_weights_fps_zero_is_all_ones() -> void:
	var w: PackedFloat64Array = c.build_rest_weights(10, 0.0)
	for i in range(10):
		assert_almost_eq(w[i], 1.0, 0.0001)


# ---------- smooth_signal / segmentação ----------

func test_smooth_signal_constant_unchanged() -> void:
	var s := PackedFloat64Array()
	s.resize(20)
	s.fill(3.0)
	var out: PackedFloat64Array = c.smooth_signal(s)
	assert_almost_eq(out[10], 3.0, 0.0001)


func test_detect_segments_burst_over_noise_floor() -> void:
	# Ruído 0.003 (abaixo do piso 0.01) + burst 0.05 no meio → 1 segmento.
	var v := PackedFloat64Array()
	v.resize(60)
	v.fill(0.003)
	for i in range(25, 40):
		v[i] = 0.05
	var segs: Array[Dictionary] = c.detect_gesture_segments(v)
	assert_eq(segs.size(), 1, "um burst claro = um segmento")
	assert_between(int(segs[0]["start"]), 20, 28)


func test_detect_segments_flat_noise_is_empty() -> void:
	var v := PackedFloat64Array()
	v.resize(60)
	v.fill(0.003)
	assert_eq(c.detect_gesture_segments(v).size(), 0, "só ruído sub-piso = sem segmentos")


func test_detect_segments_empty_input() -> void:
	assert_eq(c.detect_gesture_segments(PackedFloat64Array()).size(), 0)


# ---------- utilitários ----------

func test_median_odd_and_even() -> void:
	assert_almost_eq(c._median_packed(PackedFloat64Array([3.0, 1.0, 2.0])), 2.0, 0.0001)
	assert_almost_eq(c._median_packed(PackedFloat64Array([4.0, 1.0, 3.0, 2.0])), 2.5, 0.0001)
	assert_eq(c._median_packed(PackedFloat64Array()), 0.0)


func test_mean_packed() -> void:
	assert_almost_eq(c._mean_packed(PackedFloat64Array([2.0, 4.0])), 3.0, 0.0001)
	assert_eq(c._mean_packed(PackedFloat64Array()), 0.0)


func test_sum_packed_is_total_travel() -> void:
	# Sobre velocidades, a soma é o comprimento percorrido — base do
	# termo de quantidade de movimento.
	assert_almost_eq(c._sum_packed(PackedFloat64Array([0.1, 0.2, 0.3])), 0.6, 0.0001)
	assert_eq(c._sum_packed(PackedFloat64Array()), 0.0)
