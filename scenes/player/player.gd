extends CharacterBody2D

## Controlador do personagem: máquina de estados Idle, Run, Jump, Fall.
##
## Requer as ações "left", "right", "jump" no Input Map (Project Settings → Input Map).
##
## Traz coyote time, jump buffer, pulo de altura variável, gravidade assimétrica e atrito
## separado chão/ar. Nada disso altera o alcance do pulo com o botão segurado, que é o
## número contra o qual a geometria das fases é validada.

## Emitido ao pousar depois de uma queda relevante — a fase usa para poeira e som.
signal pousou(forca: float)
signal pulou()

enum PlayerState { IDLE, RUN, JUMP, FALL }

const JUMP_VELOCITY := -350.0

## Queda a partir da qual o pouso vira impacto (poeira, squash, som mais forte).
const QUEDA_FORTE := 260.0

@export_group("Movimento")
@export var max_speed := 180.0
## Aceleração no chão. Alta de propósito: a velocidade máxima é atingida em ~0,13s,
## o que faz o personagem responder ao toque em vez de "dar partida".
@export var acceleration := 1400.0
## Desaceleração no chão — maior que a aceleração para que soltar o direcional pare
## quase na hora. É isso que permite parar em cima de uma plataforma estreita.
@export var deceleration := 1900.0
## No ar o jogador tem menos autoridade: dá para corrigir a trajetória, não para
## trocar de direção instantaneamente. Mantém o pulo com peso de compromisso.
@export var aceleracao_ar := 900.0
@export var desaceleracao_ar := 450.0

@export_group("Pulo")
## Janela em que ainda dá para pular depois de sair da beirada (item 1 acima).
@export var coyote := 0.10
## Janela em que um pulo apertado cedo demais fica guardado (item 2 acima).
@export var buffer_pulo := 0.12
## Quanto sobra da velocidade de subida ao soltar o botão (item 3 acima).
@export var corte_pulo := 0.42
## Multiplicador de gravidade na queda (item 4 acima). 1.0 = simétrico.
@export var gravidade_queda := 1.45
## Teto de velocidade de queda: sem isso, cair num vão fundo vira um borrão e o
## jogador perde a noção de onde vai pousar.
@export var velocidade_queda_max := 460.0

var state: PlayerState = PlayerState.IDLE
var direction := 0.0

## Desligado pela fase durante o congelamento de impacto e nas telas de fim — o
## jogador para de responder sem que ninguém precise mexer no process do nó.
var controlavel := true

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var poeira_corrida: CPUParticles2D = $PoeiraCorrida
@onready var poeira_pouso: CPUParticles2D = $PoeiraPouso

var _coyote_restante := 0.0
var _buffer_restante := 0.0
var _no_chao_antes := true
var _velocidade_queda := 0.0
## Offset original do sprite. O squash escala a partir dos pés, e para isso o offset
## precisa ser recalculado a cada frame a partir da escala (ver _aplicar_squash).
var _offset_base := Vector2.ZERO
var _escala_alvo := Vector2.ONE
var _proximo_passo := 0.0


func _ready() -> void:
	_offset_base = anim.offset
	_go_to_idle()


func _physics_process(delta: float) -> void:
	_ler_entrada()
	_atualizar_temporizadores(delta)
	_aplicar_gravidade(delta)

	match state:
		PlayerState.IDLE:
			_idle_state(delta)
		PlayerState.RUN:
			_run_state(delta)
		PlayerState.JUMP:
			_jump_state(delta)
		PlayerState.FALL:
			_fall_state(delta)

	# O buffer é consumido em qualquer estado: se havia um pulo guardado e o
	# personagem acabou de ganhar chão (ou coyote), ele sai agora.
	if _buffer_restante > 0.0 and _pode_pular():
		_go_to_jump()

	move_and_slide()
	_checar_pouso()
	_aplicar_squash(delta)
	_atualizar_poeira()
	_atualizar_passos(delta)


