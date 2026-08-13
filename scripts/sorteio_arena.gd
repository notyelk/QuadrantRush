extends RefCounted

## Sorteia o layout da arena da Fase 3 — e RECUSA o que sortear errado.
##
## As posições mudam a cada partida para que não dê para decorar a sala. Nas Fases 1 e 2 a
## geometria é validada por um script Python antes de gravar o .tscn, mas aqui a fase só
## existe em tempo de execução — um sorteio ruim viraria partida invencível. Por isso o
## validador vive dentro do jogo: sorteia, confere e RE-SORTEIA enquanto não passar. Nunca
## devolve arena não validada.
##
## RefCounted e não Node: sem árvore de cena, o teste roda as 200 sementes da varredura em
## milissegundos.
##
## Os números de física abaixo são cópia de scenes/player/player.gd. Se mudarem lá, mudam
## aqui — é a razão de o validador existir.

const LARGURA := 640.0
const ALTURA := 208.0

## Superfícies pisáveis, de baixo para cima.
##
## Os degraus de 24 e 32px são folgados sobre o pulo real do jogador (62,5px de ápice),
## inclusive carregando papel — a mesma medida já validada nas Fases 1 e 2.
##
## Os cantos do CHÃO ficam sobre pedestais em Y_PEDESTAL, e não no piso: o piche sobe até
## 28px acima do piso, e um canto ao nível do chão ficaria submerso perto da derrota. Isso
## tornaria Q1 e Q4 inentregáveis justamente quando o jogador precisa se recuperar — a
## espiral sem saída que este projeto recusa desde a primeira fase.
const Y_CHAO := 192.0        # piso caminhável; é o que o piche inunda
const Y_PEDESTAL := 160.0    # superfície dos dois cantos "de baixo"
const Y_DEGRAU := 136.0
const Y_MEZANINO := 104.0

## Teto do piche. Copiado de pilha_pendencias.gd; a invariante 5 confere que os dois
## números continuam compatíveis, para que mexer num sem o outro seja pego por teste.
const PILHA_ALTURA_MAXIMA := 28.0

const VELOCIDADE_PULO := 350.0
const GRAVIDADE := 980.0
const VELOCIDADE_MAX := 180.0

## Gravidade da QUEDA é 1,45x a da subida (player.gd: `gravidade_queda`). Isso encurta o
## ápice e, por consequência, encurta o alcance horizontal — usar a fórmula simétrica aqui
## superestimaria o pulo em ~7% e produziria travessia "válida" que na mão não fecha.
const GRAVIDADE_QUEDA := GRAVIDADE * 1.45

## Pior caso previsto pelo design: carregando um papel (80%). O modo foco deixa o jogador
## ainda mais lento, mas nunca é obrigatório, então não entra no pior caso.
const FATOR_CARREGANDO := 0.8
const VELOCIDADE_PIOR_CASO := VELOCIDADE_MAX * FATOR_CARREGANDO   # 144 px/s

## Margem de segurança sobre o alcance calculado. O cálculo assume que o jogador chega ao
## salto na velocidade máxima e solta o pulo na hora certa; um humano não faz isso.
const FOLGA := 0.82

## Plataformas do mezanino. NÃO são sorteadas: elas desenham a silhueta da sala, e uma
## silhueta que muda a cada partida tiraria do jogador a única referência estável que ele
## tem para se orientar enquanto lê os rótulos sorteados.
const MEZANINO_ESQ := Rect2(96, Y_MEZANINO, 112, 16)
const MEZANINO_DIR := Rect2(432, Y_MEZANINO, 112, 16)

## Pedestais dos cantos de baixo. Também fixos, pela mesma razão das plataformas.
const PEDESTAL_ESQ := Rect2(40, Y_PEDESTAL, 96, 32)
const PEDESTAL_DIR := Rect2(504, Y_PEDESTAL, 96, 32)

## Onde cada canto da matriz pode nascer, por nível. O sorteio escolhe o x dentro da faixa.
const FAIXA_CHAO_ESQ := Vector2(56, 120)
const FAIXA_CHAO_DIR := Vector2(520, 584)
const FAIXA_MEZ_ESQ := Vector2(112, 192)
const FAIXA_MEZ_DIR := Vector2(448, 528)

