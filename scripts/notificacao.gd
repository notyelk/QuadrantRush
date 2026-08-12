extends Area2D

## A interrupção da Fase 2. Ela NÃO trava o input: o que uma interrupção custa não é o
## movimento, é a atenção. Cobra 3 segundos de expediente e apaga o enunciado de toda
## tarefa por 2,2 segundos.
##
## O apagamento é a mecânica: sem poder ler, o jogador decide no escuro se o papel que
## está caindo é urgente ou distração.
##
## O desconto passa por descontar_tempo(), por fora de registrar_acao() — interrupção não
## é tarefa da matriz e não pode sujar as notas por categoria.
##
## Aparece à frente do jogador, flutua na direção dele por alguns segundos e desiste. Não
## mata, não empurra.

signal desistiu

@export var custo_em_segundos: float = 3.0

## Segundos em que nenhum enunciado fica legível depois do encostão.
@export var cegueira: float = 2.2

@export var velocidade: float = 62.0

## Quanto tempo ela insiste antes de desistir e sumir.
@export var vida: float = 3.5

## Deslocamento, a partir da ORIGEM do jogador, do ponto que a notificação persegue.
##
## Não é zero porque a cápsula de colisão do jogador fica 7px abaixo da origem dele
## (ver player.tscn): mirar na origem deixa a notificação parada logo acima da cabeça,
## encostando em nada.
const MIRA_NO_CORPO := 4.0

## Balanço do voo — uma caixa que desliza em linha reta parece um projétil; com o
## bamboleio ela lê como algo flutuando, que é o que a distingue de uma ameaça.
const BALANCO := 5.0
const PERIODO_BALANCO := 0.9

@onready var corpo: Control = $Corpo

var _jogador: Node2D = null
var _restante := 0.0
var _fase := 0.0
var _saindo := false


func _ready() -> void:
	add_to_group("notificacao")
	_restante = vida
	var jogadores := get_tree().get_nodes_in_group("Player")
	if not jogadores.is_empty():
		_jogador = jogadores[0]

	body_entered.connect(_ao_encostar)
	Audio.tocar("notificacao", -6.0)

	# Entra crescendo: a janelinha "abre", como um pop-up de verdade.
	corpo.scale = Vector2(0.4, 0.4)
	corpo.pivot_offset = corpo.size * 0.5
	var t := create_tween()
	t.tween_property(corpo, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var pulso := create_tween().set_loops()
	pulso.tween_property(corpo, "modulate", Color(1.25, 1.25, 1.25), 0.45)
	pulso.tween_property(corpo, "modulate", Color.WHITE, 0.45)


func _physics_process(delta: float) -> void:
	if _saindo:
		return

	_restante -= delta
	if _restante <= 0.0:
		_sumir()
		return

	if _jogador == null:
		return

	_fase += TAU * delta / PERIODO_BALANCO
	var alvo := _jogador.global_position + Vector2(0, MIRA_NO_CORPO)
	var rumo := (alvo - global_position).normalized()
	global_position += rumo * velocidade * delta
	global_position.y += BALANCO * sin(_fase) * delta * TAU / PERIODO_BALANCO * 0.1


func _ao_encostar(outro: Node2D) -> void:
	if _saindo or not outro.is_in_group("Player") or not GameManager.em_jogo:
		return

	GameManager.registrar_interrupcao(custo_em_segundos, cegueira)

	Audio.tocar("notificacao")
	Audio.tocar("dano", -10.0)
	Juice.impacto(0.45)
	Juice.flash(Color("5aa9e6"), 0.14)
	Feedback.estouro(get_parent(), global_position, Color("5aa9e6"), 12, 60.0)
	Feedback.pontos(
		get_parent(), global_position + Vector2(0, -10),
		"-%ds" % int(custo_em_segundos), Color("5aa9e6")
	)

	# Prioridade 3: acima de tudo. A faixa do HUD é justamente o que a interrupção
	# sequestra — deixá-la ser atropelada por outra mensagem tiraria o efeito.
	get_tree().call_group(
		"hud", "mostrar_dica", "INTERRUPÇÃO",
		"Você parou para olhar. -%ds e perdeu o fio da leitura." % int(custo_em_segundos),
		Color("5aa9e6"), 3
	)

	_sumir()


## Some encolhendo, seja por desistência ou por ter acertado. Desliga a colisão antes
## do tween para não disparar duas vezes durante os 0,2s da saída.
func _sumir() -> void:
	if _saindo:
		return
	_saindo = true
	set_deferred("monitoring", false)
	desistiu.emit()

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(corpo, "scale", Vector2(0.3, 0.3), 0.18)
	t.tween_property(corpo, "modulate:a", 0.0, 0.18)
	t.chain().tween_callback(queue_free)
