extends Node

## Ponto único de comunicação com o Supabase (PostgREST) via HTTPRequest, sem plugins e
## sem servidor próprio.
##
## Ninguém mais no projeto monta URL, cabeçalho ou JSON: para gravar, enviar_partida();
## para ler, pedir_ranking() e escutar o sinal. As funções que montam o corpo do POST e
## que ordenam o ranking são puras, o que permite testar tudo sem rede.
##
## Sem credenciais (ver CAMINHOS_CONFIG), ou com a rede fora, a partida vai para
## user://ranking_local.cfg e a tela mostra o resultado rotulado como LOCAL. Toda partida
## é gravada localmente primeiro; quando um envio dá certo, as pendentes sobem junto.

## Emitido ao fim de uma tentativa de envio. `mensagem` é texto curto pronto para a tela.
signal envio_concluido(ok: bool, mensagem: String)
## `linhas` é um Array de Dictionary já ordenado; `origem` é "nuvem" ou "local".
signal ranking_recebido(linhas: Array, origem: String)

## Onde procurar as credenciais, em ordem. Fica fora do controle de versão (o .gitignore
## trata os dois) porque a chave anônima, mesmo sendo pública por natureza no Supabase,
## não deve ir para um repositório público junto do resto — quem clonar o projeto grava
## no banco de outra pessoa sem perceber.
##
## user:// vem depois de res:// para que um build já exportado possa ser reconfigurado sem
## reexportar.
const CAMINHOS_CONFIG := ["res://supabase.cfg", "user://supabase.cfg"]

## Onde as partidas jogadas nesta máquina ficam guardadas — sempre, com nuvem ou sem.
##
## Variável e não constante para que o teste automatizado possa apontar para um arquivo
## descartável. Sem essa costura, rodar a suíte apagaria o ranking real de quem estivesse
## jogando na mesma máquina — o teste passaria e o jogador perderia o histórico.
var caminho_local := "user://ranking_local.cfg"

## Tabela de escrita e view de leitura. A view existe para que o ranking mostre a MELHOR
## partida de cada jogador, e não dez linhas do mesmo nickname insistente. O esquema
## está em supabase/schema.sql.
const TABELA := "partidas"
const VISAO_RANKING := "ranking"

## Quantas linhas a tela de ranking pede por padrão.
const LIMITE_PADRAO := 10

## Segundos antes de desistir de uma requisição. Curto de propósito: o jogador está numa
## tela de resultado esperando para clicar "repetir", e um ranking que demora é pior que
## um ranking local imediato.
const ESPERA := 6.0

var supabase_url: String = ""
var supabase_anon_key: String = ""

var _envio: HTTPRequest
var _consulta: HTTPRequest
## Trava de reentrada: dois envios simultâneos duplicariam a fila de pendentes.
var _enviando := false
## Consulta ao ranking em curso. Ver o comentário em pedir_ranking(): no export web o
## estado do HTTPRequest não pode ser lido por get_http_client_status(), então quem sabe
## se há requisição pendente somos nós.
var _consultando := false


## Dois nós de requisição, e não um: o envio da partida e a consulta ao ranking acontecem
## na MESMA tela de resultado, e um HTTPRequest só atende uma requisição por vez.
func _ready() -> void:
	_envio = _criar_requisicao()
	_envio.request_completed.connect(_ao_responder_envio)
	_consulta = _criar_requisicao()
	_consulta.request_completed.connect(_ao_responder_consulta)
	carregar_configuracao()

	# Uma linha no console, e é deliberada: quando o ranking aparece como local, a primeira
	# pergunta é sempre "faltou credencial ou faltou rede?", e as duas causas produzem
	# exatamente a mesma tela. No export web isto sai no console do navegador, que é o
	# único lugar onde dá para investigar um build já publicado. Não imprime a chave.
	print("[ranking] nuvem configurada: ", "sim" if configurado() else "nao")


## True quando há URL e chave para falar com a nuvem. A tela de ranking usa isto para
## saber se deve sequer tentar, e o teste automatizado para exercitar o caminho offline.
func configurado() -> bool:
	return not supabase_url.is_empty() and not supabase_anon_key.is_empty()


