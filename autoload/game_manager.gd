extends Node

## Estado central da sessão de jogo: pontuação, cronômetro de expediente e contadores
## por categoria da Matriz de Eisenhower (Quadro 1 da Metodologia). Autoload —
## acessível de qualquer script como GameManager.*
##
## Este nó é a ÚNICA fonte de verdade de pontuação e tempo. A fase orquestra apenas
## o que é local dela (checkpoint, contagem de obrigatórias, sequência); o HUD e a
## tela de resultado só leem daqui e escutam os sinais abaixo. Ninguém alcança dentro
## de ninguém — é isso que deixa a Etapa 7 (Supabase) trivial depois: basta ler este
## mesmo objeto no fim da sessão.
##
## Atende as Etapas 2 (modelagem da mecânica) e 5 (cronômetro de expediente).

signal pontuacao_mudou(total: int)
signal tempo_mudou(restante: float)
signal tarefa_registrada(categoria: Categoria, acao: Acao, pontos: int, delta_tempo: float)
signal fase_terminada(vitoria: bool)
## Interrupção sofrida (Fase 2). Não é uma ação da matriz — ver registrar_interrupcao().
signal interrupcao_sofrida(total: int)

enum Categoria {
	URGENTE_IMPORTANTE,         # Q1 — coletar (obrigatório)
	IMPORTANTE_NAO_URGENTE,     # Q2 — coletar com folga
	URGENTE_NAO_IMPORTANTE,     # Q3 — delegar ou resolver
	NAO_URGENTE_NAO_IMPORTANTE, # Q4 — evitar
}

enum Acao {
	COLETAR,
	DELEGAR,
	RESOLVER,
	EVITOU,
	COLIDIU,
	## Deixou a tarefa para trás sem agir. Vale 0 ponto: não é penalidade nova, é o registro
	## de que a tarefa existiu e não foi tratada — sem ele a nota por categoria contaria só
	## os acertos.
	IGNOROU,
}

## Tempo de expediente padrão da Fase 1, em segundos.
const TEMPO_PADRAO_FASE := 90.0

## Onde mora cada dia de expediente e como ele se chama. Uma tabela só, porque título,
## resultado e a própria fase precisam da mesma informação, e três cópias de caminho de
## cena divergem no primeiro dia em que alguém renomear um arquivo.
const CENA_DO_DIA := {
	1: "res://scenes/level/fase_01.tscn",
	2: "res://scenes/level/fase_02.tscn",
	3: "res://scenes/level/fase_03.tscn",
}

const NOME_DO_DIA := {
	1: "Dia 1 · O primeiro dia",
	2: "Dia 2 · O dia das interrupções",
	3: "Dia 3 · A reunião de encerramento",
}

## Quantas tarefas e quantos segundos cada dia tem. Servem ao briefing, que roda antes de
## a fase existir e por isso não pode perguntar a ela. São números repetidos, e todo
## número repetido diverge um dia: `tests/teste_fase_01.gd` confere as duas tabelas contra
## a composição real das cenas, para que a suíte falhe em vez de o briefing mentir.
const TAREFAS_DO_DIA := {1: 24, 2: 25, 3: 44}
const SEGUNDOS_DO_DIA := {1: 60.0, 2: 70.0, 3: 100.0}

## Nomes exibidos ao jogador (faixa do HUD e tela de resultado). O jogo é em
## português porque o TCC é em português — evita traduzir na hora de tirar print.
const NOME_CATEGORIA := {
	Categoria.URGENTE_IMPORTANTE: "URGENTE E IMPORTANTE",
	Categoria.IMPORTANTE_NAO_URGENTE: "IMPORTANTE, NÃO URGENTE",
	Categoria.URGENTE_NAO_IMPORTANTE: "URGENTE, NÃO IMPORTANTE",
	Categoria.NAO_URGENTE_NAO_IMPORTANTE: "NEM URGENTE NEM IMPORTANTE",
}

## Cor de cada quadrante — usada pelo ícone da tarefa, pela borda da faixa do HUD e
## pela tela de resultado, pra que a mesma categoria tenha sempre a mesma cor.
const COR_CATEGORIA := {
	Categoria.URGENTE_IMPORTANTE: Color("e05c5c"),
	Categoria.IMPORTANTE_NAO_URGENTE: Color("4ea36b"),
	Categoria.URGENTE_NAO_IMPORTANTE: Color("5aa9e6"),
	Categoria.NAO_URGENTE_NAO_IMPORTANTE: Color("f2c14e"),
}

