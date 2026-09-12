extends GutTest

## Testes unitários para a integração da IA do TCC no PENO.

const HandNeuralEngineScript := preload("res://Scripts/HandNeuralEngine.gd")
const HandBiomechanicalGuidanceScript := preload("res://Scripts/HandBiomechanicalGuidance.gd")
const HandShapeClassifierScript := preload("res://Scripts/HandShapeClassifier.gd")


func test_engine_loads_and_passes_sanity() -> void:
	var engine: RefCounted = HandNeuralEngineScript.new()
	var loaded: bool = engine.load_model()
	assert_true(loaded, "O motor neural deve carregar os pesos e labels com sucesso")
	assert_true(engine.is_loaded, "O motor deve estar marcado como carregado")
	assert_eq(engine.labels.size(), 2364, "Devem existir 2364 classes carregadas")

	var sanity_ok: bool = engine.run_sanity_test()
	assert_true(sanity_ok, "A predição do Godot deve ser idêntica à do Python Keras")


func test_biomechanical_guidance_parser() -> void:
	# Teste de resolução do sinal V
	var code_v: String = HandBiomechanicalGuidanceScript.resolve_kinematic_code("V")
	assert_eq(code_v, "4141000110", "Código da letra V deve ser 4141000110")

	var parsed: Dictionary = HandBiomechanicalGuidanceScript.parse_hand_pose(code_v)
	assert_true(bool(parsed["index"]["is_extended"]), "No sinal V, o indicador deve estar estendido")
	assert_true(bool(parsed["middle"]["is_extended"]), "No sinal V, o médio deve estar estendido")
	assert_true(bool(parsed["ring"]["is_closed"]), "No sinal V, o anelar deve estar fechado")
	assert_true(bool(parsed["pinky"]["is_closed"]), "No sinal V, o mindinho deve estar fechado")
	assert_true(bool(parsed["spreads"]["is_v_open"]), "No sinal V, a abertura deve ser em V")

	# Teste de feedback quando o usuário fecha o indicador incorretamente
	var code_err: String = "4141014110"  # Indicador fechado (stage 4)
	var guidance: Dictionary = HandBiomechanicalGuidanceScript.get_biomechanical_guidance(code_err, code_v)
	assert_false(bool(guidance["match"]), "Não deve combinar com código divergente")
	assert_eq(String(guidance["finger_status"]["index"]), "ERR", "Status do indicador deve ser ERR")


func test_classifier_extract_features() -> void:
	var dummy_landmarks: Array = []
	for i in range(21):
		dummy_landmarks.append({"x": 0.1 + float(i) * 0.01, "y": 0.2 + float(i) * 0.02, "z": 0.0})

	var feats: PackedFloat32Array = HandShapeClassifierScript.extract_features(dummy_landmarks)
	assert_eq(feats.size(), 42, "Devem ser extraídas exatamente 42 features")
	# Landmark 0 deve ser 0.0, 0.0 pois subtraímos o pulso
	assert_almost_eq(feats[0], 0.0, 0.0001, "Feature 0 (pulso X) deve ser 0")
	assert_almost_eq(feats[1], 0.0, 0.0001, "Feature 1 (pulso Y) deve ser 0")


func test_classifier_median_filter_kills_outlier() -> void:
	# Histórico com um glitch de 1 frame no indicador (índice 6)
	var history: Array[String] = [
		"4141000110", # Indicador = 0
		"4141000110", # Indicador = 0
		"4141004110", # GLITCH! Indicador = 4
		"4141000110", # Indicador = 0
		"4141000110"  # Indicador = 0
	]
	var stabilized: String = HandShapeClassifierScript._apply_finger_median_filter(history, "4141004110")
	# A mediana de [0, 0, 4, 0, 0] é 0!
	assert_eq(stabilized.substr(6, 1), "0", "O filtro de mediana deve filtrar o spike e manter o indicador em 0")


func test_parallel_sign_validator() -> void:
	var ParallelSignValidatorScript := preload("res://Scripts/ParallelSignValidator.gd")
	var val: SignValidator = ParallelSignValidatorScript.new()
	assert_not_null(val, "Validador paralelo deve ser instanciado")

	# Teste com payload vazio - deve manter o comportamento original seguro
	var res := val.validate({}, {})
	assert_false(bool(res.get("ok", true)), "Payload vazio deve falhar com ok=false")
	assert_true(bool(res.get("has_ai", false)), "Deve incluir a chave has_ai")
	assert_eq(float(res.get("precision", -1.0)), 0.0, "Payload vazio deve ter precisão 0.0")


