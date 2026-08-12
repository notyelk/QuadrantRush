# Herança por caminho, e não pelo class_name FaseBase: nomes globais de classe vivem no
# cache que o EDITOR gera, e este projeto roda teste e captura de tela por linha de
# comando, sem abrir o editor. Pelo caminho funciona nos dois modos.
extends "res://scripts/fase_base.gd"

## Fase 2 — "O dia das interrupções", com a mecânica da pendência que amadurece.
##
## No Dia 1 o jogador encontra as tarefas; aqui elas chegam até ele. E o que ele deixou
## passar volta pior: uma Q2 adiada reaparece segundos depois como Q1, com o enunciado
## reescrito como a crise que virou ("Testar o backup antes que ele falhe sozinho" →
## "O backup falhou: recuperar o arquivo do cliente").
##
## A tarefa muda de quadrante e passa a valer o que o Quadro 1 já manda valer: nenhum
## ponto novo. O preço de adiar não é ponto, é obrigação sob relógio fixo — cada crise
## sobe a cota do elevador em 1, nasce fora da linha de quem corre, e o dia é perdido se
## ela não for coletada.
##
## Setores (colunas de 16px):
##   0 recepção 0–19 · 1 caixa de entrada 20–49 · 2 telefones 50–79 ·
##   3 enxame 80–115 · 4 arquivo 116–145 · 5 fechamento 146–169 · 6 saída 170–175

## 70s, e este número não deve ser cortado para dificultar o dia: o percurso que trata
## TUDO consome ~65s mesmo sem sofrer uma interrupção, então cortar acaba com o dia
## perfeito — condição fixa do projeto, e base do teto de pontuação e do ranking. O
## cenário 2 da suíte mede essa sobra e reprova o corte.
##
## A dificuldade vem das interrupções, que são a identidade do dia: sete, com custo e
## cegueira crescentes ao longo do corredor, somando ~21s se todas acertarem. Ao
## contrário de um relógio curto, isso é evitável por quem joga bem.
const TEMPO_FASE := 70.0

## Quantas urgentes o elevador exige de saída, ANTES de qualquer maturação.
##
## O Dia 1 exige TODAS as Q1, e lá isso é justo porque elas ficam paradas esperando. Aqui
## elas caem: uma Q1 pode chegar enquanto o jogador está lidando com outra coisa, e exigir
## todas transformaria um descuido em partida impossível.
const META_URGENTES := 4

## Distância à frente do jogador em que cada chegada nasce. 320px é além da borda direita
## da tela (que fica a 200px do centro), então nada aparece em cima dele: a tarefa entra
## em quadro já caindo, com tempo de ser lida antes de pousar.
const AVANCO_DA_CHEGADA := 320.0

const ALTURA_DE_ENTRADA := 16.0
const VELOCIDADE_DE_QUEDA := 120.0

## Segundos entre adiar uma pendência e ela voltar como crise.
##
## Tempo bastante para o jogador ter seguido em frente e ter esquecido — que é exatamente
## o ponto. Uma crise que voltasse na hora leria como "a tarefa não sumiu"; ela precisa
## voltar depois, quando ele já está lidando com outra coisa.
##
## Baixou de 8,0 para 6,5. A crise nasce no primeiro ponto pelo menos 200px
## à frente do jogador, então quanto mais tarde ela volta, mais longe do trecho em que ele
## está ela aparece — e uma crise que nasce dois setores adiante deixa de ser a conta do
## adiamento e vira uma corrida de ida e volta. Com 6,5s ela volta enquanto ele ainda está
## por perto, cobrando ATENÇÃO em vez de quilometragem, que é o que a fase quer cobrar.
const ATRASO_DA_CRISE := 6.5

## A crise nasce no primeiro ponto de crise pelo menos isto à frente do jogador. Menos que
## isso e ela apareceria dentro da tela, em cima dele.
const FOLGA_DA_CRISE := 200.0

