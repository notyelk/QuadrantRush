extends Node

## Teste automatizado da Fase 1 — Etapa 8 da Metodologia ("testes automatizados,
## cobrindo a lógica de pontuação e priorização").
##
## Como rodar:
##   godot --headless --path . res://tests/teste_fase_01.tscn
## Sai com código 0 se tudo passar, 1 se algo falhar (serve para CI depois).
##
## Roda como CENA, não com --script: em modo --script o Godot não instancia os
## autoloads, e sem GameManager nada aqui compila.
##
## São percursos opostos sobre a MESMA fase de verdade, não sobre mocks:
##   1. jogador ideal    — pega tudo pela rota alta, delega as Q3, evita as Q4
##   2. jogador apressado — corre reto pelo chão, resolve as Q3 no caminho fácil, bate nas
##      distrações e descobre que o elevador não abre. É o que prova o custo de resolver
##      em vez de delegar e a obrigatoriedade das Q1.
##   3. tarefas anônimas — nenhuma tarefa entrega o próprio quadrante antes da ação. Se um
##      ícone voltar a nascer colorido, o jogo dá a resposta de graça e o teste falha.
##   4. o prazo — o perseguidor cobra tempo sem sujar as notas por categoria

const CENA_FASE := preload("res://scenes/level/fase_01.tscn")

## Altura de trânsito usada para levar o jogador de um alvo a outro sem atravessar
## nada por acidente: fica acima de qualquer gatilho de chão ou de mezanino, e
## acima também das duas tarefas de bônus da rota alta (y=62 e y=72, raio de
## contato 8) — se o trânsito passasse na altura delas, elas seriam coletadas de
## graça e o cenário deixaria de provar que a rota alta é necessária.
const ALTURA_TRANSITO := 22.0

var falhas := 0


func _ready() -> void:
	# Os percursos chegam ao fim da fase, e a tela de resultado grava a partida no ranking
	# local (Etapa 7). Sem este desvio, rodar a suíte encheria de partidas de robô o
	# histórico de quem estiver jogando nesta máquina.
	SupabaseClient.caminho_local = "user://teste_ranking.cfg"

	await _cenario_ideal()
	await _cenario_apressado()
	await _cenario_tarefas_anonimas()
	await _cenario_prazo()
	await _cenario_rota_alta_alcancavel()
	await _cenario_urso_pressiona()
	await _cenario_percurso_a_pe()
	_cenario_perfil()
	await _cenario_briefing()
	await _cenario_colega()
	await _cenario_pasta()
	await _cenario_foco()
	await _cenario_setores()
	await _cenario_bordas()
	_cenario_enunciados()

	print("\n=====  %s  =====" % ("FALHOU (%d)" % falhas if falhas else "TODOS OS TESTES OK"))
	get_tree().quit(1 if falhas else 0)


## Percurso ideal: 4x Q1 (+400), 6x Q2 (+480), 3x Q3 delegadas (+180) = 1060 pontos,
## 11 Q4 evitadas, elevador liberado, vitória.
##
## Duas das seis Q2 só existem na rota alta (sobre as plataformas móveis). Isso é
## proposital e é o argumento de design da fase: "importante e não urgente" é o
## quadrante que as pessoas adiam justamente porque exige esforço deliberado, então
## no jogo ele fica onde exige esforço deliberado. A rota baixa, fácil, é a que está
## cheia de distrações Q4.
func _cenario_ideal() -> void:
	print("\n--- cenário 1: jogador ideal ---")
	var fase := await _abrir_fase()
	var jogador: CharacterBody2D = fase.get_node("Player")

	_conferir("tarefas Q1 na fase", fase.composicao[0], 4)
	_conferir("tarefas Q2 na fase", fase.composicao[1], 6)
	_conferir("tarefas Q3 na fase", fase.composicao[2], 3)
	_conferir("tarefas Q4 na fase", fase.composicao[3], 11)
	_conferir("cronômetro ligado ao abrir", GameManager.em_jogo, true)

	var alvos: Array[Vector2] = []
	for t in fase.get_node("Tarefas").get_children():
		if t.categoria != GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE:
			alvos.append(t.global_position)
	for b in fase.get_node("Bifurcacoes").get_children():
		alvos.append(b.get_node("PontoDelegar").global_position)
	# Sempre da esquerda para a direita: voltar atrás faria o jogador atravessar o
	# corredor de uma bifurcação já passada e disparar "resolver" sem querer.
	alvos.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	for alvo in alvos:
		await _levar(jogador, alvo)
	await _levar(jogador, Vector2(2500, 150))  # até o fim, para as Q4 contarem como evitadas

	var saida := fase.get_node("Saida")
	_conferir("elevador liberou com as 4 Q1", saida.liberada, true)
	_conferir("Q1 coletadas", GameManager.tarefas_por_categoria[0], 4)
	_conferir("Q2 coletadas", GameManager.tarefas_por_categoria[1], 6)
	_conferir("Q3 delegadas", GameManager.acoes_por_tipo[GameManager.Acao.DELEGAR], 3)
	_conferir("Q3 resolvidas", GameManager.acoes_por_tipo[GameManager.Acao.RESOLVER], 0)
	_conferir("Q4 evitadas", GameManager.acoes_por_tipo[GameManager.Acao.EVITOU], 11)
	_conferir("Q4 colididas", GameManager.acoes_por_tipo[GameManager.Acao.COLIDIU], 0)
	_conferir("nenhuma tarefa ficou para trás", GameManager.acoes_por_tipo[GameManager.Acao.IGNOROU], 0)
	_conferir("pontuação máxima (400+480+180)", GameManager.pontuacao_total, 1060)

	await _levar(jogador, saida.global_position + Vector2(4, -16))
	_conferir("terminou em vitória", GameManager.ultima_vitoria, true)
	_conferir("cronômetro parado no fim", GameManager.em_jogo, false)

	await _fechar_fase(fase)


## Percurso apressado: corre colado no chão do começo ao fim. Passa por baixo dos
## mezaninos (resolve as 3 Q3), atravessa as Q4 que oscilam na altura do chão e
## nunca sobe para pegar as Q1 do alto — então o elevador continua trancado.
func _cenario_apressado() -> void:
	print("\n--- cenário 2: jogador apressado (rota baixa) ---")
	var fase := await _abrir_fase()
	var jogador: CharacterBody2D = fase.get_node("Player")

	# O expediente é abastecido ANTES da varredura, e isso não é trapaça: é o que separa
	# medir o comportamento de medir o relógio.
	#
	# São 11 distrações no chão a −8s cada. Correr por cima de todas custa 88 segundos num
	# dia de 60 — ou seja, este perfil MORRE de tempo no meio do corredor, e é ótimo que
	# morra: é o que prova que atropelar o dia inteiro é inviável. Mas com a fase acabando
	# na metade, as tarefas do trecho final nunca se registram e o cenário deixaria de
	# medir justamente o que ele existe para medir — o que o apressado deixou para trás.
	var relogio_de_medicao := 600.0
	GameManager.tempo_restante = relogio_de_medicao

	# Até o fim do corredor (3040px). Parar antes deixaria as
	# tarefas do trecho final sem registrar e o teste mediria meio expediente.
	await _reta(jogador, Vector2(3000, 160))

	var q3_resolvidas: int = GameManager.acoes_por_tipo[GameManager.Acao.RESOLVER]
	_conferir("Q3 resolvidas na rota baixa", q3_resolvidas, 3)
	_conferir("Q3 delegadas na rota baixa", GameManager.acoes_por_tipo[GameManager.Acao.DELEGAR], 0)
	_conferir("elevador continua trancado sem as Q1", fase.get_node("Saida").liberada, false)

	# As Q1 e Q2 do alto ficaram para trás. Elas precisam aparecer no relatório como
	# "deixadas passar" — sem isso a nota por categoria contaria só acerto, e o dado
	# mais útil para a discussão do TCC (o que o jogador negligenciou) sumiria.
	_conferir("Q1 registradas mesmo sem coletar", GameManager.tarefas_por_categoria[0], 4)
	_conferir("Q1 ignoradas não pontuam", GameManager.pontuacao_por_categoria[0], 0)
	# 4 Q1 + 6 Q2: as duas Q2 novas ficam na rota alta, então quem corre pelo chão
	# nem chega perto delas — que é exatamente o ponto.
	_conferir("tarefas deixadas para trás", GameManager.acoes_por_tipo[GameManager.Acao.IGNOROU], 10)

	# Resolver custa 5s por tarefa, e o Quadro 1 dá 40 pontos em vez de 60.
	_conferir("Q3 valeu 40 por tarefa", GameManager.pontuacao_por_categoria[2], 120)
	var perdeu_tempo: bool = GameManager.tempo_restante < relogio_de_medicao - 15.0
	_conferir("resolver cobrou tempo do expediente", perdeu_tempo, true)

	var bateu: int = GameManager.acoes_por_tipo[GameManager.Acao.COLIDIU]
	_conferir("bateu em pelo menos uma distração", bateu > 0, true)
	# O que o relógio de verdade não aguentaria: 8s por distração atropelada contra um
	# expediente de 60s. É a asserção que trava a fase como "correr reto não é rota".
	_conferir("atropelar as distrações custaria mais que um expediente",
		bateu * 8.0 > fase.tempo_de_expediente(), true)
	_conferir("distrações custaram pontos", GameManager.pontuacao_por_categoria[3] < 0, true)

	# A soma por categoria tem que fechar com o placar agregado — é o que garante que
	# a "nota por categoria" do checklist institucional não é um número paralelo.
	var soma := 0
	for cat in GameManager.Categoria.values():
		soma += GameManager.pontuacao_por_categoria[cat]
	_conferir("soma por categoria = placar total", soma, GameManager.pontuacao_total)

	await _fechar_fase(fase)