func test_comparison_card_ui() -> void:
	var ComparisonCardScript := preload("res://GUI/components/ComparisonCard.gd")
	var card: PanelContainer = ComparisonCardScript.new()
	add_child_autofree(card)
	assert_not_null(card, "ComparisonCard deve ser instanciado")

	var mock_legacy := {
		"precision": 0.85,
		"global_similarity_pct": 85.2,
		"mirrored": false,
		"ok": true
	}
	var mock_ai := {
		"hand_precision": 0.90,
		"avg_confidence": 0.92,
		"dominant_code": "4141000110",
		"expected_code": "4141000110",
		"dominant_letter": "V",
		"detected_frames": 25,
		"total_frames": 30,
		"finger_status": {
			"index": "OK",
			"middle": "OK",
			"ring": "OK",
			"pinky": "OK",
			"thumb": "OK",
			"spread": "OK"
		},
		"hints": ["Excelente postura!"]
	}

	card.populate(mock_legacy, mock_ai)
	assert_true(card.is_inside_tree(), "Card deve estar na árvore de nós")
	assert_eq(card._lbl_title.text, "Avaliação Biomecânica da Forma da Mão", "Título do card deve ser a versão final")


func test_classifier_on_real_fixture() -> void:
	var file := FileAccess.open("res://tests/fixtures/api_letra_a.json", FileAccess.READ)
	assert_not_null(file, "Fixture api_letra_a.json deve existir e abrir")
	if file == null:
		return

	var text := file.get_as_text()
	file.close()

	var json: Variant = JSON.parse_string(text)
	assert_true(json is Dictionary, "Fixture deve ser um Dictionary")
	var doc: Dictionary = json as Dictionary
	var frames: Array = doc.get("frames", []) as Array
	assert_gt(frames.size(), 0, "Fixture deve ter frames")

	var classifier: RefCounted = HandShapeClassifierScript.new()
	var ai_eval: Dictionary = classifier.evaluate_recording(frames, "A")

	assert_gt(int(ai_eval.get("detected_frames", 0)), 0, "Deve detectar mãos na gravação real")
	assert_gt(float(ai_eval.get("avg_confidence", 0.0)), 0.0, "Confiança média deve ser > 0")
	gut.p("Sinal detectado na fixture: %s (Código: %s, Confiança: %.2f%%)" % [
		ai_eval.get("dominant_letter", ""),
		ai_eval.get("dominant_code", ""),
		float(ai_eval.get("avg_confidence", 0.0)) * 100.0
	])


func test_feedback_state_full_integration_with_ui() -> void:
	var tela: FeedbackState = load("res://GUI/feedback/FeedbackState.tscn").instantiate()
	add_child_autofree(tela)

	var user_file := FileAccess.open("res://tests/fixtures/api_letra_a.json", FileAccess.READ)
	assert_not_null(user_file, "Fixture api_letra_a deve abrir")
	if user_file == null:
		return
	var user_payload: Dictionary = JSON.parse_string(user_file.get_as_text()) as Dictionary
	user_file.close()

	var licao := Lesson.new()
	licao.lesson_id = 1
	licao.sinais = [{"nome_sinal": "A", "json_sinal": user_payload}]

	tela.evaluate(licao, 0, user_payload)
	await wait_for_signal(tela.evaluation_completed, 15.0)

	assert_true(tela._comparison_card != null, "ComparisonCard deve existir")
	assert_true(tela._comparison_card.visible, "ComparisonCard deve estar visível")

	var last_res := tela.get_last_result()
	var ai_res: Dictionary = last_res.get("ai_result", {}) as Dictionary
	var ai_prec: float = float(ai_res.get("hand_precision", 0.0))
	assert_eq(float(last_res.get("precision", 0.0)), ai_prec, "A precisão oficial deve ser a precisão da IA")
	assert_gt(ai_prec, 0.5, "A precisão da IA na fixture deve ser > 0.5")

	# Aguarda a animação do anel de precisão (DS.DUR_SLOW = 0.55s) concluir
	await wait_seconds(0.6)
	assert_gt(tela.ring.value, 0.5, "O valor animado do anel deve atingir a pontuação da IA")


