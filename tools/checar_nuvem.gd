extends Node

## Confere, contra o Supabase de verdade, se as credenciais de supabase.cfg funcionam:
## grava uma partida e lê o ranking de volta. Roda como CENA, e não com --script, porque
## os autoloads (GameManager, SupabaseClient, Perfil) não são instanciados no modo --script.
##
##   godot --headless --path . res://tools/checar_nuvem.tscn
##
## A suíte tests/teste_ranking.tscn NÃO faz isto de propósito: um teste que dependesse da
## rede falharia no dia da apresentação por causa do wi-fi. Esta ferramenta é o contrário —
## existe justamente para exercitar a rede, uma vez, quando se muda a configuração.
##
## Os sinais são CONECTADOS antes de chamar, e não aguardados com await depois. Vários
## caminhos de erro de enviar_partida() emitem o sinal de forma síncrona, ainda dentro da
## chamada — um await registrado depois disso esperaria para sempre.

const ESPERA_MAXIMA := 25.0

var _resposta_envio: Array = []
var _resposta_leitura: Array = []


func _ready() -> void:
	print("url configurada:   ", "sim" if SupabaseClient.supabase_url != "" else "NAO")
	print("chave configurada: ", "sim" if SupabaseClient.supabase_anon_key != "" else "NAO")

	if not SupabaseClient.configurado():
		print("\nSem credenciais: o jogo cai no ranking local, como previsto.")
		get_tree().quit(1)
		return

	SupabaseClient.caminho_local = "user://checagem_nuvem.cfg"
	SupabaseClient.envio_concluido.connect(func(ok, msg): _resposta_envio = [ok, msg])
	SupabaseClient.ranking_recebido.connect(func(l, o): _resposta_leitura = [l, o])

	Perfil.nickname = "checagem"
	var cat := GameManager.Categoria
	var acao := GameManager.Acao
	GameManager.iniciar_fase(60.0, 1)
	GameManager.registrar_acao(cat.URGENTE_IMPORTANTE, acao.COLETAR)
	GameManager.registrar_acao(cat.IMPORTANTE_NAO_URGENTE, acao.COLETAR)
	GameManager.registrar_acao(cat.URGENTE_NAO_IMPORTANTE, acao.DELEGAR)
	GameManager.registrar_acao(cat.NAO_URGENTE_NAO_IMPORTANTE, acao.EVITOU)
	GameManager.finalizar_fase(true)

	SupabaseClient.enviar_partida()
	await _esperar(func(): return not _resposta_envio.is_empty())
	print("\nenvio: ", "OK" if _resposta_envio and _resposta_envio[0] else "FALHOU",
		" — ", _resposta_envio[1] if _resposta_envio else "sem resposta")

	SupabaseClient.pedir_ranking(1)
	await _esperar(func(): return not _resposta_leitura.is_empty())

	var origem := String(_resposta_leitura[1]) if _resposta_leitura else "sem resposta"
	var linhas: Array = _resposta_leitura[0] if _resposta_leitura else []
	print("leitura: origem = ", origem, ", ", linhas.size(), " linha(s)")
	for linha in linhas:
		print("   ", linha.get("nickname", "?"), " — ", linha.get("pontuacao", 0), " pts",
			"  (Q1 ", linha.get("q1_tarefas", 0), " · Q2 ", linha.get("q2_tarefas", 0),
			" · delegou ", linha.get("delegou", 0), ")")

	var ok: bool = not _resposta_envio.is_empty() and bool(_resposta_envio[0]) and origem == "nuvem"
	print("\n", "=====  NUVEM RESPONDENDO  =====" if ok else "=====  AINDA LOCAL  =====")
	get_tree().quit(0 if ok else 1)


## Espera a condição virar verdadeira, com teto de tempo: sinal que nunca chega deixa a
## ferramenta pendurada para sempre.
func _esperar(condicao: Callable) -> void:
	var limite := Time.get_ticks_msec() + int(ESPERA_MAXIMA * 1000.0)
	while not condicao.call() and Time.get_ticks_msec() < limite:
		await get_tree().process_frame
