extends SceneTree
## Gera `res://themes/handsign.tres` a partir das constantes de `DS`.
##
##     godot --headless --script res://tools/build_theme.gd
##
## O tema é um artefato derivado: para mudar a identidade visual do app,
## edite `Scripts/ui/DS.gd` e rode este script. Editar o .tres na mão faz o
## próximo build sobrescrever a alteração.
##
## Substitui o antigo `Scripts/Themecreator.gd`, que era um @tool node que só
## rodava se alguém lembrasse de colocá-lo numa cena aberta no editor.

const OUT_PATH := "res://themes/handsign.tres"


func _init() -> void:
	var theme := Theme.new()

	# A fonte é a padrão da engine (Open Sans): sem serifa, alta legibilidade,
	# já embarcada. As duas fontes do repositório não servem para UI —
	# PlayfairDisplay é uma serifada de display com contraste alto (estava
	# aplicada em TODOS os botões) e Oi-Regular é uma display gorda decorativa.
	theme.default_font_size = DS.TEXT_BODY

	_build_labels(theme)
	_build_buttons(theme)
	_build_panels(theme)
	_build_progress(theme)
	_build_inputs(theme)
	_build_containers(theme)
	_build_scrollbars(theme)

	# Lido ANTES de gravar: o arquivo prestes a ser sobrescrito é a única
	# fonte do uid neste modo (ver _restore_uid).
	var uid := ResourceLoader.get_resource_uid(OUT_PATH)

	var err := ResourceSaver.save(theme, OUT_PATH)
	if err != OK:
		push_error("Falha ao salvar tema (%d)" % err)
		quit(1)
		return

	_restore_uid(uid)

	print("Tema gerado: %s" % OUT_PATH)
	quit(0)


## Devolve ao .tres o cabeçalho `uid://` que ele tinha antes da regravação.
##
## `ResourceSaver.save()` de um Theme recém-criado grava o arquivo sem uid, e
## as cenas que referenciam o tema por uid passariam a resolvê-lo só pelo
## caminho — com um aviso do editor a cada abertura. Como o uid do tema já
## está espalhado pelos .tscn do projeto, ele precisa ser estável entre builds.
func _restore_uid(uid: int) -> void:
	if uid == ResourceUID.INVALID_ID:
		return
	var err := ResourceSaver.set_uid(OUT_PATH, uid)
	if err != OK:
		push_warning("Não foi possível regravar o uid do tema (erro %d)" % err)


# ============================================================
#  TIPOGRAFIA
# ============================================================

func _label_variation(theme: Theme, name: String, size: int, color: Color,
		spacing: int = 0) -> void:
	theme.set_type_variation(name, "Label")
	theme.set_font_size("font_size", name, size)
	theme.set_color("font_color", name, color)
	if spacing != 0:
		theme.set_constant("line_spacing", name, spacing)