## Onde uma crise pode nascer, e a que altura. Cópia da tabela de tools/gerar_fase_02.py,
## que é quem VALIDA que cada um destes x cai no topo de uma plataforma de verdade —
## duplicação de propósito, conferida por teste, no mesmo regime das outras tabelas.
const PONTOS_DE_CRISE := [416, 688, 864, 1088, 1344, 1504, 1792, 2112, 2256, 2560]
const CRISE_POUSA := 128.0

## A agenda do dia, em ordem de corredor. `x` é onde a coisa vai parar; o gatilho é
## sempre `x - AVANCO_DA_CHEGADA`, calculado em _agenda_com_gatilhos().
##
## Os enunciados são a única informação que o jogador recebe antes de decidir — nenhum
## deles pode citar o quadrante. E toda Q2 traz junto o enunciado da crise que ela vira:
## os dois são escritos ao mesmo tempo, porque separados não contam história nenhuma.
const AGENDA := [
	# setor 0 · recepção — a primeira tarefa cai sem nenhuma ameaça em volta
	{"x": 336.0, "pousa": 160.0, "categoria": 0, "texto": "Cliente ao telefone: o contrato vence hoje"},
	{"x": 464.0, "pousa": 160.0, "categoria": 3, "texto": "Notificação de rede social", "amplitude": Vector2(0, 12)},

	# setor 1 · caixa de entrada — a primeira interrupção do dia, e a mais barata: ela
	# existe para ENSINAR o que uma interrupção faz, não para castigar quem ainda não sabe.
	{
		"x": 544.0, "pousa": 96.0, "categoria": 1,
		"texto": "Planejar o roadmap do próximo trimestre",
		"texto_maduro": "Diretoria cobra o roadmap na reunião de agora",
		"amplitude": Vector2(0, 10), "periodo": 2.6,
	},
	{"x": 640.0, "pousa": 160.0, "categoria": 0, "texto": "Servidor de produção fora do ar"},
	{"x": 656.0, "y": 66.0, "tipo": "notificacao", "custo_em_segundos": 2.0, "cegueira": 1.4, "vida": 3.0},
	{"x": 736.0, "pousa": 160.0, "categoria": 3, "texto": "Vídeo engraçado no grupo do trabalho", "amplitude": Vector2(14, 0)},

	# setor 2 · telefones (as duas bifurcações Q3 ficam paradas na cena)
	{"x": 800.0, "pousa": 160.0, "categoria": 3, "texto": "Mensagem de voz de dois minutos", "amplitude": Vector2(0, 13)},
	{"x": 976.0, "pousa": 160.0, "categoria": 0, "texto": "Folha de pagamento fecha em uma hora"},
	{"x": 1024.0, "pousa": 160.0, "categoria": 3, "texto": "Promoção relâmpago: só nas próximas 2 horas", "amplitude": Vector2(0, 12)},
	{"x": 1120.0, "y": 72.0, "tipo": "notificacao", "custo_em_segundos": 2.5, "cegueira": 1.8},
	{"x": 1152.0, "pousa": 160.0, "categoria": 3, "texto": "Convite para o amigo secreto do setor", "amplitude": Vector2(15, 0)},

	# setor 3 · enxame — o ritmo dobra e as interrupções ficam caras
	{"x": 1264.0, "pousa": 160.0, "categoria": 0, "texto": "Auditoria pede o relatório ainda hoje"},
	{"x": 1296.0, "pousa": 160.0, "categoria": 3, "texto": "Alguém marcou você numa foto", "amplitude": Vector2(16, 0)},
	{"x": 1360.0, "y": 70.0, "tipo": "notificacao"},
	{"x": 1520.0, "y": 58.0, "tipo": "notificacao", "cegueira": 2.6},
	{"x": 1552.0, "pousa": 160.0, "categoria": 3, "texto": "Enquete no grupo: pizza ou hambúrguer?", "amplitude": Vector2(0, 14)},
	{"x": 1600.0, "pousa": 160.0, "categoria": 0, "texto": "Nota fiscal do cliente vence em 40 minutos"},
	{
		"x": 1632.0, "pousa": 96.0, "categoria": 1,
		"texto": "Testar o backup antes que ele falhe sozinho",
		"texto_maduro": "O backup falhou: recuperar o arquivo do cliente",
		"amplitude": Vector2(0, 10), "periodo": 2.6,
	},
	{"x": 1696.0, "pousa": 160.0, "categoria": 3, "texto": "Newsletter que você nunca assinou", "amplitude": Vector2(0, 12)},
	{"x": 1760.0, "y": 60.0, "tipo": "notificacao", "custo_em_segundos": 3.5, "cegueira": 2.6},

	# setor 4 · arquivo — nada chega aqui, de propósito. Depois do enxame, o silêncio é
	# sentido como recompensa, e é lá que ficam as tarefas que exigem escalada.

	# setor 5 · fechamento — as duas últimas interrupções são as mais rápidas e as mais
	# caras. É o fim do dia, e é quando a atenção já está gasta: a fase cobra caro
	# justamente onde o jogador está com pressa de sair, que é quando ele mais se distrai.
	{
		"x": 2400.0, "pousa": 96.0, "categoria": 1,
		"texto": "Documentar o processo que só você sabe fazer",
		"texto_maduro": "Você está de folga amanhã e ninguém sabe rodar o fechamento",
		"amplitude": Vector2(0, 10), "periodo": 2.6,
	},
	{"x": 2432.0, "pousa": 160.0, "categoria": 3, "texto": "Corrente de mensagens do grupo da família", "amplitude": Vector2(0, 12)},
	{"x": 2480.0, "y": 64.0, "tipo": "notificacao", "custo_em_segundos": 4.0, "cegueira": 3.0, "velocidade": 74.0},
	{"x": 2496.0, "pousa": 160.0, "categoria": 3, "texto": "Vídeo de gatinho que alguém encaminhou", "amplitude": Vector2(16, 0)},
	{"x": 2608.0, "pousa": 160.0, "categoria": 3, "texto": "Lista de presentes de fim de ano", "amplitude": Vector2(0, 11)},
	{"x": 2640.0, "y": 68.0, "tipo": "notificacao", "custo_em_segundos": 4.0, "cegueira": 3.0, "velocidade": 74.0},
	{"x": 2672.0, "pousa": 160.0, "categoria": 3, "texto": "Retrospectiva do ano em vídeo", "amplitude": Vector2(13, 0)},
]

