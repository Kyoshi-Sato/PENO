class_name ComparisonCard
extends PanelContainer

## Card oficial de Diagnóstico Biomecânico da Forma da Mão (TCC).
## Exibe a identificação neural do sinal, análise articular dedo a dedo,
## dicas de ajuste postural e telemetria de validação.

var _lbl_title: Label
var _lbl_subtitle: Label
var _banner_panel: PanelContainer
var _lbl_target_sign: Label
var _lbl_detected_sign: Label
var _lbl_match_badge: Label
var _lbl_hands_detected: Label
var _hands_detail_box: VBoxContainer
var _finger_grid: GridContainer
var _lbl_hints: Label
var _lbl_telemetry: Label


func _init() -> void:
	theme_type_variation = &"CardSunken"
	mouse_filter = Control.MOUSE_FILTER_PASS

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 20)
	add_child(root_vbox)

	# --- 1. Cabeçalho Oficial ---
	var header_box := VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 6)
	root_vbox.add_child(header_box)

	_lbl_title = Label.new()
	_lbl_title.theme_type_variation = &"H2"
	_lbl_title.text = "Avaliação Biomecânica da Forma da Mão"
	header_box.add_child(_lbl_title)

	_lbl_subtitle = Label.new()
	_lbl_subtitle.theme_type_variation = &"Caption"
	_lbl_subtitle.text = "Diagnóstico postural em tempo real com Rede Neural (Classificador TCC)"
	header_box.add_child(_lbl_subtitle)

	# --- 2. Banner de Correspondência da Postura ---
	_banner_panel = PanelContainer.new()
	_banner_panel.theme_type_variation = &"CardFlat"
	_banner_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(_banner_panel)

	var banner_vbox := VBoxContainer.new()
	banner_vbox.add_theme_constant_override("separation", 10)
	_banner_panel.add_child(banner_vbox)

	var match_row := HBoxContainer.new()
	match_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner_vbox.add_child(match_row)

	var signs_col := VBoxContainer.new()
	signs_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	signs_col.add_theme_constant_override("separation", 4)
	match_row.add_child(signs_col)

	var target_row := HBoxContainer.new()
	var lbl_t_title := Label.new()
	lbl_t_title.theme_type_variation = &"Caption"
	lbl_t_title.text = "Sinal Alvo (Gabarito): "
	target_row.add_child(lbl_t_title)
	_lbl_target_sign = Label.new()
	_lbl_target_sign.theme_type_variation = &"FieldLabel"
	_lbl_target_sign.text = "Carregando…"
	target_row.add_child(_lbl_target_sign)
	signs_col.add_child(target_row)

	var detected_row := HBoxContainer.new()
	var lbl_d_title := Label.new()
	lbl_d_title.theme_type_variation = &"Caption"
	lbl_d_title.text = "Postura Reconhecida: "
	detected_row.add_child(lbl_d_title)
	_lbl_detected_sign = Label.new()
	_lbl_detected_sign.theme_type_variation = &"FieldLabel"
	_lbl_detected_sign.text = "Carregando…"
	detected_row.add_child(_lbl_detected_sign)
	signs_col.add_child(detected_row)

	_lbl_match_badge = Label.new()
	_lbl_match_badge.theme_type_variation = &"FieldLabel"
	_lbl_match_badge.text = "Aguardando…"
	_lbl_match_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	match_row.add_child(_lbl_match_badge)

	_lbl_hands_detected = Label.new()
	_lbl_hands_detected.theme_type_variation = &"Caption"
	_lbl_hands_detected.text = "Mão Avaliada: -"
	banner_vbox.add_child(_lbl_hands_detected)

	_hands_detail_box = VBoxContainer.new()
	_hands_detail_box.add_theme_constant_override("separation", 4)
	banner_vbox.add_child(_hands_detail_box)

	# --- 3. Diagnóstico Articular Dedo a Dedo ---
	var fingers_section := VBoxContainer.new()
	fingers_section.add_theme_constant_override("separation", 10)
	root_vbox.add_child(fingers_section)

	var finger_heading := Label.new()
	finger_heading.theme_type_variation = &"FieldLabel"
	finger_heading.text = "Diagnóstico Articular Dedo a Dedo:"
	fingers_section.add_child(finger_heading)

	_finger_grid = GridContainer.new()
	_finger_grid.columns = 2
	_finger_grid.add_theme_constant_override("h_separation", 24)
	_finger_grid.add_theme_constant_override("v_separation", 8)
	_finger_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fingers_section.add_child(_finger_grid)

	# --- 4. Orientações e Dicas Biomecânicas ---
	var hints_box := VBoxContainer.new()
	hints_box.add_theme_constant_override("separation", 6)
	root_vbox.add_child(hints_box)

	var hints_heading := Label.new()
	hints_heading.theme_type_variation = &"FieldLabel"
	hints_heading.text = "💡 Orientações Anatômicas para Aperfeiçoamento:"
	hints_box.add_child(hints_heading)

	_lbl_hints = Label.new()
	_lbl_hints.theme_type_variation = &"BodyMuted"
	_lbl_hints.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_hints.text = "Aguardando análise postural..."
	hints_box.add_child(_lbl_hints)

	# --- 5. Telemetria Técnica e Comparativo (Rodapé) ---
	var tele_box := VBoxContainer.new()
	tele_box.add_theme_constant_override("separation", 4)
	root_vbox.add_child(tele_box)

	_lbl_telemetry = Label.new()
	_lbl_telemetry.theme_type_variation = &"Caption"
	_lbl_telemetry.add_theme_color_override("font_color", DS.TEXT_SUBTLE)
	_lbl_telemetry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_telemetry.text = ""
	tele_box.add_child(_lbl_telemetry)


