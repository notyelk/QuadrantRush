extends Node

## Teste automatizado da Fase 3 ("O Chefe") — Etapa 8 da Metodologia.
##
## Como rodar:
##   godot --headless --path . res://tests/teste_fase_03.tscn
## Sai com código 0 se tudo passar, 1 se algo falhar.
##
## Roda como CENA, não com --script: em modo --script o Godot não instancia os autoloads,
## e sem GameManager nada aqui compila.
##
## O que cada cenário protege:
##   1. sorteio     — as invariantes de geometria valem em TODAS as 200 sementes.
##   2. quadro 1    — os sete efeitos da tabela protocolada do TCC, digitados do texto.
##   3. mapeamento  — as 16 combinações categoria x canto, e quantas delas são acerto.
##   4. pilha       — a aritmética do soterramento, inclusive os dois limiares.
##   5. recusa      — o validador REPROVA geometria quebrada de propósito. É a metade que
##                    importa: sem ela, um validador que aceitasse tudo passaria no 1.
##   6. arena       — a cena real bate com o layout sorteado, e o briefing não mente.
##   7. chefe       — as quatro fases, a curva acumulativa e o Chefe fora de alcance.
##   8. a pé        — um robô pega e entrega um papel com a física real e as mesmas
##                    teclas de um humano. É o único que prova que a fase é JOGÁVEL.
##   9. pressão     — as quatro mecânicas de dificuldade: o papel que vence
##                    na mão, a reorganização da sala, a enxurrada de e-mail e o duplo
##                    bloqueio. Mais a aritmética que motivou tudo — a fila tem de durar o
##                    expediente inteiro, e era ela que secava aos 71 s de 100.

const Sorteio := preload("res://scripts/sorteio_arena.gd")
const Pilha := preload("res://scripts/pilha_pendencias.gd")

var falhas := 0


func _ready() -> void:
	_cenario_sorteio()
	_cenario_quadro_1()
	_cenario_mapeamento()
	_cenario_pilha()
	_cenario_validador_recusa()
	await _cenario_arena()
	await _cenario_chefe()
	await _cenario_a_pe()
	await _cenario_pressao()

	print("\n=====  %s  =====" % ("FALHOU (%d)" % falhas if falhas else "TODOS OS TESTES OK"))
	get_tree().quit(1 if falhas else 0)


## A varredura é o que torna o sorteio defensável. Um layout estático se confere olhando;
## um layout sorteado só se confere provando que NENHUM sorteio possível viola as regras.
## Este cenário é mais forte que o teste estático das Fases 1 e 2, não mais fraco.
func _cenario_sorteio() -> void:
	print("\n--- cenário 1: 200 sementes, todas válidas ---")

	var reprovados := 0
	var primeiro_erro := ""
	var recorreram_a_reserva := 0
	var arranjos := {}

	for semente in range(1, 201):
		var layout := Sorteio.sortear(semente)
		var erros := Sorteio.validar(layout)
		if not erros.is_empty():
			reprovados += 1
			if primeiro_erro.is_empty():
				primeiro_erro = "semente %d: %s" % [semente, ", ".join(erros)]
		if int(layout["tentativas"]) >= Sorteio.MAX_TENTATIVAS:
			recorreram_a_reserva += 1
		# Assinatura do arranjo: qual quadrante caiu em qual lado/nível.
		var assinatura := ""
		for categoria in GameManager.Categoria.values():
			var p: Vector2 = layout["cantos"][categoria]
			assinatura += "%d%s" % [int(layout["nivel"][categoria]), "E" if p.x < 320.0 else "D"]
		arranjos[assinatura] = true

	_conferir("nenhuma semente reprovada", reprovados, 0)
	if not primeiro_erro.is_empty():
		print("        primeiro erro: %s" % primeiro_erro)
	_conferir("nenhuma caiu no layout de reserva", recorreram_a_reserva, 0)

	# Se todas as 200 sementes produzissem o mesmo arranjo, o sorteio seria decorativo e o
	# objetivo do sorteio ("para não dar para o jogador decorar") não estaria atendido.
	_conferir("o sorteio produz mais de um arranjo", arranjos.size() >= 4, true)

	# Mesma semente, mesma arena: sem isso a suíte inteira fica intermitente, e foi por
	# não ter isso que o teste da Fase 2 já falhou 1 vez em 3.
	var a := Sorteio.sortear(42)
	var b := Sorteio.sortear(42)
	_conferir("mesma semente, mesmos cantos", a["cantos"] == b["cantos"], true)
	_conferir("mesma semente, mesma fila", a["fila"] == b["fila"], true)

	# O orçamento de dificuldade é o que mantém o ranking da Etapa 7 comparável.
	#
	# A fila é o orçamento MENOS a reserva do e-mail em cópia, que chega em bloco e em
	# horário marcado (ver chefe.gd). As duas parcelas juntas têm de fechar o orçamento, e
	# é a invariante 8 do validador que garante isso — aqui se confere só o tamanho da fila,
	# para que somar à reserva e reencontrar o total continue sendo prova de duas partes.
	var total: int = (a["fila"] as Array[int]).size()
	_conferir("a fila tem sempre o mesmo tamanho", total, Sorteio.total_na_fila())
	_conferir("fila mais reserva fecham o orçamento do dia",
		total + Sorteio.RESERVA_EMAIL, Sorteio.total_de_demandas())

	# A regra pedagógica herdada das Fases 1 e 2: o importante-e-não-urgente fica onde
	# exige esforço deliberado. Se alguém "simplificar" o sorteio, isto quebra.
	var q2_no_alto := 0
	for semente in range(1, 51):
		var layout := Sorteio.sortear(semente)
		if int(layout["nivel"][GameManager.Categoria.IMPORTANTE_NAO_URGENTE]) == 1:
			q2_no_alto += 1
	_conferir("Q2 sempre no mezanino", q2_no_alto, 50)

	# Duas regras de pouso, conferidas nas 200 sementes. As duas são de GEOMETRIA e não de
	# comportamento: um papel dentro da pedra ou dois degraus fundidos num só não quebram
	# nada que rode, só tornam a partida impossível de terminar.
	var dentro_do_pedestal := 0
	var degraus_colados := 0
	for semente in range(1, 201):
		var layout := Sorteio.sortear(semente)
		for ponto in layout["pousos"] as Array[Vector2]:
			if ponto.y != Sorteio.Y_CHAO:
				continue
			if (
				Sorteio.PEDESTAL_ESQ.has_point(Vector2(ponto.x, Sorteio.Y_PEDESTAL + 1.0))
				or Sorteio.PEDESTAL_DIR.has_point(Vector2(ponto.x, Sorteio.Y_PEDESTAL + 1.0))
			):
				dentro_do_pedestal += 1
		var degraus: Array[Rect2] = layout["degraus"]
		for i in degraus.size():
			for j in range(i + 1, degraus.size()):
				if degraus[i].intersects(degraus[j]):
					degraus_colados += 1

	_conferir("nenhum papel pousa dentro de um pedestal", dentro_do_pedestal, 0)
	_conferir("nenhum par de degraus se sobrepõe", degraus_colados, 0)
	_conferir("e ainda sobram quatro degraus por arena",
		(Sorteio.sortear(7)["degraus"] as Array[Rect2]).size(), 4)


