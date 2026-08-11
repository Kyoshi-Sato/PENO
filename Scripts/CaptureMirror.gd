class_name CaptureMirror
extends RefCounted
## Espelhamento horizontal de documentos de captura {video_info, frames}.
##
## Convenção canônica do projeto (a mesma dos gabaritos da API): vídeo
## NÃO-espelhado com rótulos anatômicos derivados da pose. Câmeras
## frontais/webcams alimentam o MediaPipe com imagem espelhada (flip de
## selfie do SubViewport), então a captura precisa deste espelho completo
## para virar canônica: x -> 1-x, troca dos landmarks pareados
## esquerda/direita da pose e troca dos rótulos Left/Right das mãos.
##
## Verificado empiricamente (2026-07-23): gabarito da API com id 11
## ("ombro esquerdo") em x~0.68 → não-espelhado, rótulos anatômicos;
## captura de câmera frontal com id 11 em x~0.91 → espelhada (esse
## "esquerdo" é fisicamente o ombro direito do usuário).

## Pares esquerda/direita dos 33 landmarks de pose do MediaPipe.
const POSE_MIRROR_SWAP := {
	1: 4, 2: 5, 3: 6, 4: 1, 5: 2, 6: 3,
	7: 8, 8: 7, 9: 10, 10: 9,
	11: 12, 12: 11, 13: 14, 14: 13, 15: 16, 16: 15,
	17: 18, 18: 17, 19: 20, 20: 19, 21: 22, 22: 21,
	23: 24, 24: 23, 25: 26, 26: 25, 27: 28, 28: 27,
	29: 30, 30: 29, 31: 32, 32: 31,
}


## Espelha um documento completo. Não muta o original.
static func mirror_doc(doc: Dictionary) -> Dictionary:
	var mirrored: Dictionary = doc.duplicate()
	mirrored["frames"] = mirror_frames(doc.get("frames", []) as Array)
	return mirrored


## Espelha uma lista de frames de captura. Não muta a original.
static func mirror_frames(frames: Array) -> Array:
	var frames_out: Array = []
	for frame: Variant in frames:
		var f: Dictionary = (frame as Dictionary).duplicate()

		var hands_out: Array = []
		for h: Variant in f.get("hands", []) as Array:
			var hand: Dictionary = (h as Dictionary).duplicate()
			var side: String = String(hand.get("handedness", ""))
			hand["handedness"] = "Right" if side == "Left" else "Left"
			hand["landmarks"] = _mirror_landmarks(hand.get("landmarks", []) as Array, false)
			hands_out.append(hand)
		f["hands"] = hands_out

		var pose_out: Array = []
		for p: Variant in f.get("pose", []) as Array:
			var pose_entry: Dictionary = (p as Dictionary).duplicate()
			pose_entry["landmarks"] = _mirror_landmarks(
				pose_entry.get("landmarks", []) as Array, true)
			pose_out.append(pose_entry)
		f["pose"] = pose_out

		frames_out.append(f)
	return frames_out


## Os landmarks de mão têm a mesma topologia nos dois lados, então basta
## espelhar x; na pose os ids esquerda/direita precisam ser trocados.
## y e z não mudam num espelhamento horizontal.
static func _mirror_landmarks(landmarks: Array, swap_pose_ids: bool) -> Array:
	var out: Array = []
	for lm: Variant in landmarks:
		var d: Dictionary = (lm as Dictionary).duplicate()
		var x: Variant = d.get("x")
		if x is float or x is int:
			d["x"] = 1.0 - float(x)
		if swap_pose_ids:
			var id: int = int(d.get("id", -1))
			d["id"] = int(POSE_MIRROR_SWAP.get(id, id))
		out.append(d)
	return out
