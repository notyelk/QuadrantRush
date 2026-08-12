extends AnimatableBody2D

## Plataforma que vai e volta entre dois pontos — Etapa 4 (level design da fase).
##
## Um salto estático se resolve uma vez e vira rotina. A plataforma móvel devolve uma
## decisão a cada travessia: espero o ciclo certo, que é seguro e custa tempo, ou pulo
## agora no meio do caminho? É a pergunta da fase inteira, expressa em geometria.
##
## AnimatableBody2D e não StaticBody2D: é o corpo feito para ser movido por script e ainda
## assim carregar quem está em cima. Com `sync_to_physics`, o move_and_slide do jogador
## cuida disso sem nenhum código no player.
##
## O movimento é senoidal e não um vaivém linear: a senoide desacelera nas pontas, dando
## mais folga para embarcar e desembarcar. Vaivém linear inverte com um tranco, e o tranco
## derruba quem está em cima.

## Deslocamento total a partir da posição de origem. Y negativo sobe.
@export var curso: Vector2 = Vector2(64, 0)

## Segundos de um ciclo completo (ida e volta).
@export var periodo: float = 3.2

## Defasagem inicial, de 0 a 1 do ciclo. Serve para duas plataformas vizinhas não
## andarem grudadas — o corredor fica com ritmo em vez de parecer um mecanismo só.
@export var defasagem: float = 0.0

## Meia-largura e meia-altura do corpo. Alimenta colisor e visual de uma vez, para
## que não seja possível ajustar um e esquecer o outro.
@export var meia_extensao: Vector2 = Vector2(24, 6)

## Pele opcional. Quando preenchida, o retângulo cinza dá lugar a um tile repetido.
##
## Existe porque a Fase 1 se passa num escritório em que um bloco cinza com faixa clara
## LÊ como plataforma de manutenção, e uma fase fora do escritório teria de trocá-la —
## o mesmo bloco lê como um buraco na tela — foi exatamente assim que ele apareceu na
## primeira foto do bosque. Nula por padrão: a Fase 1 não muda.
@export var textura: Texture2D = null

@onready var colisor: CollisionShape2D = $CollisionShape2D
@onready var corpo: ColorRect = $Corpo
@onready var luz: ColorRect = $Luz
@onready var pele: TextureRect = $Pele

var _origem := Vector2.ZERO
var _tempo := 0.0


func _ready() -> void:
	_origem = position
	_tempo = defasagem * periodo
	sync_to_physics = true

	var forma := RectangleShape2D.new()
	forma.size = meia_extensao * 2.0
	colisor.shape = forma

	corpo.size = meia_extensao * 2.0
	corpo.position = -meia_extensao
	# Faixa clara no topo: é onde o jogador pousa, e marcar a superfície útil evita
	# o erro de mirar o meio do bloco.
	luz.size = Vector2(meia_extensao.x * 2.0, 2.0)
	luz.position = Vector2(-meia_extensao.x, -meia_extensao.y)

	if textura != null:
		pele.texture = textura
		pele.size = meia_extensao * 2.0
		pele.position = -meia_extensao
		pele.visible = true
		corpo.visible = false
		luz.visible = false


func _physics_process(delta: float) -> void:
	# Congela junto com a fase: continuar andando durante a tela de resultado
	# arrastaria o jogador por baixo dela.
	if not GameManager.em_jogo:
		return
	_tempo += delta
	var fase := TAU * _tempo / maxf(periodo, 0.01)
	position = _origem + curso * sin(fase)
