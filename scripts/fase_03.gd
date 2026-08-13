extends "res://scripts/fase_base.gd"

## Fase 3 — "O Chefe". A fase final: a sala É a Matriz de Eisenhower.
##
## Herança por CAMINHO, e não por class_name: nome global de classe vive no cache que o
## editor gera, e este projeto roda teste e captura por linha de comando.
##
## Nos Dias 1 e 2 o jogador corre por um corredor e encosta em papéis; a matriz é
## escrituração invisível. Aqui ele pega um papel e o carrega até o canto da sala que
## corresponde ao quadrante em que o classificou — a matriz vira a planta do cenário.
##
## Não inventa pontuação: toda entrega passa por ZonaMatriz.acao_para(), que só devolve
## linhas do Quadro 1.
##
## Onde mora cada coisa:
##   sorteio_arena.gd .... sorteia e VALIDA a geometria (roda a cada partida)
##   chefe.gd ............ o ritmo: em que fase está e quando algo acontece
##   demanda.gd .......... o papel: cai, envelhece, é carregado
##   zona_matriz.gd ...... o canto: traduz "onde entreguei" em ação do Quadro 1
##   pilha_pendencias.gd . a aritmética do soterramento (a única derrota)
##   este arquivo ........ costura tudo e é quem decide

const Sorteio := preload("res://scripts/sorteio_arena.gd")
const Pilha := preload("res://scripts/pilha_pendencias.gd")
const Zona := preload("res://scripts/zona_matriz.gd")

const CENA_DEMANDA := preload("res://entities/demanda.tscn")
const CENA_ZONA := preload("res://entities/zona_matriz.tscn")
const CENA_LIGACAO := preload("res://entities/ligacao.tscn")

## Semente do sorteio. −1 sorteia (é o caso do jogo); um valor fixo reproduz a arena
## inteira, e é assim que o teste consegue ser determinístico.
@export var semente := -1

## Quanto a origem do jogador fica acima da superfície em que ele está pisando.
## Medido, não estimado: em fase_01.tscn o Player nasce em y=160 sobre um chão cuja
## superfície é y=176.
const ALTURA_DOS_PES := 16.0

@onready var zonas: Node2D = $Zonas
@onready var colisores: Node2D = $Colisores
@onready var chefe: Node2D = $Inimigos/Chefe
@onready var piche: Polygon2D = $Piche

var layout: Dictionary = {}
var pilha := Pilha.new()

var _carregando: Node = null
var _fila: Array[int] = []
var _pousos: Array[Vector2] = []
var _proximo := 0
## Quantas Q4 da reserva de e-mail já foram despejadas.
var _reserva_gasta := 0


# O que esta fase responde por si

func tempo_de_expediente() -> float:
	return GameManager.SEGUNDOS_DO_DIA[3]


func numero_do_dia() -> int:
	return 3


## O modo foco acompanha o jogador desde o Dia 1 — habilidade aprendida não se perde de um
## dia para o outro. Ele amplia o raio de leitura, mas NÃO impede a ligação: foco não
## resolve prazo.
func usa_foco() -> bool:
	return true


## A pasta é do Dia 1: ela exige caixas de saída, e esta arena não tem. Ligá-la aqui seria
## penalidade sem antídoto. O peso do trabalho em andamento existe nesta fase de outra
## forma — carregar um papel já custa 20% da velocidade.
func usa_pasta() -> bool:
	return false


## Zerar o relógio aqui é VENCER. A ameaça é a pilha.
func vitoria_por_tempo() -> bool:
	return true


## Não há elevador nesta fase: não existe cota de urgentes a cumprir para sair. Devolver 0
## também esconde o contador do HUD (ver hud.atualizar_urgentes), que é o certo — "0 de 0"
## parado no alto seria ruído permanente.
func meta_de_urgentes() -> int:
	return 0


## A composição do dia é o ORÇAMENTO do sorteio, e não os filhos do nó Tarefas.
##
## A contagem herdada varre a cena, o que funciona nos Dias 1 e 2 porque lá as tarefas já
## estão no corredor quando a fase abre. Aqui elas chegam ao longo do expediente, então no
## primeiro quadro a cena está vazia — e o "X de N" da tela de resultado, a trava do
## elevador e o briefing leriam zero. O teste do briefing pegou isso.
func _mapear_composicao() -> Dictionary:
	var mapa := {}
	for categoria in GameManager.Categoria.values():
		mapa[categoria] = int(Sorteio.ORCAMENTO.get(categoria, 0))
	return mapa


