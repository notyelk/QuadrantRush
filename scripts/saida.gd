extends Node2D

## O elevador do fim do expediente — condição de vitória da fase (Etapa 5:
## "regras de finalização").
##
## Nasce TRANCADO: um StaticBody2D barra a passagem enquanto houver tarefa Q1
## (urgente e importante) não coletada. É isso que impede o jogador de simplesmente
## correr até o fim ignorando a mecânica — as obrigatórias do Quadro 1 são de fato
## obrigatórias.
##
## A saída não conta as Q1 sozinha: quem sabe quantas existem e quantas foram
## coletadas é fase_01.gd, que chama liberar() no momento certo.

signal alcancada
## Emitido quando o jogador chega ao elevador e ele ainda está trancado. Quem decide o
## que isso significa é a fase: se ainda houver urgente ao alcance é aviso, se não
## houver mais nenhuma o dia acabou.
signal barrada

@onready var bloqueio: StaticBody2D = $Bloqueio
@onready var gatilho: Area2D = $Gatilho
## Lâmpada acima da porta: vermelha enquanto trancada, verde ao liberar. É a única
## pista visual de que a saída depende das Q1, então não pode depender do HUD.
@onready var luz: Polygon2D = $Luz

var liberada := false

## Quantas urgentes ainda faltam. A saída não conta nada sozinha — quem sabe é a fase, que
## atualiza este número a cada coleta.
##
## A porta trancada diz QUANTAS faltam, e não só "resolva as urgentes": repetir uma
## instrução genérica é inútil justamente no momento em que o jogador já acha que
## terminou.
var pendentes := 0

## O pulso da lâmpada, guardado para poder ser parado se a saída trancar de novo.
var _pulso: Tween = null

## Desligada por desativar(). Uma fase sem elevador não pode ter a porta liberada por
## efeito colateral de coletar uma urgente.
var _desativada := false


func _ready() -> void:
	gatilho.body_entered.connect(_ao_entrar)
	_atualizar_luz()


## Tira o elevador da fase. A Fase 3 é uma arena de tela única em que sobreviver ao
## relógio é a vitória: uma porta ali seria um botão de encerrar o expediente sem
## enfrentá-lo.
func desativar() -> void:
	_desativada = true
	visible = false
	bloqueio.get_node("CollisionShape2D").set_deferred("disabled", true)
	gatilho.set_deferred("monitoring", false)


## Chamada por fase_01.gd quando todas as Q1 foram coletadas.
func liberar() -> void:
	if liberada or _desativada:
		return
	liberada = true
	# set_deferred: desligar colisão no meio do processamento de física do Godot
	# dispara erro de "flushing queries".
	bloqueio.get_node("CollisionShape2D").set_deferred("disabled", true)
	bloqueio.visible = false
	_atualizar_luz()

	# A lâmpada pulsa até o fim da fase: é o farol que puxa o jogador para a saída
	# de qualquer ponto do corredor, sem depender de o HUD estar sendo lido.
	_pulso = create_tween().set_loops()
	_pulso.tween_property(luz, "scale", Vector2(1.4, 1.4), 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulso.tween_property(luz, "scale", Vector2.ONE, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	get_tree().call_group(
		"hud", "mostrar_dica", "EXPEDIENTE LIBERADO",
		"Todas as urgentes resolvidas — o elevador abriu.", Color("8fd6a8")
	)


## Volta a trancar. Existe por causa do Dia 2: uma pendência adiada pode amadurecer
## DEPOIS de a cota de urgentes já ter sido cumprida, e sem isto adiar no fim do
## expediente sairia de graça — o elevador já estaria aberto e a crise nova seria
## decorativa. Trancar de novo é o que mantém a regra honesta em qualquer momento do dia.
##
## Não é penalidade nova: o contrato do elevador sempre foi "as urgentes são
## obrigatórias", e amadurecer cria uma urgente a mais. A porta só volta ao estado que
## corresponde à conta.
func trancar() -> void:
	if not liberada or _desativada:
		return
	liberada = false
	bloqueio.get_node("CollisionShape2D").set_deferred("disabled", false)
	bloqueio.visible = true
	if _pulso != null and _pulso.is_valid():
		_pulso.kill()
	_pulso = null
	luz.scale = Vector2.ONE
	_atualizar_luz()


func _ao_entrar(corpo: Node2D) -> void:
	if _desativada or not corpo.is_in_group("Player") or not GameManager.em_jogo:
		return

	if not liberada:
		barrada.emit()
		# A fase pode ter encerrado o expediente aqui. Chegar ao elevador sem nenhuma
		# urgente ao alcance não é um aviso: não há mais o que voltar a resolver.
		if not GameManager.em_jogo:
			return

		Audio.tocar("travado")
		Juice.tremer(0.2)
		var texto := "Resolva as tarefas urgentes e importantes antes de sair."
		if pendentes == 1:
			texto = "Falta 1 urgente para trás. Volte e resolva."
		elif pendentes > 1:
			texto = "Faltam %d urgentes para trás. Volte e resolva." % pendentes
		get_tree().call_group(
			"hud", "mostrar_dica", "ELEVADOR TRANCADO", texto,
			GameManager.COR_CATEGORIA[GameManager.Categoria.URGENTE_IMPORTANTE], 3
		)
		return

	alcancada.emit()
	GameManager.finalizar_fase(true)


func _atualizar_luz() -> void:
	luz.modulate = Color("8fd6a8") if liberada else Color("e05c5c")
