extends Node

## Teste automatizado da Etapa 7 (integração com Supabase e ranking) — Etapa 8 da
## Metodologia.
##
## Como rodar:
##   godot --headless --path . res://tests/teste_ranking.tscn
## Sai com código 0 se tudo passar, 1 se algo falhar.
##
## Roda como CENA, não com --script: em modo --script o Godot não instancia os autoloads,
## e sem GameManager/Perfil/SupabaseClient nada aqui compila.
##
## NÃO TOCA A REDE, por decisão: um teste que dependesse do Supabase no ar falharia no dia
## da apresentação por causa de wi-fi. O que se verifica aqui é o que não depende do
## servidor — formato do que vai para o banco, ordem do ranking e comportamento offline.
##
## O que cada cenário protege:
##   1. payload    — o banco recebe as notas POR QUADRANTE, e não só o placar agregado.
##   2. ordenação  — maior pontuação primeiro, empate desempatado por tempo menor.
##   3. local      — partida jogada offline sobrevive e reaparece no ranking local.
##   4. pendentes  — o que ficou offline entra na fila e é drenado depois.
##   5. sem config — sem credenciais nada estoura, e o ranking se declara local.
##   6. melhor     — uma linha por jogador por dia, a de maior pontuação.
##   7. com nuvem  — COM credenciais, a partida entra no lote em vez de sair vazia.

## Arquivo descartável: o cliente é apontado para cá para que a suíte não apague o
## ranking real de quem estiver jogando nesta máquina.
const CAMINHO_TESTE := "user://teste_ranking.cfg"

var falhas := 0


func _ready() -> void:
	SupabaseClient.caminho_local = CAMINHO_TESTE
	Perfil.caminho = "user://teste_perfil.cfg"
	_limpar()

	_cenario_payload()
	_cenario_ordenacao()
	_cenario_ranking_local()
	_cenario_fila_de_pendentes()
	await _cenario_sem_configuracao()
	_cenario_melhor_por_jogador()
	_cenario_com_nuvem_configurada()

	_limpar()
	print("\n=====  %s  =====" % ("FALHOU (%d)" % falhas if falhas else "TODOS OS TESTES OK"))
	get_tree().quit(1 if falhas else 0)


## Trava do formato enviado ao banco: simplificar a partida para "nickname e pontos"
## quebra este cenário. A nota por categoria precisa existir no banco, não só na tela.
func _cenario_payload() -> void:
	print("\n--- cenário 1: o que vai para o banco ---")

	Perfil.nickname = "Kleytonn"
	GameManager.iniciar_fase(90.0, 2)
	var cat := GameManager.Categoria
	var acao := GameManager.Acao
	GameManager.registrar_acao(cat.URGENTE_IMPORTANTE, acao.COLETAR)     # +100
	GameManager.registrar_acao(cat.URGENTE_IMPORTANTE, acao.COLETAR)     # +100
	GameManager.registrar_acao(cat.IMPORTANTE_NAO_URGENTE, acao.COLETAR) # +80
	GameManager.registrar_acao(cat.URGENTE_NAO_IMPORTANTE, acao.DELEGAR) # +60
	GameManager.registrar_acao(cat.URGENTE_NAO_IMPORTANTE, acao.RESOLVER)# +40, -5s
	GameManager.registrar_acao(cat.NAO_URGENTE_NAO_IMPORTANTE, acao.COLIDIU) # -20, -8s
	GameManager.registrar_acao(cat.URGENTE_IMPORTANTE, acao.IGNOROU)     # 0
	GameManager.registrar_interrupcao(3.0, 2.2)
	GameManager.finalizar_fase(true)

	var partida := SupabaseClient.montar_partida()

	_conferir("nickname vai junto", partida["nickname"], "Kleytonn")
	_conferir("dia vai junto", partida["dia"], 2)
	_conferir("vitória vai junto", partida["vitoria"], true)
	_conferir("pontuação agregada", partida["pontuacao"], 360)

	# A leitura por quadrante — o coração do requisito.
	_conferir("Q1 contadas (3, uma delas ignorada)", partida["q1_tarefas"], 3)
	_conferir("Q2 contadas", partida["q2_tarefas"], 1)
	_conferir("Q3 contadas", partida["q3_tarefas"], 2)
	_conferir("Q4 contadas", partida["q4_tarefas"], 1)
	_conferir("Q1 pontos", partida["q1_pontos"], 200)
	_conferir("Q4 pontos (colisão custa)", partida["q4_pontos"], -20)

	# A leitura por ação, que é o que distingue delegar de resolver no Q3.
	_conferir("delegou", partida["delegou"], 1)
	_conferir("resolveu", partida["resolveu"], 1)
	_conferir("colidiu", partida["colidiu"], 1)
	_conferir("ignorou registrado, não sumido", partida["ignorou"], 1)
	_conferir("interrupções fora da matriz", partida["interrupcoes"], 1)

	# O tempo gasto tem que refletir os descontos das ações, senão o ranking desempata
	# por um número que não é o que aconteceu.
	_conferir("tempo gasto inclui as penalidades", partida["tempo_gasto"] >= 13.0, true)

	# Nenhum campo de controle nosso pode vazar para o corpo do POST: PostgREST recusa a
	# coluna desconhecida e devolve 400 para o lote inteiro.
	_conferir("sem campo de controle no payload", partida.has("pendente"), false)


