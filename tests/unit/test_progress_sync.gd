extends GutTest
## ProgressSync: decisão, mescla e o fluxo contra um servidor falso.
## Nada aqui toca a rede nem o user:// real.

const StubGlobal := preload("res://tests/helpers/stub_global.gd")
const StubSync := preload("res://tests/helpers/stub_progress_sync.gd")
const Sync := preload("res://Scripts/autoload/ProgressSync.gd")

var g: Node
var sync: Node


func before_each() -> void:
	g = add_child_autofree(StubGlobal.new())
	sync = StubSync.new()
	sync._g = g
	add_child_autofree(sync)


# ---------------------------------------------------------------- decide()

func test_decide_nothing_to_do_when_versions_match_and_clean() -> void:
	var d: Dictionary = Sync.decide({"1": {}}, {"versao": 4, "dados": {}}, 4, false, false)
	assert_eq(d.action, "none")


func test_decide_push_local_when_only_local_changed() -> void:
	var local := {"1": {"completed": true, "stars": 2}}
	var d: Dictionary = Sync.decide(local, {"versao": 4, "dados": {}}, 4, true, false)
	assert_eq(d.action, "push")
	assert_eq(d.data, local)


func test_decide_adopts_admin_edit_even_with_local_changes() -> void:
	var server := {"versao": 5, "autoritativo": true, "dados": {"1": {"completed": true, "stars": 1}}}
	var local := {"1": {"completed": true, "stars": 3}}
	var d: Dictionary = Sync.decide(local, server, 4, true, false)
	assert_eq(d.action, "adopt", "o admin corrigiu; a mescla desfaria a correção")
	assert_eq(d.data, server.dados)


func test_decide_merges_when_both_sides_changed() -> void:
	var server := {"versao": 5, "dados": {"2": {"completed": true, "stars": 2}}}
	var local := {"1": {"completed": true, "stars": 3}}
	var d: Dictionary = Sync.decide(local, server, 4, true, false)
	assert_eq(d.action, "push")
	assert_true(d.data.has("1") and d.data.has("2"), "nenhum lado perde lição")


func test_decide_erase_overwrites_instead_of_merging() -> void:
	var server := {"versao": 5, "dados": {"1": {"completed": true, "stars": 3}}}
	var d: Dictionary = Sync.decide({}, server, 4, true, true)
	assert_eq(d.action, "push")
	assert_eq(d.data, {}, "mesclar ressuscitaria o que o usuário apagou")


func test_decide_adopts_server_when_local_is_clean() -> void:
	var server := {"versao": 7, "dados": {"3": {"completed": true, "stars": 1}}}
	var d: Dictionary = Sync.decide({}, server, 4, false, false)
	assert_eq(d.action, "adopt")


# ---------------------------------------------------------------- merge()

func test_merge_keeps_best_of_each_lesson() -> void:
	var a := {"1": {"completed": true, "stars": 1}, "2": {"completed": false, "stars": 0}}
	var b := {"1": {"completed": false, "stars": 3}, "3": {"completed": true, "stars": 2}}
	var m: Dictionary = Sync.merge(a, b)
	assert_eq(m["1"], {"completed": true, "stars": 3})
	assert_true(m.has("2"))
	assert_eq(m["3"].stars, 2)


func test_merge_stats() -> void:
	var a := {"_stats": {
		"xp": 60, "streak": 3, "best_streak": 3, "last_day": "2026-11-08",
		"practices": 10, "precision_sum": 8.0, "signs": {"1:0": 3},
	}}
	var b := {"_stats": {
		"xp": 40, "streak": 5, "best_streak": 6, "last_day": "2026-11-01",
		"practices": 4, "precision_sum": 2.0, "signs": {"1:0": 1, "2:0": 2},
	}}
	var s: Dictionary = Sync.merge(a, b)["_stats"]
	assert_eq(s.signs, {"1:0": 3, "2:0": 2}, "melhor nota por sinal")
	assert_eq(s.xp, 100, "XP = soma das melhores notas × 20, acima dos dois lados")
	assert_eq(s.practices, 10)
	assert_eq(s.precision_sum, 8.0, "precisão vem junto com o lado das práticas")
	assert_eq(s.last_day, "2026-11-08")
	assert_eq(s.streak, 3, "ofensiva do lado mais recente")
	assert_eq(s.best_streak, 6)


func test_merge_with_empty_side_is_identity() -> void:
	var a := {"1": {"completed": true, "stars": 2}, "_stats": {"xp": 40, "signs": {"1:0": 2}}}
	var m: Dictionary = Sync.merge(a, {})
	assert_eq(m["1"], a["1"])
	assert_eq(m["_stats"].xp, 40)