## A fase inteira tem que ser ilegível quanto a quadrante antes da ação: mesmo ícone,
## mesma cor, para Q1, Q2 e Q4. Com cor por categoria no ícone o jogador joga pela cor e
## a classificação deixa de existir.
func _cenario_tarefas_anonimas() -> void:
	print("\n--- cenário 3: tarefa nenhuma entrega o próprio quadrante ---")
	var fase := await _abrir_fase()

	var cores := {}
	var recortes := {}
	var categorias := {}
	for t in fase.get_node("Tarefas").get_children():
		cores[t.get_node("Icone").modulate] = true
		recortes[t.get_node("Icone").region_rect] = true
		categorias[t.categoria] = true

	_conferir("categorias diferentes na fase", categorias.size() > 1, true)
	_conferir("todas as tarefas com a mesma cor", cores.size(), 1)
	_conferir("todas as tarefas com o mesmo ícone", recortes.size(), 1)
	_conferir("cor do ícone é neutra", cores.keys()[0], Color("f2f2f2"))

	# A bifurcação Q3 segue a mesma regra pelos dois lados.
	var q3: Node2D = fase.get_node("Bifurcacoes").get_child(0)
	_conferir("lado 'resolver' neutro", q3.get_node("PontoResolver/Icone").modulate, Color("f2f2f2"))
	_conferir("lado 'delegar' neutro", q3.get_node("PontoDelegar/Icone").modulate, Color("f2f2f2"))

	await _fechar_fase(fase)


## O prazo cobra tempo, e só tempo: ele não é uma tarefa da matriz e não pode entrar
## nas notas por categoria que o checklist institucional exige.
func _cenario_prazo() -> void:
	print("\n--- cenário 4: o prazo alcança quem fica parado ---")
	var fase := await _abrir_fase(true)
	var prazo: Node2D = fase.get_node("Inimigos/Prazo")
	var jogador: CharacterBody2D = fase.get_node("Player")

	var x_inicial: float = prazo.global_position.x
	var tarefas_antes: int = _total_registrado()

	# Caixa de um elemento em vez de um bool solto: lambda em GDScript captura variável
	# local POR VALOR, então "alcancou = true" lá dentro não sairia da closure.
	var alcancou := [false]
	prazo.alcancou.connect(func(_custo: float) -> void: alcancou[0] = true)

	# O jogador fica parado de propósito: é exatamente o comportamento que o prazo
	# existe para punir.
	for i in 600:
		jogador.velocity.x = 0.0
		if alcancou[0]:
			break
		await get_tree().physics_frame

	_conferir("o prazo avançou", prazo.global_position.x > x_inicial, true)
	_conferir("o prazo alcançou quem parou", alcancou[0], true)
	_conferir("prazo não vira tarefa da matriz", _total_registrado(), tarefas_antes)

	await _fechar_fase(fase)


## A rota alta (plataformas móveis + as duas Q2 de bônus) só vale a pena se ela for
## de fato alcançável. Os cenários acima teleportam o jogador, então nenhum deles
## provaria que um salto é possível — teleporte chega a qualquer lugar.
##
## Aqui cada degrau da rota é conferido contra a trajetória REAL do pulo, integrada
## com as mesmas constantes do player (velocidade inicial, gravidade assimétrica,
## teto de queda, velocidade máxima), o que pega plataforma "quase" alcançável sem
## precisar jogar.
##
## As posições vêm dos nós da cena, não de números repetidos aqui: mover uma
## plataforma no editor tem que fazer este teste falhar, e não passar em silêncio.
func _cenario_rota_alta_alcancavel() -> void:
	print("\n--- cenário 5: a rota alta cabe no pulo do jogador ---")
	var fase := await _abrir_fase()

	var chao := _degrau_estatico(fase, "Colisores/Chao0")
	var escada_a1 := _degrau_estatico(fase, "Colisores/Plataforma6")
	var escada_a2 := _degrau_estatico(fase, "Colisores/Plataforma7")
	var escada_b1 := _degrau_estatico(fase, "Colisores/Plataforma8")
	var escada_b2 := _degrau_estatico(fase, "Colisores/Plataforma9")
	var mez_a := _degrau_estatico(fase, "Colisores/Mezanino0")
	var mez_c := _degrau_estatico(fase, "Colisores/Mezanino2")
	var mez_d := _degrau_estatico(fase, "Colisores/Mezanino3")
	var andaime := fase.get_node("Moveis/Andaime")

	# Ida: chão -> escada A -> mezanino.
	_conferir_salto("chão -> escada A degrau 1",
		chao["topo"], escada_a1["esquerda"] - 40.0, escada_a1["topo"], escada_a1["esquerda"])
	_conferir_salto("escada A degrau 1 -> degrau 2",
		escada_a1["topo"], escada_a1["direita"], escada_a2["topo"], escada_a2["esquerda"])
	_conferir_salto("escada A degrau 2 -> mezanino",
		escada_a2["topo"], escada_a2["direita"], mez_a["topo"], mez_a["esquerda"])

	# Volta: depois de descer pela passagem de mão única e pegar a Q1 do chão, o jogador
	# sobe pela escada B e entra no mezanino PELO BURACO — daí a chegada ser Mezanino2,
	# que começa depois do vão da escada.
	_conferir_salto("chão -> escada B degrau 1",
		chao["topo"], escada_b1["esquerda"] - 40.0, escada_b1["topo"], escada_b1["esquerda"])
	_conferir_salto("escada B degrau 1 -> degrau 2",
		escada_b1["topo"], escada_b1["direita"], escada_b2["topo"], escada_b2["esquerda"])
	_conferir_salto("escada B degrau 2 -> mezanino pelo buraco",
		escada_b2["topo"], escada_b2["direita"], mez_c["topo"], mez_c["esquerda"])

	# Para uma plataforma móvel o jogador escolhe o instante do salto, então a partida usa
	# o extremo que ele de fato esperaria — mas a CHEGADA usa o extremo desfavorável, para
	# o salto continuar valendo se ele errar o tempo.
	_conferir_salto("mezanino -> plataforma móvel",
		mez_c["topo"], mez_c["direita"], _topo_movel(andaime, true), _esquerda(andaime))
	_conferir_salto("plataforma móvel -> fim do mezanino",
		_topo_movel(andaime, false), _direita(andaime), mez_d["topo"], mez_d["esquerda"])

	# A Q1 do chão do setor 3 é o que impede o jogador de ficar no mezanino até o fim: se
	# ela estivesse ao alcance de quem está lá em cima, a escolha central da fase sumiria.
	_conferir("a Q1 do mezanino NÃO se pega de cima",
		_tarefa_ao_alcance(fase, "Tarefa10", mez_a["topo"]), false)

	# E as Q2 do alto têm que estar ao alcance de quem pagou para subir — senão o
	# investimento seria esforço sem prêmio.
	_conferir("Q2 ao alcance de quem está no mezanino",
		_tarefa_ao_alcance(fase, "Tarefa05", mez_a["topo"]), true)
	_conferir("Q2 ao alcance de quem está na plataforma móvel",
		_tarefa_ao_alcance(fase, "Tarefa08", _topo_movel(andaime, true)), true)

	# O vão da móvel não pode ser pulável, senão ninguém espera o ciclo e ela vira enfeite.
	var vao: float = _esquerda(andaime) - mez_c["direita"] + (mez_d["esquerda"] - _direita(andaime))
	_conferir("o vão da móvel é largo demais para um pulo",
		mez_d["esquerda"] - mez_c["direita"] > _alcance_do_pulo(0.0), true)
	_conferir("e a móvel cobre esse vão", vao <= 0.0, true)

	_conferir("nenhuma plataforma corta uma janela", _plataformas_sobre_janela(fase), [])


	await _fechar_fase(fase)


