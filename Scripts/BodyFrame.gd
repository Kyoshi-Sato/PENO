class_name BodyFrame
extends RefCounted
## Normalização espacial: reexpressa todos os landmarks num referencial
## afim construído a partir do tronco do próprio sinalizador.
##
## POR QUE
## O MediaPipe entrega coordenadas normalizadas pela imagem: x = px/W e
## y = px/H. Isso ANISOTROPIZA o espaço — o mesmo vetor físico produz
## ângulos diferentes conforme a proporção do vídeo. Concretamente, um
## gesto físico a 45° vira -29.4° num vídeo retrato 1080x1920 e -60.6°
## num paisagem 1920x1080: 31° de erro puro de formato, entre a captura
## do celular e o gabarito gravado em mp4. Com a curva de similaridade
## em vigor, 31° uniformes já derrubam a nota para ~58%.
##
## COMO
## Do tronco tiramos uma base afim por frame:
##   origem = meio dos quadris (23, 24)
##   e1     = ombro esquerdo (11) - ombro direito (12)
##   e2     = meio dos ombros - origem
## e escrevemos cada ponto p como p = origem + a*e1 + b*e2, guardando
## (a, b) no lugar de (x, y).
##
## POR QUE ISSO CANCELA A ANISOTROPIA (prova)
## A imagem aplica a todos os pontos a mesma matriz diagonal
## D = diag(1/W, 1/H). Se v é um vetor físico e E1, E2 a base física do
## tronco, o que medimos é Dv, DE1, DE2. Resolver Dv = a·DE1 + b·DE2
## equivale a v = a·E1 + b·E2, porque D é inversível e some dos dois
## lados. Logo (a, b) são as coordenadas do vetor FÍSICO na base FÍSICA
## do tronco — independentes de W e H. De quebra, some também a
## translação, a distância até a câmera e a rotação no plano (inclinação
## do celular), porque a base acompanha o corpo.
##
## O QUE SOBRA
## Dependência das proporções corporais (razão largura de ombros /
## altura do tronco), que varia ~15% entre adultos — uma ordem de
## grandeza menor que os 31° do artefato de formato.

const LM_SHOULDER_LEFT := 11
const LM_SHOULDER_RIGHT := 12
const LM_HIP_LEFT := 23
const LM_HIP_RIGHT := 24

## Abaixo disso a base é degenerada (sinalizador de perfil, tronco
## ocluído) e o frame é descartado.
const MIN_DETERMINANT := 1e-6
## Piso do divisor de z, para não explodir quando os ombros aparecem
## quase alinhados com a profundidade.
const MIN_Z_SCALE := 1e-3
## Fração mínima de frames com base válida para a normalização valer a
## pena — abaixo disso é melhor não normalizar do que normalizar metade.
const MIN_COVERAGE := 0.5
## Por quanto tempo a última base válida é reaproveitada quando a pose
## some (as mãos costumam continuar detectadas).
const BASIS_CARRY_MS := 500.0

const INVALID_VEC := Vector3(INF, INF, INF)


## Base do tronco a partir dos landmarks de pose de um frame.
## Retorna { valid, origin, e1, e2, det, z_scale }.
static func compute_basis(pose_landmarks: Array) -> Dictionary:
	var shoulder_left: Vector3 = _landmark(pose_landmarks, LM_SHOULDER_LEFT)
	var shoulder_right: Vector3 = _landmark(pose_landmarks, LM_SHOULDER_RIGHT)
	var hip_left: Vector3 = _landmark(pose_landmarks, LM_HIP_LEFT)
	var hip_right: Vector3 = _landmark(pose_landmarks, LM_HIP_RIGHT)

	for v: Vector3 in [shoulder_left, shoulder_right, hip_left, hip_right]:
		if v.x == INF:
			return { "valid": false }

	var origin: Vector3 = (hip_left + hip_right) * 0.5
	var e1: Vector3 = shoulder_left - shoulder_right
	var e2: Vector3 = (shoulder_left + shoulder_right) * 0.5 - origin

	var det: float = e1.x * e2.y - e2.x * e1.y
	if absf(det) < MIN_DETERMINANT:
		return { "valid": false }

	return {
		"valid": true,
		"origin": origin,
		"e1": e1,
		"e2": e2,
		"det": det,
		# z do MediaPipe vem na escala de x, então dividir pela largura de
		# ombros medida em x mantém a invariância de formato.
		"z_scale": maxf(absf(e1.x), MIN_Z_SCALE),
	}


