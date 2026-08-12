extends CharacterBody2D

## "Ladrão de tempo" — o inimigo não-letal da Fase 1: patrulha lenta, vai e volta, não
## persegue, não mata, não reinicia a fase. Só rouba tempo.
##
## Arte: Moe Scotty (Sprite Pack 5, GrafxKid, CC0) — uma mosca. É a metáfora certa: o que
## rouba tempo no expediente é a interrupção que fica zumbindo em volta, não outra pessoa.
##
## Como voa, não tem gravidade nem colisão com o mundo: a posição é calculada direto
## (patrulha em X + balanço em Y), sem move_and_slide. Assim ele não cai num vão nem
## entala numa quina, problemas que não acrescentariam nada à mecânica.
##
## O desconto passa por descontar_tempo(), não por registrar_acao(): ele não é tarefa da
## matriz, e contá-lo como tal sujaria as notas por categoria.

@export var velocidade: float = 26.0

## Segundos descontados a cada encostão.
@export var custo_em_segundos: float = 5.0

## Empurrão horizontal aplicado no jogador, para o contato ser sentido sem tirar
## o controle dele.
@export var empurrao: float = 130.0

## Tempo de imunidade depois de um encostão — sem isso o contato contínuo drenaria
## o expediente inteiro em poucos segundos.
@export var invulnerabilidade: float = 1.0

## Quantos pixels ele anda para cada lado a partir de onde foi posicionado na fase.
@export var alcance_esquerda: float = 40.0
@export var alcance_direita: float = 40.0

## Balanço vertical do voo, em pixels e em segundos por ciclo.
@export var balanco: float = 6.0
@export var periodo_balanco: float = 1.4

@onready var hurtbox: Area2D = $Hurtbox
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

var _limite_esquerda := 0.0
var _limite_direita := 0.0
var _altura_base := 0.0
var _direcao := 1.0
var _espera := 0.0
var _fase_balanco := 0.0


func _ready() -> void:
	# A posição de onde ele nasce vira o centro da ronda. Guardar limites absolutos
	# uma única vez evita que a patrulha "escorregue" pelo cenário se algum empurrão
	# deslocar o inimigo.
	_limite_esquerda = global_position.x - absf(alcance_esquerda)
	_limite_direita = global_position.x + absf(alcance_direita)
	_altura_base = global_position.y
	if is_equal_approx(_limite_esquerda, _limite_direita):
		push_warning("LadraoDeTempo em %s: alcance zero — ele não vai patrulhar." % name)
	# Defasa o balanço pela posição para que duas moscas vizinhas não subam juntas.
	_fase_balanco = fmod(absf(global_position.x) * 0.07, TAU)
	anim.play("voar")
	hurtbox.body_entered.connect(_ao_encostar)


func _physics_process(delta: float) -> void:
	if _espera > 0.0:
		_espera -= delta

	if global_position.x <= _limite_esquerda:
		_direcao = 1.0
	elif global_position.x >= _limite_direita:
		_direcao = -1.0

	_fase_balanco += TAU * delta / maxf(periodo_balanco, 0.01)
	global_position.x += _direcao * velocidade * delta
	global_position.y = _altura_base + balanco * sin(_fase_balanco)
	anim.flip_h = _direcao < 0.0


func _ao_encostar(corpo: Node2D) -> void:
	if _espera > 0.0 or not corpo.is_in_group("Player") or not GameManager.em_jogo:
		return

	_espera = invulnerabilidade
	GameManager.descontar_tempo(custo_em_segundos)

	# Empurra para longe do ladrão, seja de que lado o jogador tenha chegado.
	var lado := signf(corpo.global_position.x - global_position.x)
	if is_zero_approx(lado):
		lado = 1.0
	if corpo is CharacterBody2D:
		var jogador := corpo as CharacterBody2D
		jogador.velocity.x = lado * empurrao
		jogador.velocity.y = -110.0

	Audio.tocar("mosca")
	Audio.tocar("dano", -8.0)
	Juice.impacto(0.5)
	Feedback.estouro(get_parent(), global_position, Color("a06cd5"), 10, 55.0)
	Feedback.pontos(get_parent(), global_position + Vector2(0, -10), "-%ds" % int(custo_em_segundos), Color("a06cd5"))
	get_tree().call_group(
		"hud", "mostrar_dica", "LADRÃO DE TEMPO",
		"Perdeu %d segundos de expediente." % int(custo_em_segundos), Color("a06cd5")
	)

	# Pisca para deixar claro que o dano já foi aplicado e há imunidade ativa.
	var piscar := create_tween()
	piscar.tween_property(anim, "modulate:a", 0.35, 0.12)
	piscar.tween_property(anim, "modulate:a", 1.0, 0.12)
