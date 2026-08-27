extends GutTest
## Testes do MotionComparatorValidator: fps, shape do doc, caminhos de
## falha e espelhamento para sinalizadores canhotos.

var v: MotionComparatorValidator


func before_each() -> void:
	v = MotionComparatorValidator.new()


# ---------- _estimate_fps ----------

func test_estimate_fps_from_timestamps() -> void:
	var frames: Array = []
	for i in range(31):
		frames.append({"timestamp_ms": i * 33})   # ~30 fps
	assert_almost_eq(v._estimate_fps(frames), 30.0, 0.5)


func test_estimate_fps_fallback_too_few_frames() -> void:
	assert_eq(v._estimate_fps([]), 30.0)
	assert_eq(v._estimate_fps([{"timestamp_ms": 0}]), 30.0)


func test_estimate_fps_fallback_zero_duration() -> void:
	var frames := [{"timestamp_ms": 100}, {"timestamp_ms": 100}]
	assert_eq(v._estimate_fps(frames), 30.0)


# ---------- _ensure_doc_shape ----------

func test_ensure_doc_shape_fills_missing_video_info() -> void:
	var frames: Array = []
	for i in range(11):
		frames.append({"timestamp_ms": i * 100})   # 10 fps
	var doc: Dictionary = v._ensure_doc_shape({"frames": frames})
	var info: Dictionary = doc["video_info"]
	assert_almost_eq(float(info["fps"]), 10.0, 0.1)
	assert_eq(int(info["total_frames"]), 11)


func test_ensure_doc_shape_preserves_existing_info() -> void:
	var doc: Dictionary = v._ensure_doc_shape({
		"video_info": {"fps": 24.0, "total_frames": 5},
		"frames": [],
	})
	assert_eq(float((doc["video_info"] as Dictionary)["fps"]), 24.0)


# ---------- caminhos de falha ----------

func test_validate_empty_payload_fails() -> void:
	var result: Dictionary = v.validate({}, {"frames": [{}]})
	assert_false(bool(result["ok"]))
	assert_eq(float(result["precision"]), 0.0)


func test_validate_empty_frames_fails() -> void:
	var result: Dictionary = v.validate({"frames": []}, {"frames": [{}]})
	assert_false(bool(result["ok"]))


# ---------- espelhamento ----------

func test_mirror_doc_flips_x_and_swaps_handedness() -> void:
	var doc := CaptureDocFactory.make_doc(4, 30.0, false, true)
	var mirrored: Dictionary = v._mirror_doc(doc)

	var f0: Dictionary = (doc["frames"] as Array)[0]
	var m0: Dictionary = (mirrored["frames"] as Array)[0]

	var hand: Dictionary = (f0["hands"] as Array)[0]
	var mhand: Dictionary = (m0["hands"] as Array)[0]
	assert_eq(String(mhand["handedness"]), "Left", "Right vira Left")

	var lm0: Dictionary = (hand["landmarks"] as Array)[0]
	var mlm0: Dictionary = (mhand["landmarks"] as Array)[0]
	assert_almost_eq(float(mlm0["x"]), 1.0 - float(lm0["x"]), 0.0001, "x espelhado")
	assert_almost_eq(float(mlm0["y"]), float(lm0["y"]), 0.0001, "y intacto")


func test_mirror_doc_swaps_paired_pose_ids() -> void:
	var doc := CaptureDocFactory.make_doc(2, 30.0, false, true)
	var mirrored: Dictionary = v._mirror_doc(doc)

	var pose: Array = (((doc["frames"] as Array)[0] as Dictionary)["pose"] as Array)
	var mpose: Array = (((mirrored["frames"] as Array)[0] as Dictionary)["pose"] as Array)
	var lms: Array = (pose[0] as Dictionary)["landmarks"]
	var mlms: Array = (mpose[0] as Dictionary)["landmarks"]

	# O ombro esquerdo (id 11) espelhado deve reaparecer como id 12 com x=1-x.
	var original_11 := _find_lm(lms, 11)
	var mirrored_12 := _find_lm(mlms, 12)
	assert_almost_eq(float(mirrored_12["x"]), 1.0 - float(original_11["x"]), 0.0001)


func test_mirror_doc_does_not_mutate_original() -> void:
	var doc := CaptureDocFactory.make_doc(2, 30.0, false, true)
	var hand_before: Dictionary = ((doc["frames"] as Array)[0] as Dictionary)["hands"][0]
	var x_before := float((hand_before["landmarks"] as Array)[0]["x"])

	v._mirror_doc(doc)

	var hand_after: Dictionary = ((doc["frames"] as Array)[0] as Dictionary)["hands"][0]
	assert_eq(String(hand_after["handedness"]), "Right", "original intacto")
	assert_almost_eq(float((hand_after["landmarks"] as Array)[0]["x"]), x_before, 0.0000001)