func _build_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", DS.TEXT)
	theme.set_constant("line_spacing", "Label", DS.LINE_SPACING)

	# Escala única do app. Se um tamanho não estiver aqui, ele não deveria
	# existir — antes o projeto tinha 14, 18, 20, 22, 26, 28, 32, 36, 40, 48,
	# 56, 60, 64, 72 e 220 espalhados por sobrescrita local em cada cena.
	_label_variation(theme, "Display", DS.TEXT_DISPLAY, DS.TEXT)
	_label_variation(theme, "H1", DS.TEXT_H1, DS.TEXT)
	_label_variation(theme, "H2", DS.TEXT_H2, DS.TEXT)
	_label_variation(theme, "H3", DS.TEXT_H3, DS.TEXT)
	_label_variation(theme, "Body", DS.TEXT_BODY, DS.TEXT, DS.LINE_SPACING)
	_label_variation(theme, "BodyMuted", DS.TEXT_BODY, DS.TEXT_MUTED, DS.LINE_SPACING)
	_label_variation(theme, "BodySm", DS.TEXT_BODY_SM, DS.TEXT_MUTED, DS.LINE_SPACING)
	_label_variation(theme, "FieldLabel", DS.TEXT_LABEL, DS.TEXT_MUTED)
	_label_variation(theme, "Caption", DS.TEXT_CAPTION, DS.TEXT_SUBTLE)

	# Sobre o azul da marca.
	_label_variation(theme, "OnPrimary", DS.TEXT_BODY, DS.TEXT_ON_PRIMARY, DS.LINE_SPACING)
	_label_variation(theme, "OnPrimaryH1", DS.TEXT_H1, DS.TEXT_ON_PRIMARY)
	_label_variation(theme, "OnPrimaryH2", DS.TEXT_H2, DS.TEXT_ON_PRIMARY)
	_label_variation(theme, "OnPrimaryMuted", DS.TEXT_BODY_SM, DS.TEXT_ON_PRIMARY_MUTED,
		DS.LINE_SPACING)

	# Números de métrica: sempre o mesmo tratamento em toda a UI.
	_label_variation(theme, "Metric", DS.TEXT_H1, DS.PRIMARY)
	_label_variation(theme, "MetricLabel", DS.TEXT_CAPTION, DS.TEXT_SUBTLE)

	# Numeral do countdown da captura, sobre a câmera.
	_label_variation(theme, "Countdown", DS.TEXT_COUNTDOWN, DS.TEXT_ON_PRIMARY)
	theme.set_color("font_outline_color", "Countdown", Color(0.05, 0.06, 0.16, 0.45))
	theme.set_constant("outline_size", "Countdown", 18)

	# Pills (categoria, nome do sinal).
	theme.set_type_variation("Pill", "Label")
	theme.set_font_size("font_size", "Pill", DS.TEXT_LABEL)
	theme.set_color("font_color", "Pill", DS.PRIMARY)
	theme.set_stylebox("normal", "Pill",
		DS.fill(DS.PRIMARY_TINT, DS.RADIUS_PILL, DS.SPACE_MD, DS.SPACE_XS + 4))

	theme.set_type_variation("PillOnDark", "Label")
	theme.set_font_size("font_size", "PillOnDark", DS.TEXT_H3)
	theme.set_color("font_color", "PillOnDark", DS.PRIMARY)
	theme.set_stylebox("normal", "PillOnDark",
		DS.fill(Color(1, 1, 1, 0.94), DS.RADIUS_PILL, DS.SPACE_LG, DS.SPACE_SM))


# ============================================================
#  BOTÕES
# ============================================================

## Registra as 4 caixas de estado de um botão a partir de uma cor base.
func _button_styles(theme: Theme, name: String, bg: Color, fg: Color,
		height: int = DS.BUTTON_H, radius: int = DS.RADIUS_XL,
		shadow: bool = false) -> void:
	var pad_h: int = DS.SPACE_LG
	var pad_v: int = DS.SPACE_SM

	var normal := DS.fill(bg, radius, pad_h, pad_v)
	if shadow:
		normal.shadow_color = DS.alpha(bg, 0.28)
		normal.shadow_size = 16
		normal.shadow_offset = Vector2(0, 6)

	var hover := DS.fill(DS.lighten(bg, 0.10), radius, pad_h, pad_v)
	if shadow:
		hover.shadow_color = DS.alpha(bg, 0.34)
		hover.shadow_size = 20
		hover.shadow_offset = Vector2(0, 8)

	# Pressionado escurece e perde a sombra: o botão "afunda" na superfície,
	# combinando com o encolhimento aplicado por Motion.attach_press().
	var pressed := DS.fill(DS.darken(bg, 0.10), radius, pad_h, pad_v)
	var disabled := DS.fill(DS.DISABLED_TINT, radius, pad_h, pad_v)
	var focus := DS.outlined(Color(0, 0, 0, 0), DS.ACCENT, radius, 3, pad_h, pad_v)

	theme.set_stylebox("normal", name, normal)
	theme.set_stylebox("hover", name, hover)
	theme.set_stylebox("pressed", name, pressed)
	theme.set_stylebox("disabled", name, disabled)
	theme.set_stylebox("focus", name, focus)

	theme.set_color("font_color", name, fg)
	theme.set_color("font_hover_color", name, fg)
	theme.set_color("font_pressed_color", name, fg)
	theme.set_color("font_focus_color", name, fg)
	theme.set_color("font_disabled_color", name, DS.DISABLED)
	theme.set_font_size("font_size", name, DS.TEXT_BUTTON)
	theme.set_constant("h_separation", name, DS.SPACE_SM)
	theme.set_constant("minimum_character_width", name, 0)