func abertura() -> Array:
	return [
		"REUNIÃO DE ENCERRAMENTO",
		"Pegue um papel e POUSE no canto certo. O papel vence na mão. Sobreviva aos 100s.",
		Color("e07a94"),
	]


## Aqui o relógio zerado é vitória e quem derruba é a pilha, então o fecho não pode falar
## em tempo esgotado nem em elevador.
func fecho(vitoria: bool) -> Array:
	var quem := Perfil.nickname if not Perfil.nickname.is_empty() else "Você"
	if vitoria:
		return [
			"VOCÊ AGUENTOU ATÉ O FIM",
			"%s atravessou a reunião de encerramento sem ser soterrado." % quem,
		]
	return [
		"SOTERRADO PELAS PENDÊNCIAS",
		"a pilha tomou a sala antes de %s vencer o relógio. O dia foi perdido." % quem,
	]


func extras_do_resultado() -> Array:
	return [
		["Pilha de pendências", "%d de %d" % [pilha.unidades, Pilha.SOTERRA]],
		["Fase do Chefe alcançada", "%d de 4" % (chefe.fase_atual + 1)],
	]


# Montagem

func _preparar() -> void:
	# A arena não tem travessia obrigatória validada como os corredores dos Dias 1 e 2, e
	# aqui o trabalho é atravessar a sala contra o relógio de validade do papel.
	jogador.pulo_duplo = true
	jogador.arranque = true

	layout = Sorteio.sortear(semente)

	# Se um layout inválido chegasse até aqui, a partida seria invencível sem nada
	# denunciar. O sorteador já re-sorteia sozinho; este aviso existe para o caso de
	# alguém mexer nas invariantes e quebrar as duas camadas ao mesmo tempo.
	var erros := Sorteio.validar(layout)
	if not erros.is_empty():
		push_error("Fase 3 com layout inválido: %s" % ", ".join(erros))

	_fila = layout["fila"]
	_pousos = layout["pousos"]

	_montar_degraus()
	_montar_zonas()

	pilha.mudou.connect(_ao_mudar_pilha)

	chefe.arremessar.connect(_ao_arremessar)
	chefe.ataque.connect(_ao_atacar)
	chefe.ataque_telegrafado.connect(_ao_telegrafar)
	chefe.fase_mudou.connect(_ao_mudar_fase_do_chefe)
	chefe.comecar(int(layout["semente"]))

	_atualizar_piche()


## Os degraus são sorteados, então nascem em código. O resto da arena (piso, paredes,
## plataformas do mezanino, pedestais) é estático e vem do .tscn gerado por
## tools/gerar_fase_03.py — silhueta que muda a cada partida tiraria do jogador a única
## referência estável que ele tem para se orientar enquanto lê os rótulos sorteados.
func _montar_degraus() -> void:
	for degrau in layout["degraus"] as Array[Rect2]:
		var corpo := StaticBody2D.new()
		corpo.position = degrau.position + degrau.size * 0.5
		var forma := CollisionShape2D.new()
		var caixa := RectangleShape2D.new()
		caixa.size = degrau.size
		forma.shape = caixa
		corpo.add_child(forma)

		var visual := Polygon2D.new()
		var w: float = degrau.size.x * 0.5
		var h: float = degrau.size.y * 0.5
		visual.polygon = PackedVector2Array([
			Vector2(-w, -h), Vector2(w, -h), Vector2(w, h), Vector2(-w, h)
		])
		visual.color = Color("5c5142")
		corpo.add_child(visual)

		var topo := Polygon2D.new()
		topo.polygon = PackedVector2Array([
			Vector2(-w, -h), Vector2(w, -h), Vector2(w, -h + 3.0), Vector2(-w, -h + 3.0)
		])
		topo.color = Color("8a7a63")
		corpo.add_child(topo)

		colisores.add_child(corpo)


func _montar_zonas() -> void:
	for categoria in layout["cantos"]:
		var zona := CENA_ZONA.instantiate()
		zona.papel = categoria
		zona.position = layout["cantos"][categoria]
		zona.entregue.connect(_ao_entregar)
		zonas.add_child(zona)


