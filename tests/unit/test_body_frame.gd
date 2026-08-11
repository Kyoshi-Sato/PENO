extends GutTest
## Normalização pelo referencial do tronco.
##
## O teste central é `test_same_gesture_two_aspect_ratios_...`: o MESMO
## gesto físico, "gravado" em retrato e em paisagem, precisa produzir as
## mesmas coordenadas — é exatamente a situação real do projeto (captura
## do celular 9:16 contra gabarito em mp4 16:9).

## Corpo em unidades físicas arbitrárias (y cresce para baixo, como na
## imagem): ombros, quadris e um osso da mão apontando a 45°.
const PHYSICAL := {
	11: Vector2(20.0, 0.0),      # ombro esquerdo
	12: Vector2(-20.0, 0.0),     # ombro direito
	23: Vector2(15.0, 40.0),     # quadril esquerdo
	24: Vector2(-15.0, 40.0),    # quadril direito
	30: Vector2(0.0, 20.0),      # início do osso de teste
	31: Vector2(10.0, 10.0),     # fim: 45° acima e à direita
}


## Projeta o corpo físico numa imagem WxH, com deslocamento e escala
## próprios — simula uma gravação.
func _project(
		width: float, height: float,
		offset: Vector2, scale: float,
		rotation_rad: float = 0.0) -> Array:
	var landmarks: Array = []
	for id: int in PHYSICAL:
		var p: Vector2 = (PHYSICAL[id] as Vector2).rotated(rotation_rad) * scale + offset
		landmarks.append({ "id": id, "x": p.x / width, "y": p.y / height, "z": 0.0 })
	return landmarks


func _frame(landmarks: Array) -> Dictionary:
	return { "frame": 0, "timestamp_ms": 0, "hands": [], "pose": [{ "landmarks": landmarks }] }


func _body_coords(landmarks: Array) -> Dictionary:
	var basis: Dictionary = BodyFrame.compute_basis(landmarks)
	assert_true(basis.get("valid", false), "base do tronco deve ser válida")
	var out: Dictionary = {}
	for lm: Variant in landmarks:
		var d: Dictionary = lm as Dictionary
		out[int(d["id"])] = BodyFrame.to_body(
			Vector3(float(d["x"]), float(d["y"]), float(d["z"])), basis)
	return out


func _bone_angle_in_image(landmarks: Array) -> float:
	# Ângulo do osso 30->31 no espaço da imagem, em graus.
	var by_id: Dictionary = {}
	for lm: Variant in landmarks:
		by_id[int((lm as Dictionary)["id"])] = lm
	var a: Dictionary = by_id[30]
	var b: Dictionary = by_id[31]
	return rad_to_deg(atan2(float(b["y"]) - float(a["y"]), float(b["x"]) - float(a["x"])))


# ---------- o teste que importa ----------

func test_same_gesture_two_aspect_ratios_matches_after_normalization() -> void:
	# Paisagem 1920x1080 (gabarito em mp4) e retrato 1080x1920 (celular),
	# com posições e distâncias diferentes.
	var landscape := _project(1920.0, 1080.0, Vector2(960.0, 300.0), 10.0)
	var portrait := _project(1080.0, 1920.0, Vector2(540.0, 700.0), 6.0)

	# Primeiro, o problema: no espaço da imagem o mesmo osso físico tem
	# ângulos muito diferentes.
	var angle_landscape := _bone_angle_in_image(landscape)
	var angle_portrait := _bone_angle_in_image(portrait)
	var artifact: float = absf(angle_landscape - angle_portrait)
	gut.p("ângulo do osso na imagem: paisagem=%.1f° retrato=%.1f° (artefato=%.1f°)"
		% [angle_landscape, angle_portrait, artifact])
	assert_gt(artifact, 20.0,
		"sem normalizar, o formato do vídeo distorce o ângulo (é o bug)")

	# Depois, a correção: em coordenadas de tronco as duas gravações
	# coincidem.
	var coords_landscape := _body_coords(landscape)
	var coords_portrait := _body_coords(portrait)
	for id: int in PHYSICAL:
		var a: Vector3 = coords_landscape[id]
		var b: Vector3 = coords_portrait[id]
		assert_almost_eq(a.x, b.x, 0.0001, "coord x do landmark %d" % id)
		assert_almost_eq(a.y, b.y, 0.0001, "coord y do landmark %d" % id)


# ---------- invariâncias ----------

func test_invariant_to_translation_and_scale() -> void:
	var near := _project(1280.0, 720.0, Vector2(400.0, 200.0), 8.0)
	var far := _project(1280.0, 720.0, Vector2(900.0, 400.0), 3.0)
	var a := _body_coords(near)
	var b := _body_coords(far)
	for id: int in PHYSICAL:
		assert_almost_eq((a[id] as Vector3).x, (b[id] as Vector3).x, 0.0001)
		assert_almost_eq((a[id] as Vector3).y, (b[id] as Vector3).y, 0.0001)