## Converte um ponto para as coordenadas do tronco.
static func to_body(p: Vector3, basis: Dictionary) -> Vector3:
	var origin: Vector3 = basis["origin"]
	var e1: Vector3 = basis["e1"]
	var e2: Vector3 = basis["e2"]
	var det: float = basis["det"]

	var dx: float = p.x - origin.x
	var dy: float = p.y - origin.y

	return Vector3(
		(dx * e2.y - dy * e2.x) / det,
		(dy * e1.x - dx * e1.y) / det,
		(p.z - origin.z) / float(basis["z_scale"])
	)


## Fração de frames com base de tronco utilizável.
static func coverage(frames: Array) -> float:
	if frames.is_empty():
		return 0.0
	var valid: int = 0
	for frame: Variant in frames:
		if compute_basis(_pose_landmarks(frame as Dictionary)).get("valid", false):
			valid += 1
	return float(valid) / float(frames.size())


## A normalização só deve ser aplicada se AMBOS os lados puderem ser
## normalizados — normalizar um lado só destruiria a comparação.
static func has_usable_basis(frames: Array) -> bool:
	return coverage(frames) >= MIN_COVERAGE


## Reexpressa pose e mãos no referencial do tronco. Não muta a entrada.
## Frames sem base (nem por reaproveitamento) têm seus landmarks
## descartados — viram "não detectado", que o comparador já trata.
static func normalize_frames(frames: Array) -> Array:
	var out: Array = []
	var last_basis: Dictionary = {}
	var last_basis_ms: float = NAN

	for frame: Variant in frames:
		var f: Dictionary = (frame as Dictionary).duplicate()
		var ts: float = float(f.get("timestamp_ms", 0))

		var basis: Dictionary = compute_basis(_pose_landmarks(f))
		if basis.get("valid", false):
			last_basis = basis
			last_basis_ms = ts
		elif not last_basis.is_empty() and not is_nan(last_basis_ms) \
				and (ts - last_basis_ms) <= BASIS_CARRY_MS:
			basis = last_basis   # pose piscou; as mãos ainda são comparáveis

		if not basis.get("valid", false):
			f["pose"] = []
			f["hands"] = []
			out.append(f)
			continue

		var pose_out: Array = []
		for p: Variant in f.get("pose", []) as Array:
			var entry: Dictionary = (p as Dictionary).duplicate()
			entry["landmarks"] = _transform_list(entry.get("landmarks", []) as Array, basis)
			pose_out.append(entry)
		f["pose"] = pose_out

		var hands_out: Array = []
		for h: Variant in f.get("hands", []) as Array:
			var hand: Dictionary = (h as Dictionary).duplicate()
			hand["landmarks"] = _transform_list(hand.get("landmarks", []) as Array, basis)
			hands_out.append(hand)
		f["hands"] = hands_out

		out.append(f)
	return out


static func _transform_list(landmarks: Array, basis: Dictionary) -> Array:
	var out: Array = []
	for lm: Variant in landmarks:
		var d: Dictionary = (lm as Dictionary).duplicate()
		var x: Variant = d.get("x")
		var y: Variant = d.get("y")
		var z: Variant = d.get("z")
		if (x is float or x is int) and (y is float or y is int):
			var body: Vector3 = to_body(
				Vector3(float(x), float(y), float(z) if (z is float or z is int) else 0.0),
				basis)
			d["x"] = body.x
			d["y"] = body.y
			d["z"] = body.z
		out.append(d)
	return out


static func _pose_landmarks(frame: Dictionary) -> Array:
	var pose: Array = frame.get("pose", []) as Array
	if pose.is_empty():
		return []
	return (pose[0] as Dictionary).get("landmarks", []) as Array


static func _landmark(landmarks: Array, id: int) -> Vector3:
	# Caminho rápido: o exportador grava id == posição no array.
	if id >= 0 and id < landmarks.size():
		var direct: Dictionary = landmarks[id] as Dictionary
		if int(direct.get("id", -1)) == id:
			return _to_vec(direct)
	for lm: Variant in landmarks:
		var d: Dictionary = lm as Dictionary
		if int(d.get("id", -1)) == id:
			return _to_vec(d)
	return INVALID_VEC


static func _to_vec(d: Dictionary) -> Vector3:
	var x: Variant = d.get("x")
	var y: Variant = d.get("y")
	if not (x is float or x is int) or not (y is float or y is int):
		return INVALID_VEC
	var z: Variant = d.get("z")
	return Vector3(float(x), float(y), float(z) if (z is float or z is int) else 0.0)
