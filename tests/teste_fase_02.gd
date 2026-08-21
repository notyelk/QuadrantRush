extends Node

## Teste automatizado da Fase 2 — Etapa 8 da Metodologia ("testes automatizados,
## cobrindo a lógica de pontuação e priorização").
##
## Como rodar:
##   godot --headless --path . res://tests/teste_fase_02.tscn
## Sai com código 0 se tudo passar, 1 se algo falhar.
##
## Roda como CENA, não com --script: em modo --script o Godot não instancia os
## autoloads, e sem GameManager nada aqui compila.
##
## O que cada cenário protege:
##   1. agenda      — a fase apresenta as mesmas tarefas para quem corre e para quem
##                    anda. Sem isso dois placares não são comparáveis e o ranking da
##                    Etapa 7 mede pressa em vez de prioridade.
##   2. ideal       — quem trata tudo faz 1140 pontos e o elevador abre na 4ª urgente.
##   3. desatento   — quem corre pelo chão pega só as urgentes que caem no caminho e
##                    descobre que a cota não fecha.
##   4. interrupção — custa tempo, apaga o enunciado e NÃO conta como tarefa da matriz.
##   5. geometria   — toda tarefa que cai pousa sobre chão de verdade.
##   6. a pé        — um robô atravessa o corredor com a física real e as mesmas teclas.
##   7. maturação   — a Q2 adiada volta como Q1, sobe a cota do elevador e não amadurece
##                    duas vezes. É a mecânica central do dia.
##   8. escassez    — nenhuma Q2 pode ser colhida por quem só corre reto. Sem esta trava
##                    ninguém adiaria nada e a maturação nunca apareceria.

const CENA_FASE := preload("res://scenes/level/fase_02.tscn")
const CENA_NOTIFICACAO := preload("res://entities/notificacao.tscn")

## Altura de trânsito: ACIMA do ponto de onde as tarefas nascem (y=16).
##
## Tem que ser acima, e não numa faixa intermediária confortável: o teleporte anda
## 10px por quadro de física (600px/s) e as chegadas nascem à frente do jogador. Numa
## faixa abaixo do ponto de nascimento, o trânsito atravessava tarefas recém-nascidas
## ainda no ar — e o "jogador ideal" batia em distrações que jamais tocaria jogando.
const ALTURA_TRANSITO := -24.0

var falhas := 0


func _ready() -> void:
	# Ver a nota em teste_fase_01.gd: a tela de resultado grava no ranking local, e o
	# teste não pode sujar o histórico real de quem joga nesta máquina.
	# Um cenario que abre a tela de resultado envia a partida: sem nuvem e com perfil
	# descartavel, medir nao chega ao ranking nem ao perfil de quem joga nesta maquina.
	SupabaseClient.caminho_local = "user://teste_ranking.cfg"
	SupabaseClient.supabase_url = ""
	Perfil.caminho = "user://teste_perfil.cfg"

	await _cenario_agenda_deterministica()
	await _cenario_ideal()
	await _cenario_desatento()
	await _cenario_interrupcao()
	await _cenario_geometria_das_chegadas()
	await _cenario_percurso_a_pe()
	await _cenario_maturacao()
	await _cenario_q2_fora_da_linha_de_corrida()
	await _cenario_urgentes_ao_alcance()
	_cenario_progressao()

	print("\n=====  %s  =====" % ("FALHOU (%d)" % falhas if falhas else "TODOS OS TESTES OK"))
	get_tree().quit(1 if falhas else 0)


## A agenda é disparada por POSIÇÃO, não por relógio. A consequência que este cenário
## trava: dois jogadores que percorrem o mesmo corredor enfrentam exatamente as mesmas
## tarefas, mesmo que um leve o dobro do tempo do outro. Se alguém trocar o gatilho por
## um Timer, este teste falha — e era essa a intenção ao escrevê-lo.
func _cenario_agenda_deterministica() -> void:
	print("\n--- cenário 1: a agenda é a mesma para todo mundo ---")
	var fase := await _abrir_fase()

	_conferir("urgentes na fase (agenda + corredor)", fase.composicao[0], 7)
	_conferir("importantes não urgentes", fase.composicao[1], 4)
	_conferir("urgentes não importantes", fase.composicao[2], 2)
	_conferir("distrações", fase.composicao[3], 12)
	_conferir("cota do elevador", fase.meta_de_urgentes(), 4)
	_conferir("dia registrado na sessão", GameManager.dia, 2)

	var notificacoes := 0
	for entrada in fase.AGENDA:
		if entrada.get("tipo", "tarefa") != "tarefa":
			notificacoes += 1
	_conferir("interrupções na agenda", notificacoes, 7)

	var jogador: CharacterBody2D = fase.get_node("Player")
	await _reta(jogador, Vector2(2600, 160))
	var depressa: int = fase.spawner.produzidas
	await _fechar_fase(fase)

	# Segundo percurso, muito mais lento (dez vezes mais quadros de física no caminho).
	var fase2 := await _abrir_fase()
	var jogador2: CharacterBody2D = fase2.get_node("Player")
	for parada in [400, 800, 1200, 1600, 2000, 2600]:
		await _reta(jogador2, Vector2(parada, 160))
		for i in 40:
			await get_tree().physics_frame
	var devagar: int = fase2.spawner.produzidas

	_conferir("mesmo número de chegadas correndo e andando", devagar, depressa)
	_conferir("a agenda inteira foi apresentada", devagar, 20)
	await _fechar_fase(fase2)


