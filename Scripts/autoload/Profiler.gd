extends Node
## Autoload Profiler — Sistema de perfilamento de desempenho e recursos em arquivo.
##
## Registra com flush instantâneo em `user://performance.log`:
## - Timestamp ISO formatado
## - Categoria / Operação
## - Tempo decorrido (ms)
## - Memória estática utilizada (MB)
## - Pico de memória estática (MB)
## - Variação (Delta) de memória na operação

const LOG_PATH := "user://performance.log"

var _active_timers: Dictionary = {}
var _file_mutex: Mutex = Mutex.new()


func _ready() -> void:
	log_event("SYSTEM", "=== Profiler Inicializado ===", {
		"os": OS.get_name(),
		"processor_count": OS.get_processor_count(),
		"device_model": OS.get_model_name(),
		"initial_memory_mb": "%.2f" % (float(OS.get_static_memory_usage()) / 1048576.0)
	})


## Inicia um cronômetro associado a um identificador único `tag`.
func start_timer(tag: String) -> void:
	_file_mutex.lock()
	_active_timers[tag] = {
		"start_usec": Time.get_ticks_usec(),
		"start_mem": OS.get_static_memory_usage()
	}
	_file_mutex.unlock()


## Finaliza o cronômetro `tag`, calcula tempo e memória delta, e grava no arquivo de log.
## Retorna o tempo decorrido em milissegundos.
func end_timer(tag: String, details: Dictionary = {}) -> float:
	var now_usec: int = Time.get_ticks_usec()
	var now_mem: int = OS.get_static_memory_usage()
	var start_info: Dictionary = {}

	_file_mutex.lock()
	if _active_timers.has(tag):
		start_info = _active_timers[tag] as Dictionary
		_active_timers.erase(tag)
	_file_mutex.unlock()

	var elapsed_ms: float = 0.0
	var delta_mem_mb: float = 0.0

	if not start_info.is_empty():
		var start_usec: int = int(start_info.get("start_usec", now_usec))
		var start_mem: int = int(start_info.get("start_mem", now_mem))
		elapsed_ms = float(now_usec - start_usec) / 1000.0
		delta_mem_mb = float(now_mem - start_mem) / 1048576.0

	var current_mem_mb: float = float(now_mem) / 1048576.0
	var peak_mem_mb: float = float(OS.get_static_memory_peak_usage()) / 1048576.0

	var log_data: Dictionary = details.duplicate()
	log_data["elapsed_ms"] = "%.2f" % elapsed_ms
	log_data["mem_current_mb"] = "%.2f" % current_mem_mb
	log_data["mem_delta_mb"] = "%+.2f" % delta_mem_mb
	log_data["mem_peak_mb"] = "%.2f" % peak_mem_mb

	_write_log_entry("TIMER", tag, log_data)
	return elapsed_ms


## Registra um evento ou métrica instantânea no arquivo de log.
func log_event(category: String, message: String, details: Dictionary = {}) -> void:
	var now_mem: int = OS.get_static_memory_usage()
	var peak_mem: int = OS.get_static_memory_peak_usage()

	var log_data: Dictionary = details.duplicate()
	log_data["mem_current_mb"] = "%.2f" % (float(now_mem) / 1048576.0)
	log_data["mem_peak_mb"] = "%.2f" % (float(peak_mem) / 1048576.0)

	_write_log_entry(category, message, log_data)


func _write_log_entry(category: String, message: String, details: Dictionary) -> void:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var timestamp: String = "%04d-%02d-%02d %02d:%02d:%02d.%03d" % [
		dt.get("year", 2000), dt.get("month", 1), dt.get("day", 1),
		dt.get("hour", 0), dt.get("minute", 0), dt.get("second", 0),
		Time.get_ticks_msec() % 1000
	]

	var details_str := ""
	if not details.is_empty():
		var parts: Array[String] = []
		for k: Variant in details.keys():
			parts.append("%s=%s" % [str(k), str(details[k])])
		details_str = " | " + ", ".join(parts)

	var line: String = "[%s] [%s] %s%s\n" % [timestamp, category, message, details_str]
	print("[Profiler] " + line.strip_edges())

	_file_mutex.lock()
	var f: FileAccess = null
	if FileAccess.file_exists(LOG_PATH):
		f = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)

	if f != null:
		f.store_string(line)
		f.flush()
		f.close()
	else:
		push_warning("Profiler: Não foi possível abrir %s para escrita (erro %d)" % [LOG_PATH, FileAccess.get_open_error()])
	_file_mutex.unlock()


## Retorna o caminho global absoluto do arquivo de logs no sistema operacional.
func get_log_absolute_path() -> String:
	return ProjectSettings.globalize_path(LOG_PATH)


## Lê o conteúdo completo do arquivo de log.
func get_log_contents() -> String:
	_file_mutex.lock()
	var content := ""
	if FileAccess.file_exists(LOG_PATH):
		var f := FileAccess.open(LOG_PATH, FileAccess.READ)
		if f != null:
			content = f.get_as_text()
			f.close()
	_file_mutex.unlock()
	return content


## Limpa o arquivo de log.
func clear_log() -> void:
	_file_mutex.lock()
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("")
		f.close()
	_file_mutex.unlock()
