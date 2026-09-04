extends Node
## Singleton de estado global. Cadastre como Autoload com nome "Global".
##
## Responsabilidades:
## - Guardar o id da lição selecionada
## - Persistir progresso local
## - Navegar entre cenas principais
## - Carregar / baixar modelos externos do GDMP

# ---------- CAMINHOS ----------

const PROGRESS_PATH := "user://progress.json"
const MODEL_DIR := "user://GDMP"
## Modelos MediaPipe embarcados no projeto (e no APK via include_filter).
const BUNDLED_MODEL_DIR := "res://assets/mediapipe"

const MAIN_SCENE := "res://GUI/Screens/Main/Main.tscn"
const LESSON_SCENE := "res://GUI/lessonscreen/LessonScreen.tscn"
const MAP_SCENE := "res://GUI/lessonmap/LessonMapScreen.tscn"
const PROGRESS_SCENE := "res://GUI/progress/ProgressScreen.tscn"

# Se seu projeto ainda usa o caminho antigo do GDMP demo, troque MAIN_SCENE por:
# const MAIN_SCENE := "res://GUI/Screens/Main.tscn"


# ---------- CONFIG ----------

var enable_download_files: bool = false


# ---------- ESTADO ----------

## Id da lição que a próxima LessonScreen deve carregar.
var current_lesson_id: int = 1
## lesson_id em String, pois JSON usa chaves como texto.
## Exemplo:
## {
##   "1": { "completed": true, "stars": 3 }
## }
var _progress: Dictionary = {}


func _ready() -> void:
	_load_progress()
	# O aquecimento do cache de cenas é conduzido pela SplashScreen, que é a
	# cena de entrada do projeto. Fazer isso aqui competia com o primeiro
	# quadro da Home e produzia justamente o engasgo que se queria evitar.


# ============================================================
# API DE MODELOS EXTERNOS / GDMP
# ============================================================