## Percurso ideal: 7 Q1 (+700), 4 Q2 (+320), 2 Q3 delegadas (+120) = 1140 pontos, com as
## 12 distrações evitadas.
##
## O teto NÃO mudou quando o dia ficou mais difícil, e isso é a prova de que
## o aperto veio de ritmo e não de pontuação: as quatro distrações novas valem 0 evitadas,
## como todas as outras, e as cinco interrupções novas passam por descontar_tempo(), fora
## do Quadro 1. Se este número subir, alguém inventou fonte de pontos.
##
## E, o que passou a importar mais: quem trata as Q2 na hora NÃO gera crise nenhuma. O
## caminho perfeito continua existindo, e é justamente ele que dá sentido ao caminho ruim.
func _cenario_ideal() -> void:
	print("\n--- cenário 2: jogador que trata tudo ---")
	var fase := await _abrir_fase()
	var jogador: CharacterBody2D = fase.get_node("Player")
	var saida: Node2D = fase.get_node("Saida")

	# UM percurso só, em ordem de corredor: chegadas da agenda, tarefas paradas do arquivo
	# e bifurcações Q3, tudo misturado e ordenado por x.
	#
	# Antes isto eram dois laços — primeiro a agenda, depois "o resto". Com o corredor
	# atual, em que o arquivo (x 1900–2350) fica ANTES das últimas chegadas (x 2400+), o
	# primeiro laço passava por cima das tarefas paradas e as registrava como deixadas
	# para trás. O "jogador ideal" adiava quatro tarefas e ainda gerava uma crise.
	var pontos: Array = []
	for entrada in fase.AGENDA:
		if entrada.get("tipo", "tarefa") == "tarefa":
			pontos.append({
				"x": float(entrada["x"]), "cat": int(entrada["categoria"]), "bif": null,
			})
	for t in _tarefas_de(fase):
		pontos.append({"x": t.global_position.x, "cat": int(t.categoria), "bif": null})
	for b in fase.get_node("Bifurcacoes").get_children():
		pontos.append({
			"x": b.global_position.x,
			"cat": GameManager.Categoria.URGENTE_NAO_IMPORTANTE, "bif": b,
		})
	pontos.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["x"]) < float(b["x"])
	)

	# Cada chegada é tratada só depois de pousar; nunca há tarefa no ar enquanto o
	# jogador atravessa, senão o trânsito colheria uma tarefa em pleno voo por acidente.
	for ponto in pontos:
		var x: float = float(ponto["x"])
		# Distração não merece desvio: um humano passa reto por ela. O robô já
		# fazia a aproximação completa (subir, atravessar, descer) para CADA Q4 e só então
		# decidia ignorá-la, e cada uma dessas idas custava quase um segundo de relógio.
		# Quando o corredor ganhou quatro distrações novas, o cenário passou a reprovar por
		# tempo esgotado — medindo a ineficiência do robô, não a dificuldade da fase.
		var distracao: bool = ponto["bif"] == null \
			and int(ponto["cat"]) == GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE
		# Sobe e atravessa, mas não DESCE até a distração: descer e voltar era meia dúzia
		# de quadros por Q4 gastos para chegar perto de algo que o robô já decidiu ignorar.
		# Continua passando por cima dela, que é o que registra EVITOU, e continua
		# esperando os pousos — sem isso ele ultrapassa tarefas ainda no ar.
		await _reta(jogador, Vector2(jogador.global_position.x, ALTURA_TRANSITO))
		await _reta(jogador, Vector2(x - 60.0, ALTURA_TRANSITO))
		await _esperar_pousos(fase, jogador)
		if distracao:
			continue
		if ponto["bif"] != null:
			# Rota alta da Q3: subir na bandeja é delegar.
			await _levar(jogador, ponto["bif"].get_node("PontoDelegar").global_position)
			continue
		var alvo := _tarefa_em(fase, x)
		if alvo != null:
			await _levar(jogador, alvo.global_position)

	# Até a soleira do elevador, e não a 60px dela: uma tarefa só conta como deixada para
	# trás depois de MARGEM_EVITOU (40px), e a última distração do corredor ficava dentro
	# dessa margem quando o robô parava em 2700. O gatilho da saída começa em 2756, então
	# 2724 chega perto sem encerrar a fase antes das conferências.
	await _levar(jogador, Vector2(2724, 160))

	# O orçamento de relógio do dia, medido em vez de estimado. O robô é MAIS LENTO que um
	# humano (teleporta em degraus e para para esperar cada pouso), então esta sobra é um
	# piso, não uma média. Se ela chegar perto de zero, o dia perfeito deixou de caber e
	# cortar mais relógio está proibido.
	print("        sobra de relógio no percurso perfeito: %.1fs de %.0fs"
		% [GameManager.tempo_restante, fase.tempo_de_expediente()])

	_conferir("urgentes coletadas", GameManager.tarefas_por_categoria[0], 7)
	_conferir("importantes coletadas", GameManager.tarefas_por_categoria[1], 4)
	_conferir("Q3 delegadas", GameManager.acoes_por_tipo[GameManager.Acao.DELEGAR], 2)
	_conferir("Q3 resolvidas", GameManager.acoes_por_tipo[GameManager.Acao.RESOLVER], 0)
	_conferir("distrações evitadas", GameManager.acoes_por_tipo[GameManager.Acao.EVITOU], 12)
	_conferir("nenhuma distração encostada", GameManager.acoes_por_tipo[GameManager.Acao.COLIDIU], 0)
	_conferir("nada ficou para trás", GameManager.acoes_por_tipo[GameManager.Acao.IGNOROU], 0)
	_conferir("pontuação máxima (700+320+120)", GameManager.pontuacao_total, 1140)
	_conferir("elevador liberado", saida.liberada, true)
	_conferir("tratar as Q2 na hora não gera crise", fase.crises, 0)
	_conferir("e o contador do relatório fica zerado",
		GameManager.pendencias_amadurecidas, 0)
	_conferir("a cota do elevador não subiu", fase.meta_de_urgentes(), 4)

	# A soma por categoria tem que fechar com o placar agregado — é o que garante que a
	# "nota por categoria" do checklist institucional não é um número paralelo.
	var soma := 0
	for cat in GameManager.Categoria.values():
		soma += GameManager.pontuacao_por_categoria[cat]
	_conferir("soma por categoria = placar total", soma, GameManager.pontuacao_total)

	await _levar(jogador, saida.global_position + Vector2(4, -16))
	_conferir("terminou em vitória", GameManager.ultima_vitoria, true)
	await _fechar_fase(fase)


