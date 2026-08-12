extends Area2D

## Um papel da Fase 3: cai, espera, é carregado e é entregue num canto da matriz.
##
## Em tarefa.gd (Fases 1 e 2), encostar já é a decisão. Aqui encostar só PEGA: a decisão
## vem depois, e é para onde o jogador leva o papel. É o que permite a fase final exigir
## os quatro quadrantes, em vez da pergunta binária dos dois primeiros dias.
##
## Como lá, o papel mostra só o enunciado, sem cor nem ícone de categoria — quem
## classifica é o jogador, e o teste trava isso.
##
## Carrega-se um por vez, e é a escassez inteira da fase: o Chefe joga mais rápido do que
## se consegue rotear, então não dá para fazer tudo, e é para essa pergunta que a matriz
## serve. Sem o limite a fase vira coleta.

@export_enum(
	"Q1 - Urgente e importante",
	"Q2 - Importante nao urgente",
	"Q3 - Urgente nao importante",
	"Q4 - Nem urgente nem importante"
) var categoria: int = 0

@export var texto: String = ""

## Onde o papel para de cair. Ele nasce acima do teto e desce à vista do jogador — a
## chegada é o aviso, e um papel que aparecesse do nada seria injusto de ler.
@export var pousa: float = 0.0

## Segundos até apodrecer. É o relógio que transforma "não deu tempo" em consequência.
##
## O relógio corre TAMBÉM com o papel na mão (ver _physics_process). Congelar a validade
## ao pegar abriria uma saída da fase inteira: segurar uma urgente o expediente todo sem
## custo nenhum. Trabalho em andamento também vence, e é isso que torna "pegar" uma
## decisão em vez de um reflexo.
@export var validade := 8.0

const VELOCIDADE_QUEDA := 150.0
const RAIO_ROTULO := 96.0

## Deriva das Q4 em direção ao jogador. Distração não espera ser procurada — ela vem
## atrás de você. É de propósito que só o quadrante 4 se move: nas Fases 1 e 2 TODAS as
## tarefas balançam justamente porque, antes disso, "o que se mexe é Q4" era uma dica que
## dispensava ler. Aqui a dica não existe: o movimento é lento e todas as outras também
## oscilam de leve (ver _oscilar).
const DERIVA_Q4 := 26.0

const REGIAO_ICONE := Rect2(192, 107, 6, 9)
const COR_NEUTRA := Color("f2f2f2")

signal apodreceu(demanda: Node)

@onready var icone: Sprite2D = $Icone
@onready var brilho: Polygon2D = $Brilho
@onready var rotulo: Label = $Rotulo
@onready var colisor: CollisionShape2D = $CollisionShape2D

var carregada := false
var resolvida := false
## Vencido enquanto estava sendo carregado. A fase lê para escolher a frase do aviso: um
## papel que apodreceu no chão e um que apodreceu na mão ensinam coisas diferentes.
var na_mao_ao_vencer := false

var _jogador: Node2D = null
var _caiu := false
var _restante := 0.0
var _fase := 0.0
var _base_x := 0.0


func _ready() -> void:
	add_to_group("demanda")
	_restante = validade
	_base_x = position.x
	_fase = fmod(absf(position.x) * 0.07, TAU)

	icone.region_enabled = true
	icone.region_rect = REGIAO_ICONE
	icone.modulate = COR_NEUTRA
	brilho.modulate = Color(COR_NEUTRA.r, COR_NEUTRA.g, COR_NEUTRA.b, 0.3)
	rotulo.text = texto
	rotulo.modulate.a = 0.0

	var jogadores := get_tree().get_nodes_in_group("Player")
	if not jogadores.is_empty():
		_jogador = jogadores[0]


func _physics_process(delta: float) -> void:
	if resolvida:
		return

	if carregada:
		_seguir_o_jogador(delta)
		# Envelhece na mão também. É o que impede "pegar e segurar" de ser uma pausa de
		# graça no relógio da tarefa — e é o que faz o jogador escolher qual papel vale a
		# viagem, em vez de recolher o primeiro que vê.
		_envelhecer(delta)
		return

	if not _caiu:
		_cair(delta)
		return

	_oscilar(delta)
	_envelhecer(delta)
	_atualizar_rotulo()


func _cair(delta: float) -> void:
	position.y = minf(position.y + VELOCIDADE_QUEDA * delta, pousa)
	if position.y >= pousa:
		_caiu = true
		Audio.tocar("chegada", -10.0, 0.05)


