extends GutTest
## Preferência de backend de inferência (Global), sem tocar o disco.
##
## O que estes testes protegem: antes, o grafo holístico subia sem nenhum
## `base_options/acceleration` e caía no XNNPACK de uma thread. A escolha
## agora é um estado persistido, e AUTO precisa resolver para um backend
## concreto — é isso que o HolisticLandmarker consulta ao montar o grafo.

const StubGlobal := preload("res://tests/helpers/stub_global.gd")

var g: Node


func before_each() -> void:
	g = autofree(StubGlobal.new())


func test_default_is_auto() -> void:
	assert_eq(g.get_inference_backend(), g.InferenceBackend.AUTO)


func test_set_and_get_roundtrip() -> void:
	g.set_inference_backend(g.InferenceBackend.GPU)
	assert_eq(g.get_inference_backend(), g.InferenceBackend.GPU)
	g.set_inference_backend(g.InferenceBackend.CPU)
	assert_eq(g.get_inference_backend(), g.InferenceBackend.CPU)


func test_change_emits_signal_once() -> void:
	watch_signals(g)
	g.set_inference_backend(g.InferenceBackend.CPU)
	g.set_inference_backend(g.InferenceBackend.CPU)
	assert_signal_emit_count(g, "inference_backend_changed", 1,
		"regravar o mesmo valor não remonta o grafo à toa")


func test_corrupted_value_falls_back_to_auto() -> void:
	# O arquivo de preferências é JSON solto em user://: um valor fora do
	# enum não pode virar um backend inexistente na hora de montar o grafo.
	g._settings["inference_backend"] = 99
	assert_eq(g.get_inference_backend(), g.InferenceBackend.AUTO)


func test_resolve_never_returns_auto() -> void:
	for pref: int in [g.InferenceBackend.AUTO, g.InferenceBackend.GPU, g.InferenceBackend.CPU]:
		g._settings["inference_backend"] = pref
		assert_ne(g.resolve_inference_backend(), g.InferenceBackend.AUTO,
			"AUTO precisa virar GPU ou CPU antes de chegar no MediaPipe")


func test_explicit_choice_survives_resolution() -> void:
	g.set_inference_backend(g.InferenceBackend.CPU)
	assert_eq(g.resolve_inference_backend(), g.InferenceBackend.CPU)


## A GPU só roda por escolha explícita. AUTO não pode chegar nela em
## plataforma nenhuma enquanto ela não for confirmada num aparelho real —
## o único teste que existe é sob llvmpipe (GL por software).
func test_auto_never_reaches_the_gpu() -> void:
	g._settings["inference_backend"] = g.InferenceBackend.AUTO
	assert_eq(g.resolve_inference_backend(), g.InferenceBackend.CPU)


## O caminho da GPU precisa ser o TFLiteGPURunner. Com
## `use_advanced_gpu_api = false` o InferenceCalculator usa o
## TfLiteGpuDelegate, que dá SIGSEGV em `densify::Prepare` com este bundle.
func test_gpu_uses_the_advanced_runner() -> void:
	assert_true(g.GPU_ADVANCED_API,
		"o TfLiteGpuDelegate trava o app com o holistic_landmarker.task")


## O default do MediaPipe é 1 thread no desktop — medido em 18,9 ms contra
## 6,0 ms com 4. O piso de 2 existe para nunca voltar a esse caso.
func test_cpu_threads_between_two_and_four() -> void:
	var n: int = g.get_inference_cpu_threads()
	assert_between(n, 2, 4)


func test_labels_are_distinct() -> void:
	var labels := [
		g.inference_backend_label(g.InferenceBackend.AUTO),
		g.inference_backend_label(g.InferenceBackend.GPU),
		g.inference_backend_label(g.InferenceBackend.CPU),
	]
	assert_eq(labels.size(), 3)
	for label: String in labels:
		assert_ne(label, "")
	assert_ne(labels[0], labels[1])
	assert_ne(labels[1], labels[2])


# ═══════════════════════════════════════════════════════════
#  SONDA DA GPU
# ═══════════════════════════════════════════════════════════
#
# O delegate GL não devolve erro sempre: numa das execuções aqui ele
# derrubou o processo dentro de `densify::Prepare`. Um crash não deixa
# rodar tratamento nenhum em memória, então a tentativa é cercada por um
# flag em disco e o boot seguinte lê o que sobrou.


func test_failed_probe_blocks_gpu() -> void:
	g.set_inference_backend(g.InferenceBackend.GPU)
	g.begin_gpu_probe()
	g.end_gpu_probe(false)
	assert_true(g.is_gpu_blocked())
	assert_eq(g.resolve_inference_backend(), g.InferenceBackend.CPU,
		"GPU vetada resolve para CPU mesmo com a preferência em GPU")


func test_successful_probe_clears_the_block() -> void:
	g.set_inference_backend(g.InferenceBackend.GPU)
	g.begin_gpu_probe()
	g.end_gpu_probe(false)
	g.begin_gpu_probe()
	g.end_gpu_probe(true)
	assert_false(g.is_gpu_blocked())