## Corre colado no chão do começo ao fim. Pega só as urgentes que por acaso caíram no
## piso, bate em todas as distrações e chega ao elevador sem fechar a cota de 4.
func _cenario_desatento() -> void:
	print("\n--- cenário 3: jogador que só corre ---")
	var fase := await _abrir_fase()
	var jogador: CharacterBody2D = fase.get_node("Player")

	# Cronômetro folgado: seis distrações custam 48s dos 75s do expediente, e a fase
	# terminaria no meio do percurso. O que se mede aqui é a REGRA, não o relógio.
	GameManager.tempo_restante = 400.0

	# Em etapas, esperando cada leva pousar: correr sem parar passaria por baixo de
	# tarefas ainda no ar, e o cenário mediria a velocidade do headless.
	for parada in [400, 700, 1000, 1300, 1600, 1900, 2200, 2500, 2700]:
		await _reta(jogador, Vector2(parada, 160))
		await _esperar_pousos(fase, jogador)

	_conferir("elevador continua trancado", fase.get_node("Saida").liberada, false)
	# A contagem por categoria soma TODA tarefa registrada, inclusive as ignoradas —
	# é a pontuação que diz quantas foram de fato coletadas (100 por urgente).
	_conferir("coletou menos urgentes que a cota",
		GameManager.pontuacao_por_categoria[0] < fase.meta_de_urgentes() * 100, true)
	_conferir("mas as ignoradas foram registradas",
		GameManager.tarefas_por_categoria[0] >= 7, true)
	_conferir("bateu nas distrações do chão",
		GameManager.acoes_por_tipo[GameManager.Acao.COLIDIU] > 0, true)
	_conferir("distrações custaram pontos", GameManager.pontuacao_por_categoria[3] < 0, true)
	_conferir("Q3 resolvidas na rota baixa",
		GameManager.acoes_por_tipo[GameManager.Acao.RESOLVER], 2)
	# Tarefa deixada para trás precisa aparecer no relatório: é o dado mais interessante
	# para a discussão do TCC (o que o jogador negligenciou), e sem ele a nota por
	# categoria contaria só acerto.
	_conferir("o que passou foi registrado",
		GameManager.acoes_por_tipo[GameManager.Acao.IGNOROU] > 0, true)

	# E o preço de ter adiado chega depois: as Q2 que ele deixou lá em cima voltam como
	# urgentes obrigatórias, e o dia dele fica MAIOR, não menor.
	await _esperar_ate(func() -> bool: return fase.crises > 0, 900)
	_conferir("adiar as importantes gerou crise", fase.crises > 0, true)
	_conferir("e a cota do elevador subiu junto", fase.meta_de_urgentes() > 4, true)

	await _fechar_fase(fase)


