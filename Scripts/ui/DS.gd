@abstract
class_name DS
extends Object
## Design System do HandSign — fonte única de verdade visual.
##
## Todas as telas leem cores, espaçamentos, tipografia e raios daqui, e o tema
## em `res://themes/handsign.tres` é GERADO a partir destas constantes por
## `tools/build_theme.gd`. Nunca edite o .tres à mão: edite este arquivo e rode
##
##     godot --headless --script res://tools/build_theme.gd
##
## ESCALA — atenção
## ----------------
## O viewport do projeto é 1080x1920 com stretch `canvas_items`, então 1 unidade
## de UI equivale a ~1 pixel físico num aparelho 1080p, ou seja ~0,37 dp numa
## tela de densidade 3x. É por isso que os números abaixo parecem enormes:
## `TEXT_BODY = 40` são ~15 dp na mão do usuário. Qualquer valor "de desktop"
## (16, 20, 24) resulta em texto ilegível no celular.
##
## Regra prática: unidades = dp * 2.7.

# ============================================================
#  COR
# ============================================================

## Azul da marca. Fundo de ações primárias, cabeçalhos, estados travados.
const PRIMARY := Color("#243C79")
const PRIMARY_DARK := Color("#1A2C5B")
const PRIMARY_LIGHT := Color("#3C579E")
## Tinta clara do azul — fundos de chips, trilhos, superfícies tonais.
const PRIMARY_TINT := Color("#E5EAF8")
const PRIMARY_TINT_STRONG := Color("#CBD5F0")

## Ciano de ação. Progresso, estado ativo, foco, destaque interativo.
const ACCENT := Color("#00E5FF")
## Versão escurecida do ciano, legível como texto sobre fundo claro
## (o #00E5FF puro tem contraste ~1.6:1 sobre branco — nunca use em texto).
const ACCENT_INK := Color("#00758A")
const ACCENT_TINT := Color("#DEFAFF")

## Roxo de conquista. XP, badges, momentos especiais — usar com parcimônia.
const VIOLET := Color("#A829FF")
const VIOLET_INK := Color("#7A16C0")
const VIOLET_TINT := Color("#F1E2FF")

## Fundo geral do app. Nunca use branco puro como fundo de tela.
const BG := Color("#F5F7FF")
## Superfícies elevadas: cards, modais, painéis.
const SURFACE := Color("#FFFFFF")
## Superfície de segundo nível dentro de um card branco.
const SURFACE_SUNKEN := Color("#F2F5FE")

const TEXT := Color("#14163A")
## Azul-cinza dessaturado, ~5.3:1 sobre SURFACE.
const TEXT_MUTED := Color("#5A6288")
## Apoio e legendas, ~3.4:1 — só para texto de rótulo, nunca para leitura.
const TEXT_SUBTLE := Color("#868DAF")
const TEXT_ON_PRIMARY := Color("#FFFFFF")
const TEXT_ON_PRIMARY_MUTED := Color(1.0, 1.0, 1.0, 0.72)

## Fio de 1px que separa sem pesar. Preferir a sombras.
const HAIRLINE := Color("#E2E7F6")
const HAIRLINE_STRONG := Color("#CFD6EC")

const SUCCESS := Color("#4ADE80")
const SUCCESS_INK := Color("#15803D")
const SUCCESS_TINT := Color("#E4FBEC")

const DANGER := Color("#FF6B6B")
const DANGER_INK := Color("#C2352F")
const DANGER_TINT := Color("#FFE9E9")

## Recompensa / gamificação (estrelas, XP conquistado).
const GOLD := Color("#FFD978")
const GOLD_INK := Color("#946A0B")
const GOLD_TINT := Color("#FFF6E0")

## Estado desabilitado / bloqueado.
const DISABLED := Color("#C3C9DE")
const DISABLED_TINT := Color("#EDEFF7")

## Sombra padrão — uma só, muito suave. Elevação se comunica por cor e fio,
## não por empilhar sombras diferentes em cada tela.
const SHADOW := Color(0.08, 0.11, 0.29, 0.10)
const SHADOW_STRONG := Color(0.08, 0.11, 0.29, 0.16)


# ============================================================
#  ESPAÇAMENTO  (múltiplos de 8)
# ============================================================

const SPACE_XXS := 4
const SPACE_XS := 8
const SPACE_SM := 16
const SPACE_MD := 24
const SPACE_LG := 32
const SPACE_XL := 48
const SPACE_2XL := 64
const SPACE_3XL := 96

## Margem lateral padrão de tela.
const GUTTER := 40


# ============================================================
#  RAIO
# ============================================================

const RADIUS_SM := 16
const RADIUS_MD := 24
const RADIUS_LG := 32
const RADIUS_XL := 44
## Cartão-folha ancorado no rodapé (só cantos de cima).
const RADIUS_SHEET := 56
const RADIUS_PILL := 999