## Lê as credenciais do primeiro arquivo que existir. Chamada no _ready, e exposta para
## que o teste possa recarregar depois de mexer nos arquivos.
##
## Falha de leitura é silenciosa e equivale a "sem nuvem": um jogo que não abre porque
## faltou um arquivo de configuração opcional é um jogo quebrado.
func carregar_configuracao() -> bool:
	supabase_url = ""
	supabase_anon_key = ""
	for caminho in CAMINHOS_CONFIG:
		var arquivo := ConfigFile.new()
		if arquivo.load(caminho) != OK:
			continue
		supabase_url = str(arquivo.get_value("supabase", "url", "")).strip_edges().rstrip("/")
		supabase_anon_key = str(arquivo.get_value("supabase", "anon_key", "")).strip_edges()
		if configurado():
			return true
	return false


# Escrita

## O corpo do POST, montado a partir do estado da sessão. Puro e público: é por aqui que
## o teste entra, e é aqui que se vê, num lugar só, tudo o que o banco em nuvem guarda.
##
## Guarda as contagens POR QUADRANTE e POR AÇÃO, e não só o total: o desempenho por
## categoria é o dado que o jogo se propõe a medir, e ele precisa existir no banco, não
## só na tela de resultado.
func montar_partida() -> Dictionary:
	var cat := GameManager.Categoria
	var acao := GameManager.Acao
	return {
		"nickname": Perfil.nickname,
		"dia": GameManager.dia,
		"vitoria": GameManager.ultima_vitoria,
		"pontuacao": GameManager.pontuacao_total,
		"tempo_gasto": snappedf(GameManager.tempo_gasto, 0.01),
		"tempo_restante": snappedf(GameManager.tempo_restante, 0.01),
		"q1_tarefas": GameManager.tarefas_por_categoria[cat.URGENTE_IMPORTANTE],
		"q2_tarefas": GameManager.tarefas_por_categoria[cat.IMPORTANTE_NAO_URGENTE],
		"q3_tarefas": GameManager.tarefas_por_categoria[cat.URGENTE_NAO_IMPORTANTE],
		"q4_tarefas": GameManager.tarefas_por_categoria[cat.NAO_URGENTE_NAO_IMPORTANTE],
		"q1_pontos": GameManager.pontuacao_por_categoria[cat.URGENTE_IMPORTANTE],
		"q2_pontos": GameManager.pontuacao_por_categoria[cat.IMPORTANTE_NAO_URGENTE],
		"q3_pontos": GameManager.pontuacao_por_categoria[cat.URGENTE_NAO_IMPORTANTE],
		"q4_pontos": GameManager.pontuacao_por_categoria[cat.NAO_URGENTE_NAO_IMPORTANTE],
		"delegou": GameManager.acoes_por_tipo[acao.DELEGAR],
		"resolveu": GameManager.acoes_por_tipo[acao.RESOLVER],
		"evitou": GameManager.acoes_por_tipo[acao.EVITOU],
		"colidiu": GameManager.acoes_por_tipo[acao.COLIDIU],
		"ignorou": GameManager.acoes_por_tipo[acao.IGNOROU],
		"interrupcoes": GameManager.interrupcoes,
	}


## Grava a partida que acabou de terminar. Local primeiro, nuvem depois — nessa ordem,
## porque a gravação local é a única que não pode falhar.
##
## Emite envio_concluido() sempre, inclusive quando não há nuvem configurada: quem chama
## mostra uma linha de estado e não precisa saber se existe internet.
func enviar_partida() -> void:
	var partida := montar_partida()
	if partida["nickname"] == "":
		envio_concluido.emit(false, "Sem nickname — partida não registrada.")
		return

	# Sempre pendente, inclusive com a nuvem no ar: quem tira a marca é _marcar_enviadas(),
	# depois de o servidor confirmar. O envio em lote depende disso, já que o lote é
	# justamente pendentes() — marcar como enviada aqui faria o POST sair vazio.
	guardar_local(partida, true)

	if not configurado():
		envio_concluido.emit(false, "Ranking local (nuvem não configurada).")
		return
	if _enviando:
		envio_concluido.emit(false, "Envio anterior ainda em curso.")
		return

	_enviando = true
	var lote := pendentes()
	var erro := _envio.request(
		"%s/rest/v1/%s" % [supabase_url, TABELA],
		_cabecalhos(["Prefer: return=minimal"]),
		HTTPClient.METHOD_POST,
		JSON.stringify(lote)
	)
	if erro != OK:
		_enviando = false
		envio_concluido.emit(false, "Falha ao contatar o servidor — salvo localmente.")


