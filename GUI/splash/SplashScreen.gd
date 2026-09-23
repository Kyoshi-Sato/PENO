extends Control
## Cena de entrada do app.
##
## Existe por três motivos concretos, nenhum decorativo:
##
## 1. CONFIGURAÇÃO — orientação e safe area só podem ser consultadas com o
##    DisplayServer já ativo, o que não acontece em tempo de projeto.
##
## 2. AQUECIMENTO — `Global.warm_scene_cache()` destrava o GLB do avatar e as
##    texturas dele. Antes isso rodava em `Global._ready()`, competindo com o
##    primeiro quadro da Home: a tela abria e engasgava. Aqui o trabalho
##    acontece enquanto o usuário olha para a marca, que é o único momento em
##    que uma espera é aceitável.
##
## 3. PRIMEIRA IMPRESSÃO — sem isto, o app abre direto numa Home com a trilha
##    vazia enquanto a API responde.
##
## A barra de progresso é real: reflete quantas cenas já foram carregadas.

## Resolver `class_name` a partir de uma thread de carregamento é uma corrida
## conhecida do GDScript: a LessonScreen puxa HolisticLandmarker.gd, que faz
## `extends VisionTask`, e o carregamento em thread às vezes falhava com
## "Could not resolve class VisionTask" — de forma intermitente (medido: 7, 4
## e 0 erros em três boots seguidos). Estes `preload` são resolvidos em tempo
## de compilação DESTE script, ou seja, na thread principal, antes de `_boot`
## disparar qualquer requisição. Não são usados diretamente; existem para
## garantir que as classes já estejam compiladas e em cache.
const _WARM_VISION_TASK := preload("res://GUI/vision/VisionTask.gd")
const _WARM_HOLISTIC := preload(
	"res://GUI/vision/holistic_landmarker/HolisticLandmarker.gd")
const HandShapeClassifierScript := preload("res://Scripts/HandShapeClassifier.gd")

## Tempo mínimo em tela. Se o aquecimento terminar antes, ainda esperamos —
## um splash que pisca por 80 ms é pior do que nenhum.
const MIN_DURATION := 1.2

@onready var bar: ProgressBar = %Bar
@onready var lbl_status: Label = %StatusLabel
@onready var brand: VBoxContainer = %Brand


func _ready() -> void:
	bar.value = 0.0
	lbl_status.text = "Iniciando HandSign…"
	Motion.fade_in(brand, DS.DUR_SLOW, 0.0)
	_boot()


func _boot() -> void:
	var p: Node = get_node_or_null("/root/Profiler")
	if p != null and p.has_method("start_timer"):
		p.start_timer("APP_STARTUP_BOOT")

	var started := Time.get_ticks_msec()

	# 1. Carregamento de Cenas e Mascote/Avatar 3D
	lbl_status.text = "Carregando interface e avatar 3D…"
	var scenes: Array[String] = [
		Global.MAIN_SCENE, Global.MAP_SCENE,
		Global.PROGRESS_SCENE, Global.LESSON_SCENE,
	]

	for i in range(scenes.size()):
		if p != null and p.has_method("start_timer"):
			p.start_timer("PRELOAD_SCENE_%d" % i)
		await Global.preload_scene(scenes[i])
		if p != null and p.has_method("end_timer"):
			p.end_timer("PRELOAD_SCENE_%d" % i, {"path": scenes[i]})
		Motion.fill_bar(bar, float(i + 1) * 0.15, DS.DUR_FAST)

	# 2. Inicialização do Motor Neural de IA (HandShapeClassifier)
	lbl_status.text = "Inicializando IA e biomecânica…"
	if p != null and p.has_method("start_timer"):
		p.start_timer("WARM_AI_NEURAL_ENGINE")
	await get_tree().process_frame
	var _shared := HandShapeClassifierScript.get_shared_engine()
	if p != null and p.has_method("end_timer"):
		p.end_timer("WARM_AI_NEURAL_ENGINE", {"classes": _shared.labels.size() if "labels" in _shared else 0})
	Motion.fill_bar(bar, 0.85, DS.DUR_FAST)

	# 3. Inicialização antecipada da câmera em segundo plano
	lbl_status.text = "Detectando câmera do dispositivo…"
	if not CameraServer.monitoring_feeds:
		CameraServer.monitoring_feeds = true
	if OS.get_name() in ["Windows", "iOS"]:
		var _cam_ext := CameraServerExtension.new()
	await get_tree().process_frame

	# 4. Pré-busca do Catálogo de Lições
	lbl_status.text = "Sincronizando catálogo…"
	if p != null and p.has_method("start_timer"):
		p.start_timer("PREFETCH_CATALOG")
	LessonService.fetch_catalog()
	if p != null and p.has_method("end_timer"):
		p.end_timer("PREFETCH_CATALOG")
	Motion.fill_bar(bar, 1.0, DS.DUR_FAST)

	lbl_status.text = "Tudo pronto!"
	if p != null and p.has_method("end_timer"):
		p.end_timer("APP_STARTUP_BOOT", {"status": "SUCCESS"})

	# Completa o tempo mínimo antes de sair.
	var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
	if elapsed < MIN_DURATION:
		await get_tree().create_timer(MIN_DURATION - elapsed).timeout

	Global.go_to_main_scene()