# ============================================================
#  TIPOGRAFIA
# ============================================================

## Números grandes: contador de XP, precisão no resultado.
const TEXT_DISPLAY := 104
## Título de tela / resultado.
const TEXT_H1 := 72
## Título de card e de seção.
const TEXT_H2 := 54
## Subtítulo, nome de item em lista.
const TEXT_H3 := 44
## Leitura padrão.
const TEXT_BODY := 40
## Texto de apoio, descrições secundárias.
const TEXT_BODY_SM := 34
## Rótulos, chips, legendas de métrica.
const TEXT_LABEL := 30
## Menor tamanho aceitável (~9 dp) — só para rótulo curto sob um número.
const TEXT_CAPTION := 26

const TEXT_BUTTON := 42
const TEXT_BUTTON_SM := 34

## Numeral do countdown na captura — deliberadamente fora da escala.
const TEXT_COUNTDOWN := 320

## Entrelinha aplicada a textos de leitura com autowrap.
const LINE_SPACING := 8


# ============================================================
#  ALVOS DE TOQUE
# ============================================================

## Mínimo confortável (~48 dp).
const TOUCH_MIN := 130
const BUTTON_H := 150
const BUTTON_H_SM := 112
const ICON_BUTTON := 120
const NAV_H := 200


# ============================================================
#  MOVIMENTO
# ============================================================

## Retorno tátil de um toque.
const DUR_INSTANT := 0.09
## Mudança de estado de um componente.
const DUR_FAST := 0.18
## Transição entre telas/estados, barra de progresso.
const DUR_BASE := 0.28
## Celebração (XP subindo, conquista).
const DUR_SLOW := 0.55

## Escala do botão pressionado.
const PRESS_SCALE := 0.96


# ============================================================
#  HELPERS DE STYLEBOX
#  Usados pelo gerador de tema e por componentes que precisam de um
#  stylebox em runtime (ex.: chip que muda de cor conforme o estado).
# ============================================================

## Retângulo preenchido com raio uniforme. `pad` é o content margin
## horizontal; o vertical sai proporcional se `pad_v` for negativo.
static func fill(
	color: Color,
	radius: int = RADIUS_MD,
	pad_h: int = 0,
	pad_v: int = -1
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = float(pad_v) if pad_v >= 0 else float(pad_h) * 0.6
	sb.content_margin_bottom = sb.content_margin_top
	sb.anti_aliasing = true
	return sb


## Superfície com fio de contorno em vez de sombra.
static func outlined(
	color: Color,
	border: Color,
	radius: int = RADIUS_MD,
	width: int = 2,
	pad_h: int = 0,
	pad_v: int = -1
) -> StyleBoxFlat:
	var sb := fill(color, radius, pad_h, pad_v)
	sb.set_border_width_all(width)
	sb.border_color = border
	return sb


## Card elevado. Uma sombra só, sempre a mesma direção.
static func card(
	color: Color = SURFACE,
	radius: int = RADIUS_LG,
	pad: int = SPACE_MD,
	strong: bool = false
) -> StyleBoxFlat:
	var sb := fill(color, radius, pad, pad)
	sb.shadow_color = SHADOW_STRONG if strong else SHADOW
	sb.shadow_size = 20 if strong else 14
	sb.shadow_offset = Vector2(0, 8 if strong else 5)
	return sb


## Folha ancorada no rodapé — arredondada só em cima.
static func sheet(color: Color = SURFACE, radius: int = RADIUS_SHEET) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.shadow_color = SHADOW_STRONG
	sb.shadow_size = 28
	sb.shadow_offset = Vector2(0, -6)
	sb.anti_aliasing = true
	return sb


static func empty() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


# ============================================================
#  HELPERS DE COR
# ============================================================

static func alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


## Mistura em direção ao branco — para estados hover sobre cor sólida.
static func lighten(c: Color, amount: float) -> Color:
	return c.lerp(Color.WHITE, amount)


static func darken(c: Color, amount: float) -> Color:
	return c.lerp(Color.BLACK, amount)


## Primeira letra maiúscula, o resto preservado.
##
## `String.capitalize()` do Godot coloca maiúscula em TODA palavra, então
## "bom dia" virava "Bom Dia" no título do sinal e na pílula da captura —
## caixa de título em inglês aplicada a um nome em português.
static func sentence_case(text: String) -> String:
	var t := text.strip_edges()
	if t.is_empty():
		return t
	return t.substr(0, 1).to_upper() + t.substr(1)


## Cor semântica de uma nota de 0 a 3 estrelas.
static func score_color(stars: int) -> Color:
	if stars >= 3:
		return SUCCESS_INK
	if stars == 2:
		return ACCENT_INK
	if stars == 1:
		return GOLD_INK
	return DANGER_INK