# O laço da fase

func _atualizar(_delta: float) -> void:
	_ler_entrada()
	_checar_zonas()


## Entrada por SONDAGEM, e não por _unhandled_input: Input.action_press() não sintetiza
## InputEvent, então o robô a pé do teste não conseguiria exercitar este caminho. Mesma
## razão pela qual o pulo e a pausa também são lidos assim.
func _ler_entrada() -> void:
	# Desde que o papel passou a envelhecer na mão, ele pode sumir sem passar por _largar()
	# nem por _ao_entregar(). Sem esta guarda o jogador ficaria 20% mais lento até o fim do
	# expediente, sem nada na mão para explicar por quê.
	if GameManager.carregando and not is_instance_valid(_carregando):
		_carregando = null
		GameManager.carregando = false

	if Input.is_action_just_pressed("largar") and is_instance_valid(_carregando):
		_largar()
		return
	if is_instance_valid(_carregando):
		return

	# Pegar é por proximidade, e não por sinal de colisão, porque o papel carregado
	# desliga o próprio colisor: com sinal, dois papéis encostados disputariam o mesmo
	# quadro e o primeiro processado venceria, como acontecia nos gatilhos sobrepostos
	# da bifurcação Q3.
	for demanda in get_tree().get_nodes_in_group("demanda"):
		if demanda.resolvida or demanda.carregada or not demanda._caiu:
			continue
		# 22px, e não um encostão exato: o papel pousa 10px acima da superfície e a origem
		# do jogador fica nos pés dele, então um raio apertado exigiria precisão de pixel
		# para pegar algo que está literalmente no caminho. O robô do cenário 7 reprovou
		# com 16px, e um humano correndo a 180 px/s reprovaria junto.
		if demanda.global_position.distance_to(jogador.global_position) > 22.0:
			continue
		_pegar(demanda)
		return


func _pegar(demanda: Node) -> void:
	demanda.pegar()
	_carregando = demanda
	GameManager.carregando = true
	get_tree().call_group(
		"hud", "mostrar_dica", "NA MÃO",
		demanda.texto, Color("f2f2f2"), 0
	)


func _largar() -> void:
	_carregando.largar()
	_carregando = null
	GameManager.carregando = false


## Entregar é geométrico e exige POUSAR no canto, não passar por ele. Não há tecla de
## confirmar: a seção 3.1 do TCC exige que a priorização seja ação física, não menu.
##
## Só medir distância não basta — um arco de pulo que passe a 10px do canto vizinho
## entregaria o papel no lugar errado, e "perdi porque pulei perto" é o tipo de
## dificuldade injusta que este projeto recusa desde o telegrafo do urso.
##
## O `is_on_floor()` torna a entrega deliberada sem deixar de ser física. Nos cantos do
## mezanino vira "subir e pousar lá em cima", que é o esforço que o quadrante
## importante-e-não-urgente deve custar.
func _checar_zonas() -> void:
	if not is_instance_valid(_carregando) or not jogador.is_on_floor():
		return
	for zona in zonas.get_children():
		if zona.bloqueado:
			continue
		# ALTURA_DOS_PES: a origem do jogador fica ~16px ACIMA da superfície em que ele
		# pisa (confira em fase_01.tscn: Player em y=160 sobre um chão cuja superfície é
		# 176). Comparar contra a superfície crua fazia a entrega nunca acontecer, e o
		# robô do cenário 7 pegou isso. É o mesmo tipo de deslocamento que já mordeu este
		# projeto duas vezes: a notificação do Dia 2 mirava 7px acima da cápsula, e o urso
		# do Dia 1 nasceu flutuando 17px no ar.
		var alvo: Vector2 = zona.global_position + Vector2(0, -ALTURA_DOS_PES)
		var delta: Vector2 = jogador.global_position - alvo
		if absf(delta.x) > 26.0 or absf(delta.y) > 14.0:
			continue
		if zona.receber(_carregando):
			return


