extends CharacterBody2D

## "O Prazo": o urso que persegue o jogador durante o expediente, para que hesitar tenha
## custo.
##
## Estados:
##   DORMINDO  acorda alguns segundos depois do início; o rugido abre a fase
##   CACANDO   perseguição normal (velocidade variável, ver _velocidade_de_caca)
##   FARO      o jogador parou de avançar: acelera e o HUD avisa
##   BOTE      telegrafa antes de investir, para que dê para reagir
##   RECUO     recua depois de acertar
##
## Três limites impedem que vire punição sem saída: velocidade máxima abaixo da do
## jogador correndo (96 contra 180px/s); empurrão sempre para LONGE do urso; e hesitação
## medida pelo avanço máximo já alcançado, não pela velocidade instantânea.
##
## Alcançar custa tempo, não pontos, e passa por descontar_tempo(), fora das notas por
## categoria. Não colide com o mundo e não sobe: plataforma alta é área segura.

## Emitido quando ele encosta no jogador. Existe para o teste automatizado poder
## afirmar o alcance sem depender de quantos frames o headless rodou.
signal alcancou(custo: float)
## 0 = longe e tranquilo, 1 = em cima do jogador. HUD, câmera e música escutam isto
## em vez de cada um calcular a própria distância.
signal perigo_mudou(intensidade: float)
## Disparado no início do telegrafo do bote, com a duração do aviso.
signal vai_dar_o_bote(aviso: float)
signal acordou()

enum Estado { DORMINDO, CACANDO, FARO, BOTE, RECUO }

## A arte do Grizzly (Sprite Pack 5) é desenhada com o focinho para a ESQUERDA — dá
## para conferir abrindo `sprites/Sprite Pack 5/7 - Grizzly/Walking_(48 x 32).png`.
## Como o urso persegue para a direita quase o tempo todo, o estado normal dele é
## espelhado. Deixar isto como constante nomeada evita a próxima pessoa "corrigir"
## o flip para o lado errado por achar que o padrão dos sprites é olhar para a
## direita (o do jogador, businessman1, é — os dois packs não combinam entre si).
const ARTE_OLHA_PARA_ESQUERDA := true

## Abaixo deste deslocamento por quadro o urso é considerado parado, e mantém o lado
## para onde já estava virado. Sem essa zona morta ele piscaria de lado no instante
## em que o recuo termina e a caça recomeça.
const MOVIMENTO_MINIMO := 0.01

## Faixa horizontal em que ele para de se reposicionar. Sem ela, um urso exatamente
## em cima do jogador ficaria tremendo de um lado para o outro a cada quadro.
const ZONA_MORTA := 4.0

@export_group("Ritmo")
## Segundos de sono antes de acordar. É a janela em que o jogador lê a dica de
## abertura sem já estar sendo caçado.
@export var atraso_para_acordar: float = 3.0
## Velocidade de cruzeiro. Calibragem: a fase tem 2624px e 90s de expediente, ou
## seja o jogador precisa manter ~29px/s de avanço médio. 34px/s fica pouco acima —
## quem joga no ritmo mínimo o sente na nuca; quem prioriza bem abre distância.
@export var velocidade_base: float = 34.0
## Teto de velocidade quando ele está muito atrás (ver _velocidade_de_caca). Fica
## abaixo dos 180px/s do jogador correndo: ele alcança quem para, nunca quem corre.
@export var velocidade_maxima: float = 96.0
## Distância a partir da qual ele começa a acelerar para não virar irrelevante.
@export var folga_confortavel: float = 260.0
## Distância em que ele já está em velocidade máxima de recuperação.
@export var folga_maxima: float = 620.0

@export_group("Faro")
## Segundos sem o jogador avançar que ligam o modo FARO.
@export var paciencia: float = 2.2
## Multiplicador de velocidade enquanto fareja.
@export var impulso_do_faro: float = 1.7

@export_group("Bote")
## Distância em que ele arma o bote.
@export var alcance_do_bote: float = 104.0
## Duração do telegrafo. Meio segundo é o suficiente para reagir correndo e curto o
## bastante para assustar.
@export var aviso_do_bote: float = 0.5
@export var duracao_do_bote: float = 0.55
@export var velocidade_do_bote: float = 250.0
## Descanso mínimo entre dois botes, para o bote não virar o estado normal.
@export var recarga_do_bote: float = 3.5

