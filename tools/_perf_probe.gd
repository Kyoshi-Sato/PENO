extends SceneTree
## Mede o custo de instanciar cada cena, isolado da transição.

func _init() -> void:
	await process_frame
	for path: String in [
		"res://GUI/lessonmap/LessonMapScreen.tscn",
		"res://GUI/progress/ProgressScreen.tscn",
		"res://assets/models/Libra/Libra.tscn",
		"res://GUI/Screens/Main/Main.tscn",
		"res://GUI/lessonscreen/LessonScreen.tscn",
	]:
		var packed: PackedScene = load(path)   # já cacheado
		var t0 := Time.get_ticks_usec()
		var inst: Node = packed.instantiate()
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		print("%-46s instantiate: %7.1f ms" % [path.get_file(), dt])
		inst.free()
	quit(0)