## Candidatos a degrau (x inicial). Cada degrau tem 48px de largura e fica em Y_DEGRAU.
## As duas listas servem os dois lados do mezanino; o sorteio tira dois de cada.
const CANDIDATOS_DEGRAU_ESQ: Array[float] = [216.0, 232.0, 248.0, 264.0, 280.0]
const CANDIDATOS_DEGRAU_DIR: Array[float] = [344.0, 360.0, 376.0, 392.0, 408.0]
const LARGURA_DEGRAU := 48.0

## Quantas demandas de cada quadrante o dia inteiro contém. É o ORÇAMENTO DE DIFICULDADE:
## fica fora do sorteio de propósito, porque o ranking global da Etapa 7 compara jogadores
## entre si, e sortear a composição faria o placar medir a sorte do sorteio.
##
## O total sai da aritmética do Chefe: os intervalos dele (ver chefe.gd) pedem mais de 40
## arremessos em 100 s, e com menos que isso a fila seca antes do fim e a última fase, a
## mais rápida, fica sem nada para jogar. Com 44 o expediente fica cheio de ponta a ponta e
## a escassez passa a existir — dá para rotear cerca de 22, então metade tem de ser
## abandonada, e é só sob escassez que a matriz ensina alguma coisa.
const ORCAMENTO := {
	GameManager.Categoria.URGENTE_IMPORTANTE: 12,
	GameManager.Categoria.IMPORTANTE_NAO_URGENTE: 9,
	GameManager.Categoria.URGENTE_NAO_IMPORTANTE: 9,
	GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE: 14,
}

## Quantas Q4 do orçamento ficam RESERVADAS para o ataque de e-mail em cópia, em vez de
## entrarem na fila normal.
##
## Reservada, e não sacada da fila normal: sacando, o ataque puxaria o que estivesse por
## vir — quatro Q1, se calhasse —, e um "e-mail em cópia para todos" que despeja urgências
## é outra coisa. Além disso esvaziaria a fila antes do fim do expediente.
##
## É gasta em bursts de tamanho e momento fixos (ver chefe.gd), não por sorteio: se
## dependesse de sorte, dois jogadores do mesmo dia enfrentariam totais diferentes e o
## ranking da Etapa 7 deixaria de comparar.
const RESERVA_EMAIL := 6
const EMAIL_POR_ATAQUE := 3

## Distância mínima entre um ponto de pouso e o centro de um canto. Sem isto, um papel
## pousaria dentro da zona de entrega e se autoentregaria antes de o jogador tocá-lo.
const RAIO_LIVRE_DO_CANTO := 44.0

const MAX_TENTATIVAS := 50


## Distância horizontal de um pulo que precisa SUBIR `subida` pixels, integrando a
## trajetória de verdade com a gravidade assimétrica do jogo.
##
## "Altura máxima x largura máxima" é a conta ERRADA, e é a que já produziu plataforma
## inalcançável neste projeto: no instante em que o jogador está lá em cima, ele ainda
## não percorreu a largura toda.
static func alcance(subida: float, velocidade: float = VELOCIDADE_PIOR_CASO) -> float:
	var apice := VELOCIDADE_PULO * VELOCIDADE_PULO / (2.0 * GRAVIDADE)   # 62.5px
	if subida > apice:
		return -1.0                                   # não sobe tanto de jeito nenhum
	var t_subida := VELOCIDADE_PULO / GRAVIDADE
	var t_queda := sqrt(2.0 * (apice - subida) / GRAVIDADE_QUEDA)
	return velocidade * (t_subida + t_queda)


## Uma travessia de `dx` pixels na horizontal subindo `dy` é possível carregando papel?
static func alcanca(dx: float, subida: float) -> bool:
	var maximo := alcance(subida)
	if maximo < 0.0:
		return false
	return absf(dx) <= maximo * FOLGA


# Sorteio

