extends Camera2D

## Câmera desacoplada do Player — localiza o alvo pelo grupo "Player" em vez de
## depender de parentesco na árvore de cena, assim a mesma cena de câmera serve pra
## qualquer fase (só ajustando "Limit"/"Position" por instância).
##
## Ela não copia a posição do jogador: centralizar mostra tanto corredor para trás quanto
## para frente, o pior enquadramento possível num jogo de correr fugindo de algo.
##
##   OLHAR À FRENTE   adianta-se na direção da corrida, com suavização para que trocar de
##                    direção não dê solavanco
##   OLHAR PARA BAIXO na queda desce mais, para ver onde se vai aterrissar
##   TREMOR           soma o deslocamento publicado pelo Juice, DEPOIS da suavização —
##                    tremor amortecido não é tremor

## Quanto a câmera se adianta, em pixels, com o jogador em velocidade máxima.
@export var olhar_a_frente := 42.0
## Quanto ela desce quando o jogador está caindo rápido.
@export var olhar_abaixo := 22.0
## Velocidade de convergência do deslocamento (maior = mais colada, menos suave).
@export var suavidade := 3.2

var target: Node2D

var _desvio := Vector2.ZERO
var _base := Vector2.ZERO


func _ready() -> void:
	_find_target()
	make_current()
	if target != null:
		_base = target.position


func _process(delta: float) -> void:
	if target == null:
		return

	_base = target.position
	_desvio = _desvio.lerp(_calcular_desvio(), clampf(suavidade * delta, 0.0, 1.0))
	# O tremor entra por fora da suavização, de propósito (ver cabeçalho).
	position = _base + _desvio + Juice.deslocamento()
	rotation = Juice.rotacao()


func _calcular_desvio() -> Vector2:
	var v: Vector2 = target.velocity if "velocity" in target else Vector2.ZERO
	var vel_max: float = target.max_speed if "max_speed" in target else 180.0

	var x := clampf(v.x / maxf(vel_max, 1.0), -1.0, 1.0) * olhar_a_frente
	# Só olha para baixo na queda. Olhar para cima no pulo faria o chão sumir bem
	# na hora em que o jogador precisa mirar o pouso.
	var y := clampf(v.y / 400.0, 0.0, 1.0) * olhar_abaixo
	return Vector2(x, y)


func _find_target() -> void:
	var nodes := get_tree().get_nodes_in_group("Player")
	if nodes.is_empty():
		push_error("Camera: nenhum nó no grupo 'Player' encontrado.")
		return
	target = nodes[0]