func test_resolve_kinematic_code_variations() -> void:
	# Teste de variações de nome do sinal (ex.: 'Letra A', 'Sinal B', 'letra_c')
	var code_a1 := HandBiomechanicalGuidanceScript.resolve_kinematic_code("A")
	var code_a2 := HandBiomechanicalGuidanceScript.resolve_kinematic_code("Letra A")
	var code_a3 := HandBiomechanicalGuidanceScript.resolve_kinematic_code("Sinal A")
	var code_a4 := HandBiomechanicalGuidanceScript.resolve_kinematic_code("letra_a")
	assert_eq(code_a1, "4141414110", "A deve ser 4141414110")
	assert_eq(code_a2, "4141414110", "'Letra A' deve resolver para o código da letra A")
	assert_eq(code_a3, "4141414110", "'Sinal A' deve resolver para o código da letra A")
	assert_eq(code_a4, "4141414110", "'letra_a' deve resolver para o código da letra A")

	var code_b := HandBiomechanicalGuidanceScript.resolve_kinematic_code("Letra B")
	assert_eq(code_b, "0101010110", "'Letra B' deve resolver para 0101010110")


func test_parallel_validator_evaluates_base_sign_and_prevents_leakage() -> void:
	var file := FileAccess.open("res://tests/fixtures/api_letra_a.json", FileAccess.READ)
	assert_not_null(file, "Fixture api_letra_a.json deve existir")
	if file == null:
		return
	var raw_doc: Dictionary = JSON.parse_string(file.get_as_text()) as Dictionary
	file.close()

	var ParallelSignValidatorScript := preload("res://Scripts/ParallelSignValidator.gd")
	var val: SignValidator = ParallelSignValidatorScript.new()

	var reference := raw_doc.duplicate()
	reference["nome_sinal"] = "Letra A"

	var user_payload := raw_doc.duplicate()
	user_payload["nome_sinal"] = "Letra A"

	var result := val.validate(user_payload, reference)
	assert_true(result.has("has_ai"), "Resultado deve conter payload da IA")
	var ai_res: Dictionary = result.get("ai_result", {}) as Dictionary

	# 1. Verifica que a IA passou por cima do sinal base
	assert_true(ai_res.has("reference_ai"), "ai_result deve conter análise do sinal base (reference_ai)")
	var ref_ai: Dictionary = ai_res.get("reference_ai", {}) as Dictionary
	assert_gt(int(ref_ai.get("detected_frames", 0)), 0, "O modelo deve detectar frames com mão no sinal base")
	assert_eq(String(ai_res.get("base_letter", "")), "A", "A letra identificada na base deve ser 'A'")

	# 2. Verifica que o código esperado é do sinal base (Letra A), e NÃO da letra V ('4141000110')
	var exp_code: String = String(ai_res.get("expected_code", ""))
	assert_ne(exp_code, "4141000110", "O código esperado não pode cair no default arbitrário (Letra V)")
	assert_gt(float(ai_res.get("hand_precision", 0.0)), 0.7, "Precisão comparada com a própria base deve ser alta")

	# 3. Teste de isolamento de estado (execução consecutiva não pode vazar estado)
	var dummy_user := {"frames": [], "nome_sinal": "Letra B"}
	var dummy_ref := {"frames": [], "nome_sinal": "Letra B"}
	var result2 := val.validate(dummy_user, dummy_ref)
	var ai_res2: Dictionary = result2.get("ai_result", {}) as Dictionary
	assert_eq(String(ai_res2.get("expected_code", "")), "0101010110", "Segunda execução deve resolver Letra B de forma limpa")


