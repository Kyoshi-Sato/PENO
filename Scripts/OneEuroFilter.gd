class_name OneEuroFilter
extends RefCounted
## Filtro One-Euro (Casiez, Roussel & Vogel — CHI 2012), padrão de facto
## para suavizar landmarks do MediaPipe.
##
## A ideia: um passa-baixa cuja frequência de corte SOBE com a velocidade
## do sinal. Parado, corta agressivamente (mata o jitter); em movimento,
## abre a banda (não atrasa o gesto). Um passa-baixa fixo teria que
## escolher entre tremer ou atrasar.
##
## Uso (um filtro por escalar — x, y e z são independentes):
##   var f := OneEuroFilter.new()
##   var suave := f.filter(valor, timestamp_ms)
##
## Para filtrar uma captura inteira use `filter_frames()`.

## Corte mínimo, em Hz — vale quando o landmark está parado.
## Calibrado (2026-08-11) sobre dados reais: gabarito da API (12 fps, mão
## direita, 42 séries) e captura do celular (25 fps, pose, 16 séries).
## Critério: reduzir o ruído de alta frequência mantendo o sinal MAIS
## próximo da trajetória real (média móvel centrada) do que o sinal cru.
##
##   mc=1.5 β=2  ruído -56%/-83%   fidelidade +33%/+10%   <- escolhido
##   mc=0.5 β=2  ruído -82%/-88%   fidelidade +22%/-15%   (suaviza demais)
##   mc=2.0 β=0  ruído -54%/-84%   fidelidade +49%/-41%   (sem adaptação
##               quebra no movimento rápido do celular — justifica o
##               One-Euro em vez de um passa-baixa fixo)
const DEFAULT_MIN_CUTOFF := 1.5
## Ganho de adaptação à velocidade, em coordenadas normalizadas de imagem
## ([0,1]/s). Medidas reais: mão sinalizando ~0.27 un/s (mediana) e picos
## de ~1.3 un/s, então β=2 eleva o corte de 1.5 Hz para ~2 a ~4 Hz durante
## o gesto — preserva a dinâmica sem deixar passar o tremor.
const DEFAULT_BETA := 2.0
## Corte do passa-baixa aplicado à própria estimativa de velocidade.
const DEFAULT_D_CUTOFF := 1.0

## dt assumido quando os timestamps não são utilizáveis (iguais ou
## regressivos): 30 fps.
const FALLBACK_DT := 1.0 / 30.0

## Intervalo sem amostras a partir do qual o estado é descartado. Uma
## mão que sumiu e voltou noutro lugar não deve ser interpolada.
const GAP_RESET_MS := 500.0

var min_cutoff: float
var beta: float
var d_cutoff: float

var _x_prev: float = NAN
var _dx_prev: float = 0.0
var _t_prev_ms: float = NAN


func _init(
		p_min_cutoff: float = DEFAULT_MIN_CUTOFF,
		p_beta: float = DEFAULT_BETA,
		p_d_cutoff: float = DEFAULT_D_CUTOFF) -> void:
	min_cutoff = p_min_cutoff
	beta = p_beta
	d_cutoff = p_d_cutoff


## Descarta o estado — a próxima amostra passa direto.
func reset() -> void:
	_x_prev = NAN
	_dx_prev = 0.0
	_t_prev_ms = NAN


## Filtra uma amostra. `timestamp_ms` deve ser monotônico crescente.
func filter(value: float, timestamp_ms: float) -> float:
	if is_nan(_x_prev):
		_x_prev = value
		_dx_prev = 0.0
		_t_prev_ms = timestamp_ms
		return value

	var dt: float = (timestamp_ms - _t_prev_ms) / 1000.0
	if dt <= 0.0:
		dt = FALLBACK_DT

	# Derivada suavizada (a velocidade crua é ruidosa demais para pilotar
	# o corte adaptativo).
	var dx: float = (value - _x_prev) / dt
	var dx_hat: float = _lerp_alpha(dx, _dx_prev, _alpha(d_cutoff, dt))

	# Corte adaptativo: rápido = passa mais, parado = filtra mais.
	var cutoff: float = min_cutoff + beta * absf(dx_hat)
	var x_hat: float = _lerp_alpha(value, _x_prev, _alpha(cutoff, dt))

	_x_prev = x_hat
	_dx_prev = dx_hat
	_t_prev_ms = timestamp_ms
	return x_hat


## Fator do passa-baixa exponencial para um corte (Hz) e um passo (s).
static func _alpha(cutoff: float, dt: float) -> float:
	var time_constant: float = 1.0 / (TAU * cutoff)
	return 1.0 / (1.0 + time_constant / dt)


static func _lerp_alpha(value: float, prev: float, alpha: float) -> float:
	return alpha * value + (1.0 - alpha) * prev


