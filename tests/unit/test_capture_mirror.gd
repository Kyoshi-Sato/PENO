extends GutTest
## Canonicalização de capturas espelhadas (câmera frontal → convenção
## dos gabaritos). A matemática fina é coberta pelos testes do
## MotionWrapper (que delega pra cá); aqui ficam as propriedades extra.


func test_double_mirror_is_identity() -> void:
	var doc := CaptureDocFactory.make_doc(3, 30.0, true, true)
	var twice: Dictionary = CaptureMirror.mirror_doc(CaptureMirror.mirror_doc(doc))

	var f0: Dictionary = (doc["frames"] as Array)[0]
	var t0: Dictionary = (twice["frames"] as Array)[0]

	var hand: Dictionary = (f0["hands"] as Array)[0]
	var thand: Dictionary = (t0["hands"] as Array)[0]
	assert_eq(String(thand["handedness"]), String(hand["handedness"]))
	assert_almost_eq(
		float((thand["landmarks"] as Array)[0]["x"]),
		float((hand["landmarks"] as Array)[0]["x"]), 0.0000001)

	var pose_lms: Array = ((f0["pose"] as Array)[0] as Dictionary)["landmarks"]
	var tpose_lms: Array = ((t0["pose"] as Array)[0] as Dictionary)["landmarks"]
	for i in range(pose_lms.size()):
		assert_eq(int(tpose_lms[i]["id"]), int(pose_lms[i]["id"]))


func test_mirror_frames_used_by_export_path() -> void:
	# A exportação canonicaliza só a lista de frames (sem video_info).
	var doc := CaptureDocFactory.make_doc(2, 30.0, false, true)
	var frames: Array = doc["frames"]
	var mirrored: Array = CaptureMirror.mirror_frames(frames)

	assert_eq(mirrored.size(), frames.size())
	var hand: Dictionary = ((mirrored[0] as Dictionary)["hands"] as Array)[0]
	assert_eq(String(hand["handedness"]), "Left", "Right vira Left")
	# Original intacto
	var orig_hand: Dictionary = ((frames[0] as Dictionary)["hands"] as Array)[0]
	assert_eq(String(orig_hand["handedness"]), "Right")


func test_pose_swap_map_is_a_bijection() -> void:
	# Cada id precisa mapear de volta para si mesmo — um par quebrado
	# duplicaria um landmark e apagaria outro no espelhamento.
	for id: int in CaptureMirror.POSE_MIRROR_SWAP:
		var target: int = CaptureMirror.POSE_MIRROR_SWAP[id]
		assert_eq(int(CaptureMirror.POSE_MIRROR_SWAP.get(target, -1)), id,
			"par %d<->%d deve ser simétrico" % [id, target])