func _ao_entregar(zona: Node, demanda: Node) -> void:
	var acao := Zona.acao_para(demanda.categoria, zona.papel)
	demanda.resolver(acao)
	_carregando = null
	GameManager.carregando = false

	if Zona.acertou(demanda.categoria, zona.papel):
		pilha.acertou()
	else:
		pilha.errou()

	get_tree().call_group(
		"hud", "mostrar_dica",
		GameManager.NOME_CATEGORIA[demanda.categoria],
		GameManager.licao(demanda.categoria, acao),
		GameManager.COR_CATEGORIA[demanda.categoria], 2
	)


## O Chefe pediu o próximo papel. QUAL papel e ONDE ele cai saem do layout sorteado, não
## de um sorteio novo aqui: é isso que faz a mesma semente reproduzir a partida inteira.
func _ao_arremessar() -> void:
	if _proximo >= _fila.size():
		return
	var categoria: int = _fila[_proximo]
	var pouso: Vector2 = _pousos[_proximo % _pousos.size()]
	_proximo += 1
	_soltar_papel(categoria, pouso)


## Põe um papel no ar. Ponto único por onde toda demanda entra em cena, venha ela da fila
## normal ou da reserva do e-mail em cópia.
func _soltar_papel(categoria: int, pouso: Vector2) -> void:
	var demanda := CENA_DEMANDA.instantiate()
	demanda.categoria = categoria
	demanda.texto = _enunciado(categoria)
	demanda.pousa = pouso.y - 10.0
	demanda.position = Vector2(pouso.x, -20.0)
	demanda.apodreceu.connect(_ao_apodrecer)
	tarefas.add_child(demanda)


func _ao_apodrecer(demanda: Node) -> void:
	pilha.apodreceu(demanda.categoria)
	var texto := "Um papel apodreceu no chão. A pilha subiu."
	if demanda.na_mao_ao_vencer:
		texto = "Venceu na sua mão. Segurar não é resolver."
	get_tree().call_group(
		"hud", "mostrar_dica", "PENDÊNCIA", texto,
		GameManager.COR_CATEGORIA[demanda.categoria], 2
	)


const AVISO_DO_ATAQUE := {
	"ligacao": ["O TELEFONE ESTÁ TOCANDO", "Corra: alcançar prende você."],
	"ocupar": ["O CHEFE VAI OCUPAR UM CANTO", "Aquele destino sai do ar."],
	"enxurrada": ["E-MAIL EM CÓPIA PARA TODOS", "Vem lixo. Nada ali é seu problema."],
	"reorganizar": ["REORGANIZAÇÃO DO ESCRITÓRIO", "Os cantos vão trocar de lugar. Releia as placas."],
}


func _ao_telegrafar(tipo: String, aviso: float) -> void:
	Juice.tremer(0.3)
	var linhas: Array = AVISO_DO_ATAQUE.get(tipo, ["ATENÇÃO", "Prepare-se."])
	get_tree().call_group("hud", "mostrar_dica", linhas[0], linhas[1], Color("e0a458"), 2)
	get_tree().call_group("hud", "alertar_bote", aviso)


func _ao_atacar(tipo: String) -> void:
	match tipo:
		"ligacao": _atacar_ligacao()
		"ocupar": _atacar_ocupar()
		"enxurrada": _atacar_enxurrada()
		"reorganizar": _atacar_reorganizar()


func _atacar_ligacao() -> void:
	var chamada := CENA_LIGACAO.instantiate()
	chamada.position = Vector2(chefe.position.x, chefe.position.y + 24.0)
	inimigos.add_child(chamada)
	Audio.tocar("notificacao", -8.0)


## O Chefe senta num canto e o desativa. Nunca no canto do quadrante que o jogador está
## carregando: bloquear justamente o destino do papel na mão seria tirar a decisão dele
## depois de já tomada.
##
## Na última fase ele ocupa DOIS cantos de uma vez. Continua sempre havendo para onde
## levar o papel da mão (a regra acima garante isso), mas a sala encolhe de verdade: o
## jogador tem de escolher qual papel do chão ainda tem destino, que é priorizar sob
## restrição em vez de priorizar no vazio.
func _atacar_ocupar() -> void:
	var quantos := 2 if chefe.fase_atual >= chefe.ATAQUES_POR_FASE.size() - 1 else 1
	for _i in quantos:
		var candidatos: Array = []
		for zona in zonas.get_children():
			if zona.bloqueado:
				continue
			if is_instance_valid(_carregando) and zona.papel == _carregando.categoria:
				continue
			candidatos.append(zona)
		if candidatos.is_empty():
			return
		var alvo = candidatos[randi() % candidatos.size()]
		alvo.bloquear(chefe.duracao_do_bloqueio)
		Feedback.onda(self, alvo.global_position, Color("c05050"), 46.0)