func test_dual_hand_extraction_and_model_execution() -> void:
	# 1. Cria frame sintético com AMBAS as mãos (Direita e Esquerda)
	var dummy_lms_r: Array = []
	var dummy_lms_l: Array = []
	for i in range(21):
		dummy_lms_r.append({"x": 0.3 + float(i) * 0.01, "y": 0.4 + float(i) * 0.01, "z": 0.0})
		dummy_lms_l.append({"x": 0.7 - float(i) * 0.01, "y": 0.4 + float(i) * 0.01, "z": 0.0})

	var frame_two_hands := {
		"timestamp_ms": 100,
		"hands": [
			{"handedness": "Right", "landmarks": dummy_lms_r},
			{"handedness": "Left", "landmarks": dummy_lms_l}
		]
	}

	# Verifica se o extrator identifica ambas as mãos
	var extracted := HandShapeClassifierScript.extract_all_hands_from_frame(frame_two_hands)
	assert_eq(extracted.size(), 2, "Devem ser extraídas 2 mãos do frame")
	assert_eq(String(extracted[0]["handedness"]), "Right")
	assert_eq(String(extracted[1]["handedness"]), "Left")

	# 2. Testa avaliação da gravação com ambas as mãos
	var classifier: HandShapeClassifier = HandShapeClassifierScript.new()
	var frames: Array = [frame_two_hands, frame_two_hands, frame_two_hands]
	var eval_res: Dictionary = classifier.evaluate_recording(frames, "A")

	assert_true(bool(eval_res.get("both_hands_detected", false)), "A gravação deve detectar ambas as mãos")
	assert_true(bool(eval_res.get("has_right", false)), "Mão direita deve ser detectada")
	assert_true(bool(eval_res.get("has_left", false)), "Mão esquerda deve ser detectada")

	var r_stats: Dictionary = eval_res.get("right_hand", {}) as Dictionary
	var l_stats: Dictionary = eval_res.get("left_hand", {}) as Dictionary
	assert_eq(int(r_stats.get("detected_frames", 0)), 3, "Mão direita deve ter passado em 3 frames pelo modelo")
	assert_eq(int(l_stats.get("detected_frames", 0)), 3, "Mão esquerda deve ter passado em 3 frames pelo modelo")
	assert_ne(String(r_stats.get("dominant_code", "")), "0000000000", "Mão direita deve ter gerado código pelo modelo")
	assert_ne(String(l_stats.get("dominant_code", "")), "0000000000", "Mão esquerda deve ter gerado código pelo modelo")

	# 3. Testa integração com ParallelSignValidator
	var ParallelSignValidatorScript := preload("res://Scripts/ParallelSignValidator.gd")
	var val: SignValidator = ParallelSignValidatorScript.new()
	var val_res: Dictionary = val.validate({"frames": frames, "nome_sinal": "A"}, {"frames": frames, "nome_sinal": "A"})
	var ai_val_res: Dictionary = val_res.get("ai_result", {}) as Dictionary
	assert_true(bool(ai_val_res.get("both_hands_detected", false)), "Validador em paralelo deve indicar ambas as mãos")


func test_continuous_posture_similarity() -> void:
	# 1. Códigos idênticos devem ter 1.0 (100% de similaridade)
	var sim_identical: float = HandBiomechanicalGuidanceScript.calculate_posture_similarity("4141414110", "4141414110")
	assert_almost_eq(sim_identical, 1.0, 0.001, "Códigos idênticos devem ter similaridade 1.0")

	# 2. Variação leve no polegar (ex: ponta dobrada vs estendida) deve ter nota alta contínua (~0.92) e não zero binário
	var sim_close: float = HandBiomechanicalGuidanceScript.calculate_posture_similarity("4141414100", "4141414110")
	assert_gt(sim_close, 0.85, "Pequena variação no polegar deve manter similaridade alta (> 0.85)")
	assert_lt(sim_close, 1.0, "Variação deve ser estritamente menor que 1.0")

	# 3. Formas com dedos na mesma flexão (ex: punho fechado Letra A vs Letra S) devem ter proximidade contínua proporcional
	var code_a := "4141414110"
	var code_s := "4141414120"
	var sim_a_s: float = HandBiomechanicalGuidanceScript.calculate_posture_similarity(code_a, code_s)
	assert_gt(sim_a_s, 0.85, "A e S compartilham 4 dedos fechados e devem ter proximidade > 0.85")

	# 4. Formas diametralmente opostas (Letra A fechada vs Letra B aberta) devem ter nota baixa
	var code_b := "0101010110"
	var sim_a_b: float = HandBiomechanicalGuidanceScript.calculate_posture_similarity(code_a, code_b)
	assert_true(sim_a_b <= 0.40, "Letra A (fechada) e Letra B (aberta) devem ter similaridade <= 0.40")