## Entrada lida por sondagem dentro do passo de física, e não em _unhandled_input, por
## coerência de tempo e por testabilidade: coyote time, jump buffer e corte de pulo são
## medidos em passos de física, e `Input.action_press()` — que o percurso automatizado usa
## — muda o estado das ações mas não sintetiza InputEvent. Com _unhandled_input, o robô do
## teste andava mas nunca pulava.
func _ler_entrada() -> void:
	if not controlavel:
		direction = 0.0
		GameManager.alternar_foco(false)
		return

	direction = Input.get_axis("left", "right")

	# Foco é botão SEGURADO, não alternador.
	#
	# Com alternador, quem esquecesse a tecla ligada arrastaria o dia inteiro a 65% sem
	# entender por quê e culparia o jogo. Segurando, o custo é sentido continuamente e a
	# saída é soltar — que é a mesma lógica do botão de andar devagar em plataforma
	# clássico.
	GameManager.alternar_foco(Input.is_action_pressed("focar"))

	# Metade "entrada" do jump buffer: guarda a intenção mesmo quando ainda não é
	# possível pular. A metade "saída" está no fim de _physics_process.
	if Input.is_action_just_pressed("jump"):
		_buffer_restante = buffer_pulo
	elif Input.is_action_just_released("jump") and velocity.y < 0.0:
		# Pulo de altura variável: soltar cedo corta a subida em vez de cancelar,
		# para que um toque curto ainda saia do chão.
		velocity.y *= corte_pulo


func _atualizar_temporizadores(delta: float) -> void:
	if is_on_floor():
		_coyote_restante = coyote
	else:
		_coyote_restante = maxf(_coyote_restante - delta, 0.0)
	_buffer_restante = maxf(_buffer_restante - delta, 0.0)


func _aplicar_gravidade(delta: float) -> void:
	if is_on_floor():
		return
	# Assimétrica: subir com a gravidade nominal preserva a altura de pulo que a
	# geometria da fase assume; cair mais rápido só encurta o tempo morto no ar.
	var fator := gravidade_queda if velocity.y > 0.0 else 1.0
	velocity += get_gravity() * fator * delta
	velocity.y = minf(velocity.y, velocidade_queda_max)
	_velocidade_queda = maxf(_velocidade_queda, velocity.y)


func _pode_pular() -> bool:
	return controlavel and (is_on_floor() or _coyote_restante > 0.0)


## Velocidade horizontal de fato, depois das mecânicas de fase.
##
## `max_speed` nunca é alterado: as mecânicas multiplicam. Toda a geometria das fases foi
## medida contra 180 px/s, e um `max_speed` mutável faria a física depender do estado da
## partida, tornando irreprodutível qualquer bug de "pulo mais curto que o normal".
##
## A altura do pulo não muda em hipótese nenhuma — impulso vertical e gravidade ficam de
## fora daqui. Só o alcance horizontal cai junto com a velocidade, e é por isso que o
## validador confere toda travessia obrigatória a 135 px/s, o pior caso previsto.
func velocidade_atual() -> float:
	return (
		max_speed
		* GameManager.fator_da_pasta()
		* GameManager.fator_de_foco()
		* GameManager.fator_de_carga()
	)


func _move(delta: float) -> void:
	var acel := acceleration if is_on_floor() else aceleracao_ar
	var desacel := deceleration if is_on_floor() else desaceleracao_ar

	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * velocidade_atual(), acel * delta)
		anim.flip_h = direction < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, desacel * delta)


## Só troca a animação se ela já existir no AnimatedSprite2D — evita crash quando uma
## animação ainda não foi criada, mostrando um aviso no lugar de quebrar o jogo.
func _play(animation_name: String) -> void:
	if anim.sprite_frames.has_animation(animation_name):
		if anim.animation != animation_name:
			anim.play(animation_name)
	else:
		push_warning("Player: falta criar a animação '%s' no AnimatedSprite2D." % animation_name)


