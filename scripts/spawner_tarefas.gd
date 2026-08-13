extends Node2D

## A agenda do dia — Etapa 4 da Metodologia, literalmente: *"criação do mecanismo de
## geração (spawn) das quatro categorias de tarefa ao longo da fase"*.
##
## Na Fase 1 as tarefas estão paradas no corredor e o jogador escolhe em que ordem chega
## nelas. Aqui elas CHEGAM: nascem à frente dele, descem à vista e pousam. É a diferença
## entre organizar uma mesa e atender uma caixa de entrada.
##
## O gatilho é POSIÇÃO, não relógio: cada entrada dispara quando o jogador passa de um x.
## Assim a fase tem sempre a mesma composição, e quem corre e quem anda devagar enfrentam
## as mesmas tarefas — sem isso o placar mediria pressa em vez de prioridade, e o ranking
## da Etapa 7 deixaria de comparar. De quebra, torna a fase reproduzível em teste, e nada
## nasce em cima do jogador: tudo entra pela borda direita e desce à vista.
##
## Quem monta a agenda é a fase; aqui mora só o mecanismo.

## Uma tarefa da matriz (usa scenes/tasks/tarefa.tscn).
const TAREFA := "tarefa"
## Uma interrupção (usa entities/notificacao.tscn).
const NOTIFICACAO := "notificacao"

const CENA_TAREFA := preload("res://scenes/tasks/tarefa.tscn")
const CENA_NOTIFICACAO := preload("res://entities/notificacao.tscn")
const Enunciados := preload("res://scripts/enunciados.gd")

signal chegou(no: Node2D, entrada: Dictionary)

## Onde os nós nascidos são pendurados. Tarefas precisam ir para o mesmo pai das
## tarefas fixas, senão a arbitragem de rótulo entre tarefas vizinhas e a contagem da
## fase deixariam de enxergá-las.
@export var destino_tarefas: NodePath
@export var destino_notificacoes: NodePath

## Velocidade de queda das tarefas que chegam, em px/s.
@export var velocidade_de_queda: float = 150.0

## Quantas entradas da agenda já entraram em cena. Contar aqui, e não pelos filhos do
## nó Tarefas, é o que permite conferir a agenda depois: uma tarefa coletada some da
## árvore, e o nó Tarefas ainda recebe os textos flutuantes do Feedback.
var produzidas := 0

var _agenda: Array = []
var _proxima := 0
var _jogador: Node2D = null


func _ready() -> void:
	var jogadores := get_tree().get_nodes_in_group("Player")
	if not jogadores.is_empty():
		_jogador = jogadores[0]


## Recebe a agenda já pronta e a ordena pelo gatilho. Ordenar aqui, e não confiar na
## ordem em que foi escrita, é o que permite mexer numa entrada isolada sem quebrar as
## outras — o ponteiro só anda para a frente.
func definir_agenda(entradas: Array) -> void:
	_agenda = entradas.duplicate(true)
	_agenda.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("gatilho", 0.0)) < float(b.get("gatilho", 0.0))
	)
	_proxima = 0
	produzidas = 0


func _physics_process(_delta: float) -> void:
	if _jogador == null or _proxima >= _agenda.size() or not GameManager.em_jogo:
		return

	var x := _jogador.global_position.x
	# while, e não if: um teleporte de teste pode atravessar vários gatilhos de uma vez,
	# e a fase precisa ficar completa mesmo assim.
	while _proxima < _agenda.size() and x >= float(_agenda[_proxima].get("gatilho", 0.0)):
		_produzir(_agenda[_proxima])
		_proxima += 1


## Quantas tarefas de cada categoria a agenda ainda vai apresentar. A fase soma isto às
## tarefas fixas do corredor para montar o "X de N" do relatório final — sem isso, o
## relatório diria "2 de 2" numa fase em que existiam sete urgentes.
func composicao_prevista() -> Dictionary:
	var mapa := {}
	for categoria in GameManager.Categoria.values():
		mapa[categoria] = 0
	for entrada in _agenda:
		if entrada.get("tipo", TAREFA) == TAREFA:
			mapa[int(entrada["categoria"])] += 1
	return mapa