func test_unread_frames_ignored_in_evaluation() -> void:
	var file := FileAccess.open("res://tests/fixtures/api_letra_a.json", FileAccess.READ)
	assert_not_null(file, "Fixture api_letra_a.json deve existir")
	if file == null:
		return
	var raw_doc: Dictionary = JSON.parse_string(file.get_as_text()) as Dictionary
	file.close()

	var original_frames: Array = (raw_doc.get("frames", []) as Array).slice(0, 15)
	var classifier: HandShapeClassifier = HandShapeClassifierScript.new()

	# Avaliação dos frames originais puros
	var eval_clean: Dictionary = classifier.evaluate_recording(original_frames, "A")
	var prec_clean: float = float(eval_clean.get("hand_precision", 0.0))
	assert_gt(prec_clean, 0.70, "Precisão dos frames puros deve ser alta")

	# Cria gravação poluída com frames vazios / sem mão (ex: usuário posicionando a câmera)
	# Mantendo total <= 30 para manter o mesmo stride step=1 e testar isoladamente a exclusão dos vazios
	var corrupted_frames: Array = []
	for i in range(5):
		corrupted_frames.append({"timestamp_ms": i * 33, "hands": []})
	corrupted_frames.append_array(original_frames)
	for i in range(5):
		corrupted_frames.append({"timestamp_ms": (20 + i) * 33, "hands": []})

	var eval_corrupted: Dictionary = classifier.evaluate_recording(corrupted_frames, "A")
	var prec_corrupted: float = float(eval_corrupted.get("hand_precision", 0.0))

	# A pontuação de precisão da forma NÃO deve ser prejudicada/diluída pelos frames sem mão
	assert_almost_eq(prec_corrupted, prec_clean, 0.05, "Frames sem detecção não devem penalizar a precisão da mão")
	assert_gt(int(eval_corrupted.get("total_frames", 0)), int(eval_clean.get("total_frames", 0)), "Total de frames inclui vazios")
	assert_eq(int(eval_corrupted.get("detected_frames", 0)), int(eval_clean.get("detected_frames", 0)), "Apenas frames com mão contam como detectados")


func test_mobile_stride_optimization() -> void:
	# Cria gravação sintética longa (90 frames)
	var dummy_lms: Array = []
	for i in range(21):
		dummy_lms.append({"x": 0.5 + float(i) * 0.01, "y": 0.5 + float(i) * 0.01, "z": 0.0})

	var long_frames: Array = []
	for i in range(90):
		long_frames.append({
			"timestamp_ms": i * 33,
			"hands": [{"handedness": "Right", "landmarks": dummy_lms}]
		})

	var classifier: HandShapeClassifier = HandShapeClassifierScript.new()
	var eval_res: Dictionary = classifier.evaluate_recording(long_frames, "A")

	# Com 90 frames, o stride adaptativo deve ser 3, processando exatamente 30 frames (90 / 3)
	assert_eq(int(eval_res.get("total_frames", 0)), 90, "Total de frames registrado deve ser 90")
	assert_eq(int(eval_res.get("detected_frames", 0)), 30, "Stride para >60 frames deve processar 30 inferências leves")


class MockMotionValidator extends SignValidator:
	var fixed_precision: float = 0.80
	func validate(_u: Dictionary, _r: Dictionary) -> Dictionary:
		return {
			"ok": true,
			"precision": fixed_precision,
			"global_similarity_pct": fixed_precision * 100.0,
			"details": {"Pose (corpo)": {"group_similarity_pct": 80.0}}
		}


func test_weighted_precision_70_hand_30_motion() -> void:
	var ParallelSignValidatorScript := preload("res://Scripts/ParallelSignValidator.gd")
	var val: ParallelSignValidator = ParallelSignValidatorScript.new()
	var mock := MockMotionValidator.new()
	mock.fixed_precision = 0.80
	val.legacy_validator = mock

	var dummy_lms: Array = []
	for i in range(21):
		dummy_lms.append({"x": 0.5 + float(i) * 0.01, "y": 0.5 + float(i) * 0.01, "z": 0.0})
	var frames: Array = [{"timestamp_ms": 100, "hands": [{"handedness": "Right", "landmarks": dummy_lms}]}]

	var res := val.validate({"frames": frames, "nome_sinal": "A"}, {"frames": frames, "nome_sinal": "A"})
	var ai_prec: float = float(res["ai_result"]["hand_precision"])
	var motion_prec: float = 0.80
	var expected_combined := (ai_prec * 0.70) + (motion_prec * 0.30)

	assert_almost_eq(float(res["precision"]), expected_combined, 0.001, "A precisão deve ser exatamente 70% forma + 30% movimento")
	assert_eq(float(res["ai_result"]["hand_shape_weight"]), 0.70, "Peso da forma deve ser 70%")
	assert_eq(float(res["ai_result"]["motion_position_weight"]), 0.30, "Peso do movimento deve ser 30%")