## Frase de reforço pedagógico mostrada na faixa do HUD no momento da ação — o "retorno da
## última tarefa resolvida" da Etapa 6 servindo também de canal de ensino da matriz.
##
## Depende da CATEGORIA além da ação: coletar uma Q1 é acerto e coletar uma Q4 é o erro que
## a matriz existe para evitar, então uma frase por ação elogiaria e repreenderia com o
## mesmo texto.
const _LICAO := {
	Categoria.URGENTE_IMPORTANTE: {
		Acao.COLETAR: "Certo: urgente e importante se faz primeiro.",
		Acao.IGNOROU: "Era urgente e importante. Deixar passar vira crise.",
	},
	Categoria.IMPORTANTE_NAO_URGENTE: {
		Acao.COLETAR: "Certo: importante sem ser urgente é o que evita crise depois.",
		Acao.IGNOROU: "Importante, não urgente. Adiar hoje é apagar incêndio amanhã.",
	},
	Categoria.URGENTE_NAO_IMPORTANTE: {
		Acao.DELEGAR: "Delegado. Urgente para os outros, não para você.",
		Acao.RESOLVER: "Você resolveu sozinho — custou tempo seu.",
		Acao.IGNOROU: "Urgente para alguém: ignorar não faz sumir.",
	},
	Categoria.NAO_URGENTE_NAO_IMPORTANTE: {
		Acao.EVITOU: "Certo: desviou da distração.",
		Acao.COLIDIU: "Nem urgente nem importante. Distração custa pontos e tempo.",
		Acao.IGNOROU: "Certo: desviou da distração.",
	},
}

## Frase mostrada quando a combinação categoria+ação não tem texto próprio.
const _LICAO_PADRAO := "Tarefa registrada."

var pontuacao_total: int = 0
var tempo_restante: float = 0.0

## Enquanto false o cronômetro não corre (antes de começar, e depois do fim de fase).
var em_jogo: bool = false

var tarefas_por_categoria: Dictionary = {}
var pontuacao_por_categoria: Dictionary = {}

## Contagem por tipo de ação — permite responder no relatório final "quantas Q3 ele
## delegou vs resolveu", que a contagem por categoria sozinha não responde.
var acoes_por_tipo: Dictionary = {}

## Cada decisão equivocada da partida, na ordem: {categoria, acao, enunciado}. É o que a
## tela de lição lê para explicar por que aquela tarefa pedia outro tratamento.
var equivocos: Array[Dictionary] = []

## Interrupções sofridas (Fase 2). Fora de acoes_por_tipo: não é tarefa da matriz, e
## misturá-la ali quebraria a leitura por categoria.
var interrupcoes: int = 0

## Q2 adiadas a ponto de voltarem como urgentes (Fase 2, ver scripts/fase_02.gd). Fora de
## acoes_por_tipo pelo mesmo motivo: amadurecer é consequência, não ação. As duas tarefas
## envolvidas já contam pela regra normal; este contador só responde quantas vezes o
## adiamento cobrou a conta.
var pendencias_amadurecidas: int = 0

## Qual expediente está em curso (1 = Fase 1, 2 = Fase 2). A tela de resultado usa para
## saber se existe um próximo dia, e a Etapa 7 vai gravar isto junto do placar.
var dia: int = 1

## Preenchido por finalizar_fase(); a tela de resultado lê pra saber o que mostrar.
var ultima_vitoria: bool = false
var tempo_gasto: float = 0.0
var _tempo_inicial: float = TEMPO_PADRAO_FASE

## Segundos restantes de atenção roubada por uma interrupção. Ver registrar_interrupcao().
var _atencao_bloqueada: float = 0.0

## Quantas tarefas o jogador carrega sem ter entregado. Não é pontuação: os pontos são
## creditados na hora. A pasta acumula peso, e peso vira velocidade — fica fora de
## registrar_acao(), como o ladrão de tempo e a queda no vão.
var carga_da_pasta: int = 0

