extends Area2D

## Uma tarefa da Matriz de Eisenhower no corredor.
##
## Uma cena só atende Q1, Q2 e Q4; o comportamento sai da categoria escolhida no
## Inspector. Q3 NÃO usa esta cena: delegar ou resolver é escolha geométrica (rota alta
## vs. rota baixa) e vive em bifurcacao_q3.gd.
##
## Toda tarefa tem a MESMA aparência e mostra só o enunciado — quem classifica é o
## jogador, e ele responde com o corpo. Cor por categoria mataria a mecânica.
##
##   Q1 encostada  +100  · Q1 ignorada   0 e o elevador não abre
##   Q2 encostada   +80  · Q2 ignorada   0
##   Q4 encostada   -20 e -8s            · Q4 ignorada  0 (desviar é o acerto)

## A ordem tem que bater com GameManager.Categoria — é a mesma sequência dos quadrantes
## do Quadro 1 do TCC, que não muda.
@export_enum(
	"Q1 - Urgente e importante",
	"Q2 - Importante nao urgente",
	"Q3 - Urgente nao importante",
	"Q4 - Nem urgente nem importante"
) var categoria: int = 0

## Enunciado da tarefa, mostrado ao jogador no corredor e na faixa do HUD. É a ÚNICA
## informação que ele recebe antes de decidir — escrever isto bem é o que torna a fase
## jogável, então todo enunciado tem que dar para classificar sem citar o quadrante.
@export var texto: String = ""

## Oscilação (em pixels) em torno da posição inicial. Usada nas Q4 para que a
## distração se mova e exija desvio de verdade; Vector2.ZERO deixa a tarefa parada.
@export var amplitude: Vector2 = Vector2.ZERO

## Segundos de um ciclo completo de oscilação.
@export var periodo: float = 2.0

## Enunciado que esta MESMA tarefa passa a ter depois de amadurecer (Dia 2). Vazio
## significa "esta tarefa não amadurece", que é o caso de toda tarefa do Dia 1.
##
## Fica na tarefa, e não numa tabela da fase, porque o enunciado da crise é a metade
## que falta do enunciado original: os dois têm que ser escritos juntos ou a tarefa não
## conta história nenhuma ("Testar o backup" → "O backup falhou").
@export_multiline var texto_maduro: String = ""

## Emitido quando esta tarefa é deixada para trás sem nenhuma ação (Acao.IGNOROU).
##
## A tarefa não decide o que fazer com isso — ela relata, como já relata ao GameManager.
## Quem escuta é a fase: no Dia 2, uma Q2 adiada volta como urgente. Manter a decisão na
## fase é o que permite que o Dia 1 ignore o sinal sem nenhuma condicional aqui dentro.
signal adiada(tarefa: Node)

## Velocidade de queda em px/s. 0 = tarefa parada, que é o caso da Fase 1 inteira.
##
## Existe para a Fase 2, em que as tarefas CHEGAM em vez de esperar: elas nascem acima
## do teto, à frente do jogador, e descem à vista dele até `pousa`. Cair é só a entrada
## em cena — depois de pousar a tarefa é idêntica a qualquer outra, com as mesmas regras
## do Quadro 1. Ver scripts/spawner_tarefas.gd.
@export var queda: float = 0.0

## Altura (y local) em que a queda para. Ignorado enquanto `queda` for 0.
@export var pousa: float = 0.0

## Distância, medida no eixo de avanço da fase, a partir da qual a tarefa conta como
## deixada para trás.
const MARGEM_EVITOU := 40.0

## Raio em que o enunciado aparece no mundo. Bate com o CircleShape2D de
## `Proximidade` em tarefa.tscn — os dois precisam andar juntos.
const RAIO_ROTULO := 96.0