func _cenario_ordenacao() -> void:
	print("\n--- cenário 2: ordem do ranking ---")

	var bruto := [
		{"nickname": "c", "pontuacao": 800, "tempo_gasto": 40.0},
		{"nickname": "a", "pontuacao": 1200, "tempo_gasto": 70.0},
		{"nickname": "b", "pontuacao": 1200, "tempo_gasto": 55.0},
	]
	var ordenado := SupabaseClient.ordenar(bruto)

	_conferir("maior pontuação primeiro", ordenado[0]["nickname"], "b")
	_conferir("empate desempata por tempo menor", ordenado[1]["nickname"], "a")
	_conferir("menor pontuação por último", ordenado[2]["nickname"], "c")
	_conferir("ordenar não destrói a lista original", bruto[0]["nickname"], "c")


func _cenario_ranking_local() -> void:
	print("\n--- cenário 3: a partida offline sobrevive ---")
	_limpar()

	SupabaseClient.guardar_local(
		{"nickname": "Ana", "dia": 1, "pontuacao": 900, "tempo_gasto": 60.0, "q1_tarefas": 5}, true
	)
	SupabaseClient.guardar_local(
		{"nickname": "Bia", "dia": 1, "pontuacao": 1100, "tempo_gasto": 72.0, "q1_tarefas": 7}, true
	)
	# Dia diferente: não pode aparecer na consulta do Dia 1.
	SupabaseClient.guardar_local(
		{"nickname": "Cau", "dia": 2, "pontuacao": 5000, "tempo_gasto": 30.0}, true
	)

	var dia1 := SupabaseClient.ranking_local(1)
	_conferir("só as partidas do dia consultado", dia1.size(), 2)
	_conferir("melhor do dia na frente", dia1[0]["nickname"], "Bia")
	_conferir("a leitura por quadrante veio junto", dia1[0]["q1_tarefas"], 7)
	_conferir("o Dia 2 tem a sua própria lista", SupabaseClient.ranking_local(2).size(), 1)

	# Sobrevive a reler do disco — que é o que acontece quando o jogo é reaberto.
	_conferir("histórico persistido em disco", SupabaseClient.historico().size(), 3)


