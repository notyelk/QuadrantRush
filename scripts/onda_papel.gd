extends Area2D

## "Pilha de papel": uma onda que varre o piso da Fase 3 de um lado ao outro.
##
## É o ataque que existe para OBRIGAR o uso das plataformas. Sem ele, o jogador resolveria
## a fase inteira andando no chão, e os degraus e o mezanino — que são onde moram os
## quadrantes que exigem esforço deliberado — virariam decoração.
##
## Não machuca: custa tempo e empurra, como o ladrão de tempo e a queda no vão. O Dia 3 é
## o último expediente, mas continua sendo um jogo sem morte, e o custo continua sendo a
## moeda do jogo, que é o relógio.

@export var velocidade := 190.0
@export var custo := 3.0

## Para que lado varre: +1 direita, −1 esquerda.
var rumo := 1.0

var _acertou := false


func _ready() -> void:
	body_entered.connect(_ao_tocar)
	scale.x = rumo


func _physics_process(delta: float) -> void:
	position.x += rumo * velocidade * delta
	# Sai de cena sozinha. Sem isto, cada onda vira um nó vivo para sempre e a fase
	# acumula ataques invisíveis empurrando quem passa pela borda.
	if position.x < -60.0 or position.x > 700.0:
		queue_free()


func _ao_tocar(corpo: Node2D) -> void:
	if _acertou or not corpo.is_in_group("Player") or not GameManager.em_jogo:
		return
	_acertou = true

	GameManager.descontar_tempo(custo)
	Audio.tocar("dano", -4.0)
	Juice.impacto(0.6)
	Juice.flash(Color("e0a458"), 0.18)
	# Empurra SEMPRE no sentido em que a onda anda. Empurrar para trás criaria o laço em
	# que o jogador é devolvido para dentro do ataque que acabou de o acertar — o mesmo
	# cuidado que o bote do urso já tomava no Dia 1.
	corpo.velocity.x = rumo * 240.0
	corpo.velocity.y = -170.0
	get_tree().call_group(
		"hud", "mostrar_dica", "PILHA DE PAPEL",
		"Custou %d segundos. Suba nas plataformas." % int(custo), Color("e0a458")
	)