@export_group("Dano")
@export var custo_em_segundos: float = 8.0
## Empurrão dado no jogador ao alcançá-lo. É sempre para LONGE do urso, nunca numa
## direção fixa: agora que ele persegue nos dois sentidos, empurrar sempre para a
## direita jogaria o jogador para dentro dele quando o acerto viesse pela direita, e
## isso criaria um laço de punição sem saída. A punição aqui é tempo, não posição.
@export var empurrao: float = 190.0
@export var invulnerabilidade: float = 1.6
## Quanto ele recua ao acertar, em pixels — o alívio depois do susto.
@export var recuo: float = 70.0
@export var duracao_do_recuo: float = 1.1

@onready var hurtbox: Area2D = $Hurtbox
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

var estado: Estado = Estado.DORMINDO
var _espera_dano := 0.0
var _tempo_no_estado := 0.0
var _recarga := 0.0
var _sem_avancar := 0.0
var _avanco_maximo := -INF
var _jogador: Node2D = null
var _perigo := 0.0
var _alvo_recuo := 0.0
## Direção travada no início do bote, para a investida não perseguir no meio do salto.
var _lado_do_bote := 1.0


func _ready() -> void:
	# Fonte de pressão da fase: é daqui que a música, a vinheta do HUD e a barra de
	# percurso leem "o quanto o jogador está em perigo". Outra fonte de pressão entra no
	# mesmo grupo e publica o mesmo sinal — ver FaseBase._ligar_perigo().
	add_to_group("perigo")
	hurtbox.body_entered.connect(_ao_alcancar)
	_ir_para(Estado.DORMINDO)
	# Já nasce virado para o lado que vai perseguir: ele dorme de frente para o
	# corredor, não de costas.
	_virar_para(1.0)

	var jogadores := get_tree().get_nodes_in_group("Player")
	if not jogadores.is_empty():
		_jogador = jogadores[0]
		_avanco_maximo = _jogador.global_position.x


func _physics_process(delta: float) -> void:
	if not GameManager.em_jogo or _jogador == null:
		return

	_tempo_no_estado += delta
	_espera_dano = maxf(_espera_dano - delta, 0.0)
	_recarga = maxf(_recarga - delta, 0.0)
	_medir_hesitacao(delta)

	var x_antes := global_position.x

	match estado:
		Estado.DORMINDO:
			_dormindo()
		Estado.CACANDO:
			_cacando(delta)
		Estado.FARO:
			_faro(delta)
		Estado.BOTE:
			_bote(delta)
		Estado.RECUO:
			_recuo(delta)

	# Vira pelo deslocamento REAL do quadro, e não pelo estado: assim o recuo (única
	# vez em que ele anda para trás) fica certo de graça, e qualquer estado novo que
	# alguém acrescente depois já nasce virando para o lado certo.
	_virar_para(global_position.x - x_antes)
	_atualizar_perigo()


func _virar_para(deslocamento: float) -> void:
	if absf(deslocamento) < MOVIMENTO_MINIMO:
		return
	var indo_para_direita := deslocamento > 0.0
	anim.flip_h = indo_para_direita if ARTE_OLHA_PARA_ESQUERDA else not indo_para_direita


## Hesitação é medida pelo AVANÇO do jogador, não pela velocidade dele: correr para
## trás e para a frente no mesmo lugar, ou ficar pulando parado em cima de uma
## plataforma decidindo, conta como parado — que é exatamente o comportamento que a
## fase precisa desencorajar.
func _medir_hesitacao(delta: float) -> void:
	var x := _jogador.global_position.x
	if x > _avanco_maximo + 2.0:
		_avanco_maximo = x
		_sem_avancar = 0.0
	else:
		_sem_avancar += delta