## Sobe de uma vez a partida atual e tudo o que ficou para trás em partidas offline. É
## por isso que o lote é a fila inteira e não só o registro novo.
func _ao_responder_envio(
	resultado: int, codigo: int, _recebidos: PackedStringArray, _corpo: PackedByteArray
) -> void:
	_enviando = false
	if resultado != HTTPRequest.RESULT_SUCCESS or codigo < 200 or codigo >= 300:
		_relatar_falha("envio", resultado, codigo)
		envio_concluido.emit(false, "Sem conexão — partida salva localmente (%d)." % codigo)
		return
	var quantas := pendentes().size()
	_marcar_enviadas()
	var texto := "Registrado no ranking global."
	if quantas > 1:
		texto = "Registrado, com %d partidas offline anteriores." % (quantas - 1)
	envio_concluido.emit(true, texto)


# Leitura

## Pede o ranking do dia. Responde SEMPRE por ranking_recebido(), com origem "nuvem" ou
## "local" — a tela precisa poder dizer ao jogador de onde veio a lista, porque um ranking
## que mente sobre a própria origem é pior do que nenhum ranking.
func pedir_ranking(dia: int, limite: int = LIMITE_PADRAO) -> void:
	if not configurado():
		ranking_recebido.emit(ranking_local(dia, limite), "local")
		return

	var url := "%s/rest/v1/%s?dia=eq.%d&order=pontuacao.desc,tempo_gasto.asc&limit=%d" % [
		supabase_url, VISAO_RANKING, dia, limite
	]
	# A fonte da verdade é este campo, e não get_http_client_status(): no export web quem
	# busca é o navegador, e o status do cliente interno não descreve esse estado. Sem a
	# trava, trocar de dia depressa dispara request() sobre um nó ocupado, o Godot recusa,
	# e a lista do dia anterior fica sob o título do dia novo.
	if _consultando:
		_consulta.cancel_request()
	_consultando = true
	_consulta.set_meta("dia", dia)
	_consulta.set_meta("limite", limite)
	if _consulta.request(url, _cabecalhos(), HTTPClient.METHOD_GET) != OK:
		_consultando = false
		ranking_recebido.emit(ranking_local(dia, limite), "local")


func _ao_responder_consulta(
	resultado: int, codigo: int, _recebidos: PackedStringArray, corpo: PackedByteArray
) -> void:
	_consultando = false
	var dia := int(_consulta.get_meta("dia", 1))
	var limite := int(_consulta.get_meta("limite", LIMITE_PADRAO))

	if resultado != HTTPRequest.RESULT_SUCCESS or codigo < 200 or codigo >= 300:
		_relatar_falha("consulta", resultado, codigo)
		ranking_recebido.emit(ranking_local(dia, limite), "local")
		return

	var lido: Variant = JSON.parse_string(corpo.get_string_from_utf8())
	if not (lido is Array):
		_relatar_falha("consulta (resposta ilegível)", resultado, codigo)
		ranking_recebido.emit(ranking_local(dia, limite), "local")
		return

	# Reordena mesmo vindo ordenado do servidor: o critério de desempate fica num lugar
	# só, e o ranking local e o global passam a ter exatamente a mesma leitura.
	ranking_recebido.emit(ordenar(lido as Array).slice(0, limite), "nuvem")


# Ranking local

## Todas as partidas jogadas nesta máquina, na ordem em que aconteceram.
func historico() -> Array:
	var arquivo := ConfigFile.new()
	if arquivo.load(caminho_local) != OK:
		return []
	var lido: Variant = arquivo.get_value("ranking", "partidas", [])
	return lido as Array if lido is Array else []


## As que ainda não subiram para a nuvem.
func pendentes() -> Array:
	var fila := []
	for linha in historico():
		if bool((linha as Dictionary).get("pendente", false)):
			# A coluna de controle é nossa, não do banco: PostgREST recusaria a coluna
			# desconhecida e o lote inteiro voltaria com erro 400.
			var copia := (linha as Dictionary).duplicate()
			copia.erase("pendente")
			fila.append(copia)
	return fila