## A trava do Quadro 1. Se alguém inventar pontuação nova nesta fase, este cenário quebra.
## Os números vêm do texto protocolado do TCC, não do código — foram digitados aqui à mão
## a partir da tabela da seção 3.1, de propósito, para que copiar um erro do GameManager
## para o teste seja impossível.
func _cenario_quadro_1() -> void:
	print("\n--- cenário 2: o Quadro 1 continua intacto ---")

	var C := GameManager.Categoria
	var A := GameManager.Acao

	var esperado := [
		["Q1 entregue em FAZER AGORA", C.URGENTE_IMPORTANTE, A.COLETAR, 100, 0.0],
		["Q2 entregue em AGENDAR", C.IMPORTANTE_NAO_URGENTE, A.COLETAR, 80, 0.0],
		["Q3 entregue ao colega", C.URGENTE_NAO_IMPORTANTE, A.DELEGAR, 60, 0.0],
		["Q3 feita na hora", C.URGENTE_NAO_IMPORTANTE, A.RESOLVER, 40, -5.0],
		["Q4 tocada", C.NAO_URGENTE_NAO_IMPORTANTE, A.COLIDIU, -20, -8.0],
		["Q4 deixada em paz", C.NAO_URGENTE_NAO_IMPORTANTE, A.EVITOU, 0, 0.0],
		["canto errado", C.URGENTE_IMPORTANTE, A.IGNOROU, 0, 0.0],
	]

	for linha in esperado:
		GameManager.iniciar_fase(100.0, 3)
		var efeito := GameManager.registrar_acao(linha[1], linha[2])
		_conferir("%s: pontos" % linha[0], efeito["pontos"], linha[3])
		_conferir("%s: tempo" % linha[0], efeito["delta_tempo"], linha[4])

	# O Quadro 1 continua declarando o desconto de tempo, mas no dia em que esgotar o
	# relógio é VENCER ele não pode ser aplicado: encurtar o expediente transformaria a
	# punição num atalho, e errar de propósito viraria a estratégia mais rápida.
	GameManager.iniciar_fase(100.0, 3)
	GameManager.vitoria_ao_esgotar_tempo = true
	var antes := GameManager.tempo_restante
	GameManager.registrar_acao(C.NAO_URGENTE_NAO_IMPORTANTE, A.COLIDIU)
	GameManager.descontar_tempo(6.0)
	_conferir("errar não adianta o fim do expediente de sobrevivência",
		is_equal_approx(GameManager.tempo_restante, antes), true)

	# E continua descontando no dia em que o relógio é a ameaça.
	GameManager.iniciar_fase(100.0, 1)
	GameManager.registrar_acao(C.NAO_URGENTE_NAO_IMPORTANTE, A.COLIDIU)
	_conferir("mas desconta normalmente quando o relógio é a ameaça",
		is_equal_approx(GameManager.tempo_restante, 92.0), true)

	GameManager.finalizar_fase(false)