## Nenhuma plataforma pode ficar na frente de uma janela.
##
## Isto já quebrou duas vezes no projeto: cinco janelas ficaram atrás de plataformas
## estáticas, e as plataformas móveis nasceram cortando outras duas ao meio. É o tipo de erro invisível em teste de lógica e óbvio numa
## foto — então vira asserção, e não "lembrar de olhar depois".
##
## As janelas não estão escritas em lugar nenhum como lista: elas são os VÃOS entre
## os retângulos `Vidro*` da parede (esses retângulos são a parede cheia; onde não há
## parede, vê-se o céu). Derivar daí em vez de repetir as colunas aqui é o que faz o
## teste continuar certo se alguém mover uma janela.
func _plataformas_sobre_janela(fase: Node2D) -> Array:
	var parede: Node2D = fase.get_node("Parede")
	var cheios: Array[Vector2] = []
	var faixa_topo := INF
	var faixa_base := -INF
	for filho in parede.get_children():
		# "Cheia" desde que a fase passou a ser gerada: são os trechos de
		# parede FECHADA, e as janelas são os vãos entre eles. O nome anterior era
		# "Vidro", que dizia o contrário do que o nó é.
		#
		# Este prefixo já esteve errado e o teste passava por vacuidade: não encontrava
		# retângulo nenhum, montava uma lista vazia de janelas e concluía que nada
		# estava sobre janela nenhuma. Daí a asserção logo abaixo de que existe janela.
		if not filho.name.begins_with("Cheia"):
			continue
		var r: ColorRect = filho
		cheios.append(Vector2(r.position.x, r.position.x + r.size.x))
		faixa_topo = minf(faixa_topo, r.position.y)
		faixa_base = maxf(faixa_base, r.position.y + r.size.y)
	cheios.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	var janelas: Array[Vector2] = []
	for i in range(cheios.size() - 1):
		if cheios[i + 1].x > cheios[i].y:
			janelas.append(Vector2(cheios[i].y, cheios[i + 1].x))

	# Sem isto, um prefixo errado transforma este teste inteiro em decoração silenciosa.
	_conferir("o teste achou janelas para conferir", janelas.size() > 0, true)

	var culpadas := []
	for p in fase.get_node("Moveis").get_children():
		var esq := _esquerda(p)
		var dir := _direita(p)
		# Extremos verticais que o corpo da plataforma chega a ocupar.
		var alto: float = _topo_movel(p, true)
		var baixo: float = _topo_movel(p, false) + p.meia_extensao.y * 2.0
		if baixo < faixa_topo or alto > faixa_base:
			continue
		for j in janelas:
			if dir > j.x and esq < j.y:
				culpadas.append("%s sobre a janela %d..%d" % [p.name, int(j.x), int(j.y)])
				break
	return culpadas


## Integra a trajetória do pulo com as constantes reais do player e devolve a maior
## distância horizontal disponível para chegar a um degrau `subida` pixels acima do
## ponto de partida (subida negativa = degrau mais baixo). -1 se o pulo não alcança
## aquela altura de jeito nenhum.
func _alcance_do_pulo(subida: float) -> float:
	var gravidade: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
	var altura := 0.0
	var vertical := -350.0  # player.gd: JUMP_VELOCITY
	var t := 0.0
	var passo := 1.0 / 60.0
	var alcance := -1.0

	while t < 3.0:
		# Mesma assimetria de player.gd: sobe com a gravidade nominal, cai a 1.45x.
		var fator := 1.45 if vertical > 0.0 else 1.0
		vertical = minf(vertical + gravidade * fator * passo, 460.0)
		altura += vertical * passo
		t += passo
		if -altura >= subida:
			alcance = 180.0 * t  # player.gd: max_speed
	return alcance


func _conferir_salto(
	rotulo: String, topo_origem: float, x_origem: float, topo_destino: float, x_destino: float
) -> void:
	var subida := topo_origem - topo_destino
	var distancia := x_destino - x_origem
	var alcance := _alcance_do_pulo(subida)
	var cabe := alcance >= distancia
	if cabe:
		print("  ok     %s: sobe %.0fpx, vence %.0fpx (pulo alcança %.0fpx)"
			% [rotulo, subida, distancia, alcance])
	else:
		falhas += 1
		print("  FALHA  %s: sobe %.0fpx e precisa vencer %.0fpx, mas o pulo só alcança %.0fpx"
			% [rotulo, subida, distancia, alcance])


## Topo e bordas de um StaticBody2D do grupo Colisores.
func _degrau_estatico(fase: Node2D, caminho: String) -> Dictionary:
	var corpo: StaticBody2D = fase.get_node(caminho)
	var forma: RectangleShape2D = corpo.get_node("CollisionShape2D").shape
	var meia := forma.size * 0.5
	return {
		"topo": corpo.global_position.y - meia.y,
		"esquerda": corpo.global_position.x - meia.x,
		"direita": corpo.global_position.x + meia.x,
	}


## Topo de uma plataforma móvel no extremo alto (`em_cima`) ou baixo do curso dela.
func _topo_movel(plataforma: Node2D, em_cima: bool) -> float:
	var origem: float = plataforma.position.y
	var curso: float = plataforma.curso.y
	var extremos := [origem + curso, origem - curso]
	var centro: float = extremos.min() if em_cima else extremos.max()
	return centro - plataforma.meia_extensao.y


func _esquerda(plataforma: Node2D) -> float:
	return plataforma.position.x - absf(plataforma.curso.x) - plataforma.meia_extensao.x


func _direita(plataforma: Node2D) -> float:
	return plataforma.position.x + absf(plataforma.curso.x) + plataforma.meia_extensao.x


## A tarefa encosta em quem está de pé sobre uma superfície na altura `topo`?
## O corpo do jogador vai de -2 a +16 em torno da origem (cápsula de player.tscn), e
## o raio de contato da tarefa é 8 (scenes/tasks/tarefa.tscn).
func _tarefa_ao_alcance(fase: Node2D, nome: String, topo: float) -> bool:
	var tarefa: Node2D = fase.get_node("Tarefas/" + nome)
	var origem_jogador := topo - 16.0
	var corpo_de := origem_jogador - 2.0
	var corpo_ate := origem_jogador + 16.0
	# posicao_base() e não position: toda tarefa oscila, e `position`
	# devolve um ponto qualquer do ciclo. Medir a base torna o resultado determinístico —
	# o balanço só adiciona uma margem que o jogador pode esperar.
	var centro: float = tarefa.posicao_base().y
	return corpo_de <= centro + 8.0 and centro - 8.0 <= corpo_ate


