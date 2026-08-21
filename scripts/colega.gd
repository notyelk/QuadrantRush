extends Node2D

## O colega que recebe a tarefa delegada — Etapa 4 da Metodologia (sistema de tarefas),
## objetivo ii do TCC (ambiente de trabalho interativo).
##
## Sem ele, delegar uma Q3 valia +60 contra +40 de resolver e mais nada — vinte pontos num
## placar de mil não fazem ninguém subir na bandeja. Com o colega, delegar muda o corredor
## adiante: ele levanta da bandeja, desce, caminha até um alvo e o aciona.
##
## O Quadro 1 não muda: delegar continua valendo +60 sem custo de tempo. O que mudou foi a
## geometria do que vem depois.
##
## Ele anda a 140 px/s, abaixo dos 180 do jogador, e é daí que vem a profundidade: quem
## corre reto chega ao alvo antes dele e encontra tudo como estava; quem se desviou para o
## mezanino chega depois e encontra o caminho feito. A conta é conferida duas vezes, pelo
## validador de tools/gerar_fase_01.py e pela suíte da Fase 1.

## Nó que ele vai acionar ao chegar. Precisa ter um método `acionar()` — na prática é
## sempre um scripts/alvo_delegado.gd.
@export var alvo: NodePath

## 140 px/s. Menor que os 180 do jogador de propósito (ver o comentário do topo).
@export var velocidade: float = 140.0

## Altura em que ele caminha depois de descer da bandeja: o topo do piso da fase.
@export var chao_y: float = 176.0

## Tempo do pulinho da bandeja até o chão. Entra na conta como atraso dele, ou seja,
## trabalha CONTRA o colega — o que mantém a estimativa do validador conservadora.
const DURACAO_DESCIDA := 0.4
const DISTANCIA_DESCIDA := 14.0

## Sonda de chão: de quanto em quanto o percurso é medido, até onde ela procura para
## baixo, e o maior vão que ele pula. Ele não tem corpo físico, então sem isso atravessa
## um buraco do corredor caminhando no ar.
const PASSO_DA_SONDA := 8.0
const ALCANCE_DA_SONDA := 220.0
const MAIOR_VAO := 160.0
const ALTURA_DO_PULO := 22.0
const CAMADA_DO_MUNDO := 1

enum Estado { SENTADO, DESCENDO, ANDANDO, CHEGOU }

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var papel: Sprite2D = $Papel

var estado := Estado.SENTADO
var _origem := Vector2.ZERO
var _destino := Vector2.ZERO
var _rumo := 1.0
var _tempo := 0.0
## Bordas do vão que ele está atravessando: x e y de onde saiu e de onde vai cair.
## _vao_de.x < 0 significa que ele está em terra firme.
var _vao_de := Vector2(-1.0, 0.0)
var _vao_para := Vector2(-1.0, 0.0)


func _ready() -> void:
	papel.visible = false
	anim.play("idle")
	# Enquanto ninguém delegou, ele não custa quadro nenhum de física.
	set_physics_process(false)


## Chamado pela bifurcação Q3 no instante em que o jogador escolhe DELEGAR.
## Idempotente: delegar duas vezes na mesma Q3 é impossível (a bifurcação se desliga),
## mas o guarda evita que um teste ou um sinal repetido reinicie o percurso.
func despachar() -> void:
	if estado != Estado.SENTADO:
		return

	var no := get_node_or_null(alvo)
	if no == null:
		push_warning("Colega sem alvo válido: %s" % alvo)
		return

	_origem = global_position
	_destino = (no as Node2D).global_position
	_rumo = signf(_destino.x - _origem.x)
	if is_zero_approx(_rumo):
		_rumo = 1.0
	_tempo = 0.0
	estado = Estado.DESCENDO
	papel.visible = true
	anim.play("walk")
	anim.flip_h = _rumo < 0.0
	papel.position.x = absf(papel.position.x) * _rumo
	set_physics_process(true)
	Audio.tocar("delegar")