func _cenario_fila_de_pendentes() -> void:
	print("\n--- cenário 4: fila do que ficou offline ---")
	_limpar()

	SupabaseClient.guardar_local({"nickname": "Ana", "dia": 1, "pontuacao": 100}, true)
	SupabaseClient.guardar_local({"nickname": "Ana", "dia": 1, "pontuacao": 200}, true)
	SupabaseClient.guardar_local({"nickname": "Ana", "dia": 1, "pontuacao": 300}, false)

	var fila := SupabaseClient.pendentes()
	_conferir("só as pendentes entram na fila", fila.size(), 2)
	_conferir("a marca de controle não vai no lote", fila[0].has("pendente"), false)

	SupabaseClient._marcar_enviadas()
	_conferir("fila vazia depois do envio", SupabaseClient.pendentes().size(), 0)
	_conferir("nada foi perdido do histórico", SupabaseClient.historico().size(), 3)


## Sem credenciais o jogo continua inteiro, e o ranking se declara local. É o caminho que
## o projeto percorre enquanto não houver projeto Supabase configurado — e o caminho que
## qualquer jogador percorre quando a rede cai no meio de uma partida na web.
func _cenario_sem_configuracao() -> void:
	print("\n--- cenário 5: sem nuvem configurada ---")
	_limpar()

	var url := SupabaseClient.supabase_url
	var chave := SupabaseClient.supabase_anon_key
	SupabaseClient.supabase_url = ""
	SupabaseClient.supabase_anon_key = ""

	_conferir("configurado() é falso sem credenciais", SupabaseClient.configurado(), false)

	SupabaseClient.guardar_local({"nickname": "Ana", "dia": 1, "pontuacao": 700}, true)

	# Dicionário, e não duas variáveis soltas: lambda em GDScript captura local POR VALOR,
	# então atribuir a uma variável capturada não sai de dentro da lambda. Um Dictionary é
	# referência, e a mutação atravessa.
	var resposta := {}
	SupabaseClient.ranking_recebido.connect(
		func(linhas: Array, de_onde: String) -> void:
			resposta["linhas"] = linhas
			resposta["origem"] = de_onde,
		CONNECT_ONE_SHOT
	)
	SupabaseClient.pedir_ranking(1)
	await get_tree().process_frame

	_conferir("responde mesmo sem nuvem", (resposta.get("linhas", []) as Array).size(), 1)
	_conferir("e se declara local, sem fingir nuvem", resposta.get("origem", ""), "local")

	# Uma partida sem nome não vai para lugar nenhum: o ranking é por nickname, e uma
	# linha anônima seria lixo permanente num banco que não permite delete.
	Perfil.nickname = ""
	var recusa := {}
	SupabaseClient.envio_concluido.connect(
		func(_ok: bool, mensagem: String) -> void: recusa["texto"] = mensagem,
		CONNECT_ONE_SHOT
	)
	SupabaseClient.enviar_partida()
	await get_tree().process_frame
	_conferir(
		"partida sem nickname é recusada",
		str(recusa.get("texto", "")).contains("Sem nickname"), true
	)
	_conferir("e não suja o histórico", SupabaseClient.historico().size(), 1)

	SupabaseClient.supabase_url = url
	SupabaseClient.supabase_anon_key = chave
	Perfil.nickname = "Kleytonn"


## Sem isto, um jogador insistente ocuparia as dez posições do ranking sozinho. A regra é
## a mesma da view `ranking` no servidor (supabase/schema.sql) — de propósito: o ranking
## local e o global precisam ter a mesma leitura.
func _cenario_melhor_por_jogador() -> void:
	print("\n--- cenário 6: uma linha por jogador ---")
	_limpar()

	SupabaseClient.guardar_local({"nickname": "Ana", "dia": 1, "pontuacao": 400, "tempo_gasto": 80.0}, false)
	SupabaseClient.guardar_local({"nickname": "Ana", "dia": 1, "pontuacao": 900, "tempo_gasto": 65.0}, false)
	SupabaseClient.guardar_local({"nickname": "Ana", "dia": 1, "pontuacao": 700, "tempo_gasto": 50.0}, false)
	SupabaseClient.guardar_local({"nickname": "Bia", "dia": 1, "pontuacao": 500, "tempo_gasto": 60.0}, false)

	var ranking := SupabaseClient.ranking_local(1)
	_conferir("quatro partidas viram duas linhas", ranking.size(), 2)
	_conferir("a melhor da Ana é a que aparece", ranking[0]["pontuacao"], 900)
	_conferir("e ela lidera", ranking[0]["nickname"], "Ana")

	# O limite é respeitado: a tela mostra dez, não o histórico inteiro da máquina.
	_conferir("limite respeitado", SupabaseClient.ranking_local(1, 1).size(), 1)