## Recorte do ícone neutro em sprites/PixelOffice/PixelOfficeAssets.png: uma folha de
## papel. É o MESMO para os quatro quadrantes, de propósito — se o ícone variasse por
## categoria, a cor entregaria a resposta e não haveria classificação nenhuma.
## É a única folha do pack que continua legível a 6x9px sobre a parede.
const REGIAO_ICONE := Rect2(192, 107, 6, 9)

## Cor do ícone e do halo enquanto a tarefa não foi resolvida: papel branco, neutro.
const COR_NEUTRA := Color("f2f2f2")

@onready var icone: Sprite2D = $Icone
## Halo atrás do ícone: um Polygon2D em vez de textura porque nenhum dos packs tem um
## brilho circular, e um disco vetorial escala e pulsa sem borrar o pixel art.
@onready var brilho: Polygon2D = $Brilho
@onready var rotulo: Label = $Rotulo
@onready var colisor: CollisionShape2D = $CollisionShape2D
@onready var proximidade: Area2D = $Proximidade

var _resolvida := false
var _posicao_base := Vector2.ZERO
var _fase := 0.0
var _jogador: Node2D = null
var _rotulo_visivel := false
## Para que lado a fase avança — ver FaseBase.eixo_de_avanco().
var _eixo := Vector2.RIGHT


func _ready() -> void:
	add_to_group("tarefa")
	_posicao_base = position
	# Defasa a oscilação pela posição para que Q4 vizinhas não subam e desçam juntas.
	_fase = fmod(absf(_posicao_base.x) * 0.05, TAU)

	_aplicar_visual()

	body_entered.connect(_ao_tocar)

	var jogadores := get_tree().get_nodes_in_group("Player")
	if not jogadores.is_empty():
		_jogador = jogadores[0]

	var fase := get_tree().get_first_node_in_group("fase")
	if fase != null and fase.has_method("eixo_de_avanco"):
		_eixo = fase.eixo_de_avanco().normalized()


func _physics_process(delta: float) -> void:
	_cair(delta)

	if amplitude != Vector2.ZERO and periodo > 0.0:
		_fase += TAU * delta / periodo
		position = _posicao_base + amplitude * sin(_fase)

	_atualizar_rotulo()
	_checar_deixou_para_tras()


## Descida da tarefa que chega (Fase 2). Move a POSIÇÃO BASE, e não a posição direta,
## para que uma Q4 que oscila continue oscilando em torno de onde pousou.
func _cair(delta: float) -> void:
	if queda <= 0.0 or _posicao_base.y >= pousa:
		return
	_posicao_base.y = minf(_posicao_base.y + queda * delta, pousa)
	position.y = _posicao_base.y


## Só a tarefa MAIS PRÓXIMA mostra o próprio enunciado. O raio é de 96px e há trechos com
## quatro tarefas nesse espaço: sem a regra, quatro rótulos se sobrepõem e nenhum fica
## legível — e num jogo cuja mecânica é ler e classificar, isso é a mecânica quebrada.
##
## A arbitragem é da própria tarefa, varrendo o grupo, e não de um gerente central: são
## poucas tarefas, e assim a cena funciona sozinha em qualquer fase.
func _atualizar_rotulo() -> void:
	if _resolvida or _jogador == null:
		return

	var minha := global_position.distance_squared_to(_jogador.global_position)
	# O raio cresce em modo foco: a 180 px/s com 96px o jogador tem 0,53s para ler e
	# decidir; a 117 px/s com 264px, 2,2s.
	var raio := RAIO_ROTULO * GameManager.fator_do_raio()
	# atencao_livre(): interrupção em curso (Fase 2) apaga o enunciado. É o custo real da
	# notificação — o jogador continua correndo, mas classifica sem poder ler.
	var visivel := minha <= raio * raio and GameManager.atencao_livre()
	if visivel:
		for outra in get_tree().get_nodes_in_group("tarefa"):
			if outra == self or outra.esta_resolvida():
				continue
			if outra.global_position.distance_squared_to(_jogador.global_position) < minha:
				visivel = false
				break

	# A faixa do HUD segue o mesmo raio do rótulo do mundo, e não um raio fixo: em foco o
	# enunciado precisa aparecer nos dois lugares ao mesmo tempo.
	if visivel and not _rotulo_visivel:
		get_tree().call_group("hud", "mostrar_dica", "TAREFA", texto, COR_NEUTRA)
	_rotulo_visivel = visivel

	var alvo := 1.0 if visivel else 0.0
	if is_equal_approx(rotulo.modulate.a, alvo):
		return
	# move_toward em vez de tween: isto roda todo quadro, e criar um tween por
	# quadro vazaria objetos até o fim da fase.
	rotulo.modulate.a = move_toward(rotulo.modulate.a, alvo, 0.12)


