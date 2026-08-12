extends Node

## Efeitos de sensação (game feel) que não pertencem a nenhuma cena específica:
## tremor de câmera, congelamento de impacto e flash de tela.
##
## Autoload porque quem causa o efeito quase nunca é quem o desenha: o urso acerta e quem
## treme é a câmera. Cada entidade só declara a intensidade — Juice.impacto(0.9) — e os
## desenhistas leem daqui, sem referência cruzada.
##
## O tremor é por "trauma" e não por duração: um acumulador (0..1) que decai sozinho, com
## deslocamento proporcional ao QUADRADO dele. Com duração fixa, dois impactos seguidos ou
## se engolem ou se somam até virar epilepsia. O quadrado dá a curva que o olho espera —
## tremor fraco quase imperceptível, tremor forte violento.

## Quanto de trauma some por segundo. 1.8 dá um tremor de ~0,5s no impacto forte.
const DECAIMENTO := 1.8

## Deslocamento máximo em pixels, com trauma = 1. Comedido de propósito: o viewport
## tem 400x208px, então 6px já é bastante coisa na tela.
const DESLOCAMENTO_MAXIMO := 6.0

## Rotação máxima em radianos, com trauma = 1. Um giro mínimo faz o tremor parecer
## físico em vez de "a imagem está vibrando".
const ROTACAO_MAXIMA := 0.035

var trauma := 0.0

var _ruido := FastNoiseLite.new()
var _semente := 0.0
var _flash: ColorRect
var _congelando := false


func _ready() -> void:
	# Roda mesmo com a árvore pausada: o congelamento de impacto precisa se
	# desfazer sozinho, e a tela de resultado pausa o jogo.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ruido.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ruido.frequency = 0.6
	_montar_flash()


func _process(delta: float) -> void:
	# Tempo real: com Engine.time_scale = 0 no congelamento, delta chega zerado e o
	# trauma nunca decairia.
	var real := delta / maxf(Engine.time_scale, 0.001)
	trauma = maxf(trauma - DECAIMENTO * real, 0.0)
	_semente += real * 60.0


## Ponto de entrada único para "algo bateu". forca de 0 a 1.
## Acima de 0.5 o impacto também congela a imagem por um instante — o freeze frame
## é o que dá peso à pancada; sem ele o tremor sozinho parece enfeite.
func impacto(forca: float) -> void:
	forca = clampf(forca, 0.0, 1.0)
	tremer(forca)
	if forca >= 0.5:
		congelar(lerpf(0.04, 0.11, forca))


## Só o tremor, sem congelar. Usado por coisas frequentes (pouso pesado, coleta)
## que não podem interromper o fluxo.
func tremer(forca: float) -> void:
	trauma = minf(trauma + clampf(forca, 0.0, 1.0), 1.0)


## Congela a imagem por alguns milissegundos. É medido em tempo REAL (o quarto
## argumento de create_timer), senão o próprio timer congelaria junto e o jogo
## nunca voltaria.
func congelar(segundos: float) -> void:
	if _congelando:
		return
	_congelando = true
	Engine.time_scale = 0.0
	await get_tree().create_timer(segundos, true, false, true).timeout
	Engine.time_scale = 1.0
	_congelando = false


## Pisca a tela inteira. Usado com parcimônia: acerto do urso, fim de expediente.
func flash(cor: Color, duracao: float = 0.18) -> void:
	if _flash == null:
		return
	_flash.color = Color(cor.r, cor.g, cor.b, 0.0)
	var t := create_tween()
	t.tween_property(_flash, "color:a", 0.42, duracao * 0.25)
	t.tween_property(_flash, "color:a", 0.0, duracao * 0.75)


## Deslocamento que a câmera deve somar à própria posição neste frame.
## Ruído coerente em vez de random(): dois valores sorteados por frame dão uma
## vibração serrilhada e barata; o ruído dá um movimento contínuo, como um tranco.
func deslocamento() -> Vector2:
	if trauma <= 0.0:
		return Vector2.ZERO
	var intensidade := trauma * trauma
	return Vector2(
		_ruido.get_noise_2d(_semente, 0.0),
		_ruido.get_noise_2d(0.0, _semente)
	) * DESLOCAMENTO_MAXIMO * intensidade


func rotacao() -> float:
	if trauma <= 0.0:
		return 0.0
	return _ruido.get_noise_2d(_semente, 1000.0) * ROTACAO_MAXIMA * trauma * trauma


func _montar_flash() -> void:
	var camada := CanvasLayer.new()
	# Acima do HUD (que fica na camada padrão 0/1) para que o flash cubra tudo.
	camada.layer = 90
	camada.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(camada)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	camada.add_child(_flash)