## A interrupção é a mecânica nova da fase. Ela precisa cobrar tempo, apagar o enunciado
## e — o mais importante — NÃO entrar na contagem por categoria, que é o requisito
## institucional de notas por tarefa.
func _cenario_interrupcao() -> void:
	print("\n--- cenário 4: a interrupção ---")
	var fase := await _abrir_fase()
	var jogador: CharacterBody2D = fase.get_node("Player")

	# Perto o bastante para ler (o raio do rótulo é 96px) e longe o bastante para não
	# encostar: a primeira chegada é uma Q1, e coletá-la apagaria o objeto que este
	# cenário precisa observar.
	await _reta(jogador, Vector2(290, 160))
	await _esperar_pousos(fase, jogador)
	var tarefa := _tarefa_em(fase, 336.0)
	_conferir("existe tarefa para ler", tarefa != null, true)

	for i in 20:
		await get_tree().physics_frame
	var rotulo: Label = tarefa.get_node("Rotulo")
	_conferir("de perto, o enunciado aparece", rotulo.modulate.a > 0.5, true)

	var tarefas_antes := _total_registrado()
	var tempo_antes: float = GameManager.tempo_restante
	var pontos_antes: int = GameManager.pontuacao_total

	var nota: Area2D = CENA_NOTIFICACAO.instantiate()
	nota.position = jogador.global_position + Vector2(30, -10)
	fase.get_node("Inimigos").add_child(nota)
	await _esperar_ate(func() -> bool: return GameManager.interrupcoes > 0, 240)

	_conferir("a interrupção foi contada", GameManager.interrupcoes, 1)
	_conferir("custou tempo", GameManager.tempo_restante < tempo_antes, true)
	_conferir("não mexeu no placar", GameManager.pontuacao_total, pontos_antes)
	_conferir("não virou tarefa da matriz", _total_registrado(), tarefas_antes)
	_conferir("a atenção ficou bloqueada", GameManager.atencao_livre(), false)

	for i in 20:
		await get_tree().physics_frame
	_conferir("e o enunciado sumiu", rotulo.modulate.a < 0.1, true)

	# 2,2s de cegueira; 180 quadros de física são 3s, folgado.
	for i in 180:
		await get_tree().physics_frame
	_conferir("a atenção volta sozinha", GameManager.atencao_livre(), true)

	await _fechar_fase(fase)


## Toda tarefa que cai precisa pousar sobre chão de verdade. Sem esta conferência, mover
## uma plataforma no gerador deixaria tarefas boiando sobre um vão — o jogador as veria,
## não conseguiria alcançá-las, e a cota de urgentes poderia ficar impossível.
func _cenario_geometria_das_chegadas() -> void:
	print("\n--- cenário 5: toda chegada pousa em chão de verdade ---")
	var fase := await _abrir_fase()
	var espaco := fase.get_world_2d().direct_space_state
	var sem_chao := 0
	var alto_demais := 0

	for entrada in fase.AGENDA:
		if entrada.get("tipo", "tarefa") != "tarefa":
			continue
		var pouso := Vector2(float(entrada["x"]), float(entrada["pousa"]))
		# 24px abaixo do pouso: a tarefa fica ~16px acima da superfície, como as fixas.
		var consulta := PhysicsRayQueryParameters2D.create(pouso, pouso + Vector2(0, 26))
		if espaco.intersect_ray(consulta).is_empty():
			sem_chao += 1
			print("        sem chão sob a chegada em x=%d" % int(entrada["x"]))
		# E não pode pousar DENTRO do colisor: a tarefa ficaria enterrada na plataforma.
		var dentro := PhysicsRayQueryParameters2D.create(pouso, pouso + Vector2(0, 4))
		if not espaco.intersect_ray(dentro).is_empty():
			alto_demais += 1
			print("        enterrada na chegada em x=%d (pousa %d)"
				% [int(entrada["x"]), int(entrada["pousa"])])

	_conferir("toda chegada tem chão embaixo", sem_chao, 0)
	_conferir("nenhuma chegada pousa dentro do colisor", alto_demais, 0)

	# As tarefas paradas do setor 4 seguem a mesma regra.
	var fixas_sem_chao := 0
	for t in _tarefas_de(fase):
		if t.queda > 0.0:
			continue  # chegada ainda no ar; a posição de pouso dela já foi conferida acima
		var consulta := PhysicsRayQueryParameters2D.create(
			t.global_position, t.global_position + Vector2(0, 26))
		if espaco.intersect_ray(consulta).is_empty():
			fixas_sem_chao += 1
	_conferir("tarefas paradas também têm chão", fixas_sem_chao, 0)

	# Os vãos existem mesmo. Um gerador que "esquecesse" de abrir o buraco deixaria o
	# corredor plano e a fase continuaria perfeitamente jogável, sem nada denunciar.
	var vao := Vector2(1432, 150.0)
	var raio := PhysicsRayQueryParameters2D.create(vao, vao + Vector2(0, 90))
	_conferir("o corredor tem um vão de verdade", espaco.intersect_ray(raio).is_empty(), true)

	# A escada do arquivo nasce sem colisão e só o colega despachado a materializa. Aciona
	# o alvo direto, sem ele: o que este cenário prova é o efeito, e o caminho do colega
	# até lá tem cenário próprio na Fase 1.
	var escada: StaticBody2D = fase.get_node("Colisores/Escada")
	var col_escada: CollisionShape2D = escada.get_node("CollisionShape2D")
	_conferir("a escada do arquivo nasce sem colisão", col_escada.disabled, true)

	fase.get_node("Delegacoes/EscadaDoArquivo").acionar()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_conferir("depois de delegar, a escada fica sólida", col_escada.disabled, false)

	await _fechar_fase(fase)