@onready var spawner: Node2D = $Spawner

## Quantas pendências já viraram crise nesta partida. Some à cota do elevador.
var crises := 0

## Pendências esperando para amadurecer: [{"resta": segundos, "texto": enunciado da crise}].
var _maturando: Array = []


func tempo_de_expediente() -> float:
	return TEMPO_FASE


func numero_do_dia() -> int:
	return 2


## A cota CRESCE durante o expediente. É aqui que o adiamento cobra a conta: cada
## pendência que amadureceu acrescenta uma urgente obrigatória ao dia.
func meta_de_urgentes() -> int:
	return META_URGENTES + crises


## O modo foco acompanha o jogador do Dia 1 para cá. É habilidade aprendida, não pressão
## de fase — tirá-la seria desaprender. E aqui ela encontra o adversário certo: o foco
## dobra o raio de leitura, mas NÃO barra a notificação, que é justamente o que cega a
## leitura. O antídoto tem limite, e é isso que mantém a identidade do dia.
func usa_foco() -> bool:
	return true


func abertura() -> Array:
	return [
		"DIA 2 — AS TAREFAS CHEGAM",
		"Hoje elas não esperam. E o que você deixar passar volta pior.",
		Color("5aa9e6"),
	]


## Os trechos do corredor. Aqui eles anunciam a ESCALADA: as interrupções ficam
## progressivamente mais caras e mais rápidas, e sem aviso essa curva é invisível — o
## jogador sente que "de repente ficou difícil" e conclui que o jogo é injusto.
##
## O setor 4 é o único que promete calma, e cumpre: nada chega lá. Anunciar o silêncio é o
## que o transforma de vazio em respiro.
func setores() -> Array:
	return [
		{
			"em": 320.0, "nome": "CAIXA DE ENTRADA",
			"dica": "As tarefas caem à sua frente. Leia antes de encostar.",
			"cor": Color("5aa9e6"),
		},
		{
			"em": 800.0, "nome": "OS TELEFONES",
			"dica": "Suba na bandeja para delegar. As interrupções começam a insistir.",
			"cor": Color("5aa9e6"),
		},
		{
			"em": 1280.0, "nome": "O ENXAME",
			"dica": "Três interrupções aqui. Elas apagam o enunciado de tudo — desvie.",
			"cor": Color("e0a458"),
		},
		{
			"em": 1856.0, "nome": "O ARQUIVO",
			"dica": "Nada chega aqui. Use o silêncio: o que está no alto exige subir.",
			"cor": Color("4ea36b"),
		},
		{
			"em": 2336.0, "nome": "FECHAMENTO",
			"dica": "As últimas interrupções são as mais caras. Pressa é o que elas caçam.",
			"cor": Color("e05c5c"),
		},
	]


