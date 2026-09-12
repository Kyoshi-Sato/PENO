class_name HandBiomechanicalGuidance
extends RefCounted

## Mapeamento e motor de feedback biomecânico de LIBRAS baseado no modelo do TCC.
## Avalia a postura da mão representada pelo código taxonômico de 10 dígitos:
## [D4][A3][D3][A2][D2][A1][D1][A0][F][P]
## Onde D4=Mindinho, D3=Anelar, D2=Médio, D1=Indicador, F=Oposição do Polegar, A=Aberturas.

const LETTER_KINEMATICS: Dictionary = {
	"A": {"code": "4141414110", "name": "Sinal 'A'", "desc": "Punho fechado com polegar apoiado na lateral"},
	"B": {"code": "0101010110", "name": "Sinal 'B'", "desc": "4 dedos erguidos juntos, polegar dobrado na frente"},
	"C": {"code": "1010101000", "name": "Sinal 'C'", "desc": "Dedos curvados em formato de arco/concha"},
	"D": {"code": "4141410110", "name": "Sinal 'D'", "desc": "Indicador erguido, outros 3 dedos tocando o polegar"},
	"E": {"code": "2121212110", "name": "Sinal 'E'", "desc": "Dedos em garra recolhida com pontas sobre o polegar"},
	"I": {"code": "0141414110", "name": "Sinal 'I'", "desc": "Apenas o mindinho erguido, outros dedos fechados"},
	"L": {"code": "4141410000", "name": "Sinal 'L'", "desc": "Indicador reto e polegar aberto em 90°"},
	"M": {"code": "3131314110", "name": "Sinal 'M'", "desc": "Indicador, médio e anelar dobrados sobre o polegar"},
	"N": {"code": "4131314110", "name": "Sinal 'N'", "desc": "Indicador e médio dobrados sobre o polegar"},
	"O": {"code": "1010101010", "name": "Sinal 'O'", "desc": "Dedos curvados formando um círculo com o polegar"},
	"R": {"code": "4141010110", "name": "Sinal 'R'", "desc": "Indicador e médio cruzados, outros dedos fechados"},
	"S": {"code": "4141414110", "name": "Sinal 'S'", "desc": "Punho cerrado com polegar cruzando a frente dos dedos"},
	"U": {"code": "4141010110", "name": "Sinal 'U'", "desc": "Indicador e médio estendidos retos e bem juntos"},
	"V": {"code": "4141000110", "name": "Sinal 'V'", "desc": "Indicador e médio estendidos e abertos em 'V'"},
	"W": {"code": "1000000110", "name": "Sinal 'W'", "desc": "Indicador, médio e anelar estendidos em 'W', mindinho apoiado"},
	"X": {"code": "4141412110", "name": "Sinal 'X'", "desc": "Indicador em gancho (dobrado), outros fechados"},
	"Y": {"code": "0041414100", "name": "Sinal 'Y'", "desc": "Polegar e mindinho estendidos, dedos do meio fechados"}
}

const STAGE_NAMES: Dictionary = {
	0: "Estendido",
	1: "Curvado (Concha)",
	2: "Gancho (Hook)",
	3: "Plataforma",
	4: "Fechado"
}

static func resolve_kinematic_code(input_val: String) -> String:
	if input_val.is_empty():
		return "4141000110"
	var clean := input_val.strip_edges().to_upper()
	if clean.length() == 10 and clean.is_valid_int():
		return clean
	if LETTER_KINEMATICS.has(clean):
		return String(LETTER_KINEMATICS[clean]["code"])

	# Tenta remover palavras comuns como 'LETRA', 'SINAL', 'ALFABETO'
	var stripped := clean.replace("LETRA", "").replace("SINAL", "").replace("ALFABETO", "").replace("DE", "")
	stripped = stripped.replace("_", "").replace("-", "").strip_edges()
	if LETTER_KINEMATICS.has(stripped):
		return String(LETTER_KINEMATICS[stripped]["code"])

	# Procura por qualquer letra isolada no texto
	var regex := RegEx.new()
	if regex.compile("(?:^|[^A-Z])([A-Z])(?:$|[^A-Z])") == OK:
		var m := regex.search(clean)
		if m != null:
			var candidate := m.get_string(1)
			if LETTER_KINEMATICS.has(candidate):
				return String(LETTER_KINEMATICS[candidate]["code"])

	return "4141000110"