## Ligada pela fase que usa a mecânica. Neutra por padrão, e é isso que mantém as Fases 2
## e 3 idênticas ao que eram: sem a caixa de saída no corredor delas, carregar peso seria
## penalidade sem antídoto.
var pasta_em_uso: bool = false

signal carga_mudou(carga: int)

## Satura em 5 itens: 5 x 5% = 25% mais lento, e nunca mais que isso.
##
## PASTA_PISO é a velocidade contra a qual tools/gerar_fase_01.py valida toda travessia
## obrigatória. Baixá-lo sem regerar a fase deixa vãos impossíveis para quem estiver
## carregado, e nenhum teste de lógica pega isso.
const PASTA_LIMITE := 5
const PASTA_CUSTO := 0.05
const PASTA_PISO := 0.75

## Peso de cada ação na pasta. Delegar e evitar não pesam, o que faz de delegar a única
## ação que pontua sem carregar o jogador — a definição de delegação virando regra.
const PESO_NA_PASTA := {
	Acao.COLETAR: 1,
	Acao.RESOLVER: 1,
	Acao.COLIDIU: 1,
	Acao.DELEGAR: 0,
	Acao.EVITOU: 0,
	Acao.IGNOROU: 0,
}


## Concentração (tecla `focar`: Shift ou L). Anda a 65%, as Q4 não acertam e o raio de
## leitura dobra. Sem recurso e sem recarga: a moeda é velocidade, e ficar em foco o dia
## todo perde o dia.
var foco_ativo: bool = false

## Ligado pela fase, como a pasta. O modo foco nasce no Dia 1; nas Fases 2 e 3 ele ainda
## não existe, e ligá-lo lá sem rebalancear o ritmo delas mudaria fases já testadas.
var foco_disponivel: bool = false

signal foco_mudou(ativo: bool)

## 65% da velocidade. Com a pasta cheia dá 88 px/s, abaixo dos 135 px/s contra os quais o
## validador confere as travessias obrigatórias — e isso é aceitável: ele garante que
## nenhuma travessia EXIJA foco, não que toda travessia funcione com ele ligado. Soltar a
## tecla está sempre disponível, então não existe estado sem saída.
const FOCO_VELOCIDADE := 0.65
## Amplia o raio em que o enunciado da tarefa aparece. A 180 px/s e com raio de 96px o
## jogador tem 0,53s para ler e decidir; em foco são 264px a 117 px/s, ou seja 2,2s.
const FOCO_RAIO := 2.75


func alternar_foco(ligado: bool) -> void:
	if foco_ativo == ligado:
		return
	if ligado and not foco_disponivel:
		return
	foco_ativo = ligado
	foco_mudou.emit(foco_ativo)


func fator_de_foco() -> float:
	return FOCO_VELOCIDADE if foco_ativo else 1.0


func fator_do_raio() -> float:
	return FOCO_RAIO if foco_ativo else 1.0


## Multiplicador de velocidade de deslocamento imposto pela pasta. 1.0 = nada mudou.
func fator_da_pasta() -> float:
	if not pasta_em_uso:
		return 1.0
	return maxf(PASTA_PISO, 1.0 - PASTA_CUSTO * float(carga_da_pasta))


# Carregar um papel (Fase 3)
#
# No Dia 3 o jogador não coleta a tarefa: ele a CARREGA até o canto da matriz em que a
# classificou, e carregar custa velocidade.
#
# Não é ação nova do Quadro 1 e não pontua — é modificador de deslocamento, como a pasta e
# o foco, e fica fora de registrar_acao(). Também não é estado novo da máquina: a seção
# 3.1 trava a lista em Idle/Run/Jump/Fall, e carregar é qualquer um dos quatro, mais lento.

## O jogador está com um papel na mão?
var carregando: bool = false

## 80% da velocidade. Combinado com o foco (65%) dá 0,52, ou seja 94 px/s — a mesma
## situação já aceita para pasta+foco: o validador garante que nenhuma travessia EXIJA
## foco, e soltar a tecla está sempre disponível.
const CARGA_VELOCIDADE := 0.8


func fator_de_carga() -> float:
	return CARGA_VELOCIDADE if carregando else 1.0


