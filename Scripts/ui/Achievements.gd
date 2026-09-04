@abstract
class_name Achievements
extends Object
## Conquistas do HandSign.
##
## Todas são DERIVADAS do progresso que já existe (lições concluídas, sinais
## com nota máxima, ofensiva, nível, precisão média) — nenhuma exige um novo
## campo persistido, e nenhuma pode ficar dessincronizada do progresso real.
##
## Cada entrada: { id, title, description, icon, tone, unlocked, progress }
## `progress` é 0..1 e alimenta a barra das conquistas ainda bloqueadas, para
## que uma conquista trancada informe o quanto falta em vez de só existir.


static func list() -> Array[Dictionary]:
	var completed: int = Global.count_completed_lessons()
	var mastered: int = Global.get_mastered_signs()
	var streak: int = Global.get_best_streak()
	var level: int = Global.get_level()
	var precision: float = Global.get_average_precision()
	var practices: int = Global.get_practice_count()

	var out: Array[Dictionary] = []

	out.append(_entry("first_lesson", "Primeiros passos",
		"Conclua sua primeira lição.", HSIcon.Name.SPARKLE,
		StatChip.Tone.ACCENT, completed, 1))

	out.append(_entry("first_practice", "Mão na massa",
		"Grave sua primeira prática diante da câmera.", HSIcon.Name.HAND,
		StatChip.Tone.ACCENT, practices, 1))

	out.append(_entry("perfect_sign", "Execução perfeita",
		"Faça um sinal com 3 estrelas.", HSIcon.Name.STAR,
		StatChip.Tone.GOLD, mastered, 1))

	out.append(_entry("five_signs", "Vocabulário",
		"Domine 5 sinais com nota máxima.", HSIcon.Name.LESSONS,
		StatChip.Tone.VIOLET, mastered, 5))

	out.append(_entry("streak_3", "Constância",
		"Pratique 3 dias seguidos.", HSIcon.Name.FLAME,
		StatChip.Tone.GOLD, streak, 3))

	out.append(_entry("streak_7", "Semana cheia",
		"Pratique 7 dias seguidos.", HSIcon.Name.TROPHY,
		StatChip.Tone.GOLD, streak, 7))

	out.append(_entry("level_3", "Sinalizando",
		"Alcance o nível 3.", HSIcon.Name.BOLT,
		StatChip.Tone.VIOLET, level, 3))

	# Só entra na lista depois da primeira prática: sem tentativa nenhuma a
	# precisão média é -1 e a conquista apareceria com 0% de progresso, o que
	# passaria a impressão errada de que o usuário já errou.
	if precision >= 0.0:
		out.append(_entry("accuracy", "Mão firme",
			"Mantenha 80% de precisão média.", HSIcon.Name.TARGET,
			StatChip.Tone.SUCCESS, int(round(precision * 100.0)), 80))

	return out


static func unlocked_count() -> int:
	var n: int = 0
	for a: Dictionary in list():
		if bool(a["unlocked"]):
			n += 1
	return n


static func _entry(id: String, title: String, description: String,
		icon: HSIcon.Name, tone: StatChip.Tone, value: int, goal: int) -> Dictionary:
	return {
		"id": id,
		"title": title,
		"description": description,
		"icon": icon,
		"tone": tone,
		"unlocked": value >= goal,
		"progress": clampf(float(value) / float(maxi(goal, 1)), 0.0, 1.0),
		"value": value,
		"goal": goal,
	}