## Cada uma das 16 combinações categoria x canto tem UMA resposta certa, e todas as 16
## caem em linhas do Quadro 1. Este cenário é a trava: quem inventar um efeito novo para
## uma combinação quebra aqui, e vai ter de justificar mexendo no texto do TCC.
func _cenario_mapeamento() -> void:
	print("\n--- cenário 3: para onde levei = o que eu decidi ---")

	var Zona := load("res://scripts/zona_matriz.gd")
	var C := GameManager.Categoria
	var A := GameManager.Acao

	# [categoria do papel, canto de entrega, ação esperada]
	var casos := [
		[C.URGENTE_IMPORTANTE, C.URGENTE_IMPORTANTE, A.COLETAR],
		[C.URGENTE_IMPORTANTE, C.IMPORTANTE_NAO_URGENTE, A.IGNOROU],
		[C.URGENTE_IMPORTANTE, C.URGENTE_NAO_IMPORTANTE, A.IGNOROU],
		[C.URGENTE_IMPORTANTE, C.NAO_URGENTE_NAO_IMPORTANTE, A.IGNOROU],

		[C.IMPORTANTE_NAO_URGENTE, C.IMPORTANTE_NAO_URGENTE, A.COLETAR],
		[C.IMPORTANTE_NAO_URGENTE, C.URGENTE_IMPORTANTE, A.IGNOROU],
		[C.IMPORTANTE_NAO_URGENTE, C.URGENTE_NAO_IMPORTANTE, A.IGNOROU],
		[C.IMPORTANTE_NAO_URGENTE, C.NAO_URGENTE_NAO_IMPORTANTE, A.IGNOROU],

		# O quadrante 3 é o único com DUAS ações legítimas, e é assim no Quadro 1.
		[C.URGENTE_NAO_IMPORTANTE, C.URGENTE_NAO_IMPORTANTE, A.DELEGAR],
		[C.URGENTE_NAO_IMPORTANTE, C.URGENTE_IMPORTANTE, A.RESOLVER],
		[C.URGENTE_NAO_IMPORTANTE, C.IMPORTANTE_NAO_URGENTE, A.IGNOROU],
		[C.URGENTE_NAO_IMPORTANTE, C.NAO_URGENTE_NAO_IMPORTANTE, A.IGNOROU],

		# Descartar lixo é ACERTO — a Fundamentação Teórica chama o quadrante 4 de
		# "candidatas à eliminação". Tratá-lo como trabalho é o erro que a matriz existe
		# para evitar, e o Quadro 1 já tem preço para ele.
		[C.NAO_URGENTE_NAO_IMPORTANTE, C.NAO_URGENTE_NAO_IMPORTANTE, A.EVITOU],
		[C.NAO_URGENTE_NAO_IMPORTANTE, C.URGENTE_IMPORTANTE, A.COLIDIU],
		[C.NAO_URGENTE_NAO_IMPORTANTE, C.IMPORTANTE_NAO_URGENTE, A.COLIDIU],
		[C.NAO_URGENTE_NAO_IMPORTANTE, C.URGENTE_NAO_IMPORTANTE, A.COLIDIU],
	]

	var nome := ["Q1", "Q2", "Q3", "Q4"]
	var acertos := 0
	for caso in casos:
		var obtido: int = Zona.acao_para(caso[0], caso[1])
		_conferir("%s levado ao canto %s" % [nome[caso[0]], nome[caso[1]]], obtido, caso[2])
		if Zona.acertou(caso[0], caso[1]):
			acertos += 1

	# Exatamente 5 das 16 combinações são acerto: os três destinos certos, a segunda opção
	# do Q3, e descartar o lixo. Se esse número mudar, a dificuldade da fase mudou junto —
	# e é para isso que ele está travado aqui.
	_conferir("5 das 16 combinações são acerto", acertos, 5)


## A pilha é a única fonte de derrota da fase. A aritmética dela precisa ser exata: um
## erro para mais torna a fase impossível, um erro para menos a torna sem consequência.
func _cenario_pilha() -> void:
	print("\n--- cenário 4: a aritmética do soterramento ---")

	var pilha = Pilha.new()

	var C := GameManager.Categoria
	_conferir("nasce vazia", pilha.unidades, 0)

	pilha.apodreceu(C.URGENTE_IMPORTANTE)
	_conferir("Q1 apodrecida pesa 2", pilha.unidades, 2)

	pilha.apodreceu(C.IMPORTANTE_NAO_URGENTE)
	_conferir("Q2 apodrecida pesa 1", pilha.unidades, 3)

	pilha.apodreceu(C.NAO_URGENTE_NAO_IMPORTANTE)
	_conferir("Q4 ignorada não pesa nada", pilha.unidades, 3)

	pilha.errou()
	_conferir("canto errado pesa 2", pilha.unidades, 5)

	pilha.acertou()
	_conferir("acerto derruba 1", pilha.unidades, 4)

	# Errar tem de custar mais do que acertar devolve. Sem essa assimetria, largar papel em
	# canto aleatório mantém a pilha parada e a fase se ganha sem classificar nada.
	_conferir("errar pesa mais do que acertar alivia", Pilha.PESO_ERRO > 1, true)

	for _i in 10:
		pilha.acertou()
	_conferir("não passa de zero", pilha.unidades, 0)

	# Os dois limiares que definem a dramaturgia da fase.
	for _i in int(ceil(float(Pilha.ALERTA) / Pilha.PESO_ERRO)):
		pilha.errou()
	_conferir("entra em alerta no limiar", pilha.em_alerta(), true)

	for _i in Pilha.SOTERRA:
		pilha.errou()
	_conferir("soterrou no limiar", pilha.soterrou(), true)

	# A fase tem de recusar o chute. Um jogador que recolhe papel e larga em canto sorteado
	# acerta ~1 em 4; um que classifica bem acerta 4 em 5. O modelo abaixo roda o orçamento
	# real do expediente contra a aritmética real da pilha, priorizando o que pesa mais ao
	# apodrecer — que é o que um jogador competente faz.
	_conferir("classificar no chute soterra", _soterrados(0.25, 24) >= 55, true)
	_conferir("classificar bem sobrevive", _soterrados(0.8, 24), 0)

	# A recuperação precisa ser possível DEPOIS do alerta, senão a fase vira espiral sem
	# saída — recusada sete vezes neste projeto e recusada de novo aqui.
	var altura_antes: float = pilha.altura_px()
	pilha.acertou()
	_conferir("acertar ainda baixa a pilha depois do alerta", pilha.altura_px() < altura_antes, true)

	# A altura NUNCA pode cobrir os cantos de baixo. É por isso que ela é derivada do teto
	# da arena, e não um valor fixo por unidade.
	pilha.unidades = Pilha.SOTERRA
	var topo: float = pilha.topo(Sorteio.Y_CHAO)
	_conferir("no teto, o piche fica abaixo dos pedestais", topo > Sorteio.Y_PEDESTAL, true)
	_conferir("no teto, o piche fica abaixo dos degraus", topo > Sorteio.Y_DEGRAU, true)