static func get_closest_letter(code: String) -> Dictionary:
	var best_letter := ""
	var best_dist := 999999
	for letter: String in LETTER_KINEMATICS:
		var target_code: String = String(LETTER_KINEMATICS[letter]["code"])
		var dist := 0
		var n := mini(code.length(), 10)
		for i in range(n):
			dist += absi(code.unicode_at(i) - target_code.unicode_at(i))
		if dist < best_dist:
			best_dist = dist
			best_letter = letter

	return {
		"letter": best_letter,
		"distance": best_dist,
		"is_exact": best_dist == 0,
		"info": LETTER_KINEMATICS.get(best_letter, {})
	}


static func parse_hand_pose(code: String) -> Dictionary:
	var padded := (code + "0000000000").substr(0, 10)
	var d4 := padded.substr(0, 1).to_int()  # Mindinho
	var a3 := padded.substr(1, 1).to_int()  # Spread Min-Ane
	var d3 := padded.substr(2, 1).to_int()  # Anelar
	var a2 := padded.substr(3, 1).to_int()  # Spread Ane-Med
	var d2 := padded.substr(4, 1).to_int()  # Médio
	var a1 := padded.substr(5, 1).to_int()  # Spread Med-Ind
	var d1 := padded.substr(6, 1).to_int()  # Indicador
	var a0 := padded.substr(7, 1).to_int()  # Spread Ind-Pol
	var f  := padded.substr(8, 1).to_int()  # Oposição Polegar
	var p  := padded.substr(9, 1).to_int()  # Ponta Polegar

	return {
		"raw_code": padded,
		"pinky":  {"stage": d4, "is_extended": d4 == 0, "is_closed": d4 >= 3},
		"ring":   {"stage": d3, "is_extended": d3 == 0, "is_closed": d3 >= 3},
		"middle": {"stage": d2, "is_extended": d2 == 0, "is_closed": d2 >= 3},
		"index":  {"stage": d1, "is_extended": d1 == 0, "is_closed": d1 >= 3},
		"thumb": {
			"is_opposed": f == 1,
			"is_spread": a0 == 0,
			"is_tip_folded": p == 1
		},
		"spreads": {
			"middle_index": "Aberto (V)" if a1 == 0 else "Junto (U)",
			"is_v_open": a1 == 0
		}
	}