## O urso é a principal fonte de tensão da fase, então os três comportamentos que
## sustentam essa tensão são travados por teste: ele acorda, acelera quando o jogador
## para de avançar, e recua depois de acertar (que é o respiro do ritmo — sem ele a
## punição encadearia e o jogador não sairia mais do buraco).
func _cenario_urso_pressiona() -> void:
	print("\n--- cenário 6: o urso pressiona e depois dá respiro ---")
	var fase := await _abrir_fase(true)
	var urso: Node2D = fase.get_node("Inimigos/Prazo")
	var jogador: CharacterBody2D = fase.get_node("Player")

	_conferir("começa dormindo", urso.estado, urso.Estado.DORMINDO)

	# E com os pés no chão, conferido antes de ele andar.
	#
	# O urso não tem gravidade: prazo.gd move a posição direto, sem move_and_slide, então
	# ele fica para sempre na altura que a cena disser — inclusive flutuando, se a cena
	# usar a origem do jogador (16px acima dos pés dele). Medir o colisor contra o piso é
	# o que fecha essa porta.
	var colisor_urso: CollisionShape2D = urso.get_node("CollisionShape2D")
	var forma_urso: RectangleShape2D = colisor_urso.shape
	var pes_do_urso := urso.global_position.y + colisor_urso.position.y + forma_urso.size.y * 0.5
	# Tipo explícito: indexar um Dictionary devolve Variant, e o modo estrito do GDScript
	# não infere a partir disso.
	var topo_do_piso: float = _degrau_estatico(fase, "Colisores/Chao0")["topo"]
	_conferir("nasce com os pés no chão", absf(pes_do_urso - topo_do_piso) <= 2.0, true)

	# Longe do urso, parado: ele acorda e, passada a paciência, entra em faro.
	jogador.global_position = Vector2(900, 160)
	var acordou := [false]
	urso.acordou.connect(func() -> void: acordou[0] = true)
	await _esperar_ate(func() -> bool: return acordou[0], 400)
	_conferir("acordou sozinho", acordou[0], true)

	var x_antes: float = urso.global_position.x
	await _esperar_ate(func() -> bool: return urso.estado == urso.Estado.FARO, 400)
	_conferir("fareja quem parou de avançar", urso.estado, urso.Estado.FARO)
	_conferir("e avança enquanto fareja", urso.global_position.x > x_antes, true)

	# A arte do Grizzly olha para a ESQUERDA (ver a constante em prazo.gd), e ele
	# persegue para a direita: o estado normal dele é espelhado. Virado ao contrário, a
	# ameaça fica ilegível na tela, e teste de lógica não vê isso.
	var sprite: AnimatedSprite2D = urso.get_node("AnimatedSprite2D")
	_conferir("encara o lado para onde persegue", sprite.flip_h, urso.ARTE_OLHA_PARA_ESQUERDA)

	# Avançar de novo tem que desligar o faro: a pressão é sobre a hesitação, não
	# uma punição permanente por ter hesitado uma vez.
	#
	# O jogador precisa ANDAR, não ser teleportado para perto do urso: a hesitação é
	# medida contra o avanço máximo já alcançado, então voltar atrás (ou parar num
	# ponto que já foi ultrapassado) continua contando como parado — de propósito,
	# senão bastaria correr para trás e para a frente para zerar a pressão.
	for i in 400:
		if urso.estado == urso.Estado.CACANDO:
			break
		jogador.global_position.x += 3.0  # 180px/s = velocidade de corrida real
		await get_tree().physics_frame
	_conferir("alivia quando o jogador volta a andar", urso.estado, urso.Estado.CACANDO)

	# Perseguir de VERDADE: o jogador atrás do urso tem que fazê-lo dar meia-volta. Um
	# urso que só anda para a direita é ultrapassado por quem volta um pouco, e vira
	# paisagem.
	jogador.global_position.x = urso.global_position.x - 300.0
	var x_virada: float = urso.global_position.x
	await _esperar_ate(func() -> bool: return urso.global_position.x < x_virada - 20.0, 400)
	_conferir("volta atrás quando o jogador fica para trás",
		urso.global_position.x < x_virada, true)

	var sprite2: AnimatedSprite2D = urso.get_node("AnimatedSprite2D")
	_conferir("e vira o corpo para o lado certo ao voltar",
		sprite2.flip_h, not urso.ARTE_OLHA_PARA_ESQUERDA)

	# Encostar: cobra tempo e manda o urso para o recuo.
	#
	# O jogador é afastado e a invulnerabilidade é esperada ANTES de encostar de
	# propósito. Perseguindo nos dois sentidos, o urso encosta sozinho no meio da
	# aproximação do passo anterior; sem esta pausa o teste mede um acerto que já
	# aconteceu, com o urso três estados adiante.
	# 900px para o lado que couber DENTRO do corredor. Somar 900 sempre jogava o jogador
	# para fora dos 3040px da fase, e aí a ZonaDeQueda o devolvia ao checkpoint no meio
	# da preparação: o teste seguia medindo um encontro que nunca ia acontecer.
	var longe: float = urso.global_position.x + 900.0
	if longe > 2900.0:
		longe = urso.global_position.x - 900.0
	jogador.global_position = Vector2(clampf(longe, 100.0, 2900.0), 160.0)
	for i in 150:
		await get_tree().physics_frame

	var tempo_antes: float = GameManager.tempo_restante

	# O que se mede aqui é gravado NO INSTANTE do acerto, não depois.
	#
	# A versão anterior teleportava o jogador para a esquerda do urso e conferia o sinal
	# da velocidade e o estado alguns frames depois. Isso é frágil de duas maneiras: o
	# urso persegue nos dois sentidos e pode ter cruzado o jogador antes do contato, e
	# o RECUO é um estado com duração — conferi-lo tarde demais lê o estado seguinte.
	# Na prática as falhas trocavam de lugar entre execuções conforme o tamanho da fase.
	#
	# O invariante de verdade não depende do lado: o empurrão é sempre para LONGE do
	# urso. Então grava-se o lado e a velocidade no mesmo instante e compara-se o sinal.
	var acerto := {"houve": false, "lado": 0.0, "empurrao": 0.0, "custo": 0.0}
	# O lado é gravado no instante do sinal, porque é aí que ele é verdade. O empurrão
	# NÃO: prazo.gd emite `alcancou` antes de aplicar a velocidade, então lê-lo aqui
	# devolveria a velocidade anterior ao empurrão. Ele é medido no frame seguinte.
	urso.alcancou.connect(func(custo: float) -> void:
		acerto["houve"] = true
		acerto["custo"] = custo
		acerto["lado"] = signf(jogador.global_position.x - urso.global_position.x)
	)

	# A invulnerabilidade tem que escoar ANTES de aproximar o jogador.
	#
	# `alcancou` sai de um body_entered, que só dispara na ENTRADA da hurtbox. Se o
	# jogador for colocado lá dentro enquanto _espera_dano ainda corre, o acerto é
	# descartado — e não haverá segunda chance, porque ele já está dentro e nunca mais
	# entra. Era exatamente isso que fazia este cenário falhar: o urso encostava no
	# jogador durante o passo anterior, ficava invulnerável por 1,6s, e o teste então o
	# encostava de novo dentro dessa janela.
	for i in 300:
		if urso._espera_dano <= 0.0:
			break
		await get_tree().physics_frame

	# O jogador é POSTO NO CAMINHO e fica parado; quem encosta é o urso, andando.
	#
	# A versão anterior o teleportava para 6px do urso, e isso é frágil de duas maneiras:
	# a hurtbox fica 12px acima da origem do bicho (entities/prazo.tscn), então "mesma
	# posição" não garante sobreposição; e teleportar para dentro de uma Area2D depende de
	# o corpo ter saído dela antes, senão não há entrada nova. Deixar o urso vir é o que
	# um jogador parado de fato provoca — e é o comportamento que este cenário existe
	# para provar.
	var lado := 1.0 if urso.global_position.x < 2600.0 else -1.0
	jogador.global_position = Vector2(urso.global_position.x + 220.0 * lado, 160.0)
	var viu_recuo := [false]
	var medido := false
	for i in 900:
		if urso.estado == urso.Estado.RECUO:
			viu_recuo[0] = true
		# Um frame depois do sinal: já com o empurrão aplicado e antes de o atrito do
		# chão comer a velocidade.
		if acerto["houve"] and not medido:
			acerto["empurrao"] = jogador.velocity.x
			medido = true
		if medido and viu_recuo[0]:
			break
		await get_tree().physics_frame

	if not acerto["houve"]:
		print("        urso em x=%.0f (estado %d), jogador em x=%.0f"
			% [urso.global_position.x, urso.estado, jogador.global_position.x])

	_conferir("o urso encostou", acerto["houve"], true)
	# O custo vem do sinal, e não de comparar o relógio: o cronômetro do expediente corre
	# sozinho, então "o tempo diminuiu" seria verdade mesmo sem urso nenhum.
	_conferir("o acerto custou tempo", acerto["custo"] > 0.0, true)
	_conferir("e o desconto chegou ao cronômetro",
		GameManager.tempo_restante <= tempo_antes - acerto["custo"], true)
	# O `houve` na frente não é redundância: sem ele, um cenário em que nada acontece
	# compara signf(0.0) com 0.0, dá verdadeiro e a asserção passa sem ter medido nada.
	_conferir("empurrou o jogador para LONGE do urso",
		acerto["houve"] and signf(acerto["empurrao"]) == acerto["lado"], true)
	_conferir("recua depois de acertar", viu_recuo[0], true)

	await _fechar_fase(fase)


## O único cenário em que ninguém teleporta nada: um robô simplório segura "direita"
## e pula quando bate numa parede ou quando o chão some à frente. Ele tem que chegar
## ao fim do corredor.
##
## Por que isto importa mais do que parece: todos os outros cenários movem o jogador
## por atribuição de posição, e teleporte atravessa qualquer geometria. Nenhum deles
## detectaria uma parede intransponível, um vão largo demais para o pulo ou uma
## plataforma que empurra o jogador para dentro de um colisor. Este detecta, porque
## usa a física de verdade e as MESMAS teclas do jogador humano.
##
## O robô é de propósito burro (nem tenta a rota alta, nem desvia de distração): se
## até ele atravessa, um humano atravessa. Se ele emperra, tem geometria quebrada.
func _cenario_percurso_a_pe() -> void:
	print("\n--- cenário 7: dá para atravessar o corredor correndo e pulando ---")
	var fase := await _abrir_fase()
	var jogador: CharacterBody2D = fase.get_node("Player")
	var saida: Node2D = fase.get_node("Saida")

	# Sem cronômetro: o objetivo aqui é geometria, e um teste que falha porque o
	# headless rodou devagar não diz nada sobre o level design.
	GameManager.em_jogo = false

	Input.action_press("right")
	var chegou := false
	var x_maximo: float = jogador.global_position.x
	var travado := 0

	# 4200 passos de física ≈ 70s de jogo, folgado sobre os ~15s que o percurso leva.
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
		# Preso no mesmo lugar por 3s seguidos com "direita" pressionado só acontece
		# se a geometria estiver bloqueando de verdade.
		if travado > 180:
			break

	Input.action_release("right")
	Input.action_release("jump")

	_conferir("o robô atravessou o corredor a pé", chegou, true)
	if not chegou:
		print("        travou em x=%.0f (a saída fica em x=%.0f)"
			% [x_maximo, saida.global_position.x])

	await _fechar_fase(fase)


