extends Node
## Service que conversa com a API de lições.
##
## Endpoints:
##   GET {base_url}/licoes           -> [{ "id": int, "nome": String }, ...]
##   GET {base_url}/exercicio/{id}   -> {
##       "nome_exercicio": String,
##       "sinais": [
##         {
##           "nome_sinal": String,
##           "anim_lib":   String,    # texto cru de um arquivo .tres (Animation única)
##           "json_sinal": Dictionary # landmarks de referência
##         },
##         ...
##       ]
##   }
##
## Para cada lição buscada, o service:
##   1. Salva cada `anim_lib` como .tres temporário em `user://anim_cache/`
##   2. Carrega cada um como `Animation` via ResourceLoader
##   3. Monta uma única `AnimationLibrary` com todos os sinais (key = nome_sinal)
##   4. Devolve um objeto `Lesson` com a library pronta e os landmarks.
##
## Cadastre como Autoload com nome "LessonService".

const Lesson := preload("res://Scripts/Lesson.gd")

signal lesson_loaded(lesson_id: int, lesson: Lesson)
signal lesson_failed(lesson_id: int, error: String)

signal catalog_loaded(catalog: Array)
signal catalog_failed(error: String)

@export var base_url: String = " https://api.ciclicainteractive.com"
@export var api_key: String = "chave_secreta_godot"
@export var cache_dir: String = "user://anim_cache/"

# lesson_id -> { req, on_loaded, on_failed }
var _pending_lessons: Dictionary = {}
# req -> { on_loaded, on_failed }
var _pending_catalog: Dictionary = {}


# ---------- LIÇÃO INDIVIDUAL ----------

func fetch_lesson(lesson_id: int, on_loaded: Callable = Callable(), on_failed: Callable = Callable()) -> void:
	if _pending_lessons.has(lesson_id):
		push_warning("Requisição já em andamento para lição: %d" % lesson_id)
		return

	_ensure_cache_dir()

	var req := HTTPRequest.new()
	add_child(req)

	_pending_lessons[lesson_id] = {
		"req": req,
		"on_loaded": on_loaded,
		"on_failed": on_failed,
	}

	req.request_completed.connect(_on_lesson_response.bind(lesson_id))

	var url := "%s/exercicio/%d" % [base_url.rstrip("/"), lesson_id]
	var err := req.request(url, _build_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		var on_failed_cb: Callable = _pending_lessons[lesson_id]["on_failed"]
		_cleanup_lesson(lesson_id)
		_emit_lesson_fail(lesson_id, "Falha ao iniciar requisição (erro %d)" % err, on_failed_cb)


func _on_lesson_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, lesson_id: int) -> void:
	if not _pending_lessons.has(lesson_id):
		return

	var on_loaded: Callable = _pending_lessons[lesson_id]["on_loaded"]
	var on_failed: Callable = _pending_lessons[lesson_id]["on_failed"]
	_cleanup_lesson(lesson_id)

	if code != 200:
		_emit_lesson_fail(lesson_id, "HTTP %d ao buscar lição %d" % [code, lesson_id], on_failed)
		return

	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		_emit_lesson_fail(lesson_id, "JSON inválido na resposta da lição %d" % lesson_id, on_failed)
		return

	var payload: Dictionary = parsed
	if not payload.has("sinais") or not payload["sinais"] is Array:
		_emit_lesson_fail(lesson_id, "Campo 'sinais' ausente ou inválido na resposta", on_failed)
		return

	var lesson := _build_lesson(lesson_id, payload)
	if lesson == null:
		_emit_lesson_fail(lesson_id, "Falha ao montar AnimationLibrary da lição %d" % lesson_id, on_failed)
		return

	lesson_loaded.emit(lesson_id, lesson)
	if on_loaded.is_valid():
		on_loaded.call(lesson)


func _build_lesson(lesson_id: int, payload: Dictionary) -> Lesson:
	var lib := AnimationLibrary.new()
	var sinais_limpos: Array = []

	for raw_sinal: Variant in payload.get("sinais", []):
		if not raw_sinal is Dictionary:
			push_warning("Sinal ignorado: não é um Dictionary")
			continue

		var sinal: Dictionary = raw_sinal
		var nome: String = sinal.get("nome_sinal", "")
		var anim_tres: String = sinal.get("anim_lib", "")

		if nome.is_empty():
			push_warning("Sinal sem 'nome_sinal' — ignorado")
			continue
		if anim_tres.is_empty():
			push_warning("Sinal '%s' sem 'anim_lib' — ignorado" % nome)
			continue

		var animation := _load_animation_from_tres_text(anim_tres, "%d_%s" % [lesson_id, nome])
		if animation == null:
			push_warning("Falha ao carregar Animation do sinal '%s'" % nome)
			continue

		var add_err := lib.add_animation(StringName(nome), animation)
		if add_err != OK:
			push_warning("Falha ao adicionar animação '%s' à library (erro %d)" % [nome, add_err])
			continue

		sinais_limpos.append({
			"nome_sinal": nome,
			"json_sinal": sinal.get("json_sinal", {}),
		})

	if sinais_limpos.is_empty():
		return null

	var lesson := Lesson.new()
	lesson.lesson_id = lesson_id
	lesson.nome_exercicio = payload.get("nome_exercicio", "")
	lesson.sinais = sinais_limpos
	lesson.animation_library = lib
	return lesson