func test_invariant_to_camera_roll() -> void:
	# Celular inclinado 20°: a base do tronco gira junto.
	var upright := _project(1080.0, 1080.0, Vector2(540.0, 400.0), 8.0)
	var tilted := _project(1080.0, 1080.0, Vector2(540.0, 400.0), 8.0, deg_to_rad(20.0))
	var a := _body_coords(upright)
	var b := _body_coords(tilted)
	for id: int in PHYSICAL:
		assert_almost_eq((a[id] as Vector3).x, (b[id] as Vector3).x, 0.0001)
		assert_almost_eq((a[id] as Vector3).y, (b[id] as Vector3).y, 0.0001)


func test_torso_landmarks_land_on_canonical_positions() -> void:
	# Sanidade do referencial: origem no meio dos quadris, ombros a y=1.
	var coords := _body_coords(_project(1920.0, 1080.0, Vector2(960.0, 300.0), 10.0))
	var mid_hip: Vector3 = ((coords[23] as Vector3) + (coords[24] as Vector3)) * 0.5
	var mid_shoulder: Vector3 = ((coords[11] as Vector3) + (coords[12] as Vector3)) * 0.5
	assert_almost_eq(mid_hip.x, 0.0, 0.0001, "origem = meio dos quadris")
	assert_almost_eq(mid_hip.y, 0.0, 0.0001)
	assert_almost_eq(mid_shoulder.y, 1.0, 0.0001, "meio dos ombros a uma altura de tronco")
	assert_almost_eq((coords[11] as Vector3).x, 0.5, 0.0001, "ombro a meia largura")


# ---------- casos degenerados ----------

func test_missing_torso_landmarks_is_invalid() -> void:
	var partial: Array = [
		{ "id": 11, "x": 0.6, "y": 0.3, "z": 0.0 },
		{ "id": 12, "x": 0.4, "y": 0.3, "z": 0.0 },
	]
	assert_false(BodyFrame.compute_basis(partial).get("valid", false),
		"sem quadris não há base")


func test_collinear_torso_is_invalid() -> void:
	# Ombros e quadris na mesma linha: determinante ~0.
	var collinear: Array = [
		{ "id": 11, "x": 0.6, "y": 0.5, "z": 0.0 },
		{ "id": 12, "x": 0.4, "y": 0.5, "z": 0.0 },
		{ "id": 23, "x": 0.6, "y": 0.5, "z": 0.0 },
		{ "id": 24, "x": 0.4, "y": 0.5, "z": 0.0 },
	]
	assert_false(BodyFrame.compute_basis(collinear).get("valid", false))


func test_coverage_and_usable_basis() -> void:
	var good := _frame(_project(1280.0, 720.0, Vector2(400.0, 200.0), 8.0))
	var empty := { "frame": 1, "timestamp_ms": 100, "hands": [], "pose": [] }

	assert_almost_eq(BodyFrame.coverage([good, good, good, good]), 1.0, 0.001)
	assert_almost_eq(BodyFrame.coverage([good, empty]), 0.5, 0.001)
	assert_eq(BodyFrame.coverage([]), 0.0)

	assert_true(BodyFrame.has_usable_basis([good, good, empty]))
	assert_false(BodyFrame.has_usable_basis([good, empty, empty]))


# ---------- normalização de sequências ----------

func test_normalize_frames_does_not_mutate_input() -> void:
	var landmarks := _project(1280.0, 720.0, Vector2(400.0, 200.0), 8.0)
	var frames: Array = [_frame(landmarks)]
	var original_x: float = float((landmarks[0] as Dictionary)["x"])

	BodyFrame.normalize_frames(frames)

	var after: Dictionary = ((((frames[0] as Dictionary)["pose"] as Array)[0]
		as Dictionary)["landmarks"] as Array)[0]
	assert_almost_eq(float(after["x"]), original_x, 0.0000001, "entrada intacta")


func test_frames_without_basis_drop_landmarks() -> void:
	# Sem pose e passado o tempo de reaproveitamento, os landmarks do
	# frame são descartados (viram "não detectado").
	var good := _frame(_project(1280.0, 720.0, Vector2(400.0, 200.0), 8.0))
	var stale: Dictionary = {
		"frame": 1, "timestamp_ms": 5000, "pose": [],
		"hands": [{ "handedness": "Right", "landmarks": [
			{ "id": 0, "x": 0.5, "y": 0.5, "z": 0.0 }] }],
	}

	var out: Array = BodyFrame.normalize_frames([good, stale])
	assert_eq(((out[1] as Dictionary)["hands"] as Array).size(), 0,
		"base vencida não pode normalizar mãos")


func test_recent_pose_gap_carries_basis_forward() -> void:
	# A pose pisca por 2 quadros mas as mãos continuam detectadas: a base
	# recente é reaproveitada em vez de descartar a mão.
	var good := _frame(_project(1280.0, 720.0, Vector2(400.0, 200.0), 8.0))
	var blink: Dictionary = {
		"frame": 1, "timestamp_ms": 80, "pose": [],
		"hands": [{ "handedness": "Right", "landmarks": [
			{ "id": 0, "x": 0.5, "y": 0.5, "z": 0.0 }] }],
	}

	var out: Array = BodyFrame.normalize_frames([good, blink])
	assert_eq(((out[1] as Dictionary)["hands"] as Array).size(), 1,
		"lacuna curta reaproveita a última base válida")