func esta_resolvida() -> bool:
	return _resolvida


## Troca o enunciado depois de a cena já estar montada (o sorteio da fase roda com as
## tarefas do corredor já prontas, e escrever em `texto` sozinho não repinta o rótulo).
func definir_texto(novo: String) -> void:
	texto = novo
	if is_node_ready():
		rotulo.text = texto


## Posição em torno da qual a tarefa oscila. Existe para o teste de geometria: desde que
## TODA tarefa passou a balançar, ler `position` devolve um ponto qualquer do
## ciclo, e uma asserção de alcance passaria ou falharia conforme o frame em que caísse.
## O jogador pode esperar o balanço, então o que precisa ser alcançável é a base.
func posicao_base() -> Vector2:
	return _posicao_base


## Todas as tarefas nascem iguais: papel branco, halo branco, sem nada que denuncie o
## quadrante. A cor da categoria só aparece DEPOIS da ação, em _revelar().
func _aplicar_visual() -> void:
	icone.region_enabled = true
	icone.region_rect = REGIAO_ICONE
	icone.modulate = COR_NEUTRA
	brilho.modulate = Color(COR_NEUTRA.r, COR_NEUTRA.g, COR_NEUTRA.b, 0.3)

	rotulo.text = texto
	rotulo.modulate.a = 0.0

	var pulso := create_tween().set_loops()
	pulso.tween_property(brilho, "scale", Vector2(1.15, 1.15), 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulso.tween_property(brilho, "scale", Vector2(0.9, 0.9), 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _ao_tocar(corpo: Node2D) -> void:
	if _resolvida or not corpo.is_in_group("Player") or not GameManager.em_jogo:
		return

	# Em foco a distração não pega. Não é invencibilidade: a tarefa continua ali e, se o
	# jogador seguir em frente, ela ainda se registra como EVITOU quando ficar para trás.
	# O que ele comprou foi passar por dentro dela sem se enrolar — e pagou em ritmo.
	if (
		GameManager.foco_ativo
		and categoria == GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE
	):
		return

	# Encostar é sempre a mesma ação física; o que muda é se ela era a certa para
	# aquele quadrante. Numa Q4, "fazer agora" é o erro.
	if categoria == GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE:
		_registrar(GameManager.Acao.COLIDIU, true)
	else:
		_registrar(GameManager.Acao.COLETAR, false)


## Uma tarefa que ficou para trás sem ser tocada é registrada do mesmo jeito: EVITOU
## quando ignorar era o certo (Q4), IGNOROU nas demais. Sem isso a nota por categoria
## contaria só os acertos, e o relatório final não conseguiria responder "quantas Q1
## você deixou passar" — que é o dado mais interessante para a discussão do TCC.
func _checar_deixou_para_tras() -> void:
	if _resolvida or _jogador == null:
		return
	# Projeção no eixo da fase, e não comparação de X: numa escalada, o jogador passa
	# uma tarefa subindo, quase sem sair da coluna dela.
	if _jogador.global_position.dot(_eixo) <= global_position.dot(_eixo) + MARGEM_EVITOU:
		return

	var certo := categoria == GameManager.Categoria.NAO_URGENTE_NAO_IMPORTANTE
	_registrar(GameManager.Acao.EVITOU if certo else GameManager.Acao.IGNOROU, true)


## O colega assumiu esta tarefa: ela sai do corredor sem o jogador precisar desviar.
##
## Registra EVITOU, que vale 0 no Quadro 1 — e é por isso que a mecânica do colega não
## contradiz a Metodologia. Delegar uma Q3 já pagou os +60 dela; o que o colega entrega
## aqui é a REMOÇÃO de um risco de −20 e −8 s, não pontuação nova. Contar como EVITOU
## também mantém honesto o relatório por categoria: a distração de fato não atrapalhou.
func assumir() -> void:
	if _resolvida:
		return
	# A onda existe para o caso de o jogador estar olhando: uma tarefa que simplesmente
	# some da tela lê como falha de renderização, não como efeito de uma decisão dele.
	Feedback.onda(get_parent(), global_position, COR_NEUTRA, 28.0)
	_registrar(GameManager.Acao.EVITOU, false)


## Ponto único por onde toda ação da tarefa passa: aplica o Quadro 1 no GameManager,
## mostra o número que saltou e revela o quadrante.
##   permanece = a tarefa continua na tela, apagada (Q4 batida, tarefa perdida);
##               senão ela some, porque foi levada junto com o jogador.
func _registrar(acao: GameManager.Acao, permanece: bool) -> void:
	_resolvida = true
	var efeito := GameManager.registrar_acao(categoria, acao, texto)
	var cor: Color = GameManager.COR_CATEGORIA[categoria]

	# Desviar de uma distração NÃO gera texto flutuante. É a ação mais frequente da
	# fase e a que menos precisa de aviso — o jogador acertou justamente por nada ter
	# acontecido. Seis "desviou" subindo ao mesmo tempo, como acontecia no enxame de
	# Q4, cobriam o "deixou passar" da tarefa importante logo ao lado. O acerto
	# continua contando no relatório final e no som; só não disputa a tela.
	if acao != GameManager.Acao.EVITOU:
		var aviso := "%+d" % int(efeito["pontos"])
		if efeito["delta_tempo"] != 0.0:
			aviso += "  %ds" % int(efeito["delta_tempo"])
		if acao == GameManager.Acao.IGNOROU:
			aviso = "deixou passar"
		Feedback.pontos(get_parent(), global_position, aviso, cor)

	# Só o que o jogador FEZ estoura. Uma tarefa deixada para trás é registrada em
	# silêncio: encher a tela de partículas nas seis Q4 que ele corretamente ignorou
	# transformaria o acerto em poluição visual.
	if acao == GameManager.Acao.COLETAR:
		Feedback.estouro(get_parent(), global_position, cor, 16, 82.0)
		Feedback.onda(get_parent(), global_position, cor, 34.0)
		Juice.tremer(0.14)
	elif acao == GameManager.Acao.COLIDIU:
		Feedback.estouro(get_parent(), global_position, cor, 20, 100.0)
		Juice.impacto(0.6)
		Juice.flash(cor, 0.16)

	# Antes do queue_free: quem escuta precisa poder ler `texto_maduro` e a posição.
	if acao == GameManager.Acao.IGNOROU:
		adiada.emit(self)

	if not permanece:
		queue_free()
		return

	_revelar(cor)


## Revela o quadrante e some: o papel pisca na cor da categoria e então sobe e some.
##
## O nó continua vivo, invisível — a contagem de chegadas do Dia 2 varre as tarefas da
## cena, e sumir da árvore mudaria o que ela conta.
func _revelar(cor: Color) -> void:
	colisor.set_deferred("disabled", true)
	proximidade.set_deferred("monitoring", false)
	icone.modulate = cor
	brilho.visible = false

	var saida := create_tween().set_parallel(true)
	saida.tween_property(rotulo, "modulate:a", 0.0, 0.2)
	saida.tween_property(icone, "position:y", icone.position.y - 12.0, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	saida.tween_property(icone, "modulate:a", 0.0, 0.6).set_delay(0.3)