## Velocidade de cruzeiro com elástico: quanto mais longe o jogador estiver, mais
## rápido ele vem. Sem isso, um bom jogador abria distância uma vez e jogava o resto
## da fase sem nenhuma pressão — o urso vira cenário. Com isso ele sempre volta a ser
## relevante, mas nunca alcança quem está de fato correndo (o teto é 96px/s contra os
## 180px/s do jogador).
func _velocidade_de_caca() -> float:
	# Distância em módulo: o elástico vale para os dois lados, senão ele demoraria
	# uma eternidade para voltar quando o jogador ficasse atrás dele.
	var distancia := absf(_jogador.global_position.x - global_position.x)
	var t := clampf(
		(distancia - folga_confortavel) / maxf(folga_maxima - folga_confortavel, 1.0), 0.0, 1.0
	)
	return lerpf(velocidade_base, velocidade_maxima, t)


## Para que lado fica o jogador: -1, 0 ou 1. Zero dentro da zona morta, para o urso
## não tremer de um lado para o outro quando estiver em cima dele.
func _lado_do_jogador() -> float:
	var d := _jogador.global_position.x - global_position.x
	if absf(d) < ZONA_MORTA:
		return 0.0
	return signf(d)


func _dormindo() -> void:
	if _tempo_no_estado >= atraso_para_acordar:
		_ir_para(Estado.CACANDO)
		acordou.emit()
		get_tree().call_group(
			"hud", "mostrar_dica", "O PRAZO ACORDOU",
			"Ele não para. Cada segundo parado é um metro que ele ganha.",
			Color("ff8c42")
		)


func _cacando(delta: float) -> void:
	_avancar(_velocidade_de_caca(), delta)

	if _pode_dar_o_bote():
		_ir_para(Estado.BOTE)
	elif _sem_avancar >= paciencia:
		_ir_para(Estado.FARO)


func _faro(delta: float) -> void:
	_avancar(_velocidade_de_caca() * impulso_do_faro, delta)

	if _pode_dar_o_bote():
		_ir_para(Estado.BOTE)
	elif _sem_avancar < paciencia * 0.4:
		# Voltou a andar: alivia. A histerese (0.4) evita ficar piscando entre os
		# dois estados quando o jogador avança aos trancos.
		_ir_para(Estado.CACANDO)


func _bote(delta: float) -> void:
	if _tempo_no_estado < aviso_do_bote:
		# Telegrafo: ele quase para e empina. Parar de todo seria estranho; andar
		# devagar mantém a ameaça enquanto o jogador lê o aviso.
		_avancar(velocidade_base * 0.35, delta)
		return

	# A investida COMETE-SE com a direção decidida no telegrafo, em vez de continuar
	# corrigindo o rumo. Um bote que persegue no meio do salto é impossível de
	# esquivar, e a esquiva é justamente o que o telegrafo promete ao jogador.
	global_position.x += _lado_do_bote * velocidade_do_bote * delta
	if _tempo_no_estado >= aviso_do_bote + duracao_do_bote:
		_recarga = recarga_do_bote
		_ir_para(Estado.CACANDO)


func _recuo(delta: float) -> void:
	# Recua para o alvo e para. O jogador precisa deste respiro para reorganizar a
	# rota depois de levar o susto.
	global_position.x = move_toward(global_position.x, _alvo_recuo, 90.0 * delta)
	if _tempo_no_estado >= duracao_do_recuo:
		_ir_para(Estado.CACANDO)


## Anda na direção do jogador. Foi aqui que o urso deixou de ser "prazo que só corre
## para a direita" e virou perseguidor de verdade (ver o cabeçalho).
func _avancar(velocidade: float, delta: float) -> void:
	global_position.x += _lado_do_jogador() * velocidade * delta


func _pode_dar_o_bote() -> bool:
	if _recarga > 0.0:
		return false
	# Bota para qualquer lado, agora que ele persegue nos dois sentidos — mas só se o
	# jogador estiver mais ou menos na mesma altura: investir contra alguém três
	# plataformas acima não é ameaça, é ruído.
	if absf(_jogador.global_position.x - global_position.x) > alcance_do_bote:
		return false
	return absf(_jogador.global_position.y - global_position.y) < 56.0


