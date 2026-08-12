extends Node2D

## O que o colega vai fazer quando chegar — o outro lado de scripts/colega.gd.
##
## Um script só para os três alvos da Fase 1 porque eles são a mesma ideia com peças
## diferentes: alguma coisa do corredor muda de estado. O que varia é a peça.
##
##   CorredorAssumido  tira duas distrações do trecho do mezanino
##   ReuniaoAssumida   tira duas distrações do trecho final
##   EscadaDelegada    torna sólido o degrau que dá acesso à última Q2
##
## Nenhum deles pontua. Isso é deliberado e é a regra de ouro do projeto: o Quadro 1 da
## Metodologia é o que foi protocolado, e delegar já vale +60 lá. Se delegar passasse a
## dar pontos extras por aqui, o jogo estaria contradizendo o texto entregue. O que o
## colega entrega é TEMPO e ACESSO — as duas moedas que a fase de fato disputa.

signal acionado

## Linha da faixa do HUD quando abre. Obrigatória quando o efeito acontece fora da tela:
## sem ela o jogador não tem como ligar causa (delegou lá atrás) e consequência (o
## corredor está diferente). Vazio = silêncio, para efeito que ele vê acontecer.
@export var mensagem: String = ""

## StaticBody2D que só passa a existir depois de acionado (a EscadaDelegada).
@export var corpo: NodePath

## Nó visual do mesmo corpo — na prática a TileMapLayer com os tiles do degrau. Fica
## fantasma enquanto fechado: o jogador precisa ver que ali PODERIA haver um degrau,
## senão a recompensa de delegar é invisível e ninguém aprende a mecânica.
@export var visual: NodePath

## Tarefas que o colega assume. Registram EVITOU (0 ponto, Quadro 1) e saem do corredor.
@export var tarefas_assumidas: Array[NodePath] = []

const ALFA_FECHADO := 0.22
const COR_AVISO := Color("7fb8ff")

var aberto := false


func _ready() -> void:
	_aplicar_corpo(false)


func esta_aberto() -> bool:
	return aberto


func acionar() -> void:
	if aberto:
		return
	aberto = true

	_aplicar_corpo(true)

	for caminho in tarefas_assumidas:
		var tarefa := get_node_or_null(caminho)
		if tarefa != null and tarefa.has_method("assumir"):
			tarefa.assumir()

	if mensagem != "":
		# Prioridade 2: acima de tarefa e checkpoint. Esta é a mensagem que explica uma
		# mudança no mundo, e perdê-la para um "TAREFA" qualquer deixaria o jogador sem
		# entender por que o corredor mudou.
		get_tree().call_group("hud", "mostrar_dica", "DELEGADO", mensagem, COR_AVISO, 2)

	Audio.tocar("porta")
	acionado.emit()


func _aplicar_corpo(ativo: bool) -> void:
	var no := get_node_or_null(corpo)
	if no != null:
		var colisor := no.get_node_or_null("CollisionShape2D")
		if colisor != null:
			colisor.set_deferred("disabled", not ativo)

	var desenho := get_node_or_null(visual)
	if desenho is CanvasItem:
		var item := desenho as CanvasItem
		if ativo:
			# Materializa com um piscar rápido em vez de aparecer seco: sem isso, quem
			# estivesse olhando para outro ponto da tela não veria que algo mudou.
			var surgir := create_tween()
			surgir.tween_property(item, "modulate:a", 1.0, 0.25)
			Juice.tremer(0.12)
		else:
			item.modulate.a = ALFA_FECHADO