## O e-mail em cópia: um bloco de Q4 de uma vez, da RESERVA do orçamento (e não da fila),
## para que ele não adiante o expediente inteiro nem despeje urgências disfarçadas de lixo.
##
## Nada ali importa, e é exatamente por isso que atrapalha: entulha a sala, come o raio de
## leitura e tenta o jogador a "limpar" o que não precisava ser limpo.
func _atacar_enxurrada() -> void:
	for i in Sorteio.EMAIL_POR_ATAQUE:
		if _reserva_gasta >= Sorteio.RESERVA_EMAIL:
			return
		_reserva_gasta += 1
		_soltar_papel(
			GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE,
			_pousos[(_proximo + _reserva_gasta * 7) % _pousos.size()]
		)
	Audio.tocar("notificacao", -6.0)


## A reorganização do escritório: os dois cantos de um mesmo nível trocam de lugar.
##
## É o ataque à MEMÓRIA, e é o que o sorteio de layout sozinho não alcança: sortear a sala
## impede decorar entre partidas, mas dentro de uma partida o jogador ainda fixa "AGENDAR é
## o mezanino da direita" nos primeiros vinte segundos e para de ler as placas. Depois
## disto ele volta a ter de ler.
##
## Só troca dentro do MESMO nível, e isso não é timidez: Q2 e Q3 moram no mezanino porque a
## regra pedagógica das três fases é que o importante-e-não-urgente custe uma subida
## deliberada. Uma troca entre níveis rebaixaria a Q2 para o chão e desfaria isso. Como o
## conjunto de posições não muda — só o par quadrante↔posição —, todas as invariantes de
## geometria do sorteador continuam valendo sem precisar revalidar.
func _atacar_reorganizar() -> void:
	var niveis := [0, 1] if chefe.fase_atual >= chefe.ATAQUES_POR_FASE.size() - 1 else [randi() % 2]
	var trocou := false
	for nivel in niveis:
		var par: Array = []
		for zona in zonas.get_children():
			if int(layout["nivel"][zona.papel]) == nivel:
				par.append(zona)
		if par.size() != 2:
			continue
		_trocar(par[0], par[1])
		trocou = true

	if not trocou:
		return
	Audio.tocar("porta", -4.0)
	Juice.tremer(0.5)
	get_tree().call_group(
		"hud", "mostrar_dica", "A SALA MUDOU",
		"Os destinos trocaram de canto. Confira antes de entregar.",
		Color("e07a94"), 3
	)


## Troca duas zonas de lugar deslizando, e não em corte seco: um teleporte de placa é
## ilegível, e o jogador concluiria que leu errado antes em vez de que a sala mudou agora.
func _trocar(a: Node2D, b: Node2D) -> void:
	var destino_a := b.position
	var destino_b := a.position
	layout["cantos"][a.papel] = destino_a
	layout["cantos"][b.papel] = destino_b

	# Desligadas enquanto deslizam. Sem isto, uma zona que passasse por cima do jogador
	# parado registraria a entrega sozinha, no canto errado, sem ele ter andado até lá —
	# a mesma classe de defeito dos gatilhos sobrepostos da bifurcação Q3.
	a.bloquear(0.6)
	b.bloquear(0.6)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(a, "position", destino_a, 0.45).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(b, "position", destino_b, 0.45).set_trans(Tween.TRANS_CUBIC)
	Feedback.onda(self, a.global_position, Color("e07a94"), 40.0)
	Feedback.onda(self, b.global_position, Color("e07a94"), 40.0)


func _ao_mudar_fase_do_chefe(indice: int, nome: String) -> void:
	# A primeira fase não "apertou" nada — ela é o estado inicial. Dizer que apertou logo
	# no segundo zero ensina o jogador a ignorar a faixa, e é justamente ela que precisa
	# ser lida quando o ritmo apertar de verdade.
	var texto := "O ritmo apertou." if indice > 0 else "Leia o papel antes de escolher o canto."
	get_tree().call_group(
		"hud", "mostrar_dica", "FASE %d · %s" % [indice + 1, nome],
		texto, Color("e07a94"), 2
	)
	Audio.intensidade(chefe.aperto())