## Pula quando encosta numa parede ou quando não há chão logo à frente. É a lógica
## mínima que um jogador humano usa por instinto.
## O briefing de abertura anuncia quantas tarefas e quantos segundos o dia tem, e ele roda
## ANTES de a fase existir — então lê de uma tabela em GameManager em vez de perguntar à
## cena. Toda tabela repetida diverge um dia; este cenário é o que impede que a divergência
## chegue ao jogador como número errado logo na primeira tela.
func _cenario_briefing() -> void:
	print("\n--- cenário 9: o briefing não mente sobre o dia ---")
	for dia in GameManager.CENA_DO_DIA:
		var cena: PackedScene = load(GameManager.CENA_DO_DIA[dia])
		var fase: Node2D = cena.instantiate()
		add_child(fase)
		await get_tree().process_frame
		await get_tree().process_frame

		var total := 0
		for categoria in fase.composicao:
			total += int(fase.composicao[categoria])

		_conferir("dia %d: total de tarefas" % dia, GameManager.TAREFAS_DO_DIA[dia], total)
		_conferir("dia %d: duração do expediente" % dia,
			GameManager.SEGUNDOS_DO_DIA[dia], fase.tempo_de_expediente())

		fase.queue_free()
		await get_tree().process_frame
	# Sai do estado de "em jogo" em que a última fase instanciada deixou o GameManager.
	GameManager.finalizar_fase(false)


func _precisa_pular(jogador: CharacterBody2D) -> bool:
	if not jogador.is_on_floor():
		return false
	if jogador.is_on_wall():
		return true

	# Sonda o chão 20px à frente dos pés. Se não achar nada em 24px para baixo, é
	# borda de plataforma ou vão: pula.
	var espaco := jogador.get_world_2d().direct_space_state
	var pe := jogador.global_position + Vector2(20, 16)
	var consulta := PhysicsRayQueryParameters2D.create(pe, pe + Vector2(0, 24))
	consulta.exclude = [jogador.get_rid()]
	return espaco.intersect_ray(consulta).is_empty()


## Espera uma condição virar verdadeira, com teto de frames para o teste nunca
## travar se o comportamento quebrar.
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


## `com_prazo` = false tira o perseguidor da cena. Os dois percursos de pontuação
## teleportam o jogador, e um encostão do prazo no meio do caminho tiraria segundos
## em momentos que dependem de quantos frames o headless rodou — o que testaria a
## máquina, não a regra. O prazo tem cenário próprio, logo abaixo.
## Os setores anunciados dos dois dias. É leitura, não regra — mas uma fronteira digitada
## fora do corredor, ou fora de ordem, some em silêncio: o setor simplesmente nunca é
## anunciado, e ninguém percebe olhando o jogo rodar.
func _cenario_setores() -> void:
	print("\n--- cenário 13: os setores anunciados ---")

	for dia in [1, 2]:
		var cena: PackedScene = load(GameManager.CENA_DO_DIA[dia])
		var fase: Node2D = cena.instantiate()
		add_child(fase)
		await get_tree().process_frame
		await get_tree().process_frame

		var lista: Array = fase.setores()
		var inicio: float = fase.progresso(fase.get_node("Player").global_position)
		var fim: float = fase.progresso(fase.get_node("Saida").global_position)

		_conferir("dia %d tem setores anunciados" % dia, lista.size() > 0, true)

		var em_ordem := true
		var dentro := true
		var completos := true
		var anterior := inicio
		for setor in lista:
			var em: float = float(setor["em"])
			if em <= anterior:
				em_ordem = false
			anterior = em
			# Um setor além da saída nunca é alcançado; um antes do início do corredor é
			# anunciado no primeiro quadro, por cima da mensagem de abertura.
			if em <= inicio or em >= fim:
				dentro = false
			if str(setor.get("nome", "")).is_empty() or str(setor.get("dica", "")).is_empty():
				completos = false

		_conferir("dia %d: fronteiras em ordem crescente" % dia, em_ordem, true)
		_conferir("dia %d: toda fronteira cai dentro do corredor" % dia, dentro, true)
		_conferir("dia %d: todo setor tem nome e dica" % dia, completos, true)

		# E o jogador atravessa todos eles: se um setor ficar fora do alcance do percurso,
		# ele é decoração morta no código.
		var jogador: CharacterBody2D = fase.get_node("Player")
		jogador.global_position = fase.get_node("Saida").global_position
		fase._anunciar_setor()
		_conferir("dia %d: todos foram anunciados ao chegar na saída" % dia,
			fase._setor_atual, lista.size())

		get_tree().paused = false
		fase.queue_free()
		await get_tree().process_frame


## As duas pontas do corredor são fechadas, e as habilidades do último dia continuam
## desligadas aqui: a geometria dos Dias 1 e 2 foi validada contra um pulo só.
func _cenario_bordas() -> void:
	print("\n--- cenário 14: o corredor tem fim dos dois lados ---")

	for cena in [CENA_FASE, preload("res://scenes/level/fase_02.tscn")]:
		var fase: Node2D = cena.instantiate()
		add_child(fase)
		await get_tree().process_frame
		await get_tree().process_frame

		var dia: int = fase.numero_do_dia()
		var colisores: Node2D = fase.get_node("Colisores")
		_conferir("dia %d fecha a ponta esquerda" % dia,
			colisores.has_node("BordaEsquerda"), true)
		_conferir("dia %d fecha a ponta direita" % dia,
			colisores.has_node("BordaDireita"), true)

		var jogador: CharacterBody2D = fase.get_node("Player")
		_conferir("dia %d não oferece pulo duplo" % dia, jogador.pulo_duplo, false)
		_conferir("dia %d não oferece arranque" % dia, jogador.arranque, false)

		# Correndo contra a parede da esquerda por meio segundo, ele não sai do corredor.
		jogador.global_position = Vector2(24, 160)
		for _i in 30:
			Input.action_press("left")
			await get_tree().physics_frame
		Input.action_release("left")
		_conferir("dia %d segura o jogador dentro do mapa" % dia,
			jogador.global_position.x > -16.0, true)

		get_tree().paused = false
		fase.queue_free()
		await get_tree().process_frame


## O sorteio de enunciados não pode repetir texto dentro do estoque nem entregar uma Q2
## sem a crise em que ela se transforma — sem o par, a maturação do Dia 2 fica muda.
func _cenario_enunciados() -> void:
	print("\n--- cenário 15: os enunciados são sorteados ---")

	const Enunciados := preload("res://scripts/enunciados.gd")
	var C := GameManager.Categoria

	Enunciados.embaralhar()
	var vistos := {}
	var estoque: int = (Enunciados.POR_CATEGORIA[C.URGENTE_IMPORTANTE] as Array).size()
	for _i in estoque:
		vistos[Enunciados.sacar(C.URGENTE_IMPORTANTE)[0]] = true
	_conferir("o saco de urgentes não repete", vistos.size(), estoque)

	Enunciados.embaralhar()
	var sem_crise := 0
	for _i in (Enunciados.POR_CATEGORIA[C.IMPORTANTE_NAO_URGENTE] as Array).size():
		if Enunciados.sacar(C.IMPORTANTE_NAO_URGENTE)[1].is_empty():
			sem_crise += 1
	_conferir("toda importante traz a crise dela", sem_crise, 0)

	# Duas partidas seguidas não podem apresentar a mesma ordem, senão decorar volta a
	# substituir ler.
	var primeira: Array[String] = []
	var segunda: Array[String] = []
	Enunciados.embaralhar()
	for _i in 8:
		primeira.append(Enunciados.sacar(C.NAO_URGENTE_NAO_IMPORTANTE)[0])
	Enunciados.embaralhar()
	for _i in 8:
		segunda.append(Enunciados.sacar(C.NAO_URGENTE_NAO_IMPORTANTE)[0])
	_conferir("duas partidas não trazem a mesma ordem", primeira == segunda, false)