## Popula a tela com os dados do modelo neural de IA e telemetria comparativa.
func populate(legacy_result: Dictionary, ai_result: Dictionary) -> void:
	_clear_container(_hands_detail_box)
	_clear_container(_finger_grid)

	# 1. Dados do Sinal Base e Reconhecimento
	var sign_name: String = String(ai_result.get("sign_name", ""))
	var base_letter: String = String(ai_result.get("base_letter", sign_name))
	var base_display := "Sinal '%s'" % base_letter if not base_letter.is_empty() else "Sinal Base"
	_lbl_target_sign.text = base_display

	var letter: String = String(ai_result.get("dominant_letter", ""))
	var letter_display := letter if not letter.is_empty() else "Não identificado"
	_lbl_detected_sign.text = "Sinal '%s'" % letter_display

	# 2. Avaliação de Correspondência
	var exp_code: String = String(ai_result.get("expected_code", "0000000000"))
	var dom_code: String = String(ai_result.get("dominant_code", "0000000000"))
	var is_exact_match: bool = (not letter.is_empty() and letter == base_letter) or (dom_code == exp_code and dom_code != "0000000000")
	var ai_prec: float = float(ai_result.get("hand_precision", 0.0)) * 100.0

	if is_exact_match or ai_prec >= 85.0:
		_lbl_match_badge.text = "🎯 Postura Correta!"
		_lbl_match_badge.add_theme_color_override("font_color", DS.SUCCESS_INK)
	elif ai_prec >= 60.0:
		_lbl_match_badge.text = "⚠️ Postura Parcial"
		_lbl_match_badge.add_theme_color_override("font_color", DS.GOLD_INK)
	else:
		_lbl_match_badge.text = "❌ Postura a Ajustar"
		_lbl_match_badge.add_theme_color_override("font_color", DS.DANGER_INK)

	# 3. Informações das Mãos Avaliadas
	var both_hands: bool = bool(ai_result.get("both_hands_detected", false))
	var has_right: bool = bool(ai_result.get("has_right", false))
	var has_left: bool = bool(ai_result.get("has_left", false))

	if both_hands:
		_lbl_hands_detected.text = "Mãos Avaliadas: Ambas as Mãos (Direita + Esquerda)"
		var r_dict: Dictionary = ai_result.get("right_hand", {}) as Dictionary
		var l_dict: Dictionary = ai_result.get("left_hand", {}) as Dictionary
		var r_let: String = String(r_dict.get("dominant_letter", ""))
		var l_let: String = String(l_dict.get("dominant_letter", ""))
		var r_prec: float = float(r_dict.get("hand_precision", 0.0)) * 100.0
		var l_prec: float = float(l_dict.get("hand_precision", 0.0)) * 100.0
		_hands_detail_box.add_child(_create_stat_label("  • Mão Direita:", "Sinal '%s' (%.1f%%)" % [r_let if not r_let.is_empty() else "N/A", r_prec]))
		_hands_detail_box.add_child(_create_stat_label("  • Mão Esquerda:", "Sinal '%s' (%.1f%%)" % [l_let if not l_let.is_empty() else "N/A", l_prec]))
	elif has_left and not has_right:
		_lbl_hands_detected.text = "Mão Avaliada: Mão Esquerda (sinalizador canhoto)"
	else:
		_lbl_hands_detected.text = "Mão Avaliada: Mão Direita (mão dominante)"

	# 4. Diagnóstico Dedo a Dedo
	var finger_status: Dictionary = ai_result.get("finger_status", {}) as Dictionary
	var finger_names: Dictionary = {
		"thumb": "Polegar",
		"index": "Indicador",
		"middle": "Médio",
		"ring": "Anelar",
		"pinky": "Mínimo",
		"spread": "Abertura dos Dedos"
	}
	for f_key: String in finger_names:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var f_lbl := Label.new()
		f_lbl.theme_type_variation = &"Caption"
		f_lbl.text = finger_names[f_key] + ":"
		f_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(f_lbl)

		var st: String = String(finger_status.get(f_key, "OK"))
		var val_lbl := Label.new()
		val_lbl.theme_type_variation = &"FieldLabel"
		if st == "OK":
			val_lbl.text = "✅ Correto"
			val_lbl.add_theme_color_override("font_color", DS.SUCCESS_INK)
		else:
			val_lbl.text = "❌ Ajustar"
			val_lbl.add_theme_color_override("font_color", DS.DANGER_INK)
		row.add_child(val_lbl)

		_finger_grid.add_child(row)

	# 5. Dicas de Correção
	var hints: Array = ai_result.get("hints", []) as Array
	if hints.is_empty() or is_exact_match:
		_lbl_hints.text = "• Excelente postura! Os dedos e a abertura estão alinhados com o gabarito."
	else:
		var text := ""
		for h: Variant in hints:
			if not text.is_empty():
				text += "\n"
			text += "• " + String(h)
		_lbl_hints.text = text

	# 6. Telemetria Técnica e Referência Comparativa
	var ai_conf: float = float(ai_result.get("avg_confidence", 0.0)) * 100.0
	var det_frames: int = int(ai_result.get("detected_frames", 0))
	var tot_frames: int = int(ai_result.get("total_frames", 0))
	var leg_prec: float = float(legacy_result.get("precision", 0.0)) * 100.0

	_lbl_telemetry.text = "Telemetria do Modelo: Confiança da IA: %.1f%%  |  Estabilidade: %d/%d quadros  |  Ref. Geométrica: %.1f%%" % [
		ai_conf, det_frames, tot_frames, leg_prec
	]


func _clear_container(c: Node) -> void:
	for child in c.get_children():
		child.queue_free()


func _create_stat_label(label: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var l := Label.new()
	l.theme_type_variation = &"Caption"
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)

	var v := Label.new()
	v.theme_type_variation = &"FieldLabel"
	v.text = value
	row.add_child(v)

	return row
