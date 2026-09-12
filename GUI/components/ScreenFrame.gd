@tool
class_name ScreenFrame
extends MarginContainer
## Moldura responsiva de uma tela.
##
## Resolve duas coisas que nenhum layout de container resolve sozinho:
##
## 1. SAFE AREA — notch, barra de status e barra de gestos do Android comem
##    as bordas do viewport. `DisplayServer.get_display_safe_area()` diz
##    quanto, em pixels físicos; aqui isso vira unidades de canvas e entra
##    como margem, somado à margem de design que a cena já declara.
##
## 2. LARGURA MÁXIMA — com `stretch/aspect = expand`, uma tela larga
##    (tablet, ou a janela do editor em paisagem) entrega um viewport de
##    2000+ unidades de largura. Sem teto, um card de lição viraria uma
##    faixa de 2000px com o texto perdido no meio. O conteúdo passa a ser
##    centralizado e limitado a `DS.MAX_CONTENT_WIDTH`.
##
## A margem de design continua declarada na cena, via
## `theme_override_constants/margin_*`. Este script lê esses valores UMA vez
## como base e soma os ajustes por cima — então a cena permanece legível no
## editor e nada é duplicado em código.

## Bordas que recebem o recuo de safe area. A folha inferior de uma tela de
## lição, por exemplo, só precisa do recuo de baixo.
@export var apply_top: bool = true
@export var apply_bottom: bool = true
@export var apply_sides: bool = true
## Centraliza e limita a largura do conteúdo em telas largas.
@export var limit_width: bool = true

var _base := Vector4i.ZERO
var _captured: bool = false
var _is_applying: bool = false


func _ready() -> void:
	_capture_base()

	# `resized` do próprio container é o gatilho principal: em `_ready` o
	# `size` ainda é o valor pré-layout (tipicamente 0), então calcular a
	# folga de largura aqui daria sempre "não sobra nada" e o limite de
	# largura nunca entraria em telas largas.
	if not resized.is_connected(_apply):
		resized.connect(_apply)

	# O viewport muda ao girar o aparelho e ao redimensionar a janela no
	# desktop. Nem toda mudança de viewport altera o tamanho deste nó (uma
	# moldura ancorada ao topo, por exemplo), então os dois sinais somam.
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_apply):
		vp.size_changed.connect(_apply)

	_apply()


## Guarda a margem de design declarada na cena antes de qualquer sobrescrita
## nossa — depois do primeiro `_apply`, `get_theme_constant` já devolveria o
## valor somado, e as margens cresceriam a cada redimensionamento.
func _capture_base() -> void:
	if _captured:
		return
	_base = Vector4i(
		get_theme_constant("margin_left"),
		get_theme_constant("margin_top"),
		get_theme_constant("margin_right"),
		get_theme_constant("margin_bottom"))
	_captured = true


func _apply() -> void:
	if not _captured or _is_applying:
		return
	_is_applying = true

	var inset := safe_insets(self)
	var side_pad: int = 0

	if limit_width:
		var extra: float = size.x - float(DS.MAX_CONTENT_WIDTH)
		if extra > 0.0:
			side_pad = int(extra * 0.5)

	var target_left := _base.x + side_pad + (inset.x if apply_sides else 0)
	var target_right := _base.z + side_pad + (inset.z if apply_sides else 0)
	var target_top := _base.y + (inset.y if apply_top else 0)
	var target_bottom := _base.w + (inset.w if apply_bottom else 0)

	if get_theme_constant("margin_left") != target_left:
		add_theme_constant_override("margin_left", target_left)
	if get_theme_constant("margin_right") != target_right:
		add_theme_constant_override("margin_right", target_right)
	if get_theme_constant("margin_top") != target_top:
		add_theme_constant_override("margin_top", target_top)
	if get_theme_constant("margin_bottom") != target_bottom:
		add_theme_constant_override("margin_bottom", target_bottom)

	_is_applying = false


## Recuos de safe area em UNIDADES DE CANVAS (não pixels físicos).
##
## A conversão é feita por fração da janela em vez de dividir pela escala do
## stretch: a fração vale para qualquer modo de stretch e não depende de
## consultar a transformada do canvas.
static func safe_insets(ct: Control) -> Vector4i:
	# Safe area só existe em aparelhos. No desktop
	# `get_display_safe_area()` devolve a tela inteira, e comparar isso com o
	# tamanho da JANELA produziria recuos negativos ou absurdos.
	if not is_mobile():
		return Vector4i.ZERO
	if ct == null or not ct.is_inside_tree():
		return Vector4i.ZERO

	var win := DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return Vector4i.ZERO

	var safe := DisplayServer.get_display_safe_area()
	var vp := ct.get_viewport_rect().size

	return Vector4i(
		int(float(safe.position.x) / float(win.x) * vp.x),
		int(float(safe.position.y) / float(win.y) * vp.y),
		int(float(win.x - safe.end.x) / float(win.x) * vp.x),
		int(float(win.y - safe.end.y) / float(win.y) * vp.y))


static func is_mobile() -> bool:
	var os_name := OS.get_name()
	return os_name == "Android" or os_name == "iOS"