func _idle_state(delta: float) -> void:
	_move(delta)

	if not is_on_floor():
		_go_to_fall()
		return
	if direction != 0.0:
		_go_to_run()


func _run_state(delta: float) -> void:
	_move(delta)

	if not is_on_floor():
		_go_to_fall()
		return
	if direction == 0.0 and absf(velocity.x) < 8.0:
		_go_to_idle()


func _jump_state(delta: float) -> void:
	_move(delta)

	if velocity.y > 0.0:
		_go_to_fall()


func _fall_state(delta: float) -> void:
	_move(delta)

	if is_on_floor():
		if direction == 0.0:
			_go_to_idle()
		else:
			_go_to_run()


func _go_to_idle() -> void:
	state = PlayerState.IDLE
	_play("idle")


func _go_to_run() -> void:
	state = PlayerState.RUN
	_play("run")


func _go_to_jump() -> void:
	state = PlayerState.JUMP
	velocity.y = JUMP_VELOCITY
	_coyote_restante = 0.0
	_buffer_restante = 0.0
	_play("jump")
	# Esticado na vertical: leitura instantânea de "saiu do chão", mesmo em 16x32px.
	_escala_alvo = Vector2(0.82, 1.2)
	Audio.tocar("pulo")
	pulou.emit()


func _go_to_fall() -> void:
	state = PlayerState.FALL
	_play("fall")


## Detecta a transição ar → chão e mede a força do impacto pela maior velocidade de
## queda atingida, não pela velocidade no frame do toque (que o move_and_slide já
## zerou). Sem isso, todo pouso pareceria leve.
func _checar_pouso() -> void:
	var no_chao := is_on_floor()
	if no_chao and not _no_chao_antes:
		var forca := clampf(_velocidade_queda / velocidade_queda_max, 0.0, 1.0)
		if _velocidade_queda >= QUEDA_FORTE:
			_escala_alvo = Vector2(1.0 + 0.28 * forca, 1.0 - 0.26 * forca)
			poeira_pouso.restart()
			poeira_pouso.emitting = true
			# Tremor proporcional, sem congelar: pousar é frequente demais para
			# interromper o jogo a cada vez.
			Juice.tremer(forca * 0.28)
			Audio.tocar("pouso", lerpf(-9.0, 0.0, forca))
		pousou.emit(forca)
		_velocidade_queda = 0.0
	_no_chao_antes = no_chao


## Squash & stretch: a escala corre para o alvo e o alvo volta sozinho para 1.
## O offset é recalculado junto para que a deformação aconteça a partir dos PÉS —
## escalando pelo centro, o personagem afundaria no chão ao ser achatado.
func _aplicar_squash(delta: float) -> void:
	_escala_alvo = _escala_alvo.move_toward(Vector2.ONE, 3.4 * delta)
	anim.scale = anim.scale.move_toward(_escala_alvo, 7.0 * delta)
	# Metade da altura do quadro (32px) = 16px. Pés parados em _offset_base.y + 16.
	anim.offset.y = _offset_base.y + 16.0 * (1.0 - anim.scale.y)


func _atualizar_poeira() -> void:
	var correndo := is_on_floor() and absf(velocity.x) > velocidade_atual() * 0.55
	poeira_corrida.emitting = correndo
	if correndo:
		# A poeira sai para trás de quem corre.
		poeira_corrida.direction = Vector2(-signf(velocity.x), 0.0)


## Passos com cadência proporcional à velocidade, em vez de presos aos quadros da
## animação: assim andar devagar não solta o mesmo estalo rápido de correr, e o
## som some sozinho quando o personagem desacelera.
func _atualizar_passos(delta: float) -> void:
	if not is_on_floor() or absf(velocity.x) < velocidade_atual() * 0.25:
		_proximo_passo = 0.0
		return

	_proximo_passo -= delta
	if _proximo_passo > 0.0:
		return
	Audio.tocar("passo", -14.0, 0.12)
	_proximo_passo = lerpf(0.34, 0.19, absf(velocity.x) / velocidade_atual())