func _get_external_file(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	path: String,
	callback: Callable
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("Falha ao baixar modelo: resultado HTTP inválido.")
		return

	if response_code != HTTPClient.RESPONSE_OK:
		push_warning("Falha ao baixar modelo. Código HTTP: %s" % response_code)
		return

	if body.is_empty():
		push_warning("Download do modelo retornou corpo vazio.")
		return

	var base_dir := path.get_base_dir()

	if DirAccess.make_dir_recursive_absolute(base_dir) != OK:
		push_warning("Não foi possível criar diretório: %s" % base_dir)
		return

	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		push_warning("Não foi possível salvar modelo em: %s" % path)
		return

	file.store_buffer(body)
	file.close()

	if callback.is_valid():
		callback.call()


func get_external_model(path: String, callback: Callable) -> HTTPRequest:
	if not enable_download_files:
		return null

	var model_path := MODEL_DIR.path_join(path)

	# Se o modelo já existe, não baixa de novo.
	if FileAccess.file_exists(model_path):
		if callback.is_valid():
			callback.call()
		return null

	var request: HTTPRequest = MediaPipeExternalFiles.get_model(path)

	if request == null:
		push_warning("MediaPipeExternalFiles não conseguiu criar o request para: %s" % path)
		return null

	var request_callback := _get_external_file.bind(model_path, callback)
	request.request_completed.connect(request_callback)

	return request


func get_model(path: String) -> FileAccess:
	# Modelo embarcado tem prioridade: funciona offline e no APK sem
	# depender de download em runtime (enable_download_files é false).
	var bundled := BUNDLED_MODEL_DIR.path_join(path.get_file())
	if FileAccess.file_exists(bundled):
		return FileAccess.open(bundled, FileAccess.READ)

	var model_path := MODEL_DIR.path_join(path)

	if FileAccess.file_exists(model_path):
		return FileAccess.open(model_path, FileAccess.READ)

	return null


# ============================================================
# API DE PROGRESSO
# ============================================================

func is_completed(lesson_id: int) -> bool:
	var entry: Dictionary = _progress.get(str(lesson_id), {})
	return bool(entry.get("completed", false))


func get_stars(lesson_id: int) -> int:
	var entry: Dictionary = _progress.get(str(lesson_id), {})
	return int(entry.get("stars", 0))


## Uma lição está destravada se for a primeira ou se a anterior estiver completa.
## `catalog` é a lista ordenada vinda do LessonService.
func is_unlocked(lesson_id: int, catalog: Array) -> bool:
	if catalog.is_empty():
		return true

	if int(catalog[0].get("id", -1)) == lesson_id:
		return true

	for i in range(1, catalog.size()):
		if int(catalog[i].get("id", -1)) == lesson_id:
			var prev_id := int(catalog[i - 1].get("id", -1))
			return is_completed(prev_id)

	return false


func mark_completed(lesson_id: int, stars: int = 3) -> void:
	# Não rebaixa um resultado anterior melhor ao rejogar a lição.
	var best := maxi(get_stars(lesson_id), clampi(stars, 0, 3))
	_progress[str(lesson_id)] = {
		"completed": true,
		"stars": best,
	}

	_save_progress()


func reset_progress() -> void:
	_progress.clear()
	_save_progress()


## Apaga os dados locais do usuário — progresso, estrelas, XP, ofensiva e
## estatísticas. Devolve `true` quando o disco ficou de fato consistente com
## a memória.
##
## Grava um progresso VAZIO em vez de remover o arquivo. Remover faria o
## próximo boot cair no caminho de instalação nova, que semeia a lição 1 como
## concluída com 3 estrelas (ver `_load_progress`) — o usuário reabriria o app
## e reencontraria um progresso que acabou de mandar apagar.
##
## O cache de animações baixadas é de outro autoload: quem apaga tudo também
## chama `LessonService.clear_cache()`.
func erase_all_data() -> bool:
	reset_progress()
	return _saved_progress_is_empty()


## Relê o arquivo para conferir o que ficou gravado. `_save_progress()` só
## avisa quando falha; sem esta checagem, um disco cheio ou sem permissão
## deixaria o app dizendo "dados apagados" com o progresso antigo intacto,
## pronto para voltar na próxima abertura.
func _saved_progress_is_empty() -> bool:
	if not FileAccess.file_exists(PROGRESS_PATH):
		return false

	var file := FileAccess.open(PROGRESS_PATH, FileAccess.READ)
	if file == null:
		return false

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	return parsed is Dictionary and (parsed as Dictionary).is_empty()


# ============================================================
# GAMIFICAÇÃO — XP, NÍVEL, OFENSIVA
# ============================================================
#
# A UI já tinha lugares para XP, streak, nível e "sinais dominados", mas
# nenhum dado por trás: os cards ficavam `visible = false` com o texto
# "TODO: sistema de XP/recompensas" dentro. Ou se apagavam esses elementos,
# ou eles passavam a ser verdade. Isto é o mínimo para serem verdade.
#
# Fica dentro de `_progress`, sob uma chave reservada que nunca colide com
# um id de lição (que é sempre numérico), para reaproveitar exatamente o
# mesmo caminho de carga/gravação — inclusive o stub usado nos testes.

const STATS_KEY := "_stats"
const XP_PER_LEVEL := 500
## XP por estrela ganha. Só a MELHORA conta (ver `award_sign_result`).
const XP_PER_STAR := 20


func _stats() -> Dictionary:
	var s: Variant = _progress.get(STATS_KEY, null)
	if s is Dictionary:
		return s as Dictionary
	var fresh: Dictionary = {
		"xp": 0,
		"streak": 0,
		"best_streak": 0,
		"last_day": "",
		"practices": 0,
		"precision_sum": 0.0,
		"signs": {},   # "lesson:index" -> melhor nº de estrelas
	}
	_progress[STATS_KEY] = fresh
	return fresh


func get_xp() -> int:
	return int(_stats().get("xp", 0))


func get_level() -> int:
	return get_xp() / XP_PER_LEVEL + 1


## XP acumulado dentro do nível atual.
func get_xp_into_level() -> int:
	return get_xp() % XP_PER_LEVEL


## Fração 0..1 do nível atual — alimenta a barra de XP.
func get_level_progress() -> float:
	return float(get_xp_into_level()) / float(XP_PER_LEVEL)


func get_streak() -> int:
	return int(_stats().get("streak", 0))


func get_best_streak() -> int:
	return int(_stats().get("best_streak", 0))


func get_practice_count() -> int:
	return int(_stats().get("practices", 0))


## Precisão média de todas as tentativas (0..1). -1 quando nunca praticou,
## para a UI poder esconder o dado em vez de mostrar "0%".
func get_average_precision() -> float:
	var s := _stats()
	var n: int = int(s.get("practices", 0))
	if n <= 0:
		return -1.0
	return float(s.get("precision_sum", 0.0)) / float(n)


## Lições marcadas como concluídas, independentemente do catálogo atual.
func count_completed_lessons() -> int:
	var count: int = 0
	for key: Variant in _progress:
		var k: String = String(key)
		if k == STATS_KEY:
			continue
		var entry: Variant = _progress[k]
		if entry is Dictionary and bool((entry as Dictionary).get("completed", false)):
			count += 1
	return count


## Quantos sinais o usuário já executou com nota máxima.
func get_mastered_signs() -> int:
	var signs: Dictionary = _stats().get("signs", {}) as Dictionary
	var count: int = 0
	for key: Variant in signs:
		if int(signs[key]) >= 3:
			count += 1
	return count


## Concede XP pela MELHORA da nota de um sinal e devolve quanto foi concedido.
##
## Premiar toda tentativa deixaria o XP infinito (basta repetir o mesmo sinal);
## premiar só a primeira punia quem erra na estreia e depois acerta. Pagar a
## diferença resolve os dois: o teto por sinal é 3 estrelas, sempre alcançável.
func award_sign_result(lesson_id: int, sign_index: int, stars: int) -> int:
	var s := _stats()
	var signs: Dictionary = s.get("signs", {}) as Dictionary
	var key := "%d:%d" % [lesson_id, sign_index]
	var best: int = int(signs.get(key, 0))
	var earned: int = clampi(stars, 0, 3)
	if earned <= best:
		return 0

	var gained: int = (earned - best) * XP_PER_STAR
	signs[key] = earned
	s["signs"] = signs
	s["xp"] = int(s.get("xp", 0)) + gained
	_progress[STATS_KEY] = s
	_save_progress()
	return gained


## Registra uma tentativa de prática: atualiza a ofensiva e a precisão média.
## Chame uma vez por gravação avaliada, mesmo quando a nota for baixa —
## a ofensiva mede constância, não acerto.
func register_practice(precision: float) -> void:
	var s := _stats()
	s["practices"] = int(s.get("practices", 0)) + 1
	s["precision_sum"] = float(s.get("precision_sum", 0.0)) + clampf(precision, 0.0, 1.0)
	_touch_streak(s)
	_progress[STATS_KEY] = s
	_save_progress()


## Dias consecutivos com pelo menos uma prática.
## `today` é injetável para os testes não dependerem do relógio do sistema.
func _touch_streak(s: Dictionary, today: String = "") -> void:
	if today.is_empty():
		today = Time.get_date_string_from_system()

	var last: String = String(s.get("last_day", ""))
	if last == today:
		return   # já contou hoje

	var streak: int = int(s.get("streak", 0))
	if last.is_empty():
		streak = 1
	elif _days_between(last, today) == 1:
		streak += 1
	else:
		streak = 1   # quebrou a sequência

	s["streak"] = streak
	s["best_streak"] = maxi(int(s.get("best_streak", 0)), streak)
	s["last_day"] = today


## Diferença em dias entre duas datas "AAAA-MM-DD". -1 se alguma for inválida.
func _days_between(from_day: String, to_day: String) -> int:
	var a := Time.get_unix_time_from_datetime_string(from_day + "T00:00:00")
	var b := Time.get_unix_time_from_datetime_string(to_day + "T00:00:00")
	if a <= 0 or b <= 0:
		return -1
	return int(round(float(b - a) / 86400.0))


# ============================================================
# NAVEGAÇÃO
# ============================================================
#
# `change_scene_to_file()` carrega o PackedScene de forma SÍNCRONA no meio do
# frame. Para a LessonScreen isso significa destravar o GLB do avatar, suas
# texturas e o grafo do MediaPipe de uma vez só — o app congelava por vários
# frames a cada troca de tela, sem nada indicando que estava trabalhando.
#
# Aqui a troca passa a ser:
#   1. esmaece para a cor de fundo do app (0,18 s)   ← cobre a costura
#   2. carrega o recurso em thread, sem travar o frame
#   3. troca a cena e espera o layout assentar
#   4. revela (0,28 s)
#
# O carregamento pesado acontece atrás do véu, e o Godot cacheia o recurso —
# então da segunda visita em diante a etapa 2 é instantânea. O avatar é
# compartilhado entre a Home e a LessonScreen, então a primeira transição já
# aquece o cache das duas.

## Acima de qualquer CanvasLayer das cenas.
const TRANSITION_LAYER := 128

var _fade: ColorRect = null
var _is_changing: bool = false

## PackedScenes das telas principais, mantidos vivos de propósito.
##
## O Godot só cacheia um recurso enquanto alguém o referencia. Ao trocar de
## cena, o PackedScene sai de escopo e leva junto tudo o que ele referencia —
## inclusive o GLB do avatar e as ~20 texturas dele. Voltar para a Home
## reparseava tudo: medido em ~1,15 s POR TROCA, em cima de uma instanciação
## que leva só 3,8 ms. Segurar os PackedScenes aqui elimina esse trabalho
## repetido; o custo é a malha e as texturas do avatar ficarem residentes,
## que é justamente o que as duas telas mais visitadas usam.
var _scene_cache: Dictionary = {}


func go_to_lesson(lesson_id: int) -> void:
	current_lesson_id = lesson_id
	change_scene(LESSON_SCENE)


func go_to_map() -> void:
	change_scene(MAP_SCENE)


func go_to_main_scene() -> void:
	change_scene(MAIN_SCENE)


func go_to_progress() -> void:
	change_scene(PROGRESS_SCENE)


## Troca de cena com transição. Ignora chamadas enquanto outra troca está em
## andamento — sem isso, dois toques rápidos empilham duas trocas e a segunda
## roda contra uma árvore que já foi liberada.
func change_scene(path: String) -> void:
	if _is_changing:
		return
	_is_changing = true

	_ensure_fade()
	_fade.visible = true

	# O pedido de carga sai ANTES do fade: os 0,18 s do esmaecimento já são
	# tempo de carregamento útil em vez de espera pura.
	var cached: bool = _scene_cache.has(path)
	if not cached:
		ResourceLoader.load_threaded_request(path)

	var fade_out := create_tween()
	fade_out.set_ease(Tween.EASE_OUT)
	fade_out.tween_property(_fade, "modulate:a", 1.0, DS.DUR_FAST)
	await fade_out.finished

	var packed: PackedScene = null
	if cached:
		packed = _scene_cache[path] as PackedScene
	else:
		packed = await _await_threaded_load(path)
		if packed != null:
			_scene_cache[path] = packed

	if packed == null:
		push_error("Falha ao carregar cena: %s" % path)
		await _reveal()
		return

	get_tree().change_scene_to_packed(packed)

	# Dois frames: um para a nova cena entrar na árvore e rodar _ready(), outro
	# para os containers resolverem o layout. Revelar antes disso mostra a tela
	# com os elementos ainda no lugar errado.
	await get_tree().process_frame
	await get_tree().process_frame

	await _reveal()


func _reveal() -> void:
	var fade_in := create_tween()
	fade_in.set_ease(Tween.EASE_OUT)
	fade_in.tween_property(_fade, "modulate:a", 0.0, DS.DUR_FAST)
	await fade_in.finished
	_fade.visible = false
	_is_changing = false


func _await_threaded_load(path: String) -> PackedScene:
	while true:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var packed: PackedScene = ResourceLoader.load_threaded_get(path) as PackedScene
			if packed != null:
				return packed
			return _load_blocking(path)
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return _load_blocking(path)
		await get_tree().process_frame
	return null


## Último recurso quando a carga em thread falha. Trava o frame, mas uma tela
## que demora é infinitamente melhor que uma tela que não abre — e a carga em
## thread do GDScript é sabidamente sensível a resolução de `class_name`.
func _load_blocking(path: String) -> PackedScene:
	push_warning("Carga em thread falhou para %s — recarregando na thread principal" % path)
	return ResourceLoader.load(path) as PackedScene


## Carrega uma cena e guarda no cache. Idempotente e `await`-ável, para a
## SplashScreen conseguir mostrar progresso real.
##
## Deliberadamente SÍNCRONO, na thread principal. Carregar em thread durante o
## boot disparava, de forma intermitente, falhas de resolução de `class_name`
## em sub-cenas cujo script raiz declara uma (VisionTask, CameraSelectorDialog
## — o nó que falhava mudava a cada execução). Resolver nomes de classe do
## GDScript a partir de uma thread de trabalho corre com a inicialização do
## próprio cache de classes; medido em 2 falhas a cada 6 boots.
##
## A splash existe exatamente para absorver esse bloqueio. Em runtime,
## `change_scene` continua usando carga em thread — mas nessa altura tudo já
## está compilado e em cache, então o caminho em thread nem chega a rodar.
func preload_scene(path: String) -> void:
	if _scene_cache.has(path):
		return
	# Cede um quadro antes de travar: a barra da splash precisa conseguir
	# desenhar o passo anterior.
	await get_tree().process_frame
	var packed: PackedScene = ResourceLoader.load(path) as PackedScene
	if packed != null:
		_scene_cache[path] = packed
	else:
		push_error("Não foi possível pré-carregar a cena: %s" % path)


## Aquece o cache das telas principais de uma vez.
func warm_scene_cache() -> void:
	for path: String in [MAIN_SCENE, MAP_SCENE, PROGRESS_SCENE, LESSON_SCENE]:
		await preload_scene(path)


## O véu vive num CanvasLayer do autoload, não da cena: ele precisa
## sobreviver justamente ao momento em que a cena é destruída e recriada.
## Criado sob demanda para que os testes (que instanciam Global sem árvore
## de UI) nunca montem nada disso.
func _ensure_fade() -> void:
	if _fade != null and is_instance_valid(_fade):
		return

	var layer := CanvasLayer.new()
	layer.layer = TRANSITION_LAYER
	add_child(layer)

	_fade = ColorRect.new()
	# Esmaecer para o fundo do app, não para preto: a transição some dentro
	# da identidade visual em vez de piscar um retângulo escuro.
	_fade.color = DS.BG
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP   # engole toques durante a troca
	_fade.modulate.a = 0.0
	_fade.visible = false
	layer.add_child(_fade)


# ============================================================
# PERSISTÊNCIA
# ============================================================

func _load_progress() -> void:
	if not FileAccess.file_exists(PROGRESS_PATH):
		_progress = {"1": { "completed": true, "stars": 3 }}
		return

	var file := FileAccess.open(PROGRESS_PATH, FileAccess.READ)

	if file == null:
		_progress = {}
		push_warning("Não foi possível abrir progresso em: %s" % PROGRESS_PATH)
		return

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)

	if parsed is Dictionary:
		_progress = parsed
	else:
		_progress = {}
		push_warning("Arquivo de progresso inválido. Progresso reiniciado.")


func _save_progress() -> void:
	var file := FileAccess.open(PROGRESS_PATH, FileAccess.WRITE)

	if file == null:
		push_warning("Não foi possível salvar progresso em: %s" % PROGRESS_PATH)
		return

	file.store_string(JSON.stringify(_progress))
	file.close()
