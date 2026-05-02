@tool
extends Control
func _ready() -> void: 
	var mc := MotionComparator.new()
	var json_a := mc.load_json("res://data/ABACATEBOM.json")
	var json_b := mc.load_json("res://holistic_capture_2026-04-12_15-36-32.json")
	var results := mc.analyze_similarity(json_a, json_b)
	mc.print_summary(results, "BOM", "RUIM")
