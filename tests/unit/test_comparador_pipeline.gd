extends GutTest
## Testes de regressão do pipeline completo (analyze_similarity) sobre
## documentos sintéticos determinísticos. Os valores exatos pinados aqui
## fazem qualquer mudança de comportamento do comparador aparecer no diff.

var c: MotionComparator


func before_each() -> void:
	c = MotionComparator.new()


func test_identical_docs_score_near_100() -> void:
	var doc := CaptureDocFactory.make_doc(60, 30.0, true, true)
	var results: Dictionary = c.analyze_similarity(doc, doc)
	var global := float(results["_global_similarity_pct"])
	gut.p("global identical = %f" % global)
	assert_gt(global, 95.0, "doc comparado consigo mesmo deve ser ~100%%")


func test_motionless_handless_user_is_penalized() -> void:
	# Usuário parado e sem mãos vs gabarito com movimento de mão:
	# antes da correção isso pontuava 60-80% (1-2 estrelas por nada).
	var user := CaptureDocFactory.make_doc(60, 30.0, false, false)
	var ref := CaptureDocFactory.make_doc(60, 30.0, true, true)
	var results: Dictionary = c.analyze_similarity(user, ref)
	var global := float(results["_global_similarity_pct"])
	gut.p("global motionless = %f" % global)

	assert_lt(global, 35.0, "usuário imóvel sem mãos não pode passar")

	var missing: Array = results["_missing_groups"]
	assert_has(missing, "Mão Direita", "mão exigida pelo gabarito e ausente no usuário")
	var right: Dictionary = results["Mão Direita"]
	assert_eq(float(right["group_similarity_pct"]), 0.0, "grupo ausente vale 0%%")
	assert_true(bool(right.get("missing_in_user", false)))


func test_hands_not_required_are_not_flagged() -> void:
	# Gabarito SEM mãos: a ausência de mãos no usuário não deve penalizar.
	var user := CaptureDocFactory.make_doc(40, 30.0, false, false)
	var ref := CaptureDocFactory.make_doc(40, 30.0, false, false)
	var results: Dictionary = c.analyze_similarity(user, ref)
	var missing: Array = results["_missing_groups"]
	assert_eq(missing.size(), 0, "gabarito sem mãos não exige mãos")
	var global := float(results["_global_similarity_pct"])
	gut.p("global pose-only = %f" % global)
	assert_gt(global, 90.0, "só pose, idêntica, deve pontuar alto")


func test_static_hands_get_phase_zero() -> void:
	# Usuário com mãos visíveis mas paradas vs gabarito com movimento:
	# a fase deve ser 0 (não NAN ignorado) e puxar a nota do grupo pra baixo.
	var user := CaptureDocFactory.make_doc(60, 30.0, false, true)
	var ref := CaptureDocFactory.make_doc(60, 30.0, true, true)
	var results: Dictionary = c.analyze_similarity(user, ref)

	var right: Dictionary = results["Mão Direita"]
	var phase: Dictionary = right["phase"]
	assert_eq(int(phase["n_segments_a"]), 0, "mãos paradas = sem segmentos do usuário")
	assert_gt(int(phase["n_segments_b"]), 0, "gabarito em movimento tem segmentos")
	assert_almost_eq(float(phase["phase_similarity_pct"]), 0.0, 0.0001,
		"fase = 0 quando o gabarito se move e o usuário não")

	# Com a fase preservada no recálculo palma/direção, o grupo com fase 0
	# deve pontuar abaixo do mesmo grupo no doc idêntico.
	var identical: Dictionary = c.analyze_similarity(ref, ref)
	var sim_static := float(right["group_similarity_pct"])
	var sim_identical := float((identical["Mão Direita"] as Dictionary)["group_similarity_pct"])
	gut.p("mão direita: static=%f identical=%f" % [sim_static, sim_identical])
	assert_lt(sim_static, sim_identical - 4.0, "fase 0 precisa custar nota no grupo")


func test_regression_pins() -> void:
	# Valores exatos observados na versão atual do comparador (pinados na
	# introdução da suíte). Se um refactor mudar qualquer um deles, este
	# teste deve falhar e a mudança precisa ser justificada explicitamente.
	var moving := CaptureDocFactory.make_doc(60, 30.0, true, true)
	var static_doc := CaptureDocFactory.make_doc(60, 30.0, false, true)
	var empty_user := CaptureDocFactory.make_doc(60, 30.0, false, false)

	var identical := float(c.analyze_similarity(moving, moving)["_global_similarity_pct"])
	var cross := float(c.analyze_similarity(static_doc, moving)["_global_similarity_pct"])
	var motionless := float(c.analyze_similarity(empty_user, moving)["_global_similarity_pct"])
	gut.p("PIN identical  = %.4f" % identical)
	gut.p("PIN cross      = %.4f" % cross)
	gut.p("PIN motionless = %.4f" % motionless)

	# Valores observados na captura desta suíte. Mudou? Justifique e
	# re-pine conscientemente. Histórico:
	#   Sprint 1 (dados ausentes penalizados):  99.9877 / 94.5874 / 21.5587
	#   + One-Euro (item 13):                   99.9879 / 94.3726 / 21.5965
	#   + normalização de tronco (item 10):     99.9882 / 94.3112 / 21.5098
	#   + DTW com banda e caminho (item 7):     99.9882 / 94.5691 / 21.7677
	# A normalização mal move estes números porque a fábrica gera os dois
	# lados no mesmo formato de imagem — é justamente o caso em que ela é
	# quase identidade. O ganho aparece entre formatos diferentes, medido
	# em test_body_frame.gd (31.3° de artefato eliminados).
	assert_almost_eq(identical, 99.9882, 0.05)
	assert_almost_eq(cross, 94.5691, 0.05)
	assert_almost_eq(motionless, 21.7677, 0.05)
