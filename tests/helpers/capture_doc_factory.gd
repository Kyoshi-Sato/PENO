class_name CaptureDocFactory
extends RefCounted
## Fábrica de documentos de captura sintéticos no formato exportado pelo
## HolisticLandmarker ({video_info, frames:[{frame, timestamp_ms, hands, pose}]}).
##
## Determinística (jitter senoidal, sem RNG) para que os testes possam pinar
## valores exatos de similaridade como regressão.
##
## Anatomia do doc "moving": jitter de ~0.002 em todos os landmarks (piso de
## ruído que a segmentação por mediana pressupõe) + translação da mão inteira
## (~0.02/frame, acima do limiar mínimo de 0.01) no terço central do clipe.

const JITTER_AMP := 0.002
const HAND_TRAVEL := 0.25


## Posições base dos 33 landmarks de pose (coordenadas normalizadas de imagem;
## pessoa de frente, sem espelhamento).
static func _pose_base() -> Array[Vector3]:
	var p: Array[Vector3] = []
	p.resize(33)
	p.fill(Vector3(0.5, 0.2, 0.0))                # cabeça (0-10) agrupada
	for i in range(1, 11):
		p[i] = Vector3(0.47 + 0.006 * i, 0.16 + 0.004 * (i % 3), 0.0)
	p[11] = Vector3(0.62, 0.35, 0.0)              # ombro E
	p[12] = Vector3(0.38, 0.35, 0.0)              # ombro D
	p[13] = Vector3(0.66, 0.50, 0.0)              # cotovelo E
	p[14] = Vector3(0.34, 0.50, 0.0)              # cotovelo D
	p[15] = Vector3(0.68, 0.62, 0.0)              # pulso E
	p[16] = Vector3(0.32, 0.62, 0.0)              # pulso D
	for i in range(17, 23):                       # dedos da pose
		var left := (i % 2) == 1
		p[i] = (p[15] if left else p[16]) + Vector3(0.01 * ((i - 17) / 2 + 1), 0.02, 0.0)
	p[23] = Vector3(0.58, 0.62, 0.0)              # quadril E
	p[24] = Vector3(0.42, 0.62, 0.0)              # quadril D
	p[25] = Vector3(0.57, 0.80, 0.0)              # joelho E
	p[26] = Vector3(0.43, 0.80, 0.0)              # joelho D
	p[27] = Vector3(0.56, 0.95, 0.0)              # tornozelo E
	p[28] = Vector3(0.44, 0.95, 0.0)              # tornozelo D
	for i in range(29, 33):
		var left := (i % 2) == 1
		p[i] = (p[27] if left else p[28]) + Vector3(0.01, 0.02, 0.0)
	return p


## Deslocamento do pulso direito no frame i (curva suave: sobe e volta
## durante o terço central de n_frames).
static func _wrist_offset(i: int, n_frames: int) -> Vector3:
	var start := n_frames / 3
	var end := 2 * n_frames / 3
	if i < start or i >= end:
		return Vector3.ZERO
	var t := float(i - start) / float(end - start)   # 0..1 dentro do gesto
	var lift := sin(t * PI)                          # sobe e volta
	return Vector3(0.05 * lift, -HAND_TRAVEL * lift, 0.0)


## Jitter senoidal determinístico por frame/landmark/eixo.
static func _jitter(i: int, id: int, axis: int) -> float:
	return JITTER_AMP * sin(float(i) * 1.7 + float(id) * 0.91 + float(axis) * 2.3)


static func _lm(id: int, pos: Vector3) -> Dictionary:
	return {
		"id": id,
		"x": pos.x, "y": pos.y, "z": pos.z,
		"visibility": 1.0, "presence": 1.0,
	}


## 21 landmarks de mão ancorados em `wrist` (0 = pulso; 5/17 bases de dedos
## não colineares para a normal da palma; 12 = ponta do médio).
static func _hand_landmarks(wrist: Vector3, i: int) -> Array:
	var out: Array = []
	for id in range(21):
		var col := id % 5
		var row := id / 5
		var pos := wrist + Vector3(0.012 * col - 0.024, -0.015 * row, 0.002 * col)
		pos += Vector3(_jitter(i, 100 + id, 0), _jitter(i, 100 + id, 1), _jitter(i, 100 + id, 2))
		out.append(_lm(id, pos))
	return out


## Monta um doc completo.
## moving=true: mão direita (rótulo "Right") viaja no terço central.
## with_hands=false: nenhum frame tem mãos (usuário com mãos fora do quadro).
static func make_doc(n_frames: int, fps: float, moving: bool, with_hands: bool) -> Dictionary:
	var base := _pose_base()
	var frames: Array = []
	for i in range(n_frames):
		var offset := _wrist_offset(i, n_frames) if moving else Vector3.ZERO

		var pose_landmarks: Array = []
		for id in range(33):
			var pos := base[id]
			if id == 16:
				pos += offset            # pulso direito acompanha o gesto
			elif id == 14:
				pos += offset * 0.5      # cotovelo segue pela metade
			pos += Vector3(_jitter(i, id, 0), _jitter(i, id, 1), _jitter(i, id, 2))
			pose_landmarks.append(_lm(id, pos))

		var hands: Array = []
		if with_hands:
			hands.append({
				"handedness": "Right",
				"confidence": 1.0,
				"landmarks": _hand_landmarks(base[16] + offset, i),
			})

		frames.append({
			"frame": i,
			"timestamp_ms": int(round(float(i) * 1000.0 / fps)),
			"hands": hands,
			"pose": [{ "landmarks": pose_landmarks }],
		})

	return {
		"video_info": { "fps": fps, "total_frames": n_frames, "source": "factory" },
		"frames": frames,
	}