## O cenário 1 prova que o validador ACEITA 200 sorteios bons. Este prova que ele RECUSA
## os ruins — que é a metade que realmente importa.
##
## Sem ele, um validador que devolvesse lista vazia para tudo passaria no cenário 1 com
## nota máxima, e a fase poderia sortear uma arena invencível sem nada denunciar. Cada
## quebra abaixo corresponde a uma invariante, e todas foram feitas de propósito.
func _cenario_validador_recusa() -> void:
	print("\n--- cenário 5: o validador recusa geometria quebrada ---")

	var C := GameManager.Categoria
	var quebras := {
		"canto no ar, fora da plataforma": func(l: Dictionary) -> void:
			l["cantos"][C.IMPORTANTE_NAO_URGENTE] = Vector2(320, Sorteio.Y_MEZANINO),
		"dois cantos sobrepostos": func(l: Dictionary) -> void:
			l["cantos"][C.NAO_URGENTE_NAO_IMPORTANTE] = l["cantos"][C.URGENTE_IMPORTANTE],
		"uma rota só até o mezanino": func(l: Dictionary) -> void:
			var d: Array[Rect2] = [
				Rect2(216, Sorteio.Y_DEGRAU, 48, 16),
				Rect2(344, Sorteio.Y_DEGRAU, 48, 16),
			]
			l["degraus"] = d,
		"orçamento de dificuldade adulterado": func(l: Dictionary) -> void:
			var f: Array[int] = l["fila"]
			f.remove_at(0)
			l["fila"] = f,
		"pouso em cima de um canto": func(l: Dictionary) -> void:
			var p: Array[Vector2] = l["pousos"]
			p.append(l["cantos"][C.URGENTE_IMPORTANTE])
			l["pousos"] = p,
	}

	for nome in quebras:
		var layout := Sorteio.sortear(31)
		(quebras[nome] as Callable).call(layout)
		_conferir("recusa: %s" % nome, Sorteio.validar(layout).is_empty(), false)


## Instancia a fase de verdade e confere que a CENA bate com o layout sorteado. Sem isto,
## o sorteador poderia estar perfeito e a arena montar os cantos em outro lugar, e as 200
## sementes do cenário 1 não diriam nada sobre o jogo que abre de verdade.
func _cenario_arena() -> void:
	print("\n--- cenário 6: a arena montada bate com o sorteio ---")

	var fase := await _abrir_fase(77)
	var layout: Dictionary = fase.layout

	_conferir("a semente pedida foi a usada", layout["semente"], 77)
	_conferir("o layout entregue é válido", Sorteio.validar(layout).size(), 0)

	var zonas: Node2D = fase.get_node("Zonas")
	_conferir("quatro cantos na cena", zonas.get_child_count(), 4)

	var encontrados := {}
	for zona in zonas.get_children():
		encontrados[zona.papel] = zona.position
	for categoria in GameManager.Categoria.values():
		_conferir(
			"canto %d no lugar sorteado" % categoria,
			encontrados.get(categoria, Vector2.ZERO), layout["cantos"][categoria]
		)

	# Os degraus nascem em código porque são sorteados. Se alguém os mover para o .tscn
	# estático, o sorteio deles vira decoração e ninguém percebe.
	var estaticos := 0
	for corpo in (fase.get_node("Colisores") as Node2D).get_children():
		if corpo is StaticBody2D:
			estaticos += 1
	var fixos := 7                       # piso, 2 pedestais, 2 mezaninos, 2 paredes
	_conferir("degraus sorteados existem na cena", estaticos - fixos,
		(layout["degraus"] as Array[Rect2]).size())

	# A fase final é a única em que zerar o relógio é VITÓRIA. Se este gancho se perder,
	# o jogador perde exatamente no momento em que deveria ganhar.
	_conferir("zerar o relógio aqui é vencer", GameManager.vitoria_ao_esgotar_tempo, true)
	_conferir("o dia é o 3", GameManager.dia, 3)
	_conferir("o briefing anuncia a duração real", GameManager.SEGUNDOS_DO_DIA[3],
		fase.tempo_de_expediente())
	_conferir("o briefing anuncia o total real de demandas", GameManager.TAREFAS_DO_DIA[3],
		Sorteio.total_de_demandas())

	# As duas habilidades que só existem neste dia, e o anúncio delas. O jogador chega
	# aqui de dois expedientes inteiros em que pular no ar não fazia nada, então ligá-las
	# sem avisar é o mesmo que não ligá-las.
	var jogador: CharacterBody2D = fase.get_node("Player")
	_conferir("o último dia oferece pulo duplo", jogador.pulo_duplo, true)
	_conferir("o último dia oferece arranque", jogador.arranque, true)
	var Briefing := load("res://scripts/briefing.gd")
	var anuncia := false
	for regra in (Briefing.PAUTA[3]["regras"] as Array):
		if str(regra[0]).contains("PULO DUPLO"):
			anuncia = true
	_conferir("a pauta do dia anuncia o pulo duplo", anuncia, true)

	# A arena cabe numa tela só: barra de percurso ali fica colada num extremo o
	# expediente inteiro, ocupando espaço de HUD que os dois corredores precisam.
	_conferir("a arena não mostra barra de percurso", fase.usa_percurso(), false)
	_conferir("e a barra está escondida no HUD",
		fase.get_node("HUD").percurso.visible, false)

	fase.queue_free()
	await get_tree().process_frame