static func get_biomechanical_guidance(detected_code: String, expected_code: String) -> Dictionary:
	if detected_code.is_empty() or expected_code.is_empty():
		return {
			"match": false,
			"hints": ["Aguardando mão na câmera..."],
			"finger_status": {}
		}

	var detected := parse_hand_pose(detected_code)
	var expected := parse_hand_pose(expected_code)

	var hints: Array[String] = []
	var finger_status := {
		"index": "OK", "middle": "OK", "ring": "OK",
		"pinky": "OK", "thumb": "OK", "spread": "OK"
	}

	# 1. INDICADOR
	if int(expected["index"]["stage"]) != int(detected["index"]["stage"]):
		if bool(expected["index"]["is_extended"]) and not bool(detected["index"]["is_extended"]):
			hints.append("Estique o dedo INDICADOR totalmente para cima!")
			finger_status["index"] = "ERR"
		elif bool(expected["index"]["is_closed"]) and not bool(detected["index"]["is_closed"]):
			hints.append("Dobre o dedo INDICADOR para baixo (fechado na palma)!")
			finger_status["index"] = "ERR"
		elif int(expected["index"]["stage"]) == 1:
			hints.append("Curve o INDICADOR suavemente em formato de arco (C/O)!")
			finger_status["index"] = "ERR"
		elif int(expected["index"]["stage"]) == 2:
			hints.append("Dobre o INDICADOR em forma de gancho/anzol (sinal X)!")
			finger_status["index"] = "ERR"

	# 2. MÉDIO
	if int(expected["middle"]["stage"]) != int(detected["middle"]["stage"]):
		if bool(expected["middle"]["is_extended"]) and not bool(detected["middle"]["is_extended"]):
			hints.append("Estique o dedo MÉDIO totalmente para cima!")
			finger_status["middle"] = "ERR"
		elif bool(expected["middle"]["is_closed"]) and not bool(detected["middle"]["is_closed"]):
			hints.append("Dobre o dedo MÉDIO para a palma!")
			finger_status["middle"] = "ERR"
		elif int(expected["middle"]["stage"]) == 1:
			hints.append("Curve o dedo MÉDIO em arco!")
			finger_status["middle"] = "ERR"

	# 3. ANELAR
	if int(expected["ring"]["stage"]) != int(detected["ring"]["stage"]):
		if bool(expected["ring"]["is_extended"]) and not bool(detected["ring"]["is_extended"]):
			hints.append("Estique o dedo ANELAR para cima!")
			finger_status["ring"] = "ERR"
		elif bool(expected["ring"]["is_closed"]) and not bool(detected["ring"]["is_closed"]):
			hints.append("Dobre o dedo ANELAR para baixo!")
			finger_status["ring"] = "ERR"

	# 4. MINDINHO
	var is_w_posture: bool = (
		bool(expected["ring"]["is_extended"])
		and bool(expected["middle"]["is_extended"])
		and bool(expected["index"]["is_extended"])
	)
	if is_w_posture and int(detected["pinky"]["stage"]) in [1, 2] and int(expected["pinky"]["stage"]) in [1, 2]:
		pass  # Tolerância anatômica confirmada (juncturae tendinum)
	elif int(expected["pinky"]["stage"]) != int(detected["pinky"]["stage"]):
		if bool(expected["pinky"]["is_extended"]) and not bool(detected["pinky"]["is_extended"]):
			hints.append("Estique o dedo MINDINHO para cima (sinal I ou Y)!")
			finger_status["pinky"] = "ERR"
		elif bool(expected["pinky"]["is_closed"]) and not bool(detected["pinky"]["is_closed"]):
			hints.append("Dobre o dedo MINDINHO para a palma!")
			finger_status["pinky"] = "ERR"

	# 5. ABERTURA ENTRE INDICADOR E MÉDIO (V vs U)
	if bool(expected["index"]["is_extended"]) and bool(expected["middle"]["is_extended"]):
		var exp_v: bool = bool(expected["spreads"]["is_v_open"])
		var det_v: bool = bool(detected["spreads"]["is_v_open"])
		if exp_v and not det_v:
			hints.append("AFASTE o Indicador do Médio! No sinal 'V' os dedos ficam abertos em V.")
			finger_status["spread"] = "ERR"
		elif not exp_v and det_v:
			hints.append("JUNTE o Indicador e o Médio! No sinal 'U' os dedos ficam retos e colados.")
			finger_status["spread"] = "ERR"

	# 6. POLEGAR
	var exp_th_spread: bool = bool(expected["thumb"]["is_spread"])
	var det_th_spread: bool = bool(detected["thumb"]["is_spread"])
	var exp_th_opp: bool = bool(expected["thumb"]["is_opposed"])
	var det_th_opp: bool = bool(detected["thumb"]["is_opposed"])

	if exp_th_spread and not det_th_spread:
		hints.append("Abra o POLEGAR para fora em 90° (sinal L ou Y)!")
		finger_status["thumb"] = "ERR"
	elif not exp_th_spread and det_th_spread:
		hints.append("Recolha o POLEGAR apoiado contra a lateral dos dedos!")
		finger_status["thumb"] = "ERR"
	elif exp_th_opp and not det_th_opp:
		hints.append("Posicione o POLEGAR cruzando a frente da palma (sinais B / E)!")
		finger_status["thumb"] = "ERR"

	# Verifica se os dedos principais conferem
	var exact_match := (detected_code == expected_code)
	var w_match := (
		is_w_posture
		and bool(detected["index"]["is_extended"])
		and bool(detected["middle"]["is_extended"])
		and bool(detected["ring"]["is_extended"])
		and (int(detected["pinky"]["stage"]) in [1, 2])
		and bool(detected["spreads"]["is_v_open"])
	)
	var is_match := exact_match or w_match

	if is_match:
		hints = ["PERFEITO! A configuração dos dedos confere exatamente com o sinal esperado!"]

	return {
		"match": is_match,
		"hints": hints,
		"finger_status": finger_status
	}
