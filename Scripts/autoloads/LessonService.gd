extends Node
## Service que busca dados de uma lição em DOIS endpoints separados:
##   1) animação    -> retorna texto puro com o nome da animação
##   2) validação   -> retorna texto (JSON serializado) com landmarks de referência
##
## Cadastre como Autoload em Project Settings > Autoload com nome "LessonService".
##
## Uso:
##   LessonService.fetch_lesson("casa", func(data): print(data))
##
## Estrutura do dicionário retornado:
##   {
##     "sign_id": "casa",
##     "label": "CASA",
##     "animation_name": "sign_casa",
##     "reference_landmarks": { "frames": [ ... ] }
##   }

signal lesson_loaded(sign_id: String, data: Dictionary)
signal lesson_failed(sign_id: String, error: String)

## Quando true, lê os mocks em res://mocks/ ao invés de fazer HTTP.
@export var use_mock: bool = true

## URL base para chamadas reais. Esperamos 2 endpoints relativos:
##   {base_url}/animation/{sign_id}   -> texto com nome da animação
##   {base_url}/validation/{sign_id}  -> texto com JSON dos landmarks
@export var base_url: String = "https://example.com/api"

@export var mock_path: String = "res://data/mocks/"


# sign_id -> { "animation": String|null, "validation": Dictionary|null,
#              "on_loaded": Callable, "on_failed": Callable,
#              "anim_req": HTTPRequest, "valid_req": HTTPRequest }
var _pending: Dictionary = {}


func fetch_lesson(sign_id: String, on_loaded: Callable = Callable(), on_failed: Callable = Callable()) -> void:
	if use_mock:
		_fetch_mock(sign_id, on_loaded, on_failed)
	else:
		_fetch_http(sign_id, on_loaded, on_failed)


# ---------- MOCK ----------

func _fetch_mock(sign_id: String, on_loaded: Callable, on_failed: Callable) -> void:
	var anim_path := mock_path.path_join("animation_%s.txt" % sign_id)
	var valid_path := mock_path.path_join("validation_%s.json" % sign_id)

	if not FileAccess.file_exists(anim_path):
		_emit_fail(sign_id, "Mock de animação não encontrado: %s" % anim_path, on_failed)
		return
	if not FileAccess.file_exists(valid_path):
		_emit_fail(sign_id, "Mock de validação não encontrado: %s" % valid_path, on_failed)
		return

	var fa := FileAccess.open(anim_path, FileAccess.READ)
	var animation_name := fa.get_as_text().strip_edges()
	fa.close()

	var fv := FileAccess.open(valid_path, FileAccess.READ)
	var validation_text := fv.get_as_text()
	fv.close()

	# Simula latência
	await get_tree().create_timer(0.3).timeout

	var validation: Variant = JSON.parse_string(validation_text)
	if not validation is Dictionary:
		_emit_fail(sign_id, "JSON de validação inválido em %s" % valid_path, on_failed)
		return

	var data := {
		"sign_id": sign_id,
		"label": sign_id.to_upper(),
		"animation_name": animation_name,
		"reference_landmarks": validation,
	}
	lesson_loaded.emit(sign_id, data)
	if on_loaded.is_valid():
		on_loaded.call(data)


# ---------- HTTP ----------

func _fetch_http(sign_id: String, on_loaded: Callable, on_failed: Callable) -> void:
	if _pending.has(sign_id):
		push_warning("Requisição já em andamento para: " + sign_id)
		return

	var anim_req := HTTPRequest.new()
	var valid_req := HTTPRequest.new()
	add_child(anim_req)
	add_child(valid_req)

	_pending[sign_id] = {
		"animation": null,
		"validation": null,
		"on_loaded": on_loaded,
		"on_failed": on_failed,
		"anim_req": anim_req,
		"valid_req": valid_req,
		"failed": false,
	}

	anim_req.request_completed.connect(_on_animation_response.bind(sign_id))
	valid_req.request_completed.connect(_on_validation_response.bind(sign_id))

	var base := base_url.rstrip("/")
	var anim_url := "%s/animation/%s" % [base, sign_id]
	var valid_url := "%s/validation/%s" % [base, sign_id]

	var e1 := anim_req.request(anim_url)
	var e2 := valid_req.request(valid_url)

	if e1 != OK or e2 != OK:
		_cleanup(sign_id)
		_emit_fail(sign_id, "Falha ao iniciar requisições", on_failed)


func _on_animation_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, sign_id: String) -> void:
	if not _pending.has(sign_id):
		return
	if _pending[sign_id]["failed"]:
		return
	if code != 200:
		_pending[sign_id]["failed"] = true
		var on_failed: Callable = _pending[sign_id]["on_failed"]
		_cleanup(sign_id)
		_emit_fail(sign_id, "HTTP %d ao buscar animação" % code, on_failed)
		return

	_pending[sign_id]["animation"] = body.get_string_from_utf8().strip_edges()
	_try_finish(sign_id)


func _on_validation_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, sign_id: String) -> void:
	if not _pending.has(sign_id):
		return
	if _pending[sign_id]["failed"]:
		return
	if code != 200:
		_pending[sign_id]["failed"] = true
		var on_failed: Callable = _pending[sign_id]["on_failed"]
		_cleanup(sign_id)
		_emit_fail(sign_id, "HTTP %d ao buscar validação" % code, on_failed)
		return

	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		_pending[sign_id]["failed"] = true
		var on_failed: Callable = _pending[sign_id]["on_failed"]
		_cleanup(sign_id)
		_emit_fail(sign_id, "JSON de validação inválido", on_failed)
		return

	_pending[sign_id]["validation"] = parsed
	_try_finish(sign_id)


func _try_finish(sign_id: String) -> void:
	var p: Dictionary = _pending[sign_id]
	if p["animation"] == null or p["validation"] == null:
		return  # ainda esperando o outro

	var data := {
		"sign_id": sign_id,
		"label": sign_id.to_upper(),
		"animation_name": p["animation"],
		"reference_landmarks": p["validation"],
	}
	var on_loaded: Callable = p["on_loaded"]
	_cleanup(sign_id)

	lesson_loaded.emit(sign_id, data)
	if on_loaded.is_valid():
		on_loaded.call(data)


func _cleanup(sign_id: String) -> void:
	if not _pending.has(sign_id):
		return
	var p: Dictionary = _pending[sign_id]
	if p.get("anim_req") and is_instance_valid(p["anim_req"]):
		p["anim_req"].queue_free()
	if p.get("valid_req") and is_instance_valid(p["valid_req"]):
		p["valid_req"].queue_free()
	_pending.erase(sign_id)


func _emit_fail(sign_id: String, msg: String, on_failed: Callable) -> void:
	push_warning(msg)
	lesson_failed.emit(sign_id, msg)
	if on_failed.is_valid():
		on_failed.call(msg)


# ---------- Catálogo ----------

## Lista de lições disponíveis. Em produção isto também viria do servidor.
func get_lesson_catalog() -> Array:
	return [
		{ "sign_id": "ABACATE",  "label": "ABACATE",  "unlocked": true,  "completed": false, "stars": 0 },
		{ "sign_id": "agua",  "label": "ÁGUA",  "unlocked": true,  "completed": false, "stars": 0 },
		{ "sign_id": "comer", "label": "COMER", "unlocked": false, "completed": false, "stars": 0 },
		{ "sign_id": "ola",   "label": "OLÁ",   "unlocked": false, "completed": false, "stars": 0 },
	]