func _abrir_fase(com_prazo: bool = false) -> Node2D:
	var fase: Node2D = CENA_FASE.instantiate()
	add_child(fase)
	await get_tree().process_frame
	await get_tree().process_frame
	if not com_prazo:
		fase.get_node("Inimigos/Prazo").queue_free()
		await get_tree().process_frame
	return fase


func _fechar_fase(fase: Node2D) -> void:
	# fase_01.gd pausa a árvore ao terminar; sem despausar o próximo cenário congela.
	get_tree().paused = false
	fase.queue_free()
	await get_tree().process_frame


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


## Cenário 8: o crachá. Etapa 6 (campo de nickname na tela de título) e pré-requisito
## da Etapa 7 — sem um nome válido não há linha para gravar no ranking.
##
## Exercita o autoload de verdade, não um mock, pelo mesmo motivo dos outros cenários:
## é este objeto que a Etapa 7 vai usar. Não passa pela tela: a regra mora no Perfil
## justamente para poder ser testada sem instanciar interface.
func _cenario_perfil() -> void:
	print("\n--- cenário 8: crachá do jogador ---")

	_conferir("nome comum aceito", Perfil.validar("Kleytonn"), "Kleytonn")
	_conferir("espaços das bordas aparados", Perfil.validar("  Ana  "), "Ana")
	_conferir("vazio rejeitado", Perfil.validar(""), "")
	_conferir("só espaços rejeitado", Perfil.validar("    "), "")
	_conferir("1 caractere rejeitado", Perfil.validar("K"), "")
	_conferir("mínimo (2) aceito", Perfil.validar("Ke"), "Ke")
	_conferir("máximo (16) aceito", Perfil.validar("ABCDEFGHIJKLMNOP"), "ABCDEFGHIJKLMNOP")
	_conferir("17 caracteres rejeitado", Perfil.validar("ABCDEFGHIJKLMNOPQ"), "")

	# definir() só aceita o que validar() aprova, e não suja o estado quando recusa.
	var anterior := Perfil.nickname
	_conferir("definir recusa inválido", Perfil.definir("x"), false)
	_conferir("nickname intacto após recusa", Perfil.nickname, anterior)
	_conferir("definir aceita válido", Perfil.definir("  Teste  "), true)
	_conferir("definir apara ao guardar", Perfil.nickname, "Teste")

	# Ciclo completo: gravar em user://, esquecer, e recuperar do disco.
	Perfil.salvar()
	Perfil.nickname = ""
	_conferir("carregar devolve o gravado", Perfil.carregar(), "Teste")

	# Perfil ausente não pode impedir o jogo de abrir.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Perfil.CAMINHO))
	_conferir("sem arquivo devolve vazio", Perfil.carregar(), "")


func _conferir(rotulo: String, obtido: Variant, esperado: Variant) -> void:
	if obtido == esperado:
		print("  ok     %s = %s" % [rotulo, str(obtido)])
	else:
		falhas += 1
		print("  FALHA  %s: esperado %s, obtido %s" % [rotulo, str(esperado), str(obtido)])


## Cenário 10: o colega. Etapa 4 da Metodologia, e a trava da mecânica de delegar.
##
## Sem ele, delegar uma Q3 vale +60 contra +40 de resolver e mais nada — vinte pontos
## num placar de mil, que ninguém sobe numa bandeja para ganhar. O que este cenário
## protege é que delegar MUDE O CORREDOR, e que a posição escolhida para cada alvo
## produza mesmo o comportamento que o design pediu.
##
## A conta que decide isso (design, seção 6.1) é conferida duas vezes de propósito: aqui,
## contra os nós reais da cena, e no validador de tools/gerar_fase_01.py, contra a tabela
## de layout. Uma checa o que foi gerado; a outra impede que se gere errado.
func _cenario_colega() -> void:
	print("\n--- cenário 10: o colega assume o que foi delegado ---")
	var fase := await _abrir_fase()
	var jogador: CharacterBody2D = fase.get_node("Player")

	var colegas := fase.get_node("Colegas").get_children()
	_conferir("um colega por bifurcação Q3", colegas.size(),
		fase.get_node("Bifurcacoes").get_child_count())

	var escada: StaticBody2D = fase.get_node("Colisores/EscadaDelegada")
	var colisor_escada: CollisionShape2D = escada.get_node("CollisionShape2D")
	_conferir("a escada do arquivo nasce sem colisão", colisor_escada.disabled, true)

	# A promessa da fase: não existem 1.060 pontos sem delegar. Se a última Q2 estiver ao
	# alcance de um pulo do chão, a promessa é falsa e o colega vira enfeite — e nada no
	# jogo denunciaria isso, porque a fase continuaria funcionando perfeitamente.
	#
	# Um jogador em pé no piso tem a origem em y=160 e o corpo indo de origem−2 a
	# origem+16; no ápice do pulo a origem sobe 62,5px, ou seja, o alto da cabeça chega a
	# y=95,5. A tarefa tem raio de contato 8. Só há encosto se a base dela descer até a
	# cabeça.
	var q2_final := _q2_da_escada(fase)
	var topo_do_corpo := 176.0 - 16.0 - 62.5 - 2.0
	_conferir("a última Q2 é inalcançável sem a escada",
		q2_final.posicao_base().y + 8.0 < topo_do_corpo, true)

	# --- resolver não despacha ninguém ---
	#
	# Pelo chão, e não com _levar(): descer em cima da bifurcação atravessa o gatilho de
	# DELEGAR (y 92..112) antes de chegar ao de RESOLVER (y 118..174), e o cenário
	# provaria o contrário do que quer provar.
	await _levar(jogador, Vector2(1100, 150))
	await _reta(jogador, Vector2(1200, 150))
	_conferir("resolver deixa o colega sentado", colegas[0].estado, 0)  # Estado.SENTADO

	# --- delegar despacha, e ele chega ---
	#
	# O jogador é posto DE PÉ NA BANDEJA, ao lado do colega, e não teleportado para dentro
	# do gatilho: é o único jeito de reproduzir o que um humano faz. Teleporte desce por
	# cima do gatilho e passa mesmo com ele mal posicionado.
	var q3c: Node2D = fase.get_node("Bifurcacoes/Q3c")
	var tabua := _degrau_estatico(fase, "Colisores/Plataforma13")

	# Medida antes do comportamento: quanto do gatilho de DELEGAR o corpo de quem está EM
	# PÉ na bandeja realmente ocupa. Um jogador parado ali tem o corpo indo de topo-18 a
	# topo (origem em topo-16, cápsula de -2 a +16).
	#
	# Asserção de geometria, e não de comportamento: um gatilho pequeno e deslocado da
	# bandeja escapa do teste de comportamento, porque o teleporte cai dentro dele. O que
	# precisa valer é que o colega esteja DENTRO da área que dispara a delegação.
	var gatilho: CollisionShape2D = q3c.get_node("PontoDelegar/CollisionShape2D")
	# Sem exigir um tipo de forma: esta asserção precisa MEDIR o gatilho, inclusive quando
	# alguém o trocar de volta por um círculo. Uma versão anterior declarava
	# RectangleShape2D e, com o círculo no lugar, estourava em vez de acusar — o cenário
	# morria no meio e as falhas apareciam nos cenários seguintes, sem relação nenhuma.
	var meia := Vector2.ZERO
	if gatilho.shape is RectangleShape2D:
		meia = (gatilho.shape as RectangleShape2D).size * 0.5
	elif gatilho.shape is CircleShape2D:
		meia = Vector2.ONE * (gatilho.shape as CircleShape2D).radius
	var g_cima := gatilho.global_position.y - meia.y
	var g_baixo := gatilho.global_position.y + meia.y
	var corpo_cima: float = tabua["topo"] - 18.0
	var sobreposicao: float = minf(g_baixo, tabua["topo"]) - maxf(g_cima, corpo_cima)
	_conferir("quem está de pé na bandeja ocupa o gatilho de verdade",
		sobreposicao >= 8.0, true)

	var folga_x := minf(
		colegas[2].global_position.x - (gatilho.global_position.x - meia.x),
		(gatilho.global_position.x + meia.x) - colegas[2].global_position.x)
	_conferir("e o colega fica dentro do gatilho, com folga", folga_x >= 8.0, true)

	# Os dois gatilhos da Q3 não podem se tocar.
	#
	# Achado com o jogo rodando: o de RESOLVER era 28x56 e chegava a 16px
	# DENTRO do de DELEGAR. Quem subia na bandeja entrava nos dois no mesmo quadro, e o
	# primeiro sinal processado decidia a tarefa — subir para delegar registrava RESOLVER
	# boa parte das vezes, e o colega ficava sentado sem que nada denunciasse o motivo.
	#
	# É asserção de GEOMETRIA porque o defeito é geométrico e intermitente: um teste de
	# comportamento passa ou falha conforme a ordem em que o servidor de física entrega
	# os dois body_entered daquele quadro.
	var resolver: CollisionShape2D = q3c.get_node("PontoResolver/CollisionShape2D")
	var meia_r: float = (resolver.shape as RectangleShape2D).size.y * 0.5
	_conferir("os gatilhos de delegar e resolver não se sobrepõem",
		resolver.global_position.y - meia_r >= g_baixo, true)
	# E o de resolver continua pegando quem corre pelo chão (corpo em y 158..176).
	_conferir("resolver ainda pega quem passa correndo",
		resolver.global_position.y + meia_r >= 176.0
		and resolver.global_position.y - meia_r <= 158.0, true)

	# Agora o comportamento, chegando PELA LATERAL. Descer em cima do gatilho o dispara no
	# ar, o que provaria só que o pulo funciona.
	await _levar(jogador, Vector2(tabua["esquerda"] + 8.0, tabua["topo"] - 16.0))
	_conferir("pousar na ponta da bandeja ainda não delega",
		colegas[2].esta_a_caminho(), false)
	await _reta(jogador, Vector2(colegas[2].global_position.x, tabua["topo"] - 16.0))
	_conferir("andar até o colega delega", colegas[2].esta_a_caminho(), true)

	var alvo: Node2D = fase.get_node("Delegacoes/EscadaDelegada")
	_conferir("e o alvo ainda não abriu", alvo.esta_aberto(), false)

	# 260px a 140px/s = 1,9s, mais o pulinho de descida. 300 quadros de física (5s) é
	# folga de sobra; esperar por condição, e não por contagem fixa, evita que a suíte
	# fique refém da taxa de quadros da máquina.
	await _esperar_ate(func() -> bool: return alvo.esta_aberto(), 300)
	_conferir("o colega chegou ao alvo", colegas[2].ja_chegou(), true)
	_conferir("e a escada do arquivo ficou sólida", colisor_escada.disabled, false)

	# --- assumir uma distração é EVITOU, não pontuação nova ---
	var evitou_antes: int = GameManager.acoes_por_tipo[GameManager.Acao.EVITOU]
	var ignorou_antes: int = GameManager.acoes_por_tipo[GameManager.Acao.IGNOROU]
	var pontos_antes := GameManager.pontuacao_total
	var reuniao: Node2D = fase.get_node("Delegacoes/ReuniaoAssumida")
	var assumidas: int = reuniao.tarefas_assumidas.size()
	_conferir("a reunião assumida tira duas distrações", assumidas, 2)

	reuniao.acionar()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_conferir("as distrações assumidas contam como evitadas",
		GameManager.acoes_por_tipo[GameManager.Acao.EVITOU], evitou_antes + assumidas)
	_conferir("e não valem ponto nenhum", GameManager.pontuacao_total, pontos_antes)
	# Comparação com o ANTES, e não com zero: o robô chegou aqui teleportado até o fim do
	# corredor, então já deixou tarefas para trás por conta própria. O que precisa ser
	# verdade é que assumir não transforma nenhuma delas em "deixou passar" — seria o
	# colega estragando a nota de quem delegou.
	_conferir("assumir não gera 'deixou passar'",
		GameManager.acoes_por_tipo[GameManager.Acao.IGNOROU], ignorou_antes)

	# --- a conta dos 630px, sobre os nós reais ---
	#
	# limite = dianteira x v_colega x v_jogador / (v_jogador - v_colega). Alvo mais perto
	# que isso abre para qualquer um; mais longe que isso só abre para quem se desviou no
	# caminho. É contraintuitivo — a dianteira domina no curto, a velocidade no longo — e
	# é por isso que precisa de asserção: uma mudança inocente de posição inverteria o
	# papel de um alvo sem quebrar nada visível.
	var limite := 1.0 * 140.0 * 180.0 / (180.0 - 140.0)
	var esperado := {"CorredorAssumido": false, "ReuniaoAssumida": true, "EscadaDelegada": true}
	for i in colegas.size():
		var bandeja: Node2D = fase.get_node("Bifurcacoes").get_child(i)
		var destino: Node2D = colegas[i].get_node(colegas[i].alvo)
		var d: float = absf(destino.global_position.x - bandeja.global_position.x)
		_conferir("%s: paga sem desvio" % destino.name, d < limite, esperado[destino.name])

	await _fechar_fase(fase)


