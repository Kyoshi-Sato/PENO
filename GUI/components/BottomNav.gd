@tool
class_name BottomNav
extends PanelContainer
## Barra de navegação inferior.
##
## Quatro destinos + a ação principal ("Praticar") no centro, elevada e em
## ciano. Antes eram cinco Buttons de texto de peso igual, com um "📷 Praticar"
## indistinguível de "Perfil" — nada dizia qual era a ação principal do app.

signal tab_selected(id: StringName)

## Quatro destinos, todos com tela real por trás. O "Perfil" da versão
## anterior foi removido em vez de virar mais um botão que não leva a lugar
## nenhum — os dados de perfil que existem moram na tela de Progresso.
const TABS: Array[Dictionary] = [
	{"id": &"home", "icon": HSIcon.Name.HOME, "label": "Início"},
	{"id": &"lessons", "icon": HSIcon.Name.LESSONS, "label": "Trilha"},
	{"id": &"practice", "icon": HSIcon.Name.CAMERA, "label": "Praticar"},
	{"id": &"progress", "icon": HSIcon.Name.PROGRESS, "label": "Progresso"},
]

## Índice do destino que é a ação principal (recebe o tratamento elevado).
const PRIMARY_INDEX := 2

@export var active: StringName = &"home":
	set(v):
		active = v
		_sync()

var _items: Array[Dictionary] = []


func _init() -> void:
	theme_type_variation = &"NavBar"
	custom_minimum_size = Vector2(0, DS.NAV_H)
	_build()


func _ready() -> void:
	_apply_safe_bottom()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_apply_safe_bottom):
		vp.size_changed.connect(_apply_safe_bottom)


## A barra de gestos do Android come a borda inferior. O recuo entra como
## padding DENTRO do stylebox da nav, não como margem fora dela: assim o
## fundo branco continua encostando na borda da tela e só o conteúdo sobe.
## Empurrar a nav inteira para cima deixaria uma faixa da cor de fundo
## aparecendo por baixo dela.
func _apply_safe_bottom() -> void:
	var inset := ScreenFrame.safe_insets(self)
	if inset.w <= 0:
		return
	var base: StyleBox = get_theme_stylebox("panel", "NavBar")
	if base == null:
		return
	var sb: StyleBox = base.duplicate()
	sb.content_margin_bottom = base.content_margin_bottom + float(inset.w)
	add_theme_stylebox_override("panel", sb)


func _build() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DS.SPACE_XXS)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)

	for i in range(TABS.size()):
		var spec: Dictionary = TABS[i]
		var is_primary: bool = i == PRIMARY_INDEX

		var button := Button.new()
		button.theme_type_variation = &"NavButton"
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, DS.TOUCH_MIN)
		row.add_child(button)

		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", DS.SPACE_XXS)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(box)

		# A ação principal ganha um disco ciano; os demais, só o ícone.
		var puck := PanelContainer.new()
		puck.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		puck.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(puck)

		var glyph := HSIcon.new()
		glyph.icon = spec["icon"]
		glyph.custom_minimum_size = Vector2(56, 56) if is_primary else Vector2(52, 52)
		puck.add_child(glyph)

		var label := Label.new()
		label.theme_type_variation = &"Caption"
		label.text = String(spec["label"])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(label)

		if is_primary:
			puck.add_theme_stylebox_override("panel",
				DS.fill(DS.ACCENT, DS.RADIUS_PILL, DS.SPACE_SM + 2, DS.SPACE_SM + 2))
			glyph.color = DS.PRIMARY_DARK
			label.add_theme_color_override("font_color", DS.ACCENT_INK)
		else:
			puck.add_theme_stylebox_override("panel", DS.empty())

		var tab_id: StringName = spec["id"]
		button.pressed.connect(func() -> void: _on_tab(tab_id))
		if not Engine.is_editor_hint():
			Motion.attach_press(button)

		_items.append({
			"id": tab_id,
			"glyph": glyph,
			"label": label,
			"puck": puck,
			"primary": is_primary,
		})

	_sync()


func _on_tab(id: StringName) -> void:
	tab_selected.emit(id)


func _sync() -> void:
	for item: Dictionary in _items:
		if bool(item["primary"]):
			continue   # a ação principal já tem tratamento fixo
		var glyph: HSIcon = item["glyph"]
		var label: Label = item["label"]
		var puck: PanelContainer = item["puck"]
		var is_active: bool = StringName(item["id"]) == active

		glyph.color = DS.PRIMARY if is_active else DS.TEXT_SUBTLE
		glyph.filled = false
		label.add_theme_color_override("font_color",
			DS.PRIMARY if is_active else DS.TEXT_SUBTLE)
		# Estado ativo = pastilha azul-clara atrás do ícone. Sem sublinhado,
		# sem trocar o ícone por uma variante preenchida.
		puck.add_theme_stylebox_override("panel",
			DS.fill(DS.PRIMARY_TINT, DS.RADIUS_PILL, DS.SPACE_SM, DS.SPACE_XS)
			if is_active else DS.fill(Color(0, 0, 0, 0), DS.RADIUS_PILL,
				DS.SPACE_SM, DS.SPACE_XS))
