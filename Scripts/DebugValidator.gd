class_name DebugValidator
extends SignValidator
## Validador falso: devolve uma nota escolhida à mão, sem câmera e sem análise.
##
## Existe porque exercitar a tela de resultado custava caro demais: abrir o
## app, escolher a lição, ver o avatar, esperar a contagem, executar o sinal,
## esperar de 1 a 8 segundos de análise — e ainda assim sem controle nenhum
## sobre a nota que ia sair. Testar o caso de 0 estrelas exigia errar de
## propósito; testar "não vimos suas mãos" exigia sair do quadro na hora certa.
##
## O formato do retorno imita `MotionComparatorValidator` campo a campo,
## incluindo o `details` por grupo, para que o detalhamento da tela seja
## exercitado de verdade e não só o número grande.
##
## Todo resultado daqui carrega `_debug: true`. É o que impede a tela de
## creditar XP e ofensiva por uma gravação que nunca existiu — ver
## `FeedbackState._fill_reward`.

## Chave que marca o resultado como sintético.
const DEBUG_FLAG := "_debug"

const GROUPS: Array[String] = ["Pose (corpo)", "Mão Esquerda", "Mão Direita"]

## Desvio de cada grupo em torno da nota global. Sem isto as três linhas do
## detalhamento saem idênticas e o "pior parâmetro" — que é quem recebe a
## frase de orientação — ficaria indefinido.
const GROUP_OFFSETS: Array[float] = [0.06, -0.03, -0.09]

## Nota global 0..1 que a tela deve exibir.
var precision: float = 0.0
## false reproduz o caminho de falha ("Não deu para avaliar").
var ok: bool = true
var error_message: String = ""
## Grupos exigidos pelo gabarito e nunca detectados. Com uma mão aqui, a tela
## troca o título por "Não vimos suas mãos".
var missing_groups: Array[String] = []
## Liga a nota explicativa de execução espelhada.
var mirrored: bool = false


static func create(p: float) -> DebugValidator:
	var v := DebugValidator.new()
	v.precision = clampf(p, 0.0, 1.0)
	return v


## Reproduz o caminho em que a validação nem roda (gravação vazia, gabarito
## fora do formato). É um caminho distinto de "tirou zero" e tem outra tela.
static func failure(msg: String = "gravação sintética sem frames") -> DebugValidator:
	var v := DebugValidator.new()
	v.ok = false
	v.error_message = msg
	return v


## Usuário fora do quadro: a análise roda, mas as mãos nunca apareceram.
static func missing_hands() -> DebugValidator:
	var v := DebugValidator.create(0.31)
	v.missing_groups = ["Mão Esquerda", "Mão Direita"]
	return v


func validate(_user_payload: Dictionary, _reference: Dictionary) -> Dictionary:
	if not ok:
		return {
			"precision": 0.0,
			"global_similarity_pct": 0.0,
			"details": {},
			"mirrored": false,
			"ok": false,
			"error": error_message,
			DEBUG_FLAG: true,
		}

	var details: Dictionary = {"_missing_groups": missing_groups.duplicate()}
	for i in range(GROUPS.size()):
		var nome: String = GROUPS[i]
		var ausente: bool = missing_groups.has(nome)
		# Grupo ausente vale 0% com cobertura 0 — é o que o comparador real
		# produz, e é o que faz a tela mostrar a linha de "não detectado".
		var pct: float = 0.0 if ausente else clampf(
			precision + GROUP_OFFSETS[i], 0.0, 1.0) * 100.0
		details[nome] = {
			"group_similarity_pct": pct,
			"detection_coverage": 0.0 if ausente else clampf(0.6 + precision * 0.4, 0.0, 1.0),
		}

	return {
		"precision": precision,
		"global_similarity_pct": precision * 100.0,
		"details": details,
		"mirrored": mirrored,
		"ok": true,
		"error": "",
		DEBUG_FLAG: true,
	}
