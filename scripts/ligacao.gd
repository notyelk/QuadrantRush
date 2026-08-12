extends Area2D

## "Só um minutinho": um telefone que persegue devagar e, ao alcançar, prende o jogador.
##
## Por que congelar, e não descontar
## A Fase 3 já cobra tempo em dois lugares (a onda e a pilha). Um terceiro desconto seria
## mais do mesmo. O que a ligação rouba é o recurso que a fase realmente disputa: os
## segundos em que o jogador estaria DECIDINDO. Ficar preso 1,5 s enquanto três papéis
## envelhecem no chão dói de um jeito que −3 s no relógio não doeria.
##
## Ela é lenta de propósito (60 px/s contra os 180 do jogador): é sempre possível fugir. O
## que ela cobra de quem foge é a rota — você para de ir para onde precisava ir. Isso é
## interrupção, e é exatamente o que o Dia 2 ensinou.

@export var velocidade := 60.0
@export var prisao := 1.5

## Vida máxima, para que uma ligação que nunca alcança ninguém não fique eterna na tela.
@export var duracao := 12.0

var _alvo: Node2D = null
var _restante := 0.0
var _acertou := false


func _ready() -> void:
	_restante = duracao
	body_entered.connect(_ao_tocar)
	var jogadores := get_tree().get_nodes_in_group("Player")
	if not jogadores.is_empty():
		_alvo = jogadores[0]


func _physics_process(delta: float) -> void:
	_restante -= delta
	if _restante <= 0.0 or _acertou:
		if _restante <= 0.0:
			queue_free()
		return
	if _alvo == null or not is_instance_valid(_alvo):
		return

	var rumo := (_alvo.global_position - global_position).normalized()
	global_position += rumo * velocidade * delta
	rotation = sin(Time.get_ticks_msec() * 0.008) * 0.25


func _ao_tocar(corpo: Node2D) -> void:
	if _acertou or not corpo.is_in_group("Player") or not GameManager.em_jogo:
		return
	_acertou = true

	Audio.tocar("notificacao", -3.0)
	Juice.tremer(0.3)
	get_tree().call_group(
		"hud", "mostrar_dica", "SÓ UM MINUTINHO",
		"Preso na ligação por %.1fs. Os papéis continuam envelhecendo." % prisao,
		Color("6fa8d6")
	)

	# `controlavel` é o mesmo interruptor que a fase usa ao terminar; reaproveitá-lo evita
	# inventar um segundo caminho para "o jogador não responde".
	if "controlavel" in corpo:
		corpo.controlavel = false
		corpo.velocity.x = 0.0
	await get_tree().create_timer(prisao).timeout
	if is_instance_valid(corpo) and "controlavel" in corpo:
		corpo.controlavel = true

	queue_free()