## A Q2 que a EscadaDelegada destranca: a tarefa mais alta que fica na coluna do alvo do
## terceiro colega. Procurada pela posição do alvo, e não por índice fixo, para que mexer
## na ordem da tabela de tarefas não transforme esta asserção num teste de outra coisa.
func _q2_da_escada(fase: Node2D) -> Node2D:
	var alvo: Node2D = fase.get_node("Delegacoes/EscadaDelegada")
	var melhor: Node2D = null
	for t in fase.get_node("Tarefas").get_children():
		if not t.has_method("posicao_base"):
			continue
		if absf(t.posicao_base().x - alvo.global_position.x) > 64.0:
			continue
		if melhor == null or t.posicao_base().y < melhor.posicao_base().y:
			melhor = t
	return melhor


## Cenário 11: a pasta. O trabalho em andamento pesa, e delegar é a única ação que não pesa.
##
## Duas coisas aqui não são cosméticas e valem o teste:
##
## 1. **Delegar tem peso zero.** É o que torna delegar a única ação do jogo que pontua sem
##    te carregar, e é literalmente o que delegação significa. Se alguém "arrumar" o
##    dicionário de pesos para tratar todas as ações igual, o argumento pedagógico da fase
##    cai e nada quebra visivelmente.
## 2. **A pasta não pode mexer no pulo.** Toda a geometria da Fase 1 — e os testes de
##    trajetória que a provam — foi calibrada contra um pulo de 62,5px de altura. Uma pasta
##    que encurtasse o salto poderia deixar o jogador preso numa plataforma sem saída, e
##    isso apareceria como "bug aleatório", porque dependeria de quantas tarefas ele tinha
##    feito antes. O alcance HORIZONTAL cai junto com a velocidade, e é por isso que o
##    validador de geometria confere tudo a 135 px/s.
func _cenario_pasta() -> void:
	print("\n--- cenário 11: a pasta pesa, e delegar não pesa ---")
	var fase := await _abrir_fase()
	var jogador: CharacterBody2D = fase.get_node("Player")
	var cat := GameManager.Categoria
	var acao := GameManager.Acao

	_conferir("o Dia 1 usa a pasta", GameManager.pasta_em_uso, true)
	_conferir("a pasta começa vazia", GameManager.carga_da_pasta, 0)
	_conferir("e o jogador começa no ritmo normal",
		jogador.velocidade_atual(), jogador.max_speed)

	GameManager.registrar_acao(cat.URGENTE_IMPORTANTE, acao.COLETAR)
	_conferir("coletar uma urgente pesa", GameManager.carga_da_pasta, 1)
	GameManager.registrar_acao(cat.IMPORTANTE_NAO_URGENTE, acao.COLETAR)
	GameManager.registrar_acao(cat.URGENTE_NAO_IMPORTANTE, acao.RESOLVER)
	GameManager.registrar_acao(cat.NAO_URGENTE_NAO_IMPORTANTE, acao.COLIDIU)
	_conferir("resolver e bater também pesam", GameManager.carga_da_pasta, 4)

	GameManager.registrar_acao(cat.URGENTE_NAO_IMPORTANTE, acao.DELEGAR)
	_conferir("DELEGAR não pesa", GameManager.carga_da_pasta, 4)
	GameManager.registrar_acao(cat.NAO_URGENTE_NAO_IMPORTANTE, acao.EVITOU)
	GameManager.registrar_acao(cat.URGENTE_IMPORTANTE, acao.IGNOROU)
	_conferir("evitar e deixar passar também não pesam", GameManager.carga_da_pasta, 4)

	_conferir("4 itens custam 20% de velocidade",
		is_equal_approx(GameManager.fator_da_pasta(), 0.8), true)
	_conferir("e o jogador anda mais devagar de fato",
		is_equal_approx(jogador.velocidade_atual(), jogador.max_speed * 0.8), true)

	# Satura: sem piso, uma partida cheia deixaria o jogador parado, e as travessias
	# obrigatórias — validadas a 135 px/s — ficariam impossíveis.
	for i in 20:
		GameManager.registrar_acao(cat.URGENTE_IMPORTANTE, acao.COLETAR)
	_conferir("a lentidão satura em 25%",
		is_equal_approx(GameManager.fator_da_pasta(), GameManager.PASTA_PISO), true)

	# --- o pulo NÃO muda ---
	var altura_carregado := await _medir_pulo(jogador)
	GameManager.entregar_pasta()
	var altura_vazio := await _medir_pulo(jogador)
	_conferir("a pasta cheia não encurta o pulo",
		absf(altura_carregado - altura_vazio) < 1.0, true)
	# O validador de geometria calcula tudo com a altura teórica de 62,5px
	# (350²/2·980). Medido, o pulo dá 65,5: a integração em passos discretos passa um
	# pouco do ápice contínuo. A folga precisa existir PARA CIMA — se o pulo real fosse
	# menor que o teórico, todas as travessias validadas seriam otimistas e alguma delas
	# estaria impossível no jogo sem nenhum teste acusar.
	_conferir("o pulo real nunca fica abaixo do teórico usado no validador",
		altura_vazio >= 62.5, true)
	_conferir("e não passa muito dele", altura_vazio < 67.5, true)

	# --- a caixa de saída ---
	var caixas := fase.get_node("CaixasSaida").get_children()
	_conferir("três caixas de saída no corredor", caixas.size(), 3)
	for caixa in caixas:
		# Acima da linha de quem corre: no chão ela esvaziaria a pasta de graça, e a
		# única decisão da mecânica (quando parar para entregar) sumiria.
		_conferir("a caixa em x=%d exige um pulo" % int(caixa.global_position.x),
			caixa.global_position.y <= 160.0, true)

	for i in 3:
		GameManager.registrar_acao(cat.IMPORTANTE_NAO_URGENTE, acao.COLETAR)
	var pontos_antes := GameManager.pontuacao_total
	await _levar(jogador, caixas[0].global_position + Vector2(0, -8))
	_conferir("encostar na caixa esvazia a pasta", GameManager.carga_da_pasta, 0)
	_conferir("e entregar NÃO dá pontos", GameManager.pontuacao_total, pontos_antes)
	_conferir("de volta ao ritmo normal",
		is_equal_approx(jogador.velocidade_atual(), jogador.max_speed), true)

	await _fechar_fase(fase)

	# --- o outro dia continua sem pasta ---
	# A pasta é a identidade do Dia 1. Levá-la para o Dia 2 faria as duas pressões dele
	# (chegada e adiamento) competirem com uma terceira, e nenhuma seria lida.
	for dia in [2]:
		var cena: Node = load(GameManager.CENA_DO_DIA[dia]).instantiate()
		_conferir("o Dia %d não usa a pasta" % dia, cena.usa_pasta(), false)
		cena.free()


