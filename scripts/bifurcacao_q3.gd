extends Node2D

## Q3 — "urgente e não importante" (Quadro 1: delegar OU resolver).
##
## O TCC define a ação de Q3 como "delegar (ação específica) ou resolver (ação padrão)"
## mas não diz qual é a ação específica. Aqui ela é GEOMÉTRICA, não uma tecla:
##
##   rota baixa (fácil, no chão)      → PontoResolver → +40 pontos e -5s
##   rota alta (dois pulos, mezanino) → PontoDelegar  → +60 pontos, sem custo de tempo
##
## Delegar custa habilidade; resolver custa tempo. Isso mantém a exigência da
## Metodologia de que a priorização seja ação física real no corredor, e não escolha
## de menu ou clique único.
##
## Os dois pontos são exclusivos: o primeiro que disparar desliga o outro, então cada
## tarefa Q3 é contada uma vez só e a decisão é irreversível, como no trabalho real.

## Enunciado da tarefa, mostrado na faixa do HUD ao se aproximar. Como nas demais
## tarefas, ele NÃO diz de que quadrante é: identificar isso é o trabalho do jogador.
@export var texto: String = "Reunião de status sem pauta definida"

## Quem recebe a tarefa quando o jogador escolhe DELEGAR (entities/colega.tscn).
##
## É o que separa delegar de "resolver valendo 20 pontos a mais": o colega levanta e vai
## MUDAR ALGUMA COISA no corredor adiante. Sem ele preenchido a bifurcação continua
## funcionando exatamente como antes — o que mantém as Fases 2 e 3 intactas.
@export var colega: NodePath

## Mesma cor neutra das outras tarefas (ver scripts/tarefa.gd): a cor do quadrante só
## aparece depois que o jogador decide.
const COR_NEUTRA := Color("f2f2f2")

@onready var proximidade: Area2D = $Proximidade
@onready var ponto_resolver: Area2D = $PontoResolver
@onready var ponto_delegar: Area2D = $PontoDelegar
@onready var icone_resolver: Sprite2D = $PontoResolver/Icone
@onready var icone_delegar: Sprite2D = $PontoDelegar/Icone
@onready var rotulo: Label = $Rotulo

var _decidida := false
## O jogador está dentro do raio de leitura? Move o rótulo do mundo.
var _perto := false


func _ready() -> void:
	icone_resolver.modulate = COR_NEUTRA
	icone_delegar.modulate = COR_NEUTRA

	rotulo.text = texto
	rotulo.modulate.a = 0.0

	proximidade.body_entered.connect(_ao_aproximar)
	proximidade.body_exited.connect(_ao_afastar)
	ponto_resolver.body_entered.connect(_ao_resolver)
	ponto_delegar.body_entered.connect(_ao_delegar)

	_pulsar(icone_delegar)


## O enunciado aparece NO MUNDO, em cima da bifurcação, e não só na faixa do HUD.
##
## A Q3 mostra o enunciado no mundo, como as outras. Deixar o texto só na faixa do HUD
## não serve: a faixa é disputada por dica, checkpoint e aviso do urso, e sem ler o
## enunciado não há classificação nenhuma.
##
## move_toward em vez de tween pelo mesmo motivo de tarefa.gd: isto roda todo quadro, e
## criar um tween por quadro vazaria objetos até o fim do expediente.
func _process(_delta: float) -> void:
	var alvo := 1.0 if _perto and not _decidida else 0.0
	if not is_equal_approx(rotulo.modulate.a, alvo):
		rotulo.modulate.a = move_toward(rotulo.modulate.a, alvo, 0.12)


## Troca o enunciado depois de a cena já estar montada — ver tarefa.definir_texto().
func definir_texto(novo: String) -> void:
	texto = novo
	if is_node_ready():
		rotulo.text = texto


func _ao_afastar(corpo: Node2D) -> void:
	if corpo.is_in_group("Player"):
		_perto = false