## O único cenário em que ninguém teleporta nada: um robô segura "direita" e pula quando
## bate numa parede ou quando o chão some à frente. Teleporte atravessa qualquer
## geometria; só isto detecta um vão largo demais ou uma plataforma intransponível.
func _cenario_percurso_a_pe() -> void:
	print("\n--- cenário 6: dá para atravessar o corredor a pé ---")
	var fase := await _abrir_fase()
	var jogador: CharacterBody2D = fase.get_node("Player")
	var saida: Node2D = fase.get_node("Saida")

	# Sem cronômetro: o objetivo aqui é geometria, e um teste que falha porque o headless
	# rodou devagar não diz nada sobre o level design.
	GameManager.em_jogo = false

	Input.action_press("right")
	var chegou := false
	var x_maximo: float = jogador.global_position.x
	var travado := 0

	for i in 4200:
		if _precisa_pular(jogador):
			Input.action_press("jump")
		else:
			Input.action_release("jump")

		await get_tree().physics_frame

		var x: float = jogador.global_position.x
		if x > x_maximo + 0.5:
			x_maximo = x
			travado = 0
		else:
			travado += 1

		if x >= saida.global_position.x - 12.0:
			chegou = true
			break
		if travado > 180:
			break

	Input.action_release("right")
	Input.action_release("jump")

	_conferir("o robô atravessou o corredor a pé", chegou, true)
	if not chegou:
		print("        travou em x=%.0f (a saída fica em x=%.0f)"
			% [x_maximo, saida.global_position.x])

	await _fechar_fase(fase)