## Linha extra do relatório final. É o dado mais interessante do dia para a discussão do
## TCC: quantas vezes o adiamento cobrou a conta.
func extras_do_resultado() -> Array:
	if GameManager.pendencias_amadurecidas <= 0:
		return []
	return [["Pendências que viraram crise", str(GameManager.pendencias_amadurecidas)]]


func _preparar() -> void:
	spawner.velocidade_de_queda = VELOCIDADE_DE_QUEDA
	spawner.definir_agenda(_agenda_com_gatilhos())
	spawner.chegou.connect(_ao_chegar)
	GameManager.interrupcao_sofrida.connect(_ao_ser_interrompido)

	# As tarefas paradas do arquivo já estão na cena e também podem ser adiadas.
	for tarefa in tarefas.get_children():
		_escutar_adiamento(tarefa)


## O gatilho de cada entrada é derivado do x de destino, nunca digitado: assim mover uma
## tarefa no corredor não exige lembrar de mover o gatilho junto — erro que passaria sem
## ninguém notar até a tarefa nascer em cima do jogador.
func _agenda_com_gatilhos() -> Array:
	var pronta: Array = []
	for entrada in AGENDA:
		var copia: Dictionary = entrada.duplicate()
		copia["gatilho"] = maxf(float(entrada["x"]) - AVANCO_DA_CHEGADA, 0.0)
		copia["y"] = float(entrada.get("y", ALTURA_DE_ENTRADA))
		pronta.append(copia)
	return pronta


## A composição da fase é o corredor MAIS a agenda: sem somar as duas, o relatório final
## diria "1 de 2 urgentes" numa fase em que existiam sete.
func _mapear_composicao() -> Dictionary:
	var mapa: Dictionary = super()
	var previsto: Dictionary = spawner.composicao_prevista()
	for categoria in GameManager.Categoria.values():
		mapa[categoria] += int(previsto[categoria])
	return mapa


func _ao_chegar(no: Node2D, _entrada: Dictionary) -> void:
	_escutar_adiamento(no)


## Passa a ouvir o "fui deixada para trás" de uma tarefa. Vale para qualquer nó: o
## spawner também produz notificações, e o nó Tarefas recebe os textos flutuantes do
## Feedback, que são Labels. Perguntar pelo sinal é mais barato e mais honesto que
## perguntar pelo tipo.
func _escutar_adiamento(no: Node) -> void:
	if no != null and no.has_signal("adiada") and not no.adiada.is_connected(_ao_adiar):
		no.adiada.connect(_ao_adiar)