## Devolve um layout validado. `semente` < 0 sorteia a própria semente (é o caso do jogo);
## um valor fixo reproduz a mesma arena (é o caso do teste).
##
## Nunca devolve layout inválido: se as 50 tentativas falharem, cai no layout de reserva,
## que é escrito à mão e conferido por teste.
static func sortear(semente: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = semente if semente >= 0 else randi()

	for tentativa in MAX_TENTATIVAS:
		var layout := _desenhar(rng)
		if validar(layout).is_empty():
			layout["tentativas"] = tentativa + 1
			return layout

	var reserva := layout_de_reserva()
	reserva["semente"] = rng.seed
	reserva["tentativas"] = MAX_TENTATIVAS
	return reserva


static func _desenhar(rng: RandomNumberGenerator) -> Dictionary:
	var C := GameManager.Categoria

	# Q2 e Q3 vão SEMPRE para o mezanino; Q1 e Q4, para o chão. Qual dos dois lados é
	# livre. Isso preserva a regra pedagógica que as Fases 1 e 2 estabeleceram — o
	# importante-e-não-urgente fica onde exige esforço deliberado — sem abrir mão do
	# anti-decoreba, porque a ROTA até lá muda junto com os degraus.
	var alto := [C.IMPORTANTE_NAO_URGENTE, C.URGENTE_NAO_IMPORTANTE]
	var baixo := [C.URGENTE_IMPORTANTE, C.NAO_URGENTE_NAO_IMPORTANTE]
	if rng.randf() < 0.5:
		alto.reverse()
	if rng.randf() < 0.5:
		baixo.reverse()

	var cantos := {}
	var nivel := {}
	cantos[alto[0]] = Vector2(rng.randf_range(FAIXA_MEZ_ESQ.x, FAIXA_MEZ_ESQ.y), Y_MEZANINO)
	cantos[alto[1]] = Vector2(rng.randf_range(FAIXA_MEZ_DIR.x, FAIXA_MEZ_DIR.y), Y_MEZANINO)
	cantos[baixo[0]] = Vector2(rng.randf_range(FAIXA_CHAO_ESQ.x, FAIXA_CHAO_ESQ.y), Y_PEDESTAL)
	cantos[baixo[1]] = Vector2(rng.randf_range(FAIXA_CHAO_DIR.x, FAIXA_CHAO_DIR.y), Y_PEDESTAL)
	nivel[alto[0]] = 1
	nivel[alto[1]] = 1
	nivel[baixo[0]] = 0
	nivel[baixo[1]] = 0

	# Arredonda para a grade de 8px: posição fracionária de tile produz a costura de
	# meio pixel que já apareceu como "linha preta" nas capturas da Fase 2.
	for categoria in cantos:
		var p: Vector2 = cantos[categoria]
		cantos[categoria] = Vector2(roundf(p.x / 8.0) * 8.0, p.y)

	var degraus: Array[Rect2] = []
	for x in _escolher(rng, CANDIDATOS_DEGRAU_ESQ, 2, LARGURA_DEGRAU):
		degraus.append(Rect2(x, Y_DEGRAU, LARGURA_DEGRAU, 16))
	for x in _escolher(rng, CANDIDATOS_DEGRAU_DIR, 2, LARGURA_DEGRAU):
		degraus.append(Rect2(x, Y_DEGRAU, LARGURA_DEGRAU, 16))

	var layout := {
		"semente": rng.seed,
		"cantos": cantos,
		"nivel": nivel,
		"degraus": degraus,
	}
	layout["pousos"] = _sortear_pousos(rng, layout)
	layout["fila"] = _sortear_fila(rng)
	return layout


## Tira `quantos` valores distintos da lista, separados por pelo menos `distancia`.
##
## A separação existe porque dois degraus de 48px sorteados a 16px um do outro viram um
## bloco único de 64px: o jogador vê uma plataforma onde o desenho previa duas rotas, e os
## pontos de pouso das duas se empilham no mesmo lugar.
static func _escolher(
	rng: RandomNumberGenerator, fonte: Array[float], quantos: int, distancia := 0.0
) -> Array[float]:
	var copia := fonte.duplicate()
	var saida: Array[float] = []
	for _i in quantos:
		var possiveis: Array[float] = []
		for valor in copia:
			var cabe := true
			for ja in saida:
				if absf(valor - ja) < distancia:
					cabe = false
					break
			if cabe:
				possiveis.append(valor)
		if possiveis.is_empty():
			break
		var escolhido: float = possiveis[rng.randi_range(0, possiveis.size() - 1)]
		saida.append(escolhido)
		copia.erase(escolhido)
	saida.sort()
	return saida


## Pontos onde uma demanda pode pousar: qualquer superfície pisável, longe dos cantos.
##
## O passo do chão é 12px e cada degrau rende três pontos, porque com o orçamento em 44 a
## contagem de candidatos vira o gargalo: quatro cantos apagam até ~28 candidatos em volta
## (regra 7), e numa densidade menor as 50 tentativas falhariam e a fase cairia no layout
## de reserva toda partida — virando a fase fixa que o sorteio existe para impedir.
static func _sortear_pousos(rng: RandomNumberGenerator, layout: Dictionary) -> Array[Vector2]:
	var candidatos: Array[Vector2] = []

	# O piso só é piso onde não há pedestal por cima: os dois blocos descem do topo deles
	# até o chão, e um papel pousado ali nasce dentro da pedra, invisível e inalcançável.
	var x := 48.0
	while x <= LARGURA - 48.0:
		if not (_dentro(PEDESTAL_ESQ, x) or _dentro(PEDESTAL_DIR, x)):
			candidatos.append(Vector2(x, Y_CHAO))
		x += 12.0

	for plataforma in [MEZANINO_ESQ, MEZANINO_DIR, PEDESTAL_ESQ, PEDESTAL_DIR]:
		var px: float = plataforma.position.x + 16.0
		while px <= plataforma.position.x + plataforma.size.x - 16.0:
			candidatos.append(Vector2(px, plataforma.position.y))
			px += 16.0

	for degrau in layout["degraus"] as Array[Rect2]:
		for fracao in [0.25, 0.5, 0.75]:
			candidatos.append(Vector2(degrau.position.x + degrau.size.x * fracao, Y_DEGRAU))

	var livres: Array[Vector2] = []
	for ponto in candidatos:
		var colide := false
		for categoria in layout["cantos"]:
			var canto: Vector2 = layout["cantos"][categoria]
			if ponto.distance_to(canto) < RAIO_LIVRE_DO_CANTO:
				colide = true
				break
		if not colide:
			livres.append(ponto)

	livres.shuffle()
	return livres


## A ordem em que as categorias chegam. O orçamento é fixo; só a ordem é sorteada.
##
## A fila NÃO contém as Q4 reservadas ao e-mail em cópia: aquelas chegam em bloco, em
## momento fixo, e somá-las aqui as faria chegar duas vezes.
##
## Regra extra: nunca três da mesma categoria em sequência. Sem ela, o sorteio produz
## rajadas ("cinco Q4 seguidas") que o jogador lê como bug de spawn, e a fase perde a
## sensação de expediente com pauta variada.
static func _sortear_fila(rng: RandomNumberGenerator) -> Array[int]:
	for _tentativa in 200:
		var fila: Array[int] = []
		for categoria in ORCAMENTO:
			for _i in _quantidade_na_fila(int(categoria)):
				fila.append(int(categoria))

		# Embaralhamento de Fisher-Yates com o RNG semeado. Array.shuffle() usa o gerador
		# GLOBAL, que não é semeado por nós — usá-lo tornaria o "mesmo seed, mesma fase"
		# falso, e a suíte ficaria intermitente.
		for i in range(fila.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var troca := fila[i]
			fila[i] = fila[j]
			fila[j] = troca

		if not _tem_trinca(fila):
			return fila

	return fila_ordenada()


static func _tem_trinca(fila: Array[int]) -> bool:
	for i in range(2, fila.size()):
		if fila[i] == fila[i - 1] and fila[i] == fila[i - 2]:
			return true
	return false


## Último recurso da fila: intercalada à mão, sem trinca por construção.
static func fila_ordenada() -> Array[int]:
	var C := GameManager.Categoria
	var padrao := [
		C.URGENTE_IMPORTANTE, C.NAO_URGENTE_NAO_IMPORTANTE,
		C.IMPORTANTE_NAO_URGENTE, C.URGENTE_NAO_IMPORTANTE,
		C.NAO_URGENTE_NAO_IMPORTANTE, C.URGENTE_IMPORTANTE,
		C.URGENTE_NAO_IMPORTANTE, C.IMPORTANTE_NAO_URGENTE,
	]
	var restante := {}
	for categoria in ORCAMENTO:
		restante[categoria] = _quantidade_na_fila(int(categoria))
	var fila: Array[int] = []
	var i := 0
	while fila.size() < total_na_fila():
		var categoria: int = padrao[i % padrao.size()]
		if int(restante[categoria]) > 0:
			restante[categoria] = int(restante[categoria]) - 1
			fila.append(categoria)
		i += 1
		if i > 1000:
			break
	return fila


## Quantas demandas desta categoria entram na fila normal. Só a Q4 tem reserva.
static func _quantidade_na_fila(categoria: int) -> int:
	var total := int(ORCAMENTO.get(categoria, 0))
	if categoria == GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE:
		return total - RESERVA_EMAIL
	return total


## Tudo o que o dia contém — fila normal MAIS a reserva de e-mail. É este o número que
## alimenta o "X de N" da tela de resultado, o briefing e o teto de pontuação do ranking.
static func total_de_demandas() -> int:
	var soma := 0
	for categoria in ORCAMENTO:
		soma += int(ORCAMENTO[categoria])
	return soma


## Só o que chega pela fila normal.
static func total_na_fila() -> int:
	return total_de_demandas() - RESERVA_EMAIL


# Validação

## Devolve a lista de invariantes violadas. Vazia = layout aprovado.
##
## Cada regra abaixo nasceu de um defeito real deste projeto ou de um risco concreto do
## design da Fase 3, e o motivo está escrito junto — sem ele, a regra vira superstição e
## a próxima pessoa a mexer aqui a apaga por não saber o que ela protege.
static func validar(layout: Dictionary) -> Array[String]:
	var erros: Array[String] = []
	var cantos: Dictionary = layout["cantos"]
	var degraus: Array[Rect2] = layout["degraus"]

	# 1. Os quatro quadrantes existem, uma vez cada. Um sorteio que perdesse um quadrante
	#    tornaria aquelas demandas impossíveis de entregar, e a pilha subiria sozinha.
	for categoria in GameManager.Categoria.values():
		if not cantos.has(categoria):
			erros.append("quadrante %d sem canto" % categoria)
	if cantos.size() != 4:
		erros.append("esperados 4 cantos, obtidos %d" % cantos.size())
	if not erros.is_empty():
		return erros

	# 2. Nenhum canto encosta em outro. Dois gatilhos sobrepostos fazem o primeiro sinal
	#    processado decidir a entrega — foi exatamente o bug da bifurcação Q3, achado
	#    jogando, em que subir para delegar registrava RESOLVER.
	var lista: Array = cantos.values()
	for i in lista.size():
		for j in range(i + 1, lista.size()):
			if (lista[i] as Vector2).distance_to(lista[j] as Vector2) < 64.0:
				erros.append("cantos sobrepostos")

	# 3. Todo canto fica de fato sobre a plataforma dele. Um canto no ar seria
	#    inalcançável, e o jogador passaria a partida tentando pular no vazio.
	for categoria in cantos:
		var p: Vector2 = cantos[categoria]
		var sobre := false
		if int(layout["nivel"][categoria]) == 1:
			sobre = _dentro(MEZANINO_ESQ, p.x) or _dentro(MEZANINO_DIR, p.x)
		else:
			sobre = _dentro(PEDESTAL_ESQ, p.x) or _dentro(PEDESTAL_DIR, p.x)
		if not sobre:
			erros.append("canto %d fora da plataforma" % categoria)

	# 4. Cada lado do mezanino tem pelo menos DUAS rotas. Com uma só, o Chefe ocupando o
	#    canto certo na hora errada viraria sentença, e "difícil" viraria "injusto".
	var rotas_esq := _rotas_para(degraus, MEZANINO_ESQ)
	var rotas_dir := _rotas_para(degraus, MEZANINO_DIR)
	if rotas_esq < 2:
		erros.append("mezanino esquerdo com %d rota(s)" % rotas_esq)
	if rotas_dir < 2:
		erros.append("mezanino direito com %d rota(s)" % rotas_dir)

	# 5. NENHUM canto fica submerso, nem com o piche no teto. É o que impede a fase de
	#    virar espiral sem saída: altura fixa por unidade (4px) daria 96px de piche numa
	#    arena de 208px, afogando degraus, pedestais e mezanino. O teste pegou na
	#    primeira execução.
	var topo_do_piche := Y_CHAO - PILHA_ALTURA_MAXIMA
	if topo_do_piche <= Y_PEDESTAL:
		erros.append("o piche cobre os pedestais dos cantos de baixo")
	if topo_do_piche <= Y_DEGRAU:
		erros.append("o piche cobre os degraus")

	# 6. Cada degrau da escalada é vencível. Medido com a trajetória INTEGRADA e a
	#    gravidade assimétrica de verdade, carregando papel — que é o pior caso real.
	if not alcanca(0.0, Y_CHAO - Y_PEDESTAL):
		erros.append("pedestal inalcançável do chão")
	if not alcanca(0.0, Y_PEDESTAL - Y_DEGRAU):
		erros.append("degrau inalcançável do pedestal")
	if not alcanca(0.0, Y_DEGRAU - Y_MEZANINO):
		erros.append("mezanino inalcançável do degrau")

	# 7. Há pontos de pouso suficientes para o dia inteiro, e nenhum em cima de um canto.
	var pousos: Array[Vector2] = layout["pousos"]
	if pousos.size() < total_de_demandas():
		erros.append("pousos insuficientes: %d para %d demandas" % [pousos.size(), total_de_demandas()])
	for ponto in pousos:
		for categoria in cantos:
			if ponto.distance_to(cantos[categoria] as Vector2) < RAIO_LIVRE_DO_CANTO:
				erros.append("pouso em cima de um canto")
				break

	# 8. A fila MAIS a reserva de e-mail dão exatamente o orçamento. É o que mantém o
	#    ranking da Etapa 7 comparável: sem isto, dois jogadores do mesmo dia enfrentariam
	#    teto de pontuação diferente. Contar só a fila deixaria de fora a reserva, e o
	#    "X de N" da tela de resultado passaria a mentir para menos.
	var contagem := {}
	for categoria in GameManager.Categoria.values():
		contagem[categoria] = 0
	contagem[GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE] = RESERVA_EMAIL
	for categoria in layout["fila"] as Array[int]:
		contagem[categoria] = int(contagem[categoria]) + 1
	for categoria in ORCAMENTO:
		if int(contagem[categoria]) != int(ORCAMENTO[categoria]):
			erros.append("orçamento do quadrante %d: %d != %d"
				% [categoria, contagem[categoria], ORCAMENTO[categoria]])

	# 9. A reserva de e-mail é gasta por inteiro, em bursts de tamanho fixo. Uma reserva
	#    que sobrasse no fim do expediente faria o teto de pontuação do dia depender de
	#    quantos ataques couberam — que é a mesma quebra de comparabilidade da regra 8,
	#    entrando pela porta dos fundos.
	if RESERVA_EMAIL % EMAIL_POR_ATAQUE != 0:
		erros.append("a reserva de e-mail (%d) não fecha em bursts de %d"
			% [RESERVA_EMAIL, EMAIL_POR_ATAQUE])

	return erros


static func _dentro(plataforma: Rect2, x: float) -> bool:
	return x >= plataforma.position.x and x <= plataforma.position.x + plataforma.size.x


## Quantos degraus permitem saltar para esta plataforma do mezanino.
static func _rotas_para(degraus: Array[Rect2], plataforma: Rect2) -> int:
	var rotas := 0
	var subida := Y_DEGRAU - Y_MEZANINO
	for degrau in degraus:
		# Vão horizontal entre a borda mais próxima do degrau e a borda da plataforma.
		var esq := plataforma.position.x - (degrau.position.x + degrau.size.x)
		var dir := degrau.position.x - (plataforma.position.x + plataforma.size.x)
		var vao := maxf(maxf(esq, dir), 0.0)
		if alcanca(vao, subida):
			rotas += 1
	return rotas


## Layout escrito à mão, usado quando 50 sorteios seguidos falham. Não deveria acontecer
## nunca — existe para que a fase degrade para "sempre igual" em vez de para "quebrada".
static func layout_de_reserva() -> Dictionary:
	var C := GameManager.Categoria
	var cantos := {
		C.URGENTE_IMPORTANTE: Vector2(88, Y_PEDESTAL),
		C.NAO_URGENTE_NAO_IMPORTANTE: Vector2(552, Y_PEDESTAL),
		C.IMPORTANTE_NAO_URGENTE: Vector2(152, Y_MEZANINO),
		C.URGENTE_NAO_IMPORTANTE: Vector2(488, Y_MEZANINO),
	}
	var degraus: Array[Rect2] = [
		Rect2(216, Y_DEGRAU, LARGURA_DEGRAU, 16),
		Rect2(264, Y_DEGRAU, LARGURA_DEGRAU, 16),
		Rect2(344, Y_DEGRAU, LARGURA_DEGRAU, 16),
		Rect2(392, Y_DEGRAU, LARGURA_DEGRAU, 16),
	]
	var layout := {
		"semente": 0,
		"cantos": cantos,
		"nivel": {
			C.URGENTE_IMPORTANTE: 0,
			C.NAO_URGENTE_NAO_IMPORTANTE: 0,
			C.IMPORTANTE_NAO_URGENTE: 1,
			C.URGENTE_NAO_IMPORTANTE: 1,
		},
		"degraus": degraus,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	layout["pousos"] = _sortear_pousos(rng, layout)
	layout["fila"] = fila_ordenada()
	return layout