# Vitória por tempo (Fase 3)
#
# Nos Dias 1 e 2 o relógio é a ameaça: zerou, perdeu. No Dia 3 ele é a ESPERANÇA —
# sobreviver ao expediente inteiro é a vitória, e quem mata é a pilha de pendências.
#
# A inversão resolve de graça o problema que tirou o urso do Dia 2: duas pressões
# competindo sem que nenhuma seja lida. No Dia 3 só existe uma ameaça.
#
# Falso por padrão: quem não declara continua exatamente como estava.
var vitoria_ao_esgotar_tempo: bool = false


## Entrega tudo numa caixa de saída. Devolve quantas tarefas foram entregues.
##
## NÃO dá pontos, e a tentação de dar é justamente o que precisa ser recusada: os pontos
## já foram creditados quando cada tarefa foi feita, e pagar de novo na entrega seria
## inventar uma fonte de pontuação fora do Quadro 1.
func entregar_pasta() -> int:
	var entregues := carga_da_pasta
	carga_da_pasta = 0
	carga_mudou.emit(0)
	return entregues


func _ready() -> void:
	_zerar_contadores()


func _process(delta: float) -> void:
	# Fora do guard de em_jogo: o bloqueio de atenção precisa escoar mesmo se a fase
	# terminar no meio de uma interrupção, senão ele atravessaria para a próxima.
	_atencao_bloqueada = maxf(_atencao_bloqueada - delta, 0.0)
	if not em_jogo:
		return
	_alterar_tempo(-delta)


## Começa (ou recomeça) uma sessão de fase: zera placar e contadores e liga o cronômetro.
func iniciar_fase(tempo_inicial: float = TEMPO_PADRAO_FASE, dia_da_sessao: int = 1) -> void:
	pontuacao_total = 0
	tempo_restante = tempo_inicial
	_tempo_inicial = tempo_inicial
	tempo_gasto = 0.0
	ultima_vitoria = false
	em_jogo = true
	dia = dia_da_sessao
	interrupcoes = 0
	pendencias_amadurecidas = 0
	_atencao_bloqueada = 0.0
	# A pasta esvazia entre expedientes, e o uso dela volta a NEUTRO: cada fase declara se
	# usa a mecânica depois de chamar iniciar_fase(). Sem este zerar, jogar a Fase 1 e
	# depois a 2 levaria o peso junto para um corredor que não tem onde entregá-lo.
	carga_da_pasta = 0
	pasta_em_uso = false
	carga_mudou.emit(0)
	foco_ativo = false
	foco_disponivel = false
	# Mesma razão do zerar da pasta: sem isto, terminar o Dia 3 carregando um papel
	# deixaria o jogador lento na fase seguinte, sem nada na mão para explicar por quê.
	carregando = false
	vitoria_ao_esgotar_tempo = false
	foco_mudou.emit(false)
	_zerar_contadores()
	pontuacao_mudou.emit(pontuacao_total)
	tempo_mudou.emit(tempo_restante)


## Combinações categoria+ação que a matriz classifica como equívoco. Alimentam a tela de
## lição; não mudam pontuação nenhuma.
const EQUIVOCOS := {
	Categoria.URGENTE_IMPORTANTE: [Acao.IGNOROU],
	Categoria.IMPORTANTE_NAO_URGENTE: [Acao.IGNOROU],
	Categoria.URGENTE_NAO_IMPORTANTE: [Acao.IGNOROU, Acao.RESOLVER],
	Categoria.NAO_URGENTE_NAO_IMPORTANTE: [Acao.COLIDIU],
}


## Aplica o efeito de pontos/tempo definido no Quadro 1 e atualiza os contadores por
## categoria, que são o que a tela de resultado e o ranking leem.
##
## `enunciado` é só para o relatório: sem o texto da tarefa, a tela de lição conseguiria
## dizer "você deixou passar três urgentes" e não conseguiria dizer QUAIS.
##
## Retorna o efeito aplicado, para quem quiser mostrar feedback local.
func registrar_acao(categoria: Categoria, acao: Acao, enunciado: String = "") -> Dictionary:
	var pontos := 0
	var delta_tempo := 0.0

	match acao:
		Acao.COLETAR:
			pontos = 100 if categoria == Categoria.URGENTE_IMPORTANTE else 80
		Acao.DELEGAR:
			pontos = 60
		Acao.RESOLVER:
			pontos = 40
			delta_tempo = -5.0
		Acao.EVITOU:
			pontos = 0
		Acao.COLIDIU:
			pontos = -20
			delta_tempo = -8.0
		Acao.IGNOROU:
			pontos = 0

	pontuacao_total += pontos
	tarefas_por_categoria[categoria] += 1
	pontuacao_por_categoria[categoria] += pontos
	acoes_por_tipo[acao] += 1

	var peso: int = PESO_NA_PASTA.get(acao, 0)
	if pasta_em_uso and peso > 0:
		carga_da_pasta += peso
		carga_mudou.emit(carga_da_pasta)

	if acao in EQUIVOCOS.get(categoria, []):
		equivocos.append({
			"categoria": categoria, "acao": acao, "enunciado": enunciado,
		})

	pontuacao_mudou.emit(pontuacao_total)
	if delta_tempo != 0.0:
		_alterar_tempo(delta_tempo)

	tarefa_registrada.emit(categoria, acao, pontos, delta_tempo)
	return {"pontos": pontos, "delta_tempo": delta_tempo}