# ─────────────────────────────────────────────
#  FILTRAGEM DE CAPTURAS INTEIRAS
# ─────────────────────────────────────────────

## Aplica One-Euro a todos os landmarks de uma sequência de frames no
## formato {frame, timestamp_ms, hands, pose}. Cada landmark tem filtros
## independentes por eixo; o estado é descartado após um sumiço longo.
## Não muta a entrada.
##
## `zero_phase` (padrão) roda uma segunda passada de trás para frente,
## cancelando o atraso do filtro. Só é possível porque a análise é
## offline (a captura já terminou); num preview em tempo real use
## zero_phase=false. Sem isso, a 12 fps o atraso chega a ~2 quadros e
## afasta o sinal filtrado da trajetória real mais do que o próprio
## ruído — medido, não suposto.
static func filter_frames(
		frames: Array,
		min_cutoff: float = DEFAULT_MIN_CUTOFF,
		beta: float = DEFAULT_BETA,
		zero_phase: bool = true) -> Array:

	var forward: Array = _filter_pass(frames, min_cutoff, beta)
	if not zero_phase:
		return forward
	# Espelhar no tempo duas vezes devolve a ordem e os timestamps
	# originais; entre elas, o filtro roda no sentido inverso.
	var backward: Array = _filter_pass(
		_reversed_in_time(forward), min_cutoff, beta)
	return _reversed_in_time(backward)


## Inverte a ordem dos frames espelhando os timestamps (span - t), de modo
## que continuem crescentes. Aplicar duas vezes é a identidade.
static func _reversed_in_time(frames: Array) -> Array:
	if frames.size() < 2:
		return frames.duplicate()
	var first: float = float((frames[0] as Dictionary).get("timestamp_ms", 0))
	var last: float = float((frames[frames.size() - 1] as Dictionary).get("timestamp_ms", 0))
	var span: float = first + last

	var out: Array = []
	for i in range(frames.size() - 1, -1, -1):
		var f: Dictionary = (frames[i] as Dictionary).duplicate()
		f["timestamp_ms"] = span - float(f.get("timestamp_ms", 0))
		out.append(f)
	return out


static func _filter_pass(
		frames: Array,
		min_cutoff: float,
		beta: float) -> Array:

	# chave "fonte:id:eixo" -> OneEuroFilter
	var filters: Dictionary = {}
	# chave "fonte" -> timestamp da última amostra vista
	var last_seen_ms: Dictionary = {}

	var out: Array = []
	for frame: Variant in frames:
		var f: Dictionary = (frame as Dictionary).duplicate()
		var ts: float = float(f.get("timestamp_ms", 0))

		var pose_out: Array = []
		for p: Variant in f.get("pose", []) as Array:
			var entry: Dictionary = (p as Dictionary).duplicate()
			entry["landmarks"] = _filter_landmark_list(
				entry.get("landmarks", []) as Array,
				"pose", ts, filters, last_seen_ms, min_cutoff, beta)
			pose_out.append(entry)
		f["pose"] = pose_out

		var hands_out: Array = []
		for h: Variant in f.get("hands", []) as Array:
			var hand: Dictionary = (h as Dictionary).duplicate()
			var source: String = "hand_%s" % String(hand.get("handedness", "?"))
			hand["landmarks"] = _filter_landmark_list(
				hand.get("landmarks", []) as Array,
				source, ts, filters, last_seen_ms, min_cutoff, beta)
			hands_out.append(hand)
		f["hands"] = hands_out

		out.append(f)
	return out


static func _filter_landmark_list(
		landmarks: Array,
		source: String,
		timestamp_ms: float,
		filters: Dictionary,
		last_seen_ms: Dictionary,
		min_cutoff: float,
		beta: float) -> Array:

	if landmarks.is_empty():
		return []

	# Sumiço longo desta fonte: recomeça do zero.
	var previous: float = float(last_seen_ms.get(source, NAN))
	if not is_nan(previous) and (timestamp_ms - previous) > GAP_RESET_MS:
		for key: String in filters.keys():
			if key.begins_with(source + ":"):
				(filters[key] as OneEuroFilter).reset()
	last_seen_ms[source] = timestamp_ms

	var out: Array = []
	for lm: Variant in landmarks:
		var d: Dictionary = (lm as Dictionary).duplicate()
		var id: int = int(d.get("id", -1))
		for axis: String in ["x", "y", "z"]:
			var raw: Variant = d.get(axis)
			if not (raw is float or raw is int):
				continue
			var key: String = "%s:%d:%s" % [source, id, axis]
			if not filters.has(key):
				filters[key] = OneEuroFilter.new(min_cutoff, beta)
			d[axis] = (filters[key] as OneEuroFilter).filter(float(raw), timestamp_ms)
		out.append(d)
	return out