func _ir_para(novo: Estado) -> void:
	estado = novo
	_tempo_no_estado = 0.0

	match novo:
		Estado.DORMINDO:
			_tocar("dormindo")
		Estado.CACANDO:
			_tocar("andar")
			anim.speed_scale = 1.0
		Estado.FARO:
			_tocar("andar")
			# Passada mais rápida: a aceleração precisa ser visível, não só sentida.
			anim.speed_scale = 1.5
		Estado.BOTE:
			_tocar("atacar")
			anim.speed_scale = 1.0
			# Trava a direção agora: durante o telegrafo o jogador ainda pode passar
			# para o outro lado, e o bote tem que sair para onde foi anunciado.
			var lado := _lado_do_jogador()
			_lado_do_bote = lado if lado != 0.0 else 1.0
			vai_dar_o_bote.emit(aviso_do_bote)
			Audio.tocar("urso_rugido")
			_telegrafar()
		Estado.RECUO:
			_tocar("parado")
			anim.speed_scale = 1.0
			# Recua para LONGE do jogador, não para um lado fixo — senão um acerto
			# vindo pela direita empurraria o urso por cima dele.
			var fuga := _lado_do_jogador()
			_alvo_recuo = global_position.x - (fuga if fuga != 0.0 else 1.0) * recuo


## O empinar do telegrafo. Escala em vez de animação nova porque o pack não tem um
## quadro de "armar o bote" — e um susto de meio segundo se lê melhor por deformação
## do que por troca de sprite nesse tamanho.
func _telegrafar() -> void:
	var t := create_tween()
	t.tween_property(anim, "scale", Vector2(0.86, 1.24), aviso_do_bote * 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(anim, "scale", Vector2(1.18, 0.9), 0.08)
	t.tween_property(anim, "scale", Vector2.ONE, 0.18)

	var brilho := create_tween()
	brilho.tween_property(anim, "modulate", Color(1.6, 1.0, 1.0), aviso_do_bote * 0.5)
	brilho.tween_property(anim, "modulate", Color.WHITE, 0.2)


## Intensidade de ameaça, de 0 a 1, publicada num sinal só para que HUD, câmera e
## música não repitam cada um o cálculo de distância.
func _atualizar_perigo() -> void:
	# Módulo: agora que ele persegue nos dois sentidos, estar 50px atrás dele é tão
	# perigoso quanto estar 50px à frente.
	var distancia := absf(_jogador.global_position.x - global_position.x)
	var bruto := 1.0 - clampf(distancia / folga_confortavel, 0.0, 1.0)
	if estado == Estado.BOTE:
		bruto = maxf(bruto, 0.85)
	elif estado == Estado.RECUO or estado == Estado.DORMINDO:
		bruto = minf(bruto, 0.25)

	if absf(bruto - _perigo) > 0.01:
		_perigo = bruto
		perigo_mudou.emit(_perigo)


func _tocar(nome: String) -> void:
	if anim.sprite_frames.has_animation(nome):
		anim.play(nome)


func _ao_alcancar(corpo: Node2D) -> void:
	if _espera_dano > 0.0 or not corpo.is_in_group("Player") or not GameManager.em_jogo:
		return
	if estado == Estado.DORMINDO:
		return

	_espera_dano = invulnerabilidade
	GameManager.descontar_tempo(custo_em_segundos)
	alcancou.emit(custo_em_segundos)

	if corpo is CharacterBody2D:
		var jogador := corpo as CharacterBody2D
		# Para LONGE do urso, de qualquer lado que o acerto tenha vindo. Empatado
		# (jogador exatamente em cima dele), joga para a frente do corredor.
		var fuga := signf(corpo.global_position.x - global_position.x)
		if is_zero_approx(fuga):
			fuga = 1.0
		jogador.velocity.x = fuga * empurrao
		jogador.velocity.y = -150.0

	Audio.tocar("urso_acerto")
	Juice.impacto(0.9)
	Feedback.pontos(
		get_parent(), global_position + Vector2(0, -30),
		"-%ds" % int(custo_em_segundos), Color("ff6b6b")
	)
	get_tree().call_group(
		"hud", "mostrar_dica", "O PRAZO TE ALCANÇOU",
		"Hesitar custou %d segundos. Continue avançando." % int(custo_em_segundos),
		Color("ff6b6b")
	)

	_ir_para(Estado.RECUO)


## Distância até o jogador, em pixels. Lida pelo HUD para desenhar o marcador do
## urso na barra de progresso.
func distancia_do_jogador() -> float:
	if _jogador == null:
		return INF
	return _jogador.global_position.x - global_position.x