## A mecânica central do dia. Uma Q2 deixada para trás volta como Q1, com outro enunciado,
## à frente do jogador — e o dia dele fica maior, porque a cota do elevador sobe junto.
##
## O que este cenário existe para impedir, em ordem de gravidade:
##   · alguém "simplificar" a maturação para dar pontos em vez de obrigação (seria fonte
##     de pontuação fora do Quadro 1, que está protocolado no TCC);
##   · a crise nascer atrás do jogador ou em cima dele;
##   · a crise amadurecer de novo, virando espiral sem saída;
##   · o elevador ficar aberto quando aparece uma urgente nova.
func _cenario_maturacao() -> void:
	print("
--- cenário 7: a pendência que amadurece ---")
	var fase := await _abrir_fase()
	var jogador: CharacterBody2D = fase.get_node("Player")
	var saida: Node2D = fase.get_node("Saida")

	# Relógio folgado: o que se mede aqui é a regra, não quantos quadros o headless rodou.
	GameManager.tempo_restante = 400.0

	await _reta(jogador, Vector2(300, 160))
	await _esperar_pousos(fase, jogador)

	var q2 := _tarefa_em(fase, 544.0)
	_conferir("a primeira Q2 chegou", q2 != null, true)
	if q2 == null:
		await _fechar_fase(fase)
		return
	_conferir("ela é importante e não urgente",
		q2.categoria, GameManager.Categoria.IMPORTANTE_NAO_URGENTE)
	_conferir("e traz escrito no que ela vira", q2.texto_maduro.is_empty(), false)
	var texto_da_crise: String = q2.texto_maduro

	_conferir("cota do elevador antes", fase.meta_de_urgentes(), 4)
	var urgentes_antes: int = fase.composicao[GameManager.Categoria.URGENTE_IMPORTANTE]

	# Passa reto POR BAIXO dela: ela está a 96px de altura, fora da linha de corrida.
	await _reta(jogador, Vector2(700, 160))
	_conferir("passar reto a registra como deixada para trás",
		GameManager.acoes_por_tipo[GameManager.Acao.IGNOROU] >= 1, true)
	_conferir("e deixá-la passar não deu ponto nenhum",
		GameManager.pontuacao_por_categoria[GameManager.Categoria.IMPORTANTE_NAO_URGENTE], 0)
	_conferir("a crise ainda não nasceu (ela demora)", fase.crises, 0)

	# O elevador é aberto à força aqui só para provar que uma crise o tranca de volta.
	# Sem isso, adiar depois de cumprida a cota sairia de graça.
	saida.liberar()
	_conferir("elevador aberto à força para o teste", saida.liberada, true)

	await _esperar_ate(func() -> bool: return fase.crises > 0, 900)

	_conferir("a pendência amadureceu", fase.crises, 1)
	_conferir("e foi contada para o relatório", GameManager.pendencias_amadurecidas, 1)
	_conferir("a cota do elevador subiu", fase.meta_de_urgentes(), 5)
	_conferir("o dia passou a ter uma urgente a mais",
		fase.composicao[GameManager.Categoria.URGENTE_IMPORTANTE], urgentes_antes + 1)
	_conferir("e o elevador trancou de novo", saida.liberada, false)

	var crise := _crise_com_texto(fase, texto_da_crise)
	_conferir("a crise existe no corredor", crise != null, true)
	if crise == null:
		await _fechar_fase(fase)
		return
	_conferir("ela voltou como urgente e importante",
		crise.categoria, GameManager.Categoria.URGENTE_IMPORTANTE)
	_conferir("nasceu à frente do jogador",
		crise.position.x >= jogador.global_position.x + fase.FOLGA_DA_CRISE, true)
	_conferir("num ponto de crise previsto",
		fase.PONTOS_DE_CRISE.has(int(crise.position.x)), true)
	_conferir("e ela não amadurece outra vez", crise.texto_maduro, "")

	# Deixar a crise passar também: ela não pode gerar uma terceira tarefa.
	await _reta(jogador, Vector2(crise.position.x + 200.0, 160))
	for i in 60:
		await get_tree().physics_frame
	_conferir("ignorar a crise não gera outra", fase.crises, 1)

	await _fechar_fase(fase)


## A trava da mecânica: se desse para colher uma Q2 sem sair da linha de corrida, ninguém
## adiaria nenhuma e a maturação nunca aconteceria. É uma asserção de GEOMETRIA de
## propósito — um teste de comportamento passaria mesmo com as Q2 no chão, porque o
## percurso ideal as coleta de qualquer jeito.
func _cenario_q2_fora_da_linha_de_corrida() -> void:
	print("
--- cenário 8: nenhuma Q2 cai na linha de quem só corre ---")
	var fase := await _abrir_fase()

	# Corpo de quem corre no piso: a origem fica 16px acima do chão e a cápsula começa
	# 2px acima da origem. A tarefa tem 8px de raio de contato.
	var chao := 176.0
	var topo_do_corpo_correndo := chao - 16.0 - 2.0
	var dentro := 0
	var sem_crise_escrita := 0

	for entrada in fase.AGENDA:
		if entrada.get("tipo", "tarefa") != "tarefa":
			continue
		if int(entrada["categoria"]) != GameManager.Categoria.IMPORTANTE_NAO_URGENTE:
			continue
		if float(entrada["pousa"]) + 8.0 >= topo_do_corpo_correndo:
			dentro += 1
			print("        Q2 alcançável correndo em x=%d" % int(entrada["x"]))
		if str(entrada.get("texto_maduro", "")).is_empty():
			sem_crise_escrita += 1

	for t in _tarefas_de(fase):
		if t.categoria != GameManager.Categoria.IMPORTANTE_NAO_URGENTE:
			continue
		if t.queda > 0.0:
			continue
		if t.position.y + 8.0 >= topo_do_corpo_correndo:
			dentro += 1
		if str(t.texto_maduro).is_empty():
			sem_crise_escrita += 1

	_conferir("nenhuma Q2 na linha de corrida", dentro, 0)
	_conferir("toda Q2 tem enunciado de crise escrito", sem_crise_escrita, 0)

	# E todo ponto de crise fica acima da linha de corrida, pelo mesmo motivo: buscar a
	# crise tem de custar um desvio, senão o preço de adiar seria zero.
	var no_chao := 0
	for x in fase.PONTOS_DE_CRISE:
		if fase.CRISE_POUSA + 8.0 >= topo_do_corpo_correndo:
			no_chao += 1
	_conferir("os pontos de crise também estão fora dela", no_chao, 0)
	_conferir("e existem pontos de crise espalhados",
		fase.PONTOS_DE_CRISE.size() >= 6, true)

	await _fechar_fase(fase)


## A tarefa cujo enunciado é o texto da crise. Buscar pelo TEXTO, e não pela posição:
## reescrever o enunciado é metade da mecânica, e assim o cenário falha se isso parar de
## acontecer.
## Chegar ao elevador trancado encerra o dia, mas aqui as urgentes CAEM: o que ainda vai
## chegar e o que está a caminho de amadurecer contam como ao alcance.
##
## Sem essa soma, esbarrar na porta cedo encerraria a partida por urgentes que ainda nem
## tinham existido — e nenhum teste de comportamento veria isso, porque o percurso ideal
## chega ao elevador com a cota já cumprida.
func _cenario_urgentes_ao_alcance() -> void:
	print("\n--- cenário 10: o elevador só é definitivo quando não há mais volta ---")
	var fase := await _abrir_fase()
	var jogador: CharacterBody2D = fase.get_node("Player")
	var saida: Node2D = fase.get_node("Saida")

	GameManager.tempo_restante = 400.0

	# Nada chegou ainda: tudo o que a fase promete está na agenda, não na cena.
	_conferir("no primeiro quadro nada foi coletado", fase._q1_coletadas, 0)
	_conferir("mas o dia inteiro conta como ao alcance",
		fase.urgentes_ao_alcance() >= fase.meta_de_urgentes(), true)
	saida.barrada.emit()
	_conferir("a porta trancada não encerra o dia aqui", GameManager.em_jogo, true)

	# Uma pendência a caminho de virar crise também é urgente ao alcance: ela ainda vai
	# nascer, e a cota já subiu por causa dela.
	var so_da_cena: int = fase.urgentes_ao_alcance()
	fase._maturando.append({"resta": 99.0, "texto": "crise de teste"})
	_conferir("pendência a caminho conta como urgente por vir",
		fase.urgentes_ao_alcance(), so_da_cena + 1)
	fase._maturando.clear()

	# Corre até o fim sem coletar nada: agora não sobra nada a que voltar.
	for parada in [400, 900, 1400, 1900, 2400, 2700]:
		await _reta(jogador, Vector2(parada, 160))
		await _esperar_pousos(fase, jogador)
	fase._maturando.clear()

	_conferir("nenhuma urgente sobrou ao alcance", fase.urgentes_ao_alcance(), 0)
	await _levar(jogador, saida.global_position + Vector2(4, -16))
	_conferir("chegar ao elevador assim encerra a fase", GameManager.em_jogo, false)
	_conferir("e encerra como derrota", GameManager.ultima_vitoria, false)

	await _fechar_fase(fase)


func _crise_com_texto(fase: Node2D, texto: String) -> Node2D:
	for t in _tarefas_de(fase):
		if t.texto == texto:
			return t
	return null


## Progressão entre os dias (Etapa 6). O Dia 2 não pode nascer aberto: quem chega ao jogo
## pela primeira vez tem que passar pela fase que ensina a mecânica.
func _cenario_progressao() -> void:
	print("\n--- cenário 9: o segundo dia se abre com a vitória ---")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Perfil.caminho))
	Perfil.carregar()

	_conferir("perfil novo começa no Dia 1", Perfil.dia_liberado, 1)
	_conferir("Dia 1 liberado", Perfil.dia_esta_liberado(1), true)
	_conferir("Dia 2 trancado", Perfil.dia_esta_liberado(2), false)

	_conferir("liberar o Dia 2 é novidade", Perfil.liberar_dia(2), true)
	_conferir("Dia 2 agora aberto", Perfil.dia_esta_liberado(2), true)
	_conferir("liberar de novo não é novidade", Perfil.liberar_dia(2), false)
	_conferir("não dá para trancar de volta", Perfil.liberar_dia(1), false)

	Perfil.dia_liberado = 1
	_conferir("o dia liberado sobrevive ao disco", _recarregar_dia(), 2)

	# Contra Perfil.ULTIMO_DIA, e não contra um número escrito aqui: as duas tabelas
	# precisam andar juntas (um dia sem cena trava a progressão, uma cena sem dia fica
	# inalcançável), e um literal aqui só quebraria o teste a cada fase nova.
	_conferir("cada dia tem cena", GameManager.CENA_DO_DIA.size(), Perfil.ULTIMO_DIA)
	_conferir("cada dia tem nome", GameManager.NOME_DO_DIA.size(), Perfil.ULTIMO_DIA)
	for numero in GameManager.CENA_DO_DIA:
		_conferir("cena do dia %d existe" % numero,
			ResourceLoader.exists(GameManager.CENA_DO_DIA[numero]), true)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(Perfil.caminho))