func _build_buttons(theme: Theme) -> void:
	# Botão base = tonal. É o mais comum e o menos barulhento; a versão
	# preenchida fica reservada para a ação principal da tela.
	_button_styles(theme, "Button", DS.PRIMARY_TINT, DS.PRIMARY)

	theme.set_type_variation("PrimaryButton", "Button")
	_button_styles(theme, "PrimaryButton", DS.PRIMARY, DS.TEXT_ON_PRIMARY,
		DS.BUTTON_H, DS.RADIUS_XL, true)

	# Ciano é a cor de ação: texto escuro por cima, porque #00E5FF com texto
	# branco dá ~1.6:1 de contraste.
	theme.set_type_variation("AccentButton", "Button")
	_button_styles(theme, "AccentButton", DS.ACCENT, DS.PRIMARY_DARK,
		DS.BUTTON_H, DS.RADIUS_XL, true)

	# Ação destrutiva (apagar dados). O fundo é DANGER_INK, não o DANGER puro:
	# #FF6B6B com texto branco dá ~2.5:1 de contraste.
	theme.set_type_variation("DangerButton", "Button")
	_button_styles(theme, "DangerButton", DS.DANGER_INK, DS.TEXT_ON_PRIMARY,
		DS.BUTTON_H, DS.RADIUS_XL, true)

	theme.set_type_variation("SecondaryButton", "Button")
	var sec_normal := DS.outlined(DS.SURFACE, DS.HAIRLINE_STRONG, DS.RADIUS_XL, 2,
		DS.SPACE_LG, DS.SPACE_SM)
	theme.set_stylebox("normal", "SecondaryButton", sec_normal)
	theme.set_stylebox("hover", "SecondaryButton",
		DS.outlined(DS.PRIMARY_TINT, DS.PRIMARY_TINT_STRONG, DS.RADIUS_XL, 2,
			DS.SPACE_LG, DS.SPACE_SM))
	theme.set_stylebox("pressed", "SecondaryButton",
		DS.outlined(DS.PRIMARY_TINT_STRONG, DS.PRIMARY_TINT_STRONG, DS.RADIUS_XL, 2,
			DS.SPACE_LG, DS.SPACE_SM))
	theme.set_stylebox("disabled", "SecondaryButton",
		DS.outlined(DS.SURFACE, DS.HAIRLINE, DS.RADIUS_XL, 2, DS.SPACE_LG, DS.SPACE_SM))
	theme.set_stylebox("focus", "SecondaryButton",
		DS.outlined(Color(0, 0, 0, 0), DS.ACCENT, DS.RADIUS_XL, 3, DS.SPACE_LG, DS.SPACE_SM))
	theme.set_color("font_color", "SecondaryButton", DS.PRIMARY)
	theme.set_color("font_hover_color", "SecondaryButton", DS.PRIMARY)
	theme.set_color("font_pressed_color", "SecondaryButton", DS.PRIMARY_DARK)
	theme.set_color("font_disabled_color", "SecondaryButton", DS.DISABLED)
	theme.set_font_size("font_size", "SecondaryButton", DS.TEXT_BUTTON)
	theme.set_constant("h_separation", "SecondaryButton", DS.SPACE_SM)

	# Terciário: sem caixa. Para "Cancelar", "Ver módulos", "Pular".
	theme.set_type_variation("GhostButton", "Button")
	var ghost_pad := DS.fill(Color(0, 0, 0, 0), DS.RADIUS_XL, DS.SPACE_MD, DS.SPACE_SM)
	theme.set_stylebox("normal", "GhostButton", ghost_pad)
	theme.set_stylebox("hover", "GhostButton",
		DS.fill(DS.PRIMARY_TINT, DS.RADIUS_XL, DS.SPACE_MD, DS.SPACE_SM))
	theme.set_stylebox("pressed", "GhostButton",
		DS.fill(DS.PRIMARY_TINT_STRONG, DS.RADIUS_XL, DS.SPACE_MD, DS.SPACE_SM))
	theme.set_stylebox("disabled", "GhostButton", ghost_pad)
	theme.set_stylebox("focus", "GhostButton",
		DS.outlined(Color(0, 0, 0, 0), DS.ACCENT, DS.RADIUS_XL, 3, DS.SPACE_MD, DS.SPACE_SM))
	theme.set_color("font_color", "GhostButton", DS.TEXT_MUTED)
	theme.set_color("font_hover_color", "GhostButton", DS.PRIMARY)
	theme.set_color("font_pressed_color", "GhostButton", DS.PRIMARY_DARK)
	theme.set_color("font_disabled_color", "GhostButton", DS.DISABLED)
	theme.set_font_size("font_size", "GhostButton", DS.TEXT_BUTTON_SM)

	# Ghost sobre a câmera / sobre o azul.
	theme.set_type_variation("GhostButtonOnDark", "Button")
	theme.set_stylebox("normal", "GhostButtonOnDark",
		DS.fill(Color(1, 1, 1, 0.14), DS.RADIUS_PILL, DS.SPACE_MD, DS.SPACE_SM))
	theme.set_stylebox("hover", "GhostButtonOnDark",
		DS.fill(Color(1, 1, 1, 0.24), DS.RADIUS_PILL, DS.SPACE_MD, DS.SPACE_SM))
	theme.set_stylebox("pressed", "GhostButtonOnDark",
		DS.fill(Color(1, 1, 1, 0.32), DS.RADIUS_PILL, DS.SPACE_MD, DS.SPACE_SM))
	theme.set_stylebox("disabled", "GhostButtonOnDark",
		DS.fill(Color(1, 1, 1, 0.08), DS.RADIUS_PILL, DS.SPACE_MD, DS.SPACE_SM))
	theme.set_stylebox("focus", "GhostButtonOnDark",
		DS.outlined(Color(0, 0, 0, 0), DS.ACCENT, DS.RADIUS_PILL, 3, DS.SPACE_MD, DS.SPACE_SM))
	theme.set_color("font_color", "GhostButtonOnDark", DS.TEXT_ON_PRIMARY)
	theme.set_color("font_hover_color", "GhostButtonOnDark", DS.TEXT_ON_PRIMARY)
	theme.set_color("font_pressed_color", "GhostButtonOnDark", DS.TEXT_ON_PRIMARY)
	theme.set_color("font_disabled_color", "GhostButtonOnDark", DS.TEXT_ON_PRIMARY_MUTED)
	theme.set_font_size("font_size", "GhostButtonOnDark", DS.TEXT_BODY_SM)

	# Botão só de ícone: círculo. O conteúdo vem de um HSIcon filho.
	theme.set_type_variation("IconButton", "Button")
	theme.set_stylebox("normal", "IconButton", DS.fill(Color(0, 0, 0, 0), DS.RADIUS_PILL))
	theme.set_stylebox("hover", "IconButton", DS.fill(DS.PRIMARY_TINT, DS.RADIUS_PILL))
	theme.set_stylebox("pressed", "IconButton",
		DS.fill(DS.PRIMARY_TINT_STRONG, DS.RADIUS_PILL))
	theme.set_stylebox("disabled", "IconButton", DS.fill(Color(0, 0, 0, 0), DS.RADIUS_PILL))
	theme.set_stylebox("focus", "IconButton",
		DS.outlined(Color(0, 0, 0, 0), DS.ACCENT, DS.RADIUS_PILL, 3))

	theme.set_type_variation("IconButtonSurface", "Button")
	theme.set_stylebox("normal", "IconButtonSurface",
		DS.outlined(DS.SURFACE, DS.HAIRLINE, DS.RADIUS_PILL, 2))
	theme.set_stylebox("hover", "IconButtonSurface",
		DS.outlined(DS.PRIMARY_TINT, DS.PRIMARY_TINT_STRONG, DS.RADIUS_PILL, 2))
	theme.set_stylebox("pressed", "IconButtonSurface",
		DS.fill(DS.PRIMARY_TINT_STRONG, DS.RADIUS_PILL))
	theme.set_stylebox("disabled", "IconButtonSurface",
		DS.outlined(DS.SURFACE, DS.HAIRLINE, DS.RADIUS_PILL, 2))
	theme.set_stylebox("focus", "IconButtonSurface",
		DS.outlined(Color(0, 0, 0, 0), DS.ACCENT, DS.RADIUS_PILL, 3))

	theme.set_type_variation("IconButtonOnDark", "Button")
	theme.set_stylebox("normal", "IconButtonOnDark",
		DS.fill(Color(1, 1, 1, 0.16), DS.RADIUS_PILL))
	theme.set_stylebox("hover", "IconButtonOnDark",
		DS.fill(Color(1, 1, 1, 0.26), DS.RADIUS_PILL))
	theme.set_stylebox("pressed", "IconButtonOnDark",
		DS.fill(Color(1, 1, 1, 0.34), DS.RADIUS_PILL))
	theme.set_stylebox("disabled", "IconButtonOnDark",
		DS.fill(Color(1, 1, 1, 0.08), DS.RADIUS_PILL))
	theme.set_stylebox("focus", "IconButtonOnDark",
		DS.outlined(Color(0, 0, 0, 0), DS.ACCENT, DS.RADIUS_PILL, 3))

	# Item da barra de navegação: sem caixa em nenhum estado (o estado ativo
	# é comunicado pela cor do ícone e por um indicador desenhado no item).
	theme.set_type_variation("NavButton", "Button")
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "NavButton", DS.empty())