## Altura máxima de um pulo, medida com a física de verdade e a mesma tecla de um humano.
func _medir_pulo(jogador: CharacterBody2D) -> float:
	await _reta(jogador, Vector2(400, 160))
	# Alguns quadros parado para o corpo assentar no chão: pular no ar mediria uma queda.
	for i in 20:
		await get_tree().physics_frame

	var chao := jogador.global_position.y
	var teto := chao
	# O botão fica SEGURADO o tempo todo. O pulo tem altura variável: soltar antes do
	# ápice corta a subida em 42%, e soltar no primeiro quadro mede 15,7px em vez dos
	# 65,5 reais. O pulo de projeto, contra o qual a fase é validada, é o do botão
	# segurado.
	Input.action_press("jump")
	for i in 60:
		await get_tree().physics_frame
		teto = minf(teto, jogador.global_position.y)
	Input.action_release("jump")
	return chao - teto


## Cenário 12: o modo foco. Concentração protege da distração e cobra em ritmo.
##
## É a resposta direta a "não dá tempo de ler": a 180 px/s com raio de 96px o jogador tem
## meio segundo para ler e decidir. Em foco são 192px a 117 px/s, ou seja mais de um
## segundo e meio. Ler passa a ser possível, e passa a ter preço.
##
## Três coisas aqui precisam de trava:
##
## 1. **Foco nunca é obrigatório.** Se alguma travessia passasse a exigi-lo, ele deixaria
##    de ser escolha e viraria chave — e a fase inteira teria de ser revalidada, porque o
##    validador de geometria calcula tudo com foco DESLIGADO.
## 2. **Foco não vaza para os outros dias.** Na Fase 2 ele barraria a notificação; na
##    Dia 2 hoje também o oferece — é habilidade aprendida, não item de fase.
## 3. **Foco não é invencibilidade.** A Q4 não acerta, mas continua contando como EVITOU
##    quando fica para trás — senão o relatório por categoria perderia a metade dele.
func _cenario_foco() -> void:
	print("\n--- cenário 12: o modo foco ---")
	_conferir("a ação 'focar' existe no Input Map", InputMap.has_action("focar"), true)

	var fase := await _abrir_fase()
	var jogador: CharacterBody2D = fase.get_node("Player")

	_conferir("o Dia 1 oferece o foco", GameManager.foco_disponivel, true)
	_conferir("mas ele começa desligado", GameManager.foco_ativo, false)

	# Pela TECLA, e não chamando alternar_foco() na mão: o jogador lê a entrada por
	# sondagem a cada quadro de física, então estado forçado por fora é desfeito no
	# quadro seguinte.
	Input.action_press("focar")
	# Três quadros, e não um: SceneTree.physics_frame dispara ANTES de os nós rodarem o
	# _physics_process daquele quadro, então esperar um só lê o estado velho. Com um
	# quadro só, este cenário acusava "o foco não liga" enquanto o jogo, um quadro
	# depois, ligava certinho — e os efeitos apareciam nas asserções seguintes.
	for i in 3:
		await get_tree().physics_frame
	_conferir("segurar a tecla liga o foco", GameManager.foco_ativo, true)
	# Comparado contra o fator da pasta, e não contra max_speed cru: as duas mecânicas se
	# multiplicam, e o que este cenário mede é só a parcela do foco.
	var base: float = jogador.max_speed * GameManager.fator_da_pasta()
	_conferir("velocidade cai para 65%",
		is_equal_approx(jogador.velocidade_atual(), base * 0.65), true)
	_conferir("e o raio de leitura cresce", GameManager.fator_do_raio(),
		GameManager.FOCO_RAIO)
	_conferir("e cresce o bastante para dar tempo de ler",
		GameManager.FOCO_RAIO >= 2.0, true)

	# A distração fica inerte. Procurada pela categoria na cena de verdade, e não
	# fabricada: o que precisa ser provado é que a Q4 DA FASE deixa de acertar.
	var q4: Area2D = null
	for t in fase.get_node("Tarefas").get_children():
		if t.has_method("posicao_base") \
				and t.categoria == GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE:
			q4 = t
			break
	_conferir("achei uma distração na fase", q4 != null, true)

	var bateu_antes: int = GameManager.acoes_por_tipo[GameManager.Acao.COLIDIU]
	await _levar(jogador, q4.posicao_base())
	_conferir("em foco a distração não acerta",
		GameManager.acoes_por_tipo[GameManager.Acao.COLIDIU], bateu_antes)
	_conferir("e ela continua no corredor, por resolver", q4.esta_resolvida(), false)

	# Mesma distração, mesmo encostão, foco desligado: agora acerta. Sem este par, a
	# asserção acima passaria também se o teleporte simplesmente não encostasse nela.
	Input.action_release("focar")
	for i in 3:
		await get_tree().physics_frame
	_conferir("soltar a tecla volta ao ritmo normal",
		is_equal_approx(jogador.velocidade_atual(),
			jogador.max_speed * GameManager.fator_da_pasta()), true)
	await _levar(jogador, Vector2(q4.posicao_base().x, 40.0))
	await _levar(jogador, q4.posicao_base())
	_conferir("fora do foco a mesma distração acerta",
		GameManager.acoes_por_tipo[GameManager.Acao.COLIDIU], bateu_antes + 1)

	await _fechar_fase(fase)

	# --- o foco ACOMPANHA o jogador para o dia seguinte ---
	# Diferente da pasta: o foco é habilidade aprendida, não pressão de fase. Tirá-lo no
	# Dia 2 seria desaprender, e é justamente lá que ele tem o adversário certo — a
	# notificação, que ele NÃO barra.
	for dia in [2]:
		var cena: Node = load(GameManager.CENA_DO_DIA[dia]).instantiate()
		_conferir("o Dia %d também oferece o foco" % dia, cena.usa_foco(), true)
		cena.free()

	GameManager.foco_disponivel = false
	Input.action_press("focar")
	GameManager.alternar_foco(true)
	Input.action_release("focar")
	_conferir("sem a fase oferecer, focar não liga", GameManager.foco_ativo, false)
	_conferir("e a velocidade fica intacta", GameManager.fator_de_foco(), 1.0)