## As quatro fases do Chefe e a regra de que cada ataque só existe a partir da fase que o
## introduz. A fase 1 tem de ser limpa: é onde o jogador aprende o laço básico, e um
## ataque ali transformaria aprendizado em susto.
func _cenario_chefe() -> void:
	print("\n--- cenário 7: as quatro fases do Chefe ---")

	var Chefe := load("res://scripts/chefe.gd")
	_conferir("a fase 1 não tem ataque", (Chefe.ATAQUES_POR_FASE[0] as Array).size(), 0)
	_conferir("a fase 1 não agenda ataque", Chefe.new().intervalos_de_ataque[0], 0.0)

	# Cada fase contém todos os ataques da anterior: a curva é acumulativa, não uma
	# troca de conjunto. Se alguém remover um ataque no meio, a dificuldade cai no fim.
	for i in range(1, Chefe.ATAQUES_POR_FASE.size()):
		var anterior: Array = Chefe.ATAQUES_POR_FASE[i - 1]
		var atual: Array = Chefe.ATAQUES_POR_FASE[i]
		var contem_tudo := true
		for ataque in anterior:
			if ataque not in atual:
				contem_tudo = false
		_conferir("fase %d mantém os ataques da anterior" % (i + 1), contem_tudo, true)
		_conferir("fase %d aperta o ritmo" % (i + 1),
			Chefe.new().intervalos[i] < Chefe.new().intervalos[i - 1], true)

	var fase := await _abrir_fase(5)
	var chefe: Node2D = fase.get_node("Inimigos/Chefe")
	_conferir("começa na fase 1", chefe.fase_atual, 0)
	_conferir("o Chefe está fora de alcance",
		chefe.position.y < Sorteio.Y_MEZANINO - 40.0, true)

	fase.queue_free()
	await get_tree().process_frame


## O robô a pé: pega um papel e o entrega, com a física real e as mesmas teclas de um
## humano. É o único cenário que prova que a fase é JOGÁVEL, e não só aritmeticamente
## correta — teleportar o jogador para cima de um canto provaria só que a conta fecha.
func _cenario_a_pe() -> void:
	print("\n--- cenário 8: dá para pegar e entregar um papel a pé ---")

	var fase := await _abrir_fase(11)
	var jogador: CharacterBody2D = fase.get_node("Player")

	# Sem cronômetro: um teste que falhe porque o headless rodou devagar não diz nada
	# sobre o level design. Mesma decisão do robô da Fase 1.
	GameManager.em_jogo = true
	GameManager.tempo_restante = 9999.0

	# Espera um papel pousar NO CHÃO.
	#
	# O filtro de altura não é conveniência: o robô é de propósito burro e só anda em x.
	# Sem ele, o teste sorteava um papel que pousou no mezanino, o robô caminhava até
	# debaixo dele e falhava — o que reprovaria a fase por um defeito do teste. Papéis em
	# altura são cobertos pelo cenário 5, que confere que todo canto é alcançável.
	var demanda: Node = null
	for i in 900:
		await get_tree().physics_frame
		for candidata in get_tree().get_nodes_in_group("demanda"):
			if not candidata._caiu or candidata.resolvida:
				continue
			if candidata.global_position.y < Sorteio.Y_CHAO - 24.0:
				continue
			demanda = candidata
			break
		if demanda != null:
			break
	_conferir("o Chefe arremessou e o papel pousou", demanda != null, true)
	if demanda == null:
		fase.queue_free()
		return

	# Anda até um papel usando as teclas de verdade, reescolhendo o alvo a cada quadro.
	# Alvo fixo não serve: como a validade corre também com o papel na mão, o alvo pode
	# vencer no meio da caminhada e o robô seguiria andando até uma vaga vazia.
	_alvo_papel = null
	_alvo_recorde = INF
	_alvo_espera = 0
	_alvos_desistidos.clear()
	var pegou := await _caminhar_ate(jogador, 900,
		func() -> float: return _papel_mais_perto(jogador),
		func() -> bool: return fase._carregando != null)
	_conferir("o jogador pegou o papel andando até ele", pegou, true)
	_conferir("carregar deixa o jogador mais lento", GameManager.carregando, true)
	_conferir("a velocidade caiu para 80%", is_equal_approx(
		GameManager.fator_de_carga(), 0.8), true)

	if not pegou:
		fase.queue_free()
		return

	# Segundo papel não pode ser pego: é a escassez inteira da fase.
	var antes: Node = fase._carregando
	fase._ler_entrada()
	_conferir("não dá para carregar dois", fase._carregando, antes)

	# Leva o papel até um canto de CHÃO (o robô só anda em x) e confere que o que foi
	# registrado é exatamente o que o Quadro 1 manda para aquela combinação.
	#
	# Escolher o canto e prever a ação, em vez de exigir "pontuou", é o que torna este
	# cenário honesto: o papel sorteado pode ser de qualquer quadrante, e entregar um Q4
	# no canto de fazer-agora DEVE valer −20. Um teste que só exigisse pontuação positiva
	# passaria escondendo esse caso.
	#
	# A categoria sai do papel que está NA MÃO, e não do que o robô saiu perseguindo.
	# Como a validade corre também com o papel na mão, o alvo original
	# pode ter apodrecido durante a caminhada e o robô ter pego outro pelo caminho — ler o
	# nó velho aqui dava "acesso a objeto previamente liberado", e o teste morria.
	var categoria: int = fase._carregando.categoria
	var Zona := load("res://scripts/zona_matriz.gd")
	var destino_categoria := -1
	var destino_x := 0.0
	for candidata in fase.layout["cantos"]:
		if int(fase.layout["nivel"][candidata]) != 0:
			continue
		var x: float = (fase.layout["cantos"][candidata] as Vector2).x
		if destino_categoria < 0 or absf(x - jogador.global_position.x) < absf(destino_x - jogador.global_position.x):
			destino_categoria = candidata
			destino_x = x

	var acao_esperada: int = Zona.acao_para(categoria, destino_categoria)
	var contagem_antes: int = GameManager.acoes_por_tipo[acao_esperada]
	# O canto de destino é relido a cada quadro: a reorganização do escritório pode
	# deslocá-lo no meio da travessia, e é justamente isso que ela existe para fazer.
	var destino: int = destino_categoria
	await _caminhar_ate(jogador, 1600,
		func() -> float: return (fase.layout["cantos"][destino] as Vector2).x,
		func() -> bool: return fase._carregando == null)

	# "Entregou" NÃO pode ser "as mãos esvaziaram": o papel também esvazia a mão ao
	# apodrecer nela. A prova de entrega é a ação do Quadro 1 ter sido contada.
	var entregou: bool = GameManager.acoes_por_tipo[acao_esperada] == contagem_antes + 1
	_conferir("o papel foi entregue a pé, dentro da validade", entregou, true)
	_conferir("as mãos ficaram livres", GameManager.carregando, false)

	Input.action_release("right")
	Input.action_release("left")
	Input.action_release("jump")
	fase.queue_free()
	await get_tree().process_frame