# A pilha

func _ao_mudar_pilha(unidades: int, _altura: float) -> void:
	_atualizar_piche()
	hud.definir_perigo(pilha.perigo())

	if pilha.soterrou():
		get_tree().call_group(
			"hud", "mostrar_dica", "SOTERRADO",
			"A pilha de pendências tomou a sala.", Color("c05050"), 3
		)
		GameManager.finalizar_fase(false)
		return

	if unidades == Pilha.ALERTA:
		get_tree().call_group(
			"hud", "mostrar_dica", "A PILHA ESTÁ ALTA",
			"Entregue no canto certo para baixá-la.", Color("e0a458"), 3
		)


func _atualizar_piche() -> void:
	var altura: float = pilha.altura_px()
	piche.position.y = Sorteio.Y_CHAO - altura
	piche.visible = altura > 0.5
	piche.scale.y = maxf(altura / 8.0, 0.01)


# Enunciados

## Os enunciados são sorteados dentro do quadrante, e não fixos por posição na fila: com
## texto fixo, decorar "o quinto papel é Q2" substituiria a leitura, que é justamente o
## que o sorteio existe para impedir.
##
## Todo enunciado tem de dar para classificar SEM citar o quadrante. Escrever isto bem é o
## que torna a fase jogável — é a única informação que o jogador recebe antes de decidir.
const ENUNCIADOS := {
	GameManager.Categoria.URGENTE_IMPORTANTE: [
		"Servidor da folha caiu: pagamento é hoje",
		"Cliente ao telefone: contrato vence hoje",
		"Auditoria pediu o relatório para agora",
		"Falha em produção travou o time inteiro",
		"Proposta fecha em uma hora, falta assinar",
		"Banco cobra o boleto que vence hoje",
		"Diretoria espera o número na reunião das 15h",
		"Erro de cobrança atingiu 200 clientes",
		"Nota fiscal do mês fecha em trinta minutos",
		"Sistema do cliente fora do ar desde cedo",
		"Contrato precisa de assinatura antes das 18h",
		"Vazamento de dados: responder ao jurídico hoje",
	],
	GameManager.Categoria.IMPORTANTE_NAO_URGENTE: [
		"Planejar o roadmap do próximo trimestre",
		"Testar o backup antes que ele falhe sozinho",
		"Documentar o processo que só você sabe",
		"Treinar o time no sistema novo",
		"Revisar a arquitetura antes de escalar",
		"Marcar a conversa de carreira com a equipe",
		"Organizar o plano de férias da equipe",
		"Estudar a ferramenta que vai substituir a atual",
		"Escrever o manual de quem entrar no time",
	],
	GameManager.Categoria.URGENTE_NAO_IMPORTANTE: [
		"Reunião de status sem pauta definida",
		"Preencher a planilha que outro time usa",
		"Responder convite de fornecedor para café",
		"Formatar o slide que o colega vai apresentar",
		"Conferir o pedido de material do escritório",
		"Repassar o comunicado que já foi enviado",
		"Agendar a sala para a reunião de outro time",
		"Buscar o dado que já está no relatório aberto",
		"Assinar o ponto de quem esqueceu de bater",
	],
	GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE: [
		"Notificação de rede social",
		"Corrente de e-mail sobre o amigo secreto",
		"Enquete: qual o melhor sabor de café?",
		"Vídeo engraçado no grupo do trabalho",
		"Promoção de loja que você nunca usou",
		"Debate no chat sobre o jogo de ontem",
		"Newsletter que você nunca leu",
		"Convite para webinar de assunto aleatório",
		"Foto do bolo de aniversário do quarto andar",
		"Aviso de que a máquina de café voltou",
		"Pesquisa de clima com trinta perguntas",
		"Meme sobre reunião que podia ser e-mail",
		"Sorteio de brinde de fornecedor",
		"Thread de vinte respostas com só 'ok'",
	],
}

var _usados := {}


func _enunciado(categoria: int) -> String:
	var lista: Array = ENUNCIADOS[categoria]
	var indice: int = int(_usados.get(categoria, 0))
	_usados[categoria] = indice + 1
	return lista[indice % lista.size()]
