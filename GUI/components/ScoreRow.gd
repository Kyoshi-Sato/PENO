@tool
class_name ScoreRow
extends PanelContainer
## Linha de diagnóstico por parâmetro do sinal (corpo, mão esquerda, mão
## direita), com nota e barra.
##
## Existe para cumprir a regra "quando estiver incorreto, explique o problema
## em vez de mostrar um ERRO". O `MotionComparator` já devolve
## `group_similarity_pct` e `detection_coverage` por grupo — antes esses dados
## eram calculados e jogados fora, e a tela de resultado mostrava só um número
## global sem dizer o que corrigir.

enum Level { GOOD, PARTIAL, WEAK, MISSING }

var _glyph: HSIcon
var _title: Label
var _hint: Label
var _bar: ProgressBar
var _value: Label


## `verbose` controla só a frase de orientação. Quando vários parâmetros vão
## mal ao mesmo tempo, repetir o mesmo conselho em cada linha vira ruído — a
## barra e a porcentagem já dizem o que aconteceu. Causas específicas (não
## detectado, cobertura parcial) ignoram esse flag e sempre se explicam.
static func create(title: String, pct: float, coverage: float, missing: bool,
		verbose: bool = true) -> ScoreRow:
	var row := ScoreRow.new()
	row._apply(title, pct, coverage, missing, verbose)
	return row


func _init() -> void:
	theme_type_variation = &"CardSunken"
	# PanelContainer nasce STOP (diferente dos outros Container, que nascem
	# PASS). Como este card é só apresentação, STOP fazia dele uma zona morta
	# para o arrasto do ScrollContainer que o contém.
	mouse_filter = Control.MOUSE_FILTER_PASS

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", DS.SPACE_XS)
	add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", DS.SPACE_XS + 2)
	box.add_child(head)

	_glyph = HSIcon.new()
	_glyph.custom_minimum_size = Vector2(44, 44)
	_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_glyph)

	_title = Label.new()
	_title.theme_type_variation = &"FieldLabel"
	_title.add_theme_color_override("font_color", DS.TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_title)

	_value = Label.new()
	_value.theme_type_variation = &"FieldLabel"
	_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_value)

	_bar = ProgressBar.new()
	_bar.theme_type_variation = &"ProgressBarThin"
	_bar.custom_minimum_size = Vector2(0, 14)
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	# Range herda MOUSE_FILTER_STOP; aqui a barra só informa, e parar o toque
	# só serviria para travar a rolagem da tela de resultado.
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_bar)

	_hint = Label.new()
	_hint.theme_type_variation = &"Caption"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)


func _apply(title: String, pct: float, coverage: float, missing: bool,
		verbose: bool = true) -> void:
	var level: Level = Level.GOOD
	if missing or coverage <= 0.0:
		level = Level.MISSING
	elif pct < 50.0:
		level = Level.WEAK
	elif pct < 75.0:
		level = Level.PARTIAL

	_title.text = title

	var tint: Color = DS.SUCCESS_INK
	match level:
		Level.MISSING:
			tint = DS.DANGER_INK
			_glyph.icon = HSIcon.Name.EYE_OFF
			_value.text = "não visto"
			# O texto diz o que fazer, não o que deu errado.
			_hint.text = "Não apareceu na câmera. Afaste-se um pouco e mantenha essa parte do corpo dentro do quadro."
		Level.WEAK:
			tint = DS.DANGER_INK
			_glyph.icon = HSIcon.Name.CROSS
			_value.text = "%d%%" % int(round(pct))
			_hint.text = "Bem diferente da referência. Assista ao sinal em câmera lenta antes de repetir."
		Level.PARTIAL:
			tint = DS.GOLD_INK
			_glyph.icon = HSIcon.Name.TARGET
			_value.text = "%d%%" % int(round(pct))
			_hint.text = "Perto. Ajuste o ritmo e a posição final do movimento."
		_:
			tint = DS.SUCCESS_INK
			_glyph.icon = HSIcon.Name.CHECK_CIRCLE
			_value.text = "%d%%" % int(round(pct))
			_hint.text = "Dentro do esperado."

	# Cobertura parcial é uma informação diferente de nota baixa: a pessoa
	# pode ter feito o sinal certo, mas só metade foi capturada.
	var partial_coverage: bool = level != Level.MISSING and coverage > 0.0 and coverage < 0.6
	if partial_coverage:
		_hint.text = "Só apareceu em parte da gravação (%d%% dos quadros). Fique todo o tempo dentro do quadro." % int(round(coverage * 100.0))

	# Causa específica sempre se explica; conselho genérico só na linha que
	# o chamador marcou como prioritária.
	var specific: bool = level == Level.MISSING or partial_coverage
	_hint.visible = specific or verbose

	_glyph.color = tint
	_value.add_theme_color_override("font_color", tint)
	_hint.add_theme_color_override("font_color", DS.TEXT_MUTED)

	_bar.add_theme_stylebox_override("fill", DS.fill(tint, DS.RADIUS_PILL))
	_bar.add_theme_stylebox_override("background",
		DS.fill(DS.alpha(tint, 0.14), DS.RADIUS_PILL))
	Motion.fill_bar(_bar, 0.0 if level == Level.MISSING else pct)