## Papel que o robô está perseguindo. Guardado entre quadros de propósito — ver abaixo.
var _alvo_papel: Node = null


## X do papel pousado mais perto do jogador, no nível do chão. Devolve o X do próprio
## jogador quando não há nenhum — parado é melhor que correr para o infinito.
##
## Uma vez escolhido, o alvo é mantido enquanto existir. Sem essa histerese, dois papéis
## a distâncias parecidas em lados opostos fazem o robô alternar entre eles a cada quadro
## e oscilar no lugar, sem alcançar nenhum.
##
## A histerese sozinha, porém, prende o robô a alvos inalcançáveis: o layout é sorteado
## por semente fixa, mas os arremessos do Chefe não são, e um papel pode pousar atrás de
## um degrau ou do outro lado de um vão. Daí a desistência por falta de progresso — sem
## se aproximar por 2,5 s, o alvo entra na lista negra e outro é escolhido. O orçamento
## de 900 quadros continua o mesmo.
const QUADROS_SEM_PROGRESSO := 150

var _alvo_recorde := INF
var _alvo_espera := 0
var _alvos_desistidos := {}


func _papel_mais_perto(jogador: CharacterBody2D) -> float:
	if is_instance_valid(_alvo_papel) and not _alvo_papel.resolvida and not _alvo_papel.carregada:
		var atual: float = absf(_alvo_papel.global_position.x - jogador.global_position.x)
		if atual < _alvo_recorde - 1.0:
			_alvo_recorde = atual
			_alvo_espera = 0
		else:
			_alvo_espera += 1
		if _alvo_espera < QUADROS_SEM_PROGRESSO:
			return _alvo_papel.global_position.x
		_alvos_desistidos[_alvo_papel.get_instance_id()] = true

	_alvo_papel = null
	_alvo_recorde = INF
	_alvo_espera = 0
	var melhor := jogador.global_position.x
	var distancia := INF
	for candidata in get_tree().get_nodes_in_group("demanda"):
		if not candidata._caiu or candidata.resolvida or candidata.carregada:
			continue
		if candidata.global_position.y < Sorteio.Y_CHAO - 24.0:
			continue
		if _alvos_desistidos.has(candidata.get_instance_id()):
			continue
		var d: float = absf(candidata.global_position.x - jogador.global_position.x)
		if d < distancia:
			distancia = d
			melhor = candidata.global_position.x
			_alvo_papel = candidata
	if _alvo_papel != null:
		_alvo_recorde = distancia
	return melhor


## Anda na direção do X devolvido por `alvo`, pulando quando esbarra, até `pronto` virar
## verdadeiro. Pular quando a velocidade horizontal morre é o que faz o robô subir degraus
## sem precisar conhecer a geometria — que é justamente o ponto: se ele conseguir, a fase
## está atravessável para quem não decorou nada.
##
## O alvo é um Callable, e não um número, porque a Fase 3 se mexe embaixo do robô: papéis
## vencem e a reorganização do Chefe troca os cantos de lugar. Um alvo congelado no início
## da caminhada manda o robô para onde a sala ESTAVA.
func _caminhar_ate(jogador: CharacterBody2D, passos: int, alvo: Callable,
		pronto: Callable) -> bool:
	for i in passos:
		var alvo_x: float = alvo.call()
		var diferenca: float = alvo_x - jogador.global_position.x
		if absf(diferenca) < 6.0:
			Input.action_release("right")
			Input.action_release("left")
		elif diferenca > 0.0:
			Input.action_release("left")
			Input.action_press("right")
		else:
			Input.action_release("right")
			Input.action_press("left")

		# Pula se está no chão e travado, ou se o alvo está claramente acima.
		var precisa := jogador.is_on_floor() and (
			absf(jogador.velocity.x) < 20.0 or (i % 40) < 3
		)
		if precisa:
			Input.action_press("jump")
		else:
			Input.action_release("jump")

		await get_tree().physics_frame
		if pronto.call():
			Input.action_release("right")
			Input.action_release("left")
			Input.action_release("jump")
			return true
	Input.action_release("right")
	Input.action_release("left")
	Input.action_release("jump")
	return false