# ============================================================
#  SUPERFÍCIES
# ============================================================

func _build_panels(theme: Theme) -> void:
	# Card branco elevado — o padrão.
	theme.set_stylebox("panel", "PanelContainer", DS.card())
	theme.set_stylebox("panel", "Panel", DS.card())

	theme.set_type_variation("CardFlat", "PanelContainer")
	theme.set_stylebox("panel", "CardFlat",
		DS.outlined(DS.SURFACE, DS.HAIRLINE, DS.RADIUS_LG, 2, DS.SPACE_MD, DS.SPACE_MD))

	# Segundo nível dentro de um card branco (métricas, checklist).
	theme.set_type_variation("CardSunken", "PanelContainer")
	theme.set_stylebox("panel", "CardSunken",
		DS.fill(DS.SURFACE_SUNKEN, DS.RADIUS_MD, DS.SPACE_MD, DS.SPACE_MD))

	theme.set_type_variation("CardHero", "PanelContainer")
	var hero := DS.card(DS.PRIMARY, DS.RADIUS_XL, DS.SPACE_LG, true)
	hero.shadow_color = DS.alpha(DS.PRIMARY, 0.30)
	theme.set_stylebox("panel", "CardHero", hero)

	theme.set_type_variation("CardAccent", "PanelContainer")
	theme.set_stylebox("panel", "CardAccent",
		DS.fill(DS.ACCENT_TINT, DS.RADIUS_LG, DS.SPACE_MD, DS.SPACE_MD))

	theme.set_type_variation("CardReward", "PanelContainer")
	theme.set_stylebox("panel", "CardReward",
		DS.fill(DS.VIOLET_TINT, DS.RADIUS_LG, DS.SPACE_MD, DS.SPACE_MD))

	theme.set_type_variation("CardSuccess", "PanelContainer")
	theme.set_stylebox("panel", "CardSuccess",
		DS.fill(DS.SUCCESS_TINT, DS.RADIUS_LG, DS.SPACE_MD, DS.SPACE_MD))

	theme.set_type_variation("CardDanger", "PanelContainer")
	theme.set_stylebox("panel", "CardDanger",
		DS.fill(DS.DANGER_TINT, DS.RADIUS_LG, DS.SPACE_MD, DS.SPACE_MD))

	# Folha inferior — cartão de ação ancorado no rodapé.
	theme.set_type_variation("Sheet", "PanelContainer")
	theme.set_stylebox("panel", "Sheet", DS.sheet())

	# Superfície translúcida sobre a câmera.
	theme.set_type_variation("Glass", "PanelContainer")
	theme.set_stylebox("panel", "Glass",
		DS.fill(Color(1, 1, 1, 0.96), DS.RADIUS_LG, DS.SPACE_MD, DS.SPACE_MD))

	theme.set_type_variation("GlassDark", "PanelContainer")
	theme.set_stylebox("panel", "GlassDark",
		DS.fill(Color(0.08, 0.09, 0.18, 0.55), DS.RADIUS_LG, DS.SPACE_MD, DS.SPACE_MD))

	# Barra de chrome do topo da lição. Precisa de superfície própria porque
	# fica sobre o avatar 3D (cujo cenário é livre) e sobre a câmera — sem
	# ela, o indicador de etapa some em qualquer fundo claro ou saturado.
	theme.set_type_variation("ChromeBar", "PanelContainer")
	theme.set_stylebox("panel", "ChromeBar",
		DS.fill(Color(1, 1, 1, 0.94), DS.RADIUS_PILL, DS.SPACE_MD, DS.SPACE_XS))

	# Barra de navegação inferior.
	theme.set_type_variation("NavBar", "PanelContainer")
	var nav := StyleBoxFlat.new()
	nav.bg_color = DS.SURFACE
	nav.corner_radius_top_left = DS.RADIUS_LG
	nav.corner_radius_top_right = DS.RADIUS_LG
	nav.border_width_top = 2
	nav.border_color = DS.HAIRLINE
	nav.shadow_color = DS.SHADOW
	nav.shadow_size = 18
	nav.shadow_offset = Vector2(0, -4)
	nav.content_margin_left = DS.SPACE_SM
	nav.content_margin_right = DS.SPACE_SM
	nav.content_margin_top = DS.SPACE_SM
	nav.content_margin_bottom = DS.SPACE_SM
	nav.anti_aliasing = true
	theme.set_stylebox("panel", "NavBar", nav)

	# Contêiner sem pintura, só para agrupar layout.
	theme.set_type_variation("Bare", "PanelContainer")
	theme.set_stylebox("panel", "Bare", DS.empty())

	theme.set_stylebox("panel", "PopupPanel",
		DS.card(DS.SURFACE, DS.RADIUS_LG, DS.SPACE_MD, true))
	theme.set_stylebox("panel", "AcceptDialog", DS.fill(DS.BG, 0, DS.SPACE_MD, DS.SPACE_MD))
	theme.set_stylebox("embedded_border", "Window",
		DS.card(DS.BG, DS.RADIUS_LG, DS.SPACE_MD, true))
	theme.set_color("title_color", "Window", DS.TEXT)
	theme.set_font_size("title_font_size", "Window", DS.TEXT_H3)