## Quantas interrupções a agenda contém. Só para o teste e para o relatório.
func total_de_notificacoes() -> int:
	var n := 0
	for entrada in _agenda:
		if entrada.get("tipo", TAREFA) == NOTIFICACAO:
			n += 1
	return n


## Põe uma tarefa em cena FORA da agenda, agora, e devolve o nó criado.
##
## Existe para a maturação de pendências do Dia 2: uma crise não estava na agenda do dia
## — ela nasceu de uma decisão do jogador. Por isso ela não entra em `produzidas` nem em
## `composicao_prevista()`: essas duas respondem "o que este dia apresenta a todo mundo",
## que é o que torna dois placares comparáveis no ranking da Etapa 7. Misturar as crises
## ali faria a mesma fase parecer ter composições diferentes conforme quem jogou.
func produzir_avulsa(entrada: Dictionary) -> Node2D:
	# Sem sorteio: uma crise já traz o enunciado que a Q2 adiada virou, e trocá-lo
	# apagaria a única coisa que liga a crise à tarefa que a originou.
	return _produzir_tarefa(entrada, false)


func _produzir(entrada: Dictionary) -> void:
	produzidas += 1
	if entrada.get("tipo", TAREFA) == NOTIFICACAO:
		_produzir_notificacao(entrada)
	else:
		_produzir_tarefa(entrada)


func _produzir_tarefa(entrada: Dictionary, sortear := true) -> Node2D:
	var pai := get_node_or_null(destino_tarefas)
	if pai == null:
		push_warning("Spawner sem destino_tarefas: a agenda não vai aparecer.")
		return null

	var tarefa: Area2D = CENA_TAREFA.instantiate()
	tarefa.categoria = int(entrada["categoria"])
	tarefa.texto = str(entrada.get("texto", ""))
	tarefa.texto_maduro = str(entrada.get("texto_maduro", ""))

	# Do mesmo saco das tarefas paradas do corredor, embaralhado uma vez por expediente
	# em FaseBase — é o que impede decorar quais enunciados o dia apresenta.
	if sortear:
		var sorteado := Enunciados.sacar(tarefa.categoria)
		tarefa.texto = sorteado[0]
		if not tarefa.texto_maduro.is_empty():
			tarefa.texto_maduro = sorteado[1]
	tarefa.amplitude = entrada.get("amplitude", Vector2.ZERO)
	tarefa.periodo = float(entrada.get("periodo", 2.0))
	tarefa.queda = velocidade_de_queda
	tarefa.pousa = float(entrada["pousa"])
	tarefa.position = Vector2(float(entrada["x"]), float(entrada.get("y", -24.0)))

	pai.add_child(tarefa)
	Audio.tocar("chegada", -10.0)
	chegou.emit(tarefa, entrada)
	return tarefa


func _produzir_notificacao(entrada: Dictionary) -> void:
	var pai := get_node_or_null(destino_notificacoes)
	if pai == null:
		return

	var nota: Area2D = CENA_NOTIFICACAO.instantiate()
	nota.position = Vector2(float(entrada["x"]), float(entrada.get("y", 60.0)))
	# Cada interrupção pode ter o próprio preço e a própria insistência. É o que permite ao
	# Dia 2 escalar ao longo do corredor — a primeira do dia avisa, a do fim castiga — sem
	# precisar de uma cena de notificação por intensidade.
	for campo in ["vida", "custo_em_segundos", "cegueira", "velocidade"]:
		if entrada.has(campo):
			nota.set(campo, float(entrada[campo]))

	pai.add_child(nota)
	chegou.emit(nota, entrada)