## Uma tarefa foi deixada para trás. Só as Q2 com enunciado de crise escrito amadurecem —
## e uma crise nunca amadurece de novo, porque ela nasce sem `texto_maduro`. Sem essa
## trava, ignorar a crise geraria outra crise, e outra: espiral sem saída, que é
## exatamente o tipo de punição que este projeto recusou seis vezes seguidas.
func _ao_adiar(tarefa: Node) -> void:
	if not GameManager.em_jogo:
		return
	if tarefa.categoria != GameManager.Categoria.IMPORTANTE_NAO_URGENTE:
		return
	if str(tarefa.texto_maduro).is_empty():
		return
	_maturando.append({"resta": ATRASO_DA_CRISE, "texto": str(tarefa.texto_maduro)})


func _atualizar(delta: float) -> void:
	if _maturando.is_empty() or not GameManager.em_jogo:
		return
	# Percorre de trás para a frente: a lista encolhe durante a varredura.
	for i in range(_maturando.size() - 1, -1, -1):
		_maturando[i]["resta"] -= delta
		if _maturando[i]["resta"] > 0.0:
			continue
		var texto: String = _maturando[i]["texto"]
		_maturando.remove_at(i)
		_amadurecer(texto)


## A pendência volta como urgente.
func _amadurecer(texto: String) -> void:
	var crise: Node2D = spawner.produzir_avulsa({
		"x": _ponto_de_crise(),
		"y": ALTURA_DE_ENTRADA,
		"pousa": CRISE_POUSA,
		"categoria": GameManager.Categoria.URGENTE_IMPORTANTE,
		"texto": texto,
		"amplitude": Vector2(0, 10),
		"periodo": 2.6,
	})
	if crise == null:
		return

	crises += 1
	GameManager.pendencias_amadurecidas += 1
	# O relatório precisa saber que existe mais uma urgente no dia, senão o "X de N" da
	# tela de resultado passaria a mentir para menos.
	composicao[GameManager.Categoria.URGENTE_IMPORTANTE] += 1
	# Sobe a cota e, se o elevador já tinha aberto, tranca de novo. Sem isto, adiar depois
	# de cumprida a cota sairia de graça.
	revisar_meta()

	Audio.tocar("erro", -4.0)
	Juice.tremer(0.25)
	Feedback.onda(
		tarefas, crise.global_position,
		GameManager.COR_CATEGORIA[GameManager.Categoria.URGENTE_IMPORTANTE], 40.0
	)
	# Prioridade 3: acima de tudo o que a fase manda para a faixa. Sem o anúncio, a
	# mecânica é invisível — o jogador vê uma urgente nova e não a liga ao que ele fez.
	get_tree().call_group(
		"hud", "mostrar_dica", "O QUE VOCÊ ADIOU VIROU URGÊNCIA", texto,
		GameManager.COR_CATEGORIA[GameManager.Categoria.URGENTE_IMPORTANTE], 3
	)


## Primeiro ponto de crise à frente do jogador. Se ele já passou de todos, a crise nasce
## no último: ela fica para trás e ele precisa voltar. Voltar é caro e é justo — não há
## perseguidor neste dia, e o preço continua sendo tempo, que é a moeda do jogo.
func _ponto_de_crise() -> float:
	var limite := jogador.global_position.x + FOLGA_DA_CRISE
	for x in PONTOS_DE_CRISE:
		if float(x) >= limite:
			return float(x)
	return float(PONTOS_DE_CRISE[-1])


func _ao_ser_interrompido(total: int) -> void:
	# O contador vive no HUD junto do resto do estado do expediente. É informativo, não
	# penaliza pontuação — mas é o dado que o doc de 5 fases pede para o relatório.
	hud.atualizar_interrupcoes(total)