## A bifurcação é larga e o jogador precisa ler o enunciado ANTES de escolher a rota —
## quando ele chega no gatilho de resolver, já é tarde para decidir.
func _ao_aproximar(corpo: Node2D) -> void:
	if not corpo.is_in_group("Player"):
		return
	_perto = true
	if _decidida:
		return
	get_tree().call_group("hud", "mostrar_dica", "TAREFA", texto, COR_NEUTRA)


func _ao_resolver(corpo: Node2D) -> void:
	if not _pode_decidir(corpo):
		return
	_decidir(GameManager.Acao.RESOLVER, ponto_resolver.global_position)


func _ao_delegar(corpo: Node2D) -> void:
	if not corpo.is_in_group("Player"):
		return
	# Subir na bandeja de uma Q3 já resolvida no chão não faz nada, e silêncio ali lê como
	# defeito. A faixa explica que a tarefa já foi tratada.
	if _decidida:
		get_tree().call_group(
			"hud", "mostrar_dica", "JÁ TRATADA",
			"Você resolveu esta tarefa sozinho lá embaixo.", COR_NEUTRA, 1
		)
		return
	if not _pode_decidir(corpo):
		return
	_decidir(GameManager.Acao.DELEGAR, ponto_delegar.global_position)
	# Depois de _decidir(), e não antes: o colega só sai da bandeja se a delegação
	# realmente contou. Antes, um retorno cedo lá dentro deixaria um colega andando por
	# uma tarefa que não pontuou.
	var ajudante := get_node_or_null(colega)
	if ajudante != null and ajudante.has_method("despachar"):
		ajudante.despachar()


func _pode_decidir(corpo: Node2D) -> bool:
	return not _decidida and corpo.is_in_group("Player") and GameManager.em_jogo


## `acao` é um GameManager.Acao. Não dá para anotar o tipo assim: um autoload não é
## um nome de classe em tempo de compilação, então o tipo declarado aqui é int.
func _decidir(acao: int, posicao: Vector2) -> void:
	_decidida = true

	var cor: Color = GameManager.COR_CATEGORIA[GameManager.Categoria.URGENTE_NAO_IMPORTANTE]
	var efeito := GameManager.registrar_acao(GameManager.Categoria.URGENTE_NAO_IMPORTANTE, acao)

	var rotulo := "+%d" % efeito["pontos"]
	if efeito["delta_tempo"] != 0.0:
		rotulo += "  %ds" % int(efeito["delta_tempo"])
	Feedback.pontos(get_parent(), posicao, rotulo, cor)
	# A faixa do HUD não é avisada aqui: o HUD escuta GameManager.tarefa_registrada e
	# monta a mensagem de resultado sozinho. Avisar dos dois lugares mostraria duas
	# mensagens seguidas e a segunda apagaria a primeira.

	# O lado não escolhido não pode mais pontuar se o jogador voltar por ele. O de delegar
	# continua escutando só para poder explicar que a tarefa já foi tratada.
	ponto_resolver.set_deferred("monitoring", false)
	proximidade.set_deferred("monitoring", false)

	# O colega dispensado se recolhe. Sem isso ele continua sentado, aceso e pulsando,
	# como se ainda houvesse algo a fazer com ele.
	if acao != GameManager.Acao.DELEGAR:
		var ajudante := get_node_or_null(colega)
		if ajudante != null and ajudante.has_method("dispensar"):
			ajudante.dispensar()
	# Revela o quadrante depois da decisão, como as demais tarefas fazem.
	icone_resolver.modulate = Color(cor.r, cor.g, cor.b, 0.4)
	icone_delegar.modulate = Color(cor.r, cor.g, cor.b, 0.4)


## Só o lado de delegar pulsa — é a dica visual silenciosa de que existe uma opção
## melhor lá em cima, sem precisar de texto explicando.
func _pulsar(alvo: CanvasItem) -> void:
	var pulso := create_tween().set_loops()
	pulso.tween_property(alvo, "scale", Vector2(1.2, 1.2), 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulso.tween_property(alvo, "scale", Vector2(0.95, 0.95), 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