func _recarregar_dia() -> int:
	Perfil.carregar()
	return Perfil.dia_liberado


# ferramentas


## `com_notificacoes` = false tira as interrupções da agenda. Os cenários de pontuação
## teleportam o jogador, e uma notificação que encosta no meio do caminho tiraria
## segundos em momentos que dependem de quantos quadros o headless rodou — o que
## testaria a máquina, não a regra. A interrupção tem cenário próprio.
## A espera é em quadros de FÍSICA, e não de processo.
##
## O spawner decide o que nascer dentro de _physics_process. Esperando process_frame,
## o número de passos de física já ocorridos até a varredura variava de execução para
## execução — às vezes a primeira chegada já tinha nascido e era varrida, às vezes
## nascia logo DEPOIS da varredura e sobrevivia à troca de agenda, virando uma oitava
## urgente na fase. O cenário 3 falhava mais ou menos uma vez a cada três rodadas por
## causa disso, sempre com "esperado 7, obtido 8".
func _abrir_fase(com_notificacoes: bool = false) -> Node2D:
	var fase: Node2D = CENA_FASE.instantiate()
	add_child(fase)
	await get_tree().physics_frame
	await get_tree().physics_frame

	if not com_notificacoes:
		# A primeira entrada da agenda tem gatilho quase em cima do ponto de partida, e
		# já nasceu durante os dois quadros acima. Trocar a agenda sem varrer o que ela
		# produziu deixaria essa tarefa duplicada na fase.
		for t in _tarefas_de(fase):
			if t.queda > 0.0:
				t.queue_free()
		await get_tree().physics_frame

		var limpa: Array = []
		for entrada in fase.AGENDA:
			if entrada.get("tipo", "tarefa") == "tarefa":
				var copia: Dictionary = entrada.duplicate()
				copia["gatilho"] = maxf(float(entrada["x"]) - fase.AVANCO_DA_CHEGADA, 0.0)
				copia["y"] = fase.ALTURA_DE_ENTRADA
				limpa.append(copia)
		fase.spawner.definir_agenda(limpa)
		await get_tree().physics_frame

	return fase