## COM credenciais, a partida recém-jogada tem de entrar no lote que sobe.
##
## Nasceu de um defeito real, e o defeito era invisível: enviar_partida() gravava a partida
## já marcada como ENVIADA quando havia nuvem configurada. O lote é pendentes(), então saía
## vazio; o PostgREST aceita um array vazio e responde 201; e o jogo anunciava "Registrado
## no ranking global" sem ter gravado uma linha sequer. O placar do jogador sumia em
## silêncio, e a tela dizia que tinha dado certo.
##
## Os cenários 1 a 6 não pegavam isso porque todos rodam SEM credenciais — que era, até a
## conta do Supabase existir, o único estado em que o projeto já tinha estado. É o tipo de
## defeito que só aparece no dia em que a configuração muda, ou seja, no pior dia possível.
##
## Continua sem tocar a rede: forçamos _enviando, e enviar_partida() sai antes do
## HTTPRequest. O que se mede é a única linha que estava errada — com que marca a partida
## é gravada — e não a resposta do servidor.
func _cenario_com_nuvem_configurada() -> void:
	print("\n--- cenário 7: com nuvem configurada, o lote não sai vazio ---")
	_limpar()

	var url := SupabaseClient.supabase_url
	var chave := SupabaseClient.supabase_anon_key
	SupabaseClient.supabase_url = "https://exemplo.supabase.co"
	SupabaseClient.supabase_anon_key = "chave-de-teste"
	Perfil.nickname = "Ana"
	GameManager.iniciar_fase(60.0, 1)
	GameManager.registrar_acao(
		GameManager.Categoria.URGENTE_IMPORTANTE, GameManager.Acao.COLETAR
	)

	_conferir("configurado() é verdadeiro com credenciais", SupabaseClient.configurado(), true)

	SupabaseClient._enviando = true
	SupabaseClient.enviar_partida()
	SupabaseClient._enviando = false

	_conferir("a partida foi guardada", SupabaseClient.historico().size(), 1)
	_conferir("e nasce PENDENTE, mesmo com nuvem", SupabaseClient.pendentes().size(), 1)
	_conferir(
		"o lote leva o placar de verdade",
		SupabaseClient.pendentes()[0]["pontuacao"], GameManager.pontuacao_total
	)

	# E só deixa de ser pendente quando o servidor confirma.
	SupabaseClient._marcar_enviadas()
	_conferir("confirmado o envio, a fila esvazia", SupabaseClient.pendentes().size(), 0)
	_conferir("mas o histórico local guarda a partida", SupabaseClient.historico().size(), 1)

	SupabaseClient.supabase_url = url
	SupabaseClient.supabase_anon_key = chave


func _limpar() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CAMINHO_TESTE))
	if FileAccess.file_exists(CAMINHO_TESTE):
		DirAccess.open("user://").remove(CAMINHO_TESTE.get_file())


func _conferir(o_que: String, obtido: Variant, esperado: Variant) -> void:
	var passou: bool = obtido == esperado
	if not passou:
		falhas += 1
	print("  %s  %s = %s%s" % [
		"ok   " if passou else "FALHA",
		o_que, str(obtido),
		"" if passou else "   (esperado %s)" % str(esperado),
	])