## As quatro mecânicas de pressão, mais a aritmética que as motivou.
func _cenario_pressao() -> void:
	print("\n--- cenário 9: a pressão do expediente ---")

	# A conta que começou tudo
	#
	# A Fase 3 nasceu com 28 demandas e intervalos que pedem mais de 40 arremessos: a fila
	# secava por volta dos 71 s de 100, e a última fase do Chefe — a mais rápida, a única
	# com o conjunto completo de ataques — ficava sem nada para jogar. Este bloco é a trava
	# contra a regressão, e ele mede o Chefe de verdade em vez de repetir um número.
	var chefe: Node2D = load("res://entities/chefe.tscn").instantiate()
	add_child(chefe)
	var duracao: float = GameManager.SEGUNDOS_DO_DIA[3]
	var arremessos := 0
	var relogio := 0.0
	var ate_o_proximo := 1.2
	var fase_do_chefe := 0
	while relogio < duracao:
		relogio += 0.05
		fase_do_chefe = mini(int(relogio / chefe.duracao_da_fase), chefe.intervalos.size() - 1)
		ate_o_proximo -= 0.05
		if ate_o_proximo <= 0.0:
			arremessos += 1
			ate_o_proximo = chefe.intervalos[fase_do_chefe]

	_conferir("o Chefe pede mais papel do que a fila tem, e não o contrário",
		arremessos >= Sorteio.total_na_fila(), true)
	# Folga de no máximo 25%: pedir MUITO mais do que existe faz a fila secar cedo de novo,
	# só que por outro caminho. As duas bordas importam.
	_conferir("e não pede tanto a ponto de secar a fila cedo",
		arremessos <= int(Sorteio.total_na_fila() * 1.25), true)
	_conferir("a última fase do Chefe ainda tem papel para jogar",
		fase_do_chefe, chefe.intervalos.size() - 1)
	chefe.queue_free()

	# A reserva de e-mail fecha o orçamento
	_conferir("a reserva de e-mail é gasta em bursts inteiros",
		Sorteio.RESERVA_EMAIL % Sorteio.EMAIL_POR_ATAQUE, 0)
	_conferir("os bursts programados gastam a reserva exata",
		Chefe_momentos() * Sorteio.EMAIL_POR_ATAQUE, Sorteio.RESERVA_EMAIL)
	# A reserva sai da Q4, e só dela: "e-mail em cópia para todos" que despejasse urgentes
	# seria outra coisa, e a versão anterior fazia exatamente isso ao sacar da fila.
	var q4_na_fila: int = Sorteio._quantidade_na_fila(
		GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE)
	_conferir("a reserva sai da Q4",
		q4_na_fila + Sorteio.RESERVA_EMAIL,
		int(Sorteio.ORCAMENTO[GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE]))
	for categoria in [GameManager.Categoria.URGENTE_IMPORTANTE,
			GameManager.Categoria.IMPORTANTE_NAO_URGENTE,
			GameManager.Categoria.URGENTE_NAO_IMPORTANTE]:
		_conferir("nenhuma outra categoria é reservada (%d)" % categoria,
			Sorteio._quantidade_na_fila(categoria), int(Sorteio.ORCAMENTO[categoria]))

	# A sala em movimento
	var fase: Node2D = await _abrir_fase(31)

	# O duplo bloqueio da última fase. A trava que importa não é "bloqueou dois" — é que
	# NUNCA sobra zero destino: se o Chefe pudesse fechar o canto do papel que está na mão,
	# a partida cobraria uma decisão que já não pode ser executada.
	fase.chefe.fase_atual = 0
	fase._atacar_ocupar()
	_conferir("nas primeiras fases o Chefe ocupa um canto só", _bloqueados(fase), 1)
	for zona in fase.zonas.get_children():
		zona.bloqueado = false

	fase.chefe.fase_atual = fase.chefe.ATAQUES_POR_FASE.size() - 1
	fase._atacar_ocupar()
	_conferir("na última fase ele ocupa dois", _bloqueados(fase), 2)
	_conferir("e ainda sobram destinos", _bloqueados(fase) < 4, true)
	for zona in fase.zonas.get_children():
		zona.bloqueado = false

	var antes := {}
	for categoria in fase.layout["cantos"]:
		antes[categoria] = fase.layout["cantos"][categoria]

	fase._atacar_reorganizar()
	await get_tree().physics_frame

	var trocaram := 0
	for categoria in fase.layout["cantos"]:
		if fase.layout["cantos"][categoria] != antes[categoria]:
			trocaram += 1
	_conferir("a reorganização troca cantos de lugar", trocaram >= 2, true)

	# A troca é DENTRO do nível, e isso não é detalhe: Q2 e Q3 moram no mezanino porque a
	# regra pedagógica das três fases é que o importante-e-não-urgente custe uma subida
	# deliberada. Uma troca entre níveis rebaixaria a Q2 para o chão e desfaria isso.
	var nivel_mudou := 0
	for categoria in fase.layout["cantos"]:
		var y: float = (fase.layout["cantos"][categoria] as Vector2).y
		var esperado: float = Sorteio.Y_MEZANINO if int(fase.layout["nivel"][categoria]) == 1 \
			else Sorteio.Y_PEDESTAL
		if not is_equal_approx(y, esperado):
			nivel_mudou += 1
	_conferir("nenhum quadrante mudou de nível", nivel_mudou, 0)

	# O conjunto de posições é o mesmo, só o par quadrante↔posição mudou. É isso que
	# permite não revalidar a geometria depois de reorganizar.
	var posicoes_antes: Array = antes.values()
	var posicoes_depois: Array = fase.layout["cantos"].values()
	posicoes_antes.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	posicoes_depois.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	_conferir("o conjunto de posições não muda", posicoes_antes == posicoes_depois, true)
	_conferir("a arena continua válida depois de reorganizar",
		Sorteio.validar(fase.layout).size(), 0)

	# O e-mail em cópia
	var papeis_antes: int = get_tree().get_nodes_in_group("demanda").size()
	fase._atacar_enxurrada()
	await get_tree().physics_frame
	var novos: Array = []
	for candidata in get_tree().get_nodes_in_group("demanda"):
		if not candidata.resolvida:
			novos.append(candidata)
	_conferir("a enxurrada despeja o burst inteiro",
		novos.size() - papeis_antes, Sorteio.EMAIL_POR_ATAQUE)
	var so_q4 := true
	for candidata in novos:
		if candidata.categoria != GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE:
			so_q4 = false
	_conferir("e o que ela despeja é só lixo", so_q4, true)

	# Segundo burst esvazia a reserva; um terceiro não pode inventar papel.
	fase._atacar_enxurrada()
	fase._atacar_enxurrada()
	await get_tree().physics_frame
	_conferir("a reserva não passa do orçamento",
		fase._reserva_gasta, Sorteio.RESERVA_EMAIL)

	fase.queue_free()
	await get_tree().process_frame

	# O papel na mão

	# O que já foi pego é trabalho em andamento: o relógio de validade para, e volta a
	# correr se o jogador largar. Segurar continua tendo custo, porque só cabe um papel
	# por vez e o que fica no chão apodrece.
	fase = await _abrir_fase(52)
	fase._soltar_papel(GameManager.Categoria.URGENTE_IMPORTANTE,
		Vector2(fase.jogador.global_position.x, Sorteio.Y_CHAO))
	await get_tree().physics_frame

	var papel: Node = null
	for i in 240:
		await get_tree().physics_frame
		for candidata in get_tree().get_nodes_in_group("demanda"):
			if candidata._caiu and not candidata.resolvida:
				papel = candidata
				break
		if papel != null:
			break
	_conferir("o papel de teste pousou", papel != null, true)

	if papel != null:
		fase._pegar(papel)
		_conferir("o papel está na mão", GameManager.carregando, true)
		var restante_ao_pegar: float = papel._restante
		for _i in 30:
			await get_tree().physics_frame
		_conferir("a validade para com o papel na mão",
			is_equal_approx(papel._restante, restante_ao_pegar), true)
		_conferir("e o papel continua na mão", papel.resolvida, false)

		# Largar devolve o papel ao chão e o relógio volta a correr de onde parou.
		fase._largar()
		# Longe do papel largado: a fase pega por proximidade, e ficar em cima dele o
		# recolheria no quadro seguinte.
		fase.jogador.global_position.x += 150.0
		# Ele cai até o chão antes de voltar a envelhecer; a espera cobre a queda e a
		# contagem depois dela.
		for _i in 60:
			await get_tree().physics_frame
		_conferir("largado, volta a envelhecer",
			papel._restante < restante_ao_pegar - 0.3, true)

	fase.queue_free()
	await get_tree().process_frame