## Todo papel se mexe um pouco; a Q4 se mexe EM DIREÇÃO ao jogador. A diferença é sutil de
## propósito — perceptível para quem já entendeu a fase, inútil como atalho para quem
## quer pular a leitura.
func _oscilar(delta: float) -> void:
	_fase += TAU * delta / 2.4
	position.x = _base_x + 3.0 * sin(_fase)

	if categoria != GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE or _jogador == null:
		return
	var rumo: float = signf(_jogador.global_position.x - global_position.x)
	_base_x = clampf(_base_x + rumo * DERIVA_Q4 * delta, 24.0, 616.0)


func _envelhecer(delta: float) -> void:
	_restante -= delta
	# Pisca quando está para vencer: é o único aviso, e ele precisa funcionar sem o
	# jogador tirar os olhos de onde vai pousar.
	if _restante < 3.0:
		var pulso := 0.45 + 0.55 * absf(sin(Time.get_ticks_msec() * 0.012))
		icone.modulate = Color(1.0, pulso, pulso)
	if _restante > 0.0:
		return

	# Q4 que expirou sozinha é ACERTO: a resposta certa para "nem urgente nem importante"
	# é não fazer nada. Registrar isso como EVITOU, e não como omissão, é o que impede o
	# relatório final de contar um acerto como falha.
	#
	# Exceção: uma Q4 que apodreceu NA MÃO não é ter desviado da distração — é ter
	# carregado a distração o caminho todo, que é justamente o erro que a matriz existe
	# para evitar. Sem isto, pegar lixo e passear com ele seria premiado igual a ignorá-lo.
	var certo := categoria == GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE and not carregada
	na_mao_ao_vencer = carregada
	resolver(GameManager.Acao.EVITOU if certo else GameManager.Acao.IGNOROU)
	if not certo:
		apodreceu.emit(self)


## O papel vai na mão, um pouco à frente e acima do centro do corpo. O deslocamento não é
## decorativo: sem ele o papel fica sob o sprite do jogador e o enunciado some justamente
## enquanto ele está sendo carregado, que é quando mais precisa ser relido.
func _seguir_o_jogador(delta: float) -> void:
	if _jogador == null:
		return
	var alvo: Vector2 = _jogador.global_position + Vector2(0, -22)
	global_position = global_position.lerp(alvo, clampf(delta * 18.0, 0.0, 1.0))
	rotulo.modulate.a = 1.0


func _atualizar_rotulo() -> void:
	if _jogador == null:
		return
	var distancia := global_position.distance_squared_to(_jogador.global_position)
	var raio := RAIO_ROTULO * GameManager.fator_do_raio()
	var visivel := distancia <= raio * raio and GameManager.atencao_livre()
	rotulo.modulate.a = move_toward(rotulo.modulate.a, 1.0 if visivel else 0.0, 0.12)


## Pega o papel. Quem decide se PODE pegar é a fase (só um por vez) — aqui só se executa.
func pegar() -> void:
	if resolvida or carregada:
		return
	carregada = true
	colisor.set_deferred("disabled", true)
	z_index = 6
	Audio.tocar("coleta", -8.0, 0.06)


## Devolve o papel ao chão sem registrar nada. O cronômetro de validade continua de onde
## parou: pegar por engano não pode ser sentença, senão o jogador para de experimentar e
## a fase deixa de ensinar.
func largar() -> void:
	if resolvida or not carregada:
		return
	carregada = false
	colisor.set_deferred("disabled", false)
	z_index = 3
	_base_x = position.x
	_caiu = true


## Aplica o Quadro 1 e tira o papel de cena. Ponto único por onde toda ação passa.
func resolver(acao: int) -> Dictionary:
	if resolvida:
		return {"pontos": 0, "delta_tempo": 0.0}
	resolvida = true
	carregada = false

	var efeito := GameManager.registrar_acao(categoria, acao)
	var cor: Color = GameManager.COR_CATEGORIA[categoria]

	# Desviar corretamente é a ação mais frequente e a que menos precisa de aviso — o
	# jogador acertou justamente porque nada aconteceu. Mesma regra de tarefa.gd.
	if acao != GameManager.Acao.EVITOU:
		var aviso := "%+d" % int(efeito["pontos"])
		if efeito["delta_tempo"] != 0.0:
			aviso += "  %ds" % int(efeito["delta_tempo"])
		if acao == GameManager.Acao.IGNOROU:
			aviso = "classificou mal"
		Feedback.pontos(get_parent(), global_position, aviso, cor)

	if acao in [GameManager.Acao.COLETAR, GameManager.Acao.DELEGAR, GameManager.Acao.RESOLVER]:
		Feedback.estouro(get_parent(), global_position, cor, 16, 82.0)
		Feedback.onda(get_parent(), global_position, cor, 34.0)
		Juice.tremer(0.12)
	elif acao == GameManager.Acao.COLIDIU:
		Feedback.estouro(get_parent(), global_position, cor, 20, 100.0)
		Juice.impacto(0.6)
		Juice.flash(cor, 0.16)

	queue_free()
	return efeito