# ============================================================
#  PROGRESSO
# ============================================================

func _progress_variation(theme: Theme, name: String, fill_color: Color,
		height: int, track: Color = DS.PRIMARY_TINT) -> void:
	if name != "ProgressBar":
		theme.set_type_variation(name, "ProgressBar")
	theme.set_stylebox("background", name, DS.fill(track, DS.RADIUS_PILL))
	theme.set_stylebox("fill", name, DS.fill(fill_color, DS.RADIUS_PILL))
	theme.set_constant("min_height", name, height)
	theme.set_color("font_color", name, DS.TEXT_MUTED)
	theme.set_font_size("font_size", name, DS.TEXT_CAPTION)


func _build_progress(theme: Theme) -> void:
	# Ciano = progresso de aprendizado (a cor de ação da marca).
	_progress_variation(theme, "ProgressBar", DS.ACCENT, 20)
	# Roxo = XP / nível, para diferenciar recompensa de avanço de conteúdo.
	_progress_variation(theme, "XPBar", DS.VIOLET, 24, DS.VIOLET_TINT)
	_progress_variation(theme, "ProgressBarThin", DS.ACCENT, 12)
	_progress_variation(theme, "ProgressBarOnDark", DS.ACCENT, 20,
		Color(1, 1, 1, 0.22))