## Desconto de tempo que NÃO é tarefa da matriz — ladrão de tempo, queda no vão. Passa por
## fora de registrar_acao() para não poluir os contadores por categoria.
func descontar_tempo(segundos: float) -> void:
	if not em_jogo:
		return
	_alterar_tempo(-absf(segundos))


## Uma interrupção (Fase 2): custa segundos e rouba a atenção por um instante. O desconto
## passa por descontar_tempo(), como o ladrão de tempo. O que dói não é o tempo: enquanto
## a atenção está bloqueada nenhum enunciado fica legível, e o jogador classifica no
## escuro — fragmentação da atenção virando regra, em vez de mais uma penalidade.
func registrar_interrupcao(custo_em_segundos: float, cegueira: float) -> void:
	if not em_jogo:
		return
	interrupcoes += 1
	# maxf e não soma: duas notificações seguidas prolongam, não empilham para sempre.
	_atencao_bloqueada = maxf(_atencao_bloqueada, cegueira)
	descontar_tempo(custo_em_segundos)
	interrupcao_sofrida.emit(interrupcoes)


## False enquanto uma interrupção estiver roubando a leitura das tarefas.
func atencao_livre() -> bool:
	return _atencao_bloqueada <= 0.0


## Encerra a fase (vitória ao alcançar a saída, derrota ao esgotar o tempo).
func finalizar_fase(vitoria: bool) -> void:
	if not em_jogo:
		return
	em_jogo = false
	ultima_vitoria = vitoria
	tempo_gasto = _tempo_inicial - tempo_restante
	fase_terminada.emit(vitoria)


## Frase de reforço pedagógico para a combinação categoria+ação. Concentrar isso aqui
## (e não no HUD) mantém a teoria da matriz num lugar só, junto do Quadro 1.
func licao(categoria: Categoria, acao: Acao) -> String:
	var por_categoria: Dictionary = _LICAO.get(categoria, {})
	return por_categoria.get(acao, _LICAO_PADRAO)


## Percentual de acerto por categoria, para a tela de resultado. Uma categoria sem
## nenhuma tarefa registrada devolve 0.0 em vez de dividir por zero.
func aproveitamento(categoria: Categoria, pontos_maximos: int) -> float:
	if pontos_maximos <= 0:
		return 0.0
	return clampf(float(pontuacao_por_categoria[categoria]) / float(pontos_maximos), 0.0, 1.0)


## Ponto único por onde o tempo muda — garante que o clamp em zero e o fim de fase
## por tempo esgotado aconteçam do mesmo jeito, venha o desconto do cronômetro,
## de uma tarefa Q3/Q4, do ladrão de tempo ou de uma queda.
func _alterar_tempo(delta: float) -> void:
	tempo_restante = maxf(tempo_restante + delta, 0.0)
	tempo_mudou.emit(tempo_restante)
	if tempo_restante <= 0.0 and em_jogo:
		finalizar_fase(vitoria_ao_esgotar_tempo)


func _zerar_contadores() -> void:
	tarefas_por_categoria = {}
	pontuacao_por_categoria = {}
	for categoria in Categoria.values():
		tarefas_por_categoria[categoria] = 0
		pontuacao_por_categoria[categoria] = 0
	acoes_por_tipo = {}
	for acao in Acao.values():
		acoes_por_tipo[acao] = 0
	equivocos.clear()
