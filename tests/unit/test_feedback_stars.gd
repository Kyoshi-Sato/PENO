extends GutTest
## Fronteiras do mapeamento precisão → estrelas e formatação de tempo.

var fb: FeedbackState


func before_each() -> void:
	fb = autofree(FeedbackState.new())


func test_star_boundaries() -> void:
	assert_eq(fb._stars_for_precision(1.0), 3)
	assert_eq(fb._stars_for_precision(0.7), 3, "0.7 inclusivo")
	assert_eq(fb._stars_for_precision(0.699), 2)
	assert_eq(fb._stars_for_precision(0.6), 2, "0.6 inclusivo")
	assert_eq(fb._stars_for_precision(0.599), 1)
	assert_eq(fb._stars_for_precision(0.5), 1, "0.5 inclusivo")
	assert_eq(fb._stars_for_precision(0.499), 0)
	assert_eq(fb._stars_for_precision(0.0), 0)


func test_format_time() -> void:
	assert_eq(fb._format_time(0), "00:00")
	assert_eq(fb._format_time(75), "01:15")
	assert_eq(fb._format_time(600), "10:00")


## A `evaluate()` roda a análise numa tarefa do WorkerThreadPool. Cada
## `add_task` exige um `wait_for_task_completion` correspondente: sem ele a
## vaga fica presa no pool para sempre e o engine ABORTA ao encerrar o
## processo — o que também derruba a suíte inteira em CI, depois de ela já
## ter reportado sucesso.
##
## Este teste vigia a invariante observável: nenhuma tarefa fica pendurada
## depois que o resultado chegou.
func test_tarefa_do_pool_e_recolhida() -> void:
	var tela: FeedbackState = load("res://GUI/feedback/FeedbackState.tscn").instantiate()
	add_child_autofree(tela)

	var licao := Lesson.new()
	licao.lesson_id = 98
	licao.sinais = [{"nome_sinal": "S", "json_sinal": {}}]
	tela.validator = DebugValidator.create(0.4)

	tela.evaluate(licao, 0, {})
	assert_eq(tela._tasks.size(), 1, "a tarefa não foi registrada para recolhimento")

	await wait_for_signal(tela.evaluation_completed, 5.0)
	assert_eq(tela._tasks.size(), 0, "a vaga da tarefa vazou no WorkerThreadPool")