## A Q3 dele foi resolvida no chão: ele sai de cena. Deixá-lo desbotado na bandeja é o
## mesmo que deixar um convite que não responde a nada.
func dispensar() -> void:
	if estado != Estado.SENTADO:
		return
	var apagar := create_tween()
	apagar.tween_property(self, "modulate:a", 0.0, 0.3)
	apagar.tween_callback(hide)


func esta_a_caminho() -> bool:
	return estado == Estado.DESCENDO or estado == Estado.ANDANDO


func ja_chegou() -> bool:
	return estado == Estado.CHEGOU


func _physics_process(delta: float) -> void:
	match estado:
		Estado.DESCENDO:
			_descer(delta)
		Estado.ANDANDO:
			_andar(delta)


## Pulinho da bandeja até o chão. Parábola simples em vez de física: o colega não tem
## corpo nem colisor — ele atravessa plataforma, tarefa e jogador sem interagir com
## nada. Isso é decisão de projeto, não preguiça: um NPC com colisão no meio de um
## corredor calibrado ao pixel viraria parede móvel e quebraria travessias que os testes
## de geometria dão como garantidas.
func _descer(delta: float) -> void:
	_tempo += delta
	var t := minf(_tempo / DURACAO_DESCIDA, 1.0)
	var destino_x := _origem.x + DISTANCIA_DESCIDA * _rumo
	global_position.x = lerpf(_origem.x, destino_x, t)
	# Arco: sobe um pouco antes de cair, senão parece que ele escorregou.
	var altura := _origem.y - 10.0 * sin(t * PI)
	global_position.y = lerpf(altura, chao_y, t * t)
	if t >= 1.0:
		global_position.y = chao_y
		estado = Estado.ANDANDO


func _andar(delta: float) -> void:
	global_position.x = move_toward(global_position.x, _destino.x, velocidade * delta)
	_acompanhar_o_chao()
	if not is_equal_approx(global_position.x, _destino.x):
		return

	estado = Estado.CHEGOU
	set_physics_process(false)
	papel.visible = false
	anim.play("idle")

	var no := get_node_or_null(alvo)
	if no != null and no.has_method("acionar"):
		no.acionar()


## Mantém o colega em cima do piso que existe, e o faz saltar os vãos em vez de caminhar
## sobre eles. A altura vem sempre de uma superfície real; sem isso o corredor do Dia 2,
## que tem dois buracos entre a bandeja e o alvo, o mostraria pisando no ar.
func _acompanhar_o_chao() -> void:
	var aqui := _chao_em(global_position.x)
	if aqui < INF:
		_vao_de.x = -1.0
		global_position.y = aqui
		return

	if _vao_de.x < 0.0:
		_vao_de = Vector2(global_position.x, global_position.y)
		_vao_para = _outra_margem(global_position.x)

	var largura := _vao_para.x - _vao_de.x
	if absf(largura) < 1.0:
		return
	var t := clampf((global_position.x - _vao_de.x) / largura, 0.0, 1.0)
	global_position.y = lerpf(_vao_de.y, _vao_para.y, t) - ALTURA_DO_PULO * sin(t * PI)


## Altura de caminhada sobre o piso deste x, ou INF se ali não há piso nenhum.
func _chao_em(x: float) -> float:
	var consulta := PhysicsRayQueryParameters2D.create(
		Vector2(x, global_position.y - 24.0),
		Vector2(x, global_position.y + ALCANCE_DA_SONDA),
		CAMADA_DO_MUNDO
	)
	var golpe := get_world_2d().direct_space_state.intersect_ray(consulta)
	if golpe.is_empty() or (golpe["normal"] as Vector2).y > -0.7:
		return INF
	return (golpe["position"] as Vector2).y


## Primeiro ponto com piso adiante do vão. Sem nada em MAIOR_VAO pixels, devolve o fim
## dessa distância na altura de agora — melhor um salto longo do que um travamento.
func _outra_margem(x: float) -> Vector2:
	var avanco := PASSO_DA_SONDA
	while avanco <= MAIOR_VAO:
		var alvo_x := x + avanco * _rumo
		var chao := _chao_em(alvo_x)
		if chao < INF:
			return Vector2(alvo_x, chao)
		avanco += PASSO_DA_SONDA
	return Vector2(x + MAIOR_VAO * _rumo, global_position.y)