func test_no_hands_detected_handling() -> void:
	# 1. Testa o classificador com frames sem mãos (hands: [])
	var empty_frames: Array = [
		{"timestamp_ms": 0, "hands": []},
		{"timestamp_ms": 33, "hands": []}
	]
	var classifier: HandShapeClassifier = HandShapeClassifierScript.new()
	var ai_res: Dictionary = classifier.evaluate_recording(empty_frames, "A")

	assert_false(bool(ai_res.get("ok", true)), "Quando não há mãos, ok deve ser false")
	assert_eq(int(ai_res.get("detected_frames", -1)), 0, "Frames detectados deve ser 0")
	assert_eq(float(ai_res.get("hand_precision", -1.0)), 0.0, "Precisão da mão deve ser 0.0")
	assert_eq(String(ai_res.get("dominant_hand", "")), "None", "Mão dominante deve ser None")

	var f_status: Dictionary = ai_res.get("finger_status", {}) as Dictionary
	for k: String in ["thumb", "index", "middle", "ring", "pinky", "spread"]:
		assert_eq(String(f_status.get(k, "")), "MISSING", "Status do dedo %s deve ser MISSING quando ausente" % k)

	# 2. Testa o ParallelSignValidator com gravação sem mãos
	var ParallelSignValidatorScript := preload("res://Scripts/ParallelSignValidator.gd")
	var val: ParallelSignValidator = ParallelSignValidatorScript.new()
	var val_res: Dictionary = val.validate({"frames": empty_frames, "nome_sinal": "A"}, {"frames": empty_frames, "nome_sinal": "A"})

	assert_false(bool(val_res.get("ok", true)), "Validação deve falhar com ok=false quando não há mãos")
	assert_eq(float(val_res.get("precision", -1.0)), 0.0, "Precisão final deve ser estritamente 0.0")
	assert_true(String(val_res.get("error", "")).contains("Nenhuma mão detectada"), "Mensagem de erro deve alertar sobre ausência de mãos")

	# 3. Testa a exibição no ComparisonCard quando nenhuma mão foi detectada
	var ComparisonCardScript := preload("res://GUI/components/ComparisonCard.gd")
	var card: PanelContainer = ComparisonCardScript.new()
	add_child_autofree(card)
	card.populate(val_res.get("legacy_result", {}) as Dictionary, val_res.get("ai_result", {}) as Dictionary)

	assert_eq(card._lbl_match_badge.text, "❌ Mão Não Detectada", "Badge deve ser Mão Não Detectada")
	assert_eq(card._lbl_hands_detected.text, "Mão Avaliada: Nenhuma mão detectada na câmera", "Mão avaliada não deve inventar Mão Direita")
	assert_eq(card._lbl_detected_sign.text, "Nenhuma mão detectada", "Sinal reconhecido deve informar ausência de mão")
	assert_true(card._lbl_hints.text.contains("Nenhuma mão foi detectada"), "Dicas não devem elogiar postura quando a mão está ausente")
	assert_false(card._lbl_hints.text.contains("Excelente postura"), "Jamais deve elogiar postura sem mãos presentes")

	# Verifica se nenhum dedo ficou com 'Correto'
	for row: Node in card._finger_grid.get_children():
		var row_box := row as HBoxContainer
		if row_box != null and row_box.get_child_count() >= 2:
			var val_lbl := row_box.get_child(1) as Label
			if val_lbl != null:
				assert_eq(val_lbl.text, "⚠️ Não detectado", "Dedo deve estar como Não detectado quando ausente")
				assert_ne(val_lbl.text, "✅ Correto", "Dedo não pode ser marcado como Correto sem mãos")


