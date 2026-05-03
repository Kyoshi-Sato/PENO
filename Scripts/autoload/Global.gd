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

const MAIN_SCENE := "res://GUI/Screens/Main.tscn"
const LESSON_SCENE := "res://GUI/lessonscreen/LessonScreen.tscn"
const MAP_SCENE := "res://GUI/lessonmap/LessonMapScreen.tscn"

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
	_progress[str(lesson_id)] = {
		"completed": true,
		"stars": clampi(stars, 0, 3),
	}

	_save_progress()


func reset_progress() -> void:
	_progress.clear()
	_save_progress()


# ============================================================
# NAVEGAÇÃO
# ============================================================

func go_to_lesson(lesson_id: int) -> void:
	current_lesson_id = lesson_id
	get_tree().change_scene_to_file(LESSON_SCENE)


func go_to_map() -> void:
	get_tree().change_scene_to_file(MAP_SCENE)


func go_to_main_scene() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)


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