## Guarda a partida no histórico local. `pendente` marca as que ainda devem subir.
func guardar_local(partida: Dictionary, pendente: bool) -> void:
	var linha := partida.duplicate()
	linha["pendente"] = pendente
	var tudo := historico()
	tudo.append(linha)
	var arquivo := ConfigFile.new()
	arquivo.set_value("ranking", "partidas", tudo)
	arquivo.save(caminho_local)


## O ranking a partir do histórico local, no mesmo formato que a nuvem devolve.
func ranking_local(dia: int, limite: int = LIMITE_PADRAO) -> Array:
	var do_dia := []
	for linha in historico():
		if int((linha as Dictionary).get("dia", 0)) == dia:
			do_dia.append(linha)
	return ordenar(melhor_por_jogador(do_dia)).slice(0, limite)


## Uma linha por nickname, a de maior pontuação. É o que a view `ranking` faz no servidor;
## ter a mesma regra aqui é o que faz o ranking local e o global se parecerem.
func melhor_por_jogador(linhas: Array) -> Array:
	var melhores := {}
	for linha in linhas:
		var dado := linha as Dictionary
		var nome := str(dado.get("nickname", ""))
		var atual: Variant = melhores.get(nome)
		if atual == null or _e_melhor(dado, atual as Dictionary):
			melhores[nome] = dado
	return melhores.values()


## Maior pontuação primeiro; empate desempata por quem gastou menos tempo. Sem o
## desempate, dois jogadores com o mesmo placar ficariam em ordem de inserção — o que faz
## o ranking mudar de ordem entre uma consulta e outra sem ninguém ter jogado.
func ordenar(linhas: Array) -> Array:
	var copia := linhas.duplicate()
	copia.sort_custom(func(a: Variant, b: Variant) -> bool:
		return _e_melhor(a as Dictionary, b as Dictionary)
	)
	return copia


func _e_melhor(a: Dictionary, b: Dictionary) -> bool:
	var pa := int(a.get("pontuacao", 0))
	var pb := int(b.get("pontuacao", 0))
	if pa != pb:
		return pa > pb
	return float(a.get("tempo_gasto", 0.0)) < float(b.get("tempo_gasto", 0.0))


## Apaga a marca de pendente de todo o histórico — chamado depois de um envio bem-sucedido.
func _marcar_enviadas() -> void:
	var tudo := historico()
	for linha in tudo:
		(linha as Dictionary)["pendente"] = false
	var arquivo := ConfigFile.new()
	arquivo.set_value("ranking", "partidas", tudo)
	arquivo.save(caminho_local)


# Encanamento

## Uma linha no console quando a nuvem falha. Toda falha produz a mesma tela ("ranking
## local"), então sem isto não há como distinguir rede fora do ar de defeito no cliente.
func _relatar_falha(o_que: String, resultado: int, codigo: int) -> void:
	print("[ranking] falha no ", o_que, ": resultado=", resultado, " http=", codigo)


func _cabecalhos(extras: Array = []) -> PackedStringArray:
	var lista := PackedStringArray([
		"apikey: " + supabase_anon_key,
		"Authorization: Bearer " + supabase_anon_key,
		"Content-Type: application/json",
	])
	for extra in extras:
		lista.append(str(extra))
	return lista


func _criar_requisicao() -> HTTPRequest:
	var no := HTTPRequest.new()
	no.timeout = ESPERA
	# Obrigatório para o export web. O navegador descompacta o gzip sozinho e entrega o
	# JSON em texto puro, mas o Supabase publica `Content-Encoding: gzip` em
	# `access-control-expose-headers`; com accept_gzip ligado o HTTPRequest acredita no
	# cabeçalho, tenta descompactar de novo e devolve RESULT_BODY_DECOMPRESS_FAILED com
	# corpo vazio, apesar do HTTP 200. No desktop não aparece: lá quem descompacta é o
	# próprio Godot.
	no.accept_gzip = false
	# A tela de resultado pausa a árvore, e é exatamente ali que o envio acontece.
	no.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(no)
	return no