func test_strict_shape_scoring_tolerances() -> void:
	var code_v := "4141000110"  # V

	# 1. Exato: 1.0 (100%)
	assert_eq(HandBiomechanicalGuidanceScript.calculate_posture_similarity(code_v, code_v), 1.0)

	# 2. Ausente / Zerado: 0.0
	assert_eq(HandBiomechanicalGuidanceScript.calculate_posture_similarity("0000000000", code_v), 0.0)

	# 3. Tolerância de 1 caractere, nível 1: ~0.90
	var sim_1_char_1_lvl := HandBiomechanicalGuidanceScript.calculate_posture_similarity("4141000100", code_v)
	assert_almost_eq(sim_1_char_1_lvl, 0.90, 0.01, "1 caractere com nível 1 deve dar 0.90")

	# 4. Tolerância de 1 caractere, nível 2: ~0.78
	var sim_1_char_2_lvl := HandBiomechanicalGuidanceScript.calculate_posture_similarity("4141002110", code_v)
	assert_almost_eq(sim_1_char_2_lvl, 0.78, 0.01, "1 caractere com nível 2 deve dar 0.78")

	# 5. Tolerância de 2 caracteres, nível 1+1: ~0.75
	var sim_2_char_1_1 := HandBiomechanicalGuidanceScript.calculate_posture_similarity("4141000000", code_v)
	assert_almost_eq(sim_2_char_1_1, 0.75, 0.01, "2 caracteres com nível 1+1 deve dar 0.75")

	# 6. Tolerância de 2 caracteres, nível 1+2: ~0.65
	var sim_2_char_1_2 := HandBiomechanicalGuidanceScript.calculate_posture_similarity("4141002100", code_v)
	assert_almost_eq(sim_2_char_1_2, 0.65, 0.01, "2 caracteres com nível 1+2 deve dar 0.65")

	# 7. Tolerância de 2 caracteres, nível 2+2: ~0.55
	var sim_2_char_2_2 := HandBiomechanicalGuidanceScript.calculate_posture_similarity("4141202110", code_v)
	assert_almost_eq(sim_2_char_2_2, 0.55, 0.01, "2 caracteres com nível 2+2 deve dar 0.55")

	# 8. Desconto Incisivo: 3 caracteres divergentes deve derrubar para <= 0.35
	var sim_3_chars := HandBiomechanicalGuidanceScript.calculate_posture_similarity("4141202000", code_v)
	assert_true(sim_3_chars <= 0.35, "3 caracteres divergentes deve sofrer desconto incisivo (<= 0.35)")

	# 9. Erro anatômico grave em 1 dedo (diferença de 4 níveis, ex: dedo aberto 0 virou fechado 4):
	# V com indicador fechado: "4141004110"
	var sim_gross_err := HandBiomechanicalGuidanceScript.calculate_posture_similarity("4141004110", code_v)
	assert_true(sim_gross_err <= 0.10, "Erro grosseiro de nível 4 em um dedo deve derrubar a pontuação para <= 0.10")


func test_oversized_frames_safety_downsampling() -> void:
	var validator: SignValidator = autofree(ParallelSignValidator.new())

	# Cria payload com 1000 frames simulados (para testar proteção contra estouro de memória e DTW)
	var huge_user_payload := {
		"frames": [],
		"video_info": {"fps": 30.0}
	}
	for i in range(1000):
		huge_user_payload["frames"].append({
			"timestamp_ms": i * 33,
			"pose": [{"id": 0, "x": 0.5, "y": 0.5, "z": 0.0, "visibility": 1.0}],
			"hands": [{"handedness": "Right", "landmarks": [{"id": 0, "x": 0.5, "y": 0.5, "z": 0.0}]}]
		})

	var reference := {
		"nome_sinal": "A",
		"expected_code": "4141414100",
		"frames": [
			{
				"timestamp_ms": 0,
				"pose": [{"id": 0, "x": 0.5, "y": 0.5, "z": 0.0, "visibility": 1.0}],
				"hands": [{"handedness": "Right", "landmarks": [{"id": 0, "x": 0.5, "y": 0.5, "z": 0.0}]}]
			}
		]
	}

	var res: Dictionary = validator.validate(huge_user_payload, reference)
	assert_not_null(res, "Validador deve concluir sem travar")
	assert_lte(huge_user_payload["frames"].size(), 200, "Frames devem ser subamostrados para proteger DTW")