func _load_animation_from_tres_text(tres_text: String, unique_id: String) -> Animation:
	var path := cache_dir.path_join("anim_%s.tres" % unique_id)

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Não foi possível escrever cache em %s (erro %d)" % [path, FileAccess.get_open_error()])
		return null
	f.store_string(tres_text)
	f.close()

	var res := ResourceLoader.load(path, "Animation", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null:
		push_error("ResourceLoader retornou null para %s" % path)
		return null
	if not res is Animation:
		push_error("Recurso em %s não é uma Animation (é %s)" % [path, res.get_class()])
		return null
	return res


# ---------- CATÁLOGO ----------

## Busca a lista de lições disponíveis.
## Callback recebe Array de Dictionary: [{ "id": int, "nome": String }, ...]
func fetch_catalog(on_loaded: Callable = Callable(), on_failed: Callable = Callable()) -> void:
	var req := HTTPRequest.new()
	add_child(req)

	_pending_catalog[req] = {
		"on_loaded": on_loaded,
		"on_failed": on_failed,
	}

	req.request_completed.connect(_on_catalog_response.bind(req))

	var url := "%s/licoes" % base_url.rstrip("/")
	var err := req.request(url, _build_headers(), HTTPClient.METHOD_GET)
	if err != OK:
		var on_failed_cb: Callable = _pending_catalog[req]["on_failed"]
		_pending_catalog.erase(req)
		req.queue_free()
		_emit_catalog_fail("Falha ao iniciar requisição do catálogo (erro %d)" % err, on_failed_cb)


func _on_catalog_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, req: HTTPRequest) -> void:
	if not _pending_catalog.has(req):
		return

	var on_loaded: Callable = _pending_catalog[req]["on_loaded"]
	var on_failed: Callable = _pending_catalog[req]["on_failed"]
	_pending_catalog.erase(req)
	req.queue_free()

	if code != 200:
		_emit_catalog_fail("HTTP %d ao buscar catálogo" % code, on_failed)
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Array:
		_emit_catalog_fail("Resposta do catálogo não é um array", on_failed)
		return

	# Normaliza: aceita tanto [{id, nome}] quanto [int].
	var catalog: Array = []
	for entry: Variant in parsed:
		if entry is Dictionary:
			catalog.append({
				"id": int(entry.get("id", 0)),
				"nome": String(entry.get("nome", "")),
			})
		elif entry is int or entry is float:
			catalog.append({ "id": int(entry), "nome": "Lição %d" % int(entry) })

	catalog_loaded.emit(catalog)
	if on_loaded.is_valid():
		on_loaded.call(catalog)


# ---------- HELPERS ----------

func _build_headers() -> PackedStringArray:
	return PackedStringArray([
		"x-api-key: " + api_key,
		"Content-Type: application/json",
	])


func _ensure_cache_dir() -> void:
	if not DirAccess.dir_exists_absolute(cache_dir):
		var err := DirAccess.make_dir_recursive_absolute(cache_dir)
		if err != OK:
			push_warning("Falha ao criar cache dir %s (erro %d)" % [cache_dir, err])


func _cleanup_lesson(lesson_id: int) -> void:
	if not _pending_lessons.has(lesson_id):
		return
	var p: Dictionary = _pending_lessons[lesson_id]
	if p.get("req") and is_instance_valid(p["req"]):
		p["req"].queue_free()
	_pending_lessons.erase(lesson_id)


func _emit_lesson_fail(lesson_id: int, msg: String, on_failed: Callable) -> void:
	push_warning(msg)
	lesson_failed.emit(lesson_id, msg)
	if on_failed.is_valid():
		on_failed.call(msg)


func _emit_catalog_fail(msg: String, on_failed: Callable) -> void:
	push_warning(msg)
	catalog_failed.emit(msg)
	if on_failed.is_valid():
		on_failed.call(msg)


func clear_cache() -> void:
	if not DirAccess.dir_exists_absolute(cache_dir):
		return
	var dir := DirAccess.open(cache_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			dir.remove(fname)
		fname = dir.get_next()
	dir.list_dir_end()