# ---------------------------------------------------------------- fluxo

func test_first_sync_registers_and_uploads_local_progress() -> void:
	g.mark_completed(1, 3)
	await sync.sync_now()
	assert_false(sync.get_uuid().is_empty(), "ganhou um UUID")
	assert_eq(sync.server_row().dados, g.get_progress_snapshot())
	assert_eq(sync.server_row().versao, 1)
	assert_false(sync.has_pending_changes())
	assert_eq(sync.get_status(), Sync.Status.SYNCED)


func test_local_change_marks_dirty_and_next_sync_pushes() -> void:
	await sync.sync_now()
	g.mark_completed(2, 2)
	assert_true(sync.has_pending_changes())
	await sync.sync_now()
	assert_false(sync.has_pending_changes())
	assert_eq(sync.server_row().dados["2"].stars, 2)


func test_admin_edit_replaces_local_progress() -> void:
	g.mark_completed(1, 3)
	g.mark_completed(2, 3)
	await sync.sync_now()

	sync.admin_set({"1": {"completed": true, "stars": 1}})
	watch_signals(g)
	await sync.sync_now()

	assert_eq(g.get_stars(1), 1, "a nota corrigida pelo admin chegou")
	assert_false(g.is_completed(2))
	assert_signal_emitted(g, "progress_replaced", "a Home se redesenha")
	assert_false(sync.has_pending_changes(), "adotar não é alteração nova")


func test_admin_edit_wins_over_offline_local_change() -> void:
	await sync.sync_now()
	sync.admin_set({})
	g.mark_completed(3, 3)   # feito offline, antes de ver a correção
	await sync.sync_now()
	assert_false(g.is_completed(3))


func test_erase_clears_server_copy() -> void:
	g.mark_completed(1, 3)
	await sync.sync_now()
	g.erase_all_data()
	await sync.sync_now()
	assert_eq(sync.server_row().dados, {})


func test_erase_while_offline_does_not_resurrect() -> void:
	g.mark_completed(1, 3)
	await sync.sync_now()
	# Outra gravação (não-admin) chega ao servidor enquanto este aparelho está
	# offline e o usuário apaga tudo: a mescla traria a lição 1 de volta.
	var row: Dictionary = sync.server_row()
	row.versao = int(row.versao) + 1
	sync.offline = true
	g.erase_all_data()
	await sync.sync_now()
	assert_eq(sync.get_status(), Sync.Status.OFFLINE)
	sync.offline = false
	await sync.sync_now()
	assert_eq(sync.server_row().dados, {})
	assert_false(g.is_completed(1))


func test_offline_keeps_changes_pending() -> void:
	sync.offline = true
	g.mark_completed(1, 2)
	await sync.sync_now()
	assert_eq(sync.get_status(), Sync.Status.OFFLINE)
	assert_true(sync.get_uuid().is_empty(), "sem rede não há registro")
	sync.offline = false
	await sync.sync_now()
	assert_eq(sync.server_row().dados["1"].stars, 2)


func test_change_during_put_stays_pending() -> void:
	await sync.sync_now()
	g.mark_completed(1, 1)
	sync.before_put = func() -> void:
		sync.before_put = Callable()
		g.mark_completed(2, 3)   # o usuário terminou outra lição no meio do PUT
	await sync.sync_now()
	assert_eq(sync.server_row().dados["2"].stars, 3,
		"a rodada extra enviou o que mudou durante o PUT")
	assert_false(sync.has_pending_changes())


func test_deleted_user_registers_again_and_reuploads() -> void:
	g.mark_completed(1, 3)
	await sync.sync_now()
	var old_uuid: String = sync.get_uuid()
	sync.server.clear()   # o admin apagou o usuário
	await sync.sync_now()
	assert_ne(sync.get_uuid(), old_uuid, "UUID novo")
	assert_eq(sync.server_row().dados["1"].stars, 3, "o progresso do aparelho subiu de novo")


func test_blocked_user_stops_syncing() -> void:
	await sync.sync_now()
	sync.server_row().bloqueado = true
	g.mark_completed(1, 3)
	await sync.sync_now()
	assert_eq(sync.get_status(), Sync.Status.BLOCKED)
	var before: int = sync.calls.size()
	await sync.sync_now()
	assert_eq(sync.calls.size(), before, "bloqueado não insiste")
	assert_true(g.is_completed(1), "o app continua funcionando offline")