# ============================================================
#  ENTRADAS
# ============================================================

func _build_inputs(theme: Theme) -> void:
	theme.set_color("font_color", "LineEdit", DS.TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", DS.TEXT_SUBTLE)
	theme.set_color("caret_color", "LineEdit", DS.PRIMARY)
	theme.set_font_size("font_size", "LineEdit", DS.TEXT_BODY)
	theme.set_stylebox("normal", "LineEdit",
		DS.outlined(DS.SURFACE, DS.HAIRLINE_STRONG, DS.RADIUS_MD, 2, DS.SPACE_MD, DS.SPACE_SM))
	theme.set_stylebox("focus", "LineEdit",
		DS.outlined(DS.SURFACE, DS.ACCENT, DS.RADIUS_MD, 3, DS.SPACE_MD, DS.SPACE_SM))
	theme.set_stylebox("read_only", "LineEdit",
		DS.outlined(DS.SURFACE_SUNKEN, DS.HAIRLINE, DS.RADIUS_MD, 2, DS.SPACE_MD, DS.SPACE_SM))

	theme.set_color("font_color", "TextEdit", DS.TEXT)
	theme.set_font_size("font_size", "TextEdit", DS.TEXT_BODY)
	theme.set_stylebox("normal", "TextEdit",
		DS.outlined(DS.SURFACE, DS.HAIRLINE_STRONG, DS.RADIUS_MD, 2, DS.SPACE_MD, DS.SPACE_SM))
	theme.set_stylebox("focus", "TextEdit",
		DS.outlined(DS.SURFACE, DS.ACCENT, DS.RADIUS_MD, 3, DS.SPACE_MD, DS.SPACE_SM))


# ============================================================
#  CONTÊINERES
# ============================================================

func _build_containers(theme: Theme) -> void:
	# Ritmo vertical padrão. Cenas ainda podem sobrescrever, mas o default
	# deixa de ser 4px (que era o que fazia tudo parecer colado).
	theme.set_constant("separation", "BoxContainer", DS.SPACE_SM)
	theme.set_constant("separation", "VBoxContainer", DS.SPACE_SM)
	theme.set_constant("separation", "HBoxContainer", DS.SPACE_SM)
	theme.set_constant("h_separation", "GridContainer", DS.SPACE_SM)
	theme.set_constant("v_separation", "GridContainer", DS.SPACE_SM)
	theme.set_constant("separation", "HSeparator", DS.SPACE_SM)
	theme.set_stylebox("separator", "HSeparator",
		DS.fill(DS.HAIRLINE, 0, 0, 0))


func _build_scrollbars(theme: Theme) -> void:
	# Trilho invisível, polegar discreto: a lista é o conteúdo, não a barra.
	var track := DS.fill(Color(0, 0, 0, 0), DS.RADIUS_PILL)
	var grabber := DS.fill(DS.alpha(DS.PRIMARY, 0.22), DS.RADIUS_PILL)
	var grabber_hl := DS.fill(DS.alpha(DS.PRIMARY, 0.38), DS.RADIUS_PILL)
	for bar: String in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", bar, track)
		theme.set_stylebox("scroll_focus", bar, track)
		theme.set_stylebox("grabber", bar, grabber)
		theme.set_stylebox("grabber_highlight", bar, grabber_hl)
		theme.set_stylebox("grabber_pressed", bar, grabber_hl)
	theme.set_stylebox("panel", "ScrollContainer", DS.empty())
	theme.set_stylebox("focus", "ScrollContainer", DS.empty())
