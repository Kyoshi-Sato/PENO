extends SceneTree
## Mede, em dados REAIS, o efeito das duas correções geométricas do
## Sprint 3 sobre a comparação captura-do-celular x gabarito-da-API.
##
## A captura usada foi gravada ANTES da canonicalização de espelhamento
## entrar no app (câmera frontal alimenta o MediaPipe espelhado), então
## dá para medir os dois efeitos de forma independente:
##   - espelhamento: CaptureMirror.mirror_frames (o que o app faz hoje
##     na exportação)
##   - normalização: BodyFrame (referencial do tronco)
##
## Uso: godot --headless -s tools/medir_real.gd -- <captura.json> <licao.json>

## ATENÇÃO ao interpretar a linha "espelho": ela só responde qual
## convenção casa com o gabarito se a captura for do usuário EXECUTANDO
## o mesmo sinal. Numa captura qualquer (pessoa parada), a diferença
## entre "cru" e "canônico" mede só a assimetria da postura e não decide
## nada. Ver docs/REVISAO_TECNICA.md, item 6.


func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Arquivo não encontrado: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("uso: godot --headless -s tools/medir_real.gd -- <captura.json> <licao.json>")
		print("  captura.json: exportada pelo app (adb exec-out run-as ... cat)")
		print("  licao.json:   resposta de GET /exercicio/{id}")
		quit(1)
		return

	var capture := _load(args[0])
	var lesson := _load(args[1])
	if capture.is_empty() or lesson.is_empty():
		quit(1)
		return

	# O endpoint /exercicio/{id} devolve os sinais com o gabarito embutido.
	var sinal: Dictionary = (lesson["sinais"] as Array)[0] as Dictionary
	var raw_reference: Variant = sinal["json_sinal"]
	if raw_reference is String:
		raw_reference = JSON.parse_string(raw_reference)
	var reference: Dictionary = raw_reference as Dictionary

	print("captura: %d frames | gabarito '%s': %d frames\n" % [
		(capture["frames"] as Array).size(),
		String(sinal.get("nome_sinal", "?")),
		(reference["frames"] as Array).size()])

	print("%-12s %-14s %-10s %-10s" % ["espelho", "normalização", "pose", "global"])
	for mirrored: bool in [false, true]:
		var doc: Dictionary = capture.duplicate()
		if mirrored:
			doc["frames"] = CaptureMirror.mirror_frames(capture["frames"] as Array)
		for normalized: bool in [false, true]:
			var comparator := MotionComparator.new()
			comparator.enable_body_normalization = normalized
			var results: Dictionary = comparator.analyze_similarity(doc, reference)
			var pose: Dictionary = results["Pose (corpo)"] as Dictionary
			print("%-12s %-14s %-10.2f %-10.2f" % [
				"canônico" if mirrored else "cru",
				"ON" if normalized else "OFF",
				float(pose["group_similarity_pct"]),
				float(results["_global_similarity_pct"])])
	quit()