func _fechar_fase(fase: Node2D) -> void:
	# A fase pausa a árvore ao terminar; sem despausar o próximo cenário congela.
	get_tree().paused = false
	fase.queue_free()
	await get_tree().process_frame


## Só as TAREFAS que estão penduradas no nó Tarefas.
##
## O filtro não é zelo: Feedback.pontos() pendura os textos flutuantes ("+100", "-8s")
## no mesmo nó, então get_children() devolve Labels misturadas com tarefas. Sem isto o
## teste chamava esta_resolvida() numa Label — e o erro de script não interrompe a
## corrotina, ele só devolve null e o cenário segue medindo coisa errada.
func _tarefas_de(fase: Node2D) -> Array:
	var lista: Array = []
	for t in fase.get_node("Tarefas").get_children():
		if "categoria" in t:
			lista.append(t)
	return lista


## A tarefa (ainda no corredor) mais próxima de um x. Devolve null se ela já foi
## resolvida ou nunca nasceu.
func _tarefa_em(fase: Node2D, x: float) -> Node2D:
	var melhor: Node2D = null
	var distancia := 40.0
	for t in _tarefas_de(fase):
		if t.esta_resolvida():
			continue
		var d: float = absf(t.global_position.x - x)
		if d < distancia:
			distancia = d
			melhor = t
	return melhor


## Espera todas as tarefas em queda pousarem. Enquanto houver tarefa no ar, o trânsito
## do jogador pode cruzar com ela e colher (ou bater) por acidente.
##
## O jogador é SEGURADO no lugar durante a espera, como _reta() faz. Sem isso ele
## despenca da altura de trânsito enquanto as tarefas caem, atravessa o corredor na
## vertical e encosta em distrações que um humano jamais tocaria.
func _esperar_pousos(fase: Node2D, jogador: CharacterBody2D = null) -> void:
	var parado := jogador.global_position if jogador != null else Vector2.ZERO
	for i in 300:
		var caindo := false
		for t in _tarefas_de(fase):
			if t.queda > 0.0 and t.position.y < t.pousa - 0.5:
				caindo = true
				break
		if not caindo:
			return
		if jogador != null:
			jogador.global_position = parado
			jogador.velocity = Vector2.ZERO
		await get_tree().physics_frame


func _esperar_ate(condicao: Callable, limite: int) -> void:
	for i in limite:
		if condicao.call():
			return
		await get_tree().physics_frame


func _total_registrado() -> int:
	var total := 0
	for cat in GameManager.Categoria.values():
		total += GameManager.tarefas_por_categoria[cat]
	return total


## Pula quando encosta numa parede ou quando não há chão logo à frente.
func _precisa_pular(jogador: CharacterBody2D) -> bool:
	if not jogador.is_on_floor():
		return false
	if jogador.is_on_wall():
		return true

	var espaco := jogador.get_world_2d().direct_space_state
	var pe := jogador.global_position + Vector2(20, 16)
	var consulta := PhysicsRayQueryParameters2D.create(pe, pe + Vector2(0, 24))
	consulta.exclude = [jogador.get_rid()]
	return espaco.intersect_ray(consulta).is_empty()


## Sobe até a altura de trânsito, atravessa e só então desce no alvo.
func _levar(jogador: CharacterBody2D, destino: Vector2) -> void:
	await _reta(jogador, Vector2(jogador.global_position.x, ALTURA_TRANSITO))
	await _reta(jogador, Vector2(destino.x, ALTURA_TRANSITO))
	await _reta(jogador, destino)


## Teleporta em passos curtos: Area2D só detecta em frame de física, então um salto
## direto de 2000px atravessaria a fase inteira sem disparar nada.
func _reta(jogador: CharacterBody2D, destino: Vector2) -> void:
	var origem := jogador.global_position
	var passos := int(maxf(origem.distance_to(destino) / 10.0, 1.0))
	for i in range(passos + 1):
		jogador.global_position = origem.lerp(destino, float(i) / float(passos))
		jogador.velocity = Vector2.ZERO
		await get_tree().physics_frame
	await get_tree().physics_frame


func _conferir(rotulo: String, obtido: Variant, esperado: Variant) -> void:
	if obtido == esperado:
		print("  ok     %s = %s" % [rotulo, str(obtido)])
	else:
		falhas += 1
		print("  FALHA  %s: esperado %s, obtido %s" % [rotulo, str(esperado), str(obtido)])
