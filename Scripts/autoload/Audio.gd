extends Node
## Efeitos sonoros do HandSign. Cadastre como Autoload com nome "Audio".
##
## O QUE ESTE SISTEMA NÃO FAZ
## --------------------------
## Nenhum som daqui carrega informação exclusiva. Todo momento sonorizado já
## tem um equivalente visual na tela — a contagem tem o numeral, o resultado
## tem as estrelas e o anel, o XP tem o chip. Isso não é zelo genérico de
## acessibilidade: este é um app de LIBRAS, e parte do público-alvo não vai
## ouvir nada. O som é reforço do que já está sendo dito na tela, e o app
## continua completo com ele desligado.
##
## COMO USAR
##   Audio.play(Audio.Cue.TAP)
##   Audio.play(Audio.Cue.STAR, 1.26)   # transpõe a mesma amostra
##
## Falha silenciosa é intencional: um efeito sonoro que não carregou não pode
## derrubar uma tela. Cada problema avisa uma vez em push_warning e o app
## segue mudo naquele som.

enum Cue {
	TAP,             ## toque em qualquer botão
	COUNTDOWN,       ## pip da contagem 3-2-1
	RECORD_START,    ## a captura começou
	CAPTURE_DONE,    ## a captura terminou
	STAR,            ## uma estrela revelada
	XP,              ## XP creditado
	RETRY,           ## resultado sem estrelas
	FAILURE,         ## não deu para avaliar
	LESSON_DONE,     ## última lição do módulo concluída
	LEVEL_UP,        ## subiu de nível
}

const AUDIO_DIR := "res://assets/audio/"
## Barramento dedicado (ver default_bus_layout.tres). Deixa o volume dos
## efeitos ajustável sem tocar no Master, que é onde a captura de áudio do
## GDMP também vive.
const BUS_NAME := &"SFX"

## arquivo + ganho de cada som. O ganho é o que equilibra a mistura: todos os
## WAVs saem do gerador normalizados no mesmo pico, então sem esta coluna o
## clique de botão sairia tão alto quanto a fanfarra de fim de lição.
##
## Os valores subiram 2 dB em bloco quando a paleta desceu uma oitava. Não é
## gosto: som grave com a mesma amplitude é ouvido como mais baixo (curvas de
## igual sonoridade), e o alto-falante do celular ainda atenua a região por
## conta própria. O equilíbrio RELATIVO entre os sons é o mesmo.
const CUES: Dictionary = {
	Cue.TAP: {"file": "toque", "db": -18.0},
	Cue.COUNTDOWN: {"file": "contagem", "db": -8.0},
	Cue.RECORD_START: {"file": "gravar", "db": -5.0},
	Cue.CAPTURE_DONE: {"file": "captura_fim", "db": -6.0},
	Cue.STAR: {"file": "estrela", "db": -4.0},
	Cue.XP: {"file": "xp", "db": -7.0},
	Cue.RETRY: {"file": "tentar_de_novo", "db": -6.0},
	Cue.FAILURE: {"file": "falha", "db": -7.0},
	Cue.LESSON_DONE: {"file": "licao_concluida", "db": -3.0},
	Cue.LEVEL_UP: {"file": "nivel", "db": -2.0},
}

## Quantos sons podem soar ao mesmo tempo. O pior caso real é a tela de
## resultado: três estrelas em cascata + XP, e o usuário tocando um botão
## antes de a cauda da terceira estrela morrer.
const VOICES := 6

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _next_voice: int = 0
## Um aviso por som quebrado, não um por toque.
var _warned: Dictionary = {}


func _ready() -> void:
	# O áudio nunca deve segurar uma troca de cena nem parar com a árvore
	# pausada — a contagem da gravação roda com o app inteiro ativo, mas a
	# fanfarra de fim de lição toca durante o fade de saída da cena.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_load_streams()
	_build_voices()


# ═══════════════════════════════════════════════════════════
#  API
# ═══════════════════════════════════════════════════════════