## Quantos cantos da matriz estão fora do ar agora.
func _bloqueados(fase: Node2D) -> int:
	var total := 0
	for zona in fase.zonas.get_children():
		if zona.bloqueado:
			total += 1
	return total


## Quantos bursts de e-mail o Chefe dispara por expediente.
func Chefe_momentos() -> int:
	var chefe := load("res://scripts/chefe.gd")
	return (chefe.MOMENTOS_DA_ENXURRADA as Array).size()


## Instancia a Fase 3 com uma semente fixa. Semente fixa é o que torna a suíte
## reprodutível: sem ela, cada execução jogaria uma arena diferente e uma falha não
## poderia ser reproduzida para investigação.
func _abrir_fase(semente: int) -> Node2D:
	var cena: PackedScene = load("res://scenes/level/fase_03.tscn")
	var fase: Node2D = cena.instantiate()
	fase.semente = semente
	add_child(fase)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return fase


func _conferir(o_que: String, obtido: Variant, esperado: Variant) -> void:
	var passou: bool = obtido == esperado
	if not passou:
		falhas += 1
	print("  %s  %s = %s%s" % [
		"ok   " if passou else "FALHA",
		o_que, str(obtido),
		"" if passou else "   (esperado %s)" % str(esperado),
	])


## Quantas de 60 partidas soterram, dada a taxa de acerto do jogador e quantos papéis ele
## consegue rotear no expediente. O jogador do modelo prioriza pelo peso de apodrecimento.
func _soterrados(acerto: float, entregas: int) -> int:
	var perdeu := 0
	for semente in 60:
		var r := RandomNumberGenerator.new()
		r.seed = semente
		var fila: Array = []
		for cat in Sorteio.ORCAMENTO:
			for _i in int(Sorteio.ORCAMENTO[cat]):
				fila.append(cat)
		for _i in int(Sorteio.RESERVA_EMAIL):
			fila.append(GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE)
		fila.shuffle()
		fila.sort_custom(func(a, b) -> bool:
			return int(Pilha.PESO_APODRECIDA.get(a, 1)) > int(Pilha.PESO_APODRECIDA.get(b, 1)))

		var unidades := 0
		var pico := 0
		for i in fila.size():
			if i < entregas:
				unidades += -1 if r.randf() < acerto else Pilha.PESO_ERRO
			else:
				unidades += int(Pilha.PESO_APODRECIDA.get(fila[i], 1))
			unidades = clampi(unidades, 0, Pilha.SOTERRA)
			pico = maxi(pico, unidades)
		if pico >= Pilha.SOTERRA:
			perdeu += 1
	return perdeu