func test_left_handed_signer_recovered_by_mirror_retry() -> void:
	# Um canhoto executa o espelho exato do gabarito. A comparação direta
	# pontua baixo; o retry espelhado deve recuperar ~100%.
	var ref := CaptureDocFactory.make_doc(60, 30.0, true, true)
	var user: Dictionary = v._mirror_doc(ref)

	var result: Dictionary = v.validate(user, ref)
	gut.p("canhoto: precision=%f mirrored=%s" % [float(result["precision"]), result["mirrored"]])
	assert_true(bool(result["ok"]))
	assert_true(bool(result["mirrored"]), "retry espelhado deve ter sido usado")
	assert_gt(float(result["precision"]), 0.9, "espelho do gabarito = execução perfeita")


# ---------- validação do formato do gabarito ----------

func test_valid_reference_passes_schema() -> void:
	var doc := CaptureDocFactory.make_doc(10, 30.0, true, true)
	assert_eq(v.validate_reference_schema(doc), "", "gabarito bem formado passa")


func test_reference_without_pose_is_rejected() -> void:
	# Caso real: uma ferramenta offline que só rode o hand_landmarker
	# produziria isto, e a LOCALIZAÇÃO do sinal deixaria de ser avaliada
	# sem ninguém perceber.
	var doc := CaptureDocFactory.make_doc(10, 30.0, true, true)
	for frame: Variant in doc["frames"] as Array:
		(frame as Dictionary)["pose"] = []

	var error := v.validate_reference_schema(doc)
	assert_true(error.contains("pose"), "erro deve citar a pose ausente: '%s'" % error)


func test_reference_with_truncated_pose_is_rejected() -> void:
	var doc := CaptureDocFactory.make_doc(10, 30.0, true, true)
	var first: Dictionary = (doc["frames"] as Array)[0]
	var pose: Dictionary = (first["pose"] as Array)[0]
	pose["landmarks"] = (pose["landmarks"] as Array).slice(0, 10)

	assert_true(v.validate_reference_schema(doc).contains("10 landmarks"))


func test_reference_with_bad_handedness_is_rejected() -> void:
	var doc := CaptureDocFactory.make_doc(10, 30.0, true, true)
	var first: Dictionary = (doc["frames"] as Array)[0]
	((first["hands"] as Array)[0] as Dictionary)["handedness"] = "Unknown"

	assert_true(v.validate_reference_schema(doc).contains("handedness"))


func test_reference_with_truncated_hand_is_rejected() -> void:
	var doc := CaptureDocFactory.make_doc(10, 30.0, true, true)
	var first: Dictionary = (doc["frames"] as Array)[0]
	var hand: Dictionary = (first["hands"] as Array)[0]
	hand["landmarks"] = (hand["landmarks"] as Array).slice(0, 5)

	assert_true(v.validate_reference_schema(doc).contains("5 landmarks"))


func test_validate_fails_loudly_on_bad_reference() -> void:
	# O ponto do item 14: gabarito inválido tem que virar erro visível,
	# não uma nota confiantemente errada.
	var user := CaptureDocFactory.make_doc(20, 30.0, true, true)
	var broken := CaptureDocFactory.make_doc(20, 30.0, true, true)
	for frame: Variant in broken["frames"] as Array:
		(frame as Dictionary)["pose"] = []

	var result: Dictionary = v.validate(user, broken)
	assert_false(bool(result["ok"]))
	assert_eq(float(result["precision"]), 0.0)
	assert_true(String(result["error"]).contains("Gabarito inválido"))


func test_zero_fps_is_recomputed_from_timestamps() -> void:
	# fps=0 passava direto e degenerava os pesos de repouso.
	var doc := CaptureDocFactory.make_doc(13, 12.0, true, true)
	(doc["video_info"] as Dictionary)["fps"] = 0.0

	var shaped: Dictionary = v._ensure_doc_shape(doc)
	assert_almost_eq(float((shaped["video_info"] as Dictionary)["fps"]), 12.0, 0.5)


func _find_lm(lms: Array, id: int) -> Dictionary:
	for lm: Variant in lms:
		if int((lm as Dictionary).get("id", -1)) == id:
			return lm
	return {}