## Toca um efeito. `pitch` transpõe a amostra (1.5 = uma quinta acima) e é o
## que permite três notas diferentes de estrela a partir de um arquivo só.
func play(cue: Cue, pitch: float = 1.0) -> void:
	if not Global.is_sound_enabled():
		return

	var stream: AudioStream = _streams.get(cue, null) as AudioStream
	if stream == null:
		_warn_once(cue, "som ausente")
		return

	var player := _take_voice()
	if player == null:
		return

	player.stream = stream
	player.volume_db = float((CUES[cue] as Dictionary)["db"])
	player.pitch_scale = maxf(pitch, 0.01)
	player.play()


## Toca o mesmo efeito várias vezes em cascata, uma nota acima da outra.
## Usado pelas estrelas do resultado, onde `intervalo` acompanha o atraso da
## animação de revelação para o som e a imagem caírem juntos.
func play_cascade(cue: Cue, count: int, intervalo: float, pitches: Array) -> void:
	for i in range(count):
		var pitch: float = 1.0
		if i < pitches.size():
			pitch = float(pitches[i])
		if i == 0:
			play(cue, pitch)
			continue
		# `create_timer` com process_always: a cascata não pode morrer se a
		# árvore pausar no meio dela.
		await get_tree().create_timer(float(i) * intervalo, true, false, true).timeout
		if not is_inside_tree():
			return
		play(cue, pitch)


## Silencia o que estiver tocando. Usado ao sair de uma tela no meio de uma
## cascata — sem isso a fanfarra atravessa a troca de cena.
func stop_all() -> void:
	for p: AudioStreamPlayer in _players:
		p.stop()


# ═══════════════════════════════════════════════════════════
#  INTERNO
# ═══════════════════════════════════════════════════════════

func _load_streams() -> void:
	# load() e não preload(): um WAV faltando vira um som mudo com aviso, e
	# não um erro de parse que impede o autoload inteiro de subir — ou seja,
	# o app inteiro de abrir.
	#
	# O preço é que o caminho é montado em runtime e o rastreador de
	# dependências do exportador não enxerga estes arquivos. Eles entram no
	# APK porque os presets usam `export_filter="all_resources"` — se algum
	# dia isso virar "resources from scenes", os sons somem do build sem
	# nenhum erro de compilação. É o que este comentário existe para avisar.
	for cue: int in CUES:
		var path: String = AUDIO_DIR + String((CUES[cue] as Dictionary)["file"]) + ".wav"
		if not ResourceLoader.exists(path):
			_warn_once(cue, "arquivo não encontrado em %s" % path)
			continue
		var res: Resource = load(path)
		if res is AudioStream:
			_streams[cue] = res
		else:
			_warn_once(cue, "%s não é um AudioStream" % path)


func _build_voices() -> void:
	var bus: StringName = BUS_NAME if AudioServer.get_bus_index(BUS_NAME) >= 0 else &"Master"
	if bus != BUS_NAME:
		push_warning("Audio: barramento '%s' não existe — usando Master." % BUS_NAME)

	for i in range(VOICES):
		var p := AudioStreamPlayer.new()
		p.bus = bus
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_players.append(p)


## Round-robin com preferência por voz livre. Se todas estiverem ocupadas a
## mais antiga é reaproveitada: cortar a cauda de um som velho é menos ruim
## do que engolir o som novo, que é o que o usuário acabou de causar.
func _take_voice() -> AudioStreamPlayer:
	if _players.is_empty():
		return null
	for i in range(_players.size()):
		var idx: int = (_next_voice + i) % _players.size()
		if not _players[idx].playing:
			_next_voice = (idx + 1) % _players.size()
			return _players[idx]
	var victim: AudioStreamPlayer = _players[_next_voice]
	_next_voice = (_next_voice + 1) % _players.size()
	return victim


func _warn_once(cue: int, motivo: String) -> void:
	if _warned.has(cue):
		return
	_warned[cue] = true
	push_warning("Audio: efeito %d indisponível (%s)." % [cue, motivo])