## O grafo foi desmontado antes de a GPU responder (troca de backend, saída
## da tela). Nem veta nem aprova — só não pode ficar aberta, senão o boot
## seguinte lê como crash.
func test_cancelled_probe_has_no_verdict() -> void:
	g.set_inference_backend(g.InferenceBackend.GPU)
	g.begin_gpu_probe()
	g.cancel_gpu_probe()
	assert_false(g.is_gpu_blocked(), "cancelar não veta")
	g._close_dangling_gpu_probe()
	assert_false(g.is_gpu_blocked(), "e não sobra sonda para o boot seguinte ler")


## Regressão: fechar a sonda no retorno do `initialize()` deixava o app
## repetindo a GPU que o derrubava. O veredito positivo só vale depois de a
## GPU entregar resultado — antes disso a sonda tem que continuar aberta.
func test_probe_stays_open_until_the_gpu_answers() -> void:
	g.set_inference_backend(g.InferenceBackend.GPU)
	g.begin_gpu_probe()
	assert_true(g._settings.get("gpu_probe_pending", false),
		"initialize() ter voltado não fecha a sonda")
	g._close_dangling_gpu_probe()
	assert_true(g.is_gpu_blocked(), "morrer com a sonda aberta veta a GPU")


func test_choosing_again_clears_the_block() -> void:
	g.set_inference_backend(g.InferenceBackend.GPU)
	g.end_gpu_probe(false)
	assert_true(g.is_gpu_blocked())
	g.set_inference_backend(g.InferenceBackend.CPU)
	g.set_inference_backend(g.InferenceBackend.GPU)
	assert_false(g.is_gpu_blocked(), "reescolher é o pedido de tentar de novo")


func test_dangling_probe_at_boot_counts_as_failure() -> void:
	# Estado deixado por um processo que morreu no meio da inicialização.
	g._settings = {"inference_backend": g.InferenceBackend.GPU, "gpu_probe_pending": true}
	g._close_dangling_gpu_probe()
	assert_true(g.is_gpu_blocked())
	assert_false(g._settings.has("gpu_probe_pending"), "a sonda é fechada, não repetida")


func test_probe_closed_normally_leaves_no_trace() -> void:
	g.begin_gpu_probe()
	g.end_gpu_probe(true)
	g._close_dangling_gpu_probe()
	assert_false(g.is_gpu_blocked())


## Instalação com a preferência em GPU. Se a GPU sair do menu (constante
## desligada por outro crash), a preferência é migrada em vez de ficar
## apontando para um backend que nunca vai rodar; com ela no menu, a escolha
## do usuário tem que sobreviver intacta.
func test_gpu_preference_is_migrated_only_when_the_gpu_left_the_menu() -> void:
	g._settings = {"inference_backend": g.InferenceBackend.GPU, "gpu_unavailable": true}
	g._migrate_unusable_gpu_preference()

	if g.is_gpu_supported():
		assert_eq(g.get_inference_backend(), g.InferenceBackend.GPU,
			"com GPU no menu a escolha do usuário fica de pé")
		assert_true(g.is_gpu_blocked(), "e o veto continua valendo até ele reescolher")
		return

	assert_eq(g.get_inference_backend(), g.InferenceBackend.AUTO)
	assert_false(g.is_gpu_blocked(), "sem GPU no menu, o veto não tem mais o que vetar")


func test_migration_leaves_other_preferences_alone() -> void:
	g._settings = {"inference_backend": g.InferenceBackend.CPU}
	g._migrate_unusable_gpu_preference()
	assert_eq(g.get_inference_backend(), g.InferenceBackend.CPU)


## Regressão do "botão que não seleciona": aparelho que travou fica com a
## preferência em GPU E o veto ligado. Tocar em GPU tem que limpar o veto,
## mesmo a preferência já sendo GPU — era aí que o atalho de no-op engolia
## o pedido de tentar de novo.
func test_retapping_a_blocked_gpu_clears_the_block() -> void:
	g._settings = {"inference_backend": g.InferenceBackend.GPU, "gpu_unavailable": true}
	assert_eq(g.resolve_inference_backend(), g.InferenceBackend.CPU, "estado inicial: vetada")

	watch_signals(g)
	g.set_inference_backend(g.InferenceBackend.GPU)

	assert_false(g.is_gpu_blocked(), "o toque é o pedido de tentar de novo")
	assert_signal_emit_count(g, "inference_backend_changed", 1,
		"o grafo precisa ser remontado, senão nada acontece na tela")
	if g.is_gpu_supported():
		assert_eq(g.resolve_inference_backend(), g.InferenceBackend.GPU)


## E o atalho continua valendo quando realmente não há nada a fazer.
func test_retapping_without_a_block_is_still_a_noop() -> void:
	g.set_inference_backend(g.InferenceBackend.CPU)
	watch_signals(g)
	g.set_inference_backend(g.InferenceBackend.CPU)
	assert_signal_emit_count(g, "inference_backend_changed", 0)
